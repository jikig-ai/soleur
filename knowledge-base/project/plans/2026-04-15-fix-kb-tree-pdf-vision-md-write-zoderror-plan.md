---
title: "fix: KB Tree PDF to vision.md write fails with ZodError invalid_union on Write/Edit"
type: fix
date: 2026-04-15
---

# fix: KB Tree PDF to vision.md write fails with ZodError invalid_union on Write/Edit

## Enhancement Summary

**Deepened on:** 2026-04-15
**Sections enhanced:** Overview, Problem Statement, Proposed Solution, Technical Considerations, Acceptance Criteria, Risks
**Research sources:** Context7 (`/nothflare/claude-agent-sdk-docs`), official docs at `code.claude.com/docs/en/agent-sdk/hooks` and `/permissions`, SDK changelog (`github.com/anthropics/claude-agent-sdk-typescript/blob/main/CHANGELOG.md`), WebSearch for v0.2.80 issues, local SDK `.d.ts` inspection at v0.2.80, 3 relevant learnings cross-checked.

### Key Improvements Over v1

1. **Confirmed the bug is very likely an SDK regression fixed upstream.** SDK changelog shows v0.2.81 fixed a `canUseTool` bug and v0.2.85 fixed "PreToolUse hooks with `permissionDecision: 'ask'` being ignored in SDK mode". Our pinned v0.2.80 sits between these fixes. **Phase 0 is now "upgrade SDK to >= 0.2.85 and re-test"** -- the platform fix may be a one-line package.json bump.
2. **Authoritative hook-output contract documented.** Per official docs: returning `{}` from a PreToolUse hook is **explicitly valid** and allows the operation. `hookEventName` is required **inside** `hookSpecificOutput` when it IS present, but not when the output is `{}`. The existing sandbox-hook allow path is therefore spec-compliant; hypothesis #2 in v1 is rejected.
3. **`PermissionResult` allow-branch contract clarified.** Our installed v0.2.80 `.d.ts` declares `updatedInput?: Record<string, unknown>` (optional). Public docs in 2026 (nothflare mirror) declare `updatedInput: ToolInput` (required, no `?`). This is the **strongest remaining hypothesis** -- if the CLI's runtime Zod schema requires `updatedInput` on allow but our code returns `{ behavior: "allow" }` without it, every file-tool call produces exactly the reported symptom. **Fix:** always return `{ behavior: "allow", updatedInput: toolInput }` (echo the input back).
4. **Additional hypothesis added.** Claude Code's internal "file must be read first" state tracking (GitHub issue #16546) causes Edit failures on files that weren't Read in the current session. Our `agent-runner.ts` session-resume path may lose file-read state between turns. This is orthogonal to the ZodError but produces a similar user experience.
5. **New sharp edge:** `permissionMode: "acceptEdits"` auto-approves Write/Edit inside cwd + `additionalDirectories`, bypassing canUseTool. Tempting quick-fix but weakens defense-in-depth. Documented as a rejected alternative.

### New Considerations Discovered

- **SDK version is a first-class input.** Pin exact version, capture in Sentry tags, upgrade in Phase 0.
- **Deny-rules precede canUseTool.** Adding `disallowedTools: ["WebSearch", "WebFetch"]` (already present) is a stronger fence than relying on canUseTool's deny-by-default.
- **Permission evaluation order** (per docs): hooks → deny rules → permission mode → allow rules → canUseTool. Our plan must respect this when changing any layer.
- **`systemMessage` shows a warning to the user**, `additionalContext` injects into the conversation for the model. Our sandbox-hook uses `systemMessage` on deny correctly; the ZodError leaking to the user suggests the SDK is routing a Zod issue's message through this same channel.

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

0. **SDK upgrade gate (new from deepen-plan research).** Upgrade `@anthropic-ai/claude-agent-sdk` from `0.2.80` to the latest `0.2.x` (>= `0.2.85` per changelog findings). Two upstream fixes in this window are directly relevant: v0.2.81 fixed a `canUseTool` bug around bypass-immune safety checks / `addRules` suggestions; v0.2.85 fixed "PreToolUse hooks with `permissionDecision: 'ask'` being ignored in SDK mode". If the reproduction succeeds post-upgrade without any other change, file a tracking issue referencing the upstream fix and ship the bump alone. If the bug persists, continue to step 1.
1. **Reproduce** the bug against a dev workspace with a provisioned user, upload a PDF via KB Tree, and ask the dashboard agent to update `knowledge-base/overview/vision.md`. Capture the exact Zod issue path from server logs / Sentry.
2. **Classify** which permission-chain step emits the invalid output. Six hypotheses (re-ranked below with deepen-plan evidence) -- the reproduction + SDK debug logs narrow this to one.
3. **Fix** the identified root cause with a minimal diff, preserving all existing defense-in-depth layers.
4. **Defense-in-depth additions** that address the broader class of bugs:
   a. Pre-create `knowledge-base/overview/` in `provisionWorkspace` so the first Write never targets a non-existent ancestor directory.
   b. Change `buildVisionEnhancementPrompt` to emit an **absolute** path (`${workspacePath}/knowledge-base/overview/vision.md`) so the agent never passes a relative `file_path` to Write/Edit.
   c. Wrap the `canUseTool` callback and PreToolUse hook in a shape-validation layer that log.error's any malformed decision (using the SDK's exported zod schemas where available) instead of silently returning it to the CLI.
   d. **Echo `updatedInput` on allow.** Change every `return { behavior: "allow" as const }` in `canUseTool` to `return { behavior: "allow" as const, updatedInput: toolInput }`. Per public docs, `updatedInput` may be required on the allow branch. Echoing the input back is a no-op in behavior but satisfies both the permissive (optional in 0.2.80 .d.ts) and strict (required in 2026 docs) schemas.

### Research Insights (from deepen-plan)

**Permission evaluation order (official docs, `code.claude.com/docs/en/agent-sdk/permissions`):**

1. Hooks run first (allow, deny, or continue).
2. Deny rules (`disallowedTools`, settings.json) -- block even in `bypassPermissions`.
3. Permission mode -- `bypassPermissions` approves, `acceptEdits` approves file ops inside cwd, others fall through.
4. Allow rules (`allowedTools`, settings.json).
5. `canUseTool` callback -- last resort; skipped in `dontAsk` mode.

Our `permissionMode: "default"` (agent-runner.ts:790) and `settingSources: []` (line 794) mean steps 2-4 are minimal and the full brunt of decisions lands on hooks (step 1) and canUseTool (step 5). Both must return shape-valid output.

**Hook output contract (official docs):**

- `{}` is a valid return from PreToolUse hooks to allow the operation. **Hypothesis #2 from v1 (explicit hookEventName required on allow) is rejected.** Confirmed via both nothflare docs and official `code.claude.com` example `protectEnvFiles`.
- `hookEventName` is required **inside** `hookSpecificOutput` when the object is present -- it identifies which hook type the output is for.
- For PreToolUse, `permissionDecision` must be `"allow" | "deny" | "ask"`. Top-level `decision`/`reason` fields are **deprecated for this event** (per WebSearch summary); always use `hookSpecificOutput.permissionDecision` / `permissionDecisionReason`. Our sandbox-hook already does this correctly.
- `updatedInput` must live inside `hookSpecificOutput`, not at the top level. Only applies when also setting `permissionDecision: "allow"`.
- `systemMessage` injects a message visible to the model; `additionalContext` appends to tool result on PostToolUse.

**`PermissionResult` allow-branch ambiguity (root of our hypothesis #3, now #1):**

| Source | allow.updatedInput | allow.updatedPermissions |
|--------|-------------------|---------------------------|
| Local `node_modules/@anthropic-ai/claude-agent-sdk/sdk.d.ts@0.2.80:1280` | `?:` (optional) | `?:` (optional) |
| Context7 `/nothflare/claude-agent-sdk-docs` typescript.md | Required (no `?`) | `?:` (optional) |
| Official docs `code.claude.com/permissions` example | Returned when modifying input, not shown as "required" for plain allow | n/a |

Two possibilities:

- The `.d.ts` is correct and `updatedInput` truly is optional; our `invalid_union` is from another cause.
- The runtime Zod schema in the CLI is stricter than the published `.d.ts` and requires `updatedInput` on allow; the `.d.ts` is lagging. This would fit the symptoms exactly and would be fixed by the Phase 4d mitigation (always echo `updatedInput`).

**Relevant SDK bugs (upstream changelog):**

- v0.2.81: "Fixed `canUseTool` not providing a working `addRules` suggestion when a write under `.claude/skills/{name}/` hits the bypass-immune safety check." Our code does not write under `.claude/skills/` during the vision flow, but this shows the `canUseTool` validation surface was actively broken in v0.2.80.
- v0.2.85: "Fixed PreToolUse hooks with `permissionDecision: 'ask'` being ignored in SDK mode." We never use `"ask"`, but this confirms active churn in PreToolUse decision handling between 0.2.80 and 0.2.85.

**Claude Code file-state tracking (orthogonal symptom, anthropics/claude-code#16546):**

- The Edit tool enforces "file must have been Read in this session before Edit." If the model tries Edit on a file it hasn't Read, the tool returns a specific error (not a ZodError).
- The Write tool enforces a similar check for existing files (learning `kb-upload-missing-credential-helper-20260413.md` line 44 observed: "Write tool rejected /tmp files -- Attempted to use the Write tool on `/tmp/review-finding-*.md` files that hadn't been Read first").
- On SDK session resume, this in-memory state tracking may be lost between turns. If the user's chat spans multiple SDK sessions (resume flow in `sendUserMessage`), the second turn's agent has no record of reading vision.md from the first turn.
- **Not a direct cause of ZodError**, but could produce a user-visible "permission error" that the model then incorrectly labels as a platform bug. Verify during reproduction by checking server logs for the specific error string.

5. **Regression tests:**
   - Unit test: `canUseTool` returns shape-valid `PermissionResult` for Write/Edit targeting an existing file within workspace.
   - Unit test: `canUseTool` returns shape-valid `{ behavior: "deny", message: string }` for Write targeting a path outside the workspace (message is never undefined).
   - Unit test: PreToolUse hook returns shape-valid `SyncHookJSONOutput` for Write targeting `knowledge-base/overview/vision.md` where `overview/` does not yet exist on disk (exercises the `resolveParentRealPath` branch of `isPathInWorkspace`).
   - Unit test: `provisionWorkspace` creates `knowledge-base/overview/` alongside the `project/` subdirectories.
   - Integration test (vitest + mock SDK): sending the prompt "Update vision.md with this content: <markdown>" results in a `Write` tool call whose `file_path` starts with the workspace root and which passes both the hook and canUseTool.

### Root-cause hypotheses (re-ranked after deepen-plan research)

The reproduction will narrow this to one. The ranking below reflects the deepen-plan evidence -- the top hypothesis is now "SDK regression, fixed upstream":

1. **HIGHEST (new top rank): SDK regression in v0.2.80, fixed in v0.2.81 / v0.2.85.** Changelog shows active bug-fix churn in `canUseTool` and `PreToolUse` decision handling in exactly the version window we're pinned to. This is the cheapest hypothesis to test (one-line package.json bump + reproduction re-run). **Expected probability: 40-50%.**

2. **HIGH: `PermissionResult` allow branch missing `updatedInput`.** Our `canUseTool` returns `{ behavior: "allow" as const }` on the file-tool path (agent-runner.ts:881), the Agent path (line 958), safe-tools path (line 966), platform-tool auto-approve (line 1039), and plugin-mcp path (line 1052). Public docs show `updatedInput` as required on allow; our local `.d.ts@0.2.80` shows it as optional. If the runtime Zod schema follows the docs rather than the `.d.ts`, every allow return fails discriminated-union parse. **Fix is trivial: echo `toolInput` back via `updatedInput: toolInput`. This is a no-op behaviorally but satisfies both schemas.** **Expected probability: 25-30%.**

3. **MEDIUM: Path-validation false negative due to missing `knowledge-base/overview/` directory.** `provisionWorkspace` creates `project/` but not `overview/`. `isPathInWorkspace` for `<workspace>/knowledge-base/overview/vision.md` calls `resolveRealPath` → `ENOENT` → `resolveParentRealPath` walks up. Walk should resolve to `<workspace>/knowledge-base/` (exists) and re-append `overview/vision.md`. Containment check should pass. **But** if any intermediate segment is a symlink or if the walk hits EACCES (e.g., bubblewrap mount permissions), the helper returns `null` → isPathInWorkspace returns `false` → canUseTool denies. The user then sees "Access denied: outside workspace" which is NOT a ZodError but could be mislabeled by the agent. **Fix: pre-create `overview/` in provisioner; verify no ELOOP/EACCES paths in the realpath walk.** **Expected probability: 10-15%.**

4. **MEDIUM: Claude Code file-state tracking (Edit requires prior Read).** anthropics/claude-code#16546 documents Edit tool enforcement. If the model hasn't Read vision.md in this SDK session and tries Edit, the tool returns a specific error. On SDK session resume (multi-turn), the read state may be lost. **Not a ZodError** but user-visible permission error the model may mislabel. Mitigation: add `Read` before `Edit` in the dashboard-agent system prompt when it wants to modify existing files; or instruct the model to use `Write` (full replace) for this flow. **Expected probability: 5-10%.**

5. **LOW: Relative `file_path` in `buildVisionEnhancementPrompt`.** SDK `FileWriteInput.file_path: string` accepts relative; CLI resolves against cwd. Not a ZodError cause but worth fixing for clarity. **Fix in Phase 4b regardless.** **Expected probability: <5%.**

6. **LOW: hookSpecificOutput discriminated-union mismatch on allow (`{}` return).** Rejected after deepen-plan research: official docs explicitly state "Return empty object to allow the operation." The v1 hypothesis #2 is wrong. **Expected probability: <5%.** Kept in the list for completeness.

7. **LOW: Programmer error in a canUseTool deny branch (missing `message`).** Scan of current code (agent-runner.ts:858-1060) shows all deny returns include a string `message`. No gap found. **Expected probability: <2%.**

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
