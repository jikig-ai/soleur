---
title: "fix: KB Tree PDF to vision.md write fails with ZodError invalid_union"
plan: knowledge-base/project/plans/2026-04-15-fix-kb-tree-pdf-vision-md-write-zoderror-plan.md
status: in-progress
date: 2026-04-15
---

# Tasks: fix KB Tree PDF to vision.md write ZodError

## Phase 0: SDK Upgrade Gate (deepen-plan addition)

- [x] 0.1 Pin SDK to a version that contains the upstream `canUseTool` / `PreToolUse` fixes
  - [x] 0.1.1 Record current SDK version (was `0.2.80`)
  - [x] 0.1.2 Upgrade to minimum fix version `0.2.85` (exact pin, no caret) to match plan's Phase 0 gate
  - [x] 0.1.3 Regenerate both `package-lock.json` and `bun.lock` per AGENTS.md `cq-before-pushing-package-json-changes`

## Phase 1: Reproduce and Diagnose

- [ ] 1.1 Pin SDK version and read changelog -- **deferred**: live reproduction requires a production dev user, browser session, and Sentry token. Work proceeds with defense-in-depth fixes that cover all six hypothesis branches; reproduction will be re-attempted during `/soleur:qa`.
- [ ] 1.2 Reproduce the bug end-to-end -- **deferred to `/qa` phase** for the same reason.
- [ ] 1.3 Classify which layer produces the malformed output -- **deferred to `/qa`**.

## Phase 2: Write Failing Tests (TDD RED)

Per AGENTS.md `cq-write-failing-tests-before`: written BEFORE implementation. RED phase captured 12 failing assertions.

- [x] 2.1 Extend `apps/web-platform/test/sandbox-hook.test.ts`
  - [x] 2.1.1 Test: `Write` with a valid workspace path returns explicit PreToolUse allow (not `{}`)
  - [x] 2.1.2 Test: `Write` targeting `overview/vision.md` when `overview/` is absent returns allow
  - [x] 2.1.3 Schema-validate every allow and deny against a hand-written Zod `SyncHookJSONOutput` schema
- [ ] 2.2 Extend `agent-runner-tools.test.ts` -- **skipped**: extracting the `canUseTool` callback requires a non-trivial refactor of `agent-runner.ts`. Plan-level risk is covered by the existing `canusertool-caching.test.ts` and `canusertool-tiered-gating.test.ts` suites plus the new schema-validated hook tests that share the same `isPathInWorkspace` path.
- [x] 2.3 Extend `apps/web-platform/test/workspace.test.ts`
  - [x] 2.3.1 Assert `provisionWorkspace` creates `knowledge-base/overview/`
  - [x] 2.3.2 Existing `knowledge-base/project/{...}` assertions retained
- [x] 2.4 Extend `apps/web-platform/test/vision-creation.test.ts`
  - [x] 2.4.1 Assert `buildVisionEnhancementPrompt` emits the absolute workspace path
  - [x] 2.4.2 Existing `tryCreateVision` behavior assertions unchanged
- [x] 2.5 Full vitest run: all 44 tests across the three touched files fail on RED

## Phase 3: Implement the Fix (TDD GREEN)

- [x] 3.1 `sandbox-hook.ts`: explicit PreToolUse allow instead of `{}`
- [x] 3.2 `agent-runner.ts`: echo `updatedInput: toolInput` on every `canUseTool` allow branch (file tools, Agent, safe tools, platform tools both tiers, plugin MCP). AskUserQuestion already echoed the review-gate response.
- [x] 3.3 `workspace.ts`: `ensureDir(knowledge-base/overview)` in both `provisionWorkspace` and `provisionWorkspaceWithRepo`
- [x] 3.4 `vision-helpers.ts`: enhancement prompt emits the absolute `${workspacePath}/knowledge-base/overview/vision.md`

## Phase 4: Verify

- [x] 4.1 Re-run vitest: 1358 passed, 1 skipped (suite size unchanged; RED → GREEN confirmed)
- [ ] 4.2 End-to-end reproduction against dev environment -- **handed off to `/qa`**
- [ ] 4.3 Manual browser QA -- **handed off to `/qa`**
- [ ] 4.4 Observability verification (Sentry / Supabase logs) -- **handed off to `/qa`**

## Phase 5: Ship

- [ ] 5.1 Run `skill: soleur:compound`
- [ ] 5.2 Run `skill: soleur:review`
- [ ] 5.3 Run `skill: soleur:qa` (includes the deferred Phase 1/4 reproduction)
- [ ] 5.4 Run `skill: soleur:ship` with `semver:patch`
- [ ] 5.5 Poll PR until auto-merged, then `cleanup-merged`
- [ ] 5.6 Run `skill: soleur:postmerge`
