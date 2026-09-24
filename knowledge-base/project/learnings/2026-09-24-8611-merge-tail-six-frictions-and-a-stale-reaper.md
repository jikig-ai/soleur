---
title: "#8611's merge tail: six frictions after review, and a session-start reaper running a stale copy"
date: 2026-09-24
category: workflow-issues
module: ship
tags: [ship, merge-livelock, runner-backlog, admin-merge, untrusted-ci, pre-merge-hook, gitignore, session-manifest, guard-vacuity-floor, test-all-affected, worktree-reaper]
pr: 8611
issues: ["#8683", "#8677", "#8493", "#8496"]
---

# Learning: #8611's merge tail, and a session-start reaper that ran a stale copy

## Problem

PR #8611 (Inngest steps stream past Cloudflare's 524; spawns capped and throttled) was
opened at 13:44Z on 2026-09-23 and merged at 22:21Z. Almost all of that time went to the
merge tail, not the code. Six separate frictions showed up after review. The next session
(2026-09-24) found a seventh while cleaning up.

## The frictions, and what each one needs

1. **Merge livelock under a GitHub-hosted runner backlog.** Ship Phase 7's BEHIND
   auto-sync (`plugins/soleur/scripts/sync-pr-behind.sh`) merges `origin/main` and pushes
   on every `BEHIND`. `ci.yml` cancels the in-flight PR run on each push. When the runner
   queue is backed up, a run takes longer than the gap between `main` merges, so no head
   ever gets a finished run. This is the second recurrence in three days: #8474 is recorded
   in `2026-06-02-auto-merge-livelock-fast-moving-main.md` §Recurrence. **Rule until #8683
   lands: sync only after CI on the current head has settled (terminal, ideally green).
   Never sync while a run is queued or in progress.** A cancelled run is unobserved, not
   passed.
2. **A PR that edits CI has no agent admin-merge path.** #8611 touched
   `.github/workflows/apply-web-platform-infra.yml`, `infra-validation.yml` and
   `workspaces-luks-verify.yml`. `admin-merge-ready.sh` therefore exits 1 (`UNTRUSTED-CI`),
   because the PR's own runs can mint any required context
   (`plugins/soleur/skills/ship/references/settle-then-admin-merge.md`). The operator merged
   it by hand. This is already enforced. The lesson is about timing: when the diff touches
   `.github/workflows/` or `.github/actions/`, tell the operator **at mark-ready time** that
   they will merge by hand. Otherwise they learn it only after the livelock has burned hours.
3. **The pre-merge hook denies a chained `emit-review-trailer.sh && gh pr merge`.**
   `.claude/hooks/pre-merge-rebase.sh` is a PreToolUse hook. It evaluates the whole command
   before any part of it runs, so the trailer commit the first half would create does not
   exist yet, and the review-evidence check denies. Run the trailer script as its own
   command, then re-issue the merge. Fixed in this PR: the deny reason now says so.
4. **A stray `apps/web-platform/.claude/.session-manifests/*.json` blocked
   `resolve-regenerable-conflicts.sh`.** `session-rules-loader.sh` sets `REPO_ROOT` to the
   session's CWD verbatim, so a session started in `apps/web-platform/` writes its manifest
   there. `.gitignore` had `/.claude/.session-manifests/`, which is root-anchored, so the
   nested manifest was untracked. The resolver's clean-tree check uses `status -uall` and
   refused. Fixed in this PR: the pattern is now `**/.claude/.session-manifests/`. The
   first attempt was a bare `.claude/.session-manifests/`, which is **still root-anchored**,
   because any pattern with an inner slash is anchored. `git check-ignore -v` on the nested
   path caught it. Open follow-on (not fixed here): a loader rooted at a subdirectory also
   reads `AGENTS.rules.md` from that subdirectory.
5. **`guard-vacuity-floor.test.sh` needs a standalone counter floor that reports on
   stderr.** The meta-guard counts a floor only when it matches `floor_lines_of`, which
   means an `if [[ … -lt|-le|-ge … ]]` / `if (( … < … ))` statement at line start over a
   declared counter. It scores that floor's mutant as `FIRES` only if the mutant exits
   non-zero **and** prints a floor-shaped sentinel on stderr (`classify_mutant`). A floor
   folded into a compound `if`, or one that reports on stdout, is invisible or scored
   `NO_FIRE`. Write it as `if (( n < FLOOR )); then printf '[FATAL] floor …\n' >&2; exit 1; fi`.
   The meta-guard enforces this already.
6. **`test-all-affected.test.sh`'s `runnable_n` read the host's diff, not the arm's
   forced diff.** Fixed by #8677 (merged 2026-09-24 02:48Z).
7. **(This session) The session-start `cleanup-merged` ran a stale `worktree-manager.sh`.**
   The root checkout sat detached at `80a33a52fa` (a review-evidence commit), which is older
   than #8493's commit-pinned gh-evidence reap. Its copy skips the GitHub query for any
   `[gone]` branch, so every squash-merged, auto-deleted branch printed
   `upstream is [gone] but no merge evidence` and was kept. That included
   `fix-infra-privileged-doppler-description` (#8668, merged). Running `origin/main`'s copy
   from a `postmerge-*` worktree reaped 8 of them. The Step 0 gate uses the plugin root
   that the loader substitutes, and here that is the root checkout's working tree. So when
   the root is not on `main`, **session-start maintenance runs whatever version of the
   plugin the root happens to have checked out.** The same run's `git pull` of main also
   failed (`Diverging branches`), for the same reason.

## Session Errors

1. **Merge livelock on #8611** (previous session). Recovery: waited it out, and the
   operator merged by hand. **Prevention:** #8683 (settle before syncing). Until then,
   sync only after the head's run is terminal.
2. **No agent merge path for a CI-editing PR** (previous session).
   Recovery: operator merge. **Prevention:** already enforced by `admin-merge-ready.sh`
   `UNTRUSTED-CI`. At mark-ready, check the diff for `.github/workflows|actions` and tell
   the operator up front.
3. **Chained `emit-review-trailer.sh && gh pr merge` denied** (previous session).
   Recovery: ran them separately. **Prevention:** the deny reason now names the fix
   (this PR).
4. **Nested session manifest made `resolve-regenerable-conflicts.sh` refuse** (previous
   session). Recovery: removed the stray file. **Prevention:** `**/` gitignore pattern
   (this PR).
5. **guard-vacuity-floor rejected a floor it could not classify** (previous session).
   Recovery: the floor was written in the standalone, stderr-reporting shape. **Prevention:**
   already meta-guard-enforced. The shape is recorded in item 5 above.
6. **`runnable_n` measured the host diff** (previous session). Recovery and
   **Prevention:** #8677.
7. **Session-start reaper ran a stale copy and kept merged worktrees** (this session).
   Recovery: ran `origin/main`'s `worktree-manager.sh cleanup-merged` from
   `.worktrees/postmerge-8679`, and removed the detached `postmerge-8611` by hand.
   **Prevention:** keep the root checkout on `main` (or a detached `origin/main`) between
   sessions. When the reaper's skip lines say `no merge evidence` for a branch whose PR
   `gh pr list --state merged` shows as merged, re-run from a current-main worktree before
   assuming #8496.
8. **`gh issue create` denied twice by the filing gates** (this session). First, a heredoc
   write and `--body-file` in one command: the gate reads the file before the heredoc runs.
   Second, a missing `meta/machinery` label. Recovery: wrote the body in a separate step and
   added the label. **Prevention:** the same pre-evaluation shape as item 3. Write body
   files in their own tool call.
9. **First gitignore fix was still root-anchored** (this session). Recovery:
   `git check-ignore -v` on the nested path, then `**/`. **Prevention:** verify every
   ignore change with `git check-ignore -v <the exact path that leaked>`.

## Key Insight

A PreToolUse hook sees the **whole** command line before **any** of it runs. So
"create the precondition && use it" in one Bash call fails against any gate that checks the
precondition. Items 3 and 8 share that shape. Split the producer and the consumer into separate tool calls.

## Tags

category: workflow-issues
module: ship
