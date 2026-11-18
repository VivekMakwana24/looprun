"""Phase 1a area 9: DELETE /me removes every new kind of data, resumably (spec section 9)."""

from __future__ import annotations

import h3
from pymongo.errors import PyMongoError

from app import processing

from .conftest import T0, db_run, hdr, login
from .phase1a import K1, count, find, follow, get, ins, post, put, seed_event, seed_run, uid
from .test_hardening2 import where_is

RING = sorted(h3.grid_disk(h3.latlng_to_cell(50.0, 8.7, 10), 1))
SOCIAL = ("follows", "kudos", "comments", "notifications", "blocks")


def block(c, a, b):
    put(c, a, f"/users/{uid(b)}/block")


def populate(c):
    """alice (the one to be deleted), bob and dora, with every kind of social data between them."""
    a, b, d = login(c, "alice"), login(c, "bob"), login(c, "dora")
    follow(c, a, b)
    follow(c, b, a)
    follow(c, d, b)
    follow(c, d, a)
    ra, rb = seed_run(c, a, at=T0 - 1, claimed=("c1",)), seed_run(c, b, at=T0 - 1, claimed=("c2", "c3"))
    put(c, a, f"/runs/{rb}/kudos")
    put(c, b, f"/runs/{ra}/kudos")
    put(c, d, f"/runs/{rb}/kudos")
    post(c, a, f"/runs/{rb}/comments", {"text": "from alice"})
    post(c, d, f"/runs/{rb}/comments", {"text": "from dora"})
    post(c, d, f"/runs/{ra}/comments", {"text": "on alice's run"})
    block(c, a, login(c, "eve"))
    block(c, login(c, "finn"), a)
    seed_event(c, rb, RING[0], b, a, at=T0 - 5000)  # bob took a cell from alice
    seed_event(c, ra, RING[1], a, b, at=T0 - 5000)  # alice took one from bob
    seed_event(c, ra, RING[2], a, d, at=T0 - 5000)  # ... and one from dora
    ins(c, "cells", {"_id": RING[0], "owner_id": uid(b)})
    ins(c, "cells", {"_id": RING[1], "owner_id": uid(a)})
    ins(c, "cells", {"_id": RING[2], "owner_id": uid(a)})
    for who, kind, target in ((a, "cell", "x"), (b, "user", uid(a)), (d, "user", uid(a)), (a, "user", uid(b))):
        post(c, who, "/reports", {"kind": kind, "target_id": target, "reason": "r"})
    return a, b, d, ra, rb


def test_delete_me_removes_all_phase_1a_data_of_the_user(make_app):
    c = make_app(**K1)
    a, b, d, ra, rb = populate(c)
    for coll in SOCIAL:
        assert where_is_coll(c, coll, uid(a)), coll  # sanity: there was something to remove
    assert c.delete("/v1/me", headers=hdr(a)).status_code == 204
    for coll in SOCIAL:
        assert where_is_coll(c, coll, uid(a)) == 0, coll  # not in any field, not even inside an _id
    assert count(c, "battle_events", {"$or": [{"taker_id": uid(a)}, {"victim_id": uid(a)}]}) == 0
    assert count(c, "reports", {"reporter_id": uid(a)}) == 0  # filed by alice: gone
    assert count(c, "reports", {"target_id": uid(a), "kind": "user"}) == 2  # about alice: stay (180 days)
    assert [e["victim_id"] for e in find(c, "battle_events", {"taker_id": uid(b)})] == [None]  # bob's take: anonymised
    rest = sorted((e["taker_id"], e["victim_id"]) for e in find(c, "battle_events"))
    assert rest == [(uid(b), None)]  # alice's own takes are gone with her
    assert count(c, "follows") == 1 and count(c, "kudos") == 1 and count(c, "blocks") == 0  # d->b, d->rb
    assert where_is(c, uid(a)).keys() <= {"mongo:reports"}  # only the reports about her (target ids) remain


def where_is_coll(c, coll, needle):
    import json

    return json.dumps(find(c, coll), default=str).count(needle)


def test_other_people_see_nothing_of_the_deleted_user(make_app):
    c = make_app(**K1)
    a, b, d, ra, rb = populate(c)
    before = get(c, b, "/feed").json()["items"]
    assert any(i["user"]["id"] == uid(a) for i in before)
    assert get(c, b, "/me/followers").json()["items"] and get(c, b, f"/users/{uid(b)}").json()["followers_count"] == 2
    assert c.delete("/v1/me", headers=hdr(a)).status_code == 204
    assert [i["user"]["id"] for i in get(c, b, "/feed").json()["items"]] == [uid(b)]
    card = get(c, b, "/feed").json()["items"][0]
    assert card["kudos_count"] == 1 and card["comment_count"] == 1  # only dora's remain
    assert [x["text"] for x in get(c, b, f"/runs/{rb}/comments").json()["items"]] == ["from dora"]
    assert get(c, b, f"/users/{uid(b)}").json()["followers_count"] == 1  # dora
    notes = get(c, b, "/notifications").json()["items"]
    assert [i["actor"]["name"] for i in notes] == ["dora"] * 3  # her follow, kudos and comment
    assert get(c, b, f"/users/{uid(a)}").status_code == 404
    assert get(c, b, "/me/rivals").json()["users"] == []
    assert get(c, d, "/battles/summary").json()["lost"] == 0  # alice's takes from dora left history


def test_take_back_of_a_victim_shows_lost_to_null_once_the_taker_is_deleted(make_app):
    c = make_app(**K1)
    a, b = login(c, "alice"), login(c, "bob")
    seed_event(c, "r1", RING[0], b, a, at=T0 - 5000)
    ins(c, "cells", {"_id": RING[0], "owner_id": uid(b)})
    assert get(c, a, "/battles/take-back").json()["cells"][0]["lost_to"]["name"] == "bob"
    # a taker's take disappears with them: the cell is then handed on by the deletion, no battle remains
    assert c.delete("/v1/me", headers=hdr(b)).status_code == 204
    assert get(c, a, "/battles/take-back").json()["cells"] == []
    # a victim row whose taker's *account* is gone but whose event survived (older data) names nobody
    seed_event(c, "r2", RING[1], "e" * 32, a, at=T0 - 4000)
    assert get(c, a, "/battles/take-back").json()["cells"][0]["lost_to"] is None


def test_deletion_interrupted_after_the_follows_step_ends_clean_when_repeated(make_app, monkeypatch):
    c = make_app(**K1)
    a, b, d, ra, rb = populate(c)
    real = processing.SOCIAL_STEPS["kudos"]
    calls = {"n": 0}

    async def failing(db, user_id):
        calls["n"] += 1
        raise PyMongoError("mongo went away")

    monkeypatch.setitem(processing.SOCIAL_STEPS, "kudos", failing)
    r = c.delete("/v1/me", headers=hdr(a))
    assert r.status_code == 503 and "retry-after" in r.headers
    assert where_is_coll(c, "follows", uid(a)) == 0 and where_is_coll(c, "kudos", uid(a)) > 0  # stopped half way
    assert find(c, "users", {"_id": uid(a)})[0]["deleting"] is True
    assert get(c, b, f"/users/{uid(a)}").status_code == 404  # already invisible
    monkeypatch.setitem(processing.SOCIAL_STEPS, "kudos", real)
    assert c.delete("/v1/me", headers=hdr(a)).status_code == 204
    assert c.delete("/v1/me", headers=hdr(a)).status_code == 401  # nothing left to delete, no duplicates anywhere
    for coll in SOCIAL:
        assert where_is_coll(c, coll, uid(a)) == 0
    assert count(c, "follows") == 1 and count(c, "kudos") == 1


def test_follow_racing_with_the_deletion_leaves_no_row(make_app, monkeypatch):
    c = make_app(**K1)
    a, b = login(c, "alice"), login(c, "bob")
    # a follow of a deleting user is refused
    db_run(c, lambda db: db.users.update_one({"_id": uid(a)}, {"$set": {"deleting": True}}))
    assert put(c, b, f"/users/{uid(a)}/follow").status_code == 404
    assert count(c, "follows") == 0
    db_run(c, lambda db: db.users.update_one({"_id": uid(a)}, {"$unset": {"deleting": ""}}))
    # a follow that slipped in after the first cleanup (it had passed its check before `deleting` was set)
    real = processing.delete_social_data
    runs = {"n": 0}

    async def racing(db, user_id):
        await real(db, user_id)
        runs["n"] += 1
        if runs["n"] == 1:
            await db.follows.insert_one(
                {"_id": f"{uid(b)}:{user_id}", "follower_id": uid(b), "followee_id": user_id, "at": 1}
            )
            await db.kudos.insert_one(
                {"_id": f"r:{uid(b)}", "run_id": "r", "run_owner_id": user_id, "user_id": uid(b), "at": 1}
            )

    monkeypatch.setattr(processing, "delete_social_data", racing)
    assert c.delete("/v1/me", headers=hdr(a)).status_code == 204
    assert runs["n"] == 2 and count(c, "follows") == 0 and count(c, "kudos") == 0  # the final sweep removed them


def test_the_follow_route_rechecks_the_target_after_inserting(make_app, monkeypatch):
    c = make_app(**K1)
    a, b = login(c, "alice"), login(c, "bob")
    from app import social

    real = social.visible_user

    async def then_deleted(res, viewer, user_id):
        u = await real(res, viewer, user_id)
        await res.db.users.update_one({"_id": user_id}, {"$set": {"deleting": True}})  # deleted after the check
        return u

    monkeypatch.setattr(social, "visible_user", then_deleted)
    assert put(c, a, f"/users/{uid(b)}/follow").status_code == 404
    assert count(c, "follows") == 0 and count(c, "notifications") == 0
