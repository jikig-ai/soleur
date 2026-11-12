---
title: The Owner check read one workspace while the tools acted on another
date: 2026-11-11
category: security-issues
module: apps/web-platform/server (permission-callback, agent-runner, kb-share-tools, workspace-settings-tools)
tags: [approval-gate, workspace-scope, mutation-battery, review-fix-round]
issues: ["#12597", "#12197", "#12668", "#12669", "#12661"]
pr: "#12646"
---

# Learning: an authorization check is only as strong as the scope its action shares with it

## Problem

PR #12646 made the legacy runner's in-memory approval card Owner-only for all eight approval-required tools. The Owner
check reads the role in the session's `activeWorkspaceId`. The 13-seat panel found (security P1, pre-existing) that the
GitHub tools were bound to an installation and repo resolved by a *fresh* `current_workspace_id` read. So a workspace
switch during session start could pair "Owner of solo workspace A" with "push to team workspace B". The fix round then
showed that the two resolvers were an instance of a class. `kb_share_create` and `workspace_set_autonomous` also
re-resolve the workspace when they run. The coverage consult found a third shape: `email_send` and `email_suppress` are
not workspace actions at all (per user, platform sender), so a per-workspace role check excludes nobody (#12669).

## Solution

- Thread the ONE membership-verified id into every action that the check guards: `resolveInstallationId(userId, activeWorkspaceId)`,
  `getCurrentRepoUrl(userId, activeWorkspaceId)`, and a `sessionWorkspaceId` on the share and autonomy builders. On the
  legacy card (no grant), those builders refuse as `workspace_changed` when the current workspace differs.
- Pin it two ways. A pass-through spy asserts every resolver call carries the id. A comment-stripped source pin
  asserts an exact count of call sites, all with the id (the spy alone misses a branch the fixture does not reach).
- Where the action has no workspace (email), record a residual and file it. Do not claim the check covers it.

## Key Insight

For an authorization check, ask "which scope does the ACTION run in?" before "is the check fail-closed?". Then
enumerate every action site that the checked tools reach. Reviewers had read the check thoroughly (fail-closed on
error, timeout, abort and demotion), but the defect was in the action's scope, a different file.

## Session Errors

1. **A battery run was hosted inside the Monitor command and killed at the 5-minute expiry.** Recovery: re-ran it as a background job that writes its own rc line. **Prevention:** already a rule in `plugins/soleur/skills/ship/references/monitor-hygiene.md` (#8233): a Monitor never hosts the work it watches.
2. **New test titles extended existing detector substrings, so the judge would have scored older rows MISATTRIBUTED** (LO2, then LO6 twice). Recovery: tightened the detector strings (`": the role read fails: static deny"`). **Prevention:** a note in the battery's M-table header. Re-grep every detector when you add a test title.
3. **`prettier --write` reformatted a whole unformatted test file.** Recovery: `git restore --source=HEAD`, then reapplied the edit by hand. **Prevention:** never run a formatter on a file that was not formatted before.
4. **A `git stash list` was included in a command and the hook blocked it.** Recovery: dropped it. **Prevention:** hook-enforced (guardrails.sh).
5. **`gh issue create` was refused twice** (an unexpanded `$S` in `--body-file`, then no `User-Impact`/`Mandated-By` line). Recovery: wrote the body with Write, passed a literal path, added the lines. **Prevention:** hook-enforced; write the body file first and include `Mandated-By:` on its own line.
6. **`pgrep -f` was blocked as self-matching.** Recovery: used `proc.sh list_runs <pattern>`. **Prevention:** hook-enforced.
7. **MIN_CHECKS was raised by 6 instead of 4.** Recovery: recomputed the sum (19 + 36 + named + 1, plus mutants, plus 2). **Prevention:** derive the check floor from the comment's sum formula, never by adding deltas in your head.
8. **The source-pin test read a mocked `fs` and got ENOENT.** Recovery: used `vi.importActual("fs")`. **Prevention:** in a file that mocks `fs`, read real sources through `importActual`.
9. **A battery control (decide-boundary, 16 s) timed out under load from concurrent review seats.** Recovery: re-ran it, and it was green. **Prevention:** do not run battery `--only` runs while mutation-probing seats are active.
10. **The P1 fix covered two resolvers; the fix round found the class (share and autonomy).** Recovery: added `sessionWorkspaceId` pins. **Prevention:** already covered by review's "FIX COMMIT … INSTANCE or CLASS" rule. Grep every consumer of the scope, not only the reported call.
11. **(Forwarded from earlier phases.)** `gh issue create` hook blocks and markdownlint fixes. **Prevention:** hook-enforced and pre-commit lint.

## Tags

category: security-issues
module: web-platform approval gate
