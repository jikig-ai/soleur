# Decision Challenges - feat-one-shot-12362-stall-triage-headsha

The one technical fork in this work was ruled by the CTO agent before planning started; no operator
question is open. `soleur:ship` renders this table into the PR body.

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Lift the E2 hold (issue-body template kept byte-identical in the previous stall-check PR, merged as 10e66d9ab8) so the headSha field can be added in a separate PR for #12362 | technical | Ruled by CTO agent, 2026-11-08: E2 lifted, add the test assertion, delete the follow-through probe, remove the follow-through label post-merge - the hold applied only to the earlier PR, and a membership assertion plus probe retirement closes the gap with no template change beyond one field |
