---
title: "fix: restrict env vars passed to agent subprocess"
type: fix
date: 2026-03-20
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

## Proposed Solution

Replace the `...process.env` spread with a minimal allowlist of environment variables that the agent subprocess actually needs to function.

### Allowlist

The Claude Agent SDK spawns `claude` CLI as a subprocess. That subprocess needs:

| Variable | Purpose |
|----------|---------|
| `ANTHROPIC_API_KEY` | Already set explicitly from BYOK decryption |
| `HOME` | Claude CLI writes config/cache to `$HOME` |
| `PATH` | Required for the subprocess to find `claude`, `git`, and other binaries |
| `NODE_ENV` | Used by Node.js libraries for conditional behavior |
| `LANG` / `LC_ALL` | Locale settings for proper Unicode handling |

The subprocess does **not** need:
- `SUPABASE_SERVICE_ROLE_KEY` (server-side DB access only)
- `BYOK_ENCRYPTION_KEY` (server-side encryption only)
- `STRIPE_SECRET_KEY` (server-side Stripe operations only)
- `STRIPE_WEBHOOK_SECRET` (server-side webhook verification only)
- `NEXT_PUBLIC_SUPABASE_URL` / `NEXT_PUBLIC_SUPABASE_ANON_KEY` (client-side Next.js vars)
- `PORT` (server binding only)
- `WORKSPACES_ROOT` / `SOLEUR_PLUGIN_PATH` (server-side workspace provisioning only)

### Implementation

**File: `apps/web-platform/server/agent-runner.ts`**

Replace line 158:

```typescript
// BEFORE (leaks all server secrets)
env: { ...process.env, ANTHROPIC_API_KEY: apiKey },

// AFTER (minimal allowlist)
env: buildAgentEnv(apiKey),
```

Add a helper function (same file, near the top):

```typescript
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
] as const;

function buildAgentEnv(apiKey: string): Record<string, string> {
  const env: Record<string, string> = {
    ANTHROPIC_API_KEY: apiKey,
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

## Technical Considerations

### Defense-in-depth layers

This fix is one layer in a defense-in-depth strategy:

1. **This fix (env allowlist):** Prevents secrets from being accessible in the subprocess environment at all. Even if every other layer fails, the secrets are not present.
2. **`canUseTool` sandbox (existing):** Already restricts file Read/Write/Edit/Glob/Grep to the workspace path. Does not currently restrict Bash.
3. **`permissionMode: "default"` (existing):** Requires user approval for Bash tool calls. However, a compromised or careless user could approve malicious commands.
4. **Error sanitization (existing, `error-sanitizer.ts`):** Prevents server internals from leaking via error messages.

### Risk: breaking the agent subprocess

The agent subprocess could fail if it requires an env var not in the allowlist. This risk is mitigated by:

- The Claude CLI documentation specifies `ANTHROPIC_API_KEY` as the only required env var
- `HOME`, `PATH`, and locale vars cover standard Unix subprocess requirements
- `TMPDIR` covers temporary file operations
- The `TERM`, `USER`, and `SHELL` vars handle shell environment expectations

### Risk: future env vars

When a new env var is needed by the agent subprocess in the future, a developer must add it to `AGENT_ENV_ALLOWLIST`. This is intentional -- the default-deny posture means new secrets are safe by default, and adding a var to the allowlist is a conscious, reviewable decision.

## Acceptance Criteria

- [ ] `apps/web-platform/server/agent-runner.ts` no longer spreads `process.env` into the agent subprocess `env` option
- [ ] A `buildAgentEnv()` function (or equivalent) constructs a minimal env object from an explicit allowlist
- [ ] `ANTHROPIC_API_KEY` is set from the BYOK-decrypted key (unchanged behavior)
- [ ] `HOME`, `PATH`, `NODE_ENV`, locale vars, and `TMPDIR` are forwarded (subprocess functionality preserved)
- [ ] `SUPABASE_SERVICE_ROLE_KEY`, `BYOK_ENCRYPTION_KEY`, `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET` are NOT present in the subprocess environment
- [ ] Unit test verifies: `buildAgentEnv` output contains only allowlisted keys plus `ANTHROPIC_API_KEY`
- [ ] Unit test verifies: `buildAgentEnv` output does NOT contain `SUPABASE_SERVICE_ROLE_KEY` or `BYOK_ENCRYPTION_KEY` even when they exist in `process.env`
- [ ] No regression in agent session startup (existing test patterns in `apps/web-platform/test/` pass)

## Test Scenarios

- Given `process.env` contains `SUPABASE_SERVICE_ROLE_KEY`, when `buildAgentEnv("sk-ant-test")` is called, then the returned object does NOT contain `SUPABASE_SERVICE_ROLE_KEY`
- Given `process.env` contains `BYOK_ENCRYPTION_KEY`, when `buildAgentEnv("sk-ant-test")` is called, then the returned object does NOT contain `BYOK_ENCRYPTION_KEY`
- Given `process.env` contains `HOME=/home/soleur` and `PATH=/usr/bin`, when `buildAgentEnv("sk-ant-test")` is called, then the returned object contains `HOME` and `PATH` with correct values
- Given `process.env` does NOT contain `LANG`, when `buildAgentEnv("sk-ant-test")` is called, then the returned object does NOT contain a `LANG` key (no undefined values)
- Given any API key string, when `buildAgentEnv(apiKey)` is called, then the returned object contains `ANTHROPIC_API_KEY` set to that exact string

## Dependencies & Risks

**Dependencies:** None. This is a self-contained change to a single file.

**Risks:**
- If the Claude CLI or Agent SDK requires an undocumented env var, the agent subprocess will fail silently or with an unclear error. Mitigation: test the full agent flow after deployment; add the var to the allowlist if needed.
- The `AGENT_ENV_ALLOWLIST` array is TypeScript `as const` so adding new vars requires a code change, not a config change. This is the correct tradeoff for security-critical code.

## References & Research

- Issue: [#723](https://github.com/jikig-ai/soleur/issues/723)
- Affected file: `apps/web-platform/server/agent-runner.ts:158`
- Related security work: `apps/web-platform/server/error-sanitizer.ts` (CWE-209 fix)
- Learning: `knowledge-base/learnings/2026-03-20-websocket-error-sanitization-cwe-209.md`
- CWE reference: CWE-526 (Exposure of Sensitive Information Through Environmental Variables)
