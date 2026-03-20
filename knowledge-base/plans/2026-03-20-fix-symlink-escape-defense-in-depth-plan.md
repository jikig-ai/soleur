---
title: "fix: add fs.realpathSync for symlink escape defense-in-depth"
type: fix
date: 2026-03-20
semver: patch
---

# fix: add fs.realpathSync for symlink escape defense-in-depth

## Enhancement Summary

**Deepened on:** 2026-03-20
**Sections enhanced:** 7
**Research sources used:** CVE-2025-55130, gemini-cli#1121, OpenClaw GHSA-cfvj-7rx7-fc7c, CERT POS35-C, Node.js v25 fs API docs, 2 project learnings, 4 web searches

### Key Improvements
1. Added `resolveRealPath` ancestor-walk algorithm with explicit security invariant documentation
2. Identified workspace path resolution gap -- `workspacePath` itself may contain symlinks and must also be resolved
3. Added `lstatSync` pre-check consideration and documented why `realpathSync` alone is sufficient here
4. Enhanced test scenarios with relative symlink attacks and deeply nested non-existent path cases

### New Considerations Discovered
- The `workspacePath` argument must also be resolved with `realpathSync` to prevent the workspace root itself from being a symlink target
- `resolveParentRealPath` must catch non-ENOENT errors (ELOOP, EACCES) at each ancestor level and return null, not just silently continue walking up
- Relative symlinks (`../../../etc`) behave identically to absolute symlinks for `realpathSync` -- no special handling needed
- `O_NOFOLLOW` only protects the final path component, not intermediate directories -- `realpathSync` (which resolves the entire chain) is the correct tool here

## Overview

`isPathInWorkspace()` in `apps/web-platform/server/sandbox.ts` uses `path.resolve()` to canonicalize paths, which collapses `../` segments but does **not** follow symlinks. If an agent creates a symlink inside the workspace pointing outside it (e.g., `ln -s /etc /workspaces/user1/etc-link`), the resolved path `/workspaces/user1/etc-link/passwd` passes `isPathInWorkspace` because it starts with the workspace prefix. The underlying `fs.readFile` then follows the symlink and reads `/etc/passwd`.

This is the exact vulnerability class described in CVE-2025-55130 (Node.js Permissions Model symlink bypass, CVSS 9.1) and independently reported in google-gemini/gemini-cli#1121.

### Research Insights

**Industry prevalence:** This vulnerability class has been independently discovered and exploited in at least 4 major projects in 2025-2026:
- Node.js Permissions Model (CVE-2025-55130, CVSS 9.1)
- Google Gemini CLI (gemini-cli#1121)
- OpenClaw (GHSA-cfvj-7rx7-fc7c -- stageSandboxMedia symlink traversal)
- Judge0 sandbox (GHSA-h9g2-45c8-89cf)

The root cause is identical in each: path validation operates on the user-provided string, then the file operation follows symlinks to a different physical location. The Node.js fix (applied in v20.20.0, v22.22.0, v24.13.0, v25.3.0) resolves symlinks before permission checks.

## Problem Statement / Motivation

**Current risk: LOW** -- the bubblewrap sandbox (OS-level) restricts filesystem access independently, and agents cannot create symlinks without the Bash tool (which is itself sandboxed). However, defense-in-depth demands that the `canUseTool` callback independently blocks symlink-based escapes, so that if any single layer fails (sandbox misconfiguration, `dangerouslyDisableSandbox` regression, new tool that creates symlinks), the path validation still holds.

The fix closes a gap in layer 2 (canUseTool deny-by-default policy) of the three-tier defense model established in PR #871.

### Research Insights

**Defense-in-depth justification (from project learning):** The existing learning `canuse-tool-sandbox-defense-in-depth.md` documents that defense-in-depth failures are multiplicative, not additive. The pre-approved permissions bypass + `startsWith` bypass combined to produce unrestricted filesystem read access. Similarly, a bubblewrap misconfiguration + missing symlink resolution would produce unrestricted symlink-following reads. Each layer must independently block the attack class it is responsible for.

**Attack surface analysis:** The `canUseTool` callback is the sole enforcement point for layer 2. Per the `cwe22-path-traversal-canusertool-sandbox.md` learning, the SDK evaluates `permissions.allow` before `canUseTool` -- but since PR #873 emptied that array, all file tools now flow through the callback. The symlink gap is the remaining weakness in this layer.

## Proposed Solution

Add `fs.realpathSync()` to `isPathInWorkspace()` to resolve symlinks before the containment check. Handle two cases differently:

1. **Existing files** (Read, Grep, Glob): call `fs.realpathSync(filePath)` -- this resolves the full chain of symlinks to the final physical path and checks that against the workspace boundary.

2. **New files** (Write, Edit): the target file does not exist yet, so `fs.realpathSync(filePath)` would throw `ENOENT`. Instead, walk up the directory tree to find the deepest existing ancestor, resolve it with `fs.realpathSync`, and re-append the non-existent tail segments. This prevents creating a file through a symlinked directory.

### Research Insights

**Why `realpathSync` over `lstatSync` + `O_NOFOLLOW`:**
- `O_NOFOLLOW` (available via `fs.constants.O_NOFOLLOW` on POSIX) only checks the **final** path component. It does not protect against symlinks in intermediate directories. A path like `/workspaces/user1/symlinked-dir/file.md` would pass `O_NOFOLLOW` because the final component `file.md` is not a symlink -- even though `symlinked-dir` is.
- `lstatSync` + `isSymbolicLink()` has the same limitation: it checks one path component at a time. Checking every component of the path manually is equivalent to what `realpathSync` does internally, but with more code and more opportunity for bugs.
- `realpathSync` resolves the entire symlink chain in a single syscall (`realpath(3)`), returning the canonical physical path. This is the correct and simplest tool for the job.
- Per [CERT POS35-C](https://wiki.sei.cmu.edu/confluence/display/c/POS35-C.+Avoid+race+conditions+while+checking+for+the+existence+of+a+symbolic+link): "The most reliable way to avoid symlink race conditions is to use `openat(2)` with `O_NOFOLLOW`." Since Node.js does not expose `openat`, `realpathSync` is the best available alternative in userspace.

**Workspace path resolution:** Both `filePath` AND `workspacePath` must be resolved. If the workspace root itself is mounted via symlink (e.g., in Docker volume mounts or test environments), resolving only `filePath` produces a mismatch. The fix must call `realpathSync` on `workspacePath` too, with a try-catch that falls back to `path.resolve` if the workspace does not exist (defensive coding for test environments).

## Technical Considerations

### TOCTOU (Time-of-Check to Time-of-Use)

There is an inherent race condition: between the `realpathSync` check and the actual file operation, an attacker could swap a legitimate path for a symlink. This is **not practically exploitable** in our architecture because:

1. The attacker would need to execute a Bash command to create the symlink *between* the `canUseTool` check and the SDK's file operation -- but `canUseTool` is called synchronously before the tool executes, and the attacker cannot interleave commands within a single tool invocation.
2. The bubblewrap sandbox (layer 1) independently restricts filesystem access, so even a successful TOCTOU exploit hits the OS-level sandbox.
3. True TOCTOU-immune solutions require `openat(2)` with `O_NOFOLLOW` at the syscall level, which is not available through Node.js `fs` APIs without native addons. This is documented as a known limitation.

### Research Insights

**TOCTOU in practice (from OpenClaw GHSA-cfvj-7rx7-fc7c):** The OpenClaw sandbox escape demonstrated a practical TOCTOU exploit where an attacker keeps a file safe during validation, then rapidly swaps it for a symlink before the file operation executes. Their mitigation involved comparing `fstat` inode/device numbers against `lstat` results after opening the file handle. This approach is more robust but requires access to the file descriptor, which is internal to the SDK's tool execution -- our `canUseTool` callback runs before the SDK opens the file.

**TOCTOU in this codebase (from learning `stop-hook-toctou-race-fix.md`):** The project has prior art for TOCTOU defense-in-depth in bash scripts. The key pattern is: stderr suppression + re-check + output validation + idempotent deletion + write guards. For this TypeScript context, the equivalent layering is: `realpathSync` (primary check) + bubblewrap sandbox (independent enforcement) + deny-on-error (fail-closed).

**Why `canUseTool` timing matters:** The SDK's tool execution model is: `canUseTool` is called, it returns allow/deny, then (if allowed) the SDK executes the tool. Between `canUseTool` returning and the tool executing, only the SDK's internal code runs -- the agent cannot issue another tool call in this window. The TOCTOU window is therefore limited to external processes that happen to modify the filesystem, not to agent-controlled actions. This is a strictly narrower window than typical TOCTOU scenarios.

### Legitimate Symlinks

The workspace provisioning (`workspace.ts`) creates a symlink `plugins/soleur -> /app/shared/plugins/soleur`. This is a legitimate symlink that resolves **outside** the workspace. However, agents should not be reading plugin files through file tools -- they access plugins through the SDK's plugin system. If this becomes an issue, the fix is to add an explicit allowlist for the plugin symlink target path, not to weaken the symlink check.

### Error Handling

`fs.realpathSync()` throws:
- `ENOENT` -- file does not exist (expected for Write/Edit targets; handled by ancestor walk)
- `ELOOP` -- too many levels of symlinks (treat as deny -- potential attack)
- `EACCES` -- permission denied (treat as deny -- cannot verify safety)
- `ENOTDIR` -- a component of the path is not a directory (treat as deny)

All errors from `realpathSync` on existing-file tools (Read/Grep/Glob) should result in denial. The file either does not exist or cannot be verified safe.

### Research Insights

**Fail-closed is critical:** Per [Node.js fs API docs](https://nodejs.org/api/fs.html), `realpathSync` can throw any error that `stat(2)` can throw. The `resolveParentRealPath` function must catch non-ENOENT errors at each ancestor level and return `null` (deny), not silently continue walking up. A symlink loop at an intermediate directory level would throw ELOOP, and continuing to walk up would skip the malicious directory entirely, potentially re-resolving to a workspace-internal ancestor and allowing the attack.

### Performance

`realpathSync` is a synchronous syscall (`realpath(3)`) -- microseconds per call. Called once per file tool invocation, which is already I/O-bound. No measurable impact.

## Acceptance Criteria

- [ ] `isPathInWorkspace` resolves symlinks via `fs.realpathSync` before containment check for existing paths (`sandbox.ts`)
- [ ] `isPathInWorkspace` walks up to deepest existing ancestor for non-existent paths, resolves it, re-appends tail (`sandbox.ts`)
- [ ] `isPathInWorkspace` denies paths where `realpathSync` throws ELOOP, EACCES, or other non-ENOENT errors (`sandbox.ts`)
- [ ] `isPathInWorkspace` also resolves `workspacePath` with `realpathSync` (with `path.resolve` fallback) (`sandbox.ts`)
- [ ] `resolveParentRealPath` returns `null` on non-ENOENT errors at any ancestor level (`sandbox.ts`)
- [ ] Existing 11 tests continue to pass (path traversal, prefix collision, edge cases)
- [ ] New tests cover symlink escape scenarios using real filesystem temp directories (`canusertool-sandbox.test.ts`)
- [ ] TOCTOU limitation documented in code comments with CVE and CERT references

## Test Scenarios

### Symlink Escape (Read path)

- Given a symlink `/workspaces/user1/etc-link -> /etc`, when Read requests `/workspaces/user1/etc-link/passwd`, then `isPathInWorkspace` returns `false` (symlink resolves outside workspace)

### Symlink Escape (Write path -- parent is symlinked)

- Given a symlink `/workspaces/user1/outside -> /tmp`, when Write requests `/workspaces/user1/outside/evil.sh`, then `isPathInWorkspace` returns `false` (parent resolves outside workspace)

### Legitimate Internal Symlink

- Given a symlink `/workspaces/user1/docs -> /workspaces/user1/knowledge-base`, when Read requests `/workspaces/user1/docs/plan.md`, then `isPathInWorkspace` returns `true` (symlink resolves inside workspace)

### Non-existent File (Write to real directory)

- Given no symlinks, when Write requests `/workspaces/user1/new-dir/file.md` (where `new-dir` does not exist), then `isPathInWorkspace` returns `true` (ancestor walk finds workspace root, resolves it, re-appends segments -- all within workspace)

### Chained Symlinks

- Given `/workspaces/user1/a -> /workspaces/user1/b` and `/workspaces/user1/b -> /tmp`, when Read requests `/workspaces/user1/a/file`, then `isPathInWorkspace` returns `false` (chained resolution lands outside workspace)

### ELOOP (Circular Symlink)

- Given `/workspaces/user1/loop1 -> /workspaces/user1/loop2` and `/workspaces/user1/loop2 -> /workspaces/user1/loop1`, when Read requests `/workspaces/user1/loop1/file`, then `isPathInWorkspace` returns `false` (ELOOP error treated as deny)

### Relative Symlink Escape

- Given a symlink `/workspaces/user1/rel-escape -> ../../../etc`, when Read requests `/workspaces/user1/rel-escape/passwd`, then `isPathInWorkspace` returns `false` (relative symlink resolved to absolute by `realpathSync`)

### Deeply Nested Non-existent Path

- Given `/workspaces/user1/a/` exists (real directory), when Write requests `/workspaces/user1/a/b/c/d/e/file.md` (where b/c/d/e do not exist), then `isPathInWorkspace` returns `true` (ancestor walk finds `/workspaces/user1/a/`, resolves it, appends `b/c/d/e/file.md`)

### Existing Tests Unchanged

- Given no symlinks, when Read requests `/workspaces/user1/../user2/secret.md`, then `isPathInWorkspace` returns `false` (path.resolve still collapses `../` before realpathSync)

## Non-goals

- **Eliminating TOCTOU entirely**: requires `openat(2)` with `O_NOFOLLOW` at the syscall level, which Node.js `fs` APIs do not expose. Per [CERT POS35-C](https://wiki.sei.cmu.edu/confluence/display/c/POS35-C.+Avoid+race+conditions+while+checking+for+the+existence+of+a+symbolic+link), the definitive fix requires file descriptor-based operations. Documented as known limitation.
- **Blocking symlink creation via Bash**: tracked separately in #875 (Bash tool escape). The bubblewrap sandbox is the primary control for Bash commands.
- **Plugin symlink allowlisting**: only needed if agents legitimately need to read plugin files through Read/Glob/Grep tools. Not currently required.
- **`lstatSync` pre-check**: adds complexity without security benefit. `realpathSync` already resolves all symlinks in the chain. Adding `lstatSync` would only duplicate work -- it would need to check every path component to be effective, which is what `realpathSync` does internally.

## MVP

### `apps/web-platform/server/sandbox.ts`

```typescript
import fs from "fs";
import path from "path";

/**
 * Resolves a file path to its canonical form, following symlinks.
 *
 * For existing paths, uses fs.realpathSync to resolve the full symlink chain.
 * For non-existent paths (Write/Edit targets), walks up the directory tree
 * to find the deepest existing ancestor, resolves it with realpathSync,
 * and re-appends the non-existent tail segments.
 *
 * Returns null if the path cannot be safely resolved (ELOOP, EACCES, etc.).
 *
 * TOCTOU note: a race exists between this check and the file operation.
 * Mitigated by bubblewrap sandbox (layer 1) and the fact that the attacker
 * cannot interleave commands within a single tool invocation.
 *
 * @see https://cwe.mitre.org/data/definitions/59.html (CWE-59: Improper Link Resolution)
 * @see CVE-2025-55130 (Node.js Permissions Model symlink bypass)
 */
function resolveRealPath(filePath: string): string | null {
  const resolved = path.resolve(filePath);
  try {
    return fs.realpathSync(resolved);
  } catch (err: unknown) {
    const code = (err as NodeJS.ErrnoException).code;
    if (code === "ENOENT") {
      // File does not exist -- resolve deepest existing ancestor
      return resolveParentRealPath(resolved);
    }
    // ELOOP (circular symlinks), EACCES (permission denied),
    // ENOTDIR (component not a directory), etc.
    // Cannot verify safety -- deny
    return null;
  }
}

/**
 * Walks up the directory tree until finding an existing ancestor,
 * resolves it with realpathSync, then re-appends the non-existent tail.
 *
 * Returns null if any ancestor throws a non-ENOENT error (ELOOP, EACCES)
 * -- this prevents skipping a malicious symlink by walking past it.
 */
function resolveParentRealPath(filePath: string): string | null {
  let current = filePath;
  const segments: string[] = [];

  while (current !== path.dirname(current)) {
    segments.push(path.basename(current));
    current = path.dirname(current);
    try {
      const realParent = fs.realpathSync(current);
      // Re-append collected segments to the resolved parent
      return path.join(realParent, ...segments.reverse());
    } catch (err: unknown) {
      const code = (err as NodeJS.ErrnoException).code;
      if (code !== "ENOENT") {
        // Non-ENOENT error (ELOOP, EACCES) at an intermediate directory.
        // Cannot verify safety -- deny rather than walk past it.
        return null;
      }
      // ENOENT -- this ancestor doesn't exist either, keep walking up
    }
  }

  // Reached filesystem root without finding existing ancestor
  return path.join(current, ...segments.reverse());
}

/**
 * Resolves a workspace path to its canonical form.
 * Falls back to path.resolve() if the workspace path does not exist
 * (e.g., in test environments with mock paths).
 */
function resolveWorkspacePath(workspacePath: string): string {
  try {
    return fs.realpathSync(path.resolve(workspacePath));
  } catch {
    return path.resolve(workspacePath);
  }
}

/**
 * Checks whether a file path resolves to a location within the workspace.
 *
 * Canonicalizes both paths -- resolving symlinks via fs.realpathSync --
 * then checks containment with a trailing `/` guard to prevent prefix
 * collisions (e.g., /workspaces/user1 must not match /workspaces/user10).
 *
 * @see https://cwe.mitre.org/data/definitions/22.html (CWE-22)
 * @see https://cwe.mitre.org/data/definitions/59.html (CWE-59)
 */
export function isPathInWorkspace(
  filePath: string,
  workspacePath: string,
): boolean {
  if (!filePath) return false;

  const realPath = resolveRealPath(filePath);
  if (realPath === null) return false;

  const resolvedWorkspace = resolveWorkspacePath(workspacePath);
  return (
    realPath === resolvedWorkspace ||
    realPath.startsWith(resolvedWorkspace + "/")
  );
}
```

### `apps/web-platform/test/canusertool-sandbox.test.ts` (additions)

```typescript
import fs from "fs";
import os from "os";
import path from "path";

// New describe block for symlink tests (requires real filesystem)
describe("isPathInWorkspace symlink defense", () => {
  let tmpWorkspace: string;

  beforeEach(() => {
    tmpWorkspace = fs.mkdtempSync(path.join(os.tmpdir(), "sandbox-test-"));
    fs.mkdirSync(path.join(tmpWorkspace, "subdir"), { recursive: true });
  });

  afterEach(() => {
    fs.rmSync(tmpWorkspace, { recursive: true, force: true });
  });

  test("denies symlink pointing outside workspace", () => {
    const linkPath = path.join(tmpWorkspace, "escape-link");
    fs.symlinkSync("/etc", linkPath);
    expect(
      isPathInWorkspace(path.join(linkPath, "passwd"), tmpWorkspace),
    ).toBe(false);
  });

  test("denies relative symlink pointing outside workspace", () => {
    const linkPath = path.join(tmpWorkspace, "rel-escape");
    fs.symlinkSync("../../../etc", linkPath);
    expect(
      isPathInWorkspace(path.join(linkPath, "passwd"), tmpWorkspace),
    ).toBe(false);
  });

  test("allows symlink pointing inside workspace", () => {
    const target = path.join(tmpWorkspace, "subdir");
    const linkPath = path.join(tmpWorkspace, "internal-link");
    fs.symlinkSync(target, linkPath);
    fs.writeFileSync(path.join(target, "file.md"), "test");
    expect(
      isPathInWorkspace(path.join(linkPath, "file.md"), tmpWorkspace),
    ).toBe(true);
  });

  test("denies write through symlinked parent directory", () => {
    const linkPath = path.join(tmpWorkspace, "outside");
    fs.symlinkSync("/tmp", linkPath);
    expect(
      isPathInWorkspace(path.join(linkPath, "evil.sh"), tmpWorkspace),
    ).toBe(false);
  });

  test("denies circular symlinks (ELOOP)", () => {
    const link1 = path.join(tmpWorkspace, "loop1");
    const link2 = path.join(tmpWorkspace, "loop2");
    fs.symlinkSync(link2, link1);
    fs.symlinkSync(link1, link2);
    expect(
      isPathInWorkspace(path.join(link1, "file"), tmpWorkspace),
    ).toBe(false);
  });

  test("denies chained symlinks escaping workspace", () => {
    const link1 = path.join(tmpWorkspace, "chain-a");
    const link2 = path.join(tmpWorkspace, "chain-b");
    fs.symlinkSync(link2, link1);
    fs.symlinkSync("/tmp", link2);
    expect(
      isPathInWorkspace(path.join(link1, "file"), tmpWorkspace),
    ).toBe(false);
  });

  test("handles non-existent file in real directory", () => {
    expect(
      isPathInWorkspace(
        path.join(tmpWorkspace, "subdir", "nonexistent.md"),
        tmpWorkspace,
      ),
    ).toBe(true);
  });

  test("handles deeply nested non-existent path", () => {
    expect(
      isPathInWorkspace(
        path.join(tmpWorkspace, "subdir", "a", "b", "c", "file.md"),
        tmpWorkspace,
      ),
    ).toBe(true);
  });
});
```

## Dependencies & Risks

**Dependencies:**
- `fs.realpathSync` (Node.js built-in, no new dependencies)
- Existing test infrastructure (vitest)

**Risks:**
- **Plugin symlink breakage**: The `plugins/soleur` symlink resolves outside the workspace. If any agent tries to Read/Glob/Grep plugin files through file tools, those requests will be denied. Mitigated by the fact that agents access plugins through the SDK plugin system, not file tools. Monitor for agent errors that indicate plugin file access attempts.
- **Performance in high-concurrency**: `realpathSync` is synchronous and hits the filesystem. At current scale (single-tenant per workspace), this is negligible. If scaling to hundreds of concurrent tool invocations per workspace, consider `fs.promises.realpath` with caching.
- **Docker volume symlinks**: If the workspace root (`/workspaces`) is itself a symlink (common in Docker volume mounts), `resolveWorkspacePath` handles this by also resolving the workspace path. If it does not exist (test environments with mock paths), falls back to `path.resolve`.

### Research Insights

**Backward compatibility:** The existing 11 tests in `canusertool-sandbox.test.ts` use hard-coded string paths (`/workspaces/user1/...`) that do not exist on the filesystem. These tests exercise `path.resolve()` behavior. With the `resolveRealPath` change, these paths will hit `ENOENT`, triggering the ancestor walk, which will walk all the way to `/` (root exists), resolve it (root is already canonical), and re-append the full path. The final path will be identical to what `path.resolve` produces. Therefore, existing tests should pass without modification. However, if the test environment has unusual symlinks at the root level, tests could behave unexpectedly -- verify by running the existing test suite before adding new tests.

## References & Research

- [CVE-2025-55130 (NVD)](https://nvd.nist.gov/vuln/detail/CVE-2025-55130) -- Node.js Permissions Model symlink bypass, CVSS 9.1
- [CVE-2025-55130 JFrog analysis](https://research.jfrog.com/vulnerabilities/nodejs-fs-permissions-bypass-cve-2025-55130/) -- detailed exploit chain
- [gemini-cli#1121](https://github.com/google-gemini/gemini-cli/issues/1121) -- identical vulnerability in Google's Gemini CLI
- [OpenClaw GHSA-cfvj-7rx7-fc7c](https://github.com/openclaw/openclaw/security/advisories/GHSA-cfvj-7rx7-fc7c) -- stageSandboxMedia symlink traversal
- [Snyk: OpenClaw sandbox bypass](https://labs.snyk.io/resources/bypass-openclaw-security-sandbox/) -- TOCTOU race condition in sandbox path validation
- [CERT POS35-C](https://wiki.sei.cmu.edu/confluence/display/c/POS35-C.+Avoid+race+conditions+while+checking+for+the+existence+of+a+symbolic+link) -- Avoid race conditions while checking for symlinks
- [Claude Agent SDK secure deployment](https://platform.claude.com/docs/en/agent-sdk/secure-deployment) -- SDK sandbox architecture
- [Node.js v25 fs API docs](https://nodejs.org/api/fs.html) -- `realpathSync` error codes
- [LWN: The trouble with symbolic links](https://lwn.net/Articles/899543/) -- Linux kernel symlink security history
- Related: #725 (path traversal fix, merged in PR #873)
- Related: #871 (Bash tool sandbox, merged)
- Related: #875 (Bash escape tracking)
- Existing learning: `knowledge-base/learnings/2026-03-20-cwe22-path-traversal-canusertool-sandbox.md`
- Existing learning: `knowledge-base/learnings/2026-03-20-canuse-tool-sandbox-defense-in-depth.md`
- Existing learning: `knowledge-base/learnings/2026-03-18-stop-hook-toctou-race-fix.md`
