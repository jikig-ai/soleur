# Learning: "NOT retryable" is a policy label, not a determinism claim — and removing one "re-run" orphans every sentence that leaned on it

## Problem

Issue 11667's residue was two wrong operator-facing sentences in the `registry_store_restore` exit-code arms of
`.github/workflows/apply-web-platform-infra.yml`: the exit-3 arm said the store is EMPTY although exit 3 can fire after
earlier entries are already in the sink, and the exit-4 arm said "re-run this job" although the engine labels exit 4
NOT retryable. The workflow edit itself was two strings and -12 bytes. The runbook edit that mirrors it took three
commits, because each round of review found a sentence the previous round had made false or left behind.

## Solution

- Workflow: reword the two arms from the engine's own exit-code table (header of `scripts/registry-restore-from-ghcr.sh`),
  net-negative in bytes, no other line touched (the file sits ~800 bytes under its size gate and a merge fires the
  production apply).
- Runbook (`registry-luks-recut-6929.md`): the one cell the plan prescribed became six edit sites. Row 4 lost "a repeat"
  (its antecedent, "Re-run the job", was deleted); the resolver sentence and the "If the restore job fails" section still told
  the operator to re-run after any exit; row 2 had no re-run guidance once the blanket sentence went; row 3 still said
  "accept the write"; one pre-existing sentence promised a "wider set" re-run that no dispatch input supports.

## Key Insight

1. **A label and a determinism claim are different sentences.** The engine header says exits 1, 4 and 5 are
   NOT retryable. My first fix wrote "exits 1, 4 and 5 re-run identically". Only exit 1 is documented as failing
   identically; exit 4's engine arms also map some *unclassified* read faults to exit 4 where its own contract says
   exit 6, and exit 5's runbook branch tells the operator to re-run after a measurement. Write the label the
   source states ("not retryable"), never the stronger consequence you inferred from it.
2. **Deleting an instruction deletes the antecedent of every sentence that referred to it.** Grep the cell and
   its neighbours for the words that pointed at the deleted instruction ("a repeat", "the second run", "re-run the job")
   before committing, and grep the whole file for the *claim* (retry semantics), not the phrasing.
3. **The fix commit is the least-audited surface.** Both rounds-1 and -2 defects were in text I had just written; four
   report-only seats converged on the first, a targeted fix-round on the second. Budget one targeted round per
   wording fix to an operator runbook.
4. **A brief's file names are claims.** The hand-off named `registry-luks-recut.yml` for a "next recut run" check; no such
   workflow exists. The recut is the dispatch-only job `registry_luks_recut` inside `apply-web-platform-infra.yml`, and
   the restore job only runs when its `store_refill_needed` output is true.

## Session Errors

1. **The brief named a workflow file that does not exist** (`registry-luks-recut.yml`, 404). — Recovery: located the job
   inside `apply-web-platform-infra.yml`. — **Prevention:** `gh workflow list` / `ls .github/workflows` before quoting a
   workflow file name from a hand-off.
2. **The CTO's byte estimate (-4) was wrong; the dry run measured -12.** — Recovery: the planner re-measured on the real
   file. — **Prevention:** a byte budget in a plan is a measured delta against the merge-base, never an estimate carried
   from a brief (already the rule; the dry run did its job).
3. **My round-1 runbook fix overstated "re-run identically" for exits 4 and 5.** — Recovery: round-2 seats; reworded to
   "not retryable". — **Prevention:** quote the engine header's own label; run the review's targeted fix-round on any
   runbook wording fix.
4. **Removing "Re-run the job" from row 4 orphaned "a repeat" and left three blanket re-run sentences.** — Recovery: six
   edits across the runbook. — **Prevention:** grep the whole file for the claim's subject before committing a deletion.
5. **`acquire_lease` was called as a sourced function, not a subcommand of `session-state.sh`.** — Recovery: re-ran as
   `bash session-state.sh acquire_lease <branch> ship 720`. — **Prevention:** write the full invocation in briefs that name
   the lease.
6. **`test-all.sh --print-selection` blocked the same Bash call that was meant to launch the affected gate** (it queued
   behind sibling full-gate runs). — Recovery: the call moved to the background and the gate launched when it finished.
   — **Prevention:** launch the detached gate in its own call; preview the selection separately.
7. **One runbook `Edit` failed on an indent mismatch.** — Recovery: retried with the exact leading spaces.
   — **Prevention:** copy multi-line `old_string` from a `sed -n` print, indent included.
8. **The stop hook flagged an end-of-turn promise with no action behind it.** — Recovery: named a Paused reason.
   — **Prevention:** end a waiting turn with the Paused sentence, not a forward-looking promise.

## Tags

category: workflow-patterns
module: registry-restore, runbooks, apply-web-platform-infra
