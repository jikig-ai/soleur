# Learning: a retire PR's lost kills, and the three claims I carried into it unmeasured

PR #10268 (Ref #8316): delete a suite-only gate entry point, keep the live P0 gate beside it.

## Problem

Deleting `inngest_host_dark_gate` from a lib whose helpers are shared with the live
`inngest_execute_registry_gate` removes more than the entry point: every test row that only the
retired entry point drove also stops killing mutants of the SHARED helpers. A suite that is green
after the deletion says nothing about that. Three claims also travelled into the diff from a
previous context window without being re-measured.

## Solution

1. **Differential mutation proof.** Generate mutants of every guard-shaped line of the kept code
   (keyed by function, line content, occurrence index so base and branch lists join across the
   deletion), run them on the base suite (K_main) and on the branch suite (K_branch), and require
   `K_main restricted to surviving lines ⊆ K_branch`. 468 mutants: 9 kills were lost (any-red
   definition). Seven were restored by six `[ERG-port]` rows that re-express the dark rows against
   the execute gate's own fixture.
2. **The two I wrote off were not equivalent.** The `_ihdg_graded_row` default-clock fallback
   (`if [[ -z "$now_epoch" ]]; then now_epoch=...`) is unreachable through the gate, because the gate
   resolves `now_epoch` first — so I called the mutants equivalent and wrote that into the PR. A
   test-design seat showed a direct helper call with an empty sixth operand kills both. Two rows
   fixed it; re-run `KILLED 8/8`. "Unreachable through the only caller" is a statement about the
   caller, not about the helper's contract.
3. **Measure the carried claims.** The follow-up issue draft said six probe fields were consumed only
   by the retired gate; `git grep` showed `data_mount_devid` feeds a paging alert and three others
   have live consumers (`scripts/inngest-host-state.sh` et al.). The filed issue lists only the two
   fields that are actually prunable. The lib header and the ADR addendum said "G1-G7 are now E1-E7"
   from memory; the predicate tables say G7 is E8, G9 is E9, G8 is E10.

## Key Insight

For a deletion PR the verification that matters is not "the suite is green" but "what did each
deleted row kill that nothing else kills", and a justification for a lost kill must be checked
against the HELPER's contract (call it directly) rather than against its current caller. Prose that
maps old names to new ones, and lists of "fields only X uses", are claims to grep before they are
written into a durable record.

## Session Errors

1. **Called the `bash` tool name instead of `Bash`** — Recovery: re-called. **Prevention:** none beyond tool-name care (one-off).
2. **Foreground `sleep` and `pgrep -f` were blocked by hooks** — Recovery: Monitor / until-loop and `proc.sh`. **Prevention:** already hook-enforced; use Monitor.
3. **A heredoc inside a blocked `gh issue create` call never wrote the body file** (the whole command is refused, so nothing ran), then the filing gate demanded `meta/machinery`/`User-Impact` and a readable absolute body path. — Recovery: wrote the body with the Write tool into the scratchpad, re-ran as its own call with `--label meta/machinery`. **Prevention:** write the body file in a separate step first, then run `gh issue create` alone (the gate's message already says so).
4. **The "documented survivors" justification was wrong** (see Solution 2). — Recovery: two direct helper rows. **Prevention:** an equivalent-mutant claim names the shapes enumerated on the helper's side, and a lost kill is first tested by a direct helper call (review skill already carries the equivalent-mutant rule).
5. **G-to-E mapping stated from memory in the lib header and the ADR addendum** — Recovery: corrected after two seats converged; verified against both predicate tables. **Prevention:** open the base predicate table when writing any old-name-to-new-name mapping.
6. **Floor measurement off by one**: the "N assertions ran" line printed while a floor was failing counts the failing floor itself (and a second failing floor adds another), so I set 183 where the true value was 184. — Recovery: read the next run's message. **Prevention:** fix the other failing floors first, then take the count from the run where only the stale-floor line fails.
7. **Review-fix prose edits missed siblings** (verification seat found three lib comments still saying "both entry points"). — Recovery: reworded. **Prevention:** grep the claim's subject repo-wide after a prose correction, not only the lines the finding named.

## Tags
category: workflow-issues
module: tests/scripts/lib/inngest-host-dark-gate.sh
