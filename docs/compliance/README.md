# Compliance pack

Everything here is a draft written from the code as of 2026-11-03 (verifier report `docs/verification/O1-C1.md`). It is not legal advice. Items that depend on code that does not exist yet are listed under "Not in this build" and in `docs/verification/O1-C1-followups.md`.

| File | Purpose |
| --- | --- |
| `privacy-policy.md` | Public privacy policy (host it at a public URL) |
| `data-safety-answers.md` | Play Console Data safety form, as a checklist |
| `location-disclosure.md` | In-app prominent disclosure; contains the exact screen text the mobile code must show |
| `foreground-service-declaration.md` | Play Console foreground service (location) declaration |
| `listing.md` | Store listing copy, content rating notes |
| `tester-guide.md` | Instructions for closed-test testers |
| `closed-test-checklist.md` | The 12 testers / 14 days rule and dates |

## Consolidated placeholder list (fill all of these before launch)

| Placeholder | Meaning | Used in |
| --- | --- | --- |
| `[OPERATOR_NAME_AND_ADDRESS]` | Legal name and postal address of whoever runs Looprun (also needed for the German Impressum) | privacy-policy |
| `[CONTACT_EMAIL]` | Public contact and privacy request address | privacy-policy, listing, tester-guide |
| `[POLICY_DATE]` | Date of the policy version | privacy-policy |
| `[HOSTING_REGION]` | AWS region of the Lightsail instance (for example Frankfurt, eu-central-1) | privacy-policy |
| `[MAP_TILE_PROVIDER]` | Production map tile / style provider (name and host) chosen for `MAP_STYLE_URL` | privacy-policy, location-disclosure, data-safety-answers |
| `[PRIVACY_POLICY_URL]` | Public URL of the hosted privacy policy | tester-guide, location-disclosure, Play Console |
| `[ACCOUNT_DELETION_URL]` | **Operator to-do.** Public web page where a user can start account deletion without the app (Play rule), naming Looprun / the developer. Needs a Sign in with Google step because the server stores no email; the policy section alone is not enough | privacy-policy, data-safety-answers, Play Console |
| `[OPT_IN_LINK]` | Closed-test opt-in URL from Play Console | tester-guide |
| `[TEST_START]`, `[TEST_END]` | First and last day of the 14-day test | tester-guide |
| `[FEEDBACK_CHANNEL]` | Where testers send bug reports besides email | tester-guide |

Values that are facts and not placeholders: owner-name delay on the map is 30 minutes (server default `publish_delay_seconds` = 1800; production compose does not override it); backups are kept 14 days (`deploy/backup.sh`, `KEEP_DAYS`); raw GPS of held/rejected/failed runs expires after 30 days (`LOOPRUN_FIXES_RETENTION_DAYS`, TTL index on `run_fixes`); reports expire after 180 days (TTL index on `reports`). If you change these settings, change the privacy policy too.

## Not in this build (do not advertise or test these yet)

- (Done in code, phase 2, not yet device-tested) Live map updates over WebSocket (`/v1/live`, token sent in the first message) and report-a-cell / report-a-run with a free-text reason (`POST /v1/reports`). The privacy policy, Data safety answers and tester guide now describe them; do not advertise them in the store texts until the device test.
- A web page for requesting account deletion without the app (Play requirement; see below).
- Firebase, Crashlytics and Play Integrity (planned; the app sends no crash reports and sends `integrity_token` as null).
- A tappable privacy policy link in the disclosure screen: the app shows the URL in a selectable dialog only (no `url_launcher`). The hosted policy must still be reachable from the app per Play; add `url_launcher` before release if possible.
- iOS.

When one of these ships, update the matching documents (privacy policy, data safety, listing) in the same release.

## Account deletion without the app (open requirement)

The server stores only `google_sub` and a display name, no email. A deletion request by email therefore cannot be matched to an account, and it would be unsafe to act on one (anyone could name someone else). The compliance texts say: in-app Profile > Delete account is the primary route; reinstall and sign in is the fallback; the web page at `[ACCOUNT_DELETION_URL]` must verify ownership by Sign in with Google and then run the existing delete flow. Building that page (a static page plus a call to the delete endpoint with a Google ID token) is **not done and is a to-do for the operator**; the Data safety form cannot be submitted truthfully until it exists.

## Verify-before-submitting items

Play Console wording (Data safety categories, foreground-service presets, IARC questions, character limits, Health apps declaration) was not checked against the live Console. Each file marks what is unverified.
