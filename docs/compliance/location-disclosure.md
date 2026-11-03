# In-app prominent disclosure for location

Google Play requires an in-app disclosure, shown **before** the Android location permission dialog, that is not buried in the privacy policy, uses the user's language, and requires an explicit action. Source: Google Play User Data policy ("Prominent Disclosure and Consent Requirement"). **[Unverified: I could not open the policy in this session; compare the final wording with the current policy text.]**

## Where and when to show it

- First time the user taps **Start run** (or any control that would trigger the location permission request), before calling the permission API.
- A full screen or dialog, not a toast. Two buttons: **Agree and continue** and **Not now**.
- Tapping **Not now** must NOT trigger the permission prompt, and the app stays usable (map, leaderboard) without recording.
- Show it again if the user later revokes the permission and tries to run.
- Do not request background location ("Allow all the time"). The run is recorded by a foreground service with a visible notification that the user starts. **[Verify with the mobile lane that the manifest has no ACCESS_BACKGROUND_LOCATION.]**

## Text (English, proposal; keep it this short)

**Title:** Looprun uses your location

**Body:**

> Looprun records your precise location **while you are recording a run**, including when the screen is off or you switch to another app. A notification stays visible the whole time, and recording stops when you press Stop.
>
> We use it to work out your route, the loops you close and the cells you claim, and to spot cheating. Your run is saved on our server. Other players see only which cells you own, never your route.
>
> We do not show ads and we do not share your location with anyone else.
>
> Read more in our Privacy Policy.

**Buttons:** `Agree and continue` | `Not now`

The words "Privacy Policy" must link to the hosted policy.

## Checks against the policy requirements

| Requirement | Covered by |
| --- | --- |
| Says what data is accessed and collected | "precise location", "saved on our server" |
| Says how it is used | "route, loops, cells, spot cheating" |
| Says whether it is shared | "do not share your location with anyone else" |
| Says it is collected while app is not visible | "when the screen is off or you switch to another app" |
| Shown before the permission prompt, explicit action | Agree button gates the prompt |

## German version (proposal, have a native speaker check)

**Titel:** Looprun verwendet deinen Standort

> Looprun erfasst deinen genauen Standort, **solange du einen Lauf aufzeichnest**, auch wenn der Bildschirm aus ist oder du eine andere App benutzt. Währenddessen bleibt eine Benachrichtigung sichtbar, und die Aufzeichnung endet, sobald du auf Stopp tippst.
>
> Wir nutzen den Standort, um deine Strecke, geschlossene Runden und eroberte Felder zu berechnen und um Betrug zu erkennen. Dein Lauf wird auf unserem Server gespeichert. Andere Spieler sehen nur, welche Felder dir gehören, nie deine Strecke.
>
> Wir zeigen keine Werbung und geben deinen Standort an niemanden weiter.
>
> Mehr dazu in der Datenschutzerklärung.

Buttons: `Zustimmen und weiter` | `Jetzt nicht`
