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

- [ ] 0.1 Probe that a PostToolUse(`Skill`) hook's `additionalContext` actually injects into the agent's context (stub hook emitting a sentinel; mirror `.claude/hooks/PERMISSION-DENIED-PAYLOAD-SHAPE.md` method). Record CC version + outcome.
  - [ ] 0.1.1 If it does NOT inject → STOP, take the Stop/UserPromptSubmit-hybrid fallback, re-scope. Do not ship dark. (AC0)

## Phase 1: Registry

- [ ] 1.1 Create `.claude/phase-surface-map.json` with `skill_to_phase` (brainstorm/plan/work/review/ship families) + `phase_to_surface` (relevant_skills, relevant_agents, not_live_note per phase). Leave `one-shot`/`go` unmapped. (AC1)

## Phase 2: The hook

- [ ] 2.1 Create `.claude/hooks/phase-surface-hint.sh` — PostToolUse, reads `tool_input.skill`, derives phase from the map, emits `{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:"<≤15-line hint>"}}`; unmapped/missing-map/jq-fail → emit nothing, exit 0. `set -uo pipefail`, ERR-trap discipline per `session-rules-loader.sh:196-200`, exit 0 on every path, no lock (static map).
- [ ] 2.2 Wire in `.claude/settings.json` under `PostToolUse`, matcher `Skill`. (AC4)

## Phase 3: Measurement (thin)

- [ ] 3.1 Add eval-harness `tool-selection` target: `promptfooconfig.tool-selection.yaml` + `prompts/tool-selection-skill.txt` + ≤5 golden tasks under `tasks/tool-selection/` (full-surface vs phase-scoped arm). Opt-in/manual; NOT CI-wired.
  - [ ] 3.1.1 Document the manual target in `eval-harness/SKILL.md`.

## Phase 4: ADR-070

- [ ] 4.1 Author ADR-070 via `/soleur:architecture` — two-tier fail-open rule + allowedTools/disallowedTools finding + `settingSources:[]` web-isolation + canonical shared-registry-location decision (#5772) + deferred-subset binding. (AC5)
  - [ ] 4.1.1 C4: confirm no `.c4` edit (enumeration in plan §Architecture Decision).

## Phase 5: Tests & verification

- [ ] 5.1 `.claude/hooks/phase-surface-hint.test.sh` — mapped→hint, unmapped→empty/exit0, missing-map→empty/exit0, + map consistency (keys→real SKILL.md; values→`phase_to_surface` keys; 5 core phases present). (AC2, AC3)
- [ ] 5.2 `bash scripts/test-all.sh scripts` green. (AC6)
- [ ] 5.3 PR body: Phase 0 probe result (AC0) + reference #5772 (AC7).

## Phase 6: Post-merge (operator)

- [ ] 6.1 Run the `tool-selection` eval locally; record full-surface vs phase-scoped wrong-tool rate + token spend in #5768 (AC(c) evidence). (AC8)
