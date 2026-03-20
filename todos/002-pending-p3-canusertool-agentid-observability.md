---
title: Accept agentID in canUseTool options for observability
status: pending
priority: p3
domain: engineering
tags: [observability, audit]
source: review-agent/security-sentinel,architecture-strategist
---

## Description

The `canUseTool` callback signature omits the third `options` parameter which contains `agentID?: string`. The plan document called for logging `agentID` to correlate parent/subagent permission decisions with SubagentStart audit logs, but the implementation doesn't capture it.

## File

`apps/web-platform/server/agent-runner.ts` line 239-241

## Suggested Fix

Accept the options parameter and log agentID context in security-relevant paths (file tool deny, Agent tool allow).
