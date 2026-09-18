---
title: "fix(git-data): reopen /dev/mapper/git-data on every boot from a Doppler-delivered key, and prove it with a rung-2 reboot arm"
date: 2026-09-18
slug: fix-git-data-luks-mapper-reopen-at-boot
branch: feat-one-shot-8210-git-data-boot-reopen
issue: 8210
closes: 8210
type: fix
priority: p2-medium
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- Phase 2.8 reviewed (terraform-architect: IaC-routed yes): every `systemctl` and
     `/etc/systemd/system/` token in this plan is the CONTENT of cloud-init `write_files:`/`runcmd:`
     items and of baked unit files rendered by `modules/git-data-userdata/main.tf` — delivered at host
     birth/replace through the OPERATOR_APPLIED_EXCLUSION route (ADR-103/ADR-149). No step asks a
     human to run them. See `## Infrastructure (IaC)`. -->

> **v2 (post plan-review, 2026-09-18).** The 6-agent panel (DHH, Kieran, code-simplicity, architecture-strategist, spec-flow-analyzer, CTO-devex) plus the Phase 2.5/2.8 leaders (CTO, CPO, terraform-architect) and the Step 4.5 advisor reshaped v1. Cut where BOTH panels fired: the self-wrapping script + sentinel (→ `OnFailure=` reporter, the `git-data-gc` shape), the separate env file (→ two lines in `/etc/default/git-data-doppler`), the bootstrap §1b delegation (→ untouched), ADR-228 (→ dated amendments to ADR-115 and ADR-198), the birth-gate fifth key (→ the workflow upload gate is the enforcement; #8010 owns the gate). Corrected on measured facts: the rehearsal CANNOT be dispatched from this branch (`environment: web-platform-infra-apply` is `main`-only), the evidence file must be DELETED in this PR and re-landed alone (Guard 4 + squash), the `git-data-host-replace` job does NOT run the rung-2 gate today, the git-data host IS born, and `gitDataStore -> doppler` is not in the C4 model.

## Enhancement Summary

**Deepened on:** 2026-09-18 (same session, after plan-review v2)
**Sections enhanced:** 11 (script, units, reporter, runcmd arm, Consumers, reboot arm, Phase 0/1/2/4/5, Observability, Guard Contract, ACs, Files)
**Agents used:** verify-the-negative (15/15 claims confirmed; no stray cut symbols), framework-docs-researcher (systemd 255 + Doppler CLI + crypttab, quoted), git-history-analyzer (9 attributions; 2 PR-number corrections, 1 uncited commit), observability-coverage-reviewer, security-sentinel, test-design-reviewer. Halt gates 4.6/4.7/4.8/4.9/4.10/4.11/4.55 all pass (Downtime & Cutover section added).

### Key improvements
1. **Success row must not page:** `git_data_boot_fatal` filters on `stage` only (no `level` condition), so the reopen's `info` row moves to its own stage `luks_reopen_ok` (the `gc`/`gc_report`, `gitdata_runcmd_ok` precedent) and is deliberately NOT routed.
2. **The Sentry channel could not read the success row:** `scripts/sentry-issue.sh --host-events` hard-codes `level:fatal` and projects no `action`; Phase 4.1 adds a `--stage` mode; `--start` requires `--end`; `HOST_SQL` gains `action`, `restarts`, `luks_reopen_unit` projections.
3. **Reporter discriminates `action=unit`:** it now tags `result=`/`rc=`/`code=`/`restarts=` from `systemctl show` and greps the unit journal's `Doppler Error|Unable to` lines when the script never ran; `ExecStartPre` clears stale phase/log files per attempt; `timeout 90` keeps the reporter's direct arm reachable when Doppler hangs.
4. **Root-disk hygiene closed:** the emitter's `_devalue` writes the escaped passphrase to `mktemp` — on disk-backed `/tmp` that is a root-disk write; both units get `TMPDIR` on tmpfs (`RuntimeDirectory=` + `RuntimeDirectoryPreserve=yes` on the unit, `/dev/shm` on the reporter), `UMask=0077`, `NoNewPrivileges=yes`.
5. **Runtime arm made runnable:** `RUNDIR`/`DEVICE_WAIT` env seams (pinned unset in prod by a guard row), `blockdev` instead of `-b`, absolute-path rewrite for the reporter arm, a phase-tagged call-sequence log for ORDER rows, a positive stub census, `systemd-escape` unstubbed.
6. **Probe semantics fixed:** pre-`since` rows are filtered SERVER-side on both channels and ignored; the verdict is over the post-`since` set only (the production shape always has pre-`since` rows); the stub gains semantic dispatch on the `dt >` clause.
7. **Consumer-roster parity:** a `TERMINAL = producer − NON_TERMINAL` arm in `git-data-emit.test.sh` pins both readers' lists and both SQL projections to the producer.
8. **Input validation:** `validation {}` blocks on `doppler_config_name` / `git_data_luks_volume_id` (the module's `betterstack_logs_token` precedent) and shape asserts in `phase config` — the env file is dot-sourced as root at birth.
9. **Runbook corrected:** `open` and `header` are both "do not replace"; `config` is a payload defect; the DARK bound is the web-side heartbeat for host-down and gc for mapper-closed.

### New considerations discovered
- The inngest reopen unit landed in PR #6894 and was made to actually run in PR #7778 (issue #7695 is the tracking issue; the cloud-init comments cite it); the injection guard is PR #7768 (issue #7761). #7240 (`933635603`) — "rc=1 is a default errno bucket, not a blankness verdict" — is the LUKS-heredoc change this plan's `header` phase must honour: `isLuks` rc alone is never a format authorisation; the reopen path refuses on any non-zero rc, which is the conservative side of that ruling.
- `boot_complete`'s `luks_reopen_unit` reads `Result` at the instant after `enable --now`; a unit mid-`Restart=` on a transient blip reports `no` (fail-closed) even though the host is healthy a minute later — recorded, accepted.

## Overview

The git-data host opens its LUKS mapper exactly once in its life: `cryptsetup luksOpen` runs inside cloud-init's `runcmd:` stage (`cloud-init-git-data.yml`, the `STAGE=luks_open` heredoc under `doppler run --project soleur --config ${doppler_config_name}`), and cloud-init runs `runcmd` **once per instance**. The fstab line the same stage appends (`/dev/mapper/git-data /mnt/git-data-luks ext4 defaults,nofail 0 2`) carries `nofail`, so on any later boot the mount job waits for a mapper that nothing opens, times out, and the boot continues with the encrypted store absent and no signal emitted. ADR-115 already records this as a normative blocker (*"git-data is excluded until that is fixed. Its `luksOpen` is in `runcmd` … per-instance and does not re-run on reboot; there is no `crypttab` …; and its fstab entry carries `nofail`"*).

This plan adds a boot-time, unattended reopen path: one baked script (`git-data-luks-reopen.sh`, straight-line, never formats) run by one systemd oneshot (`git-data-luks-reopen.service`, the `git-data-gc.service` shape: `doppler run --only-secrets … --no-fallback` in `ExecStart`, bounded `Restart=on-failure`) on every boot after `network-online.target`; it fetches `GIT_DATA_LUKS_KEY` from Doppler at that moment (never from the root disk — ADR-198), opens the mapper if it is closed, hands the mount to PID 1 via the fstab-generated mount unit, asserts the mount's source AND the mapper's backing device, and reports `action=reopened` at `info`. Every failure — script, `doppler run`, exec, start-timeout — is reported ONCE, off-host, at `fatal` by an `OnFailure=` reporter unit (`git-data-luks-reopen-failure.service`, the `git-data-gc-failure.service` shape) that reads the `action=` phase file the script maintains. The birth heredoc and bootstrap are untouched except for one new `runcmd` item that arms the unit (`systemctl enable --now`, exercising the noop path at every birth) and one measured, TERMINAL boolean `luks_reopen_unit=yes|no` on `boot_complete`. The rung-2 rehearsal gains a **reboot arm** (Hetzner `actions/reset` + a `--reboot-since` mode of the existing capture script reading BOTH channels) that gates the evidence upload — the only way the `luksOpen`-after-reboot path is proven rather than asserted (#6497 class).

**Out of scope, by the one-shot brief:** #8101 (rsync `hooks/` + mapper assert in the three transport wrappers), #8010 (rehearsal gate binds run id / requires the reboot key / makes the Sentry cross-check load-bearing), #8094 (account-delete swallows a refused erasure), #8211 (rebuild cutover/rollback/wipe). The reopen path is written to be **cutover-agnostic** (it mounts wherever fstab names the mapper), and §"Contract for #8211" records what the cutover must keep true.

## Problem Statement

- **Symptom.** A post-cutover reboot of `soleur-git-data` (Hetzner maintenance, kernel panic, OOM, power event — none of which need the ADR-115 self-reboot primitive) leaves `/mnt/git-data` without its backing device. Every git-data consumer (provision, replicate, fetch, remove) fails, and until #8101 lands a write could land on the root disk under the empty mountpoint.
- **Silence.** `nofail` makes the failed mount a non-event; the web-side probe (`web-git-data-probe.sh`) is a TCP connect to :22, which a rebooted host with a closed mapper passes; the weekly `git-data-gc.timer` is the first thing that would notice, up to seven days later.
- **Why now.** It is a precondition of the first real cutover (#7226, #8209, #8211) and the highest-user-impact item of the post-birth git-data queue. The host is born (2026-09-14) but the store is not user-enabled (`GIT_DATA_STORE_ENABLED` gates every write path), so there is no live impact today — the window to land a payload change that re-holds the rung-2 gate.

## Research Reconciliation — Issue vs. Codebase

| Issue / brief claim | Reality (verified) | Plan response |
|---|---|---|
| "nothing reopens the LUKS mapper at boot" | TRUE. `luksOpen` lives in `runcmd:` (`STAGE=luks_open` heredoc) and in `git-data-bootstrap.sh` §1b, both first-boot-only. `git grep crypttab -- apps/` finds no git-data crypttab; the fstab line is `nofail`. | Add the unit; leave both first-boot sites untouched. |
| "key from the host's boot secret source, as the cutover's `prepare_luks_target` did" | `prepare_luks_target` **no longer exists** — #8189 removed the cutover body; `git-data-cutover.sh` keeps only `LUKS_MAPPER` and `refuse_if_cut_over`. The host's boot secret source is `/etc/default/git-data-doppler` (0600, `DOPPLER_TOKEN` = the read-only `prd_git_data` service token) consumed by `doppler run`, exactly as `git-data-gc.service` does. | The unit's `ExecStart` is the same `doppler run` shape; the key is never written to disk. |
| "a post-cutover reboot leaves `/mnt/git-data` without its backing device" | Today the mapper's fstab target is `/mnt/git-data-luks`; `/mnt/git-data` is the PLAINTEXT volume mounted by-id (reboot-safe). After #8211 the mapper's target becomes `/mnt/git-data`. | The script reads the target from fstab (`findmnt --fstab -S /dev/mapper/git-data -o TARGET`), so the same unit is correct before and after the cutover. |
| "It must land in the cloud-init / bootstrap payload, which is rung-2 hash-bound" | TRUE. `RUNG2_TEMPLATE_SHA256` is a hash-of-hashes over `cloud-init-git-data.yml` plus every `file()` in `modules/git-data-userdata/main.tf` (derived by grep, so new bindings enter automatically). | The stale evidence is DELETED in this PR (Guard 4's permitted shape); fresh evidence lands via PM1/PM2 after merge. |
| "the rehearsal can be dispatched against the branch" (v1 assumption) | FALSE. `git-data-rung2-rehearsal.yml` job `rehearse` has `environment: web-platform-infra-apply`; live policy `{"custom_branch_policies":true}` with branch policies `["main"]` (measured via `gh api …/environments/web-platform-infra-apply/deployment-branch-policies`). Precedent: #8052 merged the payload, #8126 committed the evidence from a `main` run. | AC18 (pre-merge evidence) removed; PM1/PM2 are THE path; PR body uses `Ref #8210`; issue closes by follow-through. |
| "the `git-data-host-replace` job is held by the rung-2 gate" (v1 / terraform-architect) | FALSE. The replace job calls only `git_data_authorization_map_gate` and `git_data_host_replace_gate` (measured: `awk` over the job body, `grep -c rung2` = 0); only `git_data_host_create` calls `git_data_rung2_rehearsal_gate`. | Add the rung-2 gate call to the replace job (Phase 4.5) so an un-rehearsed payload cannot reach the live host by replace either; `terraform-target-parity.test.ts` gets the replace-job case. |
| "no host in the repo has a reboot-safe LUKS reopen" (research agent) | FALSE for inngest: `cloud-init-inngest.yml` ships `inngest-luks-open.service` + `.sh` (#7695) with a BAKED key file. TRUE for the web hosts (#6931 deferred). | Mirror the inngest unit's shape and test set; diverge on key delivery (Doppler at boot) because ADR-198 forbids baking THIS passphrase. |
| "`gitDataStore -> doppler` already exists in C4" (v1) | FALSE. `model.c4` has only `github -> doppler` and `inngest -> doppler`. | Add the edge (Phase 5.3). |

## Research Insights

### Premise Validation (Phase 0.6)

Checked: #8210 OPEN, no closing PR; #8189 CLOSED (by #8206 — where the issue was found); #8262 MERGED as `a19a6df6e`; #8211, #8209, #7226, #8101, #8010, #8094 OPEN (the out-of-scope set is real). Cited files exist on `origin/main`. The key question — *does the LUKS block run on every boot?* — is answered with evidence: it is under `runcmd:` (the `STAGE=luks_open` heredoc), cloud-init's `runcmd` is per-instance, `bootcmd:` contains only the Sentry beacon, and no systemd unit opens the mapper. ADR corpus grep for the mechanism hit ADR-115 (names the defect and two candidate fixes), ADR-119/141/142, ADR-147/149, ADR-198 (the passphrase must not be baked; its leg-(2) incumbent — the baked token can fetch the key — is explicitly recorded). None rejects a systemd oneshot under `doppler run`; ADR-198 rejects the inngest-style baked key for THIS credential.

### Property List (Phase 0.6b)

- **P1** After any reboot, `/dev/mapper/git-data` is open, backed by the pinned by-id device, and mounted at the fstab-named target with `findmnt SOURCE == /dev/mapper/git-data`, with no human involved.
- **P2** The passphrase is obtained at boot from Doppler under the read-only `prd_git_data` token and is never persisted on the root disk (ADR-198) — including Doppler's own fallback cache.
- **P3** A reopen that fails for any reason (config, key, device, header, open, target, mount, identity, `doppler run` itself, exec, start-timeout) produces exactly one routed `level:fatal` event off-host instead of the `nofail` silence.
- **P4** The reopen path can never format or `mkfs`.
- **P5** The first-boot path proves the unit's WIRING (unit enabled, Doppler reachable from the unit's context with the templated config, device pin resolves, fstab target found) so a broken unit surfaces at birth, off-box. It does NOT exercise the open/mount branch — that is P6.
- **P6** The rung-2 rehearsal proves P1 end-to-end on a real reset host before the payload can be attested.
- **P7** `git-data-gc.timer` (`Persistent=true`) orders after the reopen and re-runs it weekly.
  > **Superseded 2026-09-18 (#8210):** gc only ORDERS after the reopen (`After=`, no `Wants=`); the standing retry is the dedicated `git-data-luks-reopen.timer` at 15 min. See the User-Brand Impact addendum, item 4.

### Cut List (Phase 0.6b, updated at plan-review)

| Mechanism considered | Property it would buy | Disposition |
|---|---|---|
| `/etc/crypttab` + `keyscript=` (ADR-115's first candidate) | P1 | **Cut.** `systemd-cryptsetup` implements no `keyscript=`; Debian's `cryptdisks.service` shim runs before the network, so a keyscript cannot reach Doppler (`crypttab(5)`, Debian `cryptsetup` README). Not re-measured (DHH/CTO-devex: paper). |
| `/etc/crypttab` + keyfile on disk (inngest #7695 shape) | P1 | **Cut by ADR-198.** The passphrase decrypts every user's source; a keyfile on the root disk is the passphrase baked. |
| Re-run `git-data-bootstrap.sh` from a boot unit | P1, P5 | **Cut.** Re-emits `boot_complete` (a birth-provenance signal read by the replace poll and the rehearsal — #6921 class); may `apt-get` at boot. |
| Bootstrap §1b delegating to the reopen script | "one implementation" | **Cut at plan-review** (DHH P1, simplicity P1, Kieran B19d). A refactor riding a fix; changes the birth race path and the stage a birth failure emits under. §1b stays verbatim. |
| Self-wrapping script + `/run` sentinel + outer/inner traps | P3 for the `doppler run`-itself failure | **Cut at plan-review** (DHH P0, simplicity P1, spec-flow P0-1/P0-2, Kieran P1-6). Recursed when the key was absent; dark on SIGTERM (bash runs no EXIT trap on an untrapped TERM — measured); duplicated `OnFailure=`. Replaced by the reporter unit. |
| Separate `/etc/default/git-data-luks` env file | P1 (device pin), P6 (rehearsal config) | **Cut at plan-review** (DHH P1, simplicity P2). Two lines appended to the already-templated `/etc/default/git-data-doppler`. |
| New ADR-228 | record the decision | **Cut at plan-review** (DHH P2, simplicity P2, architecture P1-6). The two decisions are amendments: ADR-115 (blocker cleared for git-data) and ADR-198 (leg-(2) incumbent accepted by design under `--only-secrets --no-fallback`). |
| Birth gate REQUIRES `RUNG2_REBOOT_REOPEN` | P6 against hand-committed evidence | **Cut at plan-review** (DHH P1, simplicity P0). The workflow upload `if:` is the enforcement; a hand-edited evidence file can forge any key; #8010 owns the gate. |
| Separate probe script + test suite for the reboot arm | P6 | **Cut at plan-review** (DHH P1, simplicity P2-8). Becomes a `--reboot-since` mode of `git-data-rung2-evidence-capture.sh`, inheriting its query helpers, three-state contract, Sentry cross-check and fixture-driven test. |
| `x-systemd.requires=` on the fstab line | P1 ordering | **Cut, on a corrected reason (review).** The original row read "the script's explicit `systemctl start` buys the same" — that clause is FALSE and it was the load-bearing one. An explicit start produces a `.mount` unit with NO dependency on the reopen unit, so a future consumer's `RequiresMountsFor=/mnt/git-data` orders it after the MOUNT and not after the REOPEN — which is precisely the structural handle ADR-119 §(e) requires. What survives of the row is the first clause (an auto-started `x-systemd.requires=` would delay `local-fs.target` on the network) and it is answered by `noauto`: `nofail,noauto,x-systemd.requires=git-data-luks-reopen.service` gives the ordering handle without the delay, since nothing auto-starts it and the script's explicit start stays the trigger. Carried into the #8211 contract as clause (h), not re-decided here. |
| `chattr +i` on the unmounted mountpoint | fail-closed writes into an empty mountpoint | **Deferred to #8101.** |
| In-script retry loop on Doppler/DNS blips | P1 on transient failure | **Cut.** A retrying guard hides its instrument fault (2026-07-15 learning); systemd's bounded `Restart=on-failure` gives the same property with the terminal failure still reported once. |
| SSH remediation lever in the runbook | operator recovery | **Cut by `hr-no-ssh-fallback-in-runbooks`.** |

### Relevant files (content anchors)

- `apps/web-platform/infra/cloud-init-git-data.yml` — `runcmd:` `STAGE=luks_open` heredoc (closing `LUKSEOF` line); the fstab append `grep -q '/dev/mapper/git-data' /etc/fstab || echo '/dev/mapper/git-data /mnt/git-data-luks ext4 defaults,nofail 0 2'`; `write_files` `path: /etc/default/git-data-doppler` (templated: `DOPPLER_TOKEN=${doppler_token}`, `DOPPLER_CONFIG_DIR=/tmp/.doppler`, 0600, #7460); the `STAGE=gitdata_nftables_metadata` item (`systemctl daemon-reload || true` + substitution-plus-`if` capture with `_nft_detail` + WARNING emit at `"$${STAGE}_warn"`) is the shape the new arm item copies; `STAGE=bootstrap` runs `doppler run … -- bash /usr/local/bin/git-data-bootstrap.sh` (no `--only-secrets` today — PM6).
- `apps/web-platform/infra/git-data-bootstrap.sh` — §1b (untouched) and the `boot_complete` emit (`"luks_mounted=yes" "repo_root=yes" "hooks_path=yes" "provision=yes" "nft_metadata_drop=${_nft_drop}" …`), where `_nft_drop` is the measured-boolean precedent.
- `apps/web-platform/infra/git-data-gc.service` / `git-data-gc-failure.service` — the unit pair to mirror: `EnvironmentFile=-/etc/default/git-data-doppler`, `Environment=HOME=/root`, `ExecStart=/bin/sh -c 'exec /usr/local/bin/doppler run --project soleur --config prd_git_data -- …'`, `PrivateTmp=yes`, `OnFailure=` under `[Unit]`; the failure unit's `set -- …; doppler run … -- "$@" || "$@"` fallback arm and its EnvironmentFile-not-dot-source rationale.
- `apps/web-platform/infra/inngest-cutover-flip.service` — repeated `--only-secrets NAME` flag form (tree precedent); `cloud-init-registry.yml` `/etc/cron.d/zot-log-shipper` — `--only-secrets … --no-fallback` with the F-13/F-14 rationale.
- `apps/web-platform/infra/cloud-init-inngest.yml` — `inngest-luks-open.service`/`.sh` (tracking issue #7695; landed in PR #6894 "the on-host LUKS cutover FSM, its unit trio, and its delivery", made to actually run in PR #7778 "the boot-reopen unit that would never have run"): bounded 30 s device wait, "opens ONLY; never formats", `reopen_noop`/`reopen_ok` markers, `systemctl enable --now` in runcmd with armed/ARM-FAILED self-report. `inngest-redis-luks.test.sh` T1.1/T1.2/T1.6 are the mutation shapes to mirror.
- `apps/web-platform/infra/modules/git-data-userdata/main.tf` — the `templatefile` vars map (one `replace(file(…), local.git_data_rationale_strip, "")` per line); `git-data-userdata-budget.sh` mirrors it (today `stored=15,444 B / cap=32,768 B`).
- `apps/web-platform/infra/git-data-luks.test.sh` — `p_doppler_config_scope` (sibling census: `git-data-cutover.sh`, `git-data-gc-failure.service`, `git-data-gc.service`; non-line-anchored `grep -Ec 'doppler run --project soleur '`), `boot_path_files()` (derives the module roster; A28a floor `_bp_count -ge 11`; A28b permits only `[ -n "${GIT_DATA_LUKS_KEY:-}"` / `printf '%s' "$GIT_DATA_LUKS_KEY"` expansion shapes), B16a (exactly one `mkfs`), B17, B18, B19d (`p_bootstrap_keyfile_stdin` over bootstrap — untouched since §1b stays).
- `apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh` — `EXPECTED_PATHS` var→path roster (`MIN_PAYLOADS = max(9, len(EXPECTED_PATHS))`), `_R3B_EXPECTED_SITES='gc_timer / gitdata_nftables_metadata / luks_err / on_err / sshd_config'` (set equality on reporting-emit windows), R3(3b)(iii) "two emit windows share a detail-variable name" FAIL.
- `apps/web-platform/infra/git-data-render-strip-parity.test.sh` — `"$n_entries" -eq 9` literal; `git-data-template-strip.test.sh` derives its roster (no edit).
- `apps/web-platform/infra/git-data-emit.test.sh` — AC30-parity `_asserted_keys="$(printf '%s\n' luks_mounted repo_root hooks_path provision nft_metadata_drop disk_pct inode_pct …` (hand roster vs bootstrap's emit).
- `apps/web-platform/infra/doppler-injection-bound.test.sh` — Guard 2 (issue #7761, PR #7768): a `doppler run` unit is in the bound-required population only on a command-position seam (`CMD_POS_RE`); the new script uses `GIT_DATA_LUKS_DEV` only as an argument, so the units are out of population and `--only-secrets` is voluntary — a Guard 1 static row (no line begins with `"$`, no `exec "$`/`. "$`) pins that status.
- `933635603` (#7240, 2026-08-04) — "rc=1 is a default errno bucket, not a blankness verdict — gate luksFormat on blkid": the LUKS-heredoc ruling the reopen's `header` phase inherits conservatively (any non-zero `isLuks` rc refuses; there is no format branch to authorise).
- `.github/workflows/infra-validation.yml` — explicit `run:` per `apps/web-platform/infra/*.test.sh`; `Lint the git-data systemd unit set` (`systemd-analyze verify`, filter `git-data-gc[^:]*`); `Rung-2 evidence freshness (active only once evidence exists)` in `deploy-script-tests` (red while a stale evidence file exists).
- `apps/web-platform/infra/sentry/issue-alerts.tf` — `sentry_alert.git_data_boot_fatal` (ten `stage` `eq` filters) and `git_data_boot_warning` (`in` list); `alert-reference.json` held equal by `scripts/sentry-alert-reference-gate.sh`.
- `scripts/followthroughs/git-data-rung2-evidence-capture.sh` — three-state contract, source-liveness anchor, `HOST_SQL=` projection, FAIL regex `"(luks_mounted|repo_root|hooks_path|provision)":"no"`, Sentry cross-check via `scripts/sentry-issue.sh --host-events`, `--host-name/--since/--out/--window/--verify-only`. `scripts/lib/git-data-boot-signal-poll.sh` — `git_data_boot_sql`, `for f in luks_mounted repo_root hooks_path provision`, `nft_metadata_drop` handled as `::warning::` (reported, never terminal).
- `.github/workflows/git-data-rung2-rehearsal.yml` — `environment: web-platform-infra-apply` (main-only), `timeout-minutes: 30`, `concurrency: git-data-state`, `host=${REHEARSAL_PREFIX}${GITHUB_RUN_ID}` output, `RUNG2_SENTRY_SINCE` before apply, bounded capture poll, upload gated on `steps.capture.outputs.capture_rc == '0'`, teardown reads `HCLOUD_TOKEN` from `prd_terraform` with `::add-mask::`.
- `.github/workflows/apply-web-platform-infra.yml` — `git_data_host_create` calls `git_data_birth_readiness_gate`, `git_data_rung2_rehearsal_gate`, `git_data_authorization_map_gate`, `git_data_host_birth_gate`; `git_data_host_replace` calls only `git_data_authorization_map_gate` + `git_data_host_replace_gate`; disclosure prose "Exactly **one** boolean in that row is measured: `nft_metadata_drop`"; the replace job's "Post-replace readiness note" lists four booleans.
- `tests/scripts/lib/git-data-birth-readiness-gate.sh` — `git_data_rung2_rehearsal_gate` (required keys exactly-once; hash derived by grepping `file("${path.module}/…")`); GUARD 4 (#8043 NFR2): evidence never MODIFIED in the same change as a bound file; may be DELETED there, or CREATED alone. `plugins/soleur/test/terraform-target-parity.test.ts` pins which gates each job INVOKES.
- `scripts/followthroughs/git-data-birth-emitter-6982.sh`, `knowledge-base/engineering/operations/runbooks/git-data-birth.md` — four-boolean SQL/prose (updated for the fifth).
- `knowledge-base/engineering/architecture/decisions/ADR-115-…` (`NORMATIVE BLOCKER (binding on any future extension of this ADR)`), `ADR-198-…` ("Leg (2) is already failed on this host, by an incumbent this ADR does not disturb … tracked at #7772" — #7772 is CLOSED without removing the path), `ADR-149`, `ADR-103`.
- `knowledge-base/engineering/architecture/diagrams/model.c4` — `gitDataStore = database "Shared git-data"`; edges `github -> doppler`, `inngest -> doppler` exist; no `gitDataStore -> doppler`.

### Institutional learnings applied

- `knowledge-base/project/learnings/2026-07-24-guest-luks-store-must-gate-consumer-on-mount-and-guard-suite-must-pin-fail-loud-semantics.md` — assert `findmnt SOURCE`, not `mountpoint -q`; guards pin the `exit 1`.
- `knowledge-base/project/learnings/2026-07-18-web-1-root-doppler-unit-needs-home-and-dedicated-token-and-vector-toml-has-no-running-host-delivery.md` — `Environment=HOME=/root`; dedicated read-scoped token (exists: `doppler_service_token.git_data`).
- `knowledge-base/project/learnings/2026-07-15-self-healing-guard-on-a-blind-host-must-fail-safe-on-its-own-instrument.md` — fail closed on every unread state; never format; no in-script retry.
- `knowledge-base/project/learnings/2026-07-16-refuting-a-hypothesis-by-reasoning-while-its-discriminator-is-invisible.md` — the reboot arm exists because the reopen path is otherwise unobservable.
- `knowledge-base/project/learnings/2026-07-03-cloud-init-32kb-cap-bake-and-extract-not-compress.md`, `knowledge-base/project/learnings/2026-07-06-cloud-init-user-data-cap-bake-bodies-and-set-e-scope-fix-ungates-security-checks.md` — rationale in stripped comment lines; measure with the budget script.
- `knowledge-base/project/learnings/2026-09-11-the-gate-i-built-for-a-dark-host-was-blind-to-the-byte-shape-of-nothing.md` — stub the process boundary; a stale signal can outlive state — `since` is pinned before the reset.
- `knowledge-base/project/learnings/2026-09-14-a-systemd-state-used-as-a-signal-had-no-provenance-and-replayed-a-stale-capture.md` — `boot_complete` stays birth-only; the reboot has its own row.
- `knowledge-base/project/learnings/security-issues/2026-09-14-the-plan-capped-the-message-before-it-redacted-it-and-a-config-is-not-a-consumer-boundary.md` — the reporter emits under `doppler run` so `_devalue` is armed; its fallback arm ships the detail unredacted only when Doppler itself is down (cryptsetup never echoes the key).
- `knowledge-base/project/learnings/2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md`, `knowledge-base/project/learnings/2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md` — harness rows and a dispatch floor.

### External references (claims to MEASURE in Phase 0, not to inherit)

- `systemd.exec(5)`: `PrivateTmp=` creates a private mount namespace with slave propagation — a `mount(8)` inside is invisible to PID 1. `systemd.service(5)`: `Restart=always|on-success` are forbidden for `Type=oneshot`; `Restart=on-failure` is allowed; `OnFailure=` units fire when the unit enters the final `failed` state (after the restart limit), so bounded restarts do not fan out the fatal. `systemd.mount(5)`: fstab entries without `noauto` are pulled in by their device unit; `nofail` demotes `local-fs.target`'s dependency to `Wants=`.
- Hetzner Cloud API `POST /v1/servers/{id}/actions/reset` (hard reset) and `GET /v1/servers/{id}/actions/{action_id}`; the rehearsal workflow already authenticates to this API for teardown.
- Doppler CLI 3.75.3 (the pinned tarball): `doppler run --only-secrets NAME` (repeatable), `--no-fallback`, `--config`; forwards the child's exit code.

### Skill-description budget

No `SKILL.md` `description:` edit is a candidate. Skipped.

## Proposed Solution

One script, one unit, one reporter unit, two env lines, one runcmd arm item, one measured boolean, one rehearsal reboot arm, two ADR amendments, one C4 edge.

### The script — `apps/web-platform/infra/git-data-luks-reopen.sh` → `/usr/local/bin/git-data-luks-reopen.sh`

Baked through the module map like `git-data-bootstrap.sh` (`replace(file(…), local.git_data_rationale_strip, "")`), so NOT templatefile'd: no `${…}` inside it; everything it needs arrives as environment from the unit (`EnvironmentFile=` + `doppler run`). `#!/bin/bash` (dash has no `pipefail`), straight-line, `set -euo pipefail`, refuses xtrace (bootstrap's `#7797` guard), **no traps and no fatal emits** — reporting belongs to the reporter unit. Its only writes are two 0600 files under `$RUNDIR` and the success `info` emit. Two test seams, both env-overridable and both pinned UNSET in production by Guard 1 (a unit that sets either is RED): `RUNDIR="${GIT_DATA_REOPEN_RUNDIR:-/run/git-data-luks-reopen}"` and `DEVICE_WAIT="${GIT_DATA_REOPEN_DEVICE_WAIT:-30}"` — without them the runtime arm cannot write `/run` or afford a 30 s device fixture (test-design P0-1). Every external command is called by bare name (`cryptsetup`, `findmnt`, `systemctl`, `git-data-emit`, …) so a scratch `PATH` intercepts it; a static row pins `grep -c '/usr/local/bin/' == 0` in the script.

- **Phase file.** `phase() { printf 'action=%s\n' "$1" > "$RUNDIR/action"; }` — written BEFORE each phase runs (the tag names the phase that was executing when the script died, including on SIGTERM); stderr of every fallible command appends to `$RUNDIR/log` (seeded at entry under `UMask=0077`). The reporter reads both. **On the success path the script `rm -f`s both files** so a later same-boot failure inside `doppler run` cannot ship a stale `action=identity-mount` (observability P2-1).
- `phase config` — `GIT_DATA_LUKS_DEV` matches `^/dev/disk/by-id/scsi-0HC_Volume_[0-9]+$` and `GIT_DATA_DOPPLER_CONFIG` matches `^[a-z0-9_]+$`, else exit 1 (security §4: the env file is dot-sourced as root at birth; the shape assert also refuses a `--`-prefixed value being parsed as a flag).
- `phase key` — `[ -n "${GIT_DATA_LUKS_KEY:-}" ]` else exit 1 (never an unencrypted fallback, NFR-026; the A28b-permitted expansion shape).
- `phase device` — bounded `$DEVICE_WAIT` s wait until `blockdev --getsize64 "$DEV"` prints a positive integer (the inngest shape minus the un-stubbable `-b` builtin — `blockdev` on a non-block path exits non-zero, so `-b` adds nothing); absent → exit 1.
- `phase header` — `cryptsetup isLuks "$DEV"` rc 0 required; any other rc → exit 1 with the rc in the log. **No `luksFormat`, no `mkfs`, no blkid-blankness branch.**
- `phase open` — `[ -e /dev/mapper/git-data ]` → `ACTION=noop`; else `printf '%s' "$GIT_DATA_LUKS_KEY" | cryptsetup luksOpen --key-file - "$DEV" git-data` → `ACTION=reopened`.
- `phase identity` (backing device, BOTH paths — spec-flow (g)) — `cryptsetup status git-data` `device:` realpath equals `realpath "$DEV"`, else exit 1 (a stale pin after a volume swap must not pass as a healthy reopen).
- `phase target` — `TARGET=$(findmnt --fstab -n -S /dev/mapper/git-data -o TARGET || true)`; exactly one non-empty line else exit 1 (`findmnt` exits 1 on no match, so the `|| true` is load-bearing under `set -e`).
- `phase mount` — if `! mountpoint -q "$TARGET"`: `systemctl daemon-reload || true` then `systemctl start "$(systemd-escape -p --suffix=mount "$TARGET")"`; on failure append `journalctl -u <unit> -n 20` to the log and exit 1. The script never calls `mount(8)`: under `PrivateTmp=yes` the unit has its own mount namespace. If the mount was absent and is now present, `ACTION` becomes `mounted` unless it is already `reopened` (spec-flow: `{noop, reopened, mounted}` is the exhaustive success set).
- `phase identity-mount` — `findmnt -n -o SOURCE "$TARGET"` equals `/dev/mapper/git-data` else exit 1.
- **Success.** `ACTION=reopened|mounted` → `git-data-emit "git-data LUKS mapper reopened at boot" luks_reopen_ok info "" "action=$ACTION" "target=$TARGET" "restarts=$(systemctl show --value -p NRestarts git-data-luks-reopen.service)"`; `ACTION=noop` → silent (birth stays quiet; the birth proof is the boolean). **The stage is `luks_reopen_ok`, not `luks_reopen`:** `sentry_alert.git_data_boot_fatal` has NO `level` condition — its filters are `stage` `eq` rows under `event_frequency_count value = 0`, so an `info` row on a routed stage would page the host's only fatal channel on every healthy reboot (observability P1-1). `luks_reopen_ok` is deliberately absent from every rule, exactly like `gitdata_runcmd_ok` and `bootcmd_start`. The `restarts=` tag makes a transient-blip-then-success visible without a per-attempt warning.
- Comment header (stripped from the payload, zero budget cost) carries the phase table and states that no literal `doppler run --project soleur ` may appear in this file's comments (Kieran: `p_doppler_config_scope` is not line-anchored).

### The two env lines — appended to the existing `write_files` `path: /etc/default/git-data-doppler`

```
GIT_DATA_LUKS_DEV=/dev/disk/by-id/scsi-0HC_Volume_${git_data_luks_volume_id}
GIT_DATA_DOPPLER_CONFIG=${doppler_config_name}
```

Both variables already exist and are already in `RUNG2_VAR_DIVERGENCE`. The file is already templated, 0600, `EnvironmentFile=`'d by the gc units and `set -a`-sourced by the bootstrap item — so the pin and the config name reach every consumer with no new file. **The config name is templated, never hardcoded** (terraform-architect BLOCKING): the rung-2 root scopes its token to `prd_git_data_rehearsal_<run_id>` (`rung2-rehearsal/rehearsal.tf`), so a hardcoded `prd_git_data` would exit 1 with the key ABSENT on every rehearsal reboot. No secret is added to the file.

### The unit — `apps/web-platform/infra/git-data-luks-reopen.service`

```
[Unit]
Description=Reopen the git-data LUKS mapper from Doppler on every boot (#8210)
Documentation=https://github.com/jikig-ai/soleur/issues/8210
Wants=network-online.target
After=network-online.target
OnFailure=git-data-luks-reopen-failure.service
StartLimitIntervalSec=1h
StartLimitBurst=5

[Service]
Type=oneshot
RemainAfterExit=yes
Restart=on-failure
RestartSec=60
Environment=HOME=/root
Environment=TMPDIR=/run/git-data-luks-reopen
EnvironmentFile=-/etc/default/git-data-doppler
RuntimeDirectory=git-data-luks-reopen
RuntimeDirectoryPreserve=yes
UMask=0077
NoNewPrivileges=yes
ExecStartPre=/bin/rm -f /run/git-data-luks-reopen/action /run/git-data-luks-reopen/log
ExecStart=/bin/sh -c 'exec /usr/local/bin/doppler run --project soleur --config "$GIT_DATA_DOPPLER_CONFIG" --only-secrets GIT_DATA_LUKS_KEY --only-secrets BETTERSTACK_LOGS_TOKEN --no-fallback -- /usr/local/bin/git-data-luks-reopen.sh'
TimeoutStartSec=300
TimeoutStopSec=30
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
```

The `git-data-gc.service` shape (`/bin/sh -c 'exec …'` keeps `systemd-analyze verify` green on runners without doppler; `EnvironmentFile=-` so an absent token file fails inside `doppler run`, which the reporter reports). `--no-fallback` declines Doppler's on-disk encrypted fallback cache (without it the resolved passphrase is written under `$DOPPLER_CONFIG_DIR` on the root disk — CTO P1; registry F-13 precedent); `--only-secrets` (repeated-flag form, the `inngest-cutover-flip.service` precedent) narrows the injected env and satisfies `doppler-injection-bound.test.sh` Guard 2 without an ACK. `PrivateTmp=yes` confines the `/tmp/.doppler` surface (#6536). Bounded `Restart=on-failure` re-attempts a transient Doppler/DNS blip five times in an hour without an in-script loop; `OnFailure=` fires once, when the unit reaches its FINAL failed state — **documented** (framework-docs pass): systemd's `service.c` rejects only `Restart=always|on-success` for `Type=oneshot`, so `on-failure` + `RemainAfterExit=yes` is a supported pair, and `service_enter_dead()` transitions through `SERVICE_FAILED_BEFORE_AUTO_RESTART` so `OnFailure=` is suppressed while an auto-restart is pending. Phase 0.2 still runs `systemd-analyze verify` on the pair to pin it. **`TMPDIR` on tmpfs is load-bearing** (security §1c): `git-data-emit`'s `_devalue_luks` writes the sed-escaped passphrase to `mktemp` before `rm -f`; on a disk-backed `/tmp` (Ubuntu 24.04 default — Phase 0.7 measures `findmnt -n -o FSTYPE /tmp` on the rehearsal image) that is a root-disk write of the key, and `PrivateTmp` only bind-mounts a subdirectory of the same device. `RuntimeDirectoryPreserve=yes` is mandatory with `RuntimeDirectory=`: systemd removes the directory when the unit reaches its final failed state — BEFORE `OnFailure=` runs — so without it the reporter would read nothing and emit `action=unit` for every class. `ExecStartPre` clears the phase/log files per attempt so a mixed-cause restart sequence (attempt 1 dies at `open`, attempts 2–5 die in `doppler run`) reports the FINAL cause, not the first. `ProtectSystem=strict` is not copied from gc: `cryptsetup` needs `/run/cryptsetup` and the reporter needs `/run/git-data-luks-reopen`; it is a Phase 0.2 measurement, not an assumption.

### The reporter — `apps/web-platform/infra/git-data-luks-reopen-failure.service`

The `git-data-gc-failure.service` shape (`Type=oneshot`, `Environment=HOME=/root`, `Environment=TMPDIR=/dev/shm` — NOT the unit's `RuntimeDirectory`, which two units sharing would remove when either stops; `EnvironmentFile=-/etc/default/git-data-doppler`, `UMask=0077`, `TimeoutStartSec=120`), with `ExecStart=/bin/sh -c '…'` that:

1. reads `a=$(head -n1 /run/git-data-luks-reopen/action 2>/dev/null | grep -oE "^action=[a-z-]+" || echo action=unit)`;
2. reads the unit's own verdict — `result=$(systemctl show --value -p Result git-data-luks-reopen.service)` (`exit-code|timeout|signal|start-limit-hit`), `rc=$(… -p ExecMainStatus)`, `code=$(… -p ExecMainCode)`, `restarts=$(… -p NRestarts)` — which is what discriminates the four `action=unit` sub-causes in one event (observability P1-3; Phase 0.2 pins that `ExecMainStatus`/`ExecMainCode` survive the `start-limit-hit` transition on systemd 255);
3. sets `d=/run/git-data-luks-reopen/log`; when that file is absent or empty, `d="$(journalctl -u git-data-luks-reopen.service -o cat --no-pager -n 40 | grep -E '^(Doppler Error|Unable to)' | tail -n 2)"` — the doppler CLI's stderr is credential-free (measured: `you must provide a token`, `Invalid Auth token`, `dial tcp … connection refused`) and a grep, not a raw tail, because `_clean` keeps the LAST 180 bytes and systemd's own `Failed with result …` trailer would push the cause out (#7227 ordering); when that grep is empty, `d="git-data luks_reopen: the unit failed before the script wrote a detail (doppler run, exec, or start timeout)"` (never a literal path — the #7204 trap);
4. `set -- /usr/local/bin/git-data-emit "git-data LUKS reopen FAILED" luks_reopen fatal "$d" "$a" "$result" "$rc" "$code" "$restarts" "unit=git-data-luks-reopen.service"; timeout 90 /usr/local/bin/doppler run --project soleur --config "$GIT_DATA_DOPPLER_CONFIG" --only-secrets GIT_DATA_LUKS_KEY --only-secrets BETTERSTACK_LOGS_TOKEN --no-fallback -- "$@" || "$@"` — the `timeout 90` is what keeps the direct arm reachable when Doppler HANGS rather than exits (security §5a: without it `TimeoutStartSec=120` kills the cgroup and neither arm emits, on the one unit that is the sole signal for a store-absent host).

Under `doppler run` the emitter's `_devalue` redactor is armed; when Doppler itself is the broken stage the fallback arm still fires from the baked DSN. What the unredacted fallback can carry (enumerated, security §1b / observability P2-1): stderr of `blockdev`, `cryptsetup isLuks|luksOpen --key-file -|status` (`No key available with this passphrase.`, `… is not a valid LUKS device.`, `… is in use` — never the input), `findmnt`, `mountpoint`, `realpath`, `systemctl start` (`Job for … failed`), the mount unit's journal (`wrong fs type, bad option, bad superblock`), and bash `set -u` variable NAMES; `_clean`'s pattern rules still run. One failure, one event, for every failure class including start-timeout (systemd, not a bash trap, is the reporter); the inherited gc-failure shape can double-emit only when `doppler run` succeeds and the emitter itself exits non-zero (bounded, noted in the runbook).

### The runcmd arm item (new, placed immediately after the `STAGE=luks_open` heredoc item's closing `LUKSEOF`, before `STAGE=gitdata_nftables_metadata`)

The nftables item's shape with its own names: `STAGE=gitdata_luks_reopen_arm`, detail truncate, `systemctl daemon-reload || true`, `_arm_rc=0; _arm_err="$(systemctl enable --now git-data-luks-reopen.service 2>&1)" || _arm_rc=$?`, and on failure a WARNING emit at `"$${STAGE}_warn"` with `_reopen_arm_detail` (a DISTINCT detail-variable name — R3(3b)(iii) fails two emit windows sharing one). Warning, not fatal: an unarmed reopen is a hardening regression on a host that does not self-reboot, not a dark host — and it is not silent: `enable --now` runs the script's noop path, so a script failure at birth fires the reporter's `luks_reopen` FATAL, and `boot_complete` carries `luks_reopen_unit=no`, which FAILS the capture and the boot-signal poll. Placed before bootstrap so `boot_complete` measures it. Both `gitdata_luks_reopen_arm` (the top-armed `on_err` re-points at it) and `gitdata_luks_reopen_arm_warn` get Sentry routes (Kieran P1-7). This blocks cloud-final for at most `TimeoutStartSec` (300 s) if Doppler is slow at birth; the capture poll window (10 min) exceeds it.

### The measured boolean — `git-data-bootstrap.sh`

Beside `_nft_drop`: `_reopen_unit=no; if systemctl is-enabled --quiet git-data-luks-reopen.service && [ "$(systemctl show -p Result --value git-data-luks-reopen.service)" = success ]; then _reopen_unit=yes; fi`; `boot_complete` gains `"luks_reopen_unit=${_reopen_unit}"`. `Result=success` (not `is-active`) is correct whether or not `RemainAfterExit` survives Phase 0. **TERMINAL, unlike `nft_metadata_drop`:** an unarmed reopen unit on the LIVE host is caught only by the replace poll (the reboot arm runs in rehearsals, not on `git-data-host-replace`), so the boolean joins the four terminal names in both readers. What it measures: the unit ran once and succeeded at birth — not the current mount (a later `luksClose`/detach is the residual gc-bounded window).

### Consumers

- `git-data-gc.service`: `Wants=git-data-luks-reopen.service` + `After=git-data-luks-reopen.service` under `[Unit]` — the weekly timer becomes a standing retry (ADR-115 amendment (a)), and gc never runs against the reopen window.
- Sentry `issue-alerts.tf`: `luks_reopen` and `gitdata_luks_reopen_arm` join `git_data_boot_fatal` (ten → twelve `eq` filters; update the prose count and the "PII: the payload is four booleans" comment); `gitdata_luks_reopen_arm_warn` joins `git_data_boot_warning`'s `in` list; **`luks_reopen_ok` is added to NO rule**, with a comment mirroring the `bootcmd_start is deliberately ABSENT` note (an `info` row on a routed stage pages — the rule has no `level` condition); regenerate `alert-reference.json`.
- `scripts/sentry-issue.sh`: `--host-events` hard-codes `level:fatal` and projects only `timestamp,level,host_name,stage,rc,detail`, and `--start` without `--end` is rejected — so as shipped it can neither read the success row nor serve the reboot probe's Sentry channel (observability P1-2). Phase 4.1 adds a `--stage <stage>` option that swaps the `level:fatal` term for `stage:<stage>` and projects `field=action`; the probe passes `--start "$since" --end "$(date -u +%FT%T)"`.
- Module `variables.tf`: `validation {}` blocks on `doppler_config_name` (`^[a-z0-9_]+$`) and `git_data_luks_volume_id` (`^[0-9]+$`) — the module already pins `betterstack_logs_token` this way; both values are dot-sourced as root at birth.
- Readers of the boolean vocabulary (the architecture sweep): `scripts/lib/git-data-boot-signal-poll.sh` (`for f in …` + SQL projection), `scripts/followthroughs/git-data-rung2-evidence-capture.sh` (FAIL regex + `HOST_SQL` projection + PASS prose "five assertions"), `apps/web-platform/infra/git-data-emit.test.sh` (AC30-parity `_asserted_keys`), `.github/workflows/apply-web-platform-infra.yml` (disclosure prose "exactly one boolean is measured" → two; the replace job's readiness note lists five), `scripts/followthroughs/git-data-birth-emitter-6982.sh` (SQL), `knowledge-base/engineering/operations/runbooks/git-data-birth.md` (SQL + prose), plus both `tests/scripts/test-*.sh` fixtures. `git-data-rung2-rehearsal.test.sh` arm 20d self-derives from `HOST_SQL` — no edit.

### The rung-2 reboot arm — `.github/workflows/git-data-rung2-rehearsal.yml`

After the capture step PASSes and BEFORE the evidence upload:

1. **Settle** — `sleep 120` after capture PASS (Kieran P2-13): `boot_complete` fires before the `gc_timer` item and cloud-final's semaphore; a reset inside that window re-runs the whole `runcmd` on the next boot and replays `boot_complete`.
2. **Reset** (`id: reset`) — resolve the server by EXACT name `${REHEARSAL_PREFIX}${GITHUB_RUN_ID}` (the apply step's `host=` output; `GET /v1/servers?name=<HOST>` — Hetzner's `name` filter is exact, so a >50-server project cannot silently drop the target the way the teardown's `per_page=50` list would — then `jq --arg n "$HOST" '.servers[] | select(.name == $n) | .id'`, exactly one id else fail closed; can never match `soleur-git-data` or a leftover survivor), `::add-mask::` the token (teardown shape), record `RUNG2_REBOOT_SINCE=$(date -u +%Y-%m-%dT%H:%M:%S)` on a line BEFORE the `curl -X POST`, `POST /v1/servers/{id}/actions/reset` (hard reset — no ACPI ambiguity; exercises ext4 journal replay on the mapper), poll `GET …/actions/{id}` to `success` (≤ 120 s).
3. **Probe** (`id: reboot_probe`) — the same bounded poll shape as the capture step, calling `bash scripts/followthroughs/git-data-rung2-evidence-capture.sh --reboot-since "$RUNG2_REBOOT_SINCE" --host-name "$HOST" --out /tmp/rung2/git-data-rung2-boot-evidence.env`. In this mode the script reads BOTH channels with the `since` bound applied SERVER-side (Better Stack: `HOST_SQL` with `dt > parseDateTimeBestEffort('<since>')` — the capture's `_BS_WHEN` shape — and projecting `action`, `restarts`; Sentry: `sentry-issue.sh --host-events "$HOST" --stage luks_reopen_ok --start "$since" --end "$now"` plus the existing fatal read) — the emitter's Better Stack POST has no `--retry`, so a single ingest miss must not burn a host (spec-flow P1-6). **Pre-`since` rows are ignored, not a verdict:** the production shape ALWAYS has pre-`since` rows (the whole birth boot), so the verdict is over the post-`since` set only (test-design P0-2): **0 PASS** = a `stage:luks_reopen_ok action:reopened` row in either channel AND zero `level:fatal` rows in either; **1 FAIL** = any fatal, or any `luks_reopen_ok` row whose `action` is not `reopened` (a mapper cannot survive a reset; `noop`/`mounted` after one means the probe or the host is lying); **2 TRANSIENT** = an EMPTY post-`since` set while the source-liveness anchor answers. On PASS it appends `RUNG2_REBOOT_REOPEN=PASS`, `RUNG2_REBOOT_REOPEN_CHANNEL=<betterstack|sentry|both>`, `RUNG2_REBOOT_REOPEN_RESTARTS=<n>` plus its `QUERY:` comments to the evidence file (extra keys are tolerated by the gate; requiring them is #8010).
4. **Upload gate** — `if: … && steps.capture.outputs.capture_rc == '0' && steps.reboot_probe.outputs.reboot_rc == '0'`. Evidence that the reopen failed is never published.
5. `timeout-minutes: 30` → `45` with a comment summing the bounded polls (CTO-devex P1-2: 25 + 2 + 2 + 10 > 30). Teardown unchanged (`always()`).

The rehearsal is dispatched from `main` after merge (the environment's branch policy permits nothing else); see Post-merge.

### The replace job gains the rung-2 gate — `.github/workflows/apply-web-platform-infra.yml`

`git_data_host_replace` today calls only the authorization-map and host-replace gates, so an un-rehearsed payload could reach the live host by replace from any ref (architecture P0-1). Add a step before its plan step mirroring the create job's `if ! git_data_rung2_rehearsal_gate "${GITHUB_WORKSPACE}/apps/web-platform/infra/cloud-init-git-data.yml"; then … exit 1; fi`, and extend `plugins/soleur/test/terraform-target-parity.test.ts`'s "the job INVOKES each gate" case to the replace job. Consequence, stated plainly: the replace route — the only remediation lever for the live host — is HELD from this PR's merge until PM2 lands fresh evidence. That is the intended safe state (the store is not user-enabled), and PM1 is dispatched in the merging session to keep the window short.

### Contract for #8211 (recorded, not implemented here)

The reopen mounts wherever `/etc/fstab` names `/dev/mapper/git-data`, and asserts the mapper is backed by `GIT_DATA_LUKS_DEV`. The cutover MUST: (a) rewrite that fstab line's target to `/mnt/git-data`; (b) remove or repoint the plaintext by-id line that also targets `/mnt/git-data`, so exactly one fstab entry claims the target; (c) `systemctl daemon-reload`; (d) keep exactly one fstab entry whose source is the mapper (the script's `target` phase catches (b)/(d) at the next boot); (e) NOT flip `GIT_DATA_STORE_ENABLED` while the weekly gc fatal is the only STANDING mapper-mounted signal — #8101's per-call mapper assert, or an equivalent standing signal bounded in minutes, must be live first (CPO condition); (f) make the post-cutover fstab/target state BIRTH-REPRODUCIBLE (template-level, and bootstrap's hardcoded `LUKS_ROOT="/mnt/git-data-luks"` derived from fstab), because a post-cutover `git-data-host-replace` re-runs the birth heredoc, which recreates the PRE-cutover fstab — the reopen would then faithfully mount the mapper at `/mnt/git-data-luks` while consumers read plaintext at `/mnt/git-data`; (g) treat a change of the mapper's backing device (rotation attaching a second LUKS volume) as a host-config change delivered by replace, never in place — the script's device-identity phase refuses a stale pin; (h) close the sshd window: `ssh.socket` accepts before `network-online → doppler → luksOpen → mount` completes (tens of seconds; indefinitely on a failed reopen), so post-cutover the forced-command wrappers need #8101's per-call mapper assert or an `ssh.service` drop-in `After=git-data-luks-reopen.service` (ordering only — a failed reopen delays sshd ≤ 300 s, never blocks it); and write the rewritten fstab line as `nofail,noauto,x-systemd.requires=git-data-luks-reopen.service`, so a consumer's `RequiresMountsFor=/mnt/git-data` is ordered after the REOPEN rather than merely after the mount. Without that option the mount unit carries no dependency on the reopen at all, and every consumer ordering is procedural rather than structural;

(i) **inherit ADR-119 §(e) rather than re-deriving it** — that ADR already ruled on this exact hazard for web-1 (mapper absent at boot ⇒ the target resolves to a root-disk directory ⇒ *"user source code written in plaintext to the root disk"*) and prescribed TWO limbs, of which (h) above is only the first: also `chattr +i` on the unmounted `/mnt/git-data` inode, so an implicit `mkdir`/write into the empty mountpoint returns EPERM instead of silently landing on the root disk. ADR-119 explicitly blesses keeping `nofail` alongside both limbs, which is what this plan does. The `chattr +i` limb was previously deferred only in this plan's Cut List — an artifact that gets archived — rather than in the contract #8211's author actually reads; it is recorded here so it cannot be lost with the archive.

## Technical Approach

### Architecture

```
boot ─► network-online.target ─► git-data-luks-reopen.service (oneshot, Restart=on-failure ×5/h)
              │  ExecStart: doppler run --config "$GIT_DATA_DOPPLER_CONFIG" --only-secrets … --no-fallback -- git-data-luks-reopen.sh
              │     config → key → device(30s) → isLuks==0 → open-if-closed → device identity
              │     → fstab target → systemctl start <target>.mount (PID 1) → findmnt SOURCE
              │     → emit info action=reopened|mounted  |  silent noop
              │     phase file /run/…action + stderr log /run/…log maintained throughout; NO traps
              ├─ final failed state ─► OnFailure= git-data-luks-reopen-failure.service
              │                          ONE fatal: stage=luks_reopen action=<phase|unit> detail=<log|literal>
              ▼
   git-data-gc.service (Wants=/After= reopen) ← weekly retry edge (Persistent=true timer)
```

First boot: `runcmd` `STAGE=luks_open` heredoc (unchanged) → **new** `STAGE=gitdata_luks_reopen_arm` (`enable --now` → noop path proves wiring) → nftables → bootstrap (§1b unchanged; `boot_complete` carries `luks_reopen_unit`).

### Implementation Phases

**Phase 0 — Measure before building** (local, no prod write; results pinned in `## Research Insights` with the date)

- 0.1 Doppler CLI forms against the PINNED tarball (`DOPPLER_VERSION="3.75.3"` in the template; the dev host runs 3.76.5): `--only-secrets` repeated form, `--no-fallback`, `--config` with a `prd_git_data_rehearsal_x` shape (auth may fail — the flag parse is what is measured), exit-code forwarding (`doppler run -- sh -c 'exit 7'; echo $?` → 7). This is the only measurement that can change code, so it runs first (CTO-devex).
- 0.2 `systemd-analyze verify` on the drafted unit pair (documented as allowed — `service.c` rejects only `always|on-success` for oneshot; the verify run pins it on the installed 255), plus the `ProtectSystem=strict` + `ReadWritePaths=/run/cryptsetup` combination as a measurement, not a copy from gc.
- 0.3 Namespace + PID-1 mount, exact shape: `systemd-run --wait -p Type=oneshot -p PrivateTmp=yes /bin/sh -c 'mount -t tmpfs none /mnt/probe-8210; findmnt /mnt/probe-8210'` then `findmnt /mnt/probe-8210` from the host (expected: inside yes, outside no); then, with a loop-device LUKS container and a `nofail` fstab line, `systemd-run -p Type=oneshot -p PrivateTmp=yes … 'systemctl daemon-reload; systemctl start <escaped>.mount'` after `luksOpen` (expected: mounted, visible on the host).
- 0.4 Tool forms: `findmnt --fstab -n -S /dev/mapper/x -o TARGET` (exit 1 on no match — measured by Kieran), `systemd-escape -p --suffix=mount /mnt/git-data-luks`, `cryptsetup status <name>` `device:` line shape, `cryptsetup isLuks` rc table (0/1/4).
- 0.5 Budget baseline: `bash apps/web-platform/infra/git-data-userdata-budget.sh` (15,444 B today).
- 0.7 `/tmp` backing on the pinned image (`docker run --rm ubuntu:24.04@<pinned> findmnt -n -o FSTYPE /tmp` is not representative — a container's `/tmp` is the overlay; read the rehearsal host's `findmnt` from the capture's stage rows if present, else assume disk-backed): decides nothing (the `TMPDIR` on tmpfs is applied either way) but is recorded so the ADR-198 amendment states the fact.
- 0.8 `systemctl show -p ExecMainStatus,ExecMainCode,Result,NRestarts` on a unit driven to `start-limit-hit` under `systemd-run` — pins that the reporter's four tags survive the transition.
- 0.6 One shell line baselining every suite the diff touches: `git-data-luks.test.sh`, `git-data-runcmd-rehearsal.test.sh`, `git-data-render-strip-parity.test.sh`, `git-data-template-strip.test.sh`, `git-data-rung2-rehearsal.test.sh`, `git-data-emit.test.sh`, `doppler-injection-bound.test.sh`, `tests/scripts/test-git-data-rung2-evidence-capture.sh`, `tests/scripts/test-git-data-boot-signal-poll.sh`, `tests/scripts/test-git-data-birth-readiness-gate.sh`, `plugins/soleur/test/terraform-target-parity.test.ts` — GREEN on the unmodified tree, then RED-first per `cq-write-failing-tests-before`. Record the cloud-init `scripts-user` semaphore mechanism (`grep -n _acquire` in cloud-init's `helpers.py` in the pinned image) as the reason a reset after cloud-final cannot replay `runcmd`.

**Phase 1 — Guard suite, script, units, ADR text (RED → GREEN)**

- 1.1 Write `apps/web-platform/infra/git-data-luks-reopen.test.sh` first (Guard 1): static predicates over the script + both units + cloud-init + bootstrap + gc.service, and a runtime arm (test-design P0-1/P1-1/P1-2/P1-5) that: sets `GIT_DATA_REOPEN_RUNDIR=$SCRATCH/run` and `GIT_DATA_REOPEN_DEVICE_WAIT=1`; stubs `cryptsetup`, `findmnt`, `mountpoint`, `systemctl`, `journalctl`, `blockdev`, `realpath`, `git-data-emit` on a scratch `PATH` — NOT `systemd-escape` (present on every systemd host; stubbing it would make Scenario 1 test the stub); runs a POSITIVE stub census before any fixture (`[ "$(command -v "$n")" = "$SCRATCH/$n" ]` for every external command the script names, floor derived from the script); every stub appends `"$(head -n1 "$RUNDIR/action")|$(basename "$0")|$*"` to a per-fixture `calls.log` (reset per fixture, as are the action/log files) so ORDER rows assert the phase tags are monotone in the script's declared order (`grep -oE '^\s*phase [a-z-]+'`, floor ≥ 9) and each command is tagged with its owning phase; drives every phase's failure and the three success actions; and runs a reporter arm that extracts the `sh -c` body from the unit (assert non-empty and containing `action=unit`), rewrites `/usr/local/bin/` → `$SCRATCH/` (assert the count went N → 0), feeds it the action/log files each script fixture left, and asserts the recorder shows `luks_reopen fatal action=<P>` with a detail that does not start with `/`.
- 1.2 Write `git-data-luks-reopen.sh`, `git-data-luks-reopen.service`, `git-data-luks-reopen-failure.service` to the contracts above; `systemd-analyze verify` locally.
- 1.3 Draft the ADR-115 and ADR-198 amendment paragraphs now (the credential decision is settled before payload wiring — advisor Change 1).

**Phase 2 — Payload wiring**

- 2.1 `modules/git-data-userdata/main.tf`: `git_data_luks_reopen`, `git_data_luks_reopen_service`, `git_data_luks_reopen_failure_service` entries (one line each); mirror in `git-data-userdata-budget.sh`; `git-data-render-strip-parity.test.sh` literal 9 → 12; `git-data-runcmd-rehearsal.test.sh` `EXPECTED_PATHS` gains three rows.
- 2.2 `cloud-init-git-data.yml` `write_files`: the script (0755) and both units (0644); the two env lines appended to `/etc/default/git-data-doppler` (verify at RED-first whether A27 / `doppler-injection-bound` / `#7460` pins byte-match that entry's content; if so the pin moves with it).
- 2.3 `cloud-init-git-data.yml` `runcmd`: the `STAGE=gitdata_luks_reopen_arm` item; `git-data-runcmd-rehearsal.test.sh` `_R3B_EXPECTED_SITES` gains `gitdata_luks_reopen_arm`.
- 2.4 `git-data-bootstrap.sh`: the `_reopen_unit` measurement + emit tag (nothing else).
- 2.5 `git-data-gc.service`: `Wants=`/`After=`.
- 2.6 `git-data-luks.test.sh`: `p_doppler_config_scope` gains the two new units in its sibling census and a third accepted scoped shape — the exact literal `--config "$GIT_DATA_DOPPLER_CONFIG"` — with a companion predicate that the cloud-init `write_files` `/etc/default/git-data-doppler` content carries `GIT_DATA_DOPPLER_CONFIG=${doppler_config_name}` (CTO-devex: pin the variable name, not "any `$X`"). A28a's floor rises with `boot_path_files()` automatically. B19d/A1–A7/B16/B17/B18 untouched.
- 2.7 `.github/workflows/infra-validation.yml`: register the new suite; widen the unit-lint list to the three units and its filter to `git-data-(gc|luks-reopen)`.
- 2.8 Budget: re-run; expected delta ≈ 2–3 KB stored against 17,324 B headroom.

**Phase 3 — Off-host routing and the boolean's readers**

- 3.1 `sentry/issue-alerts.tf` + `alert-reference.json` (three stage values; prose count).
- 3.2 The reader sweep (Consumers above): poll lib, capture script, `git-data-emit.test.sh`, apply-workflow prose, `git-data-birth-emitter-6982.sh`, `git-data-birth.md`, both fixtures (each with a RED `luks_reopen_unit":"no"` row).

**Phase 4 — Rehearsal reboot arm and the replace-job gate**

- 4.1 `git-data-rung2-evidence-capture.sh`: `--reboot-since <ts>` mode reusing the anchor and the Sentry cross-check; `HOST_SQL` gains `JSONExtractString(raw,'action')`, `…'restarts'`, `…'luks_reopen_unit'` projections (it projects none today — test-design P0-3) with a static row that every name the verdict greps appears as a projection; `scripts/sentry-issue.sh` gains `--stage <stage>` for `host-events` (observability P1-2). `tests/scripts/test-git-data-rung2-evidence-capture.sh`: teach `make_stub`'s `__HOSTROWS__` branch the same semantic dispatch its `__FATALROWS__` branch has — emit only fixture rows whose `dt` sorts after the SQL's `parseDateTimeBestEffort('X')` bound, and `exit 4` when `--reboot-since` was passed but the clause is absent (test-design P0-2); assert `SENTRY_ARGV_FILE` carries `--stage luks_reopen_ok --start <since> --end`. Fixture rows: F-B (the production shape: `fatal@since−1h`, `boot_complete@since−1h`, `reopened@since+30s`) → 0 (must-PASS); reopened(BS only) → 0; reopened(Sentry only) → 0; fatal(either, post-`since`) → 1; `mounted`/`noop` → 1; F-A (`reopened@since−1h` only) → 2; nothing+live anchor → 2; nothing+dead anchor → 2; append exactly once and only on 0.
- 4.2 Workflow: settle, `reset`, `reboot_probe`, upload gate, `timeout-minutes: 45`, step summaries ("A FAIL here releases nothing" wording).
- 4.3 `git-data-rung2-rehearsal.test.sh`: arms pinning the upload `if:` (both rcs), exact-name resolution (fixture with the prod name and a survivor both refused), `since` before POST (order), `timeout-minutes ≥ 45`, and the probe's `_BS_WHEN` literal equal to the capture's.
- 4.4 `apply-web-platform-infra.yml` `git_data_host_replace`: the rung-2 gate step; `terraform-target-parity.test.ts` case.
- 4.6 `git-data-emit.test.sh`: beside AC30-parity, a consumer-roster arm — `NON_TERMINAL="nft_metadata_drop disk_pct inode_pct"` declared once; `TERMINAL = producer − NON_TERMINAL`; assert the poll's `for f in` list, the capture's FAIL alternation, and both SQL projections' boolean columns each equal `TERMINAL` (projections ⊇ producer). Guard 3 M2/M3 then quantify over `TERMINAL` (test-design P1-4).
- 4.5 Delete `apps/web-platform/infra/git-data-rung2-boot-evidence.env` in this PR (Guard 4's permitted shape; precedent `d579d8b68`/#8052). The freshness check goes inactive; the birth and replace routes HOLD until PM2.

**Phase 5 — Architecture record and runbook**

- 5.1 ADR-115: dated section under the `NORMATIVE BLOCKER` — git-data now has the reboot-safe equivalent; a Doppler-run systemd oneshot IS the accepted equivalent of the "`crypttab` or a keyscript" the blocker named; the self-reboot primitive is still NOT adopted for git-data; the second (replace-on-rotation) blocker is untouched; Alternatives = the Cut List rows for crypttab-keyscript, keyfile, re-run-bootstrap, in-script retry.
- 5.2 ADR-198: dated amendment — the leg-(2) incumbent (the baked read-only token can fetch the passphrase) is accepted BY DESIGN for the boot reopen, on the capability argument (the token is centrally revocable via `-replace=doppler_service_token.git_data` and config-scoped; the passphrase cannot be revoked without re-encrypting), and ONLY with `--only-secrets … --no-fallback` on every `doppler run` the unit pair performs; the #7772 removal intent is superseded; cite Art. 32(1)(c) (availability) for the ledger's #6897 row.
- 5.3 `model.c4`: add `gitDataStore -> doppler "Reads GIT_DATA_LUKS_KEY at every boot (git-data-luks-reopen.service, #8210) and at birth/gc under the baked read-only prd_git_data token; --only-secrets --no-fallback" { technology "HTTPS (Doppler CLI)" }` and one sentence in `gitDataStore`'s description; verify `views.c4` container view includes both ends (elements exist; edges render when both are included); run `c4-code-syntax.test.ts`, `c4-render.test.ts`, `plugins/soleur/test/c4-count-parity.test.sh`.
- 5.4 Runbook `git-data-luks-cutover-5274.md`: a per-`action=` decision table with one row per literal the script's `phase` calls, its `ACTION=` values and the reporter can emit (config, key, device, header, open, identity, target, mount, identity-mount, unit, noop, reopened, mounted) — action → probable cause → off-host check → lever. `unit` → key on `result=`/`rc=`/detail: `doppler configs --project soleur` (config exists) and `doppler activity --project soleur` (token last used), both read-only CLI calls that need no host access; `key` → `doppler secrets --project soleur --config prd_git_data --only-names`; **`open` → restore the previous secret version from Doppler's history and DO NOT replace** (a replace with the wrong passphrase dies at the birth heredoc's `luks_open` and leaves the host dark); **`header` → DO NOT replace** (the birth heredoc formats a blank device — ADR-115 second-blocker / rotation class); `config` → a payload/tfvars defect (the values are template-rendered), lever = payload fix + replace; `device` → `GET /v1/servers/{id}` attached volume ids vs `git_data_luks_volume_id`; `identity` → same check, then replace; `target` → a #8211 fstab defect, fix the payload; `mount|identity-mount` → replace ONLY for a unit/payload defect — a `wrong fs type … bad superblock` detail is filesystem damage whose lever is the ADR-068 backup/rebuild path, named explicitly; `noop|mounted` after a reset → the rehearsal FAIL semantics. State the emitter's 180-char detail cap, "one failure, one event" for the unit path (two only when the emitter itself exits non-zero under a working Doppler), and "three events, one root cause" for the weekly gc tick. No SSH step.

**Phase 6 — Follow-through wiring (so PM closure is not human memory)**

- 6.1 `scripts/followthroughs/git-data-reboot-evidence-landed-8210.sh`: exit 0 when `origin/main`'s `git-data-rung2-boot-evidence.env` carries `RUNG2_REBOOT_REOPEN=PASS` and `git_data_rung2_rehearsal_gate` RELEASEs against `main`'s template; else 1. Its `<!-- soleur:followthrough script=… earliest=<merge+1d> -->` directive and the `follow-through` label go on #8210 at ship (the convention in `knowledge-base/engineering/operations/runbooks/followthrough-convention.md`); `secrets=` none.

## Alternative Approaches Considered

See the Cut List — each row is an alternative with its property and the reason it lost.

## User-Brand Impact

**If this lands broken, the user experiences:** after the first post-cutover reboot, every push/fetch/provision against git-data fails (or, until #8101, a push lands in an empty root-disk directory and vanishes when the store is later mounted) — for every connected user at once, until the routed Sentry fatal is read. If the reopen unit is broken at BIRTH, nothing changes for users today (the store is not live), but the rehearsal must FAIL so the birth and replace gates hold; a rehearsal that passes over a broken reopen is the artifact this plan most needs to prevent.

**If this leaks, the user's data is exposed via:** the passphrase's only new surface is the unit's process environment under `doppler run` for the seconds it runs (same as the runcmd stage and `git-data-gc.service`) — `--no-fallback` keeps Doppler from caching it on disk, `--only-secrets` keeps every other secret out of that env, `PrivateTmp` confines `/tmp`. The reporter emits under the same flags so the redactor sees the key; its Doppler-down fallback ships `cryptsetup` stderr unredacted, which never carries key material. No new credential is minted.

**Brand-survival threshold:** single-user incident — the store will hold every user's source; #8262 on the same queue was raised to this threshold at its plan boundary; this plan sits upstream of the first real cutover.

`requires_cpo_signoff: true`; CPO signed off with conditions at Phase 2.5 (applied). `user-impact-reviewer` runs at review time.

> **Superseded 2026-09-18 (#8210, user-impact seat at review) — the section above is kept as
> written; these corrections are what the review found it did not say.**
>
> 1. **"Nothing changes for users today (the store is not live)" is false for one path.**
>    `GIT_DATA_STORE_ENABLED` gates every WRITE path but not erasure: `removeGitDataRepo`
>    (`apps/web-platform/server/git-data-replication.ts`) is deliberately keyed on
>    `GIT_REMOVE_SSH_PRIVATE_KEY`, not the flag, so it runs on every `Settings → Delete Account`
>    today. With the store closed (a post-reboot host before this fix, or any reopen failure
>    after it) `git-data-remove.sh`'s fail-closed `mountpoint -q` refuses, the throw is caught
>    in `account-delete.ts` and downgraded to a `reportSilentFallback` event, and the auth user
>    is deleted while whatever the store held for them persists. Today the store holds no user
>    repository, so the user-visible cost is a delete that waits up to the 30 s `execFile`
>    timeout plus a spurious Art. 17 erasure-failure event; after the first cutover it is an
>    un-erased repository. Swallowing that refusal is #8094's subject and is NOT closed here.
> 2. **The hold window has a user-visible cost the section did not name.** The rung-2 interlock
>    this plan adds to `git_data_host_replace`, together with the Phase 4.5 evidence deletion,
>    HOLDs both birth and replace from merge until a `main` rehearsal lands fresh evidence. In
>    that window the live host runs the OLD payload with no replace lever, and every
>    Delete Account inside it pays the cost in (1). The bound that ends it is PM1+PM2 (one
>    dispatched rehearsal plus one evidence-only PR); the break-glass for an emergency replace
>    inside it is in `git-data-luks-cutover-5274.md` (dispatch from the last evidence-matching
>    ref).
> 3. **`luks_reopen_unit` is fail-closed with a bounded false-negative window.** The bootstrap
>    waits at most 420 s for the unit to leave `activating`; the unit's own worst case is
>    5 × `TimeoutStartSec=300` + 4 × `RestartSec=60` ≈ 1740 s. A birth whose Doppler is slow
>    for longer than 420 s therefore reads `luks_reopen_unit=no` and FAILs the poll even if
>    the ladder later succeeds. The wait is not raised to 1740 s because that exceeds the birth
>    capture window; the runbook instead says the response to `luks_reopen_unit=no` is a Sentry
>    read (`luks_reopen_ok` / `luks_reopen`) BEFORE any replace, never a replace first.
> 4. **The standing retry is `git-data-luks-reopen.timer` (15 min), not `git-data-gc.timer`.**
>    Every mention below of gc's `Wants=` as the retry (P7, the gc.service row, the
>    Observability `liveness_signal` (2)) describes the first draft; the `Wants=` was cut at
>    review and the dedicated timer replaced it. The timer recovers a FAILED unit only — a
>    mapper closed AFTER a healthy boot under a still-active unit is the residual the
>    failure-modes row "host up, mapper closed later" scope-outs, and it stays open.

## Observability

```yaml
liveness_signal:
  what: >
    (1) Per reboot: a `stage:luks_reopen_ok level:info action:reopened restarts=<n>` row from git-data-emit
    (Sentry + Better Stack git-data source) — an EVENT, not a heartbeat. (2) Standing:
    git-data-gc.timer (weekly, Persistent=true) Wants=/After= the reopen unit, so a failed reopen
    is re-run weekly and gc's own mountpoint FATAL fires if the store is still absent.
  cadence: per reboot; weekly (Sun 03:20 UTC)
  alert_target: Sentry `git-data-boot-fatal` (email issue owners) for level:fatal at stage
    luks_reopen / gitdata_luks_reopen_arm / gc; `git-data-boot-warning` for gitdata_luks_reopen_arm_warn
  configured_in: apps/web-platform/infra/sentry/issue-alerts.tf; apps/web-platform/infra/git-data-gc.service
error_reporting:
  destination: >
    Sentry (baked DSN in git-data-emit — works when Doppler is the broken stage) and Better Stack
    (git-data ingest token via `doppler run` env, baked 0600 fallback).
  fail_loud: >
    yes — the unit reaches its final failed state (after ≤5 bounded restarts) and
    git-data-luks-reopen-failure.service emits exactly one fatal carrying `action=<phase>` from the
    script's phase file and the stderr log as detail; when the script never ran (doppler run, exec,
    start timeout) the reporter emits `action=unit` with a fixed literal. The fstab `nofail` masks
    nothing because the fstab job is not the reporter.
failure_modes:
  - mode: doppler run itself fails (token file absent, config not covered by the token, Doppler unreachable) or exec/start-timeout
    detection: stage:luks_reopen level:fatal action=unit result=<exit-code|timeout|signal|start-limit-hit> rc= code= restarts= with the
      journal's `Doppler Error|Unable to` line as detail (baked-DSN fallback arm; `timeout 90` keeps it reachable on a hang)
    alert_route: git-data-boot-fatal
  - mode: env lines missing (GIT_DATA_LUKS_DEV / GIT_DATA_DOPPLER_CONFIG empty)
    detection: stage:luks_reopen level:fatal action=config
    alert_route: git-data-boot-fatal
  - mode: GIT_DATA_LUKS_KEY not injected (secret deleted/renamed)
    detection: stage:luks_reopen level:fatal action=key
    alert_route: git-data-boot-fatal
  - mode: volume not attached / device absent after 30 s
    detection: stage:luks_reopen level:fatal action=device
    alert_route: git-data-boot-fatal
  - mode: device present but not crypto_LUKS (wrong volume, damaged header) — the unit never formats
    detection: stage:luks_reopen level:fatal action=header (isLuks rc in detail)
    alert_route: git-data-boot-fatal
  - mode: luksOpen fails (wrong passphrase after a mis-rotation — ADR-115 second blocker)
    detection: stage:luks_reopen level:fatal action=open
    alert_route: git-data-boot-fatal
  - mode: mapper backed by a device other than the pin (stale pin after a volume swap)
    detection: stage:luks_reopen level:fatal action=identity
    alert_route: git-data-boot-fatal
  - mode: fstab has zero or >1 entries for the mapper (a bad #8211 cutover)
    detection: stage:luks_reopen level:fatal action=target
    alert_route: git-data-boot-fatal
  - mode: mount unit start fails / mounted from the wrong source
    detection: stage:luks_reopen level:fatal action=mount | action=identity-mount (journalctl tail in detail)
    alert_route: git-data-boot-fatal
  - mode: unit not enabled at birth (`enable --now` failed)
    detection: stage:gitdata_luks_reopen_arm_warn level:warning + boot_complete luks_reopen_unit=no
      (TERMINAL: FAILs the rehearsal capture and the birth/replace boot-signal poll)
    alert_route: git-data-boot-warning; capture verdict 1; poll verdict 1
  - mode: transient Doppler/DNS blip resolved within the restart budget
    detection: the success row's `restarts=<n>` tag (n > 0); the rehearsal records it as
      RUNG2_REBOOT_REOPEN_RESTARTS. No page by design. Note: at birth the boolean reads Result at the
      instant after `enable --now`, so a unit mid-Restart reports luks_reopen_unit=no (fail-closed) even
      though the host is healthy a minute later — accepted.
    alert_route: none (by design)
  - mode: host never comes up (network-online never reached) — DARK
    detection: web-side `web-git-data-probe.timer` (60 s TCP connect from the web host → git_data_prd
      heartbeat, 180 s grace) — gc is After=network-online too, so it is NOT the bound here
    alert_route: git_data_prd heartbeat (Better Stack)
  - mode: host up, mapper closed later (post-boot luksClose/detach) or reopen wedged after network-online
    detection: no row; bounded by the weekly gc FATAL and, post-#8211, by #8101's per-call assert. Residual window.
    alert_route: git-data-boot-fatal (via gc), 7-day bound
logs:
  where: >
    Host journald is NOT shipped (no Vector on git-data; ADR-149). /run/git-data-luks-reopen.log rides
    the fatal's `detail` (redacted, capped at 180 chars by the emitter); Better Stack git-data source;
    Sentry event tags (`action=`, `unit=`, `rc=`).
  retention: Better Stack source retention (#7772); Sentry 90 d default
discoverability_test:
  command: bash scripts/sentry-issue.sh --host-events soleur-git-data --stage luks_reopen_ok --start 2026-09-18T00:00:00 --end 2026-09-19T00:00:00
  expected_output: >
    JSON rows for the host projected with `action`; after a reboot exactly one row with
    stage=luks_reopen_ok action=reopened, and the default (fatal) read returns zero rows. Before any
    reboot: zero luks_reopen_ok rows. (The `--stage` option is added by Phase 4.1 — the shipped
    `host-events` hard-codes level:fatal.)
  credentials_required: >
    SENTRY_ISSUE_RO_TOKEN (Doppler prd_terraform) — the reopen signal exists only as an off-host row
    on a deny-all-public host with no shipped journal; no unauthenticated probe can observe the mapper.
```

Affected-surface note (Phase 2.9.2): the git-data host is a blind surface. The in-surface probe is `git-data-emit` from the reporter unit; the `action=` tag (config / key / device / header / open / identity / target / mount / identity-mount / unit) plus `result=`/`rc=`/`code=`/`restarts=` discriminate every hypothesis in one event, and the runbook's decision table keys on them.

## Encryption Posture

```yaml
at_rest:
  - store: hcloud_volume.git_data_luks (soleur-git-data-luks-store) — the reopen target
    mechanism: guest-side LUKS2 (cryptsetup luksFormat at first boot; unchanged by this plan)
    evidence: cloud-init-git-data.yml STAGE=luks_open heredoc; git-data-luks.test.sh A1–A7, B16, B17
    defends_against: a seized/snapshotted/re-attached block volume read without the passphrase
    does_not_defend: a compromised RUNNING host (mapper open; the read-only token can fetch the key);
      hypervisor memory access
    disclosed_as: encryption-posture ledger exception (#6897) — "pending cutover"; the privacy policy's
      at-rest claim becomes live only at #8211
    live_verification: findmnt SOURCE == /dev/mapper/git-data AND cryptsetup status device == pin,
      asserted by git-data-luks-reopen.sh on every boot; boot_complete luks_mounted + luks_reopen_unit;
      rung-2 reboot arm action=reopened
  - store: the root disk of soleur-git-data (holds /etc/default/git-data-doppler, the units, the script)
    mechanism: plaintext (Hetzner root disk, unchanged)
    evidence: this plan writes NO secret to it — the two env lines carry a device path and a config
      name; `--no-fallback` prevents Doppler's encrypted cache of the resolved secret set
    defends_against: n/a — it is why the passphrase is fetched at boot instead of stored
    does_not_defend: theft of the read-only service token from a root-disk snapshot, which yields the
      passphrase from Doppler — the ADR-198 leg-(2) incumbent, accepted by design in the ADR-198
      amendment (revocable via -replace=doppler_service_token.git_data)
    disclosed_as: ADR-198 + its amendment
    live_verification: git-data-luks-reopen.test.sh static rows (no key assignment in the env-file
      content; `--no-fallback` present on both units)
in_transit:
  - connection: git-data host → api.doppler.com (doppler run, every boot + on failure report)
    tls: yes
    cert_verification: on
    does_not_defend: a compromised host; Doppler-side compromise
    disclosed_as: existing (identical to the runcmd stage and the gc unit pair)
  - connection: git-data host → sentry.io / Better Stack ingest (git-data-emit)
    tls: yes
    cert_verification: on
    does_not_defend: telemetry-sink compromise (write-only token; ADR-198 capability ceiling)
    disclosed_as: existing
  - connection: GitHub Actions runner → api.hetzner.cloud (rehearsal reset)
    tls: yes
    cert_verification: on
    does_not_defend: HCLOUD_TOKEN leak from the runner (masked as the teardown step does)
    disclosed_as: existing
```

No `exception` block.

## Guard Contract

### Guard 1 — `git-data-luks-reopen.test.sh` (static + runtime)

**Property.** On every boot of the git-data host, the LUKS mapper is opened from a Doppler-delivered key (never from disk, never cached), backed by the pinned device, and mounted at the fstab-named target with the mapper as its source; the path can never format; every failure — including a failure of `doppler run`, exec, or start-timeout — is reported exactly once at `fatal` with the failing phase named.

**Assembly.** The chokepoints: (1) `git-data-luks-reopen.sh` (phase file written before every phase; no `mkfs`/`luksFormat`; no `mount(8)`; no traps); (2) `git-data-luks-reopen.service` (`OnFailure=`, `Restart=on-failure` bounded, `--only-secrets … --no-fallback`, templated `--config`, `EnvironmentFile=-/etc/default/git-data-doppler`, `HOME`, `PrivateTmp`, `WantedBy`); (3) `git-data-luks-reopen-failure.service` (reads the phase file, literal fallback, doppler-or-direct arm); (4) the `runcmd` arm item (present, after `LUKSEOF`, before `STAGE=bootstrap`, distinct detail var); (5) the env lines in `/etc/default/git-data-doppler`; (6) `git-data-gc.service` `Wants=/After=`; (7) the module map + budget mirror + write_files paths + `EXPECTED_PATHS` (agree by construction — the existing parity suites quantify over the map). The runtime arm quantifies over the script's actual phase list (`grep -oE '^phase [a-z-]+' git-data-luks-reopen.sh`), so a new phase without a failure fixture REDs.

**Mutation matrix** (each MUST drive the guard RED):

| # | Edit | Expected |
|---|---|---|
| M1 | Delete the `systemctl enable --now git-data-luks-reopen.service` line from `runcmd` | RED (written but never armed — inngest T1.1 class) |
| M2 | `EnvironmentFile=-/etc/default/git-data-doppler` → `Environment=X=1` in the unit | RED (no token, no config, no pin) |
| M3 | Remove `Environment=HOME=/root` | RED |
| M4 | Add `mkfs.ext4 -q /dev/mapper/git-data` (or `luksFormat`) to the script | RED (never formats; B16a count moves too) |
| M5 | Replace the `findmnt -n -o SOURCE` check with `mountpoint -q` only | RED (mountedness is not identity) |
| M6 | Add `GIT_DATA_LUKS_KEY=…` to the `/etc/default/git-data-doppler` write_files content | RED (secret on disk) |
| M7 | Move the `runcmd` arm item below `STAGE=bootstrap` | RED (boot_complete would measure an unarmed unit) |
| M8 | Drop `--no-fallback` (or an `--only-secrets`) from EITHER unit's `doppler run` | RED |
| M9 | Hardcode `--config prd_git_data` in a unit instead of `"$GIT_DATA_DOPPLER_CONFIG"` | RED (rehearsal token cannot read it) |
| M10 | Replace `systemctl start <mount>` with a direct `mount "$MAPPER" "$TARGET"` | RED (namespace-confined) |
| M11 | Reorder: `open` before `header` (or `mount` before `identity`) | RED (runtime arm records call order — an ORDER row) |
| M12 | Remove `Wants=git-data-luks-reopen.service` from `git-data-gc.service` | RED |
| M13 | Remove `OnFailure=` from the unit | RED (failures become dark) |
| M14 | Reporter emits without the literal fallback when the log is absent | RED (runtime: doppler stub exit 1 with no log → recorded detail must not be a path) |
| M15 | Script writes the phase file AFTER the phase instead of before | RED (runtime: kill the stubbed `cryptsetup luksOpen` mid-phase → action file must read `open`) |
| M16 | Drop the `cryptsetup status` device-realpath check | RED (runtime: stub reports a different device on the noop path → must exit 1 with action=identity) |
| M17 | Add `trap … EXIT` with an emit inside the script | RED (static: the script must not emit fatal; the reporter is the single emitter) |
| M18 | Either unit sets `Environment=GIT_DATA_REOPEN_RUNDIR=` or `…DEVICE_WAIT=` | RED (test seams must be unset in production) |
| M19 | Remove `RuntimeDirectoryPreserve=yes` while `RuntimeDirectory=` stays | RED (systemd removes the dir before `OnFailure=` runs — the reporter would read nothing) |
| M20 | Remove `ExecStartPre=/bin/rm -f …` | RED (runtime: pre-seeded stale action file + doppler stub exit 1 → recorded action must be `unit`, not the stale phase) |
| M21 | Remove `timeout 90` from the reporter's `doppler run` | RED (runtime: doppler stub that sleeps → the direct arm must still emit within the unit timeout) |
| M22 | The success emit's stage becomes a value present in `git_data_boot_fatal`'s `eq` list | RED (static: the script's only `info` stage must be absent from `issue-alerts.tf`'s fatal list) |
| M23 | Drop a `validation {}` block from the module variables, or the shape assert from `phase config` | RED |
| M24 | Add `--no-exit-on-missing-only-secrets` to either unit, or `set -x`/`--debug` to the script | RED (fail-open bound / key sink) |

**Harness rows.** H1 (positive census): before any fixture, `command -v <n>` resolves to `$SCRATCH/<n>` for every external command the script names (floor derived from the script); removing one stub → RED before any phase runs, never `127` at `phase header`. H2: make the argv recorder write nothing — RED on the "recorder captured the expected emit" floor for the success cases and on "phase file present" for the failure cases. H3 (must-PASS non-canonical): a script whose comment lines differ; a unit with `TimeoutStartSec=600`; `--only-secrets` in comma form — all PASS. H4: the suite exits non-zero on `0 passed, 0 failed`. H5 (ORDER recorder): the phase-tagged `calls.log` is reset per fixture and its tags are compared against the script's declared phase list with a `≥ 9` floor, so a phase file written AFTER a phase makes `cryptsetup isLuks` carry tag `device` deterministically (M11/M15 need no signal).

**Anchor.** The unit-pair predicates are anchored on the module map's `file()` roster (the `boot_path_files()` derivation), so a unit added to the payload later is enrolled automatically, and the parity suites already RED on a map/budget/`EXPECTED_PATHS` disagreement.

### Guard 2 — the rung-2 reboot arm (`git-data-rung2-rehearsal.yml` + the capture script's `--reboot-since` mode)

**Property.** Evidence that can release the birth gate is uploaded only from a rehearsal whose host was hard-reset through the Hetzner API after `boot_complete` settled and then reported `stage:luks_reopen action:reopened` (either channel) with no fatal (either channel) after the reset timestamp.

**Assembly.** The `reset` step (exact-name resolution, `since` before POST, action polled), the settle sleep, the `reboot_probe` step, the upload step's `if:` (both rcs), the capture script's `--reboot-since` verdict table and evidence append. `git-data-rung2-rehearsal.test.sh` pins the wiring; `test-git-data-rung2-evidence-capture.sh` pins the verdicts.

**Mutation matrix** (each MUST drive the guard RED):

| # | Edit | Expected |
|---|---|---|
| M1 | Drop `steps.reboot_probe.outputs.reboot_rc == '0'` from the upload `if:` | RED |
| M2 | Probe treats `action:noop` or `action:mounted` as PASS | RED (fixture rows must exit 1) |
| M3 | Probe drops the `since` clause from `_BS_WHEN` or `--start` from the Sentry read | RED (fixture F-A's stale `reopened@since−1h` reaches the script through the semantic stub and the arm expecting 2 sees 0; the Sentry argv recorder lacks `--start <since>`) |
| M4 | Reset step resolves by `startswith(prefix)` instead of exact `== "${REHEARSAL_PREFIX}${GITHUB_RUN_ID}"` | RED (fixture with the prod name AND a survivor must both be refused) |
| M5 | Record `since` AFTER the reset POST (reorder) | RED |
| M6 | Probe reads Better Stack only (drop the Sentry channel) | RED (fixture: BS empty + Sentry `reopened` must exit 0) |
| M7 | Probe's own dispatch: query helper returns empty for every query | RED (dispatch floor: ≥ 1 verdict per fixture arm) |

**Harness rows.** H1: a fixture with a post-`since` fatal AND a reopened row → exit 1 (fatal wins). H2 (must-PASS non-canonical): F-B, the production shape with pre-`since` fatal and `boot_complete` rows plus `reopened@since+30s` → 0; and a `reopened` row whose `target` is `/mnt/git-data` → 0. H3: `RUNG2_REBOOT_REOPEN=PASS` appended exactly once and only on exit 0. H4: `timeout-minutes` below the SUM of the workflow's comment-stated bounded polls (apply 25 + capture 10 + settle 2 + reset 2 + probe 10) → RED (derived, not a literal). H5: `make_stub` without the `dt >` semantic dispatch → the F-A/F-B pair cannot be distinguished → RED.

**Anchor.** The evidence file is uploaded by the workflow and committed only by an evidence-only PR after a `main` run (Guard 4 + environment policy), and the birth gate reads `RUNG2_EVIDENCE_URL` as an Actions run URL — so the reboot verdict is anchored to a run log outside any commit that touches the payload. Requiring the key in the gate is #8010.

### Guard 3 — the fifth `boot_complete` boolean

**Property.** A birth or replace whose reopen unit is not enabled-and-succeeded cannot produce a PASS from the rung-2 capture or the boot-signal poll.

**Assembly.** `git-data-bootstrap.sh` (measures and emits), the poll's `for f in` loop + SQL, the capture's FAIL regex + SQL, and `git-data-emit.test.sh`'s AC30-parity roster plus the new consumer-roster arm — one vocabulary (`yes|no`); the TERMINAL set is DERIVED (`producer − NON_TERMINAL`, with `NON_TERMINAL="nft_metadata_drop disk_pct inode_pct"` declared once), never enumerated as five names, and both consumers' lists and both SQL projections are asserted equal to it.

**Mutation matrix** (each MUST drive the guard RED):

| # | Edit | Expected |
|---|---|---|
| M1 | Bootstrap hardcodes `luks_reopen_unit=yes` | RED (static: the value is a `${_var}` expansion whose assignment is conditioned on a `systemctl` query — never a literal; Phase 0.2 fixes which query) |
| M2 | Drop `luks_reopen_unit` from the capture's FAIL regex | RED (fixture `"luks_reopen_unit":"no"` must exit 1) |
| M3 | Drop it from the poll's `for f in` list | RED (same fixture in the poll test) |
| M4 | Emit `boot_complete` BEFORE the `_reopen_unit` measurement (reorder) | RED |
| M5 | Add the tag to bootstrap's emit but not to `_asserted_keys` | RED (AC30-parity in `git-data-emit.test.sh`, existing) |
| M6 | Add `luks_reopen_unit` to the capture's FAIL regex but not to `HOST_SQL` (or to the poll's loop but not its projection) | RED (consumer-roster arm: projections ⊇ producer; a fixture cannot see a dropped projection, the parity arm can) |

**Harness rows.** H1: all five `yes` plus an unknown extra tag → PASS. H2: a fixture row lacking the field → the fixture helper fails its own run (schema floor).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1 `apps/web-platform/infra/git-data-luks-reopen.sh`, `git-data-luks-reopen.service`, `git-data-luks-reopen-failure.service`, `git-data-luks-reopen.test.sh` exist; the suite exits 0, exits non-zero on `0 passed, 0 failed`, and its self-mutation battery covers every Guard 1 row.
- [ ] AC2 `grep -cE '^\s*(mkfs|cryptsetup luksFormat)' apps/web-platform/infra/git-data-luks-reopen.sh` = 0; `grep -cE '^\s*trap ' …reopen.sh` = 0; `grep -c 'cryptsetup luksOpen' apps/web-platform/infra/git-data-bootstrap.sh` unchanged from `origin/main` (§1b untouched); `grep -c 'mkfs.ext4' apps/web-platform/infra/cloud-init-git-data.yml` unchanged (B16a).
- [ ] AC3 Both units carry `--only-secrets GIT_DATA_LUKS_KEY --only-secrets BETTERSTACK_LOGS_TOKEN --no-fallback`, the literal `--config "$GIT_DATA_DOPPLER_CONFIG"`, a `TMPDIR=` under a tmpfs path, `UMask=0077`, and neither carries `--no-exit-on-missing-only-secrets` or a `GIT_DATA_REOPEN_*` seam; the unit carries `RuntimeDirectory=git-data-luks-reopen` + `RuntimeDirectoryPreserve=yes` + `ExecStartPre=/bin/rm -f …` + `NoNewPrivileges=yes`; the reporter's `doppler run` is prefixed `timeout 90`; `grep -c prd_git_data apps/web-platform/infra/git-data-luks-reopen*.service` = 0; `bash apps/web-platform/infra/doppler-injection-bound.test.sh` exits 0 with no new `ACK_REASONS` entry.
- [ ] AC4 `systemd-analyze verify` over the three units and `git-data-gc.service` prints no line matching `git-data-(gc|luks-reopen)[^:]*\.service:`; the same list and filter appear in `infra-validation.yml`'s unit-lint step; the Phase 0.2 verdict on `Restart=` + `RemainAfterExit=` is recorded in Research Insights and the shipped unit matches it.
- [ ] AC5 `cloud-init-git-data.yml`: `write_files` carries the script (0755) and both units (0644); the `/etc/default/git-data-doppler` entry's content carries `GIT_DATA_LUKS_DEV=/dev/disk/by-id/scsi-0HC_Volume_${git_data_luks_volume_id}` and `GIT_DATA_DOPPLER_CONFIG=${doppler_config_name}` and no other new line; `runcmd` carries exactly one `systemctl enable --now git-data-luks-reopen.service` whose line number is greater than the heredoc's closing `^    LUKSEOF$` line and less than the `STAGE=bootstrap` line; its detail variable is distinct from every other item's (R3(3b)(iii)).
- [ ] AC6 `modules/git-data-userdata/main.tf` and `git-data-userdata-budget.sh` carry the three new map entries; `git-data-render-strip-parity.test.sh` (literal 12), `git-data-template-strip.test.sh`, `git-data-runcmd-rehearsal.test.sh` (three `EXPECTED_PATHS` rows; `gitdata_luks_reopen_arm` in `_R3B_EXPECTED_SITES`), `git-data-userdata-budget.sh` all exit 0; budget `stored=` ≤ 20,000 B, before/after recorded in Research Insights.
- [ ] AC7 `bash apps/web-platform/infra/git-data-luks.test.sh` exits 0 with `p_doppler_config_scope` enumerating both new units, accepting the exact `--config "$GIT_DATA_DOPPLER_CONFIG"` shape, and its companion predicate holding on the env-file content; `bash apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh` exits 0 (docker arm on the dev host; under `CI=true` without docker it reports SKIP, not PASS).
- [ ] AC8 `git-data-gc.service` `[Unit]` carries `Wants=git-data-luks-reopen.service` and `After=git-data-luks-reopen.service`.
- [ ] AC9 `sentry/issue-alerts.tf`: `git_data_boot_fatal` carries `eq` filters for `luks_reopen` AND `gitdata_luks_reopen_arm` and NOT for `luks_reopen_ok` (`grep -c luks_reopen_ok apps/web-platform/infra/sentry/issue-alerts.tf` counts only the deliberately-absent comment); `git_data_boot_warning`'s `in` value contains `gitdata_luks_reopen_arm_warn`; the script's only `info` emit uses stage `luks_reopen_ok`; `bash scripts/sentry-alert-reference-gate.sh` exits 0; `cd apps/web-platform/infra/sentry && terraform validate` exits 0.
- [ ] AC10 `git-data-bootstrap.sh` emits `"luks_reopen_unit=${_reopen_unit}"` whose assignment is conditioned on a `systemctl` query (never a literal); `git-data-emit.test.sh` carries the consumer-roster arm (`TERMINAL = producer − NON_TERMINAL`) and it is green; the boolean is in the poll's loop, the capture's FAIL regex, both SQL projections, `git-data-emit.test.sh`'s `_asserted_keys`, `git-data-birth-emitter-6982.sh`'s SQL, `git-data-birth.md`, and the apply-workflow's disclosure/readiness prose; `bash tests/scripts/test-git-data-rung2-evidence-capture.sh`, `bash tests/scripts/test-git-data-boot-signal-poll.sh`, `bash apps/web-platform/infra/git-data-emit.test.sh` exit 0, the first two each with a RED `luks_reopen_unit":"no"` fixture.
- [ ] AC11 `git-data-rung2-evidence-capture.sh --reboot-since` mode exists with `action`/`restarts`/`luks_reopen_unit` projected in `HOST_SQL`; `scripts/sentry-issue.sh --host-events` accepts `--stage`; `test-git-data-rung2-evidence-capture.sh` covers the Guard 2 verdict table including F-B (must-PASS), the Sentry-only PASS and F-A (TRANSIENT) through a `make_stub` that dispatches on the `dt >` clause; no new script or suite is registered.
- [ ] AC12 `git-data-rung2-rehearsal.yml` has steps `id: reset` and `id: reboot_probe`, a 120 s settle before the reset, exact-name resolution, `RUNG2_REBOOT_SINCE` recorded on a line preceding the `curl … -X POST`, `actions/reset`, the upload `if:` gated on both rcs, `timeout-minutes: 45`; `actionlint` exits 0; `bash apps/web-platform/infra/git-data-rung2-rehearsal.test.sh` exits 0 including the new arms.
- [ ] AC13 `apply-web-platform-infra.yml` `git_data_host_replace` invokes `git_data_rung2_rehearsal_gate` before its plan step; `cd apps/web-platform && ./node_modules/.bin/vitest run` on `plugins/soleur/test/terraform-target-parity.test.ts` (or its registered runner — verify at /work) exits 0 with the replace-job case.
- [ ] AC14 `apps/web-platform/infra/git-data-rung2-boot-evidence.env` is DELETED in this PR (`git show --stat` lists it as deleted; no bound file and the evidence are MODIFIED together — Guard 4); `bash tests/scripts/test-git-data-birth-readiness-gate.sh` exits 0 and the `Rung-2 evidence freshness` step is inactive on the PR.
- [ ] AC15 ADR-115 carries a dated amendment section under its normative blocker naming `git-data-luks-reopen.service`, the reboot arm, and the still-not-adopted self-reboot primitive; ADR-198 carries a dated amendment accepting the leg-(2) incumbent by design under `--only-secrets --no-fallback` and superseding the #7772 removal intent; `model.c4` carries `gitDataStore -> doppler`; `c4-code-syntax.test.ts`, `c4-render.test.ts`, `plugins/soleur/test/c4-count-parity.test.sh` green.
- [ ] AC16 The runbook section exists with one row per action the script and reporter can emit — the set derived as `grep -oE '^\s*phase [a-z-]+' <script> | awk '{print $2}'` ∪ `grep -oE 'ACTION=[a-z]+' <script> | cut -d= -f2` ∪ `grep -oE 'action=[a-z-]+' <reporter> | cut -d= -f2`, equal to the table's first column — with "do not replace" on both `header` and `open`; `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` exits 0.
- [ ] AC17 `scripts/followthroughs/git-data-reboot-evidence-landed-8210.sh` exists and exits 1 against the current `main` (no reboot key yet); the PR body carries `Ref #8210` (never `Closes` — the fix reaches no live host until PM4), `Ref #8010`, `Ref #8211`, and the Phase 0 verdicts.
- [ ] AC18 `apps/web-platform/infra/modules/git-data-userdata/variables.tf` carries `validation {}` blocks on `doppler_config_name` and `git_data_luks_volume_id`; `cd apps/web-platform/infra && terraform validate` exits 0; the rehearsal root (`rung2-rehearsal/`) still validates.

### Post-merge (all `gh`-driven; the environment approval is the one human gate, by ADR-149 design)

- [ ] PM1 Dispatch the rehearsal from `main`: `gh workflow run git-data-rung2-rehearsal.yml --ref main -f confirm=REHEARSE-GIT-DATA -f dry_run=true`, then `-f dry_run=false` in the merging session. The `web-platform-infra-apply` environment approval is granted via `gh api -X POST repos/jikig-ai/soleur/actions/runs/<run-id>/pending_deployments -f 'environment_ids[]=<id>' -f state=approved -f comment=…` — a `gh` route, not a dashboard step. Cap two dispatches per fix attempt. Cadence note (CTO-devex): if #8101/#8211 are about to merge, one rehearsal + one replace after the LAST payload PR is enough — a held gate in between is the safe state.
- [ ] PM2 On PASS, download `git-data-rung2-boot-evidence`, commit `apps/web-platform/infra/git-data-rung2-boot-evidence.env` ALONE in an evidence-only PR (touches no bound file — Guard 4), merge; `bash tests/scripts/test-git-data-birth-readiness-gate.sh` and the follow-through script from AC17 both exit 0.
- [ ] PM3 The follow-through directive on #8210 (`script=scripts/followthroughs/git-data-reboot-evidence-landed-8210.sh`, `earliest=<merge+1d>`, label `follow-through`) lets the daily sweeper close the issue once PM2 lands — no human-remembered `gh issue close`.
- [ ] PM4 Deliver the payload to the live host: `gh workflow run apply-web-platform-infra.yml -f apply_target=git-data-host-replace -f confirm=<token in the job header>` after PM2 (the replace job now holds on the rung-2 gate until then). Both volumes and the passphrase are preserved by omission (ADR-103). Record it as a prerequisite comment on #8211 with contract clauses (a)–(h).
- [ ] PM5 File the follow-on issue for `--only-secrets … --no-fallback` on the two `doppler run` sites this plan does not touch (`STAGE=luks_open` heredoc, `STAGE=bootstrap`) and `--retry 2` on the emitter's Better Stack POST, label `type/security`, `Ref #8210`.

## Files to Create

- `apps/web-platform/infra/git-data-luks-reopen.sh`
- `apps/web-platform/infra/git-data-luks-reopen.service`
- `apps/web-platform/infra/git-data-luks-reopen-failure.service`
- `apps/web-platform/infra/git-data-luks-reopen.test.sh`
- `scripts/followthroughs/git-data-reboot-evidence-landed-8210.sh`

## Files to Edit

- `apps/web-platform/infra/cloud-init-git-data.yml` — three `write_files` entries; two env lines; one `runcmd` arm item
- `apps/web-platform/infra/git-data-bootstrap.sh` — `_reopen_unit` measurement + emit tag only
- `apps/web-platform/infra/git-data-gc.service` — `Wants=`/`After=`
- `apps/web-platform/infra/modules/git-data-userdata/main.tf`, `apps/web-platform/infra/git-data-userdata-budget.sh` — three map entries each
- `apps/web-platform/infra/git-data-render-strip-parity.test.sh` — entry literal 9 → 12
- `apps/web-platform/infra/git-data-runcmd-rehearsal.test.sh` — `EXPECTED_PATHS` ×3, `_R3B_EXPECTED_SITES`
- `apps/web-platform/infra/git-data-luks.test.sh` — `p_doppler_config_scope` census + third shape + env predicate
- `apps/web-platform/infra/git-data-emit.test.sh` — AC30-parity roster
- `apps/web-platform/infra/git-data-rung2-rehearsal.test.sh` — new arms
- `apps/web-platform/infra/sentry/issue-alerts.tf`, `apps/web-platform/infra/sentry/alert-reference.json`
- `scripts/followthroughs/git-data-rung2-evidence-capture.sh`, `tests/scripts/test-git-data-rung2-evidence-capture.sh` — fifth boolean + `--reboot-since` mode + fixtures
- `scripts/lib/git-data-boot-signal-poll.sh`, `tests/scripts/test-git-data-boot-signal-poll.sh` — fifth boolean
- `scripts/sentry-issue.sh` — `--stage` option for `host-events`
- `apps/web-platform/infra/modules/git-data-userdata/variables.tf` — two `validation {}` blocks
- `scripts/followthroughs/git-data-birth-emitter-6982.sh` — SQL projection
- `.github/workflows/git-data-rung2-rehearsal.yml` — settle, reset, probe, upload gate, timeout
- `.github/workflows/apply-web-platform-infra.yml` — replace-job rung-2 gate step; disclosure/readiness prose
- `plugins/soleur/test/terraform-target-parity.test.ts` — replace-job gate case
- `.github/workflows/infra-validation.yml` — register the new suite; unit-lint list + filter
- `knowledge-base/engineering/architecture/decisions/ADR-115-dedicated-host-private-nic-boot-convergence.md`, `knowledge-base/engineering/architecture/decisions/ADR-198-baking-the-better-stack-ingest-token-into-git-data-user-data.md` — dated amendments
- `knowledge-base/engineering/architecture/diagrams/model.c4` — edge + description sentence
- `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md`, `knowledge-base/engineering/operations/runbooks/git-data-birth.md`

## Files to Delete

- `apps/web-platform/infra/git-data-rung2-boot-evidence.env` (re-landed alone by PM2)

## Open Code-Review Overlap

Queried `gh issue list --label code-review --state open --json number,title,body --limit 200` (65 open) against every path above with standalone `jq --arg path`. Two matches: #7098 (`set -e` audit; names `git-data-rung2-rehearsal.test.sh`) — **Acknowledge**, the new workflow steps use the existing `set -euo pipefail`/`set -uo pipefail` shapes; #7942 (`*.mutation.sh` batteries in no gate; names `infra-validation.yml`, `scripts/test-all.sh`) — **Acknowledge**, the new suite is `*.test.sh` and registered. No open scope-out touches the reopen path; #8101/#8010/#8094/#8211 carry no `code-review` label and are the declared out-of-scope set.

## Test Scenarios

- Closed mapper, target unmounted → `luksOpen` once with `--key-file -` and the pinned device; `systemctl start mnt-git\x2ddata\x2dluks.mount`; identity stubs agree → emit `info action=reopened target=/mnt/git-data-luks`; action file reads `identity-mount` at exit; exit 0.
- Open + mounted (birth noop) → no `luksOpen`, no `systemctl start`, no emit; exit 0.
- Open, target unmounted (post-failed-mount retry) → `systemctl start` only → emit `action=mounted`.
- Each of config / key / device / header / open / identity / target / mount / identity-mount failing → exit 1 with the action file naming THAT phase; `luksFormat` count 0 in every case; `calls.log` carries no tag later than the failing phase.
- Composition: for each phase-P failure fixture, the reporter arm is fed the action/log files the script left → the recorder shows `luks_reopen fatal action=P result= rc= code= restarts=` with the log as detail (not a path).
- Reporter with no action/log files (doppler-run failure) → one emit `action=unit` with the journal grep or the literal as detail, never a path; doppler stub exit 1 → the direct arm fires; doppler stub that sleeps → the direct arm fires within the timeout.
- Stale action file pre-seeded + `ExecStartPre` run → the action file is gone before the script starts (M20).
- Post-cutover shape (fstab target `/mnt/git-data`) → mount unit `mnt-git\x2ddata.mount`, `target=/mnt/git-data` (must-PASS non-canonical).
- Capture `--reboot-since`: verdict table per Guard 2; Sentry-only PASS; `mounted`/`noop` FAIL; pre-`since` TRANSIENT; append exactly once.
- Capture/poll/emit-parity: `luks_reopen_unit:"no"` → FAIL; five `yes` → PASS; roster mismatch → AC30-parity RED.
- (PM1, not a runner test) rung-2 from `main`: boot → capture PASS → settle → reset → `luks_reopen_ok action=reopened` within 10 min → evidence carries both keys → teardown survivor check clean.

## Dependencies & Risks

| Risk | Mitigation |
|---|---|
| Mount inside a `PrivateTmp` unit is namespace-confined (silent "success") | The script never mounts; PID 1 mounts via the fstab unit; Phase 0.3 measures the exact shape; M10. |
| systemd 255 refuses `Restart=` with `RemainAfterExit=yes` on a oneshot | Phase 0.2 decides; the boolean reads `Result=success` either way. |
| `doppler run` caches the resolved passphrase under `$DOPPLER_CONFIG_DIR` on the root disk (CTO P1) | `--no-fallback` + `--only-secrets` on both units (M8); `PrivateTmp` confines `/tmp/.doppler`; the two untouched `doppler run` sites are PM5. |
| The rehearsal token cannot read `prd_git_data` (scratch config per run) — a hardcoded config makes the reboot arm unpassable (terraform-architect BLOCKING) | Config name templated into the env file; M9; AC3. |
| Transient Doppler/DNS blip at reboot leaves the store absent | Bounded `Restart=on-failure` (5/h) then ONE fatal; gc `Wants=` weekly retry; no in-script loop. |
| Start-timeout / SIGTERM kills the script with no trap | The reporter is systemd's `OnFailure=`, not a bash trap; the phase file already names the phase (M15). |
| Hard reset before cloud-final's semaphore replays `runcmd` and `boot_complete` on the next boot | 120 s settle after capture PASS; the probe FAILs on `noop`. |
| Better Stack ingest miss on the reopen row burns a paid host | The probe reads Sentry too (M6); PM5 adds `--retry 2` to the emitter. |
| The replace route — the only remediation lever — is held from merge to PM2 (CPO finding 2; now real because the replace job gains the gate) | Intended: an un-rehearsed template must not reach the live host; the store is not user-enabled; PM1 runs in the merging session. |
| Post-cutover replace recreates the pre-cutover fstab (spec-flow (f)) | #8211 contract clause (f); the reopen's `target` phase and the device-identity phase make the mismatch loud at the next boot. |
| Adding a `runcmd` item shifts `git-data-runcmd-rehearsal.test.sh` pins (R3 ordering, emit-window census) | Copies the nftables shape with distinct names; `_R3B_EXPECTED_SITES` extended; RED-first. |
| The env-file `write_files` content is byte-pinned somewhere (A27 / #7460 / injection-bound) | Phase 0.6 baseline + RED-first surfaces it; the pin moves with the edit. |
| Three routed fatals per weekly tick while a reopen stays broken | Bounded; the runbook says "three events, one root cause". |
| Freshness step red / birth held while the evidence is absent | Deleting the file makes the step inactive; the hold is the safe state; PM2 re-lands it alone. |

## Downtime & Cutover

**Offline-inducing operation:** PM4 — the guarded `git_data_host_replace` dispatch (`-replace='hcloud_server.git_data'`) destroys and recreates the git-data host to deliver the payload; the rehearsal reset (`actions/reset`) power-cycles a THROWAWAY host only. Surface affected by PM4: the git-data SSH transport at `10.0.1.20:22` for the replace window; NOT the web/Concierge platform, and NOT any user data — `GIT_DATA_STORE_ENABLED` is off, every write path is gated, and the web-side probe treats git-data as a fail-soft overlay (`web-git-data-probe.sh`: "an OVERLAY, not a hard dependency").

**Zero-downtime evaluation:** a blue-green host (born fresh, cut over, old retired) is not available for git-data — both volumes are `hcloud_volume_attachment`s bound to the single `hcloud_server.git_data` and a volume can attach to one server at a time; a state-only re-address does not deliver a `user_data` change. The replace IS the repo's designated zero-data-loss path (ADR-103: both volumes + the passphrase preserved by omission; the destroy-guard pins them). This plan changes nothing on the live host at merge (OPERATOR_APPLIED_EXCLUSION), so the merge itself is zero-downtime by construction.

**Residual downtime accepted:** the replace window (minutes) on a store that serves no user traffic, under the existing replace gate chain plus — after Phase 4.4 — the rung-2 gate. Justification: the alternative (a running host that silently loses its store at the first reboot) is the defect. Sign-off: PM4 is an explicit `gh workflow run` dispatch whose confirm token is the acknowledgement, sequenced after PM2 and before #8211 flips the store live. Per-stage verification: the replace job's boot-signal poll (five terminal booleans incl. `luks_reopen_unit`); rollback: none needed — a failed replace leaves the volumes intact and the next replace re-runs first boot.

## Domain Review

**Domains relevant:** engineering, product (sign-off at single-user-incident threshold)

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Ship as designed with three changes (all folded): `--only-secrets … --no-fallback` on every `doppler run` the unit pair performs (P1; the fallback cache would put the passphrase on the root disk); a single-emitter design so a failure never double-reports (P1 — resolved at plan-review by moving reporting to `OnFailure=` rather than a sentinel); exact-name server resolution in the reset step. Disqualifying facts: ADR-198 HOLDS as the binding constraint on key delivery; `PrivateTmp` + `systemctl start <mount>` HOLDS and `PrivateTmp` must stay; `enable --now` from cloud-final HOLDS (nftables precedent); ADR-115's reboot blocker DOES NOT APPLY to an API reset of a disposable rehearsal host, but the amendment must name the oneshot as the accepted equivalent (folded); gc fan-out bounded; the reboot arm is proportionate. Review-time delegation: `observability-coverage-reviewer` (reporter reachable from the baked DSN when Doppler is down; one event per failure) and `security-sentinel` (`--no-fallback`/`--only-secrets` on every `doppler run` in the diff).

### Infrastructure (terraform-architect, Phase 2.8)

**Status:** reviewed — IaC-routed: yes. BLOCKING finding folded (templated `--config`). Missed files folded (`git-data-render-strip-parity.test.sh` literal, `git-data-runcmd-rehearsal.test.sh` roster). Its "both jobs HOLD" claim was FALSE (the replace job does not call the rung-2 gate) — corrected by architecture-strategist at plan-review and folded as Phase 4.4. `HCLOUD_TOKEN` (prd_terraform) is a Read & Write project token and covers server actions; the rehearsal root creates `hcloud_volume.rehearsal_luks` and the first-boot heredoc writes the fstab line, so a reset has a real mapper to reopen.

### Product/UX Gate

**Tier:** none (no user-facing surface; the mechanical UI-surface scan matches no `components/**`, `app/**` or design path)
**Decision:** signed-off with conditions (all applied): the git-data host IS born → Apply path corrected and the replace dispatch is PM4 with the #8211 prerequisite; the replace route is the only remediation lever → Risks row + PM1 in the merging session; contract clause (e) — no live flip while the weekly gc is the only standing mapper signal. Threshold confirmed; "ship the mechanism, hold the birth" confirmed; the founder-digest line to state plainly: "the fix is merged and the live host does not have it until PM4".
**Agents invoked:** cpo
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

### Plan-review panel (6 agents) — consolidated

- **Mechanical, applied:** OnFailure reporter replaces the self-wrap (DHH P0 / simplicity P1 / spec-flow P0-1,P0-2 / Kieran P1-6); env lines merged (DHH P1 / simplicity P2); §1b untouched (DHH P1 / simplicity P1 / Kieran P1-3); ADR-228 → amendments (DHH P2 / simplicity P2 / architecture P1-6); birth-gate fifth key cut, contradiction removed (DHH P1 / simplicity P0 / Kieran P1-5 / spec-flow P1-7); probe as a capture-script mode (DHH P1 / simplicity P2-8); Phase 0.4 and 0.2(i) cut (DHH P2 / CTO-devex P2-7); paper ACs cut (DHH P2); "≥ 25" dropped (DHH P2); rehearsal not dispatchable from the branch + evidence deleted in-PR + `Ref` only (architecture P0-2 / Kieran P0-1 / spec-flow P0-3); replace job gains the rung-2 gate (architecture P0-1); `Restart=on-failure` bounded (architecture P1-4 / spec-flow P1-11); device-identity on both paths + `action=mounted` (spec-flow P1-5, P1-8(g)); both-channel probe (spec-flow P1-6); `gitdata_luks_reopen_arm` routed (Kieran P1-7); `_R3B_EXPECTED_SITES` + distinct detail var (Kieran P1-4); `timeout-minutes` 45 (CTO-devex P1-2); AC30-parity roster + reader sweep (CTO-devex P1-1 / architecture P1-5); Guard 3 M5 census dropped (Kieran P1-8 / CTO-devex P1-4); runbook per-action table with "do not replace on header" (CTO-devex P1-3); settle before reset (Kieran P2-13); `findmnt … || true` (Kieran P2-11); `LUKSEOF` closing anchor (Kieran P2-9); repeated `--only-secrets` form + pinned-tarball measurement (Kieran P2-10); follow-through directive on #8210 (spec-flow P1-9); `gh` route for the environment approval (spec-flow P2-13); C4 edge added (architecture P2-7); P5 wording (spec-flow P2-10); #8211 clauses (f)/(g)/(h).
- **Taste (surfaced, recorded in `decision-challenges.md`, not auto-applied):** simplicity's "cut the fifth boolean entirely (reported-not-terminal, like `nft_metadata_drop`)" — kept TERMINAL because the live replace poll is the only reader that catches an unarmed unit on the born host (the reboot arm runs only in rehearsals); CTO-devex's "shared roster lib for the boolean vocabulary" — declined as new mechanism, the existing AC30-parity check is the single source; CTO-devex's "batch the payload queue behind one rehearsal + one replace" — recorded as a PM1 cadence note, not a scope change.

## Infrastructure (IaC)

### Terraform changes

No new Terraform resources, providers or variables. Three payload files enter `modules/git-data-userdata/main.tf`'s `templatefile` map as `file()` entries (rendered into `hcloud_server.git_data.user_data` and `hcloud_server.rehearsal.user_data` alike — the rehearsal root has no copy of the map). `sentry/issue-alerts.tf` gains three stage values in existing `sentry_alert` resources (applied on merge by `apply-sentry-infra.yml` with its plan-projection gate). `TF_VAR_*`: none new.

### Apply path

(c) cloud-init + guarded `-replace`. The git-data host IS born (2026-09-14, run 34836141887; re-birthed by `git-data-host-replace` run 34861860722 — `scripts/encryption-posture-ledger.json`), with the store not user-enabled. The payload reaches it ONLY through the guarded `git_data_host_replace` dispatch (PM4), which preserves both volumes and the passphrase and re-runs first boot. Merging changes nothing on the live host (OPERATOR_APPLIED_EXCLUSION). Gate hold: the birth-readiness gate derives its hash input by grepping the module's `file()` bindings, so the new payloads enter `RUNG2_TEMPLATE_SHA256` automatically; with the stale evidence DELETED in this PR, `git_data_host_create` and — after Phase 4.4 — `git_data_host_replace` both HOLD until PM2 lands fresh evidence from a `main` rehearsal. Downtime at PM4: the usual replace window (no serving traffic on the store). Blast radius: the rehearsal root (one throwaway cpx22 + volumes, torn down with the survivor check) and, at PM4, the git-data host under the replace gate chain.

### Distinctness / drift safeguards

`prd_git_data` is a dedicated Doppler config with a read-only token; the rehearsal uses `prd_git_data_rehearsal_<run_id>`, which is why the config name is templated. `hcloud_server.git_data` is an OPERATOR_APPLIED_EXCLUSION — the merge-triggered apply never plans it. `lifecycle.ignore_changes`: none added. State: no secret enters `terraform.tfstate` that is not already there.

### Vendor-tier reality check

Hetzner `POST /servers/{id}/actions/reset` is available on every plan; Sentry `sentry_alert` stage filters are already in use at the same tier. No tier gate needed.

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-115 (the normative blocker is cleared for git-data by a Doppler-run systemd oneshot — the accepted equivalent of `crypttab`/keyscript; the self-reboot primitive remains un-adopted; the second blocker is untouched) and ADR-198 (the leg-(2) incumbent is accepted by design for the boot reopen under `--only-secrets --no-fallback`; #7772's removal intent is superseded; Art. 32(1)(c) availability framing). Both are Phase 5 tasks, not follow-ups. No new ADR: the plan-review panel judged the decisions to be amendments of the two ADRs that already own the questions, and the C4 edge below is where the new runtime dependency is recorded.

### C4 views

Container view: add the edge `gitDataStore -> doppler` (verified absent; only `github -> doppler` and `inngest -> doppler` exist) — the reopen makes the host's Doppler read a store-availability dependency on every boot. Elements: no new actor, system, container or data store (the units live inside `gitDataStore`; Sentry/Better Stack edges exist; the rehearsal's Hetzner reset is the existing `github → hcloud` relationship). Access relationships: unchanged. Also the `gitDataStore` description sentence. Verified by reading all three `.c4` files; `c4-count-parity.test.sh` checks prose counts only (no monitor/alert-resource/heartbeat cardinality moves — three stage VALUES inside existing alert resources), so it stays green; `c4-render.test.ts` must stay green with the new edge.

### Sequencing

The amendments describe the target state and are `accepted` on merge; the reboot-arm evidence (PM2) is their live verification, and each amendment's Status notes the run URL once captured.

## GDPR Gate (Phase 2.7 — fired on trigger (b), `single-user incident`)

**This is not legal review. Findings are heuristic. Consult `clo` + `legal-compliance-auditor` before merging.**

`bash plugins/soleur/skills/gdpr-gate/scripts/gdpr-gate.sh <plan> cloud-init-git-data.yml issue-alerts.tf` → `path scan complete — 3 examined, 0 matched`. Five v1 checks against the plan prose: no schema/column/table/FK/RPC (Art-6/5e/17/17-caller: none); no new vendor, SDK or env var — Doppler, Sentry, Better Stack, Hetzner are pre-existing sub-processors with DPA rows (Chapter V: none); no column (Art-9: none). Suggestion: this plan IS the Art. 32(1)(c) "ability to restore availability in a timely manner" control for the encrypted store; the ADR-198 amendment cites it so the ledger's #6897 row can reference it at cutover. Read-only; no posture write.

## References & Research

- Issue #8210; #8189/#8206 (origin); #8262 (`a19a6df6e`); #7695 / PR #6894 / PR #7778 (inngest reopen unit — shape precedent); #6931 (web hosts' deferred unlock — sibling gap, not in scope); #7761 / PR #7768 (`--only-secrets` guard); #7240 (`933635603`, isLuks rc ruling); #7204/#7227 (detail-source and emit-window learnings the reporter honours); #8052 (`d579d8b68`) / #8126 (`273f29a80`) (evidence delete-then-re-land precedent, both verified on `origin/main`); #8101, #8010, #8094, #8211 (queued after this).
- ADR-115, ADR-198, ADR-149, ADR-103, ADR-147, ADR-163.
- Learnings listed under Research Insights.
- Framework docs (deepen pass, quoted): systemd `service.c` "Service has Restart= set to either always or on-success, which isn't allowed for Type=oneshot services" (so `on-failure` is allowed); `service_enter_dead()` "We make two state changes here … so that external software can watch … even if they are only transitionary and followed by an automatic restart" (OnFailure semantics); `namespace.c` "Remount / as SLAVE so that nothing now mounted in the namespace shows up in the parent" (PrivateTmp); fstab-generator: `nofail` → `.wants/` symlink; Debian `crypttab(5)`: "the systemd cryptsetup helper doesn't support the keyscript option"; Doppler `run.go`: `StringSliceVar(&secretsToInclude, "only-secrets", …)`, `Bool("no-fallback", false, "disable reading and writing the fallback file")`.
- Sharp Edge carried forward: a plan whose `## User-Brand Impact` is empty fails deepen-plan Phase 4.6 — it is filled above.
