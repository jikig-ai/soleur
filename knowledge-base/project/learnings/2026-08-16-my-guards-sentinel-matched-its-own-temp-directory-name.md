---
date: 2026-08-16
category: test-failures
module: scripts/guard-vacuity-floor.test.sh
tags: [anti-vacuity, mutation-testing, guards, oracle-design, derived-population]
issue: 7580
---

# Learning: my guard's sentinel matched its own temp-directory name, and it reported a healthier population than it had

## Problem

The task was to widen an anti-vacuity floor fix across the repo: a suite's floor calls
`fail`/`bad`, the exit status reads that same counter, so neutering the assertion helper
silences both the rows and the floor meant to notice the silence.

Ten suites were hardened and the meta-guard was rebuilt to DERIVE its population by floor shape
instead of naming two suites. It went green at **84 floor-bearing repo-wide / 41 covered / 24
firing**, with a self-run 7-row mutation battery reporting 7/7 caught against a green control.

Every one of those numbers was wrong, and the guard was the thing producing them.

## The four defects, all fail-open, all in the guard itself

### 1. The sentinel matched the guard's own temp path

`classify_mutant` scored FIRES on:

```bash
grep -qaiE 'FATAL|vacuity|cardinality|assertion floor|...' "$errf"
```

Mutants are written into a directory this same file names `vacuity-floor-meta.XXXXXXXX`. Bash
prints that path as the prefix of every diagnostic it emits. So a mutant that merely **crashed**
matched `vacuit` **in its own filename** and was credited as a firing floor. `-i` independently
made `FATAL` match git's universal `fatal:` prefix, so any mutant that shelled out to git and
failed got a free FIRES.

Correcting it moved the reported firing population **51 → 32**. Nineteen "floors that fire" were
matching a path, not their own output.

The fix is to strip shell diagnostics (`<path>: line N:`) before the sentinel test — they are
shell errors by definition and never floor output.

### 2. CONSTRUCTION was tested before FIRES

The bucket order put the crash check first, and `|| [[ "$rc" -eq 2 ]]` forced CONSTRUCTION
unconditionally at rc=2 — which is this repo's own fatal convention. Compliant floors whose
phrasing sat outside a hardcoded allowlist (`dispatched only …` vs the pattern's required
`only …dispatched`; `vacuous` vs `vacuit`) were booked as permanent debt at a ratchet pinned to
exactly their count, so they could never leave it.

### 3. The derivation missed a whole syntax form, and matched comments

`(( total < MIN_ASSERTIONS ))` was invisible to a bracket-only pattern. Adding it moved the
repo-wide population **84 → 97** and surfaced seven suites whose floors had never been tested.

Worse, a bare line match scored the guard's **own header comment** —

```
#     if [[ "$cases" -lt 75 ]]; then fail "vacuity guard: only $cases ..."; fi
```

— as a floor, sliced 277 lines of the guard's executable body into a mutant, ran it, and scored
it FIRES off the git error that mutant produced.

### 4. The slice refused to cross `$((`

Backward slice-widening skipped any preceding line containing `$(`, to avoid dragging command
substitution into the mutant. But `$((` is *arithmetic* expansion and is safe. Rejecting both
left floors preceded by `total=$((passes + fails))` with an unbound threshold, reported as
construction failures for fully compliant floors.

This is the identical conflation that made the plan's AC8 command unsatisfiable —
`\$\([^)]*…` matches the first two characters of `$((cases + 1))`, so it fires on every correct
increment. Four independent agents hit it.

## Key Insight

**A guard's own infrastructure is inside the space its oracle searches.** The temp directory, the
file path, the header comment documenting the rule — all of it is text the guard reads back and
can satisfy its own sentinel with. The moment a guard must both ASSERT a property and DOCUMENT
it, the documentation becomes false-match surface for the assertion.

Two corollaries, both measured here:

- **Widening a matcher moves the error to the other side, where no fixture lives.** Adding
  `-gt`/`-eq` to the operator set reported 13 "non-firing floors" that were neither floors nor
  broken — `-gt` is the shape of a suite's *final exit gate* (`if [[ "$FAIL" -gt 0 ]]`) and
  `-eq` of an ordinary assertion. Every fixture sat on the must-trip side, so nothing could
  catch the over-match. Reverted to below-threshold semantics only.
- **A closure identity computed from one list is not a closure check.** Deriving
  `deferred = everything not covered` makes `covered + deferred == total` true by construction:
  the two sets partition the same list, so the arm can never fail. A floor-bearing suite added
  under a directory in neither scope left the guard GREEN. Both scopes must be DECLARED, with an
  UNCLASSIFIED bucket asserted empty.

## Solution

`scripts/guard-vacuity-floor.test.sh`:

- strip `<path>: line N:` shell diagnostics before the sentinel test; drop `-i`; reject
  `^(fatal|error):` as a tool error, never a fire
- test FIRES before the shell-error signature; remove the unconditional `rc==2` clause
- require floor candidates to be conditional openers (`if`/`elif` + bracket test, or `(( … ))`),
  outside heredoc bodies
- keep the operator set at below-threshold semantics (`-lt`/`-le`/`-ge`, `<`/`<=`/`>=`)
- widen the slice across `$((` but not `$(`
- exclude the guard from its own population (a self-mutant re-enters the sweep recursively and
  its verdict flips with `$TMPDIR`'s location)

Three new arms, each mutation-proven:

| Arm | Property | Proven by |
|---|---|---|
| 8b | a non-zero exit with no floor sentinel must NOT score FIRES | adding `\|expected\|error` to the vocabulary reds it |
| 10d | the CASE counter must not move inside a verdict helper | moving an increment into `pass()` reds it, naming the helper |
| 10e | conservation is EXECUTED, not just spelled | replacing the comparison with `if false` reds it |

ARM 10e exists because arms 10a–10d are all static: a conservation block with a gutted
comparison but an intact `printf`/`exit 1` satisfied every one of them and left the guard
byte-identical green.

## Prevention

- **Name what the oracle can read that isn't the subject.** Before trusting a sentinel match,
  ask what else is in that string: the file path, the temp dir, the tool's own error prefix.
- **For any widening, name the mutation that makes the matcher too aggressive and say which
  fixture reds.** If the answer is "none", the fixtures all sit on one side.
- **For any closure/partition assertion, ask where each side comes from.** If both derive from
  one list, the identity is decoration.
- **`$((` is arithmetic; `$(` is command substitution.** Any pattern meant to catch command
  substitution needs `\$\([^(]`. A pattern without it matches every correct arithmetic increment
  and is unsatisfiable.
- **A guard's own controls are worth more than the panel.** ARM 8 caught defect #1; the M7 row
  caught the tautological closure. Both were invisible to reading.

## Session Errors

1. **`rm -rf` with a glob blocked** — resolved onto a protected location. Recovery: delete the
   specific subdirectory. **Prevention:** already hook-enforced; no change.
2. **`git stash list` denied** — incidental, inside a verification command. **Prevention:**
   already hook-enforced (`hr-never-git-stash-in-worktrees`); no change.
3. **Push rejected non-fast-forward** — the Phase 0.5 rebase rewrote history after `draft-pr`
   had already pushed the initialize commit. Recovery: verified the 3 remote commits were my own
   pre-rebase versions, then `--force-with-lease`. **Prevention:** a rebase after `draft-pr` always
   requires force-with-lease; verify the remote-only commits are yours before forcing.
4. **ADR ordinal collided twice** — ADR-191 was free across 69 `origin/*` refs at probe time;
   by review, 191 AND 192 were claimed by sibling branches. Recovery: renumbered to 193, swept 5
   files. **Prevention:** already documented as a class; the only real answer is to re-derive
   immediately before merge, which is what caught it.
5. **My widened operator set produced 13 false positives.** Recovery: reverted to below-threshold
   semantics, recorded the reason in a comment. **Prevention:** the Key Insight corollary above.
6. **My closure identity was tautological.** Recovery: declared both scopes + UNCLASSIFIED
   bucket. **Prevention:** as above. Caught by my own mutation row, not by review.
7. **The FIRES oracle matched its own temp-dir name.** Recovery: strip shell diagnostics.
   **Prevention:** as above. Caught by ARM 8.
8. **ARM 10d's first two drafts were false-positive generators** — the first flagged every
   verdict helper incrementing its own verdict counter; the second flagged the wrappers, which
   are where the increment belongs. Recovery: derive the case counter from the conservation
   identity and require the function to move a verdict counter too. **Prevention:** when a new
   check fires on the known-good reference implementations, the check is wrong, not the
   references.
9. **Debug copies under `/var/tmp` broke `REPO_ROOT`** — hit twice. **Prevention:** already a
   documented trap; run relocated copies from inside the directory whose `BASH_SOURCE` they
   resolve against.
10. **Mutation-battery expectation strings went stale** when I renamed a guard's messages, giving
    two false `SURVIVED` rows. Recovery: read the actual output and correct the expectation.
    **Prevention:** a battery's expectation strings are coupled to message text — after renaming
    any assertion message, re-run the battery and treat SURVIVED as "check the string first".
11. **Plan AC8's literal command is unsatisfiable.** Four agents reported it independently.
    Recovery: corrected form `\$\([^(]…`, recorded in the plan's deviations. **Prevention:**
    the `$((` vs `$(` rule above.
12. **The slice-widening reproduced #11's conflation.** Recovery: `\$\([^(]`. **Prevention:**
    same rule; the fact that it recurred inside the same PR that documented it is the argument
    for a mechanical check rather than another prose note.
