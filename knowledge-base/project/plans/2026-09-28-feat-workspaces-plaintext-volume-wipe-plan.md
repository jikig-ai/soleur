---
title: "feat(infra): the environment-gated WIPE of web-1's retained plaintext /workspaces volume (#6604 step 7 / ADR-119)"
date: 2026-09-28
slug: feat-workspaces-plaintext-volume-wipe
branch: feat-one-shot-6604-workspaces-plaintext-wipe
issue: 6604
closes: []
refs: [6604, 6588, 6897, 9123, 6931, 9098, 8285, 8209]
type: feat
priority: p0
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

# feat(infra): wipe web-1's retained plaintext /workspaces volume (#6604 step 7)

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Overview

The #6604 soak passed on 2026-09-24 and has re-passed on every daily sweep since. The sweeper still
exits 1 only because its close criterion is ADR-119 `accepted`, which by design flips *after* the
retained plaintext copy is gone. The step that retires that copy — runbook step 7, ADR-119's
`CONFIRM_WIPE` slot — was specified but never built: `CONFIRM_WIPE` exists in
`workspaces-cutover.sh` only as a counted operand of `assert_mode_exclusive()`, and
`workspaces-luks-cutover.yml` has no input that reaches it.

This plan ships the work in **two PRs around one gated dispatch**, because Terraform will not let
the three halves be one atomic change (measured, see Research Insights §Terraform ordering):

| Step | What | Irreversible? | Authorization |
|---|---|---|---|
| **PR A** (this one-shot) | The wipe mode (script + a gated `wipe` job), a separate `workspaces-plaintext-forget.yml` state workflow, census/parity widening, tests, runbook, ADR-119 addendum (status stays `adopting`), ADR-241 note, C4 edges, Art. 5(2) destruction-record template | No | PR merge |
| **R** rehearsal | `dry_run=true wipe_plaintext=true` — every host precondition, read-only, stops before `blkdiscard` (runs in the existing ungated `cutover` job) | No | Ungated (ADR-119 2026-07-18 addendum: rehearsals run autonomously) |
| **D** the dispatch | `dry_run=false wipe_plaintext=true` — the `wipe` job proves the write token, then `blkdiscard -z` + read-back on web-1, then API detach + delete; `workspaces-plaintext-forget.yml` then `terraform state rm`s the two `["web-1"]` addresses, serialized with every apply. The two push-apply workflows are paused from here until PR B merges | **Yes** | One operator go-ahead naming the command set **and** one `workspaces-luks-cutover` environment approval |
| **PR B** (after D) | `for_each` narrowing on both resources, web-1 `user_data` reference, ledger row, ADR-119 `accepted`, destruction record completed, legal-register sweep, #6897/#6588 records | No | PR merge; closes #6604 + #6588 |

No step reboots or replaces web-1, and the dispatch never stops the app. (Each PR merge fires the
routine container release, as every `apps/web-platform/**` merge does.) The live data never moves:
`/mnt/data` stays on `/dev/mapper/workspaces` (volume 106443278) throughout.

## Research Reconciliation — Spec vs. Codebase

| Brief / spec claim | Reality (measured 2026-09-28) | Plan response |
|---|---|---|
| "Open or record PR 3, the legal flip" | PR 3 **already merged**: #6938 (`ad81dc81b`, 2026-08-02) — "closes the legal half only". Its accepted residual is the un-wiped plaintext copy (`knowledge-base/legal/audits/2026-07-counsel-review-6588.md` frontmatter `accepted_residual`). | *Record* #6938 as PR 3; PR B appends a dated "residual cured" note to the counsel review with the dispatch evidence. No published legal doc changes (the claim is already true; the residual was never published). |
| "Terraform convergence ... after the API delete" as one step | Three constraints collide: (1) `infra-validation.yml` plans with `-refresh=false`, so a narrowed `for_each` over state that still holds `["web-1"]` plans a delete and **`prevent_destroy` fails the plan**; (2) every push apply is `-target`ed and `-target` is **resource-level transitive** — `hcloud_server.web` references `hcloud_volume.workspaces[each.key]`, so while config still lists web-1, any push apply after the delete **plans `+create` of a fresh plaintext volume** (a conditional on `each.key` does not break the edge); (3) `removed {}` cannot take instance keys, and `moved`+`removed` makes every targeted plan fail with `Moved resource instances excluded by targeting` until an *untargeted* apply runs, which this root never does. All three reproduced on Terraform 1.10.5 (Research Insights). | `state rm` rides a dedicated separate `workspaces-plaintext-forget.yml` workflow (`environment: infra-privileged`, no reviewer, main-only; workflow-level `concurrency: terraform-apply-web-platform-host`, the literal every apply of this root uses because the R2 backend has no lock), conditioned on an in-step API `404` and bound to the physical id. It cannot be a job in the cutover workflow (that would nest `web-1-swap` then the host group — the inverse of the apply workflows' order, a deadlock) nor an `apply_target` (`apply-web-platform-infra.yml` is 489,275 bytes against the 490,000-byte cap of `plugins/soleur/test/workflow-file-size.test.ts`). The delete→PR-B window is closed by **pausing the two push-apply workflows** — not by a destroy-guard surface, which would reverse #6919/T55. PR B narrows the `for_each`. |
| "`lsblk -D`, then `blkdiscard -z`" as the discard gate | `blkdiscard -z` issues `BLKZEROOUT`, which the kernel satisfies by writing zeros when the device lacks write-zeroes offload; the C5 "silently no-ops without discard support" concern applies to plain `blkdiscard` (no `-z`). util-linux ≥2.36 opens the device `O_EXCL`, so it refuses a mounted or held device unless `-f`. | `lsblk -D` is recorded as evidence; the **gate is the full-device read-back**. `-f/--force` is forbidden by a guard row. |
| "re-verify the persisted `CANARY_OK` header UUID" (DP-7 asked for a durable R2 artifact) | The implementation persists `CANARY_OK=1:<uuid>` to web-1's `/var/lib/workspaces-luks/state` at the host-canary door (`workspaces-cutover.sh`, anchor `persist_state CANARY_OK "1:$(cryptsetup luksUUID`). Run 29995956562 (2026-07-23) passed that door. The durable off-host artifact keyed to the UUID is the **header backup object** `workspaces-luks-header-<uuid>.img`. | The wipe requires BOTH: the host `CANARY_OK` UUID equals the live mapper's backing header, AND the off-host header object for that UUID downloads and its `luksUUID` matches. Absent `CANARY_OK` → refuse `wipe_canary_ok_absent`, no override input. |
| "`HCLOUD_TOKEN` from `prd_terraform`" | Tier census `tests/scripts/test-infra-privileged-tier-census.sh` G1g **fails** any workflow step that reads `HCLOUD_TOKEN` from `prd_terraform` outside `.github/actions/infra-credentials` (only a `HCLOUD_TOKEN_READONLY`-first read is sanctioned). Doppler today: `prd_terraform` holds `HCLOUD_TOKEN` (read/write), no `HCLOUD_TOKEN_READONLY`; `soleur-infra-privileged/prd` is empty (ADR-241 O-steps not run). | Write-token reads go through the loader (legacy arm currently exports the read/write `HCLOUD_TOKEN`). The `wipe` job declares `environment: workspaces-luks-cutover` unconditionally and the forget workflow's job declares `infra-privileged` (census Guard 1: every arm Tier-B). The `wipe` job **proves write capability before it reaches web-1**, with an idempotent `PUT` of the volume's unchanged labels: after ADR-241 O5 the legacy arm exports the read-only token, and without the probe the delete would 403 *after* the zeroing. |
| "`prevent_destroy` on the volume" blocks the converge | True for any plan that proposes a delete. Refreshing plans drop an API-deleted object before planning (hcloud provider `resourceVolumeRead` / `resourceVolumeAttachmentRead` call `d.SetId("")` on a missing volume or a detached one; Terraform `node_resource_plan_orphan.go` plans nothing for a refreshed-null orphan). Only `-refresh=false` plans trip it. | `state rm` before PR B; no need to remove `prevent_destroy` (web-2 keeps it). |
| "`CONFIRM_WIPE` reserved (~line 77/1524)" | Confirmed: declared at the config block, counted in `assert_mode_exclusive()`; no mode block, no workflow input. `cleanup()` has no `CONFIRM_WIPE` outcome arm, so an aborted wipe would record `outcome=pre_freeze`. | New mode block after `CLEAN_STRAY`; new `cleanup()` arm `outcome=wipe_aborted`. |

## Research Insights

### Premise validation (Phase 0.6)

- **#6604** OPEN; sweeper comments 2026-09-24…27 all read "SOAK PASSED — wipe authorized … stays OPEN
  until this script OBSERVES ADR-119 'accepted' (currently: 'adopting')".
- **#6588** OPEN (p0). Legal half closed by #6938; comment 2026-08-02 records the residual.
- **#6897** OPEN (p3) — item 1 covers `hcloud_volume.workspaces` **and** `hcloud_volume.git_data`
  (out of scope here; stays open).
- **#9123** OPEN — web-1 reboot is unsafe (fstab glob, no boot unlock). This plan never reboots.
- **#9098** MERGED 2026-09-28 (`ff019afe71`): dead-man, signal-safe `cleanup()`, `RUN_COMPLETE`,
  `assert_rollback_not_post_cutover`, counted `assert_mode_exclusive`.
- Live Hetzner (read-only GET, 2026-09-28): `105149570` `soleur-web-platform-data` server
  `123931471` (`soleur-web-platform`), 20 GB, `format=ext4`, `protection.delete=false`,
  `linux_device=/dev/disk/by-id/scsi-0HC_Volume_105149570`, hel1; `106443278`
  `soleur-web-platform-data-luks` same server, `format=null`; `106466179`
  `soleur-web-platform-data-web-2` on server `167390740`. Server 123931471 volumes = `[105149570, 106443278]`.
- `workspaces-luks-verify.yml`: scheduled run 36414403037 (2026-09-28T11:13Z) **success**.
- Environment `workspaces-luks-cutover`: reviewers `[54279]`, deployment policy `branch_pattern = "main"`
  (`workspaces-luks.tf`, `github_repository_environment_deployment_policy.workspaces_luks_cutover_main`)
  → the real dispatch must run from `main`.

### Property List (Phase 0.6b)

- **P1** No byte of web-1's pre-cutover plaintext workspace copy remains readable on any Hetzner
  volume attached to, or owned by, the project.
- **P2** The zeroed device is provably the plaintext volume 105149570 and provably not the device
  backing `/dev/mapper/workspaces`.
- **P3** At the moment of wiping, the LUKS volume is independently recoverable (passphrase opens the
  live header; the off-host header backup for that UUID exists and matches) — because the wipe
  removes the last backstop against header/passphrase loss (ADR-119 §(f) "terminal mode").
- **P4** The irreversible act is reachable only behind the `workspaces-luks-cutover` reviewer plus a
  per-verb typed token plus a physical-id pin; a rehearsal can exercise every precondition and
  cannot destroy.
- **P5** Terraform state and config converge on reality with no apply ever re-creating a plaintext
  volume and no plan ever proposing to destroy web-2's volume.
- **P6** After the wipe, no dispatch can remount a volume that no longer exists (a post-wipe
  `rollback=true` must refuse before teardown).
- **P7** The act is evidenced off-host (marker rows, run summary, API 404) — Art. 5(2) — with no SSH.
- **P8** During the dispatch window web-1 is neither rebooted nor replaced, and `/mnt/data` never
  leaves the mapper. (PR merges fire the routine container release on web-1; that is not a host
  redeploy, and the go-ahead ask names it.)

### Cut List (Phase 0.6b)

- **Hetzner snapshot before the wipe** (learning 2026-06-18 "backup before destructive migration")
  → P1 is the point; a backup is a third plaintext copy with its own retention/DSAR duties (ADR-119
  CLEAN_STRAY addendum rejected the same escrow) — and Hetzner Cloud offers no volume snapshots.
- **A separate host read-only probe in `preflight`** → P4's rehearsal is already bought by the
  existing ungated `dry_run=true` arm running the *same* `wipe_plaintext()` code with `DRY_RUN=1`;
  a second probe would diverge from the code that actually wipes.
- **Running `luks-monitor.sh` inline for P3** → pushes a heartbeat and Sentry events as side effects;
  the passphrase half is a 3-line `luksOpen --test-passphrase` already used by `luks-monitor.sh`.
- **A post-wipe host re-probe in the `wipe` job** → `workspaces-luks-verify.yml` (daily + dispatch)
  already asserts mapper/escrow/readyz/inventory; the runbook dispatches it after D.
- **Changing the soak script to observe the wipe** → its close criterion (ADR-119 `accepted`) lands
  only in PR B, which is authored after D; a Hetzner read needs a token the sweeper does not hold.
- **`moved` into a singleton + `removed`** → dead on arrival (targeted plans error; reproduced).
- **A new destroy-guard surface counting workspace-volume creates** (plan review) → P5 for the
  delete→PR-B window; a two-workflow pause buys the same property without reversing #6919/T55 or
  touching a file 725 bytes under its size cap.
- **A keepalive ticker, a timed 1 GiB read, an enumerated W0 binary list, a `PLAINTEXT_DEV`
  cross-check** (plan review) → covered respectively by `ServerAliveInterval`, a fixed 240-minute
  timeout, natural pre-write failure, and the filesystem label `workspaces_plain`.
- **A `data "hcloud_volumes"`-driven `for_each`** → still needs the `state rm` for `-refresh=false`
  plans and leaves a permanent API read in every plan.

### Terraform ordering — reproduced on Terraform 1.10.5 (scratch root, `terraform_data`)

| Case | Result |
|---|---|
| narrowed `for_each` + state still holding `["web-1"]`, `plan -refresh=false` | `Error: Instance cannot be destroyed` |
| `moved` → singleton + `removed { destroy = false }`, full plan | `0/0/0`, forget warning |
| same, any `-target` plan (even targeting the moved/removed addresses) | `Error: Moved resource instances excluded by targeting` |
| `state rm` then narrowed config, `-refresh=false` and targeted | `No changes` |
| `state rm` with **old** config (the window), targeted plan through `hcloud_server.web` | `+ create vol["web-1"]` — also with a `each.key == "web-1" ? "frozen" : …` conditional |
| stale `moved { to = vol["web-1"] }` after narrowing | `validate` OK, `No changes` (so `placement-group.tf`'s two historical `moved` blocks stay) |

### Relevant files

- `apps/web-platform/infra/workspaces-cutover.sh` — config block (`CONFIRM_WIPE="${CONFIRM_WIPE:-0}"`),
  `persist_state`/`read_state`, `emit_drift`, `_vscrub`, `LUKS_LOG_TAG`, `read_key`, `load_escrow_creds`,
  `ensure_aws`, `_same_dev`, `assert_rollback_not_post_cutover`, `cleanup()`, `emit_clean_stray`,
  `assert_mode_exclusive`, `clean_stray()`, sourced-detection guard, ROLLBACK and CLEAN_STRAY mode blocks.
- `.github/workflows/workspaces-luks-cutover.yml` — `preflight` (ungated), `cutover` (env expression
  pinned byte-exact by `workspaces-luks-header.test.sh` H17), `.env` delivery, `LUKS_DEV` resolution
  (`HCLOUD_TOKEN_READONLY`-first), summary step.
- `.github/actions/infra-credentials/action.yml` — the only sanctioned Tier-B loader.
- `tests/scripts/lib/destroy-guard-filter-web-platform.jq` — shared per-PR apply filter (8 surfaces;
  `host_creates` is the model for the new counter). Consumers: `apply-web-platform-infra.yml`,
  `apply-deploy-pipeline-fix.yml`, and `tests/scripts/lib/*-gate.sh`.
- `apps/web-platform/infra/server.tf` — `hcloud_volume.workspaces` / `hcloud_volume_attachment.workspaces`
  (`for_each = var.web_hosts`, `prevent_destroy`), and `hcloud_server.web` `user_data`
  `workspaces_volume_id = hcloud_volume.workspaces[each.key].id` (`ignore_changes = [user_data, …]`).
- `scripts/encryption-posture-ledger.json` — row `hcloud_volume.workspaces` (`plaintext-exception`,
  `tracking_issue: #6897`, **`expires_on: 2026-10-22`** — the lint FAILs an expired exception, so PR B
  must land before then or the row must be re-scoped anyway).
- `scripts/followthroughs/workspaces-luks-soak-6604.sh` — closes on ADR-119 `accepted`; unchanged.
- `knowledge-base/legal/audits/inngest-aof-destruction-record.md` — the Art. 5(2) destruction-record
  precedent (template committed before the dispatch, completed from the gate's own row).
- Test harness: `apps/web-platform/infra/workspaces-luks-harness.sh` (`run_case`, PATH stubs, `$CALLS`,
  `ok/no/has/nhas/markerF/died/ran/idx/cnt`, `harness_floor`); `workspaces-luks-loopback.test.sh` (real
  loop devices, `sudo` in `infra-validation.yml` `deploy-script-tests`, never self-skips —
  `LOOPBACK_UNAVAILABLE`); `workspaces-luks-cutover-workflow.test.sh`; `workspaces-luks-header.test.sh`.

### Institutional learnings applied

- `2026-09-28-an-ssh-drop-without-a-pty-is-sigpipe-and-my-cleanup-trap-read-it-as-success.md` — the
  wipe block ends `RUN_COMPLETE=1; exit 0` only on success; every refusal path `die`s into `cleanup()`.
- `workflow-patterns/2026-07-19-real-cutover-routes-to-workflow-dispatch-and-failclosed-gate-must-self-report.md`
  — every refusal emits its marker row **before** `die`.
- `2026-07-23-terraform-destroy-guard-address-vs-physical-id-and-replace-recovery-arm.md` — bind the
  destructive act to the operator-typed **physical id** (`expected_plaintext_volume_id`), never a
  name or address alone.
- `2026-09-27-a-status-flip-sweep-must-include-the-legal-registers-that-state-the-mechanism.md` —
  PR B sweeps `knowledge-base/legal/**` for future-tense statements about the plaintext copy.
- `2026-09-25-gh-stub-must-mirror-real-cli-flags.md` — the `curl`/`blkdiscard`/`lsblk` stubs whitelist
  real flags and exit 64 on unknown ones.
- `2026-07-27-the-subshell-bug-i-was-fixing-bit-me-three-more-times-in-the-same-session.md` — no
  `die` inside `$( )`; read-back rc captured from a file/plain command, never a substitution.
- `2026-07-03-dark-launch-pr-must-exclude-operator-prerequisite-infra.md` — PR A carries **no**
  `.tf` change, so its merge-triggered applies are inert with respect to this work.

### External references

- Hetzner Cloud OpenAPI (`https://docs.hetzner.cloud/cloud.spec.json`, fetched 2026-09-28):
  `DELETE /volumes/{id}` — "All Volume data is irreversibly destroyed. The Volume must not be attached
  to a Server and it must not have delete protection enabled." → `204`. `POST
  /volumes/{id}/actions/detach` → `201` with an `action`; `GET /actions/{id}` `status ∈
  {running, success, error}`. Volume object: `server` (null when detached), `linux_device`,
  `protection.delete`, `format`, `status`.
- util-linux `blkdiscard(8)`: `-z, --zeroout  Zero-fill rather than discard`; "Since v2.36 the block
  device is open in exclusive mode (O_EXCL) by default … The --force option disables the exclusive
  access mode." `lsblk -D, --discard  print discard capabilities`. (Verified locally 2026-09-28.)
- terraform-provider-hcloud `internal/volume/resource.go` `resourceVolumeRead` and
  `resource_attachment.go` `resourceVolumeAttachmentRead` (main, fetched 2026-09-28).
- Terraform v1.10.5 `internal/refactoring/move_validate.go` (`ValidateMoves` checks only that `from`
  is no longer declared) and `internal/terraform/node_resource_plan_orphan.go` (a refreshed-null
  orphan plans nothing).

### Related

#8285 is the sibling retirement of the plaintext Redis AOF backstop (same class, same 2026-10-22
clock). This plan does **not** generalize the mode for it (YAGNI); the destruction-record template
and the forget workflow's shape are reusable there.

## Technical Approach

### A. Script — `wipe_plaintext()` + the `CONFIRM_WIPE` mode block (`workspaces-cutover.sh`)

New inputs, delivered in the 0600 stdin `.env` as a heredoc with one named `KEY=value` line each (no
multi-`%s` `printf`, whose format repeats when the argument count outgrows it): `CONFIRM_WIPE`,
`WORKSPACES_PLAINTEXT_DEV` (`/dev/disk/by-id/scsi-0HC_Volume_<id>`, runner-built from the **pinned**
id, never a name lookup), `WORKSPACES_PLAINTEXT_VOLUME_ID`, `WORKSPACES_PLAINTEXT_SIZE_BYTES` (API
`size` × 1024³), plus the existing `WORKSPACES_LUKS_DEV`, `DRY_RUN`, `DOPPLER_TOKEN` (the boot token,
needed for W4/W5).

The mode block sits **after** the CLEAN_STRAY block and **before** the L3 gates, mirroring its shape:
`if [ "$CONFIRM_WIPE" = "1" ]; then wipe_plaintext; RUN_COMPLETE=1; exit 0; fi`. It **never assigns
`DRY_RUN`** (the ROLLBACK anti-pattern) and **never sets the globals `CANARY_OK`, `FREEZE_HELD`,
`FLIP_DONE`, `DEADMAN_ARMED`** — `cleanup()` keys its rollback/roll-forward arms on those, and an
in-process `CANARY_OK=1` would make an aborted wipe `docker start` the app. `cleanup()` gains
`elif [ "$CONFIRM_WIPE" = "1" ]; then outcome=wipe_aborted` ahead of the `pre_freeze` fallback, and
the outcome row gains `mode=wipe` (a refused rehearsal still reads `outcome=dry_run mode=wipe`). The run
steps' `::error::` guidance lists `wipe_aborted`. A refusal raised inside a reused helper that `die`s
on its own (`load_escrow_creds`) surfaces as that `wipe_aborted mode=wipe` row rather than a
`SOLEUR_WORKSPACES_LUKS_WIPE` row; every refusal `wipe_plaintext()` raises itself emits
`SOLEUR_WORKSPACES_LUKS_WIPE result=refused reason=<slug>` + `emit_drift <slug>` **before** `die`.

**Stage 1 — environment (always):**

| # | Check | Refusal reason |
|---|---|---|
| W0 | util-linux ≥ 2.36 (`blkdiscard --version`; the `O_EXCL` guarantee depends on it); `aws` already installed — W0 **never** calls `ensure_aws`, which can `apt-get install` on prod web-1; no `blkdiscard` process running (`pgrep -x blkdiscard` — an SSH drop orphans a running zero, and a re-dispatch would race it) | `wipe_tool_missing` / `wipe_in_progress` |
| W1 | inputs well-formed: id `^[0-9]+$`, dev path == `/dev/disk/by-id/scsi-0HC_Volume_${id}` exactly, size `^[0-9]+$` | `wipe_input_invalid` |
| W2 | `findmnt -no SOURCE /mnt/data` == `$MAPPER` | `wipe_live_mount_not_mapper` |

**Stage 2 — classify the arm.** `blkid -p` exit codes are mapped explicitly (0 signature, 2 none,
8 ambivalent, anything else error); markers are read with `read_state` and must name **this** id.

| Device present? | Signature | Markers for this id | Arm |
|---|---|---|---|
| yes | `ext4` | none | **first wipe** → Stage 3 in full, including W9 |
| yes | any (incl. none, ambivalent) | `PLAINTEXT_WIPE_BEGUN` or `PLAINTEXT_WIPED` | **re-zero** → Stage 3 without W9 (an interrupted zero has already cleared the superblock; zeroing a zeroed device is idempotent) |
| no | — | `PLAINTEXT_WIPED` | **detached** → `result=already_wiped_detached`, nothing written |
| yes | none or ambivalent | none | refuse `wipe_target_blank_unexplained` |
| yes | `crypto_LUKS` or any non-`ext4` | none | refuse `wipe_target_not_ext4` |
| — | — | markers naming a different id | refuse `wipe_marker_other_volume` |
| no | — | no `PLAINTEXT_WIPED` | refuse `wipe_target_absent_unexplained` |

Under `DRY_RUN=1` every arm reports `result=rehearsal_ok arm=<arm>` with its measured fields and
writes nothing.

**Stage 3 — preconditions and the act (every arm that can zero runs all of W3–W7):**

| # | Check | Refusal reason |
|---|---|---|
| W3 | **DP-7**: `read_state CANARY_OK` is `1:<uuid>`; mapper backing device from `cryptsetup status`; `luksUUID(backing) == uuid`; `_same_dev backing $WORKSPACES_LUKS_DEV` | `wipe_canary_ok_absent` / `wipe_header_uuid_mismatch` / `wipe_mapper_not_luks_volume` |
| W4 | **P3 passphrase**: `key="$(read_key)"`, then `printf '%s' "$key" \| cryptsetup luksOpen --test-passphrase --key-file - <backing>` (the `luks-monitor.sh` form — a piped raw read can carry a trailing newline) | `wipe_escrow_passphrase_mismatch` |
| W5 | **P3 off-host header**: `load_escrow_creds`; download `workspaces-luks-header-<uuid>.img` to `$STATE_DIR` (0700); its `luksUUID` == uuid; `shred -u`. The daily monitor never downloads this object — only this check proves it restorable | `wipe_header_backup_absent` / `wipe_header_backup_mismatch` |
| W6 | **P2 identity**: target `-b`; `realpath` and `stat -Lc %t:%T` differ from the backing device's; `/sys/class/block/<kname>/holders/` empty; `findmnt -S <dev>` finds nothing; `blockdev --getsize64` == `WORKSPACES_PLAINTEXT_SIZE_BYTES`; **first-wipe arm only:** filesystem label `blkid -p -s LABEL -o value` == `workspaces_plain` (the label `rollback()` mounts by — the host's own name for the plaintext volume) | `wipe_target_is_mapper_backing` / `wipe_target_held` / `wipe_target_mounted` / `wipe_target_size_mismatch` / `wipe_target_label_mismatch` |
| W6b | **detach safety**: for each of the target's device units (`dev-disk-by\x2did-scsi\x2d0HC_Volume_<id>.device`, `dev-<kname>.device`), `systemctl show -p LoadState` is `loaded` (an unloaded or misspelled unit lists no dependencies and exits 0), then `systemctl list-dependencies --reverse --plain` shows no `.mount`, `.swap` or `.service`. `mnt-data.mount`'s `What=` is the literal `scsi-0HC_Volume_*` glob (#9123), so comparing it to the target proves nothing; this probe is the measurement | `wipe_target_has_dependents` |
| W7 | no dead-man is armed: `systemctl is-active workspaces-luks-deadman.timer` ≠ `active` | `wipe_deadman_armed` |
| W8 | evidence only: `lsblk -D -b -n -o DISC-GRAN,DISC-MAX <dev>` and `/sys/block/<k>/queue/write_zeroes_max_bytes` | — |
| W9 | **positive control** (first-wipe arm only): 4096 bytes at offset 0 via `dd iflag=direct` (an unaligned direct read fails `EINVAL`), bytes 1080–1081 == `53 ef`. Evidence field, never a gate: `dumpe2fs -h` last-mount and last-write times (the CLO's check that nothing wrote after the 2026-07-23 cutover) | `wipe_positive_control_failed` |
| — | `DRY_RUN=1` → one `result=rehearsal_ok` row carrying every measured field; `RUN_COMPLETE=1; exit 0` | — |
| W10 | `persist_state PLAINTEXT_WIPE_BEGUN "<id>:<epoch>"`; `ionice -c3 blkdiscard -z -v <dev> </dev/null` — never `-f` (stdin from `/dev/null`: util-linux refuses a device carrying a signature when stdin is a terminal) | `wipe_blkdiscard_failed` |
| W11 | `blockdev --flushbufs <dev>`; `ionice -c3 dd if=<dev> iflag=direct bs=4M status=none \| cmp -n <size> - /dev/zero`, both `PIPESTATUS` values and `cmp`'s stderr captured into plain variables (never `$( )`). `cmp` decides: rc 0 with `dd` rc 0 passes; anything else refuses with one reason carrying `cmp_rc`, `dd_rc` and the scrubbed stderr tail (`cmp` exiting early on a difference makes `dd` fail with EPIPE, so `dd`'s rc alone never classifies) | `wipe_readback_failed` |
| W12 | `blkid -p` reports no signature; `persist_state PLAINTEXT_WIPED "<id>:<epoch>"`; one row `result=wiped arm=<arm> volume_id=<id> bytes=<size> readback=zero discard_gran=… discard_max=… write_zeroes_max=… last_write=…` | — |

**Post-wipe refusals (P6).** `assert_rollback_not_post_cutover` gains a first check: a non-empty
`PLAINTEXT_WIPED` **or** `PLAINTEXT_WIPE_BEGUN` → `emit_drift rollback_refused_plaintext_wiped`, then
`_deadman_row "result=cutover_aborted outcome=refused_plaintext_wiped mode=rollback"`, `trap - EXIT`,
`exit 1` (ROLLBACK mode has no `cleanup()` arm of its own, so without the explicit row the refusal
would record `outcome=pre_freeze`). **Not** overridable by `ROLLBACK_ACK_LUKS_WRITES` — there is
nothing to remount. It runs before any `umount`/`cryptsetup close`/`docker stop`. `arm_dead_man`
refuses on the same markers (`deadman_refused_plaintext_wiped`); the work phase first checks whether
any dispatch can still reach `arm_dead_man` on a post-cutover host, and drops this refusal (with a
note) if none can.

### B. Workflow — `workspaces-luks-cutover.yml`

Workflow-level `concurrency: web-1-swap` is unchanged: the new `wipe` job touches web-1 and never
takes the Terraform host group, so no job nests the two groups (the state step lives in its own
workflow, §C).

- **Inputs:** `wipe_plaintext` (boolean, default `false`; the description names AP-009, the one
  approval, and that `dry_run=true` is the rehearsal); `expected_plaintext_volume_id` (string). The
  `dry_run` description's "no wipe" wording is updated.
- **`preflight` (ungated, read-only).** Order: (1) mode exclusion first — wipe excludes `rollback`,
  `clean_stray`, `rollback_ack_luks_writes` — so a mixed dispatch is refused before any "untick
  dry_run" hint; (2) `expected_plaintext_volume_id` must match `^[0-9]+$` on a wipe and be **empty** on
  every other mode; (3) confirm token `WIPE-PLAINTEXT-USER-DATA-AP-009`. Then a read-only API read
  (`HCLOUD_TOKEN_READONLY`-first, the G1g-sanctioned shape; status codes read with `-w
  '%{http_code}'`, never `-f`, which turns a 404 into exit 22) classifies `api_state` (job output):
  - `attached` — the pinned id resolves; name `soleur-web-platform-data`; `server` == the id of the
    server named `soleur-web-platform`; `format == ext4`; `protection.delete == false`;
    `linux_device` == the pinned by-id path; id ≠ the `soleur-web-platform-data-luks` id; a name
    lookup returns exactly this one volume;
  - `detached` — the same with `server: null` (no `linux_device` assertion);
  - `absent` — the pinned id `404`s **and** the name lookup is `[]` → refuse with the remedy "already
    deleted; dispatch `workspaces-plaintext-forget.yml`";
  - anything else → refuse, naming the mismatching field.
  It writes the approver banner — id, name, size, created, server, the live LUKS id, `api_state` —
  and exports `size_bytes`.
- **`cutover` job:** unchanged for every non-wipe mode; its `environment:` expression stays
  byte-identical (`workspaces-luks-cutover-workflow.test.sh` pins it exactly; `workspaces-luks-header.test.sh`
  H17 reads the **first** `environment:` line in the file, so the new job goes **after** `cutover`).
  A job-level `if:` skips it when `wipe_plaintext && !dry_run`; that test's "no job-level `if:`" row is
  amended to allow exactly that predicate. On a wipe rehearsal it delivers `CONFIRM_WIPE=1 DRY_RUN=1`:
  its `CONFIRM_WIPE` value is `inputs.wipe_plaintext && inputs.dry_run`, so this job can never
  deliver a destructive wipe. ADR-119's 2026-07-19 rule ("every destructive mode contributes its own
  operand" to this expression) is kept by construction — the destructive wipe is not reachable from
  this job at all — and the addendum says so.
- **`wipe` job (new, after `cutover`):** `needs: preflight`; `if: inputs.wipe_plaintext &&
  !inputs.dry_run`; `environment: workspaces-luks-cutover` (**unconditional**: census Guard 1, and the
  one human approval); `timeout-minutes: 240` (a fixed ceiling committed in PR A — 20 GiB of zeroes
  without offload plus a 20 GiB direct read fits well inside it; the rehearsal's W8 fields are
  recorded, and the ceiling is only raised by a later PR if they say otherwise). Steps:
  1. `infra-credentials` loader; re-`GET` the pinned volume and require `api_state` unchanged since
     preflight (the approval may have waited hours); then the **write-capability probe** — `PUT
     /volumes/<id>` with the volume's current `labels` verbatim → `200`. A read-only token `403`s
     **here, before web-1 is touched**.
  2. CF-tunnel bridge, bundle ship, 0600 heredoc `.env` (`CONFIRM_WIPE=1 DRY_RUN=0`), run — the same
     shape as `cutover`'s run step, duplicated rather than refactored so the freeze path stays
     byte-stable. The `ssh` call adds `-o ServerAliveInterval=30 -o ServerAliveCountMax=10`: a silent
     multi-minute `blkdiscard` must not idle the tunnel into a drop. Output is tee'd; the job requires
     exactly one `SOLEUR_WORKSPACES_LUKS_WIPE` success row whose `volume_id` equals the pin **and**
     whose result matches `api_state` (`attached` → `wiped`; `detached` → `already_wiped_detached`);
     zero rows, two rows, or a mismatch fail the job before any API write. The host step always runs,
     including on `detached`, so a volume detached by hand without a wipe is refused, never deleted.
  3. API: if `server != null`, `POST …/actions/detach`, poll `GET /actions/<aid>` every 5 s ≤ 300 s;
     on timeout with the action still `running`, keep polling that action (never re-POST — a second
     detach returns `locked`); then `GET` shows `server: null`. `DELETE /volumes/<id>` → `204` (`404`
     accepted). Final `GET` must be `404`, and `GET /servers/<web-1>` `volumes` must no longer list
     it. Token masked, never echoed; `curl -sS --max-time 15 -w '%{http_code}'`.
  4. Summary: mode `WIPE`, the marker row, the detach action id, the `204`/`404`, and the next step
     (dispatch the forget workflow).

### C. The forget workflow — `.github/workflows/workspaces-plaintext-forget.yml` (new, removed in PR B)

A separate `workflow_dispatch` workflow so that no run ever holds both `web-1-swap` and the Terraform
host group (the apply workflows take host then swap; nesting them the other way can deadlock).

- Workflow-level `concurrency: { group: terraform-apply-web-platform-host, cancel-in-progress: false }`
  — the literal every writer of this lockless R2 state uses.
- Inputs: `expected_plaintext_volume_id`, `confirm` (`FORGET-RETIRED-PLAINTEXT-VOLUME`).
- One job, `environment: infra-privileged` (Tier-B, main-only, **no reviewer**: it only forgets
  addresses whose object is measured gone), `env: TERRAFORM_VERSION` equal to the apply workflows'.
- Steps: checkout, `setup-terraform`, the `infra-credentials` loader, then the apply job's own
  "Extract backend credentials" and `terraform init -input=false -lockfile=readonly` steps copied
  verbatim (the loader exports no backend config; the bucket is fixed in `main.tf`), then:
  1. the pinned id `GET` → `404` **and** the name lookup → `[]` (status via `-w '%{http_code}'`);
  2. `terraform state pull | jq`: `hcloud_server.web["web-1"]` present (positive evidence the right
     state object loaded), and every present `["web-1"]` workspaces instance's `id` equals the pin —
     so a typo'd id can never forget a live object;
  3. `terraform state rm` each present `["web-1"]` workspaces address (both, one, or none —
     `already_forgotten`);
  4. post-`state list` equals the pre-list minus exactly the removed lines.
- Census: `test-infra-privileged-tier-census.sh`'s `STATE_WRITE` pattern widens to
  `terraform\s+(apply|destroy|state\s+(rm|mv|push))` so this job is classified as a state writer
  (G1h), and `terraform-target-parity.test.ts`'s `TERRAFORM_VERSION` parity covers this workflow.
  ADR-241 D2 gains a one-line note: `infra-privileged` now also serves one dispatched state-forget.
- Recovery when a newer pending apply replaces this pending run in the group: re-dispatch it.

### D. The delete→PR-B window: pause the two push-apply workflows (no new guard)

Between the delete and PR B's merge, config still lists `["web-1"]` while reality (and, after the
forget, state) does not. Every push apply of this root reaches `hcloud_volume.workspaces` through
`-target` transitivity (`hcloud_firewall_attachment.web` → `hcloud_server.web` → `user_data` →
`hcloud_volume.workspaces[each.key]`) and would plan `+create` of a fresh plaintext volume — and the
shared destroy-guard deliberately stopped counting volume creates in #6919 (test T55), because a halt
on them fired on valid dispatches. A new filter surface would reverse that decision and add an edit
to a file 725 bytes under its size cap. Instead, for the window only:

1. Before D: `gh workflow disable apply-web-platform-infra.yml` and
   `gh workflow disable apply-deploy-pipeline-fix.yml`, recorded in the run log of the session.
2. After PR B merges: `gh workflow enable` both, then `gh workflow run apply-web-platform-infra.yml
   -f reason='#6604 post-PR-B apply'` (the default `manual-rerun` arm applies exactly what the skipped
   push apply would have), and confirm it plans no `hcloud_volume.workspaces` / attachment address.

The dispatched arms of `apply-web-platform-infra.yml` are unavailable while it is disabled; the
runbook says so, and says an operator-local apply must not run in the window.

### E. PR B — convergence (diff prepared before D, evidence filled after)

- `server.tf`: `locals { plaintext_workspaces_hosts = { for k, v in var.web_hosts : k => v if k != "web-1" } }`;
  both `for_each`s use it; `workspaces_volume_id` for web-1 becomes a sentinel literal
  (`"retired-6604"`) with a comment: web-1's `user_data` is `ignore_changes`, web-1 replace is refused
  (`apply-web-platform-infra.yml`, "LUKS-pinned host"), and a rebuild would now emit
  `workspaces_mount fatal` instead of mounting a stale copy; #9123/#6931 own web-1's boot path. Not the
  LUKS id: that would put the sole-copy LUKS volume into every push apply's `-target` closure.
- `placement-group.tf` historical `moved` blocks: unchanged (validated harmless).
- Delete `.github/workflows/workspaces-plaintext-forget.yml` (its addresses no longer exist).
- `scripts/encryption-posture-ledger.json`: re-scope the `hcloud_volume.workspaces` row to the web-2
  instance (empty, serving-weight 0) — `tracking_issue: #6931`, new `expires_on` ≤ 90 days, evidence by
  content anchor (not `server.tf:1569`). **Deadline:** the current row expires 2026-10-22 and the lint
  fails an expired exception; if D wedges past ~2026-10-15, re-scope the row in its own docs PR first.
- Destruction record completed from the single marker row + run ids — **before** the ADR flip.
- ADR-119 `status: accepted` + addendum "the plaintext backstop is retired" (run ids, marker row,
  API 404, state diff).
- Legal-register sweep (CLO-attested at ship): `article-30-register.md` PA-1 (g)(17) and PA-2
  (g)(21) — in-cell correction plus a `**Superseded <date> (#6604)**` marker, interval anchored
  "from the 2026-07-23 cutover until <date>"; `audits/2026-07-counsel-review-6588.md` addendum and a
  `residual_cured` frontmatter key, `accepted_residual` kept as history; `nfr-register.md` Compute row.
  **Do not** touch published `docs/legal/**` (no "we destroyed the copy" sentence, no Last-Updated
  bump, no widening of the LUKS clause — web-2, `git_data` and the Redis backstop are still plaintext),
  and do not touch `audits/2026-09-counsel-review-8248.md` (#8285's volume).
- `knowledge-base/operations/expenses.md` (the plaintext volume row is decommissioned; the LUKS row's
  "net-new only during the transition" note resolves), and
  `knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-job-rationale.md` where it
  names `hcloud_volume.workspaces[*]`.
- `model.c4` `workspacesVolume` description: the backstop is gone.
- Runbook step 7 marked done with evidence.
- PR body: `Closes #6604`, `Closes #6588`; #6897 comment updating item 1 (workspaces web-1 retired;
  web-2 → #6931; `git_data` untouched).

## Implementation Phases

### Phase 1 — Guard contract and RED tests first (`cq-write-failing-tests-before`)

1. `apps/web-platform/infra/workspaces-luks-wipe.test.sh` on `workspaces-luks-harness.sh`: every Guard
   Contract row as a case (stubs whitelist real flags, exit 64 on unknown ones), `harness_floor`
   pinned to the measured count.
2. `workspaces-luks-loopback.test.sh`: small loop devices (e.g. 64 MiB plus an odd tail) with a real
   `mkfs.ext4 -L workspaces_plain`; the real W9→W12 path (control sees `53 ef`; `blkdiscard -z`
   zeroes; read-back passes); a non-zero byte at a random offset > 1 MiB after zeroing must RED; an
   interrupted zero (first MiB only, `PLAINTEXT_WIPE_BEGUN` set) must resume on the re-zero arm.
3. `workspaces-luks-cutover-workflow.test.sh` (job set `{preflight, cutover, wipe}`; the `cutover`
   predicate; `wipe`'s unconditional environment; the success-row parser), `workspaces-luks-header.test.sh`
   (H17 unchanged and green), a new workflow test for `workspaces-plaintext-forget.yml`, the tier
   census, and `terraform-target-parity.test.ts`.

### Phase 2 — Script

`wipe_plaintext()`, `emit_wipe()` (own marker name; bare `echo` + `logger -t "$LUKS_LOG_TAG"`),
the mode block, the `cleanup()` arm, the ROLLBACK (and, if reachable, `arm_dead_man`) refusals, and the
header comment (the "WIPE … authored in the Phase-5 soak/converge dispatch" note now points here).

### Phase 3 — Workflows

`workspaces-luks-cutover.yml`: inputs, preflight order + `api_state` + banner, the `cutover` rehearsal
wiring, the `wipe` job, summary. `workspaces-plaintext-forget.yml`. The census regex widening and the
version-parity coverage. `actionlint` on both workflows.

### Phase 4 — Docs (PR A)

- Runbook step 7: the exact commands (rehearsal, pause, dispatch, forget, resume, un-pause), the one
  approval, the merge freeze, and a verdict table with columns *reason → irreversible act done? →
  safe to re-dispatch the same command? → next action*; the job summary prints the runbook anchor for
  the reason that fired.
- ADR-119 addendum (status stays `adopting`): the mode; the AP-009 basis — *a superseded copy frozen
  at the 2026-07-23 cutover (run 29995956562), which the live volume was certified to hold at least
  the contents of, green-verified daily since, soak passed 2026-09-24* — never "a duplicate"; the
  AP-001 deviation (the delete is an API act because Terraform cannot zero a device; state follows
  by `state rm`); the two-PR ordering and the Terraform measurements behind it; the window pause
  instead of a guard (and why #6919/T55 stands); that the destructive wipe is not reachable from the
  `cutover` job, which keeps the 2026-07-19 operand rule; and that the `wipe` job's delivery block is
  a copy of `cutover`'s, exercised for the first time by D.
- ADR-241 D2 one-line note (`infra-privileged` also serves a dispatched state-forget).
- `model.c4`: the `github -> hetzner` edge (the cutover workflow now also detaches and deletes a volume
  via the Tier-B token) and the `hetzner -> cloudflare` edge (W5 downloads the header, not only
  uploads it). Run the C4 syntax, render and count-parity tests.
- `knowledge-base/legal/audits/workspaces-plaintext-destruction-record.md`, `status: template`,
  dated, worded as a precondition, carrying the CLO's field set: timing and authority (UTC times, run
  ids, approver, the quoted go-ahead); target identity (id, name, size, `linux_device`, server,
  `format`, label, the W6 fields vs the backing device); method and proof (W8, W9 incl. `dumpe2fs`
  times, W10 without `-f`, W11 bytes == size, no signature after); live data recoverable at wipe time
  (W3/W4/W5); Hetzner deletion (action id, `204`, `404`, server volumes `== [106443278]`, state diff);
  personal data destroyed (source and git history incl. third-party commit authors — **count only**,
  never names or ids); lawful basis Art. 5(1)(e), 17(1)(a), 32(1) and the AP-009 addendum;
  recoverability: none; other copies (live LUKS; web-2 empty #6931; plaintext `git_data` #6897; the
  root-disk snapshot deleted under #8734; the CLEAN_STRAY stray deleted 2026-07-19); the count of
  Art. 17 account deletions on live between 2026-07-23 and the wipe, or the pre-onboarding bound
  (first arms-length onboarding 2026-08-06) if it cannot be measured.
- `.github/CODEOWNERS` rows for the new workflow and suite, if the file's conventions require them.
- `plugins/soleur/test/preflight-discoverability-test.test.ts`: bump `BASELINE_DECLARED_PROBES` for
  this plan's `credentials_required` declaration, with the PLACEMENT/TRUTH/NO-SUBSTITUTE comment.

### Phase 5 — Ship PR A, prepare PR B, then STOP

1. Merge PR A. The merge fires the routine `web-platform-release.yml` container release on web-1 (its
   filter is `apps/web-platform/**`) and a push apply with no workspaces changes; neither restarts or
   replaces the host. Wait for both.
2. Push PR B's diff (server.tf narrowing, sentinel, forget-workflow deletion, ledger row) as a
   **draft** PR, evidence sections marked pending.
3. Same day: `gh workflow run workspaces-luks-verify.yml` → `success` with
   `SOLEUR_WORKSPACES_READYZ ready=true … workspace_count=<n> expected=<m>` — the baseline.
4. Rehearsal, autonomous (read-only; ADR-119 rehearsal authorization), from the merged commit with no
   deploy or cutover run in between:
   `gh workflow run workspaces-luks-cutover.yml -f confirm=WIPE-PLAINTEXT-USER-DATA-AP-009 -f wipe_plaintext=true -f expected_plaintext_volume_id=105149570`
   Watch it to completion (`hr-dispatch-async-must-arm-watch`).
5. **Stop and ask the operator** (`hr-menu-option-ack-not-prod-write-auth`) for one go-ahead covering
   a named, finite command set, quoting the rehearsal's `rehearsal_ok` row and run id, the baseline,
   the accepted residual (the LUKS volume becomes the only copy), and the draft PR B link:
   - pause: `gh workflow disable apply-web-platform-infra.yml` and `gh workflow disable apply-deploy-pipeline-fix.yml`;
   - the dispatch: `gh workflow run workspaces-luks-cutover.yml -f confirm=WIPE-PLAINTEXT-USER-DATA-AP-009 -f wipe_plaintext=true -f dry_run=false -f expected_plaintext_volume_id=105149570`;
   - the one `workspaces-luks-cutover` environment approval — the operator clicks it, or explicitly
     delegates it, in which case the agent approves via `pending_deployments` only after checking the
     preflight banner's id, name, server and `api_state` against the pin;
   - the forget: `gh workflow run workspaces-plaintext-forget.yml -f confirm=FORGET-RETIRED-PLAINTEXT-VOLUME -f expected_plaintext_volume_id=105149570`;
   - re-running any of these same commands for a resume arm (`re-zero`, `detached`, forget-only);
   - after PR B merges: `gh workflow enable` both workflows and the `manual-rerun` dispatch.
   The ask also states: releases queue behind the `wipe` job (they share `web-1-swap`), so no merge
   under `apps/web-platform/**` should land during D; PR B merges the same day.

### Phase 6 — After the go-ahead (operator-authorized D), verify off-host, then PR B

1. Pause the two workflows; dispatch D; arm a watch; approve (or wait for the approval).
2. Dispatch the forget workflow; watch it.
3. Verify: `GET /volumes/105149570` → `404`; `GET /servers/123931471` → `volumes == [106443278]`;
   `GET /volumes?name=soleur-web-platform-data` → `[]`; a fresh `workspaces-luks-verify.yml` run
   `success` with `ready=true` and `workspace_count >= expected` (report the delta against the
   baseline); no new `op:workspaces-luks-drift` Sentry event; the Better Stack web-1 monitor shows no
   downtime.
4. Finish PR B (§E), CLO-attested; merge the same day; `gh workflow enable` both; dispatch the
   `manual-rerun` apply; post-merge `scheduled-terraform-drift.yml` green.
5. Comment evidence on #6604 and #6588; confirm the next sweeper run PASSes and closes #6604.

## Files to Edit

**PR A**

- `apps/web-platform/infra/workspaces-cutover.sh` — `wipe_plaintext()`, `emit_wipe()`, the mode block,
  the `cleanup()` arm, the ROLLBACK (and, if reachable, `arm_dead_man`) refusals, header comment.
- `.github/workflows/workspaces-luks-cutover.yml` — inputs, preflight, the `cutover` rehearsal wiring,
  the `wipe` job, summary.
- `tests/scripts/test-infra-privileged-tier-census.sh` — `STATE_WRITE` widened to `state (rm|mv|push)`.
- `plugins/soleur/test/terraform-target-parity.test.ts` — `TERRAFORM_VERSION` parity covers the forget
  workflow.
- `apps/web-platform/infra/workspaces-luks-loopback.test.sh`,
  `apps/web-platform/infra/workspaces-luks-cutover-workflow.test.sh`; `workspaces-luks-header.test.sh`
  only if an assertion must learn the new job (H17 itself must stay green unchanged).
- `knowledge-base/engineering/operations/runbooks/workspaces-luks-cutover-6604.md` — step 7.
- `knowledge-base/engineering/architecture/decisions/ADR-119-luks-at-rest-for-the-live-workspaces-volume.md` — addendum.
- `knowledge-base/engineering/architecture/decisions/ADR-241-terraform-credentials-are-tiered-main-only-environment-secrets.md` — D2 note.
- `knowledge-base/engineering/architecture/diagrams/model.c4` — `github -> hetzner`, `hetzner -> cloudflare`.
- `plugins/soleur/test/preflight-discoverability-test.test.ts` — `BASELINE_DECLARED_PROBES`.
- `.github/CODEOWNERS` — only if its conventions cover new workflows/suites.

**PR B**

- `apps/web-platform/infra/server.tf`, `scripts/encryption-posture-ledger.json`, ADR-119 (status +
  addendum), `knowledge-base/legal/article-30-register.md`,
  `knowledge-base/legal/audits/2026-07-counsel-review-6588.md`,
  `knowledge-base/engineering/architecture/nfr-register.md`, `knowledge-base/operations/expenses.md`,
  `knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-job-rationale.md`,
  `model.c4` (`workspacesVolume`), the runbook, the destruction record; delete
  `.github/workflows/workspaces-plaintext-forget.yml` and its workflow test.

## Files to Create

- `apps/web-platform/infra/workspaces-luks-wipe.test.sh` (PR A)
- `.github/workflows/workspaces-plaintext-forget.yml` and its workflow test (PR A; deleted in PR B)
- `knowledge-base/legal/audits/workspaces-plaintext-destruction-record.md` (PR A template; PR B completes)

## Infrastructure (IaC)

### Terraform changes

None in PR A (`*.tf` untouched). PR B narrows the `for_each` of `hcloud_volume.workspaces` and
`hcloud_volume_attachment.workspaces` in `apps/web-platform/infra/server.tf` and replaces web-1's
`workspaces_volume_id` with a sentinel. No new provider, variable or secret. The volume deletion is an
API act, not a Terraform one: Terraform cannot zero a device, and C5 requires the verified zeroing to
precede the delete (recorded as an AP-001 deviation in the ADR-119 addendum).

### Apply path

`workspaces-luks-cutover.yml` `wipe` (reviewer-gated) → `workspaces-plaintext-forget.yml` (`state rm`,
serialized on `terraform-apply-web-platform-host`) → PR B → re-enabled push applies plan no
`hcloud_volume.workspaces` / attachment address. No `-replace`, no host re-provision, no reboot;
expected downtime zero.

### Distinctness / drift safeguards

- `prevent_destroy` stays on `hcloud_volume.workspaces` (web-2 keeps it); the converge never plans a
  delete because state no longer holds web-1's instances.
- The two push-apply workflows are paused for the delete→PR-B window, so nothing re-creates a
  plaintext volume through `-target` transitivity.
- The forget binds to the physical id (state instance id == pin) and requires positive evidence of the
  right state object before removing anything.
- `scheduled-terraform-drift.yml` reports `+create` for the two web-1 addresses only inside the window.

### Vendor-tier reality check

Hetzner Cloud has no volume snapshots (nothing to retain or clean up) and bills a deleted volume up to
the hour. `DELETE /volumes/{id}` requires the volume detached and `protection.delete == false`
(measured `false` on 105149570, 2026-09-28).

## Architecture Decision (ADR/C4)

### ADR

Amend **ADR-119** (no new ADR): PR A adds an addendum recording the mode, the AP-009 basis (a
superseded copy, never "a duplicate"), the AP-001 deviation, the two-PR ordering and the Terraform
measurements behind it, the window pause (and why #6919/T55's decision stands), and how the
2026-07-19 operand rule is kept. Status stays `adopting`; PR B flips it to `accepted` after the
destruction record is complete. **ADR-241** gets a one-line D2 note: `infra-privileged` now also
serves one dispatched state-forget workflow.

### C4 views

All three model files were read for this plan. `model.c4` already models every actor and system
involved: `github` (system), `hetzner` (container "Compute"), `cloudflare` (system), and
`workspacesVolume` (database, "guest-side LUKS2, mounted /mnt/data via /dev/mapper/workspaces");
`views.c4` includes `platform.infra.hetzner`, `platform.infra.workspacesVolume`, `github` and
`cloudflare`; `spec.c4` needs no new element kind. No external human actor is added and no access
relationship changes. Description edits:

- PR A: `github -> hetzner` — `workspaces-luks-cutover.yml` no longer only looks up a volume id; it
  also detaches and deletes one through the Tier-B token. `hetzner -> cloudflare` — the header object
  is also downloaded (W5), not only uploaded.
- PR B: `workspacesVolume` — the retained plaintext volume was zeroed and deleted (date, run id).

Neither edit moves a cardinality in edge prose, but both PRs run
`plugins/soleur/test/c4-count-parity.test.sh`, `apps/web-platform/test/c4-code-syntax.test.ts` and
`apps/web-platform/test/c4-render.test.ts`.

### Sequencing

The addendum is written in PR A describing the target state; the status flip waits for the dispatch
evidence (PR B). Neither is deferred to a separate issue.

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Converge Terraform in PR A, before the wipe | Every plan of this root proposes deleting a live `prevent_destroy` volume → `Instance cannot be destroyed` (targeted push applies wedge). |
| `moved` → singleton, then `removed` | Every `-target` plan errors until an untargeted apply; this root has none. Reproduced. |
| A create-guard surface on the shared destroy-guard filter for the window | Reverses #6919/T55 (volume creates were removed from the halt because they fired on valid dispatches), needs an edit to a file 725 bytes under its cap, and guards a window a two-command pause covers. |
| Host zeroing in the `cutover` job + a gated finalize job (two approvals) | The write-token proof would run after the zeroing, and census Guard 1 bars the loader from a job whose `environment:` has an `''` arm. |
| `state rm` as a job in the cutover workflow | Holds `web-1-swap` then the host group — the inverted lock order that can deadlock against `apply-deploy-pipeline-fix.yml`. |
| A new `apply_target` in `apply-web-platform-infra.yml` for the forget | The file is 725 bytes under its 490,000-byte cap. |
| `state rm` by an agent from a laptop | Unserialized against `terraform-apply-web-platform-host` on a lockless backend; unaudited. |
| Keep the plaintext copy (it is "only" stale) | P1; it holds every workspace as of 2026-07-23 and defeats every erasure since. |
| Generalize the mode for #8285 (Redis AOF) | Different host, script and backstop; build it when that work is scheduled. |

## User-Brand Impact

- **If this lands broken, the user experiences:** every user's workspace source code gone
  (`/workspaces/<id>` empty) if `blkdiscard -z` hits the device backing `/dev/mapper/workspaces` — the
  data is sole-copy (no remote, no checkpoint push), so this is unrecoverable.
- **If this lands broken, the user experiences:** a later header corruption or passphrase drift that
  would have been survivable becomes permanent loss, if the wipe runs while escrow is broken (W4/W5
  exist for this).
- **If this lands broken, the user experiences:** app.soleur.ai down (web-1 is the sole origin) if a
  detach or a post-wipe `rollback=true` tears down the live mount.
- **If this leaks, the user's data is exposed via:** a "wipe" that zeroed nothing (a no-op
  `blkdiscard`, a page-cache read-back) followed by an API delete — Hetzner reallocates the blocks
  with the plaintext intact and no attestation (C5). The full-device direct-IO read-back is the control.
- **If this leaks, the user's data is exposed via:** a Terraform apply in the delete→PR-B window
  birthing a fresh plaintext volume that a later rebuild could mount (the two push-apply workflows
  are paused for the window).
- **Brand-survival threshold:** `single-user incident`

**Accepted residual risk (stated, not hidden).** Today the stale 2026-07-23 plaintext copy is, weakly,
the only fallback behind the LUKS volume. After the wipe the LUKS volume holds the **only** copy of
every workspace, with no snapshot and no backup. That is accepted deliberately — a retained plaintext
copy is the exposure #6588 exists to close, and a snapshot would be a third copy — and it is tracked
where it belongs: #5274 (workspace durability), #8625 (no Hetzner host declares backups), #6964 (a
web-1 rebirth strands the LUKS attachment). W4/W5 exist so the wipe never runs while that sole copy is
unrecoverable.

**What users gain.** The wipe completes erasure for anyone whose workspace was deleted on the live
volume after 2026-07-23: the retained copy currently defeats that deletion. The Art. 5(2) destruction
record evidences it.

**A failed run between the host step and the API step leaves users unaffected.** The zeroed volume is
unmounted and unused; the API steps run only on a proven `wiped` row, and a re-dispatch resumes at the
right arm (`already_wiped`, `already_wiped_detached`, or the 404 forget-only arm) without re-zeroing
or touching the live mount.

CPO sign-off: **granted with conditions** (Phase 2.5) — the three items above, a same-day
`workspaces-luks-verify.yml` baseline before the go-ahead (Acceptance Criteria → Dispatch), and a
rehearsal from the same merged commit with no deploy or cutover run in between.
`soleur:engineering:review:user-impact-reviewer` runs at review time.

## Observability

```yaml
liveness_signal:
  what: SOLEUR_WORKSPACES_LUKS_WIPE marker row (result=rehearsal_ok|wiped|already_wiped|already_wiped_detached|refused) on the luks-monitor syslog tag, shipped by Vector to Better Stack; plus the workflow run summary
  cadence: per dispatch (the mode runs once for real; rehearsals on demand)
  alert_target: Sentry (feature=workspaces-luks op=workspaces-luks-drift, via emit_drift on every refusal) and the failed-run notification to the dispatcher
  configured_in: apps/web-platform/infra/workspaces-cutover.sh (emit_wipe, emit_drift) and .github/workflows/workspaces-luks-cutover.yml (summary + job outputs)

error_reporting:
  destination: Sentry project of the luks-monitor emitter (workspaces_luks_emit reads the baked SOLEUR_SENTRY_DSN on web-1)
  fail_loud: result=refused reason=<slug> row printed BEFORE die, a ::error:: annotation naming the reason, and a non-zero job conclusion; the wipe job prints ::error:: on any unexpected API status and the forget workflow on any identity or state-list mismatch

failure_modes:
  - mode: target identity ambiguous (target is the mapper backing device, held, mounted, wrong size, not ext4)
    detection: W6 refusal row + Sentry drift event, before any write
    alert_route: Sentry + failed run
  - mode: escrow not recoverable at wipe time (passphrase or off-host header)
    detection: W4/W5 refusal rows
    alert_route: Sentry + failed run; runbook routes to the header-recovery path, never to the wipe
  - mode: zeroing did not take (no-op or partial)
    detection: W11 read-back cmp over every byte, O_DIRECT, after flushbufs
    alert_route: Sentry wipe_readback_nonzero + failed run; the API steps never run (they need exactly one wiped row)
  - mode: token lacks write permission (ADR-241 O5 legacy arm)
    detection: the labels PUT probe returns 403 before the wipe job reaches web-1
    alert_route: failed wipe job with nothing irreversible done; re-dispatch once the loader exports a write token
  - mode: the two push-apply workflows left paused after PR B merges (the window never closed)
    detection: PR B's acceptance criterion reads gh workflow view state == active for both; the next infra merge produces no apply run
    alert_route: the PR B ship checklist; scheduled-terraform-drift.yml keeps reporting the unapplied change until a manual-rerun
  - mode: zeroing interrupted (SSH drop, job timeout, cancel) before the wiped row
    detection: the job fails without a wiped row; the persisted PLAINTEXT_WIPE_BEGUN marker makes the next dispatch resume (arm=interrupted) instead of refusing, and the cleanup() row reads outcome=wipe_aborted mode=wipe
    alert_route: failed run + Better Stack row; runbook resume table
  - mode: state forget cancelled or failed after the delete (a newer pending apply replaced it in the concurrency group)
    detection: the forget run cancelled/failed; the drift job reports +create of the two web-1 addresses and PR B's infra-validation plan fails prevent_destroy
    alert_route: failed or cancelled run + drift issue; re-dispatch runs the forget-only arm (api_state=absent) with no approval
  - mode: web-1 serving degraded after the detach
    detection: workspaces-luks-verify.yml (daily schedule + post-dispatch run) and the luks-monitor heartbeat
    alert_route: ci/luks-verify issue + ops email (drift/readiness classes)

logs:
  where: GitHub Actions run logs (cutover workflow preflight/wipe, forget workflow), web-1 syslog tag luks-monitor -> Vector -> Better Stack source 2457081
  retention: Actions logs 90 days; Better Stack per the source retention plus archive

discoverability_test:
  command: bash scripts/betterstack-query.sh --since 30d --grep SOLEUR_WORKSPACES_LUKS_WIPE
  expected_output: "SOLEUR_WORKSPACES_LUKS_WIPE"
  credentials_required: "Better Stack Logs query credentials (BETTERSTACK_QUERY_*) — the marker lives only in the host log stream; no unauthenticated endpoint exposes a wipe's outcome"
```

## Encryption Posture

```yaml
at_rest:
  - store: hcloud_volume.workspaces_luks (web-1 /workspaces, volume 106443278)
    mechanism: luks
    evidence: implied by device_binding in scripts/encryption-posture-ledger.json (unchanged by this plan)
    defends_against: a seized, RMA'd or snapshot-imaged Hetzner block volume
    does_not_defend: an app-layer read on the unlocked live host, a leaked WORKSPACES_LUKS_KEY, or root on web-1
    disclosed_as: docs/legal/privacy-policy.md (the re-scoped LUKS clause published by #6938)
    live_verification: available
  - store: hcloud_volume.workspaces (after PR B, the web-2 instance only, volume 106466179)
    mechanism: plaintext-exception
    evidence: apps/web-platform/infra/server.tf — resource "hcloud_volume" "workspaces", format = "ext4", no LUKS apparatus
    defends_against: nothing at the volume layer; the volume is empty and web-2 carries serving-weight 0
    does_not_defend: any workspace data written to web-2 before its guest-side LUKS path lands
    disclosed_as: not-publicly-claimed
    live_verification: unavailable:no probe reads web-2's volume contents; tracked #6931
in_transit:
  - connection: GitHub Actions runner -> api.hetzner.cloud (detach, delete, labels PUT)
    enforced_at: .github/workflows/workspaces-luks-cutover.yml wipe job API step (curl -fsS https://api.hetzner.cloud/v1/..., no -k)
    tls: HTTPS, TLS 1.2+
    cert_verification: on
    does_not_defend: a compromised runner or a leaked HCLOUD_TOKEN, which can delete any project resource
    disclosed_as: not-publicly-claimed
exception:
  justification: web-2's per-host workspace volume stays plaintext because the fresh-host guest-side LUKS path is deferred; it is empty and takes no traffic
  tracking_issue: "#6931"
  reevaluate_when: web-2 is LUKS-enabled and pooled, or takes any serving weight
  expires_on: 2026-12-27
```

## Guard Contract

Each row is encoded as a case in the named suite (stubbed in `workspaces-luks-wipe.test.sh`, real
devices in the loopback suite, YAML-parsed in the workflow tests) — the matrix is the test list, not a
separate ritual.

### Guard 1 — the zeroed device is the plaintext volume and never the mapper's backing device

**Property.** `blkdiscard` is executed on exactly one device, and that device is the pinned plaintext
volume, distinct from the device backing `/dev/mapper/workspaces`.

**Assembly.** Chokepoint: `wipe_plaintext()` — the only `blkdiscard` call site in
`workspaces-cutover.sh` (a census row asserts the file has exactly one). Inputs flow from
`inputs.expected_plaintext_volume_id` → `preflight` API classification → the `wipe` job's `.env`
(`WORKSPACES_PLAINTEXT_DEV`, `_VOLUME_ID`, `_SIZE_BYTES`) → W1/W3/W6. Every arm that can zero runs
W3–W7; W6's label check applies to the first-wipe arm.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | stub `cryptsetup status` so the backing device resolves to the same realpath as the target | RED `wipe_target_is_mapper_backing`, no `blkdiscard` in `$CALLS` |
| 2 | same major:minor through a different path (symlink alias) | RED |
| 3 | `blkid -p` reports `crypto_LUKS` for the target | RED `wipe_target_not_ext4` |
| 4 | a holder under `/sys/class/block/<k>/holders/` | RED `wipe_target_held` |
| 5 | target size differs from the API size by one GiB | RED `wipe_target_size_mismatch` |
| 6 | `WORKSPACES_PLAINTEXT_DEV` = `/dev/disk/by-id/scsi-0HC_Volume_*` (glob), or a different id than `_VOLUME_ID` | RED `wipe_input_invalid` |
| 7 | first-wipe arm with label ≠ `workspaces_plain` | RED `wipe_target_label_mismatch` |
| 8 | a `.mount` unit in the target device unit's reverse dependencies; and separately an unloaded device unit | RED `wipe_target_has_dependents` (both) |
| 9 | re-zero arm (`PLAINTEXT_WIPE_BEGUN` set) with the target made the mapper backing device | RED — identity checks run on the re-zero arm too |
| 10 | a second `blkdiscard` call site added anywhere in the script | RED (census row) |
| 11 | `blkdiscard -f` or `--force` anywhere | RED |
| 12 | own dispatch: the mode block deleted so `CONFIRM_WIPE=1` falls through to the L3 cutover | RED (the suite requires a `SOLEUR_WORKSPACES_LUKS_WIPE` row, not merely "no blkdiscard") |
| H1 | harness: the `blkdiscard` stub records nothing | RED (floor + a must-PASS case asserting exactly one recorded call on the happy path) |
| H2 | must-PASS: a valid target whose by-id link is a relative symlink to `../../sdc` | GREEN |

### Guard 2 — the rehearsal and the ungated-capable job cannot destroy

**Property.** No `blkdiscard`, detach or delete is reachable with `inputs.dry_run=true` (or
`DRY_RUN=1`), and the `cutover` job can never deliver a destructive wipe.

**Assembly.** Script: the `DRY_RUN` return between W9 and W10, and no `DRY_RUN=` assignment in the
wipe block. Workflow: `wipe.if` requires `!inputs.dry_run`; `cutover`'s `CONFIRM_WIPE` value is
`wipe_plaintext && dry_run`; `cutover`'s `environment:` expression is byte-identical.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | move the `DRY_RUN` return below `blkdiscard` (a REORDER, not a delete) | RED — the case reads `$CALLS` for `blkdiscard` with `DRY_RUN=1` |
| 2 | add `DRY_RUN=0` inside the `CONFIRM_WIPE` block | RED |
| 3 | drop `!inputs.dry_run` from `wipe.if` | RED (workflow test) |
| 4 | `cutover`'s `CONFIRM_WIPE` value becomes `inputs.wipe_plaintext` alone | RED |
| 5 | a `wipe_plaintext` operand added to `cutover`'s env expression | RED (exact pin) |
| 6 | own dispatch: a rehearsal that stops at W2 counts as PASS | RED — the `rehearsal_ok` row must carry the W3–W9 fields |
| H1 | harness: the `DRY_RUN=1` case with `DRY_RUN` unset in the stub env | RED (default path asserted too) |

### Guard 3 — the read-back can fail

**Property.** A device that is not all-zero over its full size after W10 yields `wipe_readback_failed`
and no `result=wiped` row.

**Assembly.** W9 (positive control), W11 (the read, `cmp`-decides classification, `PIPESTATUS` into
plain variables), W12 (the marker). The loopback suite exercises the real kernel path; the stubbed
suite the rc plumbing.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | loopback: one non-zero byte at a random offset beyond the first MiB after zeroing | RED, `cmp_rc=1` on the row |
| 2 | loopback: the compare limit one byte short of the device | RED |
| 3 | stub: `cmp` exits 1 while `dd` exits 141 (EPIPE from the early close) | RED `wipe_readback_failed` with `cmp_rc=1` — never classified by `dd` |
| 4 | stub: `cmp` exits 0 while `dd` exits 1 | RED |
| 5 | the read-back moved into `$( )` so its rc is lost | RED (the stubbed case forces rc=1 and asserts the refusal row) |
| 6 | positive control removed (W9) | RED — an all-zero device on the first-wipe arm must refuse `wipe_positive_control_failed` |
| H1 | must-PASS: a correctly zeroed loop device of a non-power-of-two size | GREEN |

### Guard 4 — the forget binds to the physical volume and to reality

**Property.** `workspaces-plaintext-forget.yml` removes a `["web-1"]` workspaces address from state only
when the pinned volume is gone from Hetzner and the state instance's id equals the pin, and removes
nothing else.

**Assembly.** The workflow's single job: the `404` + empty name lookup step, the `state pull | jq`
identity step, the `state rm` step, the pre/post `state list` diff, its concurrency literal and its
environment.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | pinned id `GET` returns `200` | RED, no `state rm` |
| 2 | name lookup returns one volume while the pinned id `404`s (a typo'd pin) | RED |
| 3 | state instance id ≠ the pin | RED |
| 4 | `hcloud_server.web["web-1"]` absent from the pulled state (wrong state object) | RED |
| 5 | the post-diff removes anything but the web-1 workspaces addresses | RED |
| 6 | the concurrency group string differs from the apply workflows' literal, or the job loses `infra-privileged` | RED (workflow test / census) |
| 7 | own dispatch: the `state rm` step deleted — the job reports success with state unchanged | RED (post-diff must show the removal, or `already_forgotten` with both addresses absent in the pre-list) |
| H1 | must-PASS: one of two addresses present, pin `404` | GREEN, removes the one |
| H2 | must-PASS: both already absent | GREEN `already_forgotten`, no mutation |

### Guard 5 — nothing remounts a wiped volume

**Property.** Once `PLAINTEXT_WIPE_BEGUN` or `PLAINTEXT_WIPED` is persisted, a `ROLLBACK=1` run
performs no `umount`, `cryptsetup close` or `docker stop`, regardless of `ROLLBACK_ACK_LUKS_WRITES`.

**Assembly.** `assert_rollback_not_post_cutover()` is the only entry to `rollback()` in ROLLBACK mode;
`cleanup()` never calls `rollback()` on a wipe run (it keys on globals the wipe never sets);
`arm_dead_man` if reachable.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | move the marker check after the ack short-circuit (REORDER) | RED — ack=1 must still refuse |
| 2 | key the check on `PLAINTEXT_WIPED` only | RED — a `BEGUN`-only state must refuse too |
| 3 | an aborted wipe (`die` at W11) with `CANARY_OK` persisted: `cleanup()` records `outcome=wipe_aborted mode=wipe` and calls neither `rollback` nor `docker start` | RED if either appears in `$CALLS` |
| 4 | the refusal omits the explicit row, so the run records `outcome=pre_freeze` | RED |
| H1 | must-PASS: a ROLLBACK with no wipe markers behaves exactly as today | GREEN |

### Guard 6 — the API acts only on proven zeroing with a proven write token

**Property.** Detach and delete run only after the write token is proven and exactly one success row
for the pinned id, matching `api_state`, is observed in the same job.

**Assembly.** The `wipe` job's step order (re-GET → probe → host → API) and its row parser.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | two success rows in the log (a replayed line) | RED — the job fails before any API write |
| 2 | row id ≠ pinned id | RED |
| 3 | `api_state=detached` with a `wiped` row, or `attached` with `already_wiped_detached` | RED |
| 4 | the labels-`PUT` probe moved after the host step (REORDER) | RED (step-order assertion) |
| 5 | the host step skipped on `detached` | RED — a hand-detached, never-wiped volume must be refused, never deleted |
| H1 | must-PASS: `api_state=detached`, marker present → `already_wiped_detached` → `DELETE` | GREEN |

## Acceptance Criteria

### PR A (pre-merge)

- [ ] `CONFIRM_WIPE=1` reaches a mode block that runs `wipe_plaintext()`; every refusal it raises
      emits a `SOLEUR_WORKSPACES_LUKS_WIPE result=refused reason=<slug>` row before `die`, and a
      refusal from a reused helper yields `outcome=wipe_aborted mode=wipe`.
- [ ] Guards 1–6: every row present as a case in its suite and passing; `workspaces-luks-wipe.test.sh`
      carries a `harness_floor` at the measured count.
- [ ] The loopback suite (privileged, real loop devices) passes the zeroing, read-back, mutation and
      interrupted-zero arms.
- [ ] Green: `workspaces-luks-freeze.test.sh`, `-staging`, `-verify`, `-header`, `-cutover-workflow`,
      the forget-workflow test, `web-1-swap-concurrency-parity.test.sh` (unchanged),
      `luks-monitor.test.sh`, `tests/scripts/test-workspaces-luks-cutover-gate.sh`,
      `test-destroy-guard-counter-web-platform.sh` (T55 unchanged), the tier census,
      `terraform-target-parity.test.ts`, `actionlint`. Existing floors unchanged or raised.
- [ ] `cutover`'s `environment:` expression is byte-identical to `main` and still the first
      `environment:` line in the file.
- [ ] `git diff --name-only origin/main...HEAD -- '*.tf' tests/scripts/lib/destroy-guard-filter-web-platform.jq .github/workflows/apply-web-platform-infra.yml`
      is empty, and ADR-119's `status:` is unchanged (the sweeper closes #6604 on `accepted`).
- [ ] `infra-validation`'s web-platform plan shows the same add/change/destroy counts as `main`'s
      baseline on the same day and names no `hcloud_volume(_attachment).workspaces` address.
- [ ] Runbook step 7, ADR-119 addendum, ADR-241 note, `model.c4` edges, destruction-record template,
      `BASELINE_DECLARED_PROBES` bump committed; `c4-count-parity`, `c4-code-syntax`, `c4-render` green.

### Dispatch (post-merge, operator-authorized)

- [ ] Same-day `workspaces-luks-verify.yml` baseline: `success`, `ready=true`, `workspace_count=<n>`.
- [ ] Rehearsal from the merged commit, no deploy or cutover run in between: one
      `result=rehearsal_ok arm=first_wipe` row carrying W3 uuid, W6 identity and label, W6b
      dependents, W8 caps, W9 magic and `dumpe2fs` times.
- [ ] Operator go-ahead obtained for the named command set before any of it runs.
- [ ] Real run: one `result=wiped` row for `105149570`; detach action `success`; `204`; final `404`.
- [ ] Forget run: state diff of exactly the two `["web-1"]` workspaces lines (or `already_forgotten`).
- [ ] Off-host: `GET /v1/volumes/105149570` → `404`; server `123931471` volumes `== [106443278]`;
      a post-dispatch `workspaces-luks-verify.yml` run `success` with `ready=true` and
      `workspace_count >= expected`; no new `op:workspaces-luks-drift` Sentry event.
- [ ] web-1 never restarted or replaced during the dispatch window; the Better Stack web-1 monitor
      shows no downtime.

### PR B (post-dispatch)

- [ ] `infra-validation`'s web-platform plan shows `main`'s baseline counts and no workspaces address
      for web-1; after merge, both apply workflows re-enabled (`gh workflow view … --json state` →
      `active`), the `manual-rerun` apply plans no `hcloud_volume(_attachment).workspaces` address,
      `scheduled-terraform-drift.yml` green, and `GET /volumes?name=soleur-web-platform-data` → `[]`.
- [ ] `lint-encryption-posture.py` green with the re-scoped row.
- [ ] Destruction record complete, then ADR-119 `status: accepted`; legal-register sweep
      CLO-attested.
- [ ] #6604 and #6588 closed with evidence; #6897 item 1 updated.

## Domain Review

**Domains relevant:** Engineering, Legal, Product

### Engineering

**Status:** reviewed
**Assessment:** The Terraform ordering (state rm before narrowing; PR B after) is correct and minimal.
The CTO's blocking finding — a job-level host group inside a workflow holding `web-1-swap` inverts the
lock order the apply workflows use and can deadlock — is resolved by moving the state step into its own
workflow. Also folded: a reverse-dependency detach-safety probe (W6b) in place of the meaningless
`What=` compare; W0 requires `aws` rather than installing it; `ionice -c3`; the write-token probe
before web-1 is touched. The CTO confirmed nothing in the dispatch restarts web-1 and noted that PR
merges fire the routine container release (scoped in P8). Its devex pass drove the fixed 240-minute
timeout, the finite go-ahead command set (including resume re-runs and the approval), the draft PR B
before D, and the runbook's re-dispatch-safety columns.

### Legal

**Status:** reviewed
**Assessment:** Sound; no published legal document changes, and `soleur:gdpr-gate` is not triggered
(no migration/auth/API/`.sql` path). Folded in: the AP-009 basis is "a superseded copy frozen at the
2026-07-23 cutover", never "a duplicate"; a `dumpe2fs -h` provenance field; the destruction-record
field set, completed before the ADR flip; the PR-B register sweep (Art. 30 PA-1 (g)(17), PA-2 (g)(21);
counsel review 6588 addendum; NFR Compute row) with the do-not-touch list; an erasure-count or
pre-onboarding-bound field. CLO attests PR B's register changes at ship.

### Product/UX Gate

**Tier:** none (no UI surface in either PR's file list)
**Decision:** reviewed — CPO sign-off granted with conditions (folded into User-Brand Impact and the
Dispatch criteria)
**Agents invoked:** soleur:product:cpo, soleur:product:spec-flow-analyzer
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

#### Findings

- SpecFlow (two passes) found the dead ends (interrupted zeroing, detached-not-deleted,
  deleted-not-forgotten), the lock-order inversion, the probe-after-zeroing ordering, identity checks
  skipped on a re-zero, the host step skipped on `detached`, a `PLAINTEXT_DEV` cross-check keyed on a
  timestamp that does not exist, and a set of bash edges. All resolved in §A–§D: two success arms plus
  named refusals, identity on every zeroing arm, the host step always runs, the cross-check replaced by
  the `workspaces_plain` label, `cmp`-decides classification, `pgrep` for an orphaned zero.
- Plan review (DHH, Kieran, code-simplicity, architecture-strategist, CTO devex): the create-guard
  (reverses #6919/T55, wrong consumer model, byte budget) replaced by a two-workflow pause; the forget
  moved to its own workflow; the keepalive ticker replaced by `ServerAliveInterval`; the timed read and
  the enumerated binary list cut; the `.env` built as a heredoc; the forget bound to the physical id;
  the census regex widened; the `No changes` criterion corrected to `main`'s baseline counts.
- Advisor consult (ADR-083): the finalize path ran its checks after the zeroing — the single gated
  `wipe` job now probes first.
- Functional discovery: no community artifact covers this; build in-house.

## Test Scenarios

- Given a host whose `/mnt/data` is the mapper and a valid pin, when a rehearsal runs, then one
  `rehearsal_ok` row is printed and `$CALLS` has no `blkdiscard`.
- Given the same host, when the real mode runs, then exactly one `blkdiscard -z -v <pinned dev>` call,
  a read-back, and a `wiped arm=first_wipe` row.
- Given a device whose first MiB is zero and `PLAINTEXT_WIPE_BEGUN=<id>:…`, when re-dispatched, then the
  re-zero arm runs W3–W7, zeroes, and ends `wiped arm=re_zero`.
- Given the device absent and `PLAINTEXT_WIPED` for this id, then `already_wiped_detached`; absent
  without it, then `wipe_target_absent_unexplained`.
- Given `api_state=absent`, then preflight refuses and names the forget workflow.
- Given `rollback=true rollback_ack_luks_writes=true` after a wipe (or an interrupted one), then
  `outcome=refused_plaintext_wiped mode=rollback` and no teardown call.
- Given `wipe_plaintext=true clean_stray=true dry_run=true`, then preflight refuses on exclusion first.
- Given `expected_plaintext_volume_id` set on a non-wipe dispatch, then preflight refuses.
- Given a forget dispatch whose pin `404`s but whose state instance id differs, then no `state rm`.

## Open Code-Review Overlap

2 open scope-outs touch `server.tf`: #3216, #2197. **Acknowledge** — both concern unrelated regions
(deploy-pipeline-fix regex canary; billing types). PR A does not edit `server.tf`; PR B edits only the
two `for_each`s and one `user_data` argument.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the
  threshold will fail `deepen-plan` Phase 4.6.
- **Do not flip ADR-119 to `accepted` in PR A.** The sweeper closes #6604 on that string alone.
- **The two push-apply workflows stay paused from D until PR B merges.** While paused, every merge's
  infra change is unapplied until the `manual-rerun` dispatch, and the dispatched arms of
  `apply-web-platform-infra.yml` are unavailable. Keep the window to hours; never leave it overnight.
- **Merging PR A or PR B fires the routine container release on web-1** (`web-platform-release.yml`,
  `apps/web-platform/**`). It is not a host restart or replace; name it in the go-ahead ask so the
  2026-09-28 decision about web-1 is honored knowingly.
- **Releases queue behind the `wipe` job** (shared `web-1-swap`); a third arrival cancels the older
  pending one. No merge under `apps/web-platform/**` during D.
- `HCLOUD_TOKEN` semantics change under ADR-241: the legacy arm exports the read/write token only while
  `HCLOUD_TOKEN_READONLY` is absent. The labels-`PUT` probe makes that visible before web-1 is touched.
- The ledger row `hcloud_volume.workspaces` expires 2026-10-22; the lint fails an expired exception.
