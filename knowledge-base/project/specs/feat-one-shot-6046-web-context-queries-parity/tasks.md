# Tasks — feat(wave2) web-platform in-process parity for declarative `context_queries` (#6046)

Plan: `knowledge-base/project/plans/2026-07-05-feat-web-context-queries-parity-plan.md`
Lane: single-domain · Threshold: aggregate pattern · ADR-086 amendment

## Phase 0 — Preconditions
- [ ] 0.1 Confirm registration shape at `agent-runner-query-options.ts:261-263` (`createPhaseSurfaceHook`, matcher `"Skill"`).
- [ ] 0.2 Confirm `enablePhaseSurfaceHint: true` is set only at `cc-dispatcher.ts:2689`.
- [ ] 0.3 Read `test/phase-surface-hook.test.ts` + `test/phase-surface-hint-shell-parity.test.ts` for mock + git-fixture conventions.
- [ ] 0.4 Confirm `HookCallback` / `PostToolUseHookInput` import path from `phase-surface-hook.ts`.

## Phase 1 — Create the in-process hook
- [ ] 1.1 Create `apps/web-platform/server/context-queries-hook.ts` exporting `createContextQueriesHook(repoRoot: string): HookCallback`.
- [ ] 1.2 Kill-switch: `SOLEUR_DISABLE_CONTEXT_QUERIES === "1"` → `{}`.
- [ ] 1.3 Gate #1 (skill name): string check → defensive colon-strip → `/^[a-z0-9-]+$/` or `{}`.
- [ ] 1.4 Gate #2 (SKILL.md): `join(repoRoot,"plugins/soleur/skills",name,"SKILL.md")`, realpath containment under skills dir, symlink reject, regular-file check.
- [ ] 1.5 Frontmatter fast-path: parse block between first two `^---$`; require `context_queries:` key (frontmatter only, not body) or `{}`.
- [ ] 1.6 Parse `context_queries` — both inline `[a,b]` (incl. `[]`) and block `- item`, quote-stripped (port `skill-context-queries.sh:84-101`).
- [ ] 1.7 Gate #3+#4 per query: `knowledge-base/` prefix + reject `..`/absolute (no raw echo); `git -C repoRoot ls-files -- <q>` via execFile; `LC_ALL=C` byte-sort; `MAX_GLOB=20` cap; per-match symlink reject + realpath containment under `knowledge-base/` + exists; dedupe.
- [ ] 1.8 Note assembly byte-identical to CLI hook (resolved / 0-resolved / skipped + operator-relay sentence); return `additionalContext`.
- [ ] 1.9 Fail-open: whole body in `try/catch`; on throw → `log.warn` + `reportSilentFallback(err,{feature:"context-queries-hook",op:"resolve"})` (STATIC message, no `skill` value) → `{}`.

## Phase 2 — Register sibling hook
- [ ] 2.1 Add `enableContextQueries?: boolean` to `AgentQueryOptionsArgs` (doc-comment mirrors `enablePhaseSurfaceHint`).
- [ ] 2.2 Import `createContextQueriesHook`.
- [ ] 2.3 Restructure `PostToolUse` conditional into array concat: phase-surface + context-queries register independently; `...(postToolUse.length ? {PostToolUse: postToolUse} : {})`.

## Phase 3 — Enable on Concierge path
- [ ] 3.1 Add `enableContextQueries: true` at `cc-dispatcher.ts:2689` (cc-soleur-go only; legacy leaves undefined).

## Phase 4 — ADR + C4
- [ ] 4.1 Amend `ADR-086-declarative-skill-context-injection.md` Surface scope (web parity delivered) + add port to Verification.
- [ ] 4.2 Edit `model.c4` line ~41: add `context-queries` to the webapp in-process hooks enumeration.
- [ ] 4.3 Run `c4-code-syntax.test.ts` + `c4-render.test.ts`.

## Phase 5 — Tests + typecheck
- [ ] 5.1 `test/context-queries-hook.test.ts` — 10 scenarios (see plan Test Scenarios), mock `observability.reportSilentFallback`.
- [ ] 5.2 `test/context-queries-shell-parity.test.ts` — run real `.claude/hooks/skill-context-queries.sh` vs TS hook, byte-parity ≥3 cases; skip loudly if bash/jq/git absent.
- [ ] 5.3 Update `test/agent-runner-query-options.test.ts` PostToolUse cases (72-80) for two independent flags (2 entries when both on; undefined when neither).
- [ ] 5.4 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` clean.
- [ ] 5.5 `cd apps/web-platform && ./node_modules/.bin/vitest run test/context-queries-hook.test.ts test/context-queries-shell-parity.test.ts test/agent-runner-query-options.test.ts`.

## Acceptance Criteria
See plan `## Acceptance Criteria` (AC1–AC13). All pre-merge; no post-merge operator steps (pure code change on already-provisioned surface).
