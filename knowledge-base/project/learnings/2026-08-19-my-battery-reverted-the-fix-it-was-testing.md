---
title: "My mutation battery reverted the fix it was testing, and 33 of 34 rows still said PASS"
date: 2026-08-19
category: test-failures
module: apps/web-platform/infra
issue: 7104
tags: [mutation-testing, guards, anti-vacuity, shell-parsing, merge-conflicts]
---

# My mutation battery reverted the fix it was testing

## Problem

A six-agent panel found #7104 PR-B NOT SHIPPABLE: two P0s, plus **three fixes from the previous
pass that the panel defeated with executed mutations while both suites reported perfect green**.

The fix pass then reproduced the same class three more times. The through-line is not
carelessness — every one of these was a guard, written by someone who knew the failure class,
that measured something adjacent to what it claimed.

## The five that generalize

### 1. Restore from a pristine COPY, never from git — and commit before you mutate

The P0-A mutation battery restored between rows with `git checkout -- "$SUT"`. The fix under test
was **uncommitted**, so row 1 restored the file to HEAD — the pre-fix version — and every
subsequent row scored the defect against itself. Rows 2 and 5 were reported as SURVIVED; they
were measuring a file that no longer contained the fix.

The only thing that caught it was the battery's own `diff pristine vs SUT` restore check at the
end, which is a footnote most batteries omit.

**Prevention:** restore from a `cp`-taken pristine copy, and commit each verified unit *before*
mutating it. `git checkout` is a restore to HEAD, which is a different thing from a restore to
"what I had a moment ago" precisely when a fix is in flight.

### 2. A surviving mutant has exactly two readings, and they are not interchangeable

The row reproducing the panel's D1 bypass survived. The instinct is "the guard has a gap."

It did not. The mutation added the panel's two balanced phantom lines but never moved the content
assert INTO the poll loop — and balanced phantoms around an assert that is genuinely terminal
perturb nothing. Not detecting it was **correct**. The row was a FIXTURE failure wearing a guard
failure's clothes.

**Prevention:** label every survivor as *fixture-inadequate* or *equivalent* before acting. The
composite had to be reconstructed exactly — assert moves into the loop, a real `for … done`
restores the count scalar, and the two `[[ ]]` phantoms zero the depth — before it drove RED.

### 3. A detector that greps a sentinel classifies anything that QUOTES the sentinel

`guard-vacuity-floor` decides a suite "carries a conservation check" by grepping for that check's
`[FATAL]`-prefixed sentinel string. The mutation battery used that same string as a **row marker
in a data table**, so the battery was classified as a conserving suite and then failed the
"reports directly" arm it had never claimed to satisfy.

The first fix reproduced the failure **by explaining it**: the replacement comment quoted the
sentinel to say why the sentinel must not appear. A comment is still bytes in the file.

**Prevention:** this is `cq-assert-anchor-not-bare-token` one level out — the rule normally
protects a suite from matching its own prose; here it protects a *different* guard from matching
this file's data. When a detector greps a literal, every file that mentions that literal for any
reason is in its population.

### 4. Divergent parsers are the defect; teaching one of them is not the fix

Three hand-rolled shell parsers shipped in one directory with three noise-stripping policies —
one stripped `[[ ]]` test spans, one did not, one was a bare `grep` that stripped nothing. Two
balanced phantom lines exploited exactly that gap and restored a #6594-class coin flip with the
suite at `132 passed, 0 failed`.

The available fix was "teach the loop scanner about `[[ ]]`". That leaves three policies and
repeats the failure the next time one of them learns something the others do not. The fix was one
`strip_noise` in a shared module, used by all three.

The same consolidation immediately paid: the third parser was a three-name **deny-list** over the
higher-privilege file, measured evaded 8 ways out of 9 (absolute path, `./` path, `$VAR` in
command position, `awk` `system()`, `awk | "sh"`, `sed -e …e`, `sed -i`, bare redirection). Two
of those trampolines — `awk` and `sed` — were **on the allow list**, and the allow list blanked
quoted spans first, so an awk program body was invisible *by construction*: it had deleted the
evidence before looking for it.

### 5. `grep -c` PRINTS `0` and exits 1

`stdout_passes=$(grep -c '^  PASS: ' "$LOG" 2>/dev/null || echo 0)` appends a **second** zero, so
the variable is `"0\n0"`. This sat inside a reconciliation guard whose entire job is comparing
two counts. `|| true` keeps the zero the command already printed.

Caught by `scripts/lint-shell-capture-exit`, not by any test — the value is only wrong in the
no-match case, which the suite never reaches when it is healthy.

## Two merge-time lessons

- **An ordinal claimed on a branch is provisional in both directions.** `AP-023` was claimed here
  and taken by main mid-review (renumbered to `AP-024`); `ADR-189`, claimed the same way on the
  same branch, survived — main went 188 → 190 around it. Re-derive both against freshly-fetched
  `origin/main` immediately before merge; neither outcome is predictable from the other.
- **A shrink-only ratchet that says "do not raise this number" means build the seam.**
  `guard-vacuity-floor`'s ARM 5c had been raised once, against its own instruction, with the note
  "the correct response to a second occurrence is to build the seam, not to add another line
  here." This was the second occurrence. The per-file promotion seam took ~20 lines — and the
  promotion immediately found two real defects in the two suites it covered, including a floor
  whose threshold binding sat too far above it to survive mutant construction, i.e. a floor that
  **could not be driven red**.

## Key Insight

Every one of these is a guard that measured something adjacent to what it claimed, and in every
case the adjacent thing was green. The distinguishing question is not "did the check pass" but
"name the input that would make this check fail, and show it failing." A battery that cannot
revert its own restore, a row that cannot reproduce its own attack, and a floor whose threshold
is out of scope all report identically to correct ones.

## Session Errors

1. **The battery restored with `git checkout --` against an uncommitted fix** — Recovery: restored
   from the pristine temp copy, committed the fix, re-ran. Prevention: restore from a pristine
   copy; commit each verified unit before mutating it. (recurring → fixed inline: the battery's
   own restore semantics.)
2. **`EXIT=$?` was reset by a `$(basename …)` in the same echo** — reported `EXIT=0` for a suite
   that exited 1. Prevention: capture `rc=$?` into a variable on its own line before any other
   substitution. (recurring → one-off here; the rc-file discipline already covers the long form.)
3. **A redirect-detector regex used `\s*`, which crosses newlines** — 30 phantom findings on two
   files that have none. Prevention: `[ \t]*` whenever a match must stay on one line.
4. **The first trampoline detector ran over quote-BLANKED text** — the awk program body it was
   looking for had already been erased. Prevention: pick the stripping policy from the question,
   not from the nearest existing helper.
5. **The first D3-BYPASS row did not reproduce the attack** — fixture failure that looked like a
   guard gap. Prevention: label survivors fixture-inadequate vs equivalent. (Recorded in the row.)
6. **Two failed attempts at inserting the `CASES` call-site counter** — 41 vs 66, then 75 vs 66.
   Recovery: the conservation identity itself was the oracle. Prevention: prefer a transformation
   whose own invariant verifies it over one you eyeball.
7. **`AP-023` collided with main mid-review** — Prevention: re-derive ordinals against freshly
   fetched `origin/main` immediately before merge. (recurring → already covered by task 10.3's
   standing instruction; extended here to AP ordinals, which had no such instruction.)
8. **`git rebase` onto main conflicted at commit 24 of 39** — Recovery: aborted, merged instead.
   Prevention: on a squash-merge repo, a long branch resolves conflicts once with a merge and up
   to N times with a rebase.
9. **`git checkout --theirs` on the conflicted suite discarded all of PR-B's content** — main's
   copy predates the feature. Recovery: `--ours` plus manual re-application of main's mechanism.
   Prevention: on a conflict between "their mechanism" and "our content", take ours as the base.
10. **The battery's row marker quoted another guard's sentinel**, and the first fix re-quoted it
    in a comment. Prevention: see §3.
11. **`grep -c … || echo 0`** appended a second zero. Prevention: `|| true`.
12. **A ship-gate test pinned `if: success()` formatting**, so strengthening the condition
    red-lined it; the first regex fix allowed 8 chars where 14 were needed. Prevention: assert the
    property and the addition, not the inline shape.
13. **`comm -12` on unsorted input** while building the promotion seam. Prevention: the original
    intersection was already correct — do not rewrite a working computation while adding a set.
14. **`setsid nohup` launched with `$$` in the run-dir path** yielded an empty variable in the
    detached shell. Prevention: fixed paths for detached runs.
15. **`changelog-data.test.ts` timed out at 5 s** — a live GitHub API call under
    `SIBLING_RUN_DETECTED` with three sibling worktrees. Confirmed not-mine three ways (untouched
    by the diff, isolated re-run 3/3 in 3.9 s, contention banner present). One-off.

## Tags
category: test-failures
module: apps/web-platform/infra
