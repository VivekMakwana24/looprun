# In-app prominent disclosure for location

Google Play requires an in-app disclosure that is shown in normal use (not only in the privacy policy), describes the data collected, how it is used and whether it is shared, immediately precedes the runtime permission request, and requires an affirmative action. Checked against Google's User Data policy page by the verifier on 2026-11-03; the background-location help page additionally says the text must contain the word "location" and indicate background use.

## Flow (matches the code today)

- `AppGate` shows the disclosure screen right after sign-in, until the user accepts (stored as `location_disclosure_accepted_v1`).
- **Agree and continue** triggers the Android location prompt (then notifications). Nothing is requested before that tap.
- **No thanks, sign out** signs the user out. Looprun needs location to work, so there is no "use the app without location" path in this build.
- The app does not request background ("all the time") location.

## In-app screen text (must match code)

`mobile/lib/ui/disclosure/disclosure_screen.dart` shows exactly this (strings verified identical on 2026-11-04).

**App bar title:** `Your location`

**Heading:** `Before we ask for location access`

**What we collect**
> Your precise GPS position (latitude, longitude, time and accuracy) while you record a run, and whether your phone reports it as a mock location. We also read your current position once when the map opens, to centre it on you, and once when you add a home zone, to place it.

**Why**
> To find the loops you run, claim the map cells inside them, and check that runs are fair. Your track is sent to our server when you finish a run. The centre point of a home zone is also stored on our server, so your name stays hidden there.

**When**
> While a run is active, Looprun shows a notification and keeps recording even if you lock the screen or switch to another app. Outside a run it reads your location only for the map and home zone actions above. It never records in the background when no run is active.

**Sharing**
> We do not show ads and we do not share your location with anyone. Other players see which cells you own, never your route. The map images are loaded from [MAP_TILE_PROVIDER], which can see your IP address and the area you view.

**Your control**
> You can hide places such as your home with Home zones in Profile, and delete your account and runs at any time.

**Link:** a `Privacy Policy` button that opens a dialog showing [PRIVACY_POLICY_URL] as selectable text. It does not open the browser (no `url_launcher` yet), so the link is not tappable; adding `url_launcher` is recommended before release.

**Buttons:** `Agree and continue` (key `disclosure_agree_button`) | `No thanks, sign out` (key `disclosure_decline_button`)

`[MAP_TILE_PROVIDER]` and `[PRIVACY_POLICY_URL]` must be replaced by the real values at build time or in code before release.

## Checks against the policy requirements

| Requirement | Covered by |
| --- | --- |
| Says what is collected | "precise GPS position", the map and home-zone reads |
| Says how it is used | "Why" |
| Says whether it is shared | "Sharing" |
| Mentions use while the app is not visible | "even if you lock the screen or switch to another app" |
| Shown before the permission prompt, explicit action | Agree button triggers the prompt |

## German version (proposal; have a native speaker check)

**Titel:** Dein Standort. **Überschrift:** Bevor wir den Standortzugriff erfragen

- **Was wir erfassen:** Deinen genauen GPS-Standort (Breite, Länge, Zeit und Genauigkeit), während du einen Lauf aufzeichnest, und ob dein Telefon ihn als Mock-Standort meldet. Außerdem lesen wir einmal deinen aktuellen Standort, wenn die Karte geöffnet wird (zum Zentrieren), und einmal, wenn du eine Heimzone anlegst.
- **Wozu:** Um deine Runden zu finden, die Felder darin zu erobern und die Fairness der Läufe zu prüfen. Deine Strecke wird nach dem Lauf an unseren Server gesendet. Der Mittelpunkt einer Heimzone wird ebenfalls auf unserem Server gespeichert, damit dein Name dort verborgen bleibt.
- **Wann:** Während eines Laufs zeigt Looprun eine Benachrichtigung und zeichnet weiter auf, auch bei gesperrtem Bildschirm oder in einer anderen App. Außerhalb eines Laufs wird der Standort nur für die genannten Karten- und Heimzonen-Aktionen gelesen, nie im Hintergrund.
- **Weitergabe:** Wir zeigen keine Werbung und geben deinen Standort an niemanden weiter. Andere Spieler sehen nur, welche Felder dir gehören, nie deine Strecke. Die Kartenbilder kommen von [MAP_TILE_PROVIDER], dort sind deine IP-Adresse und der angezeigte Kartenausschnitt sichtbar.

Buttons: `Zustimmen und weiter` | `Nein danke, abmelden`
