---
title: "Tasks: registry-host at-rest posture emitter (#8386)"
plan: knowledge-base/project/plans/2026-09-19-feat-registry-host-at-rest-posture-emitter-plan.md
branch: feat-one-shot-8386-registry-posture-emitter
lane: cross-domain
---

# Tasks: registry-host at-rest posture emitter (#8386)

Derived from the plan after plan review. Phase order is load-bearing: the contract-changing edits
(emitter shape) precede their consumers (the probe), and every RED task precedes its GREEN pair.

## 0. Preconditions (read-only — measure, do not assume)

- [ ] 0.1 `bash apps/web-platform/infra/registry-userdata-budget.sh` — record stored bytes + headroom (expected ≈14,180 / 18,588 B).
- [ ] 0.2 `bash apps/web-platform/infra/zot-disk-heartbeat-redaction.test.sh` — green baseline; note its extraction + stub harness, its render map and its anti-vacuity floor.
- [ ] 0.3 `bash apps/web-platform/infra/registry-boot-guard.test.sh` — green; record the assertion count it reports (105 at `MIN_ASSERTIONS=105` on `origin/main`).
- [ ] 0.4 Locate the two registration sites: `grep -n 'run: bash apps/web-platform/infra/zot-disk-heartbeat-redaction.test.sh' .github/workflows/infra-validation.yml` and `grep -n 'zot-last-err-redact-7500' scripts/test-all.sh`.
- [ ] 0.5 `findmnt -no SOURCE "$(mktemp -d)"; echo rc=$?` → empty, rc=1 (the `__NOMOUNT__` premise); `command -v timeout lsblk findmnt blkid cryptsetup`; confirm `blkid`/`cryptsetup` resolve under `/usr/sbin`.
- [ ] 0.6 Read `apps/web-platform/infra/inngest-bootstrap.sh` from `data_mount_src=n/a` through the whitespace guard after `_devid_hits` — the block to copy — and `apps/web-platform/infra/luks-monitor.sh`'s `findmnt` → `cryptsetup status` → `device:` → `blkid` chain.
- [ ] 0.7 `python3 scripts/lint-encryption-posture.py --repo-sweep` — green baseline.
- [ ] 0.8 Row-budget measurement (read-only, existing credential): `scripts/betterstack-query.sh --since 1h --grep SOLEUR_ZOT_DISK --limit 1` → record the live row's total length and its length ahead of ` zot_last_err=`; record Better Stack's documented per-message ingest limit with its doc URL. Derive the suite ceiling as (limit − current). If the limit cannot be established, record why and degrade AC-E7 as the plan specifies. Offline floor already measured: template 876 B / 848 B ahead of the tail / 26 unexpanded vars.
- [ ] 0.9 `grep -n 'unrendered TF interpolation' -B8 apps/web-platform/infra/zot-disk-heartbeat-redaction.test.sh` — read the four `sed -i` render lines and the T1 assertion. Phase 2.2 adds a fifth template var to that block.

## 1. RED — emitter suites before the emitter

- [ ] 1.1 Extend `apps/web-platform/infra/zot-disk-heartbeat-redaction.test.sh`: add the fifth render line `sed -i 's|\${registry_volume_id}|100000003|g' "$HB"`; add stubs for `findmnt` (`HB_FINDMNT_OUT`/`HB_FINDMNT_RC`), `lsblk` (fixture tree for `-inso NAME`, exit 64 on any other argv), `cryptsetup` (`HB_CRYPT_OUT`/`HB_CRYPT_RC`, exit 64 unless argv is `status <name>`), `blkid` (`HB_BLKID_OUT`), and a by-id dir under `$TMP` exported as `ZOT_BYID_DIR`.
- [ ] 1.2 Add the posture cases (each asserting on the captured POST body, and that the four fields precede ` zot_last_err=`): healthy; no-mount (rc 1); findmnt rc 124; raw ext4; non-LUKS mapper (rc 0, no LUKS `type:`); cryptsetup rc 4 + blkid `ext4` → `no`; rc 4 + blkid silent → `unknown`; rc 1 → `unknown`; rc 127 → `unknown` with the row still emitted; forked tree → `__AMBIGUOUS__`; partitioned chain with the signature on `sdb1` → `yes` via the `device:` line; LUKS `type:` with no `device:` line → `unknown`; 0 and 2 aliases → `__NOMATCH__` / `__AMBIGUOUS__`; bracketed src → `__UNREADABLE__`; sbin-only stubs with `ZOT_SBIN_DIRS="$BIN/sbin"` → `yes`; `store_expected_devid` equal to the rendered value. Every case: exactly one POST, exit 0, no space/quote/backslash in any value, head within the 0.8-derived ceiling, and no `store_mount_base=` in the row.
- [ ] 1.3 Raise the suite's anti-vacuity floor to the count it reports after 1.2.
- [ ] 1.4 `registry-boot-guard.test.sh`: add `store_mount_src=`, `store_mount_devid=`, `store_expected_devid=`, `store_luks=` and `ZOT_SBIN_DIRS` to the presence loop; set `MIN_ASSERTIONS` to the count that run reports.
- [ ] 1.5 Create `apps/web-platform/infra/store-vs-data-mount-parity.test.sh` — derive (never list) every file declaring a `scsi-0HC_Volume_*` by-id walk, assert it found ≥ 2 and name them, extract each resolution block, and assert the three invariants: leaf-counting not last-row, Hetzner-namespace scoping, hit-counting not first-match. Include the found-count floor so a path rename reddens rather than silently passes.
- [ ] 1.6 Register the parity guard: one single-line `run: bash apps/web-platform/infra/store-vs-data-mount-parity.test.sh` in `.github/workflows/infra-validation.yml` (a multi-line `run: |` block de-registers the suite).
- [ ] 1.7 Run all three — the extended suite reddens on the missing fields, the boot guard on the four names plus the seam, the parity guard green against the faithful copy and red under each mutation.

## 2. GREEN — the emitter

- [ ] 2.1 At the top of `zot-disk-heartbeat.sh`, beside `set -u`: `ZOT_SBIN_DIRS="$${ZOT_SBIN_DIRS:-/usr/sbin:/sbin}"; PATH="$PATH:$ZOT_SBIN_DIRS"`, plus the one-line pointer comment on the `/etc/cron.d/zot-disk-heartbeat` block.
- [ ] 2.2 Add the posture block after the log-shipper block and before the `zot_last_err is free-text` comment: defaults bound before any measurement; the rc-capturing `findmnt … | head -1` read with the rc-1 `__NOMOUNT__` arm and the charset guard; the copied `lsblk -inso` leaf-counting walk and by-id hit-counting reverse map (renamed vars, `ZOT_BYID_DIR` seam, `$${…}` escapes); the `cryptsetup status` → `type:` → `device:` → `blkid` chain reading the BACKING device; the whitespace guards. Every call `timeout 5`-bounded, every rc captured with `rc=0; out=$(…) || rc=$?` — never `|| true`.
- [ ] 2.3 Extend `LINE=`: insert `store_mount_src=$STORE_MOUNT_SRC store_mount_devid=$STORE_MOUNT_DEVID store_expected_devid=scsi-0HC_Volume_${registry_volume_id} store_luks=$STORE_LUKS ` before `host=$(hostname)`. Single `$` on the template var is correct and verified.
- [ ] 2.4 Rationale comments start with `# ` so the render-time strip removes them; keep them short.
- [ ] 2.5 Run: the extended suite, the boot guard, the parity guard, `registry-userdata-budget.sh` (this IS the offline render — a bad escape fails here) and `registry-userdata-budget.test.sh`, plus `registry-luks.test.sh` and `private-nic-guard.test.sh`.

## 3. The follow-through probe

- [ ] 3.1 Create `scripts/followthroughs/registry-luks-live-8386.sh`: xtrace refusal (exit 78); secret preflight for the three Better Stack names; the guard chain as ordered early exits (query, channel_dark, envelope, decode, host filter, boot_id, `producer_silent` on a newest-row `dt` older than 30 min, integer guard); one awk pass over the trusted head producing `D`/`Y`/`P` and the newest row's four values; verdicts V1→V7 in the stated order; the three-state `python3` ledger reader invoked ONLY on the V6/V7 path. No `gh`, no `GH_TOKEN`, no `ssh`.
- [ ] 3.2 Create `scripts/followthroughs/registry-luks-live-8386.test.sh` from the 7500 harness: temp root with the probe, the parse lib, a stub `betterstack-query.sh`, a stub ledger (available / other / malformed / absent) and a stub apply workflow of controllable size. Every case pins a branch marker AND the exit code; fixtures are producer-shaped envelope rows with fabricated boot ids and aliases; positive control at the bottom.
- [ ] 3.3 Cover every verdict and guard: V1 (earlier `no` under a good newest row), V2 (all three exits incl. the 30-day escalation and both apply-file sizes as message text), V3 (newest row lacks the field), V4 (each disjunct, incl. malformed expected alias and newest `absent`), V5, V6, V7, plus channel_dark, stub rc 7, envelope-only, zero-after-host-filter, no boot_id, `producer_silent`, unreadable ledger.
- [ ] 3.4 Register: `run_suite "scripts/registry-luks-live-8386" bash scripts/followthroughs/registry-luks-live-8386.test.sh` in `scripts/test-all.sh` beside the 7500 line; `bash scripts/lint-orphan-test-suites.sh` → `orphan test suites: none`; `bash scripts/lint-followthrough-varq-ban.sh` green.
- [ ] 3.5 Mutation-prove Guard 1's matrix rows 1-14 on scratch copies and record the results in the commit message.

## 4. Records

- [ ] 4.1 Rewrite the `hcloud_volume.registry` ledger row: content-anchored `evidence` with the `CORRECTED 2026-09-19 (#8386)` clause (do NOT restate the old `.yml:<n>` literal); the `unavailable:` `live_verification` naming the emitter, the probe path, the delivery dependency and the flip criterion; `does_not_defend` saying the reboot window is *measurable once delivered*, not *now MEASURED*. `live_coverage_floor` stays 1. Run `python3 scripts/lint-encryption-posture.py --repo-sweep`.
- [ ] 4.2 ADR-141 amendment `## Amendment — 2026-09-19 (#8386)` (≤ 16 lines): what landed, why the row stays `unavailable`, what flips it, that the floor moves with the flip, the restated blocker set #6894 / #8386 / #6897, and the explicit clause that the deferred vendor alert does not discharge Decision 1's `scheduled-terraform-drift.yml` reconcile.
- [ ] 4.3 `model.c4` — extend BOTH edges: `zotRegistry -> betterstack` (the row now carries the posture fields) and `github -> betterstack` (this probe among its consumers, annotated as a read that gates a security ledger row). Run the two c4 vitest files and `bash plugins/soleur/test/c4-count-parity.test.sh`.
- [ ] 4.4 `bash scripts/generate-kb-index.sh`; commit `knowledge-base/INDEX.md`.

## 5. Ship and enrollment (runs inside /ship — no operator step)

- [ ] 5.1 Verify the full pre-merge AC set (AC-E1…E7, AC-G1, AC-P1…P4, AC-L1…L2, AC-R1…R5), including AC-R3's assertion that neither `apply-web-platform-infra.yml` nor the sweeper workflow is touched.
- [ ] 5.2 `gh issue edit 8386 --add-label follow-through` and append the tracker directive (three Better Stack secrets, `earliest=` = merge day + 1) to the #8386 body.
- [ ] 5.3 Comment on #6923: the #6895 blocker line is superseded by #8386, and the arm criterion is the OBSERVED BOOT — the ledger flip is its bookkeeping consequence, not the trigger.
- [ ] 5.4 Comment on #8361: when it lands, this template has an undelivered change behind the dispatcher watermark (`f5ad46390`); the delivering action is `gh workflow run registry-host-replace-dispatch.yml -f reason='deliver #8386 registry posture emitter' -f tracker=8386`.
- [ ] 5.5 File the deferral issue (`deferred-scope-out`): the standing `store_luks != yes` Better Stack alert WITH its own follow-through directive, plus the reboot-surviving zot launch gate. Cite it in the PR body.
- [ ] 5.6 PR body: `Ref #8386` (never `Closes`), the delivery statement, the deferral issue, and the rendered `decision-challenges.md` (UC-1, the deferred ledger flip).
