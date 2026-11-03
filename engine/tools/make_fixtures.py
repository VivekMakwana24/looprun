"""Generate the GPX test fixtures deterministically (stdlib only).

Usage: python engine/tools/make_fixtures.py [out_dir]
Default out_dir is engine/tests/fixtures. Local metres (x east, y north) are
placed around Frankfurt (50.0 N, 8.7 E).
"""

from __future__ import annotations

import math
import random
import sys
from datetime import UTC, datetime
from pathlib import Path

R = 6371008.8
LAT0, LNG0 = 50.0, 8.7
T0_MS = int(datetime(2026, 5, 2, 8, 0, 0, tzinfo=UTC).timestamp() * 1000)

Point = dict  # lat, lng, t, acc, mock


def to_latlng(x: float, y: float) -> tuple[float, float]:
    return (
        LAT0 + math.degrees(y / R),
        LNG0 + math.degrees(x / (R * math.cos(math.radians(LAT0)))),
    )


def walk(vertices, speed, interval_s, rng, noise_m=1.5, mock=False, t0=T0_MS):
    """Walk a polyline at constant speed, one fix per interval; first and last are exact."""
    seg = [math.dist(a, b) for a, b in zip(vertices, vertices[1:], strict=False)]
    total = sum(seg)
    step = speed * interval_s
    samples = []  # (s, x, y)
    s = 0.0
    while s < total - 1e-9:
        d, i = s, 0
        while i < len(seg) - 1 and d > seg[i]:
            d -= seg[i]
            i += 1
        f = d / seg[i] if seg[i] else 0.0
        (x0, y0), (x1, y1) = vertices[i], vertices[i + 1]
        samples.append((s, x0 + (x1 - x0) * f, y0 + (y1 - y0) * f))
        s += step
    if len(samples) > 1 and total - samples[-1][0] < step / 2:
        samples.pop()
    samples.append((total, *vertices[-1]))
    pts: list[Point] = []
    for k, (s, x, y) in enumerate(samples):
        if 0 < k < len(samples) - 1 and noise_m:
            x += rng.gauss(0, noise_m)
            y += rng.gauss(0, noise_m)
        lat, lng = to_latlng(x, y)
        pts.append({
            "lat": lat, "lng": lng, "t": t0 + round(s / speed * 1000),
            "acc": round(rng.uniform(4, 12), 1), "mock": mock,
        })
    return pts


def square(side, origin=(0.0, 0.0)):
    ox, oy = origin
    return [(ox, oy), (ox + side, oy), (ox + side, oy + side), (ox, oy + side), (ox, oy)]


def clean_square(rng):
    return walk(square(400), 3.0, 5, rng)


def figure_eight(rng):
    a, amp, n = 250.0, 150.0, 140
    # Gerono lemniscate, starting at the right tip, ending exactly there.
    v = []
    for k in range(n + 1):
        t = math.pi / 2 + 2 * math.pi * k / n
        v.append((a * math.sin(t), amp * math.sin(2 * t)))
    v[-1] = v[0]
    return walk(v, 3.0, 5, rng, noise_m=1.0)


def near_closed(rng, gap):
    return walk([(0, 0), (400, 0), (400, 400), (0, 400), (0, gap)], 3.0, 5, rng)


def out_and_back(rng):
    return walk([(0, 0), (1000, 0), (1000, 3), (0, 3)], 3.0, 5, rng)


def jitter(rng):
    pts = []
    for k in range(90):
        lat, lng = to_latlng(rng.gauss(0, 2.0), rng.gauss(0, 2.0))
        pts.append({"lat": lat, "lng": lng, "t": T0_MS + k * 5000,
                    "acc": round(rng.uniform(6, 14), 1), "mock": False})
    return pts


def car_drive(rng):
    return walk(square(700), 9.0, 5, rng)


def teleport(rng):
    pts = walk(square(400), 3.0, 5, rng)
    out = []
    for k, p in enumerate(pts):
        if k >= 60:
            x = math.radians(p["lng"] - LNG0) * R * math.cos(math.radians(LAT0)) + 1500
            y = math.radians(p["lat"] - LAT0) * R + 1500
            p = {**p, "lat": LAT0 + math.degrees(y / R),
                 "lng": LNG0 + math.degrees(x / (R * math.cos(math.radians(LAT0))))}
        out.append(p)
    return out


def mock_run(rng):
    return [{**p, "mock": k >= 10} for k, p in enumerate(walk(square(400), 3.0, 5, rng))]


def tiny_loop(rng):
    return walk(square(60), 3.0, 2, rng, noise_m=0.5)


def drop_window(points, start_s, end_s):
    """Remove fixes between start_s and end_s after the first fix (a signal outage)."""
    t0 = points[0]["t"]
    return [p for p in points if not (start_s * 1000 <= p["t"] - t0 < end_s * 1000)]


def gps_dropout(rng):
    # 40 s without fixes in the middle of the second side, runner keeps moving at 3 m/s
    return drop_window(walk(square(400), 3.0, 5, rng), 200, 240)


def tunnel(rng):
    # 90 s gap (270 m of route); fixes resume on the route further along
    return drop_window(walk(square(400), 3.0, 5, rng), 180, 270)


def bowtie(rng):
    return walk([(0, 0), (400, 0), (0, 400), (400, 400), (0, 0)], 3.0, 5, rng)


BUILDERS = {
    "clean_square": clean_square,
    "figure_eight": figure_eight,
    "near_closed_60m": lambda rng: near_closed(rng, 60),
    "near_closed_120m": lambda rng: near_closed(rng, 120),
    "out_and_back": out_and_back,
    "jitter": jitter,
    "car_drive": car_drive,
    "teleport": teleport,
    "mock": mock_run,
    "tiny_loop": tiny_loop,
    "gps_dropout": gps_dropout,
    "tunnel": tunnel,
    "bowtie": bowtie,
}


def build(name: str) -> list[Point]:
    """Points for one fixture; each fixture has its own fixed seed."""
    return BUILDERS[name](random.Random(f"looprun-{name}"))


def gpx_text(points: list[Point], name: str = "fixture") -> str:
    lines = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        '<gpx version="1.1" creator="looprun make_fixtures" xmlns="http://www.topografix.com/GPX/1/1">',
        f"  <trk><name>{name}</name><trkseg>",
    ]
    for p in points:
        ts = datetime.fromtimestamp(p["t"] / 1000, UTC).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"
        ext = f"<acc>{p['acc']}</acc>" + ("<mock>true</mock>" if p["mock"] else "")
        lines.append(
            f'    <trkpt lat="{p["lat"]:.7f}" lon="{p["lng"]:.7f}">'
            f"<time>{ts}</time><extensions>{ext}</extensions></trkpt>"
        )
    lines += ["  </trkseg></trk>", "</gpx>", ""]
    return "\n".join(lines)


def write_all(out_dir: Path) -> list[Path]:
    out_dir.mkdir(parents=True, exist_ok=True)
    paths = []
    for name in BUILDERS:
        path = out_dir / f"{name}.gpx"
        path.write_text(gpx_text(build(name), name), encoding="utf-8")
        paths.append(path)
    return paths


if __name__ == "__main__":
    target = Path(sys.argv[1]) if len(sys.argv) > 1 else (
        Path(__file__).resolve().parents[1] / "tests" / "fixtures")
    for p in write_all(target):
        print("wrote", p)
