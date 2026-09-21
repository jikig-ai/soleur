---
title: "fix: cleanup-merged reaps nothing — query gh merge state for [gone] worktree branches"
date: 2026-09-21
slug: fix-cleanup-merged-gone-branches-gh-query
branch: feat-one-shot-8490-cleanup-merged-gone-gh-query
issue: 8490
closes: 8490
type: bug
lane: single-domain
---

# fix: cleanup-merged reaps nothing — query gh merge state for [gone] worktree branches

## Overview

`cleanup_merged_worktrees` in `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`
builds three branch sets. Two of these combine to cause the bug:

- The `gh_merged_branches` builder (line ~2809) skips `gh pr list --state merged` for any
  worktree branch already in `gone_branches` **or** `merged_branches`. This shortcut dates from
  when a `[gone]` upstream was enough to justify a reap.
- The `SOLEUR-GUARD-MERGEEVIDENCE` block (line ~3050, added in #8418) now accepts only
  `merged_branches` or `gh_merged_branches` as proof. `[gone]` alone gives no license to reap.

In this repo, PRs are squash-merged and GitHub then auto-deletes the branch. So every such
branch is `[gone]` and never `--merged main`. The builder never asks GitHub about it, and the
guard skips it. The result is that the reaper's main cohort is never reaped. This fails safe
(nothing is deleted wrongly), but worktrees and branches pile up. First observed live on
2026-09-21 on PRs #8458 and #8459.

**Fix:** remove `gone_branches` from the builder's exclusion and keep `merged_branches`. A
branch that is already an ancestor of main needs no API call, and a `[gone]` branch now gets
its merge check. This is a one-line change. The guard stays the same.

## Enhancement Summary

**Deepened on:** 2026-09-21. This was a minimal deepen pass, as the caller asked: a one-line fix
plus test rows, so there was no agent fan-out.
**Gates run:** 4.6 User-Brand Impact (pass), 4.7 Observability (pass), 4.8 PAT sweep (no hits),
4.11 Guard Contract (`lint-guard-contract.py` green; the assembly names the gh-query loop
chokepoint, not its members), and 4.9/4.10/4.55/4.5 (did not trigger).

### Key corrections

1. **The sentinel sha is SHORT.** `_tip_sha=$(git rev-parse --short …)` is at
   `worktree-manager.sh:~3134`. The draft assertion `sha=[0-9a-f]{40}` would never have
   matched, and A14b would have stayed RED even after the fix. A14b now compares against the
   branch's short tip, captured before the run.
2. **`remote=no` is the expected value for the gone cohort.** The remote delete checks
   `git ls-remote --exit-code --heads origin <b>` first (`:~3105`). An upstream that has already
   been deleted is not deleted again, so the reap line reads `local=yes remote=no`, and no
   `SOLEUR_WORKTREE_REAP_PARTIAL` is emitted.
3. **Skips that happen before the guard.** The worktree cohort goes through the commit-age hold
   (`(skip) … recent commit (<10min)`) and the uncommitted-changes hold before it reaches the
   merge-evidence block. The A14 fixtures must be backdated and have clean worktrees, or A14d's
   `no merge evidence` line is never printed.

## Research Insights

**Premise Validation.** #8490 is OPEN (`gh issue view 8490`). Both cited sites exist on this
branch, at `worktree-manager.sh:2809` (the exclusion) and `:3050-3062` (the guard). The guard's
comment block (`:3032-3038`) says in so many words that `gone_branches` "licenses nothing", so
the combination is exactly as the issue describes. The premise holds.

**Property List.**

1. A squash-merged branch whose upstream is `[gone]`, that still has a worktree, and whose PR
   GitHub reports as merged is reaped. The reap emits `SOLEUR_WORKTREE_REAPED branch=… sha=…`.
2. A branch that is `[gone]` but has no merge evidence (gh reports 0) is still skipped before
   any write, whether or not it has a worktree.

**Cut List.** None. The ask names one mechanism (narrowing the exclusion), and nothing on main
already provides property 1. `merged_branches` stays in the exclusion because ancestry is
already proof, so the gh call would be wasted.

**Relevant files.**

- `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh:2787-2818`: the set builders.
- `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh:3050-3062`: the guard (unchanged).
- `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh:3159`: the sentinel
  `SOLEUR_WORKTREE_REAPED branch=… sha=$_tip_sha local=yes remote=…`.
- `plugins/soleur/test/worktree-manager-cleanup-merged-no-worktree.test.sh`: the suite from #8400
  and #8418. Rows that already exist:
  - A9: squash-merged, worktree, gh stub. The upstream is not deleted, so the branch is never
    `[gone]`. That is why this arm missed the bug.
  - A10: `[gone]`, unmerged, **no worktree**, no gh stub.
  - Helpers: `mk_squash_merged_branch`, which backdates the commit so the worktree commit-age arm
    does not hold the branch silently; `arm_reaper`; `run_reaper`; `local_branch_exists`.
  - The anti-vacuity floor is `MIN_ASSERTIONS=33` (line ~813).

**Why the existing rows missed it** (quoted in the issue): no row combined `[gone]` with a
gh-merged stub.

**Known and out of scope.** The gh query loop reads only `git worktree list --porcelain`, so a
squash-merged `[gone]` branch with **no** worktree still has no merge evidence and is skipped.
That fails safe, and the issue scopes the fix to the worktree case. It is recorded here and not
fixed.

## Files to Edit

- `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh`: line ~2809. Change

  ```bash
  if [[ $'\n'"$gone_branches"$'\n'"$merged_branches"$'\n' == *$'\n'"$_wt_branch"$'\n'* ]]; then continue; fi
  ```

  to

  ```bash
  if [[ $'\n'"$merged_branches"$'\n' == *$'\n'"$_wt_branch"$'\n'* ]]; then continue; fi
  ```

  Also add a one-line comment saying why `[gone]` is **not** excluded any more (#8490: since
  #8418, `[gone]` is not merge evidence, so a gone branch needs its gh answer). Update the
  stale "(1) [gone]" wording in the header comment at `:2785` if it still claims `[gone]` is
  enough.
- `plugins/soleur/test/worktree-manager-cleanup-merged-no-worktree.test.sh`: add arm **A14**
  after A13 and before `S.` (line ~789), then raise `MIN_ASSERTIONS` by the number of
  assertions A14 adds.

## Files to Create

None.

## Implementation Phases

### Phase 1: RED test (A14)

Build one fixture repo (`mk_repo "$TMP/a14"`) holding **two** branches. Both are
squash-merged-shaped with a backdated commit (via `mk_squash_merged_branch`), both have a
worktree, and both then get `push origin --delete <b>` + `fetch -q --prune --no-tags` so that
their upstream is `[gone]`:

- `feat-a14-merged`: the gh stub reports the PR merged (`1`).
- `feat-a14-unmerged`: the gh stub reports `0`. This is the `[gone]`-only case with a worktree.
  (The squash commit on main is irrelevant here: without gh evidence and without ancestry it
  must be skipped. Leaving `mk_squash_merged_branch` out for this branch and building a
  backdated unmerged commit, the way A10 does, is also acceptable and is the more literal shape.)

The gh stub keys on `--head <branch>`. It prints `1` only for `feat-a14-merged` and `0` for any
other branch. It appends each `--head` value to `$TMP/a14-gh.log`, and it exits 64 on any other
call shape (the same contract as the A9 stub). Run the reaper with
`PATH="$A14_BIN:$PATH" run_reaper …`.

Assertions:

- **A14a**: `feat-a14-merged` is gone locally.
- **A14b**: `$TMP/a14.log` contains the exact line prefix
  `SOLEUR_WORKTREE_REAPED branch=feat-a14-merged sha=$A14_TIP local=yes remote=no`, where
  `A14_TIP=$(fgit -C "$A14/clone" rev-parse --short feat-a14-merged)` is recorded **before** the
  reaper runs. The reaper records `git rev-parse --short` (`worktree-manager.sh:~3134`), so this
  is an abbreviated sha, not 40 hex characters. Comparing it with the tip captured before the
  run proves that the `sha=` field can be used for recovery (`git branch <b> <sha>`), which a
  shape regex does not. `remote=no` is expected, because the upstream was already deleted, so
  `ls-remote --exit-code` fails and no remote delete is attempted.
- **A14c**: `feat-a14-unmerged` still exists locally, its worktree directory still exists, and
  its remote-side state is unchanged (it has no remote ref to delete; checking that the local
  ref and the worktree are kept is enough).
- **A14d**: `$TMP/a14.log` contains `(skip) feat-a14-unmerged - upstream is [gone] but no merge evidence`.
- **A14e** (own dispatch): `$TMP/a14-gh.log` contains **both** `feat-a14-merged` and
  `feat-a14-unmerged`. This shows the gh query ran for `[gone]` branches and was not
  short-circuited.

Before the fix, A14a, A14b and A14e go RED. A14c and A14d pass both before and after, which is
the kept skip behaviour. Run the suite to confirm the RED result against the current script.

### Phase 2: GREEN fix

Apply the one-line exclusion change. Then re-run:

- `bash plugins/soleur/test/worktree-manager-cleanup-merged-no-worktree.test.sh`
- `bash plugins/soleur/skills/git-worktree/test/lease-protects-active.test.sh`
- `bash plugins/soleur/skills/git-worktree/test/orphan-reaper-honest-count.test.sh`

The last two drive the same reaper. Check that none of their fixtures now make a real `gh`
call for a `[gone]` worktree branch. If one does, the real `gh` fails outside a GitHub remote,
`|| echo "0"` swallows the failure, and the branch is skipped. That is safe, but it could
change an arm's verdict, so confirm the counts are unchanged.

## User-Brand Impact

**If this lands broken, the user experiences:** one of two things. Either merged worktrees and
branches keep piling up (today's state, which is safe), or, if the guard were weakened by
mistake, an unmerged `[gone]` branch is force-deleted and its commits are lost. A14c and A14d
together with A10 pin the second case.
**If this leaks, the user's workflow is exposed via:** no exposure vector. This is local git
housekeeping, and the only new outbound call is the existing read-only `gh pr list` query.
**Brand-survival threshold:** none. threshold: none, reason: a local developer-tooling reaper
whose deletion guard is unchanged; the fix only adds an existing read-only evidence query for
`[gone]` branches.

## Observability

```yaml
liveness_signal:
  what: SOLEUR_WORKTREE_REAPED sentinel line per reaped branch on cleanup-merged stdout
  cadence: every cleanup-merged run (session start / postmerge)
  alert_target: operator terminal (local CLI tool; no server surface)
  configured_in: plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh:3159
error_reporting:
  destination: stdout "(skip) <branch> - upstream is [gone] but no merge evidence" line
  fail_loud: skip is printed unconditionally (not verbose-gated)
failure_modes:
  - mode: gone branch never gh-queried (this bug)
    detection: A14e gh-stub invocation log; live — skip lines for branches whose PR is MERGED
    alert_route: test suite RED in CI
  - mode: guard weakened to accept [gone] alone
    detection: A10a / A14c
    alert_route: test suite RED in CI
logs:
  where: cleanup-merged stdout (captured by the invoking session)
  retention: session transcript
discoverability_test:
  command: grep -c "SOLEUR_WORKTREE_REAPED branch=" plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh
  expected_output: "1"
```

## Guard Contract

### Guard 1: A14 ([gone] + worktree + gh-merged is reaped; [gone]-only is skipped)

**Property.** Every worktree branch that is not already an ancestor of main is checked against
GitHub for merge state. If it is merged it is reaped, with a `sha=` sentinel. If it is not
merged it is kept, whether or not its upstream is `[gone]`.

**Assembly.** There is one chokepoint: the `while … done < <(git worktree list --porcelain)`
loop that builds `gh_merged_branches` (`worktree-manager.sh:~2803-2815`), with its exclusion
test at `:2809`. The consumer is the `SOLEUR-GUARD-MERGEEVIDENCE` block (`:3050`), which reads
only `merged_branches` and `gh_merged_branches`. `gone_branches` reaches the guard only through
`all_stale_branches`, which is candidacy, not evidence.

**Mutation matrix.**

| # | Mutation | Must go RED |
|---|---|---|
| 1 | Put `$gone_branches` back into the `:2809` exclusion (revert the fix) | A14a, A14b, A14e |
| 2 | Let the guard accept `gone_branches` as proof (add a third `elif` arm) | A14c, A14d, A10a |
| 3 | Second member: the gh loop `break`s after the first branch it queries (a check that stops at the first member) | A14e (one `--head` missing from the log); A14a or A14b, depending on porcelain order |
| 4 | Own dispatch: remove the stub from `PATH` (the real gh answers 0 outside GitHub) | A14a, A14e |

**Harness rows.**

- The suite edit that must go RED: the stub keeps no invocation log (the `>> a14-gh.log` line is
  deleted), so A14e fails. This means A14e cannot pass on an empty log.
- A must-PASS input that is not the canonical case: `feat-a14-unmerged`, which is `[gone]` and
  has a worktree but gh says 0, must PASS as "kept". Only a must-PASS row can catch a guard
  that rejects everything or reaps everything.

**Anchor.** Not applicable. There is no stored value. The suite checks behaviour directly
against a fixture repo that is synthesized fresh on every run.

## Open Code-Review Overlap

To be filled when the work phase runs the Phase 1.7.5 query against the two files above. Record
`None` if there are no matches.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected. This is an infrastructure/tooling change: a one-line fix
to a local git reaper plus test rows.

## Test Scenarios

- A14 (new) as described in Phase 1.
- A9 and A10 (existing) must stay green without changes.
- Sibling suites `lease-protects-active.test.sh` and `orphan-reaper-honest-count.test.sh` must
  stay green.

## Sharp Edges

- The new arm's commits **must be backdated** (use `mk_squash_merged_branch` with its default
  age, or backdate as A10 does). A fresh commit gets held by the worktree commit-age arm, whose
  skip line is `verbose`-gated. The arm then prints nothing, and A14a fails with a misleading
  cause (see the comment on `mk_squash_merged_branch`).
- Raise `MIN_ASSERTIONS` by exactly the number of assertions A14 adds. Put the threshold on the
  line immediately above its `if`, as the floor comment requires.
- The gh stub must key on `--head <branch>`. A stub that answers `1` to every `--state merged`
  call (the A9 stub) would reap `feat-a14-unmerged` too, and it cannot test property 2.
- Do not touch `plugins/soleur/skills/ship/SKILL.md` or `plugins/soleur/skills/postmerge/SKILL.md`,
  because the parallel PR #8492 edits them.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6.

## Acceptance Criteria

- [ ] `worktree-manager.sh` exclusion at `:~2809` tests only `merged_branches`:
  `awk '/local gh_merged_branches=""/{f=1} f; f && /git worktree list --porcelain/{exit}' plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh | grep -c gone_branches`
  prints `0` (it printed `1` before the fix).
- [ ] Arm A14 exists in `plugins/soleur/test/worktree-manager-cleanup-merged-no-worktree.test.sh`
  with assertions A14a to A14e. A14a, A14b and A14e were observed RED against the unfixed script
  before the fix was applied.
- [ ] A14b asserts `SOLEUR_WORKTREE_REAPED branch=feat-a14-merged sha=<pre-run short tip> local=yes remote=no` (short sha, compared with `rev-parse --short` captured before the run).
- [ ] The `[gone]`-only skip is covered for both shapes: A10 (no worktree) and A14c/A14d (with a
  worktree, gh=0).
- [ ] `MIN_ASSERTIONS` is raised to match, and the full suite exits 0.
- [ ] `lease-protects-active.test.sh` and `orphan-reaper-honest-count.test.sh` exit 0.
- [ ] No edits to `plugins/soleur/skills/ship/SKILL.md` or `plugins/soleur/skills/postmerge/SKILL.md`.
- [ ] The PR body contains `Closes #8490`.
