---
feature: web per-phase tool scoping parity (SDK-native phase-surface hint)
issue: 5772
parent_issue: 5768
lane: single-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
adr: ADR-070 (amend — resolve deferred shared-registry decision)
status: planned
created: 2026-06-30
---

# Spec: Web per-phase tool scoping parity (SDK-native phase-surface hint) — #5772 lever 1

## Problem Statement

The CLI ships L3 per-phase tool/skill scoping (#5769, ADR-070) via a PostToolUse(`Skill`)
hook (`.claude/hooks/phase-surface-hint.sh`) that injects a fail-open additive phase hint as
`hookSpecificOutput.additionalContext`. The **web Concierge** runs the same skill sequence
(`/soleur:go` as SDK router, ADR-022) but the web SDK agent sets `settingSources: []`
(`agent-runner-query-options.ts:155`) so it deliberately does **not** load `.claude/` hooks —
the CLI hook physically cannot fire for web agents. The web Concierge defaults to
`claude-sonnet-4-6` (`agent-runner-query-options.ts:150`), and the hardened eval (#5772
Criterion 1, PR #5792) shows the phase hint **measurably improves** Sonnet next-skill
selection (+6.7pts). So the win exists for the model the web actually runs, but web users get
none of it.

## Goals

- G1. Register an SDK-native, **fail-open additive** PostToolUse hook keyed off the `Skill`
  tool in `buildAgentQueryOptions` `options.hooks`, mirroring the CLI hook's behaviour
  (map `tool_input.skill` → phase → inject the phase's hint as `additionalContext`). One edit
  covers BOTH web paths (cc-soleur-go + legacy) since both build options via this helper.
- G2. Resolve ADR-070's explicitly-deferred shared-registry decision: the canonical map at
  `.claude/phase-surface-map.json` is unreachable in the web container; ship a bundled web copy
  with a CI parity test (ADR-053 three-coupling pattern).
- G3. Honour the two-tier fail-open rule (ADR-070): additive-hint only; never touch
  `canUseTool`/`disallowedTools`; the hook callback never throws into the SDK.

## Non-Goals

- N1. **Lever 2** (`disallowedTools` never-needed-per-phase subset) — out of scope; blocked on
  TR3 tool-attempt-vs-availability telemetry + an empirically-identified subset, neither of
  which exists. Tracked on #5772.
- N2. Tuning the `work→review` hint regression (work-phase surface foregrounds `qa`, competing
  with `review`) — affects the shipped CLI hint too; separate `phase-surface-map.json` tuning.
  **CLOSED 2026-07-01 (no change): not safely tunable at the current fixture size.** The
  "drop `qa` from work" fix is contradicted by the eval's own golden data — `qa` is a
  *legitimate* work-phase outcome (`tool-selection.jsonl:7`, a UI change needing the headless
  browser gate). The work phase genuinely fans out to three next-skills (`review` line 6, `qa`
  line 7, `test-fix-loop` line 8), so the "competition" is inherent situational ambiguity that
  the situation text disambiguates, not surface noise. The fixture has exactly one work→review
  and one work→qa case, so `--repeat 5` across the model grid cannot statistically resolve a
  subtle reorder/heuristic tweak (single-case noise). Any tuning touches THREE coupled surfaces
  in lockstep (`.claude/phase-surface-map.json`, the bundled `phase-surface-map.ts`, and the
  eval prompt `tool-selection-skill.txt:10`). Re-open only after expanding the work-phase golden
  tasks (several review-cases + qa-cases) so the eval can resolve the tradeoff. See
  `knowledge-base/project/learnings/2026-07-01-phase-surface-work-phase-tuning-is-fixture-limited.md`.
- N3. Any change to the `canUseTool` deny-by-default security floor.

## Functional Requirements

- FR1. A new hook module `apps/web-platform/server/phase-surface-hook.ts` exports
  `createPhaseSurfaceHook(): HookCallback`. On a PostToolUse event where `tool_name === "Skill"`,
  it reads `tool_input.skill`, **normalizes the key** (FR1a), maps it to a phase via the bundled
  map, and returns `{ hookSpecificOutput: { hookEventName: "PostToolUse", additionalContext:
  <hint> } }`.
- FR1a. **Key-format normalization (P0 — load-bearing, spec-flow):** the web Concierge emits
  **bare** workflow names in `tool_input.skill` (`"work"`, `"brainstorm"` — see `KNOWN_WORKFLOWS`
  `soleur-go-runner.ts:559` and the web fixture `soleur-go-runner-interactive-prompt.test.ts:256`),
  while the canonical map is **FQN-keyed** (`"soleur:work"`). A naive FQN lookup would miss EVERY
  real web call → silent no-op. The hook MUST normalize: `key = skill.includes(":") ? skill :
  "soleur:" + skill` before lookup, so both the bare web shape and the FQN CLI shape resolve. Tests
  use the **bare** shape as the primary case (FR1a is the difference between the feature working and
  shipping dead).
- FR2. **Fail-open:** for an unmapped skill, missing/empty skill, non-`Skill` tool,
  `SOLEUR_DISABLE_PHASE_HINT=1`, or ANY thrown error, the callback returns `{}` (no hint, full
  surface). The callback MUST NOT throw into the SDK.
- FR3. **Security parity with the CLI hook:** the model-controlled `skill` value is used ONLY as
  a map lookup key and is NEVER echoed into the hint; the hint is composed from map-derived
  constant text only (mirrors P1-1/P1-2/P1-3 of the shell hook). **Minimal sufficient guard set
  (security-sentinel F1 + code-simplicity — restore exact CLI parity, one gate on the model-controlled
  key):** (1) `typeof skill !== "string"` → null (the model may send a non-string); (2) normalize the
  key (FR1a); (3) `Object.hasOwn(map.skill_to_phase, key)` → else null — **this single own-property
  guard is the security gate** that rejects every inherited-key read (`__proto__`, `constructor`,
  `toString`); (4) look up `surface = map.phase_to_surface[phase]`; `if (!surface) return null` (a
  plain null-check, exactly mirroring the CLI hook's `$s == null`). NOTE — deliberately NOT added: a
  `typeof phase` check (dead under `as const` — `phase` is map-derived, no input can falsify it) and a
  hand-copied phase allowlist (it would duplicate `phase_to_surface`'s own keys and silently suppress
  a legitimately-added 6th phase, fighting the TR2 parity test). The CLI hook — ported under the same
  ADR-070 — has neither; adding them is divergence, not parity.
- FR4. The hint string is byte-equivalent in shape to the CLI hook's output (`[phase-scope] You
  are in the <phase> phase. Phase-relevant skills: … Phase-relevant agents: … Not yet live: …
  (Guidance only — all tools remain available; this never restricts what you can call.)`).
- FR5. `buildAgentQueryOptions` registers the hook as `PostToolUse: [{ matcher: "Skill", hooks:
  [createPhaseSurfaceHook()] }]` **only when `args.enablePhaseSurfaceHint === true`** (architecture
  P1-A — per-caller opt-in seam). The **cc-soleur-go Concierge router** (`cc-dispatcher.ts:2328`, the
  eval-covered workflow-routing path) opts in; the **legacy domain-leader runner**
  (`agent-runner.ts:1990`, no workflow-phase concept) does NOT, so it stays truly zero-change. This
  scopes the eval-justified behavior to the eval-covered path AND prevents the deferred fail-CLOSED
  lever 2 from inheriting a "both-callers-always-on" default that would silently restrict the
  legacy path (the exact ADR-070 unknown-tool hazard). The arg defaults to `false`/undefined.
- FR6. A bundled web map copy `apps/web-platform/server/phase-surface-map.ts` (exported const,
  guaranteed in `dist/server`) holds the same data as `.claude/phase-surface-map.json`.

## Technical Requirements

- TR1. SDK contract: `PostToolUseHookSpecificOutput = { hookEventName: 'PostToolUse';
  additionalContext?: string }`; `HookCallback = (input, toolUseID, options) => Promise<HookJSONOutput>`
  (`@anthropic-ai/claude-agent-sdk/sdk.d.ts` :1422, :537). Verified present in the installed SDK.
- TR2. **Parity test** `apps/web-platform/test/phase-surface-map-parity.test.ts` deep-equals the
  bundled copy against `.claude/phase-surface-map.json` (repo root is present in CI). Drift fails
  CI. This is the ADR-053 consistency coupling.
- TR3. **Observability:** the catch arm mirrors to Sentry via the existing silent-fallback helper
  (`reportSilentFallback`, used at `soleur-go-runner.ts:2120`) and logs `fail-open: no hint`.
  Discoverable from Sentry without SSH. **F5 (security-sentinel):** the raw model-controlled
  `skill` value MUST NOT appear in the log message, the Sentry `extra`, or the thrown error's
  `message` — otherwise it re-enters logs/Sentry as message-borne content, re-opening the
  log-injection/reflection surface the no-echo invariant closes. Use a static message string +
  the error object only.
- TR4. The drift-guard `stableShape` (T4) excludes `hooks`, so adding `PostToolUse` does not trip
  it; `agent-runner-query-options.test.ts` gains a positive assertion that `PostToolUse` is
  present with matcher `"Skill"`.

## Acceptance Criteria

See plan `knowledge-base/project/plans/2026-06-30-feat-web-sdk-phase-surface-hint-plan.md`.
