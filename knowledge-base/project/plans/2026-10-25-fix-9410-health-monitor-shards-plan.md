---
title: "fix(ci): shard main-health-monitor's tests step across parallel legs (#9410)"
date: 2026-10-25
slug: fix-9410-health-monitor-shards
branch: feat-one-shot-9410-health-monitor-shards
issue: 9410
closes: 9410
type: fix
priority: p2-medium
domain: engineering
lane: cross-domain
brand_survival_threshold: none
---

# fix(ci): shard main-health-monitor's tests step across parallel legs (#9410)

## Overview

`main-health-monitor.yml` ran `TEST_GROUP=all` as ONE sequential step
(~50 min wall; the 40-min step ceiling was exceeded on every run from
2026-09-17, and #8112's stopgap raised it to 110). Each suite-set growth forced
a step-ceiling + job-ceiling + Sentry `max_runtime`/`checkin_margin`
re-derivation — the failure the issue wants to end.

The restructure mirrors ci.yml's leg topology because `SCRIPTS_SHARD` is scoped
to the two scripts groups (test-all.sh refuses it under `TEST_GROUP=all`):

| job | legs | selector | step ceiling |
|---|---|---|---|
| test-webplat | 2 | `TEST_GROUP=webplat` + `VITEST_SHARD` | 10 |
| test-bun | 1 | `TEST_GROUP=bun` | 10 |
| test-scripts | 8 | `TEST_GROUP=scripts` + `SCRIPTS_SHARD=k/8` (ADR-240 manifest n=8) | 15 |
| test-scripts-heavy | 3 | `TEST_GROUP=scripts-heavy` + `SCRIPTS_SHARD=k/3` (manifest n=3) | 65 |
| test-infra | 1 | `TEST_GROUP=infra` (single leg — the #7432 soak probe reads one check-run) | 60 |
| report | — | `needs:` all five, `if: always()` | 15 |

Coverage vs `TEST_GROUP=all`: `all` = scripts + scripts-heavy + bun + webplat +
the diff-gated nested infra runner. The five legs cover the same registration
set; the nested runner (fires under `all` only on an infra-touching diff) is
covered unconditionally by the explicit infra leg — on `main` (empty diff)
identical, on a branch dry-run it runs once instead of twice.

## Ceiling derivation

`leg_step = max(10, roundup5(1.5 * leg_max))` (the #8112 convention),
`leg_job = leg_step + 10 setup + 10 post-steps`,
`envelope = max(leg_job) + report = 85 + 15 = 100` → Sentry
`max_runtime_minutes = 100`, `checkin_margin_minutes = 125`.
Inputs: scripts leg ~10 min measured worst at K=8 → 15; heavy leg's worst
member is the registry battery (declared `_suite_budget_ms` 2500000 ms = 41.67
min → 1.5× = 65); webplat p90 4.37 → floor 10; bun p90 <2 → floor 10; infra
38.77 s sequential uncensored → 58.15 → 60.

## Report-job contract

- Each leg's suite step (`id: suite`) carries NO `continue-on-error` —
  `needs.*.result` must carry the real verdict (continue-on-error would pin it
  to success). Downstream leg steps are `if: always()`.
- Each leg stages `capture.txt` + `status.env` (`outcome=`, `elapsed_s=`),
  uploads artifact `monitor-leg-<leg-id>`, and emits a per-leg
  `SOLEUR_MAIN_HEALTH <leg>=<outcome>` ::notice:: (`infra=`/`infra_elapsed_s=`
  on the test-infra check-run — probe parity for jobs1-stopgap-7432).
- `report` downloads `pattern: monitor-leg-*` to `/tmp/leg-reports`
  (continue-on-error — zero artifacts must not skip the filer), iterates
  `EXPECTED_LEGS` (15 ids; missing dir = "no leg report", not green), classifies
  each capture with the #8112 arm taxonomy (RED/UNACCOUNTED verdict, bare
  [FAIL] display-only, corroborated [KILLED] → "terminated", else "did not
  complete"/"could not run"), owns the single tracker and the single Sentry
  check-in (status = all five results == success && mint != red).
- `JOBS=1` removed everywhere: it pinned the `all` step's nested infra runner;
  no leg runs `all`.

## Files changed

- `.github/workflows/main-health-monitor.yml` — rewritten (6 jobs, ~830 lines).
- `apps/web-platform/infra/sentry/cron-monitors.tf` — `main_health_monitor`
  envelope 185/210 → 100/125.
- `scripts/followthroughs/jobs1-stopgap-7432.sh` — probe job lookup
  `health-check` → `test-infra` (annotation + log + timeout all stay on that
  one check-run).
- `plugins/soleur/test/main-health-monitor-workflow.test.sh` — guards reworked:
  needs.*.result lockstep, per-leg ceiling arithmetic + run envelope (G2),
  no-JOBS-anywhere, all-six-jobs runner parity, new S1–S6 shard guards
  (manifest n == matrix, SCRIPTS_SHARD binding, EXPECTED_LEGS == derived 15,
  single heartbeat, per-leg notice), leg-dir behavioural harness, floor 155.

## Non-Goals

- No monitor-specific shard manifest: `SCRIPTS_SHARD` under `TEST_GROUP=all`
  is refused by design; per-group legs reuse the ADR-240 manifests as-is.
- Not sharding infra (`SOLEUR_INFRA_SHARD` exists but the soak probe requires
  one check-run's log/annotation; recorded, not done).
- The #8112 "evaluate" alternative (read the latest CI conclusion, skip the
  re-run) — out of scope; this lands the sharding the issue asked for.

## Guard Contract (5 guards)

### Guard 1 — leg job ceilings dominate their step ceilings +15

**Property.** Every leg job's `timeout-minutes` must exceed its own suite-step
ceiling by at least 15 minutes, and every leg step must sit at or above the
10-minute floor — else a job-level cancel kills the stage/upload/notice steps
before they can run and the leg reports nothing (the sharded form of defect A).

**Assembly.** `main-health-monitor-workflow.test.sh` check (6): extracts each of
the five leg jobs' blocks, reads the job-level `timeout-minutes` vs the step
`timeout-minutes`, and requires `job >= step + 15` and `step >= 10` for every
leg, plus a declared report ceiling. There is no second ceiling site — the
suite step is the only timed step per leg.

**Mutation matrix.** Rows are evaluated by the same extracted-arithmetic path
the guard runs; the right column names the row that reddens.

| # | Mutation (must drive the guard RED) | Why it is derivable | Observed red |
|---|--------------------------------------|---------------------|--------------|
| 1 | Lower one leg's job ceiling below `step+15` | The per-leg dominance relation is the property | (6) |
| 2 | Delete a leg's step `timeout-minutes` | A missing bound must not read as satisfied | (6) |
| 3 | Drop a leg step below the 10-minute floor | The floor carries the uncensored-measurement rule | (6) |

### Guard 2 — Sentry envelope tracks the run envelope

**Property.** The `main_health_monitor` Sentry cron monitor's
`max_runtime_minutes` equals the run's bounded wall clock (the slowest leg's
job ceiling plus the report job's), and `checkin_margin_minutes` lies in
`[envelope+25, 360)` — a healthy slow run must not page, a dropped run must.

**Assembly.** Check (G2): parses `apps/web-platform/infra/sentry/cron-monitors.tf`
for the single `main-health-monitor` block (zero blocks is a RED, not a skip)
and compares both literals against the envelope computed from the workflow's
leg job ceilings plus the report ceiling.

**Mutation matrix.**

| # | Mutation (must drive the guard RED) | Why it is derivable | Observed red |
|---|--------------------------------------|---------------------|--------------|
| 1 | Bump a leg job ceiling without touching TF | The coupling is the whole point | (G2) |
| 2 | Set `checkin_margin_minutes` below `envelope+25` | A slow healthy run would page | (G2) |
| 3 | Set `checkin_margin_minutes` ≥ 360 | A dropped run would never page | (G2) |

### Guard 3 — shard matrices match the ADR-240 manifests

**Property.** `test-scripts`' matrix enumerates `k/8` for the `# n=8` manifest,
`test-scripts-heavy`'s `k/3` for the `# n=3` manifest, `test-webplat` runs
`1/2..2/2`, both scripts jobs bind `SCRIPTS_SHARD: ${{ matrix.shard }}`, and
every leg declares its own `TEST_GROUP` — a drift in any of these silently
runs a different suite slice under the same leg name.

**Assembly.** Checks (S1)/(S2)/(S2b): read the `# n=` line out of each
committed manifest (never a literal in the test), expand the matrix literals,
compare elementwise, and grep each leg block for `SCRIPTS_SHARD` bound to
`matrix.shard` and `TEST_GROUP: <group>`.

**Mutation matrix.**

| # | Mutation (must drive the guard RED) | Why it is derivable | Observed red |
|---|--------------------------------------|---------------------|--------------|
| 1 | Regenerate a manifest at a different n | The matrix literal is the thing the manifest pins | (S1) |
| 2 | Rewrite `SCRIPTS_SHARD` to a literal `1/8` | The binding must follow the matrix, not a copy of it | (S2) |
| 3 | Change a leg's `TEST_GROUP` | A leg must name the suites it claims to run | (S2b) |

### Guard 4 — report job owns the single tracker and check-in

**Property.** Exactly one job files/closes the `ci/main-broken` tracker and
posts the Sentry check-in: `report` runs under `if: always()` with `needs:`
covering all five leg jobs, every `needs.<job>.result` token appears in
lockstep across the filer's `if:`, the closer's `if:`, and the heartbeat's
`status:`, `EXPECTED_LEGS` names all 15 leg ids, and exactly one
`sentry-heartbeat` invocation exists in the file.

**Assembly.** Checks (5)/(5b)/(5c)/(S3)/(S4)/(S5): the needs list is compared
against the five leg ids, the token census counts every `needs.*.result`
reference file-wide, `EXPECTED_LEGS` is compared to the derived leg set, and
the `uses:` census requires exactly one heartbeat. A leg outside `needs:` or
`EXPECTED_LEGS` is invisible to the report's accounting — the guards red on
that, not on the symptom.

**Mutation matrix.**

| # | Mutation (must drive the guard RED) | Why it is derivable | Observed red |
|---|--------------------------------------|---------------------|--------------|
| 1 | Drop a leg job from `needs:` | The report would run before the leg finishes | (5) |
| 2 | Remove `if: always()` from report | A failed leg would skip the reporter entirely | (5b) |
| 3 | Add a second `sentry-heartbeat` on a leg | A per-leg check-in masks a leg that never ran | (S5) |

### Guard 5 — per-leg verdict channel

**Property.** Every leg reports its suite verdict and its uncensored elapsed
seconds: the suite step pipes `bash scripts/test-all.sh` through `tee` with
`rc=${PIPESTATUS[0]}` read on the IMMEDIATELY following line and `exit "$rc"`,
writes `elapsed_s` before exiting, stages `capture.txt` + `status.env`, uploads
`monitor-leg-<id>`, and emits `SOLEUR_MAIN_HEALTH <leg>=<outcome>` with the
numeric-guarded `<leg>_elapsed_s` token — `infra=`/`infra_elapsed_s=` on the
test-infra leg, which the jobs1-stopgap-7432 soak probe greps.

**Assembly.** Checks (7)/(7b)/(8k)/(S6): PIPESTATUS adjacency per tee site,
`exit "$rc"` count >= tee-site count, five `id: suite` steps each carrying
`t0=$SECONDS` and `elapsed_s` written before `exit "$rc"`, five `status.env`
elapsed writes, five per-leg notices, and one patterned
`pattern: monitor-leg-*` download in the report job.

**Mutation matrix.**

| # | Mutation (must drive the guard RED) | Why it is derivable | Observed red |
|---|--------------------------------------|---------------------|--------------|
| 1 | Insert `set -e` between the tee pipeline and the PIPESTATUS read | PIPESTATUS resets to 0 — a silent false pass | (7) |
| 2 | Drop `exit "$rc"` from a leg | A red leg reports success and the closer retires trackers | (7b) |
| 3 | Emit `elapsed_s` after `exit "$rc"` | The censored-figure channel dies silently | (8k) |

## Verification

- `python3 -c "import yaml; yaml.safe_load(...)"` — YAML parses.
- `bash plugins/soleur/test/main-health-monitor-workflow.test.sh` —
  156 assertions, 0 failures.
- No real GitHub Actions run possible; the static test is the gate.
