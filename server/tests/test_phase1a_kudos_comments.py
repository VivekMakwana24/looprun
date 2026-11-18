"""Phase 1a area 5: kudos and comments (spec section 4)."""

from __future__ import annotations

import uuid

from .conftest import T0, login
from .phase1a import K1, count, delete, find, follow, get, ins, post, put, seed_run, uid, upd


def setup(c, **kw):
    """owner bob with one published accepted run, follower alice."""
    a, b = login(c, "alice"), login(c, "bob")
    follow(c, a, b)
    return a, b, seed_run(c, b, at=T0 - 1, **kw)


def block(c, a, b):
    ins(c, "blocks", {"_id": f"{uid(a)}:{uid(b)}", "blocker_id": uid(a), "blocked_id": uid(b), "at": 1})


def kudos(c, h, rid, method=put):
    return method(c, h, f"/runs/{rid}/kudos")


def comment(c, h, rid, text="nice"):
    return post(c, h, f"/runs/{rid}/comments", {"text": text})


def comments(c, h, rid, **kw):
    r = get(c, h, f"/runs/{rid}/comments", **kw)
    assert r.status_code == 200, r.text
    return r.json()


def card(c, h, rid):
    return next(i for i in get(c, h, "/feed", limit=50).json()["items"] if i["id"] == rid)


# ---------------------------------------------------------------- kudos
def test_kudos_twice_counts_once_remove_twice_counts_zero_and_notifies_once(client):
    a, b, rid = setup(client)
    for _ in range(2):
        assert kudos(client, a, rid).json() == {"kudos_by_me": True, "kudos_count": 1}
    assert count(client, "kudos") == 1
    notes = find(client, "notifications", {"type": "kudos"})
    assert [n["_id"] for n in notes] == [f"kudos:{rid}:{uid(a)}"]
    assert notes[0]["user_id"] == uid(b) and notes[0]["run_id"] == rid and notes[0]["actor_id"] == uid(a)
    assert card(client, a, rid)["kudos_count"] == 1 and card(client, a, rid)["kudos_by_me"] is True
    assert card(client, b, rid)["kudos_by_me"] is False
    for _ in range(2):
        assert kudos(client, a, rid, delete).json() == {"kudos_by_me": False, "kudos_count": 0}
    assert count(client, "kudos") == 0 and count(client, "notifications", {"type": "kudos"}) == 0  # it goes too
    assert card(client, a, rid)["kudos_count"] == 0


def test_kudos_on_own_run_is_422_own_run(client):
    a, b, rid = setup(client)
    r = kudos(client, b, rid)
    assert r.status_code == 422 and r.json()["detail"]["code"] == "own_run"


def test_every_kind_of_invisible_run_is_the_same_404(make_app, clock):
    c = make_app(publish_delay_seconds=1800, social_comment_burst=1000, social_comment_rate=1000, **K1)
    a, b, d = login(c, "alice"), login(c, "bob"), login(c, "dora")
    follow(c, a, b)
    ok = seed_run(c, b, at=clock.now - 1_800_000)
    fresh = seed_run(c, b, at=clock.now)  # inside the delay
    held = seed_run(c, b, at=clock.now - 2_000_000, status="pending_review")
    hid = seed_run(c, b, at=clock.now - 2_000_000, hidden=True)
    stranger = seed_run(c, d, at=clock.now - 2_000_000)  # alice does not follow dora
    legacy = seed_run(c, b, at=clock.now - 2_000_000)
    upd(c, "runs", {"_id": legacy}, {"$unset": {"claimed_cells": ""}})
    unknown = str(uuid.uuid4())
    assert kudos(c, a, ok).status_code == 200
    bodies = []
    for rid in (fresh, held, hid, stranger, legacy, unknown):
        for method in (put, delete):
            r = kudos(c, a, rid, method)
            assert r.status_code == 404, (rid, method)
            bodies.append(r.text)
        assert comment(c, a, rid).status_code == 404 and get(c, a, f"/runs/{rid}/comments").status_code == 404
    assert len(set(bodies)) == 1 and '"not_found"' in bodies[0]
    block(c, b, a)
    assert kudos(c, a, ok).status_code == 404  # blocked either way
    assert get(c, a, "/runs/not-a-uuid/kudos").status_code in (404, 405, 422)


def test_unfollow_removes_the_ability_but_existing_comments_stay_for_others(client):
    a, b, rid = setup(client)
    d = login(client, "dora")
    follow(client, d, b)
    assert comment(client, a, rid, "hello").status_code == 201
    assert client.delete(f"/v1/users/{uid(b)}/follow", headers={"Authorization": a["Authorization"]}).status_code == 200
    assert kudos(client, a, rid).status_code == 404 and comment(client, a, rid).status_code == 404
    assert [x["text"] for x in comments(client, d, rid)["items"]] == ["hello"]
    assert [x["text"] for x in comments(client, b, rid)["items"]] == ["hello"]


def test_kudos_rate_limit_is_120_per_hour_for_give_and_remove_together(make_app):
    c = make_app(**K1)
    a, b, rid = setup(c)
    for i in range(120):
        assert kudos(c, a, rid, put if i % 2 == 0 else delete).status_code == 200
    r = kudos(c, a, rid)
    assert r.status_code == 429 and "retry-after" in r.headers
    assert kudos(c, a, rid, delete).status_code == 429


# ---------------------------------------------------------------- comments
def test_comment_lengths_and_characters(make_app, clock):
    c = make_app(social_comment_burst=1000, social_comment_rate=1000)
    a, b, rid = setup(c)
    assert comment(c, a, rid, "x" * 500).status_code == 201
    for bad in ("x" * 501, "   ", "", "\n\t ", "bad\x07char", "line\nbreak"):
        r = comment(c, a, rid, bad)
        assert r.status_code == 422 and r.json()["detail"]["code"] == "bad_text", repr(bad)
    r = comment(c, a, rid, "  padded  ")
    assert r.status_code == 201 and r.json()["text"] == "padded"
    assert comment(c, a, rid, "ünï 🎉").status_code == 201


def test_comment_response_and_list_shape_order_and_can_delete(client, clock):
    a, b, rid = setup(client)
    first = comment(client, a, rid, "one")
    clock.advance(seconds=1)
    comment(client, b, rid, "two")
    body = first.json()
    assert first.status_code == 201
    assert set(body) == {"id", "run_id", "user", "text", "created_at", "hidden", "can_delete"}
    assert body["user"] == {"id": uid(a), "name": "alice"} and body["hidden"] is False and body["can_delete"] is True
    page = comments(client, a, rid)
    assert [x["text"] for x in page["items"]] == ["one", "two"] and page["next_cursor"] is None  # oldest first
    assert [x["can_delete"] for x in page["items"]] == [True, False]  # alice: author of one only
    assert [x["can_delete"] for x in comments(client, b, rid)["items"]] == [True, True]  # the run owner deletes any
    p1 = comments(client, a, rid, limit=1)
    p2 = comments(client, a, rid, limit=1, cursor=p1["next_cursor"])
    assert [x["text"] for x in (*p1["items"], *p2["items"])] == ["one", "two"] and p2["next_cursor"] is None


def test_the_201st_comment_is_409_and_the_sixth_in_a_minute_is_429(make_app, clock):
    c = make_app(social_comment_burst=1000, social_comment_rate=1000)
    a, b, rid = setup(c)
    for i in range(200):
        ins(c, "comments", {"_id": f"c{i}", "run_id": rid, "run_owner_id": uid(b), "author_id": uid(b), "text": "t",
                            "created_at": i, "hidden": i % 2 == 0})  # fmt: skip
    r = comment(c, a, rid)
    assert r.status_code == 409 and r.json()["detail"]["code"] == "comment_limit"  # hidden ones count too
    d = make_app()
    a, b, rid = setup(d)
    for i in range(5):
        assert comment(d, a, rid, f"n{i}").status_code == 201
    r = comment(d, a, rid, "n5")
    assert r.status_code == 429 and "retry-after" in r.headers
    clock2 = d.app.state.res.clock
    clock2.advance(seconds=61)
    assert comment(d, a, rid, "later").status_code == 201


def test_comment_rate_limit_is_30_per_hour(make_app):
    c = make_app()
    a, b, rid = setup(c)
    clock = c.app.state.res.clock
    for i in range(30):
        if i and i % 5 == 0:
            clock.advance(seconds=61)
        assert comment(c, a, rid, f"n{i}").status_code == 201
    clock.advance(seconds=61)
    assert comment(c, a, rid, "31st").status_code == 429


def test_delete_author_owner_third_party_and_repeat(client):
    a, b, rid = setup(client)
    d = login(client, "dora")
    follow(client, d, b)
    mine, theirs, third = (comment(client, h, rid, t).json()["id"] for h, t in ((a, "a"), (b, "b"), (a, "c")))
    path = lambda cid: f"/runs/{rid}/comments/{cid}"  # noqa: E731
    r = delete(client, d, path(mine))
    assert r.status_code == 403 and r.json()["detail"]["code"] == "forbidden"  # a third party who can see the run
    assert delete(client, a, path(mine)).status_code == 204  # the author
    assert delete(client, a, path(mine)).status_code == 204  # repeated
    assert delete(client, b, path(third)).status_code == 204  # the run owner deletes anybody's
    assert delete(client, a, path(theirs)).status_code == 403
    assert delete(client, a, path("0" * 32)).status_code == 204  # absent
    assert [x["text"] for x in comments(client, a, rid)["items"]] == ["b"]
    stranger = login(client, "eve")
    assert delete(client, stranger, path(theirs)).status_code == 404  # cannot even see the run


def test_blocked_hidden_and_deleting_authors(client):
    a, b, rid = setup(client)
    d, e, f = (login(client, n) for n in ("dora", "eve", "finn"))
    for who in (d, e, f):
        follow(client, who, b)
    ids = {n: comment(client, h, rid, n).json()["id"] for n, h in (("alice", a), ("dora", d), ("eve", e), ("finn", f))}
    block(client, a, e)  # alice blocked eve: invisible to both
    upd(client, "comments", {"_id": ids["dora"]}, {"$set": {"hidden": True}})
    upd(client, "users", {"_id": uid(f)}, {"$set": {"deleting": True}})
    assert [x["text"] for x in comments(client, a, rid)["items"]] == ["alice"]
    seen_by_eve = [x["text"] for x in comments(client, e, rid)["items"]]
    assert "alice" not in seen_by_eve and "eve" in seen_by_eve  # blocked pair: neither sees the other
    own = comments(client, d, rid)["items"]  # the author gets their hidden comment, flagged
    assert [(x["text"], x["hidden"]) for x in own if x["text"] == "dora"] == [("dora", True)]
    assert all(x["text"] != "dora" for x in comments(client, b, rid)["items"])  # nobody else does
    assert all(x["text"] != "finn" for x in comments(client, b, rid)["items"])


def test_counts_on_cards_match_the_lists_after_each_operation(client):
    a, b, rid = setup(client)
    d = login(client, "dora")
    follow(client, d, b)

    def check():
        cd = card(client, a, rid)
        assert cd["comment_count"] == len([x for x in comments(client, a, rid)["items"] if not x["hidden"]])
        return cd

    assert check()["comment_count"] == 0
    c1 = comment(client, a, rid, "1").json()["id"]
    comment(client, d, rid, "2")
    assert check()["comment_count"] == 2
    delete(client, a, f"/runs/{rid}/comments/{c1}")
    assert check()["comment_count"] == 1
    kudos(client, a, rid)
    kudos(client, d, rid)
    assert check()["kudos_count"] == 2
    kudos(client, a, rid, delete)
    assert check()["kudos_count"] == 1


def test_comment_notifications_preview_self_comment_and_cleanup(make_app, clock):
    c = make_app(publish_delay_seconds=1800, **K1)
    a, b = login(c, "alice"), login(c, "bob")
    follow(c, a, b)
    rid = seed_run(c, b, at=clock.now - 1_800_000)
    long = "w" * 100
    cid = comment(c, a, rid, long).json()["id"]
    comment(c, b, rid, "my own run")  # self comment: no notification
    notes = [n for n in find(c, "notifications") if n["type"] == "comment"]
    assert [n["_id"] for n in notes] == [f"comment:{cid}"]
    n = notes[0]
    assert n["user_id"] == uid(b) and n["actor_id"] == uid(a) and n["run_id"] == rid and n["comment_id"] == cid
    assert n["comment_preview"] == "w" * 80 and n["visible_at"] == clock.now + 1_800_000
    assert delete(c, b, f"/runs/{rid}/comments/{cid}").status_code == 204
    assert [x for x in find(c, "notifications") if x["type"] == "comment"] == []


def test_comments_are_screened_when_the_filter_setting_is_on(make_app):
    c = make_app(filter_comments=True)
    a, b, rid = setup(c)
    r = comment(c, a, rid, "you are a b1tch")
    assert r.status_code == 422 and r.json()["detail"]["code"] == "text_rejected"
    assert comment(c, a, rid, "great run").status_code == 201
    off = make_app()
    a, b, rid = setup(off)
    assert comment(off, a, rid, "you are a b1tch").status_code == 201  # off by default in 1a
