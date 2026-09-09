---
title: "Every instrument I built to check my own work could not tell 'clean' from 'never ran'"
date: 2026-09-07
issue: 3210
pr: 7828
category: workflow-issues
module: verification
tags: [verification, anti-vacuity, exit-codes, worktrees, legal-documents, merge-strategy]
---

# Every instrument I built to check my own work could not tell "clean" from "never ran"

## Problem

PR #7828 spent 38 review findings removing one defect class from its own guards: a
check that **cannot distinguish "measured, and it was fine" from "did not measure"**.
Guard 3's write side failed OPEN because a command substitution inside `[[ ]]` is
exempt from `set -e`; a `.strict()` assertion was satisfied by the exact five-name
denylist its own comment said it defeated; a tracked-roster arm was a tautology that a
no-op gate passed.

Then the session took three days, and **seven of my own process errors were the same
defect**, in the instruments I built to verify the fix.

## The seven, all one shape

1. **A partial log read as a verdict.** `lefthook` prints per-hook lines as it goes and
   its verdict at the end. I read `markdown-lint … exit status 1` from a tail of a
   still-running commit, concluded "rejected", and launched a **second** `git commit`
   into the same worktree. Two writers, one index. The first commit was still alive.
2. **`git commit … | tail -25`.** The pipeline's status is `tail`'s, so a failed commit
   reported success. Worse, `test-all.sh` leaves no report artifact, so the 52 minutes
   of failure output that existed *only* in that pipe was destroyed. I had to re-run the
   battery to learn what I had already paid to learn.
3. **A long-lived log in `/tmp`.** Swept between turns. The still-running process held an
   fd onto a deleted inode, so even completion would have written nowhere.
4. **A fleet loop that reported `0 reds` without proving it ran.** `grep -c` exits 1 on
   zero matches, so "all 181 suites passed" and "the loop never executed" produced
   byte-identical output. The re-run printed `SUITES_RAN=181` for exactly this reason.
5. **`grep -c` again, twice more**, turning a CLEAN gate (`0 failed, 0 killed`) into an
   apparent failure because it was the last command in the wrapper.
6. **`.git/info/exclude` in a worktree.** `.git` is a *file* there, not a directory.
   The trap is written in this repo's own review skill, and I hit it anyway.
7. **"markdownlint is not a CI gate"** — asserted after grepping `scripts/` and
   `.github/workflows/` and never the hook config, which is where it lives. The
   incomplete search produced a confident false negative that shaped a decision.

## Key insight

**A verification instrument is subject to the same anti-vacuity discipline as the guard
it verifies — and it is exempt from every gate, because nobody reviews the wrapper.**

The reviewed artifact gets mutation testing, assertion floors and instrument self-tests.
The five-line bash wrapper that *reports* the result gets none, so it is where the
could-not-measure collapse survives. Three rules follow:

- **Never take a verdict from a partial artifact — and never from the completion
  notification either.**

  > **Superseded 2026-09-09 (#7957):** this bullet originally read *"A backgrounded
  > command has a completion notification precisely so you do not have to infer from a
  > tail."* That is false, and it is retained here rather than deleted because it is the
  > claim #7957 measured. A background task's exit code is the LAST command in the
  > backgrounded string, so a trailing convenience line becomes the verdict: measured
  > three times in one session, the notification reported `exit code 0` while the log's
  > own `COMMIT_RC` recorded `git commit` returning 1, because the string ended in a
  > `git log`. A fourth run killed mid-`tsc` by the memory reaper also notified
  > `completed` — could-not-measure rendered as measured-good, which is the parent class
  > this file is about. Write the real code yourself (`echo "RC=$?" >> log`) and read
  > that. The notification is authoritative for LIVENESS (has it exited?), never for
  > VERDICT (did it succeed?).
- **Never pipe a command whose exit code is the result.** `cmd | tail` discards the
  status *and* the evidence. Redirect to a file and read `$?`.
- **Make "the loop ran" observable.** Print the count. `0 failures` and `0 executions`
  must not render identically.

## Two things that went right, and why

- **An assertion I wrote refused to force a merge.** A superset check on an Art. 30
  register row failed; my helper had grabbed the wrong annotation block. Because it
  asserted instead of proceeding, main's #7803 text was not silently dropped from a
  GDPR record. The diff-based re-check proved the row *was* a clean superset.
- **Measuring a claim I was about to ship falsified it.** I wrote that building a
  `file://` URL with the `URL` constructor breaks on spaces. It does not — it
  percent-encodes them identically to `pathToFileURL`. The two differ only on the `#`
  and `?` characters, where the URL parser reads a fragment or query delimiter and
  truncates the path. The fix was right; the stated reason was wrong, and only a
  five-line probe separated them.

## Merge vs rebase on high-collision legal documents

Rebasing 21 commits over `docs/legal/**` was abandoned at 14/21. The same documents
re-conflicted on every replay, and **each replay is a fresh opportunity to get a legal
statement subtly wrong**. The PR squash-merges, so branch shape is collapsed regardless.
One merge with one careful resolution is strictly safer than seven sequential ones.

Two resolution rules that earned their keep:

- **A pin is a measurement, never a side.** `legal-doc-shas.ts` was RECOMPUTED from the
  merged canonical documents. `check-tc-document-sha.sh` rc=0 confirmed it.
- **A correction written against text that has since moved becomes false.** My Lawful-basis
  correction opened "written as though the signer were the only data subject" — untrue
  once main's #7625 recorded the non-signer commenter capture. Restated to cite #7625
  and add the corporate representative as a further population.

## What the merge caught that neither branch had alone

Main's #7858 landed `lint-shell-trace-credential-refusal` (AP-025). `ccla-add.sh`
predates it and binds a live credential via `gh auth`, so under `-x` bash would have
echoed the token. Three assertions, not one: the two obvious arms (rc=78, message) are
both satisfied by a script that refuses UNCONDITIONALLY, which would be entirely broken.
A must-PASS arm asserts the same argv without `-x` does not yield 78. Deleting the guard
reds 2 tests; making it unconditional reds 24.

## Session Errors

1. **Inferred a commit verdict from a partial lefthook tail and started a concurrent
   commit in the same worktree.** Recovery: killed the duplicate subtree, verified no
   `index.lock`, HEAD unmoved. **Prevention:** wait for the completion notification; a
   mid-stream hook line is not the verdict.
2. **`git commit … | tail -25` swallowed the exit code and the only copy of a 52-minute
   failure.** Recovery: re-ran the battery. **Prevention:** never pipe a command whose
   exit status is the result; redirect and read `$?`.
3. **Long-lived log written to `/tmp`, swept between turns.** Recovery: re-ran with the
   log inside the worktree. **Prevention:** any log outliving a turn goes in the worktree.
4. **Fleet loop reported `0 reds` unprovably.** Recovery: re-ran with a counter.
   **Prevention:** print the executed count; make a no-op loop distinguishable.
5. **`grep -c` exit 1 made a clean gate look failed, twice.** Recovery: read the log's
   own verdict line. **Prevention:** end reporting wrappers with `; true`, or read the
   artifact rather than a grep's status.
6. **`.git/info/exclude` in a worktree.** Recovery: `git rev-parse --git-common-dir`.
   **Prevention:** already a documented trap — consult it before writing under `.git`.
7. **Claimed markdownlint was not a CI gate after an incomplete search.** Recovery: the
   pre-commit hook rejected the commit. **Prevention:** before asserting a gate does not
   exist, search the hook config, not only `scripts/` and workflows.
8. **Asserted `new URL()` breaks on spaces.** Recovery: measured; corrected the comment
   to `#`/`?`. **Prevention:** measure a mechanism before writing it into a code comment.
9. **A superset heuristic misfired on a legal register row.** Recovery: the assert fired;
   re-checked with a diff. **Prevention:** assert, never force, when the artifact is a
   legal record.
10. **A correction of mine went stale against main's #7625.** Recovery: restated the
    opening. **Prevention:** re-read what a correction points AT after a merge.
11. **AP-025 ordinal collided with #7858.** Recovery: renumbered to AP-026 and swept
    ADR-201's two citations. **Prevention:** known class — a branch-picked ordinal is
    provisional until re-checked against freshly-fetched `origin/main`.
12. **`TC_LOCK_TIMEOUT` bounded nothing — a battery sat in `flock` for 46 hours.**
    Recovery: killed it. **Prevention:** filed; a queued battery that waits forever is
    indistinguishable from a hung one.
13. **Hook suites wrote fabricated `deny` events into the operator's real incident
    ledger** (`gh pr merge 123 …`), beyond the gdpr-gate case #7853 names. Recovery:
    identified them as fixtures before treating them as deviation evidence.
    **Prevention:** commented on #7853 to widen its scope.

## Related

- #7854 — `memory-backstop.test.sh` fails only under lefthook; blocks every local commit
- #7549 / #6842 — `changelog-data` live GitHub API 5s timeout inside the commit-blocking gate
- #7853 — hook self-tests write fabricated deny events into the real ledger
- ADR-201 — the Corporate CLA is a repo-tracked roster; AP-026 (additive evidence must not gate)
- `knowledge-base/project/learnings/2026-09-04-every-verification-i-wrote-passed-and-three-of-them-proved-nothing.md`
