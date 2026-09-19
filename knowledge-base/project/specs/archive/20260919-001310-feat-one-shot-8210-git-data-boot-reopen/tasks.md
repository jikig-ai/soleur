---
feature: feat-one-shot-8210-git-data-boot-reopen
lane: cross-domain
plan: knowledge-base/project/plans/2026-09-18-fix-git-data-luks-mapper-reopen-at-boot-plan.md
issue: 8210
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- Every `systemctl` token below is cloud-init payload content (write_files/runcmd) or a stubbed
     call inside a test harness — see the plan's ## Infrastructure (IaC). No human runs them. -->

# Tasks — git-data: reopen /dev/mapper/git-data on every boot, proven by a rung-2 reset arm

Derived from plan **v2 + deepen pass** (6-reviewer consolidation + CTO/CPO/terraform-architect/advisor, then verify-the-negative, framework-docs, git-history, observability, security and test-design passes). No `spec.md` exists for this branch, so `lane:` defaulted to `cross-domain` (TR2 fail-closed). Phase order is dependency-directed: the guard suite and the units land before the payload wiring; the readers of the fifth boolean land before the rehearsal arm that produces the reboot key; the evidence file is DELETED in this PR and re-landed alone after merge.

## Phase 0 — Measure before building (local, no prod write; pin verdicts + date in the plan's Research Insights)

- [ ] 0.1 Doppler CLI forms against the PINNED 3.75.3 tarball (not the dev host's 3.76.5): repeated `--only-secrets NAME`, `--no-fallback`, `--config prd_git_data_rehearsal_x` parse, exit-code forwarding (`doppler run -- sh -c 'exit 7'; echo $?` → 7)
- [ ] 0.2 `systemd-analyze verify` on the drafted unit pair (documented allowed: `Restart=on-failure` + `RemainAfterExit=yes` on oneshot; pin on the installed 255) plus the `ProtectSystem=strict` + `ReadWritePaths=/run/cryptsetup` combination as a measurement
- [ ] 0.3 Namespace + PID-1 mount: `systemd-run --wait -p Type=oneshot -p PrivateTmp=yes` tmpfs probe (inside yes / outside no); loop-device LUKS + `nofail` fstab line → `luksOpen` → the unit-shaped `daemon-reload` + start of the escaped `.mount` unit mounts and is host-visible
- [ ] 0.4 Tool forms: `findmnt --fstab -n -S /dev/mapper/x -o TARGET` (exit 1 on no match), `systemd-escape -p --suffix=mount /mnt/git-data-luks`, `cryptsetup status <name>` `device:` line, `cryptsetup isLuks` rc table
- [ ] 0.5 Budget baseline: `bash apps/web-platform/infra/git-data-userdata-budget.sh` (15,444 B today)
- [ ] 0.7 `/tmp` backing on the rehearsal image (record; `TMPDIR` on tmpfs is applied either way)
- [ ] 0.8 `systemctl show -p ExecMainStatus,ExecMainCode,Result,NRestarts` on a unit driven to `start-limit-hit` under `systemd-run` — the reporter's four tags survive the transition
- [ ] 0.6 One shell line baselining every touched suite GREEN on the unmodified tree: `git-data-luks.test.sh`, `git-data-runcmd-rehearsal.test.sh`, `git-data-render-strip-parity.test.sh`, `git-data-template-strip.test.sh`, `git-data-rung2-rehearsal.test.sh`, `git-data-emit.test.sh`, `doppler-injection-bound.test.sh`, `tests/scripts/test-git-data-rung2-evidence-capture.sh`, `tests/scripts/test-git-data-boot-signal-poll.sh`, `tests/scripts/test-git-data-birth-readiness-gate.sh`, `plugins/soleur/test/terraform-target-parity.test.ts`; record cloud-init's `scripts-user` semaphore mechanism

## Phase 1 — Guard suite, script, units, ADR text (RED → GREEN)

- [ ] 1.1 Write `apps/web-platform/infra/git-data-luks-reopen.test.sh` first: static predicates over script + both units + cloud-init + bootstrap + gc.service + `issue-alerts.tf` (M22) + module `variables.tf` (M23); runtime arm with `GIT_DATA_REOPEN_RUNDIR`/`DEVICE_WAIT` seams, stubbed `cryptsetup`/`findmnt`/`mountpoint`/`systemctl`/`journalctl`/`blockdev`/`realpath`/`git-data-emit` (NOT `systemd-escape`), positive stub census (H1), per-fixture phase-tagged `calls.log` for ORDER rows (H5), reporter arm via `sh -c` body extraction + `/usr/local/bin/` → `$SCRATCH/` rewrite (count N → 0), composition fixtures (script phase-P failure → reporter emit `action=P result= rc= code= restarts=`); Guard 1 M1–M24; H1–H5
- [ ] 1.2 Write `apps/web-platform/infra/git-data-luks-reopen.sh` to the contract (`#!/bin/bash`; `RUNDIR`/`DEVICE_WAIT` seams; phase file before every phase, both files `rm -f`'d on success; config shape asserts → key → device (`blockdev`, no `-b`) → header → open → identity → target → mount → identity-mount; no traps, no `mkfs`/`luksFormat`, no `mount(8)`, no `/usr/local/bin/` literals; success emit at stage `luks_reopen_ok` with `action=reopened|mounted` + `restarts=`; silent noop; comment header with the phase table and no `doppler run --project soleur ` literal)
- [ ] 1.3 Write `apps/web-platform/infra/git-data-luks-reopen.service` (gc.service shape; `OnFailure=`; bounded `Restart=on-failure`; `RuntimeDirectory=git-data-luks-reopen` + `RuntimeDirectoryPreserve=yes`; `Environment=TMPDIR=/run/git-data-luks-reopen`; `UMask=0077`; `NoNewPrivileges=yes`; `ExecStartPre=/bin/rm -f …action …log`; `--only-secrets GIT_DATA_LUKS_KEY --only-secrets BETTERSTACK_LOGS_TOKEN --no-fallback`; `--config "$GIT_DATA_DOPPLER_CONFIG"`; `PrivateTmp=yes`; `TimeoutStartSec=300`) and `git-data-luks-reopen-failure.service` (gc-failure shape; `Environment=TMPDIR=/dev/shm`; `UMask=0077`; reads `/run/git-data-luks-reopen/action` + `/log`; `systemctl show` tags `result=`/`rc=`/`code=`/`restarts=`; journal `Doppler Error|Unable to` grep when the log is absent, literal only when that is empty; `timeout 90 doppler run … -- "$@" || "$@"`); `systemd-analyze verify` locally
- [ ] 1.4 Draft the ADR-115 and ADR-198 amendment paragraphs (credential decision settled before wiring)

## Phase 2 — Payload wiring

- [ ] 2.1 `modules/git-data-userdata/main.tf`: `git_data_luks_reopen`, `git_data_luks_reopen_service`, `git_data_luks_reopen_failure_service` (one line each); mirror in `git-data-userdata-budget.sh`; `git-data-render-strip-parity.test.sh` literal 9 → 12; `git-data-runcmd-rehearsal.test.sh` `EXPECTED_PATHS` +3; `modules/git-data-userdata/variables.tf` `validation {}` on `doppler_config_name` (`^[a-z0-9_]+$`) and `git_data_luks_volume_id` (`^[0-9]+$`); `terraform validate` on both roots
- [ ] 2.2 `cloud-init-git-data.yml` `write_files`: script 0755, both units 0644; append `GIT_DATA_LUKS_DEV=…${git_data_luks_volume_id}` and `GIT_DATA_DOPPLER_CONFIG=${doppler_config_name}` to the `/etc/default/git-data-doppler` entry (RED-first: check whether A27 / injection-bound / #7460 pins byte-match its content)
- [ ] 2.3 `cloud-init-git-data.yml` `runcmd`: `STAGE=gitdata_luks_reopen_arm` item after the closing `LUKSEOF`, before `STAGE=gitdata_nftables_metadata` (nftables shape with the `enable --now` capture; `_reopen_arm_detail`; WARNING at `"$${STAGE}_warn"`); `_R3B_EXPECTED_SITES` += `gitdata_luks_reopen_arm`
- [ ] 2.4 `git-data-bootstrap.sh`: `_reopen_unit` measurement (`is-enabled` AND `show -p Result --value` = success) + `"luks_reopen_unit=${_reopen_unit}"` on `boot_complete`; §1b untouched
- [ ] 2.5 `git-data-gc.service`: `Wants=` / `After=git-data-luks-reopen.service`
- [ ] 2.6 `git-data-luks.test.sh`: `p_doppler_config_scope` enumerates both new units; third accepted shape = exact literal `--config "$GIT_DATA_DOPPLER_CONFIG"`; companion predicate on the env-file content carrying `GIT_DATA_DOPPLER_CONFIG=${doppler_config_name}`
- [ ] 2.7 `.github/workflows/infra-validation.yml`: register `git-data-luks-reopen.test.sh`; unit-lint list = three units + gc; filter `git-data-(gc|luks-reopen)`
- [ ] 2.8 Budget re-run; record before/after (expected ≈ 2–3 KB delta; ≤ 20,000 B stored)

## Phase 3 — Off-host routing and the boolean's readers

- [ ] 3.1 `sentry/issue-alerts.tf`: `luks_reopen` + `gitdata_luks_reopen_arm` in `git_data_boot_fatal` (prose ten → twelve; the "four booleans" comment); `gitdata_luks_reopen_arm_warn` in `git_data_boot_warning`; `luks_reopen_ok` in NO rule with a deliberately-absent comment (the fatal rule has no `level` condition); regenerate `alert-reference.json`; `terraform validate`; `scripts/sentry-alert-reference-gate.sh`
- [ ] 3.2 Reader sweep for `luks_reopen_unit` (TERMINAL): `scripts/lib/git-data-boot-signal-poll.sh` loop + SQL; `git-data-rung2-evidence-capture.sh` FAIL regex + `HOST_SQL` + PASS prose; `git-data-emit.test.sh` `_asserted_keys`; `apply-web-platform-infra.yml` disclosure ("exactly one boolean is measured" → two) + replace-job readiness note; `scripts/followthroughs/git-data-birth-emitter-6982.sh` SQL; `runbooks/git-data-birth.md`; RED `luks_reopen_unit":"no"` fixtures in both `tests/scripts/test-*.sh`

## Phase 4 — Rehearsal reset arm and the replace-job gate

- [ ] 4.1 `git-data-rung2-evidence-capture.sh --reboot-since <ts>` mode: `HOST_SQL` gains `action`/`restarts`/`luks_reopen_unit` projections + a static row that every grepped name is projected; `since` applied SERVER-side on both channels (`_BS_WHEN` shape; `sentry-issue.sh --host-events --stage luks_reopen_ok --start <since> --end <now>`); verdict over the post-`since` set only (reopened → 0; fatal or non-`reopened` `luks_reopen_ok` action → 1; empty + live anchor → 2); append `RUNG2_REBOOT_REOPEN=PASS` + `_CHANNEL=` + `_RESTARTS=` + `QUERY:` comments on 0 only. `scripts/sentry-issue.sh`: `--stage <stage>` option for `host-events` (swaps `level:fatal`, projects `field=action`). `test-git-data-rung2-evidence-capture.sh`: `make_stub` `__HOSTROWS__` semantic dispatch on the `dt >` clause (`exit 4` when `--reboot-since` given but clause absent); fixtures F-B (must-PASS), BS-only, Sentry-only, post-`since` fatal, `mounted`/`noop`, F-A, empty+live, empty+dead; `SENTRY_ARGV_FILE` asserts `--stage --start --end` (Guard 2 M2/M3/M6/M7, H1–H5)
- [ ] 4.2 `git-data-rung2-rehearsal.yml`: 120 s settle after capture PASS; `id: reset` (exact-name `${REHEARSAL_PREFIX}${GITHUB_RUN_ID}` via `select(.name == $n)`, exactly one id, `::add-mask::`, `RUNG2_REBOOT_SINCE` BEFORE the `curl -X POST`, `actions/reset`, action polled ≤ 120 s); `id: reboot_probe` bounded poll; upload `if:` gated on `capture_rc` AND `reboot_rc`; `timeout-minutes: 45` with the sum comment; step summaries
- [ ] 4.3 `git-data-rung2-rehearsal.test.sh` arms: upload gate (both rcs), exact-name (`GET /v1/servers?name=`) + prod-name/survivor refusal, `since` before POST, `timeout-minutes` ≥ the derived sum of the workflow's bounded polls, probe `_BS_WHEN` literal equals the capture's
- [ ] 4.4 `apply-web-platform-infra.yml` `git_data_host_replace`: rung-2 gate step before the plan step (mirror of the create job's); `plugins/soleur/test/terraform-target-parity.test.ts` replace-job case
- [ ] 4.6 `git-data-emit.test.sh`: consumer-roster arm beside AC30-parity — `NON_TERMINAL="nft_metadata_drop disk_pct inode_pct"` once; `TERMINAL = producer − NON_TERMINAL`; poll loop, capture FAIL alternation and both SQL projections asserted equal to it (Guard 3 M2/M3/M6)
- [ ] 4.5 Delete `apps/web-platform/infra/git-data-rung2-boot-evidence.env` (Guard 4 permitted shape; precedent d579d8b68/#8052); confirm the freshness step goes inactive and `test-git-data-birth-readiness-gate.sh` is green

## Phase 5 — Architecture record and runbook

- [ ] 5.1 ADR-115: dated section under the NORMATIVE BLOCKER (oneshot = accepted equivalent; self-reboot still not adopted; second blocker untouched; alternatives from the Cut List)
- [ ] 5.2 ADR-198: dated amendment (leg-(2) incumbent accepted by design under `--only-secrets --no-fallback`; revocability argument; #7772 intent superseded; Art. 32(1)(c))
- [ ] 5.3 `model.c4`: `gitDataStore -> doppler` edge + description sentence; `views.c4` includes both ends; `c4-code-syntax.test.ts`, `c4-render.test.ts`, `plugins/soleur/test/c4-count-parity.test.sh` green
- [ ] 5.4 `runbooks/git-data-luks-cutover-5274.md`: per-action decision table (rows = `phase` literals ∪ `ACTION=` values ∪ reporter literals: config, key, device, header, open, identity, target, mount, identity-mount, unit, noop, reopened, mounted); `unit` keys on `result=`/`rc=` + `doppler configs`/`doppler activity`; `key` → `doppler secrets --only-names`; `open` AND `header` → DO NOT replace; `config` → payload defect + replace; `device`/`identity` → `GET /v1/servers/{id}` volume ids vs pin; `mount|identity-mount` → replace only for unit/payload defects, `bad superblock` → ADR-068 backup/rebuild path; 180-char detail cap; one event per unit failure; three events per weekly gc tick; no SSH step; `lint-infra-no-human-steps.py --changed --base origin/main` green

## Phase 6 — Follow-through wiring

- [ ] 6.1 `scripts/followthroughs/git-data-reboot-evidence-landed-8210.sh` (exit 0 when `main`'s evidence carries `RUNG2_REBOOT_REOPEN=PASS` and the rung-2 gate RELEASEs; exit 2 TRANSIENT now — T4 — and 2 on any non-main checkout); directive + `follow-through` label on #8210 at ship

## Phase 7 — Verification and ship prep

- [ ] 7.1 Walk AC1–AC18; PR body `Ref #8210` / `Ref #8010` / `Ref #8211` + Phase 0 verdicts + budget before/after
- [ ] 7.2 `bash scripts/test-all.sh --capacity` before any full gate; queue inside the lock (`SOLEUR_ALLOW_FULL_GATE=1 TC_LOCK_TIMEOUT=10800 TC_RUNTIME_CEILING_S=21600`); confirm negatives on NUL-bearing fixtures with `grep -a`/Python, never bare `grep`
- [ ] 7.3 Post-merge (recorded, `gh`-driven): PM1 rehearsal from `main` (dry_run then real; `pending_deployments` approval via `gh api`); PM2 evidence-only PR; PM3 follow-through closes #8210; PM4 `git-data-host-replace` after PM2 + #8211 prerequisite comment with clauses (a)–(h); PM5 follow-on issue for the two untouched `doppler run` sites + emitter `--retry 2`
