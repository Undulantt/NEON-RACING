"""One canonical triangulated height field for offline road/terrain partitions."""
import hashlib
import json
import math
import struct
import time
from pathlib import Path

import numpy as np
import rasterio
from scipy.ndimage import gaussian_filter, map_coordinates
from shapely import constrained_delaunay_triangles

from map_core import R


def read(path):
    return json.loads(Path(path).read_text(encoding='utf-8'))


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write(path, data):
    write_bytes(path,json.dumps(data,ensure_ascii=False,separators=(',', ':'),allow_nan=False).encode('utf-8'))


def write_bytes(path, content):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() and path.read_bytes()==content:
        return
    # File watchers on Windows can briefly hold a generated JSON file open.
    # Preserve the previous valid snapshot until the replacement is complete.
    pending=path.with_name(path.name+'.writing')
    try:
        for attempt in range(5):
            try:
                pending.write_bytes(content)
                pending.replace(path)
                return
            except OSError:
                if attempt==4:raise
                time.sleep(.1*(attempt+1))
    finally:
        if pending.exists():pending.unlink()


def write_heightfield(out,field,root):
    out=Path(out)
    out.mkdir(parents=True,exist_ok=True)
    heights=out/'heights.bin';quality=out/'quality.bin'
    write_bytes(heights,field.values.astype('<f4').tobytes())
    write_bytes(quality,field.quality.tobytes())
    record=field.record()
    record.pop('heights');record.pop('estimated')
    record.update(heights_file=heights.relative_to(root).as_posix(),heights_sha256=digest(heights),
        quality_file=quality.relative_to(root).as_posix(),quality_sha256=digest(quality))
    write(out/'heightfield.json',record)


class Elevation:
    """WCS snapshot interpreted using actual pixel centres and CRS, never guessed resolution."""
    def __init__(self, path, origin, sigma_m=20):
        with rasterio.open(path) as src:
            if src.crs.to_epsg() != 4326:
                raise ValueError('Expected verified WCS geographic export')
            self.transform = src.transform
            self.raw = src.read(1).astype(float)
            self.valid = self.raw != src.nodata
            if not np.isfinite(self.raw).all():
                raise ValueError('Nonfinite DEM')
            self.profile = dict(crs=str(src.crs), width=src.width, height=src.height,
                transform=list(src.transform), nodata=src.nodata, pixel_interpretation=src.tags().get('AREA_OR_POINT'))
        self.lat0, self.lon0 = origin
        dy = abs(self.transform.e) * math.pi / 180 * R
        dx = abs(self.transform.a) * math.pi / 180 * R * math.cos(math.radians(self.lat0))
        sigma = (sigma_m / dy, sigma_m / dx)
        # Normalized smoothing near coastal NoData. Validity remains a separate mask.
        weight = gaussian_filter(self.valid.astype(float), sigma, mode='nearest')
        self.smooth = gaussian_filter(np.where(self.valid, self.raw, 0), sigma, mode='nearest') / np.maximum(weight, 1e-12)

    def sample(self, x, z, smoothed=True, coastal_estimate=False):
        lat = self.lat0 - math.degrees(z / R)
        lon = self.lon0 + math.degrees(x / (R * math.cos(math.radians(self.lat0))))
        inverse = ~self.transform
        col = inverse.a * lon + inverse.b * lat + inverse.c
        row = inverse.d * lon + inverse.e * lat + inverse.f
        row -= .5
        col -= .5
        r, c = math.floor(row), math.floor(col)
        if r < 0 or c < 0 or r + 1 >= self.raw.shape[0] or c + 1 >= self.raw.shape[1]:
            return None
        if not self.valid[r:r+2, c:c+2].all() and not coastal_estimate:
            return None
        return float(map_coordinates(self.smooth if smoothed else self.raw, [[row], [col]], order=1, prefilter=False)[0])


class HeightField:
    def __init__(self, dem, bounds, step, sea=None, region=None):
        self.step = step
        self.x0 = math.floor(bounds[0] / step) * step
        self.z0 = math.floor(bounds[1] / step) * step
        self.nx = math.ceil((bounds[2] - self.x0) / step) + 1
        self.nz = math.ceil((bounds[3] - self.z0) / step) + 1
        self.values = np.empty((self.nz, self.nx))
        self.quality = np.zeros((self.nz, self.nx), dtype=np.uint8)
        from shapely.geometry import Point
        support_region = region.buffer(step*2) if region is not None else None
        for iz in range(self.nz):
            for ix in range(self.nx):
                x, z = self.x0 + ix * step, self.z0 + iz * step
                h = dem.sample(x, z)
                if h is None:
                    point = Point(x,z)
                    if support_region is not None and not support_region.covers(point):
                        h = 0.0
                        self.quality[iz,ix] = 2  # Unused outside playable support, not terrain data.
                    elif sea is not None and (sea.covers(point) or (region is not None and not region.covers(point) and sea.distance(point) <= step*2)):
                        h = -1.0
                        self.quality[iz,ix] = 1
                    elif sea is not None and sea.distance(point) <= 32:
                        h = max(0.,dem.sample(x,z,coastal_estimate=True))
                        self.quality[iz,ix] = 3  # Explicit <=32 m coastal interpolation only.
                    else:
                        raise ValueError(f'Missing terrestrial DEM at {x},{z}')
                self.values[iz, ix] = h

    def height(self, x, z):
        u = (x - self.x0) / self.step
        v = (z - self.z0) / self.step
        ix = min(max(math.floor(u), 0), self.nx - 2)
        iz = min(max(math.floor(v), 0), self.nz - 2)
        a, b = u - ix, v - iz
        if not -1e-6 <= a <= 1.000001 or not -1e-6 <= b <= 1.000001:
            raise ValueError('Height outside prepared grid')
        h00, h10 = self.values[iz, ix], self.values[iz, ix+1]
        h01, h11 = self.values[iz+1, ix], self.values[iz+1, ix+1]
        if b <= a:
            return float(h00 + a*(h10-h00) + b*(h11-h10))
        return float(h00 + a*(h11-h01) + b*(h01-h00))

    def record(self):
        return dict(origin_xz=[self.x0, self.z0], step_m=self.step,
            width=self.nx, depth=self.nz, heights=self.values.ravel().tolist(),
            estimated=self.quality.ravel().tolist(), diagonal='00_to_11', interpolation='piecewise_linear',
            sea_level_m=0, vertical_origin_m=0)


def triangulate(geometry):
    if geometry.is_empty:
        return []
    if geometry.geom_type == 'Polygon':
        return [list(t.exterior.coords)[:3] for t in constrained_delaunay_triangles(geometry).geoms if t.area > 1e-8]
    return [t for p in getattr(geometry, 'geoms', []) for t in triangulate(p)]


def fair_road_grades(field, asphalt, target=.38):
    """Project only excessive road gradients; preserve anchored shoreline heights."""
    from shapely.geometry import box
    from shapely.prepared import prep
    original=field.values.copy();ready=prep(asphalt);iterations=0;corrected=0
    h=field.values;s=field.step
    fixed=getattr(field,'fixed_zero',np.zeros_like(h,dtype=bool))
    road_cells={}
    for sweep in range(200):
        low=np.hypot((h[:-1,1:]-h[:-1,:-1])/s,(h[1:,1:]-h[:-1,1:])/s)
        high=np.hypot((h[1:,1:]-h[1:,:-1])/s,(h[1:,:-1]-h[:-1,:-1])/s)
        bad=[]
        for iz,ix in np.argwhere(np.maximum(low,high)>target*1.005):
            key=(int(iz),int(ix))
            if key not in road_cells:
                x,z=field.x0+ix*s,field.z0+iz*s
                road_cells[key]=ready.intersects(box(x,z,x+s,z+s))
            if road_cells[key]:bad.append(key)
        if not bad:break
        iterations+=1;corrected+=len(bad)
        for iz,ix in bad:
            for indices in [((iz,ix),(iz,ix+1),(iz+1,ix+1)),((iz,ix),(iz+1,ix),(iz+1,ix+1))]:
                values=np.array([h[i] for i in indices])
                d=np.diff(values);grade=np.linalg.norm(d)/s
                if grade<=target:continue
                d*=target/grade
                positions=np.array([0.,d[0],d.sum()])
                anchors=[j for j,i in enumerate(indices) if fixed[i]]
                offset=-positions[anchors[0]] if anchors else values.mean()-positions.mean()
                for j,i in enumerate(indices):h[i]=0. if fixed[i] else positions[j]+offset
    delta=np.abs(h-original)
    return dict(iterations=iterations,projected_road_cells=corrected,max_adjustment_m=float(delta.max()),
        nodes_adjusted_over_10cm=int((delta>.1).sum()),target_grade=target,
        method='Alternating local triangle gradient projections; shoreline anchors fixed; original slopes below limit unchanged')


def constrain_coast(field,coast):
    """OSM shoreline overrides coarse DEM locally; exact zero along intersected cells."""
    from shapely import points,distance
    if coast.is_empty:return dict(adjusted_nodes=0,max_adjustment_m=0.)
    x,z=np.meshgrid(field.x0+np.arange(field.nx)*field.step,field.z0+np.arange(field.nz)*field.step)
    x0,z0,x1,z1=coast.buffer(64).bounds
    candidate=(x>=x0)&(x<=x1)&(z>=z0)&(z<=z1)
    positions=points(x[candidate],z[candidate])
    d=distance(positions,coast)
    field.fixed_zero=np.zeros_like(field.values,dtype=bool)
    field.fixed_zero[candidate]=d<=16
    t=np.clip((d-16)/48,0,1)
    weight=t*t*(3-2*t)
    old=field.values[candidate].copy()
    field.values[candidate]=np.where(d<64,np.maximum(old,0)*weight,old)
    delta=np.abs(field.values[candidate]-old)
    return dict(adjusted_nodes=int((delta>1e-6).sum()),max_adjustment_m=float(delta.max()),
        zero_band_m=16,transition_end_m=64,method='OSM shoreline at Y=0; smoothstep transition to CEM; no bathymetry inferred')


def binary_faces(path, faces, field, origin):
    """Little endian XYZ float32, Godot clockwise winding; identical render/collision."""
    coords=np.asarray(faces,dtype=float)
    u=(coords[:,:,0]-field.x0)/field.step;v=(coords[:,:,1]-field.z0)/field.step
    ix=np.clip(np.floor(u).astype(int),0,field.nx-2);iz=np.clip(np.floor(v).astype(int),0,field.nz-2)
    a=u-ix;b=v-iz
    h00=field.values[iz,ix];h10=field.values[iz,ix+1]
    h01=field.values[iz+1,ix];h11=field.values[iz+1,ix+1]
    heights=np.where(b<=a,h00+a*(h10-h00)+b*(h11-h10),h00+a*(h11-h01)+b*(h01-h00))
    xyz=np.stack([coords[:,:,0]-origin[0],heights,coords[:,:,1]-origin[1]],axis=2)
    normals=np.cross(xyz[:,1]-xyz[:,0],xyz[:,2]-xyz[:,0])
    max_grade=float((np.linalg.norm(normals[:,[0,2]],axis=1)/np.maximum(abs(normals[:,1]),1e-12)).max())
    flip=normals[:,1]>0
    xyz[flip]=xyz[flip][:,[0,2,1]]
    quantized=xyz.astype('<f4')
    q=quantized.astype(float)
    cross=np.cross(q[:,1]-q[:,0],q[:,2]-q[:,0])
    horizontal_area2=np.abs(cross[:,1])
    edges=np.maximum.reduce([np.linalg.norm((q[:,1]-q[:,0])[:,[0,2]],axis=1),
        np.linalg.norm((q[:,2]-q[:,0])[:,[0,2]],axis=1),np.linalg.norm((q[:,2]-q[:,1])[:,[0,2]],axis=1)])
    # GEOS cuts can yield microscopic slivers. Float32 height rounding makes
    # their normals unstable. Drop only faces narrower than half a millimetre,
    # report their total area, and validate aggregate coverage independently.
    keep=horizontal_area2/np.maximum(edges,1e-12)>=.0005
    omitted_area=float((horizontal_area2[~keep]*.5).sum())
    content=quantized[keep].tobytes()
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    write_bytes(path,content)
    return dict(file=str(path), sha256=hashlib.sha256(content).hexdigest(), triangles_count=int(keep.sum()),
        max_grade=max_grade,omitted_submillimetre_faces=int((~keep).sum()),omitted_area_m2=omitted_area)
