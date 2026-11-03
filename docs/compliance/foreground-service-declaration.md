# Foreground service declaration (location)

Where: Play Console > Policy and programs > App content > **Foreground service permissions** (name as of my last check; **verify in your Console**). Per Google's help page "Understanding foreground service and full-screen intent requirements" (fetched 2026-11-03), for each declared foreground service type the form asks for: (1) a description of the app functionality that uses the service, (2) the user impact if the system defers or interrupts the task, (3) a link to a video showing the user steps that trigger the feature, and (4) a specific use case from a preset list, or manual entry if none fits. Exact form wording and the preset list could not be confirmed; read the form and adapt.

## Technical facts the declaration relies on (verify with the mobile lane)

- Manifest: `<service android:foregroundServiceType="location" ...>` plus permissions `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_LOCATION`, `ACCESS_FINE_LOCATION`, `POST_NOTIFICATIONS`.
- The service is started only when the user presses **Start run** while the app is visible, and stops when the user presses **Stop** (or the app ends the run).
- A persistent notification is shown while it runs, with a Stop action.
- No `ACCESS_BACKGROUND_LOCATION`.

## 1. Description of the functionality (paste, proposal)

> Looprun is a running game. When the user taps Start run, the app starts a foreground service of type location that records the user's GPS position for the duration of the run. The service shows a persistent notification and stops when the user taps Stop. The recorded track is uploaded to our server to calculate the route, closed loops and map cells the user claims. Location is not collected outside an active, user-started run.

## 2. User impact if interrupted (paste, proposal)

> If the system stops or defers the service while the screen is off or the app is in another app, GPS points are lost for that period. The run would have gaps, loops may not close, and the user would lose the cells they ran for. A run is a continuous outdoor activity that the user is watching in real time, so it cannot be deferred or batched.

## 3. Use case selection

Choose the closest preset. Candidates: **"Navigation or ride tracking"** (active tracking of a journey the user started) is the nearest to a run tracker. If the list has a fitness or activity tracking entry, prefer that. If nothing fits, enter manually: "User-initiated run (workout) tracking." **[Verify the preset list in the Console.]**

## 4. Video (required) shot list

Screen recording, 30-60 seconds, shown from a real Android device, with link (unlisted YouTube or similar, no login needed):

1. Fresh install, sign in with Google.
2. Tap Start run: show the in-app location disclosure (see `location-disclosure.md`), tap Agree, show the Android permission dialog, allow while using the app.
3. Show the run screen and the persistent notification in the notification shade.
4. Press Home, lock the screen, wait 10 seconds, unlock: the notification is still there and the track continues.
5. Return to the app, tap Stop: the notification disappears.
6. Show the result screen.

## Pre-submission checks

- [ ] Declared types in the manifest equal the types declared in the Console.
- [ ] Video link works while logged out.
- [ ] Declaration text equals real behaviour (no background start, no hidden tracking).
