---
title: "Art. 5(2) destruction record — web-1's retained plaintext /workspaces volume (hcloud_volume.workspaces[\"web-1\"])"
status: template
date: 2026-09-28
related: [6604, 6588, 6897, 6931, 8734]
related_adrs: [ADR-119, ADR-241]
brand_survival_threshold: single-user incident
---

# Art. 5(2) destruction record — web-1's retained plaintext `/workspaces` volume

## What this file is

A **template**, not a record. It is committed EMPTY and dated, before the dispatch exists (PR A of
#6604 step 7), and it is completed in PR B, after the dispatch, from the dispatch's own rows. It must
be `status: complete` **before** ADR-119 flips to `accepted`.

Art. 5(2) makes the controller responsible for demonstrating compliance with Art. 5(1). Destroying a
volume that holds every user's workspace source code as of 2026-07-23 is an Art. 5(1)(e) act, and the
only thing that can evidence it afterwards is a record made at the time. **The volume itself is the
evidence, and the wipe destroys it.** A record drafted after a destructive act is a justification;
drafted before, it is a precondition. Every field below is a value the gates have already had to
read to allow the act, so completing it is transcription, not reconstruction.

The act: the environment-gated `wipe` job of `.github/workflows/workspaces-luks-cutover.yml` zeroes the
volume on web-1 (`blkdiscard -z`, full-device O_DIRECT read-back), then detaches and deletes it through
the Hetzner API; `.github/workflows/workspaces-plaintext-forget.yml` then forgets its two Terraform
addresses. Design: ADR-119 *Addendum (2026-09-28): retiring the plaintext backstop*. Runbook:
`knowledge-base/engineering/operations/runbooks/workspaces-luks-cutover-6604.md` Sequence step 7.

## Where every field comes from

From the dispatch run log and the `luks-monitor` tag (no SSH): the single
`SOLEUR_WORKSPACES_LUKS_WIPE … result=wiped` row, the `result=rehearsal_ok` row of the rehearsal the
go-ahead quoted, the `SOLEUR_WORKSPACES_LUKS_WIPE_EVIDENCE` rows, the preflight step summary, the `wipe`
job's API step, and the forget run.

```
doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh \
  --since 1d --grep SOLEUR_WORKSPACES_LUKS_WIPE --limit 500
```

**Personal data is recorded as COUNTS only — never names, ids, emails or paths.**

## Record

### Timing and authority

| Field | Value | Source |
|---|---|---|
| **Zero started / completed (UTC)** | *(fill: the `result=begun` and `result=wiped` row times)* | run log / `luks-monitor` tag |
| **Delete completed (UTC)** | *(fill)* | the `wipe` job's API step (`DELETE` → `204`) |
| **Rehearsal run id** | *(fill)* | the `dry_run=true` dispatch quoted in the go-ahead |
| **Dispatch run id** | *(fill)* | the `dry_run=false` dispatch |
| **Forget run id** | *(fill)* | `workspaces-plaintext-forget.yml` |
| **Approver** | *(fill: the GitHub user who approved `workspaces-luks-cutover`; or "agent under delegation" + the delegating message)* | the environment approval record |
| **The operator go-ahead, quoted** | *(fill: verbatim, with its date)* | the session |

### Target identity

| Field | Value | Source |
|---|---|---|
| **Volume id / name** | *(fill — MUST be `105149570` / `soleur-web-platform-data`)* | preflight banner; the `wiped` row's `volume_id` |
| **Size** | *(fill: GiB and bytes)* | preflight banner; the `wiped` row's `bytes` |
| **`linux_device` / server** | *(fill — `/dev/disk/by-id/scsi-0HC_Volume_105149570` on `123931471`)* | preflight banner |
| **`format` / label** | *(fill — `ext4` / `workspaces_plain`)* | preflight banner; the rehearsal row's `label` |
| **Resolved target vs the mapper's backing device** | *(fill: `target=` and `backing=` from the rehearsal row — they MUST differ)* | rehearsal row (W6) |
| **Holders / dependents / device units** | *(fill: `holders=0 dependents=0 device_units=<n>`)* | rehearsal row (W6, W6b) |

### Method and proof

| Field | Value | Source |
|---|---|---|
| **Discard / write-zeroes capability, scheduler** | *(fill: `discard_gran`, `discard_max`, `write_zeroes_max`, `scheduler`)* | the `wiped` row (W8) |
| **Positive control** | *(fill: `magic=53ef` on the rehearsal row)* | W9 |
| **Provenance: last mount / last write** | *(fill: from the `field=last_mount` / `field=last_write` evidence rows — the CLO's check that nothing wrote after the 2026-07-23 cutover)* | W9 evidence rows |
| **Zero command** | `blkdiscard -z -v <device>` under a 150M cgroup `io.max` cap — never `-f` (O_EXCL on) | the script; the `begun` row |
| **Read-back** | *(fill: `readback=zero`, bytes read = size)* | the `wiped` row (W11) |
| **Signature after the zero** | none (`blkid -p` rc 2) | W12 |

### Live data recoverable at wipe time

| Field | Value | Source |
|---|---|---|
| **Live header UUID = persisted `CANARY_OK`** | *(fill: `uuid=` on the rehearsal row)* | W3 |
| **Escrowed passphrase opens the live header** | *(fill: yes — the rehearsal passed W4)* | W4 |
| **Off-host header restorable and current** | *(fill: `hdr_bytes`, `hdr_sha256` on the rehearsal row)* | W5 |
| **Same-day verify baseline** | *(fill: run id, `workspace_count=<n>`)* | `workspaces-luks-verify.yml` |
| **Post-dispatch verify** | *(fill: run id, `ready=true`, `workspace_count` vs the baseline; any drop explained)* | `workspaces-luks-verify.yml` |

### Hetzner deletion and state

| Field | Value | Source |
|---|---|---|
| **Detach action id / status** | *(fill)* | the `wipe` job's API step |
| **`DELETE` status; final `GET`** | *(fill — `204`; `404`)* | the `wipe` job's API step |
| **Server `123931471` volumes after** | *(fill — MUST be `[106443278]`)* | the `wipe` job's API step |
| **Terraform state diff** | *(fill: the two removed addresses, serial `n → n+1`, lineage unchanged)* | the forget run |

### Personal data destroyed

| Field | Value | Source |
|---|---|---|
| **Categories** | Workspace source code and git history as of the 2026-07-23 cutover, including third-party commit authors' names/emails inside that history | the volume's role (ADR-119) |
| **Workspace count on the copy** | *(fill: COUNT only — the G3 count persisted at the cutover)* | cutover run 29995956562 |
| **Art. 17 account deletions on the live volume between 2026-07-23 and the wipe** | *(fill: COUNT, or the pre-onboarding bound — first arm's-length onboarding 2026-08-06 — if it cannot be measured)* | the account-deletion audit trail |

### Basis, recoverability, other copies

| Field | Value |
|---|---|
| **Lawful basis** | Art. 5(1)(e) storage limitation, Art. 17(1)(a) (the retained copy defeats every erasure made since the cutover), Art. 32(1) (the plaintext copy is the exposure the LUKS migration exists to close). AP-009 deviation recorded in the ADR-119 addendum of 2026-09-28: a superseded copy frozen at the 2026-07-23 cutover. |
| **Recoverability** | *(CLO-attested)* Logical full-device zero verified by a direct-IO read-back; physical media reclamation per the Hetzner DPA. A zero on a network block volume does not attest physical erasure. |
| **Passphrase copies** | Doppler `prd_workspaces_luks` (proven by W4); Terraform state `random_password.workspaces_luks` (not proven by this act). |
| **Other copies of workspace data** | The live LUKS volume `106443278` (now the only copy); web-2's plaintext volume (empty, serving-weight 0, #6931); the plaintext `git_data` volume (#6897); the web-1 root-disk snapshot deleted under #8734; the CLEAN_STRAY root-disk stray deleted 2026-07-19. |

## Completion checklist

- [ ] Every `*(fill)*` is replaced with a measured value, not an estimate.
- [ ] Exactly one `result=wiped` row exists for `105149570`, and `target` ≠ `backing` on the rehearsal row.
- [ ] Personal-data fields are counts only.
- [ ] The recoverability row is CLO-attested.
- [ ] `status:` is changed from `template` to `complete` — BEFORE ADR-119 flips to `accepted`.
