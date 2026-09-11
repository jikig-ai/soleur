---
date: 2026-09-10
issue: 7917
pr: 7976
category: test-failures
module: battery-tag-authorship, test-all, repo-write-boundary
tags: [guards, false-green, mutation-testing, fixtures, instrument-void, shell-parsing]
---

# Learning: I graded lines when the unit was the command, and three predicates inherited it

## Problem

PR #7976 shipped a guard asserting that no `git` command reachable from `scripts/test-all.sh`
authors a tag in the live repository. It was green: 12 assertions, a 16-row mutation battery
reporting 16/16, a clean meta-guard, clean shellcheck, and every deterministic lint at rc 0.

Review found eight P1s. Every one was in the guard's own machinery, not in the code it guards,
and the two sharpest were demonstrated end-to-end against a tree carrying live tag authors that
the guard reported clean.

## Class 1: the grading UNIT was the line; the semantic unit is the command

Three predicates were each written to take "the code line" and answer a question about it. All
three are correct for a line holding one command, and all three are wrong for a compound line --
which is the shape an adversary (or an ordinary refactor) reaches for first.

| predicate | question | how a compound line defeats it |
|---|---|---|
| `_is_in_class` | is this verb tag-authoring? | `git push ... && git tag evil` -- the `push` term declared the WHOLE line out of class |
| `_suppresses` | is tag creation suppressed here? | `git fetch --no-tags origin && git tag evil` -- found `--no-tags` and a `fetch` token somewhere on the line, graded the tag author SUPPRESSED |
| `_in_string_literal` | is this verb inside a string? | a lone apostrophe inside a double-quoted span, earlier on the line, hid a live `git fetch` |

Measured against a hardlink clone with two planted, unsuppressed, undeclared tag authors: the
shipped guard printed `12 passed, 0 failed`, **rc 0**. `occurrences` did not move off its
pristine value -- the lines were never counted at all.

The fix is one idea applied at one place: split the line into commands (quote-aware, so
`echo "a && b"` is not cut in half, and stripping a trailing unquoted comment), then run every
predicate per command. Same clone afterwards: `offenders=2`, rc 1.

**The generalisable question** is not "is this predicate correct?" but *"what is the unit this
predicate quantifies over, and is it the unit the property is about?"* A line is a transport
encoding. It is almost never the semantic unit, and the gap only shows on inputs nobody wrote a
fixture for.

### Two ways I got the fix wrong before I got it right

Both were caught by controls, not by reading, which is the whole argument for keeping controls
on a fix you are confident about:

- `printf '%s' "$line" | ...` emits no trailing newline, so `read` returns non-zero on the last
  partial line and **the loop body never executes**. My first splitter therefore returned "not
  in class" for everything -- strictly worse than the bug, and invisible except that the
  known-good control (`git tag evil` alone) flipped to DISMISSED.
- Splitting on a lone `|` tore `'nonexistent/file.sh|git fetch origin ghost'` -- the guard's own
  ledger key format -- out of its enclosing quotes. The fragment lost the string-literal
  protection that had covered it and reddened the tree. Only `&&`, `||` and `;` separate
  commands; a lone `|` is a pipe and, here, a data delimiter.

## Class 2: a bound on a FIXPOINT is a budget unless exhaustion is a failure

The closure walk was `while (( depth < DEPTH_BOUND ))` with `(( added == 0 )) && break`. Two
exits, one of them a fixpoint and one of them a truncation, and nothing distinguished them.
Measured: `DEPTH_BOUND=1` dropped 83 files from the scan surface and the guard still printed
`12 passed, 0 failed`, rc 0.

A bound is a legitimate **non-termination backstop**. It is not a budget. Exiting on it must be
a failure, and the population it produces needs its own floor -- `MIN_ROOTS` floored the roots
while the closure, which is what the scan actually walks, was floored by nothing.

## Class 3: an exemption channel keyed by PATH constrains how fixtures may be laid out

The guard hides its own fixtures via `FIXTURE_EXCLUSION`, an array of PATHS. I added two more
fixtures to the existing fixture file and wired each mutation row to delete the ones it did not
want. It could not work, for a reason that is structural rather than a bug: a row's `sed` edits
the GUARD copy, while the fixtures live at `REPO_ROOT`. Fixtures sharing a file become visible
together, and a row needing one of them visible reddens on the others.

The rule that falls out: **one fixture per file whenever the exclusion mechanism is path-keyed.**
Rows then select by pointing the slots they do not want at an absent path, which also keeps the
array's size constant so the size assertion still binds.

## Class 4: the battery's own verdict was one deletion from silence

Everything in the battery proved the SUBJECT reddens. Nothing proved the battery could. Deleting
its final one-line verdict made it print `7 passed, 9 failed` and exit 0 -- nine real row
failures, green suite -- and nothing in the repo notices, because `run_suite` judges on the child
rc alone and `guard-vacuity-floor.test.sh` states outright that it never runs a guarded suite to
completion.

Moving the verdict into the `EXIT` trap, re-derived from an append-only log of printed FAIL
lines rather than from the counter the rows move, changes the arithmetic: silencing it now takes
two edits in different constructs. Proven by mutation -- tail-deleted is now rc 1 (was rc 0), and
only trap-and-tail-deleted returns to rc 0. That is a real improvement and not an absolute one;
nothing short of an external gate makes a suite's own verdict unremovable.

Its assertion floor had the sibling defect: the threshold sat four lines from its `if`, so
`guard-vacuity-floor`'s `build_mutant` -- which widens backward over CONTIGUOUS assignments --
lost the binding and scored the floor CONSTRUCTION, i.e. untested. The guard's own comment
documents that adjacency rule in seven lines. Its sibling, in the same PR, broke it.

## Class 5: instrument voids -- a root-deriving script is void the moment you copy it out

Three separate measurements this session were void, all the same way, and each one produced a
plausible number I nearly acted on:

- a `main` shellcheck baseline (`test-all.sh` copied to `/tmp`) -- enumerated nothing, and I
  briefly attributed a pre-existing `ORPHAN_SCAN` line to this diff;
- an old-vs-new emitter timing -- reported 0.16 s vs 0.15 s for three runs;
- the verdict-pinning proof -- both arms rc 1 for a reason unrelated to the mutation.

The mechanism: these scripts compute `REPO_ROOT` from `BASH_SOURCE`, so a copy under `/tmp`
resolves its root to `/` and bails immediately. This is worse than the already-documented
git-deriving case, because that one fails RED (empty corpus, so the guard reports it), whereas
this one **exits 0 having done nothing**, which is indistinguishable from a fast, clean run.

Litmus, before reading any number off a copied script: *did the control produce a NON-EMPTY
result at the copy's location?* If the arms differ by 20x in wall-clock from the in-repo run,
the instrument is void, not fast.

## Class 6: my own comment reproduced the anchor my own mutation asserted on

I wrote a comment explaining the verdict fix and quoted the verdict expression verbatim in it.
The literal then occurred twice, and the mutation's `assert count == 1` failed. This is
`cq-assert-anchor-not-bare-token` -- a rule this repo already carries -- hit inside the prose
written to explain a fix for that class. The existing rule governs *assertions matching a
comment*; it does not say anything about **a comment the same commit adds reproducing a literal
some other check anchors on**. Both directions are the same collision. The same trap fired a
second time in this session at the process level: a heredoc writing this very learning was
blocked by a PreToolUse hook because the prose quoted a forbidden command literal, which is
exactly what `lefthook.yml`'s markdown-lint stanza warns about in its own comment.

## Session Errors

- **Leaked a non-terminating process for 79 minutes.** My first `..`-normalisation used a
  substitution that could not match a leading `../`, so the `while` never exited; it burned a
  core at 4,728 s and inflated the host load, which only surfaced because `test-all.sh`'s
  contention preamble listed it. **Recovery:** SIGKILL -- SIGTERM is ignored by a tight
  builtin-only loop, which never yields to the trap. **Prevention:** after the harness moves a
  command to the background and you supersede it, kill the original by captured PID before
  re-running; and prefer a loop whose body provably shrinks its operand.
- **`kill_mine` called with no pattern** printed usage, killed nothing, and I read that as
  "nothing to kill". **Prevention:** check the exit status, not the absence of output.
- **Reached for the full-command-line form of `pkill`** despite the documented self-match
  hazard; the hook blocked it. **Prevention:** the hook is the backstop, not the plan -- go to
  `plugins/soleur/scripts/lib/proc.sh` first.
- **Three void instrument runs** (Class 5). **Prevention:** the litmus above.
- **`rc=$?` after a pipeline** captured `tail`'s status, so I reported rc 0 for two lints that
  exit 1. **Prevention:** redirect and read `$?`; never pipe a command whose exit code IS the
  result. The repo lints this class in committed scripts; ad-hoc review shell is not scanned.
- **Ran two repo lints without their gate arguments** (`--baseline`, `--allowlist`), producing
  "204 NEW findings" I briefly read as real. **Prevention:** read the `run_suite` registration
  for a lint before invoking it by hand -- the registration carries the arguments.
- **Anchoring `row()` on the FAIL prefix** broke three rows that redden via `[FATAL]`/`ERROR:`.
  **Prevention:** exclude the PASS channel rather than enumerate the failure channels -- the
  former is closed under new failure spellings, the latter is not.
- **A patch script aborted at an anchor mismatch** (fail-safe, nothing written) and I read the
  following output as though it had applied. **Prevention:** assert the file changed before
  reading any result derived from it.
- **A spawned agent returned a status line instead of its report**, despite a spawn-time
  deliverable instruction. **Recovery:** resumed it rather than respawning, preserving context.
  **Prevention:** treat a one-line return as a resume signal, never as a finished agent.
- **Two agents died on a session limit.** **Recovery:** resumed both; the resumed test-design
  pass produced the review's highest-severity finding, which a fresh spawn would have lost.
- **A scope-out I proposed was refused by the CONCUR gate on measured grounds** -- my stated
  cost (install/teardown/interrupt-safety for a git hook) does not exist under env-scoped
  `core.hooksPath`, and my re-evaluation trigger was self-defeating: it required the guard to
  record an offender in a spelling its own regex cannot match. **Prevention:** measure a
  deferral's stated cost before claiming it, and test a trigger by asking what would have to
  happen for it to fire.

## Prevention

- Ask of every predicate: *what unit does it quantify over, and is that the unit the property is
  about?* Line-vs-command is the commonest mismatch in shell guards.
- A depth bound on a fixpoint must distinguish converged from exhausted, and the population it
  produces needs its own floor.
- One fixture per file when the exclusion mechanism is path-keyed.
- A suite's verdict should read an append-only observable and live somewhere a single deletion
  cannot reach.
- Before believing a number from a copied script, confirm the copy produced a non-empty result
  at its new location.
