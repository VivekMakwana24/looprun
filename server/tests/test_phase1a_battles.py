"""Phase 1a area 6: battles summary, rivalry and take-back (spec section 6)."""

from __future__ import annotations

import h3

from app import engine_adapter as eng

from .conftest import DAY, T0, db_run, login, run_loop
from .phase1a import K1, count, find, get, ins, seed_event, uid, upd

RING = sorted(h3.grid_disk(h3.latlng_to_cell(50.0, 8.7, 10), 1))
PENTAGON = sorted(h3.get_pentagons(10))[0]


def block(c, a, b):
    ins(c, "blocks", {"_id": f"{uid(a)}:{uid(b)}", "blocker_id": uid(a), "blocked_id": uid(b), "at": 1})


def own_cell(c, cell, owner):
    ins(c, "cells", {"_id": cell, "owner_id": uid(owner) if owner else None})


def walk(obj):
    if isinstance(obj, dict):
        for k, v in obj.items():
            yield k
            yield from walk(v)
    elif isinstance(obj, list):
        for v in obj:
            yield from walk(v)


# ---------------------------------------------------------------- summary
def test_a_takeover_shows_in_both_summaries_only_after_the_delay(make_app, clock):
    c = make_app(publish_delay_seconds=1800, **K1)
    a, b = login(c, "alice"), login(c, "bob")
    run_loop(c, a, speed=3.0)
    st = run_loop(c, b, speed=1.5)
    n = st["cells_taken_from_others"]
    assert n > 3
    for h in (a, b):
        s = get(c, h, "/battles/summary").json()
        assert (s["taken"], s["lost"], s["net"], s["battles"]) == (0, 0, 0, 0)  # before the map shows it
    clock.advance(seconds=1800)
    sa, sb = (get(c, h, "/battles/summary").json() for h in (a, b))
    assert (sa["taken"], sa["lost"], sa["net"], sa["battles"], sa["days"]) == (0, n, -n, 1, 7)
    assert (sb["taken"], sb["lost"], sb["net"], sb["battles"]) == (n, 0, n, 1)


def test_summary_window_is_exactly_seven_days_and_counts_hidden_opponents(client):
    a, b, d = login(client, "alice"), login(client, "bob"), login(client, "dora")
    seed_event(client, "r1", "x1", a, b, at=T0 - 7 * DAY + 1000)  # 7 days - 1 s: in
    seed_event(client, "r2", "x2", a, b, at=T0 - 7 * DAY - 1000)  # 7 days + 1 s: out
    seed_event(client, "r3", "x3", d, a, at=T0 - DAY, k_ok=False)  # hidden opponent still counts
    seed_event(client, "r3", "x4", d, a, at=T0 - DAY)  # same run: one battle
    seed_event(client, "r4", "x5", a, None, at=T0 - DAY)  # deleted victim: the taker's count survives
    s = get(client, a, "/battles/summary").json()
    assert (s["taken"], s["lost"], s["net"], s["battles"]) == (2, 2, 0, 3)


# ---------------------------------------------------------------- rivalry
def test_rivalry_totals_sorting_unattributed_and_window(client):
    a, b, d, e = (login(client, n) for n in ("alice", "bob", "dora", "eve"))
    seed_event(client, "r1", "x1", a, b, at=T0 - 5 * DAY)
    seed_event(client, "r1", "x2", a, b, at=T0 - 4 * DAY)
    seed_event(client, "r2", "x3", b, a, at=T0 - 3 * DAY)
    seed_event(client, "r3", "x4", d, a, at=T0 - DAY)
    seed_event(client, "r3", "x5", d, a, at=T0 - DAY)
    seed_event(client, "r3", "x6", d, a, at=T0 - DAY)
    seed_event(client, "r4", "x7", a, e, at=T0 - 20 * DAY)
    seed_event(client, "r5", "x8", a, e, at=T0 - 40 * DAY)  # outside 30 days
    seed_event(client, "r6", "x9", a, e, at=T0 - 2 * DAY, k_ok=False)  # unattributed
    seed_event(client, "r7", "y1", e, a, at=T0 - 2 * DAY, k_ok=False)
    r = get(client, a, "/battles/rivalry").json()
    assert r["days"] == 30 and r["unattributed"] == {"taken": 1, "lost": 1}
    rows = {x["user"]["name"]: x for x in r["rivals"]}
    assert [x["user"]["name"] for x in r["rivals"]] == ["dora", "bob", "eve"]  # taken+lost: dora 3, bob 3 (more recent), eve 1
    assert (rows["bob"]["taken"], rows["bob"]["lost"], rows["bob"]["net"]) == (2, 1, 1)
    assert (rows["dora"]["taken"], rows["dora"]["lost"], rows["dora"]["net"]) == (0, 3, -3)
    assert rows["bob"]["last_battle_at"] == T0 - 3 * DAY and rows["dora"]["last_battle_at"] == T0 - DAY
    assert (rows["eve"]["taken"], rows["eve"]["lost"]) == (1, 0) and rows["eve"]["last_battle_at"] == T0 - 20 * DAY
    assert set(rows["bob"]) == {"user", "taken", "lost", "net", "last_battle_at", "is_following"}
    wide = get(client, a, "/battles/rivalry", days=90).json()
    assert {x["user"]["name"]: x["taken"] for x in wide["rivals"]}["eve"] == 2
    short = get(client, a, "/battles/rivalry", days=2).json()
    assert [x["user"]["name"] for x in short["rivals"]] == ["dora"]


def test_rivalry_ties_sort_by_most_recent_battle_and_flags_follows(client):
    a, b, d = login(client, "alice"), login(client, "bob"), login(client, "dora")
    seed_event(client, "r1", "x1", a, b, at=T0 - 5 * DAY)
    seed_event(client, "r2", "x2", a, d, at=T0 - 2 * DAY)
    client.put(f"/v1/users/{uid(d)}/follow", headers={"Authorization": a["Authorization"]})
    rows = get(client, a, "/battles/rivalry").json()["rivals"]
    assert [(x["user"]["name"], x["is_following"]) for x in rows] == [("dora", True), ("bob", False)]


def test_rivalry_days_must_be_1_to_90_and_old_events_are_never_returned(client):
    a, b = login(client, "alice"), login(client, "bob")
    for days in (0, 91, -1):
        assert get(client, a, "/battles/rivalry", days=days).status_code == 422
    seed_event(client, "r1", "x1", a, b, at=T0 - 91 * DAY)  # past the 90-day retention: TTL monitor not run yet
    seed_event(client, "r2", "x2", a, b, at=T0 - 89 * DAY)
    got = get(client, a, "/battles/rivalry", days=90).json()["rivals"]
    assert [(x["user"]["name"], x["taken"]) for x in got] == [("bob", 1)]


def test_events_older_than_retention_are_gone_from_every_battle_view(client):
    a, b = login(client, "alice"), login(client, "bob")
    seed_event(client, "r1", "x1", b, a, at=T0 - 91 * DAY)
    own_cell(client, "x1", b)
    assert get(client, a, "/battles/summary").json()["lost"] == 0
    assert get(client, a, "/battles/take-back").json()["cells"] == []


def test_the_battle_events_ttl_index_exists(client):
    info = db_run(client, lambda db: db.battle_events.index_information())
    ttl = [v for v in info.values() if "expireAfterSeconds" in v]
    assert ttl and ttl[0]["key"] == [("expire_at", 1)] and ttl[0]["expireAfterSeconds"] == 0


# ---------------------------------------------------------------- take-back
def test_take_back_lists_lost_cells_once_with_the_engine_geometry_and_no_ids(client):
    a, b, d = login(client, "alice"), login(client, "bob"), login(client, "dora")
    c0, c1, c2, c3 = RING[0], RING[1], RING[2], PENTAGON
    seed_event(client, "r1", c0, b, a, at=T0 - 3 * DAY)  # lost twice: appears once, latest loss
    seed_event(client, "r2", c0, d, a, at=T0 - DAY)
    seed_event(client, "r3", c1, b, a, at=T0 - 2 * DAY)  # won back since: absent
    seed_event(client, "r4", c2, b, a, at=T0 - 4 * DAY)  # cell no longer exists (freed): listed
    seed_event(client, "r5", c3, b, a, at=T0 - 5 * DAY)
    own_cell(client, c0, d)
    own_cell(client, c1, a)
    own_cell(client, c3, b)
    got = get(client, a, "/battles/take-back").json()["cells"]
    assert [x["cell"] for x in got] == [c0, c2, c3]  # newest loss first
    first = got[0]
    assert first["lost_at"] == T0 - DAY and first["lost_to"] == {"id": uid(d), "name": "dora"}
    assert (first["lat"], first["lng"]) == tuple(eng.cell_centre(c0)) and len(first["boundary"]) == 6
    assert first["boundary"] == eng.cell_boundary(c0) and len(got[2]["boundary"]) == 5  # the pentagon
    assert set(first) == {"cell", "lat", "lng", "boundary", "lost_at", "lost_to"}
    assert not {"run_id", "taker_id", "victim_id"} & set(walk(got))
    assert get(client, b, "/battles/take-back").json()["cells"] == []  # nobody lost anything but alice


def test_take_back_window_is_seven_days_to_the_second(client):
    a, b = login(client, "alice"), login(client, "bob")
    seed_event(client, "r1", RING[0], b, a, at=T0 - 7 * DAY + 1000)
    seed_event(client, "r2", RING[1], b, a, at=T0 - 7 * DAY - 1000)
    own_cell(client, RING[0], b)
    own_cell(client, RING[1], b)
    assert [x["cell"] for x in get(client, a, "/battles/take-back").json()["cells"]] == [RING[0]]


def test_take_back_names_the_taker_only_when_the_map_would(make_app):
    c = make_app(**K1)
    a, ok, kh, hz, gone, hid, bl = (login(c, n) for n in ("alice", "ok", "kh", "hz", "gone", "hid", "bl"))
    seed_event(c, "r1", RING[0], ok, a, at=T0 - 1000)
    seed_event(c, "r2", RING[1], kh, a, at=T0 - 2000, k_ok=False)
    seed_event(c, "r3", RING[2], hz, a, at=T0 - 3000)
    seed_event(c, "r4", RING[3], gone, a, at=T0 - 4000)
    seed_event(c, "r5", RING[4], hid, a, at=T0 - 5000)
    seed_event(c, "r6", RING[5], bl, a, at=T0 - 6000)
    seed_event(c, "r7", RING[6], None, a, at=T0 - 7000)
    seed_event(c, "r8", PENTAGON, "e" * 32, a, at=T0 - 8000)  # taker account no longer exists
    for cell in (*RING, PENTAGON):
        own_cell(c, cell, ok)
    zone = {"lat": eng.cell_centre(RING[2])[0], "lng": eng.cell_centre(RING[2])[1], "radius_m": 100}
    upd(c, "users", {"_id": uid(hz)}, {"$set": {"home_zones": [zone]}})
    upd(c, "users", {"_id": uid(gone)}, {"$set": {"deleting": True}})
    upd(c, "users", {"_id": uid(hid)}, {"$set": {"name_hidden": True}})
    block(c, a, bl)
    got = get(c, a, "/battles/take-back").json()["cells"]
    assert len(got) == 8  # the cells stay listed: they were the caller's own
    named = {x["cell"]: x["lost_to"] for x in got}
    assert named[RING[0]] == {"id": uid(ok), "name": "ok"}
    assert all(named[x] is None for x in (*RING[1:], PENTAGON))


def test_taker_home_zone_set_later_hides_the_name_on_the_next_read(client):
    a, b = login(client, "alice"), login(client, "bob")
    seed_event(client, "r1", RING[0], b, a, at=T0 - 1000)
    own_cell(client, RING[0], b)
    assert get(client, a, "/battles/take-back").json()["cells"][0]["lost_to"]["name"] == "bob"
    lat, lng = eng.cell_centre(RING[0])
    upd(client, "users", {"_id": uid(b)}, {"$set": {"home_zones": [{"lat": lat, "lng": lng, "radius_m": 100}]}})
    assert get(client, a, "/battles/take-back").json()["cells"][0]["lost_to"] is None
    assert get(client, a, "/battles/rivalry").json()["unattributed"] == {"taken": 0, "lost": 1}


def test_take_back_is_capped_at_500_cells(client):
    a, b = login(client, "alice"), login(client, "bob")
    cells = sorted(h3.grid_disk(h3.latlng_to_cell(50.0, 8.7, 10), 14))[:620]
    docs = [
        {
            "_id": f"r{i}:{cell}", "run_id": f"r{i}", "cell": cell, "at": T0 - 1000 - i, "taker_id": uid(b),
            "victim_id": uid(a), "k_ok": True,
        }
        for i, cell in enumerate(cells)
    ]  # fmt: skip
    db_run(client, lambda db: db.battle_events.insert_many(docs))
    got = get(client, a, "/battles/take-back").json()["cells"]
    assert len(got) == 500 and got[0]["lost_at"] > got[-1]["lost_at"]
    assert count(client, "battle_events") == 620 and len(find(client, "cells")) == 0
