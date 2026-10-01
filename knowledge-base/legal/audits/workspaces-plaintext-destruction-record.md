---
title: "Art. 5(2) destruction record — web-1's retained plaintext /workspaces volume (hcloud_volume.workspaces[\"web-1\"])"
status: template
date: 2026-09-28
related: [6604, 6588, 6897, 6931, 8734, 9163, 9286, 9348]
related_adrs: [ADR-119, ADR-241]
brand_survival_threshold: single-user incident
---

# Art. 5(2) destruction record — web-1's retained plaintext `/workspaces` volume

## What this file is

A **template**, not a record. It is committed EMPTY and dated, before the dispatch exists (PR A of
#6604 step 7), and it is completed in PR B, after the dispatch, from the dispatch's own rows. It must
be `status: complete` **before** ADR-119 flips to `accepted`.

**Superseded 2026-10-01 (#6604, PR #9348 draft), as to "committed EMPTY":** the fields that the
rehearsal run `36769782488`, the same-day baseline run `36770448813` and the cutover run `29995956562`
already print are filled below, each labelled "at rehearsal 36769782488 (2026-09-30)" (or with its own
run), never "at wipe time". Every field only the destructive dispatch D or the state forget can supply
is a PENDING-EVIDENCE marker. `status:` stays `template` until every marker is replaced
from those runs' own output and the CLO has attested (`2026-10-counsel-review-6604.md`).

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

**Superseded 2026-10-01 (#6604, PR #9348), as to the paths above:** on the merge of PR #9348 the
`wipe` job, the `CONFIRM_WIPE` mode body (`wipe_plaintext()` and its helpers in
`workspaces-cutover.sh`) and the forget workflow are deleted from `main`. They are cited from then on
by name at commit `59abf6a76c` (the SHA rehearsal 36769782488 ran at), never by path on `main`: the
`wipe` job of `workspaces-luks-cutover.yml` at `59abf6a76c`, and `workspaces-plaintext-forget.yml` at
`59abf6a76c`. That SHA is the procedure as run only if D's and the forget's head SHAs show no diff
from it over `apps/web-platform/infra/workspaces-cutover.sh`, `.github/workflows/workspaces-luks-cutover.yml`
and `.github/workflows/workspaces-plaintext-forget.yml` (the plan's Resume release check runs that
`git diff --quiet`); otherwise the as-run head SHA is cited instead. Until PR #9348 merges, the wipe
dispatch path (the `wipe_plaintext` and `expected_plaintext_volume_id` inputs and the `wipe` job) and
the forget workflow exist on `main` only — that PR's branch has already deleted them — and D and the
forget are dispatched from `main` (the `workspaces-luks-cutover` environment admits `main` only), so
they run `main`'s copies. Each run's head SHA is recorded with its run id:
PENDING-EVIDENCE(D-head-sha), PENDING-EVIDENCE(forget-head-sha). This paragraph moves to the past
tense when `status:` becomes `complete`.

## Where every field comes from

From the dispatch run log and the `luks-monitor` tag (no SSH): the single
`SOLEUR_WORKSPACES_LUKS_WIPE … result=wiped` row, the `result=rehearsal_ok` row of the rehearsal the
go-ahead quoted, the `SOLEUR_WORKSPACES_LUKS_WIPE_EVIDENCE` rows, the preflight step summary, the `wipe`
job's API step, and the forget run.

```text
doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh \
  --since 1d --grep SOLEUR_WORKSPACES_LUKS_WIPE --limit 500
```

**Superseded 2026-10-01 (#9348), as to `--since 1d`:** a one-day window returns nothing, without an
error, when the record is filled more than a day after D. Anchor the window on D's start instead,
where `<D-start-ISO-Z>` is `gh api repos/jikig-ai/soleur/actions/runs/<D>/attempts/1 --jq .run_started_at`:

```text
doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh \
  --since <D-start-ISO-Z> --grep SOLEUR_WORKSPACES_LUKS_WIPE --limit 500
```

**Personal data is recorded as COUNTS only — never names, ids, emails or paths.** The rehearsal's
`plaintext_only_name` rows (workspace ids), if any run prints them, are never copied here.

## Record

### Timing and authority

| Field | Value | Source |
|---|---|---|
| **Zero started / completed (UTC)** | PENDING-EVIDENCE(zero-start-UTC) / PENDING-EVIDENCE(zero-complete-UTC) | run log / `luks-monitor` tag |
| **Delete completed (UTC)** | PENDING-EVIDENCE(delete-UTC) | the `wipe` job's API step (`DELETE` → `204`) |
| **Rehearsal run id** | `36769782488` — `workflow_dispatch` on `main` at `59abf6a76c`, created 2026-09-30T20:02:05Z, concluded `success`; its host row is `result=rehearsal_ok arm=first_wipe volume_id=105149570` at 2026-09-30T20:06:14Z. Whether the go-ahead quotes this rehearsal or a later one: PENDING-EVIDENCE(go-ahead-rehearsal-match) | the `dry_run=true` dispatch quoted in the go-ahead |
| **Dispatch run id** | PENDING-EVIDENCE(D-run-id) (every D run, if a `re_zero` or `detached` arm ran) | the `dry_run=false` dispatch |
| **Forget run id** | PENDING-EVIDENCE(forget-run-id); its result row (`forgot=2`, `forgot=1`, or a traced `already_forgotten`): PENDING-EVIDENCE(forget-result) | `workspaces-plaintext-forget.yml`, dispatched from `main` before PR #9348 merges |
| **Approver** | PENDING-EVIDENCE(approver) (a GitHub handle, never an email) | the environment approval record |
| **The operator go-ahead, quoted** | PENDING-EVIDENCE(go-ahead-quote) | the session |

### Target identity

| Field | Value | Source |
|---|---|---|
| **Volume id / name** | `105149570` / `soleur-web-platform-data`, at rehearsal 36769782488 (2026-09-30); the `wiped` row's `volume_id`: PENDING-EVIDENCE(wiped-row) | preflight env and API classification; the `wiped` row's `volume_id` |
| **Size** | 20 GiB / `21474836480` bytes, at rehearsal 36769782488 (2026-09-30) (`size=21474836480` on the host row; `size_bytes=21474836480` in preflight's API classification); the `wiped` row's `bytes`: PENDING-EVIDENCE(wiped-row) | preflight banner; the `wiped` row's `bytes` |
| **`linux_device` / server** | server `123931471` (`WEB1_SERVER_ID`), and `serial=ok` (the device's hypervisor serial matched the pin), at rehearsal 36769782488 (2026-09-30); preflight classified the volume `api_state=attached`. The by-id path string itself is not printed by the rehearsal: PENDING-EVIDENCE(linux-device) | preflight banner |
| **`format` / observed label / recorded mount source / fs UUID** | ext4 (superblock `magic=53ef`) / `label=none` / `plaintext_dev=/dev/sdb` (resolves to `target=/dev/sdb`) / `plaintext_fs_uuid=4cc6a724-f3b7-4c96-b607-af174f82169d`, at rehearsal 36769782488 (2026-09-30) | preflight banner; the rehearsal row's `label`, `plaintext_dev` and `plaintext_fs_uuid` |
| **Resolved target vs the mapper's backing device** | `target=/dev/sdb`, `backing=/dev/sdc` — they differ, at rehearsal 36769782488 (2026-09-30) | rehearsal row (W6) |
| **Holders / dependents / device units** | `holders=0 dependents=0 device_units=7`, at rehearsal 36769782488 (2026-09-30) | rehearsal row (W6, W6b) |

### Method and proof

| Field | Value | Source |
|---|---|---|
| **Discard / write-zeroes capability, scheduler** | `discard_gran=4096`, `discard_max=1073741824`, `write_zeroes_max=2147483136`, `scheduler=none`, at rehearsal 36769782488 (2026-09-30); on the `wiped` row: PENDING-EVIDENCE(wiped-row) | the `wiped` row (W8) |
| **Positive control** | `magic=53ef`, at rehearsal 36769782488 (2026-09-30) | W9 |
| **Provenance: last mount / last write** | `last_mount=Mon Jul 20 22:42:07 2026`, `last_write=Thu Jul 23 09:40:34 2026` (no timezone printed), from the `field=last_mount` / `field=last_write` evidence rows at rehearsal 36769782488 (2026-09-30). The last write falls inside cutover run `29995956562`'s window, one second after its `persisted workspace inventory baseline: WORKSPACES_COUNT=8` line (2026-07-23T09:40:33Z) and before the 2026-07-23T09:45:00Z freeze bound, so nothing wrote to the copy after the cutover froze it | W9 evidence rows; cutover run 29995956562 log (that run concluded `failure` after the persist) |
| **Zero command** | `blkdiscard -z -v <device>` under a cgroup `io.max` cap of `150000000` bytes/s read and write — never `-f` (O_EXCL on). In force at rehearsal 36769782488 (2026-09-30): `io_max=8:16_rbps=150000000_wbps=150000000_riops=max_wiops=max`. (Corrected 2026-10-01: the template read "150M"; the cap is plain bytes, because systemd reads a `150M` suffix in base 1000.) | the script; the `begun` row |
| **Read-back** | PENDING-EVIDENCE(readback) (`readback=zero`, bytes read = size) | the `wiped` row (W11) |
| **Signature after the zero** | PENDING-EVIDENCE(signature-after-zero) (expected: none, `blkid -p` rc 2) | W12 |

### Live data recoverable at wipe time

| Field | Value | Source |
|---|---|---|
| **Live header UUID = persisted `CANARY_OK`** | `uuid=d42ede00-4ec4-48c6-9b83-f15ff3f69082`, at rehearsal 36769782488 (2026-09-30); at D: PENDING-EVIDENCE(wiped-row) | W3 |
| **Escrowed passphrase opens the live header** | yes, at rehearsal 36769782488 (2026-09-30): the `result=rehearsal_ok` row is emitted only after W3, W4 and W5 pass | W4 |
| **Off-host header restorable and current** | `hdr_bytes=16777216`, `hdr_sha256=ac3447ec55082340d8de0e6a84a51439db1110464216dcb4e2f14df1c60dc98f`, at rehearsal 36769782488 (2026-09-30) | W5 |
| **Same-day verify baseline** | run `36770448813` (2026-09-30T20:07:45Z, `success`): `ready=true workspace_count=9 expected=8` | `workspaces-luks-verify.yml` |
| **Post-dispatch verify** | PENDING-EVIDENCE(post-dispatch-verify) (run id, `ready=true`, `workspace_count` vs the baseline of 9; any drop explained) | `workspaces-luks-verify.yml` |

### Hetzner deletion and state

| Field | Value | Source |
|---|---|---|
| **Detach action id / status** | PENDING-EVIDENCE(detach-action-id) (`n/a (arm=detached, run <id>)` if D ran on the detached arm) | the `wipe` job's API step |
| **`DELETE` status; final `GET`** | PENDING-EVIDENCE(delete-status) ; PENDING-EVIDENCE(final-get-404) (expected `204`; a presence-proven `404`) | the `wipe` job's API step |
| **Server `123931471` volumes after** | PENDING-EVIDENCE(server-volumes-after) (MUST be `[106443278]`) | the `wipe` job's API step |
| **Terraform state diff** | PENDING-EVIDENCE(state-diff) (the two removed addresses, serial `n → n+1`, lineage unchanged) | the forget run |

### Personal data destroyed

| Field | Value | Source |
|---|---|---|
| **Categories** | Workspace source code and git history as of the 2026-07-23 cutover, including third-party commit authors' names/emails inside that history | the volume's role (ADR-119) |
| **Workspace count on the copy** | 8 (COUNT only) — `persisted workspace inventory baseline: WORKSPACES_COUNT=8` at 2026-07-23T09:40:33Z | cutover run 29995956562 |
| **Workspaces on the copy only (`plaintext_only_count`)** | 0, at rehearsal 36769782488 (2026-09-30) (`plaintext_only=0` on the host row and on the `field=plaintext_only` evidence row); at D: PENDING-EVIDENCE(plaintext-only-count-at-D). A non-zero value at D is dispositioned here by count before `complete`, and that run's logs are deleted after capture (they would carry workspace ids) | rehearsal row; the D host row |
| **Art. 17 account deletions on the live volume between 2026-07-23 and the wipe** | Bounded, not counted: the copy was frozen 2026-07-23, before the first arm's-length onboarding on 2026-08-06 (tester #1, `knowledge-base/engineering/operations/runbooks/alpha-tester-onboarding.md`), so any Art. 17 erasure the copy defeated is bounded to the owners of the 8 workspaces frozen on it (re-evaluation trigger (2) of the #6588 counsel review) | the account-deletion audit trail; cutover run 29995956562 |

### Basis, recoverability, other copies

| Field | Value |
|---|---|
| **Lawful basis** | Art. 5(1)(e) storage limitation, Art. 17(1)(a) (the retained copy defeats every erasure made since the cutover), Art. 32(1) (the plaintext copy is the exposure the LUKS migration exists to close). AP-009 deviation recorded in the ADR-119 addendum of 2026-09-28: a superseded copy frozen at the 2026-07-23 cutover. |
| **Recoverability** | PENDING-EVIDENCE(recoverability-clo-attestation). Wording proposed for attestation at the evidence-fill commit: logically zeroed, verified by a full-device direct-IO read-back; physical media reclamation per the Hetzner DPA. A zero on a network block volume does not attest physical erasure. |
| **Passphrase copies** | Doppler `prd_workspaces_luks` (proven by W4); Terraform state `random_password.workspaces_luks` (not proven by this act). |
| **Other copies of workspace data** | The live LUKS volume `106443278` (the only copy after the wipe); web-2's plaintext volume (empty, serving-weight 0, #6931); the plaintext `git_data` volume (#6897 — it holds no repository: the #8634 re-attestation records the store empty and `GIT_DATA_STORE_ENABLED` off); the web-1 root-disk snapshot deleted under #8734; the CLEAN_STRAY root-disk stray deleted 2026-07-19. |

### What remains after the act (added 2026-10-01, #6604 PR #9348)

| Field | Value |
|---|---|
| **The sentinel consequence** | On the merge of PR #9348, web-1's `workspaces_volume_id` template argument becomes the literal `"retired-6604"`. Should web-1 ever be rebuilt, its first boot's `/mnt/data` mount fails, `soleur-boot-emit workspaces_mount fatal` fires, and the host keeps booting on an empty, writable `/mnt/data` on the root disk: it fails loud, not closed, and new writes there would land unencrypted (fold into #6931). That path is unreachable while the replace path refuses web-1 and `user_data` is `ignore_changes`; a web-1 rebirth is the residual tracked in #6964. |
| **Durability limits of the sole copy** | After the act, volume `106443278` holds the only copy of every workspace. There is no backup or snapshot of it. Escrow (Doppler passphrase, off-host header) covers key loss, not data loss. On the merge of PR #9348, Terraform declares `prevent_destroy = true` on `hcloud_volume.workspaces_luks` and on `hcloud_volume_attachment.workspaces_luks` (every Terraform plan that would destroy or replace either fails) and `delete_protection = true` on the volume, which is effective only after the post-merge SSH-stage apply (from then Hetzner refuses a console, API or CLI delete, until someone holding a write token lifts the protection). Hardware loss stays open: #5274, #8625. |

## Completion checklist

- [ ] Every `*(fill)*` is replaced with a measured value, not an estimate.
- [ ] Every PENDING-EVIDENCE marker is replaced from the D and forget runs' own output; a field the
  as-run arm cannot produce reads `n/a (<arm>, run <id>)` (added 2026-10-01).
- [ ] Exactly one `result=wiped` row exists for `105149570`, and `target` ≠ `backing` on the rehearsal row.
- [ ] Personal-data fields are counts only.
- [ ] The recoverability row is CLO-attested.
- [ ] `status:` is changed from `template` to `complete` — BEFORE ADR-119 flips to `accepted`.
