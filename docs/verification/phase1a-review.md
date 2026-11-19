# Phase 1a review (independent verifier)

Scope: server b0addb8..d74eb57, mobile up to 7efbf8f, checked against `docs/PHASE1_SPEC.md` (including its change log), `docs/CONTRACT.openapi.yaml`, D12 and `docs/compliance/*`. I ran the test suite: `pytest server engine` gives 350 passed and 10 skipped. CI is green. The points below are things CI does not catch. No code was edited.

## Blockers (ranked by user impact)

### B1. A hidden taker of a `cells_taken` notification can be identified: the notification id is the unsalted SHA-256 of the run id
- Where: `server/app/notifications.py:36-39` (`cells_taken_id`) and `server/app/social_api.py:584` (`id=r["_id"]` is sent to the victim).
- How it fails: victim V gets a `cells_taken` notification with `actor = null`. The taker T is hidden by `name_ok` because the cell is inside **T's home zone** or failed K-anonymity. Following someone is instant and needs no approval, so V can follow any candidate runner. V then reads their `GET /feed` cards, where `id` is the run id, computes `sha256(run_id)[:32]` and compares it with the notification id. A match names T. Together with the take-back cell coordinates, it also shows roughly where T's home zone is. This breaks the 0.1 rule that no "name, id or any hint is sent", and the change-log note on 7, whose stated goal was that the victim never learns the taker's run.
- Fix: make the id impossible to link. Either use an HMAC of `run_id:victim` keyed with a server secret (still deterministic, so the upsert stays idempotent), or store a random `public_id` with `$setOnInsert` and send that instead of `_id`. Add a test that no `/feed` card id hashes to any notification id.

### B2. Blocking someone shows whether they were the hidden taker of a `cells_taken` notification
- Where: `server/app/social.py:221-223` (`apply_block` deletes all notifications between the pair, `cells_taken` included). `server/app/social_api.py:609` and `:565` (list and unread count drop rows by `actor_id $nin blocked`).
- How it fails: V has a `cells_taken` row with `actor: null`. V blocks a suspect X. If the row disappears and the unread count drops, X was the hidden taker. V then unblocks; follows are not restored, but nothing else is lost. This works around home zone and K-anonymity protection with a single tap and needs no follow.
- Fix: for `type == "cells_taken"`, do not delete the row on block and do not filter it by actor. `name_ok` already treats a blocked taker as hidden, so the response shows `actor: null` with the cells counted in `cells_unattributed`. A taker who has been deleted already loses their events, so that part is unchanged. Add a test that blocking the hidden taker leaves the body and unread count of `GET /notifications` byte-identical.

### B3. Compliance docs are not updated for phase 1a. Spec section 10 is entirely open, so the app cannot go to testers or Play yet
`privacy-policy.md`, `data-safety-answers.md` and `tester-guide.md` say nothing about the social features. The exact edits needed are listed in "Compliance changes still needed" below. The Data safety form and the UGC declaration must match what the app now does before any build with these screens is uploaded, including the closed test.

## Follow-ups (not blocking)

1. Authors cannot remove their own content after losing access. `social_api.py:435` (`delete_comment`) and `:338` (`remove_kudos`) both call `visible_run` first. After an unfollow, a block, or a hidden run, the author gets a 404 and their comment or kudos stays visible to others. Suggested fix: allow the author to delete a comment by `author_id` (and `DELETE kudos` by its `_id`) without the view check.
2. A user cannot report someone they have blocked. `social_api.py:724` and `:736` return 404 when the pair is blocked. A user who blocks first, as the app's menu allows, cannot then report the person. Play expects reporting to remain possible. Suggested fix: allow `user` and `comment` reports from the blocker, keeping the 404 for a deleting or unknown target.
3. A user can undo a moderator's name hide with a rename. `hide-name` can be reversed by `PATCH /me`, since rename clears `name_hidden` as the spec says, at up to 5 renames per day. Consider a `name_locked` flag that the moderator sets, or a RUNBOOK note that repeat offenders need a manual action.
4. `GET /runs?status=bogus` returns FastAPI's default 422 body (`social_api.py:282`, `Literal`), not the `{"detail":{"code":...}}` shape from 0.2.
5. In the run card counts (`cards.py:30-35`), kudos from users who are being deleted are still counted until the deletion sweep finishes. Comments are filtered by `live_users`, kudos are not. This resolves itself, but filter kudos the same way for consistency.
6. `_apply` (`processing.py:~309`) writes the battle row even when the guarded `cells` write matched nothing, meaning a newer plan already holds the cell. That produces a phantom event, which is rare. Suggested fix: write the event only when the update matched or the insert succeeded.
7. Search does not apply NFC to `q` (`social_api.py:60`), while stored names are NFC. A decomposed accent in the query would miss.
8. Mobile: when run detail is opened from a kudos or comment notification there is no card (`run_detail_view_model.dart:37`), so the kudos button and numbers are missing. The contract has no single-card route. Either add `GET /runs/{id}/card` or open the run from history.
9. Mobile block confirmation text (`feed_screen.dart:35`) says "You will not see each other in the feed, comments or search". It should add that a blocked runner still appears as a map owner and on the leaderboard (spec 10, block explanation).
10. Mobile `markRead` sends `{"ids": []}` if it is ever called with an empty list, and the server rejects that with 422. Current callers guard against it, but the API helper should not send the request at all.
11. The `new_follower` and `kudos` notification ids contain user ids and run ids. That is fine today, since they are the caller's own run and the actor's own id. Keep the same rule (send no raw foreign run id) if new types are added.

## Verified correct (no action)
- **GPS and location:** `RunCard` and `build_cards` send no fixes, loop shapes, `claimed_cells`, start or end points, or `ended_at`. `/live` never names others. Take-back only returns the caller's former cells and never sends `run_id` or `taker_id`.
- **Publish delay:** applied in the feed (`processed_at <= now - delay`), in `can_view_run`, in battle windows (`at <= now - delay` for every viewer, including on own cards), in notification `visible_at`, and in profile `cells_held` and rank, which use the public counts.
- **Who gets named:** `name_ok_many` checks `k_ok`, the user's current home zones, `live_user`, `name_hidden` and blocks. It is used by cards, rivals, rivalry, take-back and notifications. Cells in the owner's home zone are removed from others' counts at read time.
- **Lists:** follower and following lists are owner-only routes. Blocks are enforced in both directions in the feed, comments, search, rivals, rivalry names, take-back names, profile (404) and follow. The map and leaderboard are left unchanged, as the spec decides.
- **Battle events:** `battle_events` rows are planned with the claim, written inside the region lock with `$setOnInsert` keyed `run:cell`, and `cells_taken` rows are written inside the lock before `_finish`, so a redelivery is safe. `scrub_claim_plans` clears `prev_owner` and the victim's event.
- **Cursors:** feed, history, lists, comments, blocks and notifications all use a stable `(sort key, _id)` cursor with `n+1` paging. The feed is stable for the reason given in spec 3.
- **DELETE /me:** removes follows, kudos, comments, notifications and blocks, deletes the user's takes and anonymises their losses. It runs before and again after the user document is deleted, so a race is covered. Redis is purged.
- **Moderation CLI:** every hide is read at request time, writes `moderation_log` and resolves the open reports on the target. `hide-name` invalidates the leaderboard cache.
- **Rate limits:** match 0.3.
- **Mobile:**
  - Every API path and field in `api_service.dart` and `social_models.dart` matches the YAML (`users` for search and rivals, `items` for pages, `cells` for take-back, `unread_count`).
  - Report and block are offered on the run card, the comment and the profile.
  - The list view models handle empty, error, offline and retry states.
  - The new repositories are built only from `apiServiceProvider`, and `provider_graph_test` checks the real providers, so I found no `CircularDependencyError` path. No view model watches a provider that is built from it.

## Compliance changes still needed (exact edits)

### `docs/compliance/privacy-policy.md`
- What we collect: add rows for follows (who follows whom, and when), kudos (who, which run), comments (text up to 500 characters, author, run, time), blocks, battle history (which cells changed hands between which players, and when; 90 days), notifications (60 days), and the display name you can change in the app (2 to 30 characters, checked against a word list).
- Line 52 ("What other players can see"): extend it as follows.
  - Your display name is visible to every signed-in player in search, on your profile, on the map and on the leaderboard.
  - Your followers and following counts are public. The lists themselves are visible only to you.
  - Followers see a summary of each accepted run: start time, distance, moving time, pace, cells claimed and taken, and the names of players you took cells from when those names are not hidden. They see it only after 30 minutes. They never see the route, the start point or the end point.
  - Comments and kudos are visible to anyone who can see the run.
  - The app has no profile photos.
- Retention: battle events 90 days; notifications 60 days; reports 180 days, including the text of a reported comment and the reported name or run summary; moderation log 365 days; follows, kudos, comments and blocks until the account is deleted.
- Deletion section: account deletion also removes follows, kudos, comments (yours, and others' comments on your runs), notifications, blocks and the cells you took from others. Cells others took from you stay counted for them without your name. Reports other people filed about you stay until they expire after 180 days.
- Reports: reports can now be about players, comments and run summaries, not only runs and cells. The operator sees the reason and a snapshot.
- Moderation: we may hide comments or runs and replace a display name with "Runner-xxxx". State the contact and appeal address and the response target (24 h). Link the community rules and Terms (no harassment, hate, sexual content, or personal data in names or comments).
- Legal basis: social features under Art. 6(1)(b); moderation and reports under Art. 6(1)(f). A lawyer should confirm.
- Blocking: a blocked player still appears as a map owner and on the leaderboard.

### `docs/compliance/data-safety-answers.md`
- Add "App activity > Other user-generated content" for comments, follows and kudos: collected, not shared, optional, App functionality. Check whether the console also needs "Messages > Other in-app messages" for comments.
- Personal info > Name: note that it can be edited and is shown to other users in the app (this does not count as shared). Purposes stay App functionality and Account management.
- Reports row: covers comment text and name snapshots; 180 days.
- Deletion answers: replace them with the updated list from the policy.
- UGC declarations: in-app reporting of users, comments and run cards; blocking; content removal through the moderation CLI with a 24 h target; Terms link.
- Listing and target audience: 18+ is unchanged. Update `listing.md` if its description mentions social features.

### `docs/compliance/tester-guide.md`
- Add a social test pass for two accounts:
  1. Rename yourself and check that a rejected name shows the generic message.
  2. Search for the other tester (at least 2 characters) and follow them.
  3. Check that their run appears in the Feed only about 30 minutes after it is processed.
  4. Give kudos, comment, then delete the comment.
  5. Check that the Inbox shows the follow, kudos and comment after 30 minutes.
  6. Take a cell from the other tester and check Battles (summary, rivals) and take-back on the victim's side after 30 minutes.
  7. Report a run card, a comment and a profile.
  8. Block, and check that the feed, comments, search and profile are hidden both ways while the map still shows the owner.
  9. Unblock.
- Add a known-limits note: no push in 1a, no photos, and a run opened from a notification shows comments only.
- Update `closed-test-checklist.md` with the same items.

## Verdict

Not ready to release. B1 and B2 are fixable in a small change and each needs one test. B3 is a documentation task. The rest of phase 1a matches the spec and contract: the privacy predicates are centralised and used everywhere, the pipeline changes are idempotent inside the lock, deletion is complete, and the app is wired correctly. After B1 to B3 are fixed, I expect to approve it; a re-check of the two notification tests is enough.

## Fixes: mobile (follow-ups 2, 8, 9, 10)

- **Follow-up 9 (block text):** one shared `blockExplanation` is used by all three block dialogs (run card, comment, profile). It says a blocked runner still appears as an owner on the map and on the leaderboard, and that they can still be reported from BLOCKED in YOU.
- **Follow-up 2 (report after block):** each row of the BLOCKED list has a Report button (`person_report_<id>`, 48 dp) that sends `kind: user`. It needs the server change in follow-up 2 to answer 202 for a blocked pair; until then the app shows the server's sentence.
- **Follow-up 8 (run from a notification):** run detail looks the run up in the first 3 history pages (`FeedRepository.ownCard`) and shows the run header with its numbers when found; no error when not found. It only helps for own runs, which is what kudos and comment notifications are about. A single-card route in the contract would still be cleaner.
- **Follow-up 10:** `ApiService.markRead` sends nothing for an empty id list.
- **Tests added:** history screen (statuses, empty, offline and retry, load more, open run), block text, report from BLOCKED, run detail from a notification, `ownCard`. The BOARD hub already had widget tests (three parts, lazy loading, 48 dp tabs) from the first push.

## Fixes (server, 2026-11-19)

Tests are in `server/tests/test_phase1a_review_fixes.py`; each fails on the code before the fix. Full suite: 362 passed, 10 skipped.

- **B1 fixed.** `cells_taken_id` is an HMAC of run id and victim, keyed with `notification_id_secret` (env `LOOPRUN_NOTIFICATION_ID_SECRET`, else the JWT secret). Tests: no feed card id hashes to the notification id, ids differ between secrets, victims and runs. Set the secret in production if the JWT secret is ever rotated, otherwise ids of rows written before the rotation no longer match and a redelivery could write a second row (rare, the rows expire after 60 days).
- **B2 fixed.** `apply_block` leaves `cells_taken` rows alone and the list and unread count no longer filter them by actor. Test: blocking the hidden taker leaves the body and unread count of `GET /notifications` byte-identical; blocking a named taker keeps the row and shows it unattributed.
- **B3 done.** `privacy-policy.md`, `data-safety-answers.md` (including the UGC declarations), `tester-guide.md` and `closed-test-checklist.md` updated as listed. The disclosure strings (`location-disclosure.md`) are untouched. New placeholder `[TERMS_URL]` (README). Wording is still a proposal for the lawyer and the Console.
- **F1 fixed** (comment and kudos self-delete after losing access), **F2 fixed** (a blocker can report the user and their comments), **F3 fixed** (rename keeps a moderator hide; contract text and spec log updated), **F4 fixed** (`bad_status` 422), **F5 fixed** (kudos of users being deleted are not counted), **F6 fixed** (`_apply` writes the battle row only when the guarded `cells` write took effect), **F7 fixed** (search query is NFC-normalised).
- **F11:** no new notification type was added, so nothing to change; the rule stays in the spec log.
- F8, F9, F10 are done by the mobile agent (section above).

