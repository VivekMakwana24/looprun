# Review of the attached "Territory Run" spec (v0.1) against Looprun

The spec says it is an original design built from the public product description. We use it as a checklist of ideas and failure modes, not as code or assets to copy. Looprun keeps its own design (H3 cells instead of free polygons, effort-based ownership, trust features).

## Adopted

| Spec idea | Where it lands in Looprun |
| --- | --- |
| "Stopping" state that waits for the last sample to be flushed before the run is finished (fixes the "run disappeared" bug) | Mobile: recorder gets a `stopping` state; finish only after the Drift write completes |
| Tricky replay tracks: tunnel, GPS dropout, bowtie route | Engine E3: new fixtures and tests (dropout, tunnel, bowtie) |
| Concurrent captures of the same area serialized by region | Server: claim lock per H3 res-5 parent region (sorted acquisition), instead of one global lock |
| Show the rule that caused a result, in the UI | Already planned: flag codes map to plain-language reasons in the run result screen |
| Run analytics events without raw location | v1.1 backlog (Crashlytics/analytics not in the app yet) |
| Launch metrics (closed loop in first week, runs lost under 1%, flagged under 5%, map update under 10 s) | Used as targets in the tester guide and the case study |
| Offline test: kill the app mid-run, reboot, confirm recovery | Already in the field checklist; add reboot case |

## Considered and not adopted for v1 (with reason)

| Spec idea | Why not now |
| --- | --- |
| Free polygons with PostGIS | We chose H3 cells: simpler ownership, cheaper map, easier privacy rules (decision in plan "Core rules") |
| Background location "Always" and iOS | Plan is Android-first and avoids background location to skip the extra Play declaration |
| Home zone samples never uploaded | Stronger privacy, but trimming breaks loop closure for runs starting at home. Ours uploads, hides on the map, and stores the track only briefly. Revisit if testers ask |
| Auto-pause with segment breaks | Needs a segment marker in the contract and engine; v1.1 |
| Chunked batch upload with checksums | Single upload capped at 20000 fixes (more than 5 hours at 1 Hz) is enough for v1; mobile downsamples above the cap |
| Monotonic clock plus wall-clock anchor | Good idea, v1.1 |
| Closure within 25 m and 800 m minimum | Ours: 80 m repair tolerance and 0.01 km2 minimum; to be tuned on real tracks from the testers |
| Decay off by default | Ours: slow decay with grace period is core to the "low upkeep" differentiator |
| Challenges, expeditions, premium, social feed | Out of scope |

## Open questions in the spec that we have already answered

1. City: Frankfurt area for the test. 2. Decay: yes, slow, with grace and freeze. 3. Cycling: no. 4. Clubs: no. 5. Map provider: open decision (production tile host). 6. Language: English, German disclosure draft.
