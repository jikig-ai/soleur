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
