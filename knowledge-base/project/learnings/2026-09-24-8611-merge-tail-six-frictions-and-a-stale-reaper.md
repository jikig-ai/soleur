---
title: "#8611's merge tail: six frictions after review, and a session-start reaper running a stale copy"
date: 2026-09-24
category: workflow-issues
module: ship
tags: [ship, merge-livelock, runner-backlog, admin-merge, untrusted-ci, pre-merge-hook, gitignore, session-manifest, session-rules-loader, guard-vacuity-floor, test-all-affected, worktree-reaper]
pr: 8685
refs: [8611, 8683, 8677, 8493, 8496]
---

# Learning: #8611's merge tail, and a session-start reaper that ran a stale copy

## Problem

PR #8611 (Inngest steps stream past Cloudflare's 524; spawns capped and throttled) was
opened as a draft at 13:44Z on 2026-09-23. It was marked ready at 19:47Z and merged at 22:21Z:
about six hours of implementation and review, then about 2.5 hours of merge tail. Six frictions
turned up after review. The next session (2026-09-24) found a seventh while cleaning up, and
its own review of this learning found that friction 4 had a bigger root cause.

## The frictions, and what each one needs

1. **Merge livelock under a GitHub-hosted runner backlog.** Ship Phase 7's BEHIND
   auto-sync (`plugins/soleur/scripts/sync-pr-behind.sh`) merges `origin/main` and pushes
   on every `BEHIND`. `ci.yml` cancels the in-flight PR run on each push, and the ruleset's
   `required_status_checks` is strict (it requires the branch to be up to date). The #8474
   recurrence is recorded in `2026-06-02-auto-merge-livelock-fast-moving-main.md` §Recurrence,
   two days earlier.

   **Until #8683 lands: sync only after CI on the current head has settled.**
   - Settling gives every head a verdict and stops burning runner time on cancelled runs.
   - Settling does **not** make the merge land. If a CI run takes longer than the gap between
     merges to `main`, the head is BEHIND again by the time it turns green.
   - The way out is admin-merge on a settled green run, an operator merge for an
     `UNTRUSTED-CI` PR, or merge queue (#4856).
   - A settled red run is fixed, not synced.
   - A cancelled run was never observed, so it is not a pass.
2. **A PR that edits CI has no agent admin-merge path.** #8611 touched
   `.github/workflows/apply-web-platform-infra.yml`, `infra-validation.yml` and
   `workspaces-luks-verify.yml`.
   - `admin-merge-ready.sh` therefore exits 1 (`UNTRUSTED-CI`), because the PR's own runs could
     mint any required context.
   - The normal queued auto-merge still works. What is lost is the fallback when the livelock
     sets in, and the operator merged it by hand.
   - This is already enforced. The gap was timing: the explanation lived only in
     `references/settle-then-admin-merge.md`, which ship loads in Phase 7, after the livelock
     has started.
   - Fixed here: ship Phase 6 step 6 now tells the operator at mark-ready.
3. **The pre-merge hook denies a chained `emit-review-trailer.sh && gh pr merge`.**
   - `.claude/hooks/pre-merge-rebase.sh` is a PreToolUse hook. It evaluates the whole command
     before any of it runs, so the trailer commit the first half would create does not exist yet.
   - The trailer commit is also local. The sibling `ship-unpushed-commits-gate.sh` denies a merge
     while it is unpushed.
   - Fixed here: the deny reason now says to run the trailer script on its own, then `git push`,
     then re-issue the merge. `pre-merge-rebase.test.sh` T5b pins that text.
4. **A stray `apps/web-platform/.claude/.session-manifests/*.json` blocked
   `resolve-regenerable-conflicts.sh`, and it was the visible sign of a rule blackout.**
   - `session-rules-loader.sh` set `REPO_ROOT` to the session's cwd verbatim. A session started or
     resumed in `apps/web-platform/` therefore wrote its manifest there, and it also read
     `apps/web-platform/AGENTS.rules.md`.
   - That file does not exist, so the session loaded **zero** rule bodies. The loader reported
     `loaded: 0 of ? rules — fail-safe: corpus missing`, with a remedy
     (`git checkout -- AGENTS.rules.md`) that fixes nothing because the file is not missing.
   - The untracked manifest made the resolver's clean-tree check refuse. A default
     `git status --porcelain` lists the untracked `.claude/` directory too; `-uall` is not the cause.
   - Fixed here: the loader now roots on `git -C "$CWD" rev-parse --show-toplevel`.
     `session-rules-loader.test.sh` Test 33 covers a subdirectory cwd: all N of N rules load and
     the manifest is written at the worktree root.
   - `.gitignore` also gains `**/.claude/.session-manifests/` as defence-in-depth against older
     loaders. It needs `**/` because a pattern with an inner slash is otherwise root-anchored;
     `git check-ignore -v` on the nested path caught a first attempt that lacked it.
   - The sibling `.claude/.*` sinks stay root-anchored. Their writers root on `BASH_SOURCE` or
     `CLAUDE_PROJECT_DIR`.
   - Treating the stray file as the bug would have silenced the only signal of the blackout.
     Three review agents converged on this.
5. **`guard-vacuity-floor.test.sh` needs a standalone counter floor.** The meta-guard counts a
   floor only if `floor_lines_of` matches it: an `if`/`elif` statement at line start using
   `[ ]`, `[[ ]]` or `(( ))` with `-lt|-le|-ge` or `<|<=|>=` over a declared counter.
   - A floor folded into a compound condition is invisible to it.
   - `classify_mutant` scores `FIRES` on a non-zero exit plus a floor-shaped sentinel on
     **either** stream (it reads both stdout and stderr). Printing the message to stderr is
     ADR-193's compliance requirement, not the scoring rule. The `:715` header comment
     ("sentinel on stderr") is stale.
   - Recommended shape: `if (( n < FLOOR )); then printf '[FATAL] floor …\n' >&2; exit 1; fi`.
6. **`test-all-affected.test.sh`'s `runnable_n` read the host's diff instead of the arm's forced
   diff.** Fixed by #8677 (merged 2026-09-24 02:48Z).
7. **(This session) The session-start `cleanup-merged` ran a stale `worktree-manager.sh`.**
   - The root checkout sat detached at `80a33a52fa`, a review-evidence twin commit, which
     predates #8493's commit-pinned gh-evidence reap.
   - That copy skips the GitHub query for any `[gone]` branch. Every squash-merged, auto-deleted
     branch printed `upstream is [gone] but no merge evidence` and was kept, including
     `fix-infra-privileged-doppler-description` (#8668, merged).
   - Running `origin/main`'s copy from a detached `postmerge-*` worktree reaped 8 of them.
   - Its `git pull` of main failed (`Diverging branches`). The reaper's `git checkout main` had
     silently failed because another worktree has `main` checked out, so the pull ran from the
     detached HEAD.
   - This is documented and deliberate. `go.md` Step 0 scopes its reap-capability gate to the
     `devin-cache` arm, and a stale `plugin-root-token` install "dispatches its own reaper"
     (ADR-179 A16).

## Session Errors

1. **Merge livelock on #8611** (previous session).
   - Recovery: settled, then the operator merged by hand.
   - **Prevention:** #8683 (settle before syncing). Settling alone does not converge (friction 1).
2. **No agent merge path for a CI-editing PR** (previous session).
   - Recovery: operator merge.
   - **Prevention:** already enforced by `admin-merge-ready.sh` `UNTRUSTED-CI`. Ship Phase 6
     step 6 now surfaces it at mark-ready (this PR).
3. **Chained `emit-review-trailer.sh && gh pr merge` denied** (previous session).
   - Recovery: ran them separately.
   - **Prevention:** the deny reason names the split trailer → push → merge sequence, pinned by T5b
     (this PR).
4. **Nested session manifest made `resolve-regenerable-conflicts.sh` refuse** (previous session).
   - Recovery: stray manifest cleared.
   - **Prevention:** the loader resolves the worktree root (this PR). The root cause was a
     zero-rule session, not the file.
5. **guard-vacuity-floor rejected a floor it could not classify** (previous session).
   - Recovery: the floor was written as a standalone floor.
   - **Prevention:** already enforced by the meta-guard. The shape is recorded in friction 5.
6. **`runnable_n` measured the host diff** (previous session).
   - Recovery and **Prevention:** #8677.
7. **Session-start reaper ran a stale copy and kept merged worktrees** (this session).
   - Recovery: ran `origin/main`'s `worktree-manager.sh cleanup-merged` from
     `.worktrees/postmerge-8679`, and removed the detached `postmerge-8611` by hand.
   - **Prevention:** keep the root checkout on a detached `origin/main` between sessions, not on an
     evidence commit. A live worktree usually holds `main` itself, so "check out main" is not
     available.
   - When skip lines say `no merge evidence` for a PR that `gh pr list --state merged` shows as
     merged, re-run from a current-main worktree before assuming #8496.
8. **`gh issue create` denied twice by the filing gates** (this session).
   - First denial: a heredoc write and `--body-file` in one command. The gate reads the file
     before the heredoc runs, which `guardrails.sh`'s deny reason already says.
   - Second denial: a missing `meta/machinery` label.
   - Recovery: wrote the body in a separate step and added the label.
   - **Prevention:** the same pre-evaluation shape as friction 3. Write body files in their own
     tool call.
9. **First gitignore fix was still root-anchored** (this session).
   - Recovery: `git check-ignore -v` on the nested path, then `**/`.
   - **Prevention:** verify every ignore change with
     `git check-ignore -v <the exact path that leaked>`.
10. **The first draft of this learning shipped three unmeasured claims** (this session).
    - The claims: "ready at 13:44Z" (the draft-creation time), "the sentinel must be on stderr",
      and a gitignore-only fix for friction 4.
    - Recovery: the review panel measured each one: the `ReadyForReviewEvent` time,
      `classify_mutant` on both streams, and the loader in a scratch repo.
    - **Prevention:** for every timestamp and mechanism a learning asserts, name the command that
      would falsify it and run it before committing.

## Key Insight

1. **A PreToolUse hook sees the whole command line before any of it runs.** So "create the
   precondition && use it" in one Bash call fails against any gate that checks the precondition.
   Friction 3 and session error 8 are the same shape. Split the producer and the consumer into
   separate tool calls.
2. **A stray file in the tree is a symptom report.** Ignoring it is not a fix until you know what
   wrote it there and why.

## Tags

category: workflow-issues
module: ship
