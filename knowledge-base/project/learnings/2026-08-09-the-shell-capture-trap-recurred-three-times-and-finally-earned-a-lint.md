---
date: 2026-08-09
issue: "#7332"
pr: 7336
category: build-errors
tags: [shell, errexit, gates, lint, adr-166, calibration]
---

# The shell-capture trap recurred three times in one PR and finally earned a lint

## The defect

`grep`, `diff` and `cmp` use a non-zero exit to report a **negative answer**, not an
error. Under `set -e` that answer is indistinguishable from a crash. And the assignment
does not shield it: for `x=$(cmd)`, the exit status **of the assignment is** the exit
status of the command substitution. `x=$(...)` reads as "store a value" and behaves as
"run a command".

Three instances inside one PR, in three disguises:

1. **`x=$(cmd)` aborting under `set -e`.**
2. **`grep … | wc -l` aborting inside a newly added guard.** With `pipefail` on, the
   pipeline's status is grep's — `| wc -l` does not launder it.
3. **`hn="$(grep -c …)"` in `write-row`.** `grep -c` prints `0` **and** exits 1 on zero
   matches, so a register with no `Auto-inferred` heading *died before its own `die`
   could print* — exit 1 with empty stderr, and 1 is not in write-row's documented
   0/2/3 contract (it collides with drift's "drift found"). The later `|| echo 0`
   "fix" then yielded the two-line string `"0\n0"`, because the guard fired **on top of**
   the value grep had already printed.

Instance 3 is the worst shape: the `||` *did* suppress errexit and produced a **wrong
value** instead of a dead script.

## Why it kept happening

Two of the three were written **while fixing the earlier ones**. From the review commit
that added a call-site guard:

> Writing that guard reproduced the `x=$(cmd)` set -e trap for the third time this
> session — grep exits 1 on no matches, so the suite aborted before printing FAIL and
> **the mutation read as surviving**.

That is the compounding cost. The trap did not merely break a script; it **corrupted the
instrument being used to check the script**, turning a killed mutant into a surviving one
and inverting the verdict.

Three comments were added across the same PR. The class recurred anyway. Documentation-only
enforcement of a shell-semantics invariant is measurably not working here — the same
finding [`lint-workflow-errexit-capture.py`](../../../scripts/lint-workflow-errexit-capture.py)
recorded for its own class after six occurrences.

## The fix

`scripts/lint-shell-capture-exit.py` + `scripts/lint-shell-capture-exit.test.sh`,
registered in `scripts/test-all.sh` as `scripts/lint-shell-capture-exit` (unit) and
`scripts/lint-shell-capture-exit-live` (gate). Per **ADR-166**: a recurring defect class
that documentation has failed to stop earns a `scripts/lint-*` gate.

Two finding classes: **S1** (abort) and **S2** (double-emit — the `grep -c` case).

## Sibling, not extension

`lint-workflow-errexit-capture.py` covers Actions `run:` blocks and anchors on the
**read** (`rc=$?`, `${PIPESTATUS[n]}`). Its docstring records that the naive rule "a
command-substitution assignment is a finding" was prototyped against the real tree and
found **only 2 of its 17 sites**, because 9 were bare commands followed by `rc=$?`.

That measurement is *why this is a separate gate*. In shell scripts the distribution is
inverted — the capture **is** the idiom — so the rule that was wrong there is the right
one here. Widening the sibling would have meant each class covering the other's blind
spot badly. **Two classes, two anchors, two calibrations.**

`shellcheck` does not close it either: SC2312 is opt-in, off by default, and aims at the
opposite problem (a status being *masked*). It runs in this repo's CI and flagged none of
the three.

## Calibrated, not assumed

774 tracked `*.sh` scanned → **216 pre-existing findings across 65 files** (206 S1, 10 S2).

The gate ships with a **baseline** keyed on `path + class + normalised text` — deliberately
**not** the line number, which churns on every edit above a finding and would train readers
to regenerate the baseline reflexively. The gate blocks **new** occurrences; the baseline
may only shrink.

The alternative was narrowing the rule until the tree looked clean, which is precisely the
"gate certifying its own blind spot as scanned" failure its sibling exists to warn about.
**Burn-down:** 216 entries in `scripts/lint-shell-capture-exit.baseline.txt`; reduce
opportunistically when touching a listed file. Regenerating it to admit a *new* finding
defeats the gate.

## The suite found two real bugs before it landed

- **`x=$(grep -c f) || echo 0` — instance (c) itself — did not match the assignment regex
  at all** and was reported clean, because the pattern anchored at `)` + end-of-line and
  had no room for a trailing decision clause. The gate was blind to the exact shape class
  S2 exists for.
- **The harness's own `LINT_RC` was assigned inside a `$( )` subshell**, so every
  must-fire assertion read "linter saw nothing" while the same linter was finding 216
  sites in the real tree. This gate's own class wearing a different hat. It is documented
  in the harness rather than quietly fixed.

Every must-not-fire fixture carries a **positive control**, because a broken detector and
a clean tree emit identical output.

## Key insight

A command that legitimately exits non-zero, captured without deciding what its exit status
**means**, is one defect with many costumes. Ask of every capture: *what does non-zero mean
here?* The three valid answers are `|| true` (it's fine), `|| x=default` (substitute), and
`if x=$(…); then` (branch on it). Silence is the fourth, and it is always a bug.

And when the same trap can corrupt the **measurement** you use to verify the fix, comments
cannot hold the line — only a mechanical gate can.

## Related

- [[2026-08-06-my-gate-would-have-fired-on-every-input-and-no-unit-test-could-see-it]]
- `scripts/lint-workflow-errexit-capture.py` (sibling class, Actions `run:` blocks)
- ADR-166 (recurring operator-facing defect class → `scripts/lint-*` gate)
