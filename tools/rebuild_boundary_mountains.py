"""Rebake only fictional boundary sectors from the verified prepared DEM grid.

Road, terrain, height and building bytes are reused. Run the native Godot cache
baker afterwards. This keeps boundary iteration independent of the GIS bake.
"""
from pathlib import Path
import numpy as np
from shapely.geometry import shape
from relief_core import HeightField,read,write,digest
from relief_limits import bake_limits

ROOT=Path(__file__).resolve().parents[1]

def rebuild():
    out=ROOT/'data/processed/relief/world';manifest=read(out/'manifest.json')
    for name,expected in manifest['sources'].items():assert digest(ROOT/name)==expected,name
    grid=read(out/'heightfield.json')
    assert digest(out/'heightfield.json')==manifest['heightfield_sha256']
    assert digest(ROOT/grid['heights_file'])==grid['heights_sha256']
    field=object.__new__(HeightField);field.step=grid['step_m'];field.x0,field.z0=grid['origin_xz'];field.nx=grid['width'];field.nz=grid['depth']
    field.values=np.fromfile(ROOT/grid['heights_file'],dtype='<f4').reshape(field.nz,field.nx).astype(float)
    region=shape(manifest['region_geojson'])
    sea=shape(read(ROOT/'data/processed/urban/urban_geography.json')['water_geometry_xz'])
    settings=read(ROOT/'config/relief_config.json')['fictional_boundary_mountains']
    manifest['limits']=bake_limits(out,region,field,ROOT,sea,settings)
    manifest['fictional_boundary_mountains']=settings
    manifest.pop('native_cache',None)
    write(out/'manifest.json',manifest)
    print('Boundary-only bake:',len(manifest['limits']),'sectors; road/terrain/building geometry unchanged')

if __name__=='__main__':rebuild()
