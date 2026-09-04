---
module: Test Fixtures
date: 2026-09-04
problem_type: logic_error
component: testing_framework
symptoms:
  - "a guard could be silenced eight ways while its suite reported 46 passed 0 failed"
  - "46% of a shrink-only baseline was resolvable false positives"
  - "a mutation closed in one round survived when moved one line up in the next"
  - "a heredoc repair hid 1864 more lines than it unhid"
root_cause: logic_error
resolution_type: code_fix
severity: high
tags: [guards, mutation-testing, anti-vacuity, review, bash, shell-parsing]
synced_to: [review, work]
---

# Three review rounds, each finding defects in the last round's fixes

**PR:** #7810 · **Closes:** #7708 · **Predecessor:** #7770 (P1a burn-down)

## Problem

Issue #7708 asked for a P1b rule: an operand that can be RELATIVE, or rooted at `/` by an empty parent.
The rule shipped, and three review rounds found **28 P1s**.

| round | P1s | inside the PREVIOUS round's fixes |
|---|---|---|
| 1 | 12 (8 scanner, 4 suite) | — |
| 2 | 9 | 5 |
| 3 | 7 (1 live, 6 latent) | 3 |

The #7770 lesson was "the defects are in the verification, not the fix." This is the sharper version:
**when you fix the verification, your fixes become the next round's defect surface.** Rounds 2 and
3 spent most of their findings on code written to close the round before.

## Solution

### The thing that broke the regress: delete, do not patch

Two heuristics kept producing a new bypass per round.

`_case_proves_absolute` — an inline `case` guard — was defeated four ways, each verified against
real bash: an extra `fixtures/*)` allow-arm (and an allowlist arm is exactly WHY someone writes an
inline case), `exit` inside a double-quoted message on the default arm, a catch-all `*)` placed
before `/*)`, and a sound validator whose return code the caller ignores.

A guard-window widening I had ADDED — to make my own remediation register — was defeated by six
assignment spellings (`read`, `for`, `printf -v`, `+=`, `(( ))`, `mapfile`), and then, after I
narrowed it to a "the name is read-only here" test, by a **helper call that mutates the global** and
by `eval "VAR=..."`, which quote-stripping erases before the check runs.

Neither is a spelling a pattern list can close; both are the limit of reading one function's text.
Deleting both closed six silencing paths in one edit instead of six patches, at the honest cost of
false positives. Round 3 confirmed the deletions could not be defeated — every remaining bypass was
in code that was KEPT or newly ADDED.

> A widening added to make your own fix look successful is the worst kind. I wrote one, and it took
> two rounds to remove.

### Fix the CONTEXT, not the OPERATOR

The single most repeated shape of my own error:

- Round 2 fixed `<<<` being read as a heredoc opener (299 lines hidden). Round 3 found the same
  class one level up: a `<<DELIM` inside a **quoted string** — `echo "BODY<<END"`,
  `sed -e '1{/^<<EOT$/d}'`, an awk program containing `<<'NICEOF'`. **1806 lines across 13 files**,
  6x larger. I had fixed the operator and not the context.
- Round 2 closed a mutation that pointed `compare_rows` at the baseline. Round 3 moved the identical
  edit ONE LINE UP — `LIVE_ROWS=$(baseline_rows)` — and it survived GREEN at 46/46, because the
  "independent totals arm" I added derived BOTH operands from `$LIVE_ROWS`, the variable the arm it
  was policing already consumes. I had pinned the spelling, not the class. The genuinely independent
  observable, the scanner's own `SITES=` line, existed the whole time and was printed three lines
  away in a decorative echo reading 1274 while both arms asserted 1273.
- I deleted the inline `case` guard partly because "a validator whose return code the caller
  ignores" cannot be detected. That defect applied verbatim to the ONE form I kept:
  `msg=$(assert_fixture_dir "$d")`, a pipeline, and an explicit subshell all cleared sites, and in
  all three the guard's `exit 2` never reaches the script.

### A repair that made it worse, caught only by measuring the direction

My first quoted-heredoc fix scanned ALL matches for the first unquoted one. That finds openers the
original single-match form never considered, and **hid 1864 further lines** — one file went 0 to 910
skipped, its entire body. I caught it because the count moved 36 rows the wrong way and the baseline
header I had written says a shrink deserves the scrutiny a growth would get.

The shipped repair tests only the FIRST match's position, so it can unhide and never hide: 3804
lines returned across 31 files, P1a unmoved at 9. A second repair was measured and rejected —
blanking quotes before the search destroys the real delimiter in `cat > "$f" <<'EOF'` (+155/-12,
P1a 9 -> 21).

> When rewriting a function that decides what gets SCANNED, diff its behaviour over the whole corpus
> in both directions and require the unsafe direction to be empty. Here: "files skipping MORE than
> before must be 0."

### Numbers I published that were wrong

- **"118 of 232 source directives resolve"** — `git grep -cE ... | wc -l` counts FILES. Real: 399
  directives, 142 resolving. Wrong in both numbers AND in the noun.
- **"`-t` names a directory"** — it does not. `mktemp -d -t p.XXXX` is TMPDIR-based and IDENTICAL to
  bare `mktemp -d` (measured: `/tmp/pre.RRbk`; `TMPDIR=rd` sends both relative together). One
  misclassification, **783 baseline rows, 38%**, and inverted on its own stated axis: the form that
  cannot go relative was reported while the form that demonstrably can was cleared.
- **"39 sites over 12 files"** survived into round 3's header as a stale round-1 number while the
  family table ten lines above said 16/5.

Reviewers caught all three.

### Declining a reviewer, with cause

A reviewer recommended clearing `$(cd X && pwd)` as absolute (24 rows). `pwd` always prints an
absolute path — but when the `cd` FAILS the `&&` short-circuits and the substitution is EMPTY,
making `"$X/sub"` into `/sub`: the ROOT-ANCHORED family this same rule covers. #7709 made and
retracted that exact claim. **A well-argued recommendation that a sibling PR already retracted is a
decline, not a finding.**

## Key Insight

**Convergence looks like findings moving from live to latent, not like a clean round.** Live defects
fell 12 -> 5 -> 1 while total findings fell 12 -> 9 -> 7. Expecting a zero-finding round from a
scanner that approximates shell semantics is the wrong bar; the right bar is that the remaining
findings cannot be reached by any input the corpus contains, and that each is pinned by a must-FAIL
arm so re-introducing it reddens.

The corollary is that **deletion is a legitimate response to a review finding.** Two heuristics
absorbed 11 of the 28 P1s across three rounds. Removing them cost false positives and bought a
surface that the third round could not defeat.

### Instrument yields were disjoint, again

| instrument | cost | found |
|---|---|---|
| shellcheck + 4 repo lints | ~30 s per round | 0 findings across all three rounds |
| 6 review agents | hours | 28 P1s |

Same split as #7770. Run the cheap gates first anyway — they cost nothing and they clear a class.

Separately: the suite ran six full-corpus scans per invocation, 120s. Reusing one scan cut it to
21s. Six scans is a cost CI pays forever for no additional signal.

## Prevention

- When an agent will MUTATE repo files, give it `isolation: "worktree"`. Never edit files an agent
  is working on.
- Replace functions by name-anchored span, never by a region between two unrelated landmarks, and
  assert every expected symbol still exists afterwards.
- Generate regex-bearing code from raw strings or a quoted heredoc, and assert the written file
  contains no control characters.
- Scope a mechanical edit to lines the branch itself added (`git diff origin/main...HEAD`), and
  assert the pre-existing count is unchanged.
- For a detector change, measure the corpus delta in BOTH directions and require the unsafe
  direction to be empty.
- A guard must be an executed STATEMENT whose failure reaches the script — not a mention in a
  comment, in prose, in `$( )`, left of a pipe, or in a subshell.

## Session Errors

1. **Ran review agents that mutate-and-restore files in the shared worktree, then kept editing those
   same files.** Every `restore()` wrote back the agent's start-of-run snapshot and silently
   reverted my work; I re-applied the same two fixes three times and spent several cycles
   diagnosing "lost" edits. The Agent tool's own output says not to work on files an agent is using.
   Recovery: saved pending work to a scratch dir, stopped editing, waited.
   **Prevention:** give any repo-mutating agent `isolation: "worktree"` — done for round 3, and the
   problem disappeared entirely.
2. **A region-based edit deleted five helper functions.** The span ran from the mktemp constants to
   `_classify_value` and swallowed `_extract_value`, `_function_bodies`, `_literal_tail`,
   `_extended_funcs` and `_strip_quoted`. Recovery: `NameError` on the next run, restored from HEAD,
   redone with per-function anchors.
   **Prevention:** replace by name-anchored function span; assert every expected symbol survives.
3. **Wrote a regex through a non-raw Python string**, so `\b` became a literal backspace and
   `\x08(?:exit|return)\x08` could never match. My hand-typed debug used a raw string and passed, so
   probe and module disagreed and I chased the wrong cause. Recovery: scanned the file for control
   characters.
   **Prevention:** generate regex-bearing code from raw strings or a quoted heredoc; assert no
   control characters in the output.
4. **A remediation script deleted 13 PRE-EXISTING guards** from #7709's burn-down, keyed on a
   pattern that matched more than the branch had added. Recovery: caught because the `git -C` count
   jumped 0 -> 43; reverted and redone by exact line with context assertions.
   **Prevention:** scope mechanical edits to `git diff origin/main...HEAD`; assert the pre-existing
   count is unchanged.
5. **`git stash list` denied by the guardrail hook** — the same reflex #7770's learning already
   recorded a prevention for, so that prevention is not sticking.
   **Prevention:** the rule is stash-FAMILY, including the read-only `list`. Use
   `git show <sha>:<path>`.
6. **Read a two-dot diff as the branch's own changes** and briefly reported 68 files / 4967
   deletions; the real diff was 8 files. Recovery: re-ran with three dots.
   **Prevention:** `origin/main...HEAD` (three dots) for "what this branch changes", always.
7. **A backtick inside a double-quoted arm label** is command substitution, not formatting.
   Recovery: shellcheck caught it before commit.
   **Prevention:** single-quote any label containing shell metacharacters.
8. **My `heredoc_lines` rewrite hid 1864 more lines than before** — it dropped the original's
   comment-line check and changed `.search` to `.finditer`. Recovery: caught by a 36-row move in the
   wrong direction; minimised the change to a position test on the first match only.
   **Prevention:** diff a scanning function's behaviour corpus-wide in both directions; the unsafe
   direction must be empty.
10. **The pre-commit hook's own test run rewrote my branch**, creating `base`/`change` commits and
    moving the tip; the reflog shows it recurring. Recovery: reset the branch back to the real
    commit (still an object), reverted the test's file edits, verified the pushed remote was
    untouched. Root cause proven: `GIT_DIR`, which hooks export, overrides `cwd` and `-C`. Filed
    as #7833.
    **Prevention:** scrub `GIT_DIR`/`GIT_WORK_TREE`/`GIT_INDEX_FILE` in test fixture helpers rather
    than relying on `cwd` or `-C`; a shared helper beats per-call scrubbing because the failure is
    silent.
9. **Published three wrong counts** (see above). Reviewers caught all three; the one I found myself
   surfaced only because a reviewer's contradicting figure made me re-derive it.
   **Prevention:** publish the command beside any count. `grep -c` counts LINES PER FILE; piping it
   to `wc -l` counts FILES.

### A live instance of this rule's own defect family, found by the pre-commit hook

While committing this learning, the lefthook `pre-commit` hook ran `bun test plugins/soleur/test/`,
which **created commits on the live branch and moved its tip**. The reflog shows it had happened
repeatedly. Recovered without loss; filed as #7833.

The test is written correctly: it builds a fixture with `mkdtempSync(join(tmpdir(), ...))` and
passes `cwd: dir` to every `execFileSync("git", ...)`, including `git init -q`.

**`GIT_DIR` beats `cwd`, and beats `-C`.** Git hooks export `GIT_DIR`; the subprocess inherits it;
git honours it over the working directory. Measured on a scratch pair of repos:

```
control (no GIT_DIR):     fixture HEAD 4642194 fixture-commit   victim 252b065 victim-base
GIT_DIR=<victim>/.git:    fixture2: fatal: not a git repository
                          victim  HEAD 48c8c8c PHANTOM   <- the commit landed HERE
```

So under a hook, EVERY git-using test writes into the developer's real repository no matter how
carefully it scopes its fixture, and `git init -q` silently initialises nothing.

This is the #7708/#7709 family one level deeper. Those cover an OPERAND that fails to control which
repository you write to. This is a correct operand **overridden by the environment** — and no
operand guard, including the one this PR ships, can see it. Worth stating plainly: the rule in this
PR would not have caught the bug that corrupted the branch it was committed on.

## Related

- `knowledge-base/project/learnings/2026-09-03-every-p1-was-in-the-verification-not-the-fix.md`
- `knowledge-base/project/learnings/2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md`
- #7808 tracks the grandfathered burn-down (1225 sites over 259 rows).
