---
title: Sanitize SubagentStart hook log values
status: complete
priority: p3
domain: engineering
tags: [security, defense-in-depth]
source: review-agent/security-sentinel
---

## Description

The SubagentStart hook in `agent-runner.ts` logs `agent_id` and `agent_type` without sanitization. While these values originate from SDK internals (not user input), defense-in-depth suggests stripping newlines and limiting length to prevent log injection.

## File

`apps/web-platform/server/agent-runner.ts` lines 227-229

## Suggested Fix

```typescript
const sanitize = (v: unknown) => String(v ?? '').replace(/[\r\n]/g, ' ').slice(0, 200);
console.log(
  `[sec] Subagent started: agent_id=${sanitize(subInput.agent_id)}, ` +
  `type=${sanitize(subInput.agent_type)}`,
);
```
