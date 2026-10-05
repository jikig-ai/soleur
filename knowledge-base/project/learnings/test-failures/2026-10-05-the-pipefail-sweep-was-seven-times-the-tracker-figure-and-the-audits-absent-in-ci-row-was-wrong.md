# Learning: the pipefail early-exit sweep was seven times the tracker's figure, so the guard derives its population and the audit's "absent in CI" row was wrong

## Problem

Three trackers (#9217, #6601, #7005) cite "41 production and 148 test-harness sites" for pipe-fed early-exit `grep -q`
under `pipefail`. Re-measured repo-wide on 2026-10-05 with the guard's own derivation (`PATTERN_V2` over every non-ignored
file with a covered extension, comment lines and marked lines dropped) the figure was **1,107 code lines in 1,644 swept
files** on the unconverted tree: 166 production lines in 82 files under `scripts/`, `plugins/`, `apps/web-platform/` and
`apps/cla-evidence/` (164 in 81 converted, 2 left as an LLM prompt literal), the rest test harness and infra/CI. The July figure was `apps/web-platform/infra/` only, with a different normalisation. A plan sized
from the tracker title would have been an order of magnitude too small, and the guard's existing model (one array entry,
one pin count and one affected-paths entry per file) cannot hold 300 files: the affected-paths edit alone arms the full
battery (about 2,900 s of runner time per push).

## Root cause

Two stale inputs were treated as facts. The tracker title was a snapshot of one subtree, and the audit
`2026-07-17-sigpipe-guard-triage-feasibility.md` carried a row saying the defect is "absent" on the Actions runner (SIGPIPE
inherited as ignored, producer rc 0). That row is true for an external writer and false for a builtin `printf`/`echo`
writer, which gets EPIPE and returns 1; `pipefail` still promotes it. The three suites that flipped on 2026-10-05 ran on that
runner. The audit now carries a corrected row.

## Solution

- The guard derives its population (`git grep --no-index --exclude-standard` over every covered extension) and asserts
  zero outside a deferral table (glob, mode, ceiling, tracker). A subtree reaching zero makes its own row stale, so the
  converting wave deletes the row. Shrink-only is a convention: `=` rows are tight, `<=` rows tolerate slack until the wave
  PR lowers the number, which is why every loose row is test-shaped (`*` crosses `/` in a row glob, so a loose row that also
  matched production code would let a new production instance hide in its slack). Nothing is enumerated per file.
- `--exclude-standard` is load-bearing: without it the scan read `node_modules` (24.3 s versus 1.0 s, ten stray hits).
- Conversion rules came from reading the real files, not from the pattern: `printf '%s'` heading a chain that ends in
  `tail -c 2` flips under a head-of-chain here-string (the newline reaches `tail`), a side-effecting producer under `set -e`
  must be captured rather than process-substituted, and a gate whose miss skips a check (`sdk-bump-sandbox-gate.sh`) must
  route a grep that could not run (rc above 1) to the gate.
- A transformer for the mechanical class refuses what it cannot prove equivalent and is checked by an inverse transform
  over every changed line; `printf '%s'` with `-v`, `-x`/`-F` and a variable pattern, or an empty-capable body goes to
  hand review.

## Prevention

- Re-derive a tracker's site count before sizing a sweep, and write the command next to the number.
- A population you can derive should be derived; pinning is for the handful of files that carry an incident.
- A "defect absent on this environment" claim needs a measurement of the writer kind, not only the signal disposition.
- Residuals a line regex cannot close are listed with counts in the guard header (`| head`, multi-line awk, `read`, a
  reader behind a variable or a function); the producer-side form (a stub that never reads the stdin it is fed) needs a
  join to the owning suite and is a separate wave.

- The review panel found the guard narrower than its name in four places a self-run battery could not see: an unanchored
  comment filter and marker (a violating line could hide behind `:3:#` or a marker-shaped string), an untested dispatch
  (`exit "$FAIL"` could be softened with the suite green), a canary check satisfied by a nested path, and loose rows that
  also owned production files. Each now has a probe and a mutation row; the lesson is to drive the whole chain on a scratch
  root and to mutate the guard, not only the code it guards.

## Session Errors

- A first transformer revision treated a trailing line-continuation backslash as part of the grep command and wrote the
  here-string after it (`grep … \ <<<"$x"`), a syntax error in four files; `bash -n` over every changed file caught it
  before any commit. Run `bash -n` over the whole changed set after any scripted rewrite.
- The same revision read `||` after the reader as a further pipe stage and refused 13 sites that were fine; a count of
  "HAND" sites that jumps after a transformer change is a signal to read the refusals, not to accept them.
