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

<!-- lint-infra-ignore start -->
<!--
  #7695: `lint-infra-no-human-steps.py` is FILE-scoped under `--changed`, so appending the
  2026-09-03 addendum below pulled this pre-existing paragraph into the diff's scan set and it
  fired. The wrap is a scoping fix, NOT a suppression of a real finding: the paragraph describes a
  reviewer-gated `workflow_dispatch` — the sanctioned route the linter exists to steer people
  TOWARD — and prescribes no SSH, no console, and no host-local command. The one imperative in it
  ("the operator runs the reviewer-gated apply_target=inngest-host cutover dispatch") is a menu
  ack, which `hr-menu-option-ack-not-prod-write-auth` treats as the correct shape.

  Deliberately NOT rewritten to dodge the matcher: the paragraph is load-bearing prose in a dated
  architecture record, and wording it around a lint is how a record stops saying what it means.
-->
Nothing destructive happens live before terraform. The only pre-terraform live action is the
read-only baseline enumerate, which runs as the cutover's first step. The quiesce/freeze/copy/
mount-swap are entirely encoded in the gated cutover window — the code-only PR merges inert, and the
second volume + LUKS + copy only materialize when the operator runs the reviewer-gated `apply_target
=inngest-host` cutover dispatch.
<!-- lint-infra-ignore end -->

## Open operator items (defaulted; revisit before the cutover)

1. **Backstop-wipe tracking.** The retained plaintext backstop needs its own tracking issue +
   `expires_on`. Defaulted to a fresh `type/chore` tracker with `expires_on: 2026-10-22` (the ledger
   pattern), rather than folding into #6897's plaintext-backstop sweep. Operator may re-home.
2. **Canary abort mode.** Defaulted to **hard-abort** on any reminder-count/`DBSIZE` mismatch
   (recommended). Operator may relax to warn-and-continue (not recommended).

## Addendum — 2026-09-03 (#7695): the premise this decision rests on is now MEASURABLE, and when it reads empty the decision is VACUOUS rather than amended

Appended, not edited. Nothing above changes — `## Decision` in particular is untouched, and it
remains binding for every state of the world it was written about. What this addendum records is
that one of its **premises** has become a measured quantity rather than an assumption, and that the
premise can be FALSE.

### The premise

§Context asserts, as the reason the #6895 registry pattern is FORBIDDEN here, that the inngest AOF
is **sole-copy non-disposable state**, and that a `-replace` therefore means "every in-flight job
lost". That is an unconditional claim about the volume, and at the time it was the only reading
available: nothing in the repo could measure how much state the volume actually held.

### What changed

`SOLEUR_INNGEST_SERVER_PROBE` now emits (from `probe_schema=3`; the schema is 8 as of #8017) a `redis_keys` count summed from
`INFO keyspace` across every database, alongside `data_mount_src` (the `findmnt` source of
`/mnt/data`), `data_bytes`, `host_role` and `redis_active`. So the sentence "the volume holds
sole-copy state" is now a proposition with a truth value, on a specific row, from a specific boot.

### The bounded reading

**When `redis_keys` reads 0 on a mount-pinned, identity-pinned, newest-row basis, ADR-142's
sole-copy premise is VACUOUS for that reading — there is no state to preserve, so a
preserve-and-copy migration preserves nothing.** All three qualifiers are load-bearing and none may
be dropped:

- **mount-pinned** — `data_mount_src` must equal the by-id path of the physical volume being
  destroyed (or the mapper, post-recut). `redis_keys` is a statement about a Redis *process*; the
  recut destroys a *block device*. Today's mount is `mount … || true` with `nofail`, so a failed
  mount leaves `/mnt/data` on the ephemeral root disk and Redis reports an empty store **while the
  volume holds a populated AOF**. Without this pin the emptiness claim is about the wrong object.
- **identity-pinned** — `inngest-bootstrap.sh` is the SHARED renderer for the dedicated host and
  the co-located web host, so an unpinned read can be a fact about a machine that is not this one.
- **newest-row** — a `boot_id` equal to the newest row's, or "dark and empty" can be a fact about a
  host that no longer exists.

### Why this BOUNDS the decision rather than amending it

The two decisions govern **disjoint worlds**, and the gate decides which world you are in at
dispatch time rather than at authoring time:

- `redis_keys > 0` (or any unreadable/unpinned reading) ⇒ ADR-142 governs, unamended. The
  destructive path is REFUSED OUTRIGHT — and note that enumeration is then unavailable too, because
  `inngest-enumerate-reminders.sh` queries `127.0.0.1:8288`, which is not bound on a dark host.
  Non-empty AND non-enumerable means preserve-and-copy is the only lawful route.
- `redis_keys == 0` under all three pins ⇒ there is nothing for the byte-copy to carry, and the
  cheaper destructive recut is available. ADR-199 governs that world and cites this addendum as its
  precondition.

An amendment would have widened ADR-142's own decision to sometimes permit a destroy, which would
have made the sole-copy protection conditional on a reader's judgement. Bounding it instead leaves
ADR-142 categorical and puts the conditionality in a gate that must MEASURE before it may proceed.

### Recorded BEFORE the arm can open, deliberately

This addendum lands in the same merge as the apparatus and the gates — before any dispatch exists
that could act on the reading. A record written after a destructive action would be a
justification; written before, it is a precondition that the gate's twenty predicates enforce.
`tests/scripts/lib/inngest-host-dark-gate.sh` is where those pins are executable.

## Amendment — 2026-09-18 (#6894): the preserve-and-copy route is BUILT, and it is additive rather than in-place

This decision said what must happen ("provision a second volume, quiesce, copy bytes, swap the
mount") and left the shape of it open. The apparatus that implements it made four choices the
decision did not dictate. They are recorded here because each one closes a failure this estate has
already paid for, and because a future reader comparing the code to this ADR would otherwise read
them as drift.

### 1. ADDITIVE, not in-place: the plaintext volume survives the swap

The second volume (`hcloud_volume.inngest_redis_luks`) is created and attached ALONGSIDE the live
one, and the live one is neither destroyed nor detached by the cutover. The swap is a mount move,
so the rollback is a mount move plus a reverse copy — not a restore from a snapshot taken at an
unknown moment.

The cost is a **plaintext copy of the AOF remaining attached** after the cutover, which is the exact
thing this ADR exists to retire. That is deliberate and bounded: it is the rollback backstop for the
window in which a rollback is plausible, it is tracked with an expiry in **#8285**, and the store
actually being on the wrong volume is DETECTED (`logtail_exploration_alert.inngest_luks_wrong_volume`,
below) rather than assumed.

### 2. The authority is a POINTER in Doppler, never a signature on a device

`INNGEST_LUKS_ACTIVE_VOLUME_ID` on `soleur-inngest/prd` names the volume that holds the store. The
boot resolver reads it first and treats a LUKS signature only as corroboration; a pointer naming an
absent device REFUSES rather than falling through to the plaintext arm.

The reason is measured, not stylistic: a root-disk marker does not survive a host replace (#7228 —
the flip's done-owner marker, and the stranding it caused), and an unprivileged `blkid -p` returns
rc 2 on a LUKS device, which is the SAME answer it gives for "no signature at all". A design that
authorises by signature therefore cannot tell "encrypted" from "could not look", and the wrong
answer wipes user data. Doppler outlives the host; that is the whole argument.

### 3. The trigger is a SEPARATE flag from the flip's, with its own FSM

`INNGEST_LUKS_CUTOVER` (armed → copying → copied → swapped → done, plus rollback → rolled-back and a
terminal aborted), polled by `inngest-luks-cutover.service` every 30s. It is NOT
`INNGEST_CUTOVER_FLIP`, which owns the one authorized `FLUSHALL`. A copy that preserves data does not
belong behind the flag that destroys it: sharing them would mean one terminal value authorising two
opposite actions, and the wrong one is unrecoverable.

Consequence for Fork L, recorded because it is easy to undo by accident: the copy is the WHOLE mount,
not `redis/`. The flip FSM's flush latch lives at `/mnt/data/inngest-cutover/flip-done.latch`, and a
swap onto a device without it reads, to that latch, as a recut — which would re-open a second
`FLUSHALL` against a populated store. T2 names that path explicitly.

### 4. The copy is PROVEN equal before the swap, and again before the rollback

T2 compares listing, per-file sha256 and total bytes over a frozen source, and runs a read-only
`redis-check-aof` on the copy. Each reading's READABILITY is a separate predicate from its
comparison — an unreadable tree prints a sentinel rather than an empty listing that would compare
equal to another empty listing. The rollback runs the same machinery with the roles reversed, so
going back is exactly as data-safe as going forward, including writes taken after the cutover.

### What this amendment does NOT change

The decision itself. `-replace` of `hcloud_volume.inngest_redis` remains forbidden while the store is
populated; the 2026-09-03 addendum's bounding (an empty, pinned, newest-row reading hands the world
to ADR-199) is untouched. This amendment describes the route this ADR always required, now that it
exists.

### Where it lives

| Element | Path |
| --- | --- |
| On-host FSM | `apps/web-platform/infra/inngest-luks-cutover.sh` (+ `.service`, `.timer`) |
| Its suite | `apps/web-platform/infra/inngest-luks-cutover.test.sh` |
| Boot resolver (pointer-authoritative) | `apps/web-platform/infra/cloud-init-inngest.yml` — both the first-boot runcmd stage and `/usr/local/bin/inngest-luks-open.sh`, which is a `write_files` payload embedded in that same file rather than a file in this repo |
| Operator verbs | `op=luks-cutover` / `op=luks-rollback` in `.github/workflows/cutover-inngest.yml` + `scripts/cutover-inngest.sh` |
| Wrong-volume alert | `apps/web-platform/infra/betterstack-logs-alerts.tf` (ships paused; armed post-cutover) |
| Runbook | `knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md` |
| Backstop retirement | #8285 (expires 2026-10-22) |

## Amendment — 2026-09-21 (#8296): the cutover ran, and apparatus scope item 8 named the wrong row

Appended, not edited. Nothing above is changed.

### The cutover was observed

The additive cutover described in the 2026-09-18 amendment ran on 2026-09-20. The terminal
`SOLEUR_INNGEST_LUKS_CUTOVER` row landed at 15:29:10Z (`reason=cutover-complete`, `flag=done`,
`phase=swapped`, `exit_code=0`, `k_freeze=1366`, `e_freeze=1355`). The first post-cutover
`SOLEUR_INNGEST_SERVER_PROBE` row from `host_role=dedicated`, at 15:36:40Z, reads
`data_mount_src=/dev/mapper/inngest-redis`, `data_mount_devid=scsi-0HC_Volume_106903269`,
`redis_active`, 1437 keys. The store now lives on `hcloud_volume.inngest_redis_luks`.
`hcloud_volume.inngest_redis` is attached and intact as the plaintext rollback backstop, retired
under #8285 (expires 2026-10-22).

The record followed the detector, not the other way round. PR-1 of #8296 armed
`logtail_exploration_alert.inngest_luks_wrong_volume` on the push apply of `b53173a04`
(run 35605929787), and the alert read back `paused=false` at 2026-09-21T14:18:56Z. Only after
that did PR-2 flip the ledger.

### Correction: apparatus scope item 8

Item 8 of "Apparatus scope for the code-only PR" says to flip `hcloud_volume.inngest_redis`'s
`mechanism` to `luks` and add a backstop exception row for the old volume. That is the opposite of
what the 2026-09-18 amendment requires, and it would have recorded the plaintext backstop as
encrypted. The additive route never encrypts `hcloud_volume.inngest_redis`; it copies the store onto
a second volume. So the row that flips is **`hcloud_volume.inngest_redis_luks`**, and
`hcloud_volume.inngest_redis` keeps `mechanism: plaintext-exception` and is rewritten as the
retained backstop, with its `expires_on` unmoved. PR-2 of #8296 did exactly that. Read item 8
through this correction.

### What this amendment does NOT change

The decision, and the status. The ledger row keeps `live_verification` at `unavailable:`: the probe
row proves which device backs `/mnt/data`, not that it is crypto_LUKS.

Two earlier lines of this ADR now read through this amendment. The Status paragraph's "Supersedes the
`plaintext-exception` for `hcloud_volume.inngest_redis`" is wrong for the same reason as item 8:
that row keeps its exception as the backstop, and it is the sibling row whose exception went away.
The "Where it lives" row's "(ships paused; armed post-cutover)" is still true as history: the alert
did ship paused and was armed after the cutover (ADR-218, 2026-09-21 amendment). One known gap in
that detector is open: a probe pipeline that goes silent reads as healthy (`treat_as_zero`), tracked
in #8516.

## Addendum — 2026-10-08 (#8285)

Appended, not edited. Nothing above is changed.

**Status of this addendum: adopting.** It describes the state this decision reaches when #8285 is
done, and is written before that happens so the design is recorded before the destructive steps run.
It flips to landed in the convergence PR (PR B), and only after the Hetzner API shows volume 106261946
gone. Until then every sentence about the retirement below is a plan, not a fact. Ref #8285, Ref #6894.

### What this addendum decides

The plaintext backstop `hcloud_volume.inngest_redis` (Hetzner id 106261946) is retired before its
ledger exception expires on 2026-10-22: detached, zeroed with a read-back, and deleted through
Terraform. Four decisions shape how.

**D1. The cloud-init template input is pinned to a literal, so the host is not replaced.**
`inngest-host.tf` feeds `inngest_volume_id = hcloud_volume.inngest_redis.id` into the cloud-init
template, so deleting the volume would change `user_data` and force-replace the sole scheduler (the
root-disk decision tracked in #8620). Instead the input becomes the literal current id string
`"106261946"` in a local, so the rendered `user_data` is byte-identical and `hcloud_server.inngest`
plans no change. The pin also removes the only graph edge between the server and the volume, which
makes a targeted destroy of the volume safe. The dead plaintext resolver arm stays in `user_data`
until the next replace that is already scheduled for another reason (#9786).

**D2. Erasure runs on a short-lived throwaway server, not on the Inngest host.**
The detached volume is attached to a Terraform-managed, count-gated, deny-all-inbound Hetzner server
that zeroes it with `blkdiscard -z`, reads it back with O_DIRECT and posts a
`SOLEUR_INNGEST_BACKSTOP_WIPE` evidence row (counts and identity only) to Better Stack. The live LUKS
volume is never attached to that server, so a mis-resolved device cannot reach the live store. The
evidence is self-attested guest-side logical erasure, not physical erasure, and the destruction record
says so.

**D3. Detach, wipe, teardown and destroy are four gated phases of one dispatch, and Terraform performs
the deletion.** `apply_target=inngest-backstop-retire` with a `phase` input, converted from the
`inngest_volume_recut` chassis (reviewer-gated `inngest-cutover` environment, typed confirm,
`expected_inngest_volume_id` id-pin, exact plan-shape gate). The orphaned addresses are destroyed by
`-target` (no `-destroy` flag), and state converges in the same apply, so there is no separate forget
step. The `[ack-destroy]` route is not used: it reaches only the per-merge `-target` apply, which never
targets these addresses.

**D4. Fallback if the wipe has not succeeded by 2026-10-17.** The decision point is the operator's and
the CLO's, never made silently. A provider delete without zeroing is defensible only as a
CLO-attested downgrade, recorded as "provider delete only, no overwrite, logical erasure not evidenced
by read-back". It is preferred over letting a non-extendable Art. 32 exception expire. The `destroy`
phase accepts either a `wipe_run_id` (evidence) or `erasure=provider-only` with a
`clo_attestation_ref`.

### Consequences this addendum records

- **`op=luks-rollback` ends at the `detach` phase.** Once the volume is detached there is nothing for
  the rollback to copy back from. The operator verb stays listed until PR B retires it; the runbook
  carries a banner at §5a.
- **The live LUKS volume becomes the only copy of the store, and `INNGEST_REDIS_LUKS_KEY` in Doppler
  `soleur-inngest/prd` its sole opener.** Losing that key is then total loss (counsel review O4,
  `knowledge-base/legal/audits/2026-09-counsel-review-8248.md`). This sharpens the "No key escrow"
  stance above, which rests on the AOF being transient and self-healing while armed reminders can
  carry unbounded future fire-times.
- **AP-009 (never delete user data) tension.** The deleted object is a stale second copy, not the live
  data. The live copy is evidenced before every phase (Doppler flag `done`, the pointer naming
  106903269, that volume attached, a fresh probe row on it) and the destroy is gated on it, which is
  why the principle holds.
- **Orphan window.** From PR A's merge until the `destroy` phase the two removed Terraform addresses
  are state-only; the scheduled drift plan will report two deletes, by design. Nothing auto-applies
  them, and an untargeted apply of the root must not be run in that window.

### Alternatives considered and rejected

| Option | Why not |
|---|---|
| Host replace carrying a re-templated cloud-init | Replaces the sole scheduler for a value that can be pinned; forces the #8620 root-disk decision onto an unrelated change. |
| On-host wipe FSM state in `inngest-luks-cutover.sh`, with an image release, a pin bump and a host replace | Same host as the live LUKS volume, so device mis-resolution can reach it; needs a replace and an image release on a 14-day clock; the script would ship in the permanent image. |
| `lifecycle.ignore_changes = [user_data]` on the server | Breaks the deliberate replace-to-reprovision design (ADR-100) for every future cloud-init change. |
| Terraform `-destroy -target` with the declarations kept | Destroy mode expands to dependents; only safe after D1, and leaves a declared-but-absent window. The orphan `-target` apply has the same effect without the flag. |
| Bespoke Hetzner-API delete plus `terraform state rm` workflows (the web-1 shape) | Two new privileged workflows and suites for effects Terraform performs under an existing gate. |
| Delete without zeroing as the default | Kept only as the D4 fallback, as a CLO-attested downgrade with weaker evidence. |
| Mount the volume read-write on a web host to zero it | Touches production web hosts; rejected. |
| A final snapshot before deleting | Creates a new plaintext copy; removed from the issue. |

### What this addendum does NOT change

The decision, its encryption mechanism, or the 2026-09-18 and 2026-09-21 amendments. The ledger row,
the Article 30 cells, the C4 model and the probe stay as they are until PR B, after the Hetzner API
read-back. The Art. 5(2) record for this destroy is
`knowledge-base/legal/audits/inngest-aof-backstop-destruction-record.md`, committed as a template with
every measured field `PENDING-EVIDENCE`.

## Addendum — 2026-10-09 (#8285, review round 1 of PR #9784)

Appended, not edited. The 2026-10-08 addendum above is unchanged; where this one narrows it, it says so.
**Status: adopting**, on the same terms as that addendum: every sentence about the retirement is a
plan until the Hetzner API shows volume 106261946 gone. Ref #8285, Ref #6894.

### What the review round decided

**E1. The wipe evidence is not forge-proof, and the records say so.** The 2026-10-08 addendum (D2)
calls the evidence self-attested, which stands. What it did not say, and the destruction record's first
draft got wrong, is what the destroy gate's binding buys. The evidence row reaches Better Stack with the
ingest token that other hosts share, so a holder of that token can write a row with any `host`. The
binding to the wipe run's nonce, the volume id, the size and the run's start time makes a **stale or
replayed** row fail; it does not make a forged one fail. No new secret is introduced to change that.
Instead the destroy precondition corroborates from the provider: it reads Hetzner's action history
for volume 106261946 (read-only token) and requires a successful `attach_volume` to a server that is
neither the live Inngest host (169426216) nor absent, finished not before the wipe run's start, and a
later successful `detach_volume`. That ties the evidence to a real attach on a real wipe host; it does
not prove the zeroing, which stays a guest-side claim. The evidence funnel also pins the emitter fields
the wipe host sends (`host`, `shipper`) so a row from another source fails the match.

**E2. The D4 attestation is a specific comment, not a reachable URL.** The 2026-10-08 D4 text accepts
`erasure=provider-only` with a `clo_attestation_ref`. That reference is narrowed to exactly
`https://github.com/jikig-ai/soleur/issues/8285#issuecomment-<digits>`, fetched through the GitHub API,
whose author must be an owner, member or collaborator and whose body contains the volume id. Any other
host or shape is refused. A downgrade that is the CLO's to make has to be a record on the tracker, not
whatever returns HTTP 200.

**E3. The untargeted whole-root plan proves the host is untouched; it does not police the rest of the
root.** It stays as the D1 proof on live state, but in untargeted mode it requires only: the server and
the LUKS pair are each exactly one no-op entry; no positive entry carries the live id 106903269; entries
for the retired and wipe addresses are within the phase's authorized set. Unrelated resources are
ignored there, so unrelated drift cannot block a phase, including the D4 path on its deadline. The
targeted plan that follows stays exact.

**E4. `teardown` is exempt from the live-store gate; `detach`, `wipe` and `destroy` keep it.** A leaked
wipe host must always be cleanable, and teardown can only delete the two wipe addresses.

**E5. The state-only reconcile is gated.** Where Hetzner says an object is gone but state lists its
address, a single-address refresh-only apply drops it, and only if `terraform state list` before and
after differs by exactly that one address.

**E6. Rollback ends at the `detach` phase or at the first host replace after PR A merges.** PR A removes
the attachment declaration, so a host replaced after it boots without the backstop attached; the
rollback then has nothing to copy back from even if `detach` has not run.

### The orphan window, restated

From PR A's merge until `destroy`, the two removed addresses are state-only orphans. The scheduled drift
plan (twice daily) reports two deletes by design and must not be applied. An untargeted `terraform apply`
of the root in that window would delete both orphans unwiped. No CI path applies the root untargeted,
and this PR amends the per-merge apply's HALT text so it no longer directs an operator to an untargeted
apply. No Terraform resource is added to guard the window: the control is the runbook
(`inngest-luks-cutover-6894.md` §5b, "The window between PR A's merge and `destroy`").

### Chain behaviour of the orphan `-target`

Measured on Terraform 1.9.8 on a local backend: with the attachment depending on the volume and the
server, `plan -target` on the attachment plans only the attachment delete, and `plan -target` on the
volume plans only the volume delete. The workflow pins 1.10.5, so the experiment is re-run on that
version before the first dispatch. If the chain differs, the plan-shape gate aborts with no mutation.

### C4 note

`knowledge-base/engineering/architecture/diagrams/model.c4` (`inngestRedis`) still says the plaintext
backstop "stays attached and intact". That is true until the `detach` phase and false after it, and the
description is generated into `model.likec4.json`, so it is rewritten once, in PR B, with the
regeneration, rather than in PR A before any phase has run.

### What this addendum does NOT change

D1 through D4 of the 2026-10-08 addendum, the decision, its encryption mechanism, or the earlier
amendments. A wipe rehearsal and a LUKS key-or-header continuity proof are not built here; both are
recorded as operator-facing prerequisites in the runbook and as untaken options in the feature's
`decision-challenges.md`.
