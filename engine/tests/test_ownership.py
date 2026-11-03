"""Table-driven tests for faded_power, apply_claim and effort_credit."""

import pytest

from looprun_engine import CellChange, CellPower, Config, apply_claim, effort_credit, faded_power

DAY = 86_400_000
CFG = Config()
NOW = 100 * DAY
CELL = "8a1f00000000fff"


def P(user, power, days_ago):
    return CellPower(user, power, NOW - int(days_ago * DAY))


# ---- faded_power ----------------------------------------------------------

@pytest.mark.parametrize(
    "days_since,expected",
    [
        (0, 10.0),
        (3, 10.0),
        (7, 10.0),            # grace ends exactly here: still no fade
        (7 + 14, 5.0),        # one half-life after grace
        (7 + 28, 2.5),
        (7 + 7, 10 * 0.5 ** 0.5),
        (-5, 10.0),           # clock skew: updated in the "future"
    ],
)
def test_faded_power_table(days_since, expected):
    p = CellPower("u", 10.0, NOW - days_since * DAY)
    assert faded_power(p, NOW, CFG) == pytest.approx(expected)


def test_grace_period_no_fading_for_7_days():
    p = CellPower("u", 10.0, 0)
    assert faded_power(p, int(6.99 * DAY), CFG) == 10.0
    assert faded_power(p, 7 * DAY, CFG) == 10.0
    assert faded_power(p, 7 * DAY + DAY, CFG) < 10.0


def test_half_life_halves_14_days_after_grace_ends():
    p = CellPower("u", 8.0, 0)
    assert faded_power(p, 21 * DAY, CFG) == pytest.approx(4.0)
    assert faded_power(p, 35 * DAY, CFG) == pytest.approx(2.0)


def test_custom_config_used():
    cfg = Config(grace_days=1, halflife_days=2)
    assert faded_power(CellPower("u", 8.0, 0), 3 * DAY, cfg) == pytest.approx(4.0)


@pytest.mark.parametrize(
    "freeze_until,expected",
    [
        (None, 2.5),               # no freeze: fades
        (NOW + DAY, 10.0),         # active freeze: no fading
        (NOW + 30 * DAY, 10.0),
        (NOW, 2.5),                # freeze ends exactly now: not in the future
        (NOW - DAY, 2.5),          # expired freeze has no effect
    ],
)
def test_freeze_stops_fading(freeze_until, expected):
    p = CellPower("u", 10.0, NOW - 35 * DAY)  # 28 days past grace -> 2 half-lives
    assert faded_power(p, NOW, CFG, freeze_until) == pytest.approx(expected)


def test_faded_power_does_not_mutate():
    p = CellPower("u", 10.0, 0)
    faded_power(p, 100 * DAY, CFG)
    assert (p.power, p.updated_at) == (10.0, 0)


# ---- apply_claim ----------------------------------------------------------

CASES = [
    # id, existing powers, owner, claimant, credit, freezes, expected owner, changed?
    ("first claim takes empty cell", [], None, "a", 1.0, None, "a", True),
    ("zero credit on empty cell stays unowned", [], None, "a", 0.0, None, None, False),
    ("tie keeps owner", [P("o", 5.0, 0)], "o", "c", 5.0, None, "o", False),
    ("challenger just below", [P("o", 5.0, 0)], "o", "c", 4.9999, None, "o", False),
    ("challenger just above", [P("o", 5.0, 0)], "o", "c", 5.0001, None, "c", True),
    ("owner adds to own cell", [P("o", 5.0, 0)], "o", "o", 3.0, None, "o", False),
    ("inside grace no fading: 6 days", [P("o", 10.0, 6)], "o", "c", 9.99, None, "o", False),
    ("inside grace: just above wins", [P("o", 10.0, 6)], "o", "c", 10.01, None, "c", True),
    ("after half-life owner has 5: 4.99 loses", [P("o", 10.0, 21)], "o", "c", 4.99, None, "o", False),
    ("after half-life owner has 5: 5.01 wins", [P("o", 10.0, 21)], "o", "c", 5.01, None, "c", True),
    ("freeze protects owner", [P("o", 10.0, 21)], "o", "c", 6.0, {"o": NOW + DAY}, "o", False),
    ("expired freeze does not protect", [P("o", 10.0, 21)], "o", "c", 6.0, {"o": NOW - 1}, "c", True),
    ("challenger own fading counts", [P("o", 5.0, 0), P("c", 8.0, 21)], "o", "c", 0.5, None, "o", False),
    ("challenger old power plus credit wins", [P("o", 5.0, 0), P("c", 8.0, 21)], "o", "c", 1.1, None, "c", True),
    ("missing owner entry treated as zero", [], "ghost", "c", 0.1, None, "c", True),
]


@pytest.mark.parametrize(
    "powers,owner,user,credit,freezes,expected_owner,changed",
    [c[1:] for c in CASES],
    ids=[c[0] for c in CASES],
)
def test_apply_claim_table(powers, owner, user, credit, freezes, expected_owner, changed):
    pw = {p.user_id: p for p in powers}
    new, change = apply_claim(CELL, pw, owner, user, credit, NOW, CFG, freezes)
    if changed:
        assert change == CellChange(CELL, owner, expected_owner)
    else:
        assert change is None
    if change is None:
        assert expected_owner == owner


def test_claimant_power_is_faded_plus_credit_and_timestamp_now():
    pw = {"c": P("c", 8.0, 21)}  # faded to 4.0
    new, _ = apply_claim(CELL, pw, None, "c", 2.0, NOW, CFG)
    assert new["c"].power == pytest.approx(6.0) and new["c"].updated_at == NOW


def test_other_users_stored_power_untouched():
    pw = {"o": P("o", 10.0, 21), "c": P("c", 1.0, 0)}
    new, _ = apply_claim(CELL, pw, "o", "c", 1.0, NOW, CFG)
    assert new["o"] == pw["o"]  # fading is lazy, nothing is rewritten


def test_inputs_not_mutated():
    pw = {"o": P("o", 5.0, 0)}
    snap = {k: (v.power, v.updated_at) for k, v in pw.items()}
    new, _ = apply_claim(CELL, pw, "o", "c", 9.0, NOW, CFG)
    assert {k: (v.power, v.updated_at) for k, v in pw.items()} == snap
    assert new is not pw and new["o"] is not pw["o"] and "c" not in pw


def test_non_claimant_with_more_faded_power_takes_over():
    # owner has faded below another user's power; any claim re-evaluates the cell
    pw = {"o": P("o", 10.0, 35), "x": P("x", 4.0, 0)}  # o faded to 2.5
    new, change = apply_claim(CELL, pw, "o", "c", 1.0, NOW, CFG)
    assert change == CellChange(CELL, "o", "x")


def test_negative_credit_rejected():
    with pytest.raises(ValueError):
        apply_claim(CELL, {}, None, "a", -1.0, NOW, CFG)


# ---- effort credit --------------------------------------------------------

@pytest.mark.parametrize(
    "moving_seconds,n_cells,expected",
    [
        (1800, 10, 3.0),
        (1800, 1, 30.0),
        (0, 10, 0.0),
        (5400, 10, 9.0),       # exactly the cap
        (12000, 10, 9.0),      # 200 minutes capped at 90
        (12000, 3, 30.0),
        (1800, 0, 0.0),
    ],
)
def test_effort_credit_table(moving_seconds, n_cells, expected):
    assert effort_credit(moving_seconds, n_cells, CFG) == pytest.approx(expected)


def test_effort_cap_follows_config():
    assert effort_credit(12000, 10, Config(effort_cap_minutes=30)) == pytest.approx(3.0)


def test_credit_is_split_across_cells_total_constant():
    for n in (1, 4, 11):
        assert effort_credit(1800, n, CFG) * n == pytest.approx(30.0)


def test_credit_split_across_cells_in_claims():
    cells = [f"c{i}" for i in range(5)]
    credit = effort_credit(3000, len(cells), CFG)  # 50 min / 5
    total = 0.0
    for c in cells:
        new, change = apply_claim(c, {}, None, "u", credit, NOW, CFG)
        total += new["u"].power
        assert change.new_owner == "u"
    assert total == pytest.approx(50.0)
