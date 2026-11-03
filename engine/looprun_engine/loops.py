"""Step 2/3: loop detection and H3 cell coverage."""

from __future__ import annotations

import math

import h3
from shapely.geometry import LineString, Polygon
from shapely.geometry.polygon import orient
from shapely.ops import polygonize, unary_union

from .geo import LocalProjection
from .models import Config, Fix, Flag, Loop

# Not part of Config (the public Config is fixed); GPS-noise guards.
NOISE_AREA_M2 = 400.0  # faces smaller than this are GPS noise, ignored silently
MIN_COMPACTNESS = 0.05  # 4*pi*A/P^2; slivers (out-and-back on one road) are ignored silently
REPAIR_MIN_GAP_M = 10.0  # a closing gap smaller than this is just noise, not a "repair"


def _polygon_cells(ring_latlng: list[tuple[float, float]], res: int, poly: Polygon,
                   proj: LocalProjection) -> list[str]:
    outer = ring_latlng[:-1]
    cells = set(h3.h3shape_to_cells(h3.LatLngPoly(outer), res))
    if not cells:  # valid loop smaller than any cell centre: take the cell it sits in
        pt = poly.representative_point()
        lat, lng = proj.to_latlng(pt.x, pt.y)
        cells.add(h3.latlng_to_cell(lat, lng, res))
    return sorted(cells)


def find_loops(cleaned: list[Fix], cfg: Config) -> tuple[list[Loop], list[Flag]]:
    """Return accepted loops and the soft flags for rejected / repaired ones."""
    if len(cleaned) < 3:
        return [], []
    proj = LocalProjection(cleaned[0].lat, cleaned[0].lng)
    xy = [proj.to_xy(f.lat, f.lng) for f in cleaned]

    cum = [0.0]
    for (x0, y0), (x1, y1) in zip(xy, xy[1:], strict=False):
        cum.append(cum[-1] + math.hypot(x1 - x0, y1 - y0))

    # Near-closure: nearest earlier vertex to the last point, ignoring the last
    # closure_tol_m of path (those are trivially close).
    last = xy[-1]
    best_j, best_d = -1, math.inf
    for j in range(len(xy) - 1):
        if cum[-1] - cum[j] <= cfg.closure_tol_m:
            break
        d = math.hypot(last[0] - xy[j][0], last[1] - xy[j][1])
        if d <= cfg.closure_tol_m and d < best_d:
            best_j, best_d = j, d

    coords = list(xy)
    closing: LineString | None = None
    gap = 0.0
    if best_j >= 0 and best_d > 1e-6:
        coords.append(xy[best_j])
        closing = LineString([last, xy[best_j]])
        gap = best_d
    if len({*coords}) < 3:
        return [], []

    noded = unary_union(LineString(coords))
    loops: list[tuple[float, Polygon]] = []
    small = large = 0
    for poly in polygonize(noded):
        area_m2 = poly.area
        perimeter_m = poly.exterior.length
        if area_m2 < NOISE_AREA_M2 or 4 * math.pi * area_m2 / perimeter_m**2 < MIN_COMPACTNESS:
            continue
        if area_m2 / 1e6 < cfg.min_loop_area_km2:
            small += 1
        elif perimeter_m / 1000 > cfg.max_loop_perimeter_km:
            large += 1
        else:
            loops.append((area_m2, orient(Polygon(poly.exterior), 1.0)))

    flags: list[Flag] = []
    if small:
        flags.append(Flag("loop_rejected_small", "soft",
                          f"{small} loop(s) below {cfg.min_loop_area_km2} km2"))
    if large:
        flags.append(Flag("loop_rejected_large", "soft",
                          f"{large} loop(s) with perimeter above {cfg.max_loop_perimeter_km} km"))

    loops.sort(key=lambda item: (-item[0], item[1].centroid.x, item[1].centroid.y))
    result: list[Loop] = []
    any_repaired = False
    for area_m2, poly in loops:
        ring = [proj.to_latlng(x, y) for x, y in poly.exterior.coords]
        repaired = False
        if closing is not None and gap > REPAIR_MIN_GAP_M:
            mid = closing.interpolate(0.5, normalized=True)
            repaired = poly.exterior.distance(mid) < 0.5
        any_repaired = any_repaired or repaired
        result.append(Loop(
            polygon=ring,
            area_km2=area_m2 / 1e6,
            cells=_polygon_cells(ring, cfg.h3_res, poly, proj),
            repaired=repaired,
        ))
    if any_repaired:
        flags.append(Flag("near_closure_repaired", "soft",
                          f"path ended {gap:.0f} m from an earlier point; closed automatically"))
    return result, flags
