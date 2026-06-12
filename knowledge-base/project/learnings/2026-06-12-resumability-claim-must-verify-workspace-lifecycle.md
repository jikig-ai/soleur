# Learning: A session-resumability claim must be verified against the workspace lifecycle, not just SDK session_id persistence

## Problem

An operator's web-platform session disconnected mid-turn (running "Fix Issue 4826") and on reconnect stayed stuck on a "Retrying…" card. Asked whether the backend session was still alive and resumable, I traced the server code and confidently answered:

> "Context is NOT lost. The SDK `session_id` is persisted to the conversation row (`agent-runner.ts:1874-1885`) and resumed on the next turn (`:2562`, `:2666`), so just send a follow-up like 'continue where you left off' and the agent resumes with full context."

The operator then ran exactly that test. The agent replied: *"fresh session with no prior workspace context — there's no git repository, no knowledge-base, and no worktrees present. Nothing to resume from."* My reassurance was **wrong**.

## Root Cause

I reasoned from ONE layer (SDK transcript persistence) and generalized it to "the session resumes." But an agent session spans two independent layers:

1. **SDK transcript** — `session_id` persisted to the DB conversation row, resumed on the next turn. This layer *does* survive.
2. **Workspace/filesystem** — the cloned repo + in-flight worktree that the agent's `cwd` points at. This layer is **ephemeral per backend container/sandbox**: the logical binding (`userWorkspaces` Map, `agent-session-registry.ts:45`) is cleared on disconnect (`clearUserWorkspace`, `ws-handler.ts:2511`) and re-resolved at WS-open, but the *physical* repo/worktree only existed on the original environment's disk. After the 30s grace abort (`DISCONNECT_GRACE_MS`) or a sandbox/process recycle, a reconnected turn resolves a valid workspace *id* but lands on a fresh filesystem where nothing was cloned.

Resuming the transcript without rebinding the workspace produces exactly the observed "no git repository, no worktrees" greeting. The two layers are decoupled, and I had only verified one.

## Solution

Retracted the claim to the operator immediately and plainly ("I was wrong, and I'm retracting it"). Re-investigated the *workspace* lifecycle specifically (provisioning, persistence, reconnect rebind, worktree durability) instead of the transcript layer. Filed **#5240** ("Design durable session/workspace resume + reconnect") capturing the verified findings and clearly separating verified facts from the leading hypothesis (physical sandbox ephemerality — flagged as needing confirmation of where/whether the repo is cloned into the resolved workspace path on (re)provision).

## Key Insight

**Recoverability/resumability is a property of the whole stack, not the one layer you happened to read.** When answering "is this still alive / can we reconnect," enumerate every layer the capability depends on (transcript, workspace binding, physical filesystem, live event stream) and verify EACH before reassuring. State what you verified vs. what you're inferring. A persisted id proves the id survived — not that the environment it points at still exists. And when a user's live test falsifies a claim, retract plainly and re-derive; don't defend the original framing.

## Session Errors

- **Asserted resumability from SDK `session_id` persistence alone** — Recovery: operator's live "continue where you left off" test falsified it; retracted, re-investigated the workspace lifecycle, filed #5240. **Prevention:** for any "is X recoverable/alive" question, list the layers the capability depends on and verify each; separate verified facts from inferences in the answer.
- **`gh issue create` denied for missing `--milestone`** — Recovery: re-ran with `--milestone "Post-MVP / Later"`. **Prevention:** already hook-enforced (`guardrails:require-milestone`); body was correctly written via the Write tool first, so no heredoc loss. One-off.
- **Edit attempted before Read in the worktree path** — I had read the bare-root copy of the same file earlier (different absolute path). Recovery: Read the worktree path, then Edit. **Prevention:** already covered by `hr-always-read-a-file-before-editing-it` + harness file-state tracking; the per-worktree-path read is the nuance. One-off.
- **Pre-existing flaky test `live-repo-badge.test.tsx`** surfaced in the full-suite exit gate (a *different* test failed on each run → non-deterministic, unrelated to this diff). **Prevention:** known parallel-load/absence-wait flake class (#5113 family); not caused by or in scope for this PR. Recurring but already-tracked-elsewhere; not re-filed to avoid a duplicate.

## Tags
category: workflow-patterns
module: web-platform/session-lifecycle
related: "#5240"
