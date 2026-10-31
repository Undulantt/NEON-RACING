"""Small terrain-supported outward boundary adjustments, independent of GIS roads."""
import math
from shapely.geometry import Point, LineString
from shapely.ops import unary_union


def apply_boundary_outsets(region, adjustments):
    additions=[region]
    rings=[region.exterior] if region.geom_type=='Polygon' else [p.exterior for p in region.geoms]
    for item in adjustments:
        center=Point(item['center_xz']);radius=float(item['radius_m']);outset=float(item['outset_m'])
        if not 0<outset<radius:
            raise ValueError('Boundary outset must be positive and smaller than transition radius')
        for ring in rings:
            line=LineString(ring.coords)
            for s in range(0,math.ceil(line.length),8):
                point=line.interpolate(s);distance=point.distance(center)
                if distance>=radius:continue
                amount=outset*.5*(1+math.cos(math.pi*distance/radius))
                if amount>.25:additions.append(point.buffer(amount,quad_segs=6))
    return unary_union(additions)
