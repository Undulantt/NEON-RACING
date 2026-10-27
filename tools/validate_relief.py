"""Validate published relief snapshots, float32 meshes, coverage bounds and shoreline."""
import argparse
from pathlib import Path

import numpy as np
from shapely import covers,points
from shapely.geometry import shape

from relief_core import HeightField,digest,read,write

ROOT=Path(__file__).resolve().parents[1]


def validate(mode):
    out=ROOT/'data/processed/relief'/mode
    manifest=read(out/'manifest.json');grid=read(out/'heightfield.json')
    for p,sha in manifest['sources'].items():assert digest(ROOT/p)==sha,p
    assert digest(out/'heightfield.json')==manifest['heightfield_sha256']
    for kind in ['heights','quality']:assert digest(ROOT/grid[kind+'_file'])==grid[kind+'_sha256']
    field=object.__new__(HeightField)
    field.step=grid['step_m'];field.x0,field.z0=grid['origin_xz'];field.nx=grid['width'];field.nz=grid['depth']
    field.values=np.fromfile(ROOT/grid['heights_file'],dtype='<f4').reshape(field.nz,field.nx).astype(float)
    region=shape(manifest['region_geojson'])
    expanded=region.buffer(.001)
    max_error=0.;max_grade=0.;triangles=0;cache_count=0
    for kind in ['roads','terrain','limits']:
        for entry in manifest[kind]:
            assert digest(ROOT/entry['file'])==entry['sha256'],entry['file']
            if 'scene_file' in entry:
                assert digest(ROOT/entry['scene_file'])==entry['scene_sha256']
                cache_count+=1
            mesh=np.fromfile(ROOT/entry['file'],dtype='<f4').reshape(-1,3,3).astype(float)
            assert len(mesh)==entry['triangles_count']
            assert np.isfinite(mesh).all()
            triangles+=len(mesh)
            if kind=='limits':continue
            mesh[:,:,0]+=entry['origin_xz'][0];mesh[:,:,2]+=entry['origin_xz'][1]
            flat=mesh.reshape(-1,3)
            assert covers(expanded,points(flat[:,0],flat[:,2])).all(),'Mesh outside playable polygon'
            u=(flat[:,0]-field.x0)/field.step;v=(flat[:,2]-field.z0)/field.step
            ix=np.clip(np.floor(u).astype(int),0,field.nx-2);iz=np.clip(np.floor(v).astype(int),0,field.nz-2)
            a=u-ix;b=v-iz;h=field.values
            expected=np.where(b<=a,h[iz,ix]+a*(h[iz,ix+1]-h[iz,ix])+b*(h[iz+1,ix+1]-h[iz,ix+1]),
                h[iz,ix]+a*(h[iz+1,ix+1]-h[iz+1,ix])+b*(h[iz+1,ix]-h[iz,ix]))
            max_error=max(max_error,float(abs(flat[:,1]-expected).max()))
            if kind=='roads':
                n=np.cross(mesh[:,1]-mesh[:,0],mesh[:,2]-mesh[:,0])
                max_grade=max(max_grade,float((np.linalg.norm(n[:,[0,2]],axis=1)/np.maximum(abs(n[:,1]),1e-12)).max()))
    assert max_error<.001,('Physics/height surface mismatch',max_error)
    assert max_grade<read(ROOT/'config/relief_config.json')['max_road_grade'],('Quantized road slope',max_grade)
    # Remove polygon clipping boundaries: only physical OSM shoreline constrains sea level.
    sea=shape(read(ROOT/'data/processed/urban/urban_geography.json')['water_geometry_xz'])
    from expansion_regions import metric_region
    coast=sea.boundary.difference(metric_region(read(ROOT/'config/map_config.json')).boundary.buffer(1)).intersection(region)
    coast_error=0.;coast_samples=0
    lines=list(coast.geoms) if hasattr(coast,'geoms') else [coast]
    for line in lines:
        for t in np.arange(0,line.length,8):
            p=line.interpolate(t)
            coast_error=max(coast_error,abs(field.height(p.x,p.y)));coast_samples+=1
    assert coast_error<.001,('Shoreline differs from Y=0',coast_error)
    report=dict(passed=True,mode=mode,manifest_sha256=digest(out/'manifest.json'),triangles_checked=triangles,
        cached_scenes_checked=cache_count,max_mesh_height_error_m=max_error,max_quantized_road_grade=max_grade,
        coast_samples=coast_samples,max_coast_height_error_m=coast_error,
        note='Geometric/metadata validation; local DEM vertical accuracy and manual foundations are separate review items')
    write(ROOT/f'docs/phase_b7r_{mode}_geometry.json',report)
    print(report)
    return report


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--mode',choices=['pilot','world'],default='pilot')
    validate(parser.parse_args().mode)
