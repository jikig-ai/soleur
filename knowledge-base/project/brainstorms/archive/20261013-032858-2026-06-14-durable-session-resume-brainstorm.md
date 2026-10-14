---
title: Durable session/workspace resume + reconnect for backend agent sessions
date: 2026-06-14
status: brainstorm-complete
issue: 5240
branch: feat-durable-session-resume
pr: 5256
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Brainstorm: Durable session/workspace resume + reconnect (#5240)

## What We're Building

Make SOLEUR's **backend agent sessions** (the product's user-facing chat, where leaders
like CPO run real work inside a cloned-repo workspace) survive a client
disconnect/reconnect **honestly and correctly**. The inciting failure (live operator
debug session): a turn running "Fix Issue 4826" dropped mid-turn; on reconnect the agent
card stuck on a fake "Retrying… Finding `**/*nav-rail*`…", and "continue where you left
off" returned a misleading **fresh-session greeting** ("no git repository… nothing to
resume from").

**v1 scope (operator-selected smallest correct slice):**

1. **Honest reconnect/resume UX (#6)** — never a fresh-session greeting on a conversation
   with prior turns; kill the misleading "Retrying…"; when work is genuinely unrecoverable,
   say so accurately and offer "resume with conversation context?".
2. **Verified deterministic workspace rebind (#1 + detection half of #3)** — on resume,
   rebind to the SAME `workspace_id` the conversation was bound to (durable in
   `user_session_state` / conversation row), verify `.git` exists at the resolved path
   before greeting, and stop the silent fallback to the solo workspace.

**Deferred to follow-ups:** physical workspace durability / re-provision (#2 — largely
moot, see below), stream-since-disconnect replay buffer (#5), in-flight work durability
(#4).

## Why This Approach

### Headline finding — the issue's leading hypothesis is FALSE

Issue #5240 hypothesized the "no git repository" failure came from an **ephemeral
per-container filesystem**. Code says otherwise (verified independently by an Explore
agent and the CTO):

- **Workspaces sit on a persistent Hetzner block volume.** `/workspaces` →
  `/mnt/data/workspaces` (`apps/web-platform/infra/server.tf:847-861`; confirmed via
  `cron-workspace-gc.ts`). It survives process restarts, redeploys, and crashes.
- **Single backend instance, no horizontal scaling** (`hcloud_server.web`, no replicas/LB)
  — a reconnect cannot land on a different process/host.
- Therefore the cloned repo and the `feat-one-shot-4826-*` worktree were almost certainly
  **still on disk** when the user was told "nothing to resume from."

**The real bug is binding-resolution drift, not filesystem durability.** On resume the SDK
transcript was restored, but `resolveActiveWorkspacePath` "never returns null" and silently
falls back to the **solo workspace** — a *different* `workspace_id` where the repo was never
cloned (`apps/web-platform/server/workspace-resolver.ts:339`). The agent then truthfully
reported an empty filesystem while the original cloned workspace sat intact one directory
over.

**Consequence:** design point #2 (physical durability) is largely already solved by the
persistent volume; the expensive part of the issue evaporates. The fix concentrates on
deterministic, *verified* rebind + honest UX — small effort (~1 day) for the worst
user-facing failure.

### Why honesty-first (CPO)

The brand promise is "an AI org that *remembers*." The damage is the **lie**, not the lost
compute. A user told "I still have our conversation about Fix Issue 4826 — the workspace was
reclaimed; resume with full context?" retains trust; a user given a fresh greeting on a
conversation with history does not. Honest + named-continuity is the trust floor.
Physical re-clone/durability is a *quality* fix that belongs after demand is proven (YAGNI).

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Reframe from "ephemeral fs durability" to "binding-resolution drift + honest UX" | Persistent volume + single instance verified in code; the cloned repo survives restarts |
| 2 | v1 = honest UX (#6) + verified deterministic rebind (#1 / detection half of #3) | Smallest slice that stops the trust bleed; ~1 day |
| 3 | Stop the silent solo-workspace fallback for conversations with an established binding | `resolveActiveWorkspacePath` never-null fallback is the proximate cause of the wrong-workspace greeting |
| 4 | Reuse `ensure-workspace-repo.ts` `.git`-presence guard as a read-only **probe** (not a re-clone) to detect loss | The detection seam already exists |
| 5 | Replace misleading "Retrying…" with accurate status (`chat-state-machine.ts:~1112`) | Fake activity is part of the trust breach |
| 6 | Defer #2 (physical durability), #5 (stream replay), #4 (in-flight durability) to follow-up issues | #2 mostly redundant; #5 is the next-highest-value follow-up; #4 lowest value/cost |
| 7 | Promote #5240 from "Post-MVP / Later" to Phase 4 | P1 single-user trust-breaking incident; founders hit it during unassisted-usage tracking |
| 8 | Document a TTL on any future buffer/persisted-workspace retention (CLO hygiene) | Load-bearing legal control if/when scope expands to third-party repos |
| 9 | Visual design: wireframe the reconnect/resume states — `knowledge-base/product/design/chat/reconnect-resume-states.pen` (4 states; screenshots in `screenshots/`) | New user-visible resume affordance + honest-status states |

## Open Questions

1. **Binding scope: conversation-level vs user-level.** `user_session_state.current_workspace_id`
   is per-user, but a user can have multiple conversations on different workspaces. The durable
   binding for "this conversation's workspace" arguably belongs on the **conversation row**.
   Resolve at plan/ADR time (CTO suggested `/soleur:architecture create`).
2. **Why did the resume resolve a different workspace_id?** Confirm the exact path: did the
   conversation row carry the correct `workspace_id` and resolution ignored it, or was the
   binding never persisted at conversation creation? Trace before writing the fix.
3. **Grace-window / abort race.** Reconnect at ~30s (`DISCONNECT_GRACE_MS`) — does `abortSession`
   race the re-attach? v1 must define the deterministic either/or.
4. **Turn-completed-while-gone case** (CPO edge case): user drops, turn finishes server-side,
   user returns — show "ended successfully while you were away — here's the result," not a stall.
   In v1 honest-UX scope or a follow-up?

## User-Brand Impact

- **Artifact:** the backend agent-session reconnect/resume flow (web-platform chat surface +
  `agent-runner` / `ws-handler` resume path).
- **Vector:** silent data-loss masquerading as success — a resumed conversation lands on the
  wrong (empty) workspace and the agent confidently reports "nothing to resume," destroying the
  "remembers" brand promise while the user's in-flight work sits intact and unreferenced.
- **Threshold:** single-user incident.

## Domain Assessments

**Assessed:** Engineering (CTO), Product (CPO), Legal (CLO)

### Engineering (CTO)

**Summary:** Load-bearing unknown resolved in code — `/workspaces` is a persistent Hetzner
volume, single instance, so points #1/#2 are largely solved at the data/fs layer; effort
concentrates on deterministic verified rebind (#3), honest UX (#6), and (next) the event-replay
buffer (#5). `user_session_state.current_workspace_id` is already a durable, restart-surviving
binding (the in-memory `userWorkspaces` Map is just a cache) — point #1 is ~80% done. Cheapest
correct first slice is making failure HONEST, not making resume DURABLE. Suggested ADR for the
binding-authority + event-buffer-tier decisions.

### Product (CPO)

**Summary:** Confirmed honesty-first ranking — #6 > #5 > #1 > #3 > #2 > #4 by trust impact. The
lie is the brand breach; physical durability is not required for v1. Minimum the user must see:
no lie, no fake activity, named continuity ("I still have our conversation about X"), one honest
actionable choice ("resume with context?"). Flagged roadmap mismatch (P1 in "Later"). Surfaced
edge cases: multi-tab reconnect, turn-completed-while-gone, flapping disconnects needing an ack
cursor, new-message-during-gap race, grace-window boundary race.

### Legal (CLO)

**Summary:** NOT a legal blocker for v1. Operator-self-use (tenant-zero, zero arms-length external
users) + same-EU-region (Hetzner hel1, signed DPA) dissolves residency/retention obligations.
A future per-turn event buffer is a transient replay cache of already-retained conversation-class
data — no new Art. 30 entry if TTL ≤ conversation retention and same EU substrate. Only hygiene
item: document a TTL. **Re-evaluation trigger:** first arms-length GitHub App install where a
third party's regulated-data repo lands on a durable volume → add Art. 30 PA entry, Privacy Policy
retention bullet, DPD entry.

## Capability Gaps

None. All required seams exist in code: durable binding (`user_session_state`, migration 060),
the `.git`-presence probe (`ensure-workspace-repo.ts`), SDK transcript resume (`agent-runner.ts:1874-1885`),
and the misleading-status site (`chat-state-machine.ts:~1112`). Evidence: file:line citations
above, verified by Explore + CTO agents against the worktree HEAD.
