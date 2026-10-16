# Learning: bash reads a running script incrementally — mid-run edits corrupt it

## Problem

Twice during the #10117 fix rounds, edits were applied to
`scripts/test-all-affected.test.sh` while the battery that consumes that very
file was still running. Bash does not read a script file once at exec — it
reads it incrementally, at byte offsets, for the life of the process. Any edit
that shifts byte offsets (even one byte, even inside a comment) makes every
subsequent read land mid-token: rows misparse, verdicts drift, or the run dies
with a syntax error partway through. Both times the run had to be killed and
restarted on the final tree, costing a full ~13-minute cycle each.

The failure is silent: the suite doesn't crash deterministically, it just
executes corrupted text — and because the mutation battery's rows are
self-checking, a corrupted read can even produce plausible-looking green output
from arms that never actually ran.

## Solution

Order matters: make **all** edits to a suite file first, commit, and only then
start the run. If a run is already in flight and an edit must land, kill the
run first — the fix commits require a fresh battery anyway. A cheap check
before editing: `pgrep -f test-all-affected.test.sh` (or the suite being run).
If the suite is green on the PRE-edit tree and only comments/bench files were
touched, note that the validation still covered the code that shipped — but a
suite file must never be edited mid-run regardless.

## Key Insight

A test suite is an instrument whose own file is the SUT's harness — unlike a
compiled artifact, the running process re-reads it lazily. "The test file is
busy" is not a scheduling constraint; it is an integrity constraint on the
evidence. The same hazard applies to any long-running script invoked as
`bash file.sh` (sourced libraries are read once at parse, but the entry file
is not).

## Tags
category: workflow-patterns
module: test-infrastructure
