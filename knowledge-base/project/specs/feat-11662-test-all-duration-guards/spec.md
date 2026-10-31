---
title: test-all duration budgets + selection caps — anti-regrow guards
status: draft
owner: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-10-30-test-all-duration-guards-brainstorm.md
closes: 11662
created: 2026-10-30
---

# Spec: test-all anti-regrow guards (#11662)

## Problem Statement

`scripts/test-all.sh` regressed to ~3 h wall-clock on the operator's host (704
registrations, ~121 min serial committed weight, 2026-10-30). Duration weight enters the
tree with no gate: `regenerate-shard-manifest.py` refuses only shape errors, committed
weights cap only the always-on tier, and nothing notices a suite doubling or the corpus
growing. The battery regrew silently and can regrow again.

## Goals

- **G1.** `regenerate-shard-manifest.py` refuses `--write` when a per-suite weight jump or
  total-corpus growth exceeds a declared threshold, computed on `src=measured` rows, with
  an explicit `--allow-growth` override. (Issue #11662 proposal 2.)
- **G2.** A committed-weight per-suite budget covers the whole registered corpus (not only
  `ALWAYS_ON_SUITES`), with an exemptions ledger for declared-big suites — the
  `test-all-fast-tier-budget` pattern extended, never wall-clock. (Proposal 1, reframed.)
- **G3.** `ALWAYS_ON_SUITES` gains a count ceiling (`live_floor + N`) and a machine-checked
  why-always-on ledger in a sidecar file (never in `test-affected-paths.sh` comments —
  INDEX-ANCHOR degradation). (Proposal 3 remainder.)
- **G4.** `lint-orphan-test-suites` gains the registration→file direction: a `run_suite`
  registration whose command target no longer exists reds statically. (Proposal 8.)

## Non-Goals

- **NG1.** Blocking lock / queue-timeout semantics — deferred to the follow-on issue
  (ADR-133 rejects abort-on-timeout; sanctioned delta is queue-timeout→exit-4 for `--full`
  + `TC_RUNTIME_CEILING_S` default-on).
- **NG2.** Shard-count scaling — manifest is already n=8 duration-aware; width scaling is a
  #11556-epic lever.
- **NG3.** Watch/soak suite demotion to a scheduled tier — deferred (needs a new scheduled
  leg + selection-decline class + manifest/orphan-lint parity in one commit).
- **NG4.** Meta-suite shallow-fixture mode — deferred (must keep ≥1 full-corpus arm;
  row-tiling requirement).
- **NG5.** Any `merge_group`/CI-battery reduction — ADR-276 hard wall.
- **NG6.** Suite-result memoization or parallel-by-default — recorded rejections.

## Functional Requirements

- **FR1.** The drift gate splits its delta into count growth (new registrations) vs
  duration growth (the drift signal); thresholds are value-pinned literals with a
  `--allow-growth` escape that refuses before `--write`.
- **FR2.** The corpus budget reads `suite-durations*.tsv` committed weights; a suite with
  no weight row reds (or sits in a pinned, three-direction-closed allowlist); exemptions
  live in a ledger file with a reason column.
- **FR3.** Every new guard ships with: totality check on its scan population, synthetic
  red+green fixture arms (a predicate that never fails is untested), exact-line
  registration pins, and a `suite-durations.tsv` floor row if registered.
- **FR4.** The always-on ceiling is expressed relative to the derived live floor, not a
  fixed constant (a fixed ceiling collides with `lint-orphan`'s derived floor).
- **FR5.** The legal-control suite set (TOM-4 RLS, PA-22, lint-legal-*, art30,
  dpa-register, gdpr-gate-glob-liveness) is enumerated in the plan and exempt from census
  removal and demotion — CLO requirement.

## Technical Requirements

- **TR1.** Guards land in `regenerate-shard-manifest.py`, `lint-orphan-test-suites.sh`,
  sidecar TSVs, and new suite files — `test-all.sh` edits are minimized (every edit pays
  the `runner-changed` full-battery fallback).
- **TR2.** Baselines diff against merge-base, never moving `origin/main` tip; fail closed
  on unresolvable base; deliberate removals are ack-edits, not exemptions.
- **TR3.** Scope/mode selection is flag-selected, never env-selected (env forks the nested
  `--enumerate-commands` self-call).
- **TR4.** No new verdict-class spelling; any new failure class is additive to the
  documented 0/1/2/3/4 exit contract.
- **TR5.** Cross-link #11648 (fast-tier drift demotion) and #11564 (balance-watch probe)
  so the drift gate doesn't re-derive their scope.

## Deferred (follow-on issue, filed at brainstorm end)

Watch/soak scheduled-tier demotion, meta-suite cost work, queue-timeout→exit-4 for
`--full`, `TC_RUNTIME_CEILING_S` default-on, parallel-default revisit after #7376 — all
gated on #11561 landing (the two dominant atomic suites are its split targets).
