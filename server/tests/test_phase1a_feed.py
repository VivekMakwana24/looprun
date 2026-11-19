"""Phase 1a area 4: activity feed and run history (spec sections 3 and 5)."""

from __future__ import annotations

import base64
import json

import h3

from .conftest import DAY, T0, db_run, login
from .phase1a import K1, count, find, follow, get, ins, put, res_of, seed_event, seed_run, uid, upd

FORBIDDEN = {
    "fixes", "lat", "lng", "polygon", "boundary", "cells", "claimed_cells", "flags", "ended_at",
    "integrity_token", "start", "end",
}  # fmt: skip
CELL = h3.latlng_to_cell(50.0, 8.7, 10)
RING = sorted(h3.grid_disk(CELL, 1))  # 7 cells around (50.0, 8.7)


def keys_of(obj, path=""):
    if isinstance(obj, dict):
        for k, v in obj.items():
            yield path + "/" + k, k, v
            yield from keys_of(v, path + "/" + k)
    elif isinstance(obj, list):
        for v in obj:
            yield from keys_of(v, path)


def block(c, a, b):
    ins(c, "blocks", {"_id": f"{uid(a)}:{uid(b)}", "blocker_id": uid(a), "blocked_id": uid(b), "at": 1})


def ids(resp):
    return [i["id"] for i in resp.json()["items"]]


def feed(c, h, **kw):
    r = get(c, h, "/feed", **kw)
    assert r.status_code == 200, r.text
    return r


# ---------------------------------------------------------------- visibility
def test_feed_shows_own_runs_at_once_and_followees_after_the_delay(make_app, clock):
    c = make_app(publish_delay_seconds=1800, **K1)
    a, b = login(c, "alice"), login(c, "bob")
    follow(c, a, b)
    mine, theirs = seed_run(c, a, at=clock.now), seed_run(c, b, at=clock.now)
    assert ids(feed(c, a)) == [mine]  # own at once, bob's not yet
    clock.advance(seconds=1799, ms=999)  # processed_at + delay - 1 ms
    assert ids(feed(c, a)) == [mine]
    clock.advance(ms=1)  # + delay
    assert set(ids(feed(c, a))) == {mine, theirs}
    assert ids(feed(c, b)) == [theirs]  # bob does not follow alice


def test_follow_unfollow_and_the_90_day_window(client, clock):
    a, b, d = login(client, "alice"), login(client, "bob"), login(client, "dora")
    old = seed_run(client, b, at=T0 - 89 * DAY)
    too_old = seed_run(client, b, at=T0 - 91 * DAY)
    other = seed_run(client, d, at=T0 - DAY)
    assert ids(feed(client, a)) == []  # not followed: absent
    follow(client, a, b)
    assert ids(feed(client, a)) == [old]  # older accepted runs appear on follow, beyond the window do not
    assert other not in ids(feed(client, a)) and too_old not in ids(feed(client, a))
    assert client.delete(f"/v1/users/{uid(b)}/follow", headers={"Authorization": a["Authorization"]}).status_code == 200
    assert ids(feed(client, a)) == []


def test_only_accepted_unhidden_new_runs_are_shown_to_others(client):
    a, b = login(client, "alice"), login(client, "bob")
    follow(client, a, b)
    ok = seed_run(client, b, at=T0 - 5)
    for st in ("pending_review", "rejected", "processing"):
        seed_run(client, b, at=T0 - 6, status=st)
    seed_run(client, b, at=T0 - 7, hidden=True)
    legacy = seed_run(client, b, at=T0 - 8)
    upd(client, "runs", {"_id": legacy}, {"$unset": {"claimed_cells": ""}})
    assert ids(feed(client, a)) == [ok]
    own_legacy = seed_run(client, a, at=T0 - 9)
    upd(client, "runs", {"_id": own_legacy}, {"$unset": {"claimed_cells": ""}})
    assert own_legacy in ids(feed(client, a))  # the owner keeps legacy runs
    hidden_own = seed_run(client, a, at=T0 - 10, hidden=True)
    assert hidden_own not in ids(feed(client, a))  # moderation hides it from every feed


def test_block_either_way_and_a_deleting_owner_remove_the_card_at_once(client):
    a, b, d = login(client, "alice"), login(client, "bob"), login(client, "dora")
    follow(client, a, b)
    follow(client, a, d)
    rb, rd = seed_run(client, b, at=T0 - 5), seed_run(client, d, at=T0 - 6)
    assert set(ids(feed(client, a))) == {rb, rd}
    block(client, b, a)  # bob blocked alice (the follow row is still there: tests the read-time filter)
    upd(client, "users", {"_id": uid(d)}, {"$set": {"deleting": True}})
    assert ids(feed(client, a)) == []
    db_run(client, lambda db: db.blocks.delete_many({}))
    assert set(ids(feed(client, a))) == {rb}  # the block is gone: bob's card is back (dora is deleting)
    block(client, a, b)
    assert ids(feed(client, a)) == []  # and the other direction


# ---------------------------------------------------------------- content
def test_card_fields_and_never_present_keys(client):
    a, b = login(client, "alice"), login(client, "bob")
    follow(client, a, b)
    rid = seed_run(
        client, b, at=T0 - 5, claimed=("c1", "c2"), distance=5000.0, moving=1500,
        fixes=[[1, 2]], lat=1.0, lng=2.0, polygon=[[1, 2]], boundary=[[1, 2]], start=[1, 2], end=[3, 4],
        flags=[{"code": "x", "severity": "soft", "detail": "y"}], ended_at=5, integrity_token="t",
    )  # fmt: skip
    card = feed(client, a).json()["items"][0]
    assert set(card) == {
        "id", "user", "started_at", "distance_m", "moving_seconds", "pace_s_per_km", "cells_claimed", "cells_taken",
        "taken_from", "taken_from_hidden", "loop_count", "kudos_count", "kudos_by_me", "comment_count", "status",
    }  # fmt: skip
    assert card["id"] == rid and card["user"] == {"id": uid(b), "name": "bob"} and card["status"] == "accepted"
    assert card["pace_s_per_km"] == 1500 / 5.0 and card["loop_count"] == 1 and card["cells_claimed"] == 2
    for path, key, value in keys_of(feed(client, a).json()):
        assert key not in FORBIDDEN or (key == "cells" and isinstance(value, int)), path
    stored = json.dumps(find(client, "runs", {"_id": rid})[0])
    assert all(f'"{k}"' in stored for k in ("fixes", "polygon", "claimed_cells", "integrity_token"))  # all stored


def test_pace_is_null_under_100_m_and_exact_otherwise(client):
    a = login(client, "alice")
    short = seed_run(client, a, at=T0 - 1, distance=99.0, moving=60)
    long = seed_run(client, a, at=T0 - 2, distance=100.0, moving=36)
    cards = {c["id"]: c for c in feed(client, a).json()["items"]}
    assert cards[short]["pace_s_per_km"] is None and cards[long]["pace_s_per_km"] == 360.0


def test_home_zone_cells_are_not_counted_for_followers_but_are_for_the_owner(client):
    a, b = login(client, "alice"), login(client, "bob")
    follow(client, a, b)
    seed_run(client, b, at=T0 - 5, claimed=tuple(RING))
    zone = {"lat": 50.0, "lng": 8.7, "radius_m": 400}
    upd(client, "users", {"_id": uid(b)}, {"$set": {"home_zones": [zone]}})
    card = feed(client, a).json()["items"][0]
    assert card["cells_claimed"] == 0 and card["cells_taken"] == 0  # still shown (distance and time reveal no place)
    assert feed(client, b).json()["items"][0]["cells_claimed"] == 7  # the true number for the owner
    upd(client, "users", {"_id": uid(b)}, {"$set": {"home_zones": []}})
    assert feed(client, a).json()["items"][0]["cells_claimed"] == 7  # changing the zone changes the next read


def test_taken_from_names_only_who_the_map_would_name_and_the_sum_identity_holds(make_app, clock):
    c = make_app(publish_delay_seconds=1800, **K1)
    names = ("alice", "bob", "v1", "v2", "v3", "v4", "v5", "v6")
    a, b, v1, v2, v3, v4, v5, v6 = (login(c, n) for n in names)
    follow(c, a, b)
    cells = [f"x{i}" for i in range(9)]
    rid = seed_run(c, b, at=clock.now, claimed=tuple(cells), cells_taken=9)
    t = clock.now
    seed_event(c, rid, cells[0], b, v1, at=t)  # named
    seed_event(c, rid, cells[1], b, v1, at=t)  # named, second cell
    seed_event(c, rid, cells[2], b, v2, at=t, k_ok=False)  # K-anonymity failed
    seed_event(c, rid, cells[3], b, v3, at=t)  # v3: hidden name
    seed_event(c, rid, cells[4], b, v4, at=t)  # v4: deleting
    seed_event(c, rid, cells[5], b, v5, at=t)  # v5: blocked with alice
    seed_event(c, rid, cells[6], b, None, at=t)  # victim deleted
    seed_event(c, rid, CELL, b, v6, at=t)  # v6: cell inside v6's home zone
    upd(c, "users", {"_id": uid(v3)}, {"$set": {"name_hidden": True}})
    upd(c, "users", {"_id": uid(v4)}, {"$set": {"deleting": True}})
    upd(c, "users", {"_id": uid(v6)}, {"$set": {"home_zones": [{"lat": 50.0, "lng": 8.7, "radius_m": 100}]}})
    block(c, a, v5)
    clock.advance(seconds=1800)
    card = feed(c, a).json()["items"][0]
    assert card["taken_from"] == [{"user": {"id": uid(v1), "name": "v1"}, "cells": 2}]
    assert card["taken_from_hidden"] == 6 and card["cells_taken"] == 8
    assert card["cells_taken"] == sum(t["cells"] for t in card["taken_from"]) + card["taken_from_hidden"]
    own = feed(c, b).json()["items"][0]  # the runner learns names by the same rules (v5 is not blocked with bob)
    assert {t["user"]["name"]: t["cells"] for t in own["taken_from"]} == {"v1": 2, "v5": 1}
    assert own["cells_taken"] == 8 and own["cells_claimed"] == 9


def test_own_card_counts_battles_only_when_the_map_would_show_them(make_app, clock):
    c = make_app(publish_delay_seconds=1800, **K1)
    a, v = login(c, "alice"), login(c, "vic")
    rid = seed_run(c, a, at=clock.now, claimed=("c1", "c2", "c3"), cells_taken=2)
    seed_event(c, rid, "c1", a, v, at=clock.now)
    seed_event(c, rid, "c2", a, v, at=clock.now)
    card = feed(c, a).json()["items"][0]
    assert card["cells_claimed"] == 3 and card["cells_taken"] == 0 and card["taken_from"] == []  # inside the delay
    clock.advance(seconds=1800)
    card = feed(c, a).json()["items"][0]
    assert card["cells_taken"] == 2 and card["taken_from"] == [{"user": {"id": uid(v), "name": "vic"}, "cells": 2}]


def test_hidden_names_show_as_runner_xxxx_on_cards(client):
    a, b = login(client, "alice"), login(client, "bob")
    follow(client, a, b)
    seed_run(client, b, at=T0 - 5)
    upd(client, "users", {"_id": uid(b)}, {"$set": {"name_hidden": True}})
    assert feed(client, a).json()["items"][0]["user"]["name"] == "Runner-" + uid(b)[:4]
    assert feed(client, b).json()["items"][0]["user"]["name"] == "bob"


def test_kudos_and_comment_counts_exclude_blocked_hidden_and_gone_authors(client):
    a, b, d, e, f = (login(client, n) for n in ("alice", "bob", "dora", "eve", "finn"))
    follow(client, a, b)
    rid = seed_run(client, b, at=T0 - 5)
    for who in (d, e, f, a):
        kid = f"{rid}:{uid(who)}"
        ins(client, "kudos", {"_id": kid, "run_id": rid, "run_owner_id": uid(b), "user_id": uid(who), "at": 1})
    for i, who in enumerate((d, e, f, a)):
        ins(client, "comments", {"_id": f"cm{i}", "run_id": rid, "run_owner_id": uid(b), "author_id": uid(who),
                                 "text": "hi", "created_at": i, "hidden": False})  # fmt: skip
    block(client, a, e)  # alice blocked eve: eve's kudos and comment vanish for alice
    upd(client, "comments", {"_id": "cm0"}, {"$set": {"hidden": True}})  # dora's comment: hidden by moderation
    upd(client, "users", {"_id": uid(f)}, {"$set": {"deleting": True}})  # finn: gone (comment and kudos)
    card = feed(client, a).json()["items"][0]
    assert card["kudos_count"] == 2 and card["kudos_by_me"] is True  # dora, alice (finn is being deleted)
    assert card["comment_count"] == 1  # only alice's own
    other = feed(client, b).json()["items"][0]
    assert other["kudos_count"] == 3 and other["kudos_by_me"] is False and other["comment_count"] == 2


# ---------------------------------------------------------------- paging and cost
def test_pagination_55_runs_in_three_pages_with_a_new_run_arriving_between_pages(make_app, clock):
    c = make_app(**K1)
    a, b = login(c, "alice"), login(c, "bob")
    follow(c, a, b)
    made = [seed_run(c, b if i % 2 else a, at=T0 - (60 - i) * 1000) for i in range(55)]  # distinct, ascending
    p1 = feed(c, a, limit=20).json()
    new = seed_run(c, b, at=T0 - 1)  # arrives between page 1 and 2: sorts above the cursor
    p2 = feed(c, a, limit=20, cursor=p1["next_cursor"]).json()
    p3 = feed(c, a, limit=20, cursor=p2["next_cursor"]).json()
    assert p3["next_cursor"] is None and len(p1["items"]) == len(p2["items"]) == 20 and len(p3["items"]) == 15
    got = [i["id"] for p in (p1, p2, p3) for i in p["items"]]
    assert got == list(reversed(made)) and new not in got  # strictly descending, none twice, none skipped
    assert feed(c, a, limit=50).json()["items"][0]["id"] == new


def test_runs_with_the_same_processed_at_page_without_gaps(make_app):
    c = make_app(**K1)
    a = login(c, "alice")
    made = [seed_run(c, a, at=T0 - 5) for _ in range(7)]
    got, cursor = [], None
    while True:
        p = feed(c, a, limit=3, **({"cursor": cursor} if cursor else {})).json()
        got += [i["id"] for i in p["items"]]
        cursor = p["next_cursor"]
        if not cursor:
            break
    assert sorted(got) == sorted(made) and len(set(got)) == 7


class CountingDb:
    """Counts the Mongo operations a request makes (find, find_one, aggregate, count_documents ...)."""

    def __init__(self, db):
        self._db, self.ops = db, 0

    def __getattr__(self, name):
        coll = getattr(self._db, name)
        outer = self

        class Coll:
            def __getattr__(self, op):
                attr = getattr(coll, op)
                if op in {"find", "find_one", "aggregate", "count_documents", "distinct"}:

                    def counted(*a, **k):
                        outer.ops += 1
                        return attr(*a, **k)

                    return counted
                return attr

        return Coll()


def test_a_page_costs_the_same_number_of_queries_for_1_and_50_cards(make_app):
    c = make_app(**K1)
    a, b = login(c, "alice"), login(c, "bob")
    follow(c, a, b)
    victims = [login(c, f"v{i}") for i in range(5)]

    def seed(n):
        for i in range(n):
            rid = seed_run(c, b if i % 2 else a, at=T0 - i * 1000, claimed=(f"c{i}a", f"c{i}b"))
            seed_event(c, rid, f"c{i}a", b if i % 2 else a, victims[i % 5], at=T0 - 10_000_000)
            kid = f"{rid}:{uid(a)}"
            ins(c, "kudos", {"_id": kid, "run_id": rid, "run_owner_id": uid(b), "user_id": uid(a), "at": 1})

    def ops_for(limit):
        res = res_of(c)
        real = res.db
        res.db = CountingDb(real)
        try:
            n = len(feed(c, a, limit=limit).json()["items"])
            return n, res.db.ops
        finally:
            res.db = real

    seed(1)
    one = ops_for(50)
    seed(49)
    fifty = ops_for(50)
    assert one[0] == 1 and fifty[0] == 50
    assert one[1] == fifty[1], (one, fifty)


# ---------------------------------------------------------------- history (spec 5)
def runs(c, h, **kw):
    r = get(c, h, "/runs", **kw)
    assert r.status_code == 200, r.text
    return r.json()


def test_history_is_own_runs_only_in_started_at_order_with_paging(make_app):
    c = make_app(**K1)
    a, b = login(c, "alice"), login(c, "bob")
    mine = [seed_run(c, a, at=T0 - i * 10_000) for i in range(25)]
    other = seed_run(c, b, at=T0)
    got, cursor = [], None
    for _ in range(3):
        p = runs(c, a, limit=10, **({"cursor": cursor} if cursor else {}))
        got += [i["id"] for i in p["items"]]
        cursor = p["next_cursor"]
    assert cursor is None and got == mine and other not in got  # newest started_at first
    assert get(c, a, "/runs", limit=0).status_code == 422 and get(c, a, "/runs", cursor="zz").status_code == 422


def test_history_status_filter_and_cards_of_unfinished_runs(client):
    a = login(client, "alice")
    ok = seed_run(client, a, at=T0 - 1)
    held = seed_run(client, a, at=T0 - 2, status="pending_review", claimed=("c1",))
    busy = seed_run(client, a, at=T0 - 3, status="processing", distance=None, moving=None, claimed=())
    upd(client, "runs", {"_id": busy}, {"$unset": {"distance_m": "", "moving_seconds": "", "processed_at": ""}})
    all_ = {i["id"]: i for i in runs(client, a)["items"]}
    assert set(all_) == {ok, held, busy}
    assert all_[held]["status"] == "pending_review" and all_[held]["cells_claimed"] == 0
    assert all_[busy]["status"] == "processing" and all_[busy]["distance_m"] is None
    assert all_[busy]["moving_seconds"] is None and all_[busy]["pace_s_per_km"] is None
    assert [i["id"] for i in runs(client, a, status="pending_review")["items"]] == [held]
    assert [i["id"] for i in runs(client, a, status="accepted")["items"]] == [ok]
    assert get(client, a, "/runs", status="done").status_code == 422


def test_history_keeps_hidden_runs_and_legacy_numbers_for_the_owner(client):
    a = login(client, "alice")
    hid = seed_run(client, a, at=T0 - 1, hidden=True)
    legacy = seed_run(client, a, at=T0 - 2, claimed=("c1", "c2"), cells_taken=2)
    upd(client, "runs", {"_id": legacy}, {"$unset": {"claimed_cells": ""}})
    cards = {i["id"]: i for i in runs(client, a)["items"]}
    assert set(cards) == {hid, legacy}
    assert cards[legacy]["cells_claimed"] == 2 and cards[legacy]["cells_taken"] == 2
    assert cards[legacy]["taken_from"] == [] and cards[legacy]["taken_from_hidden"] == 2


def test_run_status_route_is_unchanged_and_end_to_end_cards_come_from_the_pipeline(make_app):
    from .conftest import run_loop

    c = make_app(**K1)
    a, b = login(c, "alice"), login(c, "bob")
    run_loop(c, a, speed=3.0)
    st = run_loop(c, b, speed=1.5)
    card = runs(c, b)["items"][0]
    assert card["cells_claimed"] == st["cells_claimed"] and card["cells_taken"] == st["cells_taken_from_others"] > 0
    assert card["taken_from"] == [{"user": {"id": uid(a), "name": "alice"}, "cells": card["cells_taken"]}]
    follow(c, a, b)
    assert card["id"] in ids(feed(c, a))
    assert count(c, "runs") == 2


def test_feed_requires_a_token_and_a_valid_cursor(client):
    assert client.get("/v1/feed").status_code == 401
    a = login(client, "alice")
    cursor = base64.urlsafe_b64encode(b'["x"]').decode()
    for bad in ("zz", cursor):
        r = get(client, a, "/feed", cursor=bad)
        assert r.status_code == 422 and r.json()["detail"]["code"] == "bad_cursor"
    assert put(client, a, "/me/home-zones", json={"zones": []}).status_code == 204
