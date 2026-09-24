# Decision Challenges — feat-one-shot-8688-deploy-script-tests-timeout

Persisted by `soleur:plan` (headless pipeline) for `soleur:ship` Phase 6 to render into
the PR body and file as `action-required` issues where appropriate.

## Taste — job growth trend vs. smallest-fix scope (engineering-CTO lens)

- **Class:** taste (named-panel axis; not mechanical).
- **Observation:** `deploy-script-tests` has been re-derived upward five times in ten
  weeks (8 → 12 → 14 → 15 → 20 → 27 → now 35 min) because suites keep landing without the
  re-derivation the ceiling block requires. A structural answer — sharding the ~160
  suites across jobs (the issue's option c) — would shrink the per-job ceiling and the
  blast radius of any single slow step.
- **Why not applied:** the operator's stated direction for #8688 was the smallest fix
  that turns main green with attribution; ADR-238 records "splitting multiplies fixed
  cost"; and a split does not buy attribution (a hang in either half still cancels
  anonymously without step bounds anyway).
- **Re-evaluation trigger:** if ceiling re-derivations become a recurring chore (e.g. two
  more within a quarter) or the measured basis ever projects past a runner-hour budget
  the org accepts, revisit a suite-sharding split — ideally with the per-step duration
  data the new bounds will have made attributable by then.
