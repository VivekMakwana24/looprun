"""Phase 1a area 8: block, report kinds, moderation CLI, rate limits (spec section 8)."""

from __future__ import annotations

import asyncio
import json
import uuid

import pytest

from app import moderation

from .conftest import T0, cells_of, hdr, login, run_loop
from .phase1a import K1, count, delete, find, follow, get, ins, post, put, res_of, seed_event, seed_run, uid, upd


def block(c, a, b):
    return put(c, a, f"/users/{uid(b)}/block")


def report(c, h, kind, target, reason="because"):
    return post(c, h, "/reports", {"kind": kind, "target_id": target, "reason": reason})


def cli(c, *argv):
    return asyncio.run(moderation.execute(res_of(c), list(argv), admin="op"))


# ---------------------------------------------------------------- block
def test_block_removes_follows_kudos_and_notifications_between_the_pair_only(client):
    a, b, d = login(client, "alice"), login(client, "bob"), login(client, "dora")
    follow(client, a, b)
    follow(client, b, a)
    follow(client, d, a)  # dora is not part of the pair
    ra, rb = seed_run(client, a, at=T0 - 1), seed_run(client, b, at=T0 - 1)
    put(client, b, f"/runs/{ra}/kudos")
    put(client, a, f"/runs/{rb}/kudos")
    put(client, d, f"/runs/{ra}/kudos")
    assert count(client, "notifications") == 6  # 3 follows + 3 kudos
    assert block(client, a, b).status_code == 204
    assert count(client, "follows", {"$or": [{"follower_id": uid(a), "followee_id": uid(b)},
                                              {"follower_id": uid(b), "followee_id": uid(a)}]}) == 0  # fmt: skip
    assert count(client, "follows") == 1  # dora -> alice stays
    assert [k["user_id"] for k in find(client, "kudos")] == [uid(d)]
    assert [(n["user_id"], n["actor_id"]) for n in find(client, "notifications")] == [
        (uid(a), uid(d)), (uid(a), uid(d)),
    ]  # fmt: skip
    assert count(client, "blocks") == 1


def test_block_effects_profile_search_feed_comments_rivals_follow(client, clock):
    a, b = login(client, "alice"), login(client, "bob")
    follow(client, a, b)
    rb = seed_run(client, b, at=T0 - 1)
    cid = post(client, a, f"/runs/{rb}/comments", {"text": "hi"}).json()["id"]
    seed_event(client, "r1", "x1", a, b, at=T0 - 1000)
    assert [u["name"] for u in get(client, a, "/me/rivals").json()["users"]] == ["bob"]
    assert block(client, a, b).status_code == 204
    for who, other in ((a, b), (b, a)):  # both directions
        assert get(client, who, f"/users/{uid(other)}").status_code == 404
        assert get(client, who, "/users/search", q="bo" if other is b else "al").json()["users"] == []
        assert put(client, who, f"/users/{uid(other)}/follow").status_code == 404
        assert get(client, who, "/me/rivals").json()["users"] == []
    assert get(client, a, "/feed").json()["items"] == []
    assert get(client, a, f"/runs/{rb}/comments").status_code == 404
    assert get(client, a, "/battles/rivalry").json()["rivals"] == []
    assert get(client, a, "/battles/rivalry").json()["unattributed"] == {"taken": 1, "lost": 0}
    assert find(client, "comments", {"_id": cid})  # the comment row stays: hidden by the read-time filter only
    assert [u["name"] for u in get(client, a, "/me/blocks").json()["items"]] == ["bob"]
    assert get(client, b, "/me/blocks").json()["items"] == []


def test_block_twice_unblock_and_follows_are_not_restored(client):
    a, b = login(client, "alice"), login(client, "bob")
    follow(client, a, b)
    assert block(client, a, b).status_code == block(client, a, b).status_code == 204
    assert count(client, "blocks") == 1
    for _ in range(2):
        assert delete(client, a, f"/users/{uid(b)}/block").status_code == 204
    assert count(client, "blocks") == 0 and count(client, "follows") == 0
    assert get(client, a, f"/users/{uid(b)}").status_code == 200
    assert put(client, a, f"/users/{uid(b)}/follow").status_code == 200


def test_block_self_unknown_deleting_and_the_501st(make_app):
    c = make_app(social_block_rate=10_000)
    a, d = login(c, "alice"), login(c, "dora")
    r = block(c, a, a)
    assert r.status_code == 422 and r.json()["detail"]["code"] == "self"
    assert put(c, a, "/users/" + "f" * 32 + "/block").status_code == 404
    upd(c, "users", {"_id": uid(d)}, {"$set": {"deleting": True}})
    assert block(c, a, d).status_code == 404
    for i in range(500):
        ins(c, "blocks", {"_id": f"{uid(a)}:u{i}", "blocker_id": uid(a), "blocked_id": f"u{i}", "at": i})
    b = login(c, "bob")
    r = block(c, a, b)
    assert r.status_code == 409 and r.json()["detail"]["code"] == "block_limit"
    assert put(c, a, "/users/u3/block").status_code == 404  # unknown id, and the limit check does not hide that
    ins(c, "blocks", {"_id": f"{uid(a)}:{uid(b)}", "blocker_id": uid(a), "blocked_id": uid(b), "at": 1})
    assert block(c, a, b).status_code == 204  # an existing block stays idempotent at the limit


def test_block_is_rate_limited_to_30_per_hour(make_app):
    c = make_app()
    a = login(c, "alice")
    others = [login(c, f"u{i}") for i in range(31)]
    for o in others[:30]:
        assert block(c, a, o).status_code == 204
    r = block(c, a, others[30])
    assert r.status_code == 429 and "retry-after" in r.headers


def test_my_blocks_newest_first_paged_and_a_deleted_user_disappears(make_app, clock):
    c = make_app()
    a = login(c, "alice")
    others = [login(c, f"u{i}") for i in range(5)]
    for o in others:
        clock.advance(seconds=1)
        block(c, a, o)
    p1 = get(c, a, "/me/blocks", limit=2).json()
    p2 = get(c, a, "/me/blocks", limit=2, cursor=p1["next_cursor"]).json()
    assert [i["name"] for i in p1["items"] + p2["items"]] == ["u4", "u3", "u2", "u1"]
    assert set(p1["items"][0]) == {"id", "name"}
    upd(c, "users", {"_id": uid(others[4])}, {"$set": {"deleting": True}})
    assert [i["name"] for i in get(c, a, "/me/blocks", limit=50).json()["items"]] == ["u3", "u2", "u1", "u0"]


def test_block_does_not_change_the_map_or_the_leaderboard(make_app):
    c = make_app(**K1)
    a, b = login(c, "alice"), login(c, "bob")
    run_loop(c, a)
    before = (cells_of(c, b), c.get("/v1/leaderboard/weekly", headers=hdr(b)).json()["entries"])
    block(c, b, a)
    block(c, a, b)
    after = (cells_of(c, b), c.get("/v1/leaderboard/weekly", headers=hdr(b)).json()["entries"])
    assert before == after and before[1][0]["user"]["name"] == "alice"  # documented non-effect: public game state


# ---------------------------------------------------------------- report
def test_report_user_comment_run_card_store_owner_snapshot_and_state(client):
    a, b = login(client, "alice"), login(client, "bob")
    follow(client, a, b)
    rid = seed_run(client, b, at=T0 - 1, claimed=("c1", "c2"))
    cid = post(client, a, f"/runs/{rid}/comments", {"text": "rude words"}).json()["id"]
    d = login(client, "dora")
    follow(client, d, b)
    other = post(client, d, f"/runs/{rid}/comments", {"text": "dora here"}).json()["id"]
    for kind, target, owner in (("user", uid(b), uid(b)), ("comment", other, uid(d)), ("run_card", rid, uid(b))):
        r = report(client, a, kind, target)
        assert r.status_code == 202 and r.json() == {"status": "recorded"}
        row = find(client, "reports", {"kind": kind})[0]
        assert row["target_owner_id"] == owner and row["state"] == "open" and row["target_id"] == target
        assert row["reporter_id"] == uid(a) and row["reason"] == "because" and row["resolved_at"] is None
        assert row["expire_at"].year >= 2027
    snaps = {r["kind"]: r["snapshot"] for r in find(client, "reports")}
    assert snaps["user"] == "bob" and snaps["comment"] == "dora here"
    assert snaps["run_card"]["id"] == rid and snaps["run_card"]["cells_claimed"] == 2
    assert not {"lat", "lng", "fixes", "claimed_cells", "polygon"} & set(json.loads(json.dumps(snaps["run_card"])))
    assert cid  # (alice's own comment: reporting it is a self-report, below)


def test_report_snapshot_keeps_the_real_name_even_when_others_see_runner_xxxx(client):
    a, b = login(client, "alice"), login(client, "bob")
    upd(client, "users", {"_id": uid(b)}, {"$set": {"name_hidden": True}})
    assert report(client, a, "user", uid(b)).status_code == 202
    assert find(client, "reports")[0]["snapshot"] == "bob"


def test_report_of_something_the_reporter_cannot_see_is_404_and_stores_nothing(make_app, clock):
    c = make_app(publish_delay_seconds=1800, social_comment_burst=100, **K1)
    a, b, d = login(c, "alice"), login(c, "bob"), login(c, "dora")
    follow(c, a, b)
    follow(c, d, b)
    ok = seed_run(c, b, at=clock.now - 1_800_000)
    fresh = seed_run(c, b, at=clock.now)
    held = seed_run(c, b, at=clock.now - 2_000_000, status="pending_review")
    stranger = seed_run(c, d, at=clock.now - 2_000_000)  # alice does not follow dora
    visible = post(c, d, f"/runs/{ok}/comments", {"text": "hello"}).json()["id"]
    hidden = post(c, d, f"/runs/{ok}/comments", {"text": "hidden one"}).json()["id"]
    upd(c, "comments", {"_id": hidden}, {"$set": {"hidden": True}})
    ins(c, "comments", {"_id": "elsewhere", "run_id": stranger, "run_owner_id": uid(d), "author_id": uid(d),
                        "text": "x", "created_at": 1, "hidden": False})  # fmt: skip
    gone = login(c, "gina")
    upd(c, "users", {"_id": uid(gone)}, {"$set": {"deleting": True}})
    # dora blocked alice: alice cannot report her (only a blocker keeps the right to report, see review F2)
    ins(c, "blocks", {"_id": f"{uid(d)}:{uid(a)}", "blocker_id": uid(d), "blocked_id": uid(a), "at": 1})
    cases = [
        ("run_card", fresh), ("run_card", held), ("run_card", stranger), ("run_card", str(uuid.uuid4())),
        ("comment", hidden), ("comment", "elsewhere"), ("comment", "nope"), ("user", uid(gone)), ("user", "f" * 32),
        ("user", uid(d)), ("comment", visible),
    ]  # fmt: skip
    bodies = set()
    for kind, target in cases:
        r = report(c, a, kind, target)
        assert r.status_code == 404, (kind, target)
        bodies.add(r.text)
    assert len(bodies) == 1 and count(c, "reports") == 0
    clock.advance(seconds=1)
    assert report(c, a, "run_card", ok).status_code == 202


def test_duplicate_report_is_202_and_one_row_and_old_kinds_are_unchanged(client):
    a, b = login(client, "alice"), login(client, "bob")
    for _ in range(3):
        assert report(client, a, "user", uid(b)).status_code == 202
    assert count(client, "reports", {"kind": "user"}) == 1
    for _ in range(2):  # run and cell reports stay repeatable and keep their exact old shape
        assert report(client, a, "run", "any-run-id").status_code == 202
        assert report(client, a, "cell", "8a1fae32006ffff").status_code == 202
    olds = find(client, "reports", {"kind": {"$in": ["run", "cell"]}})
    shape = {"_id", "reporter_id", "kind", "target_id", "reason", "created_at", "expire_at", "state"}
    assert len(olds) == 4 and all(set(r) == shape for r in olds)


def test_report_self_and_the_shared_limit_of_20_per_hour(client):
    a, b = login(client, "alice"), login(client, "bob")
    follow(client, b, a)
    rid = seed_run(client, a, at=T0 - 1)
    mine = post(client, a, f"/runs/{rid}/comments", {"text": "mine"}).json()["id"]
    for kind, target in (("user", uid(a)), ("run_card", rid), ("comment", mine)):
        r = report(client, a, kind, target)
        assert r.status_code == 422 and r.json()["detail"]["code"] == "self", kind
    assert count(client, "reports") == 0
    for i in range(20 - 3):  # the three 422s above counted against the hour already
        assert report(client, a, "cell", f"c{i}").status_code == 202
    r = report(client, a, "user", uid(b))
    assert r.status_code == 429 and "retry-after" in r.headers
    assert report(client, a, "run", "x").status_code == 429


# ---------------------------------------------------------------- moderation CLI
def test_cli_hide_and_unhide_comment_effect_log_and_report_resolution(client):
    a, b = login(client, "alice"), login(client, "bob")
    follow(client, a, b)
    d = login(client, "dora")
    follow(client, d, b)
    rid = seed_run(client, b, at=T0 - 1)
    cid = post(client, a, f"/runs/{rid}/comments", {"text": "bad"}).json()["id"]
    report(client, d, "comment", cid)
    assert any(n["type"] == "comment" for n in find(client, "notifications"))
    out = cli(client, "hide-comment", cid)
    assert out == [f"hide-comment {cid}: ok (1 report(s) marked hidden)"]
    assert [x["text"] for x in get(client, d, f"/runs/{rid}/comments").json()["items"]] == []  # gone for others
    mine = get(client, a, f"/runs/{rid}/comments").json()["items"]  # present with hidden:true for the author
    assert [(x["text"], x["hidden"]) for x in mine] == [("bad", True)]
    assert get(client, d, "/feed").json()["items"][0]["comment_count"] == 0
    assert not any(n["type"] == "comment" for n in find(client, "notifications"))  # its notification is deleted
    rep = find(client, "reports")[0]
    assert rep["state"] == "hidden" and rep["resolved_at"] is not None
    log = find(client, "moderation_log")
    assert len(log) == 1 and log[0]["admin"] == "op" and log[0]["action"] == "hide-comment"
    assert (log[0]["target_kind"], log[0]["target_id"]) == ("comment", cid)
    assert log[0]["report_ids"] == [str(rep["_id"])]
    assert log[0]["expire_at"].year >= 2027
    cli(client, "unhide-comment", cid)
    assert [x["text"] for x in get(client, d, f"/runs/{rid}/comments").json()["items"]] == ["bad"]
    assert [x["action"] for x in find(client, "moderation_log")] == ["hide-comment", "unhide-comment"]


def test_cli_hide_name_shows_runner_xxxx_on_the_map_and_clears_the_leaderboard_cache(make_app):
    c = make_app(leaderboard_cache_seconds=60, **K1)
    a, b = login(c, "alice"), login(c, "bob")
    run_loop(c, a)
    d = login(c, "dora")
    report(c, d, "user", uid(a))
    assert c.get("/v1/leaderboard/weekly", headers=hdr(b)).json()["entries"][0]["user"]["name"] == "alice"
    out = cli(c, "hide-name", uid(a))
    alias = "Runner-" + uid(a)[:4]
    assert "1 report(s) marked hidden" in out[0]
    assert {x["owner"]["name"] for x in cells_of(c, b) if x["owner"]} == {alias}
    assert c.get("/v1/leaderboard/weekly", headers=hdr(b)).json()["entries"][0]["user"]["name"] == alias
    assert get(c, b, "/users/search", q="al").json()["users"] == []
    assert get(c, b, f"/users/{uid(a)}").json()["name"] == alias
    assert find(c, "moderation_log")[0]["action"] == "hide-name"
    cli(c, "unhide-name", uid(a))
    assert {x["owner"]["name"] for x in cells_of(c, b) if x["owner"]} == {"alice"}


def test_cli_hide_run_removes_it_from_feeds_kudos_and_comments_but_not_from_the_owners_history(client):
    a, b = login(client, "alice"), login(client, "bob")
    follow(client, a, b)
    rid = seed_run(client, b, at=T0 - 1)
    report(client, a, "run_card", rid)
    assert [i["id"] for i in get(client, a, "/feed").json()["items"]] == [rid]
    cli(client, "hide-run", rid)
    assert get(client, a, "/feed").json()["items"] == [] and get(client, b, "/feed").json()["items"] == []
    assert put(client, a, f"/runs/{rid}/kudos").status_code == 404
    assert get(client, a, f"/runs/{rid}/comments").status_code == 404
    assert [i["id"] for i in get(client, b, "/runs").json()["items"]] == [rid]  # the owner still sees it
    assert find(client, "reports")[0]["state"] == "hidden"
    cli(client, "unhide-run", rid)
    assert [i["id"] for i in get(client, a, "/feed").json()["items"]] == [rid]


def test_cli_dismiss_and_reports_listing(client):
    a, b = login(client, "alice"), login(client, "bob")
    report(client, a, "user", uid(b), "spam name")
    report(client, a, "cell", "8a1fae32006ffff", "weird")
    rid = str(find(client, "reports", {"kind": "user"})[0]["_id"])
    lines = cli(client, "reports")
    assert len(lines) == 2 and "spam name" in "".join(lines) and '"bob"' in "".join(lines) and "age=" in lines[0]
    assert len(cli(client, "reports", "--kind", "user")) == 1
    assert cli(client, "dismiss", rid) == [f"dismissed {rid}"]
    assert find(client, "reports", {"kind": "user"})[0]["state"] == "dismissed"
    assert len(cli(client, "reports")) == 1 and len(cli(client, "reports", "--state", "all")) == 2
    assert cli(client, "reports", "--state", "dismissed", "--limit", "5")[0].split()[1] == "dismissed"
    assert find(client, "moderation_log")[0]["action"] == "dismiss"
    assert report(client, a, "user", uid(b)).status_code == 202  # still one row: dismissed reports are not reopened
    assert count(client, "reports", {"kind": "user"}) == 1


def test_cli_errors_change_nothing_and_log_nothing(client):
    login(client, "alice")
    for argv in (["hide-comment", "nope"], ["hide-name", "nope"], ["hide-run", "nope"], ["dismiss", "zzz"],
                 ["dismiss", "0" * 24]):  # fmt: skip
        with pytest.raises(moderation.ModerationError):
            cli(client, *argv)
    assert count(client, "moderation_log") == 0
    with pytest.raises(SystemExit):
        cli(client, "bogus")


def test_cli_main_is_disabled_by_the_setting(monkeypatch, capsys):
    from app.config import Settings

    monkeypatch.setattr(moderation, "get_settings", lambda: Settings(admin_enabled=False))
    with pytest.raises(SystemExit) as e:
        moderation.main(["reports"])
    assert e.value.code == 2 and "disabled" in capsys.readouterr().err
