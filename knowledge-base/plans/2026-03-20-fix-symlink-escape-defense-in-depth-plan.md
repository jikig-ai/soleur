---
title: "fix: add fs.realpathSync for symlink escape defense-in-depth"
type: fix
date: 2026-03-20
semver: patch
---

# fix: add fs.realpathSync for symlink escape defense-in-depth

## Overview

`isPathInWorkspace()` in `apps/web-platform/server/sandbox.ts` uses `path.resolve()` to canonicalize paths, which collapses `../` segments but does **not** follow symlinks. If an agent creates a symlink inside the workspace pointing outside it (e.g., `ln -s /etc /workspaces/user1/etc-link`), the resolved path `/workspaces/user1/etc-link/passwd` passes `isPathInWorkspace` because it starts with the workspace prefix. The underlying `fs.readFile` then follows the symlink and reads `/etc/passwd`.

This is the exact vulnerability class described in CVE-2025-55130 (Node.js Permissions Model symlink bypass, CVSS 9.1) and independently reported in google-gemini/gemini-cli#1121.

## Problem Statement / Motivation

**Current risk: LOW** -- the bubblewrap sandbox (OS-level) restricts filesystem access independently, and agents cannot create symlinks without the Bash tool (which is itself sandboxed). However, defense-in-depth demands that the `canUseTool` callback independently blocks symlink-based escapes, so that if any single layer fails (sandbox misconfiguration, `dangerouslyDisableSandbox` regression, new tool that creates symlinks), the path validation still holds.

The fix closes a gap in layer 2 (canUseTool deny-by-default policy) of the three-tier defense model established in PR #871.

## Proposed Solution

Add `fs.realpathSync()` to `isPathInWorkspace()` to resolve symlinks before the containment check. Handle two cases differently:

1. **Existing files** (Read, Grep, Glob): call `fs.realpathSync(filePath)` -- this resolves the full chain of symlinks to the final physical path and checks that against the workspace boundary.

2. **New files** (Write, Edit): the target file does not exist yet, so `fs.realpathSync(filePath)` would throw `ENOENT`. Instead, resolve the **parent directory** with `fs.realpathSync(path.dirname(filePath))` and verify the parent is inside the workspace. This prevents creating a file through a symlinked directory.

## Technical Considerations

### TOCTOU (Time-of-Check to Time-of-Use)

There is an inherent race condition: between the `realpathSync` check and the actual file operation, an attacker could swap a legitimate path for a symlink. This is **not practically exploitable** in our architecture because:

1. The attacker would need to execute a Bash command to create the symlink *between* the `canUseTool` check and the SDK's file operation -- but `canUseTool` is called synchronously before the tool executes, and the attacker cannot interleave commands within a single tool invocation.
2. The bubblewrap sandbox (layer 1) independently restricts filesystem access, so even a successful TOCTOU exploit hits the OS-level sandbox.
3. True TOCTOU-immune solutions require `openat(2)` with `O_NOFOLLOW` at the syscall level, which is not available through Node.js `fs` APIs without native addons. This is documented as a known limitation.

### Legitimate Symlinks

The workspace provisioning (`workspace.ts`) creates a symlink `plugins/soleur -> /app/shared/plugins/soleur`. This is a legitimate symlink that resolves **outside** the workspace. However, agents should not be reading plugin files through file tools -- they access plugins through the SDK's plugin system. If this becomes an issue, the fix is to add an explicit allowlist for the plugin symlink target path, not to weaken the symlink check.

### Error Handling

`fs.realpathSync()` throws:
- `ENOENT` -- file does not exist (expected for Write/Edit targets; handled by parent directory check)
- `ELOOP` -- too many levels of symlinks (treat as deny -- potential attack)
- `EACCES` -- permission denied (treat as deny -- cannot verify safety)

All errors from `realpathSync` on existing-file tools (Read/Grep/Glob) should result in denial. The file either does not exist or cannot be verified safe.

### Performance

`realpathSync` is a synchronous syscall (`realpath(3)`) -- microseconds per call. Called once per file tool invocation, which is already I/O-bound. No measurable impact.

## Acceptance Criteria

- [ ] `isPathInWorkspace` resolves symlinks before containment check for existing paths (`sandbox.ts`)
- [ ] `isPathInWorkspace` resolves parent directory symlinks for non-existent paths (Write/Edit case) (`sandbox.ts`)
- [ ] `isPathInWorkspace` denies paths where `realpathSync` throws (ELOOP, EACCES) (`sandbox.ts`)
- [ ] `canUseTool` in `agent-runner.ts` passes a flag or uses a variant to distinguish read vs write tool context
- [ ] Existing tests continue to pass (path traversal, prefix collision, edge cases)
- [ ] New tests cover symlink escape scenarios (`canusertool-sandbox.test.ts`)
- [ ] TOCTOU limitation documented in code comments

## Test Scenarios

### Symlink Escape (Read path)

- Given a symlink `/workspaces/user1/etc-link -> /etc`, when Read requests `/workspaces/user1/etc-link/passwd`, then `isPathInWorkspace` returns `false` (symlink resolves outside workspace)

### Symlink Escape (Write path -- parent is symlinked)

- Given a symlink `/workspaces/user1/outside -> /tmp`, when Write requests `/workspaces/user1/outside/evil.sh`, then `isPathInWorkspace` returns `false` (parent resolves outside workspace)

### Legitimate Internal Symlink

- Given a symlink `/workspaces/user1/docs -> /workspaces/user1/knowledge-base`, when Read requests `/workspaces/user1/docs/plan.md`, then `isPathInWorkspace` returns `true` (symlink resolves inside workspace)

### Non-existent File (Write to real directory)

- Given no symlinks, when Write requests `/workspaces/user1/new-dir/file.md` (where `new-dir` does not exist), then `isPathInWorkspace` falls back to `path.resolve()` check (no symlink resolution needed; parent does not exist so `realpathSync` on parent throws ENOENT; fall back to pure path resolution)

### Chained Symlinks

- Given `/workspaces/user1/a -> /workspaces/user1/b` and `/workspaces/user1/b -> /tmp`, when Read requests `/workspaces/user1/a/file`, then `isPathInWorkspace` returns `false` (chained resolution lands outside workspace)

### ELOOP (Circular Symlink)

- Given `/workspaces/user1/loop1 -> /workspaces/user1/loop2` and `/workspaces/user1/loop2 -> /workspaces/user1/loop1`, when Read requests `/workspaces/user1/loop1/file`, then `isPathInWorkspace` returns `false` (ELOOP error treated as deny)

### Existing Tests Unchanged

- Given no symlinks, when Read requests `/workspaces/user1/../user2/secret.md`, then `isPathInWorkspace` returns `false` (path.resolve still collapses `../` before realpathSync)

## Non-goals

- **Eliminating TOCTOU entirely**: requires `openat(2)` with `O_NOFOLLOW` at the syscall level, which Node.js `fs` APIs do not expose. Documented as known limitation.
- **Blocking symlink creation via Bash**: tracked separately in #875 (Bash tool escape). The bubblewrap sandbox is the primary control for Bash commands.
- **Plugin symlink allowlisting**: only needed if agents legitimately need to read plugin files through Read/Glob/Grep tools. Not currently required.

## MVP

### `apps/web-platform/server/sandbox.ts`

```typescript
import fs from "fs";
import path from "path";

/**
 * Resolves a file path to its canonical form, following symlinks.
 *
 * For existing paths, uses fs.realpathSync to resolve the full symlink chain.
 * For non-existent paths (Write/Edit targets), resolves the deepest existing
 * ancestor directory and appends the remaining segments.
 *
 * Returns null if the path cannot be safely resolved (ELOOP, EACCES, etc.).
 *
 * TOCTOU note: a race exists between this check and the file operation.
 * Mitigated by bubblewrap sandbox (layer 1) and the fact that the attacker
 * cannot interleave commands within a single tool invocation.
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
    // ELOOP (circular symlinks), EACCES (permission denied), etc.
    // Cannot verify safety -- deny
    return null;
  }
}

/**
 * Walks up the directory tree until finding an existing ancestor,
 * resolves it with realpathSync, then re-appends the non-existent tail.
 */
function resolveParentRealPath(filePath: string): string | null {
  let current = filePath;
  const segments: string[] = [];

  while (current !== path.dirname(current)) {
    try {
      const realParent = fs.realpathSync(current);
      // Re-append collected segments to the resolved parent
      return path.join(realParent, ...segments.reverse());
    } catch {
      segments.push(path.basename(current));
      current = path.dirname(current);
    }
  }

  // Reached filesystem root without finding existing ancestor
  return path.join(current, ...segments.reverse());
}

export function isPathInWorkspace(
  filePath: string,
  workspacePath: string,
): boolean {
  if (!filePath) return false;

  const realPath = resolveRealPath(filePath);
  if (realPath === null) return false;

  const resolvedWorkspace = path.resolve(workspacePath);
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
    expect(isPathInWorkspace(path.join(linkPath, "passwd"), tmpWorkspace)).toBe(false);
  });

  test("allows symlink pointing inside workspace", () => {
    const target = path.join(tmpWorkspace, "subdir");
    const linkPath = path.join(tmpWorkspace, "internal-link");
    fs.symlinkSync(target, linkPath);
    // Create a file so realpathSync succeeds
    fs.writeFileSync(path.join(target, "file.md"), "test");
    expect(isPathInWorkspace(path.join(linkPath, "file.md"), tmpWorkspace)).toBe(true);
  });

  test("denies write through symlinked parent directory", () => {
    const linkPath = path.join(tmpWorkspace, "outside");
    fs.symlinkSync("/tmp", linkPath);
    // Non-existent file through symlinked parent
    expect(isPathInWorkspace(path.join(linkPath, "evil.sh"), tmpWorkspace)).toBe(false);
  });

  test("denies circular symlinks (ELOOP)", () => {
    const link1 = path.join(tmpWorkspace, "loop1");
    const link2 = path.join(tmpWorkspace, "loop2");
    fs.symlinkSync(link2, link1);
    fs.symlinkSync(link1, link2);
    expect(isPathInWorkspace(path.join(link1, "file"), tmpWorkspace)).toBe(false);
  });

  test("handles non-existent file in real directory", () => {
    // No symlinks, file just does not exist
    expect(isPathInWorkspace(
      path.join(tmpWorkspace, "subdir", "nonexistent.md"),
      tmpWorkspace,
    )).toBe(true);
  });
});
```

## Dependencies & Risks

**Dependencies:**
- `fs.realpathSync` (Node.js built-in, no new dependencies)
- Existing test infrastructure (vitest)

**Risks:**
- **Plugin symlink breakage**: The `plugins/soleur` symlink resolves outside the workspace. If any agent tries to Read/Glob/Grep plugin files through file tools, those requests will be denied. Mitigated by the fact that agents access plugins through the SDK plugin system, not file tools.
- **Performance in high-concurrency**: `realpathSync` is synchronous and hits the filesystem. At current scale (single-tenant per workspace), this is negligible. If scaling to hundreds of concurrent tool invocations per workspace, consider `fs.promises.realpath` with caching.

## References & Research

- [CVE-2025-55130 (NVD)](https://nvd.nist.gov/vuln/detail/CVE-2025-55130) -- Node.js Permissions Model symlink bypass, CVSS 9.1
- [CVE-2025-55130 JFrog analysis](https://research.jfrog.com/vulnerabilities/nodejs-fs-permissions-bypass-cve-2025-55130/) -- detailed exploit chain
- [gemini-cli#1121](https://github.com/google-gemini/gemini-cli/issues/1121) -- identical vulnerability in Google's Gemini CLI
- [Snyk: OpenClaw sandbox bypass](https://labs.snyk.io/resources/bypass-openclaw-security-sandbox/) -- TOCTOU race condition in sandbox path validation
- [Claude Agent SDK secure deployment](https://platform.claude.com/docs/en/agent-sdk/secure-deployment) -- SDK sandbox architecture
- Related: #725 (path traversal fix, merged in PR #873)
- Related: #871 (Bash tool sandbox, merged)
- Related: #875 (Bash escape tracking)
- Existing learning: `knowledge-base/learnings/2026-03-20-cwe22-path-traversal-canusertool-sandbox.md`
- Existing learning: `knowledge-base/learnings/2026-03-20-canuse-tool-sandbox-defense-in-depth.md`
