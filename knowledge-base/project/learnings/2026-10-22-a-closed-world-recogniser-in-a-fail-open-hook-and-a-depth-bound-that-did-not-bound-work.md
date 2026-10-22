# Learning: a hook that decides "is this a commit" from a closed list of words fails open on every word not in the list, and a depth bound is not a work bound

**Issue:** #10609 · **PR:** #10691 · **Date:** 2026-10-22

## Problem

#10609: the pre-commit secret scan resolved its repository from the hook's working directory, so at a
`core.bare=true` root `cd <worktree> && git commit` was never scanned. The fix lexes the command text
and scans the repositories it names. Eleven review seats then found the same structural cause in the
new walker, in different spellings: it recognised a commit only when `git` was `argv[0]` after six
known wrappers and a closed list of git options, and a second hand-kept token list decided whether the
lexer ran at all. `timeout 5 git -C W commit`, `sudo -u git git -C W commit`, `git --namespace n -C W
commit`, `export GIT_DIR=...; git commit` and `/usr/bin/env -C W git commit` were all allowed with
nothing scanned. A fix guarantees "never skipped" only for the shapes its lists name.

## Solution

- Invert the default. A word the walker does not model is searched for a LATER command word
  (`git`, `cd`, `env`, a shell, `eval`, `export`), and EVERY hit is walked (the first may be an operand:
  `sudo -u git git ...`). An unknown git option followed by a `commit` word counts as a commit.
  Over-recognition only adds a scan; under-recognition is the incident.
- Bound the WORK, not only the depth. Recursion capped at 32 levels stopped a crash (a segfault in a
  hook exits non-zero, which lets the tool call proceed), but a launcher word between `env` words
  branched at every level and took minutes. A per-record step budget (500) closes it; overflow is a
  refusal, never a skip. The same applies to the 8-hit look-through cap and the 32-target cap: a cap
  that skips silently reopens the hole it exists to close.
- Every "I cannot read this" is a deny with a cause-specific repair, and the repair must pass the hook.

## Key Insight

1. A guard that answers "is this X" from literal words is closed-world: every spelling not in the list
   allows. Ask of each recogniser what it does with a word it does not know, and make that answer
   "refuse" (or "recognise anyway"), never "ignore". This is `a guard's window narrower than its
   property`, one level down: the window is a word list.
2. A bound on recursion depth bounds the stack, not the time. Where a timeout fails open, count steps.
3. Dropping a refusal because it comes "after the last commit" is only sound for a straight-line
   command list; loops and function bodies run their text out of order.
4. The author's own mutation battery (24 mutants, 22 caught) left the first fix round's fixtures at one
   member per arm; a test-design seat that was told to find what the battery missed killed 41 of 47
   survivors with 87 rows. Brief that seat for the vacuity, not for a re-run.

## Session Errors

1. **A scripted edit matched an earlier occurrence of its end marker and duplicated half of the test
   file.** `s.index("# >>> ci-contract-epilogue")` also matched the awk pattern inside `_t_ci_contract`,
   so `s[:a] + new + s[b:]` with `b < a` repeated a chunk. Recovery: cut from the end of the new block
   to the last real marker. Prevention: anchor a splice on the LAST occurrence (`rindex`) or assert
   `b > a` and the occurrence count before writing; read the result back (`grep -c` of a unique line).
2. **`shellcheck -S warning ... && bash suite` skipped the suite silently** on an unused variable in
   merged rows and the harness reported only the chain's `rc=1`. Prevention: run lint and the suite as
   separate statements and read each rc.
3. **The mutation harness printed in submission order behind one hung mutant** (`ex.map`), losing the
   other nine results; a too-wide `rm -rf /var/tmp/mut10609.*` also deleted the harness script.
   Prevention: `as_completed` plus a per-mutant timeout that counts a hang as a kill; keep harness
   files in a directory no cleanup glob reaches.
4. **Three first-round mutants survived** (process-cwd root dropped, loose-only confirmation removed,
   a "mutation" that was a no-op by construction). Two were fixture gaps (process cwd equal to payload
   cwd; a command without the word `commit`), one equivalent. Prevention: assert each mutation changes
   behaviour before counting it, and give every fixture two members on the axis it quantifies over.
5. **Hook and ratchet refusals** (all worked as designed): `git stash list`, `ps | grep` self-match
   (twice), an issue filing without the `meta/machinery` exit, a sibling-hook comment edit that shifted
   a positionally pinned line (`boundary-prefix`), two `fixture-relative` sites (a quoted `git -C "$X"`
   data string and a redirect to a variable path), and a deny-text word that tripped the `eval` ban.
   Prevention: edit pinned files line-neutrally; keep data strings out of the scanner's reach.
6. **A shadowed loop variable between two rows and an off-by-one in a count floor** cost two suite
   reruns. Prevention: give each row group its own variable and derive a floor from a measured run.

## Tags

category: security-issues
module: .claude/hooks/git-commit-secret-scan.sh, .claude/hooks/lib/commit-target-roots.sh
