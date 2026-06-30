---
feature: web SDK phase-surface hint (#5772 lever 1)
lane: single-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-06-30-feat-web-sdk-phase-surface-hint-plan.md
---

# Tasks — #5772 lever 1 (web SDK phase-surface hint)

## Phase 0 — Preconditions (verify, no code)
- [ ] 0.1 Confirm SDK types: `PostToolUseHookInput.tool_name`/`tool_input` + `PostToolUseHookSpecificOutput.additionalContext` (`@anthropic-ai/claude-agent-sdk/sdk.d.ts` :1414, :1422). (Done in plan research.)
- [ ] 0.2 Confirm the silent-fallback Sentry helper name (`reportSilentFallback`, `soleur-go-runner.ts:2120`).
- [ ] 0.3 Confirm `model.c4` `hooks` container description is free-text before editing (Phase 4.2 / AC7 render gate).

## Phase 1 — Bundled map copy (RED → GREEN)
- [ ] 1.1 RED: `apps/web-platform/test/phase-surface-map-parity.test.ts` — deep-equal `PHASE_SURFACE_MAP` vs `JSON.parse(.claude/phase-surface-map.json)`; repo root via `findRepoRoot()` walk (not `../../..`); assert canonical file exists. (AC4)
- [ ] 1.2 GREEN: `apps/web-platform/server/phase-surface-map.ts` — `export const PHASE_SURFACE_MAP = {…} as const`, faithful copy of canonical; header comment documents the BOTH-files coupling.

## Phase 2 — Hook module (RED → GREEN)
- [ ] 2.1 RED: `apps/web-platform/test/phase-surface-hook.test.ts` — cases:
  - [ ] (a) **bare** `{skill:"work"}` → hint contains `work` + `(Guidance only …)`; FQN `{skill:"soleur:work"}` → identical (AC1/AC1a, P0)
  - [ ] (b) unmapped (`one-shot`) → `{}`; (c) `tool_name:"Read"` → `{}`; (d) `SOLEUR_DISABLE_PHASE_HINT=1` → `{}`
  - [ ] (e) malformed (`tool_input:null`, missing/non-string skill) → `{}`, **no throw**; null-branch → clean `{}` (AC2/F3)
  - [ ] (f) byte-equal snapshot for a mapped skill; `__proto__`/`constructor`/`toString` → `{}`; crafted `"ship\u2028INJECT"` → `{}`, never echoed (AC3/F1/F2)
  - [ ] (g) factory does not throw at construction; throwing-internal hook still yields `{}` (AC1b/P1)
  - [ ] (h) `isSafeTool("Skill") === true` pin (AC1c/P2)
  - [ ] (i) catch arm: log/Sentry/error carry NO raw skill value (AC3b/F5)
- [ ] 2.2 GREEN: `apps/web-platform/server/phase-surface-hook.ts` — `SOLEUR_SKILL_PREFIX` const + WHY header; side-effect-free factory; `buildHint` **minimal guard set (CLI parity)**: env kill-switch (strict `==="1"`, per-invocation) → `typeof skill !== "string"` → normalize (`skill.includes(":") ? skill : SOLEUR_SKILL_PREFIX+skill`) → `Object.hasOwn(skill_to_phase, key)` (single security gate) → `surface = phase_to_surface[phase]; if(!surface) return null`. NO typeof-phase, NO phase allowlist. Map-derived hint only; try/catch → `reportSilentFallback` (static msg, no skill) + `{}`.

## Phase 3 — Wire into builder (per-caller opt-in, P1-A)
- [ ] 3.1 Add `enablePhaseSurfaceHint?: boolean` to `AgentQueryOptionsArgs` (default false).
- [ ] 3.2 Edit `agent-runner-query-options.ts`: import `createPhaseSurfaceHook`; register `PostToolUse: [{ matcher:"Skill", hooks:[createPhaseSurfaceHook()] }]` **conditionally** via spread when `args.enablePhaseSurfaceHint`. cc-dispatcher.ts:2328 passes `true`; agent-runner.ts:1990 does not.
- [ ] 3.3 Edit `agent-runner-query-options.test.ts`: flag-on → `hooks.PostToolUse[0].matcher==="Skill"`; flag-off → `hooks.PostToolUse` undefined (AC5). T4 `stableShape` UNCHANGED.

## Phase 4 — ADR + C4 (deliverables)
- [ ] 4.1 Amend `ADR-070`: record bundled-copy decision + 2 rejected alternatives + Consequences (cc-path eval-coverage caveat + bare/FQN normalization coupling) (AC8).
- [ ] 4.2 Edit `model.c4`: broaden `hooks` container description (advisory PostToolUse context); run `c4-code-syntax.test.ts` + `c4-render.test.ts`.

## Phase 5 — Verify
- [ ] 5.1 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (AC6).
- [ ] 5.2 `./node_modules/.bin/vitest run test/phase-surface-hook.test.ts test/phase-surface-map-parity.test.ts test/agent-runner-query-options.test.ts`.
- [ ] 5.3 Full suite (`package.json scripts.test`); C4 tests green (AC7).
- [ ] 5.4 PR body: `Ref #5772` (NOT Closes), `## Changelog`, `semver:minor` (AC9).

## Post-merge
- [ ] 6.1 QA (AC11): real web `/soleur:go` multi-phase run — confirm `[phase-scope]` reaches the model after a Skill call (Sentry/transcript); observe cadence on BOTH the cc-router and legacy paths (no skew). Non-blocking.
