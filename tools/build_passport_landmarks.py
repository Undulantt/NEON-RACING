"""Integrate supplied landmark models without mutating geographic source datasets.

Model bounds: Godot --headless --script res://tools/inspect_landmark_models.gd.
Positions: source footprints; campus identity inferred from the official 2022
plan matched to those footprints (not surveyed coordinates). No new roads.
"""
import hashlib
import json
import math
import xml.etree.ElementTree as ET
from pathlib import Path
from shapely.affinity import rotate, translate
from shapely.geometry import LineString, Point, Polygon, box
from shapely.ops import unary_union
from shapely.strtree import STRtree
from shapely.prepared import prep
from map_core import gps_to_local

ROOT=Path(__file__).resolve().parents[1]
def read(path):return json.loads((ROOT/path).read_text(encoding='utf8'))
def sha(path):return hashlib.sha256((ROOT/path).read_bytes()).hexdigest()
def write(path,data):
    (ROOT/path).parent.mkdir(parents=True,exist_ok=True)
    (ROOT/path).write_bytes((json.dumps(data,ensure_ascii=False,indent=2,allow_nan=False)+'\n').encode('utf8'))

def build():
    data=read('data/processed/la_paz_map.json');arcade=read('data/processed/arcade_layout.json');city=read('data/processed/urban/city_manifest.json')
    hashes={p:sha(p) for p in ['data/processed/la_paz_map.json','data/processed/arcade_layout.json','data/processed/urban/city_manifest.json','data/processed/urban/sf3_recovery/manifest.json','data/raw/osm_map_c6_boundary_expansion.osm']}
    bounds=read('.local/artifacts/landmark_model_bounds.json')
    root=ET.parse(ROOT/'data/raw/osm_map_c6_boundary_expansion.osm').getroot()
    nodes={n.attrib['id']:(float(n.attrib['lat']),float(n.attrib['lon'])) for n in root.findall('node')}
    def project(p):return gps_to_local(*p,data['metadata']['origin_lat'],data['metadata']['origin_lon'])
    xml_polys={}
    for w in root.findall('way'):
        refs=[n.attrib['ref'] for n in w.findall('nd')]
        if len(refs)>3 and refs[0]==refs[-1] and all(n in nodes for n in refs):
            xml_polys[w.attrib['id']]=Polygon([project(nodes[n]) for n in refs])
    buildings={}
    for c in city['chunks']:
        override=arcade['chunk_overrides'].get(c['id']);changes=read(override['file']) if override else {}
        for b in read('data/processed/urban/'+c['file'])['buildings']:
            b={**b,**changes.get(b['id'],{})}
            if not b.get('disabled'):buildings[b['id']]=b
    recovery=read('data/processed/urban/sf3_recovery/manifest.json')
    for c in recovery['chunks']:
        for b in read(c['file'].removeprefix('res://'))['buildings']:buildings[b['id']]=b
    polygons=[Polygon(b['footprint_xz'],b.get('holes_xz',[])) for b in buildings.values()]
    identities=list(buildings);tree=STRtree(polygons)
    asphalt=unary_union([LineString(r['points_xz']).buffer(arcade['widths_m'][r['id']]/2,quad_segs=4,cap_style='round',join_style='mitre',mitre_limit=2) for r in data['roads']])
    active=set(read('data/processed/relief/world/manifest.json')['road_ids'])
    supported=prep(asphalt.buffer(.001))
    lines=[LineString(r['points_xz']) for r in data['roads']];road_tree=STRtree(lines)
    campus_url='https://www.uabcs.mx/dasc/wp-content/uploads/2022/10/Mapa-Campus-La-Paz-2022.pdf'
    campus='https://www.uabcs.mx/recorrido-virtual/menu.html'
    gym='https://www.uabcs.mx/recorrido-virtual/lapaz/gimnasio/pano.xml'
    # File names do not establish identities. The two Generic exports stay generic.
    definitions=[
      dict(id='kiosco',poi='poi_001',folder='Kiosco/Kiosco.glb',node='9284265569',latlon=[24.163772,-110.3165411],name='Kiosco del Malecón',url='https://turismo.lapaz.gob.mx/atractivos/kiosco-del-malecon-18',description='Punto de encuentro del Malecón frente a la bahía de La Paz.',exclude=['Floor_001','Foundation_001','LightPoles','PalmTrees']),
      dict(id='catedral',poi='poi_002',folder='Iglesia/Church.glb',way='155831066',name='Catedral de Nuestra Señora de La Paz',url='https://turismo.lapaz.gob.mx/atractivos/catedral-de-nuestra-senora-de-la-paz',description='Templo del centro histórico frente al Jardín Velasco. El modelo aportado representa su arquitectura de forma estilizada.'),
      dict(id='teatro',poi='poi_003',folder='Teatro/Theater.glb',way='155831068',name='Teatro de la Ciudad',url='https://sic.cultura.gob.mx/ficha.php?table=teatro&table_id=12',front=-1,description='Recinto de la Unidad Cultural Profesor Jesús Castro Agúndez, dedicado a presentaciones de artes escénicas. No corresponde al Teatro Juárez.'),
      dict(id='molinito',poi='poi_004',folder='Molinito/ElMolinito.glb',node='10805405566',name='El Molinito',url='https://turismo.lapaz.gob.mx/atractivos/malecon-de-la-paz',description='Hito del paseo costero identificado como Molinito en la cartografía OpenStreetMap. Su representación utiliza el modelo aportado al proyecto.'),
      dict(id='museo_arte',poi='poi_005',folder='Museo de Arte/ArtMuseum.glb',way='155831056',name='Museo de Arte de Baja California Sur',url='https://muabcs.cultura-bcs.gob.mx/historia-del-recinto/',description='Museo de arte frente al Jardín Velasco. Ocupa la reconstrucción de la antigua Casa de Gobierno.'),
      dict(id='uabcs_rectoria',poi='poi_007',folder='UABCS/UABCSRectoria.glb',building='overture:c5c01479-fb5a-46d8-9659-c1fd45b4c62a:0:0',name='UABCS · Rectoría AD-19',url=campus,description='Rectoría figura como AD-19 en el directorio oficial. La asociación de esta huella con el plano del campus es aproximada.',campus=True,plan_label='19'),
      dict(id='uabcs_gimnasio',poi='poi_008',folder='UABCS/UABCSGimnasioAuditorio.glb',building='osm:1342767403:0',name='UABCS · Gimnasio Auditorio AD-01',url=campus,description='Gimnasio Auditorio identificado como AD-01 en el directorio. Se contrasta la huella con el plano del campus y las coordenadas de las panorámicas oficiales cercanas.',campus=True,plan_label='01',extra_url=gym),
      dict(id='uabcs_sistemas',poi='poi_009',folder='UABCS/AD-46.glb',building='overture:74a61aba-f87e-4ace-b55c-f63384618bee:0:0',name='UABCS · Sistemas II DSC-46',url=campus,description='El directorio identifica Sistemas II como DSC-46. Se utiliza el archivo aportado AD-46.glb; su nombre no es la clave oficial. La ubicación se asocia aproximadamente mediante el plano y una huella real.',campus=True,plan_label='46'),
      dict(id='uabcs_academico_1',poi='poi_010',folder='UABCS/UABCSGeneric1.glb',building='overture:c22792ec-8b0e-4a3d-a542-b5f197a853f5:0:0',name='UABCS · Edificio académico A',url=campus,description='Huella real del conjunto académico representada con un modelo genérico. No se atribuye a un departamento específico: su identidad no está confirmada.',campus=True,generic=True),
      dict(id='uabcs_academico_2',poi='poi_011',folder='UABCS/UABCSGeneric2.glb',building='osm:666815700:0',name='UABCS · Edificio académico B',url=campus,description='Huella real del conjunto académico representada con un modelo genérico. Su nombre A/B solo sirve para identificarla dentro del prototipo; no es una denominación oficial.',campus=True,generic=True)]
    def approach(point,preferred=''):
        candidates=[]
        for idx in road_tree.query(point.buffer(175)):
            r=data['roads'][int(idx)];line=lines[int(idx)]
            if r['id'] not in active:continue
            for t in [max(.15,min(.85,line.project(point)/line.length)),.25,.5,.75]:
                q=line.interpolate(t,normalized=True);a,b=list(line.coords)[0],list(line.coords)[-1]
                angle=math.degrees(math.atan2(b[1]-a[1],b[0]-a[0]))
                car=translate(rotate(box(-5.5,-2.6,5.5,2.6),angle,origin=(0,0)),q.x,q.y)
                if supported.covers(car):candidates.append((q.distance(point)+(0 if preferred.lower() in r['street_name'].lower() else 40),r,t,q,car))
        assert candidates,'No supported approach'
        _,r,t,q,car=min(candidates,key=lambda v:v[0])
        assert point.distance(q)<180
        return {'road_id':r['id'],'t':t,'radius_m':9.0,'max_speed_mps':3.0,'position_xz':[q.x,q.y],'street':r['street_name'],'offset_from_place_m':q.distance(point),'validated':True,'validation_map_sha256':hashes['data/processed/la_paz_map.json'],'validation_method':'offline 11 x 5.2m footprint covered by existing asphalt'},car
    existing=read('data/passport/pois.json');old={p['id']:p for p in existing['pois']};models=[];pois=[];masks=[]
    for spec in definitions:
        poly=None
        if 'building' in spec:
            b=buildings[spec['building']];poly=Polygon(b['footprint_xz'],b.get('holes_xz',[]))
        elif 'way' in spec:poly=xml_polys[spec['way']]
        if poly is not None:p=poly.centroid
        else:p=Point(project(spec.get('latlon',nodes.get(spec.get('node')))))
        zone,car=approach(p,'navarro' if spec['id']=='teatro' else 'madero' if spec['id'] in ('catedral','museo_arte') else '')
        path='res://assets/3D/Edificios/'+spec['folder'];rows=[r for r in bounds[path] if r['name'] not in spec.get('exclude',[])]
        low=[min(r['min'][i] for r in rows) for i in range(3)];high=[max(r['max'][i] for r in rows) for i in range(3)]
        width,depth=high[0]-low[0],high[2]-low[2]
        forward=spec.get('front',1);qx,qz=zone['position_xz'];preferred=math.atan2((qx-p.x)*forward,(qz-p.y)*forward)
        if spec['id']=='uabcs_rectoria':
            preferred=math.pi/2  # Official plan: facade toward the internal courtyard, east.
        if spec['id']=='uabcs_gimnasio':
            pano=project((24.102083,-110.314333))
            preferred=math.atan2(pano[0]-p.x,pano[1]-p.y)
        yaw=preferred;scale=1.0
        if poly is not None:
            rect=poly.minimum_rotated_rectangle;coords=list(rect.exterior.coords);fits=[]
            for a,b in zip(coords,coords[1:]):
                y=-math.atan2(b[1]-a[1],b[0]-a[0]);local=rotate(poly,math.degrees(y),origin=(p.x,p.y));x0,z0,x1,z1=local.bounds
                s=min((x1-x0)/width,(z1-z0)/depth)*.92
                turn=abs(math.atan2(math.sin(y-preferred),math.cos(y-preferred)))
                fits.append((s,turn,y))
            best=max(f[0] for f in fits);scale,_,yaw=min((f for f in fits if f[0]>=best*.80),key=lambda f:f[1])
        def mask(s):return translate(rotate(box(-width*s/2,-depth*s/2,width*s/2,depth*s/2),-math.degrees(yaw),origin=(0,0)),p.x,p.y)
        envelope=mask(scale)
        while envelope.intersection(asphalt).area>1e-6 or envelope.intersects(car):
            scale*=.96;envelope=mask(scale)
            assert scale>.12, spec['id']
        removed=[identities[int(i)] for i in tree.query(envelope) if polygons[int(i)].intersection(envelope).area>.5]
        if 'building' in spec:removed.append(spec['building'])
        if 'way' in spec:removed += [b for b in buildings if b.startswith('osm:'+spec['way']+':')]
        assert all(envelope.intersection(other).area<1e-6 for other in masks),'Models overlap'
        masks.append(envelope)
        lat=data['metadata']['origin_lat']-math.degrees(p.y/6371000)
        lon=data['metadata']['origin_lon']+math.degrees(p.x/(6371000*math.cos(math.radians(data['metadata']['origin_lat']))))
        evidence={'source_ref':('footprint:'+spec['building']) if 'building' in spec else 'osm:way:'+spec['way'] if 'way' in spec else 'osm:node:'+spec['node'],'verified':True,'method':'Source footprint location; campus identity from relative matching to official 2022 plan; not surveyed' if spec.get('campus') else 'Existing OSM geometry; model scale/orientation adapted for playable asphalt','osm_snapshot_sha256':hashes['data/raw/osm_map_c6_boundary_expansion.osm'],'checked_on':'2026-11-17'}
        references=[{'title':'Fuente institucional','url':spec['url']}]
        if spec.get('campus'):references.append({'title':'Plano oficial del campus 2022','url':campus_url})
        if spec.get('extra_url'):references.append({'title':'Coordenadas de panorámicas oficiales','url':spec['extra_url']})
        poi={**old.get(spec['poi'],{}),'id':spec['poi'],'name':spec['name'],'category':'Universidad' if spec.get('campus') else 'Arte, historia y patrimonio','latitude':lat,'longitude':lon,'position_xz':[p.x,p.y],'description':spec['description'],'references':references,'coordinate_evidence':evidence,'activation':zone,'enabled':True,'model_id':spec['id']}
        # Stable discovery IDs are retained; their position now follows the actual model.
        pois.append(poi)
        models.append({'id':spec['id'],'poi_id':spec['poi'],'name':spec['name'],'scene':path,'model_sha256':sha(path.removeprefix('res://')),'position_xz':[p.x,p.y],'yaw':yaw,'scale':scale,'source_bounds_min':low,'source_bounds_max':high,'exclude_nodes':spec.get('exclude',[]),'footprint_xz':[list(p) for p in list(envelope.exterior.coords)[:-1]],'suppress_building_ids':sorted(set(removed)),'campus':spec.get('campus',False),'identity_confidence':'generic_representation_only' if spec.get('generic') else 'relative_plan_match_approximate' if spec.get('campus') else 'source_geometry','coordinate_evidence':evidence,'references':references,'plan_label':spec.get('plan_label'),'asphalt_overlap_m2':envelope.intersection(asphalt).area})
    # Main campus interaction is on an existing internal roadway, inside its parcel.
    rectoria=next(p for p in pois if p['id']=='poi_007');p=Point(rectoria['activation']['position_xz']);assert xml_polys['137201460'].contains(p)
    campus_poi={**rectoria,'id':'poi_006','name':'Universidad Autónoma de Baja California Sur','category':'Universidad','position_xz':[p.x,p.y],'latitude':data['metadata']['origin_lat']-math.degrees(p.y/6371000),'longitude':data['metadata']['origin_lon']+math.degrees(p.x/(6371000*math.cos(math.radians(data['metadata']['origin_lat'])))),'description':'Campus La Paz de la UABCS. Este punto de registro está dentro de la universidad, sobre una vialidad existente del campus. Los modelos académicos genéricos se identifican como aproximaciones.','coordinate_evidence':{'verified':True,'source_ref':'osm:way:137201460','method':'Point on existing mapped internal roadway inside the OSM campus parcel; not an official entrance coordinate'},'model_id':'uabcs_campus'}
    # Separate the campus marker from Rectoría so E never targets two entries at once.
    available=[]
    for r in data['roads']:
        if r['id'] not in active:continue
        line=LineString(r['points_xz']);q=line.interpolate(.5,normalized=True)
        if xml_polys['137201460'].contains(q) and all(q.distance(Point(v['activation']['position_xz']))>28 for v in pois):available.append((q.distance(p),q))
    for _,q in sorted(available,key=lambda x:x[0]):
        z,c=approach(q)
        if xml_polys['137201460'].contains(Point(z['position_xz'])):
            campus_poi['activation']=z;campus_poi['position_xz']=z['position_xz'];campus_poi['latitude']=data['metadata']['origin_lat']-math.degrees(z['position_xz'][1]/6371000);campus_poi['longitude']=data['metadata']['origin_lon']+math.degrees(z['position_xz'][0]/(6371000*math.cos(math.radians(data['metadata']['origin_lat']))));break
    pois.append(campus_poi);pois.sort(key=lambda p:p['id'])
    assert len(pois)==11 and all(sha(p)==h for p,h in hashes.items())
    retired=['poi_007','poi_008','poi_009','poi_010','poi_011']
    pois=[p for p in pois if p['id'] not in retired]
    for model in models:
        if model['campus']:model['poi_id']='poi_006'
    write('data/passport/landmark_models.json',{'schema_version':1,'map_sha256':hashes['data/processed/la_paz_map.json'],'arcade_sha256':hashes['data/processed/arcade_layout.json'],'source_hashes':hashes,'models':models,'campus_polygon_xz':[list(p) for p in xml_polys['137201460'].exterior.coords],'note':'Source coordinates retained; dimensions/orientation estimated. Campus identifications approximate relative-plan matches; generic buildings have no confirmed departmental identity. No source buildings are deleted: runtime suppression only.'})
    write('data/passport/pois.json',{'schema_version':1,'content_revision':3,'retired_poi_ids':retired,'map_sha256':hashes['data/processed/la_paz_map.json'],'origin_lat':data['metadata']['origin_lat'],'origin_lon':data['metadata']['origin_lon'],'max_active_pois':64,'pois':pois})
    print(json.dumps({'models':len(models),'pois':len(pois),'suppressed':len(set(i for m in models for i in m['suppress_building_ids'])),'models_summary':[{k:m[k] for k in ['id','scale','position_xz','identity_confidence']} for m in models]},indent=2))

if __name__=='__main__':build()
