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
(**#9372**, described under "Live conversion") has run and the first on-host probe has read `crypto_LUKS`
and a mapper-backed `/mnt/data`. Until then web-2 keeps its Hetzner-pre-formatted plaintext volume, which
holds no user data and is kept that way by `lb-weight-gate.sh`.

The status flips to `accepted` when `scripts/followthroughs/web2-luks-live-6931.sh` exits 0: the newest
web-2 readiness row is green and at least three days old, probe rows report `crypto_LUKS` on
`/dev/mapper/workspaces` in three distinct 24-hour buckets since, no non-green row follows it, and the newest
probe row is green and fresh. It grades from the Better Stack rows alone and holds no Doppler credential
(its directive declares `secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD`).
A non-green row after the readiness row, or a window that closes unmet at `earliest` plus four days, FAILs
the follow-through rather than leaving it at "not yet" forever. It is enrolled as a follow-through on #6931
by #9372, because its `earliest` date is the rebirth plus three days; the workflow-issued reboot proof under
"Live conversion" is part of #9372's acceptance.

> **Superseded 2026-10-08 (#9372), in part:** the reboot-proof requirement stated above (including `w2l_reboot_seen` and `reboot_not_seen`) no longer holds; see the addendum "evidence rule: immutability, not reboot" at the end of this ADR.

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
fail-closed with ordered arms, each with a distinct exit code and a Sentry stage
`workspaces_luks_provision_<arm>`: `config` 10, `device` 11, `discriminate` 12, `key` 13, `format` 14,
`open` 15, `wire` 16, `mount` 17, the non-fatal `escrow`, and a closing `result` row; exit 78 is the
refusal to run under xtrace. A Doppler key-fetch failure is arm `key`, not `format` or `open`.
The discriminator accepts blkid rc 0 or 2 only; an empty `TYPE` is treated as raw only when `PTTYPE`,
`wipefs --no-act` and a zero-content probe of the raw device also show nothing (the first 16 MiB, the last
16 MiB and a 1 MiB window at 128 MiB, where ext4's first backup superblock sits); `ext4` or anything else is
FATAL with zero writes. `_may_format()` (device level) and `_may_format_fs()` (mapper level) are re-run
immediately before each destructive call.

*Interrupted-format recovery.* Two markers precede the format's effect. The first is a LUKS2 label on the
container, `soleur-formatting`, set by `luksFormat` itself and replaced by `soleur-workspaces` only after
`mkfs` succeeds (a failed relabel is fatal `format`); it rides the volume, so a replacement host recognises an
interrupted format. The second is a host-local intent file, bound to the volume by the `luksUUID` that
`luksFormat` is told to assign: a stale or foreign file authorises nothing. A LUKS container whose mapper has
no filesystem and neither marker is FATAL ("damaged store"). Nothing re-runs the provisioner after cloud-init
(`runcmd` is once per instance), so recovery of an interrupted format is by host replace, not by a retry on
the same host; the local file would not survive the replace, which is why the label is the load-bearing marker.
The `wire` arm is fatal if the reopen service and timer cannot be enabled (nothing would reopen the mapper at
the first reboot).

*Escrow.* Header escrow is attempted once, at birth, by the idempotent provisioner, and counts as `ok` only
when the object read back from the bucket matches the header in size and in md5 (the ETag of a single-part
upload): a stale copy under the same UUID after a re-key is re-uploaded, not certified. `escrow=missing`
persists for the host's life and withholds the soak marker. The reopen unit stays luksOpen-only: the
recurring timer never contains a format arm.

> **Superseded 2026-10-03 (#9377):** `escrow=missing` still persists for the host's life and still withholds the
> soak marker, but it is no longer quiet. From the merge of PR #9448 and once `apply-sentry-infra.yml` has applied the
> alert-rule edit, the stage `workspaces_luks_provision_escrow` raises a Sentry alert emailed to issue owners (D8 in
> the 2026-10-03 addendum). This is best-effort, not a guaranteed page: the emit is `|| true`, delivery is an email,
> and the rule's 35-minute action-frequency window is a per-rule, per-shared-issue-group throttle (see D8 item 3). The boot still continues and the Sentry level is still
> `warning`; the alert is routed by stage name.

**D4 - Key access: a dedicated config, `fetch --plain` only, a dedicated fresh-host token in user_data.**
A new service token (`doppler_service_token.workspaces_luks_fresh_boot`, project `soleur`, config
`prd_workspaces_luks`, read access, no `create_before_destroy`) is a `templatefile()` variable written to
`/etc/default/luks-monitor` (mode 0600, root). It is separate from the token published as
`WORKSPACES_LUKS_BOOT_TOKEN` because that one is rotated by a `create_before_destroy` procedure whose
installer reaches web-1 only; a shared token would be destroyed under web-2, whose next reboot would then
fail `luksOpen`. The fresh-host token is never co-rotated and **its rotation is a host replacement**. The
only permitted read is `doppler secrets get WORKSPACES_LUKS_KEY --plain --config prd_workspaces_luks` (superseded for web-class hosts born after #9377: `prd_workspaces_luks_web`, see the 2026-10-02 addendum D7).
Scope, stated once and truthfully: like every `prd_*` branch-config token in this repo it resolves about
116 `prd` secrets (ADR-164 census), so "dedicated config" isolates the passphrase from the container env
file, not from a holder of this token. The metadata-endpoint exposure to containers is bounded by two
things and no more: the cron-egress nftables script installs a default-drop on `docker0` only, and it fails
open on bootstrap (it installs the drop only once allowlist resolution succeeds, and pages otherwise); and a
data test over the allowlist files (`cron-egress-metadata-endpoint.test.sh`) pins that no entry covers
`169.254.169.254`. That test reads the allowlist files, not the installed ruleset. Host-side non-root users
in the docker group are root-equivalent and can read it (residual R4 in the registers). The CTO preferred post-boot delivery over the bastion; this ADR deviates for first
delivery because a rebirth rotates the host SSH key and the committed pin (`web-2-ssh-host-key.pub`) is
re-captured by a follow-up PR, so a post-boot step cannot complete inside one dispatch.

**D5 - Soak marker: written by CI, never by the host.** A new web-2 leg in the daily
`workspaces-luks-verify.yml` (no SSH) reads web-2's latest probe row and its readiness row from Better
Stack. The two rows have different cadences, and the join respects that: the readiness row is emitted once
per **instance** (a cloud-init `runcmd` item) and carries `luks_arm` and `escrow` from the birth boot; the
probe row is daily and per boot. The join is therefore instance-level: a probe row certifies the instance
only when it is not older than the green readiness row. **Earning** the marker needs both rows; **keeping** it
needs only the newest probe row (the readiness lookback expires on a host that never reboots), unless a
readiness row newer than that probe row shows a rebirth, which is red. In both cases the reason is
`probe_predates_ready`. `boot_id` stays in both rows as a diagnostic and no judge requires equality;
`luks_arm` exists only in the first-boot readiness row (its tmpfs source is wiped at reboot). Green is
decided from a positive count: both rows present, every required field equal to its required value (backing
`crypto_LUKS`, mapper active, `/mnt/data` source `/dev/mapper/workspaces`, key re-test ok, `escrow=ok`, age
within 26 h); an empty or unparseable body is red. A query failure is neither: the run fails and the marker
is left as it is, so a vendor blip cannot reset the three-day soak; so is a fault of the judge itself (jq missing or
crashing), which is not evidence about web-2. On a fresh green it writes
`WORKSPACES_LUKS_CUTOVER_AT` only when the key is absent; a present marker is kept while the verdict is
GREEN and removed on a non-GREEN run, so the gate fails closed. The marker lives in a dedicated Doppler
config (`prd_workspaces_luks_marker`) with a write token scoped to that one config, not in shared `prd`: a
write token on `prd` could overwrite any prd secret and this writer is an unattended daily cron. The write
token is a repo-level Actions secret, so its custody is this repository's workflows, not the one job. Header escrow is a hard
precondition of the marker (a header with no off-host copy never earns it) but is non-fatal at boot. The
marker **value is advisory and shape-only**: `lb-weight-gate.sh` validates its shape, not its provenance,
and the verify leg does not re-validate a present value (a value planted in `prd` shows through the branch
config). Sourcing the marker into the gate, and validating it there, stay with the future flip orchestrator
(#9358). The job runs on the default branch alone (a `schedule` event, or a dispatch from `main`), so a branch copy of
the workflow or its helper never holds the write token. A RED or unjudgeable scheduled run files a `[ci/luks-verify-web2]`
GitHub issue (distinct titles for RED and for "could not judge", deduped by title), and the job's last step posts a Sentry
Crons check-in to `workspaces-luks-verify-web2` (schedule events only, so a dispatch cannot forge liveness). That
monitor is declared unrouted (`cron_monitor_alert_unrouted`) until its first measured check-in (#9372): the GitHub
issue is the primary channel, Sentry the backstop for silence. The reason-to-action table is in the
[web-host-replace runbook](../../operations/runbooks/web-host-replace.md).

**D6 - Verification vehicle: the existing daily probe, baked.** `luks-monitor` and its emitter are baked
onto fresh hosts so web-2 emits the same host-tagged row under the existing SyslogIdentifier that web-1 emits.
In this change the ledger row for the web-2 volume stays `plaintext-exception` and only its evidence string
changes; the row flips to `luks` with `live_verification: available`, and `live_coverage_floor` moves 2 to
3, in the live-conversion follow-up (#9372), because no live row exists before it.

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

> **Superseded 2026-10-03 (#9377):** the first paragraph above describes the state before the passphrase split. Once PR
> #9448 merges and the push-apply creates the web-class key (nothing has been applied), every NEW web-class birth will
> hold a passphrase independent of web-1's, and "a leak of the fresh-host token from web-2 is a leak of web-1's
> passphrase" and "rotating web-1's passphrase must also re-key or retire web-2's volume" will no longer hold for them. They remain true of the pre-split fresh-boot token until it is retired. See "Shared-passphrase
> residual, rewritten" in the 2026-10-03 addendum. The second paragraph (the escrow credential pair) was already
> narrowed by D7 of 2026-10-02 and is unchanged here.

> **Superseded 2026-10-05 (#9377, counsel-review C4), in part:** the condition in the callout above ("once ... the push-apply creates the web-class key (nothing has been applied)") is met (by a dispatched apply, not by a push-triggered one); see "Addendum — 2026-10-05" for the measured state. The callout is kept as the dated record.

The same token also reads the R2 header-escrow credential pair in `prd_workspaces_luks`. A compromised web-2
(or a leak of the user_data token) can therefore overwrite or delete web-1's LUKS header backup, which is the
recovery path for web-1's sole-copy volume: an integrity and availability exposure, not only a confidentiality
one. The escrow bucket has no object lock or versioning today. Hardening (splitting the web-host escrow credential
from web-1's backup-bucket access, a per-host scoped credential, bucket versioning or object lock) is tracked by
#9377. (The provisioner's idempotency check no longer compares size alone: it also compares the object's md5, so a
stale copy is re-uploaded.)

## Live conversion (single-use rebirth workflow, #9372)

The live web-2 volume is empty ext4. **Until #9372 runs, a plain `web-host-replace` of web-2 re-attaches that
ext4 volume, the new host takes the `discriminate` FATAL and powers itself off: by design, fail-closed, at
weight 0 with no user impact.** Replacing a host cannot clear it, because the volume is never in the destroy
set; only the volume rebirth can. It is converted by a single-use, environment-gated workflow, run as an
operation after the merge and not as PR content (#9372): re-assert the emptiness evidence (attached server and labels,
trailing-7-day `/mnt/data` used-bytes under a stated ceiling from `host_metrics`, never pooled) and web-2's
identity; delete the volume through the Hetzner API first (a crash leaves dangling state that a re-run
heals, not an orphan volume whose name collides with the next create); remove the one state address; destroy
the server and attachment; run `web-host-create` for web-2 with an explicit `image_tag` whose host-script
content-hash label equals `host_scripts_content_hash` at the same commit. This follows the
`workspaces-plaintext-forget.yml` precedent, and **the workflow file is deleted after use**; this ADR is
where its existence is recorded. The expected readiness row is `luks=1 luks_arm=formatted escrow=ok`. The
reboot proof is on the probe row, not the readiness row (which is emitted once per instance): after a
workflow-issued hcloud reboot, the next daily probe row must carry a **new** `boot_id`, `device_type=crypto_LUKS`
and `mount_source=/dev/mapper/workspaces` (the new `boot_id` is evidence that a reboot happened; since the #9372 workflow change the soak-marker judge and the follow-through both require it, see the 2026-10-05 addendum). The host's SSH key changes, so the committed pin is re-captured
(`scripts/capture-web-2-host-key.sh`, plus the admin-ip step its runbook names) as part of #9372; none of the SSH
consumers affected in that window is in the LUKS path, but `apply-deploy-pipeline-fix` fails closed until the
pin is re-captured. The window is web-2 only (weight 0, serving nothing, holding no user data); web-1 is
untouched. #9372 also owns the ledger flip (D6), the follow-through enrollment's `earliest` date and the
escalation if web-2 never produces rows.

> **Superseded 2026-10-08 (#9372), in part:** the reboot-proof requirement stated above (including `w2l_reboot_seen` and `reboot_not_seen`) no longer holds; see the addendum "evidence rule: immutability, not reboot" at the end of this ADR.

## Consequences

- A host born from the template mounts `/mnt/data` on `/dev/mapper/workspaces` with no human step, and
  survives a reboot (the reopen unit and `RequiresMountsFor` drop-in are baked).
- web-2 becomes observable without SSH, and the alert routes are implemented (`apps/web-platform/infra/sentry/issue-alerts.tf`,
  pinned by `sentry-fresh-boot-luks-alert-op-contract.test.ts`). `web-host-luks-boot-fatal` pages on 13 stages: the
  eight provisioner arms (`workspaces_luks_provision_{config,device,discriminate,key,format,open,wire,mount}`),
  `workspaces_luks_not_mounted` and the four readiness reasons `fresh_boot_not_ready_{token,vector,volume,luks}`.
  `web-host-luks-boot-warning` (NoOne, so it lands in the issue stream to be read) covers four: `workspaces_luks_provision_escrow`,
  `workspaces_luks_provision_wire_warn` (the daily probe timer did not arm), `workspaces_luks_provision_result` (the arm
  file was unwritable) and `fresh_boot_ready_bs_egress` (the readiness POST was skipped or failed). Severity is
  separated by stage name, not Sentry level. The readiness row `SOLEUR_FRESH_BOOT_READY` carries `luks`, `luks_arm` and
  `escrow` once per instance, and the daily probe row evidences later boots. The provisioner's own rows ride the
  journald tag `workspaces-luks-reopen`, which Vector already allowlists and ships once it is up; Vector is installed
  after the provisioner, so for a boot that powers off on a fatal the Sentry stage is the record.

  > **Superseded 2026-10-03 (#9377):** from the merge of PR #9448 (and once `apply-sentry-infra.yml` applies it),
  > `web-host-luks-boot-fatal` alerts on **14** stages (the 13 above plus `workspaces_luks_provision_escrow`), and
  > `web-host-luks-boot-warning` (NoOne) covers **three**: `workspaces_luks_provision_wire_warn`,
  > `workspaces_luks_provision_result` and `fresh_boot_ready_bs_egress`. The escrow stage is still emitted at level
  > `warning` and the boot continues; it alerts by stage name. "Alerts" means a Sentry email to issue owners, best-effort:
  > the emit is non-fatal (`|| true`) and the rule's 35-minute action-frequency window is a throttle shared by all of its
  > stages and hosts (D8 item 3).
  > `resolve_link_local` (cron-egress resolver) is additionally routed on `cron-egress-blocked`.
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
- **ADR-148**: the replace gate's refusal is untouched (key-conditional arms were added behind a separate constant on 2026-10-02, see the addendum); its unblock list (key-conditional gate arms, a rehearsal, #6964)
  is separate from this ADR's conversion.
- **ADR-140 / ADR-141**: the encryption-posture ledger row for web-2's volume moves from `plaintext-exception`
  to `luks` only with the live conversion (#9372).
- **PR #9348**: it narrows web-1's keyed `hcloud_volume.workspaces` address and rewrites the same ledger row.
  Whichever of the two lands second reconciles the comments that cite web-1's superseded keyed volume, the
  replace-gate text and the ledger row once, keeping this ADR's raw-at-birth `hcloud_volume.workspaces` block.
- **ADR-164**: source of the about-116-secrets token census.

## Diagram

No new element. `knowledge-base/engineering/architecture/diagrams/model.c4` is corrected in three places: the
`workspacesVolume` and `hetzner` descriptions no longer say the fresh-host LUKS path is deferred, and the
`doppler -> hetzner` edge gains the fresh-host scoped token delivered in user_data. Two relationships are
added because they are trust edges this decision creates: `github -> doppler` for the write token scoped to
`prd_workspaces_luks_marker`, and the `github -> betterstack` edge now names the web-2 verify leg as a reader.
Every sentence about web-2 being LUKS-backed is conditioned on the live conversion.

## Addendum — 2026-10-02 (#9377, #9358, #9356, #9357, #9378)

**D7 — web-host escrow credential and config split (#9377).** The web-host class reads its own Doppler branch config
`prd_workspaces_luks_web` through a NEW read token (`doppler_service_token.workspaces_luks_fresh_boot_web`), and its
header backups go to a NEW bucket (`soleur-workspaces-luks-header-web`). The config holds copies of `WORKSPACES_LUKS_KEY`
(in-graph from `random_password.workspaces_luks`, so rotation cannot drift), the bucket name, the endpoint, and a
bucket-scoped R2 pair that is minted live (a deferred, gated step on #9377; until it exists the provisioner records
`escrow=missing`, which withholds the soak marker). web-1 keeps `prd_workspaces_luks` and its own bucket. The provisioner
accepts the closed set {`prd_workspaces_luks`, `prd_workspaces_luks_web`}; `luks-monitor.sh` reads its key config from
`/etc/default/workspaces-luks-boot` with a web-1 fallback. The old token resource is left in place: re-pointing it is
ForceNew, which the push-apply destroy guard halts, and retiring it is a later acknowledged destroy.

> **Superseded 2026-10-05 (#9377, counsel-review C9), in part:** "a deferred, gated step" and "a deferred mint" describe the state before 2026-10-05: the two R2 credential names existed in `prd_workspaces_luks_web` at the names-only check (run 37279392332, 07:44Z) and the mint is the operator's report on #9377. The pair's scope is still unverified here (C1).

> **Superseded 2026-10-03 (#9377):** (1) "in-graph from `random_password.workspaces_luks`, so rotation cannot drift" is
> not true of PR #9448: the web-class copy is in-graph from its own `random_password.workspaces_luks_web` (and this
> D7 text was first written by #9397, merged 2026-10-03, not by #9352). (2) "a bucket-scoped R2 pair" states an
> intent: the pair is a deferred mint, no gate verifies its scope, and the signed `HEAD` isolation proof is a later,
> live-only step. (3) "until it exists the provisioner records `escrow=missing`" will, from the merge of PR #9448,
> raise a best-effort Sentry alert on a web-class birth, and a birth route will refuse to start without the R2 pair
> names (D8), which are names, not values.

**R4 is narrowed, not closed.** Narrowed on merge for every NEW birth (inferred, not read from a host: `hcloud_server.web` ignores `user_data` and
the token postdates both live hosts; the retirement step must confirm it is destroyed); closed when the old token is retired. The shared passphrase residual
above stands unchanged: a compromised web-2 still reads web-1's passphrase.

> **Superseded 2026-10-03 (#9377):** "stands unchanged: a compromised web-2 still reads web-1's passphrase" holds only
> for a host that received the pre-split token. For a NEW birth it will be narrowed once PR #9448 merges and the key
> is created (see the addendum below).

**Option (b), an R2 bucket lock, is rejected.** R2 has no object versioning, an age-based lock leaves a window after
retention expires, and an indefinite lock would break web-1's cutover flow, which rewrites the header object.

**`doppler-config-inventory.txt` is deliberately not edited**, for the same reason the marker config is absent from it:
adding a name mints a drift-read token and forces floor edits.

**Precondition for the live conversion (#9372).** `scripts/check-web-host-escrow-config.sh` in live mode must pass
before the workflow runs: the provisioner formats even when escrow is missing, by design. It is not run by the PR that
introduced it.

> **Superseded 2026-10-03 (#9377):** the live check is now run by the workflow itself on every birth route (D8), not by
> a person-run runbook step.

**#9358.** `lb-weight-gate.sh` stays pure and env-only; `lb-weight-gate-with-marker.sh` is the one seam through which the
workspaces cutover marker reaches it (a names-list membership test, then a single-secret get). The flip orchestrator
that will call it does not exist yet; a census pins that nothing else feeds the gate. The marker stays advisory and
shape-only here: provenance is not validated.

**#9356.** The replace gate gains key-conditional arms for `web-1` behind a SEPARATE constant; the by-name refusal
stays first and intact, so a complete web-1 plan still aborts. The arms do not prove web-1 safe: the by-id mount pin to
the superseded plaintext volume, the web-1-pinned SSH provisioners and upstream-only `-target` are blockers no plan can
show. A header-restore drill joins the real-cryptsetup loopback suite. Whether a non-bypassable HALT on rotating
`random_password.workspaces_luks` is needed (a `[ack-destroy]` can wave one through today) is left open; it is listed in the #9377 follow-up comment as a go/no-go before #9372 dispatches.

> **Superseded 2026-10-03 (#9377):** decided: yes, a non-ackable HALT is needed (D8), implemented in PR #9448 and
> effective on its merge.

**#9378.** The provisioner is hardened in place: `flock` on fd 9 (600 s), a pinned `PATH`, the test seam refused as root on a cloud-init host, and every write to fstab, crypttab, the docker drop-in and the format intent file through one atomic, fsynced `_install_file` that refuses symlinks. The container egress ruleset refuses any CIDR overlapping `169.254.0.0/16`, starts with a rate-limited log rule and an unconditional drop for that range, and the resolver strips link-local answers from every feeder. `case_raw_formats_once` is split into four cases.

**#9357.** Only the offline state-move rehearsal, the runbook and the blocked-by edges (#9421 de-pet rebuild; the held draft PR #9348 cannot be a GitHub dependency) ship. The HCL collapse and the
single-use state-move workflow wait for the held PR B (#9348) and a web-1 de-pet rebuild.

## Addendum — 2026-10-03 (#9377)

Offline only. This addendum records decisions taken by the issue owner on #9377 and implemented in PR #9448, the PR that
carries it (`Ref #9377`, never `Closes`); #9377 here means the issue, and the earlier credential-split change is #9397
(merged 2026-10-03). Nothing here was applied: no apply, no workflow dispatch, no Doppler or Cloudflare write. Every
"now" below means "on the merge of PR #9448", and every statement about what a host reads is conditional on the push-apply
having created the web-class key, which has not happened. The superseded sentences above are marked in place; their text is kept as the dated record. The
status stays `adopting`, and every statement that web-2 is LUKS-backed stays conditioned on the live conversion
(#9372). Nothing below says web-2 is encrypted.

> **Superseded 2026-10-05 (#9377, counsel-review C4), in part:** "which has not happened" no longer holds: the key was created on 2026-10-04 (run 37209725107). The status stays `adopting` and nothing here says web-2 is LUKS-backed.

**D7, rewritten (passphrase sentence).** The web-class config `prd_workspaces_luks_web` carries its OWN
`WORKSPACES_LUKS_KEY`, generated by a new `random_password.workspaces_luks_web` (40 characters, no special
characters, `lifecycle { prevent_destroy = true }`, no `ignore_changes`, no `keepers`) and copied in-graph into
`doppler_secret.workspaces_luks_web_key`. web-1 keeps `random_password.workspaces_luks`; the web-class file never
names web-1's password, which the checker's `--static` census (the word-bounded address may appear in code only in
`workspaces-luks.tf`) and the file-scoped suite `workspaces-luks-header-web.test.sh` both pin. The bucket name,
endpoint and the live-minted R2 pair are unchanged from 2026-10-02. As measured on 2026-10-03, nothing from the
earlier credential-split merge (#9397) had been applied (`apply-web-platform-infra.yml` was `disabled_manually` since
2026-10-01), so the swap is a first create in Terraform, not a rotation, and no volume was ever keyed by the earlier
shared value.

> **Superseded 2026-10-04 (#9481), in part:** "nothing had been applied" no longer holds for two of the objects. Measured
> on 2026-10-04: `doppler_config.workspaces_luks_web` and `doppler_service_token.workspaces_luks_fresh_boot_web` were
> created at 07:27 UTC by an `apply-deploy-pipeline-fix` run (`-target` transitive dependencies of the web-host
> user_data), and `apply-web-platform-infra.yml` was re-enabled for individual dispatches that day (08:00 to 12:06 UTC)
> and is `disabled_manually` again. The bucket, `random_password.workspaces_luks_web` and the three `doppler_secret`
> copies were still absent in the live names read of 2026-10-04. The sentence above is kept as the dated record.

**D-A1 — a distinct passphrase per host class.** Rationale: a shared value made a web-2 leak a web-1 leak and made a
future web-1 `luksChangeKey` a two-host re-key. The split is cheapest now: no web-class volume is LUKS-formatted yet
(the live web-2 volume is plaintext and empty), so there is no data keyed by the old value. It becomes a data-bearing
rotation after #9372.

**D8 — three controls (decisions A2, B1, B2).**

1. *Non-ackable rotation HALT (A2).* The push-apply's `luks_passphrase_rotations` counter now covers six addresses:
   `random_password.inngest_redis_luks`, `doppler_secret.inngest_redis_luks_key`, `random_password.workspaces_luks`,
   `doppler_secret.workspaces_luks_key`, `random_password.workspaces_luks_web` and `doppler_secret.workspaces_luks_web_key`.
   An `update`, `delete` or `forget` there, or a change whose verb list cannot be read, stops the `apply` job before the
   `destroy_count` sum and outside it, so `[ack-destroy]` cannot wave it through (a replace also trips `resource_deletes`,
   which is why an ack aimed at an unrelated delete would otherwise have acked the rotation). A first `create` and a
   `no-op` stay legal. The only bypass is `[skip-web-platform-apply]`, which skips the apply and performs nothing. The
   cutover, recut and replace dispatch gates name the web-class pair in their `luks_passphrase_touched` clause, each
   with a removal row in its suite; the by-name web-1 refusal in the replace gate is untouched. A table row in
   `terraform-target-parity.test.ts` confines the web-class key copy and the new password to the `apply` job's
   `-target` list and requires the HALT block there; the same suite checks the apply step from its `run:` header through the
   luks HALT's closing `fi` as a CLOSED SEQUENCE: every line is consumed by exactly one expected step (each required
   statement once and in order, if/fi balanced, `echo` and `grep` bodies restricted to ones that cannot run code, the numeric
   validation naming every counter), so a rewrite of the counter, an echo-prefixed short-circuit, an ack-keyed reset, an
   inserted `exit $rc` or a second `if` with an extra `fi` before the HALT has no slot and fails it. Why a HALT: a rotated Terraform value leaves the LUKS header cut from
   the old one with no surviving copy of the old one, so the volume is unopenable at the next boot of a host with no
   console. The supported rotation of a populated volume is a header re-key (`cryptsetup luksChangeKey`) followed by an
   intentional state change under review, never a Terraform replace; the HALT's remediation text says so. The counter
   compares a base address (module prefix and trailing instance index stripped, `luks_passphrase_base`, which also accepts
   a quoted key holding escaped characters), so `random_password.workspaces_luks_web["web-2"]` is the same secret to it; the three dispatch gates keep exact-address
   matching and abort an indexed or module-prefixed address as out of scope; the replace gate also aborts a plan entry
   with an empty `actions` array (it was classified as no change before). The recut gate's ABORT message in the workflow names all four counted
   passphrase addresses (pinned from the recut suite). The HALT is pinned structurally in the parity suite, executed against
   fixture plans in the destroy-guard suite, and executed as the real step text from its start (with `doppler` and `terraform`
   stubbed and the real acknowledgement environment) against ten skip or neuter mutations, each of which the structural
   check refuses and each of which is shown to defeat the HALT when run unchecked. What this proves is that the step text in
   the repository has that shape and that those ten mutants are caught; it does not prove the HALT against every possible
   shell construct, and it says nothing about a workflow other than `apply`.
2. *Escrow readiness as a workflow gate (B1).* New `scripts/web-host-escrow-preflight.sh` runs
   `check-web-host-escrow-config.sh --live` fail-closed in `web_host_create` and `web_host_replace`, before the first
   Terraform command (it follows the ADR-128 R1 backend-credentials step, which is deliberately the first Doppler reader).
   It takes the workplace-scope provider token from `TF_VAR_doppler_token_tf`, or reads exactly one secret
   (`DOPPLER_TOKEN_TF` in `prd_terraform`) with the step's own token, shape-checks it before masking it, refuses xtrace
   first, and keeps the value out of argv, files, `GITHUB_ENV` and stdout. A third, non-creating consumer runs the same script from the dispatch-only diagnostic `web-host-escrow-diagnose.yml` (ADR-241 D2 note, 2026-10-04). In CI the checker runs in a count mode for the
   `prd`-root advisory (the repo is public and the step runs on every birth, so names are withheld; a local `--live` run
   lists them), a red run re-emits the checker's CAUSE, NOTE and unreadable lines and then its FAIL lines as annotations (nine at
   most, causes first, each cut at 600 characters and flattened to printable ASCII), and the stderr of the fallback token read is scrubbed (token shapes and the literal value redacted,
   non-printable bytes flattened, the first 300 bytes kept). A census test
   (`web-host-escrow-preflight-census.test.ts`) makes any workflow job whose text has a `terraform` or `tofu` apply (bare or
   path-qualified, any global-option form including `-chdir`, continuation lines joined) and a `-target`/`-replace` of an
   indexed or module-qualified `hcloud_server.web[...]`, of the bare map outside quoted prose (a quoted string whose first
   word is the binary, as in `bash -c "terraform apply ..."`, `eval`, `ssh h "..."` or an echo `$(...)`, is read as code), or
   of a non-literal value (over-flagging on purpose) carry the step, so the single-use web-2 rebirth workflow (#9372) cannot
   be written without it by those spellings, and pins the two `host_creates` refusals by name. The runbooks' "step 0" is now a diagnostic,
   not the control.
3. *`escrow=missing` alerts (B2).* The stage `workspaces_luks_provision_escrow` moved from the NoOne rule
   `web-host-luks-boot-warning` to `web-host-luks-boot-fatal`: 14 alerting stages, 3 quiet ones. The provisioner still
   continues after a failed escrow and still emits it at level `warning`; severity is by stage name, and the op-contract
   suite carries an explicit carve-out for this one stage. "Pages" is best-effort and conditional: the emit
   (`soleur-boot-emit ... || true`) is non-fatal, so a failed emit raises nothing; delivery is a Sentry email to issue
   owners, not a push notification; and the rule edit takes effect only after `apply-sentry-infra.yml` applies it. The
   35-minute `frequency_minutes` is a per-rule, per-issue-group throttle, and every boot event shares one perpetually-active
   issue group (read from the rule's own group comments, not measured against live Sentry), so the window is fleet-wide and
   spans boots: another page of the same rule within 35 minutes, from any of the 14 stages or any host, can fold an escrow
   alert into silence, and an escrow alert can equally fold a fatal stage that follows it. The reads that do not depend on
   the throttle are the readiness row's `escrow=ok` and `scripts/sentry-issue.sh --host-events <host> --stage
   workspaces_luks_provision_escrow`, both in the runbooks. The cron-egress resolver's `resolve_link_local` op is routed on
   `cron-egress-blocked`, and its once-per-source marker is written only after a POST curl reported as sent (delivery is
   still best-effort: curl rc 0 is not an HTTP 2xx). The R2 key id and secret are shape-checked (`LC_ALL=C`, closed
   charsets) before the curl config stream, so a quote, backslash, whitespace or control byte cannot add a directive; a
   refusal records `escrow=missing` and no curl call, with reason `creds_shape` for the key id or secret and `shape` for the
   bucket or endpoint (the runbooks carry the reason decode table).

**Shared-passphrase residual, rewritten.** Once PR #9448 merges and the push-apply creates the web-class key, for every
NEW web-class birth a leak of the web-class token or passphrase will no longer yield web-1's passphrase. This is **narrowed, not eliminated**, and not proven by a value comparison: both configs
sit in one Doppler project, both passphrases live in one Terraform state, one provider token writes both, and the
distinctness is structural (two independent `random_password` resources), not read from a host. Not closed while the
pre-split fresh-boot token exists: it still resolves web-1's config (and its passphrase and escrow pair) until a later
acknowledged destroy retires it, and it was never delivered to a host born after the split (inferred, not read from a
host). R4 (a user_data credential that cannot be revoked after first boot) is narrowed by the same inference. The
`luksChangeKey` constraint on web-1 is lifted for web-class hosts from that point. The residual is recorded in the Article 30 register and
the compliance posture, scoped to NEW births, with the web-2 statements still conditioned on #9372. True isolation between
hosts remains the separate-project work (#6167).

> **Superseded 2026-10-05 (#9377, counsel-review C4), in part:** the creation condition ("Once PR #9448 merges and the push-apply creates the web-class key") is met: PR #9448 merged 2026-10-04 and a dispatched apply (run 37209725107, not a push-triggered run) created the key. The residual stays **narrowed, not eliminated**: the pre-split token is not retired (C2) and the distinctness is still structural, not read from a host. See "Addendum — 2026-10-05".

**Loss recovery.** Once the push-apply creates it (it has not), the web-class passphrase will have as durable copies the Doppler secret,
Terraform state and Doppler's secret history (plus the runner-local copy of the state described under Known limits); web-1's passphrase will no longer back it up, and the escrowed
header cannot open a volume alone. While no web-class volume holds data a loss costs a rebuild of an empty standby. A
recovery path for the data-bearing period is owned by #9372 (acceptance criterion 2 in the issue comment of 2026-10-03,
<https://github.com/jikig-ai/soleur/issues/9372#issuecomment-5973898251>) and is to be recorded and tested before data
lands (GDPR Art. 32(1)(c)). One of the two copies has no restore substrate today: the Terraform state bucket has no
object versioning (#7992).

> **Superseded 2026-10-05 (#9377, counsel-review C4), in part:** "(it has not)" no longer holds. The key and its Doppler secret were created by run 37209725107 on 2026-10-04, so the Doppler secret and Terraform state existed from that apply and were read back at 2026-10-04 17:57Z (plan-only run 37222472359) and 2026-10-05 12:32Z (dispatch run 37310111213), each an allow-list or plan-only plan reporting no changes. That Doppler's secret history holds the value is Doppler's design and was not measured. The recovery path for the data-bearing period is unchanged and still owned by #9372; no web-class volume holds data.

**Known limits, recorded not hidden.**

- A first create cannot be told from a state loss: if state were lost or rewound after a web-class volume was formatted,
  both web resources would plan as `create`, which the HALT permits, and the provider would overwrite the live secret. The
  state bucket's own protections are the control.
  > **Superseded 2026-10-06 (#9372), in part:** "which the HALT permits" no longer holds for the web-class passphrase: from the
  > merge of the retirement change (#9569) the HALT counts a `create` of the web-class passphrase (see the dated marker under
  > the D9 gate-shape item). The state bucket's protections remain the control for the other five addresses.
- A tainted first create of the generator is blocked by `prevent_destroy` on the next plan; recover with `terraform untaint`
  or by removing the tainted state entry under review. `doppler_secret.workspaces_luks_web_key` has no lifecycle block, so
  a tainted or edited key copy is stopped by the HALT (an `update`, `delete` or `forget`), not by `prevent_destroy`.
  Retiring the web-class config needs a dedicated operator-run state change reviewed on its own (owner: #9372), not the
  push-apply: removing either resource plans a delete or forget that the non-ackable HALT counts, so every push-apply would
  stop until `[skip-web-platform-apply]` (see the header comment of `workspaces-luks-header-web.tf`).
- Any provider-driven `update` of a key copy wedges the push-apply until `[skip-web-platform-apply]`; the inngest pair
  already accepts this trade.
- The preflight reads Doppler names only, so a present but wrong R2 pair passes it and fails at the provisioner (a
  best-effort alert, not a stopped birth). Whether a birth must instead fail closed on that is a recorded open question for #9372, before any
  web-class host holds data. The preflight runs after the reviewer approval of the dispatch environment, so a refused birth
  spends one approval. The preflight uses a write-capable provider token; a read-only token is a tracked deferral (#9461).
- Sequencing: this change must merge before `apply-web-platform-infra.yml` is enabled. If that workflow were enabled
  between the merge of #9397 and the merge of PR #9448, it would create the key from the shared password and the swap would
  then plan as an `update` that the new HALT stops; recovery is to treat the swap as a rotation of a never-formatted key
  and re-create the Doppler secret and its state entry under review.
- **Owned by #9372, none of it done here** (acceptance criteria 2, 3 and 4 in the issue comment cited above). (1)
  *Passphrase-loss recovery* for a data-bearing web-class host (Art. 32(1)(c)): define and test it, and re-attest the
  Article 30 cells. (2) *Escrow re-attempt for a data-bearing host:* the provisioner attempts escrow once per instance, so
  an `escrow=missing` alert cannot be cleared by re-running it, and a host replace of a host that holds data is not an
  acceptable answer; define a re-escrow step before web-2 receives data. (3) *Create-exemption expiry:* the rotation HALT
  treats a `create` as legal because no web-class volume is formatted yet; that basis ends when the rebirth formats web-2,
  after which a lost or rewound state entry (planned as a `create`, overwriting the live Doppler secret) must be counted too.
  The exemption applies to all six addresses, including web-1's long-lived pair, where a `create` can only mean state loss.
  > **Superseded 2026-10-06 (#9372), in part:** item (3) is done for the web-class passphrase from the merge of the retirement
  > change (#9569): the HALT now counts a `create` of the web-class passphrase. The exemption still applies to the other five
  > addresses, including the web-class key copy and web-1's pair. Items (1) and (2) stay open.
- **Indexed-address blind spots.** The rotation HALT compares a base address, with a module prefix and a trailing
  instance index stripped (`luks_passphrase_base` in `destroy-guard-filter-web-platform.jq`), so
  `random_password.workspaces_luks_web["web-2"]` is the same secret to it. The three dispatch gates match exact addresses
  by design: an indexed or module-prefixed address is not in their allow-set and aborts as out of scope. Not covered:
  the workflow census recognises a host-creating job by a `terraform apply` (any global-option form) beside an indexed,
  bare-map or non-literal `-target`/`-replace` of `hcloud_server.web`, so a plan/apply split across two jobs where the apply
  job names no target, a birth wrapped in a script file or nested composite action, a dependency pull (a `-target` of a
  resource whose closure includes the server, which the per-merge jobs answer with their `host_creates` HALT), a `terraform
  destroy` or Hetzner API delete step, a terraform call whose binary name is built at run time, flags held in a variable or
  array and expanded at the call (`F="-target=hcloud_server.web"` then `terraform apply $F`), and (for the later-step
  rule) job- or workflow-level `defaults.run.shell` are not seen; a message string that merely starts with the binary is a
  known over-flag. Owner: #9372
  (criterion 1: run the preflight before its first destructive step).
- **Static census limit.** The `--static` census is a NAME census over `*.tf`, `*.tf.json`, `*.yml`/`*.yaml`, `*.sh`,
  `*.tpl`/`*.tftpl` and `*.service` under the infra tree. It fails if web-1's password generator
  (`random_password.workspaces_luks`) or its Doppler copy (`doppler_secret.workspaces_luks_key`, the same value) is named
  in code outside `workspaces-luks.tf` (exact relative-path match), if a Doppler data source (`data "doppler_secret"` or
  `"doppler_secrets"`, HCL or JSON spelling) appears outside web-1's own files, or if web-1's token address is named
  outside its definition file; an empty census is a failure, not a pass. It does NOT see a value that reaches the web-class
  secret by a route that names none of these (a variable, a remote state, a `.tfvars` file, a copy made by a person or an
  out-of-band script, an indirect flow through a local that is itself assigned in `workspaces-luks.tf`), and it never proves
  value distinctness. The file-scoped suite `workspaces-luks-header-web.test.sh` additionally pins the web-class passphrase
  block in its own file. Value distinctness is unchecked by design (see "Rejected").
- **A birth that holds the escrow pair names but not working values** passes the preflight and is caught only at the
  provisioner, as a best-effort alert (above). Fail-closed on `escrow=missing` is #9372 criterion 5.
- **The "first create" premise is read from the workflow state and the commit history, not from Doppler.** The web-class
  key has never been applied because the push-apply workflow has been disabled since 2026-10-01 and the key resource first
  appeared on 2026-10-03; nothing in the repository can show that no person set `WORKSPACES_LUKS_KEY` by hand in
  `prd_workspaces_luks_web`. The provider's create overwrites an existing secret, and the HALT does not count a `create`.
  Before the reviewed push-apply the checker's live mode must either report the key missing or, while the config does not
  exist yet, exit 3 with the NOTE that the config was not found (it never reaches the per-name check then); after the
  push-apply creates the config and before the mint, a key present must be only the one that apply created, and the reviewed
  plan must show creates only for the web-class pair. Tracked as C8 with the other open legal conditions in
  <https://github.com/jikig-ai/soleur/issues/9377#issuecomment-5974285193> (C4: supersede the conditional wording in the
  register cells after the push-apply; C5: verify the Sentry rule edit applied; C8: this check).
  > **Superseded 2026-10-06 (#9372), in part:** "the HALT does not count a `create`" no longer holds for the web-class passphrase
  > from the merge of the retirement change (#9569). The premise itself (a hand-set value cannot be excluded from the
  > repository) is unchanged.
- **The credential read in the preflight's fallback arm is not seen by the privileged-tier census.** The census's check of
  workflow `run:` bodies does not scan scripts, so the single-secret read of the workplace provider token inside
  `scripts/web-host-escrow-preflight.sh` is invisible to it; the shape check on the value read is the only control, and a
  read-only credential for this check is #9461.
- **A runner-local copy exists.** The push-apply's arming step writes the root's state as JSON to `$RUNNER_TEMP`
  (`terraform show -json`, which does not redact sensitive values), a deliberate pre-existing choice that already holds web-1's
  passphrase and every other state secret for the life of a GitHub-hosted job. Once the web-class key exists it holds that
  passphrase too; "Doppler secret and Terraform state" describes the durable copies only.

> **Superseded 2026-10-05 (#9377, counsel-review C4/C8), in part:** "has never been applied because the push-apply workflow has been disabled since 2026-10-01" does not hold: the key was created by a dispatch of `apply-web-platform-infra.yml` (run 37209725107, 2026-10-04) after that workflow was enabled for dispatches, and a read of its state on 2026-10-05 returned `active` (one observation; it was toggled around dispatches earlier). The pre-apply checks in this bullet were met in part: a names-only preflight inside run 37200210561 (`web_host_replace`, 2026-10-04 12:05:58Z) reported the three Terraform-managed names missing 2.5 h before the apply; a `--live` read showing the key missing immediately before the apply was not recorded (counsel review C8 limit (d)).

**Rejected, with the reason.** A separate `sentry_alert` for `escrow=missing` (moving the stage buys the best-effort alert with no new
frequency slot or import bijection). `prevent_destroy` on web-1's `random_password.workspaces_luks` (the HALT covers it and
`workspaces-luks.test.sh` pins that file's exact content). Comparing the two passphrases by value in CI (it would give a CI
job read access to web-1's key to prove what Terraform already guarantees structurally). A read-only Doppler token for the
preflight (needs a live mint; deferred and tracked at #9461).

**Still open on #9377, gated and live-only.** The live R2 pair mint with a signed `HEAD` isolation proof in both
directions (only possible after the push-apply has created the config); retiring the pre-split token; the remaining census
proofs; the runtime link-local-in-live-chain assertion.

> **Superseded 2026-10-05 (#9377, counsel-review C4/C9), in part:** "only possible after the push-apply has created the config" is met: the config was created on 2026-10-04 at 07:27Z by `apply-deploy-pipeline-fix.yml` run 37185772362; the mint and its two-way proof are the operator's report on #9377 and remain C1.

## Addendum — 2026-10-04 (#9377)

Offline only. This addendum records the mechanism that the PR carrying it (#9481, `Refs #9377` and `Refs #8609`, never
`Closes`) adds for the first creation of the web-class escrow resources. Nothing here was applied: no workflow dispatch, no
Doppler or Cloudflare write. Every "will" below is conditional on the owner's separate, explicit authorization of each
dispatch. The status stays `adopting`; nothing below says web-2 is encrypted, and every statement that it is LUKS-backed
stays conditioned on the live conversion (#9372).

**D9 (new): a dedicated, create-only workflow is the only automated creation path for the web-class escrow resources while
the push-apply is disabled.** `apply-web-platform-infra.yml` is `disabled_manually` (measured 2026-10-04; it was toggled for individual dispatches that
day), so the three
Terraform-managed names of `prd_workspaces_luks_web` (`WORKSPACES_LUKS_KEY`, `WORKSPACES_HEADER_BUCKET`,
`WORKSPACES_HEADER_R2_ENDPOINT`) do not exist and the escrow readiness preflight cannot pass. `apply-web-escrow-create.yml`
is dispatch-only (typed confirm, a reason echoed to the step summary, `plan_only` defaulting to true) and plans with exactly
five `-target` addresses and no `-replace`: `cloudflare_r2_bucket.workspaces_luks_header_web`,
`random_password.workspaces_luks_web` and the three `doppler_secret` copies. It contacts no host, runs no Terraform state
command, imports nothing and arms no heartbeat. It runs in `infra-privileged` and takes the shared concurrency group
`terraform-apply-web-platform-host` (the lockless R2 state's only serializer), not the job-level `web-1-swap` group, because
it touches no SSH bridge credential.

> **Superseded 2026-10-04 (#9492), in part:** "do not exist" no longer holds. A dispatch of `apply-web-platform-infra.yml` (run 37209725107) created all five resources at 14:35 UTC. A plan-only run of this workflow (run 37222472359) then reported `No changes`, and the readiness diagnostic (run 37222879953) failed only on the two R2 names, the operator mint. A dispatch of this workflow therefore plans nothing to create today; it stays single-use and retires with #9372 (below). The 2026-10-03 addendum's statements that the push-apply has not created the web-class key are superseded the same way, and the first live apply has happened, so re-evaluation trigger 1 (the CLO's measured supersession, counsel review C4) is due; it is tracked on #9377 and not performed here. The sentence above is kept as the dated record.

> **Superseded 2026-10-05 (#9377, counsel-review C4), in part:** "while the push-apply is disabled" and "`disabled_manually`" are dated observations. `apply-web-platform-infra.yml` returned `active` on 2026-10-05 and ran dispatches that day (07:47Z and 07:51Z, both failed at the plan gate; 12:31Z, success; counsel review re-evaluation trigger 8); it was toggled around dispatches, so read its state again before relying on either description. The five-address plan gate of this workflow's design is unchanged.

**The gate shape.** (1) An inverted allow-set: every plan entry that is neither no-op nor read must be exactly `["create"]`
at one of the five addresses; any other address, any other verb list, an indexed or module-prefixed spelling, an entry whose
action list is missing or empty, or a `doppler_config.workspaces_luks_web` change aborts before any mutation. The workflow
measures no state fact, so the abort says only what the plan shows: a `create` means the config is not in this root's
state (it is a `-target` dependency of the three `doppler_secret` copies; `apply-deploy-pipeline-fix` or a push-apply
creates it), any other verb is read as state and live disagreeing (inferred), and the workflow has no import verb. The
destination of every `doppler_secret` create is read from the graded plan (project `soleur`, config
`prd_workspaces_luks_web`, a well-formed upper-snake name) and that name is what the live precondition checks, so a repointed config or a
renamed secret cannot slip past a restated literal. (2) The seven shared
destroy-guard counters of `tests/scripts/lib/destroy-guard-filter-web-platform.jq` must read zero with `plan_ok` true; under
`-target` most of them cannot see untargeted resources, so they are defense in depth and the allow-set is the guard. A first
create of the passphrase and its key copy is legal under `luks_passphrase_rotations`. (3) A names-only live precondition
(`scripts/web-escrow-create-names.sh`, the only Doppler verb being `secrets --only-names`, the listing written to a file and
never to the public log) aborts when a plan-created key copy's name already exists live, and never reads an unreadable
listing as absent. After an applying run the same reader re-reads the names.

**First-create legality ends once a web-class volume is formatted (the #9372 rebirth).** After that, a state loss or
rewind would plan a `create` that overwrites a live secret, which the push-apply's rotation HALT cannot tell from a first
create. From that point the live names precondition, not the plan gate, is what refuses it (and it also refuses a
hand-set value and an inherited `prd` name, a false positive that is safe). The workflow is therefore single-use and retires
with #9372; the coupled artifacts are listed in
<https://github.com/jikig-ai/soleur/issues/9372#issuecomment-5980161163>.

> **Superseded 2026-10-06 (#9372), in part, from the merge of the retirement change:** the line "A first create of the passphrase and its key copy is legal under `luks_passphrase_rotations`" (gate-shape item 2 above) no longer holds for the web-class passphrase. From the merge of this change the rotation HALT of `tests/scripts/lib/destroy-guard-filter-web-platform.jq` counts a `create` of `random_password.workspaces_luks_web` and the apply refuses it with no acknowledgement path. A create of `doppler_secret.workspaces_luks_web_key` alone stays legal (it restores the same state-held value, and a missing copy is itself an incident; the CTO's re-ruling of 2026-10-06 narrowed the earlier two-address scope), as does a first create at the other four addresses. The single-use escrow-create workflow (`apply-web-escrow-create.yml`) and its names helper are retired by the same change; the push-apply can still create the escrow config, bucket and name secrets, and a create there is not halted. There is no documented or verified automated recovery for a lost passphrase entry: importing the existing value is not a supported route (measured in a sandbox with the lock-pinned random provider, the import plans `special = true -> false`, a forced replacement that `prevent_destroy` refuses and that, forced, would mint a new passphrase), the live value is unharmed while its Doppler copy exists, and the repair is the owner's decision (the state backend has no versioning, ADR-006). Whether an import plus a state-attribute fix yields a clean plan is unmeasured and tracked on #9572. The status stays `adopting`, and this marker does not record that the rebirth has run: it is dispatch-only and still pending. The passages above that describe the live names precondition describe the retired workflow's design and stay as the dated record. The text above is kept as the dated record.

**Alternatives considered and rejected.** Re-enabling `apply-web-platform-infra.yml` (its whole-root plan carries unrelated
destroy and replace entries, and the file sits near its byte cap). A new `apply_target` on that workflow (same file, same
cap). A local, ungated `terraform apply` from a workstation (bypasses every gate and the serializer;
`hr-all-infrastructure-provisioning-servers`). A Terraform root of its own (a second state for four resources, with its own
lock question). A pre-apply copy of the state object to a dated key (a raw state read in a workflow scoped to no state
verbs); #7992 tracks the capability once, for every applier.

**Known limits.** Authorization is process, not mechanism: `infra-privileged` has a main-only branch policy and no required
reviewer, so the typed `confirm` token and the owner's per-dispatch authorization are the only gates on a dispatch; the
plan-only-first order is likewise a convention. A `doppler_secret` create is an upsert (recorded in the 2026-08-01
credential-delivery plan), so the live names precondition is the only barrier between the plan and a silent overwrite, and
the window between that check and the apply is not closed by a second read (a human Doppler write inside it would be
overwritten; the group serializes appliers, not people). The listing is read from the Doppler CLI table, shared with the
`--live` checker; an unrecognised shape is refused, a truncated name is not detectable offline. The state that will hold
the passphrase is Tier-A readable (ADR-241 residual R2). The shared concurrency group keeps one running and one pending run, so a run queued behind another
displaces an older pending run of any workflow sharing the group (`apply-web-platform-infra.yml`,
`apply-deploy-pipeline-fix.yml`, `workspaces-plaintext-forget.yml`); the runbook step says to confirm the run actually
started. The backend is lockless, so a cancelled running apply can leave a Doppler secret that state does not hold; the names
precondition then refuses and a person decides. The passphrase exists on the runner for the life of the job and in
Terraform state (no object versioning, #7992). Creation proves that names exist, not that a header can be restored (#9372
criterion 2) or that the R2 pair is bucket-scoped (intended to be scoped, unverified until the signed isolation proof on
#9377). The R2 access-key pair is not Terraform; the workflow prints the mint as the next step.

**Follow-through that this change does not perform.** The first live apply fires re-evaluation trigger 1 of the legal
posture: after reading state and re-reading the Doppler names, a dated `Superseded` marker is appended under every
conditional sentence of the Article 30 and compliance-posture records without deleting any text, the two cells are kept
byte-equal after bold removal, and `python3 scripts/lint-encryption-posture.py` is re-run (counsel review C4; owned by the
CLO agent with the owner holding a veto). The GDPR gate must run when the first data-bearing web-class host is born.

## Addendum — 2026-10-05 (#9377, counsel-review C4)

**What this addendum does.** It performs the follow-through the 2026-10-04 addendum left open ("Follow-through that this
change does not perform"): the first live apply has happened, so the conditional sentences about the web-class key are
superseded by measured state. Each is kept as the dated record and carries a `Superseded 2026-10-05` marker; the Article 30
register and compliance-posture cells carry the same marker, byte-equal.

**Measured state (read-only; GitHub Actions run logs and the Doppler config audit log; no secret value was read).**

- The web-class key exists. Run 37209725107 (`apply-web-platform-infra.yml`, `workflow_dispatch`, 2026-10-04 14:33:54Z to
  14:37:14Z) planned 7 to add, 0 to change, 0 to destroy and created `random_password.workspaces_luks_web`, the three
  `doppler_secret` resources (`WORKSPACES_LUKS_KEY` at 14:35:38Z, the bucket name and the R2 endpoint), the R2 bucket
  `soleur-workspaces-luks-header-web` and two unrelated Better Stack resources. It was a manual dispatch by the operator, not a
  push-triggered run. The web-class config and its read-only token were already in Terraform state when it began (refresh lines in its plan), and
  no run of that workflow had applied since 2026-10-01 (run 37187540739 on 2026-10-04 08:00Z ran only `entrypoint_audit`), so they came from another route: `apply-deploy-pipeline-fix.yml` run 37185772362 (`workflow_dispatch`, 2026-10-04 07:26:12Z to 07:27:32Z; 3 added, 1 destroyed,
  no secret written), which created `doppler_config.workspaces_luks_web` at 07:27:08Z and `doppler_service_token.workspaces_luks_fresh_boot_web` seconds later as
  `-target` dependencies of the web-host `user_data`, as the Superseded 2026-10-04 (#9481) callout in this ADR already records.
- C8 evidence, first-create premise: the Doppler audit log of `prd_workspaces_luks_web` (read by the author of this change at about 13:43Z on 2026-10-05 and not
  re-read by counsel; 9 entries, the whole history of
  the config) holds no secret write between the config's creation (2026-10-04 07:27Z) and the three writes at 14:35:37Z to
  14:35:38Z that match run 37209725107's three creates one to one. A plan-only run (37222472359, 17:57Z) read the live
  value back and reported no changes. The decisive control is not any of those reads but that the provider's create writes the value whether or not one
  exists (ADR-263 Known limits record it as an upsert; not measured here): a value set by hand before 14:35Z would have been overwritten by the generated
  one, and a value set by hand afterwards would show as an update in the next plan. That upsert premise is what remains unmeasured. Limits, as posted at <https://github.com/jikig-ai/soleur/issues/9377#issuecomment-5995711642>: every entry carries the operator's account, because
  the provider runs on the workplace personal token, so the actor cannot separate a person from Terraform; the audit log
  carries no secret names. The window after the apply is closed to 2026-10-05 12:32Z by the allow-list plan of dispatch run 37310111213, which refreshed `doppler_secret.workspaces_luks_web_key` and reported no changes; a later change is excluded only by the next Terraform refresh (the 06:02Z scheduled drift run is not relied on: its log carries no refresh lines for these resources, and its plan listed no web-class resource but did report drift on other hosts).
- The names-only readiness diagnostic (run 37279392332, 2026-10-05 07:44Z) passed with `escrow-split-contract:live-ok`.
  It reads names and not values, so it is necessary and not sufficient.

**Not superseded, still open.** C1: the two R2 credential names exist as of 2026-10-05 07:44Z (the names-only check above; the mint itself is the operator's report on #9377, and the same check had reported both missing on 2026-10-04, run 37213826582), and the signed `HEAD` isolation results are
recorded on #9377, but no proof record exists under `knowledge-base/` and this change did not re-run the proof, so the
cells keep "intended to be scoped". C2: the pre-split token is not retired, so the narrowing holds for new births only. C3
(#9372 items), C6 (state restore substrate, #7992) and the web-2 statements are unchanged. Nothing here says web-2 is
encrypted.

## Addendum — 2026-10-05 (#9372, offline PR: the workflow is merged inert)

**Status of this addendum.** The decision below is true of the **code** at merge. The rebirth has **not** run; nothing here says
web-2 is LUKS-backed. The workflow is dispatch-only with `plan_only` defaulting to true, and a dispatch needs the owner's explicit
go-ahead plus the `web-platform-infra-apply` reviewer approval.

**D10 — the rebirth is `-replace` over five explicit targets, not a destroy plan plus `web-host-create`.** The "Live conversion"
section above describes the operation as delete the volume, remove the state address, destroy the server and attachment, then run
`web-host-create`. Measured against the repo, a destroy-mode plan on the server also takes its dependents (including
`hcloud_firewall_attachment.web`, which would strip web-1's firewall), and the create job is not dispatchable from another
workflow. So `.github/workflows/web2-luks-rebirth.yml` (a new file: `apply-web-platform-infra.yml` is at its byte cap) deletes the
empty volume through the Hetzner API (detach, then DELETE, 404 meaning already gone), forgets the volume and its attachment with
`terraform state rm`, and then applies ONE `-replace` of `hcloud_server.web["web-2"]` over five `-target`s (server, private NIC,
keyed volume, volume attachment, fleet firewall attachment). With the volume absent from state the plan CREATES it, raw (no
`format`, D2), and `prevent_destroy` is never tripped because Terraform never destroys the volume.

**Contracts.** (1) `tests/scripts/lib/web-host-rebirth-gate.sh` grades two plans with its own allow-set, never reusing the birth
gate, the replace gate or `web2_retire_allow` (each header forbids it): `pre` (dry plan on current state; the volume is a no-op),
`post` (after the delete and `state rm`; the volume is created raw, size, labels and name checked), and `post-heal`. Allowed
action sets must EQUAL an allow-list entry, so a volume delete, forget or replace is unrepresentable; every destroy is pinned to
a physical id captured from Hetzner (server id and name, NIC `server_id`, attachment `volume_id`); the by-name web-1 refusal is
the first statement. (2) A pure classifier (`tests/scripts/lib/web2-rebirth-classify.sh`) maps Hetzner and state to `proceed`, a
named `heal:` window (detach done, delete done, state rm done, apply midway, volume created), `resume:post_apply` (the rebirth
already ran: state holds the new volume as web-2's only volume, the pinned plaintext volume is gone and the server is
younger than 72 h (the never-pooled step, not the classifier, requires the soak marker to be absent), the bound being "a rebirth that has not yet had time to be certified"; nothing is replaced or deleted: a third plan mode may only
ADD what a partly failed apply left missing, then the readiness poll, the recovery check and the reboot run) or `refuse:`
(already reborn, orphan raw volume, orphan server, a foreign volume attached to web-2, an inconsistent pin listing, wrong shape,
attached elsewhere, duplicate name, push-apply pause not real) before any write, so a re-dispatch after any crash heals, resumes or
refuses. `scripts/web2-rebirth.sh` is also the chokepoint for the irreversible step: its write subcommands refuse unless the run is an
apply dispatch, and `delete-volume` refuses unless the emptiness, never-pooled and pre-plan-graded proofs (each step's own output, empty
when the step was skipped) are present. (3) Emptiness evidence is the 7-day Better Stack `host_metrics` series (hour coverage, freshness, a non-zero minimum, a 1 GiB
ceiling, a 64 MiB spread, a 15 to 21.5 GB total; freshness is dropped only for `heal:detach_done`). The ceiling is a COARSE bound,
so the printed used-bytes values are what the owner approves on, and the first live query is the first measurement of the real empty
baseline. Never-pooled evidence is the soak marker's absence by exact-name membership over secret names, from a list shape the
reader can interpret (anything else is a refusal). Web-2's serving weight is NOT measured: no weight orchestrator exists in the repo
at this SHA, and the summary says so instead of asserting weight 0. (4) The escrow preflight runs before any Terraform command or Hetzner call; a missing escrow does NOT refuse the
format (the volume is empty; the readiness verdict goes RED and the soak marker is withheld).

> **Superseded 2026-10-06 (#9372), in part:** "the printed used-bytes values are what the owner approves on" and "the first live query is the first measurement of the real empty baseline" no longer hold; see the addendum at the end of this ADR.

**What this change altered outside the workflow.** The reboot proof is now REQUIRED where it was only diagnostic:
`scripts/lib/web2-luks-rows.sh` gains `w2l_reboot_seen`, which compares the `boot_id` tokens of the GREEN probe and readiness
verdicts (known and different), and both the marker-absent branch of `w2l_judge` (so `WORKSPACES_LUKS_CUTOVER_AT`, and with it any
weight, cannot be written on the readiness row alone) and the follow-through require it. A new `reboot_not_seen` reason is
`not_live`, not red, between a rebirth and its first reboot.

> **Superseded 2026-10-08 (#9372), in part:** the reboot-proof requirement stated above (including `w2l_reboot_seen` and `reboot_not_seen`) no longer holds; see the addendum "evidence rule: immutability, not reboot" at the end of this ADR.

**Known limits and what is unconfirmed.** The Better Stack JSON paths for the used-bytes series and whether `dm-*` excludes the
mapper device in `vector.toml` are unverified until the first live query (an absent field fails closed). `cryptsetup open
--test-passphrase` against a header-image file is covered by shims only. The birth-time recovery check (the escrowed header
object exists, begins with the LUKS magic and carries the UUID in its name; the Doppler and Terraform-state passphrases agree;
a test unlock of the downloaded header) is a **birth-time consistency check, not a restore test**: it does not prove the live
volume opens, that the backup matches the live volume, that either copy survives loss, or that the state bucket is versioned
(#7992). It does not discharge the recovery or re-escrow acceptance for a data-bearing host; web-2 stays at weight 0 and holds no
workspace data until those and #7992 are done. The marker config's only token is read/write today (#9358), bound to one
names-only step that a census holds to that. Authorization is process, not mechanism: the typed confirm is a typo guard.

> **Superseded 2026-10-06 (#9372), in part:** the Better Stack JSON paths are now confirmed (the `dm-*` exclusion is still unconfirmed); see the addendum at the end of this ADR.

**Single use and retirement.** The workflow, `scripts/web2-rebirth*.sh`, `tests/scripts/lib/web-host-rebirth-gate.sh` and
`tests/scripts/lib/web2-rebirth-classify.sh` are deleted after use in the closing change (runbook
`web2-luks-rebirth-9372.md`, "Closing checklist"), together with the retirement of `apply-web-escrow-create.yml` and the flip of the
rotation HALT's `create` exemption, which the apply path of this workflow requires to have merged first.

> **Clarified 2026-10-06 (#9372):** "the closing change" in the paragraph above names two changes. The retirement of
> `apply-web-escrow-create.yml` and the flip of the HALT's `create` arm merge together as PR #9569. The deletion of the rebirth
> workflow, its scripts, gate and fixtures is a later change made after use (runbook `web2-luks-rebirth-9372.md`, closing
> row 5).

> **Superseded 2026-10-06 (#9372), in part — the emptiness evidence's paths and who reads its numbers.** Two sentences above no longer
> hold. (1) "the first live query is the first measurement of the real empty baseline" and "unverified until the first live query": the
> first live plan-only run (run 37463995633) read the flat paths `host_name`, `source_kind`, `metric.name` and `metric.value`, which no
> stored row carries, matched zero rows and went RED `used_bytes_absent_or_host_dark`. A read-only control against the stored rows then
> confirmed the native shape (`tags.host`, `namespace`, `tags.mountpoint`, `name`, `gauge.value`) and read the level for
> soleur-web-2 `/mnt/data` (one device, `/dev/sdb` ext4, 7 days): 169 hours, used 15,556,608 to 16,027,648 bytes (spread 471,040),
> total 20,957,446,144. The query now reads those paths, requires a single non-empty device per metric group and rows no later than now; whether `dm-*` drops the LUKS mapper
> device in `vector.toml` remains unconfirmed. (2) "the printed used-bytes values are what the owner approves on": the environment
> approval is a job-level gate, so it comes before the evidence step. The numbers are readable in a plan-only run, and an apply
> dispatch's PASS flows into `delete-volume` in the same approved job. The thresholds, the verdict function and the `heal:detach_done`
> arm are unchanged; the 1 GiB ceiling is about 65 to 70 times the observed level, and tightening it is an owner decision.

## Addendum — 2026-10-07 (#9372, the reboot workflow)

**An agent-dispatchable soft reboot of the allow-listed web-2 standby (`.github/workflows/web-host-reboot.yml`) is the path for the graded reboot evidence.** It issues one Hetzner reboot request behind the `web-platform-infra-apply` environment approval and then reads Better Stack rows, reporting PASS (row presence only), FAIL or NOT YET. It states nothing about the volume or its encryption: a fixed footer on every output path names `scripts/followthroughs/web2-luks-live-6931.sh` as the grader, and web-2 stays *provisioned, proof pending* until that grader reports PASS. **The gate is a rule, not a platform separation:** that environment's sole reviewer is the owner's own login and `prevent_self_review` is off (measured 2026-10-07), so the dispatching agent's identity could approve its own dispatch; what separates the two is the owner's go-ahead per dispatch and the owner doing the approving, recorded in ADR-241 (dated section 2026-10-07; whether destructive dispatches should be two-party is tracked on #8044). It depends on the never-pooled reader, refuses web-1 by id at four layers, refuses a re-run by design, and is dispatch-only, so merging it mutates nothing. It is retired in the rebirth closing change together with `scripts/web2-rebirth*.sh` and its own tests (closing row 5 of the rebirth runbook), or kept only by a recorded owner decision made in the same change that edits the tombstone rows in both suites. Operations: `knowledge-base/engineering/operations/runbooks/web-host-reboot.md`. No new Alternatives rows: the two rejected routes (dispatching the rebirth workflow for a plain reboot, and a Hetzner web-console reboot) are recorded in that runbook and the plan.

> **Superseded 2026-10-08 (#9372), in part:** the workflow is no longer "the path for the graded reboot evidence"; no reboot is part of the evidence rule. See the addendum at the end of this ADR.

## Addendum — 2026-10-08 (#9372, evidence rule: immutability, not reboot)

**Decision.** The owner decided on 2026-10-07: "Immutability is the principle I want to encode". A host is replaced, not rebooted, so the evidence criterion for web-2 is amended and web-2 is not rebooted to satisfy it. This supersedes the reboot-proof requirement wherever it is stated above (the status paragraph, "Live conversion", "What this change altered outside the workflow"; each is marked in place). `w2l_reboot_seen` and the `reboot_not_seen` reason are removed from `scripts/lib/web2-luks-rows.sh` and from the not-live condition of `workspaces-luks-verify.yml`. Both consumers of the old rule change together in one PR, because they share the lib predicate.

**The rule.** The evidence is the readiness row of the instance that is running. It is green (`luks=1`, `luks_arm` in `formatted|opened`, `escrow=ok`), so that boot reports having brought the volume up (self-reported; the probe rows are the independent check). For the #6931 grader, probe rows after it are green (`device_type=crypto_LUKS`, `mount_source=/dev/mapper/workspaces`, escrow ok) on at least 3 distinct days, and any non-green probe row after it spoils the soak. A reboot is not required, and the `boot_id` of the probe rows is no longer compared with the readiness row's. `luks_arm=noop` is not accepted, although `w2l_ready_verdict` still tolerates it for the rebirth ready-poll; a noop or arm-less boot is a standing `ready_luks_arm` RED that only replacing the host clears, because the readiness row is written once per instance. The predicate is `w2l_ready_arm` in the lib, judged on the newest readiness row, and is used by the grader (arm 4) and by `w2l_judge` (the marker-absent branch).

**Instance identity is a weak anchor, and it is an advisory deviation from AP-027.** Rows carry no server id, so "the running instance's readiness row" means "the newest readiness row for the host". The readiness POST is best-effort, so a replacement whose POST is lost leaves its predecessor's row as the newest and the rule cannot tell. A marker that is already present is kept on the newest probe row alone, so a replacement inside the daily cadence can inherit it. The reboot rule did not close either gap (a replacement has a different `boot_id` too); this addendum records them instead of claiming them closed.

**What the marker gates (coupling #2).** `WORKSPACES_LUKS_CUTOVER_AT` is the fence in `lb-weight-gate.sh` (B.6-B.10, ADR-143 D3 coupling #2): a weight flip is the only way user data reaches web-2, and a flip requires the marker aged at least 3 days. The check is shape-only (ISO shape and soak age, not provenance). After this addendum web-2 can earn the marker on the first `web2_marker` run without a reboot, from one fresh green probe row and the readiness arm, and the 3-day age runs from the write. A marker that is already present keeps its original write time, so a replacement that inherits it (see above) arrives with the predecessor's age already met: marker age must never stand in for the new instance's soak. That is a loosening of what earns the marker, made on purpose. **A present marker is not a #6931 PASS** (no three distinct days, no scan for non-green rows) **and no longer evidences that the volume reopens after a reboot.** The flip orchestrator (#9358) must require the grader's PASS and the on-host runtime-bind probe, and ADR-263 "Known limits" still holds web-2 at weight 0 with no workspace data until the recovery acceptance and #7992 are done. Nothing calls the gate today. Once the marker is present, the never-pooled gate of the `web-host-reboot` workflow refuses reboots of web-2 by design.

**What is unchanged.** Every other judge and grader arm, the 72 h minimum, the 26 h freshness, the window rule, deletion of the marker on RED, and the #6931 directive. The wording in `scripts/web2-rebirth.sh` and `web2-luks-rebirth.yml` that named the old boot-id proof is corrected in the same PR; the restart step inside the rebirth workflow stays until the cleanup PR retires it together with the `web-host-reboot` workflow (closing row 5 of the rebirth runbook).

**Status of the claim.** The rule is not yet met by graded rows. web-2 remains *provisioned, proof pending* until the #6931 grader reports PASS. Nothing in this addendum is evidence for the encryption-posture ledger, Article 30 or any customer-facing sentence.

## Addendum — 2026-10-10 (#9879, divergence note for the inngest sole copy)

Appended; nothing above is edited. **A deliberate divergence from this ADR's pin set, recorded so it is not mistaken for a
gap.** ADR-282 gives the Inngest sole-copy volume (`hcloud_volume.inngest_redis_luks`) delete protection plus
`prevent_destroy` on the volume, its passphrase pair and the two Doppler cascade parents, but **no `prevent_destroy` on its
attachment**, where this ADR's web-1 pin set puts one on `hcloud_volume_attachment.workspaces_luks`. The reason is
structural: web-1's host-replace dispatch refuses web-1 by name, so nothing sanctioned replaces that attachment, while the
sanctioned `inngest-host-replace` replaces the Inngest server and therefore its attachment (ForceNew on `server_id`).
The Inngest attachment is protected by the dispatch gates and the reachability pins instead. This note changes nothing about
web-1, web-2 or this ADR's decision. It takes effect on the merge of PR #9925 (adopting until that merge's apply and
read-back, per ADR-282).
