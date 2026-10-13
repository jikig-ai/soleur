# Tasks — ci: rebalance the already-sharded test-scripts legs under the ~10-minute ceiling

Plan: `knowledge-base/project/plans/2026-09-25-feat-ci-test-scripts-sharding-plan.md`
Branch: `feat-one-shot-ci-test-scripts-sharding`

## Phase 1: Measure + dry-run regen

- [x] 1.1 Verify preconditions: `git diff origin/main -- scripts/test-all.sh`
      is empty (start and end of work); confirm `gh` auth works.
- [x] 1.2 Pick a completed green `ci.yml` run carrying `suite-timings-scripts-*`
      artifacts (recent green PR or main run; 14-day artifact retention).
      Fallback: this branch's own first CI run.
- [x] 1.3 Run `python3 scripts/regenerate-shard-manifest.py --run <id>`
      (dry-run, no `--write`). If its default-run lookup 404s, `--run` is
      mandatory — already prescribed.
- [x] 1.4 Record predicted per-leg totals + incumbent totals in
      `knowledge-base/project/specs/feat-one-shot-ci-test-scripts-sharding/measurements.md`.
- [x] 1.5 **Gate:** predicted worst light leg ≥ 9.5 min suite time → Phase 2a;
      else → Phase 2b.

## Phase 2a: K=6→K=7 + regen (conditional)

- [x] 2a.1 `.github/workflows/ci.yml` — `test-scripts` `strategy.matrix.shard`
      literal to `["1/7"…"7/7"]`; rewrite `# MATRIX SHARDED`/`K=6` comment to
      K=7 + new nominal (~8.5 min incl. ~0.4 setup); sweep remaining `K=6`/`/6`
      citations in the job including the "light leg ~7 min nominal at K=6"
      line inside the `timeout-minutes` block (cap stays 60).
- [x] 2a.2 `plugins/soleur/test/scripts-shard-totality-mutations.sh` ROW5 —
      match literal `["1/7"…"7/7"]`, mutant drops leg 7. Also update the
      `/6`-citing comment at `scripts-shard-totality.test.sh` ~line 170.
- [x] 2a.3 `python3 scripts/regenerate-shard-manifest.py --run <id> --write`
      (manifest `# n=` becomes 7 — the regenerator derives N from ci.yml, so
      2a.1 MUST land first). Commit TSV as generated output — never hand-edit.
- [x] 2a.4 Runbook `ci-test-scripts-sharding.md` — update TL;DR K reference +
      "Current topology" table (K, legs, worst leg) + one "Measured history"
      line citing the run ids. Stay in the disjoint sections (PR #8763 edits
      the same file elsewhere).

## Phase 2b: Regen-only (alternative arm — NOT TAKEN; gate sent us to 2a)

- [ ] 2b.1 `python3 scripts/regenerate-shard-manifest.py --run <id> --write`;
      commit TSV only.
- [ ] 2b.2 Runbook — one "Measured history" line (skew observed, regen applied,
      run ids).

## Phase 3: Verify locally

- [x] 3.1 `bash plugins/soleur/test/scripts-shard-totality.test.sh` — green.
- [x] 3.2 `bash plugins/soleur/test/scripts-shard-manifest.test.sh` — green
      (n parity, labels ⊆ registered, no dups, provenance).
- [x] 3.3 `bash plugins/soleur/test/scripts-shard-totality-mutations.sh
      --rows 1-12` and `--rows 13-24` — all rows report their expected
      verdict (ROW5 family exercises the live ci.yml matrix).
- [x] 3.4 `bash plugins/soleur/test/ci-test-aggregator-diagnosis.test.sh` and
      `bash plugins/soleur/test/scripts-shard-runtime-coverage.test.sh` —
      green.
- [x] 3.5 Leg-union parity: for each k in 1..K,
      `SCRIPTS_SHARD=k/K bash scripts/test-all.sh --enumerate scripts`;
      union == `bash scripts/test-all.sh --enumerate scripts`, zero
      duplicates. Record counts in `measurements.md`.
- [x] 3.6 TSV diff review: sorted by label, provenance header names the source
      run id, no phantom labels.
- [x] 3.7 `npx markdownlint-cli2` on the runbook edit (and plan/tasks if
      touched).
- [x] 3.8 File the deferred follow-up P3 issue (long-tail suites:
      `lint-orphan-test-suites-mutations` ~588.8 s; registry-gate battery
      contention ceiling) — labels `domain/engineering`, `type/chore`,
      `priority/p3-low` (verified to exist).

## Phase 4: Ship inputs

- [ ] 4.1 POST-MERGE PENDING: measure the PR's own CI run — worst `test-scripts*` leg
      wall-clock via `gh api repos/jikig-ai/soleur/actions/runs/<id>/jobs` —
      append to `measurements.md` (AC1 evidence; "under ~10 min" target).
- [x] 4.2 Before/after table for `soleur:ship` PR body: run 32415069661
      baseline (27.7 min single job, ~53 job-min) vs post-change (leg count,
      worst leg, total job-min), suite-growth confound named.
- [x] 4.3 Confirm AC2/AC4/AC5 diffs: `required-checks.txt`, `infra/github/`,
      `scripts/test-all.sh` all unchanged; no `on:`/`if: github.event_name`
      trigger edits in ci.yml.
