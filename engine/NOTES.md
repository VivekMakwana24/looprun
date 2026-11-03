# Engine notes

## Spec questions

Decisions where ENGINE_SPEC.md was ambiguous. The public API is unchanged.

1. **Sort or drop out-of-order fixes?** The spec says "sort, drop out-of-order". I stable-sort by
   time, then drop duplicate timestamps (first one wins). Nothing is left out of order after
   sorting, so no separate drop step exists.
2. **Smoothing:** none. First and last points are therefore exactly the raw ones.
3. **Near-closure details.** The last cleaned point is joined to the *nearest* earlier vertex within
   `closure_tol_m`, but only vertices more than `closure_tol_m` of path length before the end are
   eligible. Without that guard every run would "close" onto its own last few metres.
   `repaired=True` (and the `near_closure_repaired` soft flag) is set only when the joined gap is
   over 10 m. A smaller gap is joined silently because it is GPS noise.
4. **Noise guards that are not in Config** (module constants in `loops.py`, the public Config is fixed):
   faces under 400 m2 and slivers with compactness 4*pi*A/P^2 under 0.05 are ignored silently.
   Without them an out-and-back on one road or a person standing still would produce dozens of
   `loop_rejected_small` flags, while the spec says they simply have no loop.
5. **Loops with no cell centre inside.** A loop above `min_loop_area_km2` (about 0.7 cell) can
   contain no cell centre, so `h3shape_to_cells` returns nothing. I then award the one cell holding
   the loop's representative point so an accepted loop is never worthless.
6. **Holes** are skipped (exterior ring only), as the spec says for v1. Loops are returned
   largest first and oriented counter-clockwise.
7. **Hard flags:** `RunResult.cells` is empty, but each `Loop.cells` stays filled for reviewers.
8. **`implausible_loop`** is raised when an accepted loop has area over 5 km2, or when a run that
   has an accepted loop contains a fix-to-fix edge over 2 km (checked on the cleaned path, not on
   the polygon edges, since those can be split by noding).
9. **`vehicle_speed`** uses path distance over the smallest window that spans at least
   `sustained_window_s`. Runs shorter than the window are never flagged for it. A `teleport` jump
   normally also trips `vehicle_speed`; both flags are reported.
10. **`faded_power` and freezes.** Literal reading: a freeze only matters while `freeze_until > now`.
    An expired freeze has no retroactive effect, so fading that was paused is *not* forgiven when
    the freeze ends. The spec gives no freeze start, so a "stopped clock" cannot be computed.
    Fading restarts from the original grace end. If the product wants paused time to be skipped,
    the server should shift `updated_at` forward by the freeze length when a freeze ends.
11. **`apply_claim` details.** Inputs are never mutated. Only the claimant's stored power and
    `updated_at` change (others fade lazily). Owner = highest faded power at `now`; ties among
    challengers go to the smaller user_id; the current owner keeps the cell on any tie. A missing
    owner entry counts as 0 power. Negative credit raises `ValueError`; zero credit for a user with
    no entry creates no entry. Zero credit for an existing entry still resets `updated_at` (literal spec).
12. **"Faster single run" in the simulation.** Credit is time based (`effort_credit`), so a faster
    run earns *less*. `tools/simulate.py` therefore shows two scenarios: the strongest single run the
    rules allow (90 min, the effort cap) and one lap at a third less time. The steady runner
    (4 runs over 3 weeks) wins both.
13. **`cells_for_bbox`** returns cells that *cover* the box (the box is grown by one cell edge so
    cells that overlap with their centre outside are included), sorted. It raises `ValueError` for
    an inverted box or more than 200,000 estimated cells. Intended for map viewports.
14. **`in_home_zone`** tests the cell centre against each zone radius.
15. **`gpx_to_fixes`** reads `<trkpt>` only. Accuracy comes from `<extensions><acc>`, else `hdop*5`,
    else 5 m. `<extensions><mock>true</mock>` sets `mock`. A point without `<time>` raises
    `ValueError`; DTD/entity declarations are rejected.
16. **Fixtures vs spec thresholds.** The car fixture drives at 9 m/s: a faster car would also trip
    the `teleport` limit (12.5 m/s), and the fixture is meant to isolate `vehicle_speed`.
    Projection for geometry is a local equirectangular plane around the first fix (error far
    below 1% at city scale).
17. **Short runs and `vehicle_speed` (E3, from the E1-E2 verification).** If the whole cleaned run
    spans less than `sustained_window_s`, the average speed of the whole run is compared with
    `max_sustained_speed_ms` instead (same threshold). This supersedes the "never flagged" part of
    #9. A fast burst inside a longer run is still only covered by the window rule and `teleport`.
18. **Signal gaps (E3).** There is no special handling: a gap is just a long hop between two fixes
    and the straight line across it counts towards distance and the loop outline. The speed rules
    use the implied speed, so a 40 s or 90 s gap at running pace raises nothing, while 5 km in 30 s
    raises `teleport`. Observed: the dropout and tunnel fixtures keep their loop (area above 0.14
    km2 because chords cut corners); `moving_seconds` includes gap time because the implied speed
    is above 0.5 m/s. The bowtie gives two loops of about 0.04 km2 each with their own cells.
