# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-10-12-chore-strip-inngest-plain-id-resolver-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
None blocking (Playwright MCP server failed to connect; not needed).

### Decisions
- Merge reading corrected: a merge does not replace the host (no hcloud_server.* in the per-merge -target list; hcloud_server.inngest is in OPERATOR_APPLIED_EXCLUSIONS; ignore_changes is [ssh_keys] only). The PR is still PARKED: a merge plants a latent replace that shows as drift, makes the additive inngest-host dispatch abort at server_touched, and lets the new boot path ride the next dispatch unexercised. No replace window is scheduled (last inngest_host_replace job 2026-10-08).
- D2: the no-pointer arm is kept and re-pointed at the LUKS volume (the provision-rehearsal root renders the same template with raw volumes and no pointer); only the ext4 arm and the staging block are removed. Departs from the issue's literal wording; recorded in decision-challenges.md.
- D6: the unpointed arm formats ONLY for a `rehearsal_*` Doppler config and refuses every other value (an allowlist; first shipped as a `prd` denylist and inverted in review); loopback arms UNP5/UNP5b and the in-arm driven guard (T1.16i) pin it.
- Narrow scope: the image-baked rollback arm in inngest-luks-cutover.sh is a non-goal. inngest_expect_luks was first kept as an inert input (D4) and then RETIRED in review fix round 3 (CTO ruling A: a later retirement would force a second host replace); AC5 key set is 16.
- Ship phase stops at a reviewed DRAFT (label `parked`, base-SHA staleness rule, unpark checklist, one combined follow-up tracker).

### Components Invoked
soleur:plan, soleur:plan-review, soleur:deepen-plan; learnings-researcher, dhh/kieran/simplicity/architecture reviewers, spec-flow-analyzer, cto (read-only).

## Operator Holds
- PARKED: do NOT mark PR #10081 ready and do NOT arm auto-merge until an inngest host replace is planned (unpark checklist in the plan). Evaluate at the draft exit.

## Work / Review / Park Phase (2026-10-12)
- Status: REVIEWED DRAFT, PARKED. PR #10081 is a draft with the `parked` label, no auto-merge, `Ref #9786` only (no closing keyword). Nothing was merged, replaced, rebooted, applied or dispatched.
- Park / no-replace status: no inngest host replace is scheduled (last `inngest_host_replace` job 2026-10-08). Merging would replace nothing by itself but plants a latent ForceNew replace (`user_data` has no `ignore_changes`), so it waits for an approved `inngest-host-replace` window.
- Review: 11-seat panel (no P1), a targeted 7-seat fix round (no P1), a second fix round, a fresh-eyes verification pass, a binding CTO ruling (retire `inngest_expect_luks` in this PR), and a narrow verification of the retirement. Attested via `Reviewed-By-Soleur` (11/11) and `Reviewed-Fix-Round` trailers.
- Branch merged with origin/main at edb74743f0 (a merge commit, not a rebase, because the attestations name commit ids) to clear a CONFLICTING state.
- Residuals tracker: #10112 (image-baked rollback arm, the rehearsal root's unused volume [operator-excluded from this arc], blank-prd DR bring-up, duplicated reopen arms), re-evaluate when #10081 lands.
- Unverified until CI: `inngest-redis-luks-loopback.test.sh` (needs root; floor 82 projected) and `validate-infra-templates.sh` (needs the cloud-init binary).
- Tally: seats=18, ci_cycles=3+, fix_rounds=2, agent_rounds=2.
- Pipeline deviation (operator-directed): ship's merge phases (Phase 7) were NOT run; only the phases that apply to a reviewed draft.
