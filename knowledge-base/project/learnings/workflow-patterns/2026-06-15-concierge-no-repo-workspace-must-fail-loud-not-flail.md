---
title: Concierge repo-less workspace must fail loud, not flail
date: 2026-06-15
category: workflow-patterns
tags: [workflow-patterns, concierge, worktree, go, one-shot, readiness-gate]
---

# Learning: a repo-less Concierge workspace must fail loud at step 1, not flail for 40 steps

## Problem

A Soleur web (Concierge) session dispatched `/soleur:go "Fix issue 4826"` and died with
"Agent stopped responding after: Working…". The debug stream showed the session route
correctly (go → one-shot, deferred feature, fix intent) and then spend ~40 tool calls
flailing: `worktree-manager.sh create` produced `DIR_NOT_FOUND`, followed by repeated
`ls /workspaces/<id>`, `find / -name .git`, `EnterWorktree`, and finally reading 15+
source files via `gh api .../contents | base64 -d` — emulating a checkout it could never
write to — before hanging.

Root cause: the Concierge workspace (`/workspaces/<id>`) had **no git checkout**. A
connected repo is cloned in the background (`/api/repo/setup` → `provisionWorkspaceWithRepo`,
fire-and-forget) and self-healed on cold dispatch (`ensureWorkspaceRepoCloned`), so a
session that opens during the clone window — or after a clone failure — lands in a
repo-less dir. Every route then fails: worktree creation, KB-artifact writes, and the
go session-start preamble all need a real repo.

Why existing guards missed it:
- The `go` bare-repo guard tests `is-bare-repository == true`. A repo-less dir is
  **neither** bare nor a worktree, so the guard didn't fire.
- `worktree-manager.sh create` died **silently** under `set -e` on
  `git rev-parse --show-toplevel`, giving the skill no clear signal.
- The runtime `worktree_enter_failed` detector (#5313) only catches a **narrow**
  repeated-`cd … && pwd` loop. The agent ran `cd && pwd` once, then varied its
  commands — evading the detector entirely.
- The mature server honest-message machinery (`worktree_enter_failed` WorkflowEnd +
  `reprovisionOutcome`, `cc-workflow-end-messages.ts`) only fires on the **EnterWorktree
  tool** path. The skill drives worktree creation via the **Bash script**, which bypasses
  it. `go`/`brainstorm`/`plan` don't use worktrees at all, so they have no server net.

## Fix

Deterministic, step-1 fail-loud at the **skill + script** layer (the server tool-path
machinery already covers its own case; no risky dispatch-streaming change warranted):

1. `worktree-manager.sh`: a no-repo guard before the bare/worktree branch — emits a
   distinct `NO_GIT_REPOSITORY` marker + `exit 3` instead of dying silently. Runs for
   every subcommand, so any worktree op in a repo-less env fails the same clear way.
2. `commands/go.md` Step 0.0 **Workspace Readiness Gate**: before the preamble and any
   routing, if neither `--is-bare-repository` nor `--is-inside-work-tree` is `true`, STOP
   with an honest, no-wait message ("your workspace isn't ready yet… try again in a
   moment… reconnect in Settings"). Catch-all for every route.
3. `skills/one-shot/SKILL.md`: same gate as Step 0 (pre) since one-shot can be invoked
   directly, plus a Step 0b check that aborts on the script's `NO_GIT_REPOSITORY` failure
   rather than spawning the planning subagent.

UX decision (product owner): **honest message, no wait**. The founder retries; by retry
time the background clone / cold-dispatch self-heal has usually completed, so the loop
closes without blocking or polling.

Test: `plugins/soleur/skills/git-worktree/test/no-repo-fail-loud.test.sh` (auto-discovered
by `scripts/test-all.sh` via the `plugins/soleur/skills/*/test/*.test.sh` glob).

## Takeaway

When an environment precondition can be absent (no repo, no network, no auth), guard it
**deterministically at the first action** with an honest user message. Do not rely on
downstream pattern-detectors — an agent with no clear signal improvises many *different*
commands, which slip past any narrow loop detector and burn the whole budget.
