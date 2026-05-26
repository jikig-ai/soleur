---
title: "Plan-skill phase order is load-bearing when one phase changes a contract another consumes"
date: 2026-05-10
category: integration-issues
tags:
  - plan-skill
  - phase-ordering
  - contract-change
  - bash-hooks
  - tdd
  - plan-review
module: plan-skill
issue: 3509
---

# Learning: Plan-skill phase order is load-bearing when one phase changes a contract another consumes

## Problem

The initial draft plan for #3509 (telemetry-drop sentinels) listed eight phases in a logical-grouping order:

- Phase 1: Schema doc + new helper file
- Phase 2: Hook-side emission (3 hooks)
- Phase 3: Rotation primitive contract change (`rotate_if_needed` returns 1 on failure instead of always returning 0)
- Phase 4: Aggregator updates
- ...

Phase 2 prescribed `if ! rotate_if_needed "$file"; then _emit_drop_sentinel ... rotation_fail; fi` at hook-side call sites. But on `main` today `rotate_if_needed` is hard-wired `return 0`. If Phase 2 lands first (or even within the same atomic PR but tested in Phase-2-isolation), the new wrapper is dead code — `rotate_if_needed` never returns non-zero, the `rotation_fail` sentinel never fires, and the Phase 2 hook tests for `rotation_fail` cannot pass. Tests would have to mock or skip; either way the plan's TDD ordering was broken.

Caught by `kieran-rails-reviewer` at plan-review time (P1). The original plan author (me) did not catch it during writing, and neither did the brainstorm Phase 0 review.

## Solution

Restructure phase order so contract-changing edits precede contract-consumer edits:

- Phase 1: Helper inline in `lib/incidents.sh` (foundations, dormant)
- Phase 2: **Rotation primitive contract change** (was Phase 3) — `return 1` on failure
- Phase 3: **Hook-side emission** (was Phase 2) — wires the new contract
- Phase 4: Aggregator updates + compound prose
- Phase 5: Cross-cutting tests

The atomic-PR constraint stayed (all phases ship in one merge — pre-PR `rule-metrics-aggregate.sh` would crash on sentinel input otherwise). What changed is the per-phase TDD ordering and the dependency narrative in the plan body. Acceptance criteria mapped to the new order at the same time.

## Key Insight

When a plan prescribes both a **contract-changing edit** (function signature, return-code semantics, schema field, env-var contract) AND a **contract-consumer edit**, the contract-changing edit's phase MUST come first — even when the entire PR is single-merge atomic. The plan is read sequentially during `/work`; out-of-order phases produce dead code or fail tests in the consumer phase before the contract phase has shipped.

This generalizes the existing plan-skill Sharp Edges that catch wrong globs, paraphrased file paths, prescribed labels that don't exist, and other "plan-asserts-X-but-X-isn't-true-yet" classes. The new wrinkle: **X may be true after the PR merges, but isn't true at any phase boundary inside the PR**. Atomic merge ≠ atomic per-phase TDD.

The recurring shape:

- Contract-changing edits look like: "X now returns 1 on Y", "Z accepts a new optional arg", "schema field W is required", "env-var V replaces flag F".
- Contract-consumer edits look like: "use the new return code", "pass the new arg", "filter by the new schema field", "read from the new env-var".

Without explicit phase ordering, the planner naturally lists phases by file (Phase 2: hook files, Phase 3: rotation lib) which is a logical grouping, not a TDD-correct ordering. The rule: list contract-changing files first, even when they're conceptually "infrastructure" and the consumers are "the actual feature".

## Session Errors

- **Phase ordering bug in original plan draft** — Phase 2 used a `rotate_if_needed` non-zero return contract that Phase 3 hadn't shipped yet. Recovery: restructured phase order in plan rewrite. Prevention: plan-skill SKILL.md Sharp Edge added (this session, see Route Learning to Definition).
- **`$HOOK_EVENT` undefined under `set -u` in original plan** — helper signature presumed a global var. Kieran P1. Recovery: changed signature to take literal hook_event string at each call site. Prevention: already covered by plan-review's strict-correctness reviewer (kieran-rails-reviewer always runs).
- **rule-metrics `valid_lines` metric drift** — sentinels would inflate the existing field. Kieran P1. Recovery: tightened filter to `select(.rule_id != null)` BEFORE the reduce. Prevention: already covered by plan-review.
- **Spec FR2/FR4 drift from plan body** — Kieran P3 caught divergence. Recovery: updated spec in same PR. Prevention: already covered by plan-review's spec-vs-plan reconciliation.
- **Original plan over-engineered helper file + runbook** — DHH + Simplicity converged on YAGNI cuts. Recovery: folded helper into `lib/incidents.sh`; dropped runbook. Prevention: already covered by plan-review's YAGNI reviewers (DHH + Simplicity always run).
- **Targeted file reads instead of full `repo-research-analyst` spawn** — soft AGENTS.md `cm-delegate-verbose-exploration-3-file` violation (5 reads in main context vs delegation). No correctness impact. Prevention: discoverability exit — error was visible at decision time; don't add a new rule.

## Tags

category: integration-issues
module: plan-skill
related: 2026-04-23-plan-quality-class-deepen-pass-catches, 2026-04-22-ts-sql-normalizer-parity-when-shipping-backfill-migration, 2026-05-07-tsc-not-source-grep-enumerates-exhaustiveness-rails
