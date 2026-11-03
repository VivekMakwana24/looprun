# Looprun Privacy Policy

> **DRAFT. NOT LEGAL ADVICE. NOT YET REVIEWED.**
> Everything marked **[PROPOSAL]** is a choice the operator has to confirm. Before launch, have a lawyer or your national data protection authority's guidance review this text (for operators in Germany: your state's data protection authority, and the Impressum duties in the Digital Services Act implementation law DDG section 5). The text below describes what the app is designed to do; engineering must confirm each statement against the shipped code and server before this is published. Delete this box when done.

Last updated: [DATE]

## Who we are

Looprun is operated by [OPERATOR_NAME_AND_ADDRESS] ("we", "us"). You can reach us at [CONTACT_EMAIL]. For privacy requests use the same address.

## What Looprun does, in one paragraph

Looprun is a running game. You run a closed loop outdoors, and the map cells inside your loop become yours. To do that, the app records your position during a run and sends the run to our server, which works out the loops, the cells and whether the run looks genuine.

## What we collect and why

| Data | When | Why | Where it goes |
| --- | --- | --- | --- |
| **Precise location (GPS points with time and accuracy)** | **Only while you are recording a run.** Not before you press start, not after you press stop. | To work out your route, distance, loops and the cells you claim, and to detect cheating (for example driving, teleporting, fake GPS). | Stored on our server after you finish the run. |
| **Run data**: start and end time, distance, moving time, loops, cells claimed, review flags | After each run | To show your results, update the map, and run the weekly leaderboard. | Our server |
| **Account data from Google sign-in**: Google account ID, display name, email address | When you sign in | To create and recognise your account. | Our server. Sign-in is processed by Google. |
| **Home zones you set (centre point and radius)** | Only if you set them | To hide your home area. Cells inside a home zone never show your name to others. These centre points are precise locations, so we store them on our server and treat them as personal data. | Our server |
| **Device integrity signal** | When you upload a run | To detect tampered devices or fake apps. Whether the signal is collected depends on the app version. **[PROPOSAL: confirm with the mobile and server code; remove this row if unused.]** | Our server, checked with Google's Play Integrity service |
| **Whether Android reported your location as "mock"** | With each GPS point | Anti-cheat | Our server |
| **Reports you send** (a run or a cell, with your text) | When you send one | To review abuse. | Our server |
| **Crash reports and diagnostics** | When the app crashes | To fix bugs. Includes device model, Android version, app version, a stack trace and an installation identifier. | Firebase Crashlytics (Google) |

We do **not** collect your contacts, photos, microphone or camera. We do **not** use advertising identifiers.

## What other players can see

- Your **display name** appears on the weekly leaderboard and as the owner of cells you hold.
- Cells inside any of your home zones never show you as the owner.
- **Delayed publishing [PROPOSAL]:** the map does not show a run's cells immediately; they appear after a delay of [DELAY, for example 30 minutes] so nobody can follow you live. **Engineering must confirm the real delay and that it is implemented.**
- Other players cannot see your route, your GPS points or your run times.

## What we do not do

- We do not sell your data.
- We do not show ads and we do not share your data with advertisers.
- We do not share your data with third parties for their own purposes. Service providers that process data for us are listed below.

## Service providers who process data for us

- **Google** (Google Sign-In; Firebase Crashlytics; Play Integrity if used). Google may process data in the US and other countries; transfers rely on the safeguards Google offers, such as the EU-US Data Privacy Framework and standard contractual clauses. **[Verify against Google's current terms.]**
- **Amazon Web Services (Lightsail)** hosts our server in [HOSTING_REGION, for example Frankfurt, eu-central-1]. **[PROPOSAL: confirm region.]**

## Legal basis (GDPR) **[PROPOSAL, lawyer to confirm]**

- Providing the game, your account and your runs: performing the contract you enter by using the app (Art. 6(1)(b) GDPR).
- Precise location during a run: you start the run yourself and grant the Android location permission after seeing our in-app notice; we treat this as your consent (Art. 6(1)(a)), which you can withdraw by stopping runs, revoking the permission or deleting your account.
- Anti-cheat and abuse review: our legitimate interest in a fair game (Art. 6(1)(f)).
- Crash reports: our legitimate interest in a stable app (Art. 6(1)(f)); some national rules on reading device data may require consent instead. **[Lawyer to decide; if consent is needed, add an opt-in in the app.]**

## How long we keep data **[PROPOSAL; engineering must implement or the text must change]**

- Raw GPS points of a run: [90 days] after upload, then deleted. Derived results (distance, loops, cells) stay until you delete your account.
- Account and cell ownership: until you delete your account.
- Home zones: until you change them or delete your account.
- Reports: [12 months].
- Crash reports: [90 days] (Crashlytics default retention; verify in Firebase).
- Server backups: kept for [14] days, so deleted data can remain in backups for up to that long.

## Deleting your account

In the app: Settings > Delete account. This permanently deletes your account, your runs, your home zones and your ownership of cells (the cells become unowned). Backups are overwritten within the period above. You can also ask by email at [CONTACT_EMAIL] using the Google account email you signed in with. **[PROPOSAL: a public web page or section with these instructions is also required by Google Play; this document can serve as that page once hosted.]**

## Your rights

If GDPR applies to you, you can ask for access to your data, correction, deletion, restriction, a copy in a portable format, and you can object to processing based on legitimate interests. You can withdraw consent at any time. You can complain to a data protection authority, for example in your country of residence. Write to [CONTACT_EMAIL]. We aim to answer within one month.

## Children

Looprun is for adults (18 and over). We do not knowingly collect data from children. If you think a child uses the app, email [CONTACT_EMAIL] and we will delete the account.

## Security

Data is sent over HTTPS. Access to the server is limited to the operator. No system is perfectly secure; we cannot promise absolute security.

## Changes

If we change this policy in a way that matters, we will update the date above and tell you in the app.

## Before launch (internal checklist, remove when done)

1. Fill in [OPERATOR_NAME_AND_ADDRESS], [CONTACT_EMAIL], [DATE], [HOSTING_REGION], [DELAY].
2. Confirm each retention period exists in code, or change the text.
3. Confirm the Crashlytics and Play Integrity statements match what the app does.
4. Have a lawyer or the data protection authority's guidance review it. Check whether a Records of Processing entry and a data processing agreement with each provider are needed.
5. Host it at a public URL (no login, no PDF) and enter that URL in Play Console.
