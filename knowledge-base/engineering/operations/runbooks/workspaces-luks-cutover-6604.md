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

   > **The dead-man can undo a SUCCEEDED cutover, silently.** It is armed at the freeze and cleared
   > by `disarm_dead_man`, which runs *after* `app_canary`. So any `die` inside the canary leaves the
   > timer armed — and because `CANARY_OK=1` is already set by the host canary, `cleanup()` correctly
   > does **not** roll back, meaning nothing else intervenes either. On 2026-07-20 (run
   > `29782780158`) the cutover landed, served for ~27 minutes, aborted on a Cloudflare 521 boot
   > race, and the timer then remounted the plaintext volume over a healthy LUKS mount — stranding
   > those 27 minutes of sole-copy writes on a now-detached volume, with **no** signal on any
   > channel. See **#6812**. If a cutover run reports failure, establish whether the timer has since
   > fired before concluding anything about the current mount: a verify run from *before* the
   > 30-minute mark can legitimately report a healthy LUKS mount that no longer exists.

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
   present, `/health`=200, `/internal/readyz` reports `ready=true`, **and** the workspace inventory
   count is at or above the persisted `WORKSPACES_COUNT` baseline. Success is defined by the
   presence of the verdict line, not by the absence of an error:

   ```
   [luks-monitor] SOLEUR_WORKSPACES_READYZ ready=true writable=true populated=true workspace_count=8 expected=8 capacity=use=41%,mount=rw
   ```

   > **This gate was NON-FUNCTIONAL until #6807.** It asserted 200 on the API-prefixed health path,
   > which has no route and 307s to `/login` — the workflow was structurally incapable of ever
   > passing, so from the #6701 canary fix (2026-07-19) until #6807 this step could not succeed for
   > any state of the volume. A `failure` conclusion on a run before that fix says nothing.
   >
   > **`ready=true` is a FLOOR, not an inventory.** `readiness.ts:81` is
   > `countWorkspaceDirsAt(root) > 0`, so a cutover preserving 1 of 8 sole-copy workspaces still
   > reports ready. The `workspace_count` comparison is what carries the "inventory survived" claim.
   >
   > On a host with no baseline (any host cut over before #6807 persisted one), the first run fails
   > closed with `workspace_count_baseline_missing`. Seed it ONCE with
   > `-f seed_workspace_count=<n>`, where `<n>` comes from an INDEPENDENT proof of the inventory —
   > the cutover run's C1 differential `total=` — never from the host's own live count, which would
   > compare a number to itself.

   ### Verdict → operator action

   | Verdict / reason | What it means | Action |
   | --- | --- | --- |
   | `probe rc=0` + verdict line, `workspace_count >= expected` | Healthy and certified | None |
   | Verdict line **ABSENT**, run otherwise green | The assert never ran (flag lost). Proves **nothing** | Treat as FAILED. Re-dispatch; if it recurs, the flag delivery is broken |
   | `rc=255` | SSH/CF-tunnel transport failure | **Not** a drift finding. No Sentry event exists. Check the bridge step, re-dispatch |
   | `rc=1` `mount_not_mapper` / `device_not_luks` | At-rest drift: `/mnt/data` is **not** the LUKS mapper | **Encryption is not in effect.** Do not re-cut before reading §Rollback — a fresh freeze copies whichever volume is live now |
   | `rc=1` `escrow_passphrase_mismatch` / `header_uuid_unreadable` | Escrow or header problem | Header-recovery path; do **not** wipe the plaintext original |
   | `rc=2` `readyz_not_ready` + `capacity` shows `use=100%` or `mount=ro` | **CAPACITY fault**, not data loss | Free space / remount rw. **Never** run a data-recovery procedure for this |
   | `rc=2` `readyz_not_ready` on a healthy `rw` mount with space | The container cannot serve from the mount | Data-recovery incident on sole-copy data — halt and escalate |
   | `rc=2` `readyz_gate_regression` | 403/404/405 — loopback gate or route regression | Application/routing bug. **Not** data loss, despite the endpoint being about the mount |
   | `rc=2` `readyz_unparseable` | Proxy error page / truncated body | Transport or proxy fault. Not data loss |
   | `rc=2` `workspace_count_shortfall` | Fewer workspaces than the baseline | **Data-recovery incident on sole-copy data.** Halt and escalate. Do not wipe anything |
   | `rc=2` `workspace_count_baseline_missing` | No baseline persisted | Seed it once (above). Fail-closed by design |
   | `rc=2` `readiness_helper_unavailable` | `workspaces-luks-emit.sh` missing/stale on the host | The assert cannot run; this run proves nothing. Reinstall via the cutover channel |
   | `health_probe_structural` | `/health` returned 307/401/403/404/405/525/526 | Endpoint/routing regression. Retrying will not help |
   | `health_probe_deadline` | `/health` never reached 200 within the budget | Slow boot, no route, or DNS. Check the container and CF tunnel |

   The capacity-vs-data-loss split is the one that matters most: `isWorkspacesWritable` fails closed
   on ENOSPC/EROFS/EACCES/EIO alike, so a full disk and a lost volume produce the *same*
   `ready=false`. Escalating a full disk to "data-recovery on sole-copy data" is a destructive
   response to a non-destructive problem.

6. **Soak (7 days).** The retained plaintext volume stays **attached-unmounted, un-wiped** for 7
   days (protected by the cutover gate's `old_volume_touched==0`, NOT `prevent_destroy`). Enrol
   `scripts/followthroughs/workspaces-luks-soak-6604.sh` with a real ISO `earliest=` (canary+7d) and
   the `follow-through` label. It PASSes only on observed completion (drift=0 ∧ heartbeat spanning
   ≥7d ∧ ADR-119 `accepted`).

   > **The soak clock has not started and cannot until #6808 lands.** The heartbeat it gates on is
   > UNFED (see Failure signals), so no rows accumulate and the ≥7d span can never be satisfied.
   > #6808 is the critical path to this step, not an optional tidy-up.

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
- ~~**Better Stack** `betteruptime_heartbeat.workspaces_luks` — a missed daily push = a dead probe.~~
  **UNFED pending #6808.** The Terraform resource exists, but `WORKSPACES_LUKS_HEARTBEAT_URL` is not
  wired, so `luks-monitor.sh:116` logs the URL as absent and pushes nothing. This channel pages on
  **nothing today** — do not count it as a failure signal, and note that the 7-day soak gates on
  heartbeat rows spanning ≥7d, so that clock has not started.
  A worked consequence: on 2026-07-20 the daily probe stopped running entirely for ~6 hours and no
  dead-probe signal fired, because there is no live heartbeat to miss (#6812).
- **`betteruptime_monitor.app`** — a refused container (failed unlock) is a hard down.
