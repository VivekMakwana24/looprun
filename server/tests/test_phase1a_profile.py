"""Phase 1a area 2: public profile, rename, profanity hook, hidden names (spec section 1)."""

from __future__ import annotations

import pytest

from app import events, profanity

from .conftest import cells_of, hdr, login, run_loop
from .phase1a import K1, find, get, ins, patch, res_of, uid, upd

PROFILE_KEYS = {
    "id",
    "name",
    "cells_held",
    "weekly_rank",
    "followers_count",
    "following_count",
    "joined_at",
    "is_me",
    "is_following",
    "follows_me",
}
BBOX = "8.6,49.9,8.8,50.1"


def block(c, a, b):
    ins(c, "blocks", {"_id": f"{uid(a)}:{uid(b)}", "blocker_id": uid(a), "blocked_id": uid(b), "at": 1})


def test_profile_of_self_and_other_has_exactly_the_listed_fields(client):
    a, b = login(client, "alice"), login(client, "bob")
    mine, theirs = get(client, a, f"/users/{uid(a)}").json(), get(client, a, f"/users/{uid(b)}").json()
    assert set(mine) == set(theirs) == PROFILE_KEYS
    assert mine["is_me"] is True and theirs["is_me"] is False
    created = find(client, "users", {"_id": uid(b)})[0]["created_at"]
    assert theirs["joined_at"] == created and theirs["name"] == "bob"
    assert theirs["cells_held"] == 0 and theirs["weekly_rank"] is None
    assert theirs["followers_count"] == theirs["following_count"] == 0


def test_profile_404_bodies_are_identical_for_unknown_deleting_and_blocked(client):
    a, b, d, e = (login(client, n) for n in ("alice", "bob", "dora", "eve"))
    upd(client, "users", {"_id": uid(d)}, {"$set": {"deleting": True}})
    block(client, a, b)  # alice blocked bob
    block(client, e, a)  # eve blocked alice
    bodies = []
    for target in ("0" * 32, uid(d), uid(b), uid(e)):
        r = get(client, a, f"/users/{target}")
        assert r.status_code == 404
        bodies.append(r.json())
    assert all(x == bodies[0] for x in bodies) and bodies[0]["detail"]["code"] == "not_found"
    assert get(client, b, f"/users/{uid(a)}").status_code == 404  # both directions
    assert get(client, a, f"/users/{uid(a)}").status_code == 200


def test_profile_counts_and_flags_follow_the_follow_rows(client):
    a, b, d = login(client, "alice"), login(client, "bob"), login(client, "dora")
    for f, t in ((a, b), (d, b), (b, a)):
        ins(client, "follows", {"_id": f"{uid(f)}:{uid(t)}", "follower_id": uid(f), "followee_id": uid(t), "at": 1})
    p = get(client, a, f"/users/{uid(b)}").json()
    assert (p["followers_count"], p["following_count"], p["is_following"], p["follows_me"]) == (2, 1, True, True)
    p = get(client, d, f"/users/{uid(a)}").json()
    assert (p["followers_count"], p["following_count"], p["is_following"], p["follows_me"]) == (1, 1, False, False)


def test_cells_held_of_another_user_is_what_a_stranger_sees_and_own_is_live(make_app, clock):
    c = make_app(privacy_min_users=1, publish_delay_seconds=1800)
    a, b = login(c, "alice"), login(c, "bob")
    st = run_loop(c, a)
    n = st["cells_claimed"]
    assert get(c, a, f"/users/{uid(a)}").json()["cells_held"] == n  # own: live, no delay
    assert get(c, b, f"/users/{uid(a)}").json()["cells_held"] == 0  # inside the publish delay
    clock.advance(seconds=1801)
    assert get(c, b, f"/users/{uid(a)}").json()["cells_held"] == n
    # home zone over the cells: hidden from the stranger count, still counted for the owner
    zone = {"lat": 50.002, "lng": 8.702, "radius_m": 1000}
    assert c.put("/v1/me/home-zones", json={"zones": [zone]}, headers=hdr(a)).status_code == 204
    assert get(c, b, f"/users/{uid(a)}").json()["cells_held"] == 0
    assert get(c, a, f"/users/{uid(a)}").json()["cells_held"] == n


def test_cells_held_excludes_k_hidden_cells(make_app):
    c = make_app(privacy_min_users=2)
    a, b = login(c, "alice"), login(c, "bob")
    run_loop(c, a)
    assert get(c, b, f"/users/{uid(a)}").json()["cells_held"] == 0  # only one user around: K-hidden
    run_loop(c, b, speed=5.0)  # a second user with power around the cells
    assert get(c, b, f"/users/{uid(a)}").json()["cells_held"] > 0


def test_weekly_rank_is_returned_below_the_listed_top(make_app):
    c = make_app(privacy_min_users=1, leaderboard_size=1)
    a, b = login(c, "alice"), login(c, "bob")
    run_loop(c, a, lat=50.0, lng=8.7, side_m=500)
    run_loop(c, b, lat=50.05, lng=8.75, side_m=300)
    board = c.get("/v1/leaderboard/weekly", headers=hdr(a)).json()
    assert len(board["entries"]) == 1
    assert get(c, a, f"/users/{uid(b)}").json()["weekly_rank"] == 2  # beyond the 1 listed entry
    assert get(c, a, f"/users/{uid(a)}").json()["weekly_rank"] == 1


# ---------------------------------------------------------------- rename
@pytest.fixture
def rn(make_app):
    return make_app(social_rename_rate=1000)


def test_rename_rejects_bad_names_with_one_generic_code(rn):
    a = login(rn, "alice")
    for bad in ("x", "y" * 31, "Mi\x07a", "Mi​a", "   \t ", "a\nb", "‮Mia"):
        r = patch(rn, a, "/me", {"display_name": bad})
        assert r.status_code == 422 and r.json()["detail"]["code"] == "name_rejected", bad
    assert patch(rn, a, "/me", {"display_name": "y" * 30}).status_code == 200
    assert patch(rn, a, "/me", {"display_name": "yo"}).status_code == 200
    assert patch(rn, a, "/me", {"display_name": "z" * 500}).status_code == 422  # input size bound


def test_rename_trims_collapses_and_updates_the_search_key(rn):
    a = login(rn, "alice")
    r = patch(rn, a, "/me", {"display_name": "  Mia   K "})
    assert r.status_code == 200 and r.json() == {"user": {"id": uid(a), "name": "Mia K"}}
    doc = find(rn, "users", {"_id": uid(a)})[0]
    assert doc["name"] == "Mia K" and doc["name_lower"] == "mia k"
    assert get(rn, a, "/me").json()["user"]["name"] == "Mia K"


def test_rename_is_limited_to_five_per_24_hours(make_app, clock):
    c = make_app()
    a = login(c, "alice")
    for i in range(5):
        assert patch(c, a, "/me", {"display_name": f"Name {i}"}).status_code == 200
    r = patch(c, a, "/me", {"display_name": "Name 6"})
    assert r.status_code == 429 and int(r.headers["retry-after"]) >= 1
    clock.advance(days=1.01)
    assert patch(c, a, "/me", {"display_name": "Name 6"}).status_code == 200


def test_profanity_listed_leetspeak_and_spaced_variants_are_rejected_ordinary_names_pass(rn):
    a = login(rn, "alice")
    for bad in ("fuck", "Fuck3r", "sh1thead", "f u c k", "f.u.c.k", "b1tch", "Arschloch", "scheisse", "n1gger"):
        r = patch(rn, a, "/me", {"display_name": bad})
        assert r.status_code == 422, bad
        assert r.json()["detail"]["message"] == "This name cannot be used"  # does not say which rule
    for ok in ("Scunthorpe Sam", "Dickens", "Classic Cass", "Hancock", "Mia K", "Çağlar", "Anna-Lena", "Raj"):
        assert patch(rn, a, "/me", {"display_name": ok}).status_code == 200, ok


def test_profanity_module_unit():
    assert profanity.is_allowed("Scunthorpe") and profanity.is_allowed("Assad") and profanity.is_allowed("Nazim")
    assert not profanity.is_allowed("ass") and not profanity.is_allowed("a s s")
    assert not profanity.is_allowed("C0CKSUCKER") and not profanity.is_allowed("cuuunt")
    assert profanity.is_allowed("") and profanity.is_allowed("😀 runner")


def test_google_names_are_screened_at_first_sign_in(make_app):
    names = {"1": "Gina", "2": "fuck", "3": "A", "4": "  Mia   K "}

    def verifier(token, client_id):
        return {"sub": token, "given_name": names[token]}

    c = make_app(dev_auth=False, google_client_id="cid", google_verifier=verifier)
    got = {}
    for tok in names:
        r = c.post("/v1/auth/google", json={"id_token": tok})
        assert r.status_code == 200, r.text
        got[tok] = r.json()["user"]
    assert got["1"]["name"] == "Gina" and got["4"]["name"] == "Mia K"
    for tok in ("2", "3"):
        assert got[tok]["name"] == "Runner-" + got[tok]["id"][:4]
    again = c.post("/v1/auth/google", json={"id_token": "2"}).json()["user"]
    assert again["name"].startswith("Runner-")  # existing accounts are not renamed at sign-in


# ---------------------------------------------------------------- hidden names
def test_a_hidden_name_is_runner_xxxx_everywhere_others_look_and_rename_does_not_clear_it(make_app):
    c = make_app(**K1, social_rename_rate=100)
    a, b = login(c, "alice"), login(c, "bob")
    run_loop(c, a)
    upd(c, "users", {"_id": uid(a)}, {"$set": {"name_hidden": True}})
    alias = "Runner-" + uid(a)[:4]
    assert {x["owner"]["name"] for x in cells_of(c, b) if x["owner"]} == {alias}  # /cells
    assert [e["user"]["name"] for e in c.get("/v1/leaderboard/weekly", headers=hdr(b)).json()["entries"]] == [alias]
    assert get(c, b, f"/users/{uid(a)}").json()["name"] == alias  # profile
    # the owner still sees the real name, and the flag
    assert {x["owner"]["name"] for x in cells_of(c, a)} == {"alice"}
    assert c.get("/v1/leaderboard/weekly", headers=hdr(a)).json()["entries"][0]["user"]["name"] == "alice"
    me = get(c, a, "/me").json()
    assert me["name_hidden"] is True and me["user"]["name"] == "alice"
    assert get(c, a, f"/users/{uid(a)}").json()["name"] == "alice"
    # /live frames
    cell = cells_of(c, b)[0]["id"]
    with c.websocket_connect(f"/v1/live?bbox={BBOX}&token={b['Authorization'].split()[1]}") as ws:
        c.portal.call(events.publish_changes, res_of(c).redis, [{"cell": cell, "new_owner": uid(a), "reveal_at": 0}])
        msg = ws.receive_json()
    assert msg["owner"] == {"id": uid(a), "name": alias}
    # a rename does not undo the hide (review F3); only the moderator lifts it
    assert patch(c, a, "/me", {"display_name": "Alice B"}).status_code == 200
    assert find(c, "users", {"_id": uid(a)})[0]["name_hidden"] is True
    upd(c, "users", {"_id": uid(a)}, {"$set": {"name_hidden": False}})
    assert {x["owner"]["name"] for x in cells_of(c, b) if x["owner"]} == {"Alice B"}


def test_backfill_is_idempotent_and_indexes_old_accounts(client):
    import asyncio

    from app.backfill_social import backfill

    a = login(client, "Alice")
    upd(client, "users", {"_id": uid(a)}, {"$unset": {"name_lower": "", "name_hidden": ""}})
    db = res_of(client).db
    assert asyncio.run(backfill(db)) == 1
    doc = find(client, "users", {"_id": uid(a)})[0]
    assert doc["name_lower"] == "alice" and doc["name_hidden"] is False
    assert asyncio.run(backfill(db)) == 0


def test_an_account_from_before_phase_1a_is_indexed_when_it_signs_in(client):
    a = login(client, "Alice")
    upd(client, "users", {"_id": uid(a)}, {"$unset": {"name_lower": "", "name_hidden": ""}})
    login(client, "Alice")
    assert find(client, "users", {"_id": uid(a)})[0]["name_lower"] == "alice"
