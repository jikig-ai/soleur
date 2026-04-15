---
title: "fix: KB Tree PDF to vision.md write fails with ZodError invalid_union on Write/Edit"
type: fix
date: 2026-04-15
---

# fix: KB Tree PDF to vision.md write fails with ZodError invalid_union on Write/Edit

## Overview

When a user uploads a PDF through the KB Tree web UI and asks the dashboard agent (e.g., Oleg/CTO) to update `knowledge-base/overview/vision.md` with the extracted content, both `Write` and `Edit` tool calls fail. The agent surfaces a user-visible explanation that "Write/Edit tools are throwing an internal permission validation error (a `ZodError`)" and that the filesystem is "read-only" in Bash. The agent concludes this is a platform bug and tells the user to copy-paste markdown manually.

This plan identifies the most likely root causes in the platform's `canUseTool` / PreToolUse permission wiring, prescribes diagnostic telemetry to confirm which Zod union is failing, and ships a fix with regression tests. The fix keeps the existing defense-in-depth (bubblewrap sandbox, PreToolUse path checks, `canUseTool` file-tool guard) and corrects whichever permission-chain step is producing a SDK schema violation for Write/Edit on a path that should be allowed (`<workspacePath>/knowledge-base/overview/vision.md`).

**Out of scope:** changing the sandbox architecture (allowWrite/denyRead), rewriting the KB upload path, or giving the agent binary PDF reading capability (tracked separately in #2008).

## Problem Statement / Motivation

### User-visible symptoms (from screenshots)

Screenshot 1 (`/home/jean/Pictures/Screenshots/Screenshot From 2026-04-15 12-00-02.png`):

> "The `Write` tool hit a permission error. Let me use `Edit` instead to replace the file content. Both `Write` and `Edit` are hitting a permission error -- it looks like there's a tool permissions issue in the workspace configuration preventing file writes. This isn't a content problem; it's a sandboxing/settings issue."

Screenshot 2 (`/home/jean/Pictures/Screenshots/Screenshot From 2026-04-15 12-00-16.png`):

> "I'm hitting a platform-level issue -- the filesystem is read-only in the Bash sandbox, and the Write/Edit tools are throwing an internal permission validation error (a `ZodError`). This appears to be a bug on the platform side, not something I can work around."

The agent's structured table in Screenshot 2:

| Tool | Error |
|------|-------|
| `Write` / `Edit` | `ZodError` -- permission request validation is failing internally |
| `Bash` | Filesystem is read-only (`Read-only file system`) |

The user's recommended workaround ("copy the markdown manually to `knowledge-base/overview/vision.md`") is unacceptable: the core value proposition of the dashboard is agents maintaining KB artifacts. When the agent cannot write a single markdown file within its own workspace, onboarding breaks.

### Why this matters

1. Vision document creation is a foundation card in Start Fresh onboarding (#1751). A broken write path breaks the first-run experience.
2. The failure is surfaced to users as a self-aware "bug on the platform side", which erodes trust in the product.
3. The screenshots show the agent degrading gracefully (asking the user to use `update-config` or restart the session), which is a useful fallback but masks the root cause and makes the bug harder to detect via telemetry.

### Current code inventory

- `apps/web-platform/server/agent-runner.ts:785-1060` -- SDK `query()` with `permissionMode: "default"`, `settingSources: []`, sandbox block, PreToolUse hook, `canUseTool` callback.
- `apps/web-platform/server/sandbox-hook.ts` -- PreToolUse hook returning `{ hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: ... }, systemMessage: ... }` on deny; `{}` on allow.
- `apps/web-platform/server/tool-path-checker.ts` -- `FILE_TOOLS` includes Write/Edit; `extractToolPath` reads `file_path`.
- `apps/web-platform/server/sandbox.ts` -- `isPathInWorkspace` canonicalises via `fs.realpathSync`; returns `false` on `ELOOP`/`EACCES`/null.
- `apps/web-platform/server/vision-helpers.ts:73-77` -- `buildVisionEnhancementPrompt` instructs the agent: "Write the enhanced version to the same path." with a relative path `knowledge-base/overview/vision.md`.
- `apps/web-platform/server/workspace.ts:25-39, 58-67` -- `provisionWorkspace` creates `knowledge-base/project/{brainstorms,specs,plans,learnings}` but **not** `knowledge-base/overview/`.
- `apps/web-platform/app/api/kb/upload/route.ts` -- commits PDF to GitHub, then `git pull --ff-only` into workspace (fixed in #2145 learning `kb-upload-missing-credential-helper-20260413.md`).
- `apps/web-platform/server/agent-runner.ts:1283-1396` (`sendUserMessage`) -- downloads chat attachments to `${workspacePath}/attachments/${conversationId}/${uuid}.pdf`, appends absolute paths to prompt.
- SDK types: `apps/web-platform/node_modules/@anthropic-ai/claude-agent-sdk/sdk.d.ts`
  - `PermissionResult` (line 1280): `{ behavior: "allow", updatedInput?, updatedPermissions?, toolUseID? } | { behavior: "deny", message: string, interrupt?, toolUseID? }` -- **`message` is required on deny**.
  - `PreToolUseHookSpecificOutput` (line 1378): `{ hookEventName: "PreToolUse", permissionDecision?: "allow" | "deny" | "ask", permissionDecisionReason?: string }`.
  - `SyncHookJSONOutput` (line 3785): `{ continue?, suppressOutput?, stopReason?, decision?, systemMessage?, reason?, hookSpecificOutput? }`.
  - `FileWriteInput` (sdk-tools.d.ts:392): `{ file_path: string, content: string }`.
  - `FileEditInput` (sdk-tools.d.ts:356): `{ file_path: string, old_string: string, new_string: string, replace_all?: boolean }`.
- SDK version: `0.2.80` (apps/web-platform/node_modules/@anthropic-ai/claude-agent-sdk/package.json).

### Prior art / related issues

- #2008 "feat: agent-side binary file access for KB uploads" -- open, deferred from KB upload V1. Agents can see filenames but cannot read binary PDF content server-side. **Relevant:** when the user asks "update vision.md from the PDF I just uploaded", the agent has the filename in the KB tree but has no way to extract text -- it must either ask the user to describe the PDF or refuse. If the user dictated the content, this is orthogonal to the write failure; if the agent tried to `Read` the PDF, a read failure surfaces differently than a write failure.
- Learning `kb-upload-missing-credential-helper-20260413.md` line 44: "Write tool rejected /tmp files -- Attempted to use the Write tool on `/tmp/review-finding-*.md` files that hadn't been Read first." This is a harness-level behavior (Write requires Read first for existing files) and is **not** the same as the ZodError symptom, but it suggests Claude Code's internal "file state tracking" is active even in server-side SDK usage.
- #875, #876, #878, #891, #894 (closed) -- prior canUseTool / sandbox hardening work. The current defense-in-depth has four layers: bubblewrap filesystem, PreToolUse hook, canUseTool file-tool check, deny-by-default. An `invalid_union` ZodError is a **new failure mode** not covered by those fixes.
- #1285 (open) -- "sec: add /sys to sandbox denyRead for defense-in-depth" (unrelated, tracked separately).

## Proposed Solution

Root-cause the ZodError, fix the broken permission-chain output shape, and add regression coverage. The sequence is:

1. **Reproduce** the bug against a dev workspace with a provisioned user, upload a PDF via KB Tree, and ask the dashboard agent to update `knowledge-base/overview/vision.md`. Capture the exact Zod issue path from server logs / Sentry.
2. **Classify** which permission-chain step emits the invalid output. Six hypotheses (ranked by prior probability below) -- the reproduction + SDK debug logs narrow this to one.
3. **Fix** the identified root cause with a minimal diff, preserving all existing defense-in-depth layers.
4. **Defense-in-depth additions** that address the broader class of bugs:
   a. Pre-create `knowledge-base/overview/` in `provisionWorkspace` so the first Write never targets a non-existent ancestor directory.
   b. Change `buildVisionEnhancementPrompt` to emit an **absolute** path (`${workspacePath}/knowledge-base/overview/vision.md`) so the agent never passes a relative `file_path` to Write/Edit.
   c. Wrap the `canUseTool` callback and PreToolUse hook in a shape-validation layer that log.error's any malformed decision (using the SDK's exported zod schemas where available) instead of silently returning it to the CLI.
5. **Regression tests:**
   - Unit test: `canUseTool` returns shape-valid `PermissionResult` for Write/Edit targeting an existing file within workspace.
   - Unit test: `canUseTool` returns shape-valid `{ behavior: "deny", message: string }` for Write targeting a path outside the workspace (message is never undefined).
   - Unit test: PreToolUse hook returns shape-valid `SyncHookJSONOutput` for Write targeting `knowledge-base/overview/vision.md` where `overview/` does not yet exist on disk (exercises the `resolveParentRealPath` branch of `isPathInWorkspace`).
   - Unit test: `provisionWorkspace` creates `knowledge-base/overview/` alongside the `project/` subdirectories.
   - Integration test (vitest + mock SDK): sending the prompt "Update vision.md with this content: <markdown>" results in a `Write` tool call whose `file_path` starts with the workspace root and which passes both the hook and canUseTool.

### Root-cause hypotheses (ranked)

The reproduction will narrow this to one. All six must be investigated before writing code:

1. **Highest: `isPathInWorkspace` returns `false` for a path in a non-existent subdirectory.** `resolveRealPath(/workspaces/<uid>/knowledge-base/overview/vision.md)` calls `fs.realpathSync` → `ENOENT` → `resolveParentRealPath` walks up. `knowledge-base/overview/` does not exist (provisioner only creates `project/`). Walk continues to `knowledge-base/`, which is a real directory, so `realpathSync` returns that canonical path. Re-appends `overview/vision.md`. Result: `/workspaces/<uid>/knowledge-base/overview/vision.md` (string-joined). The containment check passes. **BUT** the `canUseTool` callback's deny branch returns `{ behavior: "deny", message: "Access denied: outside workspace..." }` -- valid. This branch should **not** fire for the legitimate path. If it does (e.g., a symlink target escapes workspace, or `realpathSync` on `/workspaces/` hits an unexpected mount state), the deny message is a proper string. This alone does **not** cause `invalid_union`.

2. **Very high: `hookSpecificOutput` discriminated-union mismatch when PreToolUse hook returns `{}` (allow).** The sandbox-hook's allow path returns `{}` -- no `hookSpecificOutput`, no `systemMessage`. Per SDK `SyncHookJSONOutput`, all fields are optional, so `{}` should validate. **However:** if the CLI's internal validator uses a discriminated union keyed on `hookEventName` and the field is missing, the CLI may synthesize a "no decision" object that then fails a stricter downstream schema when the tool is Write/Edit (file tools have stricter validation than Read). Fix: always return an explicit `{ hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision: "allow" } }` on the allow path.

3. **High: `canUseTool` deny branch missing required `message` field in some code path.** The SDK type requires `message: string` on `{ behavior: "deny" }`. A code path that returns `{ behavior: "deny" }` without `message` -- or with `message: undefined` / `message: null` -- fails the discriminated-union parse with `invalid_union`. Scan every return statement in `agent-runner.ts:858-1060`. Current code all looks correct on file-tool path (line 872), the deny-by-default (line 1057), platform-tool blocked (line 981), and platform-tool rejected (line 1027). But a programmer error in a later branch (e.g., a future edit inserting `{ behavior: "deny" }`) would produce exactly this symptom.

4. **Medium: relative `file_path` from the model.** `buildVisionEnhancementPrompt` says "Write the enhanced version to the same path" referring to `knowledge-base/overview/vision.md` (relative). If the model passes `file_path: "knowledge-base/overview/vision.md"` (relative), the SDK type `FileWriteInput.file_path` is `string` (not URL, not "absolute"), so Zod parses it fine. The CLI then resolves it against `cwd` (the workspace). Downstream `realpathSync` on the resolved absolute path works the same as hypothesis (1). **Not** a direct cause of ZodError but worth fixing for clarity.

5. **Medium: SDK tool-input validation mismatch after v0.2.80 update.** If the CLI now validates `FileEditInput` with a discriminated union (e.g., `old_string` vs a hypothetical `patch` variant), the model's invocation may not satisfy the new shape. Mitigation: pin the SDK version, read the CHANGELOG for 0.2.80, grep for schema changes.

6. **Low: `permissionDecisionReason` required when `permissionDecision` is set.** Per SDK type (`PreToolUseHookSpecificOutput`), both are optional. But the CLI may require `permissionDecisionReason` when `permissionDecision === "deny"` and fail `invalid_union` when it's missing. sandbox-hook already provides `permissionDecisionReason` on deny, so unlikely.

### Why the Bash "Read-only file system" is orthogonal

The screenshots show Bash failing with `Read-only file system` when the agent tried `echo ... > vision.md` as a fallback. This is **expected behavior** of the bubblewrap sandbox:

- `allowWrite: [workspacePath]` only grants write to the user's workspace root.
- If the agent runs `echo > vision.md` from a CWD outside `workspacePath` (e.g., `/tmp` or `/`), bwrap's read-only rootfs denies the write with EROFS.
- If the agent runs `echo > ./vision.md` with CWD=workspacePath, it should succeed.

This is **not** a bug -- it's the sandbox working as designed. The agent's interpretation ("filesystem is read-only") is misleading. The Bash symptom is secondary: the agent tried Bash as a fallback after Write/Edit failed, not as the primary path.

**Out of scope:** changing `allowWrite` scope or the sandbox's rootfs mode. The Write/Edit path must succeed; Bash-as-fallback is a dead end by design.

## Technical Considerations

### Architecture impacts

- No architectural changes. The fix is localized to `sandbox-hook.ts`, `agent-runner.ts` (`canUseTool`), `workspace.ts` (provisioner), `vision-helpers.ts` (prompt text).
- The permission-chain order (hook → sandbox → canUseTool → deny-by-default) is unchanged.
- Defense-in-depth layers are preserved. If a malformed decision sneaks through one layer, another catches it.

### Performance implications

- Negligible. Adding an explicit `hookSpecificOutput` on the allow path adds one object allocation per tool call. `provisionWorkspace` adds one `mkdir` call per new user (one-time).

### Security considerations

- **No regression in sandbox guarantees.** All path-validation logic is unchanged. The new `knowledge-base/overview/` directory is created inside `workspacePath`, which is already allowWrite-scoped.
- **No new deny-list changes.** We do not touch `denyRead` / `FILE_TOOLS_TO_REMOVE`.
- **Hook-output shape validation** must not leak internal paths to the client. If we add log.error for malformed decisions, sanitize via `sanitizeErrorForClient` before any WS emission (see `error-sanitizer.ts`).
- **Sentry must capture ZodError stack traces server-side** to diagnose any recurrence. Add `Sentry.captureException(err, { tags: { module: "canUseTool" } })` in the catch block of the `canUseTool` callback wrapper.

### NFR impacts

Run `/soleur:architecture assess` against `knowledge-base/engineering/architecture/nfr-register.md` during work phase. Expected deltas:

- **Reliability:** improves -- Write/Edit path becomes deterministic instead of failing opaquely.
- **Observability:** improves -- ZodError stack traces captured via Sentry, permission decisions logged with structured context.
- **Security:** neutral -- defense-in-depth preserved; all new code paths are additive inside the workspace boundary.

### Attack Surface Enumeration (defense-in-depth check)

List ALL code paths that enforce the workspace boundary for Write/Edit:

| Layer | Path | Mechanism | Covered by fix? |
|-------|------|-----------|-----------------|
| 1. SDK bubblewrap | `sandbox: { filesystem: { allowWrite: [workspacePath] } }` in agent-runner.ts:826 | Kernel-level namespace mount | Unchanged |
| 2. PreToolUse hook | `sandbox-hook.ts:18` via matcher `Read\|Write\|Edit\|...` | `isPathInWorkspace` + permissionDecision "deny" | Fixed (explicit allow output) |
| 3. canUseTool | `agent-runner.ts:867` via `isFileTool` check | `isPathInWorkspace` + `{ behavior: "deny", message }` | Fixed (shape validation) |
| 4. Deny-by-default | `agent-runner.ts:1056` fallthrough | `{ behavior: "deny", message: "Tool not permitted..." }` | Unchanged |

All four layers must return schema-valid output for the SDK to route the tool call. The bug is that layer 2 or 3 produces invalid output, which this plan fixes.

## Acceptance Criteria

### Functional

- [ ] User uploads a PDF through KB Tree (dashboard > KB page > Upload) successfully.
- [ ] User sends the chat message "Update `knowledge-base/overview/vision.md` with this content: \<markdown>" (or equivalent) to a domain leader.
- [ ] The agent invokes `Write` or `Edit`. The tool call completes without surfacing any `ZodError`, `invalid_union`, or "permission request validation is failing internally" language to the user.
- [ ] `knowledge-base/overview/vision.md` contains the new content after the agent turn completes.
- [ ] The change is committed to the user's GitHub repo via the existing session-sync push path (or at minimum persists in the workspace and shows up in the KB tree on the next page refresh).
- [ ] When the agent attempts to Write outside the workspace (e.g., `/etc/passwd`), the user sees a clear denial message -- NOT a ZodError.

### Observability

- [ ] Any future permission-chain malformed output produces a Sentry event with tag `module: "canUseTool"` or `module: "sandbox-hook"`, including the tool name, input shape (redacted), and Zod issue path.
- [ ] Structured log at `info` level for every successful Write/Edit decision, including `tool`, `pathWithinWorkspace: true`, `subagent: boolean`.

### Regression coverage

- [ ] New test: `canUseTool` returns `{ behavior: "allow" }` (with shape assertion via Zod parse against SDK `PermissionResult` type) for Write targeting a valid workspace path, including cases where the parent directory does not yet exist.
- [ ] New test: `canUseTool` returns `{ behavior: "deny", message: string }` (with `message` non-empty) for every deny code path in the callback.
- [ ] New test: sandbox-hook returns a shape-valid `SyncHookJSONOutput` on both allow and deny paths. Allow path must include an explicit `hookSpecificOutput` discriminated as `PreToolUse`.
- [ ] New test: `provisionWorkspace` creates `knowledge-base/overview/` alongside `knowledge-base/project/`.
- [ ] Existing tests in `sandbox-hook.test.ts`, `agent-runner-tools.test.ts`, `tool-path-checker.test.ts`, `workspace.test.ts`, `vision-creation.test.ts` still pass.

### Quality gates

- [ ] Full vitest suite passes from `apps/web-platform/` (use `node node_modules/vitest/vitest.mjs run` per AGENTS.md `cq-in-worktrees-run-vitest-via-node-node`).
- [ ] `npx markdownlint-cli2 --fix` clean on any touched markdown.
- [ ] No new lint warnings.
- [ ] Plan-review skill run before ship.

## Test Scenarios

### Acceptance Tests (RED phase targets)

Write these failing first, before any implementation:

- **Given** a user with a provisioned workspace at `/tmp/test-workspaces/<uuid>` and a repo-backed KB containing `knowledge-base/overview/vision.md`, **when** the agent invokes `Write { file_path: "<workspace>/knowledge-base/overview/vision.md", content: "# New Vision\n..." }`, **then** `canUseTool` returns `{ behavior: "allow" }` and the return value passes `z.discriminatedUnion("behavior", [...]).parse()`.
- **Given** the same workspace with `knowledge-base/overview/` **not yet existing**, **when** the agent invokes `Write` targeting that non-existent path, **then** `isPathInWorkspace` returns `true` and `canUseTool` returns `{ behavior: "allow" }`.
- **Given** the same workspace, **when** the agent invokes `Write { file_path: "/etc/passwd", content: "pwned" }`, **then** `canUseTool` returns `{ behavior: "deny", message: "..." }` where `message` is a non-empty string.
- **Given** the same workspace, **when** the PreToolUse hook fires for `Write` with a valid workspace path, **then** the hook returns `{ hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision: "allow" } }` (explicit, not `{}`).
- **Given** a freshly provisioned workspace, **when** `provisionWorkspace` completes, **then** `fs.existsSync(<workspace>/knowledge-base/overview)` is `true`.
- **Given** a workspace with a stub `vision.md` (< 500 bytes), **when** `buildVisionEnhancementPrompt` is called, **then** the returned prompt contains the **absolute** path `<workspace>/knowledge-base/overview/vision.md`, not the relative path.

### Regression Tests

- **Given** the existing `sandbox-hook.test.ts` cases (denies `/etc/passwd`, `/proc/1/environ`, etc.), **when** run after the hook-output shape change, **then** all existing deny cases still deny with the same `systemMessage` and `permissionDecisionReason`.
- **Given** the #891 path-validation test suite (LS, NotebookEdit, NotebookRead), **when** run after this change, **then** all path-validation behavior is unchanged.

### Edge Cases

- **Given** a workspace path containing symlinks (e.g., `/workspaces/<uid>` is itself a symlink), **when** `isPathInWorkspace` validates a Write target, **then** canonicalisation handles it correctly (existing behavior).
- **Given** a Write target deeper than any existing directory (e.g., `knowledge-base/overview/subdir/further/new.md`), **when** `canUseTool` runs, **then** `resolveParentRealPath` walks up past multiple non-existent segments to the workspace root and allows the write.
- **Given** a Write with `file_path: ""` (empty), **when** `canUseTool` runs, **then** the empty-path branch allows it through (consistent with Glob/Grep defaulting to cwd) and the SDK's own `FileWriteInput` schema rejects it upstream.
- **Given** a subagent (Agent tool spawning a sub-session) invoking Write on a workspace path, **when** `canUseTool` runs with `options.agentID` set, **then** the same allow/deny logic applies and the `subagentCtx` appears in the log line.

### Integration Verification (for `/soleur:qa`)

Manual reproduction against dev environment:

- **Browser:** Navigate to `https://<dev-domain>/dashboard/kb`. Click "Upload" on the root folder. Select a small PDF (< 1 MB). Wait for upload toast.
- **Browser:** Open chat panel, send: "Please update `knowledge-base/overview/vision.md` with the following content:\n\n# Vision\n\n[paste markdown]".
- **Verify:** Chat does NOT surface "ZodError", "invalid_union", or "permission request validation is failing". Agent completes the turn and reports success.
- **Verify:** Reload `/dashboard/kb/knowledge-base/overview/vision.md`. New content is visible.
- **Server log check:** `doppler run -c dev -- supabase logs agent-runner | grep -E "invalid_union|ZodError|canUseTool"` returns zero matches.
- **Sentry check:** `curl -s -H "Authorization: Bearer $SENTRY_API_TOKEN" https://sentry.io/api/0/projects/<org>/<proj>/events/?query=invalid_union | jq '.[] | .eventID'` returns no recent events for this session.
- **Cleanup:** Delete the test vision.md via KB Tree delete action.

## Success Metrics

- **Zero recurrences** of `ZodError: invalid_union` in Sentry with `module: "canUseTool"` or `module: "sandbox-hook"` tags for 7 days post-deploy.
- **100% success rate** for Write/Edit tool calls targeting paths inside `knowledge-base/` during onboarding flows (measured via structured log aggregation).
- **Vision.md enhancement completion rate** (foundation card progress) recovers to baseline (measured against `knowledge-base/product/roadmap.md` phase-1 KPI, if captured).

## Dependencies & Risks

### Dependencies

- **Claude Agent SDK v0.2.80** (`apps/web-platform/node_modules/@anthropic-ai/claude-agent-sdk`). If the root cause is an SDK bug, we need a patched SDK or a workaround. Check the SDK changelog and issue tracker before writing code.
- **Bubblewrap sandbox** (Docker image at `apps/web-platform/Dockerfile`). No changes expected, but verify `CLONE_NEWUSER` is still enabled (see `2026-04-05-investigate-verify-bwrap-sandbox-docker-seccomp-plan.md`).
- **Supabase** for persisting attachment metadata and workspace_path. No schema changes.

### Risks

- **Risk:** Fix addresses the symptom (schema mismatch) but not the underlying SDK bug, and a future SDK upgrade reintroduces it. **Mitigation:** add shape-validation wrapper around `canUseTool` and PreToolUse outputs that logs any mismatch to Sentry. This gives us early warning even if the fix stops working.
- **Risk:** Pre-creating `knowledge-base/overview/` in the provisioner breaks users who clone a repo that **already has** `knowledge-base/overview/` (the directory creation is idempotent via `ensureDir`, but if the clone creates the dir as a **file** or symlink with different permissions, `mkdirSync` may fail). **Mitigation:** wrap in try/catch, log.warn on failure, don't block provisioning.
- **Risk:** Changing the sandbox-hook allow path from `{}` to `{ hookSpecificOutput: {...} }` might change CLI behavior subtly (e.g., suppress a default log line). **Mitigation:** read SDK source for the hook dispatch code before changing; add test cases for both shapes.
- **Risk:** The actual root cause is hypothesis #5 (SDK tool-input validation changed in v0.2.80) and requires an SDK upgrade or downgrade. **Mitigation:** reproduction step includes capturing the full Zod issue path from server logs, which will name the schema that failed. If it's in `sdk-tools.d.ts` (FileWriteInput/FileEditInput), the fix is client-side (update prompt to use correct shape); if it's in `SDKControlResponse` (our hook output), fix is server-side.
- **Risk:** Reproduction requires a fully-provisioned dev workspace and GitHub App installation. **Mitigation:** use an existing dev user or provision one via the existing `provisionWorkspaceWithRepo` test flow.

### Non-goals

- Do **not** change `allowWrite` scope, `denyRead` list, or any bubblewrap config.
- Do **not** change the permission-chain ordering.
- Do **not** implement agent-side PDF text extraction (tracked separately in #2008). This plan assumes the user types or pastes the extracted markdown.
- Do **not** refactor the credential-helper pattern into a shared helper (tracked as a separate cleanup task in `kb-upload-missing-credential-helper-20260413.md`).

## Domain Review

**Domains relevant:** engineering (CTO -- this is the current task's topic, so per AGENTS.md `pdr-do-not-route-on-trivial-messages-yes` no separate CTO consultation spawned)

No other domains flagged:

- **Product:** touches the onboarding foundation card flow but does not create new user-facing pages or flows; tier is **NONE** per the mechanical check (no new files under `components/**/*.tsx` or `app/**/page.tsx`).
- **Legal, Marketing, Finance, Sales, Operations, Support:** not applicable -- internal platform bug with no external or commercial surface.

Infrastructure/tooling change. No cross-domain implications detected.

## References & Research

### Internal References

- `apps/web-platform/server/agent-runner.ts:780-1060` -- SDK query, sandbox, PreToolUse hook, canUseTool callback
- `apps/web-platform/server/sandbox-hook.ts:1-59` -- PreToolUse hook implementation
- `apps/web-platform/server/tool-path-checker.ts:25-98` -- FILE_TOOLS list, extractToolPath, isFileTool, isSafeTool
- `apps/web-platform/server/sandbox.ts:20-126` -- isPathInWorkspace, resolveRealPath, resolveParentRealPath
- `apps/web-platform/server/workspace.ts:25-103` -- provisionWorkspace (current: creates project/ only)
- `apps/web-platform/server/vision-helpers.ts:1-79` -- tryCreateVision, buildVisionEnhancementPrompt
- `apps/web-platform/app/api/kb/upload/route.ts` -- KB Tree upload route (commits to GitHub + pulls to workspace)
- `apps/web-platform/test/sandbox-hook.test.ts:1-60` -- existing PreToolUse hook tests (extend with allow-path shape tests)
- `apps/web-platform/test/agent-runner-tools.test.ts` -- existing canUseTool tests (extend with deny-branch shape tests)
- `apps/web-platform/test/workspace.test.ts` -- existing provisioning tests (extend with overview/ assertion)
- `apps/web-platform/test/vision-creation.test.ts` -- existing tryCreateVision tests (extend with absolute-path assertion for buildVisionEnhancementPrompt)
- `apps/web-platform/node_modules/@anthropic-ai/claude-agent-sdk/sdk.d.ts:1280-1290` -- `PermissionResult` discriminated union
- `apps/web-platform/node_modules/@anthropic-ai/claude-agent-sdk/sdk.d.ts:1378-1381` -- `PreToolUseHookSpecificOutput`
- `apps/web-platform/node_modules/@anthropic-ai/claude-agent-sdk/sdk.d.ts:3785-3794` -- `SyncHookJSONOutput`
- `apps/web-platform/node_modules/@anthropic-ai/claude-agent-sdk/sdk-tools.d.ts:356-401` -- FileEditInput, FileWriteInput

### Related Learnings

- `knowledge-base/project/learnings/integration-issues/kb-upload-missing-credential-helper-20260413.md` -- prior KB upload workspace-sync bug; includes the "Write tool rejected /tmp files" session error which hints at Claude Code's "file must be read first" behavior.
- `knowledge-base/project/learnings/2026-03-20-canuse-tool-sandbox-defense-in-depth.md` -- canUseTool sandbox defense-in-depth architecture (4 layers). This fix preserves all 4 layers.
- `knowledge-base/project/learnings/security-issues/bwrap-sandbox-three-layer-docker-fix-20260405.md` -- Docker seccomp + bubblewrap compatibility. Relevant for the "Read-only file system" Bash symptom interpretation.

### Related Issues / PRs

- #2008 (open) -- "feat: agent-side binary file access for KB uploads" (deferred; related context for why user must provide content in the prompt)
- #2145 (closed) -- git pull credential helper fix
- #891 (closed) -- LS/NotebookRead path validation (same defense-in-depth pattern)
- #725, #875, #876, #878, #894 (closed) -- prior canUseTool / sandbox hardening
- #1285 (open) -- `/sys` denyRead hardening (unrelated, separate fix)
- #1751 (closed) -- Start Fresh onboarding (foundation cards include vision.md)
- #1974 (closed) -- KB file upload V1 (parent of KB Tree)

### External References

- Claude Agent SDK v0.2.80 changelog -- TO READ during reproduction phase. Check for changes to `PermissionResult`, `PreToolUseHookSpecificOutput`, `FileWriteInput`, `FileEditInput`.
- Zod `invalid_union` semantics -- each branch of a `z.union([...])` or `z.discriminatedUnion(...)` is tried in order; `invalid_union` surfaces when none match. Issue path names which branch fails.

## Sharp Edges

- **Reproduction first, fix second.** Do not write any code until the exact Zod issue path is captured from server logs or Sentry. Writing a fix against a hypothesis without confirmation risks addressing the wrong hypothesis.
- **SDK source inspection.** The SDK is minified (`sdk.mjs`); reading it is hard. Prefer the `.d.ts` file and the SDK's source-map or public docs. If the minified file is the only source and the bug is in SDK validation logic, file an upstream bug and pin the SDK version.
- **Avoid touching bubblewrap config.** The "Read-only file system" Bash error is expected behavior. Do not widen `allowWrite` in response to it.
- **Absolute vs relative paths.** `buildVisionEnhancementPrompt` currently emits a relative path in its instruction text. Change to absolute and verify the existing `vision-creation.test.ts` tests still pass (they assert content, not path format; the change should be additive).
- **Test framework.** Use vitest (already in use per `apps/web-platform/vitest.config.ts`). Run with `node node_modules/vitest/vitest.mjs run` from `apps/web-platform/` per AGENTS.md `cq-in-worktrees-run-vitest-via-node-node`. Do not introduce new dependencies.
- **Do not suggest `update-config` as a fix to the user.** The screenshots show the agent offering `update-config` as a workaround -- that skill modifies `.claude/settings.json`, but the SDK sandbox config in `agent-runner.ts` overrides it (`settingSources: []` prevents the SDK from loading settings files per comment at line 791-793). The user's `.claude/settings.json` cannot grant write permissions that the SDK doesn't already enforce via `allowWrite: [workspacePath]`.
- **Schema-validate hook output in tests.** Import the SDK's exported types (`SyncHookJSONOutput`, `PermissionResult`) and assert shape via `z.discriminatedUnion` where possible. If the SDK does not export runtime schemas, hand-write a zod schema that matches the `.d.ts` type and keep it alongside the tests as documentation.
