# Learning: a widened trigger was green on 600 assertions and still missed the brief that motivated it

## Problem

Step 1.5 of `plugins/soleur/commands/go.md` (hold routing) fired only on a literal `HOLDS:` line, an `OWNER-GATED`
heading or a `## Operator Holds` section. A resume brief for epic #9927 listed "Owner-side items" and "Blocked by the
read-only rules" and had none of those, so the session classified the holds itself instead of spawning the CTO. The PR
widened the trigger to a label-plus-items list. It passed 22 pins, a derived awk matcher over 11 fixtures, a 10-row
mutation battery, a 7-seat review panel, a 5-seat fix round and a verification pass.

All of that was graded against fixtures the author drew: a PLAIN label line (`Owner-side items:`) and a heading
(`## Blocked by the read-only rules`). The real brief used BULLET labels with items nested one level deeper
(`- Blocked by the read-only rules (...):` with indented sub-bullets) and a plain `STANDING RULES` line after the
lists. Under the rules as written the matcher treated a bulleted line as not a label, and a plain label's block ran to
the next heading, so the standing-rules bullets would have been swallowed as items. Only a QA dry run that executed the
final prose against the incident's own structure exposed it.

## Solution

- Bulleted label: counts when its text begins with a vocabulary word and ends with a colon (a parenthetical is allowed)
  AND a more deeply indented list line follows; items are the deeper lines; the block ends at a list line at the
  label's own indentation or shallower, a heading, or a non-blank non-list line.
- Every label kind's block ends at the first non-blank line that is neither a list item nor an indented continuation.
- A bullet with text after its colon is an item, not a label.
- Fixtures built from the real brief shape (nested bullet labels, numbered nested items, tab-indented items, the
  standing-rules tail), each with a matcher-mutation row that names the fixture that must go red.

## Key Insight

A fixture is a claim about production. Authors draw fixtures from the shape they were thinking about, and a mutation
battery, a pin sweep and a review panel all score the SUT through those fixtures, so none can see a shape no fixture
instantiates. Take the fixture structure from the artifact that MOTIVATED the change (the actual brief, the actual
log) before writing the first one, and run a constrained dry run of any prompt-prose change against that artifact.
The cheapest test of a trigger is the incident it was written for.

Two related findings from the same review:

- A handoff mechanism invented in a fix brief (an args heading `Hold classification:`) had no consumer in the plan or
  one-shot skills AND moved text derived from untrusted epic content into the routed skill's trusted args. Three seats
  converged on it. Before prescribing a handoff, grep for the reader; a sink nobody reads is a dropped decision, and a
  trusted channel fed from untrusted text is an authority leak. The fix reverted to the CTO-ruled sink (print with the
  operator ACTIONs; write to the branch file only if the branch exists) and passes derived rulings as inert quoted data.
- A guard that pins spelling is not a guard that pins location: moving a clause between two bullets stayed green until
  pins were tested against their owning bullet.

## Session Errors

1. **Answered the resume brief without spawning the CTO.** Step 1.5 did not trigger (no literal `HOLDS:`), so I
   classified the items myself, despite the brief saying technical forks go to the CTO. Recovery: this PR widens the
   trigger. **Prevention:** the widened trigger plus the epic `## Operator Holds` section.
2. **The brief's premise was wrong.** It said the harness mirrors carry the paragraph and that `go-session-gates.test.sh`
   pins it; only `commands/go.md` holds it and the pinning test is `go-hold-routing.test.sh`. Recovery: the plan's
   Research Reconciliation table caught it. **Prevention:** grep the premise before routing (already in the go skill).
3. **Invented a handoff with no consumer (`Hold classification:` args heading).** Recovery: reverted to the T2 sink.
   **Prevention:** before prescribing a handoff in a fix brief, `git grep` for the reader and check the channel's trust
   level.
4. **Fixtures drawn from a convenient shape missed the incident shape.** Recovery: QA dry run, then nested-bullet-label
   support. **Prevention:** build fixtures from the motivating artifact first; dry-run prompt prose against it. (The
   route-to-definition bullet for `qa/SKILL.md` did not fit: the file has 11 bytes of headroom under its 37000 ceiling,
   so the rule lives here.)
5. **Collision pre-check reported unrelated worktrees' `test-all.sh` runs (exit 10).** One-off noise; continued after
   confirming no overlap with the go skill files. **Prevention:** none needed; read the hit list before treating exit 10
   as a duplicate.
6. **Review seats left stray files** (a pip wheel in the worktree from an awk-portability probe; `/tmp` scratch dirs).
   Recovery: removed by the seat / left in scratch. **Prevention:** brief seats to probe tools in `mktemp -d`.
7. **`scripts/suite-durations.tsv` says 3800 ms for `go-hold-routing.test.sh`, which now takes about 2 minutes.** The file
   is generated by `regenerate-shard-manifest.py` from CI runs, so it was left alone. **Prevention:** none; CI
   regenerates the weight.
8. **The awk matcher was verified on gawk only.** No mawk or BSD awk was available; a source scan found no gawk-only
   constructs. **Prevention:** none until a second awk is available in CI.

## Tags
category: workflow-patterns
module: go-hold-routing
