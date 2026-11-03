# Google Play Data safety form: answers for Looprun

Status: **PROPOSAL, unverified against the live Play Console form.** The form's categories and wording change; I could not open the Console. Follow this as a checklist, read each question as it appears, and correct this file when the wording differs. Answers must match the privacy policy and the real app behaviour. Google can reject an app whose answers are wrong.

Path in Play Console: **Policy and programs > App content > Data safety**.

## Section 1: Data collection and security

| Question | Answer |
| --- | --- |
| Does your app collect or share any of the required user data types? | **Yes** |
| Is all of the user data collected by your app encrypted in transit? | **Yes** (HTTPS to our server through Caddy; verify no cleartext HTTP in the release build) |
| Which account creation methods does your app support? | **OAuth** (Google sign-in). Not username/password. |
| Do you provide a way for users to request that their data be deleted? | **Yes** |
| Account deletion URL (shown when the app lets users create an account) | URL of the hosted privacy policy section "Deleting your account" (or a dedicated page). **Needed before submitting; the URL does not exist yet.** |
| Does the app let users delete some data without deleting the account? | Optional. Home zones can be edited; runs can only be removed with the account (in this version). Answer accordingly. |

## Section 2: Data types (tick only these; leave everything else unticked)

For each type below, the form asks: Collected? Shared? Processed ephemerally? Required or optional? Purposes.

"Shared" in Play's definition means transferred to a third party. Google's guidance says handing data to a service provider that processes it on your behalf (hosting, crash reporting) does **not** count as sharing. **[Verify this wording and the Firebase specifics in the current Play help article before submitting.]** Showing a display name to other players inside the app is not a transfer to a third party; mention it in the privacy policy (done).

| Category > Type | Collected | Shared | Ephemeral | Required / optional | Purposes (tick) |
| --- | --- | --- | --- | --- | --- |
| **Location > Precise location** | Yes | **No** | No (stored on server) | Required for runs (the app cannot score a run without it) | App functionality; Fraud prevention, security and compliance |
| **Personal info > Name** (Google display name) | Yes | **No** | No | Required | App functionality; Account management |
| **Personal info > Email address** | Yes | **No** | No | Required | App functionality; Account management |
| **Personal info > User IDs** (Google account ID, Looprun user ID) | Yes | **No** | No | Required | App functionality; Account management; Fraud prevention, security and compliance |
| **Health and fitness > Fitness info** (distance, moving time from runs) | Yes | **No** | No | Required | App functionality. **[PROPOSAL: Play may treat run statistics as fitness info; declaring it is the conservative choice.]** |
| **App activity > Other user-generated content** or **Other actions** (loops, claimed cells, reports you write, home-zone settings) | Yes | **No** | No | Required for loops/cells; reports optional | App functionality. **[Choose whichever Console type fits best; Play has no "runs" type.]** |
| **App info and performance > Crash logs** | Yes | **No** | No | Optional / not user-controllable (state honestly) | Analytics (stability); App functionality is not the right purpose |
| **App info and performance > Diagnostics** | Yes | **No** | No | Not user-controllable | Analytics |
| **Device or other IDs** (Firebase installation ID used by Crashlytics; Play Integrity token if used) | Yes **[verify against Firebase's data disclosure page]** | **No** | No | Not user-controllable | Analytics; Fraud prevention, security and compliance |

Do **not** tick: Approximate location (we do not collect a coarse-only location; the precise tick covers location), Financial info, Contacts, Photos and videos, Audio, Web browsing, Messages, Advertising ID. Confirm that the shipped app does not request or use any of these; if any SDK adds one, the answers change.

## Section 3: Review before saving

- [ ] The form's "Collected" list contains nothing the privacy policy omits, and the policy contains nothing the form omits.
- [ ] Every SDK in `mobile/pubspec.yaml` was checked for the data it collects (at minimum: Google Sign-In, Firebase Core, Crashlytics, any geolocator/background-service plugin).
- [ ] Release build is HTTPS only (no `usesCleartextTraffic`).
- [ ] Deletion path works in the release build and the web URL resolves.
- [ ] Re-answer this form whenever a new SDK or data field is added.

## Related declarations in App content (not part of Data safety)

- **Privacy policy URL**: required.
- **Ads**: No, the app contains no ads.
- **App access**: all features require Google sign-in; reviewers can use any Google account. Add instructions saying so.
- **Target audience and content**: adults only (see `listing.md`).
- **Health apps declaration / Health Connect**: the app is a running game; check whether Play shows a Health apps declaration for it and answer truthfully. **[Unverified.]**
- **Foreground service declaration**: see `foreground-service-declaration.md`.
- **Location permissions**: see `location-disclosure.md`.
