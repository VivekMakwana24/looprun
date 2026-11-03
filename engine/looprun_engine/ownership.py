"""Cell power fading and ownership."""

from __future__ import annotations

from dataclasses import replace

from .models import CellChange, CellPower, Config

DAY_MS = 86_400_000


def faded_power(
    p: CellPower, now: int, cfg: Config = Config(), freeze_until: int | None = None
) -> float:
    """Power of `p` at time `now`.

    No fading for grace_days after updated_at, then a half-life decay. If
    freeze_until is in the future at `now` the power does not fade at all.
    """
    if freeze_until is not None and freeze_until > now:
        return p.power
    grace_end = p.updated_at + cfg.grace_days * DAY_MS
    past = now - grace_end
    if past <= 0:
        return p.power
    return p.power * 0.5 ** ((past / DAY_MS) / cfg.halflife_days)


def apply_claim(
    cell: str,
    powers: dict[str, CellPower],
    current_owner: str | None,
    user_id: str,
    credit: float,
    now: int,
    cfg: Config = Config(),
    freezes: dict[str, int] | None = None,
) -> tuple[dict[str, CellPower], CellChange | None]:
    """Add `credit` for `user_id` in `cell` and decide the owner.

    The inputs are not mutated. A challenger needs strictly more faded power
    than the current owner; ties keep the owner.
    """
    if credit < 0:
        raise ValueError("credit must be >= 0")
    freezes = freezes or {}
    new_powers = {uid: replace(p) for uid, p in powers.items()}

    mine = new_powers.get(user_id)
    if mine is not None or credit > 0:
        base = faded_power(mine, now, cfg, freezes.get(user_id)) if mine is not None else 0.0
        new_powers[user_id] = CellPower(user_id=user_id, power=base + credit, updated_at=now)

    faded = {uid: faded_power(p, now, cfg, freezes.get(uid)) for uid, p in new_powers.items()}
    owner_power = faded.get(current_owner, 0.0) if current_owner is not None else 0.0

    best_user: str | None = None
    best_power = 0.0
    for uid in sorted(faded):  # sorted: deterministic tie-break among challengers
        if faded[uid] > best_power:
            best_user, best_power = uid, faded[uid]

    new_owner = current_owner
    if best_user is not None and best_power > owner_power:
        new_owner = best_user

    change = None
    if new_owner != current_owner:
        change = CellChange(cell=cell, old_owner=current_owner, new_owner=new_owner)
    return new_powers, change
