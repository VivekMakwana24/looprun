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
    # Corner points [lat, lng] of the hexagon (D10), so the app draws true cells without an H3 library.
    boundary: list[list[float]] = []
    owner: UserRef | None = None
    mine: bool = False
    hidden: bool = False
    # Only present on the caller's own cells (mine = true): faded power / stored power, 0..1.
    strength: float | None = Field(default=None, ge=0, le=1)


class CellsResponse(BaseModel):
    cells: list[CellOut]


class LeaderboardEntry(BaseModel):
    rank: int
    user: UserRef
    cells: int


class LeaderboardMe(BaseModel):
    # None when the caller holds no cells (not ranked).
    rank: int | None = None
    cells: int = 0


class LeaderboardResponse(BaseModel):
    week: str
    entries: list[LeaderboardEntry]
    # The caller's own place, also when it is below the listed entries (D10).
    me: LeaderboardMe = LeaderboardMe()


class HomeZone(BaseModel):
    lat: float = Field(ge=-90, le=90, allow_inf_nan=False)
    lng: float = Field(ge=-180, le=180, allow_inf_nan=False)
    radius_m: float = Field(ge=50, le=1000, allow_inf_nan=False)


class HomeZonesRequest(BaseModel):
    zones: list[HomeZone] = Field(default_factory=list, max_length=5)


class FreezeRequest(BaseModel):
    days: int = Field(ge=0, le=30)


class FreezeStatus(BaseModel):
    freeze_until: int | None = None
    # Whole frozen days (rounded up) inside the last `window_days`, the running freeze included up to now.
    used_days: int = 0
    quota_days: int = 30
    window_days: int = 90


class FreezeResponse(FreezeStatus):
    pass


class MeResponse(BaseModel):
    user: UserRef
    home_zones: list[HomeZone] = []
    freeze: FreezeStatus
    name_hidden: bool = False  # moderation hid the caller's name from others (Phase 1a)


class RenameRequest(BaseModel):
    # Length and characters are checked in the route (422 name_rejected); this only bounds the input size.
    display_name: str = Field(max_length=200)


class RenameResponse(BaseModel):
    user: UserRef


class Profile(BaseModel):
    id: str
    name: str
    cells_held: int
    weekly_rank: int | None
    followers_count: int
    following_count: int
    joined_at: int
    is_me: bool
    is_following: bool
    follows_me: bool


class ReportRequest(BaseModel):
    kind: Literal["run", "cell"]
    target_id: str = Field(min_length=1, max_length=100)
    reason: str = Field(min_length=1, max_length=500)


class UserListItem(BaseModel):
    id: str
    name: str
    is_following: bool
    follows_me: bool


class UserPage(BaseModel):
    items: list[UserListItem]
    next_cursor: str | None = None


class UserList(BaseModel):
    users: list[UserListItem]


class FollowState(BaseModel):
    is_following: bool
    followers_count: int


class TakenFrom(BaseModel):
    user: UserRef
    cells: int


class RunCard(BaseModel):
    """What a follower (or the owner) may see of an accepted run. Never GPS points, geometry, start or end."""

    id: str
    user: UserRef
    started_at: int
    distance_m: float | None = None
    moving_seconds: int | None = None
    pace_s_per_km: float | None = None
    cells_claimed: int = 0
    cells_taken: int = 0
    taken_from: list[TakenFrom] = []
    taken_from_hidden: int = 0
    loop_count: int = 0
    kudos_count: int = 0
    kudos_by_me: bool = False
    comment_count: int = 0
    status: Literal["processing", "accepted", "pending_review", "rejected"]


class RunPage(BaseModel):
    items: list[RunCard]
    next_cursor: str | None = None


class KudosState(BaseModel):
    kudos_by_me: bool
    kudos_count: int


class CommentRequest(BaseModel):
    # Length and characters are checked in the route (422 bad_text); this only bounds the input size.
    text: str = Field(max_length=5000)


class Comment(BaseModel):
    id: str
    run_id: str
    user: UserRef
    text: str
    created_at: int
    hidden: bool = False
    can_delete: bool


class CommentPage(BaseModel):
    items: list[Comment]
    next_cursor: str | None = None
