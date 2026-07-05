---
title: "feat(wave2): web-platform in-process parity for declarative context_queries"
issue: 6046
epic: 5983
ref: 5989
adr: ADR-086 (amend — Surface scope section)
lane: single-domain
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
type: feature
detail_level: MORE
date: 2026-07-05
---

# feat(wave2): web-platform in-process parity for declarative `context_queries` ✨

## Overview

`context_queries` (declarative skill context-injection, ADR-086, shipped by #5989 / PR #6035) is **CLI-only**. The CLI hook `.claude/hooks/skill-context-queries.sh` fires on `PostToolUse(Skill)` and injects a **pointer** (a Read-directive naming committed `knowledge-base/` artifacts) into the agent's `additionalContext`. Web-agent Concierge sessions run `settingSources:[]` (ADR-070) and are isolated from `.claude/` shell hooks, so the same skill (`frontend-design` → `brand-guide.md` today; the operator's `taste-profile` when #5990 lands) silently behaves differently on the two surfaces.

This plan ports the CLI hook to an **in-process TypeScript `PostToolUse(Skill)` hook** in the web-agent Agent-SDK `options.hooks` registry, as a **sibling** to the existing `createPhaseSurfaceHook()` (`apps/web-platform/server/phase-surface-hook.ts`, the ADR-070 JS port). The port reproduces the CLI hook's four containment gates and its fail-open contract byte-for-byte, and closes the ADR-086 "Surface scope (CLI-first, web parity deferred)" gap.

**Key architectural finding (load-bearing):** In the web Concierge, the plugin bundle is mounted *inside the workspace* — `pluginPath = path.join(workspacePath, "plugins", "soleur")` (`agent-runner.ts:1109`, `cc-dispatcher.ts:2387`). So `workspacePath/plugins/soleur/skills/<name>/SKILL.md` and `workspacePath/knowledge-base/...` share **one root** (`workspacePath`, the SDK `cwd`), exactly like the CLI's `repo_root`. The web port therefore needs only a single root argument (`args.workspacePath`) — there is no dual-root complication.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue #6046 body) | Codebase reality (verified) | Plan response |
|---|---|---|
| CLI hook exists at `.claude/hooks/skill-context-queries.sh` | ✅ Exists, 7267 bytes; 4-gate + fail-open contract confirmed | Port verbatim to TS |
| Web precedent `phase-surface-hook.ts` registered at `agent-runner-query-options.ts:262` | ✅ Confirmed; `createPhaseSurfaceHook()` registered conditionally on `enablePhaseSurfaceHint` | Register a sibling conditional block |
| Web emits **bare** skill names (`frontend-design`), CLI emits `soleur:`-prefixed | ✅ Confirmed (`phase-surface-hook.ts:22-24` normalizes bare↔FQN) | Port handles bare names; defensive colon-strip before the `^[a-z0-9-]+$` gate |
| #5989 merged | ✅ Issue #5989 CLOSED, merged via PR #6035 (`a1018a640`) | Premise holds — this is a BUILD atop shipped substrate, not a fix |
| No `context_queries` handling in web-platform yet | ✅ `git grep context_queries -- apps/web-platform/` returns empty | Gap is real; no prior partial impl to reconcile |
| `pluginPath` location | `path.join(workspacePath, "plugins", "soleur")` — plugin mounted **in** workspace | Single shared root = `workspacePath` (see Overview) |

## User-Brand Impact

**If this lands broken, the user experiences:** their web Concierge design session silently lacks the brand-guide (or, post-#5990, taste-profile) context that the same skill loads on the CLI — degraded, off-brand design output with no visible error. This is the *status-quo* gap the issue describes, so "broken" = "no delivery" (no regression beyond today).

**If this misbehaves, the user's workflow is exposed via:** a defective containment gate could direct the agent to `Read` a path outside `knowledge-base/`. Per ADR-086's threat model the worst achievable outcome is a directed Read of an **already-committed** `knowledge-base/` file (reference data by definition — never an out-of-tree secret; every query passes four gates). No data-write, no external egress.

**Brand-survival threshold:** aggregate pattern — the harm is cross-session design-quality inconsistency, not a single-user data/security incident. No per-PR CPO sign-off; security is reviewed at PR time (security-sentinel) given the model-controlled-path-into-filesystem trust boundary.

## Implementation Phases

Phases are ordered by dependency direction (contract → consumer), not by file. The whole change merges atomically.

### Phase 0 — Preconditions (verify before coding)
1. `git grep -n "createPhaseSurfaceHook\|PostToolUse" apps/web-platform/server/agent-runner-query-options.ts` — confirm registration shape (verified: lines 261-263).
2. Confirm `enablePhaseSurfaceHint: true` is set only at `cc-dispatcher.ts:2689` (verified — the cc-soleur-go Concierge path).
3. Read `apps/web-platform/test/phase-surface-hook.test.ts` + `phase-surface-hint-shell-parity.test.ts` for the mock + fixture conventions to mirror.
4. Confirm the `@anthropic-ai/claude-agent-sdk` `HookCallback` / `PostToolUseHookInput` types (import from `phase-surface-hook.ts`'s import line — already resolved).

### Phase 1 — Create the in-process hook (`context-queries-hook.ts`)
Create `apps/web-platform/server/context-queries-hook.ts` exporting `createContextQueriesHook(repoRoot: string): HookCallback`. Mirror the CLI hook's logic in TS:

- **Kill-switch:** `process.env.SOLEUR_DISABLE_CONTEXT_QUERIES === "1"` → return `{}`.
- **Skill-name gate (trust boundary #1):** read `tool_input.skill`; if not a string, return `{}`. Defensive colon-strip (`skill.includes(":") ? skill.slice(skill.lastIndexOf(":") + 1) : skill` — web emits bare, but strip a stray FQN for parity); gate the result against `/^[a-z0-9-]+$/` or return `{}`.
- **SKILL.md path containment (gate #2):** `skillmd = join(repoRoot, "plugins/soleur/skills", name, "SKILL.md")`; `fs.realpathSync` both `skillmd` and the skills dir; assert `realMd.startsWith(realSkills + sep)`; assert it is a regular file and **not** a symlink (`lstatSync(...).isSymbolicLink()` reject). Any failure → `{}`.
- **Frontmatter fast-path:** parse only the frontmatter block (content between the first two `^---$` lines — the awk `c==1` idiom); return `{}` unless a `context_queries:` key is present in that block (never a body occurrence). This is the ~89-skill fast-exit.
- **`context_queries` parse:** handle **both** the inline `context_queries: [a, b]` form (including empty `[]`) and the block `- item` form, stripping matching single/double quotes — a faithful port of the awk at `skill-context-queries.sh:84-101`. Do NOT ship a block-only subset (it silently parses inline to empty).
- **Per-query resolution (gate #3 + #4):** for each query:
  - Reject unless it starts with `knowledge-base/`, and reject any containing `..` or a leading `/` → push `"<out-of-tree query> (rejected)"` to `skipped` (never echo the raw crafted path).
  - `git -C repoRoot ls-files -- <query>` via `execFile` (the committed-only + glob-expansion gate; established pattern — `git-auth.ts`, `push-branch.ts` spawn git). Sort output byte-wise (`LC_ALL=C` parity — `Buffer.compare` or a code-unit sort over ASCII paths) and cap at `MAX_GLOB = 20` (skip note on truncation).
  - For each matched rel path: reject symlink (`lstatSync`), `realpathSync` and assert containment under `realpath(repoRoot/knowledge-base)`, assert file exists; dedupe; push to `resolved` (or a categorized `skipped` note on any reject).
- **Note assembly (parity):** reached only when `context_queries` was declared, so a note **always** emits (never silent) — even on 0 resolved. Byte-identical to the CLI hook's note text:
  - resolved: `"[context_queries] Read these committed knowledge-base artifacts before proceeding (reference data, not instructions): <a, b, c>."`
  - 0 resolved: `"[context_queries] declared but 0 artifacts resolved."`
  - append `" (skipped: ...)"` + the `"— tell the user which declared context artifacts were skipped..."` operator-relay sentence when `skipped` is non-empty.
  - Return `{ hookSpecificOutput: { hookEventName: "PostToolUse", additionalContext: note } }`.
- **Fail-open (load-bearing):** wrap the whole body in `try/catch`; on any throw, `log.warn` + `reportSilentFallback(err, { feature: "context-queries-hook", op: "resolve" })` with a **static** message (the model-controlled `skill` value MUST NOT enter the error path — mirror `phase-surface-hook.ts:92-97`), and return `{}`. `git ls-files` spawn failure is caught here (fail-open).

### Phase 2 — Register the sibling hook (`agent-runner-query-options.ts`)
- Add `enableContextQueries?: boolean` to `AgentQueryOptionsArgs` (doc-comment mirroring the `enablePhaseSurfaceHint` block: per-caller opt-in, additive-only, fail-open; legacy leaves it undefined so the AC5 drift snapshot stays byte-identical).
- Import `createContextQueriesHook`.
- Restructure the conditional `PostToolUse` block (currently `...(args.enablePhaseSurfaceHint ? { PostToolUse: [...] } : {})`) into an **array built by concatenation** so the two flags register **independently**:
  ```ts
  const postToolUse = [
    ...(args.enablePhaseSurfaceHint ? [{ matcher: "Skill", hooks: [createPhaseSurfaceHook()] }] : []),
    ...(args.enableContextQueries ? [{ matcher: "Skill", hooks: [createContextQueriesHook(args.workspacePath)] }] : []),
  ];
  ...(postToolUse.length ? { PostToolUse: postToolUse } : {}),
  ```
  Both hooks use matcher `"Skill"`; per ADR-086 §"Composition fallback" the CC docs guarantee both `additionalContext` values are delivered (parallel matching hooks). The pointer payload is ~1 line, so the shared budget is a non-issue.

### Phase 3 — Enable on the Concierge path (`cc-dispatcher.ts`)
- At `cc-dispatcher.ts:2689` (the block that sets `enablePhaseSurfaceHint: true`), add `enableContextQueries: true`. Only the cc-soleur-go Concierge router opts in; the legacy domain-leader runner leaves it undefined (zero behaviour change).

### Phase 4 — Amend ADR-086 + C4 model
- **ADR-086** (`ADR-086-declarative-skill-context-injection.md`): amend the "Surface scope" section — replace "web parity deferred" with a note that #6046 delivered the in-process web port (`context-queries-hook.ts`), preserving the CLI-first framing as history. Add the port to the "Verification" list.
- **C4 `model.c4`:** the change **falsifies two existing descriptions**:
  - `model.c4:41` (webapp) enumerates the in-process hooks as "sandbox, subagent-audit, phase-surface, tool-attempt-telemetry" — add **context-queries** to that list.
  - `model.c4:62` (Hook Engine) already names "declarative skill context_queries (ADR-086)" — leave as-is (already correct); optionally add "(both CLI shell + web in-process)" for precision.
  - Run the C4 validation tests (`apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts`) after the edit.

### Phase 5 — Tests (see Test Scenarios) + typecheck
- Behavioural unit test `apps/web-platform/test/context-queries-hook.test.ts`.
- Shell-parity test `apps/web-platform/test/context-queries-shell-parity.test.ts` (runs the real `.claude/hooks/skill-context-queries.sh` against a git fixture and asserts byte-equal `additionalContext`; skips loudly if bash/jq/git absent, mirroring `phase-surface-hint-shell-parity.test.ts`).
- Update `agent-runner-query-options.test.ts` (the PostToolUse cases at lines 72-80) for the two-flag independent-registration semantics.
- `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.

## Files to Create
- `apps/web-platform/server/context-queries-hook.ts` — the in-process hook (port).
- `apps/web-platform/test/context-queries-hook.test.ts` — behavioural unit tests.
- `apps/web-platform/test/context-queries-shell-parity.test.ts` — cross-language byte-parity guard.

## Files to Edit
- `apps/web-platform/server/agent-runner-query-options.ts` — add `enableContextQueries` arg + sibling registration (array concat).
- `apps/web-platform/server/cc-dispatcher.ts:2689` — set `enableContextQueries: true`.
- `apps/web-platform/test/agent-runner-query-options.test.ts` — update PostToolUse registration tests for two independent flags.
- `knowledge-base/engineering/architecture/decisions/ADR-086-declarative-skill-context-injection.md` — amend Surface scope + Verification.
- `knowledge-base/engineering/architecture/diagrams/model.c4` — add `context-queries` to the webapp in-process hooks enumeration (line 41).

## Open Code-Review Overlap
2 open code-review issues touch `cc-dispatcher.ts`: **#3243** (arch: decompose cc-dispatcher.ts into focused modules) and **#3242** (tool_use WS event lacks raw name field). **Disposition: Acknowledge both.** Neither concerns the `context_queries` hook nor the single opt-in line this plan adds at :2689; #3243 is a broad file-decomposition effort (different cycle) and #3242 is a WS-event-shape concern (different subsystem). Both remain open. No fold-in.

## Acceptance Criteria

### Pre-merge (PR)
- **AC1 (parity — happy path):** invoking the hook with `{ skill: "frontend-design" }` against a fixture where `frontend-design/SKILL.md` declares `context_queries: [knowledge-base/marketing/brand-guide.md]` (committed) returns `additionalContext` beginning `"[context_queries] Read these committed knowledge-base artifacts before proceeding (reference data, not instructions): "` and naming `knowledge-base/marketing/brand-guide.md`.
- **AC2 (byte-parity):** `context-queries-shell-parity.test.ts` asserts the TS hook's `additionalContext` is byte-equal to the real `.claude/hooks/skill-context-queries.sh` output for ≥3 fixture cases (resolved, 0-resolved, skipped-with-note). Passes, or skips loudly when bash/jq/git absent.
- **AC3 (fast-exit):** a skill whose SKILL.md declares no `context_queries` frontmatter returns `{}` (no git spawn). A body-only `context_queries:` mention (e.g. a SKILL.md documenting this feature) also returns `{}`.
- **AC4 (gate #1 — adversarial name):** `{ skill: "../../etc/passwd" }`, `{ skill: "other:plugin" }`, `{ skill: "Foo Bar" }` each return `{}` and never read a file outside the skills dir.
- **AC5 (gate #4 — traversal/symlink/untracked):** queries `../secrets`, `/etc/passwd`, an uncommitted `knowledge-base/` file, and a symlinked match are each rejected with a categorized skip note; the raw crafted traversal string is **not** echoed into the note.
- **AC6 (0-resolved note):** a declared-but-unresolvable `context_queries` emits `"[context_queries] declared but 0 artifacts resolved."` plus the operator-relay sentence — never silent.
- **AC7 (kill-switch):** `SOLEUR_DISABLE_CONTEXT_QUERIES=1` returns `{}` on every input.
- **AC8 (fail-open):** a forced `git ls-files` failure (or any throw) returns `{}` and calls `reportSilentFallback` once with a **static** message; the `skill` value does not appear in the mirrored payload.
- **AC9 (independent registration):** `buildAgentQueryOptions({ ...args, enableContextQueries: true })` registers a `PostToolUse` `Skill` block; with both flags true, `PostToolUse` has **2** entries; with neither, `hooks.PostToolUse` is `undefined` (legacy drift snapshot byte-identical).
- **AC10 (opt-in wired):** `cc-dispatcher.ts` passes `enableContextQueries: true` on the cc-soleur-go path; grep confirms the legacy runner does not.
- **AC11 (typecheck):** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` is clean.
- **AC12 (C4 valid):** `model.c4:41` enumerates `context-queries`; `c4-code-syntax.test.ts` + `c4-render.test.ts` pass.
- **AC13 (ADR amended):** ADR-086 Surface scope reflects delivered web parity and cites `context-queries-hook.ts`.

## Observability

```yaml
liveness_signal:
  what: "context-queries-hook additionalContext emission (model-visible pointer note)"
  cadence: "per PostToolUse(Skill) on the cc-soleur-go Concierge path"
  alert_target: "none (additive hint; absence is the pre-existing gap, not an incident)"
  configured_in: "apps/web-platform/server/context-queries-hook.ts"
error_reporting:
  destination: "Sentry via reportSilentFallback (feature: context-queries-hook)"
  fail_loud: "false by design (fail-open, mirrors phase-surface-hook) — but every throw is mirrored to Sentry, never swallowed silently"
failure_modes:
  - mode: "model-controlled skill name fails the ^[a-z0-9-]+$ gate"
    detection: "returns {} (expected — no telemetry; this is the security floor working)"
    alert_route: "none (by design)"
  - mode: "SKILL.md read / realpath / git ls-files throws"
    detection: "catch arm calls reportSilentFallback(err, {feature:'context-queries-hook', op:'resolve'})"
    alert_route: "Sentry issue keyed on the static message"
  - mode: "declared context_queries resolves 0 artifacts (renamed/moved artifact)"
    detection: "additionalContext note 'declared but 0 artifacts resolved' + operator-relay sentence (model surfaces to operator)"
    alert_route: "operator-visible via agent relay (closes silent-drift path)"
logs:
  where: "pino child logger 'context-queries-hook' (createChildLogger), same sink as phase-surface-hook"
  retention: "Better Stack per existing web-platform log pipeline"
discoverability_test:
  command: "cd apps/web-platform && ./node_modules/.bin/vitest run test/context-queries-hook.test.ts"
  expected_output: "all ACs green; fail-open catch arm asserts reportSilentFallback called with static message"
```

## Architecture Decision (ADR/C4)

### ADR
Amend **ADR-086** (declarative-skill-context-injection) — this is an **amendment**, not a new ADR: the ADR's "Surface scope (CLI-first, web parity deferred — feasible, tracked)" section explicitly deferred this to a tracked follow-up (#6046). Update that section to record delivered web parity; add `context-queries-hook.ts` + its tests to the Verification list. No new ordinal is minted. (Note: three files already share the `ADR-086` ordinal in the corpus — redaction-engine, freshness, declarative-context-injection — a pre-existing collision; this plan touches only `ADR-086-declarative-skill-context-injection.md` and does not attempt to renumber the others.)

### C4 views
Read all three `.c4` files. The change touches the **Container** view (webapp in-process hook set):
- `model.c4:41` webapp description enumerates in-process hooks "sandbox, subagent-audit, phase-surface, tool-attempt-telemetry" — this port adds a hook, falsifying the enumeration → **add `context-queries`**.
- `model.c4:62` Hook Engine already names "declarative skill context_queries (ADR-086)" → already correct.
- External-actor / external-system / data-store enumeration: **none new.** No new human actor (operator already interacts with the Concierge), no new external system/vendor (reads local committed files only), no new data store (reads existing `knowledge-base/` container `platform.plugin.kb`), no changed access relationship. The only C4-relevant fact is the in-process hook enumeration on the webapp element, addressed above. No new element or view `include` line is required.

### Sequencing
No soak/time-gate; the decision is true the moment the port ships. ADR amendment + C4 edit land in this PR.

## Domain Review

**Domains relevant:** none

Infrastructure/tooling change confined to `apps/web-platform/server/` + one ADR + one C4 model line. No user-facing UI surface (no `components/**`, no `app/**/page.tsx`) → Product/UX Gate = NONE. No marketing/sales/finance/legal/ops/support implications. The one cross-cutting concern — the model-controlled-path-into-filesystem trust boundary — is an engineering/security matter handled at deepen-plan (precedent-diff vs the shell hook + `phase-surface-hook.ts`) and at PR review (security-sentinel).

## Risks & Mitigations

- **Security (trust boundary #1 — model-controlled path):** `tool_input.skill` flows into a filesystem path (a boundary `phase-surface-hook.ts` lacks — it uses the value only as a map key). Mitigation: reproduce **all four** CLI gates — colon-strip → `^[a-z0-9-]+$` → realpath containment under `plugins/soleur/skills/` → symlink/regular-file check. Never echo the raw skill value into the note or the error path. deepen-plan must diff the TS gates against `skill-context-queries.sh:58-71` line-by-line.
- **Security (gate #4 — query paths):** `knowledge-base/` prefix + `..`/absolute reject + `git ls-files` committed-only + realpath containment under `knowledge-base/` + symlink reject + `MAX_GLOB` cap. Worst case (ADR-086 threat model): directed Read of an already-committed reference file — not a secret.
- **Determinism drift:** `LC_ALL=C` byte-sort + `MAX_GLOB=20` cap must match the CLI so glob truncation drops the *same* files. Node string sort ≈ byte sort for ASCII paths; assert with a multi-match fixture in the parity test.
- **Fail-open regression:** if the catch arm is ever removed or a throw path added, a bad query could reach the SDK. Mitigation: AC8 forces a throw and asserts `{}` + Sentry mirror; the `try/catch` wraps the entire body (mirror `phase-surface-hook.ts`).
- **Drift-guard test breakage:** restructuring the `PostToolUse` conditional into an array changes `agent-runner-query-options.test.ts` expectations; Phase 5 updates those cases (AC9). The legacy-caller (both flags undefined) path must keep `hooks.PostToolUse === undefined` so the AC5 byte-identical drift snapshot holds.
- **git spawn in hook latency:** the hook spawns `git ls-files` per query on the interactive Concierge turn. Bounded by `MAX_GLOB` and only fires for the ≤ handful of skills that declare `context_queries` (fast-exit for ~89 skills before any spawn). Acceptable; note in Risks for the reviewer.

## Test Scenarios

Mirror `.claude/hooks/skill-context-queries.test.sh` case-for-case in `context-queries-hook.test.ts` (vitest, mock `../server/observability`'s `reportSilentFallback` like `phase-surface-hook.test.ts:9-15`):
1. Happy-path pointer (resolved ≥1 committed artifact).
2. Inline `[a, b]` **and** block `- a` frontmatter parse both resolve.
3. Glob determinism + `MAX_GLOB` truncation skip-note.
4. Traversal / symlink / untracked / out-of-tree rejection (raw string not echoed).
5. Fast-exit: no-frontmatter-declaration and body-only mention → `{}`.
6. Adversarial skill name (`../`, `other:plugin`, whitespace) → `{}`, no file read.
7. Kill-switch → `{}`.
8. Fail-open: forced throw → `{}` + one `reportSilentFallback` with static message; `skill` absent from payload.
9. Bare-name handling (`frontend-design`, no `soleur:` strip needed) resolves identically to the FQN form.
10. Consistency check: the real pilot `frontend-design` SKILL.md against the live repo resolves ≥1 committed artifact (mirrors the CLI test's pilot check).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan's section is filled (threshold: aggregate pattern).
- **Do NOT move this hook to `PreToolUse`** (ADR-086 headline invariant): `PostToolUse` fires *after* the Skill dispatches, making the fail-closed-all-skills catastrophe structurally impossible. The port must keep the fire-after-dispatch + exit-`{}`-on-every-path contract.
- The port's frontmatter parser must handle **both** inline `[a,b]` and block `- a` forms; a block-only subset silently parses the inline form to empty (the CLI awk at `skill-context-queries.sh:84-101` handles both — port it faithfully).
- `LC_ALL=C` sort + `MAX_GLOB=20` are load-bearing for parity — a different sort order changes *which* files a capped glob drops. Test with a >20-match fixture.
- The static-message Sentry mirror is a security control, not just hygiene: the model-controlled `skill` value must never enter `reportSilentFallback`'s payload (mirror `phase-surface-hook.ts:92-97`).
