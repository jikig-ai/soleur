---
title: Guest-side fresh-boot LUKS for web hosts - one mechanism, two Terraform addresses
status: adopting
date: 2026-10-01
amends: none
supersedes: none
issue: 6931
related: [6964, 6604, 6588, 6730, 9348, 9357]
related_adrs: [ADR-143, ADR-119, ADR-068, ADR-148, ADR-140, ADR-141, ADR-164]
tags: [luks, web-host, fresh-boot, encryption-posture, terraform, doppler]
brand_survival_threshold: single-user incident
---

# ADR-263: Guest-side fresh-boot LUKS for web hosts - one mechanism, two Terraform addresses

## Status

**Adopting - 2026-10-01 (#6931).** The decision is true of the **template** (the baked provisioner and
its wiring in `apps/web-platform/infra/`) at merge, not of the live host. Merging changes no running host:
`user_data` and the image are ignored on the live web hosts and the web-2 volume's `format` is ignored
(D2). The claim "web-2 is LUKS-backed at boot" becomes true only after the single-use web-2 rebirth
described under "Live conversion" has run and the first on-host probe has read `crypto_LUKS` and a
mapper-backed `/mnt/data`. Until then web-2 keeps its Hetzner-pre-formatted plaintext volume, which
holds no user data and is kept that way by `lb-weight-gate.sh`.

The status flips to `accepted` when `scripts/followthroughs/web2-luks-live-6931.sh` exits 0: the
latest web-2 probe row reports `crypto_LUKS`, the `WORKSPACES_LUKS_CUTOVER_AT` marker is at least three
days old and no red row exists since. The probe is enrolled as a follow-through on #6931.

## Context

web-1 runs on LUKS (the additive volume `hcloud_volume.workspaces_luks`, ADR-119), but only because a
Terraform SSH installer delivered its boot-unlock units to the running pet host. A fresh host never
re-runs that installer. A web-2 born from the template therefore comes up on a Hetzner-formatted plaintext
volume (`hcloud_volume.workspaces` sets `format = "ext4"`), and nothing on a fresh boot opens a LUKS
mapper. The only thing keeping user data off that volume is a shape-only gate (`lb-weight-gate.sh`)
that a stray marker write could satisfy.

ADR-143 Implementation Rulings **R3** deferred the guest-side fresh-boot path to the Phase-4
disposability-proof PR (tracking #6931), made the defer fail-closed with three couplings, and listed
two corrections that PR must inherit: use the `blkid -o value -s TYPE` discriminator and never
`cryptsetup isLuks`, and reconcile the two-mechanism topology split. ADR-119 section (d) recorded the
opposite for web-2: out of scope, volume knowingly plaintext, and "a fresh web host must NOT get these
units". This ADR is the Phase-4 PR's decision record. (The issue body cites "ADR-142 Decision 3" and
its title cites "ADR-141 D3"; both ordinals are wrong. ADR-142 is the Inngest Redis AOF migration and
ADR-141 is encryption-posture Layer B. The binding text is ADR-143 R3.)

Three repo facts constrain the design:

1. **The `/workspaces` volume is the sole copy of user work.** A `luksFormat` or `mkfs` on a populated
   device is permanent, unrecoverable loss. The volume, not the host, is the protected asset.
2. **`moved` is unusable on this root.** ADR-119's 2026-09-28 addendum measured that a `moved` block fails
   every `-target` plan here, so any topology that needs a `state mv` of the sole-copy web-1 volume is a
   state-surgery step on the one asset with no rebuild path.
3. **`prevent_destroy` turns any planned replace of a volume into a failed apply** on every targeted
   plan that transitively reaches it (`hcloud_firewall_attachment.web` -> `hcloud_server.web` ->
   `user_data` -> `workspaces_volume_id`). A merge must therefore never plan a replace of the live volume.

## Decision

**D1 - Topology: one mechanism, two Terraform addresses.** web-1 keeps the additive singleton
(`hcloud_volume.workspaces_luks` and its attachment, untouched). web-2, and any future cattle key, keeps
the `for_each` volume `hcloud_volume.workspaces[key]`, now raw and LUKS-at-boot through the same baked
helper. The helper branches on `blkid`, never on the host name, so boot behaviour is host-name-independent.
The end state is "web-1 singleton plus web-2 keyed". It is named explicitly and is **not** claimed to be one
Terraform topology (the issue asked for one; see Alternatives, row T2). The `workspaces_luks` attachment
stays web-1-bound and outside the birth fan-out (#6964); `web-host-birth-gate.sh` refuses a birth of
`web-1` by name, which is the cheapest enforceable invariant under D1.

**D2 - Raw at birth; the live web-2 is converted by a gated rebirth.** `hcloud_volume.workspaces` drops
`format = "ext4"` and gains `lifecycle { ignore_changes = [format] }` beside `prevent_destroy`. Measured on
hcloud 1.63.0 (offline plan against a state shaped like the live volume): `format` is NOT ForceNew; dropping it
plans an in-place `ext4 -> null` update on a volume that holds user data, and `ignore_changes` turns the same plan
into "No changes", so it is what makes the merge a no-op for the live volume. New volumes are born
raw. A born-ext4 volume reaching the provisioner is FATAL (a wrong plan), never reformatted.
**Raw-at-birth is an exception to the "volume is never rebuilt" posture, not a loosening of it:** the
only volume ever created raw is one that has never held data, and the one-time conversion of the live
web-2 volume (empty, never pooled) is the single deliberate, gated exception to `prevent_destroy`.

**D3 - Code home: the baked `soleur-host-bootstrap.sh` family, not inline cloud-init.** A new baked
`workspaces-luks-provision.sh`, plus the existing `workspaces-luks-reopen.{sh,service,timer}` and
`workspaces-luks-reopen-failure.service`, baked and enabled on every fresh host. The web user_data budget
(`plugins/soleur/test/cloud-init-user-data-size.test.ts`) has about 300 bytes of headroom and the template is
shared with the populated pet, so only call sites stay inline. The provisioner is single-shot and
fail-closed with ordered arms (`config`, `device`, `discriminate`, `format`, `open`, `wire`, `escrow`,
`result`), each with a distinct exit code and a Sentry stage `workspaces_luks_provision_*`.
The discriminator accepts blkid rc 0 or 2 only; an empty `TYPE` is treated as raw only when `PTTYPE` and
`wipefs --no-act` also show nothing; `ext4` or anything else is FATAL with zero writes. `_may_format()`
(device level) and `_may_format_fs()` (mapper level) are re-run immediately before each destructive call,
and a durable intent file makes a crash between `luksFormat` and `mkfs` recoverable; a LUKS container whose
mapper has no filesystem and no intent file is FATAL ("damaged store"). The reopen unit stays luksOpen-only:
the recurring timer never contains a format arm.

**D4 - Key access: a dedicated config, `fetch --plain` only, a dedicated fresh-host token in user_data.**
A new service token (`doppler_service_token.workspaces_luks_fresh_boot`, project `soleur`, config
`prd_workspaces_luks`, read access, no `create_before_destroy`) is a `templatefile()` variable written to
`/etc/default/luks-monitor` (mode 0600, root). It is separate from the token published as
`WORKSPACES_LUKS_BOOT_TOKEN` because that one is rotated by a `create_before_destroy` procedure whose
installer reaches web-1 only; a shared token would be destroyed under web-2, whose next reboot would then
fail `luksOpen`. The fresh-host token is never co-rotated and **its rotation is a host replacement**. The
only permitted read is `doppler secrets get WORKSPACES_LUKS_KEY --plain --config prd_workspaces_luks`.
Scope, stated once and truthfully: like every `prd_*` branch-config token in this repo it resolves about
116 `prd` secrets (ADR-164 census), so "dedicated config" isolates the passphrase from the container env
file, not from a holder of this token. Containers are default-drop firewalled and no allowlist entry covers
`169.254.169.254`, so a container cannot read the metadata endpoint; a regression test over the allowlist
files pins that. Host-side non-root users in the docker group are root-equivalent and can read it (residual
R4 in the registers). The CTO preferred post-boot delivery over the bastion; this ADR deviates for first
delivery because a rebirth rotates the host SSH key and the committed pin (`web-2-ssh-host-key.pub`) is
re-captured by a follow-up PR, so a post-boot step cannot complete inside one dispatch.

**D5 - Soak marker: written by CI, never by the host.** A new web-2 leg in the daily
`workspaces-luks-verify.yml` (no SSH) reads web-2's latest probe row and its current-boot readiness row from
Better Stack. Green is decided from a positive count: both rows present, joined on `boot_id`, every required
field equal to its required value (backing `crypto_LUKS`, mapper active, `/mnt/data` source
`/dev/mapper/workspaces`, key re-test ok, `escrow=ok`, age within 26 h); an empty or unparseable body is red.
A query failure is neither: the run fails and the marker is left as it is, so a vendor blip cannot reset the
three-day soak. On a fresh green it writes `WORKSPACES_LUKS_CUTOVER_AT` only when the key is absent; on red or
stale it deletes the key so the gate fails closed. The marker lives in a dedicated Doppler config
(`prd_workspaces_luks_marker`) with a write token scoped to that one config, not in shared `prd`: a write
token on `prd` could overwrite any prd secret and this writer is an unattended daily cron. Header escrow is
a hard precondition of the marker (a header with no off-host copy never earns it) but is non-fatal at boot.
Sourcing the marker into `lb-weight-gate.sh` stays with the future flip orchestrator.

**D6 - Verification vehicle: the existing daily probe, baked.** `luks-monitor` and its emitter are baked
onto fresh hosts so web-2 emits the same host-tagged row under the existing SyslogIdentifier that web-1 emits.
The ledger row for the web-2 volume claims `live_verification: available` and `live_coverage_floor` moves
2 to 3, in the commit that adds the vehicle.

**Supersession.**

- ADR-143 R3's **DEFER is resolved** by this ADR, and its wording "AC5 reframed: LUKS-intent declared in HCL
  plus plaintext-pooling physically gated plus tracked for Phase-4" is **replaced** by "LUKS-backed at boot".
  Per the live-conversion condition above, "LUKS-backed at boot" is the architecture's target state; it is
  asserted of web-2 only after the rebirth. R3's two inherited corrections are met by D3 (blkid discriminator,
  `isLuks` forbidden by a static guard) and D1 (the topology split is decided, with T2 deferred).
- **ADR-119 section (d) is reversed.** "web-2 is out of scope", "web-2's volume is knowingly left plaintext" and
  "a fresh web host must NOT get these units" no longer hold: a fresh host MUST get the reopen unit, or it cannot
  survive a reboot. ADR-119's `workspaces_luks` singleton for web-1 and its rejection of `for_each` on that
  volume stand unchanged.
- The 2026-07-24 active-active plan's AC5 line is marked superseded by a pointer, not edited.

## Two delivery paths, one byte-parity test

web-1 keeps its Terraform SSH installer for the running pet until the web-1 de-pet; fresh hosts take the
baked path. Both take the same repo files as source, so the unit files are byte-identical by construction.
The canonical crypttab, fstab and `docker.service.d` drop-in lines written by the provisioner's `wire` arm
are pinned byte-for-byte against `local.workspaces_boot_unlock_*` by a section of
`fresh-boot-parity.test.sh`. The pair retires when the de-pet removes the SSH installer.

## Shared-passphrase residual

One `WORKSPACES_LUKS_KEY` unlocks both web-1's sole-copy volume and web-2's volume. A leak of the key or
of the fresh-host token from web-2 is therefore a leak of web-1's passphrase. This is accepted for the
duration of the standby phase and it **constrains any future `luksChangeKey` on web-1**: rotating web-1's
passphrase must also re-key or retire web-2's volume, or web-2's reboot unlock fails. True isolation between
hosts is the separate-project work (#6167). The residual is recorded in the Article 30 register and the
compliance posture, conditioned on the live conversion.

## Live conversion (single-use rebirth workflow)

The live web-2 volume is empty ext4. It is converted by a single-use, environment-gated workflow, run as an
operation after the merge and not as PR content: re-assert the emptiness evidence (attached server and labels,
trailing-7-day `/mnt/data` used-bytes under a stated ceiling from `host_metrics`, never pooled) and web-2's
identity; delete the volume through the Hetzner API first (a crash leaves dangling state that a re-run
heals, not an orphan volume whose name collides with the next create); remove the one state address; destroy
the server and attachment; run `web-host-create` for web-2 with an explicit `image_tag` whose host-script
content-hash label equals `host_scripts_content_hash` at the same commit. This follows the
`workspaces-plaintext-forget.yml` precedent, and **the workflow file is deleted after use**; this ADR is
where its existence is recorded. The expected boot row is `luks=1 luks_arm=formatted escrow=ok`, a
workflow-issued hcloud reboot must then produce `luks_arm=opened` or `noop` with a new `boot_id`, and the
host's SSH key changes, so the committed pin is re-captured in a follow-up PR (none of the SSH consumers
affected in that window is in the LUKS path). The window is web-2 only (weight 0, serving nothing, holding no
user data); web-1 is untouched.

## Consequences

- A host born from the template mounts `/mnt/data` on `/dev/mapper/workspaces` with no human step, and
  survives a reboot (the reopen unit and `RequiresMountsFor` drop-in are baked).
- web-2 becomes observable without SSH: Sentry stages `workspaces_luks_provision_*`, the readiness row
  `SOLEUR_FRESH_BOOT_READY` carrying `luks`, `luks_arm` and `escrow`, and the daily probe row.
- The user_data now carries a scoped credential (D4). It cannot be revoked after first boot because the reopen
  unit needs it on every boot; this is the price of an unattended first boot and is recorded as residual R4.
- Until the live conversion, no published or registered statement may say web-2 is encrypted. The published
  privacy and GDPR documents need no edit: their "Encrypted workspace storage" wording is scoped to the volume
  workspace git data is served from.
- The follow-through sweeper, not the PR, closes #6931 (the PR body uses `Ref`).

## Alternatives considered

| Option | Verdict | Why |
| --- | --- | --- |
| **T1 (chosen): one mechanism, two Terraform addresses** | Chosen | No `state mv` of the sole-copy volume; boot behaviour is host-name-independent. |
| **T2: one keyed raw LUKS resource now, the singleton `state mv`'d into `["web-1"]`** | Deferred (#9357) | A second state-surgery step on the sole-copy asset; `moved` is unusable on this `-target`-only root. Its gains (native `prevent_destroy`, dissolving #6964) are bought more cheaply by D1's refusal. Revisit when the web-1 de-pet rebuild exists. |
| **Reformat the existing web-2 volume in place when it reads ext4 and empty** | Rejected | "Empty" is unprovable on the failure path, and the arm would also fire on a mis-resolved device. A born-ext4 volume is FATAL. |
| **Post-boot token delivery over the bastion** | Rejected for first delivery | A rebirth changes the host SSH key and the pin is a committed file, so the dispatch cannot complete unattended. Revisit if user_data exposure is judged unacceptable. |
| **A token shared with web-1's rotation procedure** | Rejected | web-1's `create_before_destroy` rotation reaches web-1 only and would strand web-2 on its next reboot. |
| **Inline cloud-init LUKS block (the registry shape)** | Rejected | About 300 bytes of user_data headroom; the template is shared with the populated pet. |
| **`cryptsetup isLuks` as the discriminator** | Rejected | The documented data-destroyer on a populated device; forbidden by ADR-143 R3 and by a static guard. |
| **Drop `prevent_destroy` on the web-2 volume to allow `-replace`** | Rejected | Weakens the guard on the sole-copy class permanently for a one-time need. |
| **Marker in shared Doppler `prd`** | Rejected | A `prd` write token can overwrite any prd secret; this writer is an unattended cron. |

## Relationship to other ADRs

- **ADR-143 R3**: DEFER resolved and "AC5 reframed" replaced by this ADR. ADR-143 carries a one-line pointer.
- **ADR-119**: section (d) reversed. ADR-119 carries a one-line pointer. The 2026-09-28 addendum's measurement
  that `moved` fails every `-target` plan is the reason T2 is deferred.
- **ADR-068 section (c)** and **ADR-143 D3**: the anti-pooling gate remains the fence until the marker is
  consumed by the flip orchestrator (#9358).
- **ADR-148**: the replace gate is untouched; its unblock list (key-conditional gate arms, a rehearsal, #6964)
  is separate from this ADR's conversion.
- **ADR-140 / ADR-141**: the encryption-posture ledger row for web-2's volume moves from `plaintext-exception`
  to `luks` only with the live conversion.
- **ADR-164**: source of the about-116-secrets token census.

## Diagram

No new element or relationship. `knowledge-base/engineering/architecture/diagrams/model.c4` is corrected in
three places: the `workspacesVolume` and `hetzner` descriptions no longer say the fresh-host LUKS path is
deferred, and the `doppler -> hetzner` edge gains the fresh-host scoped token delivered in user_data. Every
sentence about web-2 being LUKS-backed is conditioned on the live conversion.
