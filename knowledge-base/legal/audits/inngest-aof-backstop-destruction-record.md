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
| **Exact volume size (bytes)** | `PENDING-EVIDENCE` | Hetzner `GET /v1/volumes/106261946` before the `detach` phase, and the `size_bytes` of the wipe evidence row (the two must agree) |
| **Pre-state: snapshots of the volume** | `PENDING-EVIDENCE` | Hetzner API read at the `detach` phase (expected 0; a non-zero count is a finding that the destroy does not erase) |
| **Pre-state: backups covering the volume** | `PENDING-EVIDENCE` | Hetzner API read at the `detach` phase (expected 0) |
| **Live store before: `redis_keys` / `redis_active`** | `PENDING-EVIDENCE` | newest `host_role=dedicated` `SOLEUR_INNGEST_SERVER_PROBE` row before `detach`; informational only, counts legitimately move |
| **`detach` dispatch run id and URL** | `PENDING-EVIDENCE` | GitHub Actions run of `apply_target=inngest-backstop-retire phase=detach` |
| **`detach` completion time (UTC)** | `PENDING-EVIDENCE` | that run's apply step |
| **`detach` read-back** | `PENDING-EVIDENCE` | Hetzner `GET /v1/volumes/106261946` showing `server: null` |
| **`wipe` dispatch run id and URL** | `PENDING-EVIDENCE` | GitHub Actions run of `phase=wipe`; the run id is the evidence row's `nonce` |
| **`wipe` start and end time (UTC)** | `PENDING-EVIDENCE` | that run's steps |
| **Wipe evidence row: `result`** | `PENDING-EVIDENCE` | Better Stack `SOLEUR_INNGEST_BACKSTOP_WIPE` row whose `nonce` equals the wipe run id (expected `wiped`) |
| **Wipe evidence row: `readback`, `sig_after`** | `PENDING-EVIDENCE` | same row (expected `zero`, `none`) |
| **Wipe evidence row: `volume_id`, `size_bytes`** | `PENDING-EVIDENCE` | same row (must equal 106261946 and the size above) |
| **Wipe evidence row: `fs_uuid`, `last_write`** | `PENDING-EVIDENCE` | same row; non-payload identity captured before the zero |
| **Wipe evidence row: `prior`** | `PENDING-EVIDENCE` | same row (`blank` only if the idempotent already-zero path was taken) |
| **Throwaway wipe host: created and deleted** | `PENDING-EVIDENCE` | Hetzner `GET /servers` shows the wipe host absent after the `wipe` phase; `phase=teardown` run id if one was needed |
| **`destroy` dispatch run id and URL** | `PENDING-EVIDENCE` | GitHub Actions run of `phase=destroy`; its `wipe_run_id` input |
| **`destroy` apply completion time (UTC)** | `PENDING-EVIDENCE` | that run's apply step |
| **First Hetzner 404 time (UTC)** | `PENDING-EVIDENCE` | self-pulled `GET /v1/volumes/106261946` returning 404 (a 404 carries no timestamp itself; record the time of the read) |
| **Post-state: server 169426216 attached volumes** | `PENDING-EVIDENCE` | Hetzner API (expected `[106903269]`) |
| **Post-state: snapshots / backups** | `PENDING-EVIDENCE` | Hetzner API (expected 0 / 0) |
| **Live store after: `redis_keys` / `redis_active`, `data_mount_devid`** | `PENDING-EVIDENCE` | first probe row after the destroy (expected `scsi-0HC_Volume_106903269`, `/dev/mapper/inngest-redis`) |
| **Wrong-volume alert state** | `PENDING-EVIDENCE` | `logtail_exploration_alert` 2988582970 `paused=false` plus a fresh probe row present |
| **Authorizing reviewer (each phase)** | `PENDING-EVIDENCE` | the `inngest-cutover` environment approval record |
| **Variant used** | `PENDING-EVIDENCE` | one of: `evidence-path` (wipe evidence row present) or `provider-only` (see below) |

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
| CLO attestation reference | `PENDING-EVIDENCE` (not applicable unless the variant is chosen) |
| Date of the decision | `PENDING-EVIDENCE` |
| Reason the wipe phase did not succeed | `PENDING-EVIDENCE` |

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

### Variant: the CLO attestation reference

For `erasure=provider-only` the reference is exactly one URL shape, a comment on #8285:
`https://github.com/jikig-ai/soleur/issues/8285#issuecomment-<digits>`. The gate fetches it through
the GitHub API and requires the author to be an owner, member or collaborator of the repository and
the body to contain the volume id 106261946. A reference on any other host, or of any other shape, is
refused. The completed record cites the comment URL and the date.

### Additional measured fields (all `PENDING-EVIDENCE`)

| Field | Value | Source |
|---|---|---|
| **Hetzner action history for the volume** | `PENDING-EVIDENCE` | `GET /v1/volumes/106261946/actions` read before the `destroy` phase: the `attach_volume` action id, status and finish time with the server id it names (must not be 169426216 and not null), and the later `detach_volume` action id, status and finish time |
| **Evidence row emitter** | `PENDING-EVIDENCE` | the row's `host` and `shipper` fields as received (the wipe host sets `shipper=inngest-backstop-wipe`); record what the row showed, not what the template says |
| **Wipe poll outcome and duration** | `PENDING-EVIDENCE` | the `wipe` run's poll step: seconds from start to the `wiped` row |
| **Device by-id name seen by the wipe host, and measured on-host duration** | `PENDING-EVIDENCE` | the evidence row and the run; the first real wipe is the first measurement of the 10 GiB size, the by-id naming and the duration, which were assumed until then |
| **Terraform version the orphan `-target` chain was re-checked on** | `PENDING-EVIDENCE` | local-backend re-run on the workflow's pinned version (1.10.5) before the first dispatch; the earlier experiment used 1.9.8 |

### Additional per-phase process fields (all `PENDING-EVIDENCE`)

Fill one row per production command (`detach`, `wipe`, each `teardown`, `destroy`).

| Phase / command | Operator go-ahead (quote the message that named this exact command) | Head SHA the dispatch ran from | `git diff --quiet` against the reviewed SHA | Rehearsal / dry-run id |
|---|---|---|---|---|
| `detach` | `PENDING-EVIDENCE` | `PENDING-EVIDENCE` | `PENDING-EVIDENCE` (exit status) | none: no rehearsal path exists |
| `wipe` | `PENDING-EVIDENCE` | `PENDING-EVIDENCE` | `PENDING-EVIDENCE` (exit status) | none: no rehearsal path exists |
| `teardown` (each, if any) | `PENDING-EVIDENCE` | `PENDING-EVIDENCE` | `PENDING-EVIDENCE` (exit status) | none: no rehearsal path exists |
| `destroy` | `PENDING-EVIDENCE` | `PENDING-EVIDENCE` | `PENDING-EVIDENCE` (exit status) | none: no rehearsal path exists |

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
