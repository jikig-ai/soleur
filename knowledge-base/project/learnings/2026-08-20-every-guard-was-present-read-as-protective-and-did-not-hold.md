---
title: "Every guard was present, read as protective, and did not hold"
date: 2026-08-20
category: test-failures
module: test-harness
tags: [vacuity, guard-design, fail-open, mutation-testing, verification-instruments, data-loss]
issues: [7580, 7553, 7652, 7673, 7546]
pr: 7616
---

# Every guard was present, read as protective, and did not hold

## Problem

A test suite committed into live developer worktrees and destroyed several hours of
uncommitted work. Four escapes across three sessions in under two hours. **Every suite
reported green throughout** — the escape has no failing-test symptom at all.

`plugins/soleur/skills/git-worktree/test/lease-protects-active.test.sh` silences its
`git worktree add` failures with `>/dev/null 2>&1`, then does an unguarded
`( cd "$fixture"` in a file that runs `set -uo pipefail` **without `-e`**. When the
fixture directory does not exist, `cd` fails, **the subshell continues**, and its
`git add` / `git commit` — or, at two sites, `worktree-manager.sh cleanup-merged` —
execute in the caller's CWD.

Fixture commits `victim change`, `victim2 change`, `v9 change`, `v12 change` landed on
live feature branches AND on local `main`; one worktree was checked out to `main`.

## The generalisable finding

Not "a `cd` needed a guard". The finding is:

> **Every guard in this incident was present, read as protective, and did not hold.
> Each was caught only by MUTATING it and watching it accept — never by reading it.**

Reading is what everyone had done to each of them: the authors, the reviewers, and the
sessions that shipped them. Twelve instances in one day across four sessions, and the
majority were in **verification instruments** rather than in code under review — which
is exactly why nothing caught them. Nothing was measuring the instruments.

### The catalogue (all measured, none asserted)

| # | The guard | How it failed |
|---|---|---|
| 1 | the suite's own `cd` sites | unguarded under `set -u` without `-e`; subshell continued |
| 2 | prior partial hardening | 2 of 7 sites carried "Guarded cd" comments — the file *read* as protected |
| 3 | `grep -c '<guard phrase>'` | returned 5 when the answer was 7; the reaper guards were worded differently |
| 4 | a fix-sweep keyed on `"twice"` | missed a site reading `"two of five"` |
| 5 | a merge self-check excluding `&&` | not `\|\|` — would have false-RED'd a *correct* guard |
| 6 | that same self-check | inspected 7 of 25 `cd` sites while claiming to refuse on ANY bare cd |
| 7 | the proposed exploit for (6) | a dropped backslash is a bash **syntax error** — refuted by running it |
| 8 | the first repair of (6) | exempted any line containing `if`; but `if (` tests the SUBSHELL, not the cd |
| 9 | `[FATAL] A SUITE WROTE TO THE LIVE REPOSITORY` | claimed the *repository* was protected; only *gate runs* are |
| 10 | **the containment helper itself** | **failed OPEN** — see below |
| 11 | a mutation arm | never landed (wrong shard); reported `rc=0, 7/7` — a green measuring nothing |
| 12 | a review arm | void — relocated harness lost its `BASH_SOURCE` root; `FAIL: 21` was the harness, not the subject |

### (10) is the one that matters

The containment check was `case "$top" in "$TMP_REAL"|"$TMP_REAL"/*) return 0 ;; esac`.
With `TMP_REAL` **empty**, the second pattern degrades to `/*` — which matches every
absolute path. The guard returns 0 for a **live repository**.

```
*** ACCEPTED — guard returned 0 for /var/tmp/failopen/live ***
```

And inside the suite, that state runs **`40 passed, 0 failed`**.

> **A guard that accepts everything is indistinguishable from a healthy run.**

It had passed review here and shipped in three commits. It was caught by another session
reviewing their own copy — by asking *"how does this fail OPEN?"* and then mutating it.

## Solution

Two layers, deliberately.

**Site level** — `cdx()` at all seven sites:
- refuses and **names the live repository** it declined to write to;
- pins the **resolved** `git rev-parse --show-toplevel` inside the fixture root, because
  `cd` SUCCEEDING is not containment: a directory that exists but is not a repo leaves
  git walking UP to the enclosing one;
- asserts `TMP_REAL` is absolute and marks it `readonly` (closes the fail-open);
- guards `mktemp -d`, so an empty `$TMP` cannot resolve fixture paths against `/`;
- sets a marker checked BEFORE the vacuity floor — `exit 90` ends only the *subshell*.

**Boundary level** — in `scripts/test-all.sh`: snapshot `HEAD` + `git status --porcelain`
after `tc_acquire` and before the summary; fail loudly on a delta.

Characterised by the **invariant**, not by a fingerprint of today's fixture. Detection by
commit message, by the pinned `2025-01-01` committer date, or by author each keys on an
incidental property and **fails silently clean** against a future fixture that differs.
*"The gate wrote to the repo"* does not.

## Key Insight

**Ask of every guard: how does this fail OPEN? Then mutate it and watch it accept.**

Three corollaries, each earned here:

1. **A guard narrower than the claim it carries is the default outcome, not the exception.**
   Six of the twelve were guards whose *message* was broader than their *predicate*.
2. **Partial hardening is worse than none** — the file reads as protected to anyone who greps it.
3. **Verify the instrument before reading its verdict.** A mutation that did not land,
   and a harness that lost its own root, both produce confident wrong answers.

## Detection (for a past hit)

The fixture pins `GIT_COMMITTER_DATE=2025-01-01`, which **also spoofs how the reflog
renders** — so scanning by time ordering finds nothing.

```bash
git reflog -25 | grep -E "victim|v9 change|v12 change|checkout: moving .* to main"
git reflog --date=iso -40 | grep '2025-01-01 00:00:00'   # message-independent
git diff --name-only origin/main...HEAD                  # stray a.txt-d.txt
git log --format='%an %ae' origin/main..HEAD | sort -u   # fixtures are `t <t@t>`
```

To **date** an incident use loose-object mtimes — the only clock the fixture cannot spoof.
They reconstructed four escapes across three sessions and **falsified one session's
proposed root cause** (their escape predated the thing they blamed by 25 minutes).

## Session Errors

1. **Plan subagent stalled at 600s** before its summary. **Recovery:** recovered from the
   on-disk artifact. **Prevention:** already covered by resume-from-artifact guidance.
2. **The recovered plan was internally contradictory** — ACs/Files/Tests/ADR still described
   a superseded design. **Recovery:** 10 reconciling edits before `/work`. **Prevention:**
   treat a stalled agent's artifact as unverified; reconcile before use.
3. **`git commit` hung ~2 min** — `ssh-keygen -Y sign` opened an askpass dialog; the gcr
   agent listed the key but could not sign. **Recovery:** operator `ssh-add` into a dedicated
   agent + `-c user.signingkey="key::<pubkey>"`. **Prevention:** probe signing with a
   throwaway file before a long commit sequence.
4. **A test suite destroyed ~3h of uncommitted work.** **Recovery:** `git branch -f main
   origin/main`, reset the branch, replay from `/var/tmp` backups. **Prevention:** `cdx()`
   + the boundary check; and commit each verified unit immediately.
5. **`gh pr edit --body-file` chained after a TLS-timed-out `gh pr view`** published an empty
   file and **wiped the PR body**. **Recovery:** restored from a local copy. **Prevention:**
   floor on size AND on expected markers — a *truncated* body passes a non-empty check while
   dropping the `Closes` line.
6. **`pkill -f '<pattern>'` matched its own command line** and killed the shell. **Recovery:**
   none needed (work was pushed). **Prevention:** `plugins/soleur/scripts/lib/proc.sh`.
7. **An apostrophe inside an `awk '…'` comment** closed the block. **Recovery:** reworded.
   **Prevention:** already in work/SKILL.md; grep `'` after editing an awk block.
8. **A comment quoting `tc_acquire "test-all"` verbatim** broke a fixture requiring that
   literal to be unique — the suite reported 40/51 with its own code untouched. **Recovery:**
   described the anchors without quoting them. **Prevention:** `cq-assert-anchor-not-bare-token`
   applies to COMMENTS — a comment naming a token a parser keys on is part of that parser's input.
9. **Declared a variable inside the window the two SUT-driving suites splice over** — `set -u`
   aborted them (77/0 → 40/37). **Recovery:** declared at top level, initialised to the
   NOT-MEASURED value. **Prevention:** ADR-195 Decision 7 — a change to `test-all.sh` is a
   change to those suites' SUT, and CI cannot see it (one shard, clean tree).
10. **A mutation arm that never landed** — wrong shard, so the probe never ran; `rc=0, 7/7`.
    **Recovery:** re-ran on the shard that globs it. **Prevention:** assert the mutation LANDED
    (diff against a pristine backup) AND that the mutated code executed.
11. **A review arm that was void** — relocated a peer's suite to `/var/tmp`, so its
    `BASH_SOURCE`-resolved `REPO_ROOT` left the repo; `FAIL: 21`. **Recovery:** re-ran in a
    proper worktree (40/0). **Prevention:** run a relocated harness in place, or carry what it
    resolves relative to itself.
12. **My containment guard failed open** (empty `TMP_REAL` → `/*`). **Recovery:** assert the
    post-condition; `readonly`. **Prevention:** the key insight above.
13. **My merge self-check excluded `&&` but not `||`** — would have false-RED'd a correct
    merge. **Recovery:** keyed on whether the failure is handled. **Prevention:** a self-check
    that reds a CORRECT state teaches people to bypass it.
14. **That self-check inspected 7 of 25 sites** while claiming all. **Recovery:** logical-line
    evaluation (comments stripped, continuations joined). **Prevention:** count what the
    detector INSPECTS against the population it CLAIMS.
15. **`git add` with a variable unset in a new shell** staged nothing; the commit reported
    "no changes added". **Recovery:** re-staged explicitly. **Prevention:** one-off — Bash tool
    calls do not share shell variables.
16. **ADR-194 ordinal collision** — `main` landed a different ADR-194 mid-flight. **Recovery:**
    renumbered to ADR-195, sweeping by CLAIM not by literal (3 of 9 references meant the OTHER
    record; a blanket `sed` would have silently repointed them). **Prevention:** re-check the
    ordinal against freshly-fetched `origin/main` immediately before merge.
