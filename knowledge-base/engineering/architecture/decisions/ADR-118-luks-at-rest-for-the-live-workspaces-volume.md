---
adr: 118
title: Encrypt the live /workspaces volume additively — never replace the host that cannot be rebuilt
status: adopting
date: 2026-07-17
amends: none
supersedes: none
issue: 6588
---

# ADR-118: LUKS at rest for the live `/workspaces` volume

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

**Reboot is the sharper edge.** `docker run --restart unless-stopped` means `dockerd` resurrects the
container on reboot **without ever executing `docker run`** — so a pre-`docker run` gate catches
nothing on that path, and the `-v /mnt/data/workspaces` bind mount silently resolves to a **root-disk
dir Docker creates**. Result: container healthy, `/api/health` 200, **user source code written in
plaintext to the root disk**. The gate must therefore be structural, not procedural: a systemd unit
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

## References

- Issue #6588 — the P1 that mandated CTO routing before terraform.
- `knowledge-base/project/plans/2026-07-17-fix-6588-luks-encrypt-workspaces-volume-plan.md` — the
  plan, its Premise Validation (8 issue premises did not survive), and the binding deepen corrections.
- `apps/web-platform/infra/workspaces-luks.tf` — the declaration this ADR rules.
- `apps/web-platform/infra/git-data-luks.tf` — the precedent, and the three deliberate divergences.
- ADR-068 §1 — per-user worktrees; note its "GitHub remains the durable rehydration source" does not
  hold for signup-provisioned workspaces (fact 3).
- ADR-080 — the baked-bootstrap convention; and why it has no consumer on web-1 (§(e)).
- #6538 (web-2 teardown), #6570 (cax11 stock), #6459 (active-active-N), #1439 (beta recruitment).
