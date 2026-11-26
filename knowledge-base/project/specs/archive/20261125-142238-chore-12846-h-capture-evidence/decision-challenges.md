# Decision challenges: chore-12846-h-capture-evidence

Plan: `knowledge-base/project/plans/2026-11-23-chore-origin-tls-h-capture-t2-addendum-plan.md`. Issue #12846. Headless one-shot planning session, 2026-11-23.

The S1 marker has no row here. It is an act the owner authorizes, and #13003 with its probe already tracks it, so an operator row would file a duplicate issue.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| D1 Record the offset O, which the loop does not print | technical | Ruled by CTO agent, 2026-11-23: keep O=250 (main) and O=101 (archival), labelled as derived - R1 requires O, both values recompute from the kept hour minus E, and the keep check ties the wrapper's hour to the loop's offset |
| D2 State the S1 marker and #13003 status in the addendum | technical | Ruled by CTO agent, 2026-11-23: leave it out of the addendum and state it in the PR body - a dated additions-only line would go stale, while #13003 and its probe carry the live state |
| D3 Let this PR auto-close issue 12846 while the marker is outstanding | technical | Ruled by CTO agent, 2026-11-23: correct, provided the merged PR includes both evidence files from ee0e31379a - the runbook puts the verdict in this change, the comment read has no state filter, and #13003 tracks the marker |
| D4 Evidence-bar wording and the SEA late-run reading | technical | Ruled by CTO agent, 2026-11-23: the label, "bar not met" and "no cause claimed" stand; replace the sentence on late runs, because the recipe does not scan a positive colo and SEA has sustained runs from 01Z and 02Z, and name the missing mechanism read as a second reason the bar is not met |
| D4-r Plan-review dissent: cut IAD's direct count (25 of 45) as post-hoc | technical | Ruled by CTO agent, 2026-11-23: upheld - keep it, labelled as a direct count and not a recipe output; without it "not positive" can read as "flat", and the figure cannot move the verdict because the recipe does not compute it (runbook recipe block and verdict lines, recount from the kept main file) |
| D5 Shortened "What this does and does not show" paragraph | technical | Ruled by CTO agent, 2026-11-23: no text change - the shortened block states every ruling correctly and overclaims nothing, and the dropped not-judged sentence is already carried by the 2026-11-19 addendum's scan rule |
