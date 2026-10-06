# Learning: registering a suite is itself a runner edit, so the gate that guards the runner taxed every new suite

## Problem

`scripts/test-all.sh` degrades `--affected` to the full battery (`AFFECTED_FALLBACK reason=runner-changed`) for any diff that touches it or
`scripts/lib/test-affected-paths.sh`, because those two files are the selection logic and an edit could narrow the selection that judges it.
But registering a new suite requires editing exactly those files: a `run_suite` line, and an index declaration whenever the orphan census
asks for one. So every PR that added a suite paid the whole battery. One was stopped after 2 h 13 m of contended local run, and the run
printed only `MODE=full (degraded: runner-changed)`, with no cost and no way out, so it read as a hang.

## Solution

A closed-grammar classifier over the runner-file diff (`_aff_classify_runner_diff`, ADR-242 decision 20). A diff takes the bounded selection
only when every changed line is a new single-line `run_suite` registration (or a blank or comment line directly below one), optionally with
the `AFFECTED_*_PATHS` block or `ALWAYS_ON_SUITES` entry for a suite the same diff registers; any other line, in any hunk of either file, keeps
`runner-changed`. The degraded banner now states the cause, the manifest-weight cost, the first offending
`<file>:<line> [rule-code]` and the preview and scope commands, and `--help` has a `RUNNER EDITS` block.

## Key Insight

1. **A guard and the thing it guards can share a file, and then routine work trips the guard.** Check what a normal contribution touches
   before deciding a path-based trigger is "rarely hit". Here 61.5% of the 226 runner-touching commits since 2026-06-01 were plain
   registrations; the trigger was the common case, not the exception.
2. **Do not model the language; allow whole-line shapes and default to the full battery.** The tempting design is to parse the runner. The
   closed grammar models none of bash's syntax: one line shape, a closed charset (no quote, substitution, redirect, `;`, `&`, `|`), no
   option-shaped first argument, no leading `/` and no `..` segment in a path, `python3 -m` only `unittest|pytest`, zero removed lines, and an anchor rule (the nearest preceding non-blank, non-comment post-image line must
   itself be a registration) that keeps added lines out of backslash continuations, heredocs and multi-line strings. Every miss falls toward
   the full battery, which is why the 2026-09-29 rejection ("fragile diff-content inspection") did not apply to this shape.
3. **Text cannot see what loops and globs generate.** About half of the live registrations come from loops and `SUITE_GLOBS`, so a label
   absent from the file as a literal can still exist. Label uniqueness is therefore decided by the live `--enumerate-commands` stream, after
   the walk, and a violation degrades through the existing fallback print block, never through a new `elif` arm (a dedicated arm consumed the
   chain and produced a silent full battery in #9197).
4. **The honest saving is a ratio, and it is smaller than the pain.** Manifest weights: full battery 91.4 min, bounded selection 58.6 min,
   a 36% saving. The 43 edge suites cost 36.9 min and 13.6 min of them are heavy batteries that reach the runner only through
   self-inclusion; dropping those is a separate design (tracked on #9564).
5. **A banner that prints diff text is an injection channel.** The output is read by agents, so the banner prints only a path, a line
   number, a fixed rule code and, for label findings, the charset-restricted label (spaces shown as `_`, cut at 64 characters); a row feeds it an offending line carrying a forged `AFFECTED_SUMMARY` record, an ANSI escape and instruction
   prose and asserts none of it reaches the output.

6. **A classifier that reads `git diff` judges what git believes, not what the shell will run.** Pair every diff-side rule with a
   byte-side check: the `index <a>..<b>` blob id of each diffed file must equal the hash of the RAW working-tree file, and a trigger file the
   diff does not mention must equal its merge-base blob. `skip-worktree`, `assume-unchanged` and clean filters all make the diff and the
   file disagree, and a file hidden that way is missing from the diff altogether.
7. **Say what the verdict does not cover.** It judges the two trigger files only; a registration that rides along with an edit to another
   runner-sourced file gets that file's ordinary edge-based selection, exactly as editing it alone does. That is documented in ADR-242
   decision 20 rather than left implicit.

## Session Errors

- **New suite code moved a repo-global ratchet and only a review seat saw it.** `build_sandbox` gained a `cp` under a `mktemp` root, taking
  `fixture-relative-assert`'s baseline for `scripts/test-all-affected.test.sh` from 9 to 10 sites; the implementation ran the targeted suites
  and the new rows but not the sibling fixture ratchets. Recovery: `--write-baseline` in the same commit. **Prevention:** run the fixture
  ratchets (`fixture-relative-assert`, `fixture-dir-operand-assert`, `git-fixture-containment`, `fixture-cd-containment`,
  `fixture-env-adoption`) and `guard-vacuity-floor` before the FIRST commit of any change that adds test fixtures (work §6.6 already says
  so; it was skipped, not missing).
- **A completion monitor keyed on "the seat's output file is non-empty" fired immediately.** An agent's transcript file exists from its first
  tool call, so the condition was true while the seat was still working. Recovery: wait for the real completion notification.
  **Prevention:** the notification is the only completion signal; a monitor must key on a terminal marker, never on file existence.
- **Equivalent mutants authored by the author.** `break` placed after an offence that had already been recorded, and `${_u##_}` in place of
  `${_u#_}` (the pattern `_` matches one character, so both strip one), each scored "survived" and read as a coverage gap until the mutant
  was shown to be a no-op. **Prevention:** before crediting a survivor, state the input on which the mutant and the original differ, and
  run it; a mutant with no such input is equivalent and needs no row.
- **A diff-reading classifier judged what git believed, not what bash would run.** A review seat found that `skip-worktree`,
  `assume-unchanged` or a clean filter let a working-tree file carry bytes the diff never shows; the verification seat then found the same
  hole for the OTHER trigger file, which is absent from the diff entirely. **Prevention:** see Key Insight 6.


- A table-driven battery rebuilt its scratch repos in a directory name derived only from the row name, so the second and third runs (the
  permissive and reject-all stubs that prove the table can see a broken classifier) inherited the first run's edits. Their "reddened N
  rows" counts were inflated by stale state until each call began from a freshly removed directory. A stub-based discrimination check is
  only evidence if every run starts from the same state. **Prevention:** build each scratch repo in a freshly removed directory per call.
- A first mutation battery over the classifier scored every mutant as caught for that same reason. The control row (the unmutated
  classifier must score 0) was what exposed it: read the control before reading any mutant. **Prevention:** run the unmutated control first and
  require 0 bad rows before reading any mutant.
- One mutant (`bun x` allowed) survived the first table because the later path-charset check happened to reject the one row's operand. It was
  not equivalent: `bun x cowsay` passes that charset. A survivor needs a row that removes the second line of defence's coverage, not a
  decision that the mutant is harmless. **Prevention:** for each survivor name an input on which it differs from the original.

## Prevention

- When adding a suite, expect the runner-edit path: use `bash scripts/test-all.sh --print-selection` to preview and read the banner's
  `first:` offender if the run goes full. A registration-only edit needs each added line to sit directly below another single-line
  registration; a first-in-group insertion is refused on purpose.
- Any future check that keys on "this file changed" should first measure how often ordinary work changes that file.

## Tags

category: workflow-patterns
module: scripts/test-all.sh
tags: affected-gate, runner-changed, fail-closed, closed-grammar, registration
