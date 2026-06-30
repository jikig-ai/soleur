---
title: "feat(harness): web per-phase tool scoping parity (SDK-native phase-surface hint)"
issue: 5772
parent_issue: 5768
lane: single-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
adr: ADR-070 (amend)
created: 2026-06-30
---

# ✨ feat(harness): web per-phase tool scoping parity (SDK-native phase-surface hint) — #5772 lever 1

## Overview

Port the CLI's L3 per-phase tool/skill scoping (#5769, ADR-070) to the **web Concierge** agent
runtime. The CLI hint is a `PostToolUse(Skill)` shell hook (`.claude/hooks/phase-surface-hint.sh`)
that injects a fail-open additive phase hint as `additionalContext`. The web SDK agent runs with
`settingSources: []` so it cannot load `.claude/` hooks — it needs its own SDK-native hook
registered in `buildAgentQueryOptions` `options.hooks`. This is **lever 1 only**; lever 2
(`disallowedTools` subset) stays deferred (N1).

**Gate status (why now):** #5772 Criterion 1 is met. The hardened eval (PR #5792) shows the phase
hint improves next-skill selection by +6.7pts on `claude-sonnet-4-6` — the model the web
Concierge defaults to (`agent-runner-query-options.ts:150`). Evidence recorded on #5772.

**Scope:** ~2 new source files + 1 helper edit + 3 test files + 1 ADR amendment + 1 C4 line.
The single edit to `buildAgentQueryOptions` covers BOTH web paths (cc-soleur-go and legacy) — they
share the builder.

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality (verified) | Plan response |
|---|---|---|
| Web hook can read `.claude/phase-surface-map.json` at runtime | **NO** — Dockerfile copies only `public/`, `.next/`, `dist/server/`, `next.config.mjs`, `_plugin-vendored/`→`/opt/soleur/plugin/`; `.claude/` is excluded (`.dockerignore:23`) | Bundle a web copy as a `.ts` const module compiled into `dist/server` (FR6); parity test guards drift (TR2) |
| SDK PostToolUse supports `additionalContext` | YES — `PostToolUseHookSpecificOutput.additionalContext?: string` (`sdk.d.ts:1422`); `SyncHookJSONOutput.hookSpecificOutput` accepts it (`:3974`) | Direct JS port of the shell hook (FR1) |
| Adding `PostToolUse` trips the T4 drift-guard | NO — `stableShape` SHARED_KEYS excludes `hooks` (`agent-runner-query-options.test.ts:213`) | Add a positive `PostToolUse`/matcher assertion instead (TR4) |
| Web agent invokes the `Skill` tool | YES — `soleur-go-runner.ts:2113` detects first `Skill` call; Skill is in the plugin surface, not in `disallowedTools` | Hook fires after every `Skill` execution on both paths (FR5) |
| `resolveJsonModule` available for a `.json` copy | YES (`tsconfig.json:12`) but build-inclusion of a sibling `.json` into `dist/server` is build-mechanism-dependent | Use a `.ts` const module (always compiled into the bundle) — removes the inclusion risk |

**Premise validation:** #5768 CLOSED via #5769 (MERGED 2026-06-30); #5772 OPEN; ADR-070, ADR-022
present; all cited `agent-runner-query-options.ts` symbols confirmed at the documented lines. No
stale premises.

## User-Brand Impact

**If this lands broken, the user experiences:** a web Concierge agent turn that aborts or hangs
mid-workflow — if the new PostToolUse hook threw into the SDK after a `Skill` call, the paying
user's session would break at every routing step.

**If this leaks, the user's workflow is exposed via:** the hook reads the model-controlled
`tool_input.skill` value; if that value were echoed into the injected `additionalContext`, a
prompt-injected model (WebFetch/research flow) could smuggle attacker text into its own context.
Mitigation: the skill value is a lookup key ONLY and is never echoed (FR3, mirrors the CLI hook's
P1-1/P1-2/P1-3).

**Brand-survival threshold:** single-user incident.

> CPO sign-off required at plan time (frontmatter `requires_cpo_signoff: true`). No UI surface, so
> the sign-off is an approach-ack, not a UX review. `user-impact-reviewer` runs at PR-review time
> (the load-bearing gate). The decisive mitigation is FR2 — the callback is wrapped in try/catch
> and returns `{}` on any error, so the worst realistic failure is "no hint" = current behaviour
> (zero regression), never a broken turn.

## Implementation Phases

### Phase 0 — Preconditions (verify, no code)
1. Confirm `@anthropic-ai/claude-agent-sdk/sdk.d.ts` exposes `PostToolUseHookInput` (`tool_name`,
   `tool_input`) and `PostToolUseHookSpecificOutput.additionalContext` (already verified :1414, :1422).
2. Confirm the silent-fallback Sentry helper name used elsewhere in `server/` (e.g.
   `reportSilentFallback`) so TR3 mirrors via the established path, not a bespoke `Sentry.captureException`.

### Phase 1 — Bundled map copy (RED test first)
1. Write `apps/web-platform/test/phase-surface-map-parity.test.ts` (RED): deep-equal
   `JSON.parse(readFileSync("<repo-root>/.claude/phase-surface-map.json"))` against the imported
   `PHASE_SURFACE_MAP`. Resolve repo root relative to the test file (`../../..`).
2. Create `apps/web-platform/server/phase-surface-map.ts`: `export const PHASE_SURFACE_MAP = { … }
   as const` — a faithful copy of `.claude/phase-surface-map.json` (drop the `_comment` key or keep
   it; the parity test defines the contract). Add a header comment: "Bundled web copy of the
   canonical `.claude/phase-surface-map.json`; edit BOTH and keep the parity test green (ADR-070,
   ADR-053)." GREEN.

### Phase 2 — The hook module (RED test first)
1. Write `apps/web-platform/test/phase-surface-hook.test.ts` (RED), cases:
   (a) `{tool_name:"Skill", tool_input:{skill:"soleur:work"}}` → `additionalContext` contains `work`;
   (b) unmapped skill → `{}`;
   (c) `tool_name:"Read"` → `{}`;
   (d) `SOLEUR_DISABLE_PHASE_HINT=1` → `{}`;
   (e) malformed input (`tool_input:null`, missing `skill`) → `{}` and **does not throw**;
   (f) the emitted `additionalContext` NEVER contains the raw skill token for a crafted skill name
   (security FR3) — e.g. `skill:"soleur:work<INJECT>"` is unmapped → `{}`, and a mapped skill's hint
   contains the phase name but not the skill string.
2. Create `apps/web-platform/server/phase-surface-hook.ts`:
   - `import { PHASE_SURFACE_MAP } from "./phase-surface-map";`
   - pure `buildHint(skill): string | null` — `process.env.SOLEUR_DISABLE_PHASE_HINT==="1"` (strict,
     not truthy) → null; **security guards (F1):** `typeof skill !== "string"` → null;
     `Object.hasOwn(map.skill_to_phase, skill)` guard → null; `typeof phase !== "string"` → null;
     `Object.hasOwn(map.phase_to_surface, phase)` guard → null; phase ∈ `{brainstorm,plan,work,
     review,ship}` allowlist → else null; then compose the FR4 string from map-derived constants
     only (skill NEVER interpolated). Read the env var per-invocation (not cached at module load).
   - `export function createPhaseSurfaceHook(): HookCallback` returning an async callback that:
     casts input to `PostToolUseHookInput`; returns `{}` unless `tool_name==="Skill"`; reads
     `(tool_input as {skill?:string}).skill`; `buildHint`; returns `{ hookSpecificOutput:{
     hookEventName:"PostToolUse", additionalContext:hint } }` or `{}`; wraps the whole body in
     try/catch → on error `log.warn` + Sentry mirror (TR3) + return `{}`. GREEN.

### Phase 3 — Wire into the builder
1. Edit `apps/web-platform/server/agent-runner-query-options.ts`: import `createPhaseSurfaceHook`;
   add to the `hooks` object:
   ```ts
   PostToolUse: [{ matcher: "Skill", hooks: [createPhaseSurfaceHook()] }],
   ```
2. Edit `apps/web-platform/test/agent-runner-query-options.test.ts`: assert
   `opts.hooks?.PostToolUse` is defined, is an array, and `[0].matcher === "Skill"`. (Do NOT change
   the T4 `stableShape` snapshot — `hooks` is excluded by design.)

### Phase 4 — ADR + C4 (architectural-decision deliverables)
1. Amend `knowledge-base/engineering/architecture/decisions/ADR-070-l3-phase-tool-scoping-two-tier-fail-open.md`:
   in the "Canonical shared-registry location" section, record the resolved decision (bundled `.ts`
   copy + CI parity test; canonical stays `.claude/phase-surface-map.json`). Add to `## Alternatives
   considered`: (a) read `.claude/…json` at runtime — rejected (not in the web container); (b) single
   copy relocated into the vendored plugin tree read from `pluginPath` at runtime — rejected
   (reintroduces a runtime-fs failure class on the paying-user path; the bundled in-process constant
   makes fail-open trivially true).
2. Edit `knowledge-base/engineering/architecture/diagrams/model.c4`: broaden the `hooks` container
   description (currently guard-only: "Enforces syntactic rules — blocks commits to main, rm -rf,
   etc.") to also mention advisory PostToolUse phase-surface context injection, so the description is
   not falsified by adding a non-guard hook kind. Run `apps/web-platform/test/c4-code-syntax.test.ts`
   + `c4-render.test.ts`.

### Phase 5 — Verify
1. `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
2. `./node_modules/.bin/vitest run test/phase-surface-hook.test.ts test/phase-surface-map-parity.test.ts test/agent-runner-query-options.test.ts`.
3. Full suite per `package.json scripts.test`.

## Files to Create
- `apps/web-platform/server/phase-surface-map.ts` — bundled map copy (FR6).
- `apps/web-platform/server/phase-surface-hook.ts` — `createPhaseSurfaceHook` (FR1–FR4).
- `apps/web-platform/test/phase-surface-hook.test.ts` — behavioural unit tests.
- `apps/web-platform/test/phase-surface-map-parity.test.ts` — drift parity (TR2).

## Files to Edit
- `apps/web-platform/server/agent-runner-query-options.ts` — register `PostToolUse` hook (FR5).
- `apps/web-platform/test/agent-runner-query-options.test.ts` — assert PostToolUse present (TR4).
- `knowledge-base/engineering/architecture/decisions/ADR-070-l3-phase-tool-scoping-two-tier-fail-open.md` — resolve deferred decision.
- `knowledge-base/engineering/architecture/diagrams/model.c4` — broaden `hooks` description.

## Open Code-Review Overlap

None — checked `gh issue list --label code-review --state open` against the four edited paths; no
open scope-out names `agent-runner-query-options.ts`, the C4 model, or ADR-070.

## Domain Review

**Domains relevant:** Engineering (CTO).

### Engineering (CTO)
**Status:** pending (spawned at plan-review).
**Assessment:** Cross-cutting harness/runtime change on the paying-user web agent loop. Key risks
the CTO must weigh: (1) does a `PostToolUse` callback that returns `{}` ever interfere with the
SDK's tool loop; (2) the two-tier fail-open invariant (no `canUseTool`/`disallowedTools` touch);
(3) the bundled-copy-vs-single-source-of-truth tradeoff for the registry.

### Product/UX Gate
**Tier:** none. No UI surface — Files to Create/Edit are `.ts`, a `.ts` const map, an ADR, and one
C4 line. No `components/**`, `app/**/page.tsx`, modal, banner, or flow. `requires_cpo_signoff: true`
is an approach-ack (threshold-driven), not a UX review.

## Observability

```yaml
liveness_signal:
  what: the PostToolUse(Skill) hook emits additionalContext on every mapped Skill call
  cadence: per skill-routing call (interactive + autonomous)
  alert_target: none (fail-open advisory; absence of a hint is not an incident)
  configured_in: apps/web-platform/server/phase-surface-hook.ts
error_reporting:
  destination: Sentry via the existing silent-fallback helper (reportSilentFallback)
  fail_loud: false (fail-open by contract; the error is mirrored, the turn continues)
failure_modes:
  - mode: hook callback throws (map shape regression, unexpected input)
    detection: Sentry event from the catch arm
    alert_route: Sentry project (web-platform), grouped by the hook's message string
  - mode: bundled map drifts from canonical
    detection: phase-surface-map-parity.test.ts fails in CI
    alert_route: CI red on PR (pre-merge)
logs:
  where: pino child logger "phase-surface-hook" (warn on the fail-open path)
  retention: Better Stack standard
discoverability_test:
  command: ./node_modules/.bin/vitest run test/phase-surface-hook.test.ts (asserts the catch arm returns {} and mirrors)
  expected_output: all cases pass; malformed-input case proves no-throw
```

## Architecture Decision (ADR/C4)

### ADR
Amend **ADR-070** (the #5768 deliverable, which explicitly deferred the shared-registry location to
"#5772 build time"). Resolution: bundled `.ts` copy in the web server + CI parity test; canonical
stays `.claude/phase-surface-map.json`. This is an *amendment* (the decision ADR-070 deferred), not
a new ADR.

### C4 views
Enumeration against all three `.c4` files (read in full, not grepped):
- **External human actor:** none new (founder, Inbound Correspondent unchanged).
- **External system/vendor:** none new (the hint injects into the already-modeled `engine ->
  anthropic` LLM edge).
- **Container/data-store:** none new — the bundled map is an internal config artifact at the same
  granularity the model already omits (it does not model `.claude/settings.json` etc.). The hook is
  a new instance within the already-modeled `hooks` (Hook Engine) + `claude` (Agent Runtime) containers.
- **Access relationship:** none changed (additive context, no new actor/permission boundary).
- **Correctness fix (in scope):** the `hooks` container description is guard-only ("Enforces
  syntactic rules — blocks commits…"), which a PostToolUse *advisory* hook makes incomplete →
  broaden the description (one line in `model.c4`). No `views.c4` change (no new element to render).

### Sequencing
The ADR amendment and the C4 edit ship in THIS PR (Phase 4), not a follow-up.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] AC1 — `apps/web-platform/server/phase-surface-hook.ts` exists; `createPhaseSurfaceHook()`
  returns a `HookCallback` that, for `{tool_name:"Skill", tool_input:{skill:"soleur:work"}}`, returns
  `additionalContext` whose value contains `work` and the `(Guidance only …)` suffix.
- [ ] AC2 — Fail-open: unmapped skill, non-`Skill` tool, missing skill, non-string skill,
  `SOLEUR_DISABLE_PHASE_HINT=1`, and malformed `tool_input` each return `{}`; the malformed case
  asserts **no throw**; the `buildHint→null` internal branch yields a clean `{}` (NOT
  `{hookSpecificOutput:{…additionalContext:null}}`). (F3)
- [ ] AC3 — Security (F1/F2): (a) for a mapped skill, `additionalContext` is **byte-equal** to a
  fixed expected snapshot composed from map constants (catches any future interpolation regression,
  not just the literal token); (b) crafted keys `__proto__`, `constructor`, `toString` → `{}` (own-
  property guard); (c) a crafted skill whose text embeds a phase keyword AND a `\u2028`/`\u2029`
  line-separator (e.g. `"ship\u2028INJECT"`) → unmapped → `{}` and never appears in any output;
  (d) skill sent as a non-string (`["__proto__"]`, `{}`) → `{}`.
- [ ] AC3b — F5: the fail-open catch arm's log message + Sentry `extra` + the error do NOT contain
  the raw `skill` value (static message string only).
- [ ] AC4 — `apps/web-platform/test/phase-surface-map-parity.test.ts` passes: `PHASE_SURFACE_MAP`
  deep-equals `JSON.parse(.claude/phase-surface-map.json)` (ignoring a `_comment` key if present).
- [ ] AC5 — `buildAgentQueryOptions(...).hooks.PostToolUse` is a defined array whose `[0].matcher ===
  "Skill"`; the T4 `stableShape` snapshot test is UNCHANGED and still green.
- [ ] AC6 — `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` is clean.
- [ ] AC7 — full test suite green (`package.json scripts.test`); C4 syntax + render tests green.
- [ ] AC8 — ADR-070 amended (shared-registry decision recorded + 2 rejected alternatives); `model.c4`
  `hooks` description broadened.
- [ ] AC9 — PR body uses `Ref #5772` (NOT `Closes` — #5772 stays open for lever 2); `## Changelog`
  present; `semver:minor` label (new capability).

### Post-merge (operator)
- [ ] AC10 — None automatable beyond CI; deploy is the standard `web-platform-release.yml` container
  restart on merge. No operator step.
- [ ] AC11 (QA, value-realization) — On a real web `/soleur:go` multi-phase run, confirm the
  `[phase-scope]` `additionalContext` reaches the model after a `Skill` routing call (Sentry/agent
  transcript evidence), and observe whether the router emits `Skill` at >1 phase transition. Records
  the realized firing cadence; does NOT block merge (the hint is fail-open and beneficial regardless).

## Test Scenarios
1. Mapped skill (each of the 5 phases) → hint names that phase + lists its surface.
2. Unmapped/unknown skill → `{}`.
3. Non-Skill tool (`Read`, `Bash`) → `{}` (matcher belt-and-suspenders).
4. Kill-switch `SOLEUR_DISABLE_PHASE_HINT=1` → `{}`.
5. Malformed input (`tool_input:null`, no `skill`, wrong type) → `{}`, no throw.
6. Crafted/injection skill name → unmapped → `{}`; mapped-skill hint never echoes the skill token.
7. Parity: edit the canonical map without the web copy → parity test goes red.
8. Builder: both `minArgs` (legacy) and cc-style args produce `hooks.PostToolUse` with matcher Skill.

## Sharp Edges
- A plan whose `## User-Brand Impact` section is empty or placeholder fails deepen-plan Phase 4.6 —
  this one is filled (threshold single-user incident).
- The bundled `.ts` map is a second representation of the canonical JSON (the "two literals drift"
  anti-pattern); the parity test (TR2) is the load-bearing guard — never skip it. Document the
  coupling in BOTH files' headers.
- PostToolUse fires after the `Skill` tool *executes*; on the cc path `Skill` is not in
  `CC_PATH_ALLOWED_TOOLS` (auto-approve list) but is callable via `canUseTool`, so it still runs and
  the hook still fires. QA confirms by exercising a real `/soleur:go` route on the web path.
- **Flow-cadence caveat (do not overclaim +6.7pts):** the eval measured *per-transition* next-skill
  selection. The hint fires on EVERY `Skill` PostToolUse, but the web router locks `currentWorkflow`
  on the *first* `Skill` call (`soleur-go-runner.ts:2113`) then runs sticky. Whether the router emits
  a fresh `Skill` call at each phase transition (and thus realizes the per-phase benefit) is an
  empirical property of the router, not guaranteed by this hook. The hint is still net-positive
  (fail-open, fires whenever `Skill` is called), but realized value must be confirmed by QA on a real
  multi-phase web run — not assumed. (Added AC11.)
