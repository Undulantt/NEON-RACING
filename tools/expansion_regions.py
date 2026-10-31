"""Shared geographic block and user-defined clipping masks."""
from shapely.geometry import box, Polygon
from shapely.ops import unary_union, transform


def clip_lonlat(cfg):
    points = cfg.get("clip_polygon_lonlat")
    if not points:
        return None
    polygon = Polygon(points)
    if not polygon.is_valid or polygon.is_empty:
        raise ValueError("Invalid user clipping polygon")
    return polygon


def region_lonlat(cfg):
    areas = cfg.get("active_blocks", {"default": cfg["bbox"]})
    polygons = cfg.get("block_polygons_lonlat", {})
    region = unary_union([Polygon(polygons[key]) if key in polygons else box(b[1], b[0], b[3], b[2]) for key,b in areas.items()])
    clip = clip_lonlat(cfg)
    return region.intersection(clip) if clip is not None else region


def project_geometry(geometry, cfg):
    from map_core import gps_to_local
    def project(x, y, z=None):
        if hasattr(x, "__iter__"):
            values = [gps_to_local(lat, lon, cfg["origin_lat"], cfg["origin_lon"]) for lon, lat in zip(x, y)]
            return [p[0] for p in values], [p[1] for p in values]
        return gps_to_local(y, x, cfg["origin_lat"], cfg["origin_lon"])
    return transform(project, geometry)


def metric_region(cfg):
    return project_geometry(region_lonlat(cfg), cfg)


def metric_clip(cfg):
    polygon = clip_lonlat(cfg)
    return project_geometry(polygon, cfg) if polygon is not None else None
