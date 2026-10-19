# Flip preconditions: live re-read (git-data LUKS cutover, #8211)

- Read at: 2026-10-15, 09:13Z to 09:24Z (UTC). Origin/main at read time: `6a5d639c1f`.
- Scope: read-only. No workflow dispatch, no terraform apply, no production write. No secret value printed. The only value-level reads: the boolean flag lookup (absent) and the Better Stack / Hetzner read tokens used as bearer credentials inside `doppler run` (never echoed).
- Better Stack reads used the narrowed form from `design-9943-liveness-precheck.md` (`--only-secrets` for the three query secrets plus `env -u DOPPLER_TOKEN -u AWS_*`).

## Verdict

**The brief's host facts are stale. Every precondition about the host that the brief lists as unmet is now met, but three flip refusals that the brief does not list exist, and they are not host-side.** No flip is possible today.

| # | Item | Verdict | Evidence (command, time) |
|---|---|---|---|
| 1 | Heartbeat `soleur-git-data-host-prd` (506836) up | VERIFIED | `arm-heartbeats.sh --status` 09:14:39Z: `paused=false status=up period=60 grace=300` |
| 2 | Heartbeat `soleur-git-data-prd` (498647) up | VERIFIED | same read: `paused=false status=up period=60 grace=180` |
| 3 | Newest `state=ok` event under 15 min | VERIFIED | Better Stack `stage=liveness`, `host_name=soleur-git-data`: newest `2026-10-15 09:05:48` (8 min 21 s old at 09:14:09Z) |
| 4 | Liveness newer than the current host's `boot_complete` | VERIFIED | newest `boot_complete` for `soleur-git-data`: `2026-10-14 14:52:17.960`; 102 liveness rows since 14:54:43, all one message (`ok`); zero non-ok rows since 2026-10-14 14:00 |
| 5 | The host the brief names | **STALE** | The brief's server `170368003` / LUKS volume `107125716` / `boot_complete` 14:34:43Z is gone. Hetzner (read-only token, 09:14:54Z): server `170370833` `soleur-git-data`, created 2026-10-14T14:51:27Z, volumes `106867358` (`soleur-git-data-store`, plaintext, created 2026-09-14) and `107140231` (`soleur-git-data-luks-store`, created 14:51:26Z). Cause: apply run `38583657167` (see row 6) |
| 6 | Rotate (D6) | **ALREADY DONE** | `apply-web-platform-infra.yml` run `38583657167`, `workflow_dispatch`, 2026-10-14 14:47Z to 14:53:27Z: log shows `APPLY_TARGET: git-data-host-rotate`, `CONFIRM_RAW: ROTATE-GIT-DATA`, `git_data_host_replace_gate: PASS - scoped git-data-host ROTATE permitted`, and every step green including `Rotate precondition - store never written`, `Rotate precondition - served store measured empty` and `Rotate completed (d6 marker)`. The only later apply dispatch (`38645462210`, 22:07Z) skipped the git-data jobs, so it does not displace the stamp. The brief lists the rotate re-dispatch as still owner-gated; it has run |
| 7 | `git_data_ssh_client=present` on deployed web build | VERIFIED, not per host | 28 startup rows `2026-10-13 21:36` to `2026-10-15 07:32` (36 h window), every `gitDataSshClient:true`; latest container `1021b9c3d47f` at 07:32:28Z. All rows carry `host_name=soleur-web-platform`; no row carries another host name, so web-2 is **not shown** by this signal either way |
| 8 | `git_data_pin=present` | VERIFIED, one fingerprint | 17 rows in an 18 h window, all `fp=SHA256:+f9WFF5l` (8-char prefix), latest 07:32:28Z. The loaded pin was not compared with the new host's actual key (that needs a value read; not done) |
| 9 | `git_data_store=disabled` on web | VERIFIED | same 17 rows, all `disabled`, latest 07:32:28Z |
| 10 | `GIT_DATA_STORE_ENABLED` | ABSENT in `prd` | `doppler secrets get GIT_DATA_STORE_ENABLED -p soleur -c prd`: "Could not find requested secret" at 09:14:42Z. Absent is not the same as `false`; the app treats it as off (`git_data_store=disabled`) |
| 11 | `GIT_DATA_LUKS_CUTOVER_AT` | ABSENT (as required) | name listing of `prd`, 09:14:42Z: 0 matches. `prd` carries `GIT_DATA_HEARTBEAT_URL`, `GIT_DATA_SSH_HOST`, `GIT_DATA_SSH_HOST_KEY` only |
| 12 | Host-key pin secret in `prd` | VERIFIED (name only) | `GIT_DATA_SSH_HOST_KEY` listed, 09:14:42Z |
| 13 | Sentry rule 1310055 | **NOT VERIFIED** | `SENTRY_ACTIONS_RO_TOKEN` exists only as a GitHub repo secret (listed, 09:23:54Z), so `scripts/sentry-alert-live-fidelity.sh` cannot run from here. Indirect evidence only: `scheduled-sentry-alert-drift.yml` run `38697484555` success, 2026-10-15T07:15:03Z (2 h old); `38527103515` (10-14) and `38361478133` (10-13) also success. The numeric id is still not printed by any headless read; the flip's own precheck reads it |
| 14 | `HCLOUD_TOKEN` readable from `prd_terraform` | NOT readable (as stated) | name listing, 09:14:42Z: only `HCLOUD_TOKEN_READONLY` |

## Findings the brief does not carry (each refuses the flip today)

1. **`GIT_DATA_EMITTER_FLOOR` and `GIT_DATA_DENY_FLOOR` are unset.** `gh variable list` (repo) shows only `GIT_DATA_ROOT_STATE_MIGRATED`; `gh variable list --env web-platform-infra-apply` and `--env infra-privileged` are empty (09:23-09:24Z). The flip step `Flip preconditions` reads both through `vars.` and refuses `live_image_stale` ("vars.GIT_DATA_EMITTER_FLOOR unset") then `sandbox_deny_floor`. Org-level variables were not read. Setting them is an owner/ops write (a repo variable). The running version to compare is read from `https://app.soleur.ai/health`.
2. **`DOPPLER_TOKEN_GIT_DATA_FLAG` is absent on `web-platform-infra-apply`.** Its environment secrets are `DOPPLER_TOKEN_GIT_DATA_ROOT` and `DOPPLER_TOKEN_INFRA_PRIVILEGED` only. The flip refuses `flag_write_credential_absent`. This is the "windowed prd write credential (#8573, #8609)" in the owner chain, confirmed unprovisioned.
3. **The flip is one dispatch for both web hosts.** The workflow header says the flip redeploys BOTH web hosts via `/hooks/deploy` and reads `git_data_store=enabled` per host from Better Stack (web-2 has no SSH ingress, so the log line is its only evidence). There is no separate web-1-then-web-2 flip. See `owner-command-chain.md`.
4. **Environment approval is a self-approval.** `web-platform-infra-apply`: 1 required reviewer, `prevent_self_review=false`; `infra-privileged`: 0 reviewers (main-only). Matches #10343's "self-approval" item. The headless `pending_deployments` form must never be used for any wipe mode.
5. **Plaintext volume `soleur-git-data-store` (106867358) is still attached** to the new server, `delete_protection=false`. The live LUKS volume `107140231` also reads `delete_protection=false` (#10343). The CLO plaintext outer date is 2026-11-12.
6. **Three additional `boot_complete` rows exist for two rehearsal hosts** (`soleur-git-data-rehearsal-38556214287` 2026-10-14 11:29 and 11:36; `...-38356246710` 2026-10-13 06:35). They are rung-2 boot rehearsals, not the live host, and must be excluded from any "newest boot_complete" read by `host_name` (the design-9943 query already filters on `host_name`).

## What this changes for tasks 2 and 3

- The rotate step leaves the owner chain; the chain starts at the three credential rotations, then the flag-write credential and floors, then the rehearsal.
- Because the rotate already ran on 2026-10-14 and the store has taken no write through the flip path, the #10207 guard does not block anything today; it blocks a rotate after the first flip.
- Row 7's lack of per-host attribution is unchanged and is the reason the flip's per-host readback (row 3 of the findings) is the binding evidence, not this table.

## Not read, and why

- Sentry rule 1310055 directly (no headless token).
- The pinned host key's value against the live host key (value read; skipped).
- Active agent-session count (no verified metric exists; design-rollback-rehearsal section 3).
- Org-level GitHub variables.

## Addendum 2026-10-19 (read from GitHub only; no Hetzner, Better Stack or Doppler read today)

Appended; nothing above is edited. It cites the 2026-10-15 reading and says what has moved since.

- **Wipe mechanism is on `main`.** PR #10294 (the wipe body, merged 2026-10-15), PR #10384 (ship skill: a CTO ruling clears an ask-before-push instruction for technical fixes, merged 2026-10-15) and PR #10352 (the separated wipe, `snapshot_clear` and the run-record evidence, merged 2026-10-16) are all merged. Row 14 of `owner-command-chain.md` ("No dispatch string exists on `main`") is superseded by the addendum there.
- **Three read-only `git-data-cutover` runs were dispatched by the owner since 2026-10-15** (all `main`, actor `deruelle`; none changes a volume or the flag):
  - `39081408368` (2026-10-18 00:04Z, `wipe_check`, volume 106867358): refused at the host assertion (W7) with `wipe_boot_layout_signal_offlist`, `rc=34 top_d=3 top_f=0 top_l=0 top_o=0 repos=0`.
  - `39136900735` (2026-10-18 14:38Z, `wipe_check`): the same refusal with the cause fields added by #10480 (`has_hooks_d=1 lf_entries=0 offlist_n=1`). Issue #10476 is open for it; the runbook records both refusals (#10506).
  - `39225306395` (2026-10-19 08:47Z, `proof`): success. Access gate `ok` on all three roles; `store-mounted`, `store-on-mapper`, `store-verified`, `store-empty` and `fence-shape` all `ok`. The served LUKS store is still empty, so row 11 of the flip proof is currently satisfied.
- **The host did not change.** Both `wipe_check` runs read server `170370833`, plaintext volume `106867358` and LUKS volume `107140231`, all attached, `protection_delete=false`: the same ids as the 2026-10-15 reading. No rotate has run since `38583657167`.
- **Still true from the 2026-10-15 reading, not re-read today:** the three refusals in "Findings the brief does not carry" (repo variables `GIT_DATA_EMITTER_FLOOR` and `GIT_DATA_DENY_FLOOR`, the absent `DOPPLER_TOKEN_GIT_DATA_FLAG`, the unverified Sentry rule). Heartbeats were not re-read; the owner's re-read is still the control (#9943 deferred).
- **New blocker for the wipe, not the flip:** the plaintext volume has one top-level directory the layout classifier cannot place (`offlist_n=1` beside the known `hooks` directory). `wipe_check` and `wipe` refuse until that is explained. The assertion prints counts, never names, so naming the directory needs an owner decision under the CLO's hold on C1.
