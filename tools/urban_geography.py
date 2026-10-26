"""Mapped coast/open surfaces and source-verified landmark registry, offline only."""
from shapely.geometry import Point, LineString, Polygon, mapping
from shapely.ops import unary_union, polygonize
from shapely import constrained_delaunay_triangles


def surfaces(region, coast, protected, buildings, roads, area_ids=None):
    segments=[(a,b,LineString([a,b])) for line in coast for a,b in zip(line.coords,list(line.coords)[1:]) if a!=b]
    cells=list(polygonize(unary_union([region.boundary]+[line.intersection(region) for line in coast])))
    water=[]
    for cell in cells:
        p=cell.representative_point()
        if not region.covers(p) or not segments: continue
        a,b,_=min(segments,key=lambda s:s[2].distance(p))
        cross=(b[0]-a[0])*(p.y-a[1])-(b[1]-a[1])*(p.x-a[0])
        # OSM water on right in lon/lat; the local Z axis reverses latitude.
        if cross>0: water.append(cell)
    sea=unary_union(water)
    overlap=sum(Polygon(b['footprint_xz'],b.get('holes_xz',[])).intersection(sea).area for b in buildings)
    if overlap>0.01: raise ValueError(f'Coast conflicts with buildings: {overlap} m2; review required')
    records=[]
    def add(identifier,geom,kind,color,y):
        parts=[geom] if geom.geom_type=='Polygon' else list(getattr(geom,'geoms',[]))
        triangles=[]
        for p in parts:
            if p.geom_type!='Polygon' or p.is_empty: continue
            triangles.extend([[list(v) for v in list(t.exterior.coords)[:3]] for t in constrained_delaunay_triangles(p).geoms])
        if triangles: records.append({'id':identifier,'kind':kind,'color':color,'y':y,'triangles_xz':triangles})
    add('osm:sea',sea.difference(roads),'water','397f99',-0.04)
    used=sea
    open_surface_road_mask=roads.buffer(0.1)
    for identifier,geom,tags in sorted(protected,key=lambda r:r[0]):
        if area_ids is not None and identifier not in area_ids: continue
        kind=None
        if tags.get('natural') in ('water','wetland'): kind='water'
        elif tags.get('natural') in ('beach','sand'): kind='beach'
        elif tags.get('leisure') in ('park','garden','playground') or tags.get('landuse') in ('grass','recreation_ground'): kind='park'
        elif tags.get('amenity')=='parking': kind='parking'
        elif tags.get('place')=='square' or tags.get('highway')=='pedestrian': kind='plaza'
        # Node buffers and line buffers in the old exclusion mask are not mapped extents.
        if kind is None or identifier.startswith('node:'): continue
        geom=geom.intersection(region).difference(open_surface_road_mask).difference(used)
        add(identifier,geom,kind,{'water':'397f99','beach':'decba3','park':'92ad78','parking':'a19d92','plaza':'d4bb9b'}[kind],-0.035)
        used=used.union(geom)
    # Partition the visual ground; the original safety collider remains intact.
    # No coplanar platform is rendered beneath water, open surfaces or asphalt.
    add('local:land',region.difference(used).difference(roads),'land','b4a386',-0.08)
    return {'schema_version':1,'surfaces':records,'water_geometry_xz':mapping(sea),'water_building_overlap_m2':overlap,'coast_cells':len(cells),'method':'OSM directed coastline polygonized with existing bbox; source orientation determines water; safety collision retained below water'}


def landmarks(enrichment):
    selected=['osm:way:155831056','osm:way:155831064','osm:way:155831066','osm:way:450296320','osm:way:450296505','osm:node:958717770','osm:way:137201460','osm:way:301737276']
    result=[]
    for p in enrichment['pois']:
        if p['id'] in selected:
            result.append({'id':'landmark:'+p['id'],'poi_id':p['id'],'name':p['name'],'position_xz':p['position_xz'],'lat':p['lat'],'lon':p['lon'],'category':p['category'],'building_id':p['building_id'],'source':p['source'],'priority':2,'verification':'location documented in hashed OSM snapshot; not field verified','architecture_verified':False,'model_path':None,'rotation_degrees':0,'scale':1})
    from urban_enrichment import read, ROOT
    overrides=read(ROOT/'config/urban_overrides.json')['buildings']
    for record in result:
        override=overrides.get(record['building_id'],{})
        if override.get('model_path'):
            record.update(model_path=override['model_path'],priority=override.get('priority',2),silhouette_reference=override['source'],dimensions_estimated=True)
    return {'schema_version':1,'landmarks':result}


def mapped_area_ids(raw):
    result=set()
    for e in raw['elements']:
        if e['type']=='relation': result.add('relation:'+str(e['id']))
        if e['type']=='way':
            coords=e.get('geometry',[])
            if len(coords)>=4 and coords[0]==coords[-1] and e.get('tags',{}).get('area')!='no': result.add('way:'+str(e['id']))
    return result
