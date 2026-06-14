---
title: When fixing a "binding" bug, verify which store the consuming RESOLVER reads — not the setter a research agent points at
date: 2026-06-14
category: logic-errors
tags: [plan-review, binding-resolution, call-graph-verification, subagent-claims, web-platform]
module: apps/web-platform/server
issue: 5240
---

# Learning: verify the read path's source-of-truth field, not the setter, when fixing a binding bug

## Problem

Planning the #5240 resume fix, the repo-research agent confidently identified the fix as "add
`workspace_id` to the resume SELECT and call `setUserWorkspace(userId, conv.workspace_id)`",
citing `ws-handler.ts:814-819` as the setter precedent. This was encoded into the v1 plan as the
load-bearing FR1. It was **wrong on the load-bearing mechanism**:

- `setUserWorkspace` writes the in-memory `userWorkspaces` map — which the issue body itself notes
  is "for SIGTERM precision, not auth."
- The agent's cwd is resolved by `resolveActiveWorkspacePath` (`agent-runner.ts:994`) →
  `resolveCurrentWorkspaceId` (`workspace-resolver.ts:190,217`), which reads
  **`user_session_state.current_workspace_id`** and falls back to `userId`/solo. It never consults
  the in-memory map.
- So the prescribed fix was a **no-op for the actual bug** — it writes a map the resolver ignores.
- The cited "setter precedent" at `ws-handler.ts:814-819` is actually a `getUserWorkspace` (read),
  not a setter.

## Solution

Plan-review (Kieran + code-simplicity, independently) flagged it as a P0 wrong-component error. A
30-second direct grep settled it: `resolveCurrentWorkspaceId` reads `user_session_state`, and the
resolver signature takes `(userId, tenant)` — no conversationId, no map lookup. The corrected FR1
writes `user_session_state.current_workspace_id = conversations.workspace_id` on resume (via the
existing `set_current_workspace_id` switch), which is the field the resolver actually reads.

## Key Insight

When a research agent says "the fix is to call setter `X`", that is a claim about the **write**
side. A binding/resolution bug is decided by the **read** side: *which store does the consuming
resolver actually read, and is that the store the setter writes?* An in-memory cache, a per-user
session row, and a per-entity column can all plausibly be "the binding" — and a setter that writes
one of them is dead code if the resolver reads another. Before encoding a load-bearing "call the
setter" fix into a plan:

1. Find the **consumer** (the function that produces the value the bug is about — here, the agent
   cwd via `resolveActiveWorkspacePath`).
2. Read what field/store IT reads (`user_session_state.current_workspace_id`, `?? userId` fallback).
3. Confirm the setter writes THAT store. If not, the fix targets the wrong store.

Plan-review's multi-agent panel earns its cost exactly here: a single research agent's call-graph
claim for the load-bearing fix site should be independently verified (by a reviewer or a direct
grep) before it shapes the plan — the schema/style reviewers can't catch it, but a
correctness-lensed reviewer tracing the read path will.

## Session Errors

1. **Research agent returned a wrong load-bearing fix mechanism + a mis-cited precedent.**
   Recovery: plan-review (Kieran P0-1/P0-2, Simplicity HIGH) caught it; direct grep of
   `workspace-resolver.ts:190,217` + `agent-runner.ts:994` confirmed the resolver reads
   `user_session_state`. **Prevention:** for any "the fix is at X / call setter Y" claim about a
   binding/resolution path, independently verify the *consuming read path* before encoding it as
   the plan's load-bearing FR — do not trust a single agent's call-graph claim for the fix site.

## Tags

category: logic-errors
module: apps/web-platform/server
