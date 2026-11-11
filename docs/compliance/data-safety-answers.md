# Google Play Data safety form: answers for Looprun

Status: **PROPOSAL for the build as of 2026-11-03, unverified against the live Console form** (category names and wording change). Read each question as it appears and correct this file when it differs. Answers must match the privacy policy and the real behaviour. Placeholders: `README.md`.

Path: **Policy and programs > App content > Data safety**.

## Section 1: Data collection and security

| Question | Answer |
| --- | --- |
| Does your app collect or share any of the required user data types? | **Yes** |
| Is all of the user data collected by your app encrypted in transit? | **Yes, for release builds only.** The release workflow now refuses a non-`https://` `API_BASE_URL`. Debug builds default to cleartext emulator loopback; do not submit those. |
| Account creation methods | **OAuth** (Google sign-in) |
| Do you provide a way for users to request that their data be deleted? | **Yes** (in-app Profile > Delete account; plus a web page at the account deletion URL, which must be built, see below; an emailed request cannot be actioned because the server stores no email). Deletion removes the account, runs, raw GPS, home zones, cell power and filed reports (resumable two-step flow); cells pass to the strongest remaining player or become free. |
| Account deletion URL | [ACCOUNT_DELETION_URL] (**does not exist yet; to do for the operator**). Play requires a working web link, naming Looprun / the developer as on Google Play, that lets a user request deletion without the app. The policy section "Deleting your account" describes it, but the link must point to a page that actually lets the user start deletion; the realistic design is a small page with Sign in with Google that calls the same delete-account flow. Until it exists, do not submit the form. |
| Delete some data without deleting the account? | Home zones can be cleared in the app; runs cannot be deleted individually. |
| Data retention (not asked as a field, but must match the policy) | Raw GPS of accepted runs: deleted right after processing. Held or failed runs: 30 days, then automatic deletion. Reports: 180 days. Everything else until the account is deleted. Backups: 14 days. |

## Section 2: Data types (tick only these)

"Shared" in Play's definition means transferred to a third party; Google's guidance says handing data to a service provider that processes it on your behalf does not count. **[Verify wording in the current help article.]** Showing a display name to other players inside the app is not such a transfer (disclosed in the policy).

| Category > Type | Collected | Shared | Ephemeral | Required? | Purposes |
| --- | --- | --- | --- | --- | --- |
| **Location > Precise location** (run tracks; home-zone centre) | Yes | No | No | Required for runs | App functionality; Fraud prevention, security and compliance |
| **Personal info > Name** (Google first/display name, stored) | Yes | No | No | Required | App functionality; Account management |
| **Personal info > Email address** (arrives inside the Google ID token; verified, **not stored**) | Yes | No | **Yes** (processed, not retained) **[verify how Play defines ephemeral]** | Required | Account management |
| **Personal info > User IDs** (Google account ID, Looprun user ID) | Yes | No | No | Required | App functionality; Account management; Fraud prevention |
| **Health and fitness > Fitness info** (distance, moving time) | Yes | No | No | Required | App functionality. Conservative choice; Play may not require it. |
| **App activity > Other user-generated content / other actions** (loops, claimed cells, home zones) | Yes | No | No | Required | App functionality. Choose the type that fits best. |
| **App activity > Other user-generated content** (free-text reports of up to 500 characters about a run or a cell, sent with the user's account; kept 180 days) | Yes | No | No | Optional (the user chooses to send one) | App functionality; Fraud prevention, security and compliance |

**Removed from the earlier draft (not in the app yet):** Crash logs, Diagnostics, Device or other IDs (Crashlytics, Firebase installation ID, Play Integrity token). Add them back, and update the privacy policy, in the same release that adds those SDKs.

### Open decision: map tile provider

The app downloads map tiles from [MAP_TILE_PROVIDER] (development default `demotiles.maplibre.org`). That host sees the device IP and the viewed area. Decide with the provider's terms in hand whether to declare approximate location as **shared** (conservative) or to treat the provider as a service provider. Do not publish while this is open. **[Unverified Play interpretation.]**

On-device data: the raw GPS of finished runs stays in the app's local database until the account is deleted or the app uninstalled. Data that never leaves the device is not collected in Play's definition, so no row is added, but the privacy policy says so ("What stays on your phone"). The live-update WebSocket sends the viewed map area (not the user's position) and the auth token; this is covered by the rows above and adds no new data type.

Do **not** tick: Financial info, Contacts, Photos and videos, Audio, Web browsing, Messages, Advertising ID. Re-check every SDK in `pubspec.yaml` before submitting.

## Section 3: Review before saving

- [ ] Form and privacy policy list the same data.
- [ ] Release build is HTTPS only.
- [ ] Deletion works in the release build and the web URL resolves.
- [ ] Re-answer whenever an SDK or data field is added.

## Related declarations (App content)

- Privacy policy URL: [PRIVACY_POLICY_URL]. Ads: No. App access: any Google account works; say so. Target audience: 18+.
- Health apps declaration: check whether Play shows one for a running game. **[Unverified.]**
- Foreground service: `foreground-service-declaration.md`. Location disclosure: `location-disclosure.md`.
