"""Phase 1a area 7: notifications inbox (spec section 7)."""

from __future__ import annotations

import asyncio
import json

import h3

from app import processing
from app.notifications import cells_taken_id, notify_cells_taken

from .conftest import T0, login, run_loop, square_fixes
from .phase1a import K1, count, delete, find, follow, get, ins, post, put, res_of, seed_event, seed_run, uid, upd
from .test_hardening import seed_run as seed_pipeline_run

RING = sorted(h3.grid_disk(h3.latlng_to_cell(50.0, 8.7, 10), 1))


def inbox(c, h, **kw):
    r = get(c, h, "/notifications", **kw)
    assert r.status_code == 200, r.text
    return r.json()


def note(c, user, nid, ntype, actor, visible_at, **extra):
    doc = {
        "_id": nid, "user_id": uid(user), "type": ntype, "actor_id": uid(actor) if actor else None, "run_id": None,
        "comment_id": None, "comment_preview": None, "created_at": 1, "visible_at": visible_at, "read": False,
    }  # fmt: skip
    doc.update(extra)
    ins(c, "notifications", doc)


def block(c, a, b):
    ins(c, "blocks", {"_id": f"{uid(a)}:{uid(b)}", "blocker_id": uid(a), "blocked_id": uid(b), "at": 1})


def test_each_type_appears_only_after_visible_at_and_unread_count_ignores_the_future(make_app, clock):
    c = make_app(publish_delay_seconds=1800, **K1)
    a, b = login(c, "alice"), login(c, "bob")
    rid = seed_run(c, a, at=clock.now - 1_800_000)  # alice's run, published
    follow(c, b, a)  # new_follower for alice
    put(c, b, f"/runs/{rid}/kudos")  # kudos for alice
    post(c, b, f"/runs/{rid}/comments", {"text": "go go go"})  # comment for alice
    other = seed_run(c, b, at=clock.now - 1_800_000)
    seed_event(c, other, RING[0], b, a, at=clock.now)  # bob took a cell from alice
    asyncio.run(notify_cells_taken(res_of(c), other, uid(b)))
    assert inbox(c, a)["items"] == [] and inbox(c, a)["unread_count"] == 0
    assert get(c, a, "/notifications/unread-count").json() == {"unread_count": 0}
    clock.advance(seconds=1799)
    assert inbox(c, a)["items"] == []
    clock.advance(seconds=1)
    page = inbox(c, a)
    assert {i["type"] for i in page["items"]} == {"new_follower", "kudos", "comment", "cells_taken"}
    assert page["unread_count"] == 4 and get(c, a, "/notifications/unread-count").json() == {"unread_count": 4}
    assert all(i["created_at"] == clock.now - 0 for i in page["items"])  # created_at is visible_at
    by = {i["type"]: i for i in page["items"]}
    assert by["new_follower"]["actor"] == {"id": uid(b), "name": "bob"} and by["new_follower"]["read"] is False
    assert by["kudos"]["run_id"] == rid and by["comment"]["comment_preview"] == "go go go"
    assert by["comment"]["comment_id"] and by["comment"]["run_id"] == rid
    assert set(by["kudos"]) == {"id", "type", "created_at", "read", "actor", "cells", "cells_unattributed"} | {
        "run_id", "comment_id", "comment_preview",
    }  # fmt: skip


def test_cells_taken_is_one_notification_per_run_and_victim_and_survives_reprocessing(make_app, clock):
    c = make_app(publish_delay_seconds=1800, **K1)
    a, b = login(c, "alice"), login(c, "bob")
    run_loop(c, a, speed=3.0)
    st = run_loop(c, b, speed=1.5)
    n = st["cells_taken_from_others"]
    assert n > 3
    notes = find(c, "notifications", {"type": "cells_taken"})
    assert len(notes) == 1 and notes[0]["user_id"] == uid(a) and notes[0]["visible_at"] == clock.now + 1_800_000
    clock.advance(seconds=1800)
    item = inbox(c, a)["items"][0]
    assert item["type"] == "cells_taken" and item["actor"] == {"id": uid(b), "name": "bob"}
    assert (item["cells"], item["cells_unattributed"], item["run_id"]) == (n, 0, None)
    run_b = find(c, "runs", {"user_id": uid(b)})[0]["_id"]
    assert run_b not in json.dumps(inbox(c, a))  # the taker's run id is never sent (not even inside the id)
    assert item["id"] == cells_taken_id(res_of(c), run_b, uid(a))
    assert put(c, a, "/me/home-zones", json={"zones": []}).status_code == 204
    c.post("/v1/notifications/read", json={"ids": [item["id"]]}, headers={"Authorization": a["Authorization"]})
    asyncio.run(notify_cells_taken(res_of(c), run_b, uid(b)))  # a redelivery
    asyncio.run(notify_cells_taken(res_of(c), run_b, uid(b)))
    again = find(c, "notifications", {"type": "cells_taken"})
    assert len(again) == 1 and again[0]["read"] is True  # no duplicate, `read` not reset
    assert inbox(c, a)["unread_count"] == 0


def test_cells_taken_survives_a_worker_crash_and_redelivery(make_app, monkeypatch):
    c = make_app(**K1)
    a, b = login(c, "alice"), login(c, "bob")
    run_loop(c, a, speed=3.0)
    res = res_of(c)
    rid = seed_pipeline_run(res, uid(b), square_fixes(speed=1.5))
    real = processing._apply
    calls = {"n": 0}

    async def flaky(db, user_id, o):
        calls["n"] += 1
        if calls["n"] == 4:
            raise ConnectionError("killed")
        await real(db, user_id, o)

    monkeypatch.setattr(processing, "_apply", flaky)
    try:
        asyncio.run(processing.process_run_by_id(res, rid, final=False))
    except ConnectionError:
        pass
    assert count(c, "notifications", {"type": "cells_taken"}) == 0  # not written before the apply loop is done
    monkeypatch.setattr(processing, "_apply", real)
    asyncio.run(processing.process_run_by_id(res, rid, final=True))
    asyncio.run(processing.process_run_by_id(res, rid, final=True))
    assert count(c, "notifications", {"type": "cells_taken"}) == 1
    assert inbox(c, a)["items"][0]["cells"] == find(c, "runs", {"_id": rid})[0]["cells_taken_from_others"]


def test_cells_taken_splits_named_and_unattributed_and_nulls_the_actor_when_all_hidden(make_app, clock):
    c = make_app(**K1)
    a, b, d = login(c, "alice"), login(c, "bob"), login(c, "dora")
    r1, r2 = seed_run(c, b, at=T0 - 5000), seed_run(c, d, at=T0 - 5000)
    for i, cell in enumerate(RING[:5]):
        seed_event(c, r1, cell, b, a, at=T0 - 5000, k_ok=i < 3)  # 3 nameable, 2 K-hidden
    seed_event(c, r2, RING[5], d, a, at=T0 - 5000, k_ok=False)  # dora: everything hidden
    for rid, taker in ((r1, b), (r2, d)):
        asyncio.run(notify_cells_taken(res_of(c), rid, uid(taker)))
    items = {i["actor"]["name"] if i["actor"] else None: i for i in inbox(c, a)["items"]}
    assert (items["bob"]["cells"], items["bob"]["cells_unattributed"]) == (3, 2)
    assert (items[None]["cells"], items[None]["cells_unattributed"]) == (0, 1) and items[None]["actor"] is None
    upd(c, "users", {"_id": uid(b)}, {"$set": {"name_hidden": True}})  # now bob is hidden entirely
    assert {i["actor"] for i in inbox(c, a)["items"]} == {None}
    assert sorted(i["cells_unattributed"] for i in inbox(c, a)["items"]) == [1, 5]


def test_kudos_and_comment_notifications_go_away_with_their_cause(client):
    a, b = login(client, "alice"), login(client, "bob")
    follow(client, b, a)
    rid = seed_run(client, a, at=T0 - 1)
    put(client, b, f"/runs/{rid}/kudos")
    cid = post(client, b, f"/runs/{rid}/comments", {"text": "hi"}).json()["id"]
    assert {i["type"] for i in inbox(client, a)["items"]} == {"new_follower", "kudos", "comment"}
    delete(client, b, f"/runs/{rid}/kudos")
    delete(client, a, f"/runs/{rid}/comments/{cid}")
    assert [i["type"] for i in inbox(client, a)["items"]] == ["new_follower"]
    delete(client, b, f"/users/{uid(a)}/follow")
    follow(client, b, a)
    assert [i["type"] for i in inbox(client, a)["items"]] == ["new_follower"]  # follow, unfollow, follow: still one


def test_mark_read_own_foreign_all_and_the_422s(client):
    a, b = login(client, "alice"), login(client, "bob")
    for i in range(3):
        note(client, a, f"n{i}", "new_follower", b, T0 - i)
    note(client, b, "bobs", "new_follower", a, T0)
    mark = lambda h, body: client.post("/v1/notifications/read", json=body, headers={"Authorization": h["Authorization"]})  # noqa: E731,E501
    assert inbox(client, a)["unread_count"] == 3
    assert mark(a, {"ids": ["n0", "bobs"]}).status_code == 204  # the foreign id is silently ignored
    assert inbox(client, a)["unread_count"] == 2
    assert inbox(client, b)["unread_count"] == 1  # bob's was not touched
    assert [i["read"] for i in inbox(client, a)["items"]] == [True, False, False]
    for bad in ({}, {"ids": []}, {"all": False}, {"ids": ["n1"], "all": True}, {"ids": [str(i) for i in range(101)]}):
        r = mark(a, bad)
        assert r.status_code == 422, bad
    assert mark(a, {"all": True}).status_code == 204
    assert inbox(client, a)["unread_count"] == 0 and all(i["read"] for i in inbox(client, a)["items"])
    assert client.post("/v1/notifications/read", json={"all": True}).status_code == 401


def test_all_does_not_touch_notifications_that_are_not_visible_yet(make_app, clock):
    c = make_app()
    a, b = login(c, "alice"), login(c, "bob")
    note(c, a, "now", "new_follower", b, T0)
    note(c, a, "later", "new_follower", b, T0 + 60_000)
    c.post("/v1/notifications/read", json={"all": True}, headers={"Authorization": a["Authorization"]})
    assert {n["_id"]: n["read"] for n in find(c, "notifications")} == {"now": True, "later": False}
    clock.advance(seconds=61)
    assert inbox(c, a)["unread_count"] == 1


def test_blocked_and_deleted_actors_are_filtered_at_read(client):
    a, b, d, e = (login(client, n) for n in ("alice", "bob", "dora", "eve"))
    for i, who in enumerate((b, d, e)):
        note(client, a, f"n{i}", "new_follower", who, T0 - i)
    block(client, a, b)
    upd(client, "users", {"_id": uid(d)}, {"$set": {"deleting": True}})
    page = inbox(client, a)
    assert [i["actor"]["name"] for i in page["items"]] == ["eve"] and page["unread_count"] == 1
    assert get(client, a, "/notifications/unread-count").json() == {"unread_count": 1}


def test_pagination_is_stable_across_visible_at_ties(client):
    a, b = login(client, "alice"), login(client, "bob")
    for i in range(7):
        note(client, a, f"n{i}", "new_follower", b, T0 - (i // 3))  # ties: 3 + 3 + 1
    seen, cursor = [], None
    for _ in range(4):
        p = inbox(client, a, limit=2, **({"cursor": cursor} if cursor else {}))
        seen += [i["id"] for i in p["items"]]
        cursor = p["next_cursor"]
        if not cursor:
            break
    assert sorted(seen) == [f"n{i}" for i in range(7)] and len(set(seen)) == 7
    assert seen == ["n2", "n1", "n0", "n5", "n4", "n3", "n6"]  # (visible_at, _id) descending
    assert get(client, a, "/notifications", cursor="zz").status_code == 422


def test_the_notifications_ttl_index_exists_and_rows_carry_expire_at(client):
    a, b = login(client, "alice"), login(client, "bob")
    follow(client, b, a)
    row = find(client, "notifications")[0]
    assert row["expire_at"].year >= 2027 and row["read"] is False
    from .conftest import db_run

    info = db_run(client, lambda db: db.notifications.index_information())
    assert any(v.get("expireAfterSeconds") == 0 and v["key"] == [("expire_at", 1)] for v in info.values())
