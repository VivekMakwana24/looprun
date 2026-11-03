"""H3 helpers."""

from __future__ import annotations

import math

import h3

from .geo import EARTH_R_M, haversine_m

MAX_BBOX_CELLS = 200_000


def cell_centre(cell: str) -> tuple[float, float]:
    lat, lng = h3.cell_to_latlng(cell)
    return (lat, lng)


def cells_for_bbox(
    min_lng: float, min_lat: float, max_lng: float, max_lat: float, res: int = 10
) -> list[str]:
    """Sorted cells that cover the bounding box.

    The box is grown by one cell edge length first, so cells that only partly
    overlap the box (centre outside) are included. Raises ValueError for an
    inverted box or one that would need more than MAX_BBOX_CELLS cells.
    """
    if min_lat > max_lat or min_lng > max_lng:
        raise ValueError("inverted bbox")
    edge_m = h3.average_hexagon_edge_length(res, unit="m")
    mid_lat = (min_lat + max_lat) / 2
    dlat = math.degrees(edge_m / EARTH_R_M)
    dlng = math.degrees(edge_m / (EARTH_R_M * max(0.01, math.cos(math.radians(mid_lat)))))
    s, n = max(-90.0, min_lat - dlat), min(90.0, max_lat + dlat)
    w, e = max(-180.0, min_lng - dlng), min(180.0, max_lng + dlng)
    height_km = math.radians(n - s) * EARTH_R_M / 1000
    width_km = math.radians(e - w) * EARTH_R_M * math.cos(math.radians(mid_lat)) / 1000
    if height_km * width_km / h3.average_hexagon_area(res, unit="km^2") > MAX_BBOX_CELLS:
        raise ValueError("bbox too large")
    poly = h3.LatLngPoly([(s, w), (s, e), (n, e), (n, w)])
    return sorted(h3.h3shape_to_cells(poly, res))


def in_home_zone(cell: str, zones: list[tuple[float, float, float]]) -> bool:
    """True if the cell centre is within radius_m of any (lat, lng, radius_m) zone."""
    lat, lng = cell_centre(cell)
    return any(haversine_m(lat, lng, zlat, zlng) <= r for zlat, zlng, r in zones)
