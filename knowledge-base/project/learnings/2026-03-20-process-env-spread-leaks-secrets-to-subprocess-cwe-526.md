# Learning: Process.env spread leaks server secrets to agent subprocess (CWE-526)

## Problem

In `apps/web-platform/server/agent-runner.ts`, the Claude Agent SDK subprocess was spawned with `env: { ...process.env, ANTHROPIC_API_KEY: apiKey }`. This spread every server-side environment variable into the subprocess, including `SUPABASE_SERVICE_ROLE_KEY`, `BYOK_ENCRYPTION_KEY`, `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, and any future secrets added to the server environment.

The subprocess has Bash tool access, meaning a prompt injection or misbehaving agent could run `env` or `printenv` and exfiltrate every secret the server holds. Node.js `child_process.spawn` replaces `process.env` entirely when `options.env` is set, so spreading `process.env` is functionally equivalent to granting the subprocess full server credentials.

## Solution

Created `apps/web-platform/server/agent-env.ts` with a `buildAgentEnv(apiKey)` function that constructs the subprocess environment from an explicit allowlist:

1. **Allowlist**: Only operational vars the subprocess legitimately needs -- `HOME`, `PATH`, `NODE_ENV`, `LANG`, `LC_ALL`, `TERM`, `USER`, `SHELL`, `TMPDIR`, and proxy vars (upper and lowercase).
2. **Hardcoded overrides**: `DISABLE_AUTOUPDATER=1`, `DISABLE_TELEMETRY=1`, `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` -- preventing the subprocess from phoning home.
3. **Injected key**: `ANTHROPIC_API_KEY` is the only secret passed, and it is the user's own BYOK key, not a server credential.

Extracting into a standalone module (not co-located in `agent-runner.ts`) was a testing necessity -- importing from `agent-runner.ts` pulls in `@supabase/supabase-js`, `@anthropic-ai/claude-agent-sdk`, and `@/lib/types`, which fail without runtime config.

## Key Insight

Environment variable isolation for subprocesses must be deny-by-default (allowlist), not allow-by-default (denylist or spread-then-delete). With `process.env` spread, every new secret added to the server is automatically exposed -- a negative-space vulnerability invisible to code review of the subprocess code, because the leak happens in the parent's spawn call. Node.js replacing (not merging) `process.env` when `options.env` is set makes allowlisting both natural and airtight.

## Session Errors

1. **`npx vitest` failed -- missing native binding**: Worktree lacked `node_modules`. Running `npm install` resolved it.
2. **Test import pulled full dependency graph**: Exporting `buildAgentEnv` from `agent-runner.ts` caused test failures. Extracting into standalone `agent-env.ts` with zero external imports resolved this.
3. **`constitution.md` path mismatch**: `CLAUDE.md` references `knowledge-base/overview/constitution.md` but actual path differs.

## Cross-References

- [CWE-209 error sanitization](2026-03-20-websocket-error-sanitization-cwe-209.md) -- same file, same allowlist pattern
- [GitHub Actions env indirection](2026-03-19-github-actions-env-indirection-for-context-values.md) -- related env security concern
- GitHub issue #878 -- follow-up to gate Bash tool in canUseTool

## Tags
category: security-issues
module: web-platform/agent-runner
