"""D.4: three documented places; derived safe approach points, no invented POIs."""
import hashlib,json,math,sys,xml.etree.ElementTree as ET
from pathlib import Path
from shapely.geometry import Point,Polygon,LineString,box
from shapely.affinity import rotate,translate
from shapely.ops import unary_union
from shapely.prepared import prep
from map_core import gps_to_local

ROOT=Path(__file__).resolve().parents[1]
def read(p):return json.loads((ROOT/p).read_text(encoding='utf8'))
def sha(p):return hashlib.sha256((ROOT/p).read_bytes()).hexdigest()

def build():
    if (ROOT/'data/passport/landmark_models.json').exists():
        from build_passport_landmarks import build as expanded_build
        expanded_build()
        return
    m=read('data/processed/la_paz_map.json');cfg=m['metadata']
    osm_path='data/raw/osm_map_c6_boundary_expansion.osm'
    osm=ET.parse(ROOT/osm_path).getroot();nodes={e.attrib['id']:(float(e.attrib['lon']),float(e.attrib['lat'])) for e in osm.findall('node')}
    c=next(e for e in osm.findall('way') if e.attrib['id']=='155831066')
    center=Polygon([nodes[n.attrib['ref']] for n in c.findall('nd')]).centroid
    definitions=[
      ('poi_001','Kiosco del Malecón','Patrimonio y turismo',24.163772,-110.3165411,'obreg','osm:node:9284265569','Punto OSM histórico del kiosco; corroborado por la ubicación municipal en Obregón y 16 de Septiembre.','Espacio de encuentro en el Malecón, frente a la bahía de La Paz. Su entorno reúne paseo, descanso y actividades turísticas en el centro de la ciudad.','https://turismo.lapaz.gob.mx/atractivos/kiosco-del-malecon-18'),
      ('poi_002','Catedral de Nuestra Señora de La Paz','Historia y arquitectura',center.y,center.x,'revoluc','osm:way:155831066','Centro del contorno OSM de la Catedral; no es una coordenada de acceso vehicular.','Templo del centro histórico dedicado a Nuestra Señora de La Paz. La primera piedra de la construcción actual se colocó el 6 de octubre de 1861.','https://turismo.lapaz.gob.mx/atractivos/catedral-de-nuestra-senora-de-la-paz'),
      ('poi_003','Teatro de la Ciudad','Arte y cultura',24.147021132883,-110.31775828735,'navarro','sic:teatro:12','Coordenadas del enlace cartográfico de la ficha oficial SIC. El edificio OSM 155831068 identifica el mismo conjunto, con un punto representativo distinto. No corresponde al Teatro Juárez.','Recinto de la Unidad Cultural Profesor Jesús Castro Agúndez. Fue inaugurado el 26 de enero de 1986 y alberga presentaciones de teatro, música y danza.','https://sic.cultura.gob.mx/ficha.php?table=teatro&table_id=12')]
    arcade=read('data/processed/arcade_layout.json')
    asphalt=unary_union([Polygon([(x+c['origin_xz'][0],z+c['origin_xz'][1]) for x,z in t]) for c in arcade['chunks'] for t in c['triangles_xz']])
    supported=prep(asphalt.buffer(.001))
    records=[]
    for ident,name,category,lat,lon,street,ref,note,description,url in definitions:
        p=Point(gps_to_local(lat,lon,cfg['origin_lat'],cfg['origin_lon']))
        candidates=[]
        for road in m['roads']:
            if street not in road['street_name'].lower():continue
            line=LineString(road['points_xz'])
            for t in [max(.15,min(.85,line.project(p)/line.length)),.25,.5,.75]:
                q=line.interpolate(t,normalized=True)
                a,b=list(line.coords)[0],list(line.coords)[-1]
                angle=math.degrees(math.atan2(b[1]-a[1],b[0]-a[0]))
                car=translate(rotate(box(-5.5,-2.6,5.5,2.6),angle,origin=(0,0)),q.x,q.y)
                if supported.covers(car):candidates.append((q.distance(p),road,t,q))
        if not candidates:raise ValueError('No supported road approach: '+name)
        distance,road,t,q=min(candidates,key=lambda v:v[0])
        assert distance<180,(name,distance)
        assert cfg['bbox'][0]<=lat<=cfg['bbox'][2] and cfg['bbox'][1]<=lon<=cfg['bbox'][3]
        records.append({'id':ident,'name':name,'category':category,'latitude':lat,'longitude':lon,'position_xz':[p.x,p.y],'description':description,'references':[{'title':'Fuente oficial','url':url}],'coordinate_evidence':{'verified':True,'source_ref':ref,'method':note,'osm_snapshot_sha256':sha(osm_path),'checked_on':'2026-11-16'},'activation':{'road_id':road['id'],'t':t,'radius_m':9.0,'max_speed_mps':3.0,'position_xz':[q.x,q.y],'street':road['street_name'],'offset_from_place_m':distance,'validated':True,'validation_map_sha256':sha('data/processed/la_paz_map.json'),'validation_method':'offline 11 x 5.2 m vehicle footprint covered by current arcade asphalt'},'enabled':True})
    output={'schema_version':1,'map_sha256':sha('data/processed/la_paz_map.json'),'origin_lat':cfg['origin_lat'],'origin_lon':cfg['origin_lon'],'max_active_pois':3,'pois':records}
    path=ROOT/'data/passport/pois.json';path.parent.mkdir(parents=True,exist_ok=True)
    path.write_bytes((json.dumps(output,ensure_ascii=False,indent=2)+'\n').encode('utf8'))
    print(json.dumps([{'id':p['id'],'name':p['name'],'geo':[p['latitude'],p['longitude']],'approach':p['activation']} for p in records],ensure_ascii=True,indent=2))

if __name__=='__main__':build()
