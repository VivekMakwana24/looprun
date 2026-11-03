# Looprun Privacy Policy

> **DRAFT. NOT LEGAL ADVICE. NOT YET REVIEWED.** Everything marked **[PROPOSAL]** is a choice the operator must confirm. Before launch, have a lawyer or your national data protection authority's guidance review this text (operators in Germany: also the Impressum duty under section 5 DDG). The text describes what the app and server do as of 2026-11-03; re-check it against the shipped build before publishing. Delete this box when done. Placeholders are listed in `README.md`.

Last updated: [POLICY_DATE]

## Who we are

Looprun is operated by [OPERATOR_NAME_AND_ADDRESS] ("we", "us"). Contact, including for privacy requests: [CONTACT_EMAIL].

## What Looprun does

Looprun is a running game. You run a closed loop outdoors, and the map cells inside your loop become yours. The app records your position while you run and sends the run to our server, which works out the loops, the cells and whether the run looks genuine.

## When the app reads your location

1. **During a run you start.** After you tap Start, the app records your precise position (latitude, longitude, time, accuracy) in a foreground service with a visible notification, also when the screen is off or you use another app. It stops when you stop the run in the app.
2. **Briefly, while the app is open and you use the map or home zones.** The app reads your current position once to centre the map when the map opens (only if you already allowed location), and once when you add a home zone, to place the zone at your position.

The app never reads your location in the background when no run is active, and it does not request "allow all the time" location.

## What we collect and store

| Data | Stored on our server? | Why |
| --- | --- | --- |
| **Run results**: start and end time, distance, moving time, outlines of the loops you closed, cells claimed, review flags | Yes | Show results, update the map and the weekly leaderboard |
| **Raw GPS points of a run** (position, time, accuracy, mock-location flag) | Used to process the run. After processing, they are **deleted for normal runs**. For runs held for review (for example flagged as vehicle speed, teleporting or mock location), the points are **kept** for a human check. See retention below. | Work out loops and cells; detect cheating |
| **Home zones** (centre point and radius, up to five) | Yes. A centre point is a precise location, usually your home; we store it. | So that your name never shows on cells in those zones |
| **Account data from Google sign-in**: Google account ID and display name (Google's first name if present, otherwise the full name, at most 40 characters) | Yes | Create and recognise your account; the name is shown to other players |
| **Your Google email address** | **No.** It is part of the Google sign-in token our server checks, but we do not store it. | Sign-in |
| **The map area you are viewing** (a bounding box, not your position) | Sent with each request to load cells; it is not stored as a history, but may appear in server access logs | Show claimed cells |
| **Reports you send** | The server can store them, but the app does not offer reporting yet | Abuse review |

We do not collect your contacts, photos, microphone or camera, and we do not use advertising identifiers. The app does not yet send crash reports or analytics.

## Third parties that see something

- **Google** processes your sign-in (Google Sign-In). Google may process data outside the EU under the safeguards it offers. **[Verify against Google's current terms.]**
- **Map provider [MAP_TILE_PROVIDER].** The map picture is downloaded from this provider's servers. It sees your device's IP address and which part of the map you view. It does not receive your GPS track. Until a production provider is chosen, development builds use the MapLibre demo server `demotiles.maplibre.org`, which is not meant for production. **[Decide the provider and complete this entry.]**
- **Amazon Web Services (Lightsail)** hosts our server in [HOSTING_REGION].
- **Planned, not in the app yet:** Firebase Crashlytics (crash reports) and Google Play Integrity (device check). When they ship, this policy will be updated first.

We do not sell your data, show ads or share your data with advertisers.

## What other players can see

- Your **display name** appears on the weekly leaderboard and, on the map, as the owner of cells you hold. A cell shows its owner's name only if enough different players are active nearby (currently at least 3); otherwise the owner is hidden.
- Cells inside any of your home zones never show you as the owner.
- **Delayed publishing:** when you take a cell, other players see the change after 30 minutes (you see it at once). Leaderboard totals are not delayed.
- Other players cannot see your route, GPS points or run times.

## Legal basis (GDPR) **[PROPOSAL, lawyer to confirm]**

- Running the game, your account and your runs: performing the contract (Art. 6(1)(b)).
- Precise location: you start a run yourself and grant the Android permission after seeing our in-app notice; we treat this as consent (Art. 6(1)(a)), which you can withdraw by stopping, revoking the permission or deleting your account.
- Anti-cheat and abuse review: legitimate interest in a fair game (Art. 6(1)(f)).

## How long we keep data

What the server does today:

- Raw GPS points of normal (accepted) runs: removed right after processing.
- Raw GPS points of runs held for review: kept until you delete your account. **This is longer than we want. Proposal: delete them after 90 days. Not yet implemented.**
- Run results, loop outlines, cell power and ownership: until you delete your account.
- Home zones: until you change them or delete your account.
- Reports: until the reporter deletes their account (**proposal: purge after 12 months, not yet implemented**).
- Server backups: kept 14 days, so deleted data can remain in a backup for up to that long.

## Deleting your account

In the app: Profile > Delete account. This permanently deletes your account, your runs, your home zones, your cell power and the reports you filed. Cells you owned are **handed to the strongest remaining player in that cell**, or become free if nobody else has any power there; your name is removed from them. Backups are overwritten within 14 days. You can also write to [CONTACT_EMAIL] from the address you use with Google and we will do it for you. Instructions are also available at [ACCOUNT_DELETION_URL].

## Your rights

If GDPR applies to you, you can ask for access, correction, deletion, restriction and a portable copy, object to processing based on legitimate interests, withdraw consent at any time, and complain to a data protection authority. Write to [CONTACT_EMAIL]; we aim to reply within one month.

## Children

Looprun is for adults (18 and over). We do not knowingly collect data from children; tell us at [CONTACT_EMAIL] and we will delete the account.

## Security

Data is sent over HTTPS. Access to the server is limited to the operator. No system is perfectly secure.

## Changes

If this policy changes in a way that matters, we will update the date and tell you in the app.
