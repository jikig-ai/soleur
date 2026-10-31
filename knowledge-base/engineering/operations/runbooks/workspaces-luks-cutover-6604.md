# Runbook — the /workspaces LUKS cutover (#6604 / ADR-119)

> **Verification is a workflow + an API read, NEVER a login** (`hr-no-ssh-fallback-in-runbooks`).
> Every step below is a `gh workflow run` or a dashboard-free query. There is no "SSH in and check".

> **Scope note (2026-10-01, #6931):** this runbook covers web-1 only. Fresh hosts such as web-2 get LUKS through the baked guest-side path decided in [ADR-263](../../architecture/decisions/ADR-263-guest-side-fresh-boot-luks-for-web-hosts.md), not through this cutover.

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
   first-time cutover. **Retired (2026-10-01, #6604 PR B #9348):** on that PR's merge the
   `workspaces-luks-recut` job is hard-retired — its first step exits 1 — and Terraform declares
   `prevent_destroy = true` on `hcloud_volume.workspaces_luks` and on
   `hcloud_volume_attachment.workspaces_luks`, plus `delete_protection = true` on the volume (effective
   only after the post-merge SSH-stage apply). As a second barrier, the recut's `-replace` would
   plan-fail with `Instance cannot be destroyed` against volume `106443278`, which holds the only copy
   of every workspace once D has run. Those failures are the guard, not a defect: never work around
   them. A recut now requires a new reviewed PR. Lifting the protection is a reviewed PR only, and its
   ordering is fixed (lift `delete_protection` in its own reviewed apply first, then `prevent_destroy`
   — the reverse order detaches the mounted volume before the delete fails, an outage). Re-scoping the
   target is #6931's topology work. The text below is kept as the record of the 2026-07-23 recovery
   path. **NEVER after step 7 — it destroys the only copy**: once the plaintext volume is
   wiped, the LUKS volume holds every workspace and this step `-replace`s it (the "live plaintext
   keeps serving" premise below is false after step 7). Run it ONLY when a prior cutover landed and was then undone by its dead-man
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
   target), ≤2h hard abort. The cutover runs **on web-1** (host-side EXIT trap — DP-6). The `ssh`
   has no pty, so a dropped connection kills the script with SIGPIPE on its next write, and the EXIT
   trap then rolls back (pre-canary) or rolls forward (post-canary). If the host process dies outright
   during the freeze, the host-local dead-man timer remounts plaintext after `DEAD_MAN_MIN`.

   > **The dead-man guards the freeze window only (#9045).** It is armed before the freeze and
   > disarmed once, at the host-canary pass, BEFORE `docker start`. Before disarming, the host canary
   > checks the workspace count on the live mount. After disarming, it re-asserts that the mount is
   > still the mapper. The arm verifies itself (`result=armed` only after the timer reads
   > `waiting`), and every abort records `result=cutover_aborted outcome=<x>`. So:
   >
   > - **A pre-canary abort** rolls back to plaintext. That is lossless, because nothing has written
   >   to the LUKS volume yet.
   > - **A post-canary abort** (any failure after `docker start`, including the cutover's tail) has
   >   nothing armed. It rolls FORWARD on the LUKS mount: `cleanup()` re-asserts the mapper,
   >   restarts the app there, and pages `cutover_aborted_post_canary`. If `/mnt/data` is no longer
   >   the mapper, it stops the app and writers instead. This is **fix-forward only**; see the triage
   >   table under [Failure signals](#dead-man-and-abort-triage-9045).
   >
   > **Why (history).** On 2026-07-20 (run `29782780158`) the dead-man was still disarmed only after
   > `app_canary`. The cutover landed, aborted on a Cloudflare 521 boot race at `app_canary`, and the
   > LUKS mount served traffic for ~27 minutes. Then the dead-man fired and remounted the plaintext
   > volume over it, stranding those writes on the LUKS volume, with no signal on any channel. See
   > **#6812**. On 2026-07-23 the arm very likely never took: a stale failed unit refused
   > `systemd-run`, the refusal was discarded, and `result=armed` was logged anyway (ADR-119
   > 2026-09-28 addendum, H1).

<!-- lint-infra-ignore start: C15 boot-path re-canary is a deliberately-retained deferred-orchestrator
     operator step — the cutover does NOT auto-reboot (a reboot drops the SSH session mid-run), so the
     one host-reboot is operator-gated by design and cannot be routed through the dispatch. -->
4. **Boot-path re-canary (C15) — delivered by #9123.** The cutover does NOT
   auto-reboot (a reboot drops the SSH session mid-run), so this step stays operator-gated.
   The boot path #9123 delivered:
   - web-1's `/mnt/data` fstab line is `/dev/mapper/workspaces … defaults,nofail` — exactly one
     entry, the literal glob preserved only as a comment;
   - `workspaces-luks-reopen.service` unlocks the mapper at boot — the key fetched via
     `doppler secrets get WORKSPACES_LUKS_KEY --plain --config prd_workspaces_luks`, piped to
     `cryptsetup luksOpen --key-file -` — with a bounded restart ladder and the standing
     `.timer` re-attempting; crypttab declares the same mapping `luks,noauto` as the
     manual-recovery handle;
   - the §(e) mount gate is armed: `docker.service.d/10-workspaces-luks-mount.conf` carries
     `RequiresMountsFor=/mnt/data` + `After=workspaces-luks-reopen.service`, and the covered
     root-disk `/mnt/data` inode is `chattr +i`.

   **Refusal → recovery map** (the installer's mutating steps refuse with distinct exit
   codes; what each code means for your next move):

   | Apply step exit | Cause | Recovery |
   | --- | --- | --- |
   | `17` | A live cutover freeze is armed (`workspaces-luks-deadman.timer` `SubState=waiting`) | **Self-heals.** The resource taints; the next apply re-fires it once the freeze clears |
   | `32` | `/etc/crypttab` has a foreign (whitespace-anchored, non-canonical) `workspaces` mapping | **Host reconciliation.** Comment the foreign `^[[:space:]]*workspaces` line, append the pinned by-id line `workspaces /dev/disk/by-id/scsi-0HC_Volume_<volume-id> none luks,noauto`, re-apply |
   | `42` | `/mnt/data`'s live source is not `/dev/mapper/workspaces` | **Host reconciliation.** The writer refuses to point fstab at a device that is not the live mount — reconcile the mount first, then re-apply |
   | `54` / `55` / `56` | The covered-inode bind peek failed / peek target is a symlink / peek is not on the root fs | **Host reconciliation.** Inspect `/run/workspaces-boot-unlock-peek` and `/mnt/data` on the host, clear the anomaly, re-apply |

   The C15 proof is: reboot once, then run the read-only verify below. Before rebooting,
   confirm the delivery actually landed — the `terraform_data.workspaces_boot_unlock_install`
   post-state print in the latest `apply-web-platform-infra.yml` run must show the single
   mapper fstab line, `crypttab-workspaces-lines=1`, the reopen units enabled, the peek
   `lsattr -d` reporting `i`, and the proof run reporting `noop`. If that print is absent or
   red, this step is still blocked. The run-keyed `CANARY_OK` persisted to the host state file
   cannot satisfy a fresh post-reboot check; only a new green verify does.

   If step 7 (the wipe) has not run yet, the reboot can invalidate the recorded `PLAINTEXT_DEV`: it
   is a kernel name, and a reboot may rename it (DC-3 in
   `knowledge-base/project/specs/feat-one-shot-6604-wipe-plaintext-identity/decision-challenges.md`;
   the plan leaves this ordering to the operator). Run the read-only step 7b rehearsal **before**
   rebooting: its `rehearsal_ok` row puts `plaintext_dev=` and `plaintext_fs_uuid=` (and
   `target=`, `serial=ok`) off-host as pre-reboot evidence, which is what a fix-forward would bind to.

   **Superseded 2026-10-01 (#9348), as to "step 7b":** PR #9348 removed step 7's sub-steps from this
   runbook. The rehearsal was step 7b at `59abf6a76c`
   (`git show 59abf6a76c:knowledge-base/engineering/operations/runbooks/workspaces-luks-cutover-6604.md`),
   and it ran as `36769782488` on 2026-09-30. Once D has concluded there is no plaintext record left
   for a reboot to invalidate.

   > If the unlock fails during the reboot, the expected shape is a DEGRADED boot, not emergency
   > mode: `nofail` lets `local-fs.target` complete, `RequiresMountsFor` holds `docker.service`
   > down (site down, data-safe — nothing can write the covered root-disk inode), the restart
   > ladder retries, and an exhausted ladder pages once via `op=workspaces-luks-drift` naming
   > the failing phase. That is the failure mode to look for on a bad outcome.
   >
   > On a RECOVERED boot — the standing timer later remounts the mapper — the site does not
   > come back on its own: a dependency-failed `docker.service` does not re-queue once
   > `RequiresMountsFor` is satisfied, so `systemctl start docker.service` may be needed.
   > Since the review-fix pass the reopen script self-issues exactly that start on its real
   > (non-noop) arm — the manual step above is the fallback if that kick itself fails.
<!-- lint-infra-ignore end -->

5. **Verify (read-only, no SSH).**

   > **This check is DAILY AND AUTOMATIC as of #6808** — `workspaces-luks-verify.yml` carries
   > `schedule: 41 4 * * *`, so you no longer have to remember to run it. Dispatch it by hand only
   > when you want an answer *now* (after a cutover, during an incident); the command below still
   > works and the dispatch path is unchanged. Three things follow, and they change how you read
   > this section:
   >
   > 1. **A failure finds you.** A failing scheduled run files a `ci/luks-verify` issue whose title
   >    names its class, and `drift`/`readiness` additionally page <ops@jikigai.com> by email. You do
   >    not have to watch a dashboard — `hr-no-dashboard-eyeball-pull-data-yourself`.
   > 2. **Read the `outcome_class` column below FIRST, then the reason.** The class is the workflow's
   >    own machine-readable verdict and it answers the only question that governs your next move:
   >    `drift` = encryption is not in effect (a legal re-evaluation trigger); `readiness` = the
   >    volume is a correct mapper but the app cannot serve from it or the inventory shrank;
   >    `unavailable` = **the run proved nothing in either direction**, so do NOT start a
   >    data-recovery procedure on it. Note `mapper_path_override_refused` is `unavailable` even
   >    though it arrives on `rc=1`: the classifier keys on the REASON first, precisely so a config
   >    refusal cannot masquerade as at-rest drift.
   > 3. **Silence is covered too.** A scheduled run that never fires — a dropped GitHub schedule, a
   >    concurrency-cancelled pending run, a job timeout — is invisible to the workflow itself and is
   >    caught by the `workspaces-luks-verify` Sentry Crons monitor instead (two consecutive misses,
   >    so ~31 h).
   >
   > Evidence, on demand and without SSH:
   > `gh run list --workflow=workspaces-luks-verify.yml --event=schedule --limit 40 --json databaseId,conclusion,createdAt`
   > and `gh issue list --label ci/luks-verify --state all`.

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

   | Verdict / reason | `outcome_class` (#6808) | What it means | Action |
   | --- | --- | --- | --- |
   | `probe rc=0` + verdict line, `workspace_count >= expected` | `pass` | Healthy and certified | None |
   | Verdict line **ABSENT**, run otherwise green | `unavailable` | The assert never ran (flag lost). Proves **nothing** | Treat as FAILED. Re-dispatch; if it recurs, the flag delivery is broken |

   Exit-code map: `1` = at-rest LUKS drift · `3` = readiness/inventory · `255` = SSH transport ·
   `127` = bundle/command not found. (`3`, not `2` — bash reserves `2` for its own syntax errors.)
   The two TRANSPORT/TOOLING codes prove nothing about the volume in either direction.

   | Verdict / reason | `outcome_class` (#6808) | What it means | Action |
   | --- | --- | --- | --- |
   | `rc=255` | `unavailable` | SSH/CF-tunnel transport failure | **Not** a finding. No Sentry event exists. Check the bridge step, re-dispatch |
   | `rc=127` | `unavailable` | tar bundle failed to land / script not found on web-1 | **Not** a finding. Check the bundle-ship step, re-dispatch |
   | `rc=1` `mount_not_mapper` / `device_not_luks` | `drift` | At-rest drift: `/mnt/data` is **not** the LUKS mapper | **Encryption is not in effect.** Do not re-cut before reading §Rollback — a fresh freeze copies whichever volume is live now. **If a prior cutover was undone by the dead-man** (the LUKS volume is still in state + `crypto_LUKS`), a plain re-cut re-opens the stale header instead of re-formatting — run **Sequence Step 0** (`apply_target=workspaces-luks-recut`) first to make the target genuinely raw. **After Sequence step 7 (PR #9348): never the recut and never a re-cut.** The recut job is hard-retired (its first step exits 1), `prevent_destroy` refuses its `-replace`, the LUKS volume holds the only copy, and no plaintext original exists. Fix forward on the LUKS volume: the boot reopen path (`workspaces-luks-reopen.service` and its timer, Sequence step 4) re-opens the mapper, then run the verify workflow. A recovery that changes Terraform needs a new reviewed PR. Escalate |
   | `rc=1` `escrow_passphrase_mismatch` / `header_uuid_unreadable` | `drift` | Escrow or header problem | Header-recovery path; do **not** wipe the plaintext original. **After Sequence step 7 (PR #9348) there is no plaintext original:** the header-recovery path is the only path, and the escrowed passphrase plus the off-host header are the only recovery material for the sole copy. Halt and escalate before any change |
   | `rc=1` `escrow_check_failed` | `unavailable` | `cryptsetup luksOpen --test-passphrase` could not produce a keyslot verdict — an early device/tooling error, or the key feed's producer dying on a closed pipe (the `#9325` SIGPIPE shape). The probe's FAIL line carries `cryptsetup rc=` and the first 160 bytes of its stderr | **Tooling fault, not a broken escrow** — the passphrase was never judged, so the at-rest escrow verdict was not proven in either direction. Check `cryptsetup` and the device on the host (the stderr fragment in the FAIL line names the real cause) and re-dispatch |
   | `rc=1` `mapper_path_override_refused` | `unavailable` | A `WORKSPACES_MAPPER_PATH` env override on the host | **Config fault, not data loss.** Remove the stray env var; it is a test-only seam |
   | `rc=3` `readyz_not_ready` + `capacity` `use=100%` or `mount=ro` | `readiness` | **CAPACITY fault**, not data loss | Free space / remount rw. **Never** run a data-recovery procedure for this |
   | `rc=3` `readyz_not_ready` on a healthy `rw` mount, space free, `writable=false` | `readiness` | Permission/IO fault (EACCES/EIO/inode exhaustion) — `df -P` block-use looks healthy but the write probe failed | **Not data loss.** Check ownership/perms of the workspaces root and `df -Pi` inodes before any recovery |
   | `rc=3` `readyz_not_ready`, healthy `rw` mount, space free, `writable=true`, `populated=false` | `readiness` | The mount is writable but empty | Data-recovery incident on sole-copy data — halt and escalate |
   | `rc=3` `readyz_gate_regression` | `unavailable` | 307/401/403/404/405 — loopback gate or route regression | **Probe-integrity/routing bug. NOT data loss**, despite the endpoint being about the mount |
   | `rc=3` `readyz_unparseable` | `unavailable` | Proxy error page / truncated body | Transport or proxy fault. Not data loss |
   | `rc=3` `readyz_unreachable` | `unavailable` | `/internal/readyz` gave no response for the whole budget | Container still coming up, or the port moved. Since the probe runs as `docker exec soleur-web-platform curl …` (#6812 — bridge-gateway peer 403 fix), this ALSO covers the transport failing: container not running, wrong `WL_READYZ_CONTAINER`, or `curl` absent from the image (each → code 000, fail-closed). Not (yet) a data finding — re-dispatch |
   | `rc=3` `workspace_count_shortfall` | `readiness` **p0** | Fewer workspaces than the baseline | **Data-recovery incident on sole-copy data.** Halt and escalate. Do not wipe anything |
   | `rc=3` `workspace_count_baseline_missing` | `unavailable` | No baseline persisted (or a `0`/non-numeric one) | Seed it once (above). Fail-closed by design |
   | `rc=3` `workspace_count_unreadable` | `unavailable` | The workspaces root could not be listed | Permission/IO fault on the root. Not a shrink; fix perms and re-dispatch |
   | `rc=3` `readiness_helper_unavailable` | `unavailable` | `workspaces-luks-emit.sh` missing/stale on the host | The assert cannot run; this run proves nothing. The verify job ships the helper beside the probe, so check its bundle-ship step first. The host copy (`/usr/local/bin/workspaces-luks-emit.sh`) is delivered by `terraform_data.luks_monitor_install` since #8706. A plain re-run does not re-deliver it: see [re-fire the installer](#step-e-re-fire-the-installer) (tainted installer, or a merge that changes a trigger file) |
   | `rc=1` `not_mounted` | `drift` | `/mnt/data` is not a mountpoint at all | **Encryption is not in effect** — the volume never attached, or was unmounted. Read §Rollback before re-cutting. After Sequence step 7 (PR #9348), never re-cut: see the `mount_not_mapper` row |
   | `rc=1` `mapper_absent` | `drift` | The mount source is the mapper path but `/dev/mapper/workspaces` does not exist | **Encryption is not in effect.** Same path as `mount_not_mapper` |
   | `rc=1` `cryptsetup_status_missing` | `unavailable` | The mapper node exists and IS serving the mount, but `cryptsetup status` failed | **Tooling/parse fault, not plaintext.** Reached only after mountpoint, mount-source and mapper-node checks all passed, so at-rest encryption is in effect. Check `cryptsetup` on the host |
   | `rc=1` `mapper_device_link_missing` | `unavailable` | `cryptsetup status` succeeded but its `device:` line did not parse | **Parse fault, not data loss.** Same reasoning as above |
   | `rc=1` `doppler_unreachable` | `unavailable` | The host could not read `WORKSPACES_LUKS_KEY` from Doppler | Probe-integrity: the escrow assert never ran. Check the boot token's `prd_workspaces_luks` scope |
   | `rc=1` `fstab_mnt_data_lines` | `drift` | `/etc/fstab` does not carry exactly one non-comment `/mnt/data` entry (a count ≠ 1 — e.g. the pre-#9123 literal-glob line) | **Encryption is in effect NOW but not durable** — the next boot mounts a wrong source, nothing, or fails into emergency mode, and sole-copy writes can land plaintext on the root disk. Reconcile fstab to the canonical `/dev/mapper/workspaces /mnt/data ext4 defaults,nofail 0 2` line per §Boot-unlock delivery (or re-fire `workspaces_boot_unlock_install`) before any reboot |
   | `rc=1` `fstab_mapper_line_missing` | `drift` | No non-comment fstab line names `/dev/mapper/workspaces` | Same durable-encryption verdict as above — the boot path has no mapper pin even if the mount count reads right |
   | `rc=1` `covered_inode_peek_failed` | `unavailable` | The probe's `mount --bind /` peek could not be established, so `lsattr` on the covered root-disk `/mnt/data` inode could not be read | **Probe-integrity, not a finding** — nothing was proven about the §(e) gate. Check mount/permission state on the host and re-dispatch |
   | `rc=1` `covered_inode_not_immutable` | `drift` | The covered root-disk `/mnt/data` inode lacks `+i` (peek succeeded, flag absent) | The ADR-119 §(e) tripwire regressed — a degraded boot lets dockerd write sole-copy data plaintext to the root disk. Re-fire `workspaces_boot_unlock_install` (its gate_writer re-arms the flag) before any reboot |
   | `rc=3` `heartbeat_url_absent` | `unavailable` | Every at-rest assert PASSED, but `WORKSPACES_LUKS_HEARTBEAT_URL` could not be read, so the dead-probe heartbeat was not pushed | **Alerting-path fault, NOT data loss** — the volume is fine; what broke is the probe's ability to report, which is what makes a dead probe indistinguishable from a healthy one (#6808). Confirm `doppler_secret.workspaces_luks_heartbeat_url` is applied and the boot token still reads `prd_workspaces_luks`. Never run a data-recovery procedure for this |
   | `rc=3` `heartbeat_push_failed` | `unavailable` | The URL was present but all 3 push attempts to Better Stack failed | **Alerting-path fault, NOT data loss.** Egress or Better Stack outage. The heartbeat will also miss on its own (period 86400 + 1h grace), so expect a dead-probe alert to follow; re-dispatch once egress is healthy |
   | `app_health_structural` | `readiness` | `/health` returned a structural code (307/401/403/404/405/525/526) after the full retry budget | **Routing/endpoint regression the operator can act on.** Not data loss. Check the custom server and the CF route |
   | `app_health_unreachable` | `unavailable` | `/health` exhausted its retry budget on a retryable CF-edge code | Transport outage. Nothing proven about the volume — do **not** run a data-recovery procedure |
   | `verdict_line_absent` | `unavailable` | rc=0 but the readiness/inventory verdict line never appeared | The assert did not run (`LUKS_MONITOR_ASSERT_READYZ` lost before reaching the host). Treat as FAILED, re-dispatch |
   | `ssh_transport_failure` | `unavailable` | rc=255 — SSH/CF-tunnel drop | **Not** a finding. Check the bridge step, re-dispatch |
   | `bundle_or_tooling_missing` | `unavailable` | rc=127 — bundle failed to land or the script was not where the run expected it | **Not** a finding. Check the bundle-ship step |
   | `bridge_web_host_ssh_missing` | `unavailable` | The CF Tunnel bridge did not export `WEB_HOST_SSH` | The run never reached web-1. Check the bridge step logs |
   | `boot_token_missing` | `unavailable` | `WORKSPACES_LUKS_BOOT_TOKEN` absent | The escrow assert cannot run. Check repo secrets |
   | `remote_bundle_dir_failed` | `unavailable` | Could not create the remote bundle directory on web-1 | Disk or permission fault on `/var/lib/workspaces-luks` |
   | `scheduled_seed_refused` | `unavailable` | A **scheduled** run carried a seed input | Refused by design — the scheduled path is read-only and must never mutate host state. No action beyond noting it |
   | `seed_not_positive_integer` | `unavailable` | `seed_workspace_count` was empty, zero, zero-padded, non-numeric, or >9 digits | Re-dispatch with a positive integer from an INDEPENDENT inventory proof. Zero and over-wide values are refused because both make the shortfall comparison unable to fail |
   | `seed_below_existing_baseline` | `unavailable` | The seed would LOWER the recorded baseline | **Refused by design.** A downward re-seed masks a real shortfall — treat a shortfall as a data-recovery incident, not a seed |
   | `seed_baseline_unreadable` | `unavailable` | The existing baseline could not be read, or is not a usable integer | Refused rather than seeding blind: a seed written without reading the current baseline can silently lower it. Re-dispatch once the tunnel is healthy |
   | `seed_write_failed` | `unavailable` | The baseline write to web-1 failed | No baseline was recorded. Re-dispatch |

   **Cutover-only reason codes (emitted by `app_canary`).** NOTE: the verify workflow's runner-side
   `/health` loop DOES now emit its own reason codes as of #6808 — `app_health_structural` and
   `app_health_unreachable`, both in the table above. The former wording ("no reason code") described
   the pre-#6808 loop and is retained here only to mark what changed. The cutover-only codes are:
   `health_probe_structural`
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

   > **The soak clock STARTED 2026-08-04**, when the heartbeat it gates on took its first observed
   > push (#6808 — see Failure signals). Rows now accumulate daily, so the ≥7d span is first
   > satisfiable on **2026-08-11**. Before that date the soak has not failed, it has merely not
   > matured — do not read a short span as a drift finding.
   > The blocker this note used to record is cleared; #6897's plaintext-volume soak is no longer
   > waiting on #6808.

7. **RETIRED by PR #9348 — the retained plaintext volume is wiped and deleted, and Terraform
   converges (#6604 step 7; PR A #9163 / #9286, PR B #9348); complete only once D and the forget have
   run, 2026-10-08.** The retained plaintext volume (`105149570`,
   `soleur-web-platform-data`, `hcloud_volume.workspaces["web-1"]`) is a superseded copy frozen at the
   2026-07-23 cutover. The wipe dispatch D zeroes it with a full-device read-back, detaches and deletes
   it (run 37801674740), and the forget removes its two Terraform addresses
   (run 37803274724). PR #9348 merges only after both (the plan's §Operator Holds).
   From D's `delete_issued=true`, the LUKS volume `106443278` holds the **only** copy of every
   workspace.

   - **Evidence:** the Art. 5(2) destruction record,
     `knowledge-base/legal/audits/workspaces-plaintext-destruction-record.md`, and ADR-119's addendum
     "the plaintext backstop is retired (#6604 step 7, PR B)".
   - **The procedure is in git history at `59abf6a76c`**, and it is the procedure as run only when D's
     and the forget's head SHAs show no diff from `59abf6a76c` over the wipe and forget files (the
     plan's Resume release check runs that `git diff --quiet`) — the rehearsal, the go-ahead, the
     push-apply pause, the dispatch, the forget, the off-host checks and both step-7 verdict tables:
     `git show 59abf6a76c:knowledge-base/engineering/operations/runbooks/workspaces-luks-cutover-6604.md`.
     The single-use code it drove (`wipe_plaintext()` in `workspaces-cutover.sh`, the `wipe` job of
     `workspaces-luks-cutover.yml`, and `workspaces-plaintext-forget.yml`) is cited by name at that SHA.
     Until PR #9348 merges, that wipe dispatch path (the `wipe_plaintext` and
     `expected_plaintext_volume_id` inputs, the `wipe` job) and the forget workflow exist on `main` only,
     and D and the forget run from `main` (the `workspaces-luks-cutover` environment admits `main`
     only); every resume arm (`arm=re_zero`, `arm=detached`, `already_forgotten`) stays available there
     until that merge, and the merge deletes them.
   - **What stays:** `CONFIRM_WIPE` is a tombstone. Any value other than unset or `0` writes one
     `result=cutover_aborted outcome=wipe_retired` row and dies before any mutation (see the triage
     table below). The post-wipe rollback refusal (Guard 5) stays for ever.
   - **Terraform, on the merge of PR #9348:** `hcloud_volume.workspaces` and its attachment range over
     every web host except web-1 (web-2 keeps volume `106466179`, #6931); web-1's
     `workspaces_volume_id` is the literal `"retired-6604"`; Terraform declares `prevent_destroy` and
     `delete_protection` on `hcloud_volume.workspaces_luks` and `prevent_destroy` on
     `hcloud_volume_attachment.workspaces_luks`. Re-enabling the two push-apply workflows ends the
     pause; the first `apply`-job run after that (the post-merge `manual-rerun`, or a push) delivers
     the one in-place `delete_protection` update through its SSH stage, and the Hetzner-side
     protection is effective only from then.
   - **Verify the retired end state (read-only, any time after D; no SSH, GETs only):**

     ```bash
     doppler run -p soleur -c prd_terraform -- sh -c 'curl -sS -o /dev/null -w "%{http_code}\n" -H "Authorization: Bearer $HCLOUD_TOKEN" https://api.hetzner.cloud/v1/volumes/105149570'   # expect 404
     doppler run -p soleur -c prd_terraform -- sh -c 'curl -sS -H "Authorization: Bearer $HCLOUD_TOKEN" https://api.hetzner.cloud/v1/servers/123931471' | jq -c '.server.volumes'   # expect [106443278]
     doppler run -p soleur -c prd_terraform -- sh -c 'curl -sS -H "Authorization: Bearer $HCLOUD_TOKEN" "https://api.hetzner.cloud/v1/volumes?name=soleur-web-platform-data"' | jq -c '[.volumes[].id]'   # expect []
     doppler run -p soleur -c prd_terraform -- sh -c 'curl -sS -H "Authorization: Bearer $HCLOUD_TOKEN" https://api.hetzner.cloud/v1/volumes/106443278' | jq '.volume.protection.delete'   # expect true after the SSH-stage apply
     ```

     (`sh -c` so the token expands inside Doppler's environment. Use `HCLOUD_TOKEN_READONLY` once it
     is provisioned, #9371.)

   > **web-1 lost (note, 2026-10-01, #6604 PR B).** web-1 is not replaceable by automation (ADR-148;
   > the replace path refuses it by name), and after step 7 there is no plaintext copy to fall back on.
   > If web-1 is lost while volume `106443278` survives, the recovery is the #6964 path: the LUKS volume
   > goes to a replacement host in the same Hetzner location (`hel1`) through a reviewed Terraform
   > change, unlocked with the escrowed passphrase. `prevent_destroy` on `hcloud_volume.workspaces_luks`
   > and on its attachment is lifted only through a reviewed PR, never to make such a change plan. A
   > web-1 host-replace plan now fails closed on the attachment's `prevent_destroy` (its `server_id` is
   > ForceNew), so a deliberate replacement needs a PR that relaxes it. A rebuilt web-1 on the sentinel
   > emits `workspaces_mount fatal` and keeps booting on an empty, writable root-disk `/mnt/data` (fails
   > loud, not closed; new writes there would land unencrypted, #6931). The loss of the volume itself is not recoverable: there is no backup or snapshot (#5274,
   > #8625).

   ROLLBACK after this step is refused permanently (`outcome=refused_plaintext_wiped mode=rollback
   why=marker`): there is no plaintext copy to remount. **Sequence Step 0 is never run after step 7**;
   PR #9348 hard-retires its job (its first step exits 1).

## Rotating the boot token (#8632)

The host reads `WORKSPACES_LUKS_KEY` with the `prd_workspaces_luks` service token in
`/etc/default/luks-monitor`. Terraform owns that token (`doppler_service_token.workspaces_luks` in
`apps/web-platform/infra/workspaces-luks.tf`) AND its delivery to web-1
(`terraform_data.luks_monitor_token_install`, triggered only by the token's hash). A rotation is
therefore one code change and one merge, with no dispatch. The `SOLEUR_SENTRY_DSN=` line in the same
file is delivered by `terraform_data.luks_monitor_install` (#8706); a rotation keeps it. Line
ownership is recorded in ADR-119's 2026-09-24 and 2026-09-27 addenda.

1. **Change the token's `name`** (or `-replace` it). The plan must show exactly: one replace of
   `doppler_service_token.workspaces_luks` (create before destroy), one in-place update of
   `github_actions_secret.workspaces_luks_boot_token`, and one replace of
   `terraform_data.luks_monitor_token_install`. Nothing else. Never
   `-replace random_password.workspaces_luks`, which rotates the PASSPHRASE.
2. **Merge with `[ack-destroy]` on its own line.** In that merge's `apply-web-platform-infra.yml`
   run, the main apply mints the new token, updates the repo secret, then deletes the old token. The
   SSH-provisioned apply step then runs `luks-monitor-token-refresh.sh` on web-1, which proves the new
   token can read the key BEFORE it rewrites only the `DOPPLER_TOKEN=` line (every other line is kept
   byte for byte, and the original is restored on any mismatch). It never starts
   `luks-monitor.service`. Avoid merging between 04:30 and 05:00 UTC, so a scheduled
   `workspaces-luks-verify` run does not start with the old secret and finish after it is revoked.
   Also avoid merging between 00:00 and 00:35 UTC. The host timer fires in that window, and a host
   run that reads the token file while the old token is being revoked emits `doppler_unreachable`.
   Both windows apply to token-rotating merges only.
3. **Evidence, each readable without SSH:**
   - The apply run's SSH step is green (workflow run log, layer 6):
     `gh run list --workflow apply-web-platform-infra.yml --branch main -L1 --json databaseId,conclusion`.
   - Better Stack carries the helper's verdict under the `luks-monitor` tag (Vector journald,
     layer 3):
     `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 2h --grep SOLEUR_LUKS_HOST_TOKEN_REFRESH`.
     `result=ok` is success; `result=fail reason=<reason>` names the refusal, and on any refusal the
     host keeps the old file.
   - The old token is gone and the new one exists. The config also holds the drift scanner's
     separate `token-drift-ci-tf-prd_workspaces_luks` token, which is expected and stays:
     `doppler configs tokens -p soleur -c prd_workspaces_luks --json | jq -r '.[] | [.name, .created_at] | @tsv'`.
   - The repo secret was rewritten:
     `gh secret list --json name,updatedAt -q '.[] | select(.name=="WORKSPACES_LUKS_BOOT_TOKEN")'`.
   - A plain `workspaces-luks-verify.yml` dispatch goes green (`re-assert PASSED`,
     `outcome_class=pass`). It sends the token from the repo secret, so it proves the token, not the
     host file; the helper's `result=ok` is what proves the host file.
   - No new Sentry `workspaces-luks-drift` event with reason `doppler_unreachable` (the query in
     `scripts/followthroughs/workspaces-luks-soak-6604.sh`).

If the SSH step fails after the main apply succeeded, the old token is already revoked, so the host
has no working token until the installer succeeds. The host timer then fails with
`doppler_unreachable` (one `workspaces-luks-drift` Sentry email; not at-rest drift). The installer is
left tainted, so the next per-merge apply re-fires it; re-running the failed job does the same, but
with the helper at that commit. If the file is absent, the helper creates it (0600 root, token line
only) after proving the token. #8703's first apply found web-1 without the file (`envfile_absent`);
merging #8724 re-fires the tainted installer with that fix. Nothing on this path can lock the volume: the only consumers of this token are
`luks-monitor.sh` and the cutover; a fresh host's in-guest unlock path (#6931, ADR-263) reads a separate
fresh-host token that this rotation never touches.

Do not reboot web-1 as part of a rotation.

## Rollback

**After Sequence step 7 (PR #9348) there is no rollback:** no plaintext copy is left to remount, and
every `rollback=true` is refused (the last part of this section). The next three paragraphs describe
the path before step 7 and are kept as its record.

Before step 7,
`gh workflow run workspaces-luks-cutover.yml -f confirm=CUTOVER-WORKSPACES-LUKS -f dry_run=false -f rollback=true`
remounted the retained plaintext at `/mnt/data` + restarted. Post-canary rollback is **reconcilable, not
a one-way door** — the LUKS volume retains post-cutover writes, so the door is "restore the read-only
T0 remount + replay from LUKS", never a total loss.

**Never the first move after `docker start` (#9045).** Once the app has served from the LUKS mount,
`rollback=true` strands every write since `docker start` on the LUKS volume. That is reconcilable,
but a post-canary abort is fix-forward first: `cleanup()` has already restarted the app on the LUKS
mount. See [the triage table](#dead-man-and-abort-triage-9045).

The script enforces this. When the persisted `CANARY_OK` matches the live volume's LUKS UUID, a
`rollback=true` dispatch refuses (Sentry `rollback_refused_post_cutover`), **whatever `/mnt/data` is
mounted on now**. That includes a reboot whose boot unlock failed (`/mnt/data` empty, the mapper
closed, so the header cannot be read: it fails closed) and a plaintext mount left by an earlier
rollback. The row carries `mount_src=` (what `/mnt/data` was on). Only a different live header, a
later re-format, is not this cutover. Before the 2026-09-30 review the check keyed on "the mapper is
mounted", so an unacked rollback after a failed boot unlock would have served the 2026-07-23 copy and
stranded every LUKS write; this closes that residual, which sat next to DC-4 (a drifted remount
source), and the record-status gate below closes the remount half of it.
Add `-f rollback_ack_luks_writes=true` only once the stranded writes have a reconciliation plan.
The rollback restarts the app only when the plaintext volume actually mounted. A failed remount
leaves the app down and pages `rollback_remount_failed`. (Before PR #9348, an acknowledged
**pre-wipe** `rollback=true` remounted the plaintext read-write, so the wipe's W9 gate — at
`59abf6a76c` — refused the step-7 wipe (`wipe_plaintext_written_after_cutover`) until those writes
were reconciled. The wipe mode is retired, so this no longer applies.)

**After Sequence step 7 there is no rollback.** `rollback=true` refuses before any unmount, with or
without the ack, when either witness holds. The two witnesses page under different slugs, because only
the first one is a wipe:

- `why=marker` (`outcome=refused_plaintext_wiped mode=rollback`, Sentry
  `rollback_refused_plaintext_wiped`): `PLAINTEXT_WIPE_BEGUN` or `PLAINTEXT_WIPED` is persisted on
  web-1. The wipe began, so the copy may be partly or wholly zeroed. Never a rollback: fix forward on
  the LUKS volume. (Before PR #9348 an interrupted wipe was recovered by re-dispatching it, resuming on
  `arm=re_zero`. That code is deleted by PR #9348, which merges only after the wipe completed; should
  an interrupted wipe ever need finishing again, recovery requires a new PR — a partial revert that
  restores the wipe mode and keeps the sole-copy protections, per the PR B plan's §Operator Holds.)
  This is the **only** refusal that proves a wipe: the wipe persisted `PLAINTEXT_WIPE_BEGUN` and read
  it back before any zero.
- `why=plaintext_dev_gone` (`outcome=refused_plaintext_record_gone mode=rollback`, Sentry
  `rollback_refused_plaintext_record_gone`): `/mnt/data` is the mapper and the plaintext device the
  cutover recorded (`PLAINTEXT_DEV`, the device a rollback remounts) is not an intact ext4. No wipe
  marker exists, so this is **never** a wipe, whatever `recorded_status=` says: the record drifted
  (a kernel-name rename after a reboot), the volume was detached, or the probe failed. The intact
  plaintext may still be attached under another name. **Halt and escalate on every value.**
  `recorded_status=` narrows the cause: `absent` (the recorded node is no block device: a rename or a
  detach), `none` (no filesystem signature: another device such as the partitioned root disk, or an
  ambivalent probe), `crypto_LUKS` or another type (the record now names another volume),
  `is_mapper` (the record names the live mapper), `invalid` (no record, or an unsafe one),
  `blkid_absent` / `blkid_error_<rc>` (the probe itself failed).

The check is the first line of `rollback()` itself, so `cleanup()`'s freeze arm refuses the same way
(the same two outcomes, the row carrying `why=`, plus `recorded=`/`recorded_status=` under
`why=plaintext_dev_gone` only), and the dead-man fire string carries its own subset
(`result=fail reason=refused_plaintext_wiped why=marker`, or
`result=fail reason=refused_plaintext_record_gone why=plaintext_dev_gone recorded=<dev> recorded_status=<type>`).
**A refusal from `cleanup()` (a row with no `mode=`) or from a dead-man fire during a cutover leaves the
app and the writers DOWN** on a LUKS copy that has not passed the host canary: the freeze already
stopped them, and the refusal restarts nothing. Run the verify workflow and escalate at once; the
users stay offline until this is resolved.

Off the mapper (for example `/mnt/data` still on the plaintext, or empty), a `rollback()` remounts the
record only when it reads as an intact restore source. Otherwise it mounts nothing, leaves the app
down, and its `rollback_remount_failed` row carries `recorded=`/`recorded_status=`.

## Failure signals (all off-host)

- **Sentry** `feature=workspaces-luks` / `op=workspaces-luks-drift` — the nine discriminating fields
  (`device_type`, `mount_source`, `mapper_present`, `luks_open_result`, `header_uuid_match`,
  `cryptsetup_unit_result`, `doppler_reachable`, `mountpoint_ok`, `host`, `reason`) tell the failure
  modes apart in one event.
- **Better Stack** `betteruptime_heartbeat.workspaces_luks` — a missed daily push = a dead probe.
  **LIVE as of 2026-08-04** (#6808). `WORKSPACES_LUKS_HEARTBEAT_URL` is provisioned by terraform as a
  reference to the heartbeat resource, and `luks-monitor.sh` (the heartbeat push,
  `WORKSPACES_LUKS_HEARTBEAT_URL` block) pushes it on a fully-green probe. Period 86400 + 1h grace,
  so a probe that dies goes `up` → `down` about 25h later. First observed push: the verify run of
  2026-08-04, which took the heartbeat `pending` → `up`.
  Pull it without a dashboard (the heartbeat id is stable; the URL itself is a bearer capability and
  must never be echoed):
  `curl -s -H "Authorization: Bearer $(doppler secrets get BETTERSTACK_API_TOKEN --plain -p soleur -c prd_terraform)" https://uptime.betterstack.com/api/v2/heartbeats/478794 | jq '.data.attributes | {paused, status}'`
  A `status` of `up` means a push landed inside the window; `down` means the probe stopped; `paused`
  means someone re-paused it (terraform will NOT un-pause it for you — the resource ships
  `paused = true` behind `lifecycle { ignore_changes = [paused] }`, so a re-pause survives every
  apply and is invisible in a plan). Un-pausing does not need the UI:
  `curl -X PATCH -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -d '{"paused":false}' https://uptime.betterstack.com/api/v2/heartbeats/478794`
  **Margin, because it is thinner than it looks.** Until #8706 this heartbeat had ONE pusher, the
  daily verify (scheduled 04:41 UTC; GitHub started it between 09:31 and 13:48 UTC on 2026-09-24..27),
  because the host unit was never installed (see ADR-119's
  [2026-09-27 addendum](../../architecture/decisions/ADR-119-luks-at-rest-for-the-live-workspaces-volume.md#addendum-2026-09-27-the-monitor-units-and-the-dsn-line-have-a-terraform-owner-8706)).
  Now it has two: the host unit (`luks-monitor.timer`, `OnCalendar=daily` +
  `RandomizedDelaySec=1800`, installed by `terraform_data.luks_monitor_install`) and the verify.
  Together the largest gap is ~20h, inside the 25h window. The host unit ALONE can space two pushes
  up to **24h30m** apart at opposite jitter extremes, against a 25h window: about 30 minutes of
  headroom. So if the scheduled verify is ever paused, dropped or retired, a slow probe or a
  `Persistent=true` catch-up after a reboot can tip this heartbeat into a false `down`. Widen
  `grace` before removing the verify, not after the first spurious page. The shared heartbeat cannot
  tell the two pushers apart, so a green beat says nothing about the host unit. The only
  host-specific signal is the [host-timer liveness alert](#host-timer-liveness-alert-8706).
  Two things it still does not cover, so do not over-read a green heartbeat. It is
  `policy_id`-gated on the paid tier (`var.betterstack_paid_tier`); on the free tier it alerts by
  **email only** and does not page. And the readyz/inventory dimension has no host-side coverage at
  all, because `LUKS_MONITOR_ASSERT_READYZ` is default-OFF on the daily host unit (which only orders
  after the mount, `After=local-fs.target mnt-data.mount`, and never pulls it in) — a shortfall is
  still seen only by the scheduled verify below.
  Historical note, kept because it is the worked example of why this channel matters: on 2026-07-20
  the daily probe stopped running entirely for ~6 hours and no dead-probe signal fired, because at
  that time there was no live heartbeat to miss (#6812).
- **`workspaces-luks-verify.yml` (daily `schedule: 41 4 * * *`) — the SECOND independent channel,
  alongside the heartbeat above (#6808/#7196).** It was introduced as the compensating control while
  the heartbeat was unfed; now that the heartbeat is live it is no longer the only automatic
  verification of the at-rest claim, but it is still not redundant — it remains the ONLY channel that
  sees the readyz/inventory dimension (a `workspace_count_shortfall`), which the heartbeat cannot
  observe. A failing scheduled run files one `ci/luks-verify` issue classified `drift` (the
  at-rest claim itself — p0, `type/security`, and the counsel re-evaluation trigger), `readiness`
  (an ops or inventory event; a `workspace_count_shortfall` files under its own title at p0 because
  it is irreversible sole-copy data loss) or `unavailable` (nothing proven in either direction — do
  NOT run a data-recovery procedure for it). `drift` and `readiness` also page ops by email;
  `unavailable` deliberately does not.
  Pull it without a dashboard:
  `gh run list --workflow=workspaces-luks-verify.yml --event=schedule --limit 40 --json databaseId,conclusion,createdAt`
  and `gh issue list --label ci/luks-verify --label action-required --state open`
  (the `action-required` filter excludes the `luks/class-selftest` rehearsal issues).
  **It is a compensating control, not a replacement for the heartbeat.** It runs on GitHub's
  scheduler, which drops runs (#4189). It also cannot see the host unit stop, and because it pushes
  the same heartbeat, it keeps that heartbeat `up` when the host unit is dark. The
  [host-timer liveness alert](#host-timer-liveness-alert-8706) catches that. The run-that-never-fires mode is
  covered one layer out by the `workspaces-luks-verify` Sentry Crons monitor, which pages on two
  consecutive missed or errored check-ins.
- **Better Stack heartbeat `soleur-luks-monitor-host-timer-prd`** (#8706, rebuilt as an archive-fed
  heartbeat in #11631) — the feeder withholds its beat once the host unit's last good run is more than 27 h old, and
  the heartbeat pages 29 to 30 h after that run. It replaces the retired logs
  alert `soleur-luks-monitor-host-timer-dark-prd`, which could not see its once-a-day row. See the next section.
- **`betteruptime_monitor.app`** — a refused container (failed unlock) is a hard down.
- **Better Stack logs alert `soleur-workspaces-luks-deadman-fired-prd`** (#9045): an unattended dead-man fire.
  See the next section.

### Dead-man and abort triage (#9045)

Every abort writes one `SOLEUR_WORKSPACES_LUKS_DEADMAN … result=cutover_aborted outcome=<x>` row on
the `luks-monitor` tag, and the cutover run log echoes it. **Read that row first**; its `outcome`
says what `cleanup()` did:

`doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh --since 2h --grep SOLEUR_WORKSPACES_LUKS_DEADMAN`

A `rollback=true` dispatch that does not end `rolled_back` writes the same row with a trailing
`mode=rollback` field and fails its run. Read its `outcome` from the table below.

The drift reasons (the second column below) reach Sentry only, as `workspaces-luks-drift` events.
They all group into one Sentry issue (135268270); **never archive it**, or later reasons stop paging.
Read its latest event with `doppler run -p soleur -c prd -- bash scripts/sentry-issue.sh 135268270 --latest-event`.
Several reasons can fire in one abort, so the Better Stack outcome row is the authoritative summary.

| `outcome=` | What `cleanup()` did | Action |
|---|---|---|
| `pre_freeze` | The run died before the freeze. Nothing changed; no timer was left armed. | Read the `die` line in the run log; fix and re-dispatch. |
| `arm_aborted` | The timer was created but never reached `waiting`; `cleanup()` disarmed it. Check for a `result=disarm_failed` row: if present, a timer may still be live, so watch for `result=fired` within 30 min before re-dispatching. | Re-dispatch once. |
| `rolled_back` | A pre-canary abort. The plaintext volume is mounted alone and the mapper is closed. Lossless. | Confirm with `gh workflow run workspaces-luks-verify.yml`, find the cause, re-cut. |
| `rollback_stacked` | The plaintext mount landed on top of another mount, or the mapper stayed open. | Do not re-dispatch. Run the verify workflow, then file a tracked issue with its output. |
| `rollback_remount_failed` | The plaintext remount failed, or was not attempted. The app was left down on purpose, rather than started on the bare root-disk directory. The row carries `recorded=<PLAINTEXT_DEV> recorded_status=<status>`: `ok` means the record was an intact ext4 and the `mount` itself failed; any other value means nothing was mounted because the record is not an intact restore source (read the values as in the `refused_plaintext_record_gone` row below). | Run the verify workflow. `recorded_status=ok`: dispatch `rollback=true` once more; if it fails again, escalate. Any other `recorded_status=`: do NOT re-dispatch (the record will not change); halt and escalate. |
| `post_canary_luks_retained` | A post-canary abort. The app and writers were restarted on the LUKS mount. | **Fix-forward only.** Diagnose the reason (Sentry) from the run log. `rollback=true` would strand every write since `docker start` (ADR-119 §(b)). |
| `post_canary_restart_failed` | The roll-forward re-asserted the mapper, but `docker start` failed. Its first stderr line is on the `detail=` field. | Fix the container error, then restart through a normal deploy: `gh workflow run web-platform-release.yml`. |
| `post_canary_mount_not_mapper` | After a post-canary abort `/mnt/data` was no longer the mapper, so the app and writers were STOPPED. | Run the verify workflow. The only off-host recovery is `rollback=true -f rollback_ack_luks_writes=true` (plaintext, strands LUKS writes); re-mounting the mapper has no dispatch path. Escalate before choosing. |
| `clean_stray`, `dry_run` | A `clean_stray` or dry run aborted. Nothing was cut over. | Read the run log. |
| `wipe_retired` | `CONFIRM_WIPE` reached the host with a value other than unset or `0` after the wipe mode was retired (#6604 step 7, PR #9348). The tombstone wrote this one row, dropped the EXIT trap and died before any mutation. It emits no drift event, so nothing reaches Sentry. Nothing was touched. (Until that PR, the retired wipe's abort row was `outcome=wipe_aborted mode=wipe`; it is in git history at `59abf6a76c`.) | Nothing in this repo delivers `CONFIRM_WIPE` any more: find what set it (a stale branch's workflow, an edited `.env`) and remove it. Never restore the wipe mode: PR #9348 merges only after D deleted the plaintext volume (destruction record). |
| `refused_plaintext_wiped` (`why=marker`; `mode=rollback`, or no `mode` from `cleanup()`'s freeze arm) | A rollback was attempted after the wipe began (`PLAINTEXT_WIPE_BEGUN`/`PLAINTEXT_WIPED` persisted); the copy may be partly or wholly zeroed. `rollback()` refused as its first act: nothing was touched. With no `mode=` (from `cleanup()`), the app and the writers are DOWN on a LUKS copy that has not passed the host canary. | Do not roll back. Fix forward on the LUKS volume. (Before PR #9348, an interrupted wipe was re-dispatched here and resumed on `arm=re_zero`; after step 7 the wipe is complete and its mode is retired.) With no `mode=`: run the verify workflow and escalate at once, the users are offline. `rollback_ack_luks_writes` does not override this. |
| `refused_plaintext_record_gone` (`why=plaintext_dev_gone`; `mode=rollback`, or no `mode` from `cleanup()`'s freeze arm) | `/mnt/data` is the mapper and the recorded `PLAINTEXT_DEV` is not an intact ext4, with NO wipe marker: this is never a wipe. `recorded=` is the record; `recorded_status=` is what it read (`absent`, `none`, `crypto_LUKS` or another type, `is_mapper`, `invalid`, `blkid_absent`, `blkid_error_<rc>`; see the Rollback section). The intact plaintext may still be attached under another kernel name. `rollback()` refused as its first act: nothing was touched. With no `mode=` (from `cleanup()`), the app and the writers are DOWN on a LUKS copy that has not passed the host canary. | **Halt and escalate on every `recorded_status=`** (drift, a detach or a failed probe). Do not append `PLAINTEXT_DEV=` on the host. With no `mode=`: run the verify workflow first, the users are offline. `rollback_ack_luks_writes` does not override this. |

`abnormal_exit=1` on the row means the script was killed (SIGPIPE from a dropped SSH connection,
TERM or HUP) rather than dying on a check. Treat the outcome the same way, and look for the network
or runner cause.

Other dead-man rows and reasons:

| Signal | Meaning | Action |
|---|---|---|
| `result=arm_refused reason=already_armed` or `reason=fire_in_progress` / `deadman_already_armed` | A timer was already waiting, or a fire was live, when the cutover tried to arm. Nothing was frozen. | Do not re-dispatch while a timer waits; it fires within 30 min. Read the `result=fired` row, then the next verify run, then re-dispatch. |
| `result=arm_refused reason=plaintext_dev_unrestorable` / `deadman_arm_failed` | The arm found no restorable recorded plaintext. `detail=<status>:<record>` names what the record read: `invalid:<value>` (no `PLAINTEXT_DEV`, or an unsafe one), `is_mapper:<dev>`, `absent:<dev>`, `none:<dev>`, `<fstype>:<dev>`, `blkid_absent:<dev>` or `blkid_error_<rc>:<dev>`. A dead-man armed then would unmount `/mnt/data` and restore nothing. Nothing was frozen. | **Not** "re-dispatch once": the record will not change, so a re-dispatch refuses the same way. Halt and escalate with the `detail=` value; do not re-dispatch the cutover until the record is explained. |
| `result=arm_failed reason=systemd_run_refused` or `reason=timer_not_waiting` / `deadman_arm_failed` | `reason=systemd_run_refused`: nothing was created (`detail=` carries `systemd-run`'s first stderr line). `reason=timer_not_waiting`: see `arm_aborted` above. | Re-dispatch once (these two reasons only); the stale unit was already cleared. On a second failure, file a tracked issue with the `detail=` value. |
| `result=disarm_failed` / `deadman_disarm_failed` | `check=a`, `b` or `c` at the host canary: the disarm could not be verified, so the run rolled back before `docker start`. `check=fire_stuck` in a rollback: a fire ran past the wait. | Read the outcome row, run the verify workflow. |
| `deadman_fired_before_disarm` | A fire raced the host-canary disarm and reverted the mount. The run rolled back before `docker start`. | As above. |
| `host_canary_workspace_count_mismatch`, `host_canary_baseline_missing` | The mounted copy's workspace count does not match what G3 counted in this run, or G3's count is missing. Rolled back before `docker start`. | Do not re-dispatch blind. Compare the counts in the run log, then file a tracked issue. |
| `workspace_count_persist_failed` | G3 could not count the copy's workspaces. The run stopped at G3 and rolled back, losslessly. | Read the counter error in the run log; fix, then re-dispatch. |
| `rollback_refused_post_cutover` | A `rollback=true` dispatch found the cutover had succeeded (or could not read the LUKS header to rule it out), and refused. This holds whatever `/mnt/data` is mounted on: the row reads `outcome=refused_post_cutover mode=rollback mount_src=<source or none>`. `mount_src=none` after a reboot means the boot unlock failed. Nothing changed. | Only re-dispatch with `-f rollback_ack_luks_writes=true` once the stranded LUKS writes have a reconciliation plan. |
| `cutover_aborted_post_canary` (fatal) | Any post-canary abort, including tail failures (`green_run_degraded_queue`, `luks_monitor_timer_enable_failed`), not only an app failure. | Read the outcome row. |
| `result=not_armed prior=<substate>` | A `rollback=true` dispatch found no timer armed by this run; `prior` is what it stopped. | None, unless `prior=waiting` (a stale armed timer was cancelled). |
| `result=already_disarmed` | A rollback found this run had already disarmed its timer at the host canary. | None. |
| `result=fail reason=refused_plaintext_wiped` (dead-man, `why=marker`) or `result=fail reason=refused_plaintext_record_gone` (dead-man, `why=plaintext_dev_gone recorded=<dev> recorded_status=<type>`) | A dead-man FIRE found a wipe marker, or the mapper mounted with the recorded plaintext device no longer reading ext4 (read `recorded_status=` as in the `refused_plaintext_record_gone` row above: never a wipe), and exited before any stop/umount/close. The live mount is untouched. A fire that restores logs `result=ok reason=plaintext_remounted mount_source=<dev>`. **A fire during a cutover leaves the app and the writers DOWN**: the freeze stopped them, the refusal restarts nothing, and the LUKS copy has not passed the host canary. | Run the verify workflow; halt and escalate at once (users stay offline until this is resolved). After the host canary a dead-man should never be armed on a cut-over host. |
| Alert `soleur-workspaces-luks-deadman-fired-prd` (`result=fired`) | An unattended dead-man fire stopped the app and remounted plaintext, for example after a SIGKILL of the host script mid-freeze. The alert auto-resolves after 10 quiet minutes; that does not mean anything was reconciled. | Match the fire's time against `gh run list --workflow=workspaces-luks-cutover.yml` to find the run that armed it. Run the verify workflow. Writes made on the LUKS volume **before** the fire are stranded there: reconcile them before any re-cut. |

### Host-timer liveness alert (#8706)

**What it means.** The Better Stack heartbeat `soleur-luks-monitor-host-timer-prd`
(`betteruptime_heartbeat.luks_monitor_host_timer` in `apps/web-platform/infra/uptime-alerts.tf`) withholds its
beat once web-1's last PASSING host run is more than 27 h old, and pages 29 to 30 h after that run. It is born `paused = true` behind
`lifecycle { ignore_changes = [paused] }`, so it pages only after the owner unpauses it; until then the
feeder logs `deadman heartbeat luks-monitor-host-timer is UNARMED (paused)` on every run.

**How it is fed (#11631).** The retired logs alert `soleur-luks-monitor-host-timer-dark-prd` read
`Current value: 0` through 33 nights of passing rows, so it could not see its once-a-day row. The heartbeat
replaces it. `.github/workflows/scheduled-deadman-heartbeat-feeder.yml` runs hourly and calls
`scripts/deadman-heartbeat-feeder.sh luks-monitor-host-timer`. The script asks the Logs archive (`remote()`
UNION `s3Cluster`) whether a qualifying row exists in the trailing 97200 s (27 h) and beats the heartbeat only
if one does. No qualifying row means NO beat: the heartbeat times out and pages. The feeder never beats
`/fail`. Predicate: an `OK: /mnt/data is LUKS-backed` row from `_SYSTEMD_UNIT=luks-monitor.service` with
`host_name = 'soleur-web-platform'`. Period 3600 s plus grace 7200 s means the page lands about 3 h after the
last beat (page threshold 3600 + 7200 = 10800 s). The last beat falls in the final hour of the 27 h window
that opens on the last qualifying row, so the page arrives between 29 h and 30 h after that row.

It is scoped to web-1. web-2 (`host_name = 'soleur-web-2'`) ships to the same Logs source, so the
host conjunct keeps web-2 rows out. The verify job's rows never carry the unit, so they cannot keep
it quiet either.

The page does not say why the passing row is missing. Three causes read the same:

- the host unit did not run, or died before it logged;
- the host unit ran and FAILED an assert, for example `FAIL (device_not_luks)` or
  `FAIL (not_mounted)`, which can mean encryption is **not** in effect;
- no row reached Better Stack (a Vector or Logs-source outage).

A fourth cause is not about the host at all: the feeder itself did not run. Both web hosts' watchdog clocks
dispatch it, with a GitHub `schedule:` fallback, so a dark clock can false-page this heartbeat.

**Triage order.**

0. Check the feeder first, before touching the timer: the Sentry monitor `scheduled-deadman-heartbeat-feeder`
   and `gh run list -a --workflow scheduled-deadman-heartbeat-feeder.yml`. Both dead-man heartbeats share one
   script, one workflow run, one Sentry monitor and one Logs credential, so a feeder outage pages both. Two
   causes sit upstream of every verdict below and say nothing about the host: a GitHub Actions or GitHub App
   token incident (the watchdog clock mints an installation token per dispatch, so no run, or a late run, means
   no beat), and an expired or rotated `BETTERSTACK_QUERY_*` (Logs read) or `BETTERSTACK_API_TOKEN_READONLY`
   (heartbeat lookup) credential (verdict `query_failed` or `beat_failed`). The feeder workflow reads these from
   **GitHub repository secrets** (`secrets.BETTERSTACK_QUERY_HOST`, `_USERNAME`, `_PASSWORD` and
   `secrets.BETTERSTACK_API_TOKEN_READONLY`), not from Doppler `prd_terraform`, so a rotation in Doppler alone does
   not reach the feeder: the GitHub repo-secret copy must be updated too. Read-only check that all four names are
   present and when each was last set: `gh secret list` (it prints names and update times, never values; never
   print a value).
1. Read the run's marker line:
   `gh run view <id> --log | grep 'deadman-feeder: target=luks-monitor-host-timer'`, and decode its `verdict=`
   with the table below. A GitHub run that shows success only means the feeder executed; the run conclusion is
   success by design, so read the marker, not the green tick.
2. Decode the FAIL row (step D) via `scripts/betterstack-query.sh`.
3. Re-fire the installer (step E).

**Verdict dictionary** (the same dictionary serves `target=claude-cost-capture`). Each run prints one
`deadman-feeder: target=<t> verdict=<v> ...` line per target; the workflow loops over both targets.

| `verdict=` | exit | Means | Says anything about the host? |
|---|---|---|---|
| `beat` | 0 | A qualifying row exists in the window and the heartbeat was beaten (`http=2xx`). | Healthy. |
| `qualifying_row_heartbeat_paused` | 0 | A qualifying row exists but the heartbeat is still paused, so nothing was sent. **UNARMED**: nothing can page for this target until the owner arms it ([Arming the dead-man heartbeats](#arming-the-dead-man-heartbeats-11631)). | Healthy row, no paging surface. |
| `no_qualifying_row` | 3 | The window (hot plus archive) holds no qualifying row. This is the legitimate page: the host, the shipper or the Logs source is dark. | Yes: read `any_rows` and `fail_rows` below. |
| `query_failed` | 3 | The Logs warehouse could not be read or its answer could not be parsed (`reason=secret_unset`, `helper_status class=auth`, `malformed`, ...). A credential or helper fault. | No. |
| `beat_failed` | 4 | A qualifying row existed but the heartbeat could not be resolved or the ping was not accepted (`reason=api_token_unset`, `api_token_malformed`, `api_unreadable`, `api_malformed`, `heartbeat_not_unique`, `paused_not_boolean`, `url_shape`, `http_status`). `paused_not_boolean` is the one that matters for arming: the lookup returned the heartbeat but its `paused` attribute is absent or not a JSON boolean, so the feeder refuses to guess whether it is armed and sends nothing. | No: the host is fine. |
| `no_marker` | workflow-synthesised | The feeder died before printing any marker (script missing, parse error); the line carries `rc=` and `out_bytes=`. | No. A feeder bug. |
| `trap_remapped` | 3 | The feeder exited with a status outside its contract, or with 0 that no verdict produced; the exit trap rewrote it to 3 (`rc=` is the original). | No. A feeder bug. |
| `unreachable` | 3 | The decision flow fell through without any verdict (the feeder prints `CANNOT BEAT: the decision flow fell through`). | No. A feeder bug. |
| `usage` / `xtrace_refused` | 64 / 78 | A bad target argument, or shell tracing was refused because a live credential is set. | No. |

Besides verdict lines, the workflow can print `deadman-feeder: target=<t> dropped_lines=<n>`: the feeder printed
`<n>` lines that claimed the marker prefix but did not match the marker shape, so the workflow counted them and
printed none of their text. Treat it as a feeder bug (a marker with an unexpected shape), not a host finding.

Exit codes are 0 (`beat` or `qualifying_row_heartbeat_paused` only), 3 (withheld), 4 (a beat could not be
delivered), 64 (usage) and 78 (tracing refused). `paged=1` appears only on `beat_failed reason=heartbeat_not_unique`
and means the uptime API reports a further result page, so the feeder refused to trust page 1.

**Reading the funnel counts** (counts only; no row text is ever printed). `n` is the number of qualifying rows
in the window; `newest_dt` is the newest qualifying row's timestamp, or `none` when `n=0`. On a luks
`no_qualifying_row` two diagnostics run over the same window:

- `any_rows=0`: no `luks-monitor.service` row at all from web-1, so the host timer did not run, or the
  shipper or Logs source is dark. Start at step A, then B.
- `any_rows>0`, `fail_rows>0`: the probe ran and failed an assert. Encryption may NOT be in effect. Step D.
- `any_rows>0`, `fail_rows=0`, `n=0`: the unit logged but never logged a passing `OK: /mnt/data is
  LUKS-backed` line or a `FAIL (` line in the window, for example it died between start and verdict, or the
  message text changed. Read the unit's raw rows with `scripts/betterstack-query.sh` (step B) before anything
  else.
- `unknown`: that diagnostic query itself failed. It never changes the verdict.

**Cost target (`claude-cost-capture`).** There is no `any_rows` control for it. On `no_qualifying_row`, read the
cost-marker section of `betterstack-log-query.md` ([Querying Anthropic cost
markers](./betterstack-log-query.md#querying-anthropic-cost-markers-soleur_claude_cost--_daily)) to see
whether the emitter, Vector or the field moved. The page text for this target must not be read as "the host is
dark": the cost markers come from Inngest-executed crons, so a quiet scheduler or a credit-probe outage reads
the same. An out-of-credit day stays quiet by design (the predicate also accepts a credit-probe RED row).

So do not assume the volume is fine. The daily verify job still checks the volume on its own schedule.

**On the merge that creates it**, the heartbeat is born paused, so nothing can page, and the merge also destroys
the old logs alert: until the owner arms it there is NO paging dead-man for the luks host timer. An unarmed state
shows only as a run annotation and step summary on the feeder run, and as `verdict=qualifying_row_heartbeat_paused`.
Arming (unpause plus read-back) is the owner-gated block
[Arming the dead-man heartbeats](#arming-the-dead-man-heartbeats-11631).

**Read it back without a dashboard.** Raw SQL through `scripts/betterstack-query.sh`, hot and
archive together:

```bash
doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh "
SELECT toDate(dt) AS day,
       JSONExtractString(raw, 'host_name') AS host,
       JSONExtractString(raw, '_SYSTEMD_UNIT') = 'luks-monitor.service' AS host_unit,
       multiIf(JSONExtractString(raw, 'message') LIKE '%OK: /mnt/data is LUKS-backed%', 'ok',
               JSONExtractString(raw, 'message') LIKE '%FAIL (%', 'fail', 'other') AS kind,
       count() AS n
FROM (SELECT dt, raw FROM remote(\$BS_TABLE)
      UNION ALL SELECT dt, raw FROM s3Cluster(primary, \$BS_TABLE_S3) WHERE _row_type = 1)
WHERE dt > now() - INTERVAL 3 DAY
  AND JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = 'luks-monitor'
GROUP BY day, host, host_unit, kind ORDER BY day FORMAT JSONEachRow"
```

The feeder's predicate is the `host=soleur-web-platform, host_unit=1, kind=ok` cell.

**Decode, one no-SSH action per branch.** The cells hold prose only. The commands are in the steps
below the table.

| What the query shows | Where the fault is | Action |
|---|---|---|
| No `luks-monitor` rows at all, in any cell | Most likely the log pipeline (Vector or the Logs source), not the host | Check the pipeline first: step A |
| `host_unit=0` rows present (the verify job), no `host_unit=1` rows | The host unit is not running, or it dies before it logs | Read the unit state (step B), then find the installer's last fire (step C) |
| `host_unit=1` rows, `kind=fail` | The host probe runs and fails an assert | Read the reason from the row (step D) |
| `host_unit=1` rows, `kind=ok`, inside the last 27 h, heartbeat still down | Nothing: the next hourly feeder run beats it, and the incident auto-resolves | None. Re-read in an hour |

#### Step A: is the pipeline alive?

Count rows from another web-1 unit in the last hour. `web-git-data-probe` runs every minute on
web-1 and logged 118 rows in one hour on 2026-09-27, about two a minute.

```bash
doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh "
SELECT count() AS n
FROM (SELECT dt, raw FROM remote(\$BS_TABLE)
      UNION ALL SELECT dt, raw FROM s3Cluster(primary, \$BS_TABLE_S3) WHERE _row_type = 1)
WHERE dt > now() - INTERVAL 1 HOUR
  AND JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = 'web-git-data-probe'
  AND JSONExtractString(raw, 'host_name') = 'soleur-web-platform'
FORMAT JSONEachRow"
```

Zero means the pipeline, not the host. Query mechanics and the credential traps are in
[`betterstack-log-query.md`](./betterstack-log-query.md). If a merged Vector config change never
reached web-1, see [`vector-redeliver.md`](./vector-redeliver.md). The verify job's own run log
still shows its verdict meanwhile:

```bash
gh run list --workflow=workspaces-luks-verify.yml --limit 3
```

#### Step B: read the unit state without SSH

The verify job prints one `[unit-state]` block per unit. Each block starts with `Id=`.

```bash
gh workflow run workspaces-luks-verify.yml
# when it has finished:
id=$(gh run list --workflow=workspaces-luks-verify.yml --event workflow_dispatch --limit 1 --json databaseId --jq '.[0].databaseId')
gh run view "$id" --log | grep -F '[unit-state]' | head -20
```

| Unit | Healthy between runs | Never installed |
|---|---|---|
| `luks-monitor.timer` | `UnitFileState=enabled`, `ActiveState=active` | `LoadState=not-found` |
| `luks-monitor.service` | `UnitFileState=static`, `ActiveState=inactive`, `Result=success`, `ExecMainStatus=0` | `LoadState=not-found` |

The service reads `static` because it has no `[Install]` section: the timer starts it.

When no host row landed, read the state like this:

| Reading | Meaning | Action |
|---|---|---|
| Timer `LoadState=not-found` | Never installed | Find the installer's last fire (step C) |
| Timer `UnitFileState=disabled`, or `ActiveState` not `active` | Something changed it after install | Re-fire the installer (step E) |
| Service `Result=exit-code` with `ExecMainStatus=203` | systemd could not exec the binary: it is missing or not executable | Re-fire the installer (step E). It re-copies and chmods both binaries |
| Service `ExecMainStatus` 1 or 3, and a FAIL row exists | A normal assert failure | Step D |
| Service `ExecMainStatus` not 0, and no FAIL row | The probe died before it logged | File a tracked issue with the `[unit-state]` lines. The verify job runs the same script, so compare its verdict |

A failed mount dependency is no longer a cause. The service only orders after the mount
(`After=local-fs.target mnt-data.mount`) and never pulls it in, so an unmounted `/mnt/data` gives a
`FAIL (not_mounted)` row, not a unit that never started.

#### Step C: find the apply run where the installer last fired

The latest apply run usually shows nothing. The installer fires only when its trigger changes:
the hashes of its four files, or the hash of the DSN. Find the last merge that changed one of the
files:

```bash
git fetch origin main
sha=$(git log -1 --format=%H origin/main -- apps/web-platform/infra/luks-monitor.sh apps/web-platform/infra/workspaces-luks-emit.sh apps/web-platform/infra/luks-monitor.service apps/web-platform/infra/luks-monitor.timer)
gh run list --workflow apply-web-platform-infra.yml --commit "$sha" --json databaseId,conclusion,createdAt
gh run view <id> --log | grep -E 'luks_monitor_install|UnitFileState|NextElapse|envfile after|exited with status' | head -60
```

A DSN rotation in Doppler also re-fires it, with no git change. Then read the first apply run after
the rotation instead. No installer output at all can also mean the SSH stage was green-skipped
(`ssh_apply_skip`, #7539). That run is green and delivers nothing.

A red installer step prints `exited with status <n>`. Decode it:

| Exit | Meaning | No-SSH action |
|---|---|---|
| 10 | `SENTRY_DSN` in Doppler `prd_terraform` is empty | Set it, then re-run (step E). The timer is not armed by this fire (see below) |
| 11 | `/etc/default/luks-monitor` is a symlink | No Terraform channel repairs this. The writer refuses by design and nothing else rewrites the path. File a tracked issue |
| 12 | `/etc/default/luks-monitor` exists but is not a regular file | Same as 11: no Terraform channel repairs it. File a tracked issue |
| 13 | The env file could not be read | Re-run once (step E). If it repeats, file a tracked issue |
| 14 | The rewrite would have changed a line other than the DSN line | Nothing was written. Re-run once. If it repeats, file a tracked issue |
| 15 | The result would not hold exactly one DSN line | Nothing was written. A writer bug: file a tracked issue |
| 16 | The final move failed | Usually a full or read-only `/etc`. Read the `df -P /etc` line the installer prints before the write, free space, then re-run |
| 17 | A cutover freeze is live: `workspaces-luks-deadman.timer` reads `SubState=waiting` | Wait for the cutover to finish, or for the dead-man to fire or be disarmed, then re-run with `manual-rerun` (step E). The installer refuses rather than arm a probe mid-freeze. An aborted cutover that leaves the dead-man armed is tracked in #9045 |

Every red exit taints the resource, so the next apply re-fires it.

#### Step D: read the reason from the row

Take the reason from the Better Stack row, not only from Sentry. If the Sentry send failed, the
row is the only record.

```bash
doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh "
SELECT dt,
       JSONExtractString(raw, '_SYSTEMD_UNIT') = 'luks-monitor.service' AS host_unit,
       substring(JSONExtractString(raw, 'message'), 1, 160) AS msg
FROM (SELECT dt, raw FROM remote(\$BS_TABLE)
      UNION ALL SELECT dt, raw FROM s3Cluster(primary, \$BS_TABLE_S3) WHERE _row_type = 1)
WHERE dt > now() - INTERVAL 3 DAY
  AND JSONExtractString(raw, 'SYSLOG_IDENTIFIER') = 'luks-monitor'
  AND JSONExtractString(raw, 'host_name') = 'soleur-web-platform'
  AND (JSONExtractString(raw, 'message') LIKE '%FAIL (%'
       OR JSONExtractString(raw, 'message') LIKE '%SOLEUR_WORKSPACES_LUKS_SEND_FAILED%')
ORDER BY dt DESC LIMIT 20 FORMAT JSONEachRow"
```

| Row | Meaning | Action |
|---|---|---|
| `FAIL (<reason>)` | The host probe failed that assert | The [verdict table](#verdict--operator-action) above, row `<reason>`. The Sentry `workspaces-luks-drift` event carries the same `reason` field when the send worked |
| `SOLEUR_WORKSPACES_LUKS_SEND_FAILED reason=no_dsn drift_reason=<slug>` | A drift event was lost: no DSN resolved on the host | The `SOLEUR_SENTRY_DSN=` line is missing. Read the installer's `envfile after` counts (step C); expect `SOLEUR_SENTRY_DSN=1`. If it reads 0, re-fire the installer. Treat `<slug>` as the lost drift reason and decode it in the verdict table |
| `SOLEUR_WORKSPACES_LUKS_SEND_FAILED reason=send_failed drift_reason=<slug>` | A drift event was lost: the Sentry POST failed | Sentry ingest or web-1 egress. Decode `<slug>` in the verdict table, since Sentry never got it |

Both `SEND_FAILED` rows also page through `soleur-monitor-send-failed-prd`
([`monitor-send-failed-alert.md`](./monitor-send-failed-alert.md)).

#### Step E: re-fire the installer

Do NOT use `gh run rerun --failed`. It re-applies the old commit's bytes for every SSH target, which
can roll other installers back. Dispatch against `main` instead:

```bash
gh workflow run apply-web-platform-infra.yml --ref main -f apply_target=manual-rerun -f reason='#8706 re-fire tainted luks_monitor_install'
```

This re-fires the installer only if it is tainted, that is, its last SSH step was red. A green,
untainted installer does not re-fire. Then a re-fire needs a merge that changes a trigger file. The
harmless one is a comment line in `apps/web-platform/infra/luks-monitor.timer`.

**A bad `SENTRY_DSN` rotation.** An empty value fails only `terraform_data.luks_monitor_install`,
with exit 10 in its SSH step. The DSN writer runs before the arming step, so that fire does not arm
the timer. The apply stays red until the DSN is fixed, and on a first install the host-timer heartbeat
(once unpaused) pages 29 to 30 h after the last passing row. A malformed non-empty value fails the resource's precondition at plan time.
That stops the WHOLE per-merge SSH apply step, every SSH-provisioned resource in it, including the
boot-token delivery on a rotation merge, until the DSN in Doppler `prd_terraform` is fixed. The
reasoning is in ADR-119's 2026-09-27 addendum.

**Acceptance criteria for the rebuilt heartbeat (#11631).** Issue #8706 itself closed on 2026-10-01 (the old
three-consecutive-date follow-through script `scripts/followthroughs/luks-monitor-host-timer-8706.sh` was deleted
by #10371; do not look for it). The heartbeat that replaced the retired alert is accepted under #11631 when all
of these hold after the owner arms it ([Arming the dead-man heartbeats](#arming-the-dead-man-heartbeats-11631)):

1. a feeder run whose marker reads `deadman-feeder: target=luks-monitor-host-timer verdict=beat`, and a second
   such run one slot later;
2. the heartbeat `soleur-luks-monitor-host-timer-prd` reads `status=up paused=false` through
   `GET /api/v2/heartbeats` with the read-only token;
3. the measured archive lag (Phase 0.2, 66 minutes) still sits under the window slack (27 h window vs a 24.5 h
   legitimate gap, so 2.5 h). The 24.5 h is derived from `apps/web-platform/infra/luks-monitor.timer`:
   `OnCalendar=daily` with `RandomizedDelaySec=1800`, so two consecutive nightly rows are at most 24 h + 1800 s apart.

## Arming the dead-man heartbeats (#11631)

`betteruptime_heartbeat.luks_monitor_host_timer` (`soleur-luks-monitor-host-timer-prd`) and
`betteruptime_heartbeat.claude_cost_capture` (`soleur-claude-cost-capture-prd`) ship born paused (period 3600,
grace 7200, `ignore_changes = [paused]`). The merge that creates them also destroys the retired logs alerts, so
**until a heartbeat is armed there is NO paging dead-man for its target**. Arming is the owner's step, one target
at a time, and nothing in this section is run by an agent on its own: every command marked **production write**
needs the owner to authorize THAT exact command as a unit (a menu answer or an earlier approval does not
authorize it). Reads use the read-only token (`hbr`). The writes are: the unpause, the forced workflow dispatch,
the rollback re-pause that the unpause block runs on its own, the manual re-pause, and the incident resolve. The
write token is read inside `doppler run` and sent through `curl --config -`, so nothing here prints a token or a
ping URL.

**How to run the blocks.** Every block below is a COMPLETE script. Nothing carries from one block to the next: a
block run by the Monitor tool, or in a fresh terminal, starts with none of the variables or functions of any other
block. So:

1. Paste the **helpers block** below at the top of each block's text (the line `# --- paste the helpers block
   here ---` marks the spot), and save the combined text as a script file in a scratch directory outside the
   repository (for example `arm-3.sh`). The helpers block contains no secret.
2. Run it as a script with the target in the environment: `TARGET=luks-monitor-host-timer bash arm-3.sh` (or
   `TARGET=claude-cost-capture`). Never `source` a block into an interactive shell: the blocks use `exit` and
   `set -u`, which would kill or poison it.
3. Step 3 runs only through the Monitor tool (`TARGET=<target> bash arm-3.sh`), never as a foreground call.
4. Step 4 also needs `ARM_AT`: set it to the value step 3 printed (`ARM_AT=<printed value> TARGET=<target> bash
   arm-4.sh`).

<!-- lint-infra-ignore start -->

Helpers block (parameters, the two token helpers, and the read-only lookup of the heartbeat id by exact name; the
id is not known before the merge-triggered apply creates the heartbeat, and the lookup must find exactly one
match; the listing's `url` attribute is deliberately not selected):

```bash
set -uo pipefail
: "${TARGET:?set TARGET=luks-monitor-host-timer or claude-cost-capture}"
case "$TARGET" in
  luks-monitor-host-timer) HB_NAME=soleur-luks-monitor-host-timer-prd; INCIDENT=1023423999; ISSUE=11048 ;;
  claude-cost-capture)     HB_NAME=soleur-claude-cost-capture-prd;     INCIDENT=1020832712; ISSUE=11049 ;;
  *) echo "unknown target" >&2; exit 64 ;;
esac
WORKFLOW=scheduled-deadman-heartbeat-feeder.yml
MARKER="deadman-feeder: target=$TARGET verdict="
PERIOD=3600; GRACE=7200
DEADLINE=$((PERIOD + GRACE - 900))    # 9900 s, NOT 10800: the last 900 s are the rollback margin
BASE=https://uptime.betterstack.com/api/v2/heartbeats
hbr() { doppler run -p soleur -c prd_terraform --silent -- bash -c '
  [[ "$BETTERSTACK_API_TOKEN_READONLY" =~ ^[A-Za-z0-9._~+/=-]{20,}$ ]] || { echo "token shape refused" >&2; exit 78; }
  printf "header = \"Authorization: Bearer %s\"\n" "$BETTERSTACK_API_TOKEN_READONLY" | curl --disable --noproxy "*" -fsS --max-time 20 --config - "$@"' _ "$@"; }
hb() { doppler run -p soleur -c prd_terraform --silent -- bash -c '
  [[ "$BETTERSTACK_API_TOKEN" =~ ^[A-Za-z0-9._~+/=-]{20,}$ ]] || { echo "token shape refused" >&2; exit 78; }
  printf "header = \"Authorization: Bearer %s\"\n" "$BETTERSTACK_API_TOKEN" | curl --disable --noproxy "*" -fsS --max-time 20 --config - "$@"' _ "$@"; }
resolve_hb() {   # read-only; sets HB_ID and HB_STATE ("<status> <paused> <period> <grace>"); exits 3 unless exactly one match
  local live
  live="$(hbr "$BASE?per_page=250" | jq -r --arg n "$HB_NAME" '[.data[] | select(.attributes.name==$n)]
    | if length==1 then .[0] | [.id, .attributes.status, (.attributes.paused|tostring), (.attributes.period|tostring), (.attributes.grace|tostring)] | join(" ")
      else "NOT_UNIQUE matches=\(length)" end')" || { echo "LOOKUP: FAIL (the read failed)" >&2; exit 3; }
  case "$live" in NOT_UNIQUE*|"") echo "LOOKUP: FAIL ($live)" >&2; exit 3 ;; esac
  HB_ID="${live%% *}"; HB_STATE="${live#* }"
  echo "LOOKUP: id=$HB_ID state=$HB_STATE"
}
```

### 1. Preflight (read-only)

Paste the helpers block at the top. Both runs must be completed, must have a `workflow_dispatch` origin, and must
read `verdict=qualifying_row_heartbeat_paused` for the target: that proves the feeder is on `main`, the watchdog
clock is dispatching it, the predicate matches the live archive, and the archive lag is inside the window slack.
There is deliberately NO minimum spacing between the two runs: Phase 0.4 measured a minimum gap of 0 s between
watchdog-dispatched runs of the same workflow (a duplicate dispatch), so a spacing floor would reject real clock
behaviour, and nothing in the evidence derives one. What the check needs is two separate completed runs that each
read the paused verdict. A manual dispatch inside a slot makes the clock skip that slot (the clock counts a
`workflow_dispatch` run created inside the slot as covering it: `COVERING_EVENTS` in
`apps/web-platform/server/watchdog-dispatch-clock.ts`), and the check cannot tell a clock dispatch from a manual
one, so do not stack manual runs before this check.

```bash
# --- paste the helpers block here ---
n=0; fail=""
while IFS=$'\t' read -r rid created; do
  [ -n "$rid" ] || continue
  v="$(gh run view "$rid" --log | grep -o "${MARKER}[a-z_]*" | tail -1 | sed 's/.*verdict=//')"
  echo "$rid $created verdict=${v:-none}"
  n=$((n + 1))
  [ "$v" = qualifying_row_heartbeat_paused ] || fail="$fail run $rid verdict=${v:-none};"
done < <(gh run list --workflow="$WORKFLOW" --event workflow_dispatch --status completed --limit 2 \
           --json databaseId,createdAt --jq '.[] | [.databaseId, .createdAt] | @tsv')
[ "$n" = 2 ] || fail="$fail saw $n runs, expected 2;"
if [ -z "$fail" ]; then echo "PREFLIGHT 1: PASS"; else echo "PREFLIGHT 1: FAIL$fail"; exit 1; fi
```

If any run reads anything else, do not arm: `no_qualifying_row` means the target is currently dark (arming would
page at once), `query_failed` or `beat_failed` means a credential fault ([Verdict dictionary](#host-timer-liveness-alert-8706)).

### 2. Look the heartbeat up and read the incident (read-only)

Paste the helpers block at the top of each of the two blocks. The lookup must find exactly one heartbeat and report
`paused true 3600 7200`:

```bash
# --- paste the helpers block here ---
resolve_hb
[ "$HB_STATE" = "paused true 3600 7200" ] && echo "STATE: PASS (expected paused true 3600 7200)" || echo "STATE: not the unarmed shape: $HB_STATE"
```

Read the incident's state now, before anything is changed (read-only GET; field names beyond `resolved_at` are
UNVERIFIED, so absent ones print `absent`):

```bash
# --- paste the helpers block here ---
hbr "https://uptime.betterstack.com/api/v2/incidents/$INCIDENT" \
  | jq '.data.attributes | {name, started_at: (.started_at // "absent"), acknowledged_at: (.acknowledged_at // "absent"), resolved_at: (.resolved_at // "absent"), status: (.status // "absent")}'
```

### 3. Unpause (production write: authorize the exact command)

One script so that the unpause and its rollback live in one shell under a `trap`: a catchable interruption (INT,
TERM, HUP, a shell exit) rolls back to paused, while SIGKILL or a lost machine cannot. The poll deadline is
`DEADLINE = PERIOD + GRACE - 900 = 9900 s`, not 10800 s: an unfed unpause pages at period + grace = 10800 s
(assumed to count from the unpause, the same assumption the probe heartbeat's arm block makes for its own period +
grace), so the last 900 s are the rollback margin. Run it through the Monitor tool, never as a foreground call: it
can run for up to 165 minutes (9900 s). Paste the helpers block at the top of the SAME script text, and run it as
`TARGET=<target> bash arm-3.sh`. It needs a `doppler` login that can read `prd_terraform` and a `gh` login with
`actions: write`. Its writes are the unpause, the forced workflow dispatch, and (only on failure or interruption)
the rollback re-pause.

```bash
# --- paste the helpers block here ---
# production write: authorize the exact command
resolve_hb
[ "$HB_STATE" = "paused true 3600 7200" ] \
  || { echo "state is '$HB_STATE', expected 'paused true 3600 7200': refusing (a second arm, or drift)"; exit 3; }
patch() { hb -X PATCH -H 'Content-Type: application/json' --data-binary "{\"paused\":$1}" "$BASE/$HB_ID" | jq -e ".data.attributes.paused == $1" >/dev/null; }
rollback() {  # runs on EXIT, INT, TERM, HUP; three attempts, each confirmed by read-back
  trap - EXIT INT TERM HUP
  for t in 1 2 3; do patch true && { echo "ROLLED BACK (paused=true read back)"; exit 1; }; sleep 5; done
  echo "ROLLBACK FAILED - pause heartbeat $HB_ID now (Re-pause below); Better Stack pages within $((PERIOD + GRACE)) s of the unpause"; exit 2
}
trap rollback EXIT INT TERM HUP
patch false || { echo "unpause not confirmed by read-back"; exit 1; }      # exit fires the rollback trap
echo "ARM_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)"                               # anchor for the read-back (step 4)
gh workflow run "$WORKFLOW" --ref main \
  || echo "FORCED DISPATCH FAILED; waiting for the watchdog clock instead"  # force one real beat now
SECONDS=0; last=""
while [ "$SECONDS" -lt "$DEADLINE" ]; do
  s=$(hbr "$BASE/$HB_ID" | jq -r '.data.attributes.status') || s=read_failed
  [ "$s" != "$last" ] || [ $((SECONDS % 300)) -lt 30 ] && echo "$(date -u +%H:%M:%S) elapsed=${SECONDS}s status=$s"; last="$s"
  if [ "$s" = "up" ]; then trap - EXIT INT TERM HUP; echo "ARMED: status=up after ${SECONDS}s"; exit 0; fi
  sleep 30
done
echo "arm failed: status never reached up in ${SECONDS}s"; exit 1        # exit fires the rollback trap
```

Copy the printed `ARM_AT=` value: step 4 needs it. Exit codes: 0 armed (`status=up`), 1 rolled back or never reached
`up`, 2 ROLLBACK FAILED, 3 refused before any write (no unique heartbeat, or not in the unarmed shape). The forced
dispatch is a `workflow_dispatch` run, which the watchdog clock counts as covering the slot it lands in
(`COVERING_EVENTS`; verified by reading `watchdog-dispatch-clock.ts`), so the clock skips that slot's own dispatch
and the forced run stands in for it. Arm one target at a time and read back a second `verdict=beat` (step 4) before
treating the heartbeat as armed.

Re-pause (**production write: authorize the exact command**), for when the arm script printed `ROLLBACK FAILED`
or its shell died after the unpause. It is a complete script: paste the helpers block at its top and run
`TARGET=<target> bash repause.sh`.

```bash
# --- paste the helpers block here ---
# production write: authorize the exact command
resolve_hb
hb -X PATCH -H 'Content-Type: application/json' --data-binary '{"paused":true}' "$BASE/$HB_ID" \
  | jq -e '.data.attributes.paused == true' >/dev/null && echo PAUSED || { echo "RE-PAUSE NOT CONFIRMED"; exit 1; }
```

### 4. Read-back (read-only)

Paste the helpers block at the top and run `ARM_AT=<value step 3 printed> TARGET=<target> bash arm-4.sh`. It lists
the runs created since `ARM_AT` and reads the target's marker in each:

```bash
# --- paste the helpers block here ---
: "${ARM_AT:?set ARM_AT to the value the arm script printed}"
[[ "$ARM_AT" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || { echo "ARM_AT shape refused" >&2; exit 64; }
for rid in $(gh run list --workflow="$WORKFLOW" --created ">=$ARM_AT" --json databaseId --jq '.[].databaseId'); do
  echo "$rid $(gh run view "$rid" --log | grep -o "${MARKER}[a-z_]*.*" | tail -1)"
done
resolve_hb
```

Expect `verdict=beat http=2xx` on the forced run, a second `verdict=beat` on a LATER run (one slot later; re-run the
block an hour later), and the lookup line to read `state=up false 3600 7200`. A
`verdict=qualifying_row_heartbeat_paused` after the unpause means that run predates it; `beat_failed` means the
feeder cannot deliver (a `reason=paused_not_boolean` there means the heartbeat's `paused` attribute is not a JSON
boolean: the feeder refuses to guess and sends nothing, so the arm script times out and rolls back); and
`no_qualifying_row` means the target is dark and the heartbeat will page. Only after the second beat, a record PR
drops the `arming_pending: { tracking_issue: 11631 }` declaration from the target's row in
`plugins/soleur/lib/heartbeat-manifest.ts`; from its merge the nightly live reconcile's `fed-but-paused` class is
the safety net if anything re-pauses the heartbeat (a paused heartbeat makes the feeder exit 0, so the feeder
itself would not alert).

### 5. Resolve the stuck Better Stack incident (production write: authorize the exact command)

The retired logs alert's incident does not resolve itself once the alert is gone: incident `1023423999`
(luks, issue #11048) and incident `1020832712` (cost capture, issue #11049). Do this AFTER the read-back above,
so the open incident stays as the visible record until the replacement is proven. **The write token's scope for
this endpoint is UNVERIFIED**: `POST /api/v2/incidents/<id>/resolve` is from Better Stack's public API reference
and has not been exercised from this repo. If the API answers 401 or 403, stop, record the status code on #11631,
and do not retry with a different token without a fresh authorization. Paste the helpers block at the top and run
`TARGET=<target> bash resolve-incident.sh`.

```bash
# --- paste the helpers block here ---
# production write: authorize the exact command
hb -X POST -H 'Content-Type: application/json' --data-binary '{}' \
  "https://uptime.betterstack.com/api/v2/incidents/$INCIDENT/resolve" >/dev/null && echo "RESOLVE SENT" || { echo "RESOLVE FAILED"; exit 1; }
```

Then read the state again with the incident GET block in step 2 and require a non-`absent` `resolved_at`. The
incident mirror (`scheduled-betterstack-incident-mirror.yml`, ADR-298) comments and closes the mirrored
`[ci/betterstack-incident]` issue on its next run once the incident leaves the open set
(`gh issue view <ISSUE> --json state`, with `<ISSUE>` 11048 for luks or 11049 for cost).

<!-- lint-infra-ignore end -->
