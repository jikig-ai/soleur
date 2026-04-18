# Tasks — drain agent-runtime review backlog

**Branch:** `feat-one-shot-agent-runtime-1662-2333-2336`
**Plan:** `knowledge-base/project/plans/2026-04-18-refactor-agent-runtime-drain-plan.md`
**Closes:** #1662 #2333 #2334 #2335 #2336

## Phase 1 — MCP tool extraction (#1662)

1.1. Create `apps/web-platform/server/github-tools.ts` exporting `buildGithubTools(opts): { tools, toolNames }` covering `create_pull_request`, `github_read_ci_status`, `github_read_workflow_logs`, `github_trigger_workflow`, `github_push_branch`.
1.2. Create `apps/web-platform/server/plausible-tools.ts` exporting `buildPlausibleTools({ plausibleKey }): { tools, toolNames }` covering `plausible_create_site`, `plausible_add_goal`, `plausible_get_stats`.
1.3. Delete inline `tool()` definitions from `agent-runner.ts` (lines ~644-857 per pre-edit grep) and replace with factory calls.
1.4. Spread `tools`/`toolNames` into `platformTools`/`platformToolNames` at call sites.
1.5. Run `cd apps/web-platform && ./node_modules/.bin/vitest run agent-runner-tools canusertool-tiered-gating` — must pass.

## Phase 2 — Workspace hardening + dedupe (#2333, #2334)

2.1. **RED** — write `apps/web-platform/test/workspace-symlink-hardening.test.ts` with symlink-at-`knowledge-base/overview`-pointing-outside test. Run → expect failure.
2.2. Rewrite `ensureDir` in `apps/web-platform/server/workspace.ts` to use `lstatSync` and throw on non-directory entries.
2.3. Rename constant `KNOWLEDGE_BASE_DIRS` → `KNOWLEDGE_BASE_PROJECT_DIRS`. Grep-sweep `apps/web-platform` and `plugins/` for old name; zero hits after edit.
2.4. Extract `scaffoldWorkspaceDefaults(workspacePath, { suppressWelcomeHook? } = {})` covering KB dirs + `.claude/` + plugin symlink.
2.5. Replace duplicated blocks in `provisionWorkspace` and `provisionWorkspaceWithRepo` with single `scaffoldWorkspaceDefaults` call each.
2.6. Run `cd apps/web-platform && ./node_modules/.bin/vitest run workspace` — all four workspace test files must pass.

## Phase 3 — canUseTool extraction + tests (#2335)

3.1. **RED** — write `apps/web-platform/test/canusertool-decisions.test.ts` covering 7 allow branches + deny-by-default with SDK-permission-shape schema validation. Run → expect failure.
3.2. Create `apps/web-platform/server/permission-callback.ts` exporting `createCanUseTool(ctx: CanUseToolContext): CanUseTool`. Move the `allow()` helper inside this module.
3.3. Replace inline `canUseTool:` closure in `agent-runner.ts` with `canUseTool: createCanUseTool({...})`.
3.4. Run `cd apps/web-platform && ./node_modules/.bin/vitest run canusertool-decisions canusertool-tiered-gating canusertool-caching agent-runner-tools` — must pass.

## Phase 4 — SOLEUR_DEBUG_PERMISSION_LAYER (#2336)

4.1. **RED** — write `apps/web-platform/test/permission-log.test.ts` covering: flag unset → 0 debug calls; flag `"1"` → 1 debug call per invocation with correct payload. Run → expect failure.
4.2. Create `apps/web-platform/server/permission-log.ts` with `PermissionLayer` union + `logPermissionDecision()` gated on `process.env.SOLEUR_DEBUG_PERMISSION_LAYER === "1"`.
4.3. Instrument `sandbox-hook.ts` (file-tool deny, bash env-access deny, explicit allow).
4.4. Instrument `permission-callback.ts` (all 7 allow branches + deny-by-default + review-gate deny + platform-blocked deny).
4.5. Run `cd apps/web-platform && ./node_modules/.bin/vitest run permission-log canusertool-decisions sandbox-hook` — must pass.

## Phase 5 — Verification

5.1. Run full test suite: `cd apps/web-platform && ./node_modules/.bin/vitest run`.
5.2. Run `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` — must pass.
5.3. Run `npx markdownlint-cli2 --fix knowledge-base/project/plans/2026-04-18-refactor-agent-runtime-drain-plan.md knowledge-base/project/specs/feat-one-shot-agent-runtime-1662-2333-2336/tasks.md`.
5.4. Commit with conventional-format message; ensure PR body contains `Closes #1662`, `Closes #2333`, `Closes #2334`, `Closes #2335`, `Closes #2336`.

## Learning hooks

- If during implementation the SDK exposes `PermissionResult` as a runtime-importable zod schema, use it directly in the tests instead of hand-rolling one. Record in `knowledge-base/project/learnings/best-practices/<topic>.md`.
- If `createCanUseTool` context object exceeds ~15 fields, extract a sub-context (e.g., `ReviewGateContext`) rather than bloating a single interface. Record the seam.
