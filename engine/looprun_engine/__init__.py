"""Looprun engine: loop detection, H3 cell capture, ownership. Pure, deterministic, no I/O."""

from .cells import cell_centre, cells_for_bbox, in_home_zone
from .gpx import gpx_to_fixes
from .models import CellChange, CellPower, Config, Fix, Flag, Loop, RunResult
from .ownership import apply_claim, faded_power
from .pipeline import effort_credit, process_run

__all__ = [
    "CellChange",
    "CellPower",
    "Config",
    "Fix",
    "Flag",
    "Loop",
    "RunResult",
    "apply_claim",
    "cell_centre",
    "cells_for_bbox",
    "effort_credit",
    "faded_power",
    "gpx_to_fixes",
    "in_home_zone",
    "process_run",
]
