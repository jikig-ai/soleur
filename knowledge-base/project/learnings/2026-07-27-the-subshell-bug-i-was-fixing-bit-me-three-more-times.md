---
title: "The subshell bug I was fixing bit me three more times in the same session"
date: 2026-07-27
category: logic-errors
module: scripts
tags: [bash, subshell, command-substitution, tempfile-cleanup, tmpfs, fail-open, mutation-testing, vacuous-test]
symptom: "/tmp tmpfs full; tool output unwritable; 3,766 leaked files across weeks"
root_cause: "A cleanup-array append inside a command-substitution subshell is discarded, so the EXIT trap owns nothing"
related_prs: [6986]
related_issues: [6734, 6789, 6991, 6992]
---

# The subshell bug I was fixing bit me three more times in the same session

## Problem

`/tmp` — a 4 GiB RAM-backed tmpfs — repeatedly filled to 100%, wedging agent
sessions. At its worst `du` itself could not write its own output.

The source was `scripts/followthroughs/anthropic-admin-key-6297.test.sh`:

```bash
TMP_PATHS=()
trap cleanup_tmp EXIT INT TERM
mktmp()  { local p; p=$(mktemp "$@");    TMP_PATHS+=("$p"); printf '%s' "$p"; }

f=$(mktmp -t ft.XXXXXXXX)      # <-- command substitution == SUBSHELL
```

Every call site invoked the helper via `$( )`. Command substitution runs the body
in a subshell, so `TMP_PATHS+=("$p")` mutated a copy that vanished on return. The
parent array stayed empty for the entire run and the EXIT trap iterated nothing.

Measured: **36 leaked files per run, 3,766 orphans accumulated**, oldest 7 days.

## The generalizable lesson

**The same defect class appeared FOUR times in one session — three of them in code
written to fix it, by an author who had just spent hours characterizing it.**

| # | Site | Failure mode |
|---|---|---|
| 1 | The original leak (`TMP_PATHS+=` in `$( )`) | silent, 3,766 files |
| 2 | `run_sut` in `raise-tmp-tmpfs-ceiling.test.sh` | loud (`RC: unbound variable`) |
| 3 | `resolve` in `scratch-root.test.sh` | loud (identical) |
| 4 | `die` inside `mem_total_bytes` `$( )` | **silent, fail-open** |

Occurrence 4 is the one to build the rule around. `die` calls `exit 1`, but inside
`$( )` that exits only the subshell. The parent continued with an empty value,
computed a target of 0 bytes, satisfied its never-shrink guard trivially
(`cur >= 0`), and **printed FATAL then exited 0 having done nothing**. Review found
it; I did not.

**Rule:** a shell function is only safe to call as `x=$(fn)` if its ONLY contract is
stdout. The moment it assigns a caller-visible variable, mutates an array, or calls
`exit`/`die`, `$( )` silently discards that half of its behavior. Either return the
value through stdout and check `$?` in the parent, or call the function directly and
let it set globals — never both.

Awareness is not protection. I knew this class cold and still wrote it three times.
The mitigation has to be mechanical (the linter below), not vigilance.

## Why five deployed layers all missed it

Each was measured, not inferred:

1. **The CI guard returned ZERO findings.** `scripts/lint-trap-tempfile-ownership.py`
   exists for exactly this defect and ships a `bad-subshell-append` fixture. Two
   independent blind spots had to line up: `ARRAY_APPEND` was `^\s*`-anchored (the
   helper is a one-liner, so the append sits mid-line after two `;`), AND
   `trap_owned_arrays` harvested `${VAR}` refs only from the trap LINE, while the trap
   names a FUNCTION (`trap cleanup_tmp EXIT`) containing no `$` at all. **Either fix
   alone yields 0 findings across 689 files.**
2. **The janitor was structurally blind.** `scripts/tmpfs-guard.sh` runs `*/5` on the
   user crontab with `SCRATCH_MIN_MB=100`. Largest leaked artifact: **372 bytes**.
   `tmp.*` entries over 1 MB: **0 of 11,172**. A size-thresholded reaper cannot see a
   count-shaped leak.
3. **Its alarm fired 94 times into channels nobody reads.** The "nothing reapable
   found" branch is documented for precisely this scenario. It reaches `logger` (an
   unwatched journal) and `notify-send`, which no-ops under cron with no DBUS session
   and is suppressed by `2>/dev/null || true`.
4. **Its telemetry read healthy and was fabricated by its own tests.** 346 `Reaped`
   journal lines in 14 days; **344 came from fixture roots** created by
   `tmpfs-guard.test.sh`. Real `/tmp` was reaped **once**.
5. **The detector that would have caught it reported to `/dev/null`.** `run_suite()`
   in `test-all.sh` already computed a per-suite `/tmp` delta, gated behind
   `TEST_TIMING_LOG`.

Every layer reported success while doing nothing. That is the through-line, and it is
why the fix had to be held to the same standard.

## Solution

- Drop path tracking entirely: one scratch root, `TMPDIR` pointed at it, trap removes
  that one directory. No registration step left to get wrong.
- Guards are load-bearing, not style. The file is `set -uo pipefail` with **no `-e`**,
  so a failing `mktemp -d` does not abort: unguarded, `TMP_ROOT=""` sends `TMPDIR`
  back to `/tmp` and makes `rm -rf -- ""` a no-op, restoring the leak while the run
  looks clean. `readonly TMP_ROOT` is required because the trap body is single-quoted
  hence **late-bound**.
- Widen the linter on both axes (command-position `ARRAY_APPEND` + `.search()`, and
  one level of named-function trap resolution).

Measured: **36 leaked entries before, 0 after**, same suite and isolated `TMPDIR`.

## Review-phase learnings (the highest-value ones)

- **A regression test that re-declares the correct idiom inline is decoupled from the
  file it guards.** My test drove a heredoc child rather than the real suite. Reverting
  the real header to the leaky form leaked 34 orphans while the test printed **PASS**.
  A regression test that cannot observe its own regression is worse than none: it
  certifies the bug fixed. Fix: run the actual file under a sentinel `TMPDIR`
  (recursion broken by an env guard) and assert zero survivors.
- **`--dry-run` verification proves nothing about a path `--dry-run` returns before
  reaching.** I reported "verified `--dry-run` against the real `/etc/fstab`" as
  evidence the script worked. It aborted on every real invocation, because `--dry-run`
  exits before `validate_candidate`. **Ask which branches your verification command
  actually executes.**
- **A validator no fixture can drive is dead weight.** `return 0` at the top of
  `validate_candidate` left the suite 21/21 green — all five branches unreachable, and
  the "only unbootable path" test passed because `awk` happened to be correct. Needed a
  test-only render-hook seam to make the branches reachable.
- **`cp -p` is wrong for backups you intend to age out.** `-p` preserves the SOURCE
  mtime, so a prune sorting by mtime sorts by "age of the file that was copied" — and
  deleted the pristine pre-change `/etc/fstab` first, precisely the artifact a bad
  rewrite needs. Sort by a stamp embedded in the filename.
- **Widening one regex without widening its exemption partner creates a false
  positive.** `ARRAY_APPEND` went command-position; `declared_local` stayed
  `^\s*`-anchored; correct one-liner helpers with `local paths=()` were then flagged.
  On a guard running over 689 files a false positive is worse than a miss — **a guard
  that fires on correct code gets switched off.**

## Process learnings

- **Ask the reviewer to find the vacuity your battery missed, not to re-run it.** The
  prompt "find what my verification could not see — do NOT re-run my mutations"
  produced the two most valuable findings. A self-run mutation battery only covers the
  mutations its author imagined.
- **Mutate a sandbox copy.** Four agents ran concurrently on one worktree; in-place
  mutation would have surfaced to the other three as false "uncommitted drift" P1s.
- **Assert the mutation LANDED** (`diff -q` against a pristine backup) **and that the
  un-mutated baseline is GREEN in the same harness.** A baseline-identical result is
  UN-RUN, not evidence.

## Session Errors

**`pkill -f "scripts/test-all.sh"` matched its own command line** — killed the invoking
shell (exit 144) and the monitor watching the run.
**Prevention:** never `pkill -f` a pattern that appears in the pkill command itself;
match on a resolved PID, or use a pattern the command line cannot contain.

**Premature docstring close** while editing `trap_owned_arrays` produced a SyntaxError
whose `exit=1` looked exactly like a successful lint detection.
**Prevention:** after editing a Python file, `ast.parse` it before interpreting any
exit code as a result.

**`SyntaxWarning: invalid escape sequence '\$'`** from a regex quoted in a new
docstring. **Prevention:** use `r"""` for any docstring containing backslashes.

**`run_sut` and `resolve` harnesses lost `RC` to command substitution** (occurrences
2 and 3 of the session's defining class). **Prevention:** the linter fix in this PR;
plus a harness helper that sets caller-scope variables must never be invoked as
`x=$(helper …)`.

**`""close)` typo** in a `case` statement — a paste artifact that shellcheck did not
flag because it is syntactically valid. **Prevention:** run the suite after every edit,
not after every batch.

**`git push` rejected non-fast-forward** after an earlier rebase rewrote already-pushed
commits. **Prevention:** expect `--force-with-lease` after any rebase of a pushed
branch.

**`findmnt --verify` used as an absolute gate** rejected every fixture, because it
resolves source devices and fixtures carry synthetic UUIDs.
**Prevention:** a validation tool that inspects the ENVIRONMENT, not just the artifact,
must be applied differentially (fail only on a regression vs the original).

**`wc -l` vs `awk END{print NR}`** — `wc -l` counts newlines, so a file lacking a
trailing newline read one line short and adding the newline looked like a line-count
change. **Prevention:** count records, not newlines, whenever the code may add one.

**A test asserted a lexical `/tmp` prefix instead of containment**, failing as a
fixture artifact rather than a real defect. **Prevention:** assert the property
(containment in the configured base), not a proxy for it.

**Cited `--dry-run` as verification of a path it returns before reaching.**
**Prevention:** see the review-phase learning above — name the branches your
verification command executes.

**Six P1s reached review**, two of them inside this PR's own guards.
**Prevention:** the mutation discipline above, applied before review rather than after.

**Planning subagent skipped `deepen-plan`, lost 2 of 7 reviews, and self-reported a
fabricated attribution.** **Prevention:** treat a subagent's factual claims as
hypotheses; every load-bearing one in this session was independently re-measured, and
one (`*/5` cron) was only confirmable on the host, not in the repo.

**Bulk checkbox marking via a loop of `perl` replacements** silently no-matched on
several patterns, so the remaining-count summary I reported was misleading.
**Prevention:** a checkbox is a CLAIM — mark them individually against verified
evidence, and assert the replacement landed.

## Related

- #6991 — tmpfs-guard janitor: size-floor blindness, unread alarm, self-polluted telemetry
- #6992 (P1) — `iac-plan-write-guard.sh` `pipefail` + `grep -q` SIGPIPE race making every
  policy check fail OPEN
- ADR-129 / #6734 — the shell cleanup-ownership rule this PR widens
- #6789 — the tmpfs contention instrumentation whose delta counter was gated off
