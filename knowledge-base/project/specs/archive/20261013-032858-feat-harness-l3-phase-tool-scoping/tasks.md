---
feature: harness-l3-phase-tool-scoping
issue: 5768
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-06-30-feat-harness-l3-phase-tool-scoping-plan.md
deferred_followup: 5772
---

# Tasks: L3 per-phase tool/skill scoping (CLI v1, #5768)

## Phase 0: Empirical probe (load-bearing assumption)

- [x] 0.1a Probe parent injection — CONFIRMED in CC 2.1.196: a stub PostToolUse(`Skill`) hook fired (`tool_name=Skill, skill=soleur:help, hook_event_name=PostToolUse`) and its `additionalContext` (`PROBE_SENTINEL_7F3A`) reached the model as a `<system-reminder>`. Not ship-dark. (AC0)
- [~] 0.1b Subagent case — NOT live-probed this session (parent case is definitive; forcing a subagent Skill call is expensive/flaky in-sandbox). **Fallback designed in:** the hook covers all parent-run phases (work/review/ship — the bulk); if a future check shows additionalContext does not reach a subagent's context, plan/deepen phases get the pointer via the skill bodies. Recorded in PR body as a known-unverified with the fallback. (AC0)

## Phase 1: Registry

- [x] 1.1 `.claude/phase-surface-map.json` created — `skill_to_phase` (16 skills, 5 phases) + `phase_to_surface`; `one-shot`/`go` left unmapped. (AC1)

## Phase 2: The hook

- [x] 2.1 `.claude/hooks/phase-surface-hint.sh` created — PostToolUse, stateless, fail-open (exit 0 every path). Mirrors `pencil-collapse-guard.sh` + `skill-invocation-logger.sh:46` + `session-rules-loader.sh` ERR-trap.
  - [x] 2.1.1 SECURITY P1-1/2/3 applied: hint = map-derived constant only (skill name never echoed); `jq -r --arg s` lookup; `jq -n --arg hint` envelope. Adversarial test passes.
- [x] 2.2 Wired in `.claude/settings.json` PostToolUse matcher `Skill`. (AC4)

## Phase 3: Measurement (thin)

- [x] 3.1 eval-harness `tool-selection` target — `promptfooconfig.tool-selection.yaml` + skill/baseline prompts + `enums/tool-selection.json` + 5 golden tasks at `tasks/tool-selection.jsonl` (flat file per existing eval-harness convention, NOT a `tasks/tool-selection/` subdir — plan authoritative for intent, codebase for paths). Opt-in/manual; not gated (no eval-gate block).
  - [x] 3.1.1 Documented the manual target in `eval-harness/SKILL.md`.

## Phase 4: ADR-070

- [x] 4.1 ADR-070 authored — two-tier fail-open rule + PostToolUse mechanism + allowedTools/disallowedTools finding + `settingSources:[]` web-isolation + shared-registry decision (#5772) + deferred-subset binding. (AC5)
  - [x] 4.1.1 C4: no `.c4` edit (enumeration in plan §Architecture Decision — no new external actor/system/store/access-edge; individual hooks aren't modeled components).

## Phase 5: Tests & verification

- [x] 5.1 `.claude/hooks/phase-surface-hint.test.sh` — 20/20 pass (behavior + consistency PARITY/dangling-phase + adversarial P2-1 + NEGATIVE). (AC2, AC3, AC0b)
- [~] 5.2 `bash scripts/test-all.sh scripts` — running (exit gate). (AC6)
- [ ] 5.3 PR body: Phase 0 probe result (AC0) + reference #5772 (AC7) — at ship.

## Phase 6: Post-merge (operator)

- [ ] 6.1 Run the `tool-selection` eval locally; record full-surface vs phase-scoped uplift + token spend in #5768 (AC(c) evidence). (AC8)
