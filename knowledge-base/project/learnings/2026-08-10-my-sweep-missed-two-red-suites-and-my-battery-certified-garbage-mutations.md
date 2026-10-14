---
title: "My sibling-suite sweep missed two red suites, and my mutation battery certified garbage mutations"
date: 2026-08-10
problem_type: logic_error
component: shell_script
module: git-worktree
severity: critical
symptoms:
  - "slash-bearing branch worktrees nest three levels, run unleased, and are rm -rf'd by the orphan reaper"
  - "two CI suites red on the branch, neither surfaced by a targeted sibling-suite run"
  - "mutation battery reports SURVIVED for mutations that landed as garbage"
root_cause: verification_scoped_to_the_wrong_set
tags: [mutation-testing, test-vacuity, drift-guard, worktree, data-loss, verification]
issue: 7408
pr: 7415
synced_to: [review, git-worktree]
---

# My sibling-suite sweep missed two red suites, and my battery certified garbage mutations

## Problem

`worktree-manager.sh` derived the worktree **directory path** and the **session lease key** from
the raw git branch name, while `cleanup_merged_worktrees` assumed a slugified name and had said so
in a comment since PR #17. For any slash-bearing branch the mismatch was unattended destruction of
uncommitted work: `create ci/rule-metrics` nested three levels, `_validate_worktree_name` rejected
the slash so creation ran **unleased**, and the unregistered intermediate `.worktrees/ci` matched
no guard in `cleanup_orphan_worktree_dirs` and was `rm -rf`'d with the live worktree inside it.
Origin carried 29 slash-bearing branches, so it was reachable.

The fix — derive `safe_branch` once, use it for path and lease key, keep the raw name for
`git worktree add -b` — was correct and stayed correct. **The review found more defects in the
guards than in the fix**: 9 P1s across an 11-agent panel, five of them introduced by the fix.

## What actually went wrong

Every miss reduces to one sentence: **the verification was scoped to a set that did not contain
the thing it needed to see.**

### 1. The sweep enumerated directories, not consumers

I ran every `worktree-manager-*.test.sh` and reported "190 assertions, zero regressions." True,
and incomplete: I had scoped the enumeration to `plugins/soleur/test/`, `.claude/hooks/`, and
`scripts/`. Two suites that gate this file live elsewhere, and **both were red**:

- `apps/web-platform/test/git-lock-marker-telemetry.test.ts` — a drift guard that scrapes every
  `echo "SOLEUR_…` literal out of the shell script and asserts the extractor matches it. My new
  `SOLEUR_ORPHAN_SKIP_DESCENDANT` was not in `MARKER_RE`, so the marker was emitted into a
  channel nothing ingests.
- `plugins/soleur/skills/git-worktree/test/lease-protects-active.test.sh` — scenario 6 asserted
  that `create feat/probe6` runs **unleased**. That was the bug. The fix inverted the assertion.

A directory list is a guess about where consumers live. The consumers are wherever the changed
file's **symbols** are referenced, and that is a `git grep`, not a hand-picked path set.

### 2. The mutation battery reported SURVIVED for mutations that never happened as intended

Two rows came back `SURVIVED`. Both were false. The perl replacements contained `$_registered`
and `$safe_branch` — **perl interpolated them as its own variables**, so the substitution wrote
`[[ " == "/*/* ]]` rather than the intended predicate. The mutation changed bytes, so the
`diff -q` landing assertion passed; it just landed as garbage.

This is the documented "a mutation that does not land reports a false result" class in its
subtler form: it *did* land, incorrectly. `diff -q` answers "did the file change", never "did the
intended change occur". Re-run with a quoted heredoc so perl cannot interpolate, and both rows
flipped to `killed`.

### 3. An assertion I wrote during the fix pass could never match

A14 asserted the collision guard refuses, via `grep -qE '^\[0;32mSwitching to worktree'`. The real
line begins with a raw ESC byte, so `^` never matches — the pattern was unmatchable and the
assertion passed whether the guard fired or not. Confirmed by mutating the refusal out: still
green. The contract is the **exit status**, which is what an orchestrating agent branches on;
human-readable output is ANSI-coloured and a poor anchor.

### 4. A measurement of an open sibling PR has a shelf life of hours

The plan concluded #7407's hunks were "disjoint" from a real `gh pr diff` at `+289/-75`. A review
agent re-measured at `+443/-88`. By ship time it was **`+3070/-105`** and had grown into
`git-lock-marker-telemetry.ts` — the same `MARKER_RE` line this PR edits. Three measurements,
three answers, one moving target. The section was **superseded**, not amended: a botched conflict
resolution there drops a marker and fails **green**, since an unregistered marker is simply never
ingested.

### 5. Guards keyed on strings, not on the filesystem

The descendant guard compared `git worktree list` output against the glob path. That comparison
breaks whenever git reports the path differently — symlinked `.worktrees/`, a newline-truncated
porcelain record, a lost registry entry — and misses any nested clone at depth ≥ 2. All
reproduced destroying planted work. Replaced with `compgen -G "$dir"/*/.git`: ask the filesystem
whether anything below looks like a checkout, instead of asking the registry whether it was told.

### 6. A many-to-one transform made branch→directory non-injective for the first time

`tr '/' '-'` means `ci/foo` and `ci-foo` share a directory. The existence check was
directory-only, so `create ci/foo` on a box holding `.worktrees/ci-foo` printed "already exists",
switched into branch `ci-foo`, returned 0, and **never created `refs/heads/ci/foo`**. Verified
against `origin/main` that the pre-fix code creates the ref — so this branch introduced it.

The guard had to be scoped precisely: refuse only when slugification actually happened. A blanket
abort would have broken the `--yes` resume path that `one-shot`/`work` depend on, which is exactly
why plan revision R2 cut an earlier collision guard.

## Solution

```bash
# Ask the filesystem, not the registry.
if compgen -G "$dir"/*/.git >/dev/null 2>&1; then
  echo "SOLEUR_ORPHAN_SKIP_DESCENDANT dir=$(_sanitize_marker_field "${dir##*/}") reason=holds-checkout-on-disk"
  continue
fi

# An empty parse is a broken registry, not a repo with no worktrees.
# Counted in the loop: ${#arr[@]} errors under `set -u` on a declared-but-empty
# associative array (bash 5.3).
if [[ "$registered_count" -eq 0 ]]; then ... return 0; fi

# A floor, not equality — optional, because ~21 sibling suites call this.
print_results 36
```

Neutering `assert_eq` to `return 0` previously printed `Passed: 0 / ALL TESTS PASSED` and exited
0. CI reads the exit code, so that was indistinguishable from a clean run.

## Key Insight

**A green verification answers a question about the set you gave it.** Every failure here was a
correctly-executed check over the wrong set: the wrong directories, the wrong mutation, the wrong
anchor, a stale snapshot of a moving PR, the registry instead of the disk, one slash instead of
two. None of them looked like failures — they looked like passes, which is the whole problem.

Before believing a green signal, name the set it quantified over and ask what is outside it.

## Prevention

- Derive the consumer set with `git grep` over the changed file's **symbols**, repo-wide.
- Any `perl`/`sed` mutation containing `$` must use a quoted heredoc; assert the intended
  construct changed, not merely that bytes did.
- Never anchor an assertion on ANSI-coloured output; assert the exit status.
- Re-measure an open sibling PR immediately before merge; supersede a stale conclusion.
- Register every new `SOLEUR_*` marker in `MARKER_RE` in the same PR.
- Give every accumulate-then-exit suite an assertion floor.

## Session Errors

1. **Sibling-suite sweep scoped to three directories** — missed two CI-red suites.
   Recovery: agent panel found both; ran them directly and fixed. **Prevention:** derive the
   consumer set by grepping the changed file's symbols repo-wide, not from a directory list.
2. **Ran the drift guard from the bare root and got a false PASS** — the bare root holds stale
   synced copies. Recovery: re-ran from the worktree, which failed correctly.
   **Prevention:** already covered by `hr-when-in-a-worktree-never-read-from-bare`; the tell is a
   result that disagrees with an agent's measurement.
3. **Mutation battery reported two false SURVIVED** (perl variable interpolation).
   Recovery: re-ran with a quoted heredoc; both flipped to killed. **Prevention:** see above.
4. **Launched the full-suite exit gate before the review fixes**, then nearly read its result as
   valid for the post-fix tree. Recovery: killed it (resolving PIDs by `/proc/<pid>/cwd` so
   sibling worktrees were spared) and relaunched against the clean tree.
   **Prevention:** already documented in `work/SKILL.md`; the gate describes the tree it was
   launched against.
5. **My own new assertion was vacuous** (ANSI anchor). Recovery: mutation-tested the guard, found
   it survived, re-pointed the assertion at the exit status. **Prevention:** see above.
6. **Three PR-introduced regressions** (slug collision, `copy-env` traversal, `switch` unreachable).
   Recovery: all fixed inline with covering arms. **Prevention:** when a transform becomes
   many-to-one, enumerate the verbs that build a path from operator input and check each.
7. **New markers emitted unsanitized and unregistered.** Recovery: extracted
   `_sanitize_marker_field` from the failure summary that already carried the rule.
   **Prevention:** the drift guard catches registration; sanitization needs the shared helper.
8. **Plan asserted "no server-side surface"** and cited a sentinel (`SOLEUR_WORKTREE_NAME_UNSAFE`)
   existing nowhere. Recovery: corrected both. **Prevention:** grep every sentinel a plan names.
9. **`tsc` thrashed 55 minutes** on a saturated box; **a background watcher was reaped (exit 144)**.
   Recovery: killed and relaunched detached; read the rc file rather than the notification.
   One-off, environmental.
10. **Forwarded from `session-state.md`:** API cutoff mid-deepen (resumed, not re-run);
    `soleur:deepen-plan` skipped by the planning subagent (re-run inline by the parent, and it
    caught the AC13 defect); a false load-bearing premise that propagated into two domain reviews;
    two published measurement commands that did not reproduce as written.

## Related

- `2026-07-16-a-mutation-battery-only-covers-what-you-mutate.md`
- `2026-08-04-a-proof-of-red-pinned-to-a-moving-ref-consumes-its-own-fix.md`
- `2026-07-15-narrowing-is-not-anchoring-and-a-documented-class-recurred-four-times-in-one-pr.md`
- #5454 (zero-commit work branch reaped), #7102 (orphan reaper honest reporting), #7373 (create unleased)
