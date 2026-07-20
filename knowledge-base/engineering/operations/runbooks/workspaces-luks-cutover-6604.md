# Runbook — the /workspaces LUKS cutover (#6604 / ADR-119)

> **Verification is a workflow + an API read, NEVER a login** (`hr-no-ssh-fallback-in-runbooks`).
> Every step below is a `gh workflow run` or a dashboard-free query. There is no "SSH in and check".

## What this is

`hcloud_volume.workspaces` (web-1's `/mnt/data`) holds every user's checked-out source as **plaintext
ext4**, while three published legal documents say it is LUKS-encrypted. The data is **sole-copy**
(`refs/checkpoints/*` is pushed by no refspec; signup-provisioned workspaces have no git remote). This
cutover moves that data onto a LUKS-encrypted volume and re-points the mapper, with a retain-then-wipe
rollback window. It also **creates a terminal failure mode** — passphrase/header loss ⇒ unreadable
forever — which the escrow proof + off-host header backup exist to prevent.

## Preconditions

- `prd_workspaces_luks` Doppler config exists with `WORKSPACES_LUKS_KEY` (operator precondition,
  `workspaces-luks.tf`).
- The `workspaces-luks-cutover` GitHub **environment** is **provisioned by the default allow-list
  apply** (`github_repository_environment.workspaces_luks_cutover` in `workspaces-luks.tf`,
  `-target`-ed in the push/`manual-rerun` block of `apply-web-platform-infra.yml`) — **not** a manual
  operator step (`hr-all-infrastructure-provisioning-servers`,
  `hr-fresh-host-provisioning-reachable-from-terraform-apply`; same class as `inngest-cutover`). Its
  required-reviewer set (`reviewers.users = [54279]`, @deruelle) **must remain non-empty** — a
  zero-reviewer environment auto-approves (DP-11 F8), and that reviewer is the sole human
  authorization on the freeze. Verify post-apply with `gh api
  repos/jikig-ai/soleur/environments/workspaces-luks-cutover` (200 + non-empty
  `protection_rules[].reviewers`).
- A distinct off-host bucket for the LUKS header backup (`WORKSPACES_HEADER_BUCKET`), **not** the
  tfstate bucket (C4).

## Sequence

1. **Provision the encrypted volume (additive, zero downtime).**
   `gh workflow run apply-web-platform-infra.yml -f apply_target=workspaces-luks-cutover -f reason='#6604 cutover volume'`
   The sourced `workspaces_luks_cutover_gate` aborts unless the plan is exactly the five-resource
   `+create` with the live plaintext volume/attachment + web-1 untouched. No `[ack-destroy]` bypass.

2. **Dry-run the cutover.**
   `gh workflow run workspaces-luks-cutover.yml -f confirm=CUTOVER-WORKSPACES-LUKS -f dry_run=true`
   Exercises the L3 gates + escrow proof + bulk rsync + itemized verify with **no freeze, no repoint**.
   Confirm the run is green before the real freeze.

3. **Engage the freeze (the one human decision).**
   `gh workflow run workspaces-luks-cutover.yml -f confirm=CUTOVER-WORKSPACES-LUKS -f dry_run=false`
   The `workspaces-luks-cutover` environment reviewer must approve. Window: ≤20 min budget (~10
   target), ≤2h hard abort. The cutover runs **on web-1** (host-side EXIT trap — DP-6), so an SSH
   drop mid-freeze still auto-rolls-back to the plaintext mount, and a host-local dead-man timer
   remounts plaintext if no orchestrator heartbeat lands.

<!-- lint-infra-ignore start: C15 boot-path re-canary is a deliberately-retained deferred-orchestrator
     operator step — the cutover does NOT auto-reboot (a reboot drops the SSH session mid-run), so the
     one host-reboot is operator-gated by design and cannot be routed through the dispatch. -->
4. **Boot-path re-canary (C15) — operator step, after the freeze.** The cutover does NOT auto-reboot
   (a reboot drops the SSH session mid-run). The realistic failure is the boot path (the structural
   fail-closed gate + the `--restart unless-stopped` resurrection), so prove it explicitly: **reboot
   web-1 once**, then run the read-only verify below. The run-keyed `CANARY_OK` persisted to the host
   state file cannot satisfy a fresh post-reboot check — only a new green verify does.
<!-- lint-infra-ignore end -->

5. **Verify (read-only, no SSH).**
   `gh workflow run workspaces-luks-verify.yml` → conclusion `success` means `blkid`=`crypto_LUKS`,
   `findmnt /mnt/data`=`/dev/mapper/workspaces`, the `cryptsetup status` mapper→device link is
   present, and `/api/health`=200. The daily `luks-monitor` probe re-asserts this and pushes a
   Better Stack heartbeat; a missed push pages.

6. **Soak (7 days).** The retained plaintext volume stays **attached-unmounted, un-wiped** for 7
   days (protected by the cutover gate's `old_volume_touched==0`, NOT `prevent_destroy`). Enrol
   `scripts/followthroughs/workspaces-luks-soak-6604.sh` with a real ISO `earliest=` (canary+7d) and
   the `follow-through` label. It PASSes only on observed completion (drift=0 ∧ heartbeat spanning
   ≥7d ∧ ADR-119 `accepted`).

7. **Wipe + converge + PR 3 (separate, environment-gated).** After the soak comments "SOAK PASSED —
   wipe authorized", a human authorizes the **separate** environment-gated destructive dispatch:
   `lsblk -D` → `blkdiscard -z` → verified read-back → **detach** → Hetzner API delete (C5); the
   `for_each` key-set convergence (narrow to exclude web-1 on both the volume and its attachment —
   DP-2, never a block delete); flip ADR-119 `adopting → accepted`; open **PR 3** (the legal flip).
   This dispatch re-verifies the durable run-keyed `canary_ok` header UUID against the live mapper
   immediately before `blkdiscard` (DP-7).

## Rollback

`gh workflow run workspaces-luks-cutover.yml -f confirm=CUTOVER-WORKSPACES-LUKS -f dry_run=false -f rollback=true`
remounts the retained plaintext at `/mnt/data` + restarts. Post-canary rollback is **reconcilable, not
a one-way door** — the LUKS volume retains post-cutover writes, so the door is "restore the read-only
T0 remount + replay from LUKS", never a total loss.

## Failure signals (all off-host)

- **Sentry** `feature=workspaces-luks` / `op=workspaces-luks-drift` — the nine discriminating fields
  (`device_type`, `mount_source`, `mapper_present`, `luks_open_result`, `header_uuid_match`,
  `cryptsetup_unit_result`, `doppler_reachable`, `mountpoint_ok`, `host`, `reason`) tell the failure
  modes apart in one event.
- **Better Stack** `betteruptime_heartbeat.workspaces_luks` — a missed daily push = a dead probe.
- **`betteruptime_monitor.app`** — a refused container (failed unlock) is a hard down.
