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

0. **RECOVERY-ONLY — re-cut after a dead-man-orphaned LUKS volume (#6812 / #6855).** Skip this on a
   first-time cutover. Run it ONLY when a prior cutover landed and was then undone by its dead-man
   timer, leaving `hcloud_volume.workspaces_luks` **in state and already `crypto_LUKS`** (holding a
   discarded write window) while `/mnt/data` is back on plaintext `/dev/sdb`. In that state a plain
   re-cut does **NOT** re-format: `workspaces-cutover.sh`'s device guard treats an already-`crypto_LUKS`
   device as an idempotent no-op, so it re-opens the OLD header and serves stale data — it does **not**
   `luksFormat`. Make the volume genuinely fresh first (this **destroys** the orphaned volume — an
   irreversible, operator-accepted discard of the stranded window):
   First read the orphaned volume's Hetzner id from the latest `terraform-drift` run's
   `hcloud_volume.workspaces_luks: Refreshing state... [id=<ID>]` line (e.g. `106406962`). Then:
   `gh workflow run apply-web-platform-infra.yml -f apply_target=workspaces-luks-recut -f confirm=RECUT-WORKSPACES-LUKS -f expected_luks_volume_id=<ID> -f reason='#6812 re-cut fresh target'`
   The `workspaces-luks-cutover` **environment reviewer must approve** (the sole authorization; the
   typed `confirm` and `expected_luks_volume_id` are typo/id guards, not the authorization). The
   sourced `workspaces_luks_recut_gate` aborts unless the plan is exactly `{volume REPLACE + attachment
   CREATE}` with the live plaintext volume/attachment + web-1 + the passphrase all untouched (the
   passphrase is **reused**, never re-minted) **and the replaced volume's id equals `<ID>`** — a
   `luks_id_mismatch=1` means the `workspaces_luks` address resolves to a DIFFERENT physical volume than
   you named (state corruption); STOP and reconcile state. No `[ack-destroy]` bypass. After it runs, the
   volume is a raw replacement with the same name, so Step 2 onward proceeds normally — the cutover
   resolves it by name and hits the raw→`luksFormat` arm. Zero downtime (the live plaintext keeps
   serving throughout). **If the apply fails mid-replace** (destroy-before-create leaves the volume out
   of state), just re-dispatch with the same inputs — the gate's recovery arm accepts the bare create
   that a re-dispatch then plans, completing the raw-volume create.

1. **Provision the encrypted volume (additive, zero downtime).** *(FIRST cutover only — skip if you
   ran Step 0, which already leaves the five resources in state.)*
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
   > `29782780158`) the cutover landed and **aborted almost immediately** on a Cloudflare 521 boot
   > race at `app_canary`; the LUKS mount then served traffic for ~27 minutes until the dead-man
   > timer fired and remounted the plaintext volume over it — stranding those 27 minutes of sole-copy
   > writes on the LUKS volume (now unmounted and mapper-closed, **not** detached — it still exists),
   > with **no** signal on any channel (a *successful* dead-man remount emitted nothing until #6807
   > added arm/fired/disarm markers). See **#6812**. If a cutover run reports failure, establish
   > whether the timer has since
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
   > passing. That assertion was present from the workflow's creation (2026-07-17); #6701 fixed only
   > the cutover's own canary (2026-07-19), never this workflow, so the §5 gate was dead from
   > 2026-07-17 until #6807. A `failure` conclusion on a run before this fix says nothing.
   >
   > **`ready=true` is a FLOOR, not an inventory.** `readiness.ts:81` is
   > `countWorkspaceDirsAt(root) > 0`, so a cutover preserving 1 of 8 sole-copy workspaces still
   > reports ready. The `workspace_count` comparison is what carries the "inventory survived" claim.
   >
   > On a host with no baseline (any host cut over before #6807 persisted one), the first run fails
   > closed with `workspace_count_baseline_missing`. Seed it ONCE with
   > `-f seed_workspace_count=<n>`, where `<n>` comes from an INDEPENDENT proof of the inventory —
   > the **host-side directory count of the copied tree** the cutover records automatically at its
   > G3 gate (`wl_count_workspace_dirs` of `$STAGING/workspaces`; for web-1's landed run that was 8).
   > Do **not** use the fsck advisory gate's `total=` field — `total` skips un-probeable workspaces,
   > so it can be lower than the real inventory, and the cutover deliberately does not derive the
   > baseline from it (workspaces-cutover.sh, at the persist site). And never the host's own current
   > live count, which would compare a number to itself. The seed is refused if it is `0` or would
   > **lower** an existing baseline.

   ### Verdict → operator action

   | Verdict / reason | What it means | Action |
   | --- | --- | --- |
   | `probe rc=0` + verdict line, `workspace_count >= expected` | Healthy and certified | None |
   | Verdict line **ABSENT**, run otherwise green | The assert never ran (flag lost). Proves **nothing** | Treat as FAILED. Re-dispatch; if it recurs, the flag delivery is broken |
   Exit-code map: `1` = at-rest LUKS drift · `3` = readiness/inventory · `255` = SSH transport ·
   `127` = bundle/command not found. (`3`, not `2` — bash reserves `2` for its own syntax errors.)
   The two TRANSPORT/TOOLING codes prove nothing about the volume in either direction.

   | Verdict / reason | What it means | Action |
   | --- | --- | --- |
   | `rc=255` | SSH/CF-tunnel transport failure | **Not** a finding. No Sentry event exists. Check the bridge step, re-dispatch |
   | `rc=127` | tar bundle failed to land / script not found on web-1 | **Not** a finding. Check the bundle-ship step, re-dispatch |
   | `rc=1` `mount_not_mapper` / `device_not_luks` | At-rest drift: `/mnt/data` is **not** the LUKS mapper | **Encryption is not in effect.** Do not re-cut before reading §Rollback — a fresh freeze copies whichever volume is live now. **If a prior cutover was undone by the dead-man** (the LUKS volume is still in state + `crypto_LUKS`), a plain re-cut re-opens the stale header instead of re-formatting — run **Sequence Step 0** (`apply_target=workspaces-luks-recut`) first to make the target genuinely raw |
   | `rc=1` `escrow_passphrase_mismatch` / `header_uuid_unreadable` | Escrow or header problem | Header-recovery path; do **not** wipe the plaintext original |
   | `rc=1` `mapper_path_override_refused` | A `WORKSPACES_MAPPER_PATH` env override on the host | **Config fault, not data loss.** Remove the stray env var; it is a test-only seam |
   | `rc=3` `readyz_not_ready` + `capacity` `use=100%` or `mount=ro` | **CAPACITY fault**, not data loss | Free space / remount rw. **Never** run a data-recovery procedure for this |
   | `rc=3` `readyz_not_ready` on a healthy `rw` mount, space free, `writable=false` | Permission/IO fault (EACCES/EIO/inode exhaustion) — `df -P` block-use looks healthy but the write probe failed | **Not data loss.** Check ownership/perms of the workspaces root and `df -Pi` inodes before any recovery |
   | `rc=3` `readyz_not_ready`, healthy `rw` mount, space free, `writable=true`, `populated=false` | The mount is writable but empty | Data-recovery incident on sole-copy data — halt and escalate |
   | `rc=3` `readyz_gate_regression` | 307/401/403/404/405 — loopback gate or route regression | **Probe-integrity/routing bug. NOT data loss**, despite the endpoint being about the mount |
   | `rc=3` `readyz_unparseable` | Proxy error page / truncated body | Transport or proxy fault. Not data loss |
   | `rc=3` `readyz_unreachable` | `/internal/readyz` gave no response for the whole budget | Container still coming up, or the port moved. Not (yet) a data finding — re-dispatch |
   | `rc=3` `workspace_count_shortfall` | Fewer workspaces than the baseline | **Data-recovery incident on sole-copy data.** Halt and escalate. Do not wipe anything |
   | `rc=3` `workspace_count_baseline_missing` | No baseline persisted (or a `0`/non-numeric one) | Seed it once (above). Fail-closed by design |
   | `rc=3` `workspace_count_unreadable` | The workspaces root could not be listed | Permission/IO fault on the root. Not a shrink; fix perms and re-dispatch |
   | `rc=3` `readiness_helper_unavailable` | `workspaces-luks-emit.sh` missing/stale on the host | The assert cannot run; this run proves nothing. Reinstall via the cutover channel |

   **Cutover-only reason codes (emitted by `app_canary`, NOT the verify workflow — the verify's
   runner-side `/health` loop prints an `::error::` line, no reason code):** `health_probe_structural`
   (`/health` returned a structural 307/401/403/404/405/525/526 — endpoint regression, retrying will
   not help) and `health_probe_deadline` (`/health` never reached 200 in budget — slow boot, no
   route, or DNS). Also emitted only by the cutover: `workspace_count_persist_failed` (the baseline
   could not be counted at the C1/G3 gate — the next verify will fail closed until it is seeded).

   The capacity-vs-data-loss split is the one that matters most: `isWorkspacesWritable` fails closed
   on ENOSPC/EROFS/EACCES/EIO alike, and `capacity` only carries `df -P` block use% + rw/ro — so an
   EACCES, an EIO, or inode exhaustion presents as `use=NN%,mount=rw` with `writable=false`. The
   `writable`/`populated` sub-fields, not `capacity` alone, are what separate a permission/IO fault
   from an actual empty mount. Escalating either non-destructive fault to "data-recovery on sole-copy
   data" is a destructive response to a non-destructive problem.

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
  wired, so `luks-monitor.sh` (the heartbeat push, `WORKSPACES_LUKS_HEARTBEAT_URL` block) logs the URL as absent and pushes nothing. This channel pages on
  **nothing today** — do not count it as a failure signal, and note that the 7-day soak gates on
  heartbeat rows spanning ≥7d, so that clock has not started.
  A worked consequence: on 2026-07-20 the daily probe stopped running entirely for ~6 hours and no
  dead-probe signal fired, because there is no live heartbeat to miss (#6812).
- **`betteruptime_monitor.app`** — a refused container (failed unlock) is a hard down.
