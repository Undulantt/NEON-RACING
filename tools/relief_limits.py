"""Bake elevated boundary walls into streamed sectors, never thousands of global boxes."""
import hashlib
import math
import struct
from collections import defaultdict

from relief_core import write


def bake_limits(out,region,field,root):
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
        path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(content)
        entries.append(dict(id=f'{cx}_{cz}',origin_xz=[cx*256,cz*256],file=path.relative_to(root).as_posix(),
            sha256=hashlib.sha256(content).hexdigest(),triangles_count=len(content)//36))
    return entries
