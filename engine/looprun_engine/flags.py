"""Step 4: plausibility flags."""

from __future__ import annotations

from .geo import haversine_m
from .models import Config, Fix, Flag


def cumulative_distance(fixes: list[Fix]) -> list[float]:
    cum = [0.0]
    for a, b in zip(fixes, fixes[1:], strict=False):
        cum.append(cum[-1] + haversine_m(a.lat, a.lng, b.lat, b.lng))
    return cum


def speed_flags(fixes: list[Fix], cum: list[float], cfg: Config) -> list[Flag]:
    flags: list[Flag] = []
    # teleport: a single hop faster than max_jump_speed_ms (times are strictly increasing)
    jumps, worst, worst_i = 0, 0.0, 0
    for i in range(1, len(fixes)):
        v = (cum[i] - cum[i - 1]) / ((fixes[i].t - fixes[i - 1].t) / 1000)
        if v > cfg.max_jump_speed_ms:
            jumps += 1
            if v > worst:
                worst, worst_i = v, i
    if jumps:
        flags.append(Flag("teleport", "hard",
                          f"{jumps} jump(s) above {cfg.max_jump_speed_ms} m/s; "
                          f"fastest {worst:.1f} m/s at fix {worst_i}"))

    # vehicle_speed: average over any window of at least sustained_window_s
    window_ms = cfg.sustained_window_s * 1000
    best, j = 0.0, 0
    for i in range(len(fixes)):
        j = max(j, i)
        while j < len(fixes) and fixes[j].t - fixes[i].t < window_ms:
            j += 1
        if j >= len(fixes):
            break
        v = (cum[j] - cum[i]) / ((fixes[j].t - fixes[i].t) / 1000)
        best = max(best, v)
    if best > cfg.max_sustained_speed_ms:
        flags.append(Flag("vehicle_speed", "hard",
                          f"{best:.1f} m/s sustained over {cfg.sustained_window_s} s "
                          f"(limit {cfg.max_sustained_speed_ms} m/s)"))
    return flags
