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

## Enhancement Summary

**Deepened on:** 2026-09-28
**Sections enhanced:** Technical Approach §A–§D, Implementation Phases 1/5/6, User-Brand Impact,
Observability, Guard Contract, Acceptance Criteria; new Downtime & Cutover and Risks & Precedents.
**Agents used:** security-sentinel, data-integrity-guardian, observability-coverage-reviewer,
user-impact-reviewer, test-design-reviewer, a verify-the-negative/self-audit pass (on top of the plan
phase's CTO, CLO, CPO, spec-flow ×2, DHH, Kieran, code-simplicity, architecture-strategist, CTO devex
and the ADR-083 advisor). The skill's "run every agent" fan-out was narrowed to the reviewers relevant to
an infra/security plan that had already been through a twelve-agent pass; the narrowing is disclosed
here rather than implied away.

### Key improvements

1. **"Gone" is only believed when presence was shown with the same token** — a token from another
   Hetzner project answers `404`/`[]` for a live volume; preflight, the `wipe` job and the forget
   workflow now prove they can see server 123931471 and volume 106443278 first.
2. **The off-host header is proven restorable, not just present** — the escrowed passphrase opens the
   downloaded header, and a fresh `luksHeaderBackup` must equal it (a UUID survives key changes).
3. **The window pause is enforced, not remembered** — the `wipe` job refuses unless both apply
   workflows are `disabled_manually` with no queued run, and unless a green same-day
   `workspaces-luks-verify.yml` run exists.
4. **No Terraform-state secret can leak from the no-reviewer forget runner** — state is never printed,
   stored or uploaded; the pin is a constant; identity is checked by exact type/name; `serial`/`lineage`
   are verified after the removal.
5. **The stubbed suite cannot reach a real binary or the real prod key** — `PATH` tripwires for
   `blkdiscard`/`dd`/`doppler`/`aws`, a device-resolution seam, reason-slug census, stub fidelity fixes.

### New considerations discovered

- `ionice` is a no-op under `mq-deadline`/`none`; the zero and read-back are capped with a cgroup
  `io.max` limit instead.
- systemd creates one device unit per symlink; W6b now checks every unit sharing the target's
  `SysFSPath`, and `mnt-data.mount`'s own bindings.
- After D the LUKS volume is the only copy and has no delete protection; the recut runbook step is
  marked never-after-step-7 and #6931 gets the protection as a precondition.
- The success row, the `.env` values and the host output are all shell/workflow-command surfaces:
  strict row regex plus `ssh` rc, `::stop-commands::`, `.env` re-validation and duplicate-key refusal.

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
Row format, built in exactly one place (`emit_wipe`, bare `echo` + `logger -t "$LUKS_LOG_TAG"`, every
value through `_vscrub`): `SOLEUR_WORKSPACES_LUKS_WIPE feature=workspaces-luks op=workspaces-luks-wipe
result=<r> arm=<a> volume_id=<id> [key=value …]` — the field order the workflow's success-row parser
anchors on.

**Stage 1 — environment (always):**

| # | Check | Refusal reason |
|---|---|---|
| W0 | util-linux ≥ 2.36 (`blkdiscard --version`, compared as a full `major.minor` version so 3.x passes; the `O_EXCL` guarantee depends on it); `systemd-run` present; `aws` already installed — W0 **never** calls `ensure_aws`, which can `apt-get install` on prod web-1; no `blkdiscard` process running (`pgrep -x blkdiscard` — an SSH drop orphans a running zero, and a re-dispatch would race it) | `wipe_tool_missing` / `wipe_in_progress` |
| W1 | inputs well-formed: id `^[0-9]+$`, dev path == `/dev/disk/by-id/scsi-0HC_Volume_${id}` exactly, size `^[0-9]+$` | `wipe_input_invalid` |
| W2 | `findmnt -no SOURCE /mnt/data` == `$MAPPER` | `wipe_live_mount_not_mapper` |

**Stage 2 — classify the arm.** `blkid -p` exit codes are mapped explicitly (0 signature, 2 none,
8 ambivalent, anything else error); markers are read with `read_state` and must name **this** id.

| Device present? | Signature | Markers for this id | Arm |
|---|---|---|---|
| yes | `ext4` | none | `arm=first_wipe` → Stage 3 in full, including W9 |
| yes | `ext4`, none or ambivalent (never `crypto_LUKS` — an interrupted zero of ext4 cannot create a LUKS header, so a LUKS signature here means the wrong device) | `PLAINTEXT_WIPE_BEGUN` or `PLAINTEXT_WIPED` | `arm=re_zero` → Stage 3 without W9 (an interrupted zero has already cleared the superblock; zeroing a zeroed device is idempotent) |
| no | — | `PLAINTEXT_WIPED` | `arm=detached` → `result=already_wiped_detached`, nothing written |
| yes | none or ambivalent | none | refuse `wipe_target_blank_unexplained` |
| yes | `crypto_LUKS` (any markers), or any other non-`ext4` signature without markers | any | refuse `wipe_target_not_ext4` |
| — | — | markers naming a different id | refuse `wipe_marker_other_volume` |
| no | — | no `PLAINTEXT_WIPED` | refuse `wipe_target_absent_unexplained` |

Under `DRY_RUN=1` every arm reports `result=rehearsal_ok arm=<arm>` with its measured fields and
writes nothing.

**Stage 3 — preconditions and the act (every arm that can zero runs all of W3–W7):**

| # | Check | Refusal reason |
|---|---|---|
| W3 | **DP-7**: `read_state CANARY_OK` is `1:<uuid>`; mapper backing device from `cryptsetup status`; `luksUUID(backing) == uuid`; `_same_dev backing $WORKSPACES_LUKS_DEV` | `wipe_canary_ok_absent` / `wipe_header_uuid_mismatch` / `wipe_mapper_not_luks_volume` |
| W4 | **P3 passphrase**: `key="$(read_key)"`, then `printf '%s' "$key" \| cryptsetup luksOpen --test-passphrase --key-file - <backing>` (the `luks-monitor.sh` form — a piped raw read can carry a trailing newline); `key` is kept for W5 and `unset` right after it; W4 and W5 run one after the other, never alongside the zeroing (Argon2 memory cost) | `wipe_escrow_passphrase_mismatch` |
| W5 | **P3 off-host header is restorable, not merely present**: `load_escrow_creds`; download `workspaces-luks-header-<uuid>.img` to `$STATE_DIR` (0700); its `luksUUID` == uuid; `printf '%s' "$key" \| cryptsetup luksOpen --test-passphrase --key-file - <downloaded file>` (the escrowed passphrase opens the backup's own keyslot); a fresh `cryptsetup luksHeaderBackup <backing>` into `$STATE_DIR` `cmp`s equal to the download (a UUID survives `luksAddKey`/`luksKillSlot`, so a UUID match alone can certify a stale backup); `hdr_bytes` and `hdr_sha256` go on the evidence row. Both files are `shred -u`'d on **every** exit from W5 (local trap plus a `cleanup()` wipe-arm sweep of the two fixed paths) — a header left on the root disk plus a leaked key decrypts every workspace. The daily monitor never downloads this object — only this check proves it restorable | `wipe_header_backup_absent` / `wipe_header_backup_mismatch` / `wipe_header_backup_stale` |
| W6 | **P2 identity**: target `-b`; `realpath` and `stat -Lc %t:%T` differ from the backing device's; `/sys/class/block/<kname>/holders/` empty; `findmnt -S <dev>` finds nothing; `blockdev --getsize64` == `WORKSPACES_PLAINTEXT_SIZE_BYTES` (bytes, not GiB); `udevadm info --query=property` `ID_SERIAL`/`ID_SCSI_SERIAL` contains `HC_Volume_<id>` (a hypervisor-derived identity that does not depend on the by-id symlink); **first-wipe arm only:** filesystem label `blkid -p -s LABEL -o value` == `workspaces_plain` (the label `rollback()` mounts by — the host's own name for the plaintext volume) | `wipe_target_is_mapper_backing` / `wipe_target_held` / `wipe_target_mounted` / `wipe_target_size_mismatch` / `wipe_target_label_mismatch` |
| W6b | **detach safety**: for **every** device unit whose `SysFSPath` equals the target's (enumerate `systemctl list-units --all --type=device` + `show -p SysFSPath` — systemd makes one unit per symlink: by-id, by-label, by-uuid, by-path, wwn, diskseq), `systemctl show -p LoadState` is `loaded` (an unloaded or misspelled unit lists no dependencies and exits 0), then `systemctl list-dependencies --reverse --plain` shows no `.mount`, `.swap` or `.service`. `mnt-data.mount`'s `What=` is the literal `scsi-0HC_Volume_*` glob (#9123), so comparing it to the target proves nothing; this probe is the measurement. Also refuse if `systemctl show mnt-data.mount -p BindsTo,Requires,What` names any of those units — a detach would then make systemd stop the live mapper mount | `wipe_target_has_dependents` |
| W7 | no dead-man is armed or firing: `workspaces-luks-deadman.timer` not `active`, `workspaces-luks-deadman.service` not `active`/`activating`, and no queued job for either | `wipe_deadman_armed` |
| W8 | evidence only: `lsblk -D -b -n -o DISC-GRAN,DISC-MAX <dev>`, `/sys/block/<k>/queue/write_zeroes_max_bytes`, `/sys/block/<k>/queue/scheduler` | — |
| W9 | **positive control** (first-wipe arm only): 4096 bytes at offset 0 via `dd iflag=direct` (an unaligned direct read fails `EINVAL`), bytes 1080–1081 == `53 ef`. Evidence field, never a gate: `dumpe2fs -h` last-mount and last-write times (the CLO's check that nothing wrote after the 2026-07-23 cutover) | `wipe_positive_control_failed` |
| — | `DRY_RUN=1` → one `result=rehearsal_ok` row carrying every measured field; `RUN_COMPLETE=1; exit 0` | — |
| W10 | `persist_state PLAINTEXT_WIPE_BEGUN "<id>:<epoch>"`; emit `result=begun arm=<arm> volume_id=<id>`; `systemd-run --scope --quiet -p IOWriteBandwidthMax="<dev> 150M" -p IOReadBandwidthMax="<dev> 150M" blkdiscard -z -v <dev> </dev/null` — never `-f` (stdin from `/dev/null`: util-linux refuses a device carrying a signature when stdin is a terminal). The cgroup `io.max` cap, not `ionice`, bounds the impact on the live volume's shared storage path: `ionice` is honoured only by BFQ and virtio-scsi guests usually run `mq-deadline` or `none` (W8 records which) | `wipe_blkdiscard_failed` |
| W11 | emit `result=readback_start`; `blockdev --flushbufs <dev>`; `systemd-run --scope --quiet -p IOReadBandwidthMax="<dev> 150M" dd if=<dev> iflag=direct bs=4M status=none \| cmp -n <size> - /dev/zero` (never `cmp -l`/`-b`, which print device bytes — user content — into logs), both `PIPESTATUS` values and `cmp`'s stderr captured into plain variables (never `$( )`). `cmp` decides: rc 0 with `dd` rc 0 passes; anything else refuses with one reason carrying `cmp_rc`, `dd_rc` and `cmp`'s first-difference line (`cmp` prints it on **stdout**; captured, `_vscrub`bed, capped at 200 bytes, on a separate evidence row) — `cmp` exiting early on a difference makes `dd` fail with EPIPE or be killed by SIGPIPE, so `dd`'s rc alone never classifies | `wipe_readback_failed` |
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

**Absence is only evidence when presence was shown with the same token.** A token scoped to a
different Hetzner project answers `404` and `[]` for a volume that is alive — and after ADR-241's
operator steps the loader draws its token from a different Doppler source. So every step that reads
"gone" from the API first proves it can see the project: `GET /servers/123931471` → `200`, name
`soleur-web-platform`, `volumes` contains `106443278`. Anything other than `200`/`404` on any call is
an error, never "absent".

- **Inputs:** `wipe_plaintext` (boolean, default `false`; the description names AP-009, the one
  approval, and that `dry_run=true` is the rehearsal); `expected_plaintext_volume_id` (string). The
  `dry_run` description's "no wipe" wording is updated. Every input reaches `run:` only through
  `env:`, never inline `${{ inputs.* }}`.
- **`preflight` (ungated, read-only).** Order: (1) mode exclusion first — wipe excludes `rollback`,
  `clean_stray`, `rollback_ack_luks_writes` — so a mixed dispatch is refused before any "untick
  dry_run" hint; (2) `expected_plaintext_volume_id` must match `^[0-9]+$` on a wipe and be **empty** on
  every other mode; (3) confirm token `WIPE-PLAINTEXT-USER-DATA-AP-009` (a public typo-guard, not an
  authorization). Then a read-only API read (`HCLOUD_TOKEN_READONLY`-first, the G1g-sanctioned shape;
  status codes read with `-w '%{http_code}'`, never `-f`, which turns a 404 into exit 22), the
  presence proof above, and `api_state` (job output, validated against its enum before it is written
  to `$GITHUB_OUTPUT`; `size_bytes` against `^[0-9]+$`):
  - `attached` — the pinned id resolves; name `soleur-web-platform-data`; `server` == 123931471;
    `format == ext4`; `protection.delete == false`; `linux_device` == the pinned by-id path; id ≠ the
    `soleur-web-platform-data-luks` id; a name lookup returns exactly this one volume;
  - `detached` — the same with `server: null` (no `linux_device` assertion);
  - `absent` — the pinned id `404`s **and** the name lookup is `[]` **and** the presence proof holds →
    refuse with the remedy "already deleted; dispatch `workspaces-plaintext-forget.yml`";
  - anything else → refuse, naming the mismatching field.
  It writes the approver banner — id, name, size, created, server, the live LUKS id, `api_state` —
  and exports `size_bytes`. API text reaches annotations only as `jq -r '.error.code'` with `%`, CR and
  LF escaped (`%25`, `%0D`, `%0A`), never the raw body.
- **`cutover` job:** unchanged for every non-wipe mode; its `environment:` expression stays
  byte-identical (`workspaces-luks-cutover-workflow.test.sh` pins it exactly; `workspaces-luks-header.test.sh`
  H17 reads the **first** `environment:` line in the file, so the new job goes **after** `cutover`).
  A job-level `if:` skips it when `wipe_plaintext && !dry_run`; that test's "no job-level `if:`" row is
  amended to allow exactly that predicate. On a wipe rehearsal it delivers `CONFIRM_WIPE=1 DRY_RUN=1`:
  its value is `${{ (inputs.wipe_plaintext && inputs.dry_run) && '1' || '0' }}` (a bare boolean would
  deliver the string `true`, which the script does not read as `1` and would fall through to a cutover
  rehearsal), so this job can never deliver a destructive wipe. ADR-119's 2026-07-19 rule ("every
  destructive mode contributes its own operand" to this expression) is kept by construction — the
  destructive wipe is not reachable from this job at all — and the addendum says so.
- **`.env` hardening (both delivering jobs).** The host runs `set -a; . .env`, so every value is shell
  code; the existing comment calls this safe only because every field is metacharacter-free. The step
  that writes the heredoc re-checks, immediately before writing: id and size `^[0-9]+$`, dev ==
  `/dev/disk/by-id/scsi-0HC_Volume_${ID}`, and `CONFIRM_WIPE`/`DRY_RUN` ∈ {0,1}; those two are the last
  lines. The script refuses a `.env` whose key set contains a duplicate.
- **`wipe` job (new, after `cutover`):** `needs: preflight`; `if: inputs.wipe_plaintext &&
  !inputs.dry_run`; `environment: workspaces-luks-cutover` (**unconditional**: census Guard 1, and the
  one human approval); `permissions: { contents: read, actions: read }`; `timeout-minutes: 240` (a
  fixed ceiling committed in PR A — 20 GiB of zeroes plus a 20 GiB direct read at the 150 MB/s cap is
  about 2.5 minutes each at full cap, and still well under an hour at a tenth of it; the rehearsal's W8 fields are
  recorded and the ceiling is only raised by a later PR if they say otherwise). Steps:
  1. **Preconditions, all before web-1 is touched:** the `infra-credentials` loader; the presence
     proof; re-`GET` the pinned volume and require `api_state` unchanged since preflight (the approval
     may have waited hours); the **window pause is real** — `gh api
     repos/{o}/{r}/actions/workflows/<f>` reports `disabled_manually` for both
     `apply-web-platform-infra.yml` and `apply-deploy-pipeline-fix.yml`, and `gh run list --workflow
     <f>` shows no `queued`/`waiting`/`pending`/`in_progress` run of either (disabling does not cancel
     a run already queued); a successful `workspaces-luks-verify.yml` run on `main` within the last
     24 h whose summary carries `ready=true` (the baseline is a machine precondition, not a
     reminder); then the **write-capability probe** — `PUT /volumes/<id>` with the volume's current
     `labels` verbatim → `200`. A read-only token `403`s **here**.
  2. CF-tunnel bridge, bundle ship, 0600 heredoc `.env` (`CONFIRM_WIPE=1 DRY_RUN=0`), run — the same
     shape as `cutover`'s run step, duplicated rather than refactored so the freeze path stays
     byte-stable. `unset HCLOUD_TOKEN` at the top of the bridge and host steps. The `ssh` call adds `-o
     ServerAliveInterval=30 -o ServerAliveCountMax=10`: a silent multi-minute `blkdiscard` must not idle
     the tunnel into a drop. The host output is wrapped in `::stop-commands::<random token>` (so no
     host line can issue a workflow command) and tee'd: `… 2>&1 | tee "$LOG"; rc=${PIPESTATUS[0]}`.
     Proceed only if `rc == 0` **and** exactly one line of `$LOG` fully matches
     `^SOLEUR_WORKSPACES_LUKS_WIPE feature=workspaces-luks op=workspaces-luks-wipe result=(wiped|already_wiped_detached) arm=[a-z_]+ volume_id=([0-9]+)( [a-z_]+=[^ ]*)*$`
     with `volume_id` == the pin and the result matching `api_state` (`attached` → `wiped`;
     `detached` → `already_wiped_detached`). Free text (the `cmp` line, `dumpe2fs` times) rides a
     separate, CR/LF-stripped evidence row, never the success row. Anything else fails the job before
     any API write. The host step always runs, including on `detached`, so a volume detached by hand
     without a wipe is refused, never deleted.
  3. API: re-check pin ≠ the LUKS id; if `server != null`, `POST …/actions/detach`, poll `GET
     /actions/<aid>` every 5 s ≤ 300 s; on timeout with the action still `running`, keep polling that
     action (never re-POST — a second detach returns `locked`); then `GET` shows `server: null`.
     `DELETE /volumes/<id>` → `204` (`404` accepted only with the presence proof re-run). Final `GET`
     must be `404`, and `GET /servers/123931471` must be `200` with `volumes == [106443278]`. The token
     reaches `curl` through `--config -` on stdin, never argv; `curl -sS --max-time 15 -w
     '%{http_code}'`; errors print the status and `.error.code` only.
  4. Summary: mode `WIPE`, the marker row, the detach action id, the `204`/`404`, and the next step
     (dispatch the forget workflow).

### C. The forget workflow — `.github/workflows/workspaces-plaintext-forget.yml` (new, removed in PR B)

A separate `workflow_dispatch` workflow so that no run ever holds both `web-1-swap` and the Terraform
host group (the apply workflows take host then swap; nesting them the other way can deadlock).

- Workflow-level `concurrency: { group: terraform-apply-web-platform-host, cancel-in-progress: false }`
  — the literal every writer of this lockless R2 state uses.
- The pin is a **constant**, `PINNED=105149570`, in the workflow file (single-use, deleted in PR B);
  the `expected_plaintext_volume_id` input must equal it exactly, and `confirm` must equal
  `FORGET-RETIRED-PLAINTEXT-VOLUME`. Inputs reach `run:` only through `env:`.
- One job, `environment: infra-privileged` (Tier-B, main-only, **no reviewer**: it only forgets
  addresses whose object is measured gone), `permissions: { contents: read, actions: read }`,
  `env: TERRAFORM_VERSION` equal to the apply workflows'. Every step refuses to run under xtrace
  (`case $- in *x*) exit 78`).
- Steps: checkout, `setup-terraform`, the `infra-credentials` loader, then the apply job's own
  "Extract backend credentials" and `terraform init -input=false -lockfile=readonly` steps copied
  verbatim (the loader exports no backend config; the bucket is fixed in `main.tf`), then:
  1. the presence proof; the pinned id `GET` → `404` **and** the name lookup → `[]`; the window pause is
     still real (same check as the `wipe` job).
  2. Identity, without ever printing or storing state: `terraform state pull` is piped straight into
     one `jq` program that emits only `serial`, `lineage`, and — selected by exact `.type` and `.name`,
     never by address prefix (`workspaces_luks` shares the `hcloud_volume.workspaces` prefix) — the
     `index_key`, `attributes.id` and, for the attachment, `attributes.volume_id` of each `web-1`
     instance, plus whether `hcloud_server.web["web-1"]` exists. The state holds
     `random_password.workspaces_luks`; nothing else from it may reach a log, a file or an artifact.
     Require `hcloud_server.web["web-1"]` present, the volume instance's `id` == the pin, and the
     attachment's `volume_id` == the pin.
  3. `terraform state rm` each present `["web-1"]` workspaces address (both, one, or none —
     `already_forgotten`).
  4. Re-pull through the same `jq` filter: `serial` == pre + 1 (or unchanged when nothing was removed),
     same `lineage`, and `terraform state list` equals the pre-list minus exactly the removed lines.
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
   `gh workflow disable apply-deploy-pipeline-fix.yml`, then wait until neither has a queued or
   running run (the `wipe` job re-checks both facts and refuses otherwise).
2. After PR B merges: `gh workflow enable` both, then `gh workflow run apply-web-platform-infra.yml
   -f reason='#6604 post-PR-B apply'` (the default `manual-rerun` arm applies exactly what the skipped
   push apply would have), and confirm it plans no `hcloud_volume.workspaces` / attachment address.

Other members of the `terraform-apply-web-platform-host` group are unaffected, but
`registry-host-replace-dispatch.yml` dispatches `apply-web-platform-infra.yml` and fails while it is
disabled, and `git-data-pin-redeploy.yml` shares the group; the runbook names both. The dispatched arms
of `apply-web-platform-infra.yml` are unavailable while it is disabled, and an operator-local apply
must not run in the window.

**Sole-copy protection after the window (pre-existing gap, made sharper).** After D the LUKS volume
106443278 is the only copy, and it has neither `prevent_destroy` (deferred to #6931, because it
collides with the `workspaces-luks-recut` `-replace` escape hatch) nor Hetzner delete protection.
The recut path's premise ("the live plaintext keeps serving") stops being true at D. Its gate binds to
a typed id, so an accident needs the LUKS id typed deliberately; still, PR A's runbook marks Sequence
Step 0 **never after step 7 — it destroys the only copy**, and PR B comments on #6931 to raise
delete protection for 106443278 to a precondition of that work.

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
- A comment on #6931 making Hetzner delete protection for volume 106443278 a precondition of that work.
- PR body: `Closes #6604`, `Closes #6588`; #6897 comment updating item 1 (workspaces web-1 retired;
  web-2 → #6931; `git_data` untouched).

## Implementation Phases

### Phase 1 — Guard contract and RED tests first (`cq-write-failing-tests-before`)

1. `apps/web-platform/infra/workspaces-luks-wipe.test.sh` on `workspaces-luks-harness.sh`: every Guard
   Contract row as a case (stubs whitelist real flags, exit 64 on unknown ones), `harness_floor`
   pinned to the measured count.
2. `workspaces-luks-loopback.test.sh`: small loop devices (e.g. 64 MiB plus an odd tail) with a real
   `mkfs.ext4 -L workspaces_plain`; the real W9→W12 path (control sees `53 ef`; `blkdiscard -z`
   zeroes; read-back passes); a non-zero byte at **fixed** offsets (1 MiB + 1, one byte before a 4 MiB
   boundary, the last byte) after zeroing must RED; an interrupted zero (first MiB only,
   `PLAINTEXT_WIPE_BEGUN` set) must resume on the re-zero arm; the device size is a multiple of 512
   bytes but not of 4 MiB. Behavioral `-f` ban: the script's own `blkdiscard` command line run against
   an open-LUKS loop device and against a mounted loop device must fail `EBUSY` and leave the data
   intact. Capture real `systemctl list-dependencies --reverse --plain` output here to pin the stub's
   format; a missing systemd counts as a failure, never a skip.
3. `workspaces-luks-cutover-workflow.test.sh` (job set `{preflight, cutover, wipe}`; the `cutover`
   predicate; `wipe`'s unconditional environment; the success-row parser), `workspaces-luks-header.test.sh`
   (H17 unchanged and green), a new workflow test for `workspaces-plaintext-forget.yml`, the tier
   census, and `terraform-target-parity.test.ts`. Behavior rows for the workflow steps (Guards 4 and
   6) extract each step's `run:` block by job and step id with `yq`, assert exactly one match (the
   duplicated delivery block would otherwise collide), and execute it against a `curl` stub that
   prints what `-w '%{http_code}'` prints and exits 22 under `-f` on a 404.

**Harness requirements (test-design review).** The stubbed suite must not be able to reach a real
binary or a real secret:

- recording executables that `exit 64` for `blkdiscard`, `dd`, `doppler` and `aws` sit first on
  `PATH`, so a call that escapes the function stubs fails loudly (without this, `systemd-run …
  blkdiscard` would start the real `/usr/sbin/blkdiscard`, and `read_key` would fetch the real prod
  key); `systemd-run` is stubbed as a function that drops its options and runs `"$@"`; a census asserts
  every command `wipe_plaintext` invokes has a stub; a hygiene row deletes the `blkdiscard` function
  stub and requires the case to fail through the `PATH` executable;
- the device path is resolved through a function seam the harness overrides (W1 requires the literal
  by-id path and `-b` is a builtin, so no fixture could otherwise reach W6); the seam is not settable
  from the environment, and a census row checks that;
- stub fidelity: `cryptsetup --test-passphrase` compares stdin byte-for-byte (so the trailing-newline
  mutant REDs); `luksUUID` answers per path (W3 vs W5); `blkid` answers `-s TYPE` and `-s LABEL`
  separately and changes once a zeroed flag is set, with real exit codes (0/2/4/8); `systemctl show`
  answers per exact escaped unit name; `list-dependencies` prints the unit first and dependents
  indented, as systemd does; `cmp` prints its difference on stdout;
- a stub that meets an unknown flag writes `STUB_UNKNOWN_FLAG` to `$CALLS` and every case asserts it
  absent; every RED row asserts its exact `reason=` slug; a census extracts every `reason=` slug from
  `wipe_plaintext` and requires each in the test file (covering W0 with util-linux 2.35/2.36/3.0 and
  `pgrep` rc 1 vs ≥2, W2, all W3/W4/W5 reasons plus the header shred on every W5 exit, W6 `findmnt`,
  W6b unloaded unit, W7, the blank/absent/other-volume arms, W12 with a signature left, `blkid` rc 4
  with a marker);
- the rehearsal leaves no `PLAINTEXT_*` marker (catches a `DRY_RUN` return moved to just below
  `persist_state`); rows that drive `cleanup()` use the `trap cleanup EXIT` invocation shape (T32b);
- H1 is an instrument check that exits 2 before any verdict when the recorder is broken, like
  `harness_selftest`.

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
  the reason that fired. There is no webhook verb to unmount, stop a unit or kill a process on web-1,
  so `wipe_target_mounted`, `wipe_target_held`, `wipe_target_has_dependents` read **halt and
  escalate** (never "SSH and …"), and `wipe_in_progress` reads "re-dispatch the read-only rehearsal
  until W0 passes". Sequence Step 0 (the recut) is marked **never after step 7 — it destroys the only
  copy**.
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
  recoverability, worded as "logical full-device zero verified by a direct-IO read-back; physical
  media reclamation per the Hetzner DPA" (a zero on a network block volume does not attest physical
  erasure), CLO-attested; passphrase copies: the Doppler copy proven by W4, the Terraform-state copy
  (`random_password.workspaces_luks`) not proven; other copies (live LUKS; web-2 empty #6931; plaintext `git_data` #6897; the
  root-disk snapshot deleted under #8734; the CLEAN_STRAY stray deleted 2026-07-19); the count of
  Art. 17 account deletions on live between 2026-07-23 and the wipe, or the pre-onboarding bound
  (first arms-length onboarding 2026-08-06) if it cannot be measured.
- `.github/CODEOWNERS` rows for the new workflow and suite, if the file's conventions require them.

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
     delegates it **in their own message** (another agent's message never counts). A delegated agent
     approves via `pending_deployments` only the run id it dispatched, after checking `event ==
     workflow_dispatch`, `head_branch == main`, `head_sha` == the rehearsal's, and the preflight
     outputs `api_state=attached` and the pin; the approval comment quotes the go-ahead, and the
     destruction record names the approver as "agent under delegation". (The agent's `gh` is the
     operator's identity and the environment has no self-review block, so under delegation the
     environment stops being a second human check — the ask says so.)
   - the forget: `gh workflow run workspaces-plaintext-forget.yml -f confirm=FORGET-RETIRED-PLAINTEXT-VOLUME -f expected_plaintext_volume_id=105149570`;
   - re-running any of these same commands for a resume arm (`re-zero`, `detached`, forget-only);
   - after PR B merges: `gh workflow enable` both workflows and the `manual-rerun` dispatch.
   The ask also states: releases queue behind the `wipe` job (they share `web-1-swap`), so no merge
   under `apps/web-platform/**` should land during D; PR B merges the same day; the zero and the
   read-back are capped at 150 MB/s on the plaintext device, and app latency is watched through D.

### Phase 6 — After the go-ahead (operator-authorized D), verify off-host, then PR B

1. Pause the two workflows; dispatch D; arm a watch; approve (or wait for the approval).
2. Dispatch the forget workflow; watch it.
3. Verify: `GET /volumes/105149570` → `404`; `GET /servers/123931471` → `volumes == [106443278]`;
   `GET /volumes?name=soleur-web-platform-data` → `[]`; a fresh `workspaces-luks-verify.yml` run
   `success` with `ready=true`, and `workspace_count` compared against the **same-day baseline** `n`
   (a drop is explained, e.g. by an Art. 17 deletion, or escalated — the persisted `expected` floor
   alone is a weak signal); no new `op:workspaces-luks-drift` Sentry event; the Better Stack web-1
   monitor shows no downtime; `gh workflow run scheduled-prod-version-drift.yml` confirms the image on
   web-1 matches the latest `apps/web-platform/**` commit on `main` (a release queued behind the `wipe`
   job may have been replaced while pending — re-dispatch it if so).
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

## Downtime & Cutover

**Operation.** A hot detach and delete of an unmounted, unheld volume on web-1 (the sole origin), after
a full-device zero and read-back of that volume. The serving surface — `/mnt/data` on
`/dev/mapper/workspaces`, volume 106443278 — is never unmounted, and the app container is never
stopped.

**Zero-downtime path (the default, and the only path).** Nothing is drained because nothing that serves
is touched. Per stage:

| Stage | What could take the surface down | Verification before moving on | Rollback |
|---|---|---|---|
| Zero + read-back | I/O contention on the shared storage path | 150 MB/s cgroup `io.max` cap; readyz and latency watched through D | Stop the run; nothing to undo (the volume holds no live data) |
| Detach | A unit bound to the detached device (systemd would stop it) | W6b: no mount/swap/service depends on any of the target's device units, and `mnt-data.mount` binds none of them | None needed — the check runs before the detach |
| Delete | Deleting the wrong volume | Pin ≠ LUKS id, success row for the pin, presence proof | None — irreversible by design, which is why every check precedes it |
| Forget + PR B | A push apply re-creating a plaintext volume | Both apply workflows paused and idle; `manual-rerun` after PR B plans no workspaces address | Re-dispatch the forget workflow |

No maintenance window is needed. The only restarts in the whole sequence are the routine container
releases fired by merging PR A and PR B, the same as any `apps/web-platform/**` merge.

## Risks & Precedents

| Pattern | Precedent in repo | This plan |
|---|---|---|
| Serializing a writer of the lockless web-platform state | `apply-web-platform-infra.yml` / `apply-deploy-pipeline-fix.yml` workflow-level `concurrency: terraform-apply-web-platform-host` (the header comment calls it the SOLE serializer) | Same literal, workflow level, and never nested with `web-1-swap` |
| Reading Terraform state in CI | `apply-sentry-infra.yml` `terraform state pull > "${RUNNER_TEMP}/sentry-state-pre.json"` (a root holding no LUKS secret) | Never written to disk or printed: piped straight into a field-selecting `jq`, because this root's state holds `random_password.workspaces_luks` |
| A destructive, operator-approved mode on the cutover script | `clean_stray()` (CLEAN_STRAY, AP-009 carve-out): own marker, own typed token, refuses `DRY_RUN=1`, ungated preflight banner | Same shape, with one deliberate difference: the wipe *has* a rehearsal (`DRY_RUN=1` runs every precondition), because its preconditions are the complex part |
| Binding a destroy to a physical id | `workspaces_luks_recut_gate` (`expected_luks_volume_id`, `luks_id_mismatch`) | `expected_plaintext_volume_id` pinned through preflight, the host by-id path, `ID_SERIAL`, the success row and the forget's state identity |
| Destruction record | `knowledge-base/legal/audits/inngest-aof-destruction-record.md` (template before the act, completed from the gate's own row) | Same, for a populated volume |
| Hot-detaching a volume from a running host | No precedent in this repo | Novel — hence W6b's measurement rather than a reasoned claim |

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
- **If this lands broken, the user experiences:** slow or timing-out requests on app.soleur.ai for the
  length of D, because 20 GiB of zeroes and a 20 GiB read share web-1's storage path with the live
  volume. Controlled by the 150 MB/s cgroup `io.max` cap (W10/W11) and a latency watch through D.
- **If this lands broken, the user experiences:** a hotfix release silently not deployed — releases
  queue behind the `wipe` job on `web-1-swap`, and a third arrival cancels the older pending one.
  Controlled by the merge freeze and the post-D `scheduled-prod-version-drift.yml` check.
- **If this leaks, the user's data is exposed via:** a copy of the LUKS header left on web-1's root disk
  after a W5 refusal (with a leaked key it decrypts every workspace) — shredded on every W5 exit.
- **If this leaks, the user's data is exposed via:** device bytes printed into the Actions log, Better
  Stack or Sentry (`cmp -l`/`-b`, an echoed `dd` buffer) — forbidden, and the one `cmp` line is scrubbed
  and capped.
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
right arm (`arm=re_zero`, which re-runs every identity check before zeroing again; `arm=detached`;
or the forget workflow alone once the volume is deleted) without touching the live mount.

CPO sign-off: **granted with conditions** (Phase 2.5) — the three items above, a same-day
`workspaces-luks-verify.yml` baseline before the go-ahead (Acceptance Criteria → Dispatch), and a
rehearsal from the same merged commit with no deploy or cutover run in between.
`soleur:engineering:review:user-impact-reviewer` runs at review time.

## Observability

Layer names follow `hr-observability-layer-citation`: **workflow run log** (layer 6, the synchronous
signal — host output streams into it, refusal rows print before `die`, `::error::` annotations);
**vector → Better Stack** (layer 3 — `luks-monitor` is in `include_matches.SYSLOG_IDENTIFIER`,
Source 4 `host_scripts_journald`, `vector.toml`; live rows from `soleur-web-platform` observed
2026-09-28); **Sentry** is additive, via `emit_drift` → `sentry_alert.workspaces_luks_drift`
(`sentry/issue-alerts.tf`), with a crit `SEND_FAILED` row on the vector path if the send fails.

```yaml
liveness_signal:
  what: SOLEUR_WORKSPACES_LUKS_WIPE rows (result=rehearsal_ok|begun|readback_start|wiped|already_wiped_detached|refused, with arm=first_wipe|re_zero|detached) written by emit_wipe to stdout and to the luks-monitor syslog tag
  cadence: per dispatch (once for real; rehearsals on demand)
  alert_target: the failed-run notification to the dispatcher (workflow run log, layer 6) and, for every refusal, the Sentry issue alert on feature=workspaces-luks op=workspaces-luks-drift
  configured_in: apps/web-platform/infra/workspaces-cutover.sh (emit_wipe, emit_drift), .github/workflows/workspaces-luks-cutover.yml (row parser + summary), apps/web-platform/infra/vector.toml (luks-monitor tag)

error_reporting:
  destination: Sentry via workspaces_luks_emit (baked SOLEUR_SENTRY_DSN in /etc/default/luks-monitor on web-1), plus the workflow run log
  fail_loud: a result=refused reason=<slug> row printed BEFORE die, a ::error:: annotation carrying the reason (API errors print only the HTTP status and .error.code), and a non-zero job conclusion

failure_modes:
  - mode: target identity ambiguous (mapper backing device, held, mounted, wrong size, wrong serial or label, not ext4, dependents)
    detection: W6/W6b refusal row in the workflow run log (layer 6) and on vector → Better Stack (layer 3), before any write
    alert_route: failed run to the dispatcher; Sentry workspaces-luks-drift alert
  - mode: escrow not recoverable at wipe time (passphrase, header absent, mismatched or stale)
    detection: W4/W5 refusal rows, workflow run log (layer 6) and vector → Better Stack (layer 3)
    alert_route: failed run; Sentry alert; runbook routes to re-escrowing the header, never to the wipe
  - mode: zeroing did not take (no-op or partial)
    detection: wipe_readback_failed row (cmp_rc, dd_rc) from the W11 full-device O_DIRECT compare, workflow run log (layer 6) and vector → Better Stack (layer 3)
    alert_route: failed run; Sentry alert; the API steps never run (they need exactly one success row)
  - mode: zeroing interrupted (SSH drop, job timeout, cancel) before the success row
    detection: a result=begun row with no result=wiped after it (vector → Better Stack, layer 3), the cleanup() outcome=wipe_aborted mode=wipe row, and the failed run (layer 6); PLAINTEXT_WIPE_BEGUN makes the next dispatch take arm=re_zero
    alert_route: failed run; runbook resume table
  - mode: token lacks write permission (ADR-241 O5 legacy arm) or the project is not visible
    detection: the labels-PUT probe or the presence proof fails in the wipe job before web-1 is touched (workflow run log, layer 6)
    alert_route: failed run with nothing irreversible done; re-dispatch once the loader exports a write token
  - mode: detach done, DELETE failed or timed out
    detection: wipe job step 3 ::error:: with status and .error.code (workflow run log, layer 6)
    alert_route: failed run; the next dispatch classifies api_state=detached and takes arm=detached
  - mode: state forget cancelled or failed after the delete (a newer pending apply replaced it in the group)
    detection: the forget workflow's run log (layer 6); scheduled-terraform-drift.yml reports +create of the two web-1 addresses (its own run log and issue route)
    alert_route: failed or cancelled run plus the drift issue; re-dispatch the forget workflow
  - mode: the two push-apply workflows left paused after PR B merges
    detection: PR B's acceptance criterion reads gh workflow view state == active for both; scheduled-terraform-drift.yml keeps reporting the unapplied change (its run log)
    alert_route: the PR B ship checklist and the drift issue
  - mode: web-1 serving degraded during or after D
    detection: workspaces-luks-verify.yml run log (layer 6, daily schedule plus a post-dispatch run) and the luks-monitor heartbeat on vector → Better Stack (layer 3); the Better Stack uptime monitor
    alert_route: ci/luks-verify issue plus ops email (drift/readiness classes); uptime alert

logs:
  where: workflow run logs (cutover workflow preflight/wipe, forget workflow); web-1 syslog tag luks-monitor -> vector -> Better Stack source 2457081
  retention: Actions logs 90 days; Better Stack per the source retention plus archive

discoverability_test:
  command: grep -c -e 'SOLEUR_WORKSPACES_LUKS_WIPE feature=workspaces-luks' apps/web-platform/infra/workspaces-cutover.sh
  expected_output: "1"
```

The discoverability probe proves the emitter exists at the single `emit_wipe` definition (a count other
than 1 means the row format was duplicated or removed). The live query of the rows themselves —
`doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 1d --grep SOLEUR_WORKSPACES_LUKS_WIPE`
— is a Phase 6 verification step, not the discoverability probe, because it returns nothing until the
first dispatch. A test extracts every `reason=` and `arm=` token named in this section and asserts each
one exists in `workspaces-cutover.sh`.

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
    enforced_at: .github/workflows/workspaces-luks-cutover.yml wipe job API step (curl -sS --max-time 15 https://api.hetzner.cloud/v1/..., no -k; status read with -w)
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
| 9b | re-zero arm with a `crypto_LUKS` signature | RED `wipe_target_not_ext4` |
| 9c | `ID_SERIAL` of the target does not contain `HC_Volume_<id>` | RED |
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
| 6b | the presence proof fails (`GET /servers/123931471` ≠ `200`, or its volumes lack 106443278) while the pin `404`s — a token from another project | RED, no `state rm` |
| 6c | a step prints, tees or uploads `terraform state pull` output, or the `jq` filter selects by address prefix | RED (static row over the workflow text) |
| 6d | the post-removal `serial` is not pre + 1, or `lineage` changed | RED |
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
| 6 | exactly one success row but `ssh` rc ≠ 0 | RED |
| 7 | a host line `::add-mask::…` or `::set-output` appears in the tee'd output | inert — the `::stop-commands::` wrap is asserted present |
| 8 | either apply workflow still `active`, or one has a queued run | RED before web-1 is touched |
| 9 | no successful `workspaces-luks-verify.yml` run on `main` in the last 24 h | RED before web-1 is touched |
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
- [ ] Runbook step 7, ADR-119 addendum, ADR-241 note, `model.c4` edges, destruction-record template
      committed; `c4-count-parity`, `c4-code-syntax`, `c4-render` green.

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
      shows no downtime; `scheduled-prod-version-drift.yml` green after D (no release dropped while
      queued behind the `wipe` job).

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
`What=` compare; W0 requires `aws` rather than installing it; a cgroup `io.max` cap (deepen replaced `ionice`); the write-token probe
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
