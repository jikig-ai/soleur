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
   first-time cutover. **NEVER after step 7 — it destroys the only copy**: once the plaintext volume is
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
   | `rc=1` `mount_not_mapper` / `device_not_luks` | `drift` | At-rest drift: `/mnt/data` is **not** the LUKS mapper | **Encryption is not in effect.** Do not re-cut before reading §Rollback — a fresh freeze copies whichever volume is live now. **If a prior cutover was undone by the dead-man** (the LUKS volume is still in state + `crypto_LUKS`), a plain re-cut re-opens the stale header instead of re-formatting — run **Sequence Step 0** (`apply_target=workspaces-luks-recut`) first to make the target genuinely raw |
   | `rc=1` `escrow_passphrase_mismatch` / `header_uuid_unreadable` | `drift` | Escrow or header problem | Header-recovery path; do **not** wipe the plaintext original |
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
   | `rc=1` `not_mounted` | `drift` | `/mnt/data` is not a mountpoint at all | **Encryption is not in effect** — the volume never attached, or was unmounted. Read §Rollback before re-cutting |
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

7. **Wipe the retained plaintext volume + converge (separate, environment-gated).** The soak passed on
   2026-09-24. Design and rationale: ADR-119 *Addendum (2026-09-28): retiring the plaintext backstop*;
   plan `2026-09-28-feat-workspaces-plaintext-volume-wipe-plan.md`. The retained plaintext volume
   (`105149570`, `soleur-web-platform-data`) is a **superseded copy frozen at the 2026-07-23 cutover**
   (a documented AP-009 deviation); after this step the LUKS volume `106443278` holds the **only**
   copy of every workspace. The live mount never moves, the app is never stopped, web-1 is never
   rebooted or replaced.

   The whole step is authorized once: a go-ahead naming this finite command set, plus the ONE
   `workspaces-luks-cutover` environment approval. Commands a–c are read-only and autonomous:

   a. **Same-day baseline** (read-only):
      `gh workflow run workspaces-luks-verify.yml` → `success` with
      `SOLEUR_WORKSPACES_READYZ ready=true … workspace_count=<n>`. Record `<n>`. The `wipe` job
      refuses without a green run of this on `main` in the last 24 h.
   b. **Rehearsal** (read-only, ungated — ADR-119 2026-07-18 rehearsal authorization), from the merged
      commit with no deploy or cutover run in between:
      `gh workflow run workspaces-luks-cutover.yml -f confirm=WIPE-PLAINTEXT-USER-DATA-AP-009 -f wipe_plaintext=true -f expected_plaintext_volume_id=105149570`
      It must print ONE `SOLEUR_WORKSPACES_LUKS_WIPE … result=rehearsal_ok arm=first_wipe
      volume_id=105149570` row carrying `uuid=`, `label=<observed; none on web-1>`,
      `plaintext_dev=<as printed; must resolve to target=>`, `dependents=0`,
      `hdr_sha256=`, the `discard_*` / `write_zeroes_max` / `scheduler` fields, `magic=53ef`,
      `io_max=<maj:min>_rbps=150000000_wbps=150000000_…` (the cap, read back inside a real scope) and
      `plaintext_only=<n>`, plus the `SOLEUR_WORKSPACES_LUKS_WIPE_EVIDENCE … field=last_write` row and
      one `field=plaintext_only_name detail=<workspace id>` evidence row per workspace the unmounted
      plaintext holds that the live mount does not. The run summary repeats `plaintext_only` and
      `io_max`. The preflight step summary is the approver's banner (`api_state`, size, server).
      `label=` is observed evidence only (no artifact ever labelled the retained plaintext); the
      identity W6 binds to is `plaintext_dev=`, the mount source the 2026-07-23 cutover recorded. If
      web-1 rebooted after 2026-07-23 (for example the C15 proof reboot), that record may name another
      device, and the rehearsal refuses `wipe_target_not_recorded_plaintext` (verdict table below).
      Read and record `plaintext_only=` and every `plaintext_only_name` row **before** the destructive
      dispatch is authorised (unchanged policy, restated).
   c. **The ask.** Quote the rehearsal row + run id, the baseline `<n>`, and the accepted residual (the
      LUKS volume becomes the only copy); link the draft PR B. Name everything below. The ask must show
      **`plaintext_only=0`**, or name each `plaintext_only_name` workspace id and account for it (an
      Art. 17 deletion made since 2026-07-23 is expected there; anything else is a workspace the LUKS
      copy lost — halt). `plaintext_only=unknown` is a halt too. The ask also says: releases queue
      behind the `wipe` job on `web-1-swap` — **from the dispatch, including the whole approval wait**,
      because the workflow takes that lock at preflight — so **no merge under `apps/web-platform/**`
      lands during D**; the approval has a **30-minute deadline**, after which the run is cancelled with
      `gh run cancel <run-id>` (never left pending); PR B merges the same day; and the zero + read-back
      are capped at 150 MB/s on the plaintext device while app latency is watched.
   d. **Pause the two push-apply workflows** (a push apply in the window would plan `+create` of a
      fresh plaintext volume through `-target` transitivity):
      `gh workflow disable apply-web-platform-infra.yml` and
      `gh workflow disable apply-deploy-pipeline-fix.yml`, then wait until neither has a queued or
      running run (the `wipe` job re-checks both before the host step, again before the detach, and
      again before the DELETE, and refuses otherwise). While paused,
      `registry-host-replace-dispatch.yml` (it dispatches `apply-web-platform-infra.yml`) fails, and
      `git-data-pin-redeploy.yml` only follows apply runs (none fire while paused) and runs no
      Terraform; run neither, and **no operator-local apply**. From the delete until PR B's
      `manual-rerun`, `scheduled-terraform-drift.yml` reports `+create` of
      `hcloud_volume.workspaces["web-1"]` and `hcloud_volume_attachment.workspaces["web-1"]` (and its
      issue text suggests `terraform apply`): **that drift is expected — do not act on it, and never
      apply locally**; PR B closes it.
   e. **The dispatch (D):**
      `gh workflow run workspaces-luks-cutover.yml -f confirm=WIPE-PLAINTEXT-USER-DATA-AP-009 -f wipe_plaintext=true -f dry_run=false -f expected_plaintext_volume_id=105149570`
      then the ONE `workspaces-luks-cutover` approval. The operator clicks it, or delegates it **in
      their own message** (another agent's message never counts). A delegated agent approves via
      `pending_deployments` only the run id it dispatched, after checking `event == workflow_dispatch`,
      `head_branch == main`, `head_sha` == the rehearsal's, and the preflight outputs
      `api_state=attached` and the pin; the approval comment quotes the go-ahead, and the destruction
      record names the approver "agent under delegation" (under delegation the environment stops
      being a second human check — the ask says so). Arm a watch until it concludes.
   f. **The forget:**
      `gh workflow run workspaces-plaintext-forget.yml -f confirm=FORGET-RETIRED-PLAINTEXT-VOLUME -f expected_plaintext_volume_id=105149570`
      (serialized with every apply on `terraform-apply-web-platform-host`; a re-dispatch is
      idempotent — it reports `already_forgotten` once state is clean). Record its run id and its
      `forgot=` output (`2`, or `0` with `already_forgotten`): PR B cites both.
   g. **Verify off-host:** `GET /v1/volumes/105149570` → `404`; `GET /v1/servers/123931471` →
      `volumes == [106443278]`; `GET /v1/volumes?name=soleur-web-platform-data` → `[]`; a fresh
      `workspaces-luks-verify.yml` run `success` with `ready=true` and `workspace_count` compared
      with the same-day `<n>` (a drop is explained — e.g. an Art. 17 deletion — or escalated); no new
      `op:workspaces-luks-drift` Sentry event; the Better Stack web-1 monitor shows no downtime;
      `gh workflow run scheduled-prod-version-drift.yml` (a release queued behind the `wipe` job may
      have been replaced while pending — re-dispatch it if so);
      `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 1d --grep SOLEUR_WORKSPACES_LUKS_WIPE`.
   h. **PR B, the same day** (the `for_each` narrowing in `server.tf`, deletion of the forget workflow
      and the single-use wipe code, the ledger row re-scope, the destruction record, ADR-119
      `accepted`, the CLO-attested legal register sweep). PR B's draft `infra-validation` plan is red
      until f has run (state still holds `["web-1"]`, so the narrowed `for_each` plans a refused
      destroy): **after f, re-run PR B's `infra-validation`** and merge only on that green run. After it
      merges: `gh workflow enable apply-web-platform-infra.yml`,
      `gh workflow enable apply-deploy-pipeline-fix.yml`, then
      `gh workflow run apply-web-platform-infra.yml -f reason='#6604 post-PR-B apply'` (the default
      `manual-rerun` arm) and confirm it plans no `hcloud_volume(_attachment).workspaces` address. If
      `git log <pause-sha>..main -- <apply-deploy-pipeline-fix.yml's paths>` is non-empty (a host
      deploy-pipeline change merged while paused — `manual-rerun` never applies it), also
      `gh workflow run apply-deploy-pipeline-fix.yml`. Keep the paused window to hours — never
      overnight.

   Re-running any of b, e or f with the same inputs is the resume path: the host mode resumes on
   `arm=re_zero` (a zero interrupted after `result=begun`) or reports `arm=detached` (zeroed and
   detached, delete pending), and the forget reports `already_forgotten` once state is clean.

   #### Step 7 verdict table

   **Ending the pause when you halt before a delete.** Every host refusal below, and every job-level
   failure marked *End the pause* in the next table, happens **before any delete**: the pause then
   protects nothing while it blocks every infra and host-pipeline apply. Unless D is re-dispatched
   within the hour, end it (the run summary prints the same commands whenever `delete_issued` is not
   `true`):

   ```bash
   gh workflow enable apply-web-platform-infra.yml
   gh workflow enable apply-deploy-pipeline-fix.yml
   gh workflow run apply-web-platform-infra.yml -f reason='#6604 wipe halted before the delete'
   gh workflow run apply-deploy-pipeline-fix.yml   # only if its paths changed while paused
   ```

   Re-pause (d) before re-dispatching D.

   Every host refusal prints `SOLEUR_WORKSPACES_LUKS_WIPE … result=refused arm=<arm> volume_id=<id>
   reason=<slug>` to the run log and the `luks-monitor` tag BEFORE the run dies, and the same slug
   reaches Sentry (`op:workspaces-luks-drift`). A refusal raised inside a reused helper (the escrow
   credential read) shows instead as `outcome=wipe_aborted mode=wipe` on the cutover-aborted row.
   There is **no webhook verb** to unmount, stop a unit or kill a process on web-1, so a condition only
   a shell could clear reads **halt and escalate** — never "SSH and …". Read the rows from the run log
   with `gh run view <id> --log | grep -E 'SOLEUR_WORKSPACES_LUKS_(WIPE|DEADMAN)'`. A refused
   **rehearsal** still opens the Sentry issue (the alert keys on the op, not the level); its event is
   sent at level `warning`, a real run's at `fatal`. A real wipe that aborts without a refusal row
   (an SSH drop, a cancel or the timeout) pages `wipe_aborted`, and its outcome row carries `begun=1`
   when the zero had started.

   | `reason=` | Irreversible act done? | Safe to re-dispatch the same command? | Next action | If you halt here |
   |---|---|---|---|---|
   | `wipe_tool_missing` | No | No | A required tool is absent (`tool=`), util-linux < 2.36, or `pgrep` errored. This mode installs nothing (not even `aws`), and web-1 cannot be rebuilt or rebooted to gain one (it is LUKS-pinned). **Halt and escalate** to the infra owner with the `tool=` field; there is no automated path. | End the pause (above) |
   | `wipe_in_progress` | Possibly (an orphaned zero is running) | Rehearsal only | A `blkdiscard` is already running (an SSH drop orphaned it). Re-dispatch the read-only rehearsal (b) until W0 passes, then re-dispatch D; it resumes on `arm=re_zero`. | End the pause (above) |
   | `wipe_input_invalid` | No | After fixing the inputs | The pin, by-id path, size or LUKS path is malformed, or `DRY_RUN`/`CONFIRM_WIPE` is not exactly `0` or `1` (`detail=mode_flag`). Re-read preflight's banner; re-dispatch with the correct pin. | End the pause (above) |
   | `wipe_live_mount_not_mapper` | No | No | `/mnt/data` is not the LUKS mapper — this is not a cut-over host. Run `workspaces-luks-verify.yml`; halt and escalate. | End the pause (above) |
   | `wipe_marker_other_volume` | No | No | A persisted wipe marker names another volume id. Halt and escalate: the pin or the host state is wrong. | End the pause (above) |
   | `wipe_target_absent_unexplained` | No | No | The pinned device is not on web-1 and no `PLAINTEXT_WIPED` marker explains it (detached by hand without a wipe?). Halt and escalate; **never** delete it by API unwiped. | End the pause (above) |
   | `wipe_target_blank_unexplained` | No | No | The device has no filesystem signature and no marker explains it. Halt and escalate. | End the pause (above) |
   | `wipe_target_not_ext4` | No | No | The device carries `crypto_LUKS` (the live volume's shape) or another non-ext4 signature. Halt and escalate — this is the wrong device. | End the pause (above) |
   | `wipe_blkid_probe_failed` | No | Yes, once | `blkid -p` errored; a failed probe is not an answer. Re-dispatch once; on a repeat, escalate. | End the pause (above) |
   | `wipe_canary_ok_absent` | No | No | No persisted `CANARY_OK=1:<uuid>` on web-1 — the cutover this retires is not on record. Halt and escalate. | End the pause (above) |
   | `wipe_header_uuid_mismatch` | No | No | The live header UUID is not the persisted `CANARY_OK` UUID. Halt and escalate: the mapper may be backed by a re-formatted volume. | End the pause (above) |
   | `wipe_mapper_not_luks_volume` | No | No | The mapper is backed by a device other than the LUKS volume `106443278`. Halt and escalate. | End the pause (above) |
   | `wipe_escrow_passphrase_mismatch` | No | After re-escrow | The Doppler passphrase does not open the live header (or is unreadable). **Never wipe while the sole copy is unrecoverable**: fix the escrow (ADR-119 §(c)) and re-run the rehearsal. | End the pause (above) |
   | `wipe_header_backup_absent` | No | After the fix `class=` names | The off-host header object for this UUID did not download. The row carries `aws_rc=` and `class=` (never aws's text). `class=not_found` or `empty_object`: re-escrow the header, then re-run the rehearsal. `class=access_denied`: the escrow read credential is wrong or revoked — fix it (re-escrowing would fail the same way). `class=network`: re-run the rehearsal; on a repeat, escalate. `class=other`: escalate. | End the pause (above) |
   | `wipe_header_backup_mismatch` | No | After re-escrow | The escrowed header's UUID differs, or the passphrase does not open its keyslot. Re-escrow, then the rehearsal. | End the pause (above) |
   | `wipe_header_backup_stale` | No | After re-escrow | The escrowed header differs from a fresh backup of the live one (same UUID, different keyslots), or the fresh backup failed. Re-escrow, then the rehearsal. | End the pause (above) |
   | `wipe_target_is_mapper_backing` | No | No | The target resolves to the device backing the live mapper (path or major:minor). **Halt and escalate — this is the one refusal that stands between the zero and every user's data.** | End the pause (above) |
   | `wipe_target_held` | No | No | Something (dm/md) holds the device. Halt and escalate. | End the pause (above) |
   | `wipe_target_mounted` | No | No | The device is mounted somewhere. Halt and escalate. | End the pause (above) |
   | `wipe_target_size_mismatch` | No | No | The device size is not the API's size for the pin. Halt and escalate. | End the pause (above) |
   | `wipe_target_serial_mismatch` | No | No | udev's `ID_SERIAL` does not name `HC_Volume_<pin>`. Halt and escalate. | End the pause (above) |
   | `wipe_target_not_recorded_plaintext` | No | No | The first-wipe target is not the device this cutover recorded as the plaintext's mount source. Compare `target=` with `recorded=`/`recorded_real=`: `none` = the record is missing or invalid; a different device = kernel-name drift after a reboot (then `rollback()`'s and the dead-man's remount source is stale too — do not dispatch `rollback=true` or a cutover either). Nothing was written. Do NOT append `PLAINTEXT_DEV=` to the state file on the host: the record is evidence of what the cutover took the copy from, and a hand-written value is not. Halt and escalate; the remedy is a reviewed fix-forward PR (a serial-anchored record step), not a host edit. | End the pause (above) |
   | `wipe_target_has_dependents` | No | No | A `.mount`/`.swap`/`.service` depends on one of the target's device units, a unit is unloaded/inactive, none maps to the target, or the live mount unit binds one — a detach would stop it. Halt and escalate. | End the pause (above) |
   | `wipe_deadman_armed` | No | No | A cutover dead-man is armed, firing or queued on a cut-over host. **Halt and escalate — do not let it fire.** Since the 2026-09-30 fix-forward a fire on this host *restores*: before any wipe, no wipe marker exists and the recorded `PLAINTEXT_DEV` still reads as an intact ext4, so the fire unmounts the live LUKS copy and remounts the stale 2026-07-23 plaintext over `/mnt/data`, hiding every write since. This W7 refusal is therefore the only protection (arming is unreachable on a cut-over host — S6). | End the pause (above) |
   | `wipe_io_cap_unavailable` | No (from W8), or No with `PLAINTEXT_WIPE_BEGUN` persisted (from the zero's own scope, `gate_rc=97`) | Rehearsal only | The scope's own `io.max` does not carry `rbps=wbps=150000000` for the target's MAJ:MIN (`io_max=` on the row is what it read; `absent` means the io controller is not enabled on the scope's path — systemd starts such a scope uncapped with rc 0). The zero would run uncapped against the live volume's storage path. Halt and escalate. | End the pause (above) |
   | `wipe_target_changed` | No | No | At the act, the by-id link no longer resolves to the device W6 measured, or that device no longer carries `HC_Volume_<pin>`: a volume was detached or attached between the checks and the zero. Nothing was zeroed and no marker was written. Halt and escalate; re-run the rehearsal only once the attachment is understood. | End the pause (above) |
   | `wipe_plaintext_written_after_cutover` | No | No | The plaintext's superblock `Last write time` is later than the 2026-07-23 cutover froze it (`2026-07-23T09:45:00Z`; run 29995956562's host step ended 09:40:41Z), or unreadable (`detail=unparseable`). Something remounted it read-write since, so it may hold writes that exist on no other volume. **Halt and escalate**; never wipe until those writes are reconciled. The `field=last_write` evidence row carries the time. | End the pause (above) |
   | `wipe_positive_control_failed` | No | No | The first 4 KiB does not carry the ext4 magic, so the read path cannot be trusted to see the zero. Halt and escalate. | End the pause (above) |
   | `wipe_marker_write_failed` | `marker=begun`: No. `marker=wiped`: Yes — zeroed and verified, but no API write | No, until the disk is fixed | The state file on web-1's root disk (`/var/lib/workspaces-luks/state`) could not be written and read back (disk full or read-only). `marker=begun`: nothing was zeroed. `marker=wiped`: the zero completed and verified, `PLAINTEXT_WIPE_BEGUN` still locks ROLLBACK out, and the job made no API write. Halt and escalate: freeing root-disk space needs a shell. Once fixed, re-dispatch D (it resumes on `arm=re_zero`). | End the pause (above) |
   | `wipe_blkdiscard_failed` | Partially (`PLAINTEXT_WIPE_BEGUN` persisted) | Yes | The zero itself failed (`rc=` on the row). Re-dispatch D; it resumes on `arm=re_zero` and re-runs every identity check. ROLLBACK is now refused permanently (nothing to remount). | End the pause (above) |
   | `wipe_readback_failed` | Yes — the zero ran, the device is not all-zero | Yes | The O_DIRECT read-back found a non-zero byte (`cmp_rc`/`dd_rc` on the row, the first difference on the evidence row). Re-dispatch D (re-zero); on a repeat, halt and escalate. No API write happened. | End the pause (above) |
   | `wipe_signature_survived` | Yes — the zero ran | Yes | `blkid` still finds a signature after the zero. Re-dispatch D once; on a repeat, escalate. No API write happened. | End the pause (above) |

   Job-level failures (no `reason=` row; the run's `::error::` annotation, step outputs and summary carry
   `reason=`/`outcome=` whenever the host printed them):

   | Symptom | Irreversible act done? | Safe to re-dispatch? | Next action | If you halt here |
   |---|---|---|---|---|
   | preflight refuses `already deleted … dispatch workspaces-plaintext-forget.yml` | Yes (earlier run) | — | Run f. | No — the volume is gone: continue with f and PR B. |
   | preflight: `expected_plaintext_volume_id must equal the constant pin` / `not the constant` (any step) | No | After fixing the input | The pin must be exactly `105149570`. | End the pause (above) |
   | preflight / `wipe` presence proof fails | No | After fixing the token | The token cannot see web-1 (another project, or ADR-241 loader drift). Fix the credential source. | End the pause (above) |
   | `wipe` pre: `api_state changed since preflight` | No | Yes | Re-dispatch so the approver sees the current state. | End the pause (above) |
   | `wipe` pre: an apply workflow not `disabled_manually`, or a queued run | No | Yes, after d | Complete d. | — (the pause is not in place) |
   | `wipe` pre: no successful verify run on main in 24 h / no host-emitted `ready=true` line / `workspace_count` below its baseline | No | Yes, after a | Complete a. A shrunken `workspace_count` is a halt: read the verify run and escalate. | End the pause (above) |
   | `wipe` pre: write-capability probe (labels `PUT`) not `200` | No | After fixing the token | The loader exported a read-only token (ADR-241 O5). Supply a write token; nothing was done. | End the pause (above) |
   | `wipe` host: boot token `carries characters a Doppler token never has` | No | After re-minting | The `WORKSPACES_LUKS_BOOT_TOKEN` secret is malformed (it is written into a sourced `.env`). Re-publish it with the DEFAULT apply. | End the pause (above) |
   | `wipe` host: `did not return a …/wl-cutover.XXXXXX bundle dir` | No — nothing ran | No | web-1 answered `mktemp` with something else (a second line would have injected into `GITHUB_ENV`). Halt and escalate: treat web-1's root shell as suspect. | End the pause (above) |
   | `wipe` host: `bundle upload to web-1 failed — nothing ran` | No | Yes | A tunnel blip during the upload. Re-dispatch D. | End the pause (above) |
   | `wipe` host: not exactly one success row / wrong id / result ≠ `api_state` / ssh rc ≠ 0 | Possibly — read the rows | Yes | Read `reason=`/`outcome=` on the annotation (or the `SOLEUR_WORKSPACES_LUKS_WIPE` rows); re-dispatch D (resume arms). No API write happened. | End the pause (above) |
   | `wipe` api: an apply workflow re-enabled (before the detach, or before the DELETE) | Zero done; maybe detached, not deleted | Yes, after d | Someone lifted the pause mid-run. Re-pause (d), then re-dispatch D (it resumes on the detached or attached arm). | — (re-pause) |
   | `wipe` api: detach action `error` | Zero done; the volume is normally **still attached** | Yes | Re-dispatch D: preflight classifies `attached`, the host takes `arm=re_zero` (it re-zeroes and re-reads the whole device at the cap — expected, not a runaway second wipe), then the API step retries the detach and deletes. | End the pause (above) |
   | `wipe` api: `DELETE` not `204`/`404` after a successful detach | Zero done; detached, not deleted | Yes | Re-dispatch D: preflight classifies `detached`, the host reports `arm=detached`, then the API step deletes. | End the pause (above) |
   | `wipe` api: volume still answers after delete, or server volumes ≠ `[106443278]` | Delete issued | — | Re-read with the GETs in g; escalate if the server still lists `105149570`. | No — a delete was issued: continue with g, then f. |
   | `wipe` post: `wipe_post_api_mount_not_mapper` / `wipe_post_api_readyz_failed` (`reason=` on the step output; Sentry `op:workspaces-luks-drift`) | The API step acted | No | After the detach/delete, `/mnt/data` is no longer the mapper, or the app no longer answers readyz: users are affected. Run `workspaces-luks-verify.yml` now and escalate; never `rollback=true` (it is refused, and there is no plaintext copy). | Depends on `delete_issued` in the summary. |
   | forget: pin still `200`, name lookup non-empty, or state identity mismatch | No state change | Yes, once the cause is fixed | The volume is not gone or the state is not the expected object. Never `state rm` by hand. | No — keep the pause until PR B. |
   | forget: serial/lineage/list post-check fails | State was written | — | Halt and escalate with the run log (it prints no state content). | No — keep the pause until PR B. |

   ROLLBACK after this step is refused permanently (`outcome=refused_plaintext_wiped mode=rollback
   why=marker`): there is no plaintext copy to remount. **Sequence Step 0 is never run after step 7.**

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
`luks-monitor.sh` and the cutover, and the in-guest unlock path is deferred to #6931.

Do not reboot web-1 as part of a rotation.

## Rollback

`gh workflow run workspaces-luks-cutover.yml -f confirm=CUTOVER-WORKSPACES-LUKS -f dry_run=false -f rollback=true`
remounts the retained plaintext at `/mnt/data` + restarts. Post-canary rollback is **reconcilable, not
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
leaves the app down and pages `rollback_remount_failed`. An acknowledged **pre-wipe** `rollback=true`
remounts the plaintext read-write, so W9 then refuses the step-7 wipe
(`wipe_plaintext_written_after_cutover`) until those writes are reconciled.

**After Sequence step 7 there is no rollback.** `rollback=true` refuses before any unmount, with or
without the ack, when either witness holds. The two witnesses page under different slugs, because only
the first one is a wipe:

- `why=marker` (`outcome=refused_plaintext_wiped mode=rollback`, Sentry
  `rollback_refused_plaintext_wiped`): `PLAINTEXT_WIPE_BEGUN` or `PLAINTEXT_WIPED` is persisted on
  web-1. The wipe began, so the copy may be partly or wholly zeroed. Recovery is a re-dispatch of the
  wipe (it resumes on `arm=re_zero`), never a rollback. This is the **only** refusal that proves a
  wipe: the wipe persists `PLAINTEXT_WIPE_BEGUN` and reads it back before any zero.
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
- **Better Stack logs alert `soleur-luks-monitor-host-timer-dark-prd`** (#8706) — the host unit has
  not reported a good run in about 27 h. See the next section.
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
| `wipe_aborted` (`mode=wipe`) | A step-7 wipe aborted. `cleanup()` never rolls back or restarts anything for it (the wipe never sets the freeze/canary flags) and shreds any header copy the wipe left on the root disk. A refused wipe REHEARSAL reads `outcome=dry_run mode=wipe`. | Read the `SOLEUR_WORKSPACES_LUKS_WIPE result=refused reason=` row and follow [the step 7 verdict table](#step-7-verdict-table). |
| `refused_plaintext_wiped` (`why=marker`; `mode=rollback`, or no `mode` from `cleanup()`'s freeze arm) | A rollback was attempted after the wipe began (`PLAINTEXT_WIPE_BEGUN`/`PLAINTEXT_WIPED` persisted); the copy may be partly or wholly zeroed. `rollback()` refused as its first act: nothing was touched. With no `mode=` (from `cleanup()`), the app and the writers are DOWN on a LUKS copy that has not passed the host canary. | Do not roll back. Fix forward on the LUKS volume; re-dispatch the wipe (it resumes on `arm=re_zero`). With no `mode=`: run the verify workflow and escalate at once, the users are offline. `rollback_ack_luks_writes` does not override this. |
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

**What it means.** `soleur-luks-monitor-host-timer-dark-prd`
(`logtail_exploration_alert.luks_monitor_host_timer_dark` in
`apps/web-platform/infra/betterstack-logs-alerts.tf`) fires when web-1 has had no PASSING host run
in about 27 h. Its predicate: no `OK: /mnt/data is LUKS-backed` row from
`_SYSTEMD_UNIT=luks-monitor.service` with `host_name = 'soleur-web-platform'` in the trailing 27 h.
It is evaluated hourly and alerts by email.

It is scoped to web-1. web-2 (`host_name = 'soleur-web-2'`) ships to the same Logs source, so the
host conjunct keeps web-2 rows out. The verify job's rows never carry the unit, so they cannot keep
it quiet either.

The alert does not say why the passing row is missing. Three causes read the same:

- the host unit did not run, or died before it logged;
- the host unit ran and FAILED an assert, for example `FAIL (device_not_luks)` or
  `FAIL (not_mounted)`, which can mean encryption is **not** in effect;
- no row reached Better Stack (a Vector or Logs-source outage).

So do not assume the volume is fine. Read the FAIL-row decode (step D) before anything else. The
daily verify job still checks the volume on its own schedule.

**On the merge that creates it**, one email can fire before the first host row lands. The installer
starts one probe run a few minutes after the alert is created, and the alert resolves within about
an hour of that row.

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

The alert's own predicate is the `host=soleur-web-platform, host_unit=1, kind=ok` cell.

**Decode, one no-SSH action per branch.** The cells hold prose only. The commands are in the steps
below the table.

| What the query shows | Where the fault is | Action |
|---|---|---|
| No `luks-monitor` rows at all, in any cell | Most likely the log pipeline (Vector or the Logs source), not the host | Check the pipeline first: step A |
| `host_unit=0` rows present (the verify job), no `host_unit=1` rows | The host unit is not running, or it dies before it logs | Read the unit state (step B), then find the installer's last fire (step C) |
| `host_unit=1` rows, `kind=fail` | The host probe runs and fails an assert | Read the reason from the row (step D) |
| `host_unit=1` rows, `kind=ok`, inside the last 27 h, alert still open | Nothing: the alert recovers after an hour of passing reads | None. Re-read in an hour |

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
the timer. The apply stays red until the DSN is fixed, and on a first install the host-timer alert
follows in about 27 h. A malformed non-empty value fails the resource's precondition at plan time.
That stops the WHOLE per-merge SSH apply step, every SSH-provisioned resource in it, including the
boot-token delivery on a rotation merge, until the DSN in Doppler `prd_terraform` is fixed. The
reasoning is in ADR-119's 2026-09-27 addendum.

**Closing #8706.** `scripts/followthroughs/luks-monitor-host-timer-8706.sh` passes on three
consecutive UTC dates, each with a host-unit `OK:` row in the 00 UTC hour. It counts only that hour,
to skip the installer's kick run. If the SSH apply itself lands between 00:00 and 00:59 UTC, its kick
row falls in that hour and counts as one night. So the three-night rule can close one night early.
