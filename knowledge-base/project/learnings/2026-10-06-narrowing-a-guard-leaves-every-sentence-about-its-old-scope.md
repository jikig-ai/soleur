# Learning: narrowing a guard's scope leaves every sentence about its old scope, and a "no X creates it" claim is a measurement per creator

## Problem

PR #9569 (#9372, retire the escrow-create workflow and flip the rotation HALT's `create` arm) shipped
a first design that counted a create of BOTH web-class addresses (`random_password.workspaces_luks_web`
and `doppler_secret.workspaces_luks_web_key`). A CTO re-ruling during review narrowed it to the passphrase
alone: a create of the key copy restores the same state-held value, so refusing it blocks the self-heal.
Two further things went wrong in the prose, not the code:

- The narrowing left "pair", "both entries", "those two addresses" and "no creation route" in the HALT
  text, ADR-263 markers, ADR-006, the C4 clause, three runbooks, the plan, tasks.md and test labels. The
  fix round found them in six places, and the verification seat found one more it had introduced.
- A "recovery" (reviewed import of the live value) and two universal claims ("no workflow creates
  `prd_workspaces_luks_web`", then the repair "only the push-apply can create it now") were written
  without a command that could falsify them. Each was false: an import plans `special = true -> false`
  (a forced replacement refused by `prevent_destroy`), the escrow workflow's only run was plan-only, and
  `apply-deploy-pipeline-fix` run 37185772362 created the config on 2026-10-04.

## Solution

- Re-derive by CLAIM, not by file: after a scope change, write the old scope as a sentence and grep its
  paraphrases ("pair", "both", "two addresses", "no creation route"), then read every hit. A residual-zero
  count over the new wording is blind to the sites still carrying the old.
- A universal creator claim ("only X can create Y") is a measurement per creator. Grep every workflow's
  `-target` list and the ADR's recorded runs for Y before writing it; name the workflow in the sentence.
- Retract an unverified recovery everywhere in one pass and pin its absence in the test that pins the
  HALT text (a banned-phrase loop over the job-wide emitted text), plus positive pins for the scope clause.
- Give each change one name. "The closing change" meant PR #9569 in some sites and the post-rebirth
  deletion in others; rename one ("retirement change") before the first prose sweep.
- Record the narrowing in a dated, append-only Review-Phase Amendments section and put a one-line
  supersession pointer at the top of tasks.md and session-state.md, since those are read as current.

## Key Insight

A guard's scope is stated in every document that mentions it, and a test that pins the guard cannot see
them. The cheapest control is a single named scope sentence at the artifact that owns the decision, with
every other site a pointer; the second cheapest is a review seat that re-derives by claim. A mutation of
the create list (M1-M5 red, M6 equivalent) proved the code; only review proved the prose.

## Session Errors

1. **Infra write guard rejected the first plan write** — Recovery: reworded. Prevention: none (one-off).
2. **Shard-manifest regenerator (`--incremental --write`) added 7 unrelated rows** — Recovery: reverted both
   TSVs from HEAD and removed only the retired suite's two rows. Prevention: when retiring a suite, edit
   the two TSVs by row, never run the regenerator (follow-up is a checkbox on #9572).
3. **`"["create"]:${cw}"` lost its escaped quotes in `_wl_shape_check`** — Recovery: `"[\"create\"]:${cw}"`.
   Prevention: none (one-off).
4. **A Python edit batch aborted on a placeholder assertion before writing** — Recovery: redone as one clean
   batch. Prevention: assert uniqueness per anchor before the first write (already how the batch ran).
5. **Unfalsified prose claims** (import recovery, "created the pair", "no workflow creates them", "only the
   push-apply can create it") — Recovery: retracted/qualified and pinned. Prevention: for every causal or
   universal sentence a diff adds, name and run the falsifying command (grep the `-target` lists) before
   writing it.
6. **A scope narrowing left the old scope in about fifteen sites** — Recovery: two fix rounds plus a
   verification seat. Prevention: sweep by claim paraphrase across the whole repo, and give each change a
   single name before the sweep.
7. **The Write hook blocked review reports under the main repo `.git` path** — Recovery: reports in
   /var/tmp/review-9372/. Prevention: none (hook working as designed).

## Tags

category: workflow-issues
module: web-platform infra, rotation HALT, review process
