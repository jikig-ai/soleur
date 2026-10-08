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
