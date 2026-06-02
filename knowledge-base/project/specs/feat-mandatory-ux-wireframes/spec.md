---
title: Mandatory UX Wireframes + Stale-Claim Hardening
feature: feat-mandatory-ux-wireframes
date: 2026-06-02
status: draft
lane: cross-domain
brand_survival_threshold: none
brainstorm: knowledge-base/project/brainstorms/2026-06-02-mandatory-ux-wireframes-and-stale-claim-hardening-brainstorm.md
related_issues: [4819, 4817]
---

# Spec: Mandatory UX Wireframes + Stale-Claim Hardening

## Problem Statement

Two workflow gaps surfaced in one session. (1) ux-design-lead `.pen` wireframes are an
auto-spawned-but-**skippable** step for UI features — research found **9 distinct skip
sites** (3 in brainstorm Phase 3.55, 6 in plan Phase 2.5), and on the one-shot path (which
skips brainstorm) a UI feature can ship with zero wireframes. (2) The orchestrator asserted
**false stale claims** about repo capabilities ("pencil-setup can't auto-install"; "Pencil is
GUI-only") — including as a load-bearing premise injected into a subagent prompt — because the
repo's premise-validation machinery is scoped only to *cited artifacts*, not the orchestrator's
own claims or subagent-prompt premises.

## Goals

- G1. Make `.pen` wireframes a non-skippable deliverable for any new/changed UI surface;
  remove "skipped" as a permitted outcome.
- G2. When Pencil MCP is unavailable: auto-install (`pencil-setup --auto`) then hard-block
  only if auth (`PENCIL_CLI_KEY`) or Node ≥ 22.9.0 is genuinely unsatisfiable.
- G3. Close the one-shot gap: plan Phase 2.5 must *generate* (not just verify) wireframes.
- G4. Prevent stale capability claims via two hard rules + extended premise-validation phases.
- G5. Promote the demoted UX-gate constitution principle (line 177) to a live AGENTS.md `wg-*`.

## Non-Goals

- NG1. No non-Pencil (Markdown/ASCII/HTML) wireframe fallback (headless `.pen` works).
- NG2. No new CI/Docker headless-Pencil provisioning beyond ensuring `PENCIL_CLI_KEY` exists.
- NG3. No change to ux-design-lead's `.pen` authoring itself or the `knowledge-base/product/design/`
  output convention.
- NG4. Hedge-word verify-trigger scoped to *this-repo* artifact claims, not general facts.

## Functional Requirements

### Feature A — Mandatory wireframes

- FR1. Brainstorm Phase 3.55: replace the 3 skip clauses (`SKILL.md:406` no-UI heuristic kept
  as the *trigger*; `:419` headless; `:421` Pencil-unavailable) so that for a UI-surface
  feature the only outcomes are `.pen committed` or `hard-block`. Headless/Pencil-unavailable
  must first run the `--auto` install attempt.
- FR2. Plan Phase 2.5: close the `Skipped specialists:` leak at `SKILL.md:321` (BLOCKING
  self-stop). On the one-shot/pipeline path, Phase 2.5 must *produce* the wireframe (sole
  producer). Verifier asserts the **`.pen` artifact exists on disk** under
  `knowledge-base/product/design/{domain}/` and is referenced in the spec FRs.
- FR3. Auto-install-then-block sequence: detect `mcp__pencil__*` → if absent run
  `pencil-setup --auto` (sources `PENCIL_CLI_KEY` from Doppler) → hard-block with one
  instruction only if auth/Node unsatisfiable.
- FR4. deepen-plan: add a halt (mirroring Phase 4.6/4.7) that greps the plan for a wireframe-
  artifact reference when UI surfaces are touched; HALT + telemetry if absent.
- FR5. Shared UI-surface term-list reference cited by both brainstorm + plan; plan keeps its
  mechanical file-glob escalation as a superset.
- FR6. Promote constitution line 177 (`ex-wg-for-user-facing-pages...`) to a live AGENTS.md
  workflow gate (new immutable `wg-*` ID) with rule-fire telemetry.

### Feature B — Stale-claim hardening

- FR7. AGENTS.md hard rule (subagent-prompt premises): a limiting factual premise about repo
  state in a subagent prompt must be grep/read-verified before spawn OR phrased as a question.
- FR8. AGENTS.md hard rule (verify-before-assert): grep before asserting repo-capability
  claims; hedge words (`only/doesn't/can't/no longer/to my knowledge/I believe/likely`) about
  repo state are the verify-trigger.
- FR9. Extend brainstorm Phase 0.6/1.1 + plan Phase 0.6 to cover the orchestrator's own
  option-bounding capability claims, not just cited references.
- FR10. Learning file capturing the pencil-auto-install false-claim incident.

## Technical Requirements

- TR1. New AGENTS.md rule IDs are additive; the demoted `ex-wg-...` ID stays (immutable per
  `cq-rule-ids-are-immutable`). Verify loader-class fit for the new `wg-*` (UI source = code
  class; plan/spec edits = docs-only) per the loader-class-fit Sharp Edge before placement.
- TR2. Word/byte budgets: new SKILL.md text must respect the 1800-word description cap
  (`cq-skill-description-budget-headroom`) and AGENTS.md rule-body budget — measure before edit.
- TR3. `PENCIL_CLI_KEY`: confirm Doppler config (`soleur/dev` per SKILL.md:108 vs `prd`) and
  whether it is provisioned; add a provisioning task if absent (Open Question #1).
- TR4. Tests: extend `plugins/soleur/test/` skill-structure tests to assert the brainstorm/plan
  skip clauses are gone and the AGENTS rules exist; verify against the runner the package uses
  (check `package.json scripts.test` / `bunfig.toml`).

## Acceptance Criteria

- AC1. Grep brainstorm + plan SKILL.md: no reachable "skip"/"Skipped specialists" outcome for a
  UI-surface feature; only `.pen committed` or `hard-block`.
- AC2. one-shot path: a UI feature with no carried-forward wireframe causes plan Phase 2.5 to
  produce one (or hard-block) — not record a skip.
- AC3. AGENTS.md contains the two new hard rules (FR7, FR8) + the promoted wireframe `wg-*`,
  passing `scripts/lint-rule-ids.py` + the rule-budget lint.
- AC4. deepen-plan halts on a UI plan missing a wireframe-artifact reference.
- AC5. Learning file exists documenting the false-claim incident.
- AC6. New/changed skill text within budget; `plugins/soleur/test` green.

## Open Questions (resolve in plan)

1. `PENCIL_CLI_KEY` Doppler config + whether provisioned (TR3).
2. AGENTS `wg-*` loader-class-fit + sidecar placement (TR1).
3. Empirical headless `.pen` authoring in this runner (/work Phase 0 precondition).
4. Hedge-word rule false-positive scoping (FR8 / NG4).

## Domain Review

**Domains relevant:** Engineering (CTO — assessed in brainstorm, carried forward), Product
(operator-decided). This plan discusses UI concepts but implements orchestration/docs changes →
Product/UX Gate tier **NONE** (no recursion; per plan SKILL.md:312).
