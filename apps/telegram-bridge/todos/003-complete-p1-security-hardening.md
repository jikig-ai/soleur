---
status: complete
priority: p1
issue_id: "003"
tags: [code-review, security]
dependencies: []
---

# Security hardening for headless bridge

## Problem Statement

`--dangerously-skip-permissions` grants unrestricted system access. Combined with full env passthrough (`env: { ...process.env }`), the CLI can read the bot token, all env vars, and execute arbitrary commands. The health endpoint is unauthenticated on `0.0.0.0:8080`.

## Findings

- **security-sentinel**: CRITICAL -- unrestricted system access via CLI, live token on disk, env passthrough
- **architecture-strategist**: "significant security trade-off" with hardcoded flag

## Proposed Solutions

### Option A: Minimal allow-list for env vars (Recommended first step)
Strip `TELEGRAM_BOT_TOKEN` and other secrets from the CLI subprocess env:
```typescript
const { TELEGRAM_BOT_TOKEN, TELEGRAM_ALLOWED_USER_ID, ...safeEnv } = process.env;
env: safeEnv,
```
- **Effort**: Small
- **Risk**: Low

### Option B: Replace `--dangerously-skip-permissions` with `--allowedTools`
Whitelist only safe tools: `Read`, `Grep`, `Glob`, `Write`, `Edit`, `Task`, `Skill`, `WebSearch`, `WebFetch`, `LSP`, and specific Bash patterns.
- **Effort**: Medium -- need to identify all safe tools
- **Risk**: Medium -- may break some workflows if tool list is incomplete

### Option C: Bind health endpoint to 127.0.0.1
- **Effort**: Small
- **Risk**: Low (may break external health checks)

### Option D: Private chat enforcement
Check `ctx.chat.type === "private"` to prevent group chat leakage.
- **Effort**: Small
- **Risk**: Low

## Acceptance Criteria
- [ ] CLI subprocess does not receive `TELEGRAM_BOT_TOKEN` in its env
- [ ] Health endpoint bound to 127.0.0.1 or authenticated
- [ ] Bot rejects messages from non-private chats
- [ ] NaN validation on allowedUserId

## Work Log
- 2026-02-11: Identified during /soleur:review
