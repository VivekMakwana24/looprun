# Google Play Data safety form: answers for Looprun

Status: **PROPOSAL for the build as of 2026-11-19 (Phase 1a social features included), unverified against the live Console form** (category names and wording change). Read each question as it appears and correct this file when it differs. Answers must match the privacy policy and the real behaviour. Placeholders: `README.md`.

Path: **Policy and programs > App content > Data safety**.

## Section 1: Data collection and security

| Question | Answer |
| --- | --- |
| Does your app collect or share any of the required user data types? | **Yes** |
| Is all of the user data collected by your app encrypted in transit? | **Yes, for release builds only.** The release workflow now refuses a non-`https://` `API_BASE_URL`. Debug builds default to cleartext emulator loopback; do not submit those. |
| Account creation methods | **OAuth** (Google sign-in) |
| Do you provide a way for users to request that their data be deleted? | **Yes** (in-app Profile > Delete account; plus a web page at the account deletion URL, which must be built, see below; an emailed request cannot be actioned because the server stores no email). Deletion removes the account, runs, raw GPS, home zones, cell power, filed reports, follows, kudos, comments (written by the user and left by others on their runs), notifications, blocks and the cells the user took from others (resumable two-step flow); cells pass to the strongest remaining player or become free. Reports others filed about the user stay until they expire after 180 days. |
| Account deletion URL | [ACCOUNT_DELETION_URL] (**does not exist yet; to do for the operator**). Play requires a working web link, naming Looprun / the developer as on Google Play, that lets a user request deletion without the app. The policy section "Deleting your account" describes it, but the link must point to a page that actually lets the user start deletion; the realistic design is a small page with Sign in with Google that calls the same delete-account flow. Until it exists, do not submit the form. |
| Delete some data without deleting the account? | Home zones can be cleared in the app; runs cannot be deleted individually. |
| Data retention (not asked as a field, but must match the policy) | Raw GPS of accepted runs: deleted right after processing. Held or failed runs: 30 days, then automatic deletion. Battle history: 90 days. Notifications: 60 days. Reports (including the copy of a reported comment, name or run summary): 180 days. Moderation log: 365 days. Everything else, including follows, kudos, comments and blocks, until the account is deleted. Backups: 14 days. |

## Section 2: Data types (tick only these)

"Shared" in Play's definition means transferred to a third party; Google's guidance says handing data to a service provider that processes it on your behalf does not count. **[Verify wording in the current help article.]** Showing a display name to other players inside the app is not such a transfer (disclosed in the policy).

| Category > Type | Collected | Shared | Ephemeral | Required? | Purposes |
| --- | --- | --- | --- | --- | --- |
| **Location > Precise location** (run tracks; home-zone centre) | Yes | No | No | Required for runs | App functionality; Fraud prevention, security and compliance |
| **Personal info > Name** (Google first/display name, stored; the user can edit it in the app and it is shown to other users in the app, which is not sharing) | Yes | No | No | Required | App functionality; Account management |
| **Personal info > Email address** (arrives inside the Google ID token; verified, **not stored**) | Yes | No | **Yes** (processed, not retained) **[verify how Play defines ephemeral]** | Required | Account management |
| **Personal info > User IDs** (Google account ID, Looprun user ID) | Yes | No | No | Required | App functionality; Account management; Fraud prevention |
| **Health and fitness > Fitness info** (distance, moving time) | Yes | No | No | Required | App functionality. Conservative choice; Play may not require it. |
| **App activity > Other user-generated content / other actions** (loops, claimed cells, home zones) | Yes | No | No | Required | App functionality. Choose the type that fits best. |
| **App activity > Other user-generated content** (free-text reports of up to 500 characters about a run, a cell, a run summary, a comment or a player, with a copy of the reported text, name or summary, sent with the user's account; kept 180 days) | Yes | No | No | Optional (the user chooses to send one) | App functionality; Fraud prevention, security and compliance |
| **App activity > Other user-generated content** (comments of up to 500 characters, follows, kudos and blocks; battle history 90 days, notifications 60 days; the rest until the account is deleted) | Yes | No | No | Optional (the user chooses to use the social features) | App functionality |

**Removed from the earlier draft (not in the app yet):** Crash logs, Diagnostics, Device or other IDs (Crashlytics, Firebase installation ID, Play Integrity token). Add them back, and update the privacy policy, in the same release that adds those SDKs.

### Open decision: map tile provider

The app downloads map tiles from [MAP_TILE_PROVIDER] (default `OpenFreeMap (tiles.openfreemap.org)`). That host sees the device IP and the viewed area. Decide with the provider's terms in hand whether to declare approximate location as **shared** (conservative) or to treat the provider as a service provider. Do not publish while this is open. **[Unverified Play interpretation.]**

On-device data: the raw GPS of finished runs stays in the app's local database until the account is deleted or the app uninstalled. Data that never leaves the device is not collected in Play's definition, so no row is added, but the privacy policy says so ("What stays on your phone"). The live-update WebSocket sends the viewed map area (not the user's position) and the auth token; this is covered by the rows above and adds no new data type.

Check whether the Console also wants **Messages > Other in-app messages** for comments (they are short texts on a run, visible to anyone who can see the run, not private messages; **[verify in the current form]**). Tick it if the form's definition covers them.

Do **not** tick: Financial info, Contacts, Photos and videos, Audio, Web browsing, Advertising ID. Re-check every SDK in `mobile/pubspec.yaml` before submitting.

## Section 3: Review before saving

- [ ] Form and privacy policy list the same data.
- [ ] Release build is HTTPS only.
- [ ] Deletion works in the release build and the web URL resolves.
- [ ] Re-answer whenever an SDK or data field is added.

## User-generated content (UGC) declarations

Looprun has comments, display names and run summaries seen by other users, so answer the UGC questions as follows. **[Verify the exact wording in the Console.]**

- In-app reporting of users, comments and run summaries: **yes** (Report on a profile, a comment and a run card).
- Blocking of users: **yes** (profile and run card menus).
- Content removal: the operator hides comments, runs and names with a moderation tool on the server (`docs/RUNBOOK.md` 4c) and answers reports within a **24 hour** target; appeals go to [CONTACT_EMAIL].
- Rules: the Terms ([TERMS_URL]) forbid harassment, hate, sexual content and personal data in names or comments. Comments and names pass a word list before they are accepted.
- Listing and target audience: 18+ is unchanged. If `listing.md` describes social features, keep it in line with this file (it does not mention them today).

## Related declarations (App content)

- Privacy policy URL: [PRIVACY_POLICY_URL]. Ads: No. App access: any Google account works; say so. Target audience: 18+.
- Health apps declaration: check whether Play shows one for a running game. **[Unverified.]**
- Foreground service: `foreground-service-declaration.md`. Location disclosure: `location-disclosure.md`.
