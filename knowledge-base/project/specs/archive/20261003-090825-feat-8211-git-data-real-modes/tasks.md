# Tasks: git-data cutover residual gaps (#8211)

Plan: knowledge-base/project/plans/2026-10-02-feat-git-data-cutover-residual-real-mode-gaps-plan.md

## PR-A — cutover hardening (Refs #8211)

### 1. Host-set parity (P1)
- 1.1 Add env seams (workflow path, variables.tf path) to web-hosts-fanout-parity.test.sh
- 1.2 Add readback-host key extractor and a set-equality operand with its own floor
- 1.3 Mutation rows: extra var.web_hosts key, missing readback entry, zero-match extractor, reorder (GREEN)

### 2. Notify job (P2)
- 2.1 Give the finalizer step an id; write freeze_held / recovery_failed to GITHUB_OUTPUT only on failure branches, before exit 1
- 2.2 Set unfreeze/recovery outputs from the real exit code in mode=unfreeze and the rollback trailing unfreeze
- 2.3 Make nothing_to_rollback report a held sentinel
- 2.4 Add jobs.cutover.outputs (mode, started, freeze_held, recovery_failed, probe_failed)
- 2.5 Add notify-failure job (checkout, permissions, timeout, no environment, no concurrency, if clause with started and probe_failed)
- 2.6 Issue channel (ci/git-data-cutover) primary, ops email secondary; STATE UNKNOWN body and unfreeze remedy line; no free-text interpolation
- 2.7 Update census rows: WF-jobs, WF9, AC9 local-action row, _wf_n floor, wr_sites over all jobs; add Guard 2 rows 1-8
- 2.8 Reconcile header wording at git-data-cutover.yml:29

### 3. Rollback probe (P3)
- 3.1 Widen the single MODE=probe step if to flip||rollback, gated on unfreeze success; amend WF-gating rows
- 3.2 Probe failure fails the run red after unwind and sets probe_failed; notify names residue_left
- 3.3 Runbook: pre-flip flip-then-rollback rehearsal precondition with a run-URL slot

### 4. Downtime statements (P4)
- 4.1 Measure redeploy duration from deploy-status frames / release runs
- 4.2 Runbook downtime table (flip, rollback, redeploy, rotate) with sources; header pointer line
- 4.3 User-visible refusal-window statement, Art. 12(3) clock, cross-ref #9153

### 5. Records (P7)
- 5.1 ADR-241 D1 line classifying RESEND_API_KEY as Tier A
- 5.2 AC-1 hash-bound-set check script (template + file() payloads in modules/git-data-userdata/main.tf)
- 5.3 GitHub: #8211 checklist/umbrella, #8573 comment + owner request, #8571/#8093 notes, observability issue (flip precondition), deferred-items issue(s), re-erasure/positive-replication blocker statement

## PR-B — bound apt cycles (P5, #9395)
- 6.1 git-data-cutover-access.test.sh: bounded helper, keep _runtime_skip fail-closed
- 6.2 cloud-init-inngest-provision-unit.test.sh: bounded helper, bash -c
- 6.3 apt-bounded.test.sh: glob-derived assembly row, widened docker regex, recount floors

## P6 — #9066 closeout (standalone, deadline 2026-10-24)
- 7.1 Verify constant .init.lock and freeze-window purge (count only) with file:line
- 7.2 State plaintext retention end in ADR-239 and runbook if missing
- 7.3 Comment on #9066; leave open until the purge has run

## Authorization-gated (not performed)
- #8609 R-steps, #8209 residue, #9361/#9362, entrypoint-audit dispatch, #8573 credential, git-data-host-rotate, rehearsal, mode=flip
