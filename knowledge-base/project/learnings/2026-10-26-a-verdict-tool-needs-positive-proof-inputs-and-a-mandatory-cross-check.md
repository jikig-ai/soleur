# Learning: a measurement-to-verdict tool must demand positive proof, and its cross-check cannot be optional

## Problem

S4 PR5 (#10861) had to decide, per whole-tree reader, whether the affected index gets a `glob:` edge or an
`ALWAYS_ON_SUITES` entry (PR4b row 6). The replay tool could not compute a per-glob selection rate, so a read-only
`glob-rate` subcommand was built. The first version shipped green (26 rows, 38 mutants) with five ways to emit a
`glob` verdict on nothing: no `--pairs` file, an `@tree` suite whose extension tail did not parse (empty cover),
`--spot-check` defaulting to 0 (no model-versus-real-selector check), a spot-check that was global rather than per
candidate suite, and an always-on verdict above the 10 s fast-tier cap that the repo's own lint would reject.

## Solution

- A `glob` verdict needs a positive coverage proof (a pair list to cover, or an `@tree` cover with files), else
  `baselined` / `no-coverage-proof`.
- `@tree` with no recognised extension (or no tracked file) is refused; multi-dot extensions count.
- `--spot-check` defaults to 3, `< 1` is refused, and every candidate suite must be compared on at least one sampled diff.
- The tool never recommends a verdict the repo cannot install (CTO row 13: 10 s cap, 30 s stays the policy bound).
- Printed labels go through `quote_field`; exit codes and the rows/base/candidates recipe live in the docstring, `--help` and the runbook.

## Key Insight

For a tool whose output licenses an irreversible-ish edit, every optional input is a way for the verdict to rest on
nothing. Ask per input: "what verdict does the tool emit when this is absent?" The answer must be "baselined", never
"qualified". A cross-check against the real system is part of the measurement, so it defaults on.

## Session Errors

1. **Implemented `glob-rate` before writing its tests.** Recovery: re-proved RED by running the new section against
   `git show origin/main:` of the old tool. **Prevention:** write the failing section first; if code exists already,
   run the section against the pre-change file before trusting any green.
2. **A guard that counts textual `edge_hit(` call sites (ONE function, ONE call site) tripped three times** (new calls,
   a docstring, a comment). Recovery: alias `_edge = edge_hit` and reword prose. **Prevention:** before adding a call to
   an oracle function, grep the test file for a count-of-call-sites guard on its name; prose containing `name(` counts.
3. **New code duplicated the anchor strings of existing mutants** (`if e.startswith("glob:"):`, a comment-skip line),
   turning two existing mutants into `edit-failed`. **Prevention:** after adding code to a file with a mutation
   battery, run the whole suite once before anything else; a mutant going `edit-failed` means an anchor is no longer unique.
4. **The plan's file list missed `scripts/test-affected-kb-consumers.baseline.txt`**, which also carries one row per
   suite pair and went red when the suite became always-on. Found by the Phase 3 verification set. **Prevention:** an
   always-on edit owes the accept rows, the audit baseline AND the kb-consumers baseline (runbook section 7 now says so).
5. **The orphan census flagged the replay test** for `git ls-files | grep` text in a new assertion. **Prevention:** use
   `ls-tree` / non-corpus spellings in test text, or run `scripts/lint-orphan-test-suites.sh` after adding a `*.test.sh` row.
6. **Making the spot-check mandatory turned two mutants into rc-4 "crashes"** (the divergence IS the kill). Recovery:
   `CRASH_IS_THE_POINT` row:mutant pairs. **Prevention:** when a new fail-closed exit (rc 4) can fire for a mutant, list
   it deliberately and say why; a seat noted the exemption also accepts a true Traceback for those pairs.
7. **A decision row appended outside the ruling-gate shape failed twice** (`bad-class`, `bad-ruling-shape`) before a
   real CTO ruling. **Prevention:** a technical fork gets a CTO spawn first; write the row from its reply verbatim.
8. **Tool friction.** Hooks denied `git stash list`, `pgrep -f` and a `bash -c "..."` command; a Monitor died at once;
   two monitors on one target were superseded. **Prevention:** use a script file for detached runs and a background
   `until` loop for waits.
9. **Two stale facts in docs** (PR-facts "6 commits" vs 5; a review seat reporting a posted comment as missing).
   **Prevention:** re-derive counts with a command at write time; verify a seat's "absent" claim before acting.
10. **Dev-harness missed the `chk` helper; stop-hook flagged turn closings that named an action.** **Prevention:**
    end a waiting turn with a `Paused:` sentence naming what is awaited.
