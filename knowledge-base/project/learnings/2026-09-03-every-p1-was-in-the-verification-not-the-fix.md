---
module: Test Fixtures
date: 2026-09-03
problem_type: test_failure
component: testing_framework
symptoms:
  - "suite printed FAIL on screen and reported 64 passed, 0 failed, exit 0"
  - "a detector widening silenced a genuinely unguarded site in five measured shapes"
  - "corpus narrowed 914 -> 232 files with every anti-narrowing arm still green"
  - "a production guard whose predicate could not be true at either call site"
root_cause: logic_error
resolution_type: code_fix
severity: high
tags: [guards, mutation-testing, anti-vacuity, fixture-safety, bash, review]
synced_to: [review, work]
---

# Every P1 was in the verification I built, not in the fix

**PR:** #7770 · **Closes:** #7709 · **Predecessor:** the fixture-operand guard that
merged 2026-09-02

## Problem

#7709 asked for a burn-down: a shrink-only baseline of 167 `git -C "$X" <write-verb>`
sites where `$X` could be empty. `git -C ""` does not error — it silently operates on
the current directory, which for these suites is the developer's live worktree, whose
`.git/config` is shared with every worktree on the machine.

The burn-down itself went fine. 167 measured, 30 files remediated, non-vacuity proven
by stripping the added guards and watching the count go back to 153.

Then a nine-agent review found four P1s. **All four were in the verification I had built
around the fix, and three were guards that could not fail.** On a guard-shaped PR the
dangerous surface is not the fix — it is the thing asserting the fix.

## Solution

### P1-1 — the merge gate could print FAIL and exit 0

`passes + fails == asserted` is **direction-blind**: it conserves the TOTAL, so moving a
verdict from the `fails` bucket to the `passes` bucket is free. The arm added to police
exactly that grepped `fail()`'s *body* for the literal `fails=$((fails + 1))`.

One edit defeats both while preserving the grepped literal:

```bash
fail() { echo "  FAIL: $1"; passes=$((passes + 1)); if false; then fails=$((fails + 1)); fi; }
```

Measured in place against a pristine backup, with a genuine already-proven-RED
regression also present:

```
  FAIL: the word `exit` in prose silenced a genuinely unguarded site (0)
  fixture-dir-operand-assert.test.sh: 64 passed, 0 failed  ->  EXIT=0
```

**Fix:** an append-only verdict ledger the accounting reconciles against *both* counters,
plus an arm that DRIVES `fail()` and asserts it moved `fails` and only `fails`.

> A conservation check needs an INDEPENDENT observable. And any check of the form "the
> source contains string X" is defeated by preserving X and changing the meaning around
> it — the `cdx()` name-token gap this scanner exists to replace, reproduced in the
> harness row policing it.

### P1-2 — a detector widening that silences

I added a brace-group abort pattern (`|| { echo …; exit 2; }`) to retire 8 false
positives. Five shapes satisfied it while aborting nothing, each measured:

| shape | why it aborts nothing |
|---|---|
| `\|\| { echo "step 1; exit code unknown" >&2; }` | a `;` **inside a quoted string** reads as a statement boundary |
| `\|\| { [[ -n "$V" ]] && exit 1; }` | conditional abort |
| `d=$( … \|\| { echo err; exit 2; } )` | `exit` in a command substitution exits the **subshell** |
| `d=$(mktemp -d); command -v jq \|\| { echo SKIP; exit 0; }` | an **unrelated** abort on the same line, credited by an unbounded `.*` |
| `\|\| { echo …; return 1; }` at top level | `return` outside a function does not abort — reproduced live, created a `.git` in the probe's CWD |

My must-FAIL fixture used a **comma** (`"will exit soon"`) where the bypass uses a
**semicolon**. One character between covered and uncovered — and the baseline header
claimed the fixture pinned the class.

**Fix:** reverted. The 8 sites are acknowledged with their measured reason.

> Recognising a brace group correctly needs quoting, statement-boundary, subshell-scope
> and function-scope analysis — a shell parser approximated in a regex. When the choice
> is between over-reporting and a detector that can be silenced, acknowledge the false
> positives.

### P1-3 — replacing a floor with an equality lost the property the floor bought

`SITES >= 120` was the anti-narrowing instrument. At population 1 a floor genuinely
cannot distinguish a narrowed scanner from a clean tree, so equality *is* locally
stronger. That reasoning is correct and incomplete: the anti-narrowing burden then landed
on a number that could not carry it.

Measured — narrowing the corpus glob to `apps/web-platform/*.sh` drops **682 of 914**
files and leaves the equality, the `FILES > 100` floor **and** the named-file pin all
green. Two agents converged on this independently.

**Fix:** a corpus floor of 850, derived from the measured 914.

> When you retire an instrument because it no longer fits, name the property it was
> buying and check that something still buys it. "Strictly stronger at this size" can be
> true while total coverage goes down.

### P1-4 — a guard whose predicate cannot be true

`[[ -z "$worktree_path" ]]` in `ensure_worktree_identity`, where both call sites bind
`worktree_path="$WORKTREE_DIR/$safe_branch"` — a literal `/` between two expansions, so
the floor value is `/`, never `""`. It also waved through `/`, which is the reachable
**and** the dangerous value: `git -C /` walks up to whatever repository contains the
filesystem root, and the write path then sets identity into that repo's shared
common-dir config — #6184 with the repository swapped.

Shipped in the PR whose own baseline header argues a vacuous guard is worse than an
acknowledged row. Measured: the old predicate caught **1 of 4** degenerate spellings; a
`case` over `"" | "/" | "//" | "/."` catches 4. It also had no test — the only production
change in the PR, on a new refusal branch, while its two sibling refusal branches were
covered.

> For every guard, name a call site where the predicate can be TRUE. If you cannot, the
> guard is documentation.

### A fifth: a one-line function is its own `FUNC_HEAD`

A guard-window walk starting at `i - 1` steps over a one-line function definition and
runs on to the **previous** function's head, swallowing an unrelated body — any guard on
a same-named positional there clears the site:

```bash
new_repo() {
  local d
  d=$(mktemp -d)
  : "${1:?fixture dir is empty}"        # guard in the WRONG function
  printf '%s\n' "$d"
}
commit_all() { git -C "$1" add -A; }    # genuinely unguarded  ->  SITES=0
```

This is exactly the placement my mechanical remediation pass produced in two legal-lint
suites (taking both `rc 0 -> 1`), and the detector could not tell the two placements
apart — so the regression was invisible to CI. The scanner's comment asserted the
invariant the code did not have. **Fix:** start the walk at `i`; a tightening, the safe
direction.

## Key Insight

**On a guard-shaped PR, review the new ASSERTIONS before the new code.** A fix is written
while holding the defect in mind, so its verification inherits the defect's framing and
gets written fast because it feels like bookkeeping rather than authorship. Ask of every
new assertion: *name an implementation a reasonable engineer might write next that
satisfies this while violating the property.*

### Numbers I asserted instead of measuring

- "~140 sites carry an unrecognised custom guard" → **8**. The estimate counted
  `|| <word>` idioms without checking whether the word aborted.
- "9 holders could reach the helper" → **8**, and the paragraph's own arithmetic
  (4 inline − 1 miscounted + 5 sourcers) already said 8.
- A fallback-site count had **three** defensible readings giving 8, 11 and 12 depending
  on per-site vs per-occurrence and end-of-statement anchoring. I shipped two of them in
  *adjacent sentences*. Disposition: drop the number, state the property — a number whose
  predicate has to travel with it is not carrying the argument.
- "the predecessor merged 2026-08-31" → `2026-09-02T22:27:47Z`, settled by one
  `gh pr view --json mergedAt`.

### Bash fact worth the file on its own

**`''` inside `${VAR:?word}` is stripped before printing.** Bash performs quote removal
on `word`, so `git -C ''` rendered as `git -C  ` — with a double space. The apostrophes
bought nothing and cost a whole-file parse error reported ~150 lines from its cause.

```
$ d=""; : "${d:?git -C '' would retarget}"
bash: d: git -C  would retarget          # <- the '' is gone
```

Hit twice in one branch, the second time *after* documenting it. Swept 19 files to
`<empty>`, which removes the hazard class rather than balancing it.

### Instrument yields were disjoint

| instrument | cost | found |
|---|---|---|
| shellcheck + 4 repo lints | ~30 s | 0 new findings (correctly cleared a class) |
| 9-agent panel | hours | 4 P1s |

Running the cheap deterministic gates FIRST cost almost nothing. Separately, the last
agent was spawned before three review commits landed and correctly re-verified every
finding against the current SHA rather than reporting against the tree it started on —
that is the behaviour to prompt for when a panel runs long.

## Prevention

- Before trusting any anti-vacuity accounting, **neuter the assertion helpers** on a copy
  and confirm the suite reddens. Pair every conservation check with an independent,
  append-only observable.
- For every guard added, name a reachable input that makes the predicate true.
- After retiring an instrument, name the property it bought and prove something still
  buys it.
- Never grep a function's body to prove the function behaves; drive it.
- Publish the command beside any count, or state the property instead.

## Session Errors

1. **`git stash list` denied twice** by `guardrails:block-stash-in-worktrees` — reached for
   reflexively inside a compound probe. Recovery: removed it.
   **Prevention:** no stash-family command in a worktree, including the read-only `list`.
2. **Mutation sandbox had a RED control** — I copied a subtree, but the suite derives its
   corpus from the repo, so it scanned nothing and every mutation result was void.
   Recovery: mutated in place against a pristine backup.
   **Prevention:** for a guard whose corpus comes from `git ls-files`, either `git init` the
   sandbox or mutate in place with a backup; always run the unmutated control first and
   require it GREEN.
3. **Sandbox died on `BASH_SOURCE` resolution** — copied the suite without
   `lib/fixture-scan.py`. Recovery: rebuilt with the resolved layout.
   **Prevention:** grep `BASH_SOURCE` in the SUT and copy every file it resolves.
4. **Apostrophe inside `${VAR:?word}`, twice** — a whole-file parse error reported ~150
   lines from its cause. Recovery: removed; swept 19 files.
   **Prevention:** no apostrophes in those messages; `bash -n` over WHOLE files after any edit.
5. **My prefix-collision probe's classifier modelled 2 of 4 guard forms** and reported 8
   false alarms. Recovery: read the actual guard lines.
   **Prevention:** build a probe's classifier from the SUT's own predicate set, never a
   remembered subset.
6. **Read a mutant's verdict from a log concatenating two runs** — briefly reported
   `63 passed, 0 failed` when the mutant's real exit was 1. Recovery: re-ran with a captured
   log and explicit `EXIT=`.
   **Prevention:** capture each run to its own file and read `rc` explicitly; never `tail`
   across two runs.
7. **Stale merge date in the plan.** Recovery: corrected to 2026-09-02.
   **Prevention:** resolve dates with `gh pr view --json mergedAt`.
8. **Two contradictory counts in adjacent sentences.** Recovery: dropped the number.
   **Prevention:** publish the command beside any count, or state the property.
9. **"9 holders" contradicted the paragraph's own arithmetic.** Recovery: corrected to 8.
   **Prevention:** when a sentence contains its own sum, check the sum.
10. **Read a non-zero `git push` exit as a failure** — it was a Dependabot notice on stderr.
    Recovery: compared local and remote HEAD.
    **Prevention:** verify a push by comparing refs, not by exit code.
11. **Two full-gate launches refused `rc=4`** under a sibling lock. Recovery: built a
    wait-then-run waiter.
    **Prevention:** `test-all.sh --capacity` before launching; `rc=4` is REFUSED — neither
    pass nor fail.
12. **A stale Monitor reported TIMEOUT** after the gate had already started. Recovery: read
    the rc file.
    **Prevention:** read the rc file, never the notification.

## Related

- The scanner's structural blind spots (a quote-blind heredoc classifier leaving 30
  matching lines unscanned across 18 files, dropped binding forms, read spellings counted
  as writes) are recorded on #7708, which already owns that machinery.
- `knowledge-base/project/learnings/2026-08-27-i-committed-the-defect-class-i-was-closing-eleven-times.md`
- `knowledge-base/project/learnings/2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md`
