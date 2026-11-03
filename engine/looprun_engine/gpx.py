"""Minimal GPX reader (tracks only)."""

from __future__ import annotations

import xml.etree.ElementTree as ET
from datetime import UTC, datetime

from .models import Fix

DEFAULT_ACC_M = 5.0


def _local(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def _parse_time_ms(text: str) -> int:
    dt = datetime.fromisoformat(text.strip().replace("Z", "+00:00"))
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=UTC)
    return int(round(dt.timestamp() * 1000))


def gpx_to_fixes(gpx_text: str) -> list[Fix]:
    """Parse <trkpt> elements.

    Accuracy is read from <extensions><acc>, else <hdop> * 5, else 5 m. A mock
    flag is read from <extensions><mock>true</mock>. Points need a <time>.
    """
    upper = gpx_text.upper()
    if "<!DOCTYPE" in upper or "<!ENTITY" in upper:
        raise ValueError("GPX with DTD/entity declarations is not accepted")
    root = ET.fromstring(gpx_text)
    fixes: list[Fix] = []
    for el in root.iter():
        if _local(el.tag) != "trkpt":
            continue
        values: dict[str, str] = {}
        for child in el.iter():
            if child is not el:
                values[_local(child.tag)] = (child.text or "").strip()
        if "time" not in values or not values["time"]:
            raise ValueError("trkpt without <time>")
        if "acc" in values and values["acc"]:
            acc = float(values["acc"])
        elif "hdop" in values and values["hdop"]:
            acc = float(values["hdop"]) * 5.0
        else:
            acc = DEFAULT_ACC_M
        fixes.append(
            Fix(
                lat=float(el.attrib["lat"]),
                lng=float(el.attrib["lon"]),
                t=_parse_time_ms(values["time"]),
                acc=acc,
                mock=values.get("mock", "").lower() in ("true", "1"),
            )
        )
    return fixes
