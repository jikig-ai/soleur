---
title: Encrypt the live /workspaces volume additively — never replace the host that cannot be rebuilt
status: adopting
date: 2026-07-17
amends: none
supersedes: none
issue: 6588
---

# ADR-119: LUKS at rest for the live `/workspaces` volume

**Ruled by:** `soleur:engineering:cto`, 2026-07-17, per issue #6588's explicit routing mandate
(*"Do not start with terraform… The design question belongs to `soleur:engineering:cto`"*).

`status: adopting` → flips to `accepted` on soak-pass after the cutover.

## Context

`hcloud_volume.workspaces` (`server.tf`) holds every user's checked-out repository as plain ext4.
Three published legal documents — `docs/legal/{privacy-policy,gdpr-policy,data-protection-disclosure}.md`
and their Eleventy mirrors — assert it is LUKS-encrypted. The operator's decision, taken three times
and most recently on 2026-07-17 with the counter-arguments in hand, is to **make the claim true rather
than retract it**.

Five facts constrain the design. Each was verified against the repo, not inherited from the issue.

1. **LUKS at Hetzner is guest-side.** `git-data-luks.tf`: *"encryption-at-rest is GUEST-SIDE LUKS, NOT
   an hcloud_volume attribute. There is no hcloud 'encrypted' flag."* **The issue's central hazard —
   "`format` is ForceNew ⇒ a naive apply destroys the volume" — is a red herring. `format` never
   changes.**
2. **The real data-loss mechanism is the `isLuks` guard inverting.** `cloud-init-git-data.yml`:
   `if ! cryptsetup isLuks "$DEV"; then luksFormat`. On a **populated plaintext** device `isLuks` is
   false ⇒ `luksFormat` ⇒ live user code wiped. The guard is safe in the precedent only because
   git-data's volume is born fresh. It must never be pointed at the live volume.
3. **The data is sole-copy.** `refs/checkpoints/*` is pushed by no refspec; `session-sync.ts`
   autocommits only `knowledge-base/**`; and `provisionWorkspace` — the signup/auth-callback path —
   does `git init` with no `remote add`. ADR-068 §1's *"GitHub remains the durable rehydration
   source"* does not hold for signup-provisioned workspaces. **There is no second copy anywhere.**
   The hypothesis "re-clone from GitHub instead of rsync" was raised and refuted on this evidence.
4. **web-1 cannot be rebuilt.** `cx33` is `available = false` in all three EU datacentres (live
   Hetzner API 2026-07-16; corroborated at `tests/scripts/test-stock-preflight-gate.sh`). A
   `-replace` of `hcloud_server.web["web-1"]` would **destroy the sole prod host and then fail to
   recreate it**, leaving the platform unrebuildable.
5. **There is no load balancer and no peer.** `app.soleur.ai` is a hard-pinned singleton A record to
   web-1. web-2 has never served user traffic and its volume is empty.

## Decision

**Encrypt the live `/workspaces` volume by attaching a fresh LUKS volume ADDITIVELY, freezing writers
by stopping the app container, two-pass rsync with filesystem-level verification, repointing the
mapper to `/mnt/data`, and retaining the plaintext volume as the rollback backstop — never by
replacing the host.**

Single-host (web-1 only). Bounded downtime ≤20 min (target ~10; ≤2h hard abort). Adapt the *shape* of
`git-data-cutover.sh`; do **not** build `soleur-drain.service`.

### (a) The freeze is a container stop — but stop is NOT strictly stronger than drain

`soleur-drain.service` must not be built. A drain sheds traffic from one fleet member while peers
absorb it; there is no LB and no peer (fact 5), so for a singleton the distinction collapses.

**Correction to the original ruling.** The ruling claimed *"stop is strictly stronger than drain."*
That is true for **availability quiescence** and **false for write-atomicity**. A drain lets in-flight
work *finish*; a stop *interrupts* it. `git-data-cutover.sh` says exactly this — *"stop new turns; let
in-flight finish."* `docker stop` defaults to a **10s** grace then SIGKILL, so an agent mid-`write()`
leaves a **truncated file** that is then faithfully rsynced and certified correct. `fuser` cannot see
a dead writer; the verify cannot see a quiesce failure.

Therefore: `docker stop -t 120`, plus halt `webhook.service` so a CI deploy cannot restart the
container mid-rsync. **Post-stop interrupted-write asserts are blocking** — no `.git/index.lock`, no
`objects/pack/tmp_pack_*`, no `gc.pid` ⇒ abort rather than copy wreckage. The straggler assert is
`lsof +D /mnt/data` (`lsof +f -- /mnt/data` is malformed). `git gc --auto` is a verified non-risk: it
dies with the PID namespace, and `refs/checkpoints/*` are gc roots.

#### Addendum 2026-07-19 (#6588 freeze-quiesce) — the quiesce set was incomplete

The enumeration above (`docker stop -t 120` + `webhook.service`) is **not the full set of
`/mnt/data` writers**, and this ADR asserting it was is what let two real freezes abort.

On 2026-07-19 the first two REAL freezes (runs 29676994044 and 29687729540) each safe-aborted on the
C1 byte-identity verify with exactly **one** difference:

```
SOLEUR_WORKSPACES_LUKS_VERIFY_DIFF count=1 idx=0
  icode=>fcst...... path=redis/appendonlydir/appendonly.aof.94.incr.aof
```

`>fcst......` = checksum + size + mtime differ — the signature of a file being appended to *during*
the copy. **`inngest-redis.service` persists its AOF to `/mnt/data/redis`** (`inngest-redis.conf`:
`dir /mnt/data/redis`, `appendonly yes`) and is a **systemd unit, not a container** — so
`docker stop "$CONTAINER"` never touched it and Redis appended straight through the freeze, the
pass-2 delta rsync, and the verify. DP-6 auto-rolled back both times; no data was lost.

The C1 gate was **correct**: copying a live-appending journal would have put a torn AOF on the
encrypted volume and silently lost armed Inngest reminders. The writer was not quiesced.

**Restated quiesce set** (`QUIESCE_UNITS` in `workspaces-cutover.sh`, a single declaration point):

| Unit | Quiesced? | Why |
|---|---|---|
| `webhook.service` | yes, first | a CI deploy must not restart the container mid-rsync |
| the app container | yes, `-t 120` | C8 drain (unchanged) |
| `${CONTAINER}-canary` | yes, best-effort | shares the same `-v /mnt/data/workspaces:/workspaces` bind mount; an aborted deploy leaves it running |
| `inngest-redis.service` | **yes (new)** | writes `/mnt/data/redis`; `TimeoutStopSec=30` gives a graceful SIGTERM + AOF flush |
| `orphan-reaper.{timer,service}` | **yes (new)** | a 6-hourly **root `rm -rf`** over `/mnt/data/workspaces/*.orphaned-*` with **no** `RequiresMountsFor`. Firing between the delta rsync and the verify makes `rsync --delete --dry-run` emit a `*deleting` line — the *identical* C1 abort signature as the AOF, on a 6h duty cycle against a ~20 min freeze |
| `luks-monitor.{timer,service}` | yes, best-effort | armed by a *prior* successful cutover; `luks-monitor.service` is `RequiresMountsFor=/mnt/data`, so a mid-run instance holds the mount and trips the now fail-closed G4 **Superseded 2026-09-27 (#8706):** Terraform arms it now (`terraform_data.luks_monitor_install`), not a prior cutover. And the service is ordering-only now (`After=local-fs.target mnt-data.mount`), not `RequiresMountsFor=`. The quiesce still stops the pair, and G4 still catches a mid-run instance that holds the mount |
| `inngest-server.service` | **no — deliberately** | `ProtectSystem=strict` + `ReadWritePaths=/var/lib/inngest /var/lock` means it provably cannot **write** `/mnt/data`; `TimeoutStopSec=180` would burn 3 min of a ~10 min freeze for zero quiescence benefit. Reconciled post-freeze instead (clear failed state, start only if inactive). The write claim is **not** a hold claim — `ProtectSystem=strict` makes the mount read-only, not invisible — so the *hold* axis is delegated to G4 by design. |

Timers are stopped as **`<timer> <service>` pairs**: stopping a `.timer` only prevents future
triggers, it does not stop the instance the timer already launched.

**The quiesce set is not a property of the units, it is a property of the mount.** Both misses above
were units nobody thought of as "part of the cutover". The enumeration to re-run when adding any
host-side unit is: *what else opens, writes, or deletes under `/mnt/data`?*

**The straggler assert must be fail-closed and self-delivering.** `lsof +D /mnt/data` was wrapped in
`if command -v lsof`, so on a host without `lsof` the entire gate silently vanished — false
assurance, and the reason the unquiesced writer was never named. `lsof` is provisioned by no repo
artifact, so making the gate fail-closed without also *delivering* it would guarantee an abort on
the next real freeze. Both halves are required: `ensure_lsof` (on-demand install, mirroring
`ensure_aws`; the cloud-init package covers future hosts only) **and** an abort — never a skip — if
it is still absent. The predicate must also carry **no pipe**: `lsof +D … | grep -q .` under
`set -o pipefail` returns 141 when `grep` closes the pipe early and the producer takes SIGPIPE, so
`&& die` never fires — a *size-dependent fail-open* that evaporates precisely when there are many
stragglers. And holders are emitted (`SOLEUR_WORKSPACES_LUKS_FREEZE_HOLDER`) **before** `die`, the
same evidence-survives-the-abort constraint #6604 established for C1.

**G4 is re-asserted, not sampled once.** `assert_mount_quiesced` runs at the freeze *and* again
immediately before `verify_byte_identity`. A single sample cannot see a writer that starts in the
~10 minutes between them — which is exactly the orphan-reaper's window.

**G4 carries a positive control.** `lsof` exits 1 *both* when it finds nothing and when it errors,
and writes diagnostics only to stderr, so `"$(lsof … 2>/dev/null || true)"` reads *"the probe
failed"* as *"the mount is clean"*. The assert therefore holds its own fd under `$MOUNT` and
requires the probe to report it: empty output then **proves** the scan reached the mount instead of
assuming it. Mirrors `verify_byte_identity`, which captures stdout/stderr separately and treats a
probe error as fail-closed for the same reason.

**Three restore sites, not two** — and the two quiesced units fail *differently* on an unmounted
`$MOUNT`, which is why `resume_writers()` gates on `mountpoint -q` rather than relying on unit
properties:

- `inngest-redis.service` carries `RequiresMountsFor=/mnt/data`, so it fails **safely** — systemd
  refuses to start it and it lands in `failed`, outliving the run.

  > **Superseded 2026-09-27 (#8706):** "systemd refuses to start it" is not what
  > `RequiresMountsFor=` does. It is Requires-strength: starting the unit while `/mnt/data` is
  > unmounted makes systemd START `mnt-data.mount`, which mounts whatever `/etc/fstab` names. The
  > unit lands in `failed` only if that mount itself fails. On web-1 the fstab can name the
  > superseded plaintext volume. The #8706 review made `luks-monitor.service` ordering-only for this
  > reason (`After=local-fs.target mnt-data.mount`, the `inngest-cutover-flip.service` precedent,
  > #7228). `resume_writers()`'s `mountpoint -q` gate is what actually keeps writers off an
  > unmounted `$MOUNT`.
  >
  > **Qualified 2026-09-28 (#9045):** "the fstab can name the superseded plaintext volume" does not
  > hold as stated. Apply run 36340195638 printed web-1's `/mnt/data` fstab source as the literal
  > glob `/dev/disk/by-id/scsi-0HC_Volume_*`, the 2026-03-17 first-boot line. systemd does not expand
  > it, so it names no device at all. The real hazard is a reboot into emergency mode, tracked in
  > #9123.
- `webhook.service` carries **no** `RequiresMountsFor`, only `ReadWritePaths=/mnt/data`, so it
  starts **successfully onto the bare root-disk mountpoint directory**. It is the CI deploy
  receiver, so a deploy landing during the incident writes user data into the root filesystem,
  shadowed the instant the volume is remounted. That is the dangerous one, and it is precisely the
  trap `inngest-redis.service`'s own `RequiresMountsFor` comment was added to prevent.

The three sites are the success path, `rollback()` (the EXIT trap and `ROLLBACK=1`), and the
dead-man `systemd-run` command — whose restore sequence is **derived from `_quiesce_list`** and
gated on the remount succeeding, because it is the one that runs **unattended**.

**The canary proves the mount, not just the process.** `/health` returns 200 *unconditionally* and
never touches `$MOUNT` (`server/readiness.ts` states the no-mount-coupling invariant explicitly), so
it cannot fail on an empty or unmounted volume — if the mapper mounts but `$MOUNT/workspaces` is
absent, docker auto-creates an empty bind source and a cutover serving zero user data reports green.
`app_canary` therefore also asserts `/internal/readyz` (`workspaces_writable` + `workspaces_populated`),
and runs **before** `disarm_dead_man` so an app-level failure still has the unattended backstop.

> **Superseded 2026-09-28 (#9045):** `app_canary` no longer runs before the disarm. The single
> disarm now sits at the host-canary pass, before `docker start`, so the dead-man guards the freeze
> window only. An app-level failure after `docker start` is fix-forward: `cleanup()` rolls forward on
> the LUKS mount and pages. See the
> [2026-09-28 addendum](#addendum-2026-09-28-the-dead-man-guards-the-freeze-window-only-9045).

**`readyz` proves a FLOOR, not an INVENTORY (#6807).** `readiness.ts:81` is
`countWorkspaceDirsAt(root) > 0`, and `isWorkspacesWritable` write+unlinks **one** probe file at the
root. A cutover that preserved **1 of 8** sole-copy workspaces therefore returns `ready=true`.
Certifying a cutover needs a **separate inventory count** compared against a persisted baseline —
which is why `luks-monitor.sh` now carries a host-side count (exclusions mirrored from
`session-metrics.ts`) that fails **closed** when the baseline is absent, and why the cutover persists
`WORKSPACES_COUNT` at the G3 data gate. Never let prose imply `ready=true` means the inventory survived.

**This reasoning binds the OFF-HOST VERIFY surface too, and did not (#6807).** The same argument was
implemented in the cutover's canary and never swept into `workspaces-luks-verify.yml`, which asserted
200 on a no-route health path and was structurally incapable of passing — so the runbook §5 gate was
dead. Both probes are now retry-bounded (the mapper mounts and `docker start` returns before Node
listens, so a single-shot probe races container boot), and both live in one shared helper.

**The 2026-07-20 cutover is the worked example of why the canary must not abort silently.** It
landed, ran ~27 minutes, aborted at `app_canary` on a Cloudflare 521 — *before* `disarm_dead_man` —
and the dead-man then remounted the retained plaintext over a healthy LUKS mount, stranding those 27
minutes of sole-copy writes. Nothing paged: the `/health` arm called a bare `die` and emitted
nothing, a *successful* dead-man remount emits no marker, and the dead-man's own restart chain
failed, leaving the daily monitor unarmed. See **#6812**. The `status: adopting` above is therefore
still accurate — at-rest encryption is **not** in effect on web-1 as of 2026-07-21.

### (b) Rollback is the retained plaintext volume — and the "one-way door" framing is wrong

No flag-flip analogue exists (`/workspaces` has no `GIT_DATA_STORE_ENABLED` equivalent) and GitHub is
not a backstop (fact 3).

**Correction to the original ruling.** The ruling said rollback is lossless inside the freeze and
that *"rollback authority expires at canary-pass — this is a one-way door."* **The lossless/lossy
dichotomy is false**, and stating it as a one-way door will make an operator refuse a rollback they
should take. The LUKS volume physically retains every post-cutover write, so a post-canary rollback is
**reconcilable, not impossible**: remount the retained plaintext volume **read-only at a distinct
path** for a byte-exact T0, and the door becomes "restore T0 + replay from LUKS."

**The rollback door closes at `docker start`, ~30s earlier than the ruling implies** — the app writes
on boot. So the host-level canary (`blkid` / `findmnt` / `mountpoint` / `cryptsetup status`) runs
**before** `docker start`, and `webhook.service` resumes only after canary-pass.

**Do not take a pre-cutover Hetzner snapshot.** A retained plaintext snapshot re-creates the exact
exposure this ADR closes. (COO, independently: *"it manufactures an indefinitely-retained unencrypted
copy of user source code inside the very issue that exists to eliminate them."*) The additive design
already yields a two-copy state; the old volume **is** the backup, and unlike a snapshot it is a live,
mountable device the cutover **rehearses**. This satisfies the CPO's blocking C3 without a snapshot.

**The retained volume is DETACHED, not attached-unmounted.** Unmounted is hygiene, not a control:
`dd if=/dev/sdb | strings` still recovers everything. Detached collapses the root-compromise read path
*and* makes the device-glob class structurally unable to remount it. Re-attach for rollback is one API
call. Detached-retained strictly dominates at zero cost.

### (c) Bounded downtime is justified; budget ≤20 min

The #5887 norm permits downtime with explicit justification + a bounded window + sign-off.
Justification: the zero-downtime path needs a load balancer with no implementation and no ADR (#6459),
and is impossible anyway given fact 4 — against a population of one operator and zero beta users. The
bulk rsync runs **live** (no downtime); only delta + verify + repoint + restart + canary sit inside
the freeze, over a quiesced tree well under 20 GB.

### (d) web-2 is out of scope — but this work is NOT blocked (supersedes the original ruling)

**The original ruling's premise is dead.** It held that this work waits for PR #6568, after which
web-2 leaves `var.web_hosts` and the AC means web-1 only. **#6568 merged as docs-only** (`cb93c2948`,
*"state the hosting locative at EU level"*) with zero `.tf` files; **web-2 survives** and
`var.web_hosts` still contains both. The teardown is **#6538 — an open issue with no PR**. Blocking on
it would block on a PR that does not exist.

**Corrected:** proceed on **web-1 only**, and scope web-2 out explicitly. `hcloud_volume.workspaces_luks`
is a **singleton for web-1**, not `for_each = var.web_hosts` — a for_each'd attachment would land
outside `web2_allow` in `destroy-guard-filter-web-platform.jq` and **permanently brick the
web-2-recreate path**, and `moved` wants a singleton source.

**web-2's volume is knowingly left plaintext**, tracked by #6538: it is slated for destruction, has
never served (fact 5), and its volume is empty. Encrypting a volume scheduled for deletion is waste.
**This is a recorded deviation from #6588's "every `var.web_hosts` member" AC.**

### (e) The fail-closed mount gate reaches web-1 via the CUTOVER channel, not the bake

**Supersedes the original ruling.** It held that LUKS goes in the baked `soleur-host-bootstrap.sh`
(ADR-080) rather than inline cloud-init, on gzip-budget grounds (`WEB_GZIP_BUDGET`, ~300 bytes of
headroom — that part still holds).

**But the bake has no consumer.** The bake is read only on a **fresh host create**;
`hcloud_server.web` carries `lifecycle { ignore_changes = [user_data] }` so cloud-init never re-runs
on live web-1; and **cx33 is unorderable, so web-1 can never be created** (fact 4). There is no
`web_1_replace` dispatch job, and `hcloud_server.web` is an operator-applied exclusion. **A LUKS block
in the bake is therefore dead code on the only host that exists** — and with it dies the very
mechanism the CPO's G6 requires *in this PR* to stop silent root-disk writes. A mutation test for that
gate would pass against a gate that never runs in production.

**Corrected:** the bake still ships (it is the correct convention for any future fresh host, and the
`isLuks` guard is safe there in its intended direction — the volume is born empty), but **the live
delivery path for web-1 is the cutover job's SSH channel**. Any claim that merging this work protects
web-1 is false until the cutover runs.

> **Superseded 2026-09-27 (#8706):** for the monitor units, `workspaces-luks-emit.sh` and the
> `SOLEUR_SENTRY_DSN=` line only. No real cutover reached the step that delivers them, so
> `terraform_data.luks_monitor_install` now does. The mount-gate claim above stands. See the
> 2026-09-27 addendum.
>
> **Superseded 2026-09-28 (#9123):** the mount-gate claim too. The §(e) gate and the boot
> unlock reach web-1 through `terraform_data.workspaces_boot_unlock_install`, not the cutover
> channel. See the
> [2026-09-28 addendum](#addendum-2026-09-28-the-e-mount-gate-and-the-boot-unlock-have-a-terraform-owner-9123).

**Reboot is the sharper edge.** `docker run --restart unless-stopped` means `dockerd` resurrects the
container on reboot **without ever executing `docker run`** — so a pre-`docker run` gate catches
nothing on that path, and the `-v /mnt/data/workspaces` bind mount silently resolves to a **root-disk
dir Docker creates**. Result: container healthy, `/health` 200, **user source code written in
plaintext to the root disk**. (This narrative said `/api/health` until #6807; that path has no route
and 307s to `/login`, so it could never have been the 200 being described. `/health` is the custom
server's path — and note that its 200 is exactly the *unconditional* liveness signal this paragraph
is warning about, which is why the mount claim needs `/internal/readyz`, not either health path.) The gate must therefore be structural, not procedural: a systemd unit
with `RequiresMountsFor=/mnt/data` ordered after the mapper-open, so *container running ⇒ mount
correct* holds **by construction**, plus `chattr +i` on the root-disk `/mnt/data` inode so Docker's
implicit `mkdir` returns EPERM.

`nofail` stays in fstab (a Doppler outage must yield a degraded, pageable boot rather than a hang on
an unrebuildable host) — `nofail` and fail-closed are not in conflict once the gate is structural.

### (f) The passphrase is Soleur-minted, and escrow is proven against the REAL device

`random_password` → `doppler_secret` → read-only scoped `doppler_service_token`. No `TF_VAR`, no
human-minted secret (`hr-tf-variable-no-operator-mint-default`). `--key-file -` via stdin, never argv.
Fail loud on an empty key — **never an unencrypted fallback** (NFR-026).

**The Doppler config is dedicated (`prd_workspaces_luks`), on a rationale git-data's does not supply.**
git-data isolates for host blast radius; web-1 already carries full-prd, so there is none left to buy.
The real boundary is **host-vs-container**: cloud-init runs `doppler secrets download --config prd`
into the TMPENV that feeds `docker run --env-file`, so a key in shared `prd` would be readable via
`/proc/self/environ` **by the very agent code whose data it encrypts** (CWE-522).

**The mechanism is inheritance DIRECTIONALITY, not scope reduction — and this ADR will not claim
otherwise.** Doppler resolves **root → branch**, so a secret in the branch does not appear in a
`--config prd` download. That asymmetry is the whole guarantee. The inverse does **not** hold: the
branch **inherits the full root set**, so the boot token resolves ~116 `prd` secrets including
`SUPABASE_SERVICE_ROLE_KEY` and is materially a full-prd token. The repo established this empirically
(`knowledge-base/project/learnings/security-issues/2026-07-07-doppler-branch-config-does-not-isolate-secrets.md`,
severity high; #6122 fixed zot by moving to a **separate project**; **#6167** audits the rest —
including `prd_git_data`, the precedent this ADR mirrors). It is free on web-1, which already carries
a full-prd token, so the CWE-522 container boundary holds regardless. **True isolation is a separate
Doppler project — #6167's scope, deliberately not this work's.**

**Named deferral to #6604 (the cutover).** Because the branch inherits the root, the natural host-side
reads reintroduce the exact exposure this section closes:
`doppler run --config prd_workspaces_luks -- …` and
`doppler secrets download --config prd_workspaces_luks` both inject all ~116 secrets **plus** the key
into one environment. **Only `doppler secrets get WORKSPACES_LUKS_KEY --plain --config
prd_workspaces_luks` is safe.** Nothing in PR 1 can pin this — the `.tf` and its guard cannot see
host-side code. #6604 must pin it, and should carry the boot self-assertion the learning prescribes
(refuse to start unless the shipped token resolves exactly the expected secret set — count AND
identity), because **every other signal fails OPEN on an over-scoped token**. Precedent:
`cloud-init-registry.yml`.

**Escrow is a blocking pre-freeze gate** (CPO amendment): passphrase loss makes the volume unreadable
forever — a terminal mode **created by this fix**, strictly worse than the exposure being closed.

**Correction to the original escrow design.** Formatting a throwaway volume with the same string read
from Doppler and opening it **passes for any string** — it cannot fail. It was also **tautological by
order**: it ran *before* `prepare_luks_target`, so it could not test the real volume, and it proved the
*CI* read path rather than the *host's service-token* path that actually runs at unlock time.

**Corrected:** after `prepare_luks_target`, against the **real** device, via the **host's token path**:

```
printf '%s' "$WORKSPACES_LUKS_KEY" | cryptsetup luksOpen --test-passphrase --key-file - "$REAL_DEV"
```

No throwaway volume, no CI-transit surface, no orphan cost. **Then make it continuous** — a daily
`--test-passphrase` probe with `reason=escrow_divergence`. The original plan invented a terminal
failure mode and then declined to monitor it.

**The LUKS header is an independent terminal limb.** A corrupted or overwritten LUKS2 header is
unrecoverable **even with a perfect passphrase** — keyslots live in the header and no derivation path
exists. `cryptsetup luksHeaderBackup` after `prepare_luks_target`, stored off-host in a bucket
**distinct from the tfstate bucket** (else both halves are colocated and the "different provider,
different blast radius" property evaporates).

**Rotation is not a re-key, and the plan's own mitigation was the catastrophe.** `-replace` on
`random_password.workspaces_luks` re-mints the passphrase and updates Doppler **while the volume
header is untouched** ⇒ that IS the terminal mode, permanently, once the plaintext backstop is wiped.
The cutover gate asserts `luks_passphrase_touched == 0` on exactly these grounds (precedent:
`git-data-host-replace-gate.sh`). If rotation must ever be supported, it is `cryptsetup luksChangeKey`.

### (g) No `format` on the new volume — the discriminator must exist

`format = "ext4"` (the precedent's shape) would make the fresh volume **byte-indistinguishable** from
the live plaintext volume — both `TYPE=ext4`. That destroys the only sound guard: *format only a
device with no filesystem signature*. With `format` dropped the device is raw and the guard is real:

```
sig=$(blkid -o value -s TYPE "$DEV" 2>/dev/null || true)
case "$sig" in
  "")          luksFormat ;;   # raw — the ONLY formattable state
  crypto_LUKS) : ;;            # idempotent no-op
  *) echo "FATAL: $DEV carries TYPE=$sig — refusing to format a populated device"; exit 1 ;;
esac
```

Select the device **by volume ID from terraform output — never by glob scan**. The precedent scans for
the device that *is* LUKS; the inverse predicate matches the **live plaintext volume**. Pinning the
`/mnt/data` mount by volume ID is a hard prerequisite: with a second volume attached, the existing
`scsi-0HC_Volume_*` glob in `cloud-init.yml` is ambiguous.

**The device arm is only half the state machine — after `luksOpen` the MAPPER is an EMPTY CONTAINER.**
`luksFormat` writes a LUKS2 header and `luksOpen` exposes `/dev/mapper/<name>`; neither lays a
filesystem. `mkfs.ext4` must run on the **mapper**, so the filesystem is created INSIDE the encrypted
container rather than beside it. Omit it and the mapper has no superblock, `mount "$MAPPER"
"$STAGING"` fails with *"wrong fs type, bad option, bad superblock"*, and — under `set -uo pipefail`
with no `-e` — that failure is **swallowed**, leaving the rsync to land on the plain root-disk
directory the preceding `mkdir -p "$STAGING"` just created. That is #6588's realised defect: a cutover
reporting green while writing every user's source code, **in plaintext, to the very disk this ADR
exists to get it off**. Fixed in `workspaces-cutover.sh :: prepare_staging_target`.

The mapper therefore carries the **same three-arm discriminator shape as the device**, one level down:

```
fs_type=$(blkid -p -s TYPE -o value "$MAPPER" 2>/dev/null || true)
case "$fs_type" in
  "")   mkfs.ext4 "$MAPPER" ;;  # empty container — the ONLY mkfs-able state
  ext4) : ;;                    # idempotent no-op on a re-run
  *) echo "FATAL: $MAPPER carries TYPE=$fs_type — refusing to mkfs over it"; exit 1 ;;
esac
```

Three details of that shape are decisions, not style:

- **`-p`, not a cached probe.** The mapper probe is `blkid -p` — a low-level superblock read that
  **bypasses `/run/blkid/blkid.tab`**. A cached entry can report the **previous** type across a
  rollback-and-reformat cycle, which is precisely the sequence a safe-abort produces. And the arms are
  destructive in **opposite** directions: one `mkfs`es (destroying a filesystem that really is there)
  while another refuses (stranding the cutover on a mapper that really is empty). **A stale read is
  wrong in BOTH directions**, so "probably fresh enough" is not a defensible default here.
- **`-s TYPE -o value`, not bare `blkid`.** Bare `blkid` exits 0 on a partition-table-only device, so
  an `if blkid …` form would **skip the needed `mkfs`** — reproducing this very bug through a
  different door.
- **The staging mount is fail-closed and carries a positive control.** A `mount` failure `die`s rather
  than falling through, and after the mount `findmnt -no SOURCE "$STAGING"` must equal `$MAPPER`,
  whose backing device must in turn equal `$FRESH_DEV`. **Both links are asserted because neither
  alone is sufficient:** `$MOUNT` and `$STAGING` are *strings*, and a string that is merely non-empty
  and merely distinct proves nothing about which block device sits underneath it. The assert anchors
  the mount to the mapper and the mapper to the fresh device, so *copy target is encrypted* holds by
  construction — the same positive-control constraint §(a) places on G4's `lsof` scan, for the same
  reason (a probe that cannot distinguish "clean" from "never ran" is not a gate).

Every `die` in `prepare_staging_target` fires at **prepare** time — **before** the freeze is held — so
the abort note must say so: nothing was unwound, and `ROLLBACK=1` must **not** be run (it would
unmount the LIVE plaintext volume at `/mnt/data` and cause a gratuitous outage for no benefit).
Residual state is at worst an open mapper, possibly mounted at `$STAGING`; both are idempotent on
re-run, which is what the `ext4` arm above exists to make true.

## Alternatives Considered

| Alternative | Verdict |
|---|---|
| **Blue-green host** (the issue's preferred option 1) | **Impossible.** cx33 `available = false` in all 3 EU DCs (fact 4) ⇒ `-replace` destroys the sole prod host and cannot recreate it. Also inverts #5887's own norm, whose zero-downtime machinery (LB) does not exist (#6459 is OPEN with "ADR needed"). |
| **In-place `cryptsetup reencrypt`** | Rejected. Operates on the live device holding sole-copy data with no rollback artifact; a power loss mid-reencrypt is unrecoverable. The additive design's two-copy state is strictly safer. |
| **fscrypt / per-directory encryption** | Rejected. Does not satisfy the published claim (which says the *volume* is LUKS-encrypted), and leaves metadata in plaintext. |
| **Option 3 — retract the claim instead** | **Declined by the operator**, three times, most recently 2026-07-17 with the Art. 5(2) scienter and Art. 34(3)(a) arguments in hand. Priced here so the alternative stays legible: it is free today (zero beta users) and gets monotonically more expensive with every founder recruited (#1439). |
| **Build `soleur-drain.service`** (the precedent's shape) | Rejected. It does not exist (`grep -rln` finds it referenced only in `git-data-cutover.sh`, defined nowhere) and a drain is meaningless for a singleton with no LB. |
| **Pre-cutover Hetzner snapshot as backstop** | Rejected. Manufactures an indefinitely-retained plaintext copy of user source code inside the very issue that exists to eliminate them. The retained volume is a better backup — live, mountable, and rehearsed. |
| **`for_each = var.web_hosts` on the new volume** | Rejected. Lands outside `web2_allow` in the destroy-guard filter ⇒ permanently bricks `web-2-recreate`; `moved` wants a singleton source. |
| **Rename the LUKS volume to the old name post-cutover** | Rejected. `hcloud_volume.name` *is* update-in-place in provider 1.63.0 (measured), but the name is cosmetic — the mount pins by volume ID, so nothing reads it. Keeping `workspaces_luks` as the permanent address eliminates the `state rm` / `moved` / rename divergence window entirely. |

## Consequences

**Positive.** The published Art. 32 claim becomes true for the volume that actually holds user code.
The `isLuks`-inversion foot-gun is structurally unreachable (no `format` ⇒ raw-device discriminator).
The mount stops depending on a device glob that a second attached volume makes ambiguous. The retained
plaintext volume gives a rehearsed rollback that a snapshot never would.

**Negative, and named.**

- **A terminal failure mode is created that did not exist before**: passphrase or header loss ⇒ user
  source code unreadable forever. Today's worst case is *someone else reads the user's code*;
  post-LUKS the worst case is *the user cannot*. This is why escrow proof + header backup + a daily
  divergence probe are blocking rather than nice-to-have.
- **Bounded downtime** on the sole production host (≤20 min budget, ≤2h hard abort).
- **web-2's volume stays plaintext** — a knowing deviation from the issue's AC, tracked by #6538.
- **Nothing is protected at merge time.** The declaration has zero live effect; the volume is born and
  cut over by a dispatch job. Any claim of protection before that job's canary passes is false.

**Sequencing.** The doc corrections are **coupled** to live verification per the operator's decision
(2026-07-17): all four — the three permanently-false clauses *and* the LUKS present-tense flip — land
in a single PR **after** the cutover canary passes, never before. See
`knowledge-base/project/specs/feat-one-shot-6588-luks-workspaces-volume/decision-challenges.md`.

## Addendum (2026-07-18): the header-escrow implementation (#6649)

The C4 "independent terminal limb" decision above (back the LUKS header up off-host to a bucket
DISTINCT from tfstate) is implemented by #6649. Recording the **implementation** decision (no new
architectural axis, so no new ADR):

- The escrow credential is a **distinct, bucket-scoped R2 API token** (Object Read & Write on
  `soleur-workspaces-luks-header` only), minted out-of-band and delivered to web-1 via the SAME
  `prd_workspaces_luks` scoped-read path as the passphrase (`WORKSPACES_HEADER_R2_ACCESS_KEY_ID` /
  `_SECRET_ACCESS_KEY`; the bucket name + endpoint are Terraform-managed `doppler_secret`s). The S3
  creds are **not** derivable from any `cloudflare_api_token` field — `sha256(token.value)` fails
  SigV4 (learning 2026-05-18). A DRY_RUN-safe probe-PUT measures the creds before the freeze trusts
  them.
- **The escrow token must NEVER also reach `soleur-terraform-state`.** That bucket holds
  `random_password.workspaces_luks.result` in plaintext Terraform state; reusing the tfstate R2 token
  for the header escrow would hand a host-compromise adversary write/read on the passphrase-bearing
  state bucket — the real C4 blast-radius property for this issue. Enforced at runtime by the
  `[ "$HEADER_BACKUP_BUCKET" != "$TFSTATE_BUCKET" ]` name compare in `load_escrow_creds` + a
  **negative probe** (the escrow creds must be DENIED against the tfstate bucket — catches an
  over-scoped account-wide token the name-compare cannot; it fails CLOSED on an inconclusive/transport
  error rather than trusting a bare non-zero exit as "denied").

**Residuals (recorded, not resolved here):**

- The header bucket's confidentiality-at-rest is already gated on tfstate secrecy (the passphrase
  lives there); the escrow does not improve that, it only prevents *loss* of the header.
- The `prd_workspaces_luks` host token inherits all ~116 `prd` root secrets (pre-existing for
  `WORKSPACES_LUKS_KEY`, tracked by #6167); the escrow now depends on that same token.
- `prevent_destroy` on the bucket protects against a Terraform `-destroy`, NOT against an API-delete
  by the Object-R&W escrow token itself — consider R2 object-retention (cla-evidence `object_lock.tf`
  precedent) or accept that the escrow copy is deletable by the token that writes it.
- The local header copy is written to a mode-0700 dir on web-1's **persistent** NVMe root disk (not a
  tmpfs `/tmp`, so `shred -u` is not a no-op) — but `shred` on a wear-levelled/journaled SSD is
  **best-effort**, not a guaranteed raw-block overwrite. Acceptable at this threshold: the header alone
  is inert without the passphrase, which lives in tfstate/Doppler, not on this disk.
- **Honest C4 limitation:** a single `hetzner → cloudflare` edge collapses BOTH R2 buckets (tfstate +
  header) into the one `cloudflare` node, so the diagram does NOT visually encode the "distinct blast
  radius" property — that distinctness lives only at runtime (the `load_escrow_creds` name-compare +
  negative probe) + the `workspaces-luks-header.test.sh` reference-not-literal guard, not in the picture.

## Addendum (2026-07-18): the escrow-rehearsal authorization model (#6649)

The escrow rehearsal (`workspaces-luks-cutover.yml -f dry_run=true`) must run FULLY AUTONOMOUSLY — the
operator is non-technical and never approves gates or runs terraform. Three host-provisioning/
execution gaps (content-carrier, boot-token delivery, `WORKSPACES_LUKS_DEV`) blocked the probe; a
fourth — the human gate — blocked autonomy. This addendum records the authorization-model change only;
the mechanics live in the plan.

**The gate moves onto the irreversible arm.** The cutover job previously declared a static
`environment: workspaces-luks-cutover` at job level, so EVERY dispatch — including a `dry_run=true`
rehearsal — waited on a required-reviewer (`[54279]`) approval. But a dry-run performs NO irreversible
operation: the freeze/repoint are behind `DRY_RUN != 1` in `workspaces-cutover.sh`, and the plaintext
wipe is a separate `CONFIRM_WIPE` dispatch. Gating a reversible probe behind a human is the actual
misconfiguration. The job now declares:

```yaml
environment: ${{ !inputs.dry_run && 'workspaces-luks-cutover' || '' }}
```

> **⚠️ SUPERSEDED — see "Addendum (2026-07-19): the stray-copy carve-out (CLEAN_STRAY, #6588)".**
> The expression above, and the truth table + tautology argument below, are the **2026-07-18 state**
> and are retained for provenance. They were **wrong in a way that left a live authorization hole**:
> the argument assumes `dry_run` is a faithful proxy for "which mode", but the ROLLBACK block
> force-sets `DRY_RUN=0` in-script while `dry_run` **defaults to `true`** — so `rollback=true` with an
> untouched form took the **ungated** branch and performed a real umount / `cryptsetup close` /
> container restart behind nothing but the typo-guard token. Every destructive mode now contributes
> its own operand; read the addendum for the current expression and truth table.

**Reversibility proof (what the dry-run actually touches on web-1).** The dry-run is NOT
host-side-effect-free, but every effect is reversible/benign: `ensure_aws` installs a SHA-pinned
aws-cli (additive, no service restart); `escrow_probe` does a PUT→read-back→delete of a namespaced
`.probe/<run-id>` R2 key (self-cleaning); `prepare_luks_target` selects, `luksFormat`s-if-raw, and
opens the FRESH device (never the live plaintext volume — selected by by-id + a single-match assertion,
guarded by the `blkid` discriminator §(g) that refuses to format a device carrying a filesystem
signature) under the DP-6 `trap cleanup EXIT` host-local rollback; `prepare_staging_target` then
`mkfs.ext4`s the **mapper**-if-empty and mounts it at `$STAGING` behind the mapper-arm discriminator +
staging positive control §(g). The `luksFormat` and the `mkfs` are destructive only on the disposable
fresh volume and on the container opened from it; the live plaintext `/mnt/data` is never a candidate
for either. **No new destructive operation on this arm; two new read-only refusals added.** ("Unchanged" would
be the wrong word — the dry-run arm gained two terminal exits it did not have: `stray_present` and
`already_cutover`. Both are read-only assertions, deliberately evaluated in BOTH arms so a rehearsal
reports those conditions honestly rather than passing green over them. The *destructiveness* claim
below is what the reversibility premise rests on, and it survives.) Under `DRY_RUN=1`
`prepare_staging_target` returns before it
touches the mapper at all, so the mkfs/staging-mount work added by #6588 adds **nothing destructive
to the dry-run arm**. Precisely: the dry-run arm performs `mkdir -p "$STAGING"` (idempotent; creates
at most an empty directory) and two read-only asserts — the stray-copy check and the
already-cutover check, both of which are deliberately evaluated in BOTH arms so the rehearsal
reports those conditions honestly. It performs no `mkfs`, no `mount`, and no deletion. This proof is
corrected for completeness, not weakened. None of these is the irreversible act
the C19/AC20b gate exists to authorize (the freeze + plaintext wipe), all of which stay behind
`DRY_RUN != 1`.

**Truth table (why the expression is fail-closed).**

| `inputs.dry_run` | `!inputs.dry_run` | `&& 'workspaces-luks-cutover'` | `\|\| ''` | environment | gated? |
|---|---|---|---|---|---|
| `true` (rehearsal) | `false` | `false` | `''` | none (empty) | NO — autonomous |
| `false` (real freeze) | `true` | `'workspaces-luks-cutover'` | (short-circuits) | `workspaces-luks-cutover` | YES — human ack |

The expression reads the **typed** `inputs.dry_run` boolean context (declared `type: boolean, default: true`), so `!inputs.dry_run` coerces on a real boolean — never the string-typed `github.event.inputs.dry_run`, where `!'false'` is `false` and the freeze would run **ungated**. Drift guards `workspaces-luks-header.test.sh` H17 (exact fail-closed byte-form) + H19 (non-empty reviewers) pin this; they go RED on the inversion. **Sequencing:** the boot-token secret rides the DEFAULT apply, not the scoped `apply_target=workspaces-luks-cutover` first-provision — between a scoped first-provision and the next default apply the secret is unpublished, so both workflows fail loud (`[[ -n "$WORKSPACES_LUKS_BOOT_TOKEN" ]] || exit 1`) rather than proceeding tokenless.

~~The gate and `DRY_RUN` derive from the SAME `inputs.dry_run` operand, so "freeze-reachable" ⟺ "gated"
is a tautology — there is no input that reaches the freeze arm ungated.~~ **This tautology is FALSE and
was the defect** (corrected 2026-07-19, #6588): it holds only for the freeze arm. `ROLLBACK` and
`CONFIRM_WIPE` are *separate* destructive modes whose reachability `inputs.dry_run` does not describe,
and the ROLLBACK block force-sets `DRY_RUN=0`, breaking the derivation the argument rests on. The
lesson generalizes past this file: **an operand that means "which mode" must be read from the mode,
never inferred from a sibling flag that merely correlates with it today.**

The empty-string branch changes ONLY autonomy, never the safety property. **Never invert the
operands:** `inputs.dry_run && '' || 'X'` gates ALWAYS (`''` is falsy, so it falls through to `'X'` in
both arms) — the opposite of intent, and it would leave the freeze ungated in exactly the case that
matters. Drift guards: `workspaces-luks-header.test.sh` H17 asserts the fail-closed **shape** (the
ungated branch is the `''` arm, and every destructive mode contributes an operand), and
`workspaces-luks-cutover-workflow.test.sh` pins the **exact expression** by parsing the workflow as
YAML — deliberately in one place only, so the literal is not replicated across two files without a
parity test.

The reviewer set MUST stay non-empty (a zero-reviewer environment auto-approves — DP-11 F8); H19 asserts
it. Split-job (a `rehearse` job with no environment + a `freeze` job with a static `environment:`) is the
auditability-preferred fallback if GitHub's empty-string-environment semantics ever change; the
conditional form is the primary because it keeps the two arms in one job (no duplicated bridge/teardown).

## Addendum (2026-07-19): the C1 verify is self-diagnosing (#6604 cutover follow-up)

The first real cutover (`workspaces-luks-cutover.yml`, `dry_run=false`) **safe-aborted** on the C1
itemized verify's *"1 difference"* and DP-6 auto-rolled-back to the plaintext mount (web-1 healthy) —
the fail-closed gate did its job. But the verify **discarded** the offending path (it `rm`'d the diff
log and `die`'d with only the count) and **folded rsync's stderr into that count** (`>"$vlog" 2>&1`),
so the operator could not tell whether the diff was a real byte difference, an mtime-only/dir-mtime
attribute diff, or a benign stderr warning. That is an observability defect, not a gate defect — fixed
in `workspaces-cutover.sh :: verify_byte_identity` / `emit_verify_diff`:

- the verify rsync's **stdout** (the `%i %n` itemize lines) and **stderr** are captured **separately**;
  the count reads only itemize-shaped stdout lines (`^(\*deleting|[<>ch.*][fdLDS])`), so stderr can no
  longer inflate it and **no itemize code is narrowed away** (attribute-only diffs still count);
- on a non-zero count OR a verify-rsync error, the capped (≤40) itemized path(s)+code(s) are logged to
  the run log AND to Better Stack via a new **`SOLEUR_WORKSPACES_LUKS_VERIFY_DIFF`** marker
  (`op=workspaces-luks-verify-diff`, riding the already-allowlisted `luks-monitor` Vector tag — no
  `vector.toml` change) **before** the temp files are removed and before `die()`.

**Telemetry taxonomy:** `op=workspaces-luks-drift` remains the at-rest / daily-probe Sentry page;
`op=workspaces-luks-verify-diff` is the new itemized-diff channel (Better Stack) — the verify still
also pages Sentry via `emit_drift` on the existing `op=workspaces-luks-drift`. The gate's
data-integrity contract (0 real content diffs, fail-closed on rsync error) is **unchanged**; this is a
bug fix, not a new decision.

## Addendum (2026-07-19): the stray-copy carve-out (CLEAN_STRAY, #6588)

The 2026-07-19 cutover run swallowed its staging mount and sent the entire bulk rsync to
`/mnt/data-luks` **on web-1's root disk** instead of onto the LUKS mapper. `bec339250` fixed the
mount (mkfs the mapper, fail-close the staging mount) and added a **detect-and-refuse stray guard**
so no future run can prepare over such a residue.

That guard is a read-only assert placed deliberately **above** the `DRY_RUN` short-circuit, so it
fires in both arms — which means it `die()`s on *every* dispatch, including every rehearsal, for as
long as the stray exists. No dispatch shape both reached the host and survived it: the cutover was
fully wedged. The guard is correct and is **not** moved or relaxed here; a rehearsal that proceeded
over a live stray would certify the staging path while the exact defect that caused the incident sat
on disk. The wedge is cleared by **remediating the stray**, not by weakening the check.

**Decision.** Add a `CLEAN_STRAY=1` mode — a standalone, explicitly-gated operator entrypoint
(`clean_stray()` in `workspaces-cutover.sh`, `clean_stray` input on the cutover workflow) that
removes the stray. It mirrors the `ROLLBACK=1` mode's *shape* and deliberately **not** its *gate*
(see below).

- **AP-009 (Never delete user data): Deviation — documented carve-out.** `clean_stray()` deletes the
  contents of `/mnt/data-luks` on web-1's root disk. That content is **user data** — workspace source
  code. This is not data loss: provenance establishes the copy is a **duplicate**. Nothing ever wrote
  to that path except the misdirected rsync of `/mnt/data`; no service, mount, or container
  references it, which is why the guard's own message names it "a DUPLICATE; the canonical data is at
  $MOUNT". The canonical copy at `/mnt/data` is retained and is never touched. `clean_stray()`
  refuses — each with its own named reason on the no-SSH marker channel — when: any probe binary it
  depends on is absent (a missing `mountpoint` exits 127, which an `if` reads as "the dangerous
  condition does not hold"); `/mnt/data-luks` is a symlink; `/mnt/data-luks` is a **mountpoint** (that
  is the real LUKS volume); `/mnt/data` is not a healthy mountpoint backed by a block device;
  `/mnt/data` and `/mnt/data-luks` are on the **same filesystem** (compared by `stat -c %d` on the
  directories — `findmnt` cannot answer this, because the mountpoint refusal above guarantees
  `/mnt/data-luks` is not a mount target, so a `findmnt`-based check would be dead code that merely
  looks like a guard); a filesystem is mounted **beneath** `/mnt/data-luks` (which `rm -rf` would
  descend through into live data); or the enumeration itself fails.

  The premise is left **falsifiable** rather than asserted: a relative-path subset check refuses if
  the stray holds any path `/mnt/data` does not. That check runs to **depth 2**, not depth 1, and the
  distinction is load-bearing: `/mnt/data`'s top level is infrastructure (`workspaces/`, `plugins/`,
  `redis/`) while user identity lives at `workspaces/<id>/`, so a depth-1 comparison reduces to "does
  `/mnt/data` contain a directory named `workspaces`?" — true in every reachable state, **including one
  where the stray holds a user's only surviving copy**. Depth 2 is where the check starts asking a real
  question; deeper would refuse forever on ordinary per-file churn in a live workspace. The ungated
  preflight probe publishes that result plus the magnitude for a human to read before approving, and
  **fails the dispatch** rather than rendering an empty banner if it cannot read the host — an absent
  magnitude reads to an approver as "nothing to delete", which is the one thing this surface must
  never say by accident. The carve-out is scoped to this one path, this one mode, and this one
  incident; it is reachable only behind the `workspaces-luks-cutover` environment reviewer gate and a
  distinct typed token, `DELETE-STRAY-USER-DATA-AP-009`.
- **Escrowing the stray before deleting it was considered and rejected.** It would create a *third*
  copy of user data on a new egress path carrying its own retention, DSAR and Art. 30 obligations —
  arguably a worse AP-009 outcome than a provenance-established, human-approved delete of a proven
  duplicate. The existing escrow path is sized for a ~2 MB LUKS header, not a bulk dataset.

**Why the mode does not inherit ROLLBACK's gate.** `dry_run` had been serving as a proxy for "which
mode" across the workflow, and that synonymy was already false: `dry_run` **defaults to `true`**
while the script's ROLLBACK block force-sets `DRY_RUN=0`, so a `rollback=true` dispatch with
`dry_run` left untouched resolved to the **ungated** branch of the `environment:` expression and
performed a real `umount` / `cryptsetup close` / container restart on web-1's live volume behind
nothing but a typo-guard token. Mirroring that gate would have satisfied "same approval posture" by
violating "not reachable from the ungated dry-run arm". Both are fixed together: every destructive
mode now contributes its own operand, and the ungated branch is reachable only for
`dry_run=true ∧ clean_stray=false ∧ rollback=false`.

**Why the workflow is now two jobs.** A job's `environment:` gate blocks the job **before its first
step**, so validation and operator-legibility placed inside the gated job can only ever run *after* a
reviewer has been paged. An ungated, mutation-free `preflight` job therefore rejects impossible mode
combinations before waking anyone, and on a `clean_stray` dispatch reaches web-1 read-only to write
the AP-009 banner and the deletion's magnitude to the run summary. GitHub's approval UI shows
workflow, actor and ref — never the dispatch inputs — so without this a routine cutover and a
user-data deletion are indistinguishable at the moment of authorization.

**Mode exclusion is an availability control, not just a correctness one.** ROLLBACK's block ends
`exit 0`, so a CLEAN_STRAY block after it is unreachable whenever `ROLLBACK=1`: an operator who
ticked both would type the delete-user-data token, receive a **rollback** on a host where no freeze
was held — per the script's own `_PREPARE_ABORT_NOTE`, "a gratuitous outage" — see the run exit
green, and still have the stray. `assert_mode_exclusive()` refuses that combination ahead of both
blocks, mirrored by the preflight job.

**The detect-and-refuse invariant is unchanged elsewhere.** The deletion lives in its own function,
never in `prepare_staging_target`, so that suite's "this path issues no `rm`" assertion (T4c) is left
byte-identical and keeps holding for every arm that is not this explicit entrypoint.

**Telemetry:** `SOLEUR_WORKSPACES_LUKS_CLEAN_STRAY` (`op=workspaces-luks-clean-stray`, carrying
`deviation=AP-009`) is a **new** marker rather than an overload of
`SOLEUR_WORKSPACES_LUKS_STAGING_TARGET`, whose `result=`/`reason=` vocabulary is pinned by the
T-series; a user-data deletion must not be indistinguishable from a staging-prep outcome on the
operator's only no-SSH channel. Magnitude is reported **top-level only** — a per-path itemization
would publish workspace structure (repo and branch names) into the Actions log and the Sentry drift
channel, a wider audience than the data itself.

## Addendum (2026-07-23): the re-cut-after-orphaned-volume path (#6812 / #6855)

The 2026-07-20 cutover (run `29782780158`) landed, served for ~27 minutes, then its host-local
dead-man timer fired and remounted the plaintext volume — stranding those 27 minutes of sole-copy
writes on the LUKS volume and leaving `/mnt/data` back on plaintext `/dev/sdb` (**#6812**). The
operator's recovery decision (2026-07-21, recorded on #6812): **accept the 27-minute loss and
re-cut**; the live plaintext volume is authoritative, and the stranded window is *deliberately
discarded*.

**The premise "a re-cut luksFormats that device" does NOT hold against the current on-disk state,
and that is the gap this addendum closes.** The dead-man is a host-side mount operation — it does
NOT touch terraform state — so `hcloud_volume.workspaces_luks` (Hetzner id `106406962`) is **still
in state and still `crypto_LUKS`**, holding the discarded window. `workspaces-cutover.sh`'s device
guard (§(g)) is three-arm — raw→`luksFormat`, **`crypto_LUKS`→idempotent no-op**, other→abort — so a
plain re-cut against `106406962` hits the **no-op** arm: it re-opens the OLD header and surfaces the
stale ext4, never re-formatting. A re-cut now would reuse the orphaned volume + old header, bulk-rsync
(no `--delete`) live plaintext over the stale ext4, and most likely abort at the C1 `--delete
--dry-run` verify — not the clean fresh cut that was authorized.

**Mechanism — `apply_target=workspaces-luks-recut` (a scoped `-replace`, environment-gated).** A new
dispatch job in `apply-web-platform-infra.yml` runs `terraform -replace=hcloud_volume.workspaces_luks`
(+ `-target` on the volume and its attachment). It **destroys** the orphaned volume `106406962`
(discarding the accepted window) and creates a genuinely **raw** replacement carrying the *same stable
name* `soleur-web-platform-data-luks` — because `workspaces-luks.tf` deliberately omits `format`
(§(g)), the replacement is born raw. The existing cutover then resolves the new device by name
(`workspaces-luks-cutover.yml` queries the Hetzner API `?name=soleur-web-platform-data-luks`), hits
the raw→`luksFormat` arm, `mkfs`, and copies from the authoritative live plaintext. Zero downtime:
`/mnt/data` serves from the untouched live `/dev/sdb` throughout; attach/detach is a hot Hetzner-API
operation.

**Invariants (enforced by `tests/scripts/lib/workspaces-luks-recut-gate.sh`, mutation-tested):**

- The plan is EXACTLY `{volume REPLACE (delete AND create) + attachment CREATE}` — a bare
  delete/forget or an update-in-place aborts.
- **Recovery arm (arch review P2):** because the volume has no `create_before_destroy`, a `-replace`
  is destroy-before-create, so an apply that fails between the delete and the create strands the
  volume out of state. A re-dispatch then plans a bare create (`before == null`); the gate accepts
  that recovery shape (a fresh empty volume touches no live data), so the operator auto-recovers by
  re-dispatching rather than hand-editing terraform state (`hr-exhaust-all-automated-options`).
- **Id-pin (user-impact review P2):** the operator supplies `expected_luks_volume_id` (the orphaned
  volume's Hetzner id); the gate asserts the *replaced* volume's `before.id` equals it, so a state
  corruption that mapped the `workspaces_luks` ADDRESS onto the LIVE volume's physical id cannot
  silently destroy live data even though every address-based counter reads 0. Skipped for the
  recovery bare create (`before == null` — nothing to destroy).
- The LIVE plaintext volume (`hcloud_volume.workspaces["web-1"]`, id `105149570`), its attachment,
  and the web-1 server carry **zero** actions.
- **The passphrase is REUSED, never re-minted** — any create/update/delete/forget on
  `random_password.workspaces_luks` / `doppler_secret.workspaces_luks_key` aborts (a re-mint opens a
  new header and strands at-rest data — the F4 catastrophe). This inverts the cutover gate, where the
  passphrase's *first* create is legal.
- **Authorization** is the required-reviewer `environment: workspaces-luks-cutover` gate (reused, with
  a non-empty reviewer set — DP-11 F8) plus a typed `confirm=RECUT-WORKSPACES-LUKS` typo-guard. Unlike
  the additive first provision (un-gated), the recut is destructive on sole-copy data, so it carries
  the same human authorization as the freeze.

**No C4 impact** — checked all three model files (`diagrams/{model.c4,views.c4,spec.c4}`): the recut is
a lifecycle operation on the already-modeled `/workspaces` LUKS volume, the already-modeled web-1
host, the already-modeled operator, and the already-used Hetzner API. Actors checked {operator},
external systems {Hetzner API}, data stores {LUKS volume}, access relationships {operator→recut
dispatch} — all already modeled; no new element or edge.

**Status unchanged — `adopting`.** This addendum builds the *prerequisite* mechanism only. Executing
the recut, the freeze, and the verify are the operator's downstream gated dispatches; the
`adopting → accepted` flip stays downstream (soak-gated, blocked on the unwired heartbeat #6808).

## Addendum (2026-09-24): the luks-monitor token line has a steady-state owner (#8632)

**Why.** Retained web-1 snapshot `411798619` (2026-07-23) very likely holds the
`prd_workspaces_luks` service token `workspaces-luks-boot`. Rotating it is a rename of
`doppler_service_token.workspaces_luks` (every user-set attribute is ForceNew in DopplerHQ/doppler
v1.21.2). The rename rotates the token in Doppler and in the repo secret, but nothing delivered it to
the one consumer on web-1: `/etc/default/luks-monitor`, read by `luks-monitor.service`. Only
`workspaces-cutover.sh` had written that file, and it refuses to run again (`already_cutover`).

**§(e) is not a standing write channel, and this addendum does not extend it.** §(e) grants the
cutover job's SSH channel for delivering the fail-closed mount gate. An earlier draft of #8632 cited
§(e) for a dispatch-only "refresh" job in `workspaces-luks-verify.yml`; that citation overstated what
§(e) grants, and the job would also have shared the read-only verifier's concurrency group (a pending
approval parks the daily verify) and put a host write into a workflow whose runs are cited as legal
evidence. It was replaced before merge.

**Line ownership of `/etc/default/luks-monitor`:**

| Line | Owner |
|---|---|
| `SOLEUR_SENTRY_DSN=` | cloud-init (fresh hosts only; `ignore_changes = [user_data]` means web-1's file may lack it) |
| `DOPPLER_TOKEN=` | first write: `workspaces-cutover.sh`. After that: `terraform_data.luks_monitor_token_install` (`workspaces-luks.tf`), triggered only by the token's hash |

> **Superseded 2026-09-27 (#8706):** the `SOLEUR_SENTRY_DSN=` row. On web-1 that line is now
> written by `terraform_data.luks_monitor_install`; cloud-init keeps it for fresh hosts. See the
> 2026-09-27 addendum's table.

The installer ships `luks-monitor-token-refresh.sh`, which proves the new token can read
`WORKSPACES_LUKS_KEY` (the pinned `doppler secrets get … --plain --config prd_workspaces_luks` form)
BEFORE it rewrites only the token line, keeping every other line byte for byte and restoring the
original on any mismatch. The token reaches it on stdin through a builtin `printf`.

**Rotation** is a rename or `-replace` of the token, with `create_before_destroy`, delivered in the
one apply that carries `[ack-destroy]`: the main apply mints the new token and updates the secret
before deleting the old one; its SSH step re-fires the installer. No dispatch, no second approval.

**Proof boundary.** The installer proves the token reads the key. It never starts
`luks-monitor.service`, so a mount, escrow or readyz fault cannot redden a rotation merge. The daily
probe's health is proven by `workspaces-luks-verify.yml`, not by this installer and not by the host
timer (which #8632 review found silent; tracked separately). The installer prints the timer's state
into the apply log as evidence.

> **Superseded 2026-09-27 (#8706), in part:** this still holds for the token installer. The host
> timer was silent because it was never installed. The new `terraform_data.luks_monitor_install`
> starts the service once with `--no-block`, so probe faults still never redden a merge. See the
> 2026-09-27 addendum's "Proof boundary, qualified".

**Deviation from `hr-prod-host-config-change-immutable-redeploy`.** This is an in-place edit of one
line over SSH through Terraform, allowed under ADR-154's standing exception (web-1 cannot be
redeployed: `cx33` remains unorderable, re-sampled 2026-09-24 in ADR-154). It is the same class as
`terraform_data.private_nic_guard_install`, which delivers the `web_probes` token the same way.
Rebuilding web-1 to rotate a token would mean a reboot, and whether web-1 re-opens the LUKS volume at
boot is still unproven (the in-guest unlock path is deferred to #6931).

## Addendum (2026-09-24, after #8703's apply): the token line's owner also creates the file (#8632)

The first rotation apply (run 35991817062) found web-1 with **no** `/etc/default/luks-monitor`.
The helper reported `SOLEUR_LUKS_HOST_TOKEN_REFRESH result=fail reason=envfile_absent`. By then the
main apply had already revoked the old token, so the refusal left the host with no working token,
not with the old one. The file's earlier writers do not cover it: cloud-init bakes the DSN line only
at a host's birth, and the cutover's write did not survive.

The helper therefore creates an absent file, ending in the same state `workspaces-cutover.sh`
leaves (0600 root):

- it creates the file only AFTER the new token is proven (with `O_EXCL`), holding the token line only;
- it records `created_envfile=1` in its `result=ok` line;
- on a failed write or any post-write mismatch it removes the file, restoring the ABSENT state;
- it refuses a symlink at the path.

The addendum above still holds for the `DOPPLER_TOKEN=` line. The file itself is created by this
installer when absent. The missing `SOLEUR_SENTRY_DSN=` line stays cloud-init's, tracked in #8706.

> **Superseded 2026-09-27 (#8706):** the DSN line on web-1 is now delivered by
> `terraform_data.luks_monitor_install`. See the 2026-09-27 addendum.

## Addendum (2026-09-24): the same rotation shape, applied to `web_probes` (#8705)

`doppler_service_token.web_probes` (soleur/prd, read) is the second token rotated with this shape.
Retained web-1 snapshot `411798619` very likely holds its first token, `web-probes-read` (created
2026-07-18, written to web-1 the same day). It is renamed to `web-probes-read-2026-09-24` with
`create_before_destroy`; the merge that lands the rename must carry `[ack-destroy]`.

- **A rename, not a same-name `-replace`.** Without `create_before_destroy` a same-name replace
  deletes first, so a failed create leaves no token. With it, Doppler must accept two tokens with one
  name, which nobody has probed. For `workspaces_luks` and `web_probes`, the "rename or `-replace`"
  wording in the #8632 addendum above reads as "rename". The other Doppler service tokens in
  `apps/web-platform/infra/` still document a same-name `-replace` in their own comments; each is
  re-decided when it is next rotated.
- **web-1 delivery.** The four probe installers in `server.tf` (`private_nic_guard_install`,
  `zot_consumer_probe_install`, `inngest_consumer_probe_install`, `git_data_probe_install`) hash the
  key in `triggers_replace`, so the merge's SSH stage rewrites their `/etc/default/*` files whole.
  That in-place write rests on ADR-154's standing exception to
  `hr-prod-host-config-change-immutable-redeploy`, exactly as the luks-monitor line above does.
- **Fresh hosts.** web-2 got the old key at birth through user_data, which `hcloud_server.web`
  ignores after create. It is re-seeded by the ADR-148 `web-host-replace` dispatch once the merge
  apply is green; `runbooks/web-host-replace.md` lists that use.
- **Pinned.** `apps/web-platform/infra/web-probes-token-rotation.test.sh` fails when a consumer of the
  key would not re-fire on rotation, or when the token loses `create_before_destroy`.
  `apps/web-platform/infra/scripts/web-probes-token-rotation-verify.sh` proves the rotation from the
  Doppler token listing (the retired slug is gone and a later replacement exists).
- **Only one workflow may perform it.** `apply-deploy-pipeline-fix.yml` reaches the token
  transitively (its `-target`s reach `hcloud_server.web["web-1"]`, whose user_data reads the key)
  and has no `[ack-destroy]` path, so it now refuses any plan that deletes or forgets a
  non-`terraform_data` resource, or forces a reboot. The rotation happens only in
  `apply-web-platform-infra.yml`, behind its destroy guard.
- **No C4 impact.** Checked `diagrams/{model,views,spec}.c4`: no element or edge names this token.

This closes forward read access only. Values the image already holds are tracked in #8734.

## Addendum (2026-09-27): the monitor units and the DSN line have a Terraform owner (#8706)

**What was wrong.** `luks-monitor.timer`, `luks-monitor.service` and `/usr/local/bin/luks-monitor`
were never installed on web-1. They were not disabled, and they did not fail before exec. The
token installer's state print in `apply-web-platform-infra.yml` run 36005279546 (2026-09-24) read
`0 timers listed.` and an empty `UnitFileState=` for the timer. A disabled unit reads
`UnitFileState=disabled`; an empty value means there is no unit file.

The only installer was the tail of `workspaces-cutover.sh` (anchor: `# Deliver the standing
observability to the LIVE host via THIS channel (ADR-119 §(e)).`). That tail runs after
`app_canary`. The two real cutovers that passed the host canary, runs 29782780158 and 29995956562,
both died in `app_canary`. Every other real run died earlier, and every dry run stops before the
tail. So no run ever installed the units. The same unreached tail explains the missing
`/etc/default/luks-monitor` that #8724 fixed and the missing `SOLEUR_SENTRY_DSN=` line. It is one
defect, not three.

**Why nobody noticed for about nine weeks.** Three things read green over the gap:

- `betteruptime_heartbeat.workspaces_luks` has a second pusher, the daily
  `workspaces-luks-verify.yml` job, which ships its own copy of the probe. One live pusher keeps a
  shared beat `up`.
- The ADR-117 static guard cited the arming line in the cutover tail. The line exists, so the guard
  passed over code that never ran (see the ADR-117 amendment of 2026-09-27).
- A failing host run would not have reached Sentry (see "The DSN line is the only Sentry path on
  web-1" below).

**Decision.** `terraform_data.luks_monitor_install` in `workspaces-luks.tf` now owns delivery. It
rides the per-merge SSH apply and does four things:

1. It copies `luks-monitor.sh` to `/usr/local/bin/luks-monitor`, `workspaces-luks-emit.sh` to
   `/usr/local/bin/workspaces-luks-emit.sh`, and `luks-monitor.service` and `luks-monitor.timer` to
   `/etc/systemd/system/`. These are the cutover tail's destinations.
2. It writes the `SOLEUR_SENTRY_DSN=` line in `/etc/default/luks-monitor`. The file stays 0600 root,
   and every other line, the `DOPPLER_TOKEN=` line included, is kept byte for byte.
3. It runs `systemctl enable --now luks-monitor.timer`, asserts `is-enabled` and `is-active`, then
   starts the service once with `systemctl start --no-block luks-monitor.service`.
4. It prints the unit state into the apply log, the dead-man units included.

Its trigger hashes the four delivered files and the DSN, so a change to any of them re-delivers. The
cutover tail stays as it is. It installs the same repo files, so it is a harmless second installer
for a future re-cut.

**What this changes in §(e), and what it does not.** §(e)'s delivery claim no longer covers the
monitor units, `workspaces-luks-emit.sh` or the `SOLEUR_SENTRY_DSN=` line on web-1: Terraform owns
them now. §(e)'s mount-gate claim stands: the fail-closed mount gate still reaches web-1 through the
cutover channel. "§(e) is not a standing write channel" (2026-09-24) still holds, and this addendum
does not rely on §(e) at all. In the 2026-07-19 quiesce table, `luks-monitor.{timer,service}` is
now armed by this resource, not "by a *prior* successful cutover". The quiesce itself is unchanged.

**The DSN line is the only Sentry path on web-1.** `workspaces-luks-emit.sh` reads the DSN from
`/etc/default/luks-monitor` first. Its fallback is `doppler secrets get SENTRY_DSN --config prd`,
run with the `prd_workspaces_luks`-scoped token. That token cannot read `prd`, so the fallback is
unreachable, and the helper then returned without sending. Before this change a host drift event
on web-1 could not reach Sentry.

> **Qualified 2026-09-27 (#8706 review):** "that token cannot read `prd`, so the fallback is
> unreachable" is ASSERTED, not measured. It follows from the token's `prd_workspaces_luks` scope,
> but no run read the fallback with that token. What was measured is the missing DSN line. Since
> the review, a lost event is visible either way: the helper logs
> `SOLEUR_WORKSPACES_LUKS_SEND_FAILED reason=no_dsn` when no DSN resolves (see the review amendments
> below).

**Why the installer is in `workspaces-luks.tf`, not `server.tf`.** The units are web-1-only by
design (§(d)), so a fresh web host must NOT get them. Sections 1 and 2 of
`web-host-provisioner-parity.test.sh` scan `server.tf` only and require every SSH-written
destination there to have a fresh-boot writer. The installer therefore sits beside its sibling,
`terraform_data.luks_monitor_token_install`. This placement is a decision, not a way around that
sweep. The file-wide SSH connection count (G2) does include it.

**Line ownership of `/etc/default/luks-monitor`, from 2026-09-27.** This replaces the
`SOLEUR_SENTRY_DSN=` row of the 2026-09-24 table, and the sentence "The missing
`SOLEUR_SENTRY_DSN=` line stays cloud-init's, tracked in #8706" in the second 2026-09-24 addendum.

| Line | Owner |
|---|---|
| `SOLEUR_SENTRY_DSN=` on web-1 | `terraform_data.luks_monitor_install` (`workspaces-luks.tf`), re-fired when the DSN's hash or a delivered file changes |
| `SOLEUR_SENTRY_DSN=` on a fresh host | cloud-init, at the host's birth |
| `DOPPLER_TOKEN=` | unchanged: the 2026-09-24 table |

Each writer keeps the other's line. The DSN writer drops only `^SOLEUR_SENTRY_DSN=` lines and
refuses if any other line changed. The token helper does the same for its own line. `depends_on`
runs the token installer first within one apply.

**The DSN precondition, and its blast radius.** The resource accepts an empty `var.sentry_dsn`, or
one matching `^https://[A-Za-z0-9]+@[A-Za-z0-9.-]+/[0-9]+$` (the expression `inngest-host.tf`
already uses). The class is strict because the value lands in a single-quoted shell `printf` and in
a file that root sources. Empty is allowed at plan time on purpose. A failed precondition stops the
whole `-target`-scoped SSH apply, every SSH-provisioned resource in it, and other workflows plan this
root too. So the host-side writer refuses an empty value instead (exit 10), which fails only this
resource. A malformed non-empty value still fails the precondition and stops the SSH apply step.
That is deliberate: writing it would put an unchecked string into a file root sources.

**Proof boundary, qualified.** The 2026-09-24 "Proof boundary" paragraph still holds for the token
installer: it never starts `luks-monitor.service`. This installer starts it once, with `--no-block`,
so the apply never waits on the probe and a mount, escrow or readyz fault still cannot redden a
merge. What the apply asserts is delivery: `is-enabled` and `is-active` on the timer. The kick
exists to produce a same-day host row. It fires only when a delivered file or the DSN changes.

**The runtime proof is a logs alert, not the static guard.**
`logtail_exploration_alert.luks_monitor_host_timer_dark` (`soleur-luks-monitor-host-timer-dark-prd`,
in `betterstack-logs-alerts.tf`, per ADR-218) fires when the trailing 27 h holds no
`OK: /mnt/data is LUKS-backed` row from `_SYSTEMD_UNIT=luks-monitor.service`. The verify job's rows
never carry that unit, so it cannot mask the host. The heartbeat manifest now cites
`workspaces-luks.tf` as evidence, but a green static guard only proves the arming line exists. #8706
closes when `scripts/followthroughs/luks-monitor-host-timer-8706.sh` prints
`HOST_TIMER_PASS nights=3` after three consecutive timer-fired nights.

**Deviation from `hr-prod-host-config-change-immutable-redeploy`.** Two binaries, two unit files, one
env-file line, a `daemon-reload`, a timer enable and one service start change web-1 in place, over
SSH, through Terraform. This rests on ADR-154's standing exception, as the 2026-09-24 token line does:
web-1 cannot be redeployed, because `cx33` remains unorderable.

> **Qualified 2026-09-27 (#8706 review):** "`cx33` remains unorderable" is re-measured in ADR-154's
> [Re-examined 2026-09-27 (#8706)](./ADR-154-repair-the-credential-channel-not-the-host.md#consequences)
> block: available in 0 of 6 datacenters. The exception stands for this change.

**Known gap, not fixed here.** A cutover that aborts after the host canary leaves the dead-man timer
armed: `cleanup()` does nothing once `CANARY_OK=1`, and both such runs died before
`disarm_dead_man`. What the dead-man did in July has aged out of log retention. A future re-cut must
not inherit this silently. It is tracked in #9045. Meanwhile this installer's state print shows the
dead-man units' state on every fire.

> **Superseded 2026-09-28 (#9045):** the gap is closed. The dead-man is disarmed at the host-canary
> pass, before `docker start`, so a post-canary abort has nothing armed. `cleanup()` also records a
> `result=cutover_aborted outcome=<x>` marker on every abort. See the
> [2026-09-28 addendum](#addendum-2026-09-28-the-dead-man-guards-the-freeze-window-only-9045).

### Review amendments (2026-09-27)

Appended after the 10-agent review of PR #9044. Each item below changes or qualifies a claim above.

- **`RequiresMountsFor=` became `After=`.** `luks-monitor.service` now carries
  `After=local-fs.target mnt-data.mount`, ordering only. `RequiresMountsFor=/mnt/data` is
  Requires-strength: starting the unit while `/mnt/data` is unmounted would start `mnt-data.mount`,
  which mounts whatever `/etc/fstab` names. On web-1 that can be the superseded plaintext volume,
  served over the only copy. The probe needs no mount to run: it checks `mountpoint -q /mnt/data`
  and reports `not_mounted` itself. Same downgrade as `inngest-cutover-flip.service` (#7228). This
  also corrects the §(a) claim that `RequiresMountsFor=` makes systemd "refuse to start" a unit (see
  the note there).

  > **Qualified 2026-09-28 (#9045):** "that can be the superseded plaintext volume" does not hold.
  > The fstab source is a literal glob that names no device. The ordering-only downgrade is still
  > correct, because a mount the unit started would still be wrong. See the §(a) note and #9123.
- **A cutover-freeze guard (exit 17).** Before it arms, the installer refuses with exit 17 when
  `workspaces-luks-deadman.timer` reads `SubState=waiting`: a cutover freeze is live. The apply goes
  red, the resource taints, and the next apply re-fires it. The plan cut an earlier freeze guard.
  That cut does not apply here. The cut guard keyed on the dead-man reading `active`, and an elapsed
  transient timer keeps `ActiveState=active`, `SubState=elapsed` until reboot, so an old July
  dead-man would have blocked every install. `SubState=waiting` is reported only by a live transient
  timer that has not fired yet, which is exactly a freeze in progress.

  > **Qualified 2026-09-28 (#9045):** "an elapsed transient timer keeps `ActiveState=active`,
  > `SubState=elapsed` until reboot" was never measured. The same run's state print shows the timer
  > `inactive/dead`. systemd.timer(5)'s `RemainAfterElapse=yes` default would keep it loaded, so the
  > two sources disagree. #9045's real-systemd loopback case measures it on systemd 255. The guard
  > keys on `SubState=waiting` and holds under either reading. Measured 2026-09-28 against a user
  > systemd 261 (the same case body, run unprivileged): once a transient timer fires, systemd
  > unloads it. It then reads `inactive/dead` with an empty `LastTriggerUSec`, which matches web-1's
  > print. The privileged CI run on systemd 255 is the authoritative reading.
- **Host scope.** The alert predicate gains `AND JSONExtractString(raw, 'host_name') =
  'soleur-web-platform'`. web-2 (`soleur-web-2`) ships to the same Logs source (measured
  2026-09-27). Its `incident_cause` no longer says "the volume is still encrypted": the alert also
  fires when the host run fails an assert. It means "no PASSING host run in about 27 h".
- **Lost drift events page.** The two exits in `workspaces-luks-emit.sh` that drop a drift event
  (no DSN resolved; the Sentry POST failed) now log
  `SOLEUR_WORKSPACES_LUKS_SEND_FAILED reason=no_dsn|send_failed drift_reason=<slug>` at
  `user.crit` through an `emit_refusal()` definer. So `logtail_exploration_alert.monitor_send_failed`
  pages on them. Sentry is the channel that failed, so the mirror is journal to Vector to Better
  Stack.
- **Script cleanup.** Terraform leaves an inline script's full body on the host when it exits
  non-zero. The DSN writer carries the DSN, so it now removes its own uploaded script
  (`rm -f -- "$0"`), uses the temp file `$f.dsn.tmp`, and has an EXIT trap. The state print removes
  the `/root/tf-luks-*.sh` stubs. The installer also deletes stale root-owned `/tmp/terraform_*.sh`
  older than 60 minutes: pre-#8706 failed runs could leave the token there. It chmods both binaries
  right after delivery, and its state print adds the `luks-monitor.service` state,
  `findmnt --fstab /mnt/data`, and `mnt-data.mount`'s `What` and `FragmentPath`.
- **An empty DSN leaves the timer unarmed.** The DSN writer runs before the arming step. So its
  exit 10 means that fire does not arm the timer, and the apply stays red until the DSN is fixed.
  Writer exits: 10 empty DSN, 11 symlink, 12 not a regular file, 13 read error, 14 another line
  would change, 15 not exactly one DSN line, 16 `mv` failed. Installer exit 17: cutover freeze live.
- **The DSN fallback claim is asserted.** See the qualification under "The DSN line is the only
  Sentry path on web-1".
- **`query_period = 97200` is measured, not assumed.** Better Stack's docs list no bounds. On
  2026-09-27 a throwaway PAUSED alert was created on the live API with `query_period = 97200`, read
  back `query_period:97200 confirmation_period:0` (not clamped), and deleted.
- **The dead-man gap** above is tracked in #9045.

## Addendum (2026-09-28): the dead-man guards the freeze window only (#9045)

**Decision.** The cutover disarms the dead-man once, at the host-canary pass, before
`docker start`. This follows from §(b): the rollback door closes at `docker start`, so an unattended
revert after it strands every write the app made on the LUKS mount. That is the 2026-07-20 incident.
The cutover previously kept the dead-man armed across `app_canary`, as an app-health backstop. That
intent is reversed: app health is attended, and the dead-man now guards the freeze only.

The mechanics live in `workspaces-cutover.sh`:

- **`arm_dead_man` fails closed and verifies itself.**
  - It refuses when a timer already reads `SubState=waiting` or a fire is live
    (`ActiveState` `active`, `activating` or `deactivating`; a running fire is a simple service,
    so it reads `active`).
  - It clears a stale unit before arming: it stops the timer, then runs `reset-failed` on both units.
  - It no longer discards `systemd-run`'s error; a refusal emits `result=arm_failed` with the first
    stderr line, scrubbed, as `detail=`. Every arm failure `die`s, so the freeze never starts behind an
    unverified backstop.
  - It sets `DEADMAN_ARMED=1` as soon as `systemd-run` returns, then polls for `waiting`.
  - The arm runs BEFORE `FREEZE_HELD=1`, so a failed arm leaves no freeze to unwind.
- **`disarm_dead_man <reason>` verifies and never `die`s.**
  - It reads the timer's `LastTriggerUSec` before the stop, and after the stop the service's
    `ActiveState` and any queued start `Job`.
  - It checks that the timer is no longer `waiting`.
  - Any failed check emits `result=disarm_failed … check=<a|b|c>`.
  - The reasons are a closed set: `host_canary_passed`, `rollback_engaged`, `arm_aborted`.
- **The host canary gates the disarm.**
  - Before disarming, it compares the workspace count on the live `$MOUNT` against the count G3 took
    in THIS run (an in-process value, never the append-only state file, which carries earlier runs'
    counts). A missing count fails closed, and a G3 count failure is now fatal at G3
    (`workspace_count_persist_failed`), where the rollback is lossless.
  - This re-proves that the mounted filesystem is the copy G3 counted and that the repoint landed.
    It is not a plaintext-versus-copy population proof; that proof is G3 against G2, plus C1.
  - After disarming, `findmnt -no SOURCE "$MOUNT"` must still equal the mapper, because a fire that
    raced the disarm unmounts `$MOUNT`.
  - Either failure dies while `CANARY_OK=0`, so the rollback is still lossless.
  - The `findmnt` re-assert is the real proof. A fired transient timer is unloaded, so its
    `LastTriggerUSec` reads empty and check (a) only catches a fire in the short window before
    that. This was measured on systemd 261; see the qualification under the 2026-09-27 review
    amendments.
- **`rollback()` stops the timer first, then waits.**
  - With the dead-man armed it runs the verifying disarm, which stops the timer, so no new fire can
    start. It then waits, bounded by attempt count, for a fire already in flight to finish, and
    emits `check=fire_stuck` only if that wait expires.
  - With nothing armed by this run it records the timer's prior state (`result=not_armed
    prior=<substate>`). If this run armed and already disarmed, it records `result=already_disarmed`.
  - It restarts the app only when the plaintext volume is mounted. A failed remount leaves the app
    down and pages `rollback_remount_failed`, rather than starting it on the bare root-disk directory.
- **`cleanup()` records one outcome on every abort**, on the existing `luks-monitor` tag:
  `SOLEUR_WORKSPACES_LUKS_DEADMAN … result=cutover_aborted outcome=<x>`. The values are:
  - `rolled_back` — one plaintext mount and the mapper closed;
  - `rollback_stacked` — a mount stacked on another, or the mapper still open (pages);
  - `rollback_remount_failed` — nothing, or the mapper, is mounted;
  - `post_canary_luks_retained` — rolled forward and the app restarted;
  - `post_canary_restart_failed` — rolled forward, but `docker start` failed;
  - `post_canary_mount_not_mapper` — the mount is no longer the mapper, so the app and writers were
    stopped;
  - `arm_aborted`, `pre_freeze`, `clean_stray`, `dry_run`.
- **`cleanup()` is signal-safe.**
  - The workflow runs the script over `ssh` without a pty, so a dropped connection does not deliver
    SIGHUP. The script dies of SIGPIPE on its next write, and bash still runs the EXIT trap.
  - Two defects made that trap silent, and both are fixed:
    - `$?` inside the trap is the last command's status, usually 0, so the trap took the success
      exit. A `RUN_COMPLETE` sentinel, set only at intentional exits, now separates a normal end
      from a signal death, which is recorded with `abnormal_exit=1`.
    - The trap's own first `log` raised SIGPIPE again and killed it. It now ignores PIPE, HUP,
      INT and TERM.
- **A post-canary abort rolls FORWARD.** `cleanup()` re-asserts the mapper, restarts the app with its
  exit status checked, and resumes writers. It pages through the fatal Sentry drift
  `cutover_aborted_post_canary`. If the mapper re-assert fails, it stops the app and the writers, so
  nothing writes to a mount that is not the mapper. The runbook makes this path fix-forward only.
- **`ROLLBACK=1` refuses after a successful cutover.** When the persisted `CANARY_OK` matches the
  live volume's LUKS UUID, a rollback dispatch refuses unless the `rollback_ack_luks_writes` input
  is set. Such a rollback strands every write made since `docker start` on the LUKS volume. It also
  refuses, with the same override, when `CANARY_OK` is persisted but the live header UUID cannot be
  read (a closed mapper included) or the persisted UUID is empty: an unmeasurable match fails closed.
  A refusal records `outcome=refused_post_cutover mode=rollback mount_src=<source>`. (Corrected
  2026-09-30, PR #9286 review: the check no longer requires `/mnt/data` to be on the mapper. Keyed on
  the mount, an unacked rollback after a failed boot unlock, with `/mnt/data` empty, would have
  served the stale plaintext.)
- **An unattended fire pages.** `logtail_exploration_alert.workspaces_luks_deadman_fired` (ADR-218
  semantics) matches `op=workspaces-luks-deadman result=fired` from `soleur-web-platform`. This
  closes the #6812 six-hour silence. The alert auto-resolves after ten quiet minutes; that does not
  mean the stranded writes were reconciled.

**Rejected alternatives.**

- **Keep the dead-man armed across `app_canary`, or only for data-shaped `readyz` failures.** Either
  way an automated revert still strands writes. C1 byte-identity, the G3 count and the host-canary
  device anchor already certify the data before the door.
- **A fire-time guard inside the dead-man's `sh -c` keyed on `CANARY_OK`.** The state file persists
  across runs, so a stale `CANARY_OK` could suppress a legitimate pre-canary revert.
- **Clear web-1's failed dead-man unit now through Terraform.** That is a host mutation with no
  functional gain, and it would destroy the evidence before the forensic print reads it.
- **A watchdog for a SIGKILL.** Disproportionate. An SSH drop is SIGPIPE, not SIGKILL, and the
  signal-safe `cleanup()` handles it. Two SIGKILL residuals are accepted:
  - after the host-canary disarm, where nothing is armed and nothing records an outcome;
  - mid-`rollback()` after its own disarm, where the app stays down with no backstop.

  Neither loses data: both land before the app serves from the LUKS mount, or on a mount already
  certified. The uptime monitor pages both.

**Accepted narrowing.** The installer's exit-17 guard keys on the dead-man reading `waiting`, which
now spans only the freeze, not the whole run. An apply that lands between the host-canary door and
the cutover's tail passes the guard. It redelivers files the tail also installs, and kicks the monitor
probe while `app_canary` boots the app. The worst case is a false readyz page during an attended
cutover. No user data is touched.

**What the dead-man did in July (H1/H2).** The 2026-09-27 state print showed
`workspaces-luks-deadman.service` `failed` (`Result=exit-code`) and the timer `inactive/dead`.

- **H1 (favoured).** The 2026-07-20 fire left the service loaded and failed, and only a dry run
  touched the unit before 2026-07-23. On 07-23, `systemd-run --unit=workspaces-luks-deadman` was
  refused, the refusal was discarded (`2>/dev/null || true`), and `result=armed` was logged anyway.
  The 07-23 dead-man never armed, which is why the LUKS mount survived that post-canary abort.
- **H2.** It armed and failed on firing. This is disfavoured, because the live mount is the mapper.

The discriminator is the new forensic print. It shows `ExecMainExitTimestamp`, and whether the
loaded unit's `ExecStart` contains `result=fired`, a substring that exists only in the post-#6807
fire command. An exit on 2026-07-20 without that substring confirms H1. The verdict is posted on
#9045 from the first apply after merge.

**Print/installer coupling.** The forensic step's command list is `local.luks_monitor_forensic_print`,
and it is folded into `terraform_data.luks_monitor_install`'s `triggers_replace`. So any later edit
to the print re-delivers the installer on web-1: files byte-identical, the DSN line rewritten
identically, one extra probe kick. The step runs BEFORE the exit-17 freeze guard, so a live freeze
cannot suppress it. It reads manager-memory properties, which survive journal rotation. It never
prints `ExecStart` itself or a journal tail, because a transient unit's journal echoes its command
line into the public Actions log. This is another in-place web-1 change under ADR-154's standing
exception (re-examined 2026-09-28: `cx33` is available in 0 of 6 datacenters).

> **Qualified 2026-09-28 (#9123):** "available in 0 of 6 datacenters" was the 08:05Z sample.
> The 21:31Z–21:34Z re-probe for #9123 reads `cx33` **available** in `hel1-dc2` and `fsn1-dc14`
> — the first ✓ in web-1's DC since 2026-08-01. See the next addendum and ADR-154's #9123 note.

**Reboot hazard.** The fstab finding moved the green-path reboot instruction (C15) to #9123. A
web-1 restart currently lands in emergency mode, so no reboot is planned until the coupled
fstab + crypttab + §(e) gate fix ships.

> **Delivered 2026-09-28 (#9123):** the coupled fstab + crypttab + §(e) gate fix is the next
> addendum. The C15 restart proof itself stays the runbook's separate supervised step — it is
> unblocked, not performed, by this delivery.

## Addendum (2026-09-28): the §(e) mount gate and the boot unlock have a Terraform owner (#9123)

**What was wrong.** Three coupled boot-path defects made a web-1 restart a site-down event,
measured in the apply-run prints (run 36340195638; `reboot-required=yes` on run 36425473000),
not inferred:

1. `/etc/fstab` on web-1 carries the **literal** glob `/dev/disk/by-id/scsi-0HC_Volume_*` — the
   unexpanded first-boot line of 2026-03-17. systemd-fstab-generator expands no globs and the
   line has no `nofail`, so `mnt-data.mount` waits on a device that can never appear and
   `local-fs.target` fails into emergency mode.
2. `/dev/mapper/workspaces` — the live `/mnt/data` source since the 2026-07-23 cutover — is in
   neither fstab nor crypttab. Nothing unlocks it at boot: no crypttab line, no key-fetch unit.
3. §(e)'s structural mount gate never reached web-1. It routed through the cutover channel and
   no cutover tail ever ran to completion — the same delivery gap that left the monitor units
   uninstalled for nine weeks (the 2026-09-27 addendum).

The obvious one-line fix — rewrite fstab to `/dev/mapper/workspaces … nofail` alone — is worse
than the defect: the boot then succeeds with `/mnt/data` as a bare root-disk directory, dockerd
resurrects the app container over `--restart unless-stopped`, and sole-copy workspaces land on
the unencrypted root disk. The three parts are coupled and land atomically.

**Decision.** `terraform_data.workspaces_boot_unlock_install` in `workspaces-luks.tf` owns the
delivery, riding the same CF-Tunnel-SSH apply stage as `terraform_data.luks_monitor_install`
(the #8706 precedent extended), with `depends_on` on both monitor installers so the token and
the probe channel land first. In one resource fire it:

1. prints the read-only "before" state (field-selected fstab source, crypttab
   `^[[:space:]]*workspaces[[:space:]]` count — an INDENTED `workspaces` mapping is live
   crypttab syntax, so the anchor skips leading whitespace, unit states);
2. delivers the `workspaces-luks-reopen` family — the phase-tagged reopen script
   (`config → key → device → header → open → identity → target → mount → identity-mount →
   emit`), the `Type=oneshot` unit with the bounded restart ladder, the `-failure.service`
   reporter, and the standing-retry `.timer` — modelled on the `git-data-luks-reopen` family
   (#8210);
3. appends-if-absent the crypttab line `workspaces
   /dev/disk/by-id/scsi-0HC_Volume_<hcloud_volume.workspaces_luks.id> none luks,noauto` —
   FIRST of the mutating steps, so an exit-32 foreign-line refusal leaves the consistent OLD
   pin pair;
4. writes `/etc/default/workspaces-luks-boot` (0600 root: the by-id device pin and the Doppler
   config name — a NEW env file; `/etc/default/luks-monitor`'s two-writer ownership is
   untouched, the reopen unit reads `DOPPLER_TOKEN` through it and never writes);
5. arms the §(e) gate: `docker.service.d/10-workspaces-luks-mount.conf` carrying
   `RequiresMountsFor=/mnt/data` AND `After=workspaces-luks-reopen.service` (docker
   fails-then-retries under `RequiresMountsFor` — its own restart policy re-queues it —
   while `mnt-data.mount`'s device wait can still race `dev-mapper-workspaces.device`'s
   timeout), plus
   `chattr +i` on the **covered** root-disk `/mnt/data` inode through a non-recursive
   `mount --bind /` peek — the mapper is mounted, so the baked gate's `mountpoint -q`-guarded
   arm cannot reach that inode on web-1. The gate lands BEFORE the fstab rewrite: a
   mid-window abort leaves the boot fail-closed (emergency mode), never
   fstab-fixed-but-gate-absent;
6. rewrites fstab idempotently to exactly one `/dev/mapper/workspaces /mnt/data ext4
   defaults,nofail 0 2` line, commenting every superseded line and refusing on a zero- or
   two-plus-`/mnt/data` post-edit table;
7. daemon-reloads (docker is never restarted — the drop-in takes effect at the next
   `docker.service` start), enables the units, and runs one proof start of the reopen service,
   which takes the `noop` arm on the live system — the mapper is already open, so the run
   exercises config/key/device/header/identity/target/mount end to end without touching the
   mount;
8. prints the post-state into the apply log: `findmnt --fstab`, `crypttab-workspaces-lines`,
   unit states, `lsattr -d` through a second peek, `systemd-analyze verify`.

Every remote-exec mutating step refuses with the exit-17 convention while
`workspaces-luks-deadman.timer` reads `SubState=waiting` — the four file provisioners land
inert payloads before the first remote-exec check (the units stay un-enabled until `arm`),
and the installer and a live cutover are mutually exclusive around the /mnt/data mount
epoch: the cutover never writes fstab, but a mid-flight fstab writer races its mount flip.
`triggers_replace` hashes every delivered byte (the four files plus the writer locals), so
an edit to delivered bytes re-fires the installer; host-side drift is caught by the units'
and the daily probe's own asserts, not the apply — nothing marks the host done permanently.

**What this changes in §(e).** §(e)'s last standing claim — "the live delivery path for web-1
is the cutover job's SSH channel" — is superseded for the mount gate too. The gate and the
unlock reach web-1 through Terraform, as the monitor units did under #8706. The cutover tail
stays: it installs the same state a future re-cut re-verifies, and it remains the only writer
*while a cutover owns the freeze* (which is why the exit-17 refusal exists). The bake
(`soleur-luks-structural-gate`) is unchanged and stays the fresh-host convention; #6931 owns
the fresh-host boot-unlock path and is deliberately not this work.

**The §(e) gate's honest boundary.** The drop-in + covered-inode `chattr +i` is a tripwire
for dockerd-class resurrection — a daemon or an unprivileged process cannot write the bare
root-disk `/mnt/data` while the mapper is absent. It is NOT an adversarial boundary: root
can still mount over the covered inode or rename it, and nothing here resists that. What
covers that residual is the daily `luks-monitor` probe's mount-source/identity asserts
(`findmnt` source == `/dev/mapper/workspaces`, cryptsetup mapper→device link, header UUID),
which page the drift a mount-over would create.

**The crypttab divergence is recorded, not reconciled.** The baked gate writes `workspaces
/dev/disk/by-label/workspaces_luks none luks,nofail`; web-1's line is `workspaces
/dev/disk/by-id/scsi-0HC_Volume_<id> none luks,noauto`. Two deliberate differences:

- **by-id over by-label** — the repo's volume-pinning convention (#6604), Terraform-interpolated
  from `hcloud_volume.workspaces_luks.id`. Nothing in the cutover writes a `workspaces_luks`
  LUKS label, so the by-label spelling would not resolve on web-1 today.
- **`noauto` over `nofail`** — on web-1 the reopen unit owns the unlock, so the
  `systemd-cryptsetup@workspaces` ask-password job must not enter boot ordering at all: under
  `nofail` it would sit in a bounded interactive-timeout window every boot and could race the
  unit's `luksOpen`. crypttab stays declarative — the declared mapping and the manual-recovery
  handle — while the unit does the work. The baked `nofail` was written for a host whose unlock
  half is deferred; when #6931 lands, the baked line should be reconciled to this shape.

**Delivery vs. decision.** The decision is true at merge; the *delivery* is verified
post-apply — the installer's before/after prints must show the single mapper fstab line,
`crypttab-workspaces-lines=1`, the units enabled, the peek `lsattr -d` showing `i`, and the
proof run reporting `noop` — the #8706 print contract extended, plus the unchanged daily
`workspaces-luks-verify` job. A success-path emit deliberately does NOT page: `op` is hardcoded
to the sole paging op `workspaces-luks-drift`, so success is a journald row under
`SyslogIdentifier=workspaces-luks-reopen` (registered in `vector.toml`, re-delivered by
`terraform_data.journald_persistent`), and only an exhausted restart ladder emits one fatal
envelope naming the failing phase.

**Deviation from `hr-prod-host-config-change-immutable-redeploy`.** This is a multi-file
in-place delivery on web-1 over SSH through Terraform — the same class as #8706, resting on
ADR-154's standing exception. Re-examined the same day
([ADR-154's #9123 note](./ADR-154-repair-the-credential-channel-not-the-host.md#consequences)):
the probe reads `cx33` **available** in `hel1-dc2` for the first time since 2026-08-01, so the
exception's expiry question is live and the immutable-redeploy route is re-weighed on #9123
before this ships — the plan's own instruction when a probe reads ✓.

**The runbook's C15 step is unblocked, not performed.** `workspaces-luks-cutover-6604.md` §4's
"Boot-path re-canary (C15)" moved from blocked-on-#9123 to delivered-by-#9123: the proof itself
is unchanged — one supervised restart, then the read-only verify — and it stays the runbook's
separate gated step, not a step of this delivery.

## Addendum (2026-09-28): retiring the plaintext backstop (CONFIRM_WIPE, #6604 step 7)

**Status stays `adopting`.** It flips to `accepted` only in PR B, after the dispatch below has run and
the Art. 5(2) destruction record is complete — the #6604 soak sweeper closes that issue on the string
`accepted` alone.

The soak passed on 2026-09-24. The last open item of this ADR is §(f)'s "terminal mode": until the
retained plaintext volume (`105149570`) is gone, it holds every workspace as of the 2026-07-23 cutover,
including ones users have deleted since, and defeats every Art. 17 erasure made on the live volume.

**Decision.** Build the `CONFIRM_WIPE` slot this ADR reserved as a mode of `workspaces-cutover.sh`
(`wipe_plaintext()`), reached through a separate, environment-gated `wipe` job in
`workspaces-luks-cutover.yml`, followed by a single-use `workspaces-plaintext-forget.yml` for the
Terraform state, and a second PR (PR B) that narrows the `for_each`s. Plan:
`2026-09-28-feat-workspaces-plaintext-volume-wipe-plan.md`; runbook: Sequence step 7.

- **AP-009 (Never delete user data): Deviation — documented carve-out.** The volume is **a superseded
  copy frozen at the 2026-07-23 cutover** (run 29995956562), which the live LUKS volume was certified to
  hold at least the contents of (C1 itemized verify, G3 counts, the git fsck differential),
  green-verified daily since, soak passed 2026-09-24. It is *not* "a duplicate" (the CLEAN_STRAY basis):
  it differs from the live volume by every deletion since the cutover, which is exactly why it must go.
  Retaining it is the exposure #6588 exists to close. The accepted residual is stated, not hidden: after
  the wipe the LUKS volume holds the **only** copy (tracked by #5274, #8625, #6964). W4/W5 exist so the
  wipe never runs while that sole copy is unrecoverable.
- **AP-001 (Terraform-only infrastructure provisioning): Deviation.** The delete is an API act, not a Terraform one: Terraform
  cannot zero a device, and C5 requires a verified full-device zero to precede the delete. State
  follows by `terraform state rm`, then config by PR B.
- **The one property.** `blkdiscard -z` runs on exactly one device, the pinned volume, never the device
  backing `/dev/mapper/workspaces`. The pin (`expected_plaintext_volume_id`) is bound through preflight's
  API classification, the host's by-id path (W1), path + major:minor + holders + mount + size +
  hypervisor `ID_SERIAL` + the cutover's recorded plaintext mount source `PLAINTEXT_DEV` (W6, first wipe only; the label
  premise was false — no artifact labels the retained plaintext, corrected 2026-09-30), every systemd
  device unit sharing the
  target's `SysFSPath` (W6b), the success row the job parses, and the forget's state identity.
  Recoverability of the sole copy is proven at wipe time: the persisted `CANARY_OK` UUID names the live
  header (W3), the escrowed passphrase opens it (W4), and the off-host header object downloads, carries
  that UUID, opens with that passphrase, and is byte-identical to a fresh `luksHeaderBackup` (W5 — a UUID
  survives `luksAddKey`, so a UUID match alone could certify a stale backup).
- **The zero is proven, not assumed.** `blkdiscard -z` (util-linux >= 2.36 opens O_EXCL; never `-f`)
  under a 150 MB/s cgroup `io.max` cap (plain bytes, `150000000` — systemd reads a `150M` suffix in base 1000) (not `ionice`, a no-op under `mq-deadline`/`none`), then a full-device
  O_DIRECT read-back that `cmp` decides (dd's rc alone never classifies), then no signature, and only
  then `PLAINTEXT_WIPED`. The cap is **proven in force**, not assumed from `systemd-run`'s rc (0 even
  when io.max cannot apply): a gate running inside the scope reads that scope's own `io.max` for the
  device's MAJ:MIN and refuses unless `rbps`/`wbps` carry the cap; the zero and the read-back run behind
  the same gate. The identity is re-asserted AT the act (the by-id link still resolves to the measured
  kernel name, which still carries the pin's serial), and W6b re-runs after the zero, before the success
  row. `PLAINTEXT_WIPE_BEGUN` is persisted first, so an interrupted zero resumes on `arm=re_zero`; a
  zeroed-and-detached volume reports `arm=detached`. Both markers are written **and read back**; an
  unwritable state file refuses before the zero (or before the success row).
- **Provenance and completeness.** A first wipe refuses a plaintext whose superblock `Last write time`
  is later than the cutover froze it (2026-07-23T09:45:00Z; run 29995956562's host step ended 09:40:41Z):
  such a volume was remounted read-write since and may hold writes that exist nowhere else. As evidence
  (never a refusal) the rehearsal lists the workspace names on the unmounted plaintext (read-only
  `debugfs`) that the live mount lacks (`plaintext_only=`); the approver's ask accounts for each.
- **Post-wipe rollback is refused permanently**, with or without the ack, on either of two witnesses: a
  persisted wipe marker (`outcome=refused_plaintext_wiped`, the only proof of a wipe), or `/mnt/data`
  on the mapper with the recorded `PLAINTEXT_DEV` not an intact restore source: invalid, resolving to
  the mapper, not a block device, or not ext4 (`outcome=refused_plaintext_record_gone`, its own slug:
  with no marker it is drift or a detach, never a wipe; a lost record reads as gone: it refuses). One
  predicate, `_plaintext_record_status`, decides "intact" for this check, the dead-man arm and the
  rollback remount (corrected 2026-09-30, PR #9286 review). The check is the first
  line of `rollback()` itself, so every caller is covered, and the dead-man fire string carries its own
  self-contained copy. Arming a dead-man stays unreachable on a cut-over host: `prepare_staging_target`
  refuses it first.

**Two PRs, because Terraform will not take one.** Measured on Terraform 1.10.5 against a scratch root:
a narrowed `for_each` over state still holding `["web-1"]` makes every `-refresh=false` plan fail with
`Instance cannot be destroyed` (`prevent_destroy`, which web-2 keeps); `moved` + `removed` makes every
`-target`ed plan fail with `Moved resource instances excluded by targeting` until an untargeted apply
this root never runs; and `state rm` with the OLD config still in place makes any push apply plan
`+create` of a fresh plaintext volume through `-target` transitivity (`hcloud_firewall_attachment.web`
→ `hcloud_server.web` → `user_data` → `hcloud_volume.workspaces[each.key]`), conditional or not. Only
`state rm` then narrowed config plans `No changes`. So: PR A (the mode, no `.tf` change), the dispatch,
the forget, PR B the same day.

**The delete→PR-B window is closed by a pause, not a new guard.** Both push-apply workflows
(`apply-web-platform-infra.yml`, `apply-deploy-pipeline-fix.yml`) are `gh workflow disable`d before the
dispatch and re-enabled after PR B, with a `manual-rerun` apply. The `wipe` job and the forget
workflow refuse unless both read `disabled_manually` with nothing queued. A create-counting surface on
the shared destroy-guard filter would reverse #6919 (test T55 — volume creates were removed from the
halt because they fired on valid dispatches) and needs an edit to a file a few hundred bytes under its
size cap; #6919/T55 stands.

**How the 2026-07-19 operand rule is kept.** "Every destructive mode contributes its own operand to the
`cutover` job's `environment:` expression" holds by construction: the destructive wipe is not reachable
from `cutover` at all. That job skips on a real wipe, and on a rehearsal delivers `CONFIRM_WIPE` only as
`wipe_plaintext && dry_run`. The `wipe` job's environment is unconditional.

**Serialization, and why the forget is its own workflow.** The forget runs in its own workflow on
`terraform-apply-web-platform-host` (the lockless state's sole serializer). The reasons it is separate
are **credential separation** — the destructive job (root SSH to web-1 and a Hetzner write token) never
holds the R2 state credentials or runs `terraform init`, and the forget holds nothing that reaches web-1
— and **idempotent re-runnability**: a failed forget is re-dispatched on its own (`already_forgotten`
once state is clean) and never re-enters the wipe. Lock order is not the reason: with both appliers
proven paused and idle, no apply can hold the host group, so nesting it could not deadlock in the
window; the host group is belt.

**A known gap, recorded, and the trade-off.** The `wipe` job's SSH delivery block is a **copy** of
`cutover`'s. Byte-stability of the freeze path is not the reason any more — the freeze already ran and a
cut-over host refuses it. The copy is kept because the two jobs differ where it matters (the wipe job
fences all host output, keeps the tunnel alive through a silent zero, and parses a strict success row),
and extracting a shared composite action would put the 2026-07-23-proven cutover delivery behind a new,
unexercised abstraction. The cost: the rehearsal rides `cutover`'s copy, so the `wipe` job's copy first
runs on the host at the real dispatch. It is mitigated, not closed: the remote `bash -c` delivery string
is byte-identical in both (the workflow suite pins it), both copies' bodies are executed against an ssh
stub, the host half is the same script, and every failure mode of the copy is fail-closed (a red run,
never a wrong zero).

## Addendum (PENDING-EVIDENCE(D-date)): the plaintext backstop is retired (#6604 step 7, PR B)

**Status stays `adopting`** in this addendum's draft. It flips to `accepted` in its own commit, after
the Art. 5(2) destruction record (`knowledge-base/legal/audits/workspaces-plaintext-destruction-record.md`)
reads `status: complete` and the CLO has attested at that commit
(`knowledge-base/legal/audits/2026-10-counsel-review-6604.md`). PR B (#9348) is the convergence half of
the 2026-09-28 addendum above; it stays a draft until the evidence exists.

**What ran (by reference to the record).** The as-run facts — the dispatch run(s), the `wiped` row, the
read-back, the detach and delete, the state forget, the approver — live in the destruction record and
nowhere else; this addendum does not restate them. Dispatch: PENDING-EVIDENCE(D-run-id). Forget:
PENDING-EVIDENCE(forget-run-id). Evidence already in hand: rehearsal run `36769782488` (2026-09-30,
`result=rehearsal_ok arm=first_wipe volume_id=105149570`, `target=/dev/sdb` ≠ `backing=/dev/sdc`,
`holders=0 dependents=0`, `plaintext_only=0`) and the same-day baseline run `36770448813`
(`ready=true workspace_count=9 expected=8`).

- **AP-009 basis, as run.** The deleted volume was a superseded copy frozen at the 2026-07-23 cutover
  (run 29995956562, 8 workspaces). At the rehearsal, `plaintext_only=0`: no workspace existed only on
  that copy, so the wipe destroyed nothing the live volume lacked.
- **The accepted drop to a single copy.** Volume `106443278` (`hcloud_volume.workspaces_luks`) now holds
  the only copy of every workspace. There is no backup and no snapshot of it; escrow (the Doppler
  passphrase and the off-host header) covers key loss, not data loss. Hardware loss of that volume stays
  open and is tracked by #5274 and #8625; a web-1 rebirth that strands it is #6964. This is the residual
  the 2026-09-28 addendum named; it is accepted, not closed.
- **D1 — the sole copy is protected in Terraform.** `hcloud_volume.workspaces_luks` gains
  `prevent_destroy = true` and `delete_protection = true`. `prevent_destroy` makes every plan that
  would destroy or replace it fail — the `workspaces-luks-recut` dispatch's `-replace`, or a ForceNew
  edit reaching it through the SSH stage's `-auto-approve` apply (it is in that stage's `-target`
  closure through `terraform_data.workspaces_boot_unlock_install`). `delete_protection` makes Hetzner
  refuse a console, API or CLI delete until someone holding a write token lifts it; it is delivered as
  one in-place update by the post-merge `manual-rerun` apply. Both are accident guards, not access
  controls: a reviewed PR can remove them. This **supersedes** #6931's deferral of `prevent_destroy`,
  which existed only because it collided with the recut `-replace` — whose premise, that the live
  plaintext keeps serving as the rollback source, is false after step 7. The recut `-replace` is
  therefore retired for the live volume: it now plan-fails with `Instance cannot be destroyed`, which is
  the guard, not a defect. Retiring or re-scoping the recut dispatch arm itself is #6931's topology
  work. **Ordering trap for #6931:** if `prevent_destroy` is removed while `delete_protection` stays
  on, a destroy apply detaches the mounted volume and then fails the delete — an outage. Lift
  `delete_protection` first, in its own reviewed apply.
- **Terraform converges on web-1 having no plaintext volume.** `hcloud_volume.workspaces` and
  `hcloud_volume_attachment.workspaces` range over `local.plaintext_workspaces_hosts` (every web host
  except web-1; web-2 keeps volume `106466179`, still `prevent_destroy`, still a ledgered posture
  exception, now tracked by #6931). web-1's `workspaces_volume_id` template argument is the literal
  `"retired-6604"`: a rebuilt web-1 would emit `workspaces_mount fatal` and keep booting on an empty
  `/mnt/data` (fails loud, not closed), unreachable while the replace path refuses web-1 and
  `user_data` is `ignore_changes`.
- **The `CONFIRM_WIPE` mode is a tombstone.** The wipe body, `wipe_plaintext()` and its helpers, the
  `wipe` job and the forget workflow are deleted by PR #9348 (the procedure as run is in git history at
  `59abf6a76c`). Until that merge they exist on `main` only, and D and the forget are dispatched from
  `main` (the `workspaces-luks-cutover` environment admits `main` only), so they run `main`'s copies and
  every resume arm stays available until the merge deletes them. `CONFIRM_WIPE` stays declared and counted by `assert_mode_exclusive`; any value other
  than unset or `0` writes one `result=cutover_aborted outcome=wipe_retired` row, drops the EXIT trap and
  dies before any mutation, so a stray value can neither wipe nor fall through to the L3 cutover body.
  The tombstone deliberately calls no `emit_drift`.
- **Guard 5 is kept, for ever.** The post-wipe rollback refusal — the `PLAINTEXT_WIPE_BEGUN` /
  `PLAINTEXT_WIPED` marker witness and the physical witness through `_plaintext_record_status` — stays
  at the first line of `rollback()`, in `assert_rollback_not_post_cutover` and in the dead-man fire's
  `gone_guard`, with its tests (now `workspaces-luks-rollback-refusal.test.sh` and loopback Session G5).
  After step 7 there is no plaintext copy to remount, so a rollback that unmounted the mapper would make
  every workspace unreachable.
- **The sweeper and the drift window.** The #6604 soak sweeper (`workspaces-luks-soak-6604.sh`) closes
  #6604 on `accepted` plus a clean 7-day `op:workspaces-luks-drift` window plus a heartbeat span. Its
  Sentry query has no level filter, so any refused rehearsal or refused dispatch restarts that window
  (its 2026-09-29/30 FAILs were the refused rehearsal's `wipe_target_label_mismatch` events, run
  36710773788, fixed by #9286). This addendum does not change the sweeper; the tombstone emits no drift
  so a stray `CONFIRM_WIPE` cannot restart it.
- **Gates that name the retired addresses now pass vacuously on those names.** The gates that treat
  `hcloud_volume.workspaces["web-1"]` / `hcloud_volume_attachment.workspaces["web-1"]` as
  must-be-untouched (`inngest-volume-recut-gate.sh`, `workspaces-luks-cutover-gate.sh`,
  `workspaces-luks-recut-gate.sh`, and the post-apply backstop loops in `apply-web-platform-infra.yml`)
  can no longer meet those addresses in a plan. Safety holds through their `out_of_scope` /
  `resource_deletes` catch-alls and the loops' `create` verb (after PR B those addresses can only appear
  as a `create`, which the loops still catch); their stale "live plaintext" comments are corrected (text
  only), and the web-1 birth gate fails closed on a rebirth.

## References

- Issue #6588 — the P1 that mandated CTO routing before terraform.
- Issue #6649 — the header-escrow wiring (this addendum); part of #6604.
- `knowledge-base/project/plans/2026-07-17-fix-6588-luks-encrypt-workspaces-volume-plan.md` — the
  plan, its Premise Validation (8 issue premises did not survive), and the binding deepen corrections.
- `apps/web-platform/infra/workspaces-luks.tf` — the declaration this ADR rules.
- `apps/web-platform/infra/git-data-luks.tf` — the precedent, and the three deliberate divergences.
- ADR-068 §1 — per-user worktrees; note its "GitHub remains the durable rehydration source" does not
  hold for signup-provisioned workspaces (fact 3).
- ADR-080 — the baked-bootstrap convention; and why it has no consumer on web-1 (§(e)).
- #6538 (web-2 teardown), #6570 (cax11 stock), #6459 (active-active-N), #1439 (beta recruitment).
