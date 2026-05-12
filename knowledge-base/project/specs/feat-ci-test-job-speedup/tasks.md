---
title: "CI test-job speedup — tasks"
issue: 3680
pr: 3672
branch: feat-ci-test-job-speedup
plan: knowledge-base/project/plans/2026-05-12-feat-ci-test-job-speedup-plan.md
lane: cross-domain
brand_survival_threshold: single-user incident
date: 2026-05-12
---

# Tasks — feat-ci-test-job-speedup

Derived from `knowledge-base/project/plans/2026-05-12-feat-ci-test-job-speedup-plan.md`. Five phases, all on this same PR (#3672). One pre-merge BLOCKER is conditional on Phase 0 results (spawn-count probe).

## Phase 0 — Measurement (commit 1)

- [ ] **0.1** Instrument `scripts/test-all.sh` `run_suite()` with `EPOCHREALTIME` boundaries. Compute `elapsed_ms` via integer math on `seconds.microseconds`. Write tab-separated label/ms/status to `${TEST_TIMING_LOG:-/dev/null}`.
- [ ] **0.2** Add script header comment documenting (a) `EPOCHREALTIME` requires bash 5+, (b) CI runs ubuntu-latest (bash 5.x), (c) macOS default `/bin/bash` is 3.2 — `bash` from Homebrew works.
- [ ] **0.3** Run locally on Linux (or in this worktree's CI): `TEST_TIMING_LOG=/tmp/test-timing.tsv bash scripts/test-all.sh`. Save the tsv.
- [ ] **0.4** Run the spawn-count probe locally: `strace -fe trace=clone -c bun test apps/web-platform/ 2>/tmp/strace-summary.txt 1>/dev/null && grep clone /tmp/strace-summary.txt`. Record the `clone` count.
- [ ] **0.5** Commit instrumentation. Message: `feat(ci): instrument test-all.sh with per-suite timing — #3680`. Push.
- [ ] **0.6** Append a markdown table to PR #3672 body containing: (a) all 29 suite wall-clock timings sorted descending with top-5 in **bold**; (b) bun-side aggregate, bash-side aggregate, `max/min` ratio; (c) `apps/web-platform/` clone(2) count + verdict line (`<100: safe / 100-130: caution / >130: HALT`).
- [ ] **0.7 PIVOT GATE — conditional BLOCKER:** If clone(2) count >130, HALT and execute Deferred-Items Item 2 (`apps/web-platform/` suite-internal split) as a pre-Phase-1b commit on this same PR before continuing. If 100-130, proceed but document residual risk in PR body. If <100, proceed to Phase 1.

## Phase 1a — TEST_GROUP selector (commit 2)

- [ ] **1a.1** Edit `scripts/test-all.sh`: add `TEST_GROUP="${TEST_GROUP:-${1:-all}}"` after the version check; add the validation arm exiting code 2 with stderr usage message on invalid value.
- [ ] **1a.2** Wrap the 7 bun-side `run_suite` lines (content-publisher, x-community, pre-merge-rebase, apps/web-platform, apps/telegram-bridge, plugins/soleur, blog-link-validation) in `if [[ "$TEST_GROUP" == "all" || "$TEST_GROUP" == "bun" ]]; then ... fi`.
- [ ] **1a.3** Wrap the `plugins/soleur/test/*.test.sh` glob loop in `if [[ "$TEST_GROUP" == "all" || "$TEST_GROUP" == "bash" ]]; then ... fi`.
- [ ] **1a.4** Add inline comment above `blog-link-validation` line explaining: "Co-located with seo-aeo-drift-guard.test.ts (bun group); reads `_site/` which the test builds. DO NOT move to bash group — `_site/` race under matrix sharding."
- [ ] **1a.5** Add header comment to `scripts/validate-blog-links.sh` documenting the `_site/` co-location invariant; reference `scripts/test-all.sh` and `.github/workflows/ci.yml` `test-bun` job.
- [ ] **1a.6** Verify locally: `bash scripts/test-all.sh` (all), `bash scripts/test-all.sh bun`, `TEST_GROUP=bun bash scripts/test-all.sh`, `bash scripts/test-all.sh bash`, `bash scripts/test-all.sh invalid` — each behaves per AC2-AC5.
- [ ] **1a.7** Commit. Message: `feat(ci): add TEST_GROUP selector to test-all.sh — #3680`. Push.
- [ ] **1a.8** Verify CI on the pushed commit: existing single `test` job passes (script invoked without args defaults to `all`).

## Phase 1b — CI workflow restructure (commit 3)

- [ ] **1b.1** Edit `.github/workflows/ci.yml`: delete the existing `test` job definition.
- [ ] **1b.2** Add `test-bun` job per Phase 1b YAML in plan. Steps: checkout, setup-bun, `actions/cache@0057852bfaa89a56745cba8c7296529d2fc39830 # v4.3.0` with both `bun.lockb` files in hash, install deps (root + web-platform), `bunx tsc --noEmit` in `apps/web-platform`, `bash scripts/test-all.sh bun`, telegram-bridge coverage.
- [ ] **1b.3** Add `test-bash` job per Phase 1b YAML. Steps: checkout, setup-bun, `actions/cache@0057852bfaa89a56745cba8c7296529d2fc39830 # v4.3.0`, install deps (root only), `bash scripts/test-all.sh bash`.
- [ ] **1b.4** Add synthetic `test` aggregator job: `needs: [test-bun, test-bash]`, `if: always()`, per-shard `result` checks. Include the load-bearing-sub-value comment from Phase 1b YAML naming cross-layer truing / drift-resilience / observability + the `scheduled-compound-promote.yml:291` precedent citation.
- [ ] **1b.5** Verify no `|| true`, no `continue-on-error: true` anywhere in the three new jobs: `git grep -nE "(\|\| true|continue-on-error: true)" .github/workflows/ci.yml` returns zero matches.
- [ ] **1b.6** Commit. Message: `feat(ci): split test job into bun + bash shards with synthetic aggregator — #3680`. Push.
- [ ] **1b.7** Create three follow-up GitHub issues (verified labels: `chore`, `domain/engineering`, `priority/p3-low`, milestone `Post-MVP / Later`):
  - [ ] **1b.7.a** "ci: bun version probe for FPE-class re-evaluation" — body cites #3680 + the 2026-03-20 FPE learning + the re-evaluation trigger (every minor Bun bump).
  - [ ] **1b.7.b** "ci: suite-internal split of apps/web-platform/test/" — body cites #3680 + Phase 2 trigger condition.
  - [ ] **1b.7.c** "ci: shard e2e job with --shard=2 + synthetic aggregator" — body cites #3680 + the test-job pattern as the template.
- [ ] **1b.8** Update PR #3672 body to link the three new issues under an "Out of scope (deferred follow-ups)" section.

## Phase 2 — Validation (no commits beyond mutation test; PR-level — 10 runs + T14)

- [ ] **2.1 T14 SKIPPED-shard mutation test.** Edit `.github/workflows/ci.yml` to add `if: false` directly to `test-bun`. Commit (`test: validate aggregator fails closed on skipped shard — #3680 [REVERTME]`). Push. Wait for run to complete.
- [ ] **2.2** Confirm via `gh run view <run-id> --json jobs`: `test-bun` has `conclusion: skipped`; synthetic `test` has `conclusion: failure`. Run `gh pr checks 3672` and confirm `test` is shown as failing.
- [ ] **2.3** Revert the mutation: `git revert HEAD --no-edit`; push. Confirm next CI run is green.
- [ ] **2.4** Execute 10 empty-commit-push cycles for validation:
  ```bash
  for i in 1 2 3 4 5 6 7 8 9 10; do
    git commit --allow-empty -m "ci: validation run $i — #3680"
    git push
  done
  ```
- [ ] **2.5** Collect per-run timings via `gh run list --branch feat-ci-test-job-speedup --workflow ci.yml --limit 15 --json databaseId,createdAt,conclusion,jobs` + per-run drill-down. Compute median `test` aggregator duration.
- [ ] **2.6** **VALIDATION GATE:** Confirm `test` aggregator wall-clock <130s on ≥6 of 10 runs AND 10/10 green. If <6/10 within target, execute Deferred-Items Item 2 (`apps/web-platform/` internal split) as a fix-on-same-PR follow-up commit. If any non-green, diagnose flake class before proceeding.
- [ ] **2.7** Append the 10-run timing distribution + the T14 mutation result to PR #3672 body.
- [ ] **2.8** Mark PR #3672 ready-for-review (`gh pr ready 3672`).

## Phase 3 — Post-merge sanity

- [ ] **3.1** After merge to main, verify `gh api repos/jikig-ai/soleur/rulesets/14145388 --jq '.rules[] | select(.type=="required_status_checks") | .parameters.required_status_checks[].context'` returns the 5-context list identical to pre-merge.
- [ ] **3.2** Verify the merge commit's main-branch CI run: `test` aggregator green and wall-clock <130s. (11th green run — post-merge sanity.)
- [ ] **3.3** Verify the next PR opened against main shows `test` as a required status check, running, merge-gating. If missing, immediately revert the merge commit (`git revert <merge-sha>`; push).
- [ ] **3.4** Close #3680 with a comment linking to the merged PR and the three deferral issues (1b.7.a/b/c).

## Cross-phase

- [ ] **X.1** PR body uses `Closes #3680` (in body, not in title) — per `wg-use-closes-n-in-pr-body-not-title-to`.
- [ ] **X.2** `## User-Brand Impact` section appears in spec.md, plan, and PR body verbatim — single-user incident threshold preserved.
- [ ] **X.3** Capture compound learnings from this PR — at minimum any `_site/` EACCES class encountered (no existing learning), the synthetic-aggregator introduction pattern, and any spawn-count-instrumentation gotchas.
