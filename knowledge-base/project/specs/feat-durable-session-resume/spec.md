---
title: Durable session/workspace resume + reconnect (v1 — honest UX + verified rebind)
date: 2026-06-14
status: draft
issue: 5240
branch: feat-durable-session-resume
pr: 5256
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-06-14-durable-session-resume-brainstorm.md
---

# Spec: Durable session/workspace resume — v1

## Problem Statement

Backend agent sessions (the product chat where a leader runs work in a cloned-repo
workspace) mishandle disconnect/reconnect. On a mid-turn drop + reconnect, the agent card
shows a **fabricated** "Retrying… Finding `**/*nav-rail*`…" with no progress, and "continue
where you left off" returns a misleading **fresh-session greeting** ("no git repository…
nothing to resume from"). The user's cloned repo and in-flight worktree are in fact still on
disk — the failure is wrong-workspace **binding resolution**, not lost data — but the product
*reports* total loss, breaking the "an AI org that remembers" promise. Single-user
trust-breaking incident (P1).

## Goals

- G1: On resume of a conversation with prior turns, rebind to the **same** `workspace_id` the
  conversation was bound to and verify its `.git` exists before responding.
- G2: Never return a fresh-session greeting on a conversation that has prior turns.
- G3: When the workspace is genuinely unrecoverable, report the truth accurately and offer an
  explicit "resume with full conversation context" action (named continuity).
- G4: Replace the fabricated "Retrying…" status with accurate connection/activity states.

## Non-Goals (deferred to follow-up issues)

- N1: Physical workspace durability / snapshot / re-provision (#2) — largely moot; `/workspaces`
  is already a persistent Hetzner volume on a single instance.
- N2: Stream-since-disconnect server-side event-replay buffer (#5) — next-highest-value follow-up.
- N3: In-flight (mid-turn, uncommitted) work durability via worktree checkpointing (#4).
- N4: Horizontal-scaling / cross-host reconnect concerns — single instance today.

## Functional Requirements

- FR1: On `resume_session`, resolve workspace from the conversation's durable binding
  (`user_session_state.current_workspace_id` / conversation row), NOT via the silent
  solo-workspace fallback in `resolveActiveWorkspacePath` (`workspace-resolver.ts:339`).
  → wireframe state 4 (`reconnect-resume-states.pen`).
- FR2: Before greeting on resume, probe `.git` presence at the resolved path (read-only reuse
  of the `ensure-workspace-repo.ts` `.git` guard — a probe, not a re-clone).
- FR3: If transcript resumes but the bound workspace is absent/diverged, emit the honest
  unrecoverable state (named continuity + single `[Resume with full context]` action), never a
  fresh greeting. → wireframe state 3.
- FR4: Replace the fabricated "Retrying… Finding …" status (`chat-state-machine.ts:~1112`) with
  accurate states: "Connection lost — reconnecting" (within grace) and "No response for 45s"
  (stuck-watchdog). → wireframe states 1 & 2.
- FR5: When the bound workspace exists with `.git`, the resumed turn continues in that exact
  workspace/worktree with prior context.

## Technical Requirements

- TR1: No silent fallback that masks a binding mismatch — a missing/mismatched binding must
  surface honestly (mirror to Sentry per `cq-silent-fallback-must-mirror-to-sentry`).
- TR2: Determine the authoritative binding store (conversation row vs `user_session_state`) and
  record the decision in an ADR (`/soleur:architecture create`). See brainstorm Open Question 1.
- TR3: Define the grace-window/abort vs re-attach race resolution deterministically
  (`DISCONNECT_GRACE_MS`).
- TR4: No new persisted data category in v1 (CLO). If a follow-up adds an event buffer, document
  a TTL ≤ conversation retention, same EU region.

## Acceptance Criteria

- AC1: Reconnect within grace → client re-attaches; resumed turn lands in the **correct**
  workspace/worktree with prior context (no solo-workspace drift).
- AC2: Reconnect after a backend restart where the bound workspace still exists → continues in it.
- AC3: "continue where you left off" on a conversation with prior turns → never a fresh-session
  greeting; either correct continuation or an honest "workspace reclaimed — resume with context?".
- AC4: The "Retrying…" fabrication is gone; status copy matches wireframe states 1 & 2.
- AC5: No `getUserWorkspace` "No workspace binding" throw after reconnect.

## References

- Issue: #5240 · Brainstorm: see frontmatter · Wireframes:
  `knowledge-base/product/design/chat/reconnect-resume-states.pen`
- Code seams: `workspace-resolver.ts:339`, `agent-session-registry.ts:45,179`,
  `ws-handler.ts:2404-2433,2511`, `agent-runner.ts:1874-1885`,
  `ensure-workspace-repo.ts`, `chat-state-machine.ts:~1112`.
