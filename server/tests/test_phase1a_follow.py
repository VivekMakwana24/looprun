"""Phase 1a area 3: follow, followers/following lists, search, rivals (spec section 2)."""

from __future__ import annotations

import h3

from .conftest import DAY, T0, login
from .phase1a import HOUR, K1, count, delete, find, follow, get, ins, patch, put, seed_event, uid, upd

CELL = h3.latlng_to_cell(50.0, 8.7, 10)


def fake_users(c, n, prefix="u"):
    ids = []
    for i in range(n):
        i_d = f"{prefix}{i:05d}".ljust(32, "0")
        ids.append(i_d)
        name = f"{prefix}{i}"
        ins(c, "users", {"_id": i_d, "google_sub": f"fake:{i_d}", "name": name, "name_lower": name, "created_at": 1})
    return ids


def block(c, a, b):
    ins(c, "blocks", {"_id": f"{uid(a)}:{uid(b)}", "blocker_id": uid(a), "blocked_id": uid(b), "at": 1})


# ---------------------------------------------------------------- follow
def test_follow_twice_is_one_row_and_one_notification_unfollow_twice_is_200(client):
    a, b = login(client, "alice"), login(client, "bob")
    r1, r2 = put(client, a, f"/users/{uid(b)}/follow"), put(client, a, f"/users/{uid(b)}/follow")
    assert r1.status_code == r2.status_code == 200
    assert r1.json() == r2.json() == {"is_following": True, "followers_count": 1}
    assert count(client, "follows") == 1
    notes = find(client, "notifications")
    assert len(notes) == 1 and notes[0]["_id"] == f"new_follower:{uid(b)}:{uid(a)}"
    assert notes[0]["user_id"] == uid(b) and notes[0]["actor_id"] == uid(a) and notes[0]["read"] is False
    for _ in range(2):
        r = delete(client, a, f"/users/{uid(b)}/follow")
        assert r.status_code == 200 and r.json() == {"is_following": False, "followers_count": 0}
    assert count(client, "follows") == 0 and count(client, "notifications") == 1  # the notification stays
    follow(client, a, b)  # follow, unfollow, follow: still one notification
    assert count(client, "notifications") == 1


def test_new_follower_notification_is_visible_only_after_the_publish_delay(make_app, clock):
    c = make_app(publish_delay_seconds=1800)
    a, b = login(c, "alice"), login(c, "bob")
    follow(c, a, b)
    assert find(c, "notifications")[0]["visible_at"] == clock.now + 1_800_000


def test_follow_self_unknown_deleting_blocked(client):
    a, b, d, e = (login(client, n) for n in ("alice", "bob", "dora", "eve"))
    r = put(client, a, f"/users/{uid(a)}/follow")
    assert r.status_code == 422 and r.json()["detail"]["code"] == "self"
    upd(client, "users", {"_id": uid(d)}, {"$set": {"deleting": True}})
    block(client, a, b)
    block(client, e, a)
    bodies = [put(client, a, f"/users/{t}/follow") for t in ("f" * 32, uid(d), uid(b), uid(e))]
    assert {r.status_code for r in bodies} == {404} and len({r.text for r in bodies}) == 1
    assert count(client, "follows") == 0
    # unfollowing someone who is gone or blocked is still fine and tells nothing
    r = delete(client, a, f"/users/{uid(b)}/follow")
    assert r.status_code == 200 and r.json()["followers_count"] == 0


def test_the_501st_follow_is_409_and_an_existing_follow_stays_idempotent(make_app):
    c = make_app(social_follow_rate=10_000)
    a = login(c, "alice")
    ids = fake_users(c, 501)
    for i in range(500):
        ins(c, "follows", {"_id": f"{uid(a)}:{ids[i]}", "follower_id": uid(a), "followee_id": ids[i], "at": i})
    r = put(c, a, f"/users/{ids[500]}/follow")
    assert r.status_code == 409 and r.json()["detail"]["code"] == "follow_limit"
    assert put(c, a, f"/users/{ids[0]}/follow").status_code == 200  # already following: no new row, no error
    assert delete(c, a, f"/users/{ids[0]}/follow").status_code == 200
    assert put(c, a, f"/users/{ids[500]}/follow").status_code == 200


def test_follow_is_rate_limited_to_100_per_hour_with_retry_after(make_app):
    c = make_app()
    a, b = login(c, "alice"), login(c, "bob")
    for i in range(100):
        assert (put if i % 2 == 0 else delete)(c, a, f"/users/{uid(b)}/follow").status_code == 200  # shared scope
    r = put(c, a, f"/users/{uid(b)}/follow")
    assert r.status_code == 429 and int(r.headers["retry-after"]) >= 1
    assert delete(c, a, f"/users/{uid(b)}/follow").status_code == 429


# ---------------------------------------------------------------- lists
def test_lists_are_own_only_newest_first_with_flags(make_app, clock):
    c = make_app()
    a, b, d, e = (login(c, n) for n in ("alice", "bob", "dora", "eve"))
    for who in (b, d, e):  # b follows a first, then d, then e
        clock.advance(seconds=1)
        follow(c, who, a)
    follow(c, a, b)  # alice follows bob back
    followers = get(c, a, "/me/followers").json()
    assert [i["name"] for i in followers["items"]] == ["eve", "dora", "bob"] and followers["next_cursor"] is None
    flags = [(i["is_following"], i["follows_me"]) for i in followers["items"]]
    assert flags == [(False, True), (False, True), (True, True)]
    following = get(c, a, "/me/following").json()["items"]
    assert [(i["name"], i["is_following"], i["follows_me"]) for i in following] == [("bob", True, True)]
    assert set(followers["items"][0]) == {"id", "name", "is_following", "follows_me"}


def test_followers_list_skips_deleting_users_and_hidden_names_show_as_runner(client, clock):
    a, b, d = login(client, "alice"), login(client, "bob"), login(client, "dora")
    follow(client, b, a)
    clock.advance(seconds=1)
    follow(client, d, a)
    upd(client, "users", {"_id": uid(d)}, {"$set": {"deleting": True}})
    upd(client, "users", {"_id": uid(b)}, {"$set": {"name_hidden": True}})
    names = [i["name"] for i in get(client, a, "/me/followers").json()["items"]]
    assert names == ["Runner-" + uid(b)[:4]]


def test_pagination_is_stable_when_new_follows_arrive_between_pages(make_app, clock):
    c = make_app()
    a = login(c, "alice")
    others = [login(c, f"u{i}") for i in range(7)]
    for o in others[:5]:
        clock.advance(seconds=1)
        follow(c, o, a)
    page1 = get(c, a, "/me/followers", limit=2).json()
    assert len(page1["items"]) == 2 and page1["next_cursor"]
    clock.advance(seconds=1)
    follow(c, others[5], a)  # arrives between pages: newer, so it sorts above the cursor
    page2 = get(c, a, "/me/followers", limit=2, cursor=page1["next_cursor"]).json()
    page3 = get(c, a, "/me/followers", limit=2, cursor=page2["next_cursor"]).json()
    assert page3["next_cursor"] is None
    seen = [i["name"] for p in (page1, page2, page3) for i in p["items"]]
    assert seen == ["u4", "u3", "u2", "u1", "u0"]  # each once, in order, none skipped
    assert get(c, a, "/me/followers", limit=50).json()["items"][0]["name"] == "u5"


def test_bad_limit_and_cursor_are_422_bad_cursor(client):
    a = login(client, "alice")
    for params in ({"limit": 0}, {"limit": 51}, {"cursor": "!!!"}, {"cursor": "W10"}):
        for path in ("/me/followers", "/me/following"):
            r = get(client, a, path, **params)
            assert r.status_code == 422 and r.json()["detail"]["code"] == "bad_cursor", (path, params)


# ---------------------------------------------------------------- search
def test_search_is_a_case_insensitive_prefix_that_hides_the_right_people(client):
    me = login(client, "mario")
    names = ["Mia", "mark", "Amy", "mabel", "mad", "mal", "maya"]
    users = {n: login(client, n) for n in names}
    upd(client, "users", {"_id": uid(users["mad"])}, {"$set": {"name_hidden": True}})
    upd(client, "users", {"_id": uid(users["mal"])}, {"$set": {"deleting": True}})
    block(client, me, users["mabel"])  # I blocked mabel
    block(client, users["mark"], me)  # mark blocked me
    got = get(client, me, "/users/search", q="MA").json()["users"]
    assert [u["name"] for u in got] == ["maya"]  # not me, mad (hidden), mal (deleting), mabel, mark (blocked)
    assert [u["name"] for u in get(client, me, "/users/search", q="mi").json()["users"]] == ["Mia"]
    assert get(client, me, "/users/search", q="am").json()["users"][0]["name"] == "Amy"
    seen_by_mark = get(client, users["mark"], "/users/search", q="ma").json()["users"]
    assert [u["name"] for u in seen_by_mark] == ["mabel", "maya"]  # mario is blocked in the other direction
    assert set(seen_by_mark[0]) == {"id", "name", "is_following", "follows_me"}


def test_search_validation_limit_and_regex_characters(make_app):
    c = make_app(social_rename_rate=100)
    me = login(c, "mario")
    assert get(c, me, "/users/search", q="m").status_code == 422
    assert get(c, me, "/users/search", q="x" * 31).status_code == 422
    assert get(c, me, "/users/search", q=" a ").status_code == 422  # trimmed to one character
    assert get(c, me, "/users/search").status_code == 422
    star = login(c, "star")
    assert patch(c, star, "/me", {"display_name": ".*Dot"}).status_code == 200
    login(c, "zed")
    got = get(c, me, "/users/search", q=".*").json()["users"]
    assert [u["name"] for u in got] == [".*Dot"]  # never a pattern
    assert get(c, me, "/users/search", q="((").json()["users"] == []
    for i in range(30):
        login(c, f"max{i:02d}")
    assert len(get(c, me, "/users/search", q="max").json()["users"]) == 20


def test_search_renamed_user_found_by_new_name_only(make_app):
    c = make_app(social_rename_rate=100)
    me, a = login(c, "mario"), login(c, "alice")
    assert patch(c, a, "/me", {"display_name": "Bella"}).status_code == 200
    assert get(c, me, "/users/search", q="al").json()["users"] == []
    assert [u["name"] for u in get(c, me, "/users/search", q="be").json()["users"]] == ["Bella"]


def test_search_is_rate_limited_to_30_per_minute(make_app, clock):
    c = make_app()
    me = login(c, "mario")
    for _ in range(30):
        assert get(c, me, "/users/search", q="zz").status_code == 200
    r = get(c, me, "/users/search", q="zz")
    assert r.status_code == 429 and "retry-after" in r.headers
    clock.advance(seconds=61)
    assert get(c, me, "/users/search", q="zz").status_code == 200


def test_read_routes_share_one_limit_of_120_per_minute(make_app):
    c = make_app()
    a = login(c, "alice")
    for i in range(120):
        assert get(c, a, "/me/followers" if i % 2 else "/me/following").status_code == 200
    r = get(c, a, f"/users/{uid(a)}")
    assert r.status_code == 429 and r.json()["detail"]["code"] == "rate_limited" and "retry-after" in r.headers


# ---------------------------------------------------------------- rivals
def test_rivals_window_direction_and_order(client):
    a, b, c_ = login(client, "alice"), login(client, "bob"), login(client, "carl")
    seed_event(client, "r1", "x1", a, b, at=T0 - 10 * DAY)  # A took from B 10 days ago
    seed_event(client, "r2", "x2", c_, a, at=T0 - 40 * DAY)  # C took from A 40 days ago
    got = get(client, a, "/me/rivals").json()["users"]
    assert [u["name"] for u in got] == ["bob"] and set(got[0]) == {"id", "name", "is_following", "follows_me"}
    seed_event(client, "r3", "x3", c_, a, at=T0 - 2 * DAY)  # a more recent loss to C
    follow(client, a, c_)
    got = get(client, a, "/me/rivals").json()["users"]
    assert [(u["name"], u["is_following"]) for u in got] == [("carl", True), ("bob", False)]  # most recent first
    assert [u["name"] for u in get(client, b, "/me/rivals").json()["users"]] == ["alice"]  # either direction


def test_rivals_hide_unnameable_opponents(make_app):
    c = make_app(publish_delay_seconds=1800, **K1)
    a, b, d, e, f, g, h = (login(c, n) for n in ("alice", "bob", "dora", "eve", "finn", "gus", "hal"))
    t = T0 - HOUR * 3
    seed_event(c, "k", "x1", a, b, at=t, k_ok=False)  # K-anonymity failed at claim time
    seed_event(c, "z", CELL, a, d, at=t)  # inside dora's home zone
    upd(c, "users", {"_id": uid(d)}, {"$set": {"home_zones": [{"lat": 50.0, "lng": 8.7, "radius_m": 200}]}})
    seed_event(c, "y", "x3", a, e, at=T0 - 600_000)  # younger than the delay
    seed_event(c, "bl", "x4", a, f, at=t)
    block(c, a, f)
    seed_event(c, "n", "x5", a, g, at=t)
    upd(c, "users", {"_id": uid(g)}, {"$set": {"name_hidden": True}})
    seed_event(c, "ok", "x6", h, a, at=t)
    assert [u["name"] for u in get(c, a, "/me/rivals").json()["users"]] == ["hal"]
    seed_event(c, "gone", "x7", a, None, at=t)  # a deleted victim never names anyone
    assert [u["name"] for u in get(c, a, "/me/rivals").json()["users"]] == ["hal"]


def test_rivals_are_capped_at_50(make_app):
    c = make_app(**K1)
    a = login(c, "alice")
    ids = fake_users(c, 60, "r")
    for i, v in enumerate(ids):
        seed_event(c, f"r{i}", f"c{i}", a, v, at=T0 - i * 1000 - 1000)
    got = get(c, a, "/me/rivals").json()["users"]
    assert len(got) == 50 and got[0]["id"] == ids[0]
