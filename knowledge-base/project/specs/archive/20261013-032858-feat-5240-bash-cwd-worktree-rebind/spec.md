---
title: Bash sandbox worktree-rebind — make the bwrap sandbox reach git worktrees
status: draft
date: 2026-06-15
issue: 5313
parent_epic: 5240
branch: feat-5240-bash-cwd-worktree-rebind
pr: 5311
app: web-platform
lane: cross-domain
brand_survival_threshold: single-user incident
requires_security_signoff: true
brainstorm: knowledge-base/project/brainstorms/2026-06-15-bash-sandbox-worktree-rebind-brainstorm.md
---

# Spec: Bash sandbox worktree-rebind loop (deferred #5240 FR-half)

## Problem Statement

In the production Concierge, a worktree-creating session (`/soleur:go → one-shot →
worktree-manager.sh`) hangs in a "rebind loop": after the worktree is created, the Bash tool's
`pwd` stays at `/home/soleur`, Bash cannot `ls /workspaces/<uuid>/` or `git -C <worktree>`, while
Read/Edit/Grep tools read the repo fine. The one-shot CWD-verification gate
(`cd <worktree> && pwd` must equal the worktree path) can never pass, the agent loops the verify
command, and the turn dies with "Agent stopped responding" — the most trust-destroying state a
non-technical operator can see.

Root cause (code-verified): Bash runs in a **bwrap sandbox** whose mount namespace + `cwd` are
**frozen once per `query()`** (`agent-runner-query-options.ts:149`, `cwd: args.workspacePath`),
with `denyRead: ["/workspaces", "/proc"]` (`agent-runner-sandbox-config.ts:94`). `EnterWorktree`
is an SDK-native tool with no Soleur handler and cannot rebind that mount/cwd. File tools run
in-process (not bwrap-sandboxed), which is why they see the worktree and Bash does not.

Distinct from #5256 (reconnect logical rebind, merged) and #5306 (UI false-positive banner, draft).

## Goals

- **G1.** A worktree created mid-session is **reachable from the Bash sandbox** (`cd`, `ls`,
  `git -C` all succeed) so the CWD-verification gate passes.
- **G2.** When a worktree is genuinely unenterable, the agent **fails loud and bounded** — never
  loops, never silently masks — surfacing an honest operator status and a Sentry event.
- **G3.** Preserve the `/workspaces` cross-tenant `denyRead` isolation boundary unchanged.

## Non-Goals

- **NG1.** No workspace/sandbox-layer redesign. This is a mount-visibility fix, not a durability fix
  (the `/mnt/data/workspaces` volume is already persistent).
- **NG2.** Not the reconnect logical-rebind path (#5256, merged) nor the UI watchdog banner (#5306).
- **NG3.** No weakening of `denyRead`/seccomp/AppArmor cross-tenant controls.
- **NG4.** No new user-facing UI surface — honest failure reuses `reconnect-resume-states.pen`.

## Functional Requirements

- **FR1 — Sandbox reaches worktrees.** Re-derive or extend the bwrap mount set + `cwd` so that
  worktrees created under the mounted `workspacePath` (and their gitdir target) are visible and
  enterable from Bash, without mounting the `/workspaces` parent. Decide at plan time whether to
  mount the worktrees-root up-front (per-query) or re-derive on worktree entry.
- **FR2 — Bounded fail-loud gate.** The CWD-verification gate retries at most ~3 times, then raises
  `WorktreeEnterFailed{worktreeId, expectedPath, observedCwd}`, aborts the loop, and does NOT fall
  back silently.
- **FR3 — Honest operator status.** On FR2 failure, surface an accurate "couldn't enter the
  workspace/worktree" status reusing the #5256/#5306 honest-status family — never fake activity,
  never a fresh-session greeting.
- **FR4 — Sentry mirror.** FR2 failure mirrors to Sentry (`cq-silent-fallback-must-mirror-to-sentry`,
  `hr-observability-as-plan-quality-gate`) with the diagnostic triple.

## Technical Requirements

- **TR1.** Confirm via runtime repro the exact failure trigger (gitdir-escapes-mount vs.
  cwd-frozen-at-root vs. workspace-id binding drift) before finalizing FR1 — see Open Questions.
- **TR2.** Capture an ADR for the bwrap-mount-namespace-for-worktrees decision
  (`/soleur:architecture create`).
- **TR3.** `security-sentinel` + CTO sign-off REQUIRED before PR ready (sandbox-config change).
- **TR4.** Verify `$GIT_ROOT` for the Concierge clone resolves inside the mounted `workspacePath`
  (`worktree-manager.sh` creates worktrees at `$GIT_ROOT/.worktrees/<branch>`).

## Acceptance Criteria

- **AC1 (FR1):** A test/repro shows a mid-session worktree is `cd`-able, `ls`-able, and `git -C`-able
  from the Bash sandbox; the one-shot CWD gate passes.
- **AC2 (FR2):** An unenterable worktree triggers `WorktreeEnterFailed` after ≤3 attempts; no
  infinite loop; the genuine-hang exit is preserved (no permanent suppression).
- **AC3 (FR3):** The failure renders the honest, **retryable** status ("Couldn't open a workspace
  to run that step. Try sending your message again."), not "Agent stopped responding"/fresh-session
  greeting. [Reconciled at review: as-built routes `worktree_enter_failed` through cc-dispatcher's
  *recoverable* `else` branch — intentionally NOT in `TERMINAL_WORKFLOW_END_STATUSES` — since the
  failure is per-turn and retryable. The original "unrecoverable" wording was looser; recoverable-
  retry is the endorsed UX (CTO + user-impact review).]
- **AC4 (FR4):** The failure path emits a Sentry event with `worktreeId/expectedPath/observedCwd`.
- **AC5 (G3):** `denyRead: ["/workspaces", "/proc"]` and the seccomp/AppArmor profiles are unchanged
  for the cross-tenant boundary; security-sentinel confirms no new cross-tenant read surface.
- **AC6 (PR body):** `Ref #5240` (epic stays OPEN) + `Closes #<new-sub-issue>`.

## References

- `apps/web-platform/server/agent-runner-sandbox-config.ts:94` — `denyRead`/`allowWrite`
- `apps/web-platform/server/agent-runner-query-options.ts:149` — `cwd: args.workspacePath`
- `apps/web-platform/server/agent-runner.ts:852+` — `startAgentSession`
- `apps/web-platform/server/workspace-resolver.ts:339-348,668` — path resolution (NOT loop source)
- `apps/web-platform/infra/cloud-init.yml:632` — `-v /mnt/data/workspaces:/workspaces`
- `apps/web-platform/infra/server.tf:585-647` — seccomp + AppArmor bwrap profiles
- `plugins/soleur/skills/one-shot/SKILL.md:56,70-76` — CWD-verification gate
- `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` — worktree creation
- Learnings: `2026-05-15-one-shot-plan-subagent-cwd-divergence.md`,
  `2026-05-16-bash-cwd-persists-across-tool-calls.md`,
  `2026-06-04-cron-silence-was-bwrap-userns-drift-not-turn-budget.md`,
  `2026-06-03-sandbox-helper-cleanup-on-transient-controller-and-worktree-residency.md`
- Parent: `knowledge-base/project/brainstorms/2026-06-14-durable-session-resume-brainstorm.md` (#5240)
