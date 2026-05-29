---
title: "Tasks — Phase 7 Monitor gate enforcement"
plan: "../../plans/2026-05-29-fix-phase7-monitor-gate-enforcement-plan.md"
branch: feat-fix-phase7-monitor-gate-enforcement
lane: engineering
---

# Tasks — elevate the Monitor-vs-run_in_background gate

## Phase 1 — Always-loaded rule
- [x] 1.1 Add `hr-monitor-not-run-in-background-for-polling` to AGENTS.md index → core.
- [x] 1.2 Add rule body to AGENTS.core.md (≤600B; hook + skill enforcement cites).

## Phase 2 — Deterministic hook
- [x] 2.1 Write `.claude/hooks/background-poll-prefer-monitor.sh` (AND-gated deny; override marker).
- [x] 2.2 Write `.test.sh` (13 cases: 5 deny, 8 allow incl. false-positive guards).
- [x] 2.3 Register in `.claude/settings.json` PreToolUse(Bash); validate JSON.
- [x] 2.4 Hook test green; hookeventname-coverage green.

## Phase 3 — Close the skill seams
- [x] 3.1 one-shot Step 7: merge-wait ownership rule (no hand-rolling, no fast-path).
- [x] 3.2 schedule verify-after-trigger: `gh run watch` → Monitor-tool loop.

## Phase 4 — Validate + document
- [x] 4.1 `lint-agents-enforcement-tags.py` exits 0.
- [x] 4.2 Learning file (workflow-gap durable artifact).
- [ ] 4.3 File tracking issue for pre-existing `B_ALWAYS` rule-budget overage.

## Acceptance gates
- [x] Rule id present in index + body exactly once; body ≤600B.
- [x] Hook denies the exact incident pattern; allows builds/single-shot/local/write/override.
- [x] No CI-gating linter regressed (rule-budget is advisory, not wired into CI; pre-existing over).
