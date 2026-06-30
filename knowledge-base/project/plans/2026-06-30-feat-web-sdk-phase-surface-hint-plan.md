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

## Enhancement Summary

**Deepened on:** 2026-06-30 (single-user-incident threshold → substance pass)
**Review passes folded:** security-sentinel, spec-flow-analyzer, CTO (round 1); architecture-strategist
+ code-simplicity-reviewer (deepen round); mechanical halt gates 4.6/4.7/4.8/4.9 all PASS.

### Key improvements from review
1. **P0 (spec-flow):** web `tool_input.skill` is **bare** (`work`), the canonical map is FQN-keyed →
   without FR1a normalization the hint silently never fires on web. Fixed + bare-shape tests.
2. **P1-A (architecture):** hook is now **per-caller opt-in** (`enablePhaseSurfaceHint`, cc-router
   only) — keeps the fail-CLOSED lever-2 precedent off the legacy domain-leader path.
3. **P1-B (architecture):** C4 edit corrected — do NOT misattribute the web `options.hooks` surface to
   the CLI `engine.hooks` container.
4. **Security (F1/F5):** single own-property gate on the model-controlled key; skill kept out of the
   Sentry/log path.
5. **Simplicity:** dropped the dead `typeof phase` check + redundant phase allowlist (restored exact
   CLI parity); `SOLEUR_SKILL_PREFIX` constant; honest `.ts`-choice rationale.
6. **Hygiene (P2-C/P2-D):** ADR-070 amended as a dated delimited block (original Decision immutable);
   parity-test repo-root resolved via `findRepoRoot()` not `../../..`.

### Net design (post-deepen)
A side-effect-free `PostToolUse(Skill)` hook, **cc-router opt-in**, bare→FQN key normalization, single
prototype-safe own-property gate, fail-open try/catch with Sentry mirror; bundled `.ts` map + parity
test; ADR-070 dated amendment + corrected C4 note. No P0/P1 unresolved.

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

**Value-claim honesty (spec-flow P1):** the +6.7pts is a *model-level, per-transition* eval result.
Its transfer to the web depends on the router emitting a `Skill` call at each phase transition; the
web router locks one workflow per conversation and runs sticky (`soleur-go-runner.ts:2113`). The
hint is still net-positive (fail-open; biases in-phase skill selection on every `Skill` dispatch),
but the realized web value is "in-phase biasing per dispatch," not a guaranteed +6.7pts — confirmed
by QA (AC11), not asserted.

**Per-caller scoping (architecture P1-A — resolves the both-paths concern):** the hook is registered
**only when the caller opts in** (`enablePhaseSurfaceHint: true`). The cc-soleur-go Concierge router
(`cc-dispatcher.ts:2328`, the eval-covered workflow path) opts in; the legacy domain-leader runner
(`agent-runner.ts:1990`, no workflow-phase concept) does not. This scopes the eval-justified behavior
to the eval-covered path and — critically — keeps the deferred **fail-CLOSED lever 2** from inheriting
a "both-callers-always-on" default that would silently restrict the legacy path (the ADR-070
unknown-tool hazard). Recorded in the ADR-070 amendment Consequences for the lever-2 implementer.

**Scope:** ~2 new source files + 1 helper edit (+ `enablePhaseSurfaceHint` arg, cc-caller opt-in) +
3 test files + 1 ADR dated-amendment + 1 C4 correction. The builder edit lives in one place but fires
only on the opted-in cc-soleur-go caller.

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality (verified) | Plan response |
|---|---|---|
| Web hook can read `.claude/phase-surface-map.json` at runtime | **NO** — Dockerfile copies only `public/`, `.next/`, `dist/server/`, `next.config.mjs`, `_plugin-vendored/`→`/opt/soleur/plugin/`; `.claude/` is excluded (`.dockerignore:23`) | Bundle a web copy as a `.ts` const module compiled into `dist/server` (FR6); parity test guards drift (TR2) |
| SDK PostToolUse supports `additionalContext` | YES — `PostToolUseHookSpecificOutput.additionalContext?: string` (`sdk.d.ts:1422`); `SyncHookJSONOutput.hookSpecificOutput` accepts it (`:3974`) | Direct JS port of the shell hook (FR1) |
| Adding `PostToolUse` trips the T4 drift-guard | NO — `stableShape` SHARED_KEYS excludes `hooks` (`agent-runner-query-options.test.ts:213`) | Add a positive `PostToolUse`/matcher assertion instead (TR4) |
| Web agent invokes the `Skill` tool | YES — `soleur-go-runner.ts:2113` detects first `Skill` call; Skill is in the plugin surface, not in `disallowedTools` | Hook fires after every `Skill` execution on both paths (FR5) |
| `tool_input.skill` is FQN (`soleur:work`) on the web path | **NO — it is BARE** (`work`): `KNOWN_WORKFLOWS` (`soleur-go-runner.ts:559`) + system prompt (`:1291`) + web fixture (`soleur-go-runner-interactive-prompt.test.ts:256`) all use bare names; no prefix-stripping exists. The canonical map is FQN-keyed. | **P0 fix:** normalize `key = skill.includes(":") ? skill : "soleur:"+skill` (FR1a); tests use the bare shape as the primary case. Without this the hint silently never fires on web. |
| `Skill` reaches execution on the cc path (so PostToolUse fires) | YES — Skill ∉ `CC_PATH_ALLOWED_TOOLS` but ∈ `SAFE_TOOLS` (`tool-path-checker.ts:55`) so `canUseTool` approves it (`permission-callback.ts:883`) | Silent coupling — AC pins `isSafeTool("Skill")===true` so dropping it from `SAFE_TOOLS` fails CI (P2) |
| `resolveJsonModule` available for a `.json` copy | YES (`tsconfig.json:12`) | A web-local second copy + parity test is needed EITHER way (canonical `.claude/` is excluded from the container regardless; a `.json` import would import a NEW web-local json, not the canonical — so it saves neither a representation nor the parity test, simplicity P3). Use a `.ts` const module as the **build-mechanism-agnostic** choice (guaranteed inlined under both bundler and plain-`tsc` emit, without verifying which the build uses). A `.json` import would be marginally cleaner if Phase 0 confirms a bundler — a wash, not worth churn. |

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
   `PHASE_SURFACE_MAP`. Resolve repo root with a `findRepoRoot()` upward walk (look for a `.git`
   marker / `.claude/` dir), NOT a brittle hard-coded `../../..` (CTO low-risk flag — mis-resolves
   silently if the test file moves); assert the canonical file exists with a clear message.
2. Create `apps/web-platform/server/phase-surface-map.ts`: `export const PHASE_SURFACE_MAP = { … }
   as const` — a faithful copy of `.claude/phase-surface-map.json` (drop the `_comment` key or keep
   it; the parity test defines the contract). Add a header comment: "Bundled web copy of the
   canonical `.claude/phase-surface-map.json`; edit BOTH and keep the parity test green (ADR-070,
   ADR-053)." GREEN.

### Phase 2 — The hook module (RED test first)
1. Write `apps/web-platform/test/phase-surface-hook.test.ts` (RED), cases:
   (a) **bare web shape (P0 primary case):** `{tool_name:"Skill", tool_input:{skill:"work"}}` →
   `additionalContext` contains `work`; AND FQN passthrough `{skill:"soleur:work"}` → same hint;
   (b) unmapped skill (`{skill:"one-shot"}` → normalizes to `soleur:one-shot`, absent from map) → `{}`;
   (c) `tool_name:"Read"` → `{}`;
   (d) `SOLEUR_DISABLE_PHASE_HINT=1` → `{}`;
   (e) malformed input (`tool_input:null`, missing `skill`) → `{}` and **does not throw**;
   (f) the emitted `additionalContext` NEVER contains the raw skill token for a crafted skill name
   (security FR3) — e.g. `skill:"soleur:work<INJECT>"` is unmapped → `{}`, and a mapped skill's hint
   contains the phase name but not the skill string.
2. Create `apps/web-platform/server/phase-surface-hook.ts`:
   - `import { PHASE_SURFACE_MAP } from "./phase-surface-map";`
   - `const SOLEUR_SKILL_PREFIX = "soleur:";` — named constant (architecture P2-D: do NOT inline a
     second bare `"soleur:"` literal; the namespace gets one definition). Header-comment the WHY:
     "web Concierge emits BARE Skill names (`KNOWN_WORKFLOWS` `soleur-go-runner.ts:559`); the canonical
     map is FQN-keyed (CLI emits FQN); this normalizes bare→FQN at lookup."
   - pure `buildHint(skill): string | null` — **minimal guard set (CLI parity; security-sentinel F1 +
     code-simplicity):** `process.env.SOLEUR_DISABLE_PHASE_HINT==="1"` (strict) → null; `typeof skill
     !== "string"` → null; **normalize (FR1a, P0):** `key = skill.includes(":") ? skill :
     SOLEUR_SKILL_PREFIX + skill`; `Object.hasOwn(map.skill_to_phase, key)` → else null **(the single
     own-property gate on the model-controlled key — rejects `__proto__`/`constructor`/`toString`)**;
     `phase = map.skill_to_phase[key]`; `surface = map.phase_to_surface[phase]`; `if (!surface) return
     null` (plain null-check, mirrors the CLI hook's `$s == null`). NO `typeof phase` check and NO
     phase allowlist — both are dead/divergent from the CLI (simplicity cuts 1+2). Compose the FR4
     string from map-derived constants only (skill/key NEVER interpolated). Read the env var
     per-invocation.
   - `export function createPhaseSurfaceHook(): HookCallback` — the factory MUST be **side-effect-free**
     (no map access / no work at construction; it only returns the closure) so a builder-time call in
     the `hooks` literal cannot throw into `buildAgentQueryOptions` → `query()` startup on EITHER
     caller (P1, spec-flow). The returned async callback: casts input to `PostToolUseHookInput`;
     returns `{}` unless `tool_name==="Skill"`; reads `(tool_input as {skill?:string}).skill`;
     `buildHint`; returns `{ hookSpecificOutput:{ hookEventName:"PostToolUse", additionalContext:hint
     } }` or `{}` (the `buildHint→null` branch yields a clean `{}`, NOT `additionalContext:null`);
     wraps the whole body in try/catch → on error `log.warn` (static message, NO skill value — F5) +
     `reportSilentFallback` (TR3) + return `{}`. GREEN.

### Phase 3 — Wire into the builder (per-caller opt-in, architecture P1-A)
1. Add `enablePhaseSurfaceHint?: boolean` to `AgentQueryOptionsArgs` (defaults to `false`/undefined).
2. Edit `apps/web-platform/server/agent-runner-query-options.ts`: import `createPhaseSurfaceHook`;
   register the hook **conditionally** — only when `args.enablePhaseSurfaceHint`:
   ```ts
   ...(args.enablePhaseSurfaceHint
     ? { PostToolUse: [{ matcher: "Skill", hooks: [createPhaseSurfaceHook()] }] }
     : {}),
   ```
   inside the `hooks` literal (spread). The cc-soleur-go caller (`cc-dispatcher.ts:2328`) passes
   `enablePhaseSurfaceHint: true`; the legacy caller (`agent-runner.ts:1990`) does NOT (stays
   zero-change). This scopes the eval-justified hint to the eval-covered Concierge path and keeps the
   fail-CLOSED lever-2 precedent off the legacy path.
3. Edit `apps/web-platform/test/agent-runner-query-options.test.ts`: assert that **with**
   `enablePhaseSurfaceHint:true`, `opts.hooks?.PostToolUse[0].matcher === "Skill"`; and **without** the
   flag, `opts.hooks?.PostToolUse` is undefined (the real branch — Test Scenario 8). Do NOT change the
   T4 `stableShape` snapshot (`hooks` is excluded by design).

### Phase 4 — ADR + C4 (architectural-decision deliverables)
1. Amend `ADR-070` as a **dated, delimited amendment block** (architecture P2-C — follow the
   ADR-036/ADR-030 convention; do NOT edit the original Accepted Decision prose in place, keep it
   immutable). Add an `Amended: 2026-06-30 (#5772)` line to the header and a `## Amendment — 2026-06-30
   (#5772): shared-registry resolution` section that records: the resolved decision (bundled `.ts`
   copy + CI parity test; canonical stays `.claude/phase-surface-map.json`); the rejected alternatives
   — (a) read `.claude/…json` at runtime (not in the web container), (b) single copy in the vendored
   plugin tree read from `pluginPath` (best-effort warn-only symlink `workspace.ts:424` → ENOENT
   silent-degradation; and the CLI hook must keep reading `.claude/`, so its "single source" is
   illusory); and the Consequences — **lever 1 is now per-caller opt-in (cc-router only)** so the
   fail-CLOSED lever-2 precedent does NOT default onto the legacy path; the +6.7pt eval covered only
   the cc workflow-routing path; the bare-vs-FQN `tool_input.skill` normalization (FR1a) is a
   documented cross-surface coupling the lever-2 implementer inherits.
2. Edit `knowledge-base/engineering/architecture/diagrams/model.c4` (architecture P1-B — **do NOT
   broaden the CLI `engine.hooks` description**; that container is the `.claude/` shell-guard engine
   under "Cloud CLI Engine" loaded via `settingSources`, and the new hook is the opposite surface — a
   web-server JS closure on `options.hooks` registered with `settingSources: []`). Correct the latent
   misattribution instead: add a one-line description note (or small relationship) on the **webapp**
   side (`api`/`claude` web container that "Spawns agent sessions") that the web Agent SDK runtime
   registers in-process `options.hooks` closures (sandbox + SubagentStart + phase-surface), distinct
   from the CLI `.claude/` shell `hooks` engine. Run `c4-code-syntax.test.ts` + `c4-render.test.ts`.
   (Pre-existing gap: the web SDK hook surface was already unmodeled/folded into `api`; this PR adds
   the minimal correct note rather than deepening the misattribution. A full web-hook-surface element
   is a fair follow-up but out of this PR's scope.)

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
**Status:** reviewed.
**Assessment:** Approved the bundled-`.ts`-copy + parity-test registry design (rejected the
single-copy-in-plugin-tree alternative: its "single source" is illusory because the CLI hook must
keep reading `.claude/`, and it reintroduces an ENOENT silent-degradation via the best-effort
warn-only plugin symlink `workspace.ts:424`). Raised the cc-path eval-coverage caveat (folded into
the Overview both-paths note + ADR Consequences) and the steady-state token-injection note (folded
into Observability).

### Review panel (substitute for DHH/Kieran — stack-appropriate for TS harness)
**security-sentinel:** F1 prototype-pollution (folded — `typeof` + `Object.hasOwn` both lookups +
phase allowlist), F2 byte-equal snapshot test, F3 fail-open `{}` confirmed safe (PostToolUse has no
permission authority — cannot weaken the `canUseTool` floor), F5 keep skill out of the Sentry/log
path. All folded.
**spec-flow-analyzer:** P0 bare-vs-FQN key mismatch (folded — FR1a normalization, the load-bearing
fix), P1 factory-throw + SDK-loop-neutrality (folded — AC1b), P1 value-claim cadence (folded —
Overview honesty note + AC11), P2 SAFE_TOOLS coupling (folded — AC1c). All folded.
**architecture-strategist + code-simplicity-reviewer:** transiently rate-limited (server-side); their
lenses (ADR-070 compliance, C4 enumeration, YAGNI cuts) are re-run by **deepen-plan** (mandated at
single-user-incident threshold — re-runs the data-integrity + security + architecture substance triad).

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
  where: pino child logger "phase-surface-hook" (warn on the fail-open path; static message, no skill value — F5)
  retention: Better Stack standard
steady_state_note: >
  small constant hint text is appended after every mapped Skill call; under the cc/legacy path's
  maxTurns:50 / maxBudgetUsd:5.0 envelope this is expected per-dispatch context growth (CTO low), not
  an incident — bounded by the per-turn Skill-call count, not unbounded.
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
- **Correctness fix (in scope, architecture P1-B):** do NOT broaden the CLI `engine.hooks` container
  (it correctly describes `.claude/` shell guards under the Cloud CLI Engine; the new hook is a
  web-side `options.hooks` closure with `settingSources:[]` — the opposite surface). Instead add a
  one-line note on the **webapp** `api`/`claude` container that it registers in-process SDK
  `options.hooks` (sandbox + SubagentStart + phase-surface), correcting the pre-existing
  misattribution rather than deepening it. No `views.c4` change (no new element to render).

### Sequencing
The ADR amendment and the C4 edit ship in THIS PR (Phase 4), not a follow-up.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] AC1 (P0 — bare-shape normalization, load-bearing) — `phase-surface-hook.ts` exists;
  `createPhaseSurfaceHook()` returns a `HookCallback` that, for the **REAL web shape** `{tool_name:
  "Skill", tool_input:{skill:"work"}}` (bare — cross-referenced to `KNOWN_WORKFLOWS`
  `soleur-go-runner.ts:559` and web fixture `soleur-go-runner-interactive-prompt.test.ts:256`),
  returns `additionalContext` containing `work` + the `(Guidance only …)` suffix; the FQN form
  `{skill:"soleur:work"}` returns the identical hint. (A test feeding ONLY synthetic FQN would mask
  the silent-no-op — the bare case IS the guard.)
- [ ] AC1b (P1 — factory safety) — `createPhaseSurfaceHook()` construction does not throw (factory is
  side-effect-free), so a builder-time registration cannot break `query()` startup. (The "SDK
  iterator continues after a `{}` return" property is the SDK's own contract, verified by AC11 QA on a
  real run, not unit-tested here — our side is covered by AC2's no-throw.)
- [ ] AC1c (P2 — cc-path coupling) — a test pins `isSafeTool("Skill") === true` (`tool-path-checker.ts:55`)
  so dropping `Skill` from `SAFE_TOOLS` (which would deny-by-default it on the cc path and silently
  kill the hint there) fails CI.
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
- [ ] AC5 (per-caller opt-in branch, P1-A) — with `enablePhaseSurfaceHint:true`,
  `buildAgentQueryOptions(...).hooks.PostToolUse[0].matcher === "Skill"`; **without** the flag,
  `.hooks.PostToolUse` is undefined. The T4 `stableShape` snapshot is UNCHANGED and still green.
- [ ] AC6 — `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` is clean.
- [ ] AC7 — full test suite green (`package.json scripts.test`); C4 syntax + render tests green.
- [ ] AC8 — ADR-070 amended as a dated `## Amendment — 2026-06-30 (#5772)` block + `Amended:` header
  line (original Decision immutable); `model.c4` corrects the web-SDK-hook misattribution on the
  webapp side (does NOT broaden the CLI `engine.hooks` container).
- [ ] AC9 — PR body uses `Ref #5772` (NOT `Closes` — #5772 stays open for lever 2); `## Changelog`
  present; `semver:minor` label (new capability).

### Post-merge (operator)
- [ ] AC10 — None automatable beyond CI; deploy is the standard `web-platform-release.yml` container
  restart on merge. No operator step.
- [ ] AC11 (QA, value-realization) — On a real web `/soleur:go` run (cc Concierge path), confirm the
  `[phase-scope]` `additionalContext` reaches the model after a `Skill` routing call (Sentry/agent
  transcript) and the turn completes normally (SDK-loop-neutrality observed in situ), and observe
  whether the router emits `Skill` at >1 phase transition (realized cadence). Non-blocking. (The
  legacy path no longer receives the hint — per-caller opt-in P1-A — so no cc-vs-legacy skew to chase.)

## Test Scenarios
1. Mapped skill, bare shape (each of the 5 phases) → hint names that phase + lists its surface; FQN form → identical.
2. Unmapped/unknown skill (e.g. `one-shot`) → `{}`.
3. Non-Skill tool (`Read`, `Bash`) → `{}` (matcher belt-and-suspenders).
4. Kill-switch `SOLEUR_DISABLE_PHASE_HINT=1` → `{}`.
5. Malformed input (`tool_input:null`, no `skill`, non-string) → `{}`, no throw.
6. Crafted skill name (`__proto__`, `\u2028` line-sep) → `{}`; mapped-skill hint never echoes the skill token.
7. Parity: edit the canonical map without the web copy → parity test goes red.
8. **Flag branch (P1-A):** `enablePhaseSurfaceHint:true` (cc args) → `hooks.PostToolUse` present (matcher Skill); flag absent (legacy `minArgs`) → `hooks.PostToolUse` undefined.

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
