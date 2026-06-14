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

- [x] 1.1 Create `.github/enforcement-contracts.json` with `_doc` + `sibling_sets`
      seeded with `cron-tier2-parity`. No `mode`, no `format_contracts`.
- [x] 1.2 Verify every seeded path exists on disk (AC5) — passed.

## Phase 2 — Fixture (RED first)

- [x] 2.1 Write `.github/scripts/test/test-check-sweep-completeness.sh` (TS1-TS8,
      synthetic temp registry + changesets, drives the real executor, never `gh`).
- [x] 2.2 Confirmed RED (0 pass / 18 fail, executor absent).

## Phase 3 — Executor (GREEN)

- [x] 3.1 Write `.github/scripts/check-sweep-completeness.sh` (`set -uo pipefail`;
      `$1` registry / `$2` changeset-or-`-`; fail-closed; `jq empty` guard;
      registry self-consistency; exact `grep -Fxq`; aggregate across all sets).
- [x] 3.2 Fixture GREEN (18 pass / 0 fail).
- [x] 3.3 `bash .github/scripts/test/run-all.sh` exit 0; output names the fixture (AC3).

## Phase 4 — CI wiring

- [x] 4.1 Added `sweep-completeness` job to `pr-quality-guards.yml` (checkout + env;
      no opt-out label, modeled on `pii-grep`). YAML parses; shellcheck clean.
- [x] 4.2 Confirmed gate is a no-op on this PR's own changeset (AC4, exit 0).

## Phase 5 — Verification gates

- [x] 5.1 AC1 registry parses + 1 set; AC5 baseline paths exist.
- [x] 5.2 AC6 zero new AGENTS.md rules; `lint-agents-rule-budget.py` rc=0.
- [x] 5.3 AC7 `set -uo pipefail` confirmed (zero `set -euo`).
- [x] 5.4 Relevant suites green (fixture via `run-all.sh`; `scripts` shard). webplat/bun
      vitest shards not run — diff is `.github`-only; no suite references the touched files.

## Phase 6 — Deferral tracking

- [x] 6.1 Gap-1 tracking issue filed: #5283.
- [x] 6.2 Brainstorm defers (#5270/#5271/#5272) remain open.
