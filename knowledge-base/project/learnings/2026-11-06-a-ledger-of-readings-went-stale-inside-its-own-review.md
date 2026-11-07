# Learning: a precondition ledger of readings goes stale inside its own review, and so do the premises you hand the reviewers

## Problem

PR #12245 (docs only) planned the bundled Inngest host-replace window as a precondition ledger: each row has a
read-only command, a class and a dated state. Within the same session, before the PR merged, main moved twice
(two infra merges), a merge-queue run was already pending on a third, and the plan's own invalidation rule voided
two of its rows. The plan said "tip bd89194eed" in four places; the real tip was `1ee0d6af49`. I had repeated
"bd89194eed is the current main tip" as fact in a CTO prompt, so a premise I supplied came back inside the ruling.

## Solution

- Define the moving reference once ("dispatch SHA = the `origin/main` tip at the moment of the go") and make every
  row either SHA-exact (a2: a ci.yml `merge_group` or `workflow_dispatch` run whose `headSha` equals the dispatch
  SHA) or bound to it by a command that prints a marker (`&& echo diff-ok`, `&& echo monitor-is-ancestor`), because
  an empty `git diff` is also what a failed fetch prints.
- Replace "voids nothing / voids a row" with tiers (whole ledger; a1, a2 and b; a2 and b only; any tip move re-reads
  a2) plus a dependency-ordered re-clear list, so a rule cannot be circular with the row it re-clears.
- Make acceptance criteria that cannot fail on their own mutation: the first AC2 was paragraph-level and passed
  with the run kind deleted; the replacement checks each 11-digit id for its kind within the same sentence.

## Key Insight

A ledger of readings is a claim about a moment; its value is the rule for when a reading stops counting, and that
rule needs the same review as a gate (read it against the current tip, name a merge that satisfies the wording
while breaking the property). Separately: a state a lead asserts in a reviewer prompt (a tip, a count, a run kind)
is the lead's reading, not the reviewers' evidence; pass the command that produces it instead.

## Session Errors

1. **Stale tip repeated as fact.** The plan and my CTO prompt said `bd89194eed` was main's tip; `1ee0d6af49` had
   landed. Recovery: re-read origin/main, restated a2 and b, added the dispatch-SHA definition.
   **Prevention:** give a seat or the CTO the command (`git rev-parse origin/main`), never the value; re-run it in
   the same call as any edit that quotes it.
2. **Inclusive end-marker in my replace helper.** `srep(start, end, new)` replaces through the end marker, so three
   edits would have deleted the heading or line after the block. Caught before running.
   **Prevention:** when the end marker is the next heading, either end the replacement text with it or use an
   exclusive helper; assert the replacement's tail equals the marker.
3. **Assert-before-write aborts (4).** Wrapped lines, a wrong start marker and a stray backtick prefix made exact
   anchors miss; nothing was written. **Prevention:** keep the all-or-nothing write; copy anchors from `grep -n`
   output, not from memory of the Read.
4. **Mutation that did not land.** The first AC2 mutation targeted text wrapped over two lines; `cmp` showed no
   change and the "pass" would have been the baseline. **Prevention:** assert the mutation landed (`cmp -s`)
   before reading any mutant result, and mutate the joined text when the check works on joined text.
5. **A criterion that could not fail.** The paragraph-scoped AC2 and the "(helpful) count of table rows" AC3 passed
   with their property violated. **Prevention:** for every AC write the mutation that satisfies it while breaking
   the property, run it, and keep the AC only if the mutant is caught.
6. **Duplicated paragraph from the inclusive replace.** An old copy of the "Rows c1 and c2" exception survived
   after a larger rewrite. **Prevention:** after any block rewrite, count occurrences of the block's first sentence.
7. **Impossible timestamp.** The planner stamped readings "14:50Z" against a 14:38Z commit. **Prevention:** stamp
   with `date -u` in the same command that takes the reading.
8. **Decision row failed the ruling-shape gate** (a "Mechanical" ruling in a `technical` row), costing a second
   CTO spawn. **Prevention:** route a technical row to the CTO when it is written, not when the gate rejects it.
9. **CTO spawns exceeded the planning cap** (4 against 2): two planning rulings, then two batched spawns at review
   on seat dissents, as the review procedure requires. Recorded in session-state.md; not a violation.
10. **A seat wrote outside the scratchpad** (`/tmp/claude-1000/plan.diff`). **Prevention:** brief seats to use
    the scratchpad or a mktemp dir; the lead removes strays after the panel.

## Tags
category: workflow-patterns
module: review, plan, inngest-sole-copy-window
