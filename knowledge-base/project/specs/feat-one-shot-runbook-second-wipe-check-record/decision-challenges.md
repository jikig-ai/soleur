# Decision challenges — feat-one-shot-runbook-second-wipe-check-record

Headless plan run (one-shot). Technical forks go to the CTO agent, legal forks to the CLO agent; none is put to the owner.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Marker shape under the two bullets: indented blockquote vs unindented as at the 2026-10-15 precedent | technical | Ruled by CTO agent, 2026-10-18: indented (two spaces) blockquote under both bullets, with a blank line under the loose wipe_check list and none under the tight exit-34 list - an unindented quote ends the list and trips MD032 on the next bullet; measured with the repo's markdownlint, 0 errors |
| Keep the `Status (2026-10-14)` heading date | taste | Ruled by CTO agent, 2026-10-18: keep it; the heading dates the baseline claims and the Update sentence is the dated amendment, so only that sentence is rewritten |
| Leave the 'Reading the exit-34 line' table and the `Not proven` H9/H8/3600 s/snapshot-listing bullets unedited | technical | Ruled by CTO agent, 2026-10-18: the second run lands on the table's first row, so quote it and add nothing; the other bullets stay literally true, and exit-path reasoning is an inference whose values were never printed, so it is not recorded as a measurement |
| Test and lint coupling of the runbook edit | technical | Ruled by CTO agent, 2026-10-18: only verdict-map parity tests read the runbook and the edit is before the Verdict map and adds no verdict word, so no test or baseline change; re-run markdownlint and lint-infra-no-human-steps.py after editing |
| Wording of the C1 marker: bare "Superseded as to that hold" vs scoped | technical (legal) | Ruled by CLO agent, 2026-10-18: the hold is not superseded, the lift was for one run and is spent; keep the brief's "Superseded 2026-10-18" word only with "as to run 39136900735 only", cite addendum 2 item 7 for "any further wipe_check needs a new CLO addendum", and leave the hold otherwise as written |
| Name the fields rather than "no residue count was measured" | technical (legal) | Ruled by CLO agent, 2026-10-18: repos=0 was printed by both runs, so say that lock_residue and store_root_repos were not printed or measured by either run; the closed posting list is unchanged |
| "The owner named the command" in the second marker | technical (legal) | Ruled by CLO agent, 2026-10-18: addendum 2 item 1 sets out the command and the owner only approves the environment; drop the attribution and cite item 1 |
