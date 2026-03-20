# Learning: canUseTool sandbox requires defense-in-depth — no single layer stops Bash escape

## Problem

The `canUseTool` sandbox in `apps/web-platform/server/agent-runner.ts` only checked file-system tools (Read, Write, Edit, Glob, Grep). The Bash tool was completely unrestricted, allowing arbitrary shell commands — cross-tenant data access, secret exfiltration, destructive actions like `rm -rf /`. Two compounding gaps made this worse:

- `env: { ...process.env }` in the subprocess spawn leaked ALL server environment variables (database URLs, API keys, encryption secrets) to the agent subprocess. Even without Bash, any tool that could read `process.env` had full access.
- `permissions.allow: ["Read", "Glob", "Grep"]` in `settings.json` bypassed `canUseTool` entirely. The SDK evaluates "Allow rules" before the `canUseTool` callback — tools listed in `permissions.allow` never reach the callback at all.

## Solution

Three-tier defense-in-depth, where each layer independently blocks the most critical attack classes:

1. **SDK bubblewrap sandbox** (`sandbox: "bubblewrap"` in `AgentRunner` config) — OS-level filesystem/network isolation via Linux namespaces. The agent subprocess cannot access arbitrary paths or make network requests regardless of what commands it runs. This is the only layer that stops `bash -c 'cat /etc/shadow'` or `curl attacker.com`.

2. **canUseTool deny-by-default policy** — every tool invocation hits the callback. Bash commands are validated against an env-var-access regex and a path allowlist. File-system tools are validated against the same path allowlist. Any tool not explicitly handled is denied.

3. **disallowedTools for hard deny** — `WebSearch` and `WebFetch` are blocked at the SDK level before `canUseTool` even runs. Belt-and-suspenders for tools that should never be available to tenant agents.

Supporting changes:
- **Minimal env allowlist** — only 6 variables (`NODE_ENV`, `HOME`, `PATH`, `LANG`, `TERM`, `USER`) are passed to the subprocess instead of the full `process.env`. This eliminates the entire class of env-var exfiltration attacks.
- **Empty permissions.allow** — `settings.json` uses `"allow": []` so every tool invocation flows through `canUseTool`.
- **`settingSources: []` in query() options** — explicitly prevents the SDK from loading `.claude/settings.json`, which could contain `permissions.allow` entries that bypass `canUseTool` (permission chain step 4 before step 5). The SDK defaults to `[]` since v0.1.0, but the explicit setting is defense-in-depth against SDK regression or someone adding `settingSources: ["project"]` for CLAUDE.md support. If CLAUDE.md support is ever needed, inject content via `systemPrompt` instead of changing `settingSources`.
- **bubblewrap + socat in Dockerfile** — runtime dependencies for the SDK sandbox.

## Key Insight

Five generalizable lessons:

1. **Env var allowlists beat command filtering.** The env var allowlist was the most impactful single change. It eliminates the entire class of attacks where Bash reads secrets from the subprocess environment (`echo $DATABASE_URL`, `env | grep KEY`, `python -c "import os; print(os.environ)"`). Regex-based command filtering cannot catch all encoding/indirection tricks, but an empty environment has nothing to leak.

2. **Regex command filtering is defense-in-depth, not a security boundary.** Patterns like `\benv\b` are fundamentally bypassable via eval tricks (`e=env; $e`), string concatenation, hex encoding, interpreter-level access (`python -c "import os; os.environ"`), and subshell expansion. Treat regex checks as a speed bump that catches accidental misuse, not a wall that stops adversarial input.

3. **`startsWith` without trailing slash is a path traversal vulnerability.** `"/data/tenants/abc".startsWith("/data/tenants/ab")` returns `true` — tenant `ab` can read tenant `abc`'s files. Always append a trailing delimiter before prefix comparison: `(path + "/").startsWith(allowed + "/")`.

4. **SDK `permissions.allow` bypasses `canUseTool`.** This is architectural, not a bug — the SDK evaluates allow rules before the callback. An overly permissive `permissions.allow` list silently disables your entire `canUseTool` security layer for those tools. Use `"allow": []` and route everything through the callback.

5. **Anchor regex to command position.** `\benv\b` false-positives on legitimate commands like `python -m venv` and `printenv`. Anchoring to command position with `(?:^|[|;&])\s*env\b` reduces false positives while maintaining detection of actual `env` invocations.

## Session Errors

1. **`npx vitest` failed with rolldown native binding error** — the worktree's `node_modules` had a stale or incompatible rolldown binary. Resolved by using the project-local vitest binary (`./node_modules/.bin/vitest`) instead of `npx`, which can resolve to a different version.

## Tags
category: security-issues
module: web-platform
