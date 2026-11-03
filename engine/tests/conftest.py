import sys
from pathlib import Path

import pytest

ENGINE = Path(__file__).resolve().parents[1]
FIXTURES = Path(__file__).resolve().parent / "fixtures"
sys.path.insert(0, str(ENGINE / "tools"))

from looprun_engine import gpx_to_fixes, process_run  # noqa: E402


@pytest.fixture
def load():
    """load(name) -> list[Fix] from tests/fixtures/<name>.gpx"""
    return lambda name: gpx_to_fixes((FIXTURES / f"{name}.gpx").read_text(encoding="utf-8"))


@pytest.fixture
def run(load):
    return lambda name: process_run(load(name))
