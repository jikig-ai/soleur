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
   option-shaped first argument, no leading `/` or `..` in a path, `python3 -m` only `unittest|pytest`, zero removed lines, and an anchor rule (the nearest preceding non-blank, non-comment post-image line must
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

## Session Errors

- A table-driven battery rebuilt its scratch repos in a directory name derived only from the row name, so the second and third runs (the
  permissive and reject-all stubs that prove the table can see a broken classifier) inherited the first run's edits. Their "reddened N
  rows" counts were inflated by stale state until each call began from a freshly removed directory. A stub-based discrimination check is
  only evidence if every run starts from the same state.
- A first mutation battery over the classifier scored every mutant as caught for that same reason. The control row (the unmutated
  classifier must score 0) was what exposed it: read the control before reading any mutant.
- One mutant (`bun x` allowed) survived the first table because the later path-charset check happened to reject the one row's operand. It was
  not equivalent: `bun x cowsay` passes that charset. A survivor needs a row that removes the second line of defence's coverage, not a
  decision that the mutant is harmless.

## Prevention

- When adding a suite, expect the runner-edit path: use `bash scripts/test-all.sh --print-selection` to preview and read the banner's
  `first:` offender if the run goes full. A registration-only edit needs each added line to sit directly below another single-line
  registration; a first-in-group insertion is refused on purpose.
- Any future check that keys on "this file changed" should first measure how often ordinary work changes that file.

## Tags

category: workflow-patterns
module: scripts/test-all.sh
tags: affected-gate, runner-changed, fail-closed, closed-grammar, registration
