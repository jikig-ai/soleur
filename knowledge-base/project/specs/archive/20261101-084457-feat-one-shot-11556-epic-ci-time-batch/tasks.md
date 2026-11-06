# Tasks — feat-one-shot-11556-epic-ci-time-batch

Plan: `knowledge-base/project/plans/2026-11-01-fix-epic-11556-ci-time-batch-plan.md`

## Phase 1 — #10865 probe bound (AC1, AC2)

- [x] 1.1 Re-anchor budget model in `scripts/followthroughs/ratchet-observation-window-10865.sh`: single `END = T0 + BUDGET` deadline (`SOAK_BUDGET_S` default 270, cap 300); `SOAK_FACTS_BUDGET_S` becomes `min(FACTS_BUDGET, remaining)`; gate listing loop, read dispatch, facts loop, baseline reads against it; per-read `timeout` ≤ `min(60, END − SECONDS − 5)`; `SOAK_PARALLEL` default 8. Preserve exit contract, priority dispatch (newest-10 merge_group first), oldest-first certification, `truncated=`/`units_read=`/`quota:` fields.
- [x] 1.2 Update the "ratchet observation window" rows in `plugins/soleur/test/ci-pr-affected-replay.test.sh` (deadline cut, facts sub-allocation, PAR default, verdict-preserving truncation) and the time-arithmetic paragraph in `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md`.
- [x] 1.3 Live dry-run with `SOAK_PROGRESS=1` + `timeout -k 10 300`; record phase lines + status line for the PR body.

## Phase 2 — #10781 close-out (AC3)

- [x] 2.1 Re-verify `deploy-script-tests` green on a head containing current main (`gh run list --workflow infra-validation.yml`).
- [x] 2.2 Post root-cause comment on #10781 (shared-budget mechanism + #11442/#11573/#11676 + advisory-by-design Lever D disposition) and `gh issue close 10781`.

## Phase 3 — #11379 K18 fix (AC4)

- [x] 3.1 `.claude/hooks/lib/commit-target-roots.sh`: `printf '%s' "$cmd" 2>/dev/null |` in `ctr_collect`.
- [x] 3.2 K18 regression row in `.claude/hooks/git-commit-secret-scan.test.sh` (early-exit stub loop ≥20 iterations, byte-exact `got`; static grep assert on the producer line). Grep `.claude/hooks/lib/` for sibling `printf |` early-reader producers.
- [x] 3.3 Close #11379 with the fix link.

## Phase 4 — #9323 soak + Lever E filings (AC5, AC6)

- [x] 4.1 Re-instrument `scripts/followthroughs/pr-battery-gate-saving-9323.sh` arm (a): realized-skip accounting from `suite-timings-*` artifacts (`skip=relevance` rows × committed `suite-durations{,-heavy}.tsv` prices; battery set derived from `--pr-gated` call sites); `rate_limit` precheck + artifact-read budget; missing evidence → NOT YET; mean ≥ 20 → PASS; under → FAIL; escape arm (b) unchanged; whole-run mean + queue wait informational.
- [x] 4.2 Update `pr-battery-gate-saving-9323.test.sh` fixtures (full-skip ~48.5 min, partial <20 FAIL, quota-cut NOT YET, escape unchanged).
- [x] 4.3 Post the methodology finding + realized-saving evidence + queue-wait-AC-met report on #9323 (do NOT close — the re-instrumented soak decides).
- [x] 4.4 File Lever E tracker (a): digest wall-clock p50/p90 per required-check job + regression ratchet (requirements-level; cites `deploy-script-tests-legs-8736.sh` pattern, `watch-shard-balance-11564.sh`, ADR-057 boundary).
- [x] 4.5 File Lever E tracker (b): CI wall-clock in `pipeline-tally.sh` dims + `pipeline-tally-render.md` machine line.
- [x] 4.6 Comment on epic #11556 ticking the two Lever E filing bullets (noting #11564 drift watch covers part of the second bullet).

## Phase 5 — #10448 decision record (AC7)

- [x] 5.1 Post the operator's 2026-11-01 FUND ruling (option (i)) on #10448; holds unchanged (no CI_PR_AFFECTED, no activation-lock removal, no PR D #10414, no PR3b #10859, no flip PR).
- [x] 5.2 File the index-completion scheduling issue: verbatim entry condition (`gap_suites=0` OR all remaining rows carry human `false-positive:` reasons; required ratchet check; escape-replay re-run); carried-forward remainder `gap_suites=272 gap_refs=1634` (2026-11-01 audit, baseline 1,510 lines); continuation of #10671/#10945/#11109/#11131/#11226, not a restart.

## Phase 6 — Ship hygiene

- [x] 6.1 Sweeper dry-run evidence for both amended probes in the PR body (runbook requirement).
- [ ] 6.2 `git status` clean; PR body carries `## Changelog`; semver label for `plugins/soleur/` touch (test file only — evaluate `semver:patch`).
