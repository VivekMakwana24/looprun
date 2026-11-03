"""Step 1: fix cleaning."""

from __future__ import annotations

import math

from .models import Config, Fix


def clean_fixes(fixes: list[Fix], cfg: Config) -> list[Fix]:
    """Drop poor / invalid fixes, sort by time, drop duplicate timestamps.

    No smoothing is applied, so first and last points equal the raw ones.
    """
    good = [
        f
        for f in fixes
        if math.isfinite(f.lat)
        and math.isfinite(f.lng)
        and -90.0 <= f.lat <= 90.0
        and -180.0 <= f.lng <= 180.0
        and f.acc <= cfg.max_acc_m  # NaN accuracy is dropped too
    ]
    good.sort(key=lambda f: f.t)  # stable: the first of equal timestamps stays first
    out: list[Fix] = []
    for f in good:
        if out and f.t == out[-1].t:
            continue
        out.append(f)
    return out
