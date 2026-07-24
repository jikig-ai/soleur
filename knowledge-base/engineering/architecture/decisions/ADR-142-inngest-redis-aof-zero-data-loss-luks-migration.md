---
title: Zero-data-loss guest-side LUKS migration for the Inngest Redis AOF volume (hcloud_volume.inngest_redis)
status: accepted
date: 2026-07-24
related: [6894, 6588, 6897]
related_adrs: [ADR-140-encryption-posture-as-a-design-time-default, ADR-119, ADR-100, ADR-068]
brand_survival_threshold: aggregate pattern
---

# ADR-142: Zero-data-loss guest-side LUKS migration for the Inngest Redis AOF volume (`hcloud_volume.inngest_redis`)

## Status

accepted

Supersedes the `plaintext-exception` for `hcloud_volume.inngest_redis` in the encryption-posture
ledger (#6894). Mechanism per ADR-119 / ADR-140 (guest-side LUKS is the Hetzner-volume at-rest
control). Depends on ADR-100 (dedicated Inngest host).

Recorded via the `soleur:engineering:cto` agent as the binding architecture decision the issue
requires **before any terraform** (#6894 is P2, highest-sensitivity — the volume holds user data).
The apparatus PR and the operator-gated cutover are separate, downstream, gated deliverables.

## Context

`hcloud_volume.inngest_redis` (`apps/web-platform/infra/inngest-host.tf:314`, `format = "ext4"`,
attachment/mount `:325-328`/`:236-256`) is a **plaintext ext4** block volume mounted at `/mnt/data`,
holding the host-local Redis **AOF** (appendonly file). Per `inngest-redis.conf:3-6`, Inngest's
queue + run-state live in Redis (Postgres holds only config/history), and `:17-19` the AOF "is the
queue's survival mechanism across a root-disk wipe." The AOF payloads are **in-flight job data —
user prompts and agent output** — so this is the encryption-posture ledger's highest-sensitivity
row (`scripts/encryption-posture-ledger.json`, `mechanism: plaintext-exception, tracking_issue:
#6894`).

The **#6895 registry LUKS pattern is FORBIDDEN here.** #6895 (PR #6926) migrated the disposable zot
registry volume via a destroy+recreate `-replace` (fresh raw volume → cloud-init `luksFormat` →
re-fill from GHCR). The registry store is born-fresh and disposable; the inngest AOF is **sole-copy
non-disposable state**. A `-replace` of `hcloud_volume.inngest_redis` is ForceNew → a new empty
volume → **every in-flight job lost** (the #6588 hazard class).

**Inngest cannot be drained to empty.** There is an intake pause (`INNGEST_CUTOVER_QUIESCE` → the
arming route 503s, `inngest-rearm-reminders.sh:18-24`), but armed future reminders sit in the AOF at
arbitrary future fire-times (`inngest-redis.conf:4-6`; `inngest-enumerate-reminders.sh:6-9` fetches
"future-dated AND not yet fired" events). Draining to empty would mean waiting until the last armed
reminder fires — unbounded. So a byte-preserving migration is required; a logical
enumerate/re-arm captures only the reminder subset (not in-flight step state / retries /
`step.sleep`) and is therefore a **canary, not the migration mechanism**.

## Decision

**Additive blue-green migration.** Provision a **second raw (unformatted) LUKS volume** alongside
the live plaintext AOF volume, in the **existing isolated `soleur-inngest` Doppler project**. Cut
over inside an operator-gated maintenance window (reviewer approval on the existing
`github_repository_environment.inngest_cutover`, `inngest-arm-write-token.tf:72`):

1. **Baseline (read-only):** record the armed-reminder count (`inngest-enumerate-reminders.sh`) and
   Redis `DBSIZE`.
2. **Quiesce intake:** set `INNGEST_CUTOVER_QUIESCE` on `soleur-inngest/prd` → arming route 503s;
   new events are cleanly rejected/retried by the SDK, not lost.
3. **Provision the LUKS volume:** the second volume attaches; cloud-init `luksFormat`s the **raw**
   device (guard confirms no `blkid` TYPE signature), opens mapper `inngest-redis`, `mkfs.ext4`,
   mounts at a **staging** path (`/mnt/data-luks`).
4. **Freeze:** `systemctl stop inngest-redis` — a clean shutdown flushes the AOF (a sub-second
   freeze; the volume is bounded small, `inngest-redis.conf:22-30`: `maxmemory 256mb`,
   `auto-aof-rewrite-min-size 64mb`).
5. **Byte-copy:** `cp -a /mnt/data/redis/. /mnt/data-luks/redis/` — source and destination **both
   selected by volume ID**, never by the now-ambiguous `scsi-0HC_Volume_*` glob.
6. **Canary (hard-abort on mismatch):** assert the copied AOF yields `DBSIZE` and enumerate-count ==
   baseline before proceeding. A mismatch hard-aborts the cutover (chosen operational default).
7. **Mount-swap:** repoint `/mnt/data` at `/dev/mapper/inngest-redis` (fstab / mount unit),
   `systemctl start inngest-redis` on the LUKS volume.
8. **Verify (non-destructive):** `/health` 200, `functions >= 1`, reminder-count invariant holds
   (the `inngest-wiped-volume-verify.sh` assertion shape).
9. **Un-quiesce:** clear `INNGEST_CUTOVER_QUIESCE` only **after** verify passes.
10. **Backstop:** the plaintext volume stays attached as the rollback backstop until a later,
    separately-tracked destroy-then-wipe.

Byte-copy under a clean-stop freeze is zero-data-loss because it preserves **everything** (queue,
in-flight step state, retries, armed reminders) exactly — strictly more complete than a logical
re-arm. The retained plaintext volume is the rollback backstop, mirroring the workspaces/git-data
two-copy design.

**No key escrow (git-data-lean shape).** The AOF is transient and self-healing (its contents churn
as jobs complete and reminders fire), and its total-loss recovery is already built and proven
(`inngest-wiped-volume-verify.sh`: functions re-sync from Postgres, the SDK re-registers, and the
sole-copy reminder subset can be enumerated/re-armed). Escrow's specific job — surviving LUKS-header
corruption while the passphrase is intact — has a blast radius here equal to the bounded loss the
queue-with-retry architecture already tolerates on host media death. Escrowing the header would
**add** a sensitive artifact (which, with the Doppler passphrase, yields full plaintext decrypt of
user prompts/agent output) — a net **increase** in confidentiality attack surface for a durability
gain this transient store does not need.

**Template = hybrid, leaning git-data-lean.** From git-data-lean: `random_password` (len 40,
`special=false`, no `ignore_changes`), one `doppler_secret` LUKS key into the **existing** isolated
`soleur-inngest/prd` project read by the **existing** read/write boot token
(`inngest-host.tf:225-230`) — no new token, no `github_actions_secret`, no branch config; the
workspaces CWE-522 "key must not reach the agent container" concern does not apply (the inngest host
never runs agent containers). From workspaces-heavy, only two elements: (1) the LUKS volume has **no
`format` attribute** and the cloud-init guard uses the **`blkid` TYPE discriminator** — "refuse to
format any device carrying a filesystem signature" (`workspaces-luks.tf:154-167`) — mandatory
because the fresh volume is attached alongside the **live populated plaintext** AOF volume; (2)
reuse the existing reviewer-gated `github_repository_environment.inngest_cutover` as the human
authorization on the irreversible freeze.

### Apparatus scope for the code-only PR (inert on merge)

Every net-new resource in `inngest-host.tf` (or a sibling `inngest-redis-luks.tf`) is inert on merge
per `inngest-host.tf:18-24` (none are in the per-PR CI `-target=` list). Zero live mutation on
merge, exactly like #6895:

1. `random_password.inngest_redis_luks` (len 40, `special=false`, no `ignore_changes`).
2. `doppler_secret.inngest_redis_luks_key` → `INNGEST_REDIS_LUKS_KEY` on `soleur-inngest/prd`
   (existing isolated project/config; masked).
3. `hcloud_volume.inngest_redis_luks` — **no `format` attribute** — + `hcloud_volume_attachment.
   inngest_redis_luks` to `hcloud_server.inngest`.
4. Cloud-init LUKS block in `cloud-init-inngest.yml`: git-data-shaped (`doppler run` →
   `cryptsetup luksFormat/luksOpen` piped via stdin, mapper `inngest-redis`) **with** the `blkid`-TYPE
   discriminator guard; mount the mapper at staging `/mnt/data-luks`; device selected by the
   interpolated volume ID; fail loud on an empty key (no unencrypted fallback).
5. Cutover script (`inngest-redis-luks-cutover.sh`) delivered via the infra-config push / `/hooks`
   channel (same as `inngest-wiped-volume-verify.sh`), driving quiesce → stop → byte-copy → canary →
   mount-swap → restart → verify, all device-selected by volume ID, with the emptiness/latch gate
   shape of `inngest-wiped-volume-verify.sh:80-99`.
6. Reminder-count canary via `inngest-enumerate-reminders.sh` (non-destructive invariant; hard-abort
   on mismatch).
7. Mutation-tested guard (`inngest-redis-luks.test.sh`) asserting RED on: a `format` line on the
   LUKS volume; the key written to `soleur/prd` instead of `soleur-inngest`; a cloud-init guard that
   formats on `isLuks`-false without the `blkid`-TYPE check; `luks_passphrase_touched != 0` at
   cutover.
8. Ledger prep: flip `hcloud_volume.inngest_redis` `mechanism` → `luks` with the new
   `device_binding`/`evidence`, and add a retained-plaintext-backstop exception row for the old
   volume (mirroring the `workspaces`/`git_data` plaintext rows), tracked under a new
   backstop-wipe issue.

### FATAL footguns (must be in the apparatus PR body + the cutover runbook)

- **Wrong device.** `luksFormat` or the copy *destination* pointed at the OLD plaintext volume wipes
  the in-flight AOF. Select every device by volume ID from terraform output; the `blkid`-TYPE guard
  is the backstop.
- **Copying while Redis runs** → torn/partial AOF → corrupt restore. Stop Redis (step 4) and verify
  the unit is inactive before the copy.
- **Un-quiescing before verify** (step 9 before step 8) lands new jobs on an unverified backend.
- **Reboot mid-window re-mounting the old volume.** The mount-swap (fstab) must complete atomically
  with the restart so a mid-window reboot cannot auto-start Redis on plaintext `/mnt/data`; mirror
  the reboot-safety `deploy-inngest-bootstrap.sudoers:52-63` already applies to `inngest-server`.
- **Rotation-is-not-rekey.** A `-replace` of `random_password.inngest_redis_luks` mints a new
  passphrase but does NOT rekey the LUKS header; post-backstop-wipe it strands the AOF. The cutover
  gate asserts `luks_passphrase_touched == 0`; real rotation is `cryptsetup luksChangeKey`, never
  `-replace`.

## Consequences

- (+) In-flight user data becomes LUKS-at-rest with **zero job loss**; the ledger row flips
  `plaintext-exception → luks`.
- (+) Reuses existing isolation (`soleur-inngest` project, read/write boot token) and the reviewer
  gate — no new tokens, no branch-config gymnastics, no `github_actions_secret`.
- (+) Code-only PR is inert on merge; all live mutation is operator-gated (matches #6895's
  code-merges / cutover-is-a-separate-gated-event split).
- (−) A retained plaintext backstop volume persists until a tracked destroy-then-wipe (a transient
  plaintext exposure window, ledgered like `workspaces`/`git_data`).
- (−) A maintenance-window Redis stop (sub-second freeze) during cutover; new events 503 and are
  retried by the SDK.
- (−) No escrow means LUKS-header-region corruption strands the current in-flight set — an accepted
  bounded risk equal to host media death, mitigated by re-provision + reminder re-arm.

## Sequencing

Nothing destructive happens live before terraform. The only pre-terraform live action is the
read-only baseline enumerate, which runs as the cutover's first step. The quiesce/freeze/copy/
mount-swap are entirely encoded in the gated cutover window — the code-only PR merges inert, and the
second volume + LUKS + copy only materialize when the operator runs the reviewer-gated `apply_target
=inngest-host` cutover dispatch.

## Open operator items (defaulted; revisit before the cutover)

1. **Backstop-wipe tracking.** The retained plaintext backstop needs its own tracking issue +
   `expires_on`. Defaulted to a fresh `type/chore` tracker with `expires_on: 2026-10-22` (the ledger
   pattern), rather than folding into #6897's plaintext-backstop sweep. Operator may re-home.
2. **Canary abort mode.** Defaulted to **hard-abort** on any reminder-count/`DBSIZE` mismatch
   (recommended). Operator may relax to warn-and-continue (not recommended).
