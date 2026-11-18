# Phase 1 spec: social + battles (1a), and the 1b list

Status: spec for implementers, 2026-11-18. Contract: `docs/CONTRACT.openapi.yaml` (additive; every old field kept). Decision: D12.
Owner decisions (fixed): feed is followers-only; route lines are never shown to others; everything free; no profile photos.
No implementation code here. File names below are suggestions.

## 0. Cross-cutting rules (apply to every feature)

### 0.1 Vocabulary and predicates (one shared module, `app/social.py`; every route uses these, none re-implements them)

| Name | Definition |
| --- | --- |
| `delay` | `settings.publish_delay_seconds` (LOOPRUN_PUBLISH_DELAY_SECONDS, 1800 s). Tests set 0 and also test with a positive value. |
| `blocked(a,b)` | a row in `blocks` for (a,b) or (b,a). |
| `live_user(u)` | user exists and not `deleting`. Every other user shown anywhere must pass it. |
| `display_name(u)` | `u.name`, or `"Runner-" + u._id[:4]` when `u.name_hidden`. Replaces `u["name"]` everywhere a name is shown to someone else (cellview, leaderboard, live frames, all new routes). The owner sees their own real name (`GET /me`, `name_hidden` flag). |
| `published(run, viewer)` | `viewer == run.user_id` or `now >= run.processed_at + delay`. |
| `can_view_run(viewer, run)` | run `status == accepted`, not `hidden` (moderation), owner `live_user`, not `blocked`, and (viewer is owner, or viewer follows owner and `published`). Used by kudos, comments, reports of `run_card`. Not visible: 404 (never 403, so existence leaks nothing). |
| `event_visible(ev)` | `now >= ev.at + delay`, for every viewer including the two parties. Nobody learns of a battle before the map shows it. |
| `name_ok(ev, user_id)` | the named user may be shown by name for event `ev`: `ev.k_ok` is true (K-anonymity of the cell neighbourhood, computed once at claim time, see 0.4), the cell is not in any of that user's home zones (checked at read time against current zones), the user is `live_user`, `name_hidden` is false, and the pair (viewer, user) is not blocked. If false the opponent is counted as unattributed/hidden and no name, id or any hint is sent. |

### 0.2 API conventions for new routes
- Error body `{"detail": {"code": "<slug>", "message": "<text>"}}`. Old routes keep their old bodies.
- All new routes: 401 (bad token), 403 (account `deleting`) exactly like existing routes (`auth.current_user`). A user being deleted is invisible to others at once.
- Lists: `limit` 1..50 (default 20), opaque `cursor` (base64 of the sort key + `_id`), `next_cursor` null at the end. Bad cursor/limit: 422 `bad_cursor`.
- No count in any list response (no total) except where the schema says so.

### 0.3 Rate limits (existing `hit_rate_limit` fixed-window Redis counter; 429 + Retry-After)

| Scope | Limit | Setting |
| --- | --- | --- |
| `follow` (follow + unfollow) | 100 / hour | `social_follow_rate` |
| `kudos` (give + remove) | 120 / hour | `social_kudos_rate` |
| `comment` | 30 / hour and 5 / minute (two scopes) | `social_comment_rate`, `social_comment_burst` |
| `report` | 20 / hour (existing, shared by all kinds) | unchanged |
| `block` | 30 / hour | `social_block_rate` |
| `rename` | 5 / 24 h | `social_rename_rate` |
| `search` | 30 / minute | `social_search_rate` |
| read routes (feed, lists, notifications, battles, profile) | 120 / minute per user, one shared scope `social_read` | `social_read_rate` |

Caps (409 with the named code): following 500 (`follow_limit`), blocks 500 (`block_limit`), comments per run 200 (`comment_limit`).

### 0.4 Changes to the existing claim pipeline (the only edits to engine-adjacent server code)
1. `_plan`: each outcome gains `prev_owner` (the `current` owner before this claim; null if unowned) and `k_ok` (neighbourhood user count `>= privacy_min_users`, from `cellview._users_in_neighbourhoods` for the changed cells that had a previous owner; one batched call per run). The plan gains `claimed_cells` (cell ids where `out.new_owner == user_id`) and keeps it after `outcomes` is unset.
2. `_apply`: when `o["changed"]` and `prev_owner` is not null and differs from the taker, upsert one `battle_events` row (`_id = "<run_id>:<cell>"`, `$setOnInsert`) after the `cells` write. Idempotent under redelivery.
3. Inside `_claim_cells`, after the apply loop and before `_finish`: upsert one `cells_taken` notification per victim (see 7). Idempotent by `_id`. (Not after `_finish`: a crash there would lose it because the run is already finished.)
4. `_finish` copies `claimed_cells` into the run document (accepted runs only).
5. `scrub_claim_plans` also clears `prev_owner`. A taker's or victim's deletion handling is in 9.
6. `runs` documents gain `claimed_cells: [h3]`, `hidden: bool` (moderation). Runs without `claimed_cells` (made before phase 1) are never shown in others' feeds; the owner's history shows their stored counts with `taken_from` empty and `taken_from_hidden = cells_taken_from_others`.
7. Own cells are not battle events when the owner re-claims them, when a cell is first claimed (no previous owner), or when account deletion reassigns cells (`_reassign_cells`): only a run claim that flips ownership from another live user is a battle.

### 0.5 New settings (config.py, all env-overridable `LOOPRUN_*`)
`social_*` rates above; `feed_window_days` 90; `battle_retention_days` 90; `notification_retention_days` 60; `social_max_following` 500; `social_max_blocks` 500; `social_max_comments_per_run` 200; `profanity_list_path` (default `app/data/blocked_terms.txt`); `admin_enabled` (see 8.3).

### 0.6 Collections and indexes (created in `ensure_indexes`; all new)

| Collection | `_id` | Fields | Indexes | Retention |
| --- | --- | --- | --- | --- |
| `follows` | `"<follower>:<followee>"` | follower_id, followee_id, at | unique (follower_id, followee_id); (followee_id, at -1, _id -1); (follower_id, at -1, _id -1) | until either user is deleted |
| `kudos` | `"<run_id>:<user_id>"` | run_id, run_owner_id, user_id, at | (run_id); (user_id); (run_owner_id) | until run or user deleted |
| `comments` | uuid hex | run_id, run_owner_id, author_id, text, created_at, hidden (bool) | (run_id, created_at 1, _id 1); (author_id); (run_owner_id) | until run or author deleted |
| `blocks` | `"<blocker>:<blocked>"` | blocker_id, blocked_id, at | unique (blocker_id, blocked_id); (blocked_id) | until either user deleted |
| `battle_events` | `"<run_id>:<cell>"` | run_id, cell, at, taker_id, victim_id, k_ok, expire_at | (victim_id, at -1); (taker_id, at -1); (run_id); TTL `expire_at` (=0 s) | 90 days (TTL); also account deletion (9) |
| `notifications` | deterministic, see 7 | user_id, type, actor_id, run_id, comment_id, comment_preview, created_at, visible_at, read, expire_at | (user_id, visible_at -1, _id -1); (user_id, read, visible_at); (actor_id); TTL `expire_at` | 60 days (TTL) |
| `reports` (existing) | ObjectId | + target_owner_id, snapshot, state in {open, hidden, dismissed}, resolved_at | + (state, created_at); unique partial (reporter_id, kind, target_id) where kind in {user, comment, run_card}; existing TTL | 180 days (unchanged) |
| `moderation_log` | ObjectId | at, admin, action, target_kind, target_id, report_ids | TTL 365 days | 365 days |
| `users` (existing) | | + name_lower, name_hidden (bool) | + (name_lower) | with the account |
| `runs` (existing) | | + claimed_cells, hidden | + (user_id, status, processed_at -1, _id -1); (user_id, started_at -1, _id -1) | with the account |

Migration (one-off script `server/scripts/backfill_social.py`, idempotent): set `users.name_lower`, `users.name_hidden=false`; create indexes. Existing runs stay as described in 0.4.6.

## 1. Public profile and rename

| Route | Notes |
| --- | --- |
| `GET /users/{id}` | `Profile`: id, name, cells_held, weekly_rank, followers_count, following_count, joined_at (`users.created_at`), is_me, is_following, follows_me. 404 `not_found` for unknown, deleting, blocked either way. |
| `PATCH /me` `{display_name}` | trims, collapses inner whitespace, 2..30 characters (Unicode code points), no control or zero-width characters, must pass `profanity.is_allowed(name)`. Sets `name`, `name_lower`, clears `name_hidden`. 422 `name_rejected` (message generic: do not say which rule failed for profanity). 429 per 0.3. Returns `{user}`. |
| `GET /me` | additive `name_hidden`. |

- No profile photos, no bio, no avatar upload. The app draws initials from the name. No image moderation is needed and none is built.
- Counts: `followers_count`/`following_count` are `count_documents` on the follow indexes (no denormalised counters, so nothing can drift). Excludes deleting users and blocked pairs is unnecessary because blocking deletes the rows.
- `cells_held`: other users see what a stranger sees on `GET /cells` (published, named, not home zone, not K-hidden: the existing `_public_counts`); own profile shows the live `owner_id` count. `weekly_rank`: refactor the leaderboard sort into `leaderboard.weekly_rows(res, viewer)` returning the full sorted list (the route still truncates to 100); rank = position there, null if absent. Same cache key.
- Profanity hook: `app/profanity.py: is_allowed(text: str) -> bool`. Default: blocklist file, matching after lowercasing, accent stripping, leetspeak mapping (0->o, 1->i/l, 3->e, 4->a, 5->s, @->a, $->s) and removing separators; whole-token and substring match for listed stems. The hook is the only place to swap in a service later. `auth.upsert_user` applies it to the Google name too: a rejected or shorter-than-2 Google name is stored as `"Runner-" + id[:4]`. Existing names of 31..40 characters stay until renamed. Comments are not auto-filtered in 1a (setting `filter_comments`, default off, calls the same hook).
- Privacy: the display name is visible to every signed-in user (search, leaderboard, map, profiles). No opt-out in 1a. Profile never shows runs, times, home zones or locations.

Acceptance tests
- Profile of self and other returns exactly the listed fields (no extra keys: assert the key set); `joined_at` equals `created_at`.
- Profile of a blocked user (both directions), a deleting user, an unknown id: identical 404 bodies.
- `cells_held` of another user excludes cells inside that user's home zone, K-hidden cells, and cells still inside the publish delay; the caller's own count includes them.
- `weekly_rank` of a user below position 100 is still returned.
- Rename: 1 and 31 characters, control characters, zero-width space, all-whitespace -> 422; `"  Mia   K "` stored as `"Mia K"`; 6th rename in 24 h -> 429.
- Profanity: listed word, leetspeak variant, spaced-out variant rejected; ordinary names such as "Scunthorpe Sam" accepted (test the Scunthorpe case explicitly; decide with the blocklist, document the choice).
- Rename clears `name_hidden`; a hidden name appears as `Runner-xxxx` in `/cells`, leaderboard, `/live` frames, search (absent), profile, comments, cards.
- Rename updates `name_lower` so prefix search finds the new name and not the old.

## 2. Follow, lists, search, rivals

| Route | Behaviour |
| --- | --- |
| `PUT /users/{id}/follow` | idempotent upsert; response `{is_following:true, followers_count}`. 404 unknown/deleting/blocked; 422 `self`; 409 `follow_limit`; 429. Creates a `new_follower` notification (7) only when the row was inserted. |
| `DELETE /users/{id}/follow` | idempotent; removes the row; keeps the `new_follower` notification (already sent). |
| `GET /me/followers`, `GET /me/following` | own lists only (other people's lists are not exposed in 1a); newest first, cursor on (`at`, `_id`); items `UserListItem` with `is_following`, `follows_me`. Skip deleting users. |
| `GET /users/search?q=` | `name_lower >= q' and < q'+"￿"` range query (q' = lowercased, trimmed q), limit 20, excludes self, deleting, `name_hidden`, blocked either way. No cursor. 422 if len < 2 or > 30. Regex special characters are never interpreted (range query, no regex). |
| `GET /me/rivals` | distinct opponents (taker or victim) over `battle_events` of the last 30 days where `event_visible` and `name_ok` for that opponent; most recent first; max 50; `UserListItem`. |

Privacy: follow is instant, no approval (public accounts). Following gives access to the followee's accepted run cards (after the delay), nothing else. Existing runs become visible on follow (within `feed_window_days`).

Acceptance tests
- Follow twice -> one row, one notification; unfollow twice -> 200 both times.
- Follow self -> 422; follow unknown/deleting/blocked -> 404; the 501st follow -> 409 `follow_limit`.
- Lists: pagination returns each item once across pages with no gaps when new follows arrive between pages (cursor stability); order newest first.
- Search: "ma" finds "Mia", "mark", not "Amy"; case-insensitive; excludes self, blocked (either way), `name_hidden`, deleting; `q="m"` 422; `q=".*"` matches only names starting with ".*".
- Rivals: A takes cells from B 10 days ago and C takes from A 40 days ago -> A's rivals = [B]. Opponent with `k_ok=false` or in a home zone is not listed. Event younger than the delay is not listed. Blocked opponent not listed.

## 3. Activity feed

`GET /feed` returns `RunCard` items.

Source and filter (one query): runs with `status = accepted`, `hidden != true`, `processed_at >= now - feed_window_days`, and either `user_id = me`, or `user_id in followees` (max 500) with `processed_at <= now - delay` and `claimed_cells` present. Sort `processed_at desc, _id desc`, cursor on that pair. Because the delay is a constant offset on `processed_at`, a run that becomes visible later always sorts above everything already paged (no run is skipped by a cursor). Drop users that fail `live_user` or `blocked`.

Card fields (`RunCard`): `id, user, started_at, distance_m, moving_seconds, pace_s_per_km (moving_seconds / (distance_m/1000), null if distance < 100 m), cells_claimed, cells_taken, taken_from [{user, cells}], taken_from_hidden, loop_count (len(loops)), kudos_count, kudos_by_me, comment_count`. `status` is present on every card (always `accepted` in the feed).

Rules for others' cards (the viewer is not the owner):
- Home zones: cells in any of the owner's current home zones are excluded from `cells_claimed` and `cells_taken` (computed at read time from `claimed_cells` and the run's events with `in_home_zone`). A run with all claimed cells in zones shows 0/0 and still appears (distance and time reveal no place).
- `taken_from`: group the run's `battle_events` by `victim_id` for events passing `name_ok(ev, victim)`; the rest sum into `taken_from_hidden`. `cells_taken = sum(taken_from.cells) + taken_from_hidden`. Events not yet `event_visible` count in neither (cannot happen for others since `published` is later than `at`, but own cards need it).
- Own cards (feed and history): full `cells_claimed`/`cells_taken` (home-zone cells included), names follow `event_visible` and `name_ok`, so even the runner learns a victim's name only when the map would show it.
- Never present: fixes, loop polygons, loop cells, `claimed_cells`, start/end points, `started_at`-derived location, flags, integrity data, `ended_at`. (`started_at` is the only timestamp.)
- Counts: `kudos_count` = kudos rows for the run excluding blocked pairs with the viewer; `comment_count` = non-hidden comments from non-blocked live authors. Computed per page with two batched aggregations (no per-card queries).
- Page assembly is batched: one `users` query, one `battle_events` `$in run_ids` query, two aggregations.

Acceptance tests
- Feed contains own runs at once and followees' runs only after the delay (run with positive delay: absent at `processed_at + delay - 1 ms`, present at `+ delay`).
- Not followed -> absent; unfollow -> disappears; follow -> older accepted runs within 90 days appear; older than 90 days absent.
- `pending_review`, `rejected`, `processing` runs and `hidden` runs absent; legacy runs without `claimed_cells` absent for others, present for the owner.
- Response JSON (recursively) contains none of the keys `fixes, lat, lng, polygon, boundary, cells, claimed_cells, flags, ended_at, integrity_token, start, end`; assert on a fixture with all of them stored.
- Home zone: a run whose claimed cells are all in the owner's zone shows 0 claimed to a follower and the true number to the owner; changing the zone changes the follower's number on the next read.
- Victim named only if `k_ok`, not in victim's home zone, `name_hidden` false, live, not blocked; otherwise counted in `taken_from_hidden`; sum identity `cells_taken == sum(taken_from) + taken_from_hidden`.
- Block either way removes the card at once; deleting owner removes it.
- Pagination: 55 runs, limit 20: three pages, no duplicates, no gaps, strictly descending; a new run arriving between page 1 and 2 does not duplicate or skip.
- `pace_s_per_km` null under 100 m; correct otherwise.
- No N+1: the page query count is constant (assert with a Mongo command counter) for 1 and 50 cards.

## 4. Kudos and comments

| Route | Behaviour |
| --- | --- |
| `PUT /runs/{id}/kudos` | idempotent give; requires `can_view_run`; 404 otherwise; 422 `own_run`. Returns `{kudos_by_me, kudos_count}`. Inserts a `kudos` notification to the run owner only on first insert. |
| `DELETE /runs/{id}/kudos` | idempotent remove; deletes the notification `kudos:<run>:<user>`. |
| `GET /runs/{id}/comments` | oldest first, cursor; requires `can_view_run` (owner included); excludes hidden comments (the author still receives their own with `hidden: true`), authors that are not `live_user`, blocked pairs with the viewer. `can_delete` true for the author and for the run owner. |
| `POST /runs/{id}/comments` `{text}` | trimmed, 1..500 code points, no control characters; `can_view_run`; 409 `comment_limit`; 429 (hour and minute scopes). Creates a `comment` notification for the run owner unless the author is the owner. |
| `DELETE /runs/{id}/comments/{cid}` | author or run owner; 403 `forbidden` otherwise; idempotent 204 when absent; removes the comment's notification. |

Privacy: commenting needs the same view right as seeing the card, so only followers (and the owner) can comment; a comment shows the author's `display_name`. "Toggle" in the app = PUT/DELETE (idempotent, safe to retry).

Acceptance tests
- Kudos twice -> count 1; remove twice -> count 0; own run -> 422; non-follower, unpublished (inside delay), pending_review, hidden, blocked, other-user's-invisible run -> 404 (same body as unknown run).
- Unfollowing removes the ability to comment/kudo but existing comments stay visible to others who can see the run.
- Comment: 500 chars ok, 501 -> 422, whitespace-only -> 422; 201st on a run -> 409; 6th in a minute -> 429.
- Delete: author ok; run owner can delete any comment on their run; third party -> 403; repeated delete -> 204.
- Comment by a blocked user is invisible to the blocker and the blocked; hidden comment invisible to others, visible with `hidden:true` to the author.
- Counts on cards match lists after each operation; self-comment creates no notification.

## 5. Run history

`GET /runs?limit&cursor&status`: the caller's own runs, `started_at desc, _id desc`, `RunCard` with `status` (processing, accepted, pending_review, rejected). Own numbers (see 3, own-card rules); `distance_m`, `moving_seconds`, `pace_s_per_km` null while processing; `cells_*` 0 unless accepted. `GET /runs/{id}` is unchanged (flags stay there). Moderation-hidden runs still show to their owner.

Acceptance tests
- Only own runs; another user's run id never appears; order and pagination as in 3.
- `status` filter works; unknown status -> 422.
- A `pending_review` run has `cells_claimed = 0`.
- Card for a still-`processing` run has null metrics and `status = processing`.

## 6. Battles

Source of truth: `battle_events` (0.4, 0.6). One row per cell that flips from a live other user to the taker. `at` = the plan's `now`. Visible to anyone only when `event_visible`.

| Route | Result |
| --- | --- |
| `GET /battles/summary` | last 7 days: `taken` (events where I am taker), `lost` (I am victim), `net = taken - lost`, `battles` = distinct run ids involved. Counts include events whose opponent name is hidden. |
| `GET /battles/rivalry?days=30` | per opponent with `name_ok`: `taken`, `lost`, `net`, `last_battle_at`, `is_following`; sorted by `taken+lost` desc then `last_battle_at` desc; max 50. Events failing `name_ok` are summed in `unattributed {taken, lost}`. |
| `GET /battles/take-back` | events where I am victim, last 7 days, `event_visible`, whose cell is currently owned by someone else (`cells.owner_id != me`) or missing, newest first, max 500, one row per cell (latest event). Row: `cell, lat, lng, boundary` (from the engine: `cell_centre`, `cell_boundary`, D10 shape), `lost_at`, `lost_to` (UserRef only if `name_ok(ev, taker)`, else null). The taker's run id is never sent. |

Privacy notes
- A hidden owner (K-anonymity, home zone of the named user, deleted, `name_hidden`, blocked) is never named in any battle response; counts survive, identity does not. `k_ok` was fixed at claim time (conservative: a cell that became K-visible later stays unnamed in history).
- The take-back list only contains cells the caller owned, so it reveals no new location. The home zone of the taker does not hide the cell (it is the caller's former cell) but hides the taker's name.
- Events about the same cell are not merged across runs for counts, only for the take-back list.
- Live `/live` frames and the map are unchanged.

Acceptance tests
- Run B takes 5 of A's cells: A.lost = 5, B.taken = 5 only after the delay; before: both 0.
- First claim of an unowned cell, a self re-claim, and a deletion reassignment create no event.
- Redelivered run (apply twice) creates exactly one event per cell.
- Rivalry: totals, net sign, `last_battle_at`, sort; `days=0` and `91` -> 422; events older than `days` excluded; 7-day window for summary/take-back is exact (event at 7d - 1 s included, 7d + 1 s excluded).
- Take-back: a cell A won back is absent; a cell lost twice appears once with the latest `lost_at`; each row has a 6-point `boundary` (5 for a pentagon) and the engine centre; `lost_to` null for K-hidden, taker-home-zone, deleted, `name_hidden` and blocked takers; no `run_id`/`taker_id` key anywhere.
- Taker's home zone changed later: name hidden on next read.
- TTL index exists on `battle_events.expire_at`; events older than 90 days are not returned even before the TTL monitor runs.

## 7. Notifications inbox (no push in 1a)

| Type | Created | `_id` (idempotent upsert) | `visible_at` | Payload at read time |
| --- | --- | --- | --- | --- |
| `cells_taken` | in `_claim_cells`, one per victim per run | `cells_taken:<run>:<victim>` | event `at` + delay | actor (taker) only if at least one event passes `name_ok`; `cells` = events passing `name_ok`, `cells_unattributed` = the rest. If `cells == 0`: `actor = null` |
| `new_follower` | on first follow insert | `new_follower:<followee>:<follower>` (a re-follow after unfollow does not notify again) | now + delay | actor |
| `kudos` | on first kudos insert | `kudos:<run>:<giver>` (deleted when kudos is removed) | now + delay | actor, run_id |
| `comment` | on comment insert, not for self-comments | `comment:<comment_id>` (deleted with the comment; deleted when moderation hides it) | now + delay | actor, run_id, comment_id, `comment_preview` (first 80 chars) |

| Route | Behaviour |
| --- | --- |
| `GET /notifications` | `visible_at <= now`, newest first by (`visible_at`, `_id`), cursor; response includes `unread_count`; `created_at` field = `visible_at`. Filtered at read: blocked actors, actors not `live_user`. |
| `GET /notifications/unread-count` | count of `read = false` and `visible_at <= now`, same filters. |
| `POST /notifications/read` `{ids}` or `{all:true}` | marks the caller's own only (foreign ids silently ignored); exactly one of `ids`/`all` else 422. 204. |

Privacy: nothing is delivered before the publish delay, so a notification cannot be used to see a change before the map would. No push in 1a, so no notification content leaves the server. Retention 60 days (TTL `expire_at`). Blocking deletes notifications between the pair.

Acceptance tests
- Each type appears only after `visible_at`; `unread_count` ignores not-yet-visible ones.
- `cells_taken`: one notification per run per victim even if 200 cells; re-processing the same run does not duplicate or reset `read`.
- Named vs unattributed split matches the rules of 0.1; all-hidden -> `actor = null`.
- Kudos removed -> notification gone; comment deleted/hidden -> gone; follow, unfollow, follow -> still one `new_follower`.
- Mark read: own ids, foreign ids ignored, `all`, both/neither -> 422; unread count updates.
- Blocked actor's notifications absent; deleted actor's absent.
- Pagination stable across `visible_at` ties.

## 8. Report, block, moderation

### 8.1 Block
| Route | Behaviour |
| --- | --- |
| `PUT /users/{id}/block` | idempotent; 204. In one flow: insert block; delete follows both ways; delete kudos both ways (rows where giver/owner are the pair); delete notifications between the pair (either direction, any type); 404 unknown/deleting; 422 `self`; 409 `block_limit`; 429. |
| `DELETE /users/{id}/block` | idempotent 204; follows are not restored. |
| `GET /me/blocks` | `[UserRef]` newest first, cursor. A deleted user disappears. |

Effects, enforced by `blocked()` in every read: no feed cards, no comments (both directions), absent from search, rivals, rivalry and take-back names, profile 404, no follow, no new notifications. Known non-effects (decided): the public map owner names, the weekly leaderboard and `/live` still show a blocked player (public game state; hiding them would break the map). The blocked user is not told.

### 8.2 Report
`POST /reports` kinds: `run`, `cell` (unchanged) plus `user`, `comment`, `run_card`.
- `user`: target = user id; `comment`: comment id; `run_card`: run id. For the new kinds the target must be visible to the reporter (`can_view_run` for run_card and for the run of a comment, user not blocked/deleting, comment not hidden), else 404 `not_found`. Not allowed against yourself (422).
- Stored: existing fields plus `target_owner_id` (user id of the reported person), `snapshot` (user: current name; comment: text; run_card: the card JSON as the reporter saw it, no GPS), `state: open`. The snapshot keeps evidence after the target is deleted; retention stays 180 days.
- Same reporter + kind + target again: 202 no-op (unique partial index). 20/hour limit unchanged (shared).
- App obligation (Play UGC policy): report and block entries on profile, comment, and run card.

### 8.3 Moderation path (no public admin API)
CLI `python -m app.moderation` run on the host (RUNBOOK section to add), no HTTP admin surface in 1a:

| Command | Effect |
| --- | --- |
| `reports [--state open] [--kind K] [--limit N]` | list with target snapshot, reporter id, reason, age |
| `hide-comment <id>` / `unhide-comment <id>` | `comments.hidden`; deletes the comment's notification; resolves matching open reports to `hidden` |
| `hide-name <user_id>` / `unhide-name <user_id>` | `users.name_hidden` |
| `hide-run <run_id>` / `unhide-run <run_id>` | `runs.hidden` (removed from feeds, kudos, comments for others; the owner still sees it in history) |
| `dismiss <report_id>` | state `dismissed` |

Every action writes `moderation_log` (admin = OS user, action, target, report ids). Target response time to adopt in the operator's Terms: 24 h. Hidden state is read-time everywhere (no cache to invalidate except the leaderboard cache key, which `hide-name` also deletes).

Acceptance tests
- Block: follows both ways removed, kudos and notifications between the pair removed, profile 404 both ways, search/feed/comments/rivals exclude, follow attempt 404; unblock leaves follows removed; block twice -> 204; 501st block -> 409.
- Block does not change `/cells` or the leaderboard (documented non-effect).
- Report kinds: each new kind stores the right `target_owner_id` and snapshot; report of an invisible comment/run -> 404; duplicate -> 202 and a single row; 21st per hour -> 429; self-report -> 422; old kinds `run`/`cell` behave exactly as before (regression).
- Moderation CLI: each command changes state, writes `moderation_log`, and the effect is visible through the API on the next request (comment gone for others and present with `hidden:true` for the author; hidden name appears as `Runner-xxxx` on `/cells`; hidden run gone from the feed but present in the owner's history).
- Rate limits: follow (101st), kudos (121st), comment (31st/hour, 6th/minute), block (31st), search (31st/minute) return 429 with `Retry-After`.

## 9. Account deletion (`delete_account`, resumable)

Add after cell reassignment and before the user document is deleted. Every step is `delete_many`/`update_many` (idempotent, safe to repeat after a 503):

| Data | Action |
| --- | --- |
| `follows` | delete where follower_id or followee_id = user |
| `kudos` | delete where user_id = user, or run_owner_id = user |
| `comments` | delete where author_id = user, or run_owner_id = user (their runs go away) |
| `notifications` | delete where user_id = user or actor_id = user |
| `battle_events` | delete where taker_id = user (their takes disappear from others' history and take-back); set `victim_id = null` where victim_id = user (taker's counts survive, name gone). Null victims never name anyone and never appear in `/me/rivals`. |
| `blocks` | delete where blocker_id or blocked_id = user |
| `reports` | existing: delete reports filed by the user. Reports about the user stay until their 180-day TTL (unchanged; snapshot of that user's name goes with them at expiry) |
| `moderation_log` | unchanged (ids only, 365 days) |
| Redis | existing `purge_redis` pattern covers rate-limit keys; the leaderboard cache is already purged |

During `deleting`, `live_user` already hides the user from every new route. `DELETE /me` contract description is extended (additive text).

Acceptance tests
- After `DELETE /me`: no document in `follows, kudos, comments, notifications, blocks` references the user in any field; `battle_events` has no `taker_id` or `victim_id` equal to the user; reports by them are gone; reports about them remain.
- Other users' feeds, comment counts, kudos counts, followers_count, notification lists no longer include them; a take-back row whose taker was deleted has `lost_to: null`.
- Deletion interrupted after the follows step (simulate failure) and repeated: ends clean, no duplicates, 204.
- A concurrent `PUT /follow` to a deleting user returns 404 and leaves no row after deletion completes (also a follow created in the race window is removed by the final repeat-safe sweep: run the follow/kudos/comment cleanup once more after the user document check).

## 10. Privacy policy and Play Data safety (checklist only; do not edit those files in this task)

Privacy policy (`docs/compliance/privacy-policy.md`)
- [ ] "What we collect": add follows (who follows whom), kudos, comments (text, up to 500 chars, author, run), blocks, battle history (which cells changed hands between whom, 90 days), notifications (60 days), the display name you can change.
- [ ] "What other players can see": display name visible to all signed-in users (search, profile, map, leaderboard); followers see your accepted run summaries (time, distance, moving time, pace, cells claimed/taken, names of players you took cells from when not hidden) after 30 minutes; never route, start or end point; comments and kudos visible to people who can see the run.
- [ ] State: no profile photos; followers/following counts public; own lists private.
- [ ] Retention list: battle events 90 days, notifications 60 days, reports incl. comment text snapshots 180 days, moderation log 365 days; follows/kudos/comments/blocks until deletion.
- [ ] Deletion section: add follows, kudos, comments, notifications, blocks, battle events (the cells you took from others stay with their new owners; your name is removed from history).
- [ ] Reports text: now also users, comments, run cards; reason may be shown to the operator.
- [ ] Moderation: content may be hidden, display names replaced; contact/appeal address; community rules and Terms (no harassment, hate, sexual content, personal data in names or comments) referenced in app and listing.
- [ ] Legal basis: add the social features under Art. 6(1)(b) and moderation under 6(1)(f); lawyer to confirm.
- [ ] Block explanation: blocked users still appear as public map owners.

Play Data safety (`docs/compliance/data-safety-answers.md`)
- [ ] Add "App activity > Other user-generated content" for comments (and, if the console offers it, "Messages > Other in-app messages"; verify taxonomy) and for follows/kudos (collected, not shared, optional, App functionality).
- [ ] Personal info > Name: purposes add "Developer communications: no"; keep "App functionality, Account management"; note it is shown to other users in-app (not "shared").
- [ ] Reports row: reason text now also covers comments snapshots; retention 180 days.
- [ ] Deletion answers: updated list of what deletion removes.
- [ ] UGC policy declarations: in-app reporting, blocking, content removal path, Terms; "App access" note unchanged.
- [ ] Listing/target audience: 18+ unchanged; update description if it mentions social features.
- [ ] Re-check consistency policy <-> form <-> behaviour before the production release.

## 11. Phase 1b (list only, specify later)
1. Run beacon (share a live position with a chosen contact during a run; needs its own consent, privacy and retention design).
2. In-run audio and haptic cues (cells entered, loop closed, rival nearby), mobile only plus any server hints.
3. FCM push for the notification types of 7 (needs a Firebase project, device-token collection, policy and Data safety update; publish-delay rule applies to push too).

## 12. Implementation order (suggested)
1. 0.4 pipeline changes + `battle_events` + migration/indexes, with tests (highest risk).
2. `social.py` predicates, profile/rename/search/follow, blocks.
3. Feed/history/cards, kudos/comments.
4. Notifications, battles routes.
5. Reports/moderation CLI, deletion changes, rate limits, privacy checklist.

## Change log (implementation notes and additive contract corrections)

- 2026-11-18, contract: every phase 1a read route (`GET /runs`, `/users/{id}`, `/me/followers`, `/me/following`, `/me/rivals`, `/feed`, `/runs/{id}/comments`, `/battles/*`, `/notifications*`, `/me/blocks`) now lists `429`. The spec (0.3) already rate limits them (`social_read`, 120 per minute) but the contract did not say so. Additive.
- 2026-11-18, 1.0: the 2..30 character rule and the profanity hook are applied to Google names in `auth.upsert_user` only for `google:` subjects. Dev logins (`LOOPRUN_DEV_AUTH`, tests) keep the typed name, because the existing tests use one-letter dev names.
- 2026-11-18, 1.0: the rename limit (`rename`, 5 per 24 h) counts every `PATCH /me` attempt that reaches the route, accepted or rejected, so the profanity filter cannot be probed without limit.
- 2026-11-18, 0.4: `k_ok` counts the taker among the users around the cell (after the claim they hold power there, exactly as `GET /cells` will see it). The battle row is planned with the claim (`outcome.event`) and written by `_apply`, so `_apply`'s signature is unchanged.
- 2026-11-18, 0.5: `admin_enabled` (default true) only gates the moderation CLI; the CLI has no network surface.
