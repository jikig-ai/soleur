# Learning: CWE-22 path traversal in canUseTool workspace sandbox

## Problem

The `canUseTool` workspace sandbox in `agent-runner.ts` used `path.startsWith(workspaceRoot)` to check whether a file path fell inside the workspace. This check is trivially bypassed with `../` segments: `path.startsWith("/workspace/project")` returns `true` for `/workspace/project/../../../etc/passwd` because `startsWith` operates on the raw string, not the resolved filesystem path. This is textbook CWE-22 (Improper Limitation of a Pathname to a Restricted Directory).

However, the more severe issue was hiding in plain sight: `workspace.ts` DEFAULT_SETTINGS pre-approved Read, Glob, and Grep tools unconditionally. These tools never reached `canUseTool` at all — they were permitted by the settings layer before the sandbox check ran. An attacker with workspace access could read any file on the server filesystem via these tools without triggering any path validation.

The combination meant:
1. Read/Glob/Grep bypassed `canUseTool` entirely (pre-approved in settings.json)
2. Even if they reached `canUseTool`, the `startsWith` check was bypassable with path traversal

## Solution

1. **Extracted `isPathInWorkspace()`** into a dedicated `server/sandbox.ts` module. The function calls `path.resolve()` to canonicalize the path (collapsing `../`, resolving symlinks at the string level), then checks `resolved.startsWith(normalizedRoot + path.sep)` with a trailing separator guard to prevent prefix collisions (e.g., `/workspace/project-evil` matching `/workspace/project`). Also handles empty-string input as an explicit rejection.

2. **Removed pre-approved permissions** from `workspace.ts` DEFAULT_SETTINGS. Read, Glob, and Grep now flow through `canUseTool` like every other tool, where they hit the `isPathInWorkspace` check.

3. **Added runtime migration** `patchWorkspacePermissions()` in `agent-runner.ts`. Changing DEFAULT_SETTINGS only affects new workspaces — existing `settings.json` files on disk still contain the pre-approved entries. The migration runs at workspace load time, detects legacy pre-approved tools, removes them, and writes the updated settings back.

4. **Added an empty-string guard** to `isPathInWorkspace`. `path.resolve("")` returns the current working directory, which could be inside the workspace by coincidence — an empty path argument should always be rejected.

## Key Insight

Defense-in-depth failures are multiplicative, not additive. The `startsWith` bypass alone was exploitable but required crafting a path with `../` segments. The pre-approved permissions alone meant Read/Glob/Grep skipped all path checks. Combined, the result was unrestricted filesystem read access with zero path manipulation required — just use any pre-approved tool with an absolute path outside the workspace.

When auditing access control, trace the full call chain from the entry point (user request) to the enforcement point (sandbox check). If any layer short-circuits the chain (pre-approved permissions, cached decisions, allow-listed tool names), the downstream check is irrelevant. The `startsWith` fix alone would have been a false sense of security because the pre-approved tools never reached it.

Extracting security-critical logic into pure, dependency-free modules (following the `error-sanitizer.ts` pattern from the CWE-209 fix) makes it unit-testable without mocking heavy dependencies like Anthropic SDK, Supabase, or WebSocket connections. `sandbox.ts` imports only `node:path` — tests run in milliseconds with zero setup.

For path containment checks specifically: never use string prefix matching (`startsWith`, `indexOf`, regex anchors). Always canonicalize first with `path.resolve()`, and always append a path separator before the `startsWith` comparison to prevent `/workspace/project-evil` matching `/workspace/project`.

## Session Errors

1. **`npx vitest` pulled stale global cache**: Running `npx vitest run` invoked a cached global vitest binary instead of the project-local version, causing version mismatches and cryptic failures. Fix: use `./node_modules/.bin/vitest run` or `npx --no vitest run` to force local resolution. This is a recurring footgun in monorepos with multiple vitest versions.

2. **Test imported agent-runner.ts, pulling heavy dependencies**: The initial test file imported `isPathInWorkspace` from `agent-runner.ts`, which transitively imported Anthropic SDK, Supabase client, and WebSocket libraries — all of which failed to initialize in a test context. Fix: extract `isPathInWorkspace` into the standalone `sandbox.ts` module with zero heavy dependencies. This is the same pattern used for `error-sanitizer.ts` (CWE-209 fix) and should be the default approach for any security-critical function.

3. **GitHub label `priority/p2-high` doesn't exist**: The issue creation command used a label that hadn't been created in the repository. Fix: run `gh label list` to verify available labels before referencing them. Assumption-based label usage wastes a round-trip and forces error recovery.

4. **Wrong path for setup-ralph-loop.sh script**: A script path referenced in the session was incorrect, causing a command failure. Fix: always verify paths with `ls` or `stat` before executing scripts, especially when paths are recalled from memory rather than read from the filesystem.

## Tags
category: security-issues
module: web-platform/server
