---
title: "Retire the plaintext Redis AOF backstop volume after the LUKS cutover window"
date: 2026-10-08
slug: retire-inngest-plaintext-redis-backstop
branch: feat-one-shot-8285-retire-inngest-plaintext-backstop
issue: 8285
type: chore
priority: p2-medium
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# Retire the plaintext Redis AOF backstop volume `hcloud_volume.inngest_redis` (#8285, also tracks #6894)

## Overview

`hcloud_volume.inngest_redis` (Hetzner id **106261946**, ext4, 10 GB, location hel1, attached to
`hcloud_server.inngest` id 169426216) is the pre-cutover copy of the Inngest Redis append-only file,
kept as the `op=luks-rollback` target since the additive cutover of 2026-09-20 (ADR-142, #8296). The
live store runs on its encrypted sibling `hcloud_volume.inngest_redis_luks` (id **106903269**). The
backstop is a second, unencrypted copy of in-flight user prompts, agent output and armed reminders as
of the freeze; its ledger exception carries `expires_on: 2026-10-22` and the date is pinned
(`expires_on_not_extended`). This plan retires it: evidence gates, erasure (zero plus read-back),
detach, delete, state convergence, and the record changes that may only follow the Hetzner API
showing the volume gone.

**The known coupling, resolved (decision D1).** `inngest-host.tf` feeds
`inngest_volume_id = hcloud_volume.inngest_redis.id` into the cloud-init template (`PLAIN_ID`), so
deleting the volume changes `user_data` and force-replaces the sole-scheduler host (the root-disk
decision in #8620). This plan does **not** replace the host. It pins the template input to the literal
current id string `"106261946"` in a local, so the rendered `user_data` is byte-identical and
`hcloud_server.inngest` plans no change. It also removes the only graph edge between the server and
the volume, which is what makes a targeted destroy of the volume safe (a destroy-mode plan destroys
dependents, and `hcloud_server.inngest` is currently a dependent through `local.inngest_user_data_plain`).
The dead plaintext resolver arm stays in `user_data` until the next replace that is already scheduled
for another reason (follow-up #9786, folded into #8620 if that lands first).

**Erasure without a host replace (decision D2).** The inngest host has no SSH and its only inbound
channel is a Doppler-flag-polled FSM shipped in the bootstrap image; adding a wipe there would need an
image release, a pin bump and an approved host replace (a cron outage on the sole scheduler, with
the live LUKS volume attached beside the wipe target). Instead the volume is detached from the host,
attached to a **short-lived throwaway Hetzner server** (Terraform-managed, count-gated, deny-all
inbound, torn down in the same dispatch) that zeroes it with `blkdiscard -z`, reads it back with
O_DIRECT, and ships a `SOLEUR_INNGEST_BACKSTOP_WIPE` evidence row to Better Stack. The live LUKS
volume is never attached to the wipe host, so a mis-resolved device cannot reach the live store.

**Convergence (decision D3).** Three small, individually gated phases of one new dispatch target
(`apply_target=inngest-backstop-retire`, converted from the `inngest_volume_recut` chassis that already
destroys exactly this volume pair under an id-pin and a reviewer-gated environment): `detach` (Terraform
destroys the orphaned attachment), `wipe` (the throwaway host), `destroy` (Terraform destroys the
orphaned volume; state converges in the same apply, so there is no separate forget step). Two PRs,
mirroring the web-1 wipe (PR A tooling and decoupling, dispatches, PR B convergence).

## Addendum — 2026-10-09: supersessions from review round 1 of PR #9784

Appended; the text below is kept as written on 2026-10-08. Where it conflicts with this block, this block
governs. Rationale and the full decision list are in the ADR-142 addendum of 2026-10-09 (E1 to E6) and
`decision-challenges.md`. Ref #8285, Ref #6894.

- **Evidence authenticity.** Statements below that the nonce, the Hetzner id/size re-check and the run
  timestamp "make a stale or forged row fail" are corrected to: they make a stale or replayed row fail;
  a holder of the shared ingest token could forge a row; Hetzner's action history for the volume
  (a successful `attach_volume` to a server that is neither 169426216 nor null, finished not before the
  wipe run's start, then a successful `detach_volume`) corroborates it.
- **D4 attestation.** "A URL ... non-empty and resolvable" is corrected to exactly
  `https://github.com/jikig-ai/soleur/issues/8285#issuecomment-<digits>`, fetched through the GitHub API,
  author an owner, member or collaborator, body containing 106261946.
- **2.0 live-store gate and untargeted plan.** The gate applies to `detach`, `wipe` and `destroy`, not
  `teardown`. In untargeted mode the plan requires only the server and the LUKS pair as one no-op each,
  nothing carrying the live id 106903269, and the retired and wipe addresses within the phase's authorized
  set; other resources are ignored there. The targeted plan stays exact.
- **2.1.** "Tolerate a 404 on the detach call" is replaced by the Hetzner-first convergence read: if the
  volume already shows `server: null` or is gone, the phase skips the plan, and a stale attachment entry
  is dropped by the gated single-address refresh-only reconcile.
- **2.3.** "Whose timestamp is later than the detach run's" is corrected to: not earlier than the wipe
  run's start.
- **Rollback.** It ends at `detach` or at the first host replace after PR A merges, whichever is first.
- **Orphan window.** No untargeted `terraform apply` of the root until `destroy` completes; the per-merge
  apply's HALT text no longer prescribes one; no new Terraform resource.
- **Not built, recorded as prerequisites:** a wipe rehearsal path and a LUKS key or header continuity
  proof (runbook `inngest-luks-cutover-6894.md` §5b; `decision-challenges.md` 2026-10-09).

## Research Reconciliation — Spec vs. Codebase

| Claim (issue #8285 / brief) | Reality (verified 2026-10-08) | Plan response |
|---|---|---|
| Step 4: "remove the attachment, then the volume, and run the `[ack-destroy]` procedure" | `[ack-destroy]` (apply-web-platform-infra.yml `apply` job, `destroy_count` guard) only reaches the per-merge `-target` apply. That job never targets these two addresses (`OPERATOR_APPLIED_EXCLUSIONS` in `plugins/soleur/test/terraform-target-parity.test.ts`). The dispatch jobs that do target them use exact-equality gates with "NO [ack-destroy] BYPASS" (`tests/scripts/lib/inngest-volume-recut-gate.sh`). | The ack route is not used. A dedicated reviewer-gated dispatch with a plan-shape gate and an id-pin does the destroy (D3). The issue's step 4 wording is superseded here and in the runbook. |
| "Removing the volume force-replaces `hcloud_server.inngest`" (comment 2026-09-23) | True: `inngest-host.tf` `templatefile` map `inngest_volume_id = hcloud_volume.inngest_redis.id`; `cloud-init-inngest.yml` renders it at two sites (`PLAIN_ID`). | D1: literal pin, byte-identical render, no replace. Proven by the `detach` phase's own plan (server must show no action) before any destructive apply. |
| "Zero + read-back + detach + API delete + state forget, same shape as the web-1 wipe" | Web-1's wipe ran an on-host script over its deploy channel (`wipe_plaintext()` at git `59abf6a76c`), then raw Hetzner API detach/DELETE, then a `terraform state rm` workflow. The inngest host has no such channel. | D2 for the zero (throwaway host) and D3 for detach/delete/state: Terraform performs the API calls and the state removal in one gated apply; no bespoke API-delete or `state rm` workflow. Divergence recorded as a user-challenge in `decision-challenges.md`. |
| "Step 1: `data_mount_devid` equals the `inngest_redis_luks` by-id alias" | Confirmed live: newest `host_role=dedicated` `SOLEUR_INNGEST_SERVER_PROBE` rows carry `data_mount_devid=scsi-0HC_Volume_106903269` and `data_mount_src=/dev/mapper/inngest-redis`; Hetzner volume 106903269 is `soleur-inngest-redis-store-luks`. | Re-pulled at work start and again as a destroy-phase precondition. |
| "Step 2: wrong-volume alert armed, not fired since cutover" | Armed: `logtail_exploration_alert` 2988582970 reads `paused=false`, `higher_than 0`, `treat_as_zero`. Zero incidents named `soleur-inngest-luks-wrong-volume-prd` among the 48 incidents listed for 2026-09-20..2026-10-09. `scripts/followthroughs/inngest-luks-property-8296.sh` run locally today: `verdict=agree claim=luks`. | Re-pulled as a destroy-phase precondition. |
| Brief: "the destroy PR also deletes the probe, test and `run_suite` line" | The probe's own header says retire it only AFTER the destroy apply shows the volume gone; closing #8285 turns the ledger-vs-device probe off. | Probe retirement is in PR B, after the Hetzner API read-back. |
| Brief: "root-disk decision tracked in #8620" forces a replace | A pin bump replaced the host on 2026-10-08T19:24Z (server created then; apply runs 37829680169 / 37831488134), so replaces are routine, but nothing in this change needs one. | No replace. #9786 tracks stripping the dead arm at the next replace. |
| Brief: "note the overlap with draft PR #8626" | #8626 (draft, stale since 2026-09-28) edits `scripts/encryption-posture-ledger.json` and `scripts/lint-encryption-posture.py`. This plan edits only two ledger rows and no lint code. | Rebase PR B onto main at ship; resolve any ledger textual conflict by keeping both edits; do not depend on #8626. |

## Research Insights

**Premise validation (Phase 0.6).** #8285, #6894, #8620, #8527, #8626 are all OPEN; #9348 (the web-1
PR B) is MERGED. `hcloud_volume.inngest_redis` and `hcloud_volume_attachment.inngest_redis` exist on
`origin/main`. The brief's `[ack-destroy]` premise is stale (table above). The proposed mechanism
(a flag-driven on-host wipe) was checked against the ADR corpus: ADR-142 keeps the backstop for
rollback and defines the Doppler-flag FSM; ADR-199 owns the recut and its empty-store clearance;
neither rejects an ephemeral wipe host.

**Property list (Phase 0.6b).**
- P1. The plaintext copy of the AOF no longer exists in Hetzner (volume deleted) and its content was
  overwritten before release, with off-box evidence.
- P2. The sole-scheduler host and its live encrypted store are untouched: no replace, no reboot, LUKS
  pair and server show no plan action.
- P3. Every record (ledger, runbook, ADR-142, C4, Article 30, probes, alerts) changes only after the
  Hetzner API shows the volume gone.
- P4. Each destructive write is individually gated and pinned to the physical volume id; a mistargeted
  volume cannot be destroyed.
- P5. #8285 and #6894 close only after the destroy is evidenced; the probe retires after that.

**Cut list.**
- Terraform `removed {}` / `terraform state rm` forget workflow -> P1 state convergence -> bought by the orphan targeted destroy, which removes state in the same apply (authority grepped: apply-web-platform-infra.yml `inngest_volume_recut`, the #8754 `removed` precedent applies only to a NON-destroy forget).
- Bespoke Hetzner-API detach/DELETE workflow (web-1 shape) -> P1 -> covered by Terraform with the gate lib + id-pin.
- `[ack-destroy]` procedure -> P4 -> unreachable for these addresses (table row 1); the reviewer-gated environment is the authorization.
- On-host wipe FSM state + image release + pin bump + host replace -> P1 -> cut by D2 (throwaway host); also removes the live-store mis-resolution class.
- Host replace to decouple the template -> P2 -> cut by D1.
- Final snapshot -> already removed from the issue (creates a new plaintext copy).

**Evidence snapshot (read-only, 2026-10-08, Doppler `soleur/prd_terraform`, no secret printed).**
- Hetzner volumes: 106261946 `soleur-inngest-redis-store` ext4 attached to server 169426216, `protection.delete=false`; 106903269 `soleur-inngest-redis-store-luks` attached to the same server. Server 169426216 `soleur-inngest` cpx22, created 2026-10-08T19:24:54Z, `no-backups`. Snapshots: 0. Backups: 0. Web-1 LUKS volume 106443278 untouched and out of scope.
- Doppler `soleur-inngest/prd`: `INNGEST_LUKS_ACTIVE_VOLUME_ID=106903269`, `INNGEST_LUKS_CUTOVER=done`.
- The host booted fresh today in pointer mode with the plaintext volume attached and never mounted it (probe: `/dev/mapper/inngest-redis` on 106903269).
- Lint experiment (scratch copy, not the worktree): deleting the two resource blocks while the ledger row stays still PASSes `scripts/lint-encryption-posture.py` (the partition check is one-way), so PR A may remove the declarations before the ledger row goes.
- Two further ledger exceptions (`git_data.baked_credentials_on_host`, registry/inngest in_transit) also expire 2026-10-22; they belong to other runs and are not touched here.

**Learnings applied.** `2026-07-17-target-scoped-terraform-apply-makes-resource-deletion-a-silent-noop`
(a removal outside the target set is a no-op); `2026-07-23-terraform-destroy-guard-address-vs-physical-id-and-replace-recovery-arm`
(pin the physical id against `.change.before.id`); `2026-07-07-immutable-redeploy` (`-target` pulls
dependencies, not dependents; any render change replaces the host); `2026-09-03-the-gate-cleared-the-destroy-and-never-graded-the-create`
(read the plan JSON, not the comment); `2026-10-01-the-guards-i-wrote-to-protect-the-sole-copy-scanned-a-shape-the-attack-did-not-take`
(the retirement guard must cover the attachment and census every path to the destructive primitives);
`2026-06-05-followthrough-pr-body-prose-closes-keyword-autocloses-tracker` (use `Ref #8285`, never a
closing keyword); `2026-07-08-inngest-cutover-authoring-review-and-observability-allowlist` (a new
`logger -t` tag is invisible off-box; the wipe host therefore POSTs directly to the ingest endpoint
like `inngest-boot-phone-home.sh`, which needs no `vector.toml` allowlist entry).

## Hypotheses

The network-outage gate fired on the constraint wording "no SSH"; there is no connectivity symptom to
diagnose. L3 facts the design relies on: the wipe host is created with the existing deny-all-inbound
firewall `hcloud_firewall.inngest` (Hetzner firewalls filter only inbound public traffic, so egress to
the Better Stack ingest host is unaffected); no inbound path to the wipe host is needed or provided; DNS
for the ingest endpoint is the same one `inngest-boot-phone-home.sh` already uses from the dedicated host.

## Proposed Solution

### Decisions

- **D1 literal pin.** In `inngest-host.tf` add `local.inngest_retired_plaintext_volume_id = "106261946"`
  and pass it as `inngest_volume_id`. Keep the key (`inngest-boot-emitter.test.sh` AC5 key-set parity
  floor 17 and `inngest-userdata-budget.sh` stub depend on it). The value stays numeric (cloud-init
  FATALs on a non-numeric id and when `PLAIN_ID == LUKS_ID`). In pointer mode `PLAIN_ID` is only an
  allowlist member (`inngest-luks-open.sh`, the runcmd resolver, `/etc/default/inngest-luks-volumes`);
  if the Doppler pointer were ever lost the pre-cutover arm fails closed at `wait_dev` on the absent
  device and never formats.
- **D2 throwaway wipe host.** `apps/web-platform/infra/inngest-backstop-wipe.tf` (whole file deleted by
  PR B): `var.inngest_backstop_wipe_enabled` (bool, default false) gates `count` on
  `hcloud_server.inngest_backstop_wipe` and `hcloud_volume_attachment.inngest_backstop_wipe`
  (`volume_id` = a numeric variable pinned to 106261946, `automount = false`). Same location
  (`var.location`, hel1), smallest x86 type with stock (reuse the stock preflight pattern from
  `inngest-host-replace`), `firewall_ids = [hcloud_firewall.inngest.id]`, labels
  `role=inngest-backstop-wipe`, `ephemeral=true`. The only credential in its `user_data` is the
  write-only Better Stack ingest token, reusing the existing no-default `var.betterstack_logs_token`
  (already provisioned from Doppler `prd_terraform`; no new secret variable, so the merge-triggered
  apply cannot fail on an unprovisioned variable); the LUKS key and Doppler tokens never reach it.
- **D3 Terraform-native retire dispatch.** Convert the `inngest_volume_recut` job
  (`apply_target=inngest-volume-recut`) into `inngest_backstop_retire` with a `phase` input
  (`detach`, `wipe`, `teardown`, `destroy`). Reuse its reviewer-gated environment `inngest-cutover` (with the
  non-empty-reviewer assertion), `confirm` typo token, `expected_inngest_volume_id` id-pin input,
  tiered credential loader and the `deploy-inngest-restart` concurrency group, and ALSO join the
  root's `terraform-apply-web-platform-host` group (the state backend has `use_lockfile = false`, so a
  merge apply racing a phase could clobber a state write and forget an orphan). The new plan-shape
  gate is a REWRITE, not a conversion: the old gate demands delete AND create and a born-RAW volume;
  reuse only its preamble, `named_live` pattern and id-pin counters. Keep
  `tests/scripts/lib/inngest-host-dark-gate.sh` (still used by `scripts/cutover-inngest.sh` and listed in
  `infra-validation.yml`); the retire job deliberately drops its empty-store predicates. The orphaned
  addresses are destroyed by `-target` (no `-destroy` flag, so no dependent expansion). Every phase is
  idempotent: it first reads Hetzner, and if its post-condition already holds (attachment gone, wipe
  host absent, volume 404) it exits green without planning, so a retry after a partial apply (apply
  succeeded, state write or later step failed) cannot dead-end on an exact-shape gate; if Hetzner says
  gone but state still lists the address, the phase runs a state-only reconcile for exactly that
  address. After every phase (success or failure) a step comments on #8285 with the run URL and
  read-back, which is also the failure notification and the days-remaining reminder.
- **D4 fallback.** If the `wipe` phase has not succeeded by **2026-10-17**, stop and ask for a
  decision: provider delete without zeroing (`detach` then `destroy`) is defensible per the CLO
  advisory if the record says "provider delete only, no overwrite, logical erasure not evidenced by
  read-back" and the CLO attests it as a downgrade. It beats an expired non-extendable Art. 32
  exception. It is never chosen silently. Implementation: the `destroy` phase accepts either a
  `wipe_run_id` input (evidence path) or `erasure=provider-only` plus a `clo_attestation_ref` input (a URL
  to the CLO attestation comment/file; the gate checks it is non-empty and resolvable); there is no third
  way past the precondition. The 2026-10-17 date is restated in every progress comment on #8285 and in
  the PR A body, so it does not depend on one live session remembering it.

### Implementation Phases

#### Phase 0 — evidence re-pull at work start (read-only)

0.1 Re-run the five reads above; they are gates, not decoration: devid/pointer/flag, alert state and
incident list, `scripts/followthroughs/inngest-luks-property-8296.sh` verdict, Hetzner volume list,
snapshot/backup counts. 0.2 Record the live store's `redis_keys` / `redis_active` from the newest probe
row for the destruction record as an INFORMATIONAL before/after pair only (counts legitimately move as
reminders fire, so no gate compares to it; the live-store gate is reachability plus identity, see 2.0).
0.3 Run a throwaway local-backend experiment (a `terraform_data` resource, applied, then its block
deleted, then `terraform apply -target=<addr>`) to prove an ORPHAN state entry is destroyed by `-target`
alone and that plan JSON carries the delete; nothing in the repo proves it today (the recut job destroys a
still-declared resource via `-replace`). 0.4 Read the on-host rollback path
(`apps/web-platform/infra/inngest-luks-cutover.sh`, `rollback)` arm and `assert_ids`) and its fixture rows:
confirm `op=luks-rollback` refuses when the plaintext device is absent; if it does not, retire the op in
PR A instead of guarding it. 0.5 Confirm `gh api repos/:owner/:repo --jq .squash_merge_commit_message`
and keep every closing keyword out of commit bodies and PR bodies (`Ref #8285`).

#### Phase 1 — PR A: decouple, apparatus, gates (no production effect on merge)

1.1 `inngest-host.tf`: D1 pin; delete the `hcloud_volume.inngest_redis` and
`hcloud_volume_attachment.inngest_redis` blocks and every comment that depends on them; drop the
volume-unknown-at-plan "HONEST LIMIT" text. State still holds both addresses, so they become
orphans; nothing auto-destroys them (see Sharp Edges).
1.2 New `inngest-backstop-wipe.tf` and `cloud-init-inngest-backstop-wipe.yml` (D2). The script, in
order: bounded wait for `/dev/disk/by-id/scsi-0HC_Volume_106261946`; refuse unless that path is a
whole block device of exactly the expected size, `blkid -p` TYPE is `ext4` (never `crypto_LUKS`), it
is unmounted with no sysfs holders; emit a `started` row (so a crash after this point is distinguishable
from "never booted"); capture non-payload identity (fs UUID, last-write time via `dumpe2fs -h`);
`blkdiscard -z`; `blockdev --flushbufs`;
full-device O_DIRECT read-back decided by `cmp -n <size> - /dev/zero` (both rc 0; never `cmp -l/-b`,
which print device bytes); `blkid -p` must now report no signature; POST one
`SOLEUR_INNGEST_BACKSTOP_WIPE result=started|wiped|refused nonce=… volume_id=… size_bytes=… readback=zero sig_after=none fs_uuid=… last_write=…`
row (the `nonce` is the GitHub run id of the wipe dispatch, delivered through `user_data`, so the destroy
phase can bind to THIS run's evidence; the ingest token is shared with other hosts, so the nonce, the
Hetzner-side id/size re-check and the run timestamp together make a stale or forged row fail, and the
record states the evidence is self-attested guest-side logical erasure, not physical) to the Better Stack ingest endpoint with the token on stdin (`curl -K -`), never on argv. A
`refused` row names the failed guard and exits without touching the device. Idempotent re-entry: if the
device already reads no signature and the full read-back is all zero at the expected size, the script
emits `result=wiped prior=blank` instead of refusing (a retry after a completed or crashed-after-zero
run must not dead-end); a damaged-superblock device that still reads all-zero takes the same path, and
one that does not is zeroed again from the `started` state. Server `ssh_keys` set explicitly to the
existing `hcloud_ssh_key.default` with `ignore_changes=[ssh_keys]` (no emailed root password), mirroring
`hcloud_server.inngest`; `hcloud_firewall.inngest` carries no `apply_to` selector (verified), so attaching a
second server plans no firewall update. Zero/read-back function
bodies are adapted from `git show 59abf6a76c:apps/web-platform/infra/workspaces-cutover.sh`
(`_wipe_readback`, the `blkdiscard -z` call); the io.max cap is dropped (dedicated host).
1.3 `apply-web-platform-infra.yml`: replace the `inngest_volume_recut` job and dispatch input docs
with `inngest_backstop_retire`; add the `phase` input; delete `-target` lines for the two removed
addresses from `inngest_host` (L~1739) and `inngest_host_replace` (L~2052) and the
`redis_volume_destroyed`-style jq selects on `hcloud_volume.inngest_redis`; add the wipe-host
addresses to the new job only. New `tests/scripts/lib/inngest-backstop-retire-gate.sh` (sourced by the
workflow step and by `tests/scripts/test-inngest-backstop-retire-gate.sh`, as the old pair was);
delete `inngest-volume-recut-gate.sh` and its test; adjust `inngest-host-shape-gate.sh` /
`inngest-host-replace-gate.sh` allow-sets. The new job creates an `hcloud_server`, so it carries the stock
preflight and the `HCLOUD_TOKEN` read like the other server-creating jobs
(`plugins/soleur/test/stock-preflight-coverage.test.ts` exclusion entry for `inngest-volume-recut` is
replaced by a coverage entry). Reword the workflow error text that sends readers to
`apply_target=inngest-volume-recut` (L~825-826) to the new recovery path.
1.3b (cut at plan review) The earlier Guard 5 / orchestrator-side rollback refusal is NOT built: it mapped
to no property and added a Hetzner credential to `cutover-inngest.yml` for an op PR B retires. The
protection is instead the 2.0 live-store gate at every phase (flag must read `done`, never `rollback`)
plus the 0.4 verification that the on-host path fails closed on an absent plaintext device.
1.4 Tests: `plugins/soleur/test/terraform-target-parity.test.ts` (inngest_host target count 17 -> 15,
the B6 attachment test, the recut describe block, B9 mutex list, `OPERATOR_APPLIED_EXCLUSIONS`);
`apps/web-platform/infra/inngest-host.test.sh`; new `inngest-backstop-wipe.test.sh` (loop-device
fixture with `--fixture-seams`-style gating if it needs seams, floor on assertions);
`scripts/test-all.sh` registrations; `scripts/suite-shard-legs.tsv` / `scripts/suite-durations.tsv`
(remove the recut suite rows, add legs for the new suites); `plugins/soleur/test/stock-preflight-coverage.test.ts`
and `plugins/soleur/test/web-host-escrow-preflight-census.test.ts` (both assert on
`inngest_volume_recut`; renaming the job fails them). Run the pre-merge read-only plan the CI already
runs (`infra-validation.yml`, config against live state) and read its JSON: `hcloud_server.inngest` no-op
and the only deletes are the two orphan addresses, so D1 is proven BEFORE merge, not first on the
production `detach` run.
1.5 Records created now (the deliverable is a plan task, not a follow-up): the destruction-record
template `knowledge-base/legal/audits/inngest-aof-backstop-destruction-record.md` (status template,
fields per the CLO advisory, all measured values `PENDING-EVIDENCE`); the ADR-142 addendum (status
adopting); the runbook section "Retiring the backstop (#8285)" with the exact dispatch commands and
a banner on §5a that rollback ends at the `detach` phase, plus the cross-references that name the deleted
dispatch (`apply-web-platform-infra-job-rationale.md` sections for `inngest_volume_recut`,
`infra-credential-tiers-8209.md` row, `inngest-server.md` pointers, `inngest-arm-write-token.tf` comments); `knowledge-base/product/roadmap.md` row
(CPO: wg-every-feature-listed-in-a-roadmap-phase).
1.6 Review, QA, ship PR A with `Ref #8285 #6894` (no closing keyword). Merge. The merge applies
nothing to these resources (per-merge `-target` set excludes them).

#### Phase 2 — production phases, each a separate dispatch with its own per-command go-ahead

The agent shows the exact command, waits for the go-ahead naming it, runs it, and self-pulls the
evidence. Target dates: PR A merged by 2026-10-12; `detach` by 10-13; `wipe` by 10-15; decision point
10-17; `destroy` by 10-17 (or the D4 path by 10-19); PR B merged by **2026-10-21**. The real deadline is PR B
merged, not the destroy: `scripts/lint-encryption-posture.py` fails an expired exception on 10-22 whether or
not the volume is gone. "Wiped but never destroyed" is a defined state: the volume is zeroed, detached and
rollback is gone, and the next move is `destroy`, not a retry of `wipe`.

2.0 Live-store gate, the SAME single chokepoint in front of every phase (`detach`, `wipe`, `destroy`),
proved before any plan is invoked: Doppler `INNGEST_LUKS_CUTOVER == done` (never `rollback`,
`rolled-back`, `armed`, `copying`), `INNGEST_LUKS_ACTIVE_VOLUME_ID == 106903269`, Hetzner shows 106903269
attached to server 169426216, the newest `host_role=dedicated` probe row is < 3 h old with
`data_mount_devid == scsi-0HC_Volume_106903269` and `redis_active` true, and no merge-triggered apply is in
flight (read the `terraform-apply-web-platform-host` group). Then an UNTARGETED read-only plan of the whole
root: `hcloud_server.inngest` MUST be present as a no-op entry (absence from a `-target` plan proves
nothing), the LUKS pair no-op, and the only non-no-op entries are within the phase's authorized set plus the
later phases' orphan or wipe addresses.

2.1 `detach` — `gh workflow run apply-web-platform-infra.yml --ref main -f apply_target=inngest-backstop-retire -f phase=detach -f expected_inngest_volume_id=106261946 -f confirm=RETIRE-INNGEST-BACKSTOP -f reason='#8285 detach plaintext backstop'`.
Gate: the targeted plan has exactly one non-no-op change, a delete of
`hcloud_volume_attachment.inngest_redis` with `tostring(before.volume_id) == 106261946`. After: rollback
is gone by design. Read back: Hetzner GET shows volume 106261946 with `server: null`. Tolerate a 404 on
the detach call (a routine host replace leaves a stale `server_id` on the orphan attachment).
2.2 `wipe` — same command with `phase=wipe`. Step A creates the wipe host and its attachment (gate:
exactly two creates, and `after.volume_id == 106261946` on the attachment, never 106903269, because the
volume variable is overridable through the Doppler `tf-var` environment). It passes the run id as the
nonce, and the job polls Better Stack for a row with that nonce, `result=wiped`, `volume_id=106261946`
and the expected size (bounded; absent row = fail, not pass). Step B runs under `if: always()` and
applies with `inngest_backstop_wipe_enabled=false`; its gate accepts ANY subset (0, 1 or 2) of deletes
of exactly the two wipe addresses and nothing else, so a half-failed step A still tears down. `phase=teardown`
runs step B alone for a leaked host. Read back: the evidence row, volume 106261946 detached again, wipe
server absent from `GET /servers`.
2.3 `destroy` — `phase=destroy` with `wipe_run_id=<the wipe dispatch run id>` (or the D4 inputs).
Preconditions beyond 2.0, proved before planning: a `wiped` row exists whose nonce equals `wipe_run_id`,
whose timestamp is later than the detach run's, with matching volume id and size (any such row counts, a
later `refused` or `prior=blank` row does not hide it); no live attachment of 106261946 exists. Gate:
exactly one delete, `hcloud_volume.inngest_redis`, `before.id == 106261946`; everything else no-op.
Terraform's apply deletes the Hetzner volume and drops the state entry. If Hetzner already says 404 and
state still lists the address, run the state-only reconcile for that address.
2.4 Verification (self-pulled, read-only token; a hard exit criterion for the phase): `GET
/v1/volumes/106261946` returns 404 (this also catches a clobbered state write that left the volume
orphaned on Hetzner); server 169426216 `volumes == [106903269]`; a read-only untargeted plan shows no entry
for either retired address; next probe row still `/dev/mapper/inngest-redis` on 106903269; wrong-volume
alert quiet AND a fresh probe row present (absence of an alert alone proves nothing); Hetzner
snapshots/backups still 0. The destruction record captures the destroy job's apply completion time and the
first 404 time (a 404 carries no timestamp itself) for the Article 30 amendments.

#### Phase 3 — PR B: convergence (after 2.4 is green)

3.1 Delete `inngest-backstop-wipe.tf`, its cloud-init template and test, the `inngest_backstop_retire`
job, its dispatch input docs, gate lib and test, and the matching parity expectations (web-1 precedent:
apparatus removed after use; the procedure as run lives in git history at the PR A merge SHA, named in
the runbook).
3.2 Retire `op=luks-rollback` in `.github/workflows/cutover-inngest.yml` and `scripts/cutover-inngest.sh`
(first step exits 1, like `workspaces-luks-recut`), with `cutover-inngest-workflow.test.sh` and
`scripts/guard-vacuity-floor.test.sh` updated; runbook §5a rewritten as "no rollback exists".
3.3 `scripts/encryption-posture-ledger.json`: remove the `hcloud_volume.inngest_redis` row; edit the
`hcloud_volume.inngest_redis_luks` row (`does_not_defend` no longer says a second copy exists;
`live_verification` text). `scripts/lint-encryption-posture.py` run; positive-work floor stays green.
3.4 Delete `scripts/followthroughs/inngest-luks-property-8296.sh`, its `.test.sh`, and the
`run_suite "scripts/inngest-luks-property-8296"` line in `scripts/test-all.sh`; fix stale comments in
`scripts/followthroughs/inngest-luks-cutover-6894.sh`, `betterstack-logs-alerts.tf`,
`uptime-alerts.tf`, `inngest-redis-luks.tf` ("size tracks the source"), `variables.tf`.
3.5 Records: complete the destruction record from the dispatch rows (counts only, no payloads); amend
Article 30 PA-13 §(e), PA-21 §(f), PA-22 §(f) in-cell (superseded markers, dated from the Hetzner
delete time); `compliance-posture.md` row; ADR-142 addendum status -> landed (+ pointers in ADR-100 /
ADR-199 only if their text now misleads); `model.c4` `inngestRedis` description and the
`github -> hetzner` / `hetzner -> betterstack` edges, then `bash scripts/regenerate-c4-model.sh` and the
c4 tests incl. `plugins/soleur/test/c4-count-parity.test.sh`; `knowledge-base/operations/expenses.md`
(volume retired).
3.6 Ship PR B (`Ref #8285`). After merge: `gh issue close 8285` and `gh issue close 6894` with the PR
link, the dispatch run URLs and the Hetzner 404 read-back. The sweeper cannot close #8285 (the probe is
notify-only), so the explicit close is the last step.

## Alternative Approaches Considered

| Option | Why not (or when) |
|---|---|
| Host replace carrying a re-templated cloud-init (the 2026-09-23 comment's reading) | Replaces the sole scheduler for a value that can be pinned; forces the #8620 root-disk decision on an unrelated change. |
| On-host wipe FSM state in `inngest-luks-cutover.sh` + image release + pin bump + replace | Same host as the live LUKS volume (device mis-resolution can reach it); needs a replace and an image release on a 14-day clock; the script ships in the permanent image. CTO advisory rejected it. |
| `lifecycle.ignore_changes = [user_data]` on the server | Breaks the deliberate replace-to-reprovision design (ADR-100) for every future cloud-init change. |
| Terraform `-destroy -target` with declarations kept | Destroy mode expands to dependents; only safe after D1, and leaves a declared-but-absent window. Orphan `-target` apply is the same effect without the flag. |
| Bespoke API-delete + `state rm` workflows (web-1 shape) | Two new privileged workflows and suites for effects Terraform performs under an existing gate. |
| Delete without zeroing | Kept as D4 fallback only, CLO-attested as weaker evidence. |
| Mount the volume read-write on a web host to zero it | Touches prod web hosts; rejected. |

## User-Brand Impact

- **If this lands broken, the user experiences:** every armed reminder and scheduled run on the dedicated Inngest host silently stops (a `destroy` that hits the live encrypted volume 106903269, or a host replace caused by a template change), so reminders a user set never fire.
- **If this leaks, the user's data is exposed via:** a residual plaintext copy of the Redis AOF (in-flight prompts, agent output, armed reminders as of 2026-09-20) surviving on a detached-but-undeleted volume, an un-overwritten volume released to Hetzner's pool, or evidence rows that carry payloads instead of counts.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** one wrong physical-volume destroy loses every user's armed reminders and one residual plaintext copy leaks prompts, so a single run can hurt a single named user; `aggregate pattern` would under-weight that. CPO advisory (2026-10-08): sign-off yes, conditioned on a live-store health precondition and an explicit-id gate, both carried above.

## Observability

Layer numbers follow `plugins/soleur/agents/engineering/review/observability-coverage-reviewer.md`:
layer 3 is the asynchronous host-journald-to-Better-Stack path, layer 6 is the synchronous
workflow-run log. Layer 7 (self-hosted CLI consumer) is not applicable: nothing here executes on a
customer's machine.

```yaml
liveness_signal:
  what: (a) per-run SOLEUR_INNGEST_BACKSTOP_WIPE evidence row from the wipe host, posted straight to the Better Stack ingest endpoint and read synchronously by the workflow's own poll (layer 6); (b) SOLEUR_INNGEST_SERVER_PROBE hourly row from host_role=dedicated, data_mount_devid pins the live LUKS volume (layer 3); (c) logtail_exploration_alert.inngest_luks_wrong_volume, paused=false (layer 3)
  cadence: hourly (probe); once per wipe dispatch (evidence row)
  alert_target: Better Stack incident email (wrong-volume alert); dispatch job failure and the #8285 progress comment on the retire workflow run (layer 6)
  configured_in: apps/web-platform/infra/betterstack-logs-alerts.tf (alert); apps/web-platform/infra/cloud-init-inngest-backstop-wipe.yml (evidence row, created in PR A)
error_reporting:
  destination: the retire workflow run log and job summary (non-secret fields only; layer 6); Better Stack Logs source 2457081 for the wipe row (the row is read by the poll in the same run, so it is not a separate async hop)
  fail_loud: wipe host emits result=refused with the failed guard; the dispatch fails when no row carrying this run's nonce appears within the poll's wall-clock deadline or when result is not wiped; every phase comments its run URL and read-back on #8285
failure_modes:
  - mode: wipe host never boots or never posts (stock, cloud-init error, egress)
    layer: 6
    detection: bounded Better Stack poll in the wipe phase times out and fails the job; teardown step still runs
    alert_route: failed workflow run plus the #8285 comment (a pending environment approval is not a failure, so each progress comment restates days remaining to 2026-10-22)
  - mode: target device is not the expected ext4 volume (wrong id, already zeroed, LUKS)
    layer: 6
    detection: script guards emit result=refused before any write; the poll stops at once and names the guard
    alert_route: same poll; job fails loud
  - mode: live store leaves the LUKS volume during the window
    layer: 3
    detection: wrong-volume alert (probe row off 106903269) and the live-store gate of detach, wipe and destroy
    alert_route: Better Stack incident email
  - mode: plan shows any action on hcloud_server.inngest or the LUKS pair
    layer: 6
    detection: gate lib named-live counters abort the phase before apply
    alert_route: failed workflow run
  - mode: the wiped row cannot be delivered after the device was zeroed (ingest outage, token failure)
    layer: 6
    detection: the poll times out with no wiped row although the device is zero; the started row, if delivered, shows the host got that far
    alert_route: failed workflow run; runbook triage table says to query Better Stack for a late wiped row, then re-dispatch wipe (an already-blank device takes the prior=blank path and re-emits evidence)
  - mode: the started row cannot be delivered
    layer: 6
    detection: the script exits before any write ("NO EVIDENCE CHANNEL") and no row exists; the poll times out
    alert_route: failed workflow run; nothing was written, so the volume is intact; teardown then re-dispatch wipe
  - mode: teardown leaks the wipe host (job dies between steps, or the host is absent from Terraform state)
    layer: 6
    detection: the read-back step lists the labelled servers in Hetzner and fails when one remains; the convergence read of the next phase refuses until it is gone
    alert_route: failed workflow run and the #8285 comment; recovery in runbook 5b (phase=teardown, or delete the labelled server by id when it is absent from state)
  - mode: evidence forged or replayed (shared ingest token)
    layer: 6
    detection: stale or replayed rows fail the nonce, size and time bindings; a forged row is corroborated against Hetzner's action history for the volume before destroy
    alert_route: destroy refuses in the run log; the destruction record states the residual limit
logs:
  where: Better Stack Logs (SOLEUR_INNGEST_BACKSTOP_WIPE, SOLEUR_INNGEST_SERVER_PROBE); GitHub Actions run logs
  retention: Better Stack retention is finite, so the evidence row values are copied into the destruction record in PR B
discoverability_test:
  command: bash apps/web-platform/infra/inngest-backstop-wipe.test.sh && bash tests/scripts/test-inngest-backstop-retire-gate.sh
  expected_output: "passed, 0 failed"
```

The discoverability test is the credential-free fixture pair for PR A, because merging PR A mutates nothing in production (no waiver of `credentials_required` is adopted; the corpus baseline in `preflight-discoverability-test.test.ts` is unchanged). The production read-backs are not a preflight probe: each dispatch phase reads Hetzner itself and comments the result on the tracker, and the volume-absence read-back (a `GET /v1/volumes/106261946` returning 404 with the read-only token) is the exit criterion of phase 2.4 and is recorded in the destruction record in PR B. Before the destroy phase that same request returns 200, so it cannot be this plan's merge-time probe.

**Why `expected_output` is "passed, 0 failed".** The bare substring "0 failed" also matches "10 failed" and "20 failed", so a red suite would satisfy it. Both suites print a summary containing `passed, N failed` (the wipe suite `N passed, N failed, N executed`, the gate suite `N passed, N failed`); "passed, 0 failed" cannot match "passed, 10 failed".

**How the pair is intended to run.** The wipe suite runs longer than preflight Check 10's 15-second wall-clock cap (`timeout 15s` in the preflight skill), so inside the Check 10 sandbox it reports a timeout, not a pass. Its authoritative run is CI (`infra-validation.yml` runs every `apps/web-platform/infra/*.test.sh` by glob; the gate suite is the `tests/scripts/inngest-backstop-retire-gate` line in `scripts/test-all.sh`) and the local run at ship time; the plan's evidence for PR A is those results, not the sandboxed probe. If Check 10 is to pass in the sandbox, the command needs a fast subset or a declared waiver; neither is adopted here (open question for the ship step).

**Operator signal while a dispatch awaits approval.** The progress comment on #8285 is written by the run itself, so a dispatch waiting for the reviewer produces nothing. The only unprompted signal in that interval is the daily comment of `scripts/followthroughs/inngest-luks-property-8296.sh`, which should carry a "days to expiry" line (task 0.7 in `tasks.md`); that script is deleted in PR B step 3.4, which is gated on the dead-probe heartbeat feeder #9703 being armed.

## Encryption Posture

```yaml
at_rest:
  - store: hcloud_volume.inngest_redis
    mechanism: plaintext-exception
    evidence: apps/web-platform/infra/inngest-host.tf, resource "hcloud_volume" "inngest_redis" (declaration removed in PR A, object retired by the destroy phase); live device ext4 since 2026-07-07
    defends_against: nothing at the volume layer
    does_not_defend: a seized, RMA'd or snapshot-imaged disk exposes a full second copy of the Inngest queue and run-state AOF as of the 2026-09-20 freeze, and no erasure path reaches those bytes until the wipe phase overwrites them
    disclosed_as: not-publicly-claimed
    live_verification: available (Hetzner GET /v1/volumes/106261946 returns 404 after the destroy phase)
  - store: hcloud_volume.inngest_redis_luks
    mechanism: luks
    evidence: unchanged - apps/web-platform/infra/inngest-redis-luks.tf; this plan never plans an action on it (gate named-live counter)
    defends_against: a seized, RMA'd or snapshot-imaged Hetzner block volume
    does_not_defend: a leaked credential, an app-layer read on the unlocked host, and (until #8620) a seized root disk that caches the passphrase at /etc/default/inngest-luks
    disclosed_as: not-publicly-claimed
    live_verification: unavailable:the probe proves which device backs /mnt/data, not crypto_LUKS (existing ledger text, unchanged)
in_transit:
  - connection: throwaway wipe host -> Better Stack ingest endpoint (evidence row)
    enforced_at: apps/web-platform/infra/cloud-init-inngest-backstop-wipe.yml (curl -fsS https, created in PR A)
    tls: HTTPS, TLS 1.2+
    cert_verification: on
    does_not_defend: a compromised wipe host or a leaked ingest token (write-only, lifetime minutes)
    disclosed_as: not-publicly-claimed
exception:
  justification: the plaintext backstop is retained only until the three gated phases complete; the existing ledger exception stands unchanged until the Hetzner API shows the volume gone
  tracking_issue: "#8285"
  reevaluate_when: the destroy phase's read-back returns 404, at which point PR B removes the ledger row
  expires_on: 2026-10-22
```

## Architecture Decision (ADR/C4)

### ADR
Amend **ADR-142** (`knowledge-base/engineering/architecture/decisions/ADR-142-inngest-redis-aof-zero-data-loss-luks-migration.md`)
by appending an addendum (never editing prior text): the backstop is retired, `op=luks-rollback` ends
at the detach phase and the live LUKS volume becomes the only copy (loss of `INNGEST_REDIS_LUKS_KEY`
in Doppler `soleur-inngest/prd` is then total, counsel review 2026-09 O4); erasure was performed by a
throwaway wipe host rather than the host FSM, with Alternatives Considered rows for the on-host FSM
and the host replace. Authored in PR A with status "adopting", flipped to landed in PR B. Ordinal
n/a (amendment, not a new ADR).

### C4 views
Read all three model files (`model.c4`, `views.c4`, `spec.c4`). Checked and already modeled: the
operator/founder actor, Hetzner (`platform.infra.hetzner`), GitHub Actions (`github`), Doppler, Better
Stack (`betterstack`), the `inngestRedis` container, edges `github -> hetzner` (L~690, already
narrates the web-1 write-through) and `hetzner -> betterstack`. No new element or relationship: the
throwaway host is a transient `hetzner` activity and its evidence row rides the existing
`hetzner -> betterstack` shipping edge. Edits: `inngestRedis` description (drop "RETAINED PLAINTEXT
BACKSTOP", record retirement and the rollback removal), one clause on the `github -> hetzner` edge
(retire dispatch destroys the volume and creates/destroys a transient wipe host), then
`scripts/regenerate-c4-model.sh`; run `apps/web-platform/test/c4-code-syntax.test.ts`,
`c4-render.test.ts` and `plugins/soleur/test/c4-count-parity.test.sh` (the edit moves no counted
cardinality; the run proves it).

### Sequencing
The ADR addendum and the model text describe the post-retire state, so they are written in PR A as
"adopting" and the C4 description change lands in PR B, when it becomes true.

## Guard Contract

### Guard 1 — render-identity pin (the host is never replaced by this change)

**Property.** After the volume resource is removed, `hcloud_server.inngest` plans no change and
nothing in the root derives from `hcloud_volume.inngest_redis`.

**Assembly.** Every expression that feeds `hcloud_server.inngest` arguments: the `templatefile` map
passed to `cloud-init-inngest.yml` (the `inngest_volume_id` key), `local.inngest_user_data_plain`,
`local.inngest_user_data_b64gz`, the server's labels, and any other `.tf` file in
`apps/web-platform/infra/` that names `hcloud_volume.inngest_redis` or `hcloud_volume_attachment.inngest_redis`
outside comments. The chokepoint is the plan JSON `resource_changes[]` for `hcloud_server.inngest`,
asserted by the retire gate's named-live counter in every phase, plus a static scan in
`inngest-host.test.sh` over all `*.tf`. The offline render in `inngest-userdata-budget.sh` is a MODEL
of the real payload and stubs the volume id (`100000004`) and every secret, so it can prove cap
headroom but not identity; the identity claim therefore rests on the real plan JSON of the `detach`
phase (live state, real ids), and the stubbed inputs are listed here so nobody reads the budget
script's green as an identity proof.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Change one digit of the pinned literal in the local | RED (rendered `PLAIN_ID` differs from the live id; the gate sees a server action or the static test sees a literal that is not 106261946) |
| 2 | Replace the literal with a non-numeric sentinel such as `retired-8285` | RED (cloud-init numeric assertion and the static scan) |
| 3 | Re-introduce `hcloud_volume.inngest_redis.id` in the template map | RED (static scan finds a resource reference; plan graph shows the server as a dependent) |
| 4 | Add a second reference to the volume in a server label after the pin is compliant | RED (scan quantifies over all `*.tf`, not just the template map) |
| 5 | Make the gate's named-live counter for `hcloud_server.inngest` accept `update` | RED (gate test row) |

**Harness rows.** One edit to the suite itself: delete the static-scan loop's file glob so it checks
zero files; the suite must report a floor failure (a "0 checked" exit 0 is vacuous). One must-PASS
input that is not the canonical: a `.tf` that mentions the volume only inside a comment.

**Anchor.** The pinned literal is compared to the physical id by the destroy phase's `expected_inngest_volume_id`
input and `before.id`, both of which come from the dispatching session and the live Hetzner API, not
from the same diff as the literal.

### Guard 2 — retire gate (exact plan shape per phase)

**Property.** Each phase applies exactly its authorized set of changes against exactly volume
106261946, and nothing else.

**Assembly.** `inngest_backstop_retire_gate` in `tests/scripts/lib/inngest-backstop-retire-gate.sh`,
sourced by the workflow's plan step and by `test-inngest-backstop-retire-gate.sh`; it quantifies over
EVERY element of `.resource_changes[]` (an address nobody enumerated aborts as out_of_scope), per
phase: detach = one delete of the attachment; wipe step A = two creates, wipe step B / teardown = a
subset of deletes of exactly the two wipe addresses; destroy = one delete of the volume. Named-live with zero actions: `hcloud_server.inngest`,
`hcloud_volume.inngest_redis_luks`, `hcloud_volume_attachment.inngest_redis_luks`, the LUKS key
resources, and the web-1 volume. Id pin: `.change.before.id` (volume) / `.change.before.volume_id`
(attachment) equals the input; an empty pin is its own counter.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Plan JSON adds a delete of `hcloud_volume.inngest_redis_luks` during destroy | RED |
| 2 | Run the gate with `phase` unset or unknown | RED (dispatch of the gate itself: an unrecognized phase must abort, never default to a permissive set) |
| 3 | Plan has the authorized volume delete plus a second delete of the attachment, after a compliant first | RED (checks every member, not the first) |
| 4 | `expected_inngest_volume_id` omitted on a genuine destroy | RED (id_pin_absent counter) |
| 5 | State maps the address to a different physical id than the pin | RED |
| 6 | Plan adds an `update` to `hcloud_server.inngest` | RED |
| 7 | Wipe step A plan has the attachment's `after.volume_id` equal to 106903269 | RED |
| 8 | Teardown plan with only the server delete (the attachment never created) | PASS (subset rule); with an extra unrelated delete, RED |
| 9 | The untargeted plan omits the `hcloud_server.inngest` entry entirely | RED (the entry must be present as a no-op) |

**Harness rows.** Suite edit: replace the sourced lib with an always-pass stub; the suite must fail on
its own must-RED rows. Must-PASS non-canonical input: a plan JSON with the authorized change plus
unrelated `no-op` entries in a different order and extra read-only data entries.

**Anchor.** The gate cannot weaken itself in one diff: the workflow step and the test both source the
same lib, and the mutation rows are asserted by the test; an independent reviewer-gated environment
(non-empty reviewer set, read from the GitHub API at run time) authorizes the apply.

### Guard 3 — wipe script refusal guard (device identity)

**Property.** `blkdiscard -z` runs only on the whole block device that is volume 106261946, in the
ext4 state it was left in, and a pass is claimed only when a full read-back is all zero.

**Assembly.** Every code path in `cloud-init-inngest-backstop-wipe.yml` that can reach `blkdiscard`,
`dd`, `wipefs`, `shred` or any write to a block device: exactly one call site, behind the guard
function. The guards: by-id path equals the pinned id; `lsblk` shows it as `disk` of the expected
byte size; `blkid -p` TYPE is `ext4`; unmounted; no sysfs holders/slaves; no other attached volume.
The read-back is decided by `cmp`'s rc together with `dd`'s rc.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Fixture device reports TYPE `crypto_LUKS` | RED (refused, no write) |
| 2 | Fixture device size differs by one byte | RED (refused) |
| 3 | Fixture device is mounted or has a holder | RED (refused) |
| 4 | Fixture has the pinned device plus a second attached volume (second member after a compliant first) | RED (refused) |
| 5 | Read-back fixture has a single non-zero byte in the last block | RED (result not wiped) |
| 6 | Move the `blkdiscard` call above the guard function | RED (a refusal fixture shows a write happened) |
| 7 | Add a second `blkdiscard` call site | RED (call-site census pinned at exactly 1) |

**Harness rows.** Suite edit: make the fixture seam path point at an empty directory; the suite must
report a floor failure instead of passing. Must-PASS non-canonical input: a sparse loop-image of a
different (valid) size supplied through the size variable with matching expected size.

**Anchor.** The script posts its own evidence, so this guard proves consistency, not integrity. What
sits OUTSIDE the script's diff: the destroy gate re-reads Hetzner for the volume's id and size, binds the
row to the wipe dispatch's run id (the nonce, set by the workflow, not the script) and its timestamp, and
requires the 2.0 live-store gate; the destruction record words the claim as self-attested logical erasure.

### Guard 4 — evidence-before-destroy ordering

**Property.** The volume is never destroyed unless a wipe evidence row for that exact volume id says
zero read-back succeeded after the detach, and the live store is healthy.

**Assembly.** The destroy phase's precondition step is the single chokepoint; the evidence query,
the nonce binding, the live-volume attachment check and the probe freshness/identity check all run inside
it (and the 2.0 half runs in front of every phase), before `terraform plan` is invoked. A wipe row from an earlier run of a different
volume id does not count.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Evidence row absent | RED (destroy refuses) |
| 2 | Evidence row has `result=refused` or `readback=nonzero` | RED |
| 3 | Evidence row exists for a different volume id | RED |
| 4 | Newest probe row older than 3 h or off 106903269 | RED |
| 5 | Reorder: run the precondition after the apply step | RED (an ordering row: the stub records the apply as already invoked when the precondition fails) |
| 6 | Evidence row has a different nonce than `wipe_run_id`, or a timestamp earlier than the detach run | RED |
| 7 | `INNGEST_LUKS_CUTOVER` reads `rollback` while `detach` or `wipe` is dispatched | RED (the 2.0 chokepoint guards those phases too, not only `destroy`) |

**Harness rows.** Suite edit: stub the Better Stack query to always answer success; the must-RED rows
1-3 must then fail the suite. Must-PASS non-canonical input: evidence row fields in a different key
order with extra fields.

**Anchor.** The nonce is the wipe dispatch's GitHub run id, which the destroy dispatch takes as an input
from the dispatching session; the evidence values live in the Better Stack row and later in the
destruction record (PR B), two stores a single diff to the workflow cannot rewrite.

## Infrastructure (IaC)

### Terraform changes
`inngest-host.tf` (pin, removals), new `inngest-backstop-wipe.tf` (provider `hetznercloud/hcloud`,
already pinned in the root; no new provider), variable `inngest_backstop_wipe_enabled` (default false) and a numeric
`inngest_backstop_volume_id` (non-secret, default 106261946) in `variables.tf`; the ingest token reuses the
existing `var.betterstack_logs_token`. Both new variables carry defaults, so the merge-triggered apply
cannot fail on a missing `TF_VAR_*`. New resources are
`hcloud_server` and `hcloud_volume_attachment`, both in the ledger's `non_store_types`, so no new
ledger row; the parity test lists them in the operator-applied exclusions (they are touched only by
the retire dispatch).

### Apply path
**Does merging PR A alone mutate production? No.** `apply-web-platform-infra.yml` fires on any
`apps/web-platform/infra/**` push, but its per-merge `apply` job is an explicit `-target` allow-list
with no `hcloud_server.*` and neither retired address (`OPERATOR_APPLIED_EXCLUSIONS` in the parity
test), the wipe resources are `count = 0` and untargeted, and the new variables have defaults. The PR
body's first line says so. Every workflow that can apply the changed resources, enumerated:
`apply-web-platform-infra.yml` (push `apply`: does not reach them; dispatch jobs `inngest_host`,
`inngest_host_replace`: edited to drop the two addresses; the new `inngest_backstop_retire`: the only
route), `apply-deploy-pipeline-fix.yml` (paths are web-host webhook scripts and units; it names no
`inngest-host.tf`, `variables.tf` or wipe file, verified by reading its `paths:` list),
`scheduled-terraform-drift.yml` (plan-only, files a drift issue), `infra-validation.yml` (validate and
static gates). Re-run this enumeration at ship time against the final file list.

Not a host replace and not cloud-init-only. Targeted applies from the reviewer-gated dispatch
`apply_target=inngest-backstop-retire`: no downtime on the scheduler; blast radius is the three
named addresses per phase. PR A's merge applies nothing to them.

### Distinctness / drift safeguards
Between PR A's merge and the `destroy` phase the two removed addresses are orphans in state, so
`scheduled-terraform-drift.yml` (full-root plan, plan-only) will report two deletes; this is expected,
tracked by the run, and clears when the phases finish. Nothing auto-applies: the per-merge apply is
`-target`-scoped and excludes them, and the dispatch gates reject any delete outside a phase's set.
Do not dispatch `inngest-host`, `inngest-host-replace` or any host rebirth in the window.

### Vendor-tier reality check
Hetzner: the wipe host and the volume must share hel1; verify stock for the chosen type before the
`wipe` phase (a failed create before the wipe leaves the volume detached and intact, which is safe and
retryable). No Better Stack tier constraint: it is an ingest POST.

## Files to Edit

PR A:
- `apps/web-platform/infra/inngest-host.tf` (D1 pin, resource removals, stale comments)
- `apps/web-platform/infra/inngest-redis-luks.tf` (comments that cite the source volume)
- `apps/web-platform/infra/variables.tf` (wipe variables)
- `.github/workflows/apply-web-platform-infra.yml` (convert recut job, drop targets and jq selects, `phase` input)
- `tests/scripts/lib/inngest-host-shape-gate.sh`, `tests/scripts/lib/inngest-host-replace-gate.sh` (allow-sets)
- `plugins/soleur/test/terraform-target-parity.test.ts`
- `apps/web-platform/infra/inngest-host.test.sh`, `apps/web-platform/infra/inngest-userdata-budget.sh` (only if the stub or counts move)
- `scripts/test-all.sh`, `scripts/suite-shard-legs.tsv`, `scripts/suite-durations.tsv` (register new suites; remove the deleted recut suite)
- `plugins/soleur/test/stock-preflight-coverage.test.ts`, `plugins/soleur/test/web-host-escrow-preflight-census.test.ts` (both name `inngest_volume_recut`)
- `knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-job-rationale.md`, `knowledge-base/engineering/operations/runbooks/infra-credential-tiers-8209.md`, `knowledge-base/engineering/operations/runbooks/inngest-server.md` (cross-references to the deleted dispatch)
- `apps/web-platform/infra/inngest-arm-write-token.tf` (comments enumerating the recut job)
- `knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md` (retire section, §5a banner)
- `knowledge-base/engineering/architecture/decisions/ADR-142-inngest-redis-aof-zero-data-loss-luks-migration.md` (addendum)
- `knowledge-base/product/roadmap.md` (row)

PR B:
- `.github/workflows/apply-web-platform-infra.yml`, `.github/workflows/cutover-inngest.yml`, `scripts/cutover-inngest.sh`, `apps/web-platform/infra/cutover-inngest-workflow.test.sh`, `scripts/guard-vacuity-floor.test.sh`
- `scripts/encryption-posture-ledger.json`, `scripts/test-all.sh`
- `apps/web-platform/infra/betterstack-logs-alerts.tf`, `apps/web-platform/infra/uptime-alerts.tf`, `apps/web-platform/infra/inngest-redis-luks.tf`, `apps/web-platform/infra/variables.tf`
- `scripts/followthroughs/inngest-luks-cutover-6894.sh`
- `knowledge-base/engineering/architecture/diagrams/model.c4`, `model.likec4.json` (regenerated), ADR-142 (status), `knowledge-base/legal/article-30-register.md`, `knowledge-base/legal/compliance-posture.md`, `knowledge-base/operations/expenses.md`, the runbook, `knowledge-base/legal/audits/inngest-aof-backstop-destruction-record.md`
- Deleted: `scripts/followthroughs/inngest-luks-property-8296.sh`, `scripts/followthroughs/inngest-luks-property-8296.test.sh`

## Files to Create

PR A:
- `apps/web-platform/infra/inngest-backstop-wipe.tf`, `apps/web-platform/infra/cloud-init-inngest-backstop-wipe.yml`, `apps/web-platform/infra/inngest-backstop-wipe.test.sh`
- `tests/scripts/lib/inngest-backstop-retire-gate.sh`, `tests/scripts/test-inngest-backstop-retire-gate.sh`
- `knowledge-base/legal/audits/inngest-aof-backstop-destruction-record.md` (template)
- Deleted: `tests/scripts/lib/inngest-volume-recut-gate.sh`, `tests/scripts/test-inngest-volume-recut-gate.sh`

PR B deletes the wipe `.tf`, template, test, retire gate lib and test (point-in-time apparatus; the procedure as run stays in git history).

## Open Code-Review Overlap

2 open scope-outs touch `scripts/test-all.sh`: #8659 (test-helpers composed EXIT trap leak) and #7942 (two `*.mutation.sh` batteries run in no gate). Acknowledge both: different concerns, no fold-in; they remain open. No other planned file matches an open code-review issue. Draft PR #8626 overlaps `scripts/encryption-posture-ledger.json` and `scripts/lint-encryption-posture.py`: acknowledge, rebase PR B onto main, do not depend on it.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Retire the plaintext Redis AOF backstop volume `hcloud_volume.inngest_redis` per #8285 (also tracks #6894)." | Overview, Phases 1-3 | mapped |
| 2 | "(1) read data_mount_devid on the newest host_role=dedicated SOLEUR_INNGEST_SERVER_PROBE row and confirm it equals the inngest_redis_luks volume's by-id alias" | Phase 0.1, Guard 4 precondition | mapped |
| 3 | "(2) confirm the wrong-volume alert is armed and has not fired since the cutover; check the notify-only probe" | Phase 0.1, Guard 4 precondition | mapped |
| 4 | "zero + read-back + detach + Hetzner API delete + Terraform state forget" | D2 wipe phase, D3 detach/destroy phases (state converges in the destroy apply) | mapped (divergence recorded) |
| 5 | "remove `hcloud_volume_attachment.inngest_redis` then `hcloud_volume.inngest_redis`, run the `[ack-destroy]` procedure" | Phase 1.1 (declarations), D3 dispatch replaces the ack route | mapped (premise superseded, Research Reconciliation row 1) |
| 6 | "delete the probe script + test + run_suite line in scripts/test-all.sh" | Phase 3.4 | mapped |
| 7 | "remove the ledger row only after the Hetzner API shows the volume gone" | Phase 3.3, property P3 | mapped |
| 8 | "Do NOT close #8285 before the volume is destroyed." | Phase 3.6, `Ref` only | mapped |
| 9 | "Plan it as a host replace or find a way to decouple the template input (e.g. drop the PLAIN_ID use) so the destroy does NOT replace the server" | D1, Guard 1 | mapped |
| 10 | "every destructive prod write (zero/detach/API delete/state forget/apply) needs a per-command go-ahead from the operator naming the exact command" | Phase 2 | mapped |
| 11 | "note the overlap but do not depend on it" (PR #8626) | Open Code-Review Overlap | mapped |
| 12 | "OUT OF SCOPE ... web-2's hcloud_volume.workspaces, hcloud_volume.git_data and any git-data files. NEVER touch web-1's LUKS /workspaces volume 106443278" | Guard 2 named-live list; no such file in Files lists | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| D1 literal pin | "find a way to decouple the template input" | asked |
| D2 throwaway wipe host | "zero + read-back + detach" (asks 4) | asked (mechanism chosen because the host has no channel; user-challenge filed) |
| D3 retire dispatch + gate lib | "run the `[ack-destroy]` procedure" and "per-command go-ahead" (asks 5, 10) | asked (replaces an unreachable route) |
| D4 fallback | "expires 2026-10-22 (pinned expires_on_not_extended)" | inferred - justification: a hard non-extendable expiry needs a defined fallback or the plan silently depends on the zero step landing |
| Destruction record template | "Self-pull evidence" / zero + read-back (asks 4) | inferred - justification: CLO advisory; the superseded template says this destroy needs its own Art. 5(2) record made at the time |
| Roadmap row, compliance-posture row | none | inferred - justification: CPO sign-off conditions (wg-every-feature-listed-in-a-roadmap-phase) |
| Retire `op=luks-rollback` | "retire the backstop" (asks 1) | inferred - justification: the op's target no longer exists after the detach phase; leaving it live invites a dispatch that fails mid-flight |
| Guard 1-4 and their suites | "every destructive prod write ... needs a per-command go-ahead" | inferred - justification: the deliverable includes destructive gates; plan Phase 2.12 requires a guard contract |
| Follow-up #9786 | "drop the PLAIN_ID use" | asked (deferral tracked) |

### Split Assessment

- Subsystems touched: 6 - `apps/web-platform`, `.github`, `scripts`, `tests`, `plugins`, `knowledge-base`
- Planned files: ~45 | Estimated changed lines: ~1,900
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: split - PR A (decouple, apparatus, gates, records template; no production effect on merge) and PR B (convergence after the Hetzner read-back), the same boundary the web-1 wipe used.

## Acceptance Criteria

### Pre-merge (PR A)
- [ ] The pre-merge read-only plan (infra-validation) shows `hcloud_server.inngest` as a no-op and the two orphan addresses as the only deletes; `terraform validate` passes with the two resource blocks removed; no `.tf` file outside comments names `hcloud_volume.inngest_redis` or `hcloud_volume_attachment.inngest_redis` (`git grep` census in `inngest-host.test.sh`).
- [ ] The rendered `local.inngest_user_data_plain` for the pinned literal is byte-identical to the render with the real id (shown by the budget script's render and by the `detach` phase plan in Phase 2.1; the gate aborts on any `hcloud_server.inngest` action).
- [ ] `tests/scripts/test-inngest-backstop-retire-gate.sh` passes with every Guard 2 matrix row and its harness rows; `inngest-backstop-wipe.test.sh` passes with every Guard 3 row (call-site census exactly 1); the Guard 1 and Guard 4 rows are asserted in their suites.
- [ ] `plugins/soleur/test/terraform-target-parity.test.ts`, `bash plugins/soleur/test/c4-count-parity.test.sh`, `python3 scripts/lint-encryption-posture.py`, `python3 scripts/lint-guard-contract.py <this plan>` are green.
- [ ] `op=luks-rollback` stays listed until PR B; Phase 0.4 recorded that the on-host path refuses with the plaintext device absent (or the op was retired in PR A instead); the runbook banner says rollback ends at the detach phase.
- [ ] Destruction-record template is committed with every measured field `PENDING-EVIDENCE`; no closing keyword anywhere (`Ref #8285`, `Ref #6894`).
- [ ] `knowledge-base/project/specs/feat-one-shot-8285-retire-inngest-plaintext-backstop/decision-challenges.md` carries the erasure-mechanism divergence as a user-challenge.

### Post-merge (phases, each with the exact command shown and a named go-ahead)
- [ ] `detach`: 2.0 live-store gate and untargeted plan passed (server present as no-op); plan was one attachment delete; Hetzner GET shows `server: null` for 106261946; a progress comment is on #8285.
- [ ] `wipe`: evidence row with the run's nonce, `result=wiped readback=zero sig_after=none`, volume_id 106261946 and the exact size; wipe host and its attachment gone (`GET /servers` has no wipe host).
- [ ] `destroy`: preconditions proven in the run log; one delete; `GET /v1/volumes/106261946` returns 404; server 169426216 `volumes == [106903269]`; a read-only untargeted plan lists neither address.
- [ ] A fresh probe row after destroy still reports `/dev/mapper/inngest-redis` on 106903269 with `redis_active`; wrong-volume alert quiet; before/after `redis_keys` recorded for the destruction record (informational).

### Pre-merge (PR B)
- [ ] Ledger row `hcloud_volume.inngest_redis` removed, LUKS row text corrected, lint green; probe, its test and the `run_suite` line deleted; wipe apparatus and retire job deleted with parity tests updated; `op=luks-rollback` retired with its suites.
- [ ] Destruction record completed from run output (counts only), Article 30 amendments in-cell, compliance-posture row, C4 regenerated and green, ADR-142 landed, CLO attestation recorded.
- [ ] After merge: `gh issue close 8285` and `gh issue close 6894` with the PR link, run URLs and the 404 read-back.

## Domain Review

**Domains relevant:** Engineering, Legal, Product (sign-off only)

### Engineering (CTO)
**Status:** reviewed
**Assessment:** D1 sound (prove with plan JSON; keep the literal numeric). On-host FSM wipe rejected: a replace and image release sit on a 14-day critical path and the wipe would run beside the live LUKS volume; use an ephemeral wipe host. `[ack-destroy]` cannot reach these addresses; use a dedicated dispatch modelled on the recut job with an id-pin and no ack bypass. Remove the recut job and gate branches naming the plaintext volume; check snapshots/backups (none); retire `luks-rollback` and runbook §5a; get CLO acceptance before any delete-without-zero.

### Legal (CLO)
**Status:** reviewed
**Assessment:** New Art. 5(2) destruction record, committed as a template before the destructive step and completed from run output (counts only). Amend Article 30 PA-13 §(e), PA-21 §(f), PA-22 §(f) in-cell after the API shows the volume gone. Delete-without-zero is defensible only as a CLO-attested downgrade worded "provider delete only"; it beats an expired exception. Public disclosures make no backstop or Inngest-encryption claim, so no edit and no lockstep gate. No breach-register row needed.

### Product/UX Gate
**Tier:** none (no user-facing UI surface; infrastructure change)
**Decision:** reviewed
**Agents invoked:** soleur:product:cpo
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

#### Findings
CPO sign-off: yes, with conditions (all carried above). Gate the destroy on a fresh live-store health check (reachability, key count not below the backstop baseline); the destroy must name volume 106261946 explicitly and fail closed if the id, name or LUKS flag points at the live volume, plus a "no live attachment" assertion; keep rollback available until the final dispatch is armed and retire it in the destroy PR; make no "securely deleted" claim beyond what the evidence row supports; add roadmap and compliance-posture rows.

## Test Scenarios

- Given the pinned literal, when `terraform plan` runs against live state, then `hcloud_server.inngest` shows no action and only the orphan addresses show deletes.
- Given the wipe host boots and the device is ext4 and unmounted, when the script runs, then the row says `result=wiped readback=zero`.
- Given the device reads `crypto_LUKS` or is mounted, when the script runs, then it emits `result=refused` and never writes.
- Given no evidence row, when `phase=destroy` is dispatched, then it fails before planning.
- Given the wipe job fails after creating the host, then the `if: always()` step deletes the host and attachment.
- Given PR B, when the lint runs with the ledger row gone and no `.tf` declaration, then the sweep passes and the positive-work floor holds.

## Risks and Sharp Edges

- **Mistargeted volume.** Mitigated by the id-pin against both the live Hetzner volume and `before.id`, the live-volume-attached precondition, and the wipe host never seeing the LUKS volume.
- **Orphan window.** From PR A's merge until the destroy phase the addresses are state-only; drift will report two deletes and the dispatch jobs must not be used for hosts. Keep the window to days.
- **Deadline.** 2026-10-22 is non-extendable; decision point 2026-10-17 for D4. Other sessions own the other 2026-10-22 exceptions.
- **Evidence retention.** Better Stack retention is finite; copy values into the destruction record in PR B.
- **Key single point.** After retirement `INNGEST_REDIS_LUKS_KEY` in Doppler `soleur-inngest/prd` is the sole opener of the only copy (counsel review 2026-09 O4); state it in the record and ADR addendum.
- **Race on state.** The backend has `use_lockfile = false`; the 2.0 gate refuses while a merge apply is in flight and the job joins the root's apply concurrency group, and the 404 read-back is a hard exit criterion that catches a clobbered write.
- **Untargeted apply in the orphan window.** Any untargeted apply of this root would destroy both orphans unwiped; no CI path performs one (verified: per-merge `-target` set, gated dispatch jobs, plan-only drift). The runbook says so.
- **After retirement there is no second copy** of the live store and `INNGEST_REDIS_LUKS_KEY` in Doppler is the sole opener; state it in the ADR addendum together with the AP-009 ("never delete user data") tension and why it holds (the live copy is evidenced and the destroy is gated on it).
- **#9786 trigger and a tautology.** The pinned dead id stays in `user_data` until #9786; after the destroy the static assertion that the literal equals 106261946 only pins a historical fact, so word the test that way. #9786's trigger is the next approved host replace or #8620 reaching its window.
- **Closing keywords.** A squash commit body with "close #8285" auto-closes the tracker (it already happened once on 2026-09-21). Use `Ref`.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This one is filled.
- Removal outside the `-target` set is a silent no-op; the retire job's own `-target` list is the only route to these addresses, so its list and the parity test are one change.
