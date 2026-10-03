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
and `mount_source=/dev/mapper/workspaces` (the new `boot_id` is evidence that a reboot happened; no judge requires it). The host's SSH key changes, so the committed pin is re-captured
(`scripts/capture-web-2-host-key.sh`, plus the admin-ip step its runbook names) as part of #9372; none of the SSH
consumers affected in that window is in the LUKS path, but `apply-deploy-pipeline-fix` fails closed until the
pin is re-captured. The window is web-2 only (weight 0, serving nothing, holding no user data); web-1 is
untouched. #9372 also owns the ledger flip (D6), the follow-through enrollment's `earliest` date and the
escalation if web-2 never produces rows.

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

**R4 is narrowed, not closed.** Narrowed on merge for every NEW birth (inferred, not read from a host: `hcloud_server.web` ignores `user_data` and
the token postdates both live hosts; the retirement step must confirm it is destroyed); closed when the old token is retired. The shared passphrase residual
above stands unchanged: a compromised web-2 still reads web-1's passphrase.

**Option (b), an R2 bucket lock, is rejected.** R2 has no object versioning, an age-based lock leaves a window after
retention expires, and an indefinite lock would break web-1's cutover flow, which rewrites the header object.

**`doppler-config-inventory.txt` is deliberately not edited**, for the same reason the marker config is absent from it:
adding a name mints a drift-read token and forces floor edits.

**Precondition for the live conversion (#9372).** `scripts/check-web-host-escrow-config.sh` in live mode must pass
before the workflow runs: the provisioner formats even when escrow is missing, by design. It is not run by the PR that
introduced it.

**#9358.** `lb-weight-gate.sh` stays pure and env-only; `lb-weight-gate-with-marker.sh` is the one seam through which the
workspaces cutover marker reaches it (a names-list membership test, then a single-secret get). The flip orchestrator
that will call it does not exist yet; a census pins that nothing else feeds the gate. The marker stays advisory and
shape-only here: provenance is not validated.

**#9356.** The replace gate gains key-conditional arms for `web-1` behind a SEPARATE constant; the by-name refusal
stays first and intact, so a complete web-1 plan still aborts. The arms do not prove web-1 safe: the by-id mount pin to
the superseded plaintext volume, the web-1-pinned SSH provisioners and upstream-only `-target` are blockers no plan can
show. A header-restore drill joins the real-cryptsetup loopback suite. Whether a non-bypassable HALT on rotating
`random_password.workspaces_luks` is needed (a `[ack-destroy]` can wave one through today) is left open; it is listed in the #9377 follow-up comment as a go/no-go before #9372 dispatches.

**#9378.** The provisioner is hardened in place: `flock` on fd 9 (600 s), a pinned `PATH`, the test seam refused as root on a cloud-init host, and every write to fstab, crypttab, the docker drop-in and the format intent file through one atomic, fsynced `_install_file` that refuses symlinks. The container egress ruleset refuses any CIDR overlapping `169.254.0.0/16`, starts with a rate-limited log rule and an unconditional drop for that range, and the resolver strips link-local answers from every feeder. `case_raw_formats_once` is split into four cases.

**#9357.** Only the offline state-move rehearsal, the runbook and the blocked-by edges (#9421 de-pet rebuild; the held draft PR #9348 cannot be a GitHub dependency) ship. The HCL collapse and the
single-use state-move workflow wait for the held PR B (#9348) and a web-1 de-pet rebuild.
