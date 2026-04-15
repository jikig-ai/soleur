---
title: "fix: KB Tree PDF to vision.md write fails with ZodError invalid_union"
plan: knowledge-base/project/plans/2026-04-15-fix-kb-tree-pdf-vision-md-write-zoderror-plan.md
status: planned
date: 2026-04-15
---

# Tasks: fix KB Tree PDF to vision.md write ZodError

## Phase 1: Reproduce and Diagnose

- [ ] 1.1 Pin SDK version and read changelog
  - [ ] 1.1.1 Record current SDK version: `node -e "console.log(require('@anthropic-ai/claude-agent-sdk/package.json').version)"` from `apps/web-platform/`
  - [ ] 1.1.2 Check SDK changelog/release notes for `0.2.80` changes to `PermissionResult`, `PreToolUseHookSpecificOutput`, `FileWriteInput`, `FileEditInput`
  - [ ] 1.1.3 Note any reported SDK issues with `invalid_union` on Write/Edit tool permissions

- [ ] 1.2 Reproduce the bug end-to-end
  - [ ] 1.2.1 Provision a test user workspace (or use an existing dev user) with a repo-backed KB
  - [ ] 1.2.2 Upload a small PDF via the dashboard KB Tree upload button
  - [ ] 1.2.3 Send a chat message to the dashboard agent: "Please update `knowledge-base/overview/vision.md` with the following content: [paste markdown]"
  - [ ] 1.2.4 Capture the full server log from `agent-runner` for the session (look for `ZodError`, `invalid_union`, `canUseTool`)
  - [ ] 1.2.5 Capture the Sentry event stack trace (use `SENTRY_API_TOKEN` from Doppler prd)
  - [ ] 1.2.6 Record the exact tool input the model sent (Write vs Edit, absolute vs relative file_path, content length)

- [ ] 1.3 Classify which layer produces the malformed output
  - [ ] 1.3.1 From the Zod issue path, determine which schema failed (PermissionResult, PreToolUseHookSpecificOutput, FileWriteInput, etc.)
  - [ ] 1.3.2 Map the failure to one of the six hypotheses in the plan's Root-cause hypotheses section
  - [ ] 1.3.3 Write a one-paragraph root-cause statement with evidence and save it inline in the plan under a new `## Root Cause (Confirmed)` subsection

## Phase 2: Write Failing Tests (TDD RED)

Per AGENTS.md `cq-write-failing-tests-before`: write these BEFORE implementation.

- [ ] 2.1 Extend `apps/web-platform/test/sandbox-hook.test.ts`
  - [ ] 2.1.1 Add test: `Write` with a valid workspace path returns `{ hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision: "allow" } }` (explicit allow, not `{}`)
  - [ ] 2.1.2 Add test: `Write` targeting a path whose parent dir does not yet exist (e.g., `<workspace>/knowledge-base/overview/vision.md` when `overview/` is absent) returns allow
  - [ ] 2.1.3 Schema-validate the returned object against a hand-written Zod schema matching `SyncHookJSONOutput` with `hookSpecificOutput` as `PreToolUseHookSpecificOutput`

- [ ] 2.2 Extend `apps/web-platform/test/agent-runner-tools.test.ts` (or create `apps/web-platform/test/canusertool-decisions.test.ts` if the existing file does not exercise the callback directly)
  - [ ] 2.2.1 Add test: extract the `canUseTool` callback into a testable unit (may require a small refactor in `agent-runner.ts` to export the builder function) and call it for `Write { file_path: "<workspace>/knowledge-base/overview/vision.md", content: "..." }`; assert `{ behavior: "allow" }`
  - [ ] 2.2.2 Add test: call it for `Write { file_path: "/etc/passwd", content: "..." }`; assert `{ behavior: "deny", message: string }` with non-empty `message`
  - [ ] 2.2.3 Schema-validate every return value against a hand-written Zod discriminated union matching SDK `PermissionResult`

- [ ] 2.3 Extend `apps/web-platform/test/workspace.test.ts`
  - [ ] 2.3.1 Add test: `provisionWorkspace` creates `${workspacePath}/knowledge-base/overview/` as a directory
  - [ ] 2.3.2 Assert existing `knowledge-base/project/{brainstorms,specs,plans,learnings}` still created

- [ ] 2.4 Extend `apps/web-platform/test/vision-creation.test.ts`
  - [ ] 2.4.1 Add test: `buildVisionEnhancementPrompt` returns a prompt string containing the **absolute** path `${workspacePath}/knowledge-base/overview/vision.md`, not the relative form
  - [ ] 2.4.2 Assert `tryCreateVision` behavior is unchanged

- [ ] 2.5 Run the full `apps/web-platform` vitest suite and confirm only the new tests fail
  - Command: `cd apps/web-platform && node node_modules/vitest/vitest.mjs run` (per AGENTS.md `cq-in-worktrees-run-vitest-via-node-node`)

## Phase 3: Implement the Fix (TDD GREEN)

Implement in the order dictated by Phase 1.3's confirmed root cause. The tasks below are the full menu; execute only those that apply, and document skipped items with reason.

- [ ] 3.1 `apps/web-platform/server/sandbox-hook.ts` -- explicit allow output
  - [ ] 3.1.1 Change the final `return {};` (line 57) to `return { hookSpecificOutput: { hookEventName: "PreToolUse" as const, permissionDecision: "allow" as const } };`
  - [ ] 3.1.2 Leave deny branches unchanged (already shape-valid)

- [ ] 3.2 `apps/web-platform/server/agent-runner.ts` -- shape-safe `canUseTool` wrapper
  - [ ] 3.2.1 Wrap the `canUseTool` callback body in a try/catch that `Sentry.captureException` with tag `module: "canUseTool"` and returns `{ behavior: "deny", message: "Internal permission check failed" }` on any error. This prevents a future programmer error from surfacing as `invalid_union` to the user
  - [ ] 3.2.2 Optionally: define a small local helper `assertPermissionResult(result: unknown): PermissionResult` that zod-parses the result before returning, with `Sentry.captureException` on parse failure

- [ ] 3.3 `apps/web-platform/server/workspace.ts` -- add `overview/` to provisioner
  - [ ] 3.3.1 Add `"overview"` to the `KNOWLEDGE_BASE_DIRS` tuple (line 25-30) OR create a separate block that creates `knowledge-base/overview/` outside `project/`
  - [ ] 3.3.2 Verify via existing provisioning code path (line 58-67) that the new directory is created on every fresh workspace
  - [ ] 3.3.3 Mirror the change in `provisionWorkspaceWithRepo` (line 120-245) so cloned workspaces also get the dir

- [ ] 3.4 `apps/web-platform/server/vision-helpers.ts` -- absolute path in enhancement prompt
  - [ ] 3.4.1 Change the return value of `buildVisionEnhancementPrompt` (line 73-76) to include the absolute workspace path in the instruction text: ``"... at `${visionPath}`. Enhance it... Write the enhanced version to the same path (`${visionPath}`)."``
  - [ ] 3.4.2 Keep the existing stub-detection logic unchanged

## Phase 4: Verify

- [ ] 4.1 Re-run the vitest suite; all tests green
  - Command: `cd apps/web-platform && node node_modules/vitest/vitest.mjs run`

- [ ] 4.2 Reproduce the end-to-end flow from Phase 1.2 against a dev environment; confirm no `ZodError`, no `invalid_union`, vision.md written correctly

- [ ] 4.3 Manual browser QA
  - [ ] 4.3.1 Upload a PDF via KB Tree
  - [ ] 4.3.2 Ask the agent to update vision.md
  - [ ] 4.3.3 Screenshot the successful turn + the updated vision.md page

- [ ] 4.4 Observability verification
  - [ ] 4.4.1 `doppler run -c dev -- supabase logs agent-runner | grep -E "invalid_union|ZodError"` returns zero matches for the new session
  - [ ] 4.4.2 Sentry search for `module:canUseTool` produces no new events

## Phase 5: Ship

- [ ] 5.1 Run `skill: soleur:compound` to capture learnings (required by AGENTS.md `wg-before-every-commit-run-compound-skill`)
- [ ] 5.2 Run `skill: soleur:review` on the branch
- [ ] 5.3 Run `skill: soleur:qa` against the dev deployment
- [ ] 5.4 Run `skill: soleur:ship` to open the PR with `semver:patch` label
- [ ] 5.5 Poll PR until auto-merged, then `cleanup-merged`
- [ ] 5.6 Run `skill: soleur:postmerge` to verify deploy + production health
