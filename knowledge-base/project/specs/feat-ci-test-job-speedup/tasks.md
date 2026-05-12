---
title: "CI test-job speedup — tasks (replan)"
issue: 3680
pr: 3672
branch: feat-ci-test-job-speedup
plan: knowledge-base/project/plans/2026-05-12-feat-ci-test-job-speedup-plan.md
lane: cross-domain
brand_survival_threshold: single-user incident
date: 2026-05-12
supersedes: prior tasks.md (v1, replaced in place)
---

# Tasks — feat-ci-test-job-speedup (replan)

Derived from `knowledge-base/project/plans/2026-05-12-feat-ci-test-job-speedup-plan.md`. Three implementation phases plus post-merge sanity, all on this same PR (#3672). 3-way matrix split (`webplat` / `bun` / `scripts`) with synthetic aggregator named `test`. No pre-Phase-1b BLOCKER — v1's spawn-count HALT gate dropped because `apps/web-platform` is Vitest, not Bun.

## Phase 0 — Measurement (commit 1)

- [x] **0.1** Instrument `scripts/test-all.sh` `run_suite()` with `EPOCHREALTIME` boundaries. Compute `elapsed_ms` via integer math on `seconds.microseconds`. Write tab-separated label/ms/status to `${TEST_TIMING_LOG:-/dev/null}`.
- [x] **0.2** Add script header comment documenting (a) `EPOCHREALTIME` requires bash 5+, (b) CI runs ubuntu-latest (bash 5.x), (c) macOS default `/bin/bash` is 3.2 — `bash` from Homebrew works.
- [x] **0.3** Run locally on Linux (or in this worktree's CI): `TEST_TIMING_LOG=/tmp/test-timing.tsv bash scripts/test-all.sh`. Save the tsv. **Result:** 38/38 green; webplat=41.7s, bun=44.6s, scripts=33.2s; max/min=1.34 → 3-way split confirmed.
- [x] **0.4** Run the spawn-count probe locally (informational only): `strace -fe trace=clone -c bun test plugins/soleur/ 2>/tmp/strace-summary.txt 1>/dev/null && grep clone /tmp/strace-summary.txt`. Record the `clone` count. NOTE: probe targets `bun test plugins/soleur/` (the actual largest bun-test invocation — `apps/web-platform` is Vitest and excluded from the FPE class). **Result:** 26,380 clone(2) syscalls on Bun 1.3.11 (includes worker threads). Informational only.
- [x] **0.5** Commit instrumentation. Message: `feat(ci): instrument test-all.sh with per-suite timing — #3680`. Push.
- [x] **0.6** Append a markdown table to PR #3672 body containing: (a) all 38 suite wall-clock timings sorted descending with top-5 in **bold**; (b) per-group aggregates (`webplat`, `bun`, `scripts`) and `max/min` ratio; (c) `bun test plugins/soleur/` clone(2) count (informational); (d) Phase 1b grouping decision (3-way default; collapse to 2-way only if `max/min ≥ 2.0` AND one of {bun, scripts} is the small side). **Decision:** max/min=1.34 < 2.0 → 3-way matrix confirmed.
- [x] **0.7** **NO HALT GATE.** v1's pre-Phase-1b BLOCKER (`apps/web-platform` clone(2) >130) is dropped — that target was misframed (Vitest, not Bun). Proceed to Phase 1a unconditionally.

## Phase 1a — TEST_GROUP selector (commit 2)

- [x] **1a.1** Edit `scripts/test-all.sh`: add `TEST_GROUP="${TEST_GROUP:-${1:-all}}"` after the version check; add the `case` validation arm exiting code 2 with stderr usage message on invalid value. Valid values: `all`, `webplat`, `bun`, `scripts`.
- [x] **1a.2** Define helper functions `want_scripts()`, `want_bun()`, `want_webplat()` returning truthy when `TEST_GROUP` matches.
- [x] **1a.3** Wrap the 11 pre-suite tests inside `if want_scripts; then ... fi`.
- [x] **1a.4** Wrap the 3 bun-named tests inside `if want_bun; then ... fi`.
- [x] **1a.5** Wrap the apps/web-platform vitest line inside `if want_webplat; then ... fi`.
- [x] **1a.6** Wrap `plugins/soleur` + `blog-link-validation` inside `if want_bun; then ... fi`. Inline comment explains co-location with `seo-aeo-drift-guard.test.ts` (perf reuse + defense against future xargs-P).
- [x] **1a.7** Wrap the `plugins/soleur/test/*.test.sh` glob loop inside `if want_scripts; then ... fi`.
- [x] **1a.8** Add header comment to `scripts/validate-blog-links.sh` documenting (a) the `_site/` co-location invariant with `seo-aeo-drift-guard.test.ts`, (b) shared `bun` TEST_GROUP, (c) perf-vs-correctness framing.
- [x] **1a.9** Verify locally — all five modes:
  - [x] `bash scripts/test-all.sh` (no args, all 38 suites — dispatch dry-run confirms 38)
  - [x] `bash scripts/test-all.sh webplat` (1 suite — apps/web-platform vitest only)
  - [x] `bash scripts/test-all.sh bun` (5 suites — 3 named bun + plugins/soleur + blog-link-validation; **end-to-end 5/5 green**)
  - [x] `bash scripts/test-all.sh scripts` (32 suites — 11 pre-suite + 21 *.test.sh)
  - [x] `bash scripts/test-all.sh bogus` (exits 2 with stderr usage naming all 4 valid values)
- [x] **1a.10** Verify env-vs-positional precedence: `TEST_GROUP=bun bash scripts/test-all.sh scripts` runs the bun group (5 suites — env wins).
- [ ] **1a.11** Commit. Message: `feat(ci): add TEST_GROUP selector to test-all.sh — #3680`. Push.
- [ ] **1a.12** Verify CI on the pushed commit: existing single `test` job passes (script invoked without args defaults to `all`, byte-identical behavior).

## Phase 1b — CI workflow restructure (commit 3)

- [ ] **1b.1** Edit `.github/workflows/ci.yml`: delete the existing `test` job definition.
- [ ] **1b.2** Add `test-webplat` job per Phase 1b YAML in plan. Steps: checkout, setup-bun, setup-node v22, `actions/cache@0057852bfaa89a56745cba8c7296529d2fc39830 # v4.3.0` keyed on `apps/web-platform/bun.lock` (caches `~/.bun/install/cache` + `apps/web-platform/node_modules`), `bun install --frozen-lockfile` in `apps/web-platform`, `npx tsc --noEmit` in `apps/web-platform`, `bash scripts/test-all.sh webplat`.
- [ ] **1b.3** Add `test-bun` job per Phase 1b YAML. Steps: checkout, setup-bun, setup-node v22 (for `npx eleventy` in validate-blog-links.sh), `actions/cache@0057852bfaa89a56745cba8c7296529d2fc39830 # v4.3.0` keyed on root `bun.lock` (caches `~/.bun/install/cache` + root `node_modules`), `bun install --frozen-lockfile` at root, `bash scripts/test-all.sh bun`.
- [ ] **1b.4** Add `test-scripts` job per Phase 1b YAML. Minimal: checkout + `bash scripts/test-all.sh scripts`. NO setup-bun, NO setup-node, NO cache, NO install (verified at plan time: zero `.test.sh` files invoke `bun`; python3 + bash ship on ubuntu-latest).
- [ ] **1b.5** Add synthetic `test` aggregator job: `needs: [test-webplat, test-bun, test-scripts]`, `if: always()`, per-shard `result` checks in a for-loop with explicit `fail=1; exit 1`. Include the load-bearing-sub-value comment naming cross-layer truing / drift-resilience / observability + the `scheduled-compound-promote.yml:291` precedent citation.
- [ ] **1b.6** Verify no `|| true`, no `continue-on-error: true` anywhere in the four new jobs: `git grep -nE "(\|\| true|continue-on-error: true)" .github/workflows/ci.yml` returns zero matches in the new job bodies.
- [ ] **1b.7** Drift safeguard: `git diff main...HEAD | grep -c telegram-bridge` MUST return 0. `git diff main...HEAD | grep -c bun.lockb` MUST return 0.
- [ ] **1b.8** Commit. Message: `feat(ci): split test job into webplat + bun + scripts shards with synthetic aggregator — #3680`. Push.
- [ ] **1b.9** Create three follow-up GitHub issues (verified labels: `chore`, `domain/engineering`, `priority/p3-low`, milestone `Post-MVP / Later`):
  - [ ] **1b.9.a** "ci: bun version probe for FPE-class re-evaluation" — body cites #3680 + the 2026-03-20 FPE learning + the re-evaluation trigger (every minor Bun bump). Note: probe targets bun-runtime test surfaces only (`test/`, `plugins/soleur/`), NOT `apps/web-platform/` (Vitest).
  - [ ] **1b.9.b** "ci: suite-internal split of apps/web-platform/test/" — body cites #3680 + Phase 2 trigger condition (webplat shard wall-clock dominates >100s consistently).
  - [ ] **1b.9.c** "ci: shard e2e job with --shard=2 + synthetic aggregator" — body cites #3680 + the test-job pattern as the template.
- [ ] **1b.10** Update PR #3672 body to link the three new issues under an "Out of scope (deferred follow-ups)" section.

## Phase 2 — Validation (mutation tests + 10-run wall-clock validation)

- [ ] **2.1 T14 SKIPPED-shard mutation tests — three sub-runs.** For each shard `test-webplat`, `test-bun`, `test-scripts`:
  - [ ] **2.1.a** Edit `.github/workflows/ci.yml` to add `if: false` directly to that shard. Commit (`test: validate aggregator fails closed on skipped <shard> — #3680 [REVERTME]`). Push. Wait for run to complete.
  - [ ] **2.1.b** Confirm via `gh run view <run-id> --json jobs`: the mutated shard has `conclusion: skipped`; synthetic `test` has `conclusion: failure`. Run `gh pr checks 3672` and confirm `test` is shown as failing.
  - [ ] **2.1.c** Revert the mutation: `git revert HEAD --no-edit`; push. Confirm next CI run is green before testing the next shard.
- [ ] **2.2** Execute 10 empty-commit-push cycles for wall-clock validation:
  ```bash
  for i in 1 2 3 4 5 6 7 8 9 10; do
    git commit --allow-empty -m "ci: validation run $i — #3680"
    git push
  done
  ```
- [ ] **2.3** Collect per-run timings via `gh run list --branch feat-ci-test-job-speedup --workflow ci.yml --limit 15 --json databaseId,createdAt,conclusion,jobs` + per-run drill-down. Compute median `test` aggregator duration. Compute per-shard medians for `test-webplat`, `test-bun`, `test-scripts`.
- [ ] **2.4** **VALIDATION GATE:** Confirm `test` aggregator wall-clock <130s on ≥6 of 10 runs AND 10/10 green. If <6/10 within target, execute Deferred-Items Item 2 (`apps/web-platform/` internal split) as a fix-on-same-PR follow-up commit. If any non-green, diagnose flake class before proceeding.
- [ ] **2.5** Append the 10-run timing distribution + the T14 mutation results (all three sub-runs) to PR #3672 body.
- [ ] **2.6** Mark PR #3672 ready-for-review (`gh pr ready 3672`).

## Phase 3 — Post-merge sanity

- [ ] **3.1** After merge to main, verify `gh api repos/jikig-ai/soleur/rulesets/14145388 --jq '.rules[] | select(.type=="required_status_checks") | .parameters.required_status_checks[].context'` returns the 5-context list identical to pre-merge.
- [ ] **3.2** Verify the merge commit's main-branch CI run: `test` aggregator green and wall-clock <130s. (11th green run — post-merge sanity.)
- [ ] **3.3** Verify the next PR opened against main shows `test` as a required status check, running, merge-gating. If missing, immediately revert the merge commit (`git revert <merge-sha>`; push).
- [ ] **3.4** Close #3680 with a comment linking to the merged PR and the three deferral issues (1b.9.a/b/c).

## Cross-phase

- [ ] **X.1** PR body uses `Closes #3680` (in body, not in title) — per `wg-use-closes-n-in-pr-body-not-title-to`.
- [ ] **X.2** `## User-Brand Impact` section appears in spec.md, plan, and PR body verbatim — single-user incident threshold preserved.
- [ ] **X.3** AC16 — `git diff main...HEAD | grep -c telegram-bridge` returns 0 at PR-ready time. Drift safeguard against v1's fabricated reference.
- [ ] **X.4** AC17 — `git diff main...HEAD | grep -c bun.lockb` returns 0 at PR-ready time. Drift safeguard against v1's wrong cache-key shape.
- [ ] **X.5** Capture compound learnings from this PR — at minimum (a) the plan-vs-codebase drift class encountered (5 v1 preconditions failed at /work start), (b) the synthetic-aggregator introduction pattern with 3-way matrix, (c) the `bun.lock` vs `bun.lockb` cache-key gotcha if not already captured.
