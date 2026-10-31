"""Bake elevated boundary walls into streamed sectors, never thousands of global boxes."""
import hashlib
import math
import struct
from collections import defaultdict
from shapely.geometry import Point, Polygon

from relief_core import write_bytes


def bake_limits(out,region,field,root,sea=None,mountains=None):
    if mountains and mountains.get('enabled'):
        return bake_mountains(out,region,field,root,sea,mountains)
    groups=defaultdict(bytearray)
    rings=[region.exterior] if region.geom_type=='Polygon' else [p.exterior for p in region.geoms]
    for ring in rings:
        points=list(ring.coords)
        for a,b in zip(points,points[1:]):
            steps=max(1,math.ceil(math.dist(a,b)/8))
            for i in range(steps):
                p=[a[j]+(b[j]-a[j])*i/steps for j in range(2)]
                q=[a[j]+(b[j]-a[j])*(i+1)/steps for j in range(2)]
                hp,hq=field.height(*p),field.height(*q)
                cell=(math.floor((p[0]+q[0])/512),math.floor((p[1]+q[1])/512))
                x0,z0=cell[0]*256,cell[1]*256
                lowp=(p[0]-x0,hp-1,p[1]-z0);lowq=(q[0]-x0,hq-1,q[1]-z0)
                highp=(p[0]-x0,hp+3,p[1]-z0);highq=(q[0]-x0,hq+3,q[1]-z0)
                for vertex in [lowp,lowq,highq,lowp,highq,highp]:groups[cell].extend(struct.pack('<fff',*vertex))
    entries=[]
    for (cx,cz),content in sorted(groups.items()):
        path=out/'limits'/f'{cx}_{cz}.bin'
        write_bytes(path,content)
        entries.append(dict(id=f'{cx}_{cz}',origin_xz=[cx*256,cz*256],file=path.relative_to(root).as_posix(),
            sha256=hashlib.sha256(content).hexdigest(),triangles_count=len(content)//36))
    return entries


def bake_mountains(out,region,field,root,sea,settings):
    """Triangulate non-overlapping exterior distance bands, including concave joins.

    Offsetting each boundary vertex independently folds a wide ridge at tight
    concave corners. Boolean annuli share their boundaries and cannot cross.
    A 16m grid bounds triangle size; the separate 6m front remains unscalable.
    """
    from shapely.geometry import box
    from shapely.ops import nearest_points
    from shapely.prepared import prep
    from relief_core import triangulate
    groups=defaultdict(lambda:[bytearray(),bytearray()])
    shore=float(settings['shore_clearance_m'])
    clear=sea.buffer(shore)
    distances=[0.,6.,80.,140.,float(settings['width_m'])]
    buffers=[region]+[region.buffer(d,quad_segs=6) for d in distances[1:]]
    bands=[buffers[i+1].difference(buffers[i]).difference(clear) for i in range(4)]
    boundary=region.boundary
    heights={}
    def height(x,z):
        key=(round(x,6),round(z,6))
        if key not in heights:
            p=Point(key);near=nearest_points(boundary,p)[0];d=near.distance(p)
            base=field.height(near.x,near.y)
            wave=.5+.25*math.sin(near.x*.013+near.y*.005)+.25*math.cos(near.y*.017-near.x*.004)
            peak=settings['height_m']*(.65+.7*wave)
            levels=[-1.,45.,peak,peak*.4,-3.]
            k=next((i for i in range(4) if d<=distances[i+1]+1e-6),3)
            t=min(1.,max(0.,(d-distances[k])/(distances[k+1]-distances[k])))
            rise=levels[k]*(1-t)+levels[k+1]*t
            strength=min(1.,max(0.,(sea.distance(p)-shore)/100))
            heights[key]=base+rise*strength
        return heights[key]
    def append(cell,kind,tri):
        a,b,c=tri
        area=(b[2]-a[2])*(c[0]-a[0])-(b[0]-a[0])*(c[2]-a[2])
        if kind==0:
            edge=max(math.hypot(u[0]-v[0],u[2]-v[2]) for u,v in [(a,b),(b,c),(c,a)])
            if abs(area)/max(edge,1e-12)<.0005:return
        if area>0:b,c=c,b
        for x,y,z in [a,b,c]:groups[cell][kind].extend(struct.pack('<fff',x-cell[0]*256,y,z-cell[1]*256))
    # Only maritime edges keep their original low, invisible collision wall.
    rings=[region.exterior] if region.geom_type=='Polygon' else [p.exterior for p in region.geoms]
    for ring in rings:
        coords=list(ring.coords)
        for a,b in zip(coords,coords[1:]):
            steps=max(1,math.ceil(math.dist(a,b)/8))
            for i in range(steps):
                p=[a[j]+(b[j]-a[j])*i/steps for j in range(2)];q=[a[j]+(b[j]-a[j])*(i+1)/steps for j in range(2)]
                if sea.distance(Point((p[0]+q[0])/2,(p[1]+q[1])/2))>=shore:continue
                hp,hq=field.height(*p),field.height(*q)
                cell=(math.floor((p[0]+q[0])/512),math.floor((p[1]+q[1])/512))
                v=[(p[0],hp-1,p[1]),(q[0],hq-1,q[1]),(q[0],hq+3,q[1]),(p[0],hp+3,p[1])]
                append(cell,1,[v[0],v[1],v[2]]);append(cell,1,[v[0],v[2],v[3]])
    for band in bands:
        ready=prep(band);x0,z0,x1,z1=band.bounds
        for x in range(math.floor(x0/16)*16,math.ceil(x1/16)*16,16):
            for z in range(math.floor(z0/16)*16,math.ceil(z1/16)*16,16):
                square=box(x,z,x+16,z+16)
                if not ready.intersects(square):continue
                for face in triangulate(band.intersection(square)):
                    append((math.floor((x+8)/256),math.floor((z+8)/256)),0,[(px,height(px,pz),pz) for px,pz in face])
    entries=[]
    for (cx,cz),(visible,hidden) in sorted(groups.items()):
        content=visible+hidden;path=out/'limits'/f'{cx}_{cz}.bin';write_bytes(path,content)
        entries.append(dict(id=f'{cx}_{cz}',origin_xz=[cx*256,cz*256],file=path.relative_to(root).as_posix(),sha256=hashlib.sha256(content).hexdigest(),triangles_count=len(content)//36,visible_triangles_count=len(visible)//36))
    return entries
