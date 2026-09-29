---
title: "I pinned a flake class with a weaker fork of the detector the repo already maintained — and the control tested my copy, not the detector"
date: 2026-09-29
category: workflow-patterns
tags: [pipefail, sigpipe, grep-q, detector-reuse, drift-guards, ci-flake, instrument-vs-verdict]
issue: 9210
pr: 9213
branch: feat-one-shot-9210-birth-readiness-gate
---

# Learning: the detector I wrote was a weaker fork of one the repo already kept — and my control proved my copy could fire, not the shipped one

## Problem

Fixing #9210 — a main-CI flake where `printf '%s\n' "$src" | grep -qE pat` under
`set -o pipefail` returned non-zero despite the pattern MATCHING (grep -q closes
the pipe on first match; printf took EPIPE on a large var; pipefail promoted the
transport failure to a pipeline failure, which a `!` arm read as a shape
violation). The mechanism was already corpus: ADR-119:122 documents it verbatim,
and the lib's own comment said "A HERESTRING, NOT A PIPE" — yet four sites were
never converted, including one added by the same commit that wrote that comment.

The implementation fix was easy and verified (deterministic reproducer: 200KB
input, early match — old form false-ABORTed 40/40, herestring 0/40). **Every
significant finding in the 9-seat review was in the DRIFT PIN I added, not in
the mechanism fix.**

## Solution

### 1. Before writing a detector for a known class, grep for the canonical one

I wrote W2's extraction as `\|[[:space:]]*grep[[:space:]]+-[a-zA-Z]*q` — measured
against the incident's exact spelling and nothing more. The repo's canonical
detector lives at `.claude/hooks/grep-q-pipe-guard.test.sh:67`:

```
(^|[^|])\|&?[[:space:]]*grep([[:space:]]+-[A-Za-z]+)*[[:space:]]+(-[A-Za-z]*[qm][A-Za-z0-9]*|--quiet|--silent|--max-count)
```

My fork reintroduced two defects that file had already paid for: the `||`
false-positive (the second bar of `cmd || grep -q` reads as a pipe — #8807,
fixed there by the `(^|[^|])` anchor) and blindness to the class's other
spellings (`|&`, `-m`/`--max-count`, `--quiet`/`--silent`, a `q`/`m` flag in a
later flag-cluster position like `grep -E -q`). Four review seats converged on
it independently — the plan's own archive carried a census of pipe-into-grep
detector copies flagged precisely because drift was the known risk.

**Rule: the class census is not done when the incident's spelling is pinned.**
`git grep -l 'grep -q'` is not the search — the search is for the file that
already owns the detector (`grep -l 'pipeguard\|SIGPIPE\|pipefail' .claude/hooks
scripts tests`). Adopt the maintained pattern verbatim and say so in a comment;
a fork is a maintenance debt the moment it's written, and it is always written
to the incident's spelling rather than the class's.

### 2. A control that validates a COPY of the detector proves nothing

W2-control's first draft inlined the same `sed | grep` extraction a second
time — so it verified that *a* detector fires on a seeded line, not that *the*
detector ships. A later edit weakening W2's regex would leave both rows green
forever. The suite's own standard applies to the suite's own pin: extract the
extraction (`_w2_sweep <dir>`), have the pin and the control call the same
function, and let the seeded fixture cover the widened shapes (split flag
cluster, `|&`, `-m1`) plus the must-pass forms (`grep -q file`, `<<<`,
`cmd || grep -q` — the #8807 regression). A non-compiling pattern must also not
read as zero hits: compile-check it once (`grep -E -- "$PATTERN" </dev/null`
must exit 1, not 2) before trusting the sweep.

### 3. The verdict vocabulary is a second fix, not a refactor

Three of the four sites were non-negated `if` arms where a mid-pipe death read
as "no match" — fail-OPEN past HOLDs, worse than the observed fail-closed
flake. Splitting `matcher || _rc=$?` and ABORTing on `rc >= 2` (instrument
failure, "could not evaluate") vs `rc == 1` (measured verdict) is the arm that
keeps the NEXT transport flake from arriving dressed as a shape violation. And
`if ! cmd; then` is structurally unsplittable — inside the then-branch `$?` is
already the inverted status — which is why the capture-then-test form is the
only honest shape. The panel's structural map enumerated the residual surface
(six more `if !` arms, ~12 `|| true` captures, `=~` matchers, `| head`
producers) — filed to #9217 as the deferred sweep's real scope.

## Key Insight

A drift pin is code, and it gets the same review discipline as the fix it
protects: the regex is a claim about a class, so a divergent re-implementation
of a maintained detector is a bug introduction, not a test. And "the control
row can red" means the control drives THE shipped detector — through a shared
extractor — or it drives nothing.

## Session Errors

1. **Forked a canonical detector weaker** — wrote W2's regex against the
   incident's spelling; it reintroduced #8807's `||` false-positive and missed
   five class spellings. **Prevention:** before writing any pattern for a named
   class, grep `.claude/hooks`, `scripts/`, `tests/` for an existing detector
   for that class; adopt the canonical text and cite it.
2. **Control validated a copy** — inlined the extraction twice; the control
   would keep passing on a detector that no longer shipped. **Prevention:**
   controls consume the shipped artifact through a shared helper — never a
   re-typed twin.
3. **BRE `\|` is alternation, not a literal pipe** — a `\|\| *true` classifier
   "matched" every line and would have mis-dispositioned a finding.
   **Prevention:** literal-string membership checks get `grep -F`, never a
   regex built by hand from memory.
4. **Unmeasured causal claim in a comment** — wrote "failed OPEN on exactly
   that (#9210)" for an arm where the observed incident had failed closed.
   **Prevention:** for every causal sentence a comment adds, name the command
   that would falsify it and run it — the corpus rule already exists; apply it
   to comments, not only code.
5. **Plan/task floor arithmetic drifted** — artifacts prescribed `_FLOOR`
   252→254; three assertions landed, shipped 255. **Prevention:** compute the
   floor from the counted run, and disclose the delta in the commit when it
   diverges from the plan's number.
6. **Tool-call parameter misuse** — `get_output` invoked with an unsupported
   `command` field; the tool rejected it and work resumed via the accepted
   interface. **Prevention:** check the tool schema before invoking rather
   than pattern-matching on another tool's signature.
