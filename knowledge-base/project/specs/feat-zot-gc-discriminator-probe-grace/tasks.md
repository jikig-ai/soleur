---
feature: zot-gc-discriminator-probe-grace
lane: cross-domain
plan: knowledge-base/project/plans/2026-08-12-feat-zot-gc-attribution-discriminator-plan.md
created: 2026-08-13
---

# Tasks — Registry log-channel follow-ups

Derived from the post-panel plan. No new files: every task edits a file that already exists, is
already tested, and is already scheduled.

## Phase 1 — Failing tests first (`cq-write-failing-tests-before`)

- [ ] **1.1** In `tests/scripts/test-zot-log-channel-probe.sh`, add a case: delivery evidence +
      zero envelope rows + literal `log_shipper_last_ok_age_s=-1` → softened framing, exit 2.
      RED before Phase 3.
- [ ] **1.2** Add a case pinning C3b: `control_row_predelivery` (no `log_shipper_*` fields) still
      asserts `delivered_but_silent`, unsoftened. Guards FR6.
- [ ] **1.3** Add a case: `log_shipper_last_ok_age_s=42` → unsoftened.
- [ ] **1.4** Add a case asserting the `not_delivered` arm carries no "open ordered path" / "step-6"
      text. RED before Phase 4.
- [ ] **1.5** Add a case asserting `run_query()` surfaces a stubbed rc=3 message, bounded ≤600 bytes.
- [ ] **1.6** In `scripts/followthroughs/zot-fill-rate-7341.test.sh`, add: attribution-query stub
      fails → exit code identical to the no-lead run, output contains `attribution_unavailable`.
- [ ] **1.7** Add: attribution stub returns garbage / hangs → exit code unchanged.
- [ ] **1.8** Add: a fixture row whose **header** renders `executing gc … for /var/lib/zot/x/phantom`
      contributes **no** repository to the lead (FR4, the injection guard).
- [ ] **1.9** Add: a fixture with an unmatched start **and** a non-zero `SOLEUR_ZOT_LOG_DROPPED`
      count prints both, so the confound is visible (FR3).
- [ ] **1.10** Add: envelope anchor requires the trailing space — `host=soleur-registry-2` rows are
      not admitted.
- [ ] **1.11** Raise the assertion floor in both suites to cover the new cases (TR3).

## Phase 2 — Attribution lead (GREEN)

- [ ] **2.1** In `scripts/followthroughs/zot-fill-rate-7341.sh`, add an attribution helper querying
      the four gc evidence classes over the trailing window, anchored per FR4.
- [ ] **2.2** Extract repositories from the parsed `message` field only; never the whole line.
- [ ] **2.3** Emit gc starts, completions, unmatched-start repositories, `PatchBlobUpload` count,
      and the `SOLEUR_ZOT_LOG_DROPPED` count.
- [ ] **2.4** Call it from the `FAIL)` arm (`:262`) **after** the verdict, guarded so it cannot
      change the exit code; print `attribution_unavailable` on any error.
- [ ] **2.5** Bound the printed output (public issue comment).
- [ ] **2.6** Follow the in-file precedent at `:125` for naming a tool in probe output.

## Phase 3 — First-tick softening

- [ ] **3.1** In `scripts/followthroughs/zot-log-channel-7440.sh`, promote the existing
      `last_ok_age_s=-1` explanation above the ACT-NOT-WAIT sentence.
- [ ] **3.2** Soften that sentence when the value is the **literal** `-1`; no new verdict name, no
      exit-code change, no clock read.

## Phase 4 — Stale arm + rc=3

- [ ] **4.1** Rewrite the `not_delivered` arm (`:328`) and the header (`:16`): #7287 closed
      2026-08-12T20:39Z and the host is replaced; the real remaining wait is the first `4-59/5` tick.
- [ ] **4.2** In `run_query()` (`:140`), stop swallowing stderr; surface rc=3 bounded to 600 bytes
      (mirror `zot-fill-rate-7341.sh`'s `head -c 600 "$qerr"`).

## Phase 5 — Docs, verification, successors

- [ ] **5.1** Amend ADR-184 `## Consequences` with the measured class shapes. Leave frontmatter
      `status:` and `## Status flip condition` byte-identical to `origin/main` (TR6).
- [ ] **5.2** `shellcheck` clean on both edited probes and both edited suites.
- [ ] **5.3** `bash scripts/test-all.sh` green.
- [ ] **5.4** Verify no new test file and no new `run_suite` registration (AC8).
- [ ] **5.5** Live check: `bash scripts/followthroughs/zot-log-channel-7440.sh` still PASSes.
- [ ] **5.6** Correct #7456's ADR-179 → ADR-184 citation.
- [ ] **5.7** File successor issues: (c) rate-cap trigger; standing detection expiring when #7341
      closes; the two false `zotRegistry` claims in `model.c4`; `lint-orphan-test-suites.sh` blind
      to `scripts/followthroughs/*.test.sh`.
- [ ] **5.8** PR body uses `Refs #7456`, **not** `Closes` — items (a) and (c) remain.
