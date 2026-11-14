"""Institutional parcels prohibit invented infill, not surveyed buildings."""
from shapely.geometry import shape
from shapely.ops import unary_union


def institutional_parcel(tags):
    return tags.get('amenity') in ('school', 'university', 'hospital') and tags.get('building') in (None, 'no')


def real_building_exclusions(records):
    # Explicit parks, pitches, parking, water, paths, etc. remain protected,
    # including those nested inside a campus. Fictional fill uses ALL records.
    return unary_union([shape(p['geometry_xz']) for p in records if not institutional_parcel(p.get('tags', {}))])
