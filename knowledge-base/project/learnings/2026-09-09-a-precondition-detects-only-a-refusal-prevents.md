---
title: "A precondition detects; only a refusal prevents"
date: 2026-09-09
category: test-failures
module: plugins/soleur/test
issues: [7822, 7835, 7849]
pr: 7987
tags: [git-fixture, containment, vacuity, guards, mutation-testing, measurement]
---

# A precondition detects; only a refusal prevents

## Problem

PR #7987 exists to stop test fixtures writing to the caller's repository under an inherited
`GIT_DIR` (#7835: a rewritten branch tip and a wiped index, under lefthook). A seven-agent review
found **three P0s in that PR**, each of which performed the exact harm the PR closes. All three were
reproduced on synthesized decoys before being fixed.

```
git-fixture-containment.test.sh, run as its own header documents:
  HEAD    7771322 -> 0c59cc3      "victim seed" committed onto the developer's branch
  status  [ M IMPORTANT.txt ?? wip-notes.txt ] -> []      uncommitted work swallowed
  commit.gpgsign  true -> false
  user.email      dev@real.test -> victim@fixture.test

proc.test.sh, same environment:
  rc=0   "Total: 61  pass: 61  FAIL: 0"      <-- reported GREEN while breaching
  head 070a4b6 -> 42a3258, refs 1 -> 2, a branch and a dangling worktree in the caller's .git

fixture-dir-operand-assert.test.sh, same environment:
  commit.gpgsign true -> false, user.email overwritten
  — verbatim the 2026-08-20 incident recorded in its OWN baseline header
```

## Root cause

**All three had a guard. All three placed it downstream of the write it describes.**

The first revision gave each suite a *precondition*: assert the fixture is what the case assumes.
Each precondition was correct, three-part, with a positive control — and each ran **after** the
`git -C "$FIXTURE" init/config/add/commit` sequence that a hostile `GIT_DIR` retargets. A
precondition that fires after the write is a post-mortem. It reported the breach and could not
prevent it, and in `proc.test.sh` it did not even report: the precondition covered T9 and the
breach was in T-NEST, so the suite exited 0 at 61/61.

The containment suite had a second, subtler version: it took **neither** layer. Not sourcing
`test-helpers.sh` is correct there — it controls the tripwire, so sourcing would abort it in the
arms it exists to exercise — but the conclusion drawn was "therefore no protection", when the
correct one is "therefore it must scrub itself".

## Solution

**Refusal, above the first write, derived rather than transcribed.**

- The containment suite scrubs its own environment as its first executable statement, using the
  scrub line derived from `scripts/test-all.sh` — the same line it writes into the child runner.
  A post-scrub precondition over the derived variable list backs it up. Both are load-bearing and
  neither is redundant: removing the `eval` alone is caught by the precondition (decoy untouched);
  removing **both** breaches the decoy.
- `proc.test.sh` and `fixture-dir-operand-assert.test.sh` now source `test-helpers.sh`. Neither
  controls the tripwire, so neither had a reason to abstain, and `scripts/test-all.sh` already
  classifies rc 97 as `[TRIPWIRE]` rather than a failing assertion.

## Key insight

**Ask of every guard: does it run before or after the thing it is guarding?**

The question sounds trivial and is not, because a precondition *reads* like prevention — it is
placed near the risky code, it names the hazard exactly, and it goes red when the hazard occurs. In
all three files the comment above the guard described the harm correctly. What none of them did was
run first.

The corollary is about which remedy you reach for. When a file cannot adopt the standard guard,
"no guard" is almost never the right conclusion; the right one is "a guard of a different shape,
derived from the same source of truth".

## Four subsidiary lessons, each measured

### 1. An encoding gap in a measurement predicate recurs until it is named

One gap — a predicate's "already sources `test-helpers.sh`" limb matching only the *literal*
filename, so `source "$HELPERS"` reads as a non-adopter — produced **four** wrong numbers in one PR:
a wrong adoption count posted to an issue, a wrong exclusion cause written into the plan, a wrong
post-fix scoped count, and a wrong "correction" to a figure that had been right.

Three encodings of "adoption" over one tree: `git grep -l` = **55** (mentions), literal-source =
**48**, indirection-resolved = **49**. A count whose encoding is unstated is not falsifiable.

Every one was caught by re-measuring. None was caught by re-reading.

### 2. An instrument that cannot measure still returns a verdict

Three times in one session an instrument reported a result it had not obtained:

- a `grep` against a file in a directory that did not exist printed `clear:` for all five inputs
- a mutation battery run on a **sandbox copy** of `proc.test.sh` died at `BASH_SOURCE` relocation
  before reaching the arm; `rc=1` with zero output read as a kill
- the tripwire-variable derivation returned 8 of 9 because `GIT_EXEC_PATH;` carries a semicolon

Only the third was caught automatically, by a fail-closed `>= 9` guard written minutes earlier. The
lesson is the guard, not the vigilance: **give every derivation a cardinality floor**, so a
silently-short list aborts instead of narrowing the thing it feeds.

### 3. A mutation must be run in the environment the defect lives in

Removing the self-scrub **survived** a clean-environment run — correctly, since a self-scrub only
matters under a hostile one. Batteries default to the environment the author is sitting in, which
is the environment where the defect cannot occur. Enumerate the environment as an axis alongside
fixture shape and direction.

### 4. Generated code is authored code

Two defects came from how the child fixture was written, not what it did:

- backticks inside an **unquoted** heredoc were command-substituted, printing
  `add: command not found` on every run
- rebuilding the child with `printf` instead made every generated `git -C "$d"` line visible to the
  P1b scanner as though it were the parent's own code — **10** spurious rows, none of which a guard
  in the parent could honestly clear, because the operand is bound in the child

A **quoted** heredoc with values passed through a generated prelude fixes both at once.

## Prevention

- For any guard, state where it sits relative to the first write it protects. If it is below, it is
  detection; decide explicitly whether detection is enough (it usually is not).
- When a file cannot take the standard guard, write down *why*, then ask what guard it CAN take.
  "Controls the tripwire" justifies not sourcing; it does not justify no protection.
- Give every derived list a cardinality floor and every derived string a shape check.
- Re-measure rather than re-reading, and publish the command next to the number.
- Run mutations under each environment the SUT ships into, not only the ambient one.
- Prefer a quoted heredoc for generated code; pass values in through a prelude.

## Session Errors

1. **Sweep-set derivation returned 2 instead of 5** — regex not `git -C`-aware. Recovery:
   normalization pass. Prevention: this repo's dominant fixture idiom is `git -C "$dir" <verb>`;
   an adjacency-matching predicate sees almost nothing.
2. **A grep check printed `clear:` for five files because the scratchpad directory did not exist**
   and grep failed. Recovery: `mkdir -p` and re-run. Prevention: assert the operand exists before
   reading a "clean" result — a failed probe and a clean one are the same output.
3. **A mutation battery on a sandbox copy was void** — `proc.test.sh` resolves paths through
   `BASH_SOURCE` and died before the arm. Recovery: re-ran in place against a pristine backup.
   Prevention: require a GREEN unmutated control *in the sandbox* before reading any row.
4. **Backticks inside an unquoted heredoc were command-substituted.** Recovery: removed them, then
   moved the whole body to a quoted heredoc. Prevention: quoted heredoc by default.
5. **The child used a plain `git commit`**, which under breach exits 1 without moving HEAD, so the
   negative control could not see the breach. Recovery: `--allow-empty`. Prevention: a control must
   be able to observe the thing it controls for; verify it fires before trusting the arm it guards.
6. **The tripwire-variable derivation returned 8 of 9** (`GIT_EXEC_PATH;`). Caught by a fail-closed
   floor. Prevention: cardinality floor on every derived list.
7. **Adoption metric was literal-only**, so a real adopter counted as a non-adopter; a wrong count
   was posted to #7849. Recovery: corrected on the issue. Prevention: resolve one level of variable
   indirection, and require the variable's own assignment to name the file.
8. **I "corrected" a correct figure.** The plan's 44 -> 47 was right; my grep counted comments.
   Recovery: retracted in the PR body and on the issue. Prevention: comment-strip before counting.
9. **The looser indirection metric returned 54** (false positives) before tightening to 49.
   Prevention: an indirection match must verify the variable's assignment, not just its use.
10. **The T1 test-scenario predicate carried the same literal-only gap**, reporting 1 remaining
    instead of 0. Prevention: as 7 — one predicate, reused, fixed once.
11. **Ran `git stash list` needlessly**; denied by the guardrail hook. Recovery: dropped it.
    Prevention: none needed — the hook is the prevention and it worked.
12. **`printf`-built child produced 10 spurious P1b rows** — a regression introduced while fixing
    review findings. Recovery: quoted heredoc. Prevention: re-run the ratchets after a fix, not
    only after the original implementation.
13. **Hoisting the sandbox above the harness self-test polluted the verdict ledger** (26/1 vs
    25/0). Caught by the ledger reconciliation. Recovery: truncate the ledger after the self-test.
14. **The PR body claimed #7822 says hooks exposure is "highest"** — it says *candidates* and *most
    likely*. Recovery: quoted the source. Prevention: quote, do not paraphrase, when the paraphrase
    is stronger than the source.
15. **The `TRIPWIRE_RC` comment cited AC17 and T6**, neither of which binds 97, and omitted
    `test-all.sh:851`, the most consequential site. Recovery: grepped and rewrote. Prevention: a
    cross-reference is a claim; run the grep before writing it.
16. **Drafted a residue issue citing a rule that discourages filing.** Recovery: filed nothing;
    documented the residue in-place on the two trackers that stay open (net -1). Prevention: read
    the rule body before citing it as a mandate.
17. **The three P0s.** Recovery and prevention as the body above.
18. **The A2 adoption itself shipped unguarded.** The two A1 suites guard their `source` of
    `test-helpers.sh` with `|| exit 2`; the three A2 suites — the ones A2 exists to protect — did
    not, and two of them run without errexit by design while the third sources the helper above
    the point errexit becomes active. Measured: with the path unresolvable, bash printed "No such
    file or directory" and each suite ran to completion, rc != 97 — the tripwire gone, nothing
    saying so, and the textual adoption metric still counting all three as adopters. Found by the
    ship-gate completeness consult, after seven review agents and 22 green suites. Recovery:
    guarded all three, verified by in-place mutation (control rc=0, mutant rc=2, restore
    byte-identical). Prevention: when a PR adopts one guard shape in some files and another in
    others, the difference is a finding, not a style choice — diff the adoption sites against each
    other, not only against the pre-adoption state.

## Related

- `knowledge-base/project/learnings/2026-09-04-a-learning-two-working-copies-and-it-still-got-re-derived-wrong.md`
- `knowledge-base/project/learnings/2026-09-08-six-instruments-were-broken-and-three-printed-a-verdict-anyway.md`
- `knowledge-base/project/learnings/2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md`
- ADR-157 (a hook that cannot parse its input asks), #7833 (the Guard 3 tripwire)
