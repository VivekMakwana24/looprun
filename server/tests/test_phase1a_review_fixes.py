"""Fixes from docs/verification/phase1a-review.md (B1, B2 and the server-side follow-ups)."""

from __future__ import annotations

import asyncio
import hashlib
import json

import h3

from app import processing
from app.notifications import cells_taken_id, notify_cells_taken

from .phase1a import K1, count, delete, find, follow, get, ins, patch, post, put, res_of, seed_event, seed_run, uid, upd

RING = sorted(h3.grid_disk(h3.latlng_to_cell(50.0, 8.7, 10), 1))
H = 3_600_000


def setup(c, clock):
    from .conftest import login

    a, b = login(c, "alice"), login(c, "bob")
    follow(c, a, b)
    rid = seed_run(c, b, at=clock.now - 2 * H)
    seed_event(c, rid, RING[0], b, a, at=clock.now - 2 * H, k_ok=False)
    asyncio.run(notify_cells_taken(res_of(c), rid, uid(b)))
    return a, b, rid


def inbox_bytes(c, h):
    r = get(c, h, "/notifications")
    u = get(c, h, "/notifications/unread-count")
    assert r.status_code == 200 and u.status_code == 200
    return r.content, u.content


# ------------------------------------------------------------------ B1
def test_b1_cells_taken_id_cannot_be_derived_from_a_run_id(make_app, clock):
    c = make_app(publish_delay_seconds=1800, **K1)
    a, b, rid = setup(c, clock)
    item = get(c, a, "/notifications").json()["items"][0]
    assert item["type"] == "cells_taken" and item["actor"] is None
    # the victim follows bob and reads his feed: every card id (a run id) must fail to hash to the notification id
    cards = get(c, a, "/feed").json()["items"]
    assert [x["id"] for x in cards] == [rid]
    for card in cards:
        for victim in (uid(a), ""):
            old = f"cells_taken:{hashlib.sha256(card['id'].encode()).hexdigest()[:32]}"
            assert item["id"] not in (old, f"{old}:{victim}")
        assert hashlib.sha256(card["id"].encode()).hexdigest()[:32] not in item["id"]
    assert rid not in item["id"] and uid(a) not in item["id"]


def test_b1_id_is_keyed_with_a_server_secret_and_still_deterministic(make_app, clock):
    one = make_app(publish_delay_seconds=1800, notification_id_secret="secret-one", **K1)
    r1 = res_of(one)
    other = make_app(publish_delay_seconds=1800, notification_id_secret="secret-two", **K1)
    r2 = res_of(other)
    assert cells_taken_id(r1, "run", "victim") == cells_taken_id(r1, "run", "victim")
    assert cells_taken_id(r1, "run", "victim") != cells_taken_id(r2, "run", "victim")
    assert cells_taken_id(r1, "run", "victim") != cells_taken_id(r1, "run", "other-victim")
    assert cells_taken_id(r1, "run", "victim") != cells_taken_id(r1, "run2", "victim")


# ------------------------------------------------------------------ B2
def test_b2_blocking_the_hidden_taker_changes_nothing_in_the_inbox(make_app, clock):
    c = make_app(publish_delay_seconds=1800, **K1)
    a, b, _ = setup(c, clock)
    before = inbox_bytes(c, a)
    assert json.loads(before[1]) == {"unread_count": 1}
    assert put(c, a, f"/users/{uid(b)}/block").status_code == 204
    assert inbox_bytes(c, a) == before  # byte-identical: the block says nothing about who took the cells
    assert count(c, "notifications", {"type": "cells_taken"}) == 1


def test_b2_blocking_a_named_taker_hides_the_name_but_keeps_the_notification(make_app, clock):
    from .conftest import login

    c = make_app(publish_delay_seconds=1800, **K1)
    a, b = login(c, "alice"), login(c, "bob")
    rid = seed_run(c, b, at=clock.now - 2 * H)
    seed_event(c, rid, RING[0], b, a, at=clock.now - 2 * H)
    asyncio.run(notify_cells_taken(res_of(c), rid, uid(b)))
    assert get(c, a, "/notifications").json()["items"][0]["actor"] == {"id": uid(b), "name": "bob"}
    put(c, a, f"/users/{uid(b)}/block")
    page = get(c, a, "/notifications").json()
    assert page["unread_count"] == 1
    item = page["items"][0]
    assert item["actor"] is None and (item["cells"], item["cells_unattributed"]) == (0, 1)
    # other types from the blocked user are still dropped
    ins(c, "notifications", {"_id": "nf", "user_id": uid(a), "type": "new_follower", "actor_id": uid(b), "run_id": None,
                             "comment_id": None, "comment_preview": None, "created_at": 1, "visible_at": 1,
                             "read": False})  # fmt: skip
    assert get(c, a, "/notifications").json()["unread_count"] == 1


# ------------------------------------------------------------------ follow-ups
def test_f1_author_can_remove_own_kudos_and_comment_after_losing_access(make_app, clock):
    from .conftest import login

    c = make_app(publish_delay_seconds=1800, **K1)
    a, b, x = login(c, "alice"), login(c, "bob"), login(c, "xena")
    follow(c, a, b)
    rid = seed_run(c, b, at=clock.now - 2 * H)
    assert put(c, a, f"/runs/{rid}/kudos").status_code == 200
    cid = post(c, a, f"/runs/{rid}/comments", {"text": "nice"}).json()["id"]
    follow(c, x, b)
    assert get(c, x, f"/runs/{rid}/comments").json()["items"][0]["text"] == "nice"
    assert delete(c, a, f"/users/{uid(b)}/follow").status_code == 200  # alice loses access
    assert get(c, a, f"/runs/{rid}/comments").status_code == 404
    other = delete(c, x, f"/runs/{rid}/comments/{cid}")
    assert other.status_code == 403  # a stranger still cannot
    r = delete(c, a, f"/runs/{rid}/kudos")
    assert r.status_code == 200 and r.json() == {"kudos_by_me": False, "kudos_count": 0}
    assert count(c, "kudos", {"run_id": rid}) == 0
    assert delete(c, a, f"/runs/{rid}/comments/{cid}").status_code == 204
    assert get(c, x, f"/runs/{rid}/comments").json()["items"] == []
    assert delete(c, a, f"/runs/{rid}/kudos").status_code == 404  # nothing left and not visible: the one 404


def test_f1_blocked_and_hidden_run_authors_can_still_remove_their_comment(make_app, clock):
    from .conftest import login

    c = make_app(publish_delay_seconds=1800, **K1)
    a, b = login(c, "alice"), login(c, "bob")
    follow(c, a, b)
    rid = seed_run(c, b, at=clock.now - 2 * H)
    cid = post(c, a, f"/runs/{rid}/comments", {"text": "hi"}).json()["id"]
    upd(c, "runs", {"_id": rid}, {"$set": {"hidden": True}})
    assert delete(c, a, f"/runs/{rid}/comments/{cid}").status_code == 204
    assert find(c, "comments", {"_id": cid}) == []


def test_f2_a_blocker_can_still_report_the_user_and_their_comment(make_app, clock):
    from .conftest import login

    c = make_app(publish_delay_seconds=1800, **K1)
    a, b = login(c, "alice"), login(c, "bob")
    rid = seed_run(c, a, at=clock.now - 2 * H)
    follow(c, b, a)
    cid = post(c, b, f"/runs/{rid}/comments", {"text": "rude"}).json()["id"]
    assert put(c, a, f"/users/{uid(b)}/block").status_code == 204
    assert get(c, a, f"/users/{uid(b)}").status_code == 404  # the profile stays hidden
    r = post(c, a, "/reports", {"kind": "user", "target_id": uid(b), "reason": "harassment"})
    assert r.status_code == 202, r.text
    r = post(c, a, "/reports", {"kind": "comment", "target_id": cid, "reason": "rude"})
    assert r.status_code == 202, r.text
    kinds = {x["kind"]: x for x in find(c, "reports")}
    assert kinds["user"]["target_id"] == uid(b) and kinds["comment"]["snapshot"] == "rude"
    # the blocked user cannot report the blocker (the one 404), and a deleting target is still 404
    assert post(c, b, "/reports", {"kind": "user", "target_id": uid(a), "reason": "x"}).status_code == 404
    upd(c, "users", {"_id": uid(b)}, {"$set": {"deleting": True}})
    assert post(c, a, "/reports", {"kind": "user", "target_id": uid(b), "reason": "again"}).status_code == 404


def test_f3_a_rename_does_not_undo_a_moderator_name_hide(client):
    from .conftest import login

    a = login(client, "alice")
    upd(client, "users", {"_id": uid(a)}, {"$set": {"name_hidden": True}})
    r = patch(client, a, "/me", {"display_name": "Fresh Name"})
    assert r.status_code == 200 and r.json()["user"]["name"] == "Fresh Name"
    assert find(client, "users", {"_id": uid(a)})[0]["name_hidden"] is True
    assert get(client, a, "/me").json()["name_hidden"] is True


def test_f4_bad_status_filter_uses_the_error_shape(client):
    from .conftest import login

    a = login(client, "alice")
    r = get(client, a, "/runs", status="bogus")
    assert r.status_code == 422 and r.json()["detail"]["code"] == "bad_status"
    assert get(client, a, "/runs", status="rejected").status_code == 200


def test_f5_kudos_of_a_user_being_deleted_are_not_counted(make_app, clock):
    from .conftest import login

    c = make_app(publish_delay_seconds=1800, **K1)
    a, b, x = login(c, "alice"), login(c, "bob"), login(c, "xena")
    rid = seed_run(c, b, at=clock.now - 2 * H)
    for u in (a, x):
        follow(c, u, b)
        assert put(c, u, f"/runs/{rid}/kudos").status_code == 200
    card = lambda: get(c, a, "/feed").json()["items"][0]["kudos_count"]  # noqa: E731
    assert card() == 2
    upd(c, "users", {"_id": uid(x)}, {"$set": {"deleting": True}})
    assert card() == 1


def test_f6_no_battle_row_when_a_newer_plan_already_holds_the_cell(make_app):
    from .conftest import login

    c = make_app(**K1)
    a, b = login(c, "alice"), login(c, "bob")
    cell = RING[0]
    ins(c, "cells", {"_id": cell, "lat": 50.0, "lng": 8.7, "changed_at": 2000, "owner_id": uid(a)})
    o = {
        "cell": cell, "t": 1000, "p": 1.0, "changed": True, "lat": 50.0, "lng": 8.7,
        "fields": {"changed_at": 1000, "owner_id": uid(b)},
        "event": {"_id": "run:cell", "run_id": "run", "cell": cell, "at": 1000, "taker_id": uid(b),
                  "victim_id": uid(a), "k_ok": True},
    }  # fmt: skip
    asyncio.run(processing._apply(res_of(c).db, uid(b), o))
    assert count(c, "battle_events") == 0 and find(c, "cells", {"_id": cell})[0]["owner_id"] == uid(a)
    o["fields"]["changed_at"] = o["t"] = 3000
    o["event"]["at"] = 3000
    asyncio.run(processing._apply(res_of(c).db, uid(b), o))
    asyncio.run(processing._apply(res_of(c).db, uid(b), o))  # a redelivery stays one row
    assert count(c, "battle_events") == 1


def test_f7_search_normalises_the_query_to_nfc(client):
    from .conftest import login

    a, b = login(client, "alice"), login(client, "bob")
    assert patch(client, b, "/me", {"display_name": "José Runner"}).status_code == 200
    names = [u["name"] for u in get(client, a, "/users/search", q="José R").json()["users"]]
    assert names == ["José Runner"]
