---
title: "A negative row passed for the wrong reason four times inside the guard built to contain mutants"
date: 2026-10-10
category: test-failures
module: plugins/soleur/scripts/run-in-pid-namespace.sh + scan-ancestor-signal-helpers.py + scripts/soleur-sandbox.sh
issues: [9217]
---

# The PID-namespace guard for signal-helper mutants: what the mutation pass of the guard's own tests found

## Problem

The change added a wrapper that runs a command as PID 1 of a PID namespace (and refuses, never falls back), a `run-isolated` verb on the sandbox allocator, an inventory scan with a baseline of signalling sites, and a bound on a second ancestor-walking helper. The author's first mutation pass reported the guards killed. A 12-seat review panel and a second mutation pass, run through the wrapper itself, found that several "refusal" rows were green for a reason other than the one they named:

- **A skip row fed a non-baseline file.** The row asserting "a skipped member under a baseline gate is rc 3" passed a source-fixture as the baseline; the scan returned rc 3 because the baseline was malformed, so removing the skip check changed nothing.
- **One empty marker was refused by three conjuncts.** The verb checks `pid=`, `schema=1` and `ns=` in the sandbox marker; the only fixture was an empty marker, so deleting any one conjunct stayed green. Each conjunct needs a fixture that fails only it.
- **A fixture carried two operators.** The comparison-operator fixture used `-ne` and `-lt` on one line, so removing `-lt` from the scanner stayed green.
- **A stress file finished 3 seconds under its own cap.** The quadratic-time mutant took 57 s against a 60 s timeout, so the row passed with the regression present.
- **The namespace rows could be skipped by the helper's own refusal.** The suite decided "real namespaces are unavailable" by asking the helper under test; a helper that false-refused turned 18 rows into SKIP and the row asserting "the real helper refuses" passed. The availability probe must not go through the code under test.

The unfixed survivors were also instructive: a presence-grep over the walker's own source (a trailing comment carrying the bound text satisfied it), a seat-brief that said "carries the command" on surfaces that did not, and an evidence line counting 12 kills where 11 rows were listed.

## Solution

- Every negative row names its reason in the assertion (match the message text, not only the exit code) and uses a fixture that violates exactly one conjunct.
- A fixture exercises one operator or one prefix; a stress input is sized so the regressed algorithm takes at least twice the cap.
- The environment probe that decides SKIP versus RUN is independent of the code under test, and a host that can do the thing while the code refuses is a FAIL.
- A pass over the evidence recounts every figure from the rows it lists.
- A static assertion over a helper's text strips trailing comments and anchors on the loop condition, never on a token anywhere in the file.

## Key Insight

A refusal row proves the guard only when the guard is the sole reason for the refusal. When several checks overlap, the first mutation pass credits the whole set to the fixture that trips any of them; the second pass, one mutant per conjunct with a fixture per conjunct, is the one that measures. Run the mutation pass against the guard's own tests, inside the containment the guard provides.

## Session Errors

1. **A weak baseline argument in a negative row (skip gate).** Recovery: valid baseline plus the message text. **Prevention:** the test-design reviewer's checklist carries "a negative row's control input must be valid for every reason except the one asserted" (added in this PR).
2. **An all-conjuncts-one-fixture marker row.** Recovery: one fixture per conjunct. **Prevention:** same checklist line; the mutation driver lists one mutant per conjunct.
3. **A fixture with two operators.** Recovery: one operator per fixture. **Prevention:** same checklist line.
4. **A stress input under the cap.** Recovery: input sized to exceed the cap with the regression present. **Prevention:** run the regressed algorithm once and read its time before choosing the size.
5. **Helper decided its own availability.** Recovery: independent host probe (row R10). **Prevention:** the environment probe for SKIP is never the code under test.
6. **A docs claim ("this is the one copy") written stronger than the facts.** Recovery: reworded; the reference carries the full statement and other surfaces carry a pointer. **Prevention:** after editing a claim of uniqueness, grep the claim's subject across the repo.
7. **Evidence arithmetic ("12 of 13") that listed 11 kills.** Recovery: appended correction. **Prevention:** recount from the listed rows before writing a total.
8. **Pre-existing, from the earlier phases of this session:** shallow clone inflating the branch range (fixed by unshallowing); the first S5 CI run red on a bot-status lint and a registry fetch (reworded prose; re-ran); sandbox-suite construction slips (a chain built from files, a stub that preserved arguments, `pipefail` capture order); an accidental `chmod +x` glob that flipped sibling suite modes (reverted); two ratchet-lane members red after the first run (fixture-relative operands; a path spelled in a docstring read as a consumer). **Prevention:** run the pre-push ratchet lane before the first push, and never `chmod +x` by glob.
9. **Working directory reset after a command that changed it.** One-off; later commands used absolute worktree paths.

## Tags
category: test-failures
module: run-in-pid-namespace, scan-ancestor-signal-helpers, soleur-sandbox
