# Foreground service declaration (location)

Where: Play Console > Policy and programs > App content > Foreground service permissions (verify the name in your Console). Per Google's help page 13392821 (fetched 2026-11-03 by the builder and the verifier), for each declared type the form asks for: (1) the app functionality that uses the service, (2) the user impact if the system defers or interrupts it, (3) a link to a video showing the user steps that trigger it, (4) a use case. For the location type the page lists three presets: **background location updates (user-initiated sharing)**, **background location updates (navigation, for example ride tracking)** and **geofencing**. Exact form wording could not be confirmed.

## Technical facts the declaration relies on (verifier-confirmed in code, 2026-11-03)

- Manifest: service with `foregroundServiceType="location"`, permissions `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_LOCATION`, fine location, `POST_NOTIFICATIONS`. No `ACCESS_BACKGROUND_LOCATION`.
- The service starts only from the Run screen's Start button, after location permission is granted, and stops when the run ends.
- A persistent notification is shown while it runs. It has one **Stop** button, which stops and saves the run (the same as Stop in the app). The Stop button is built in code (phase 2) but has not been tried on a device yet; verify it in Gate 1.
- Reading the current position for the map or a home zone is done while the app is open and does not use the service.

## 1. Functionality (paste, proposal)

> Looprun is a running game. When the user taps Start run, the app starts a foreground service of type location that keeps the app alive and recording the user's GPS position for the duration of that run, shown by a persistent notification. The recorded track is uploaded to our server after the run to calculate the route, closed loops and map cells the user claims. The service runs only during a run the user started and stops when the user ends it, with the Stop button in the notification or in the app. Outside a run the app does not collect location in the background.

## 2. User impact if interrupted (paste, proposal)

> If the system stops or defers the service while the screen is off or another app is in front, GPS points are lost for that period. The run would have gaps, loops would not close, and the user would lose the cells they ran for. A run is a continuous outdoor activity the user is performing in real time, so it cannot be deferred or batched.

## 3. Use case

Choose **"Background location updates (navigation, for example ride tracking)"**, the nearest to tracking a route the user started. If the Console wording differs, or you prefer, enter manually: "User-initiated run (workout) tracking." **[Confirm against the live list.]**

## 4. Video shot list (30 to 60 seconds, real Android device, unlisted link)

1. Fresh install, sign in with Google.
2. The in-app location disclosure appears; tap Agree and continue; show the Android location dialog; allow while using the app; allow notifications.
3. Tap Start run; show the Run screen and the notification in the shade.
4. Press Home, lock the screen, wait 10 seconds, unlock: notification still there, track still growing.
5. Tap Stop in the notification (or return to the app and stop the run there); the run is saved and the notification disappears.
6. Show the result screen.

## Pre-submission checks

- [ ] Types in the manifest equal types in the Console.
- [ ] Video link works while logged out.
- [ ] Text equals real behaviour.
