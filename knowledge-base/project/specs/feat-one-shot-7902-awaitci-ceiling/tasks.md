# Tasks — fix: await-ci ceiling vs ci.yml duration (#7902)

Plan: `knowledge-base/project/plans/2026-09-07-fix-release-await-ci-ceiling-vs-ci-duration-plan.md`

Decision: shard the long-pole `test-scripts` job and declare a CI duration budget (option 2).
The `await-ci` gate, `CEILING_S=3000`, `notify-gated` and the whole release topology are
**deliberately untouched**. Option 3 (`workflow_run`) stays deferred on #5806.

Phase order is load-bearing: the shard mechanism and its totality guard land **before** `ci.yml`
calls it with a shard argument, so no commit leaves CI silently running a subset.

## Phase 0: Preconditions

- [ ] 0.1 Measure the per-suite duration distribution for the scripts group. If any single suite
      exceeds ~8 min, choose K against the tail rather than the mean before committing to K=3.
- [ ] 0.2 Re-read `scripts/lib/test-contention.sh` and ADR-133 to confirm the advisory-lock
      semantics a per-leg run must preserve.
- [ ] 0.3 Record the pre-change baseline (ci.yml wall p50 34.27 / p90 51.77 / max 57.40) so
      Phase 3's ceilings and AC21 have a reference point.

## Phase 1: Deterministic, total shard partition (contract first)

- [ ] 1.1 Write the Guard 1 (shard totality) suite **before** the partition exists, from the
      plan's mutation matrix — 5 RED rows plus the harness rows, parameterised over K.
- [ ] 1.2 Write the Guard 2 (shard determinism) suite, likewise from the matrix.
- [ ] 1.3 Add `SCRIPTS_SHARD=k/N` support to `scripts/test-all.sh`, partitioning the scripts group
      by a stable hash of the suite path modulo N. Unset/empty must run the full group.
- [ ] 1.4 Emit the per-leg executed suite list, and add the `--list-shard-coverage` reporting path
      used by the plan's `discoverability_test`.
- [ ] 1.5 Scale `TC_RUNTIME_CEILING_S` in `scripts/lib/test-contention.sh` for a sharded leg.
- [ ] 1.6 Drive Guards 1 and 2 GREEN against the real discovery set, not fixtures.

## Phase 2: Matrix the test-scripts job

- [ ] 2.1 Add `strategy: {fail-fast: false, matrix: {shard: ["1/3","2/3","3/3"]}}` to `ci.yml`'s
      `test-scripts` job; pass `SCRIPTS_SHARD: ${{ matrix.shard }}` via `env:`.
- [ ] 2.2 Keep the job key literally `test-scripts` so `needs.test-scripts.result` and the
      required-check contract are unchanged. Confirm the `test` aggregator block is untouched.
- [ ] 2.3 Keep every leg's runtime profile identical — same gitleaks and likec4 pins, no
      `setup-node`/`setup-bun` version pin (47+ suites assert the shard has no bun and no node).
- [ ] 2.4 Re-run `plugins/soleur/test/scripts-shard-runtime-coverage.test.sh` and fix its awk
      job-block extractor if `strategy:` breaks the bound. Do not assume it survives.
- [ ] 2.5 Re-run `plugins/soleur/test/required-checks-canonical-parity.test.sh` for gitleaks pin
      parity with one install site now a matrix.

## Phase 3: Declare the CI duration budget

- [ ] 3.1 Write the Guard 3 suite (deploy-critical jobs declare a timeout) from its mutation
      matrix, recomputing membership from the `needs` graph rather than a hand-listed set.
- [ ] 3.2 Declare `timeout-minutes` on `test-scripts` (per leg), `test-webplat`, `test-bun`,
      `test`, and every job with a `needs`-path into `test`.
- [ ] 3.3 Size each ceiling above the measured post-shard p100 with the headroom stated in an
      inline comment. A ceiling that kills a slow-but-healthy leg reintroduces this bug one layer
      down.
- [ ] 3.4 Drive Guard 3 GREEN against the real workflow.

## Phase 4: Verify nothing else moved

- [ ] 4.1 Assert `git diff origin/main -- .github/workflows/web-platform-release.yml` is empty and
      `CEILING_S` is still `3000`.
- [ ] 4.2 Assert `scripts/prod-version-drift-check.sh` and its test suite are unmodified, and the
      suite still passes — the drift alerter's sensitivity must not be spent.
- [ ] 4.3 Run `bash plugins/soleur/test/c4-count-parity.test.sh` (expect 10/10).
- [ ] 4.4 Run `actionlint` on `.github/workflows/ci.yml`; extract each edited `run:` snippet
      through `bash -c`. Do **not** run `bash -n` against workflow YAML.
- [ ] 4.5 Confirm `SCRIPTS_SHARD` unset still runs the full group, so local runs and
      `main-health-monitor.yml`'s `TEST_GROUP=all` path are unchanged.

## Phase 5: Architecture records

- [ ] 5.1 Re-derive the next free ADR ordinal across **every** `origin/*` ref (205 and 206 are
      claimed on pushed branches; a `main`-scoped probe is wrong). Author
      `ADR-<n>-ci-wallclock-declared-budget.md`, `status: accepted`.
- [ ] 5.2 Amend ADR-072 — **amend, not supersede**. Add the dated re-measurement, record that
      Decision item 4's sizing premise is falsified, and correct the option-1 record (its
      rejection was pre-adaptive-wait; it now fails on the B9 coupling).
- [ ] 5.3 Update #5806 with the evaluation outcome, the fourteen scoping findings, and the
      re-armed criterion (post-shard p100 > 60% of `CEILING_S`). Do **not** close it.
- [ ] 5.4 If the ordinal moved, sweep `knowledge-base/project/{plans,specs}/` for the old number.

## Phase 6: Ship

- [ ] 6.1 Run `python3 scripts/lint-guard-contract.py` and
      `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main`.
- [ ] 6.2 Full battery at the `/ship` checkpoint.
- [ ] 6.3 PR body uses `Closes #7902` and `Ref #5806` — never `Closes #5806`.
- [ ] 6.4 Render `decision-challenges.md` (DC-1, the option-2-over-option-3 reversal) into the PR
      body and file it as an `action-required` issue.
- [ ] 6.5 Post-merge: verify the first main `ci.yml` run has three green `test-scripts` legs and a
      materially reduced wall clock (AC21).
- [ ] 6.6 Post-merge: `gh workflow run web-platform-release.yml -f bump_type=patch` to unblock
      production, then `curl -fsS https://app.soleur.ai/health` and confirm `build_sha` (AC22).
- [ ] 6.7 Post-merge: record post-shard p100 over the following 10 main runs on #5806 and evaluate
      the re-armed criterion (AC23).
