# Tasks — fix: await-ci ceiling vs ci.yml duration (#7902)

Plan: `knowledge-base/project/plans/archive/20260908-132617-2026-09-07-fix-release-await-ci-ceiling-vs-ci-duration-plan.md`

Decision: **bounded ceiling raise + shard the long pole**, together. The raise is the deterministic
unblock; the shard is what stops the raised ceiling becoming the next incident. Option 3
(`workflow_run`) stays deferred on #5806.

Order is load-bearing twice over: the drift threshold moves **before** the ceilings (or B9 reds in
between), and the partition + its guard land **before** `ci.yml` calls with a shard argument (or CI
silently runs a subset).

## Phase 0: Derive K from data that already exists

- [x] 0.1 Pull `TEST_TIMING_LOG` from one full scripts-group run. Report the per-suite duration
      distribution and name the single longest suite — that value is the floor no K can beat.
      Known: `tests/scripts/registry-gate-mutation-battery` carries a 2,500,000 ms budget with
      measured runs of 860,692 ms and 1,675,430 ms, and is relevance-gated.
- [x] 0.2 Choose K against the measured tail. K=3 is provisional, not an acceptance criterion.
- [x] 0.3 Record the baseline gated metric — time-to-`test` p50 34.1 / p90 49.6 / max 56.1 min.
- [x] 0.4 Confirm the ADR-133 CI exemptions still hold (advisory lock and runtime ceiling both
      short-circuit under `CI`). Verified at plan time; re-confirm before relying on it.

## Phase 1: Bounded ceiling raise — the deterministic unblock

- [x] 1.1 `scripts/prod-version-drift-check.sh`: `DRIFT_SUSTAINED_THRESHOLD_MIN` 195 → 207, and
      update the derivation comment so the arithmetic matches the ceilings. **This lands first.**
- [x] 1.2 `.github/workflows/web-platform-release.yml`: `CEILING_S` 3000 → 3600 and `await-ci`
      `timeout-minutes` 60 → 72, preserving ADR-072 invariant #7 (`timeout-minutes ≥ 1.2 ×
      CEILING_S`) and the wall-clock-keyed ceiling.
- [x] 1.3 Update the anti-regression comment to name what the new ceiling bounds — CI liveness,
      sized above the measured max of 56.1 min, not above p50.
- [x] 1.4 `bash scripts/prod-version-drift-check.test.sh` green, B9 included.
- [x] 1.5 Confirm nothing else in `web-platform-release.yml` changed — `await-ci`'s polling logic,
      `notify-gated`, and the `migrate`/`deploy` wiring are untouched.

## Phase 2: Round-robin partition at the `run_suite` chokepoint

- [x] 2.1 Write the Guard 1 (shard totality) suite **before** the partition, from the plan's
      eight-row mutation matrix, including row 6 (the K=1 tautology stub) and row 8 (malformed
      value). Each mutation must be line-range-scoped with its placement asserted.
- [x] 2.2 Add an **enumerate mode** to `scripts/test-all.sh` that records registrations without
      executing them, handled in the same early block as `--print-suite-globs` — before `TMPDIR`
      export, the bare-repo guard, `TEST_GROUP` validation and `tc_acquire`. A path that blocks on
      the advisory lock deadlocks the gate on itself.
- [x] 2.3 Add `SCRIPTS_SHARD=k/N`. Filter inside `run_suite()` **before** `suites=$((suites + 1))`,
      and mirror the identical filter into `skip_suite()` — both increment `suites`.
- [x] 2.4 Partition round-robin on the registration counter, keyed on the `run_suite` **label**.
      Not a hash over the suite path: ~198 registrations are hand-written and ~24 name no path.
- [x] 2.5 A shard non-selection must not increment `skipped`, must not reach `_ceiling_declined`
      accounting, and must not push the leg toward ADR-181's `exit 3`.
- [x] 2.6 Malformed `SCRIPTS_SHARD` (`0/3`, `4/3`, `1/0`, `abc`, empty) exits `2`, following the
      `TEST_GROUP` validation precedent. Never a silent full-group or empty run.
- [x] 2.7 Unset/empty runs the full group. The filter keys on `SCRIPTS_SHARD` presence, never on
      `TEST_GROUP == scripts`.
- [x] 2.8 `scripts/lint-orphan-test-suites.sh`: `env -u TEST_GROUP` → `env -u TEST_GROUP -u
      SCRIPTS_SHARD`; widen the matching assertion in its companion suite.
- [x] 2.9 Drive Guard 1 GREEN against the real tree, with its reference set derived by static
      `run_suite` extraction + `--print-suite-globs` — never by calling the partition with K=1.

## Phase 3: Matrix the job

- [x] 3.1 Add `strategy: {fail-fast: false, matrix: {shard: [...]}}` to `ci.yml`'s `test-scripts`;
      pass `SCRIPTS_SHARD: ${{ matrix.shard }}` via `env:`. Comment why the group stays positional.
- [x] 3.2 Keep the job key literally `test-scripts`; no leg may carry `continue-on-error`.
- [x] 3.3 Each leg echoes its resolved `k/N`; assert N distinct values across N legs so a leg that
      lost its `env:` is detected rather than passing green on the full group.
- [x] 3.4 Keep every leg's runtime profile identical — same gitleaks and likec4 pins, no
      `setup-node`/`setup-bun` version pin.
- [x] 3.5 Re-run `plugins/soleur/test/scripts-shard-runtime-coverage.test.sh` (its extractor anchors
      on 2-space keys and `strategy:` is indented 4 spaces — verify, do not assume) and
      `plugins/soleur/test/required-checks-canonical-parity.test.sh`.
- [x] 3.6 Confirm the `test:` job block is byte-unchanged and `scripts/required-checks.txt` is
      unmodified.

## Phase 4: Guard 2 — CI's declared budget is bounded by the gate

- [x] 4.1 Write the Guard 2 suite from its seven-row mutation matrix.
- [x] 4.2 Declare `timeout-minutes` on `test`'s `needs`-closure (today exactly `test-webplat`,
      `test-bun`, `test-scripts`, `test`, plus the legs), sized above the measured post-shard p100
      with headroom stated inline.
- [x] 4.3 Assert `max(closure ceilings) + test's own <= CEILING_S/60`, reading `CEILING_S` out of
      `web-platform-release.yml` rather than restating it, with a **pinned closure string** (B8e's
      shape) so a graph edit reds.
- [x] 4.4 Drive Guard 2 GREEN.

## Phase 5: Guard placement in CI

- [x] 5.1 Run Guard 1 from a job that can observe **all** legs — a non-sharded job invoking the
      enumerate mode K times, or a join job over per-leg artifacts. A guard inside one leg cannot
      see a cross-leg union.
- [x] 5.2 Assert the enumerate mode and the executing pass emit identical label sequences with
      `SCRIPTS_SHARD` unset.

## Phase 6: Architecture records

- [x] 6.1 Re-derive the next free ADR ordinal across **every** `origin/*` ref (205 and 206 are
      claimed on pushed branches; a `main`-scoped probe is wrong). Author
      `ADR-<n>-ci-declared-budget-bounds-deploy-gate.md`, `status: accepted`.
- [x] 6.2 Amend ADR-072 — **amend, not supersede**. Add the re-measurement, record that item 4's
      sizing premise was stated in run-wall-clock terms (a quantity the gate does not measure), and
      correct the option-1 record.
- [x] 6.3 Update #5806 with the evaluation outcome, the fourteen scoping findings, and the re-armed
      criterion keyed to time-to-`test`. Do **not** close it.
- [x] 6.4 If the ordinal moved, sweep `knowledge-base/project/{plans,specs}/` for the old number.

## Phase 7: Ship

- [ ] 7.1 `python3 scripts/lint-guard-contract.py` and
      `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main`.
- [ ] 7.2 `actionlint` on both edited workflows; `bash -c` extraction on edited `run:` snippets.
      Never `bash -n` against workflow YAML.
- [ ] 7.3 `bash plugins/soleur/test/c4-count-parity.test.sh` (expect 10/10).
- [ ] 7.4 Full battery at the `/ship` checkpoint.
- [ ] 7.5 PR body uses `Closes #7902` and `Ref #5806` — never `Closes #5806`.
- [ ] 7.6 Render `decision-challenges.md` (DC-1) into the PR body and file it as an
      `action-required` issue.
- [ ] 7.7 File the deferred issue. NOTE: "runner-pool contention" was the WRONG attribution — see the Correction stanza; filed as #7931 covering the ci.yml concurrency key, aggregator diagnosis honesty, and matrix-leg balance.
- [ ] 7.8 Post-merge: time-to-`test` below 25 min over the first 3 main runs (AC25).
- [ ] 7.9 Post-merge: `gh workflow run web-platform-release.yml -f bump_type=patch`, then
      `curl -fsS https://app.soleur.ai/health` and confirm `build_sha` (AC26).
- [ ] 7.10 Post-merge: record post-shard time-to-`test` p100 over 10 runs on #5806 (AC27).

## Post-review amendments (2026-09-07)

- [x] Guard 2 + battery + its ci.yml step DELETED on a CTO ruling; ADR-212 rewritten at the same
      ordinal to record the rejection. Phase 4's tasks are superseded, not unmet.
- [x] `await-ci` gains a `::warning::` at 0.7 x CEILING_S (derived, never restated) — the
      replacement mechanism, measuring the gated quantity including the concurrency queue.
- [x] `test-scripts` `timeout-minutes` 30 -> 60, reconciled against the 2,500,000 ms per-suite
      budget at `scripts/test-all.sh:599`. A silent bound must not fire before a loud one.
- [x] The "dispatch" measurement is corrected everywhere it was load-bearing; dated correction
      stanzas appended to the plan and to decision-challenges.
- [x] Follow-up filed: #7931 (concurrency key, aggregator diagnosis, LPT leg balance).
