# Decision challenges — feat-one-shot-8285-retire-inngest-plaintext-backstop

## 2026-10-08 — User-Challenge: erasure mechanism diverges from "same shape as the web-1 wipe"

**Stated direction (default):** zero + read-back + detach + Hetzner API delete + Terraform state forget, the shape of the web-1 plaintext /workspaces wipe, with an `[ack-destroy]` procedure for the Terraform removal.

**Plan's divergence:** (1) the zero runs on a short-lived Terraform-managed throwaway Hetzner server instead of the inngest host, because the inngest host has no SSH or deploy-webhook channel (its only inbound path is a Doppler-flag FSM shipped in the bootstrap image, so a host-side wipe needs an image release, a pin bump and an approved host replace of the sole scheduler, with the live LUKS volume attached next to the wipe target); (2) detach, delete and state removal are done by Terraform in two gated dispatch phases instead of a raw Hetzner API workflow plus a `terraform state rm` workflow; (3) `[ack-destroy]` is not used because it only reaches the per-merge `-target` apply, which never targets these addresses, and the dispatch gates carry no ack bypass.

**Why:** CTO advisory (no replace, live volume never attached to the wipe host, less throwaway code); verified in `plugins/soleur/test/terraform-target-parity.test.ts` (`OPERATOR_APPLIED_EXCLUSIONS`) and `tests/scripts/lib/inngest-volume-recut-gate.sh` ("NO [ack-destroy] BYPASS").

**Choices if the operator disagrees:** (a) on-host FSM wipe + image release + approved host replace (adds an outage window and the #8620 root-disk decision); (b) delete without zeroing (needs CLO attestation as a weaker-evidence downgrade; also the plan's D4 fallback after 2026-10-17).

## 2026-10-08 — Taste: one plan, two PRs

The plan recommends a split (PR A apparatus/decoupling, PR B convergence after the Hetzner read-back) because the probe retirement and ledger-row removal are ordered after the destroy by the probe's own header and by the brief.

## 2026-10-08 — Plan-review consolidation (5-agent panel, single-user-incident threshold)

Applied as mechanical: teardown gate accepts any subset of the wipe addresses; per-phase idempotent convergence and a `teardown` phase; evidence bound to the wipe run's nonce; the baseline-count precondition replaced by reachability plus identity (counts legitimately move); the live-store gate moved in front of EVERY phase; wipe step A pins `after.volume_id`; untargeted plan must list the server as a no-op; `started` row and an idempotent already-blank path; pre-merge read-only plan as D1 proof; orphan-destroy experiment in Phase 0; missing files added (stock-preflight and escrow-census tests, shard TSVs, runbook cross-references); Guard 5 and task 1.3b cut (maps to no property).

Surfaced, NOT applied (Taste):
- **Fold `detach` into `wipe` step A** (DHH, SpecFlow): saves one dispatch and one go-ahead. Kept separate: the orphan attachment destroy and the wipe attachment create have no graph edge, so one apply could try to attach a still-attached volume, and `detach` is the irreversible rollback cut that deserves its own pause with the D1 proof on live state.
- **Trim Guards 1 and 3 and the "edit the suite itself" harness rows** (DHH, simplicity): kept; the plan skill's guard-contract gate requires harness rows and these guards protect the sole-scheduler host and a customer-data volume.
- **Write the ADR addendum once, in PR B** (DHH): kept as "adopting" in PR A per the plan-time ADR-deliverable rule.
- **Schedule risk** (~45 files, ~1,900 lines against a non-extendable 2026-10-22): mitigated by the two-PR split, target dates in Phase 2 and the 2026-10-17 D4 decision point; the operator may prefer to shrink PR A further.

## 2026-10-09 — Review round 1 of PR #9784 (13-seat panel, panel SHA 63266dcaa8)

No seat found a P1 in the product code. The dispositions below are the lead's; the code changes ride in
the same fix round and the records changes are in the ADR-142 addendum of 2026-10-09, the runbook
(`inngest-luks-cutover-6894.md` §5b) and the destruction record's addendum. Ref #8285, Ref #6894.

Decided as mechanical (applied in the fix round):
- Wipe evidence is corroborated from Hetzner's action history for the volume, not from a new secret;
  every record now says a stale or replayed row fails and a holder of the shared ingest token could
  forge one (ADR-142 addendum E1).
- The D4 attestation is a specific #8285 issue comment fetched through the GitHub API (E2).
- The untargeted whole-root plan blocks only on the host, the LUKS pair, the live id and the phase's
  authorized set, not on unrelated drift (E3); `teardown` is exempt from the live-store gate (E4); the
  refresh-only reconcile is gated on an exact one-address state diff (E5).
- Orphan-window control is the runbook plus the HALT-text fix, not a new Terraform resource.
- Workflow size is held under the file-size gate by moving prose into the job-rationale runbook.

### 2026-10-09 — Taste (not applied): a rehearsal path for the wipe

**Surfaced by:** history seat (P2). **Option:** a dry-run input for the wipe so the script runs end to end
against a scratch volume or in a no-write mode before the real one.
**Not applied because:** it needs a new input threaded through cloud-init, Terraform, `variables.tf`, the
workflow and their tests, and the first real wipe's own guards already refuse before any write, so a
refusal costs one approval cycle, not data. **Recorded as:** an operator-facing prerequisite in runbook
§5b ("no wipe rehearsal exists") and the destruction record's rehearsal column ("none: no rehearsal path
exists"). Revisit if the first `wipe` is refused for a reason a rehearsal would have caught.

> Clarified 2026-10-09 (round 2): "refuse before any write" holds for the pre-write guards only. The
> post-write guards `zero_failed`, `readback_nonzero` and `sig_survived` fire after the write began, so a
> refusal by one of them can leave the device partly zeroed and the rollback gone (runbook section 5b,
> "When the wipe does not go green").

### 2026-10-09 — Taste (not applied): LUKS key and header continuity proof

**Surfaced by:** history seat (P2). **Option:** prove, before the backstop goes, that the Doppler key and
the on-disk LUKS header still open the live volume.
**Not applied because:** there is no SSH-free channel to open the header, and the gap predates this work
(ADR-142). The running host serving from the mapper is the only available evidence. **Recorded as:** an
operator-facing prerequisite in runbook §5b, accepted knowingly before `detach` because `detach` ends
the rollback.

### 2026-10-09 — Taste (not applied): simplicity cuts S2 to S13

**Surfaced by:** simplicity seat. Not applied, recorded so the operator and PR B see them. Line savings
are the seat's own estimates.

| Cut | What | Seat's estimate | Why kept |
|---|---|---|---|
| S1 | Live-store gate on `teardown` and `destroy` | not estimated | Partly applied: `teardown` is exempt (E4) so a leaked host is always cleanable; `detach`, `wipe` and `destroy` keep it because those are the phases that can strand or delete user data |
| S2 | The untargeted whole-root plan machinery | about 85 lines | It is the live-state proof (D1) that the cloud-init pin leaves the host alone; narrowed by E3 rather than removed |
| S3 | The dead in-flight-run check and the Hetzner LUKS cross-check | about 45 lines | Kept unless the workflow-size gate forces it; first in the cut order if so |
| S4 | The refresh-only reconcile | about 25 lines | Kept and gated (E5): it is what lets a retry converge after a partial apply |
| S5 | Four redundant guards in the wipe script | about 80 lines | The script writes to a customer-data volume; each guard fails closed before a write and PR B deletes the script |
| S6 | The time floor and the run lookup | about 35 lines | They bind a row to the wipe run (stale or replayed rows fail) |
| S7 to S14 | Optional cuts | not itemised in the consolidation handed to the records author | Not applied; PR B deletes the apparatus they would trim |

If the workflow-size gate (`plugins/soleur/test/workflow-file-size.test.ts`) still fails after the prose
moves, the cut order is S3, then the post-apply loop that duplicates a gate check, then the
progress-comment trim.

> Superseded in part 2026-10-09 (round 2): S3 was applied, not held in reserve. See "Applied: the
> in-flight-run check is cut" below.

### 2026-10-09 — Verified measurement: the orphan `-target` chain

A local-backend experiment on Terraform 1.9.8 reproduced the orphan chain (the attachment depends on the
volume and the server): `plan -target` on the attachment plans only the attachment delete, and `plan
-target` on the volume plans only the volume delete. This refuted the architecture seat's P2 that a
targeted destroy would expand to dependents. The workflow pins 1.10.5, so the experiment is re-run on
that version before the first dispatch; the retire gate fails closed (abort, no mutation) if the plan
shape differs. Recorded in ADR-142's 2026-10-09 addendum and runbook §5b.

### 2026-10-09 — Open: the workflow input count

actionlint reports 13 `workflow_dispatch` inputs against a limit of 10. The lead is verifying GitHub's
current limit, and no input is removed in this round; this is likely a stale tool limit, not a defect.

## 2026-10-09 — Review round 2 of PR #9784 (the second and last targeted fix round)

Dispositions are the lead's. The records are in the ADR-142 addendum of 2026-10-09 (round 2), runbook
`inngest-luks-cutover-6894.md` §5b and the destruction record's second addendum. Nothing here states that
the volume has been wiped, detached or destroyed. Ref #8285, Ref #6894.

### 2026-10-09 — Applied: the in-flight-run check is cut (simplicity S3)

**Surfaced by:** simplicity seat (S3, round 1); the round-2 panel (finding G1) recorded that the check was
unpinned and fail-open. **Decision:** the live-store step no longer polls the
Actions API for other apply runs and no longer cross-checks the LUKS volume's attachment against the
Hetzner server listing; the gate loses its `--inflight-runs`, `--server-id` and `--luks-volume-file`
options, their reasons, fixtures and pins. **Why this is safe:** the workflow-level concurrency group
`terraform-apply-web-platform-host` (`cancel-in-progress: false`) already queues a second run, and the
probe row's `data_mount_devid` proves the live mount. The cut also pays the workflow byte budget. **What
it costs:** a run that somehow escaped the concurrency group would no longer be seen by this gate; the
group is the shared, load-bearing serializer for the unlocked R2 state, so that is a workflow-wide
failure, not this gate's.

### 2026-10-09 — Applied: teardown exemptions

**Surfaced by:** quality seat (P2-1) and data seat (N3). **Decision:** `teardown` skips the live-store
gate (round 1, E4) and now also the untargeted whole-root plan, so a leaked wipe host is cleanable
whatever state the rest of the root is in. **Compensating control:** the teardown plan is still graded
exactly, and on the wipe server's physical identity (the pinned name `soleur-inngest-backstop-wipe` and a
physical id other than the live server's 169426216; otherwise `wipe_server_identity`), so the exemption
cannot be used to delete the live host.

### 2026-10-09 — Applied: tighter provider-only attestation (two-person rule)

**Decided by:** the lead in round 2, as the follow-up to D-B. **Decision:** the D4 comment needs an exact
first line, must be unedited, from a human `User` with `OWNER` or `MEMBER` association (not
`COLLABORATOR`), from a login different from the dispatching actor's. **Cost accepted:** a one-person
organization cannot use D4 alone; the operator is told so at the decision point.

### 2026-10-09 — Taste (not applied): Hetzner delete-protection or a `removed {}` guard for the orphan window

**Surfaced by:** structural seat (F1). **Option:** make the two orphan addresses un-deletable by an
accidental untargeted apply (Hetzner delete-protection on the volume, or a Terraform `removed {}`
block). **Not applied because:** D-H decided no new Terraform resource for the window, and both options need
one (a re-declaration) or an extra production write per phase (lift the protection before the sanctioned
`destroy`); the control in place is the runbook paragraph plus the corrected operator-apply text in the
workflow and the drift cron's next-steps. Revisit if an untargeted apply is ever attempted in the window.

### 2026-10-09 — Taste (not applied): refusing a host replace while an orphan is in state

**Surfaced by:** structural seat (F4). **Option:** make an Inngest host replace refuse while either
orphan address is in state, since a replace implicitly detaches the backstop and ends the rollback.
**Not applied because:** it reaches into the host-replace gates, outside this change's scope, for a window
of days; the runbook says not to dispatch a replace in the window and the rollback banner (§5a) says a
replace ends the rollback.

### 2026-10-09 — Taste (not applied): a preventive, plan-gated refresh-only reconcile

**Surfaced by:** structural seat (F3) and data seat (N1). **Option:** run the reconcile as a plan whose
shape is gated before the state write, instead of comparing `terraform state list` afterwards.
**Not applied because:** the reconcile exists only to converge a retry of a single state-only address, the
detective comparison was judged enough for that, and a gated pre-write plan is a second round trip to
build and test inside the byte budget. The limit ("recover by re-planning") is recorded in the runbook
and the ADR (E10).

### 2026-10-09 — Taste (not applied): per-run HMAC or Hetzner instance-id binding of the evidence row

**Surfaced by:** security seat (the D-A residual). **Option:** bind the row to something the ingest-token
holder cannot mint. **Not applied because:** D-A forbade a new secret, and instance-id binding needs the
wipe host to learn its own Hetzner id and the gate to compare it, a change in cloud-init, the funnel and
both suites. The residual (a forged row inside a real attach-to-detach window) is stated in every record.

### 2026-10-09 — Taste (not applied): the workflow deleting a leaked wipe host through the API

**Surfaced by:** data seat (P3-1 and P3-3) and security seat (P3-3). **Option:** `teardown` deletes
labelled servers by id when they are absent from state. **Not applied because:** it is a new
privileged API write outside Terraform's state and the workflow byte budget was already tight
(round 1 allowed it only within budget); the runbook triage table covers the case with a named
go-ahead.

### 2026-10-09 — Taste (not applied), recorded elsewhere: rehearsal, key continuity, simplicity cuts

The wipe rehearsal mode and the LUKS key-or-header continuity proof (history seat) are recorded in
"2026-10-09 — Taste (not applied)" above with their reasons; they stay unbuilt. Simplicity cuts S2, S5,
S6 and S7 to S14 are in the table above and stay unapplied (S3 is applied, see above); S1 is applied in
part (teardown). The seat's own estimates are in that table.

### 2026-10-09 — Open: the workflow input count (carried over)

Unchanged from round 1: actionlint's count of 13 `workflow_dispatch` inputs against 10 is unresolved in
this round and no input is removed.
