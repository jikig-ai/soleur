# Decision challenges (Item G, `--ratchets` selector)

Technical forks on this branch were ruled by the CTO agent, never put to the operator. Each row is one decision;
the full evidence is in the plan, `knowledge-base/project/plans/2026-10-16-fix-grep-q-series-item-g-ratchets-selector-plan.md`.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Item G: implement `--ratchets` in scripts/test-all.sh, or record not fixed | technical | Ruled by CTO agent, 2026-10-16: record as not fixed; do not edit the runner - cost is a full-battery `--affected` degrade plus armed `--pr-gated` batteries, and the pre-push ratchet lane plus `--affected` already buy the property |
| Pipe-guard lane gap (option C): in this PR or a follow-up | technical | Ruled by CTO agent, 2026-10-16: separate follow-up issue, conditional-tier lane member preferred - Item G is the selector only and the unconditional-versus-conditional trade is its own decision |
| Pipe-guard lane gap (option C) after a first Phase 1 measurement that counted line presence instead of the selected bit | technical | Ruled by CTO agent, 2026-10-16: withdraw option C and file no issue - VOID, it rested on a measurement bug (98/98 and 97/97 "selected") found by a bogus-path negative control; superseded by the next row |
| Pipe-guard lane gap (option C) after the corrected, bit-parsed measurement (47/98 producers and 64/97 owner suites selected, 51 and 33 not) | technical | Ruled by CTO agent, 2026-10-16: restore the first ruling - record Item G not fixed, file the follow-up issue (#10447) proposing a conditional lane member whose trigger is derived from the guard's own pairs, do not fix it inline and do not widen the edge array (a runner-changed trigger) |
| Guard header sentence `DOES NOT SELECT THIS GUARD`: correct in this PR or leave | technical | Ruled by CTO agent, 2026-10-16: correct only its false parts as a comment-only edit (95/93 to 98/97, "most owner suites" to 33 of 97), keep the producer claim, stamp date and sha, cite #10447 |
| #9217 comment that said "zero gap" | technical | Ruled by CTO agent, 2026-10-16: edit my own comment with a dated correction block stating the corrected figures and the follow-up |
| Meaning of "forbidden-to-edit" for scripts/test-all.sh | technical | Ruled by CTO agent, 2026-10-16: a cost label (PR_GATE_MACHINERY_PATHS arming plus the `runner-changed` full-battery degrade), not a prohibition - no hook, CODEOWNERS entry or AGENTS rule bans the edit |
| Plan review (DHH, Kieran, simplicity): drop the guard-header edit and fold it into a follow-up issue | taste | Kept, then widened: the header edit stays because its `STILL OPEN` list and its selection sentence were both false after this record; the CTO ruling moved the correction of the header's false selection figures into this PR |
| Plan review: cut the producer-path sample to the three already measured | taste | Superseded: the whole 98-producer / 97-owner population was measured instead (`selection-measurement.md`), after the first count was found invalid |
| Plan review: shorten the #9217 comment and drop the 36/27/9/10/3 breakdown | taste | Kept: the counts are the evidence that the `grep -lis ratchet` set is a text-mention heuristic, stamped as of `ee8644bded` |
| Plan review: collapse the skipped-gate sections and the Property/Cut table | taste | Kept: the plan skill requires the Property List and Cut List, and each skipped gate states its reason in one line |
