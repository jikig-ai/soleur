---
title: "CI test-job speedup — bun-vs-bash matrix split with synthetic aggregator"
status: Draft
lane: cross-domain
brand_survival_threshold: single-user incident
branch: feat-ci-test-job-speedup
pr: 3672
issue: 3680
brainstorm: knowledge-base/project/brainstorms/2026-05-12-ci-test-job-speedup-brainstorm.md
date: 2026-05-12
---

# Spec: CI test-job speedup — bun-vs-bash matrix split

**Issue:** #3680
**Branch:** feat-ci-test-job-speedup
**Draft PR:** #3672
**Status:** Draft
**Brainstorm:** `knowledge-base/project/brainstorms/2026-05-12-ci-test-job-speedup-brainstorm.md`

## Problem Statement

The `test` job in `.github/workflows/ci.yml` is the critical-path bottleneck on PR CI at ~199s wall-clock (per `gh run view 25729591818`, commit d9542f5c, 2026-05-12). The 164s `Run tests` step runs `bash scripts/test-all.sh`, which executes ~29 test suites strictly sequentially because Bun 1.3.5's spawn-count-sensitive SIGFPE crash class required per-suite process isolation (see `knowledge-base/project/learnings/2026-03-20-bun-fpe-spawn-count-sensitivity.md`). `test` is one of five required status checks on branch-protection ruleset 14145388, so its wall-clock directly gates merge time for every PR.

The secondary target is the 111s `Run E2E tests` step in the `e2e` job, where Playwright's native `--shard=N` support offers a mechanically isolated parallelism win.

## Goals

- G1: Reduce median `test` job wall-clock to <130s (down from ~199s); stretch <100s.
- G2: Reduce median `e2e` job wall-clock to <80s by running Playwright with `--shard=2`.
- G3: Preserve the `test-all.sh` orphan-suite invariant (PR #3512/#3533) — any new suite added under `plugins/soleur/test/*.test.sh`, `apps/*/test/`, or `test/` must be discovered without manual workflow edits.
- G4: Keep branch-protection ruleset 14145388 untouched — required checks (`test`, `e2e`) reconstructed via synthetic aggregator jobs.
- G5: Introduce no new flake class — 5/5 green runs on the validation pass.

## Non-Goals

- N1: Bun version bump (`.bun-version` stays at 1.3.11). The FPE-class probe is a separate follow-up PR — bundling would mask which change caused any regression.
- N2: Suite-internal split of `apps/web-platform/test/` into sub-directories. Deferred to follow-up if Phase 0 measurement shows the bun-side dominates >100s and A′ doesn't hit the target.
- N3: Approach B (`xargs -P` in-script). Rejected — three confirmed sharp edges on this codebase.
- N4: Approach D (`bun test --max-pool-size`). Rejected — re-creates the FPE spawn-pressure pattern.
- N5: Touched-file-aware test selection on PR. Violates orphan-suite invariant without complex preservation logic.
- N6: `web-platform-build` job optimization (75s next-build). Different bottleneck class.
- N7: Adding new test infrastructure (vitest, jest, playwright-test for unit tests). Work within `bun test` + `bash` toolchain.
- N8: `bun.lock`/`package-lock.json` changes. No dependency churn.
- N9: Ruleset 14145388 editing. Synthetic aggregator strategy makes this unnecessary.

## Functional Requirements

- FR1: `scripts/test-all.sh` MUST be instrumented with per-suite `date +%s.%N` timing boundaries (Phase 0 measurement). Output to stderr or a sidecar log; do not change `[ok]/[FAIL]` markers.
- FR2: `.github/workflows/ci.yml` `test` job MUST split into two parallel jobs: `test-bun` (runs the 6 bun-test suites in `test-all.sh` + `scripts/validate-blog-links.sh`) and `test-bash` (runs the 22 `plugins/soleur/test/*.test.sh` files).
- FR3: A synthetic aggregator job named exactly `test` MUST `needs: [test-bun, test-bash]` and emit pass/fail based on both shards. The aggregator MUST fail-closed (no `||` fallback per `2026-03-19-ci-squash-fallback-bypasses-merge-gates.md`).
- FR4: `scripts/validate-blog-links.sh` MUST land in `test-bun`, NOT `test-bash`, because it reads `_site/` which is built by `plugins/soleur/test/seo-aeo-drift-guard.test.ts` (also in `test-bun`). Co-location protects against the `_site/` race class.
- FR5: Both `test-bun` and `test-bash` MUST run `bun install --frozen-lockfile` (per `2026-03-18-bun-test-segfault-missing-deps.md`). `test-bash` needs deps because some `.test.sh` files invoke `bun` indirectly.
- FR6: An `actions/cache@v4` step MUST cache `~/.bun/install/cache` and `node_modules` keyed on `hashFiles('bun.lockb')`, present in both shards.
- FR7: `.github/workflows/ci.yml` `e2e` job MUST run Playwright with `--shard=${{ matrix.shard }}/2` across a 2-element matrix (`shard: [1, 2]`).
- FR8: A synthetic aggregator job named exactly `e2e` MUST `needs:` both Playwright shards and emit pass/fail.
- FR9: `bash scripts/test-all.sh` MUST remain a complete-discovery exit gate when invoked locally. The CI workflow change does NOT mutate `test-all.sh`'s behavior under direct invocation — it only consumes a subset via env-controlled filtering (e.g., `TEST_GROUP=bun bash scripts/test-all.sh` runs only the bun suites). Default invocation runs all 29 suites as before.
- FR10: The `test-all.sh` change MUST be backward-compatible — the script with no env vars set behaves identically to today.

## Technical Requirements

- TR1: Branch-protection ruleset 14145388 MUST NOT be edited. The `test` and `e2e` required contexts are reconstructed by aggregator jobs of the same names.
- TR2: Shard membership (which suite goes to which job) is encoded in `scripts/test-all.sh` itself via a `TEST_GROUP` env var (values: `bun`, `bash`, `all`; default `all`). The CI workflow passes `TEST_GROUP=bun` and `TEST_GROUP=bash` to the two shards. Suite discovery still happens dynamically inside `test-all.sh` — adding a new `.test.sh` to `plugins/soleur/test/` is auto-picked-up by `test-bash`.
- TR3: Bun version pinned at 1.3.11 via `.bun-version`. No upgrade in this PR.
- TR4: The `Enforce telegram-bridge coverage` step (`bun test --coverage` in `apps/telegram-bridge/`) stays in `test-bun` shard — it is already a separate step in the current `test` job, and it depends on `node_modules/` being installed.
- TR5: Phase 0 measurement instrumentation MUST be committed in a separate commit BEFORE the workflow restructure commit, so the per-suite timings appear in the PR as evidence backing the shard balance decision.
- TR6: Validation pass: the `test` and `e2e` aggregator jobs MUST be re-run 5 times each on the PR branch (via `gh workflow run` or push-trigger) and all 5 must pass green. Median wall-clock recorded in PR body.

## Components

| Component | Type | Path |
|-----------|------|------|
| Per-suite timing instrumentation | Modify | `scripts/test-all.sh` |
| TEST_GROUP env-var filtering | Modify | `scripts/test-all.sh` |
| `test-bun` matrix job | New | `.github/workflows/ci.yml` |
| `test-bash` matrix job | New | `.github/workflows/ci.yml` |
| `test` synthetic aggregator | New | `.github/workflows/ci.yml` |
| `e2e` Playwright sharding | Modify | `.github/workflows/ci.yml` |
| `e2e` synthetic aggregator | New | `.github/workflows/ci.yml` |
| Bun-install action cache | New | `.github/workflows/ci.yml` |
| Phase 0 measurement note | New | PR body |

## Success Criteria

- SC1: `gh run view <pr-run>` shows `test` aggregator wall-clock <130s on ≥3 of 5 validation runs (50% threshold). Stretch: <100s on ≥3 of 5.
- SC2: `gh run view <pr-run>` shows `e2e` aggregator wall-clock <80s on ≥3 of 5 validation runs.
- SC3: All 29 suites passing on every validation run (5/5 green).
- SC4: Branch-protection ruleset 14145388 unchanged (`gh api repos/jikig-ai/soleur/rulesets/14145388` returns identical contexts pre- and post-merge).
- SC5: PR body contains the Phase 0 per-suite timing table for all 29 suites, with top-5 highlighted and bun-side/bash-side aggregate totals.
- SC6: No new flake class — running the `test` and `e2e` jobs a 6th time after merge to main passes green (post-merge regression sanity).

## User-Brand Impact

(Carried forward from brainstorm Phase 0.1.)

- **Artifact:** the `test` and `e2e` required status checks on branch-protection ruleset 14145388 — the load-bearing merge gate for every PR including those touching regulated surfaces (GDPR transcript persistence #3603, payment flows, auth boundaries).
- **Vector:** three failure modes — (1) flake class introduced by parallelization erodes trust in red signal → real regression eventually merges; (2) `_site/` race corrupts the Eleventy build, blog links silently broken in production; (3) aggregator-job naming drift orphans the merge gate, blocks all team PRs.
- **Threshold:** single-user incident. Trust-breach probability low but regulated-surface blast radius non-trivial. Orphan-check is time-bound but team-blocking. Data-loss has low probability under the chosen approach.
- **Mitigation:** synthetic aggregator preserves the required-check contract without touching the ruleset; FR4 co-locates `_site/` builders; FR3 mandates fail-closed aggregator; SC3+SC6 require 6/6 green across validation + post-merge.

## Open Questions

- OQ1: Will Phase 0 measurement confirm bun-side/bash-side balance? If bash-side <40s and bun-side >120s, A′ doesn't hit the target. Pivot trigger: if measurement reveals imbalance >2:1, escalate to suite-internal split of `apps/web-platform/test/`.
- OQ2: Does the Bun 1.3.11 FPE class still trigger under directory-discovery? Probe is a separate follow-up issue (out of scope here).
- OQ3: Should the `_site/` EACCES class from PR #3654 produce a compound learning during this work? Yes — if the parallelism work hits it. If not, deferred.
