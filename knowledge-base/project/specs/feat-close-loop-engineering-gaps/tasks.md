---
feature: close-loop-engineering-gaps
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-14-feat-close-loop-sweep-completeness-harness-plan.md
issue: 5269
date: 2026-06-14
---

# Tasks: Close-Loop Sweep-Completeness Gate

Derived from the finalized (post-review) plan. RED-first per `cq-write-failing-tests-before`.

## Phase 1 — Registry

- [ ] 1.1 Create `.github/enforcement-contracts.json` with a top-level `_doc` string and a
      `sibling_sets` array seeded with ONE entry: `cron-tier2-parity`
      (trigger `apps/web-platform/server/inngest/cron-manifest.ts`; dependents
      `cron-safe-commit-parity.test.ts` + `cron-shared.test.ts`; `reason`).
      No `mode`, no `format_contracts`.
- [ ] 1.2 Verify every seeded path exists on disk (`jq -r '.sibling_sets[]|(.trigger[],.dependents[])' | while read f; do test -f "$f" || echo MISSING:$f; done` → no output). (AC5)

## Phase 2 — Fixture (RED first)

- [ ] 2.1 Write `.github/scripts/test/test-check-sweep-completeness.sh` covering TS1-TS8 against
      a SYNTHETIC temp registry + synthetic changeset files (never the live registry, never `gh`);
      PASS/FAIL counter; `exit 1` if any case fails; runs with `PR_NUMBER`/`GH_REPO` unset.
- [ ] 2.2 Confirm it FAILS now (executor absent) — RED.

## Phase 3 — Executor (GREEN)

- [ ] 3.1 Write `.github/scripts/check-sweep-completeness.sh`:
  - [ ] 3.1.1 `#!/usr/bin/env bash` + `set -uo pipefail` (no `-e`). (AC7)
  - [ ] 3.1.2 Args: `$1` registry (default `.github/enforcement-contracts.json`); `$2` changeset file or `-` (stdin). `$2` short-circuits ALL `gh`/`PR_NUMBER` access.
  - [ ] 3.1.3 CI path (`$2` unset): `gh pr diff "$PR_NUMBER" --repo "$GH_REPO" --name-only`; on failure/empty → `exit 1` `::error::` (fail-closed, never exit 0).
  - [ ] 3.1.4 `jq empty "$1" || exit 1` before iterating; iterate `< <(jq -c '.sibling_sets[]? // empty' "$1")`.
  - [ ] 3.1.5 Registry self-consistency: every trigger/dependent path exists on disk (else exit 1); `dependents: []` → exit 1.
  - [ ] 3.1.6 Exact full-path match via `grep -Fxq` over the normalized changeset (strip blank/CRLF); no globs; no substring match.
  - [ ] 3.1.7 Aggregate across ALL sets; print every missing dependent; single `exit 1` at end; positive per-set confirmation on success; `.name // "(unnamed)"`.
- [ ] 3.2 Run the fixture → all TS1-TS8 PASS, exit 0 (GREEN). (AC2)
- [ ] 3.3 `bash .github/scripts/test/run-all.sh` exit 0; output includes `=== test-check-sweep-completeness.sh ===`. (AC3)

## Phase 4 — CI wiring

- [ ] 4.1 Add a sweep-completeness job to `.github/workflows/pr-quality-guards.yml`:
      `actions/checkout` (PR head) + `GH_TOKEN`/`PR_NUMBER`/`GH_REPO` env; run
      `check-sweep-completeness.sh`. No opt-out label (model on `pii-grep`; one-line rationale).
- [ ] 4.2 Confirm the job is green on THIS PR's diff (non-triggering → no-op). (AC4)

## Phase 5 — Verification gates

- [ ] 5.1 AC1 registry parses + ≥1 set; AC5 baseline paths exist.
- [ ] 5.2 AC6 zero new AGENTS.md rules; `lint-agents-rule-budget.py` exits 0.
- [ ] 5.3 AC7 `set -uo pipefail` confirmed.
- [ ] 5.4 Full relevant suites green (the fixture via `run-all.sh`; rule-budget via `scripts/test-all.sh`).

## Phase 6 — Deferral tracking

- [ ] 6.1 File a Gap-1 tracking issue (cited classes already CI-gated; build only on a recurring uncovered-class bypass; re-eval criterion documented). Milestone "Post-MVP / Later".
- [ ] 6.2 Confirm brainstorm defers (#5270/#5271/#5272) remain open and accurate.
