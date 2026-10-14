---
module: Plugin
date: 2026-09-21
problem_type: logic_error
component: git-worktree
symptoms:
  - "cleanup-merged reaped nothing: squash-merged branches whose remote was auto-deleted are [gone], the gh merged-PR query skipped [gone] branches, and the #8418 merge-evidence guard no longer accepts [gone] alone"
  - "The one-line fix (drop gone_branches from the gh-loop exclusion) was green, TDD'd and RED-proven, yet let a name-only `gh pr list --head <b> --state merged` license `git branch -D` over commits made after the merge"
root_cause: evidence_keyed_on_name_not_commit
severity: high
tags: [worktree-manager, cleanup-merged, merge-evidence, destructive-path, review-panel]
---

# Widening who reaches an evidence check inherits what the evidence is keyed on

## Problem

Issue #8490: in `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`, the
`gh_merged_branches` builder skipped any branch already in `gone_branches`. That was a sound
choice when it was written (660182b90), because back then `[gone]` alone licensed a reap. Then
#8418 (9768645ad, 2026-09-21) added a merge-evidence guard that no longer accepts `[gone]` alone.
The two halves stopped agreeing. A squash-merged branch whose remote was auto-deleted (this
repo's default for every PR) is `[gone]` and not an ancestor of main, so it reached the guard
with no evidence and was never reaped.

## Solution

1. Drop `gone_branches` from the gh-loop exclusion and keep `merged_branches`, so `[gone]`
   worktree branches get asked about on GitHub (commit 34c22fa05; test arm A14).
2. **Review P1, where four seats converged:** the gh query was `--head <name> --state merged`.
   That answers "some PR with this NAME merged", not "these commits are on main". Before the fix
   no `[gone]` branch reached this check. After it, the cohort that cannot push
   (remote deleted) could be force-deleted over local commits made after the merge, or over a
   reused or fork head name. The evidence is now pinned: the branch counts only if its local tip
   is an ancestor of the `headRefOid` of a merged PR with `isCrossRepository == false`. A tip that
   moved, or a merged head that is not present locally, fails closed with an explicit `(skip)`
   line (commit 4ef807c56; test arm A15).
3. A failed gh query now prints `SOLEUR_CLEANUP_GH_QUERY_FAILED branch=… rc=…` on stdout instead
   of reading as "not merged". That silent read reproduces the #8490 symptom whenever gh is
   down.
4. One suite-wide `gh` stub, argv-exact (exit 64 on drift), replaces two partial per-arm stubs.
   It answers by running the SUT's own `--jq` expression through real `jq` over a per-arm JSON
   fixture, so the `isCrossRepository` filter is under test and not re-implemented. Arms without their own stub (A5, M3)
   no longer reach the real `gh`.

## Key Insight

**When a fix widens WHICH items reach an existing evidence check, the fix inherits every weakness
of what that evidence is keyed on, and those weaknesses matter more for the newly admitted
cohort.** The original check was only as strong as its population needed. Branches whose remote
still existed were pushed, so a name match coincided with a commit match. `[gone]` branches are
exactly the ones that cannot push, so name and commit diverge. Before admitting a new cohort to
a destructive path, ask: *what is the evidence keyed on (name, id, timestamp, commit), and is
that key still bound to the thing being destroyed for the cohort I am adding?* The RED/GREEN
tests for the fix cannot answer this, because they fixture only the cohort the fix was about.

## Session Errors

1. **The planned and implemented fix keyed merge evidence on the branch name.** Recovery: review
   P1 (security, data-integrity, code-quality and architecture converged); pinned the evidence to
   `headRefOid` + same-repo; added A15. **Prevention:** a plan that widens the population reaching
   a destructive gate's evidence must state what the evidence is keyed on and prove the key still
   binds for the new cohort (routed to `plan/references/plan-sharp-edges.md`).
2. **The mutation-battery `revert-fix` anchor matched two sites** (the gh loop and the guard use
   the same `$merged_branches` membership test). Recovery: the `count == 1` assert refused the row
   (NOT-LANDED), and it was re-run with a `_wt_branch`-anchored unique string. **Prevention:**
   keep the `count == 1` assert in every scripted mutation; anchor on a token unique to the site.
3. **`gh issue view 8440` ran from the home CWD** after the per-call CWD reset and failed with
   "not a git repository". **Prevention:** prefix every `gh`/`git` call with the worktree `cd`.
4. **`gh pr comment 8492` failed: #8492 is an issue, not a PR,** although the brief called it a
   "parallel PR". **Prevention:** resolve a `#N` with `gh issue view`/`gh pr view` before
   acting on it as either kind.
5. **The plan's Test Scenarios said "A9 must stay green without changes",** and review replaced
   A9's stub with the shared stub. Recovery: disclosed at QA. **Prevention:** phrase scenario
   invariants as behaviour ("A9's assertions stay green"), not as file immutability.
6. **The `TEST_GROUP=scripts` gate was refused (rc=4)** because two sibling worktrees were running
   the full gate. Recovery: a substitute set of consumer suites, fixture ratchets,
   guard-vacuity-floor and repo-wide shell lints; CI's required `test` context covers the shards.
   **Prevention:** already by design (#7553); run `--capacity` first.
7. **A green Bash call reported exit 1** because a trailing `[ $rc -ne 0 ] && tail` evaluated
   false. **Prevention:** end a verification loop with an explicit `echo done`, or read per-suite
   `RC=` lines, never the call's status.

## Tags
category: logic-errors
module: git-worktree
