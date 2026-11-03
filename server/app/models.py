"""Pydantic request/response models (the contract in docs/CONTRACT.openapi.yaml)."""

from __future__ import annotations

from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field, model_validator

MAX_MS = 4_102_444_800_000  # year 2100: keeps every integer far inside int64


class UserRef(BaseModel):
    id: str
    name: str


class Session(BaseModel):
    access_token: str
    user: UserRef


class GoogleAuthRequest(BaseModel):
    id_token: str = Field(min_length=1, max_length=8192)


class FixIn(BaseModel):
    lat: float = Field(ge=-90, le=90, allow_inf_nan=False)
    lng: float = Field(ge=-180, le=180, allow_inf_nan=False)
    t: int = Field(ge=0, le=MAX_MS)
    acc: float = Field(ge=0, le=100000, allow_inf_nan=False)
    mock: bool = False


class RunUpload(BaseModel):
    id: UUID
    started_at: int = Field(ge=0, le=MAX_MS)
    ended_at: int = Field(ge=0, le=MAX_MS)
    integrity_token: str | None = Field(default=None, max_length=16384)
    # No max_length here on purpose: too many fixes must be HTTP 413, not 422 (checked in the route).
    fixes: list[FixIn]

    @model_validator(mode="after")
    def _times(self) -> RunUpload:
        if self.ended_at < self.started_at:
            raise ValueError("ended_at must not be before started_at")
        return self


class FlagOut(BaseModel):
    code: str
    severity: Literal["hard", "soft"]
    detail: str = ""


class LoopOut(BaseModel):
    cells: int
    area_km2: float


class RunStatus(BaseModel):
    id: str
    status: Literal["processing", "accepted", "pending_review", "rejected"]
    distance_m: float | None = None
    moving_seconds: int | None = None
    loops: list[LoopOut] = []
    cells_claimed: int = 0
    cells_taken_from_others: int = 0
    flags: list[FlagOut] = []


class CellOut(BaseModel):
    id: str
    lat: float
    lng: float
    owner: UserRef | None = None
    mine: bool = False
    hidden: bool = False


class CellsResponse(BaseModel):
    cells: list[CellOut]


class LeaderboardEntry(BaseModel):
    rank: int
    user: UserRef
    cells: int


class LeaderboardResponse(BaseModel):
    week: str
    entries: list[LeaderboardEntry]


class HomeZone(BaseModel):
    lat: float = Field(ge=-90, le=90, allow_inf_nan=False)
    lng: float = Field(ge=-180, le=180, allow_inf_nan=False)
    radius_m: float = Field(ge=50, le=1000, allow_inf_nan=False)


class HomeZonesRequest(BaseModel):
    zones: list[HomeZone] = Field(default_factory=list, max_length=5)


class FreezeRequest(BaseModel):
    days: int = Field(ge=0, le=30)


class FreezeResponse(BaseModel):
    freeze_until: int | None


class ReportRequest(BaseModel):
    kind: Literal["run", "cell"]
    target_id: str = Field(min_length=1, max_length=100)
    reason: str = Field(min_length=1, max_length=500)
