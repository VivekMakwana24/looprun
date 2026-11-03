"""Small geodesy helpers (spherical earth, good to well under 0.5% at city scale)."""

from __future__ import annotations

import math

EARTH_R_M = 6371008.8


def haversine_m(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dphi = p2 - p1
    dlam = math.radians(lng2 - lng1)
    a = math.sin(dphi / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dlam / 2) ** 2
    return 2 * EARTH_R_M * math.asin(min(1.0, math.sqrt(a)))


class LocalProjection:
    """Equirectangular projection around an origin, in metres (x east, y north)."""

    def __init__(self, lat0: float, lng0: float) -> None:
        self.lat0 = lat0
        self.lng0 = lng0
        self._kx = EARTH_R_M * math.cos(math.radians(lat0))
        self._ky = EARTH_R_M

    def to_xy(self, lat: float, lng: float) -> tuple[float, float]:
        return (
            math.radians(lng - self.lng0) * self._kx,
            math.radians(lat - self.lat0) * self._ky,
        )

    def to_latlng(self, x: float, y: float) -> tuple[float, float]:
        return (
            self.lat0 + math.degrees(y / self._ky),
            self.lng0 + math.degrees(x / self._kx),
        )
