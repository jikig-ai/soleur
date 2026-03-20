---
title: "fix: restrict env vars passed to agent subprocess"
type: fix
date: 2026-03-20
---

## Enhancement Summary

**Deepened on:** 2026-03-20
**Sections enhanced:** 5
**Research sources:** Claude Code env-vars documentation, CWE-526 mitigations, Node.js child_process docs, Agent SDK GitHub issues, project learnings

### Key Improvements

1. Expanded allowlist with `DISABLE_AUTOUPDATER=1` and `DISABLE_TELEMETRY=1` hardcoded overrides to prevent the subprocess from phoning home or auto-updating
2. Added `HTTP_PROXY`/`HTTPS_PROXY`/`NO_PROXY` to the allowlist for corporate environments where the agent subprocess needs proxy config to reach the Anthropic API
3. Added exhaustive deny-list verification test that iterates all known server secrets rather than spot-checking two
4. Identified `canUseTool` gap (Bash tool not gated) as a follow-up hardening item to file as a separate issue

### New Considerations Discovered

- The Agent SDK `options.env` replaces `process.env` entirely for the subprocess (Node.js `child_process.spawn` semantics) -- omitting a var is equivalent to blocking it, no explicit deny logic needed
- `CLAUDECODE=1` is set by Claude Code in shells it spawns; if the server itself runs inside a Claude Code session (dev mode), passing it through causes "cannot launch inside another session" errors (anthropics/claude-agent-sdk-python#573); the allowlist approach naturally excludes it
- The `options.env` field in the SDK does NOT override `env` entries in `~/.claude/settings.json` (anthropics/claude-agent-sdk-typescript#217) -- this means the allowlist is defense-in-depth at the OS process level, but settings.json could inject vars at the CLI level; this is acceptable because settings.json is not attacker-controlled

---

# fix: restrict env vars passed to agent subprocess

Closes #723

## Overview

`apps/web-platform/server/agent-runner.ts` line 158 spreads the entire server `process.env` into the Claude Agent SDK subprocess:

```typescript
env: { ...process.env, ANTHROPIC_API_KEY: apiKey },
```

This passes `SUPABASE_SERVICE_ROLE_KEY`, `BYOK_ENCRYPTION_KEY`, `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, and all other server-side secrets into an LLM-driven agent subprocess that has access to the Bash tool. A prompt injection in any user message could instruct the agent to `echo $SUPABASE_SERVICE_ROLE_KEY` and exfiltrate every secret the server holds.

## Problem Statement / Motivation

**Severity:** CRITICAL -- labeled `priority/p0-critical` on the issue.

**Exploitability:** High. The agent subprocess runs with `permissionMode: "default"`, which means Bash tool calls require user approval -- but the `canUseTool` callback does not gate Bash. An attacker who controls the user message can instruct the agent to read environment variables via Bash, `printenv`, or `/proc/self/environ`. Even if `canUseTool` were extended to block Bash, the correct defense-in-depth posture is to never expose secrets to the subprocess in the first place.

**Blast radius:**
- `SUPABASE_SERVICE_ROLE_KEY` -- full database access, bypasses RLS
- `BYOK_ENCRYPTION_KEY` -- ability to decrypt every user's stored API keys
- `STRIPE_SECRET_KEY` -- ability to issue refunds, read customer data
- `STRIPE_WEBHOOK_SECRET` -- ability to forge webhook events
- Any other env var present in the Docker container at runtime

**Pre-existing since:** MVP commit `5b8e242`.

### Research Insights

**CWE Classification:**
- Primary: [CWE-526](https://cwe.mitre.org/data/definitions/526.html) -- Cleartext Storage of Sensitive Information in an Environment Variable
- Related: CWE-209 (already mitigated via `error-sanitizer.ts`)

**OWASP Mapping:** A05:2021 Security Misconfiguration. The process.env spread is a textbook example of overly permissive default configuration.

**Attack vectors beyond `echo`:**
- `/proc/self/environ` -- readable by the process owner, no Bash tool needed if the agent has file Read access (gated by `canUseTool` to workspace, but defense-in-depth demands the vars not exist at all)
- `env` / `printenv` / `set` -- Bash builtins that list all environment variables
- Node.js `process.env` -- if the subprocess runs Node.js code via MCP tools

## Proposed Solution

Replace the `...process.env` spread with a minimal allowlist of environment variables that the agent subprocess actually needs to function.

### Allowlist

The Claude Agent SDK spawns `claude` CLI as a subprocess. The [Claude Code environment variables documentation](https://code.claude.com/docs/en/env-vars) lists 80+ configuration variables. The subprocess needs only a small subset:

| Variable | Category | Purpose |
|----------|----------|---------|
| `ANTHROPIC_API_KEY` | Required | Set explicitly from BYOK decryption (not forwarded from process.env) |
| `HOME` | OS | Claude CLI writes config/cache to `$HOME`; also needed by `git` |
| `PATH` | OS | Subprocess must find `claude`, `git`, and other binaries |
| `NODE_ENV` | Runtime | Node.js libraries use this for conditional behavior |
| `LANG` | Locale | Proper Unicode handling in CLI output |
| `LC_ALL` | Locale | Overrides all locale categories |
| `TERM` | Shell | Terminal capability detection |
| `USER` | OS | Process identity for git commits and file ownership |
| `SHELL` | OS | Default shell for Bash tool |
| `TMPDIR` | OS | Temporary file operations; Claude Code also reads `CLAUDE_CODE_TMPDIR` |
| `HTTP_PROXY` | Network | Required if the Docker host routes through a corporate proxy |
| `HTTPS_PROXY` | Network | Required if the Docker host routes through a corporate proxy |
| `NO_PROXY` | Network | Domains to bypass proxy (e.g., localhost, internal services) |

**Hardcoded overrides (not forwarded, always set):**

| Variable | Value | Purpose |
|----------|-------|---------|
| `DISABLE_AUTOUPDATER` | `1` | Prevent the subprocess from auto-updating the Claude CLI mid-session |
| `DISABLE_TELEMETRY` | `1` | Prevent telemetry from the user's agent subprocess |
| `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` | `1` | Umbrella disable for autoupdater + feedback + error reporting + telemetry |

The subprocess does **not** need:
- `SUPABASE_SERVICE_ROLE_KEY` (server-side DB access only)
- `BYOK_ENCRYPTION_KEY` (server-side encryption only)
- `STRIPE_SECRET_KEY` (server-side Stripe operations only)
- `STRIPE_WEBHOOK_SECRET` (server-side webhook verification only)
- `NEXT_PUBLIC_SUPABASE_URL` / `NEXT_PUBLIC_SUPABASE_ANON_KEY` (client-side Next.js vars)
- `PORT` (server binding only)
- `WORKSPACES_ROOT` / `SOLEUR_PLUGIN_PATH` (server-side workspace provisioning only)
- `CLAUDECODE` (would cause "cannot launch inside another session" error if the server is running in a Claude Code dev session -- [anthropics/claude-agent-sdk-python#573](https://github.com/anthropics/claude-agent-sdk-python/issues/573))

### Implementation

**File: `apps/web-platform/server/agent-runner.ts`**

Replace line 158:

```typescript
// BEFORE (leaks all server secrets)
env: { ...process.env, ANTHROPIC_API_KEY: apiKey },

// AFTER (minimal allowlist)
env: buildAgentEnv(apiKey),
```

Export the helper function for testability (same file, near the top after imports):

```typescript
// --- Agent subprocess environment isolation (CWE-526) ---

const AGENT_ENV_ALLOWLIST = [
  "HOME",
  "PATH",
  "NODE_ENV",
  "LANG",
  "LC_ALL",
  "TERM",
  "USER",
  "SHELL",
  "TMPDIR",
  "HTTP_PROXY",
  "HTTPS_PROXY",
  "NO_PROXY",
] as const;

const AGENT_ENV_OVERRIDES: Record<string, string> = {
  DISABLE_AUTOUPDATER: "1",
  DISABLE_TELEMETRY: "1",
  CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: "1",
};

export function buildAgentEnv(apiKey: string): Record<string, string> {
  const env: Record<string, string> = {
    ANTHROPIC_API_KEY: apiKey,
    ...AGENT_ENV_OVERRIDES,
  };

  for (const key of AGENT_ENV_ALLOWLIST) {
    const value = process.env[key];
    if (value !== undefined) {
      env[key] = value;
    }
  }

  return env;
}
```

### Research Insights

**Node.js `child_process.spawn` env semantics:**
When `options.env` is provided, it completely replaces `process.env` for the child process ([Node.js docs](https://nodejs.org/api/child_process.html)). This means the allowlist approach is naturally deny-by-default -- any variable not explicitly included is invisible to the subprocess. No explicit deny logic is needed, and no new secrets added to the server in the future will leak without a conscious code change to add them to the allowlist.

**Agent SDK `options.env` caveat:**
The SDK's `options.env` does not override `env` entries in `~/.claude/settings.json` ([anthropics/claude-agent-sdk-typescript#217](https://github.com/anthropics/claude-agent-sdk-typescript/issues/217)). In the Docker container, there is no `~/.claude/settings.json` for the `soleur` user, so this caveat does not apply. If settings.json were ever introduced, it would be under the container's control, not the attacker's.

**`buildAgentEnv` must be exported** for unit testing. Use named export at declaration site per project convention (TypeScript uses inline `export` at declaration site, not separate `export {}` blocks -- constitution.md).

## Technical Considerations

### Defense-in-depth layers

This fix is one layer in a defense-in-depth strategy:

1. **This fix (env allowlist):** Prevents secrets from being accessible in the subprocess environment at all. Even if every other layer fails, the secrets are not present.
2. **`canUseTool` sandbox (existing):** Already restricts file Read/Write/Edit/Glob/Grep to the workspace path. Does not currently restrict Bash.
3. **`permissionMode: "default"` (existing):** Requires user approval for Bash tool calls. However, a compromised or careless user could approve malicious commands.
4. **Error sanitization (existing, `error-sanitizer.ts`):** Prevents server internals from leaking via error messages.

### Research Insights

**Follow-up: gate Bash in `canUseTool`:**
The `canUseTool` callback currently does not restrict the Bash tool. While the env allowlist makes Bash-based secret exfiltration impossible (the secrets are not in the environment), gating Bash provides defense-in-depth against other attack vectors (file system access outside workspace via shell, network exfiltration of workspace data). This should be filed as a separate GitHub issue.

**Follow-up: audit `/proc/self/environ`:**
Even with the env allowlist, the subprocess can read its own environment via `/proc/self/environ`. This is expected behavior -- it will only see the allowlisted vars. However, the workspace sandbox (`canUseTool`) should block reads of `/proc/` paths. Verify this is the case in the workspace path check.

### Risk: breaking the agent subprocess

The agent subprocess could fail if it requires an env var not in the allowlist. This risk is mitigated by:

- The [Claude Code documentation](https://code.claude.com/docs/en/env-vars) lists `ANTHROPIC_API_KEY` as the only authentication-required env var
- `HOME`, `PATH`, and locale vars cover standard Unix subprocess requirements
- `TMPDIR` covers temporary file operations
- The `TERM`, `USER`, and `SHELL` vars handle shell environment expectations
- `HTTP_PROXY`/`HTTPS_PROXY`/`NO_PROXY` cover corporate proxy scenarios
- The hardcoded `DISABLE_AUTOUPDATER=1` and `DISABLE_TELEMETRY=1` prevent unnecessary network calls that would fail or waste resources in the containerized environment

### Risk: future env vars

When a new env var is needed by the agent subprocess in the future, a developer must add it to `AGENT_ENV_ALLOWLIST`. This is intentional -- the default-deny posture means new secrets are safe by default, and adding a var to the allowlist is a conscious, reviewable decision.

### Research Insights

**Institutional learning -- error sanitization pattern:**
The project already applied the allowlist-with-fallback pattern in `error-sanitizer.ts` (documented in `knowledge-base/learnings/2026-03-20-websocket-error-sanitization-cwe-209.md`). The env allowlist follows the same principle: known-safe items are explicitly listed, everything else is blocked by default.

**Institutional learning -- fire-and-forget catch handler:**
The `sendUserMessage` function (line 296) calls `startAgentSession` fire-and-forget with a `.catch()` handler (documented in `knowledge-base/learnings/2026-03-20-fire-and-forget-promise-catch-handler.md`). The env change affects the env passed inside `startAgentSession`, not the error handling around it. No changes needed to the catch handler.

## Acceptance Criteria

- [ ] `apps/web-platform/server/agent-runner.ts` no longer spreads `process.env` into the agent subprocess `env` option
- [ ] An exported `buildAgentEnv()` function constructs a minimal env object from an explicit allowlist
- [ ] `ANTHROPIC_API_KEY` is set from the BYOK-decrypted key (unchanged behavior)
- [ ] `HOME`, `PATH`, `NODE_ENV`, locale vars, `TMPDIR`, and proxy vars are forwarded when present (subprocess functionality preserved)
- [ ] `DISABLE_AUTOUPDATER`, `DISABLE_TELEMETRY`, and `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC` are hardcoded to `"1"` (subprocess isolation hardening)
- [ ] `SUPABASE_SERVICE_ROLE_KEY`, `BYOK_ENCRYPTION_KEY`, `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET` are NOT present in the subprocess environment
- [ ] Unit test verifies: `buildAgentEnv` output contains only allowlisted keys, override keys, and `ANTHROPIC_API_KEY`
- [ ] Unit test verifies: `buildAgentEnv` output does NOT contain any known server secret, tested exhaustively against a deny list
- [ ] No regression in agent session startup (existing test patterns in `apps/web-platform/test/` pass)

## Test Scenarios

- Given `process.env` contains `SUPABASE_SERVICE_ROLE_KEY`, when `buildAgentEnv("sk-ant-test")` is called, then the returned object does NOT contain `SUPABASE_SERVICE_ROLE_KEY`
- Given `process.env` contains `BYOK_ENCRYPTION_KEY`, when `buildAgentEnv("sk-ant-test")` is called, then the returned object does NOT contain `BYOK_ENCRYPTION_KEY`
- Given `process.env` contains `STRIPE_SECRET_KEY` and `STRIPE_WEBHOOK_SECRET`, when `buildAgentEnv("sk-ant-test")` is called, then the returned object does NOT contain either
- Given `process.env` contains `HOME=/home/soleur` and `PATH=/usr/bin`, when `buildAgentEnv("sk-ant-test")` is called, then the returned object contains `HOME` and `PATH` with correct values
- Given `process.env` does NOT contain `LANG`, when `buildAgentEnv("sk-ant-test")` is called, then the returned object does NOT contain a `LANG` key (no undefined values)
- Given any API key string, when `buildAgentEnv(apiKey)` is called, then the returned object contains `ANTHROPIC_API_KEY` set to that exact string
- Given `process.env` contains `HTTPS_PROXY`, when `buildAgentEnv("sk-ant-test")` is called, then the returned object contains `HTTPS_PROXY` (proxy support)
- Given any call to `buildAgentEnv`, the returned object always contains `DISABLE_AUTOUPDATER: "1"`, `DISABLE_TELEMETRY: "1"`, and `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: "1"`
- Given `process.env` contains `CLAUDECODE=1`, when `buildAgentEnv("sk-ant-test")` is called, then the returned object does NOT contain `CLAUDECODE` (prevents nested-session error)
- Given `Object.keys(buildAgentEnv("key"))`, the total count equals the allowlist length + override count + 1 (`ANTHROPIC_API_KEY`), minus any allowlisted vars not present in `process.env`

### Research Insights

**Test file location:** `apps/web-platform/test/agent-env.test.ts` -- follows existing test file naming convention in the project (see `byok.test.ts`, `error-sanitizer.test.ts`, `workspace.test.ts`).

**Exhaustive deny-list test:** Rather than spot-checking individual secrets, include a test that iterates a `SERVER_SECRETS` array containing all known dangerous env vars and asserts none appear in the output. This catches regressions if someone accidentally adds a secret to the allowlist.

```typescript
const SERVER_SECRETS = [
  "SUPABASE_SERVICE_ROLE_KEY",
  "BYOK_ENCRYPTION_KEY",
  "STRIPE_SECRET_KEY",
  "STRIPE_WEBHOOK_SECRET",
  "NEXT_PUBLIC_SUPABASE_URL",
  "NEXT_PUBLIC_SUPABASE_ANON_KEY",
  "PORT",
  "WORKSPACES_ROOT",
  "SOLEUR_PLUGIN_PATH",
  "CLAUDECODE",
] as const;
```

## Dependencies & Risks

**Dependencies:** None. This is a self-contained change to a single file.

**Risks:**
- If the Claude CLI or Agent SDK requires an undocumented env var, the agent subprocess will fail silently or with an unclear error. Mitigation: test the full agent flow after deployment; add the var to the allowlist if needed.
- The `AGENT_ENV_ALLOWLIST` array is TypeScript `as const` so adding new vars requires a code change, not a config change. This is the correct tradeoff for security-critical code.
- Proxy vars (`HTTP_PROXY`/`HTTPS_PROXY`/`NO_PROXY`) are in the allowlist because blocking them would break the subprocess in corporate environments. These are infrastructure config, not secrets.

## References & Research

- Issue: [#723](https://github.com/jikig-ai/soleur/issues/723)
- Affected file: `apps/web-platform/server/agent-runner.ts:158`
- Related security work: `apps/web-platform/server/error-sanitizer.ts` (CWE-209 fix)
- Learning: `knowledge-base/learnings/2026-03-20-websocket-error-sanitization-cwe-209.md`
- Learning: `knowledge-base/learnings/2026-03-20-fire-and-forget-promise-catch-handler.md`
- CWE reference: [CWE-526](https://cwe.mitre.org/data/definitions/526.html) (Cleartext Storage of Sensitive Information in an Environment Variable)
- OWASP: A05:2021 Security Misconfiguration
- Claude Code env vars docs: [code.claude.com/docs/en/env-vars](https://code.claude.com/docs/en/env-vars)
- Agent SDK env issue: [anthropics/claude-agent-sdk-typescript#217](https://github.com/anthropics/claude-agent-sdk-typescript/issues/217)
- CLAUDECODE inheritance bug: [anthropics/claude-agent-sdk-python#573](https://github.com/anthropics/claude-agent-sdk-python/issues/573)
- Node.js child_process docs: [nodejs.org/api/child_process.html](https://nodejs.org/api/child_process.html)
