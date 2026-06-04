---
module: workspace-switch / one-shot collision gate
date: 2026-06-04
problem_type: logic_error
component: react_component
symptoms:
  - "collision gate flagged a MERGED PR linked to an OPEN issue as 'already done'"
  - "workspace switch failure left DB/JWT tenant divergence (cross-tenant risk)"
root_cause: incorrect_assumption
severity: high
tags: [collision-gate, two-phase-commit, cross-tenant, fsm, one-shot, verify-before-trust]
synced_to: [go]
issue: 4917
pr: 4931
---

# Learning: a MERGED PR linked to an OPEN issue may be a SIBLING-scope artifact, not the fix

## Problem

`/soleur:one-shot #4917` hit the open-issue collision gate: issue #4917 was OPEN, but
`gh pr list --search "linked:issue #4917" --state all` returned PR #4911 in `MERGED`
state. The gate treats a merged-linked-PR as a near-certain "this work is already done"
signal and aborts-by-default. Taken at face value, the run would have aborted as a
duplicate — but #4917 was genuinely unimplemented.

Separately, the bug itself (#4917): the workspace org-switcher ran a two-phase commit —
`set_current_workspace_id` RPC (durable write to `user_session_state`) → `refreshSession()`
(ephemeral JWT re-mint) → hard-nav. A single `status === "failed"` state offered Retry/Cancel
for BOTH failure modes, so **Cancel after a committed RPC** left the DB pointing at the new
workspace while the screen still labeled the old one — a silent cross-tenant context switch.

## Solution

**Collision-gate verification (the reusable insight):** A MERGED PR linked to an OPEN issue
is not proof the issue's work is done — it may be a *sibling-scope* artifact. Here #4911 was
the KB chrome/visual redesign (issue #4915) that, per a CTO constraint, *deliberately
preserved* the switch FSM verbatim; #4917 was filed separately to fix that FSM. The link
existed only because #4917 was surfaced during #4911's spec-flow analysis.

Verify before trusting the "already done" signal by reading whether the bug still exists in
`main`, not by trusting the link:

```bash
# Did the merged PR actually touch the issue's target surface, and is the bug still live?
gh pr view 4911 --json files --jq '.files[].path' | grep org-switcher   # yes, it touched the file
git show main:apps/web-platform/components/dashboard/org-switcher-container.tsx | sed -n '95,99p'
#   catch (err) { setStatus("failed"); return; }   ← bug present verbatim → fix NOT landed
```

A name/file match is not a scope match. The merging PR touched the same FILE (redesign) but
not the same BEHAVIOR (the post-RPC failure branch).

**The fix (#4917):** split the FSM discriminant into pre- vs post-commit failure:

```ts
type SwitchStatus = "idle" | "switching" | "syncing" | "failed_pre_rpc" | "failed_post_rpc";
```

- `failed_pre_rpc` (RPC errored, nothing committed) → keep Retry + **Cancel** (safe).
- `failed_post_rpc` (RPC committed, `refreshSession` threw) → **converge forward, never Cancel**.
  Online → `window.location.assign("/dashboard")` (server re-reads the durable truth, JWT
  re-mints on load). Offline → honest "saved / will finish on reconnect" + bounded Try-again +
  always-present Continue. Mirror the divergence to Sentry via `reportSilentFallback`.

A compensating rollback-RPC was rejected: the same network blip can fail the rollback and
re-open the divergence. The user already authorized the switch, so converge-forward is correct.

## Key Insight

Two generalizable lessons:

1. **Collision gate: a merged linked PR is a hypothesis ("maybe done"), not a verdict.** When
   an issue stays OPEN under a merged linked PR, read the actual target surface in `main` and
   confirm the specific behavior is or is not fixed before aborting or trusting. Sibling-scope
   PRs (a redesign that preserves the buggy mechanism by constraint) are the trap.
2. **Client-side two-phase commit must branch failure UX on commit state.** A durable write
   (RPC) followed by an ephemeral one (JWT re-mint) has two failure modes; collapsing them into
   one "failed" state with a Cancel that implies "nothing happened" is a silent-divergence bug.
   Pre-commit = safe to undo; post-commit = converge forward only.

## Session Errors

1. **[plan] Task-subagent spawning unavailable in the planning subagent's env** — Recovery: ran
   plan-review/deepen inline across all lenses. Prevention: pipeline subagents lacking the Task
   tool should declare the inline-execution caveat (done in the plan's Enhancement Summary).
2. **[plan] `gh pr view --json merged` invalid field** — Recovery: used `state` (`MERGED`).
   Prevention: prefer `--json state` for merge status on this gh version.
3. **[go] Collision gate flagged merged #4911 against open #4917** — Recovery: verified #4911
   was the sibling redesign by reading the live bug in `main`. Prevention: the gate already
   prescribes a merged-PR probe; this session confirms the read-the-code verification step is
   load-bearing (the `[[2026-05-29-one-shot-collision-gate-must-probe-merged-prs]]` learning).
4. **[qa] `nav-states-shell` structural-UI gate flaked (recurring)** — KB-rail single-read of an
   animated `transition-[width]` (`66`/`126` vs `≤64`) + KB-route goto timeout; both passed on
   retry. Recovery: re-ran failing tests with `--retries=2` (`2 flaky`). Prevention: migrate the
   width assertion to `expect.poll` per the PR #4871 class — filed #4934 (different subsystem).
5. **[qa] Playwright auto-backgrounded** — Recovery: waited via Monitor until-loop per
   `hr-monitor-not-run-in-background-for-polling`. Prevention: none (handled correctly).

## Tags
category: workflow-patterns
module: one-shot collision gate / org-switcher-container
