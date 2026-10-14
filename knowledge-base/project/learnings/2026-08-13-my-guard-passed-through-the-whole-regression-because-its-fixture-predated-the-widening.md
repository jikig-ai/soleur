---
title: "My guard passed through the whole regression because its fixture predated the widening"
date: 2026-08-13
category: test-failures
module: plugins/soleur/scripts/lib
issue: 7525
pr: 7531
tags: [mutation-testing, fixtures, guards, widening, bash, review]
---

# My guard passed through the whole regression because its fixture predated the widening

## Problem

#7525 asked for `proc.sh` — an executable replacement for a prose rule against self-matching
`pkill`. Two review rounds found twelve defects. Every single one was in a **fix**, not in the
original design. The general shape ("a fix reintroduces the class it closes") was documented one
day earlier in [[2026-08-12-every-fix-i-shipped-reintroduced-the-class-it-closed]] and recurred
here anyway, so this file records only the parts that document does not: a specific,
mechanically-checkable reason a guard fails to notice, and a second instance of a class the
same PR had already paid to fix.

## A widening fix leaves the existing guard's fixture on the OLD side, by construction

Round one found that `timeout 600 bash suite.sh` was invisible to the matcher — `argv[0]` is
`timeout`, not a shell, so a real test run could not be found. The fix let the matcher step over
wrapper commands.

That widening turned the argv-position rule into a bare basename match over the whole argv:

| cmdline | classified |
|---|---|
| `grep -rn test-all.sh scripts/` | refused ✅ |
| `timeout 600 grep -rn test-all.sh scripts/` | **mine** ❌ |
| `env FOO=1 grep -rn test-all.sh scripts/` | **mine** ❌ |
| `nice -n 10 cat notes/test-all.sh` | **mine** ❌ |

So `kill_mine test-all.sh` would kill the operator's own grep — from inside their own worktree,
where the cwd boundary cannot save them. That is verbatim the harm the rule exists to prevent.

**The mutation that exists to catch exactly this — M4 — passed throughout.** Its fixture is
`grep test-all.sh` with no wrapper, i.e. the branch that still worked. The guard was intact and
the property was gone, and no amount of re-running the battery would have said so.

This is not bad luck, it is structural: **a widening admits a region that no pre-existing fixture
can occupy, because every existing fixture was written against the narrower predicate.** The
guard's silence is guaranteed, not probable.

**Gate.** When a diff WIDENS a matcher, allowlist, predicate, or regex, add a fixture in the
**newly-admitted region** in the same commit, and mutation-prove it. The question to ask is not
"does the existing guard still pass?" — it will — but *"what does this now accept that it did not
accept before, and which fixture lives there?"* If the answer is "none", the widening is unguarded
regardless of how green the suite is.

Corollary for reviewers: a passing mutation row is evidence about its own fixture, never about the
predicate. When a PR both fixes an over-narrow guard and keeps that guard green, treat the green as
the thing to explain.

## The same defect class, twice, in one PR — the second time inside the fix for the first

**Instance 1.** `_proc_scan` emitted `class<TAB>pid<TAB>cwd` and the consumer parsed it back with
`IFS=$'\t' read`. A directory name may legally contain a newline and `/proc/<pid>/cwd` reports it
verbatim, so a process whose cwd was a directory named `evil\nsignal\t31337\t/pwned` **forged a
`signal` row**. Measured: pid 31337 reached the kill site having never matched the pattern, never
been classified, and never had its cwd tested. The carrier itself was correctly *refused* — the
refusal path was the injection vector, so a correct boundary check did not help, and `list_runs`
rendered the forged row as a genuine `mine` entry, so the dry run confirmed the lie.

Fixed by removing paths from the channel entirely: it now carries a class token from a closed set
plus a pid that is numeric by construction.

**Instance 2.** Round one also found that in the ordinary `main/.worktrees/x` layout the main
checkout's toplevel is a strict prefix of every worktree beneath it, so running from the parent
classified every sibling worktree's processes as ours. The fix enumerated worktrees and excluded
them — by parsing `git worktree list` with `${line%% *}`, joining the results into a
space-delimited string, and re-splitting with an unquoted `for`.

That is **a path in a delimiter-sensitive text channel**: the same class, inside the guard written
to close a different instance of it. Measured: a worktree at `.worktrees/my branch` truncated to
`.worktrees/my`, matched nothing, and was not excluded — the cross-worktree kill, restored through
the new guard.

**Gate.** After fixing a defect, grep the fix itself for the defect's own shape before committing.
For this class the shapes are enumerable: `${var%% *}` / `${var%%<TAB>*}` applied to a path, an
unquoted `for x in $list` over paths, `IFS=$'\t' read` where any field is a path, and any
`printf`-joined accumulator of filesystem paths. Paths carry newlines, tabs, spaces and globs;
arrays and `--porcelain`/`-z` output do not have this problem.

## Two smaller ones worth naming

**A backtick inside a double-quoted string is command substitution — including in a test label.**
`check_row 1008 mine "T-WRAP: \`timeout 600 bash <suite>\` is selected"` executed its own label
content, producing a syntax error that masked a genuine failure underneath. `work/SKILL.md`
documents this for commit messages; it applies to every double-quoted string.

**A grep assertion can be satisfied by its own pattern.** `AC11a` scanned the suite for
`pkill|killall` and matched the literal inside a sibling assertion's regex. Fixed by anchoring on
command position **and** writing the pattern as `p[k]ill|kill[a]ll` — the one context where the
bracket trick is the right tool, since it is a grep over source. (It is a category error against a
`/proc` walk, which is why `proc.sh` itself does not use it.)

## An instrument must be verified before its output is read — again

The first attempt to verify the new assertion floor copied the suite to a sandbox where
`$SCRIPT_DIR/../scripts/lib/proc.sh` does not resolve. All three mutation runs aborted at the
helper-existence check and returned **rc=1**, which reads exactly like the floor firing. Three
"caught" results, none of which measured anything.

A green **control** in the same location caught it. This is the third instance of the class in a
week ([[2026-08-12-every-fix-i-shipped-reintroduced-the-class-it-closed]] §"An instrument must be
verified before its output is read"), and the cheap habit is unchanged: run the unmutated control
first and require it GREEN, because a red baseline voids every row after it.

## Session Errors

1. **Planning subagent stalled at the 600s stream watchdog**, then a respawn of the single
   correctness arm stalled identically, at the same point. **Recovery:** completed that arm inline
   against the runner source. **Prevention:** bound a delegate's read scope; both stalls were on
   wide reads of `scripts/test-all.sh`.
2. **Two acceptance criteria were self-defeating** — each would have failed against a *correct*
   implementation. AC5 grepped for the suite path, but `run_suite` prints its label twice (`--- $label ---`
   and `[ok] $label`), so a correctly-registered suite returns 2. AC8 counted `\bkill ` across the
   whole file including the header that deliberately discusses kill semantics. **Prevention:**
   before writing an AC, run its literal command against the intended-correct state.
3. **`mutate()` ran inside a command substitution**, so its `fail "mutation did not land"`
   incremented `FAIL` in a subshell — the suite printed a FAIL and exited 0. This is the subshell
   defect `work/SKILL.md` documents, committed three lines from the pointer to the rule.
   **Prevention:** a helper that both returns a value and can fail must not be called as `$(...)`.
4. **The suite had no assertion floor.** Neutering `pass()`/`fail()` gave `Total: 0`, exit 0.
   Adding a floor was necessary and not sufficient: neutering `fail()` **alone** leaves PASS at its
   full value and rc=0. **Prevention:** floor **plus** a positive control that calls both counters
   and verifies each moved.
5. **A mutation anchor silently ceased to exist** when the matcher was rewritten — the row would
   have reported the baseline, which is indistinguishable from a pass. **Prevention:** the `mutate`
   helper now asserts the anchor occurs **exactly once** and fails loudly otherwise.
6. **All 8 review agents died** — 7 on a session limit, 1 on the stall watchdog. **Recovery:**
   resumed from transcript rather than respawned; two had partial results a fresh spawn would have
   re-derived. **Prevention:** resume in batches of 3–4, and instruct agents to report
   incrementally with an explicit truncation priority.
7. **The `_proc_sanitize` herestring appended a newline**, which is itself non-printing and so
   became a spurious trailing `?` on every path. **Prevention:** `printf '%s' | tr`, not `<<<`.
8. **The plan's Test Scenarios table went stale** — 9 listed, 25 actually run. **Prevention:**
   `/qa` reads that section, so treat it as an artifact to sync, not a historical record.
9. **`cleanup-merged` timed out** at the session-start 2-minute budget and
   `SOLEUR_GIT_BARE_POISON` was emitted on every `worktree-manager.sh` call. Neither blocked this
   run. **Prevention:** tracked separately; 26 live worktrees is the likely cause.
10. **`tasks.md` was never written** for this branch (the planning subagent died before it).
    **Prevention:** none needed — `/work` consumes the plan file.

## Related

- [[2026-08-12-every-fix-i-shipped-reintroduced-the-class-it-closed]] — the general class, one day
  earlier. Its recurrence here is why this file proposes gates rather than restating it.
- [[2026-08-11-the-pr-that-fixed-narrow-guards-shipped-three-narrow-guards]]
- [[2026-07-27-the-subshell-bug-i-was-fixing-bit-me-three-more-times]] — the `x=$(fn)` class, whose
  pointer this PR adds to `work/SKILL.md` and whose defect this PR then committed.
- [[2026-07-16-a-mutation-battery-only-covers-what-you-mutate]]
