---
title: "Art. 5(2) destruction record — Inngest plaintext Redis AOF backstop volume (hcloud_volume.inngest_redis, id 106261946)"
status: template
date: 2026-10-08
related: [8285, 6894, 8296]
related_adrs: [ADR-142, ADR-199, ADR-140]
supersedes_template_for_this_destroy: knowledge-base/legal/audits/inngest-aof-destruction-record.md
brand_survival_threshold: single-user incident
---

# Art. 5(2) destruction record — Inngest plaintext Redis AOF backstop volume

## What this file is

> **Completed 2026-10-09 (#8285 PR B):** every measured field below now carries its value from run output or a named API read, and the section "Completion — 2026-10-09 (#8285 PR B)" at the end states what the evidence does and does not show. The text of this section is the template as committed and is otherwise unchanged. The `status:` frontmatter flips only with the CLO attestation named in that section.

A **template**, not a record. It is committed with every measured field set to `PENDING-EVIDENCE`
before any destructive step runs, and it is completed from the dispatch run output in PR B of #8285
(counts and identifiers only, never payloads). Nothing in this file states that the volume has been
wiped, detached or destroyed: until the fields below are filled from run output, the retirement has
not happened.

It replaces `inngest-aof-destruction-record.md` for this destroy. That older template was written for
ADR-199's empty-store recut (it says STOP unless `redis_keys` is 0); the store took ADR-142's
additive route instead, so the volume being retired is a **non-empty** plaintext backstop, and the
destroy needs its own record made at the time.

Art. 5(2) makes the controller responsible for demonstrating compliance with Art. 5(1), including
storage limitation (e) and integrity and confidentiality (f). Retiring a volume that holds a
plaintext copy of in-flight job payloads is an Art. 5(1) act, and the only thing that can evidence it
afterwards is a record made at the time. Committing the template first is deliberate: drafted before
the act it is a precondition; drafted after it is a justification.

## Facts fixed at template time (2026-10-08)

These are the identity of the object and are not completed later. They come from the plan for #8285
and a read-only Hetzner API read on 2026-10-08; they are pinned by the dispatch's
`expected_inngest_volume_id` input and by the gate's comparison against `.change.before.id`.

| Field | Value |
|---|---|
| Object | `hcloud_volume.inngest_redis` (Hetzner name `soleur-inngest-redis-store`), ext4, plaintext |
| Hetzner volume id | 106261946 |
| Nominal size | 10 GB (exact byte size is a measured field below) |
| Location | hel1 |
| Created | 2026-07-07 |
| Role | Pre-cutover copy of the Inngest Redis append-only file, retained as the `op=luks-rollback` target since the additive LUKS cutover of 2026-09-20 (ADR-142) |
| Live store (must NOT be touched) | `hcloud_volume.inngest_redis_luks`, id 106903269, LUKS |
| Ledger exception expiry | 2026-10-22, pinned and not extendable |
| Tracking issue | #8285 (also #6894) |

## Measured fields (all `PENDING-EVIDENCE`)

Pull each from the named source. Do not assemble a field from memory or from a second moment than the
one named.

| Field | Value | Source |
|---|---|---|
| **Exact volume size (bytes)** | 10737418240 (the wipe evidence row's `size_bytes`; 10 GiB). The destroy gate required the row's size to match the Hetzner-side size and the destroy run passed that gate. Hetzner reports volume sizes in whole GB, so the byte figure is the row's; the volume itself can no longer be read (404). | Hetzner `GET /v1/volumes/106261946` before the `detach` phase, and the `size_bytes` of the wipe evidence row (the two must agree) |
| **Pre-state: snapshots of the volume** | 0, read 2026-10-09T19:05Z (record time). Hetzner Cloud has no volume-snapshot object, and the volume's 58 recorded actions contain only `attach_volume`, `detach_volume` and `delete_volume`. Not read separately at the `detach` phase. | Hetzner API read at the `detach` phase (expected 0; a non-zero count is a finding that the destroy does not erase) |
| **Pre-state: backups covering the volume** | 0, read 2026-10-09T19:05Z: no snapshot or backup image is bound to, or was created from, server 169426216. Not read separately at the `detach` phase. | Hetzner API read at the `detach` phase (expected 0) |
| **Live store before: `redis_keys` / `redis_active`** | `redis_keys=4124`, `redis_active=active`, `data_mount_src=/dev/mapper/inngest-redis`, `cutover_flag=done` (newest `host_role=dedicated` row before `detach` began, dt 2026-10-09 14:30:33Z). The next hourly row, dt 15:30:43Z (after `detach`), read `redis_keys=4426`, `redis_active=active`. | newest `host_role=dedicated` `SOLEUR_INNGEST_SERVER_PROBE` row before `detach`; informational only, counts legitimately move |
| **`detach` dispatch run id and URL** | https://github.com/jikig-ai/soleur/actions/runs/37950928039 (workflow_dispatch, `apply_target=inngest-backstop-retire phase=detach`) | GitHub Actions run of `apply_target=inngest-backstop-retire phase=detach` |
| **`detach` completion time (UTC)** | Hetzner `detach_volume` (server 169426216) finished 2026-10-09T15:27:18Z; run 15:19:57Z to 15:27:30Z; apply step 15:27:10Z to 15:27:22Z; conclusion success | that run's apply step |
| **`detach` read-back** | volume 106261946 `server: null` (recorded in the run's read-back step, 15:27:22Z to 15:27:23Z) | Hetzner `GET /v1/volumes/106261946` showing `server: null` |
| **`wipe` dispatch run id and URL** | https://github.com/jikig-ai/soleur/actions/runs/37955244979 (the run id is the evidence row's `nonce`) | GitHub Actions run of `phase=wipe`; the run id is the evidence row's `nonce` |
| **`wipe` start and end time (UTC)** | run 2026-10-09T15:54:55Z to 16:05:31Z (the approval wait precedes the job; job body 16:01:33Z to 16:05:30Z); apply (create) 16:02:41Z to 16:03:14Z; evidence poll 16:03:14Z to 16:04:51Z; teardown 16:04:51Z to 16:05:25Z | that run's steps |
| **Wipe evidence row: `result`** | `wiped` (nonce 37955244979) | Better Stack `SOLEUR_INNGEST_BACKSTOP_WIPE` row whose `nonce` equals the wipe run id (expected `wiped`) |
| **Wipe evidence row: `readback`, `sig_after`** | `readback=zero`, `sig_after=none` | same row (expected `zero`, `none`) |
| **Wipe evidence row: `volume_id`, `size_bytes`** | `volume_id=106261946`, `size_bytes=10737418240` (both equal the pinned id and the size above) | same row (must equal 106261946 and the size above) |
| **Wipe evidence row: `fs_uuid`, `last_write`** | `fs_uuid=a535548b-2c22-4b90-a522-1c1922bba674`, `last_write=2026-09-20T15:28:40Z` (the volume's last write is the 2026-09-20 cutover freeze, as expected for a retained backstop) | same row; non-payload identity captured before the zero |
| **Wipe evidence row: `prior`** | the field is absent from the row as received (the `wiped` row carries `result`, `nonce`, `volume_id`, `size_bytes`, `readback`, `sig_after`, `fs_uuid`, `last_write` only); the idempotent already-zero path was therefore not recorded as taken | same row (`blank` only if the idempotent already-zero path was taken) |
| **Throwaway wipe host: created and deleted** | server 169544191 (name `soleur-inngest-backstop-wipe`), created by the `wipe` apply (16:02:41Z to 16:03:14Z) and deleted by the same dispatch's teardown step (16:04:51Z to 16:05:25Z); no `phase=teardown` dispatch was needed. Hetzner `GET /v1/servers?label_selector=role%3Dinngest-backstop-wipe` returns no server (read 2026-10-09T19:05Z). | Hetzner `GET /servers` shows the wipe host absent after the `wipe` phase; `phase=teardown` run id if one was needed |
| **`destroy` dispatch run id and URL** | https://github.com/jikig-ai/soleur/actions/runs/37958051426 (`wipe_run_id=37955244979`) | GitHub Actions run of `phase=destroy`; its `wipe_run_id` input |
| **`destroy` apply completion time (UTC)** | Terraform apply step 2026-10-09T16:21:21Z to 16:21:25Z; Hetzner `delete_volume` started and finished 16:21:24Z; log line `Apply complete! 0 added, 0 changed, 1 destroyed` | that run's apply step |
| **First Hetzner 404 time (UTC)** | 2026-10-09T16:21:26Z (the destroy run's read-back line `GET /v1/volumes/106261946 -> 404 at 2026-10-09T16:21:26Z`); re-read 2026-10-09T19:05Z: 404 | self-pulled `GET /v1/volumes/106261946` returning 404 (a 404 carries no timestamp itself; record the time of the read) |
| **Post-state: server 169426216 attached volumes** | `[106903269]` (destroy run line `server volumes == [106903269]`; re-read 2026-10-09T19:05Z) | Hetzner API (expected `[106903269]`) |
| **Post-state: snapshots / backups** | 0 / 0 (read 2026-10-09T19:05Z; see the pre-state rows for what the figure covers) | Hetzner API (expected 0 / 0) |
| **Live store after: `redis_keys` / `redis_active`, `data_mount_devid`** | first `host_role=dedicated` probe row after the destroy, dt 2026-10-09 16:31:12Z: `redis_active=active`, `redis_keys=4356`, `data_mount_src=/dev/mapper/inngest-redis`, `data_mount_devid=scsi-0HC_Volume_106903269`, `cutover_flag=done`. A further row at 17:31:19Z reads the same device with `redis_keys=4509`. | first probe row after the destroy (expected `scsi-0HC_Volume_106903269`, `/dev/mapper/inngest-redis`) |
| **Wrong-volume alert state** | `logtail_exploration_alert` 2988582970 (`soleur-inngest-luks-wrong-volume-prd`) `paused=false`, read 2026-10-09T19:05Z via `GET telemetry.betterstack.com/api/v2/alerts/2988582970`; fresh probe rows present (16:31:12Z and 17:31:19Z) | `logtail_exploration_alert` 2988582970 `paused=false` plus a fresh probe row present |
| **Authorizing reviewer (each phase)** | `deruelle`, state `approved`, environment `inngest-cutover`, on each of the three runs. The dispatching actor was also `deruelle`, so the approval is a self-approval by one person; this is the variant `evidence-path`, to which the two-person rule of the provider-only variant does not apply. | the `inngest-cutover` environment approval record |
| **Variant used** | `evidence-path` (a wipe evidence row was present and corroborated; the provider-only variant D4 was not used) | one of: `evidence-path` (wipe evidence row present) or `provider-only` (see below) |

## What the evidence does and does not show

> Superseded 2026-10-09 (review round 1 of PR #9784): the sentence below that says the gate's binding
> "makes a stale or forged row fail" overstates it. Use the corrected paragraph in "Addendum -
> 2026-10-09" in the completed record, not this one.

State this paragraph in the completed record unchanged.

The wipe evidence is **self-attested guest-side logical erasure, not physical erasure**. The wipe host
zeroes the volume with `blkdiscard -z`, reads the whole device back with O_DIRECT and posts the result
to Better Stack itself. It proves the guest saw zeros through the Hetzner block interface at the time
of the read. It does not evidence anything about the provider's physical media, replicas or
sanitisation, and it is not independently attested: the destroy gate binds the row to the wipe run's id
(nonce), the Hetzner-side volume id and size, and the run timestamp, which makes a stale or forged
row fail, but the row's author is the wipe host. No claim of secure or physical deletion is made
beyond this.

## Variant: provider delete only (decision D4)

Applicable only if the `wipe` phase has not succeeded by **2026-10-17** and the operator and the CLO
choose, at that decision point, to proceed without zeroing. It is never selected silently. If used, the
completed record must say, in these words:

> Provider delete only: the volume was detached and deleted through the Hetzner API without an
> overwrite. Logical erasure is not evidenced by read-back. This is a downgrade from the
> evidence-path variant, attested by the CLO at `<clo_attestation_ref>` on `<date>`, and was chosen
> because an expired, non-extendable Art. 32 exception on 2026-10-22 is worse than the weaker
> evidence.

The `destroy` phase accepts either a `wipe_run_id` (evidence path) or `erasure=provider-only` with a
`clo_attestation_ref`; there is no third way past its precondition.

> Superseded 2026-10-09 (review round 1 of PR #9784): the attestation reference is not "any resolvable
> reference". See "Addendum - 2026-10-09", "Variant: the CLO attestation reference".

| Field (variant only) | Value |
|---|---|
| CLO attestation reference | not applicable: the provider-only variant was not used |
| Date of the decision | not applicable |
| Reason the wipe phase did not succeed | not applicable: the `wipe` phase succeeded on its first dispatch |

## Categories and basis

| Field | Value |
|---|---|
| **Categories of personal data on the object** | Plaintext copy of the Inngest Redis queue and run-state append-only file as of the 2026-09-20 freeze: in-flight user prompts, agent output and armed reminders. Counts only are recorded here; no payload is read, copied or posted at any stage. |
| **Lawful basis for the act** | Art. 5(1)(e) storage limitation and Art. 32 security of processing: the act removes the second, unencrypted copy that the additive cutover left in place |
| **Recoverability after the destroy** | NONE for the backstop. After retirement the live LUKS volume is the only copy of the store, and `INNGEST_REDIS_LUKS_KEY` in Doppler `soleur-inngest/prd` is its sole opener; losing that key is total loss (counsel review 2026-09, O4). The rollback to plaintext ends at the `detach` phase. |
| **Records amended in PR B, after the Hetzner 404** | Article 30 PA-13 §(e), PA-21 §(f), PA-22 §(f) (in-cell, dated from the Hetzner delete time); `compliance-posture.md`; ADR-142 addendum status |

## Completion checklist (for PR B)

- [ ] Every `PENDING-EVIDENCE` above is replaced with a value copied from run output or the named
      API read, not an estimate. Better Stack retention is finite, so the evidence row values are
      copied here.
- [ ] The wipe row's `nonce` equals the wipe run id and its `volume_id` and `size_bytes` match the
      Hetzner read.
- [ ] The first 404 time and the `destroy` apply time are both recorded.
- [ ] The "does and does not show" paragraph is retained, or the D4 variant wording is used with a
      resolvable CLO attestation reference.
      > Superseded 2026-10-09: use the corrected paragraph and the strict attestation rule in the
      > addendum; the extended checklist there governs `status: complete`.
- [ ] No payload, key material or token value appears anywhere in the record.
- [ ] `status:` in this file's frontmatter is changed from `template` to `complete` only in the PR
      that also carries the Hetzner 404 read-back.

## Addendum — 2026-10-09

Appended after review round 1 of PR #9784; the dated sections above are unchanged except for the
`Superseded` markers that point here. This file is still a **template**: nothing in it states that the
volume has been wiped, detached or destroyed, and every measured field remains `PENDING-EVIDENCE`
until it is filled from run output. Ref #8285, Ref #6894.

### Corrected paragraph: what the evidence does and does not show

State this paragraph, in place of the one above, in the completed record.

The wipe evidence is **logical, guest-side and self-attested**, not physical erasure. The wipe host
zeroes the volume with `blkdiscard -z`, reads the whole device back with O_DIRECT and posts the result
to Better Stack itself. It proves the guest saw zeros through the Hetzner block interface at the time
of the read. It does not evidence anything about the provider's physical media, replicas or
sanitisation. The destroy gate binds the row to the wipe run's id (nonce), the Hetzner-side volume id
and size, and the run timestamp, so a **stale or replayed** row fails. It does not make a forged row
fail: the row is posted with the ingest token that other hosts share, so a holder of that token could
write a row. What narrows that is Hetzner's own action history for the volume, which the destroy
precondition reads from the provider: a successful `attach_volume` to a server that is neither the
live Inngest host nor absent, finished not before the wipe run's start, followed by a successful
`detach_volume`. That corroborates that the volume really was attached to a wipe host; it does not
corroborate the zeroing. No claim of secure or physical deletion is made beyond this.

> Superseded 2026-10-09 (round 2): use the second corrected paragraph in "Addendum — 2026-10-09
> (review round 2)" below, which states what the Hetzner corroboration does and does not show.

### Variant: the CLO attestation reference

For `erasure=provider-only` the reference is exactly one URL shape, a comment on #8285:
`https://github.com/jikig-ai/soleur/issues/8285#issuecomment-<digits>`. The gate fetches it through
the GitHub API and requires the author to be an owner, member or collaborator of the repository and
the body to contain the volume id 106261946. A reference on any other host, or of any other shape, is
refused. The completed record cites the comment URL and the date.

> Superseded 2026-10-09 (round 2): the author set and the comment properties are narrowed. See
> "Variant: the CLO attestation, second revision" below.

### Additional measured fields (all `PENDING-EVIDENCE`)

| Field | Value | Source |
|---|---|---|
| **Hetzner action history for the volume** | `attach_volume` id 660462892361707, server 169544191 (the throwaway wipe host; not the live host 169426216, not null), success, finished 2026-10-09T16:03:10Z; later `detach_volume` id 660462892361820, server 169544191, success, finished 16:05:05Z; latest `attach_volume` to the live host 169426216: id 660282503645192, finished 2026-10-08T19:27:04Z (before the wipe run started, so the floor is the wipe run's own start, 15:54:55Z); the live host's `detach_volume` id 660454302424771 finished 15:27:18Z. Read 2026-10-09T19:05Z; the action list stays readable after the volume's deletion. | `GET /v1/volumes/106261946/actions` read before the `destroy` phase: the `attach_volume` action id, status and finish time with the server id it names (must not be 169426216 and not null), and the later `detach_volume` action id, status and finish time |
| **Evidence row emitter** | `host=soleur-inngest-backstop-wipe`, `shipper=inngest-backstop-wipe`, on both the `started` row (dt 16:03:16Z) and the `wiped` row (dt 16:04:25Z) as received; the pin held and no row read `emitter_mismatch` | the row's `host` and `shipper` fields as received (the wipe host sets `shipper=inngest-backstop-wipe`); record what the row showed, not what the template says |
| **Wipe poll outcome and duration** | green. Poll step 16:03:14Z to 16:04:51Z (97 s); the `wiped` row was ingested 71 s into it (16:04:25.9Z) | the `wipe` run's poll step: seconds from start to the `wiped` row |
| **Device by-id name seen by the wipe host, and measured on-host duration** | by-id name: NOT RECOVERABLE (the row does not emit it; the wipe completing implies the path resolved inside the 300 s wait). On-host duration 69 s for 10737418240 bytes (`started` 16:03:16Z to `wiped` 16:04:25Z on the host's clock); the 10 GiB size, the device naming and the duration were assumed until this run and held. | the evidence row and the run; the first real wipe is the first measurement of the 10 GiB size, the by-id naming and the duration, which were assumed until then |
| **Terraform version the orphan `-target` chain was re-checked on** | 1.10.5 (the workflow's `TERRAFORM_VERSION` pin; also what the three runs executed). The local-backend experiment (builtin `terraform_data` resources standing in for the orphan attachment and volume) was re-run on 1.10.5 in the session of 2026-10-09 and matched 1.9.8: a targeted plan on the orphan attachment shows only the attachment delete, on the volume only the volume delete, untargeted shows both. The experiment's output is not in this repository; the three green runs are the in-repo corroboration. | local-backend re-run on the workflow's pinned version (1.10.5) before the first dispatch; the earlier experiment used 1.9.8 |

### Additional per-phase process fields (all `PENDING-EVIDENCE`)

Fill one row per production command (`detach`, `wipe`, each `teardown`, `destroy`).

| Phase / command | Operator go-ahead (quote the message that named this exact command) | Head SHA the dispatch ran from | `git diff --quiet` against the reviewed SHA | Rehearsal / dry-run id |
|---|---|---|---|---|
| `detach` | recorded in the pipeline session; quote not in the repo | 32b2fe2abb (run 37950928039) | exit 1 against the reviewed commit 50fd47bb8a, confined to two TEST files (`inngest-backstop-wipe.test.sh`, `test-inngest-backstop-retire-gate.sh`: early-exit pipe-into-grep-q rewritten to count forms, 13 lines each way); exit 0 against PR #9784's head d0d74819c7 and against the squash commit d7dee46bb0 (the workflow, `variables.tf`, the wipe `.tf` and cloud-init and the gate library are byte-identical) | none: no rehearsal path exists |
| `wipe` | recorded in the pipeline session; quote not in the repo | 32b2fe2abb (run 37955244979) | as for `detach` | none: no rehearsal path exists |
| `teardown` (each, if any) | none dispatched on its own: teardown ran as a step of the `wipe` dispatch (16:04:51Z to 16:05:25Z) | 32b2fe2abb | as for `detach` | none: no rehearsal path exists |
| `destroy` | recorded in the pipeline session; quote not in the repo | 32b2fe2abb (run 37958051426) | as for `detach` | none: no rehearsal path exists |

"None: no rehearsal path exists" is the true entry for the wipe: building one was weighed and not done
(see `knowledge-base/project/specs/feat-one-shot-8285-retire-inngest-plaintext-backstop/decision-challenges.md`,
2026-10-09). Replace it only if a rehearsal is actually run.

### Completion checklist for PR B, extended

These add to the checklist above; `status:` changes from `template` to `complete` only when all of both
lists hold.

- [ ] A CLO-attested audit of this record has been done at a **named commit SHA**, recorded here with
      the reviewer and the date, before `status` is changed. The ship skill's Phase 5.5 gate applies
      to the PR that completes this record; passing it does not replace the attestation.
- [ ] Article 30 PA-13 section (e), PA-21 section (f) and PA-22 section (f), and the
      `compliance-posture.md` row, each reuse the sentence "logical, guest-side, self-attested" (or the
      provider-only wording of the D4 variant if that variant was used) and cite the first-404 time and
      the `destroy` apply-completion time recorded above. None of them says physical erasure.
- [ ] `scripts/followthroughs/inngest-luks-property-8296.sh` is not deleted (PR B task 3.4) until the
      dead-probe heartbeat feeder #9703 is armed, because that script is the only reporter of a silent
      probe pipeline until then.
- [ ] #8316 (the retire-or-keep decision for the dormant `inngest-volume-recut` target) is updated or
      closed at convergence with the PR link: the target is gone after PR A, so its question is moot.
- [ ] The wrong-volume alert in `apps/web-platform/infra/betterstack-logs-alerts.tf` is re-read for
      the backstop's absence: its `incident_cause` string and the comment block above it (the passage
      "WHAT IT DELIBERATELY DOES NOT DETECT: the plaintext backstop volume merely staying ATTACHED")
      are reworded where they presuppose the backstop still exists. The alert's query is unchanged.
- [ ] PR B is not merged before the Hetzner 404 read-back is recorded, and its squash-merge message
      uses `Ref` for both trackers and no closing keyword at all (see commit 7f7d9c3d9b for why the property
      probe is notify-only). The trackers are closed explicitly afterwards with the PR link, the run
      URLs and the 404 read-back.
- [ ] The older template `inngest-aof-destruction-record.md` already carries its own `Superseded`
      banner (2026-09-21) and is kept as the record of the recut route; it is not completed for this
      destroy and needs no change in PR B beyond the pointer appended there on 2026-10-09.

## Addendum — 2026-10-09 (review round 2)

Appended after the second and last fix round of PR #9784; nothing above is edited except the
`Superseded` markers that point here. This file is still a **template**: nothing in it states that the
volume has been wiped, detached or destroyed, and every measured field remains `PENDING-EVIDENCE` until
it is filled from run output. Ref #8285, Ref #6894.

### Second corrected paragraph: what the evidence does and does not show

State this paragraph, in place of the earlier two, in the completed record.

The wipe evidence is **logical, guest-side and self-attested**, not physical erasure. The wipe host
zeroes the volume with `blkdiscard -z`, reads the whole device back with O_DIRECT and posts the result
to Better Stack itself. It proves the guest saw zeros through the Hetzner block interface at the time of
the read. It does not evidence anything about the provider's physical media, replicas or sanitisation.
The destroy gate binds the row to the wipe run's id (nonce), the pinned emitter (host and shipper), the
Hetzner-side volume id and size, and a time window, so a **stale or replayed** row fails. It does not
make a forged row fail: the row is posted with the ingest token that other hosts share, so a holder of
that token could write a row, including one that falls inside a real attach-to-detach window. The
destroy precondition adds Hetzner's own action history for the volume. **Hetzner records an attach and
a later detach of the volume by a non-live server; this corroborates that a host held the volume, not
that the overwrite happened; erasure remains self-attested.** The attach must have finished not before the
later of the wipe run's start and any attach of the volume to the live Inngest host (169426216); no
attach to the live host may have finished after it; and the row's Better Stack ingest time must lie
between that attach's finish and the first later detach's finish, with 300 s of slack either side. No
claim of secure or physical deletion is made beyond this.

### Variant: the CLO attestation, second revision

For `erasure=provider-only` the reference is exactly one URL shape, a comment on #8285:
`https://github.com/jikig-ai/soleur/issues/8285#issuecomment-<digits>`. The gate fetches it through the
GitHub API and requires all of: the first line exactly
`CLO-ATTESTATION erasure=provider-only volume=106261946`; the comment unedited (`created_at` equal to
`updated_at`); the author a `User` (not a bot) whose `author_association` is `OWNER` or `MEMBER`; the
author's login **different from the login of the actor who dispatched the destroy**; the comment on
issue 8285; and the body containing the volume id 106261946. The completed record cites the comment URL,
the dates, and both logins (commenter and dispatcher).

### Further measured fields (all `PENDING-EVIDENCE`)

| Field | Value | Source |
|---|---|---|
| **Hetzner attach/detach times and servers** | see 'Hetzner action history' above: matched non-live attach finished 16:03:10Z (server 169544191); first later detach finished 16:05:05Z; latest attach to server 169426216 finished 2026-10-08T19:27:04Z | `GET /v1/volumes/106261946/actions`: the matched non-live `attach_volume` (server id, finish time), the first later `detach_volume` (finish time), and the finish time of the latest `attach_volume` to server 169426216 if any |
| **Wipe row ingest time versus that window** | top-level `dt` 16:04:25.000000 (the sender's clock, see 'Completion'); Better Stack `ingest_time` 16:04:25.889296 (read from the hot window on 2026-10-09 before it aged out; the archive arm carries no `ingest_time`). Window: attach finish 16:03:10Z, detach finish 16:05:05Z. The `ingest_time` lies 75.9 s after the attach finish and 39.1 s before the detach finish, so it holds without the 300 s slack. | the `wiped` row's Better Stack top-level time; it must lie between the attach finish and the detach finish, 300 s slack either side |
| **Guest hostname as received** | `soleur-inngest-backstop-wipe`, as pinned; no `emitter_mismatch` | the row's `host`; the pin assumes `soleur-inngest-backstop-wipe`, which is unmeasured until the first run. If it differs, record that rows read `emitter_mismatch` and how it was resolved |
| **Dispatching actor and CLO commenter logins** | not applicable (provider-only variant not used). Dispatching actor `deruelle` on all three runs. | D4 variant only: the run's actor and the comment's author; they must differ |
| **Attestation comment properties** | not applicable (provider-only variant not used) | D4 variant only: first line, `created_at` and `updated_at`, `author_association`, user type |
| **Terraform version of the orphan `-target` re-run** | 1.10.5; matched 1.9.8 (see 'Terraform version the orphan `-target` chain was re-checked on' above) | the 1.10.5 local-backend result (the earlier experiment used 1.9.8); this repeats the row in the previous addendum and is the one to fill |

### Completion checklist for PR B, second revision

These add to both earlier lists.

- [ ] The second corrected paragraph above is the one stated, or the D4 wording with the second-revision
      attestation properties verified.
- [ ] The "Further measured fields" are filled from the named reads, including the observed guest
      hostname.
- [ ] The days-to-expiry gap is recorded as it stood: the property probe's daily comment never carried
      a days-to-expiry line, because PR A did not edit the probe. PR B's pre-deletion checklist notes
      this rather than adding the line to a script it is about to delete.

> **Clarification 2026-10-09 (#8285, verification seat):** wherever this record says the wipe row's
> "ingest time" or "Better Stack top-level time" lies in the Hetzner attach..detach window, read "top-level
> `dt` column": the wipe host sends its own `dt`, so it may be the sender's clock, not Better Stack's
> receive time. This is unmeasured until the first real wipe. The window check is a plausibility bound;
> Hetzner's action history is the independent evidence.

## Completion — 2026-10-09 (#8285 PR B)

Appended by PR B of #8285 (draft PR #9877); the dated sections above are unchanged except that the measured fields now
hold values and a pointer sits under "What this file is". Counts and identifiers only: no payload, key material or token
value appears anywhere in this record. Ref #8285, Ref #6894.

### What happened

Volume 106261946 (`hcloud_volume.inngest_redis`, 10737418240 bytes) was detached from the live host (run 37950928039,
Hetzner `detach_volume` finished 2026-10-09T15:27:18Z), attached to a throwaway server, zeroed and read back
(run 37955244979; evidence row `result=wiped readback=zero sig_after=none`, host clock 16:04:25Z), detached again
(16:05:05Z), and deleted (run 37958051426; Hetzner `delete_volume` 16:21:24Z, first 404 read 16:21:26Z). The throwaway
server was removed by the same dispatch. The live LUKS volume 106903269 was never touched and its probe row is
unchanged in shape afterwards. The variant used is the evidence path.

### What the evidence does and does not show

The wipe evidence is **logical, guest-side and self-attested**, not physical erasure. The wipe host
zeroes the volume with `blkdiscard -z`, reads the whole device back with O_DIRECT and posts the result
to Better Stack itself. It proves the guest saw zeros through the Hetzner block interface at the time of
the read. It does not evidence anything about the provider's physical media, replicas or sanitisation.
The destroy gate binds the row to the wipe run's id (nonce), the pinned emitter (host and shipper), the
Hetzner-side volume id and size, and a time window, so a **stale or replayed** row fails. It does not
make a forged row fail: the row is posted with the ingest token that other hosts share, so a holder of
that token could write a row, including one that falls inside a real attach-to-detach window. The
destroy precondition adds Hetzner's own action history for the volume. **Hetzner records an attach and
a later detach of the volume by a non-live server; this corroborates that a host held the volume, not
that the overwrite happened; erasure remains self-attested.** The attach must have finished not before the
later of the wipe run's start and any attach of the volume to the live Inngest host (169426216); no
attach to the live host may have finished after it; and the row's Better Stack ingest time must lie
between that attach's finish and the first later detach's finish, with 300 s of slack either side. No
claim of secure or physical deletion is made beyond this.

### Measurement: what the wipe row's top-level `dt` is

Measured 2026-10-09 against the `SOLEUR_INNGEST_BACKSTOP_WIPE` rows of run 37955244979. **`dt` is the sender's clock,
not Better Stack's receive time; `ingest_time` is the receipt time; the window check holds on `ingest_time`.** Evidence:
the top-level `dt` of the `wiped` row is `2026-10-09 16:04:25.000000` (whole-second precision) and equals the `dt` field
inside the JSON the wipe host posted (`"dt":"2026-10-09T16:04:25Z"`), while the same row's `ingest_time` is
`16:04:25.889296`; the `started` row reads `dt` 16:03:16.000000 against `ingest_time` 16:03:17.468257 (the two `ingest_time`
values were read from Better Stack's hot window on 2026-10-09 before it aged out; the archive arm has no `ingest_time`
column, so they cannot be re-read now, while the `dt` values and the in-payload `dt` were re-read from the archive). Receipt follows the
sender's stamp by 0.9 s and 1.5 s. The clarification of 2026-10-09 above ("top-level `dt` column ... unmeasured") is
therefore resolved: the host sets its own `dt` and Better Stack keeps it. The window check is still only a plausibility
bound; Hetzner's action history is the independent evidence.

### Gaps and deviations, recorded as they stood

- **Operator go-ahead quotes** for the three production commands are recorded in the pipeline session; the quotes are
  not in the repository. The approvals themselves are: `deruelle` approved the `inngest-cutover` environment on each of
  the three runs, and `deruelle` was also the dispatching actor. This is a self-approval; the evidence path does not
  require two people.
- **Reviewed commit versus dispatched head.** The reviewed commit 50fd47bb8a differs from the dispatched head
  32b2fe2abb on two test files only (13 lines each way: `inngest-backstop-wipe.test.sh` and
  `test-inngest-backstop-retire-gate.sh`, early-exit pipe-into-grep-q rewritten to count forms). The workflow, the
  variables, the wipe `.tf` and cloud-init and the gate library are byte-identical between the PR head, the squash commit
  d7dee46bb0 and the dispatched head. The reviewed-commit comparison therefore exits 1, and this is the reason.
- **No rehearsal existed** for the wipe (weighed and not built; `decision-challenges.md`, 2026-10-09). The first real wipe
  was the first run of its host script and it passed.
- **No key or header continuity proof existed** before the backstop went: nothing proved, ahead of `detach`, that the
  LUKS header and the Doppler key `INNGEST_REDIS_LUKS_KEY` still open the live volume at rest. The only evidence is that the
  running host serves from it (probe rows on `scsi-0HC_Volume_106903269` and `/dev/mapper/inngest-redis`). After retirement
  that volume is the only copy and the key its sole opener; protection is tracked in #9879.
- **The wipe host's by-id device name is not recoverable** (the row does not emit it).
- **Days-to-expiry.** The property probe's daily comment never carried a days-to-expiry line, because PR A did not edit the
  probe and PR B does not delete it (it stays until the dead-probe feeder #9703 is armed).
- **The pre-detach snapshot and backup read was not captured separately**; the counts are from 2026-10-09T19:05Z.

### Records amended by PR B (all after the Hetzner 404)

Article 30 register PA-13 section (e), PA-21 section (f) and PA-22 section (f) (dated brackets appended, nothing deleted);
`compliance-posture.md` (Completed Compliance Work row); ADR-142 (addendum 2026-10-09, PR B); the C4 model
(`platform.infra.inngestRedis`, regenerated); `operations/expenses.md`; the encryption-posture ledger (the
`hcloud_volume.inngest_redis` row removed, the `hcloud_volume.inngest_redis_luks` row corrected); the cutover runbook
(5a rewritten, 5b a past-tense record).

### Completion checklist for PR B: state at the time of writing

- [x] Every value cell is filled from run output or a named read; the mentions of the placeholder token that remain are in
      dated template headings and prose above and describe the template, not a pending value.
- [x] The `wiped` row's nonce equals the wipe run id; its `volume_id` and `size_bytes` match.
- [x] The first 404 time (16:21:26Z) and the `destroy` apply time (16:21:21Z to 16:21:25Z; `delete_volume` 16:21:24Z) are recorded.
- [x] The second corrected paragraph is stated above (evidence path).
- [x] No payload, key material or token value appears in this record.
- [x] Article 30 PA-13 (e), PA-21 (f), PA-22 (f) and the compliance-posture row reuse "logical, guest-side, self-attested" and cite both times.
- [x] The property probe is not deleted (#9703 not armed).
- [ ] CLO attestation at a named commit SHA: recorded in "CLO attestation" below.
- [ ] `status:` flips from `template` to `complete` only in the commit that records that attestation, in the PR that also carries the 404 read-back.

### CLO attestation

PENDING: recorded by the attestation step of PR B once the record is final at a named commit SHA.
