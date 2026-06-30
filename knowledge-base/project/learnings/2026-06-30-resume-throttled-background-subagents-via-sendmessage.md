# Learning: Resume throttled background subagents via SendMessage; verify-sentinel UNION aliases live only on the first branch

date: 2026-06-30
issue: 5756
pr: 5799
category: workflow-patterns

## Problem

During the `/soleur:one-shot #5756` pipeline, three independent throttle/limit events interrupted background subagents, and two recovery missteps cost cycles:

1. The first **planning** subagent died on a *session usage limit* ("You've hit your session limit · resets 10:20pm") after 22 tool-uses, leaving **no artifact** (clean `git status`, no plan file). The limit reset 7 minutes later.
2. A **7-way parallel review fan-out** tripped a *server-side* throttle ("API Error: Server is temporarily limiting requests (not your usage limit) · Rate limited") — 4 of 7 agents (security, architecture, data-integrity, pattern) returned the error with zero findings after ~12 tool-uses each (they had already read the files).
3. The **fix-applier** subagent hit the same server throttle mid-application after 18 tool-uses (only a partial header edit landed).

Two recovery missteps:
- To re-run a throttled background agent I first spawned a **fresh `fork` Agent with a placeholder prompt** — wrong tool; it starts a new agent that loses the throttled agent's already-completed file-reads, and the placeholder did nothing. Had to `TaskStop` it.
- When directing the fix-applier to make the verify-sentinel branch-count test "convention-stable," I told it to count `AS check_name`. In a UNION-based sentinel that token appears **only once** (Postgres takes column names from the first `SELECT`; later-branch aliases are ignored), so the counter would read 1, not the real branch count.

## Solution

**Recovery for a throttled/limited background subagent that has useful context:** use `SendMessage(to: "<agentId>", ...)` to resume it from its transcript — NOT a fresh `Agent` spawn. The transcript (already-read files, partial edits) is preserved, so the resume just emits the remaining work. The tool result confirms `"had no active task; resumed from transcript in the background with your message."` Re-spawning fresh discards that context and re-pays the file-reads. Reserve a fresh `Agent`/`fork` spawn for genuinely new work.

**For a transient *session usage limit*:** check the clock against the stated reset time before acting. Here the reset (22:20) had already passed (22:27), so an immediate re-spawn succeeded. If a planning/impl subagent died with **no artifact** (verify: clean `git status` + no plan/spec file), re-spawn fresh (nothing to resume); if it left a partial artifact, recover from disk per one-shot's partial-artifact path.

**For a server-side throttle on a wide parallel fan-out:** don't proceed on partial coverage when the throttled agents are *core lenses* (security, data-integrity). Resume them via SendMessage in small batches (2 at a time) rather than re-firing all N at once, which re-trips the throttle. The Rate-Limit-Fallback gate permits partial coverage, but only after you've actually tried to recover the high-value agents.

**Counting check rows in a UNION-based verify sentinel:** count a per-branch token — the `::int` cast (one per branch) or the leading `SELECT '<check_name>'` literal (`/SELECT\s+'[a-z0-9_]+'/gi`) — never the column alias (`AS check_name` / `AS bad`), which appears only on the first branch.

## Key Insight

A background subagent that stops on a *transient* error (server throttle, usage limit) is **paused, not dead** — `SendMessage(agentId)` resumes it with full context. Choosing `Agent`/`fork` instead throws away its work. And UNION SQL column aliases are first-branch-only — any "count the rows" assertion must target a per-branch construct.

## Session Errors

- **Planning subagent hit a session usage limit, left no artifact** — Recovery: confirmed reset time had passed, re-spawned fresh (partial-artifact check found nothing to recover). Prevention: on subagent limit/throttle, check reset clock + run the no-artifact `git status` check before deciding resume-vs-respawn.
- **4/7 review agents tripped a transient server throttle on a wide parallel fan-out** — Recovery: resumed each via `SendMessage(agentId)` in small batches; all returned full findings. Prevention: for wide review fan-outs, expect transient throttling; resume (don't re-spawn) and batch the resumes.
- **Fix-applier subagent throttled mid-application** — Recovery: inspected partial state (`git status` + targeted greps), resumed via SendMessage with a correction. Prevention: same resume-via-SendMessage pattern.
- **Spawned a stray `fork` with a placeholder prompt to "resume" a throttled agent** — Recovery: `TaskStop` the stray, then `SendMessage` the real agent. Prevention: to continue a completed/throttled background agent, ALWAYS use `SendMessage(to: agentId)`; a fresh `Agent`/`fork` is for new work only.
- **Told the fix-applier to count `AS check_name` for a convention-stable check count** — Recovery: corrected on resume to count `::int` casts / `SELECT '<literal>'` rows. Prevention: UNION column aliases are first-branch-only; count a per-branch token.

## Tags
category: workflow-patterns
module: one-shot, review, supabase-verify
