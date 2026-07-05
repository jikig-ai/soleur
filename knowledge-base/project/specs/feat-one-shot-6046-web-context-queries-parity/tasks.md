# Tasks — feat(wave2) web-platform in-process parity for declarative `context_queries` (#6046)

Plan: `knowledge-base/project/plans/2026-07-05-feat-web-context-queries-parity-plan.md`
Lane: single-domain · Threshold: aggregate pattern · ADR-086 amendment

## Phase 0 — Preconditions
- [x] 0.1 Confirm registration shape at `agent-runner-query-options.ts:261-263` (`createPhaseSurfaceHook`, matcher `"Skill"`).
- [x] 0.2 Confirm `enablePhaseSurfaceHint: true` is set only at `cc-dispatcher.ts:2689`.
- [x] 0.3 Read `test/phase-surface-hook.test.ts` + `test/phase-surface-hint-shell-parity.test.ts` for mock + git-fixture conventions.
- [x] 0.4 Confirm `HookCallback` / `PostToolUseHookInput` import path from `phase-surface-hook.ts`.

## Phase 1 — Create the in-process hook
- [x] 1.1 Create `apps/web-platform/server/context-queries-hook.ts` exporting `createContextQueriesHook(repoRoot: string): HookCallback`.
- [x] 1.2 Kill-switch: `SOLEUR_DISABLE_CONTEXT_QUERIES === "1"` → `{}`.
- [x] 1.3 Gate #1 (skill name): string check → **anchored** `startsWith("soleur:")` strip (NOT `lastIndexOf(":")` — launders `other:plugin`→`plugin`) → `/^[a-z0-9-]+$/` or `{}`.
- [x] 1.4 Gate #2 (SKILL.md): `join(repoRoot,"plugins/soleur/skills",name,"SKILL.md")`, realpath containment via shared `isContained(real,root)` (`+ path.sep` guard), symlink reject (`lstatSync`), regular-file check.
- [x] 1.5 Frontmatter fast-path: parse block between first two `^---$`; require `context_queries:` key (frontmatter only, not body) or `{}`.
- [x] 1.6 Parse `context_queries` — both inline `[a,b]` (incl. `[]`) and block `- item`, quote-stripped (port `skill-context-queries.sh:84-101`; inline form is ADR-086 forward-compat, keep it).
- [x] 1.7 Gate #3+#4 per query: `knowledge-base/` prefix + reject `..`/absolute (no raw echo); `execFile("git",["-C",repoRoot,"ls-files","--",q],{timeout:2000})`; **per-query inner try/catch** → git failure/timeout ⇒ `skipped.push("<q> (no committed match)")` + continue (mirror shell `2>/dev/null||true`); `LC_ALL=C` byte-sort; `MAX_GLOB=20` cap; per-match symlink reject + `isContained` under `knowledge-base/` + exists; dedupe.
- [x] 1.8 Note assembly byte-identical to CLI hook (resolved / 0-resolved / skipped + operator-relay sentence); return `additionalContext`.
- [x] 1.9 Fail-open: whole body in `try/catch`; on throw → `reportSilentFallback(new Error("context-queries-hook: resolve failed"),{feature:"context-queries-hook",op:"resolve"})` (SYNTHETIC static Error — NEVER forward raw `err`, its `.message` leaks the skill-derived path); `log.warn({errName:(err as Error)?.name},...)` (never `{err}`) → `{}`.

## Phase 2 — Register sibling hook
- [x] 2.1 Add `enableContextQueries?: boolean` to `AgentQueryOptionsArgs` (doc-comment mirrors `enablePhaseSurfaceHint`).
- [x] 2.2 Import `createContextQueriesHook`.
- [x] 2.3 Restructure `PostToolUse` conditional into array concat: phase-surface + context-queries register independently; `...(postToolUse.length ? {PostToolUse: postToolUse} : {})`.

## Phase 3 — Enable on Concierge path
- [x] 3.1 Add `enableContextQueries: true` at `cc-dispatcher.ts:2689` (cc-soleur-go only; legacy leaves undefined).

## Phase 4 — ADR + C4
- [x] 4.1 Amend `ADR-086-declarative-skill-context-injection.md` Surface scope (web parity delivered) + add port to Verification.
- [x] 4.2a Edit `model.c4:41`: add `context-queries` to the webapp in-process hooks enumeration + extend citation to `(ADR-070 #5772, #5843; ADR-086 #6046)`.
- [x] 4.2b Add new edge to `model.c4` (near :302): `api -> kb "Reads context_queries artifacts (skill-scoped injection, web in-process)" { technology "File I/O" }`.
- [x] 4.3 Run `c4-code-syntax.test.ts` + `c4-render.test.ts`.

## Phase 5 — Tests + typecheck
- [x] 5.1 `test/context-queries-hook.test.ts` — 11 scenarios (see plan Test Scenarios; incl. #11 git-unavailable never-silent + AC8/AC8b), mock `observability.reportSilentFallback`.
- [x] 5.2 `test/context-queries-shell-parity.test.ts` — note byte-parity (3 note shapes) over the SHARED git fixture; skip loudly if bash/jq/git absent.
- [x] 5.3 Update `test/agent-runner-query-options.test.ts` PostToolUse cases (72-80) for two independent flags (2 entries when both on; undefined when neither).
- [x] 5.4 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.
- [x] 5.5 `cd apps/web-platform && ./node_modules/.bin/vitest run test/context-queries-hook.test.ts test/context-queries-shell-parity.test.ts test/agent-runner-query-options.test.ts`.

## Acceptance Criteria
See plan `## Acceptance Criteria` (AC1–AC13). All pre-merge; no post-merge operator steps (pure code change on already-provisioned surface).
