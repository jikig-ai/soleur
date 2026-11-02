# Tasks — #11774 required-check wall-clock p50/p90 in weekly digest + regression ratchet

Plan: knowledge-base/project/plans/2026-11-02-feat-required-check-wallclock-p90-digest-ratchet-plan.md

## 1. Setup / measurement

- 1.1 Measure the bound-seeding baseline: pull the last ~30 completed+success `ci.yml` runs per surface (pull_request, merge_group); per run, `gh api repos/jikig-ai/soleur/commits/<head_sha>/check-runs` and compute per-required-context `latency_s` (completed_at - run.created_at) and `duration_s`; record p50/p90 in the runbook's measured history.
- 1.2 Write `scripts/required-check-wallclock-bounds.tsv` — `check_name<TAB>pr_bound_s<TAB>mq_bound_s<TAB>margin_frac`, seeded = measured p90 (rounded up) + margin default 0.30, one row per non-comment `scripts/required-checks.txt` line.

## 2. Probe

- 2.1 Write `scripts/watch-wallclock-p90-11774.sh`: required-set population derived from required-checks.txt; per-surface sampling; p50/p90 aggregation; breach = p90 > bound*(1+margin); unbound required context = finding; report body composition; sentinel drift-hash dedupe; standing tracker `ci-wallclock-p90: required-check wall-clock report` (find-or-file by title+bot author; body rewritten in place; never auto-closed; duplicate-title ::warning:: + lowest number); exit 0 ok/no-data, 1 breach/unbound, 2 usage, 3 cannot-establish, 78 xtrace; `--dry-run`, `--print-report`, `WATCH_*` fixture seams. Mirror `scripts/watch-shard-balance-11564.sh` structure.
- 2.2 Write `scripts/watch-wallclock-p90-11774.test.sh` — mock-`gh` fixture suite covering every Guard Contract mutation row (both guards).

## 3. Registration

- 3.1 Register `run_suite "scripts/watch-wallclock-p90-11774" bash scripts/watch-wallclock-p90-11774.test.sh` in `scripts/test-all.sh`.
- 3.2 Add floor rows: `scripts/suite-durations.tsv` and `scripts/suite-shard-legs.tsv`.

## 4. Workflow

- 4.1 Write `.github/workflows/wallclock-p90-watch.yml` — weekly cron staggered from the Mon-09:17 trio + Tue-09:41 sibling; `workflow_dispatch.dry_run`; default-branch guard; `actions:read`+`contents:read`+`issues:write`; concurrency group; timeout-minutes 15; header comment block (self-disable, dedupe, retirement set).

## 5. Digest

- 5.1 Edit `plugins/soleur/skills/operator-digest/SKILL.md`: new §6 "Your checks pipeline" reading the standing tracker body via `gh issue list` (aggregate-only render, plain language); L1 five->six sources; "five sections" wording; fallback list line.
- 5.2 Edit `plugins/soleur/skills/operator-digest/assets/operator-digest.workflow.yml`: prompt "five sources"/"five plain-language sections" -> six (no allowlist change).

## 6. Docs + verification

- 6.1 Update `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md`: watcher section + measured-history entry + retirement set.
- 6.2 Run `bash scripts/watch-wallclock-p90-11774.test.sh` and the affected + global ratchets (lint-orphan-test-suites, fast-tier budget, guard vacuity floor).
- 6.3 Post-merge (operator): `gh workflow run wallclock-p90-watch.yml -f dry_run=true` verify; re-run `provision-operator-digest-repo.sh` to reinstall the six-source prompt.
