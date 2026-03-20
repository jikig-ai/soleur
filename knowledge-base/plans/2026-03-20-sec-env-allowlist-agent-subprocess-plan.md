---
title: "sec: replace process.env spread with minimal allowlist in agent subprocess"
type: fix
date: 2026-03-20
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
- **`HOME`**: Required by Claude Code CLI for config resolution (`~/.claude/`).
- **`PATH`**: Required to locate `claude` binary and git.

No other server secrets are needed by the subprocess.

## SpecFlow Edge Cases

1. **Missing `HOME` or `PATH`**: If `process.env.HOME` or `process.env.PATH` is undefined (unlikely in Docker but possible), the subprocess would fail to find the Claude CLI. The Dockerfile sets `USER soleur` which guarantees `HOME=/home/soleur`. `PATH` is inherited from the node base image. No guard needed -- if these are missing, the entire server is misconfigured.

2. **Future env requirements**: If a future Agent SDK version or plugin needs additional env vars (e.g., `LANG`, `TERM`, `NODE_ENV`), the subprocess will fail visibly (missing env error or broken behavior). This is the correct failure mode -- it forces an explicit allowlist update rather than silently leaking new secrets.

3. **`NODE_OPTIONS`**: Not needed. The subprocess is spawned by the Agent SDK which manages its own Node.js process flags.

4. **`SOLEUR_PLUGIN_PATH`**: Not needed in the subprocess env. The `pluginPath` is already passed via the `plugins` option to the Agent SDK `query()` call (line 159).

## Acceptance Criteria

- [ ] Line 158 of `apps/web-platform/server/agent-runner.ts` uses an explicit allowlist (`ANTHROPIC_API_KEY`, `HOME`, `PATH`) instead of `...process.env`
- [ ] No server secrets (`SUPABASE_SERVICE_ROLE_KEY`, `BYOK_ENCRYPTION_KEY`, `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`) appear in the subprocess environment
- [ ] Agent subprocess can still start successfully (Claude CLI resolves, git is on PATH)

## Test Scenarios

- Given the server has `SUPABASE_SERVICE_ROLE_KEY` in `process.env`, when `startAgentSession` spawns an agent subprocess, then the subprocess environment does NOT contain `SUPABASE_SERVICE_ROLE_KEY`
- Given the server has `BYOK_ENCRYPTION_KEY` in `process.env`, when `startAgentSession` spawns an agent subprocess, then the subprocess environment does NOT contain `BYOK_ENCRYPTION_KEY`
- Given the server has `HOME=/home/soleur` and a valid `PATH`, when `startAgentSession` spawns an agent subprocess, then the subprocess environment contains both `HOME` and `PATH` with the correct values

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
