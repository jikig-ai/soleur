# Decision Classes — feat-one-shot-10932-runbook-exit1-sentence

| Item | Class | Ruling |
|---|---|---|
| Runbook sentence wording: state the header table lists exit 1, drop the "tracked on #10932" pointer | technical | Ruled by CTO agent, 2026-10-29: use "Its own header table lists exit 1 (input or manifest faults), as do the restore step's annotation and the row below." - grammatical, matches the engine header's "INPUT or MANIFEST fault" and the table row's name for the code (earlier parent-session ruling gave the same sentence with "input faults"). |
| Leave the `1` table row and the runbook "except exit 1" phrase unchanged | technical | Ruled by CTO agent, 2026-10-29: both already agree with the header, so editing them only widens the diff. |
| Do not add a runbook-vs-header parity test | technical | Ruled by CTO agent, 2026-10-29: W9 already compares the header to emitted codes; a parity test is separate scope (residual PR). |
| Verification: keep the three registry suites as no-regression, add `lint-infra-no-human-steps.py --changed --base origin/main` | technical | Ruled by CTO agent, 2026-10-29: the suites do not read the markdown file; the lint does. Flags verified to run (`OK` on 3 files). |
