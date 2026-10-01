---
title: "Phase-4: web-2 fresh-boot guest-side LUKS path"
type: feat
date: 2026-10-01
slug: web-host-fresh-boot-luks-path
branch: feat-one-shot-6931-web2-fresh-boot-luks
issue: 6931
closes: none (soak-gated; the follow-through sweeper closes #6931 on live evidence, the PR body uses Ref)
priority: p2-medium
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# Phase-4: web-2 fresh-boot guest-side LUKS path

## Enhancement Summary

**Deepened on:** 2026-10-01. **Halt gates run and green:** 4.6 user-brand impact, 4.7 observability (command starts with
`bash`, no shell-active bytes, literal `expected_output`, declared `credentials_required`), 4.8 no PAT-shaped variable, 4.10
encryption posture, 4.11 guard contract (`scripts/lint-guard-contract.py`: 3 guards), 4.55 downtime and cutover (section added
below), 4.9 not applicable (no UI surface). Every AGENTS.md rule id cited in this plan resolves to an active rule.
**Research and review used:** repo-research, learnings, functional-overlap (no community overlap), CTO consult (topology and key
delivery), CLO consult, and the plan-review panel (DHH, Kieran, code-simplicity per mechanism, architecture-strategist,
spec-flow, CTO devex lens), then a verify-the-negative sweep and a provider-docs check.

**Key improvements from review and deepening**
1. A crash between `luksFormat` and `mkfs` is now recoverable (intent file); previously it bricked the host on every boot.
2. The P7 emptiness proof no longer relies on a Hetzner usage field that does not exist (evidence set fixed in Phase 0.4).
3. The fresh host gets its OWN read token so web-1's rotation procedure cannot strand it; the soak marker moved to a dedicated
   Doppler config because a daily cron must not hold a `prd` write token.
4. The marker writer distinguishes "query failed" from "negative evidence" and joins rows on `boot_id`; escrow is non-fatal at
   boot and a hard precondition of the marker.
5. Merge-effect is stated and measured from the push-apply trigger and transitive `-target` reach.

**New considerations discovered while deepening**
- `host_metrics` excludes `dm-*` devices, so `/mnt/data` used-bytes exists only while the volume is still plaintext: the P7
  emptiness evidence is a pre-conversion-only signal by construction (fine, it is only used before conversion).
- `store-vs-data-mount-parity.test.sh` governs any block that resolves a mount source with an `lsblk` inverse walk plus a
  `scsi-0HC_Volume_*` reverse map; the provisioner takes the by-id path as given and must not grow such a block (or must satisfy
  that guard).
- `isLuks` occurs in many repo files (git-data, registry, comments, tests); Guard 1's static grep is therefore scoped to the new
  provisioner, `cloud-init.yml` and `soleur-host-bootstrap.sh`, with the reopen script's read-only use allowlisted.
- The provider docs describe `format` as "Format volume after creation" and do not state ForceNew; the pinned provider is
  hcloud 1.63.0, so Phase 0.2 proves ForceNew with a `terraform plan` fixture rather than trusting memory.
- No `delete_protection` is set on any volume in this root, so the Hetzner API delete in P7 is not blocked at the API layer;
  `prevent_destroy` is the only guard, which is why the delete-then-state-removal order and identity re-assertion matter.

## Overview

Give the shared web-host first boot a guest-side LUKS path for the `/workspaces` data volume, so a
freshly born web host (web-2 today; any future cattle host) comes up with `/mnt/data` on an encrypted
`/dev/mapper/workspaces` instead of a plaintext volume. web-1 already runs on LUKS (additive volume
`hcloud_volume.workspaces_luks`, ADR-119; boot unlock merged 2026-09-29 as #9179), but only because a
Terraform SSH installer delivered its boot-unlock units to the running pet host. A fresh host never
re-runs that installer, so today a born web-2 comes up on a plaintext, empty, Hetzner-pre-formatted
volume and is kept safe only by `lb-weight-gate.sh` refusing to pool it.

The binding ruling is **ADR-143 section Implementation Rulings R3** (the issue body cites "ADR-142 D3", its
title cites "ADR-141 D3"; both are wrong ordinals, see Research Reconciliation). R3 deferred this to the
"Phase-4 disposability-proof PR" and listed corrections it MUST inherit. This plan builds that PR.

Six scope items from the issue, mapped to deliverables:

| # | Issue item | Deliverable (phase) |
|---|---|---|
| 1 | guest-side fresh-boot LUKS path keyed by `WORKSPACES_LUKS_KEY` via the boot token | baked `workspaces-luks-provision.sh` + wiring (P1, P2) |
| 2 | `blkid -o value -s TYPE` discriminator, never `cryptsetup isLuks` | provisioner arms + static guard (P1, Guard 1) |
| 3 | `WORKSPACES_LUKS_CUTOVER_AT` soak marker | CI-side writer after a real probe, removed on red (P5, Guard 3) |
| 4 | reconcile the two-mechanism topology split | ruling D1: one boot mechanism, two Terraform addresses; raw-at-birth (P3) |
| 5 | `workspaces-luks-verify` live verification on web-2 | baked daily probe + ledger row `available` (P4) |
| 6 | singleton-rationale comment + AC5 rewrite | comment/ADR/plan wording (P6) |

## Research Reconciliation — Spec vs. Codebase

| Spec / issue claim | Reality (verified in this worktree) | Plan response |
|---|---|---|
| Binding ruling is "ADR-142 Decision 3" (body) / "ADR-141 D3" (title) | ADR-142 is the Inngest Redis AOF LUKS migration; ADR-141 is encryption-posture Layer B. The ruling is ADR-143 R3 (D3 there is the anti-pooling gate rebuild, R3 refines it). `model.c4` prose and `soleur-host-bootstrap.sh` comments repeat the stale "ADR-141 D3". | Cite ADR-143 R3 only; sweep stale citations (P6). |
| `blkid` empty -> `luksFormat` on web-2's volume | `hcloud_volume.workspaces` sets `format = "ext4"` (`server.tf`, block `resource "hcloud_volume" "workspaces"`). Hetzner formats at create, so web-2's volume reads `TYPE=ext4` from birth: the mandated discriminator would hit its FATAL arm and the format arm would be dead code. | Volume must be born raw (D2): drop `format`, add `ignore_changes = [format]`; the live web-2 is converted by a single-use gated rebirth, not by merge (P7). |
| The path goes in `cloud-init.yml` `/mnt/data` setup | `plugins/soleur/test/cloud-init-user-data-size.test.ts` leaves ~300 B headroom (22,450 B budget vs 32,768 B cap). Every fresh-boot analogue (readiness marker, vector install, host scripts) is baked into `soleur-host-bootstrap.sh`; only call sites stay inline. | Logic is baked; `cloud-init.yml` shrinks (two fstab/mount lines become one helper call) (D3). |
| ADR-119 section (d): "a fresh web host must NOT get these units" (`workspaces-luks-reopen.service` header, `workspaces-luks.tf` comments) | Reversed by this change: a fresh host MUST get the reopen unit, otherwise it cannot survive a reboot. | ADR-119 addendum + comment rewrite (P6). |
| `lb-weight-gate.sh` "reads `WORKSPACES_LUKS_CUTOVER_AT` from Doppler" | The gate is pure and env-only; its header says the Doppler-sourcing entry point "ships with the deferred cutover orchestrator", which does not exist. Only `GIT_DATA_LUKS_CUTOVER_AT` has a writer (a `git-data-cutover.yml` step). | This plan builds the writer (the marker lives in Doppler `prd`); sourcing it into the gate env stays with the future flip orchestrator (non-goal, recorded). |
| Topology question is "open": singleton vs `for_each` for web-1 | web-1's plaintext volume was zeroed (CONFIRM_WIPE, #9163). Draft PR #9348 ("PR B") narrows the `for_each`s so web-1 no longer owns `hcloud_volume.workspaces["web-1"]`. The `for_each`-for-web-1 option would now mean a `state mv` of the sole-copy volume, and ADR-119's addendum MEASURED that `moved` fails every `-target` plan on this root. | D1: keep web-1 on the singleton; share the MECHANISM, not the Terraform address; T2 (single keyed resource) deferred behind the web-1 de-pet. |
| #6964: "the `for_each` topology dissolves the hazard" | Under D1 the singleton stays, so the hazard stays and needs a measured refusal. | Gate arm in `web-host-birth-gate.sh` refuses `web-1` (P3, Guard 2). |
| Ledger: web-2 volume row is `plaintext-exception`, `expires_on` 2026-10-22 | PR B (in flight) also edits this row (re-scopes the exception to web-2). | Sequence after PR B (Risks R1); this plan flips the row to `luks` with the live conversion. |

## Research Insights

### Premise Validation (Phase 0.6)

Checked: `gh issue view` on #6931 (OPEN), #6964 (OPEN), #6604 (OPEN), #6588 (OPEN), #6730 (OPEN), #6919 and
#6953 (MERGED). Held: #6931 is genuinely unimplemented (`soleur-host-bootstrap.sh` still says "luksFormat-on-birth is
a tracked deferral"). Stale: the ADR ordinals in the issue (above); the issue's implied "empty -> luksFormat"
reachability (above). ADR corpus check (mechanism vs rejected alternatives): ADR-119 Alternatives rejects
`for_each = var.web_hosts` on the LUKS volume (destroy-guard `web2_allow`, `moved` needs a singleton), and its
2026-09-28 addendum measured that `moved` plus `-target` fails on this root. The CTO consult (below) found the
`web2_allow` blocker largely stale in the current `destroy-guard-filter-web-platform.jq` (the sibling allow-set was
removed with the dispatch sweep); Phase 0 re-verifies before relying on either reading.

### Property List (Phase 0.6b)

- P-a: a web host born with no prior state ends with `/mnt/data` on `/dev/mapper/workspaces`, with no human step.
- P-b: no code path can `luksFormat` (or `mkfs`) a device that carries any filesystem, partition table or signature.
- P-c: a host rebooted after birth re-opens its mapper before any container can write `/mnt/data`.
- P-d: the soak marker that `lb-weight-gate.sh` trusts exists only while a real on-host probe says the volume is `crypto_LUKS`.
- P-e: web-2's LUKS posture is observable without SSH and recorded truthfully in the ledger and the published registers.
- P-f: the `workspaces_luks` attachment hazard (#6964) is enforced by a test, not a comment.

### Cut List (Phase 0.6b)

| Mechanism proposed or tempting | Property it would buy | What already covers it / decision |
|---|---|---|
| Remap web-1's `workspaces_volume_id` to `hcloud_volume.workspaces_luks.id` in `server.tf` | rebuilt web-1 opens the right volume | Not needed for P-a..P-f on web-2; puts the sole-copy volume into every targeted plan graph (ADR-148 warns about exactly this reference path). Belongs to PR B / the de-pet. CUT. |
| Dedicated second Doppler token for fresh hosts | rotation independence and attribution | REVERSED at plan review (was a cut): the shared token is rotated by web-1's `create_before_destroy` procedure, which only reaches web-1, so a shared token would silently strand web-2 on its next reboot. A separate, never-co-rotated token removes the coupling. KEPT (D4). |
| `terraform_data` SSH installer for web-2's units | units on web-2 | Violates `hr-prod-host-config-change-immutable-redeploy`; baking covers it. CUT. |
| Empty-ext4 "safe to reformat" arm | convert the existing web-2 volume in place | Unprovable "empty" on the failure path; also fires on a mis-resolved device. REJECTED (D2). |
| Header-escrow upload for the fresh volume | recoverability of web-2's header (a damaged header strands the volume) | At `single-user incident` a "next most likely" deferral is the anti-pattern, so it is IN scope as the provisioner's `escrow` arm and a precondition of the marker (D5). Not cut. |
| Sourcing `WORKSPACES_LUKS_CUTOVER_AT` into `lb-weight-gate.sh` env | gate consumption | No caller exists; belongs to the flip orchestrator. NON-GOAL. |
| Per-host generalization of the Better Stack "host timer dark" alert | detect a dead probe on web-2 | CUT at review: the verify leg already fails on a stale or missing row (it must, to decide the marker), and the existing absence alert covers the readiness row. |
| A second follow-through script re-implementing the Better Stack query | closure after soak | SIMPLIFIED at review: the follow-through script sources the same query helper the verify leg uses. |
| Separate `workspaces-luks-canonical-lines.test.sh` | byte parity with the web-1 installer | SIMPLIFIED at review: a section of `fresh-boot-parity.test.sh`, not a new file. |
| Addenda to ADR-143 and ADR-119 as separate edits | supersede R3 and section (d) | SIMPLIFIED at review: ADR-262 carries the supersession; each older ADR gets a one-line pointer. |

### Institutional learnings that bind this plan

- `2026-07-02-multi-host-ga-cutover-review-mechanisms.md`: cloud-init runs once; an additive mount with hardcoded write paths strands data. Fresh-boot logic must be idempotent in-script, and the covered-inode gate must precede any write.
- `2026-07-07-immutable-redeploy.md`: `-target` walks upstream only; a replace must target downstream attachments; a freshly replaced host may boot with the private NIC down (wait before network-dependent steps, as the existing NIC gate does).
- `2026-07-18-web-1-root-doppler-unit-needs-home-and-dedicated-token-and-vector-toml-has-no-running-host-delivery.md`: root Doppler units need `HOME=/root`; a SyslogIdentifier and the `vector.toml` allowlist move in lockstep (so the new probe reuses an existing tag).
- `2026-03-20-terraform-base64encode-cloud-init-deduplication.md` and the `$$` escaping rule: shell variables inside `templatefile()` text need `$${...}`; baking avoids this class.
- `knowledge-base/project/learnings/security-issues/2026-07-07-doppler-branch-config-does-not-isolate-secrets.md`: the boot token reads ~116 `prd` secrets, not only the key.
- `2026-09-14-the-birth-gate-refused-the-real-birth-because-its-fixtures-never-showed-it-a-real-plan.md`: gate fixtures must be shaped like a real plan.

### Existing mechanisms this plan reuses (grep-verified)

- Baked-script delivery with a byte-identity parity test: `apps/web-platform/infra/fresh-boot-parity.test.sh` (`host_script_files` in `server.tf`, Dockerfile COPY set, bootstrap install, cloud-init enable).
- Web-1's boot-unlock set: `workspaces-luks-reopen.{sh,service,timer}`, `workspaces-luks-reopen-failure.service`, and the canonical crypttab/fstab/drop-in lines in `local.workspaces_boot_unlock_*` (`workspaces-luks.tf`).
- In-user_data guest LUKS precedent for a raw volume: `cloud-init-registry.yml` (format on first provision, `registry-luks-open.sh` reopen) and git-data's blkid-aware format guard in `cloud-init-git-data.yml` (rc 0 or 2 only; mkfs keyed on "did THIS run create the container").
- Marker-writer precedent: the `git-data-cutover.yml` step "Write GIT_DATA_LUKS_CUTOVER_AT (last — proven cutover only)".
- Container egress is already default-drop (`cron-egress-nftables.sh`, DOCKER-USER jump to `SOLEUR-EGRESS`) and the allowlist files carry no link-local address, so a container cannot reach the Hetzner metadata endpoint.

## Open Code-Review Overlap

Queried open `code-review` issues against every planned file path. One body mentions `apps/web-platform/infra/server.tf`:
#2197 (billing `SubscriptionStatus` type refactor, an unrelated app-layer scope-out). **Acknowledge:** different
concern, stays open. No other overlap.

## Problem Statement

1. A born web-2 mounts a Hetzner-pre-formatted plaintext ext4 volume; nothing on a fresh boot opens a LUKS mapper
   (crypttab keyfile `none`, the baked structural gate arms only "once `/dev/mapper/workspaces` exists").
2. The only thing keeping user data off that plaintext volume is a shape-only gate that a stray marker write could
   satisfy; the `workspaces-luks.tf` comment says the marker MUST be derived from a real probe.
3. web-1 and web-2 reach "LUKS at boot" by different mechanisms (SSH-installed units vs nothing), so the cattle claim
   (ADR-143) is not demonstrated.
4. `hcloud_volume_attachment.workspaces_luks` is bound to web-1 and outside the birth fan-out (#6964): a web-1 birth
   through the dispatch can strand the sole-copy attachment.

## Proposed Solution — decisions

D1-D6 were routed to the CTO agent (`hr-technical-fork-is-not-an-operator-question`); rulings are adopted below with
this plan's deltas called out.

**D1 — Topology (issue item 4): one MECHANISM, two Terraform addresses; T2 deferred.**
web-1 keeps the additive singleton (`hcloud_volume.workspaces_luks` + its attachment, untouched). web-2 (and any
future cattle key) keeps the `for_each` `hcloud_volume.workspaces[key]`, but raw and LUKS-at-boot through the same
baked helper, so the boot behaviour is host-name-independent (the helper branches on `blkid`, never on host name).
The end state is "web-1 singleton plus web-2 keyed", named explicitly in the ADR; it is NOT claimed to be one
Terraform topology. T2 (a single keyed raw LUKS resource, with the singleton `state mv`'d into `["web-1"]`) is
deferred: it needs a second state-surgery step on the one asset with no rebuild path, `moved` is unusable on this
`-target`-only root (ADR-119 addendum, measured on Terraform 1.10.5), and its benefits (native `prevent_destroy`,
dissolving #6964) are bought more cheaply below. Revisit when the web-1 de-pet rebuild exists. See R5: the issue
asked for ONE topology.

**D2 — Raw at birth; the live web-2 is converted by a gated rebirth.**
Drop `format = "ext4"` from `hcloud_volume.workspaces` and add `lifecycle { ignore_changes = [format] }` beside the
existing `prevent_destroy`. `format` is ForceNew, and `prevent_destroy` turns any plan containing a replace into
"Instance cannot be destroyed" on every targeted plan that transitively includes the volume (the class ADR-119's
addendum measured), so the merge MUST NOT plan a replace of the live volume; `ignore_changes` makes the merge a no-op
for it. New volumes are born raw. A born-ext4 volume reaching the provisioner is FATAL (a wrong plan), never
reformatted. The live web-2 (empty ext4) is converted by a single-use, environment-gated rebirth in P7.

**D3 — Code home: the baked `soleur-host-bootstrap.sh` family, not inline cloud-init.**
New baked `workspaces-luks-provision.sh` plus the existing `workspaces-luks-reopen.{sh,service,timer}` and
`-failure.service`, baked and enabled on every fresh host. The Terraform SSH installer for web-1 is retained for the
running pet (both paths take the same repo files as source, so they are byte-identical by construction; a parity test
pins it, the `fresh-boot-parity.test.sh` pattern). The reopen unit stays luksOpen-only: the recurring timer must never
contain a format arm.

**D4 — Key access: dedicated config, `fetch --plain` only, a dedicated fresh-host token delivered in user_data.**
A NEW service token, `doppler_service_token.workspaces_luks_fresh_boot` (project `soleur`, config `prd_workspaces_luks`,
read access, NO `create_before_destroy`), becomes a `templatefile()` variable and is written to `/etc/default/luks-monitor`
(the `DOPPLER_TOKEN=` line, mode 0600 root) by the runcmd that already writes that file's DSN line. It is separate from
`doppler_service_token.workspaces_luks` (the value published as `WORKSPACES_LUKS_BOOT_TOKEN`) because that token is
rotated by a `create_before_destroy` procedure whose installer reaches web-1 only (`terraform_data.luks_monitor_token_install`):
a shared token would be destroyed under web-2, whose next reboot would then fail `luksOpen`, keep docker held by
`RequiresMountsFor`, and go dark. The fresh-host token is never co-rotated; its rotation IS a host replacement (a runbook
line plus a test that pins the absence of `create_before_destroy`). Scope, stated once and truthfully: like every
`prd_*` branch config token in this repo it resolves ~116 `prd` secrets (ADR-164 census, measured), so "dedicated config"
isolates the passphrase from the CONTAINER env file, not from a holder of this token; the full-`prd` `doppler_token` is
already in the same user_data map, so the token's marginal exposure is the LUKS passphrase and the escrow credentials.
Because the SAME `WORKSPACES_LUKS_KEY` unlocks web-2 and web-1's sole-copy volume, a leak from web-2 is a leak of web-1's
passphrase; ADR-262 records this shared-passphrase residual (it also constrains any future `luksChangeKey` on web-1).
The CTO preferred post-boot delivery over the bastion; this plan deviates for FIRST delivery: a rebirth rotates the host
SSH key and the web-2 pin (`web-2-ssh-host-key.pub`) is a committed file re-captured by a follow-up PR, so a post-boot
step cannot complete inside one dispatch. The CTO's condition for user_data delivery (a container cannot reach the
metadata endpoint) is already met: containers are default-drop firewalled and no allowlist entry covers `169.254.169.254`.
The residual is host-side non-root users in the docker group, who are root-equivalent (R4). Phase 0 adds a regression
test so the residual cannot silently widen. The only permitted read is `doppler secrets get WORKSPACES_LUKS_KEY --plain
--config prd_workspaces_luks` (never `doppler run` or `secrets download` on that config).

**D5 — Marker (issue item 3): written by CI, never by the host.**
A step in the daily `workspaces-luks-verify.yml` (a new web-2 leg, no SSH) reads web-2's most recent probe row and its
current-boot readiness row from Better Stack through `scripts/betterstack-query.sh`. GREEN is decided from a POSITIVE
count, never from "no culprit named": at least one probe row AND at least one readiness row must be returned, shape-checked,
and every required field must be present and equal to its required value (backing `crypto_LUKS`, mapper active,
`/mnt/data` source `/dev/mapper/workspaces`, key re-test ok, `escrow=ok`, row age within 26 h); an empty or unparseable
body is RED. A QUERY FAILURE (transport error, 5xx, 429, timeout) is neither: the workflow fails and the marker is
LEFT AS IT IS, so a vendor blip cannot reset the 3-day soak. The probe row and the readiness row are joined on a
`boot_id` field (the kernel's `/proc/sys/kernel/random/boot_id`, added to both emitters), so a probe row that predates
the current boot can never certify it. On a fresh green it writes
`WORKSPACES_LUKS_CUTOVER_AT` (ISO-8601 UTC) through the Doppler CLI only when the key is absent, so the 3-day soak is
measured from the first green; on any red or stale row it deletes the key so the gate fails closed. The marker lives in a DEDICATED
Doppler branch config (`prd_workspaces_luks_marker`, a `doppler_config` resource following the `prd_git_data` pattern),
not in shared `prd` as the issue wrote, and the write token is scoped to that one config. Doppler tokens are scoped per
config, so a write token on `prd` could overwrite any prd secret and the git-data stamp precedent only gets away with it
because its caller is an environment-gated dispatch; this is a daily cron with no human gate. The future flip
orchestrator reads the marker with `--config prd_workspaces_luks_marker` (recorded in DC-5). This is CI-owned runtime state derived from a probe, which Terraform cannot
express (the marker is a measurement, not a configuration); the git-data cutover stamp is the same class.

**D6 — Verification vehicle (issue item 5): the existing daily probe, baked.**
Bake `luks-monitor` (+ `workspaces-luks-emit.sh`, service, timer) onto fresh hosts so web-2 emits the same host-tagged
`luks-monitor` row under the existing SyslogIdentifier (already in the Vector allowlist) that web-1 emits. The ledger
row for the web-2 volume then claims `live_verification: available` and `live_coverage_floor` moves 2 to 3. Phase 0
characterizes `luks-monitor.sh` on an empty standby (no state file, empty workspaces dir); if its inventory or
readiness arms would false-page there, a minimal `standby` profile switch is added rather than forking the probe (DP-11:
"DRY, not a bespoke reimplementation").

## Architecture Decision (ADR/C4)

An architectural decision is made (topology ruling, a new credential path into user_data, reversal of ADR-119 section
(d)), so the records are in-scope tasks of THIS plan, not follow-up issues.

### ADR

- **New ADR-262** (provisional ordinal; origin/main max is 261; `soleur:ship`'s ADR-ordinal gate re-verifies, and a
  renumber must sweep this plan, tasks.md and any AC naming the ordinal): "Guest-side fresh-boot LUKS for web hosts:
  one mechanism, two Terraform addresses". Status `adopting` (flips to `accepted` after the live conversion and first
  soak). Records D1-D6, the raw-at-birth exception, and the rejected alternatives (T2 now, empty-ext4 reformat,
  post-boot token delivery, a token shared with web-1's rotation procedure).
- ADR-262 carries the supersession: it marks ADR-143 R3's "DEFER" resolved, replaces "AC5 reframed: LUKS-intent declared in
  HCL" with "LUKS-backed at boot", and reverses ADR-119 section (d) ("a fresh host must not get these units"). ADR-143 and
  ADR-119 each get a ONE-LINE pointer to it, not a separate addendum. ADR-262 also records: the shared-passphrase residual
  (one `WORKSPACES_LUKS_KEY` unlocks web-1 and web-2), that web-1 keeps its SSH installer until the de-pet (two delivery
  paths, one byte-parity test), and the single-use rebirth workflow.
- Author these with `soleur:architecture`.

### C4 views

Read in full: `model.c4`, `views.c4`, `spec.c4`. Checked against the change: (a) external human actors: none new (no new
sender, recipient or reviewer); (b) external systems: Doppler, Cloudflare R2 (header escrow edge), Better Stack and
Hetzner are all already modeled with the relevant edges (`doppler -> hetzner` LUKS key edge, `hetzner -> cloudflare`
header edge, `hetzner -> betterstack`); (c) data stores: `workspacesVolume` already models a guest-LUKS volume, no new
element; (d) actor-to-surface access relationships: unchanged. No new element or edge is needed, so `views.c4` needs no
`include` line. What IS falsified and must be edited in `model.c4`: the `workspacesVolume` description sentence saying
web-2's volume is born RAW/empty PLAINTEXT "because the guest-side LUKS path for a FRESH host is the deferred #6931 work
(ADR-141 D3)"; the `hetzner` description sentence about web-2 and the web-1-bound attachment; and the
`doppler -> hetzner` edge ("a STORE-AVAILABILITY dependency of every web-1 boot"), which must add the fresh-host
user_data-delivered scoped token. Validate with `apps/web-platform/test/c4-code-syntax.test.ts`, `c4-render.test.ts`
and `plugins/soleur/test/c4-count-parity.test.sh` (derived counts embedded in edge prose).

### Sequencing

The ADR is authored now with status `adopting`; the claim "web-2 is LUKS-backed at boot" only becomes true after the P7
rebirth, so every register and ledger sentence is written conditioned on that event (Domain Review, CLO).

## Infrastructure (IaC)

Phase 2.8 routing review: every provisioning step is Terraform, baked image content or cloud-init; nothing here asks a
person to run a host command, set a secret by hand or click a dashboard. The only runtime-derived write (the soak
marker) is a measurement owned by a CI step, the same class as the existing git-data stamp.

### Terraform changes

- `apps/web-platform/infra/server.tf`: `hcloud_volume.workspaces` drops `format` and gains `ignore_changes = [format]`
  (keeps `prevent_destroy`); `host_script_files` gains the new baked files; the `user_data` templatefile map gains
  `workspaces_luks_fresh_boot_token = doppler_service_token.workspaces_luks_fresh_boot.key` (sensitive; `ignore_changes=[user_data]`
  means web-1 sees no diff); the singleton-rationale comment block near `prevent_destroy` is rewritten.
- `apps/web-platform/infra/workspaces-luks.tf`: rewrite the "SINGLETON, not for_each" reason 3 and the "THE DEFER IS
  FAIL-CLOSED" comment (item 6); the `blkid` doctrine comment stays and gains a pointer to the executable guard; add the
  fresh-host read token (D4), the marker config `prd_workspaces_luks_marker` (a `doppler_config`), its write-scoped
  service token (D5) and the GitHub repo secret carrying that write token.
- Providers and pins: unchanged (Doppler, hcloud, github are already pinned in this root).
- Sensitive variables: no new `TF_VAR_*`; the token comes from an in-graph resource, never an operator-minted default
  (`hr-tf-variable-no-operator-mint-default`).
- Allow-list: the new fresh-host token, marker config, marker write token and GitHub secret join the default push-apply
  `-target` list and the `terraform-target-parity.test.ts` expectations in the SAME PR, and MUST exist in state before any
  web-2 birth: a resource created inside a birth plan is an out-of-scope create to `web-host-birth-gate.sh` and aborts the
  birth. A new edge `hcloud_server.web[*]` -> the fresh-host token puts it into every targeted plan, so Phase 0 measures
  that, once created, it plans as a no-op, and the P7 dispatch is preceded by a plan showing zero pending creates outside
  the birth fan-out.

### Apply path

(b) bake + immutable redeploy. The merge changes no running host (user_data ignored, volume `ignore_changes`). The
image carrying the new baked files is built by the release pipeline; web-2 then adopts it through a single-use gated
rebirth (P7) that consumes the new image digest. Expected downtime: web-2 only (weight 0, serves nothing, holds no user
data); web-1 untouched. No `-replace` on any sole-copy volume, no SSH configuration change.

### Does merging this alone mutate production? (answered from the trigger and the allow-list)

The push-apply workflow fires on any `apps/web-platform/infra/**` change, so this PR's merge WILL run it. What it does,
from its `-target` allow-list: it CREATES the new additive resources (the fresh-host read token, the marker config, the marker write
token and its GitHub secret, all added to the allow-list in this PR) and nothing else. It does not create, replace or destroy any
host or volume. The one trap is transitive: the allow-list reaches `hcloud_volume.workspaces[...]` through
`hcloud_firewall_attachment.web` -> `hcloud_server.web` -> `user_data` -> `workspaces_volume_id` (ADR-119's 2026-09-28
addendum measured exactly this path). Dropping `format` from the live volume's config would therefore plan a ForceNew
replace that `prevent_destroy` turns into a failed apply on every merge; `ignore_changes = [format]` is what makes the
merge a no-op for the volume. The PR body's first line states this answer, and an acceptance criterion requires a plan
run with the push-apply's own `-target` set against live state showing no change to any `hcloud_volume` or
`hcloud_server` address.

### Distinctness / drift safeguards

- `lifecycle.ignore_changes = [format]` is creation-only and documented as such; a test pins its presence AND the
  absence of `format`, so neither half can be dropped alone.
- `prevent_destroy` stays on `hcloud_volume.workspaces`; the rebirth (P7) is the one deliberate, gated exception.
- The new Doppler tokens are `project = "soleur"` and scoped to one config each, mirroring the
  `doppler_service_token.workspaces_luks` shape; the fresh-host token carries no `create_before_destroy`.
- The `server.tf` comment that says the volume is "not in the push-apply `-target` allow-list" is rewritten to the exact
  truth (it is reached transitively; see the merge-effect statement).
- State storage: the token and passphrase already live in `terraform.tfstate`; this adds one more sensitive value of the
  same class.

### Vendor-tier reality check

No tier gate applies (Doppler service tokens and raw hcloud volumes are already in use here). The plan relies on the
Hetzner API formatting a volume only when `format` is set; Phase 0.2 re-confirms against the provider docs (context7)
and against `workspaces_luks`, which is born raw with empty `blkid` per ADR-119.

## Downtime & Cutover

**Offline-inducing operation.** Phase 7 destroys and re-creates web-2 (server, attachment, volume). Nothing else in the plan
reboots or replaces a running host: the merge changes no host (user_data and image are ignored; the volume's `format` is
ignored), and web-1 is untouched throughout.

**Surface affected.** web-2 only. It is an out-of-band standby at serving weight 0, outside the ingress rotation, holds no user
data, and is gate-blocked from receiving any (lb-weight-gate). No user-facing availability is lost; the only loss is the
standby's own health signal for the duration of the rebirth.

**Zero-downtime path evaluated.** Blue-green (provision the new web-2 beside the old one, then retire the old) is the default
shape and is what a rebirth already is for a standby: the new host is born by the existing `web-host-create` birth path with the
new image, and the old one is retired only after the emptiness evidence is re-asserted. A same-name blue-green is not possible
because `var.web_hosts` keys the host and the volume name is per key; the window between destroy and create is therefore the
residual downtime. Rolling and drain-then-act do not apply (nothing is served).

**Residual downtime accepted, with bounds.** A bounded maintenance window of the birth job's own budget (30 minutes, the
`web_host_create` timeout), executed behind the `web-platform-infra-apply` environment's reviewer approval (the sign-off), with
a stop condition: if the new host does not report `SOLEUR_FRESH_BOOT_READY ready=1` inside the 900 s boot window plus the 300 s
device wait, the job fails with a named reason and the standby stays dark and paged rather than being retried blindly.

**Per-stage verification and rollback.** Stage 3 re-asserts identity before each destructive call; stage 4 verifies the
readiness row; stage 5 verifies the marker lifecycle; stage 6 verifies the reboot. Rollback before stage 3 is "do not
dispatch". After the volume delete there is nothing of value to restore (empty volume); rollback is a fresh `web-host-create`.

## Technical Approach

### The provisioner (`apps/web-platform/infra/workspaces-luks-provision.sh`, baked)

Single-shot and fail-closed: `set -u`, refuses under xtrace (the `luks-monitor.sh` #7797 guard), `umask 077`. Inputs: a
non-secret env file `/etc/default/workspaces-luks-boot` written by cloud-init (`WORKSPACES_LUKS_DEV=/dev/disk/by-id/
scsi-0HC_Volume_<id>`, `WORKSPACES_DOPPLER_CONFIG=prd_workspaces_luks`) and the token line in `/etc/default/luks-monitor`.
Arms, in order, each with a distinct exit code and one structured result row (`SOLEUR_WORKSPACES_LUKS_PROVISION arm=…
rc=…`) sent through `soleur-boot-emit` (Sentry) and logged:

1. `config`: validate both env files (regular, root-owned, correct mode; device matches
   `^/dev/disk/by-id/scsi-0HC_Volume_[0-9]+$`).
2. `device`: wait up to 300 s (the volume attachment is a separate resource and the by-id link can lag server boot) for a
   block device; refuse if it is mounted or has holders or child partitions.
3. `discriminate`: `blkid -o value -s TYPE "$DEV"`. Accept ONLY rc 0 or rc 2 (any other rc is FATAL "could not read the
   device", the git-data precedent). Then, additively and never relaxing: `blkid -o value -s PTTYPE` and `wipefs
   --no-act` must show nothing before an empty TYPE is treated as raw (a GPT-partitioned disk reads an empty TYPE).
   Empty -> `format` arm; `crypto_LUKS` -> `open` arm; anything else (including `ext4`) -> FATAL refuse, no write.
4. `format` arm (this run creates the container): fetch the key (`fetch --plain`, passed with `printf '%s'` on a pipe,
   never argv) under a bounded retry ladder (about 5 minutes) before giving up, so a Doppler blip at first boot does not
   end in the fail-closed poweroff. Then, in this order: re-run `_may_format()` (the state may have changed since step 3),
   write the durable intent file `/var/lib/soleur/workspaces-luks-formatting` (root disk, fsynced), `cryptsetup luksFormat
   --batch-mode --type luks2 --key-file -`, `luksOpen`, re-run `_may_format_fs()` on the mapper, `mkfs.ext4` ONLY if the mapper
   is blank AND the intent file exists, then remove the intent file. The intent file is what makes a crash between
   `luksFormat` and `mkfs` recoverable.
5. `open` arm: `luksOpen` if the mapper is closed; no-op if already open with a matching backing-device identity. `mkfs` is
   permitted ONLY when the mapper is blank AND the intent file from step 4 exists (the interrupted first birth); a LUKS
   container whose mapper carries no filesystem and NO intent file is FATAL ("damaged store", the git-data rule).
6. `wire`: write the canonical crypttab line (`workspaces /dev/disk/by-id/... none luks,noauto`), the single mapper
   fstab line, the `docker.service.d` drop-in (`RequiresMountsFor=/mnt/data`, `After=workspaces-luks-reopen.service`),
   `chattr +i` the unmounted root-disk mountpoint BEFORE mounting, mount, enable the reopen service and timer. The
   canonical lines are byte-identical to `local.workspaces_boot_unlock_*` (parity test).
7. `escrow`: after BOTH the `format` and `open` arms (idempotent check-then-upload, so a crash between format and upload
   self-heals on the next boot), `cryptsetup luksHeaderBackup` to a tmpfs file, upload it to the header-escrow bucket
   (`WORKSPACES_HEADER_BUCKET`, endpoint and R2 credentials read with the same pinned `doppler secrets get ... --plain
   --config prd_workspaces_luks` form the cutover uses), verify by a HEAD read-back of the object size, then shred the
   tmpfs copy. Transport is `curl --aws-sigv4 "aws:amz:auto:s3" --user "$id:$secret"` so no aws-cli install is needed on a
   fresh host <!-- verified: 2026-10-01 source: `curl --help all` lists `--aws-sigv4 <provider1[:prvdr2[:reg[:srv]]]>`; Phase 0.7 proves the exact form against R2 --> .
   The object key is per host and per header UUID. A failed upload is NOT fatal to boot (an empty standby must not be held
   dark by R2): it records `escrow=missing`, pages, and is retried on every boot (the `open` arm re-runs this step). The
   FENCE is the marker (D5): a header with no off-host copy never earns the marker, so it can never be flipped to.
8. `result`: write `/run/soleur/workspaces-luks-arm` (`formatted`, `opened` or `noop`) and `escrow=ok`, read by
   `soleur-fresh-boot-ready`.

The provisioner contains no `cryptsetup isLuks`. (The existing reopen script uses it read-only as a "refuse if not
LUKS" header check on a populated device, the opposite polarity, and stays.)

### Wiring

- `soleur-host-bootstrap.sh`: install the baked files; replace the structural gate's `by-label/workspaces_luks ...
  luks,nofail` crypttab write (it would collide with the canonical line, and web-1's installer refuses a foreign
  `workspaces` line with exit 32) by the helper's canonical write; tighten `soleur-fresh-boot-ready` so `luks=1`
  requires the mapper to BE the `/mnt/data` source, add `luks_arm=`, and make `luks` a readiness reason.
- `cloud-init.yml`: replace the fstab-append and mount lines in the `/mnt/data` block with the env-file write and one
  helper call, followed by a hard gate placed BEFORE the `mkdir -p /mnt/data/workspaces` line (and therefore before the plugin-seed block
  further down that also writes under `/mnt/data`): `mountpoint -q /mnt/data` on the mapper, else `soleur-boot-emit
  workspaces_luks_not_mounted fatal` and the existing fail-closed `poweroff -f` path; extend the
  `/etc/default/luks-monitor` write with the `DOPPLER_TOKEN=` line; re-baseline the user_data budget comment and number
  (the net change is expected to be neutral or negative).
- The Dockerfile COPY set and `server.tf` `host_script_files` list the new files (the parity test asserts both).

## Implementation Phases

Write each phase's RED tests first (`cq-write-failing-tests-before`); every phase ends green on its own tests.

### Phase 0 — Preconditions and characterization (no production code)

- 0.1 Re-read PR B (#9348); decide merge order (R1). Rebase on it once merged; until then do not touch lines PR B owns
  (`hcloud_volume.workspaces` `for_each`, the web-1 `workspaces_volume_id` reference, the ledger row's exception block).
- 0.2 FIRST, as a hard fork in scope: confirm with the provider docs (context7) that omitting `format` yields a raw volume and `format` is ForceNew, AND
  read the live web-2 volume's `format` attribute from the Hetzner API (read-only GET on the volume resource) so the
  "born ext4" claim in this plan is MEASURED on the affected resource, not inferred from the HCL. If the API says the
  volume is unformatted, D2/P7 shrink (the existing volume can be provisioned in place) and this plan is re-scoped.
- 0.3 Characterize `luks-monitor.sh` against an empty-standby fixture (mapper present, no state file, empty workspaces
  dir) using the `workspaces-luks-harness.sh` seams; record which arms false-page (decides D6's profile switch).
- 0.4 Verify the `destroy-guard-filter-web-platform.jq` allow-set facts the ADRs cite, with a plan fixture, and choose the
  P7 destroy mechanism from the measurement. Fix the EMPTINESS EVIDENCE now, because the Hetzner volume object exposes no
  usage field: (a) the volume's attached `server` is web-2 and its labels match; (b) Better Stack `host_metrics`
  filesystem-used for `/mnt/data` on `host:soleur-web-2` stayed under a stated byte ceiling for the trailing 7 days (Phase
  0.4 first confirms Vector ships that field); (c) web-2 was never pooled (no marker, serving weight 0, no connector); if (b)
  is not measurable the rebirth does not proceed and a host-emitted inventory row is added first.
- 0.5 Verify `luks-monitor-token-refresh.sh` line-shape expectations so the cloud-init-written `DOPPLER_TOKEN=` line is
  parsed identically by the web-1 refresh helper and the reopen unit's `EnvironmentFile`.
- 0.6 Add a regression test over `cron-egress-allowlist*.txt`: no entry matches `169.254.0.0/16` (bounds the D4 residual).
- 0.7 Prove the escrow transport form against a scratch object in the real escrow bucket's credentials scope (PUT, HEAD
  read-back, delete) from a runner, and confirm Ubuntu 24.04's packaged curl (the fresh-host OS) accepts `--aws-sigv4`
  with the R2 endpoint; pin the verified output in the plan before Phase 1.
- 0.9 Name the vehicle for the pre-merge "no change to any volume or server" plan run (the push-apply workflow's own plan
  step, or `scheduled-terraform-drift.yml` dispatched at the PR branch, whichever runs the SAME `-target` set) and pin the
  output artifact the PR body quotes; both need live-state credentials, so it is a CI run, not a laptop command.
- 0.10 Confirm how `image_tag` is chosen for a rebirth: `web-host-create` defaults to the running version read from
  web-1's `/health`, which will NOT carry the new baked provisioner. P7 passes `image_tag` explicitly, and a pre-dispatch
  check compares the image's host-script content-hash label with `host_scripts_content_hash` computed from the same commit.
- 0.8 Derive the allow-list work-list with `git grep -ln -e '-target=' -e 'workspaces_luks_boot_token' -- tests scripts
  plugins/soleur/test .github` and add every hit that asserts on the push-apply `-target` set to Files to Edit (an
  orphan scope-guard suite is the one that gets missed).

### Phase 1 — The provisioner and its tests

Create `workspaces-luks-provision.sh` and `workspaces-luks-provision.test.sh` (stub `cryptsetup`, `blkid`, `wipefs`,
`doppler`, `findmnt` on a mock PATH; drain stdin in the stubs, learning from the #9245 EPIPE fix; add a loopback arm
when root). Cases: raw -> formatted and mkfs (intent file written before luksFormat, removed after mkfs); a simulated crash after
`luksFormat` -> the next run finishes `mkfs`; a blank LUKS mapper with NO intent file -> FATAL; device state changing between
discriminate and `luksFormat` -> FATAL; Doppler failing for the first N attempts -> succeeds inside the ladder; escrow PUT
or HEAD failing -> boot continues with `escrow=missing` and the next boot retries; `crypto_LUKS` -> open, no mkfs; `ext4` -> FATAL and ZERO write calls; blkid
rc 4 or 8 -> FATAL; empty TYPE with PTTYPE=gpt -> FATAL; empty TYPE with a `wipefs` signature -> FATAL; LUKS without a
filesystem -> FATAL; empty key -> FATAL; Doppler failure -> FATAL before touching the device; second run is a no-op;
xtrace refused; no `isLuks` anywhere.

### Phase 2 — Wiring (bake, bootstrap, cloud-init)

Edits listed under Technical Approach / Wiring. Extend `fresh-boot-parity.test.sh` (new files baked, installed,
enabled), add a canonical-lines parity test against `local.workspaces_boot_unlock_*`, re-baseline the user_data size
test, extend `fresh-boot-ready.test.sh` for `luks_arm=` and the gated `luks` reason.

### Phase 3 — Terraform topology and the #6964 measured invariant

The `server.tf` and `workspaces-luks.tf` edits (Infrastructure section). In `web-host-birth-gate.sh`: add the
REQUIREMENT arm (the host being created gets a keyed volume with no `format`) and the `web-1` refusal arm
(`hcloud_volume_attachment.workspaces_luks` is web-1-bound and outside the fan-out; refusing is the cheapest enforceable
invariant under D1). `test-web-host-birth-gate.sh` gets the mutation rows of Guard 2. Update the `image_tag` input help
text in `apply-web-platform-infra.yml`, which currently says it is required "when birthing web-1".

### Phase 4 — Verification vehicle (item 5)

Bake the `luks-monitor` family on fresh hosts per D6 (the profile switch only if Phase 0.3 requires it); add `boot_id` to
the probe and readiness rows; flip the ledger row and `live_coverage_floor` to 3 in the commit
that adds the vehicle (the linter checks the floor against the count of `available` rows).

### Phase 5 — The marker writer (item 3)

Extend `workspaces-luks-verify.yml` with the web-2 leg (no SSH): Better Stack read, write-if-absent on green, delete on
red or stale. Add the write-scoped Doppler token resource and GitHub secret (D5). Tests in the style of
`workspaces-luks-verify-workflow.test.sh`: green writes once and only when absent; red, stale or missing row deletes;
the step refuses xtrace; the token never appears in argv.

### Phase 6 — Records and wording (item 6)

ADR-262 with one-line pointers in ADR-143 and ADR-119 (ADR section); `model.c4` prose; `workspaces-luks.tf` and `server.tf` comments; the
stale-citation sweep (`grep -rn "ADR-141 D3\|ADR-142 D3"` over infra, tests and `model.c4`); the
`workspaces-luks-reopen.service` header; `web-host-replace.md` and `web-host-replace-gate.sh` unblock-condition text
(#6931 done; remaining: key-conditional arms, a rehearsal, #6964); one-line pointers in `nfr-register.md` (Compute row) and
the 2026-07-24 plan's AC5 line; a short "web-2 boot failed, how to read it" paragraph (Sentry stages, the Better Stack
query) in the web-host runbook; and the registers the CLO listed:
`knowledge-base/legal/article-30-register.md` (cross-host replication row and the web-2 recipient/location rows) and
`knowledge-base/legal/compliance-posture.md` (Hetzner row and TS-1/T-1 rows), each sentence conditioned on the live
conversion, never past tense before it. The published privacy and GDPR documents need no edit (their "Encrypted
workspace storage" wording is scoped to the volume workspace git data is served from, per the 2026-07 counsel review).

### Phase 7 — Live conversion of web-2 (post-merge, gated dispatches, single-use; run as an operation, not as PR content)

Every step is a workflow dispatch behind an approval gate: (1) the merge's push apply creates the new Terraform
resources and the follow-up plan shows nothing pending; (2) the release image built from the MERGE commit is published
(the host-script content hash in user_data must equal the image's label; Phase 0.10 adds the pre-dispatch comparison and
`image_tag` is passed explicitly); (3) a single-use "web-2 volume rebirth" job: re-assert the emptiness evidence of Phase 0.4
and web-2's identity, DELETE the volume through the Hetzner API first (a crash then leaves dangling state, which a re-run
heals, rather than an orphan volume whose name collides with the next create), then remove the one state address, then
destroy the server and attachment and run `web-host-create` for web-2 with the new image tag; every step idempotent, the
volume id re-asserted at each. Because `prevent_destroy` refuses destroy and `-replace`, this follows the
`workspaces-plaintext-forget.yml` precedent, and the workflow file is deleted after use (its existence is recorded in
ADR-262). (4) Boot: the provisioner takes the `format` arm and `SOLEUR_FRESH_BOOT_READY` reports `luks=1 luks_arm=formatted`.
(5) The daily verify leg goes green and writes the marker. (6) Reboot proof: an hcloud reboot action issued by the workflow
(no SSH) must produce a row with `luks_arm=opened` or `noop` and a new `boot_id`. The replace-with-populated-volume proof
(`web-host-replace` on a populated volume) stays blocked on its own unblock list (key-conditional arms, rehearsal, #6964)
and is tracked, not claimed. Because web-2's host key changes on rebirth, the committed pin is re-captured with
`scripts/capture-web-2-host-key.sh` in the follow-up PR the existing cattle re-key procedure defines; the list of web-2 SSH
consumers that fail in the window between rebirth and that PR (bastion deploy delivery, the `*_install` provisioners) is
enumerated in Phase 0, and none of them is in the LUKS path.

## Alternative Approaches Considered

| Alternative | Why not |
|---|---|
| T2: one keyed raw LUKS resource now (`state mv` the singleton to `["web-1"]`) | A second state-surgery step on the sole-copy volume; `moved` unusable here; the gains are deferred, not lost. Deferred behind the de-pet. |
| Post-boot token delivery over the bastion (the CTO's first preference) | A rebirth changes the host SSH key and the pin is a committed file, so the dispatch could not complete unattended. Revisit if user_data exposure is judged unacceptable. |
| Convert the existing web-2 volume in place (reformat when ext4 and empty) | "Empty" is unprovable on the failure path; the arm would also fire on a mis-resolved device. Rejected. |
| Inline cloud-init LUKS block (the registry shape) | The web user_data budget has ~300 B headroom and the template is shared with the populated pet web-1. |
| Reuse `isLuks` as the discriminator | The documented data-destroyer on a populated device (`workspaces-luks.tf` doctrine). Forbidden by the issue and by Guard 1. |
| Drop `prevent_destroy` on the web-2 volume to allow `-replace` | Weakens the guard on the sole-copy class permanently for a one-time need. |

## User-Brand Impact

- **If this lands broken, the user experiences:** a rebuilt or newly born web host that boots with an empty or
  unreadable `/workspaces` (their workspaces appear gone), a host that never starts the app (an outage), or, worst
  case, a `luksFormat` over a populated volume that destroys a user's only copy of their source code.
- **If this leaks, the user's data is exposed via:** the LUKS passphrase or the boot token read from the Hetzner
  metadata endpoint, `/proc/<pid>/environ`, the Terraform state or a CI log (xtrace); or a volume that is plaintext
  while a published claim says it is encrypted.
- **Brand-survival threshold:** `single-user incident`

One workspace lost to a mis-aimed format, or one plaintext copy that a privacy claim says is encrypted, is a
brand-ending event for this product. `requires_cpo_signoff: true`; at review time
`soleur:engineering:review:user-impact-reviewer` enumerates these against the diff. Artifact/vector pairs:
(1) populated volume + a format arm reachable on a non-blank device; (2) token or key in user_data + the metadata
endpoint; (3) a marker written without a real probe + a flip routing users to a plaintext web-2; (4) a stranded
sole-copy attachment after a web-1 birth. Each has a guard below.

## Observability

```yaml
liveness_signal:
  what: daily luks-monitor row under SyslogIdentifier luks-monitor from host soleur-web-2 (backing crypto_LUKS, mapper active, mount source /dev/mapper/workspaces, key re-test ok) plus the one-shot SOLEUR_FRESH_BOOT_READY row carrying luks=1 and luks_arm
  cadence: daily for the probe; once per boot for the readiness row
  alert_target: Sentry (feature=workspaces-luks, op=workspaces-luks-drift) for drift; the daily verify leg fails on a stale or missing probe row; absence of the readiness row past its 900 s window pages through the existing web-probe absence alert
  configured_in: apps/web-platform/infra/luks-monitor.sh, apps/web-platform/infra/soleur-host-bootstrap.sh (soleur-fresh-boot-ready), .github/workflows/workspaces-luks-verify.yml
error_reporting:
  destination: Sentry via soleur-boot-emit (baked DSN) with stage workspaces_luks_provision_*; drift events via workspaces-luks-emit.sh
  fail_loud: a fatal soleur-boot-emit event naming the arm (config, device, discriminate, format, open, escrow, wire) plus a SOLEUR_WORKSPACES_LUKS_PROVISION row; the host does not start the app container
failure_modes:
  - mode: provisioner refuses a populated or typed device (ext4, GPT, foreign signature)
    detection: stage workspaces_luks_provision_discriminate fatal in Sentry, readiness row ready=0 reason=luks
    alert_route: Sentry issue alert on the stage tag
  - mode: a crash between luksFormat and mkfs, or Doppler unreachable at first boot past the retry ladder
    detection: the intent file makes the next boot finish mkfs; an unreachable Doppler ends in a fatal stage event and workspaces-luks-reopen-failure.service at ladder exhaustion (op=workspaces-luks-drift)
    alert_route: Sentry page via the existing drift alert
  - mode: daily probe stops running on web-2
    detection: the verify leg treats a missing or stale probe row as red (workflow failure, and the marker is deleted)
    alert_route: workflow failure notification
  - mode: soak marker present while the volume is not LUKS
    detection: the verify leg deletes the marker on any red or stale row, and a test pins delete-on-red
    alert_route: workflow failure notification, and lb-weight-gate failing closed
logs:
  where: journald (luks-monitor and workspaces-luks-reopen units) shipped by Vector to Better Stack source 2457081
  retention: Better Stack source retention; Sentry event retention
discoverability_test:
  command: bash scripts/betterstack-query.sh "host:soleur-web-2 SOLEUR_FRESH_BOOT_READY"
  expected_output: luks=1
  credentials_required: Better Stack ClickHouse read connection (Doppler soleur/prd_terraform BETTERSTACK_QUERY_*) - a remote host's boot row has no unauthenticated substitute
```

## Encryption Posture

```yaml
at_rest:
  - store: hcloud_volume.workspaces (web-2 key)
    mechanism: luks
    evidence: apps/web-platform/infra/workspaces-luks-provision.sh content anchors `cryptsetup luksFormat --batch-mode --type luks2 --key-file -` and `cryptsetup luksOpen`, fstab line `/dev/mapper/workspaces /mnt/data ext4 defaults,nofail 0 2`; key random_password.workspaces_luks + doppler_secret.workspaces_luks_key
    defends_against: a seized, RMA'd or snapshot-imaged Hetzner block volume of a web-2 workspace store
    does_not_defend: any read on a live host where the mapper is unlocked; a leaked boot token or Doppler credential (the token reads ~116 prd secrets and sits in user_data); a host-side non-root docker-group user reading the metadata endpoint
    disclosed_as: not-publicly-claimed
    live_verification: available
  - store: hcloud_volume.workspaces_luks (web-1)
    mechanism: luks
    evidence: unchanged (existing ledger row)
    defends_against: unchanged
    does_not_defend: unchanged
    disclosed_as: docs/legal/privacy-policy.md:Encrypted workspace storage
    live_verification: available
in_transit:
  - connection: web-2 host -> Doppler API (key fetch at provision and at each boot reopen)
    enforced_at: apps/web-platform/infra/workspaces-luks-provision.sh (Doppler CLI, HTTPS)
    tls: TLS 1.2+ (Doppler CLI)
    cert_verification: on
    does_not_defend: a compromised host that already holds the token
    disclosed_as: not-publicly-claimed
  - connection: GitHub runner -> Better Stack ClickHouse HTTP (the marker writer's probe read)
    enforced_at: scripts/betterstack-query.sh
    tls: HTTPS
    cert_verification: on
    does_not_defend: a leaked read credential
    disclosed_as: not-publicly-claimed
```

No `exception` block is needed once the row is `luks`. Until the P7 rebirth lands, the CURRENT row stays
`plaintext-exception` (expires 2026-10-22, tracking #6897); if the rebirth cannot land before that date, extend it
within the 90-day cap citing #6931 rather than letting Layer A fail on an expired exception. The `device_binding`
`mapper` for this row changes from `workspaces-plain` to `workspaces`, and `lint-encryption-posture.py` must be green
on the final tree.

## Guard Contract

Matrices were trimmed at review to the rows that exercise a real destructive or fail-open path, plus ONE shared harness
case-count assertion per suite (the "suite asserts its own case set" row) instead of a self-test per guard.

### Guard 1 — Fresh-boot format discriminator

**Property.** `workspaces-luks-provision.sh` runs `cryptsetup luksFormat` or `mkfs` only on a device whose
`blkid -o value -s TYPE` is empty (rc 2) AND which shows no partition-table or other signature (checked again immediately
before each destructive call), and never on any other state; `mkfs` on a LUKS mapper happens only for a blank mapper whose
format was started by this provisioner (the intent file).

**Assembly.** Every path that can reach a destructive call: the `format` arm's `luksFormat`, the `mkfs.ext4` inside the
mapper (reached from BOTH the `format` arm and the `open` arm's interrupted-birth branch), and any fallback or retry branch
added later. The chokepoints are two functions, `_may_format()` (device level) and `_may_format_fs()` (mapper level);
every destructive call is preceded by a call to its function in the same code path, not merely somewhere earlier in the
script. The static guard greps the whole provisioner for `isLuks` and for any `luksFormat` or `mkfs` token outside those regions,
so a second injection site is also caught. The `isLuks` grep is scoped to the provisioner, `cloud-init.yml` and
`soleur-host-bootstrap.sh` (the repo's other `isLuks` users are single-purpose-host scripts and tests, deliberately out of
scope; the reopen script's read-only use is the one documented allowlisted occurrence).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Replace the `blkid` probe with `cryptsetup isLuks` (inverted guard) | RED |
| 2 | Treat `TYPE=ext4` as formattable (an `ext4` arm added to the empty case) | RED |
| 3 | Fold blkid rc 4 or 8 into "empty" (drop the rc 0/2 filter) | RED |
| 4 | Drop the PTTYPE and `wipefs` corroboration (a GPT disk with empty TYPE formats) | RED |
| 5 | Call `luksFormat` directly from the open arm (a second injection site after a compliant first) | RED |
| 6 | REORDER: call `_may_format()` once at discriminate time and not again before `luksFormat`, with the stub changing the device state in between | RED |
| 7 | Remove the intent-file check so the open arm runs `mkfs` on any blank mapper | RED |
| 8 | Remove the intent file write, so a crash between `luksFormat` and `mkfs` becomes FATAL on every later boot | RED (the crash-window case) |
| 9 | HARNESS: the stub reports "0 calls checked", or a case is deleted from the suite | RED (the suite asserts a minimum call count and its case set) |
| 10 | MUST-PASS non-canonical input: a raw device with a different by-id serial and a longer path | GREEN |

**Anchor.** Nothing outside the commit has to move: the property is behavioural (a stub records every call), not a
stored value compared with the thing it protects.

### Guard 2 — Birth gate: raw-volume requirement and the web-1 attachment invariant

**Property.** A web-host birth plan passes only if the host being created gets a keyed volume with no `format`, and a
birth of `web-1` (whose LUKS attachment is outside the fan-out) is refused by name.

**Assembly.** `tests/scripts/lib/web-host-birth-gate.sh` (the one gate every `web-host-create` plan flows through), its
fixtures in `tests/scripts/test-web-host-birth-gate.sh`, and the dispatch's `-target` list in
`.github/workflows/apply-web-platform-infra.yml` (job `web_host_create`). The fixture plan JSON is shaped from a real
`terraform show -json` plan, not hand-written (2026-09-14 learning: this gate once refused a real birth because its
fixtures never showed it one). `ignore_changes = [format]` on the live volume and this gate's "no format" arm are two
different facts (existing volume vs volume being born), pinned by one test each.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Re-add `format = "ext4"` to the web-2 volume in the plan fixture | RED |
| 2 | Remove the volume attachment from the birth plan | RED |
| 3 | Request `web-1` while every other arm is satisfied | RED (named refusal) |
| 4 | Add a second created host after a compliant first | RED |
| 5 | A fixture with zero `resource_changes` | RED, not a vacuous pass |
| 6 | HARNESS: delete the web-1 case from the suite | RED (the suite asserts its case set) |
| 7 | MUST-PASS: a web-2 birth whose volume carries extra non-format attributes | GREEN |

**Anchor.** The refusal list is edited in the same file as the gate; a weakening needs a diff to a path covered by an
existing review rule (verify the CODEOWNERS or required-check coverage at work time), and the suite asserts its case set
so a deleted case reds.

### Guard 3 — Soak marker writer fails closed

**Property.** `WORKSPACES_LUKS_CUTOVER_AT` exists in its Doppler config only while the latest web-2 probe row is fresh,
belongs to the current boot, and reports a LUKS-backed mount with an off-host header copy; negative evidence removes it,
a failed query leaves it untouched.

**Assembly.** The verify-workflow step(s) that write or delete the key; every other Doppler CLI write or delete against
that name anywhere in `.github/workflows/` and `scripts/` (a grep-derived census, so a second writer is a finding); and
`lb-weight-gate.sh`'s read of the same name.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Write the marker when the row is stale (age over 26 h) | RED |
| 2 | Write on `luks=0` or a non-`crypto_LUKS` backing type | RED |
| 3 | Skip the delete on negative evidence | RED |
| 4 | Write every run (overwrites the first-green start of the soak) | RED |
| 5 | A second workflow writes the key | RED (census assertion) |
| 6 | The query returns an empty or unparseable body (zero counted rows) | RED, key deleted, never `ready` |
| 7 | The query FAILS (5xx, 429, timeout): the key must be untouched and the workflow must fail | RED if the key is deleted or the run passes |
| 8 | Drop the `escrow=ok` requirement | RED |
| 9 | Probe row green but its `boot_id` differs from the readiness row's | RED |
| 10 | HARNESS: the `doppler` stub records nothing; the suite fails on zero recorded calls | RED |
| 11 | MUST-PASS: a row with an extra unknown field and a 25 h age | GREEN |

**Anchor.** The marker is a stored value the gate trusts, so integrity needs something outside one diff: the writer
credential is write-scoped to the dedicated marker config (it cannot touch any other secret) and lives only in this
workflow's environment, and the value is re-derived from a fresh probe on every run (a hand-written value is removed at the
next run).

## Acceptance Criteria

### Pre-merge (PR)

Functional:

- [ ] `workspaces-luks-provision.sh` contains no `cryptsetup isLuks`; an `ext4`, GPT or foreign-signature device causes
      FATAL and zero write calls (`workspaces-luks-provision.test.sh`); a raw device formats once, a `crypto_LUKS` device
      only opens, a second run is a no-op.
- [ ] The `escrow` arm uploads the header after BOTH the `format` and `open` arms, verifies a read-back, shreds the tmpfs
      copy; a failed upload is NOT fatal to boot, records `escrow=missing`, and is retried on every boot (stubs that fail
      the PUT and the HEAD); a missing escrow is a hard RED for the marker.
- [ ] A crash between `luksFormat` and `mkfs` is recoverable: the intent file lets the next boot finish `mkfs`; a blank LUKS
      mapper with no intent file is FATAL.
- [ ] The web-2 volume is declared without `format` and with `ignore_changes = [format]` and `prevent_destroy = true`.
- [ ] A CI plan run (the vehicle named in Phase 0.9) with the push-apply's own `-target` set against live state shows NO
      change to any `hcloud_volume` or `hcloud_server` address (the merge-effect statement is measured, not asserted); the PR
      body's first line states it and quotes the pinned artifact.
- [ ] `web-host-birth-gate.sh` refuses `web-1` by name and requires the raw-volume arm for any other key; the fixtures are
      shaped from a real `terraform show -json` plan.
- [ ] The marker-writer leg writes `WORKSPACES_LUKS_CUTOVER_AT` (in the dedicated marker config) only on a positive-count
      green (probe row and readiness row joined on `boot_id`, `escrow=ok`, age within 26 h), only when the key is absent;
      deletes it on negative evidence (red, stale, empty body); leaves it untouched and fails the run on a query failure.
- [ ] `encryption-posture-ledger.json`: the web-2 row is `luks` with `live_verification: available`, `live_coverage_floor`
      is 3, and `scripts/lint-encryption-posture.py` is green; `BASELINE_DECLARED_PROBES` is bumped.
- [ ] The `workspaces-luks.tf` singleton-rationale comment, ADR-143 R3 (addendum), the 2026-07-24 plan AC5 line and
      `model.c4` say "LUKS-backed at boot"; no "ADR-141 D3" or "ADR-142 D3" citation remains in infra, tests or `model.c4`.

Non-functional:

- [ ] No secret in argv; xtrace refused on every credential-bearing script and workflow step.
- [ ] `cloud-init-user-data-size.test.ts` is green with an explicit byte budget stated in the PR (the env-file write, the
      token line and the hard gate are added against ~300 B of headroom; the two removed fstab/mount lines offset them), cloud-init
      renders under `templatefile()` in the test, and `terraform validate` passes for the root.
- [ ] `fresh-boot-parity.test.sh`, `fresh-boot-ready.test.sh`, `terraform-target-parity.test.ts`,
      `web-hosts-fanout-parity.test.sh`, `test-web-host-birth-gate.sh` and the c4 tests (`c4-code-syntax`, `c4-render`,
      `c4-count-parity`) are green.
- [ ] Residual risk R4 is written into the Article 30 register and the compliance posture, conditioned on the live event.
- [ ] The PR body uses `Ref #6931` (not `Closes`), and carries the follow-through directive for the soak-gated closure.

Quality gates:

- [ ] The user-impact review agent runs on the diff (threshold `single-user incident`); CPO sign-off is recorded on the plan.
- [ ] ADR-262 is authored and its ordinal re-verified against every pushed branch AND `origin/main` immediately before merge.

### Post-merge (gated dispatches; each runs from a workflow, none is a hand-run host step)

- [ ] The push apply created the new token and secret resources; a second plan with the same `-target` set shows none pending.
- [ ] The release image built from the merge commit is published; the pre-dispatch check shows the image's host-script content
      hash label equals `host_scripts_content_hash` at the same commit; the P7 rebirth was dispatched with that explicit `image_tag`.
- [ ] After the rebirth, `bash scripts/betterstack-query.sh "host:soleur-web-2 SOLEUR_FRESH_BOOT_READY"` returns a row with
      `luks=1`, `luks_arm=formatted` and `escrow=ok`; after a workflow-issued hcloud reboot, a row with a new `boot_id` and
      `luks_arm=opened` or `noop`.
- [ ] The daily verify leg is green and `WORKSPACES_LUKS_CUTOVER_AT` exists with the first-green timestamp; the follow-through
      probe `scripts/followthroughs/web2-luks-live-6931.sh` exits 0 after the 3-day soak and closes #6931.

## Test Scenarios

- Given a raw device and a valid key, when the provisioner runs, then luksFormat, luksOpen, mkfs, the fstab line and the
  crypttab line are written exactly once, `luks_arm=formatted`, and a second run is a no-op (`noop`).
- Given a device with `TYPE=crypto_LUKS` whose mapper is closed, when the provisioner runs, then it opens and mounts,
  calls neither luksFormat nor mkfs, and records `opened`.
- Given a device with `TYPE=ext4` (a populated or Hetzner-formatted volume), when the provisioner runs, then it exits
  with the discriminate FATAL, the Sentry stage is emitted, and no write command was invoked.
- Given an empty `TYPE` with a GPT partition table, when it runs, then FATAL (a TYPE-only discriminator would have
  formatted a partitioned disk).
- Given Doppler is unreachable, when the provisioner runs on a raw device, then it exits non-zero before touching the
  device and the app container does not start.
- Given the web-2 probe row is 30 h old, when the verify leg runs, then `WORKSPACES_LUKS_CUTOVER_AT` is deleted.
- Given a `web-host-create` dispatch for `web-1`, when the gate runs, then it refuses with the named reason.
- Integration (for `soleur:qa`, deterministic, no SSH): `bash scripts/betterstack-query.sh "host:soleur-web-2
  SOLEUR_FRESH_BOOT_READY"` expects a row containing `luks=1`.

## Domain Review

**Domains relevant:** engineering, legal

### Engineering (CTO)

**Status:** reviewed
**Assessment:** The consult ruled T1 with a T2-ready seam, rebirth sequencing for raw-at-birth, a baked code home, a
CI-side marker with a web-2 verify leg and ledger floor 2 to 3, and recommended post-boot token delivery. This plan
adopts all but the token channel (D4: the SSH host-key re-capture makes a post-boot step non-unattended) and keeps the
CTO's containment requirement (containers cannot reach the metadata endpoint, which the default-drop firewall already
provides). Two CTO fact adjustments adopted: the `web2_allow` blocker is likely stale (Phase 0.4 verifies), and birth is
not a guaranteed ext4 format today.

### Legal (CLO)

**Status:** reviewed (CONDITIONAL)
**Assessment:** No published-claim edit is needed (the privacy wording is scoped to the volume workspace git data is
served from). Required: Article 30 register rows (cross-host replication, web-2 recipient/location) and
compliance-posture rows updated with sentences conditioned on the live event, never past tense before it; the user_data
token residual (scope ~116 prd secrets; no revocation after first boot is possible because the reopen unit needs the
token on every boot; the metadata endpoint is reachable by root-equivalent host users) recorded as a residual like the
host private-key entry. Art. 32: web-2 holds no personal data and is gate-blocked from receiving any until verified
`crypto_LUKS`; do not say "encrypted" until the probe has passed on the live host. No new processor or transfer.

### Product/UX Gate

**Tier:** none (no user-facing surface; no component, page or layout file in the plan's file lists).
**Decision:** not applicable to this infrastructure plan.

## Files to Edit

- `apps/web-platform/infra/server.tf` — volume block (`format`, `ignore_changes`), `host_script_files`, user_data map, comment.
- `apps/web-platform/infra/workspaces-luks.tf` — rationale comments (item 6), marker-writer token and GitHub secret.
- `apps/web-platform/infra/cloud-init.yml` — `/mnt/data` block, `/etc/default/luks-monitor` token line.
- `apps/web-platform/infra/soleur-host-bootstrap.sh` — install and enable baked files, replace the structural-gate crypttab write, readiness fields.
- `apps/web-platform/infra/workspaces-luks-reopen.service` — header comment (section (d) reversal).
- `apps/web-platform/infra/luks-monitor.sh` — only if Phase 0.3 requires the `standby` profile.
- `apps/web-platform/Dockerfile` — COPY the new baked files.
- `apps/web-platform/infra/fresh-boot-parity.test.sh` (now also carries the canonical-lines byte-parity section), `fresh-boot-ready.test.sh`, `workspaces-luks.test.sh` (comment and anchor pins; note its A11 guard asserts file-scoped cardinality, so the new Doppler resources may need their own file, the `workspaces-luks-header.tf` precedent), `web-hosts-fanout-parity.test.sh`.
- `apps/web-platform/infra/workspaces-boot-unlock.test.sh` and `store-vs-data-mount-parity.test.sh` — verify (and extend where the baked path now overlaps web-1's boot-unlock assertions or introduces a mount-source resolution).
- `plugins/soleur/test/cloud-init-user-data-size.test.ts`, `plugins/soleur/test/terraform-target-parity.test.ts`,
  `tests/scripts/test-destroy-guard-counter-web-platform.sh` (push-apply `-target` set assertions; the full list is
  derived by the Phase 0.8 `git grep`).
- `plugins/soleur/test/preflight-discoverability-test.test.ts` — the declared-probes ratchet `BASELINE_DECLARED_PROBES`
  moves from 39 to 40 in the same PR (this plan's `discoverability_test` declares `credentials_required`), with a
  PLACEMENT/TRUTH/NO-SUBSTITUTE entry; no file-scoped suite selection reaches it, so it is listed explicitly.
- `tests/scripts/lib/web-host-birth-gate.sh`, `tests/scripts/test-web-host-birth-gate.sh`, `tests/scripts/lib/web-host-replace-gate.sh` and `tests/scripts/test-web-host-replace-gate.sh` (unblock-condition text).
- `.github/workflows/apply-web-platform-infra.yml` — push allow-list for the new resources; `image_tag` help text.
- `.github/workflows/workspaces-luks-verify.yml` and `apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh` — web-2 leg, marker writer.
- `scripts/encryption-posture-ledger.json` — web-2 row, `live_coverage_floor`.
- `knowledge-base/engineering/architecture/diagrams/model.c4` (and the generated `model.likec4.json` if the repo regenerates it), ADR-143 and ADR-119 (addenda).
- `knowledge-base/engineering/architecture/nfr-register.md`, `knowledge-base/engineering/operations/runbooks/web-host-replace.md`, `workspaces-luks-cutover-6604.md` (one-line pointers).
- `knowledge-base/legal/article-30-register.md`, `knowledge-base/legal/compliance-posture.md`.
- `knowledge-base/project/plans/2026-07-24-feat-web-active-active-cluster-iac-plan.md` — AC5 superseded marker only.

## Files to Create

- `apps/web-platform/infra/workspaces-luks-provision.sh`, `apps/web-platform/infra/workspaces-luks-provision.test.sh`.
- `scripts/followthroughs/web2-luks-live-6931.sh` (live-evidence and soak probe; sources the verify leg's query helper; see Follow-Through).
- `knowledge-base/engineering/architecture/decisions/ADR-262-guest-side-fresh-boot-luks-for-web-hosts.md`.
- The single-use P7 workflow file (name fixed in Phase 0.4 after the destroy-mechanism measurement).
- `knowledge-base/project/specs/feat-one-shot-6931-web2-fresh-boot-luks/tasks.md` and `decision-challenges.md`.

Path check: every Edit entry was confirmed present in this worktree (`git ls-files` or a direct read); Create entries are new.

## Follow-Through Enrollment (soak-gated closure)

The closure criterion is time-gated: live-conversion evidence plus the marker's 3-day soak. The PR body uses `Ref #6931`;
`scripts/followthroughs/web2-luks-live-6931.sh` (exit 0 when the latest web-2 probe row is `crypto_LUKS`, the marker is at
least 3 days old and no red row exists since) is wired by the tracker directive
`<!-- soleur:followthrough script=scripts/followthroughs/web2-luks-live-6931.sh earliest=<deploy+3d> secrets=BETTERSTACK_QUERY -->`
with the `follow-through` label, and the sweeper workflow's `secrets=` list gains the Better Stack query credentials.
`soleur:ship` Phase 5.5 enforces this at PR-ready time.

## Deferrals (tracking issues filed 2026-10-01, milestone Phase 4: Validate + Scale)

- The replace-based "populated volume" disposability proof (`web-host-replace` on a populated web host): #9356.
- T2, a single keyed raw LUKS resource after the web-1 de-pet (folds into #6964): #9357.
- Sourcing the marker into `lb-weight-gate.sh` env in the flip orchestrator: #9358.

## Delivery slicing (recommended; the pipeline may ship it as one PR)

The plan is sized for one pipeline run, but three reviewers independently recommended splitting it (DC-6). The slices are
dependency-ordered and each is independently safe: **PR-1** provisioner, wiring, raw-at-birth (`ignore_changes`), records core
(ADR-262, `model.c4`); changes no running host. **PR-2** verification vehicle, `boot_id`, marker writer and its Terraform,
ledger row and floor; fail-closed until the live conversion. **PR-3** birth-gate hardening (raw-volume requirement, web-1
refusal); independent of the others. Phase 7 is an operation run after PR-1 and PR-2, not PR content. If the work phase ships
one PR, keep the commit order PR-1, PR-2, PR-3 so any slice can be peeled off.

## Plan Review Outcomes (provenance)

Panel: DHH, Kieran, code-simplicity (per mechanism), architecture-strategist, spec-flow-analyzer, CTO (devex lens); earlier
CTO and CLO consults under Domain Review. Applied (mechanical): the intent-file recovery for a crash between `luksFormat` and
`mkfs`; the emptiness evidence replacing the non-existent API usage proof; a re-check of `_may_format()` immediately before
each destructive call; `boot_id` joining and the query-failure vs negative-evidence split; the dedicated fresh-host token
(rotation coupling) and the corrected token-scope wording; the dedicated marker config (a daily cron must not hold a `prd`
write token); the image/content-hash pre-dispatch check; API-delete-then-state-removal ordering; a named vehicle for the
pre-merge plan run; hard gate placement before the first `/mnt/data` write; the Doppler retry ladder; the 300 s device wait;
guard-matrix trimming; cuts of the per-host dark-timer alert and the separate canonical-lines test; ADR addenda folded into
ADR-262. Surfaced, not decided silently (see `decision-challenges.md`): PR split, escrow-in-scope, marker-writer-in-scope,
in-place web-2 reformat vs rebirth.

## Dependencies & Risks

- **R1 PR B (#9348) collision.** It edits the same `hcloud_volume.workspaces` `for_each`, the web-1 `workspaces_volume_id`
  reference (adjacent to this plan's user_data map edit) and the same ledger row. It is currently an empty draft, so there
  is nothing to rebase onto yet: treat it as a HARD dependency for the server.tf/ledger edits (land PR B first, then rebase,
  never re-narrow here); the provisioner, bootstrap, tests and workflow work can proceed independently in the meantime.
- **R2 Dead-code trap.** If the volume stays ext4 the format arm never runs and the merge looks green. Guard 2 row 1 and
  the P7 evidence (`luks_arm=formatted`) are the measures.
- **R3 Boot ordering.** Provisioning must complete before `mkdir`, `chown` and `docker run` touch `/mnt/data`; a failure
  must not fall through to writing the root-disk directory (immutable inode first, hard gate before `docker run`).
- **R4 Token residual.** The token sits in user_data (readable by root-equivalent host users) and reads ~116 prd secrets;
  no revocation after first boot is possible. Recorded in the registers; true isolation is the separate-project work (#6167).
  The container-side closure is the default-drop egress firewall, which is "fail-open on bootstrap" by design (it does not
  install its drop if allowlist resolution fails and pages instead), so the closure has a bounded window at boot; the
  Phase 0.6 test pins the allowlist content, and the post-container egress probe (`cron-egress-enforce-probe.sh`) already
  powers a fresh host off if enforcement is not proven.
- **R5 User-Challenge.** The issue asked web-1 and web-2 to "share ONE topology"; D1 delivers one MECHANISM and two
  Terraform addresses and defers T2. Recorded in `decision-challenges.md` for the PR body and an `action-required` issue.
- **R6 Rebirth side effects.** New SSH host key, private IP binding and placement group; all web-2 only, weight 0.
- **R8 Interrupted first birth.** Closed by the intent file (Guard 1 rows 7 and 8); without it a crash between `luksFormat` and
  `mkfs` is FATAL on every later boot and the only recovery is a rebirth the `prevent_destroy` volume cannot take.
- **R9 Boot-time races.** The by-id link can lag server boot (300 s wait), Doppler can blip at first boot (retry ladder), and
  a stale `image_tag` carries no provisioner (explicit tag plus the content-hash check): each ends fail-closed, but the
  dispatch must then fail with a named reason rather than wait.
- **R7 Gate narrowing.** Refusing web-1 in `web-host-create` removes a capability merged earlier (the dispatch could
  target web-1); it is intentional and mirrors `web-host-replace`'s by-name refusal, pending #6964's full fix.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or carries filler text fails `deepen-plan` Phase 4.6; this one is filled.
- `templatefile()` text needs `$${...}` for shell variables; baking avoids the class, and the inline call-site lines are plain.
- Do not "fix" `ignore_changes = [format]` by deleting it: the merge would then plan a ForceNew replace that `prevent_destroy` turns into an error on every targeted plan.
- The reopen script's `isLuks` is a read-only "refuse if not LUKS" check; the static guard allowlists exactly that occurrence and nothing else.
- Cite content anchors, never line numbers (the ledger linter resolves anchors).
- A resource created inside a birth plan is an out-of-scope create to the birth gate: the Doppler token and secret resources must be applied by the push apply BEFORE the P7 rebirth.
- Renumbering ADR-262 requires sweeping this plan, tasks.md and any AC naming it.

## References

- ADR-143 R3 (binding), ADR-119 (additive design, section (d), 2026-09-28 addendum), ADR-068 section (c), ADR-148 (replace gate), ADR-140 and ADR-141 (encryption posture).
- `apps/web-platform/infra/workspaces-luks.tf`, `workspaces-luks-reopen.sh`, `luks-monitor.sh`, `lb-weight-gate.sh`, `cloud-init-registry.yml`, `cloud-init-git-data.yml` (blkid-aware format guard).
- Related issues: #6964 (attachment web-1-bound), #6604 and #6588 (cutover), #6730 (web-1 birth path), PR B #9348.
- Brainstorm: none (direct one-shot planning); the CTO and CLO consults are recorded under Domain Review.
