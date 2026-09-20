---
title: "feat(encryption-posture): registry-host at-rest posture emitter — SOLEUR_ZOT_DISK carries store_mount_src / store_mount_devid / store_luks so hcloud_volume.registry's LUKS claim is verifiable off-box"
type: feat
date: 2026-09-19
slug: feat-registry-host-at-rest-posture-emitter
branch: feat-one-shot-8386-registry-posture-emitter
issue: 8386
closes: none  # #8386 is the follow-through TRACKER; the sweeper closes it on a real PASS after delivery AND the ledger flip. The PR body uses `Ref #8386`, never `Closes`.
priority: p2
domain: engineering
brand_survival_threshold: aggregate pattern
lane: cross-domain
---

# feat(encryption-posture): registry-host at-rest posture emitter

## Enhancement Summary

**Deepened on:** 2026-09-19
**Sections enhanced:** Proposed Solution §1/§2/§3, Implementation Phases 0-5, Observability, Guard Contract (all three), Test Scenarios, Acceptance Criteria, Non-Goals, Risks, Files.
**Agents used:** verify-the-negative sweep, citation/attribution audit, `test-design-reviewer`, `security-sentinel`, `observability-coverage-reviewer`, `git-history-analyzer` — after a six-reviewer plan-review panel and a scoped advisor consult.

### Key improvements

1. **A root-RCE seam was removed before it was written.** The deepen pass proposed `ZOT_SBIN_DIRS` as a test seam for the PATH append; `security-sentinel` established that the heartbeat runs under `doppler run --config prd`, where every secret in the config becomes an environment variable — so a config-store write could have owned root's first resolution of `cryptsetup` and `blkid` every five minutes, because cron's own PATH contains neither. The seam moved to render time (the suite already sed-renders the extracted script), the literal ships, and the boot guard now pins BOTH the literal's presence and the absence of any env read. `ZOT_BYID_DIR` went the same way.
2. **V7 no longer auto-closes a security tracker.** Source 2457081 is shared and multi-tenant, a Better Stack source has one ingest token, and `host=`/`boot_id` are producer-controlled inside the message — so three producer-shaped rows are forgeable by any holder of that token. Adequate authority to stop waiting; not adequate for unattended closure plus a ledger flip. Exit 0 returns when the emitter moves to a single-tenant source.
3. **A cut field came back, on a better argument and under a better name.** Plan review cut `store_mount_base` as a second carrier; the observability review overturned it with the inngest sibling's own recorded rationale — on the `__NOMATCH__` path it is the only field separating "failed open onto the root disk" from "attached to some other volume". It returns as `store_backing_dev`, which names the device the `yes` verdict actually rests on and also covers the partitioned case.
4. **A guard that would have reddened correct code was rescoped.** Guard 3's population predicate was "any file with a `scsi-0HC_Volume_*` walk"; the tree has ten-plus, and `git-data-bootstrap.sh` deliberately first-matches over it because it answers a different question. Rescoped to the mount-source-resolution shape, with that file as an explicit must-PASS control — the precedent's own recorded failure mode, avoided.
5. **The blkid read targets the wrong device on a partitioned volume** — caught by spec-flow. It now reads the `cryptsetup status` `device:` line (the `luks-monitor.sh` form), not `/dev/$STORE_MOUNT_BASE`, and a partitioned fixture pins it.
6. **The staleness clock generalized from one branch to all of exit 3.** Scoped to the undelivered verdict, a structurally broken probe would have idled forever on V3/V5/the integer guard, indistinguishable from legitimate waiting.

### New considerations discovered

- The issue's claim that the reopen unit "exits 0 on every failure arm" is overbroad — two arms do, the empty-key arm exits 1 and fails the oneshot. The conclusion survives (no off-box reader sees a unit state), and the plan now says so precisely rather than inheriting the phrasing.
- `AC-E6`'s awk used `\s`, a gawk extension that mawk matches as a literal `s`; measured against `gawk --posix`, the assertion guarding "the emit is unconditional" passed on a script with an `exit` before `LINE=`.
- The emitter measures device binding but NOT escrow recoverability — `luks-monitor.sh` runs five steps and this copies three. `store_luks=yes` will mean "the store is on a LUKS device", never "we can still unlock it". Stated in the ledger text and the ADR amendment, and deferred with the cadence question attached.
- `disclosed_as: not-publicly-claimed` is unguarded for a `luks` row: `check_at_rest` hands `luks` to `check_luks_row`, which returns before the disclosure check runs.
- Two citation defects: `ADR-190 (dispatcher)` was really ADR-169, and the plan and tasks.md named different halves of the `lint-followthrough-varq-ban` pair. Both corrected.

## Overview

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

The `SOLEUR_ZOT_DISK` heartbeat the registry host ships to Better Stack every five minutes reports fill level, restarts, memory, image digest and log-shipper counters, but nothing about what `/var/lib/zot` is mounted from. The encryption-posture ledger row for `hcloud_volume.registry` asserts `mechanism: luks` on the strength of one 2026-08-10 job log, and its `live_verification` is `unavailable:` pointing at a tracker (#6895) that is already closed. The boot-time mapper reopen is fail-open on its two most likely arms — device-absent-after-60s and `TYPE != crypto_LUKS` both `exit 0` — so a host whose store silently fell back to a root-filesystem directory keeps emitting a healthy heartbeat. (The issue's wording, "exits 0 on every failure arm", is overbroad and is corrected here: the empty-`REGISTRY_LUKS_KEY` arm inside the `doppler run` heredoc exits 1, and the script sets no `-e` but ends on that command, so its status propagates and the oneshot unit fails. That is a host-local signal with no off-box reader, which is the same gap by a different route.)

This plan adds five point-in-time device-binding fields to the trusted region of that heartbeat (mirroring the inngest probe's `data_mount_devid` resolution and git-data's `luks_mounted=`), re-anchors and re-words the ledger row so it names the emitter and the runner-reachable Better Stack read, and adds a follow-through probe that closes the loop once a real boot's row is observed carrying the expected volume alias with `store_luks=yes` AND the committed ledger has been flipped to `available` on that evidence. Delivery of the cloud-init change to the host rides the registry-host-replace dispatcher, which is dead until #8361 (PR #8362) repairs the apply workflow; the PR merges behind that delivery watermark and the follow-through probe is what turns "merged" into "observed".

**What this PR does NOT do, deliberately:** it does not flip `live_verification` to `available` (that string is what the Layer A floor counts, and ADR-141 defines it as "a HOST probe exists" — at merge the host does not run the emitter and #8361 has no ETA), and it does not touch `.github/workflows/apply-web-platform-infra.yml` (513,306 B, over GitHub's 512,000 B limit; a parallel session is shrinking it).

## Research Reconciliation — Spec vs. Codebase

| Issue / brief claim | Codebase reality (verified 2026-09-19) | Plan response |
|---|---|---|
| "add store_mount_src / store_mount_devid / store_luks" (three fields) | The follow-through sweeper runner has no Hetzner token and no Terraform-state access (`.github/workflows/scheduled-followthrough-sweeper.yml` env map: GH_TOKEN, SENTRY_ACTIONS_RO_TOKEN, WEBHOOK_DEPLOY_SECRET, CF_ACCESS_*, BETTERSTACK_QUERY_*, BETTERSTACK_API_TOKEN, GIT_DATA_BETTERSTACK_LOGS_TOKEN, SUPABASE_ACCESS_TOKEN). `hcloud_volume.registry.id` lives only in state and in the rendered template (`registry_volume_id = hcloud_volume.registry.id` in `zot-registry.tf`; `DEV=/dev/disk/by-id/scsi-0HC_Volume_${registry_volume_id}` in `registry-luks-open.sh`). | Emit FOUR fields: the three asked for, plus `store_expected_devid` (the Terraform-rendered alias) so the runner can compare measured vs declared inside one row. A fifth, `store_mount_base`, is computed but NOT emitted — plan review found it carried no property and no probe consumer, and its sentinels already mirror into `store_mount_devid`. Technical fork, not an operator question (`hr-technical-fork-is-not-an-operator-question`). |
| "flip the ledger row's live_verification to available … add the row to the Layer A live_coverage_floor" | `LIVE_VERIFICATION_RE = ^(available\|unavailable:.+)$` — `available` is a bare exact string; `check_live_coverage_floor` counts it; ADR-141 §Context 2 defines it as "a HOST probe exists". The sibling row `hcloud_volume.inngest_redis_luks` records the discipline: "The mechanism flips … in the follow-up commit that records an OBSERVED cutover boot, never before". | Rewrite the row's `unavailable:` reason to name the merged emitter, the probe, the delivery dependency and the flip criterion. The flip + `live_coverage_floor: 2` is a follow-up one-line PR gated by the probe's ACTION REQUIRED branch (exit 5) — it cannot rot, because #8386 cannot close until the ledger reads `available`. |
| "Extend the trusted-region consumers (zot_trusted_region() callers)" | `zot_trusted_region()` is `sort \| sed 's/ zot_last_err=.*//'` — anything before the first ` zot_last_err=` is trusted by construction. No consumer parses a fixed field list; `registry-boot-guard.test.sh` pins field PRESENCE on the `LINE=` assignment and that `zot_last_err` is last. | No parser change. Extend the boot-guard's field-presence loop with the five names and raise `MIN_ASSERTIONS` in lockstep. |
| "the dispatcher delivers it on the next run after #8361" | `registry-host-replace-dispatch.yml` fires only on a `main` push touching `apps/web-platform/infra/cloud-init-registry.yml` (or itself) or on `workflow_dispatch`. Its base is the last SUCCESSFUL dispatcher run's head (`gh run list --workflow=… --status success`, currently `f5ad46390`, 2026-09-18); the 2026-09-19 push run (`47f9654e2`) FAILED because the apply is `startup_failure`. After #8362 merges NOTHING fires the dispatcher unless a push touches the template. | The watermark makes this change lossless (a failed run never advances it) but not self-delivering. The delivery step is a `gh workflow run registry-host-replace-dispatch.yml -f reason=… -f tracker=8386` re-fire after #8361 closes — automatable, deferred, and surfaced by the probe: when `apply-web-platform-infra.yml` on the sweeper's checkout of main is under 512,000 B and no row on the newest boot carries `store_luks=`, the probe exits 5 ACTION REQUIRED naming that exact command. Phase 5 also posts the re-fire request as a comment on #8361. |
| "registry-luks-open.sh exits 0 on every failure arm, so after any host replace the store could be a plaintext directory" | **Partly false, corrected.** Two arms `exit 0` (device absent after the 60s wait; `TYPE != crypto_LUKS`); the empty-`REGISTRY_LUKS_KEY` arm inside the heredoc exits 1 and, because the script sets no `-e` and that `doppler run` is its last command, the status propagates and the oneshot unit fails. No off-box reader sees that unit state, so the conclusion survives the correction. And it is worse than a replace: `docker run … --restart unless-stopped -v /var/lib/zot:/var/lib/zot` re-launches zot on ANY reboot with whatever `/var/lib/zot` is; the `findmnt … grep -qx /dev/mapper/registry \|\| exit 1` launch gate is a runcmd entry (first boot only). The NIC guard's 5-min self-heal reopens the mapper and `docker restart`s zot when the mount lands, so the window is bounded but real. | The emitter makes this window VISIBLE off-box (`store_luks=absent`, `store_mount_src=__NOMOUNT__`). Closing the window itself (a launch-time mount gate that survives reboot) is a non-goal here — tracked in the deferral issue with the standing alert. |
| "#6895 — registry-host posture emitter" is a #6923 blocker "that will never flip" | #6895 is CLOSED by PR #6926 (the `registry_luks_recut` delivery); #6923's arm check reads "a new emitter should flip a ledger row's live_verification to available". | Phase 5 comments on #6923 that the #6895 blocker line is superseded by #8386 and that its arm criterion (a row flipped to `available`) is satisfied by the flip commit, not by this merge. #6923's body is NOT edited. |
| Ledger evidence `apps/web-platform/infra/cloud-init-registry.yml:773,778 … fstab: cloud-init-registry.yml:804` | Those line numbers point at unrelated bytes today; the anchors are the `cryptsetup luksFormat --batch-mode --type luks2 --key-file - "$DEV"` and `cryptsetup luksOpen --key-file - "$DEV" registry` calls and the `/dev/mapper/registry /var/lib/zot ext4 defaults,nofail 0 2` fstab line. `lint-encryption-posture.py` does not reject line-number citations; `cq-cite-content-anchor-not-line-number` does. | Re-anchor the evidence on content in the same row edit. The correction note must NOT restate the old literal (AC-L2 greps the row for a `.yml:<digits>` shape). |

## Research Insights

### Premise Validation (Phase 0.6)

- #8386 OPEN, no closing PR. #8361 OPEN (PR #8362 OPEN, "bring apply-web-platform-infra.yml under GitHub's 512,000-byte workflow-file limit"). #6895 CLOSED by #6926. #6923 OPEN. #6894 OPEN. #8017 CLOSED by #8314. #7500 CLOSED by #7954. #7456 OPEN (root-fs LUKS exception, expires 2027-02-11).
- `git grep -nE 'SOLEUR_ZOT_(LUKS|POSTURE)|store_mount_src|store_mount_devid|store_luks' origin/main -- apps/web-platform/infra/cloud-init-registry.yml` → no matches: the emitter is genuinely absent (build, not fix).
- ADR corpus grep for the mechanism (`live_verification`, `posture emitter`, `at-rest posture probe`): ADR-141 (Layer B deferred until an emitter lands; `live_coverage_floor`), ADR-140 (ledger as design-time default), ADR-142 (inngest additive cutover + `data_mount_devid`), ADR-211 (`zot_last_err` redaction; trusted region), ADR-117 (unconditional emit), ADR-199 (measured, not remembered). None rejects this mechanism; ADR-141 names it as the arm trigger.
- Measured on the planning host (util-linux findmnt; cryptsetup 2.8.7): `findmnt -no SOURCE <non-mountpoint>` prints nothing and exits 1; `findmnt -no SOURCE /` prints the source and exits 0. `cryptsetup status <name>` as non-root exits 1 ("Cannot initialize device-mapper") — the cron runs as root under `doppler run`, so rc=1 there is a genuine measurement fault, never posture. `man cryptsetup` RETURN CODES: 1 wrong parameters, 2 no permission, 3 out of memory, 4 wrong device specified, 5 device already exists or busy. Binary locations on the shipped image class: `/usr/bin/findmnt`, `/usr/bin/lsblk`, `/usr/sbin/blkid`, `/usr/sbin/cryptsetup` — hence the PATH append.
- `bash apps/web-platform/infra/registry-userdata-budget.sh` → stored 14,180 B, cap 32,768 B, headroom 18,588 B.
- `bash plugins/soleur/test/c4-count-parity.test.sh` → ALL TESTS PASSED. That is a PRE-CHANGE baseline, not evidence that no count moves; AC-R2 re-runs it after the edit, and that run is the gate.

### Property List (Phase 0.6b)

- P1. An off-box reader can tell, from the newest heartbeat row alone, what block device backs `/var/lib/zot` and whether that device is a LUKS container on the Terraform-declared volume.
- P2. A plaintext store (root-fs directory, raw ext4 mount, mapper over the wrong volume) is distinguishable from a measurement fault (a command that failed or timed out), on every row — AND, when the volume alias cannot be resolved (`__NOMATCH__`), the row still names the backing device, so "failed open onto the root disk" and "attached to some other volume" are separable from a single event without a second delivery.
- P3. Adding the measurement cannot dark the heartbeat: every path still emits one `SOLEUR_ZOT_DISK` row and exits 0.
- P4. A crafted `zot_last_err` tail cannot forge any posture field (they sit in the trusted region).
- P5. The ledger row for `hcloud_volume.registry` never asserts a live verification the host has not performed, and cannot stay `unavailable` after the host has performed it without a daily, actionable nag.
- P6. #8386 closes only when the newest real boot has been observed encrypted on the expected volume AND the ledger says so.

### Cut List (Phase 0.6b)

| Mechanism proposed | Property | Disposition |
|---|---|---|
| A new schema/revision field (`posture_schema=1`) as the delivery-proof token, mirroring `err_redact_rev` | P6 (delivery proof) | CUT — the presence of `store_luks=` in the trusted region IS the proof; a second token is a second carrier for one fact. |
| A new trusted-region parser or a change to `scripts/lib/zot-telemetry-parse.sh` | P4 | CUT — `zot_trusted_region` already bounds everything before the first ` zot_last_err=` (grepped the definer). |
| `store_mount_base` emitted as a peer field | P2's discrimination half | CUT then REINSTATED as `store_backing_dev`. The cut was made on "no property, no probe consumer"; the observability review showed the property exists (the `__NOMATCH__` discrimination the inngest sibling's comment records) and that the probe is not the only consumer — a human diagnosing a FAIL is. Reinstated as the backing device rather than the base, which is strictly more informative and covers the partitioned case. |
| `store_mount_src` alone as the mount signal | P1 | KEPT but note the partial overlap with `SOLEUR_PRIVATE_NIC zot_store_mounted=` (a `mountpoint -q` boolean on the other stream): that field cannot name the device or say LUKS, so it does not cover P1. |
| A standing Better Stack `logtail_exploration_alert` on `store_luks != yes` (mirror of `inngest_luks_wrong_volume`) | standing detection after #8386 closes | DEFERRED with a tracking issue — it needs `-target=` lines in `apply-web-platform-infra.yml` (the 513,306 B file a parallel session is shrinking). Interim: the sweeper while #8386 is open, then #6923 Layer B. |
| A third verdict stream in `scripts/zot-restart-loop-alarm.sh` | standing detection | CUT — 600+ line security-sensitive alarm (2026-09-08 learning); standing consumer is #6923 by design. |
| Sharing the lsblk/by-id block as a file injected into both templates | reuse | CUT — different delivery substrates (user_data templatefile with a rationale strip vs an OCI-shipped bootstrap); ~60 lines are copied with the invariants restated. |
| Extending the `zline()` fixture in `scripts/zot-restart-loop-alarm.test.sh` | fixture fidelity | CUT — that fixture already omits ~15 producer fields and the alarm reads none of the new ones; the new suites carry producer-shaped rows. |

### Relevant files (content-anchored)

- `apps/web-platform/infra/cloud-init-registry.yml` — write_files `- path: /usr/local/bin/zot-disk-heartbeat.sh` (`set -u`; `LINE="SOLEUR_ZOT_DISK … host=$(hostname) zot_last_err=$ZOT_LAST_ERR"`; `post || post || echo … FAILED`; `exit 0`); `- path: /usr/local/bin/registry-luks-open.sh` (`DEV=/dev/disk/by-id/scsi-0HC_Volume_${registry_volume_id}`); the runcmd LUKS block (`case "$TYPE" in "") … luksFormat`, `crypto_LUKS) : ;;`); the zot launch gate (`findmnt -no SOURCE /var/lib/zot | grep -qx /dev/mapper/registry || … exit 1`); the NIC guard's store-mount self-heal (`ZOT_STORE_MOUNTED=false` … `docker restart zot`).
- `apps/web-platform/infra/inngest-bootstrap.sh` — `probe_schema=8`; the `data_mount_src` / `data_mount_base` / `data_mount_devid` block (`lsblk -inso NAME`, the leaf-counting awk, `for _alias in "$byid_dir"/scsi-0HC_Volume_*`, `_devid_hits`, the whitespace charset guard). This is the code to copy.
- `apps/web-platform/infra/luks-monitor.sh` — the LUKS discriminator chain (`findmnt -no SOURCE "$MOUNT"`, `cryptsetup status "$MAPPER_NAME"`, `device:` line, `blkid -s TYPE -o value "$real_dev"` = `crypto_LUKS`).
- `apps/web-platform/infra/zot-disk-heartbeat-redaction.test.sh` — the harness template: `extract_block()` pulls the write_files block, applies `local.registry_rationale_strip`, asserts valid bash, runs under PATH stubs (`docker`, `curl` capturing `--data-raw`, `df`, `hostname`, `htpasswd`), `run_hb()`; anti-vacuity floor.
- `apps/web-platform/infra/registry-boot-guard.test.sh` — `LINE_ASSIGN="$(grep -F 'LINE="SOLEUR_ZOT_DISK' "$CI" | head -1)"`, the `for f in pcent= … htpasswd_push_matches=; do` presence loop, `zot_last_err is the LAST field`, `MIN_ASSERTIONS=105`.
- `scripts/lib/zot-telemetry-parse.sh` — `zot_envelope_anchor`, `zot_trusted_region`, `zot_newest_boot`, `zot_scope_to_boot`.
- `scripts/followthroughs/zot-last-err-redact-7500.sh` + `.test.sh` — the probe template (xtrace refusal, secret preflight, `--limit 5000`, envelope anchor, double decode with `dt` carried, trusted cut, `NEWEST_BOOT` character class, one-pass awk, integer guard, decision table, exit 0/1/2/3) and its harness (`run_probe` copies the probe + lib into a temp root with a stub `betterstack-query.sh`; branch markers pinned, not just exit codes; positive control).
- `scripts/sweep-followthroughs.sh` — verdict map: 0 PASS (close), 1 FAIL (comment), 2 NOT YET, 3 CANNOT ESTABLISH, 5 ACTION REQUIRED, other TRANSIENT; closed-mode reopen on 1 (but an issue the sweeper itself closed on PASS is skipped by `closed_precheck` — the sibling plan measured this, so a PASS is final).
- `scripts/encryption-posture-ledger.json` — `live_coverage_floor: 1`; row `"store": "hcloud_volume.registry"`; sibling rows `hcloud_volume.inngest_redis_luks` (observed-boot flip discipline) and `hcloud_volume.workspaces_luks` (`"live_verification": "available"`).
- `scripts/lint-encryption-posture.py` — `LIVE_VERIFICATION_RE`, `check_live_coverage_floor` (MB-13), `_validate_store` (extra keys tolerated; no line-number check).
- `.github/workflows/registry-host-replace-dispatch.yml` — `on.push.paths`, the watermark lookup (`gh run list --workflow="$SELF" --branch main --status success`), `workflow_dispatch` inputs `reason` + `tracker`, the poll (`exit 1` on a non-success apply conclusion).
- `.github/workflows/infra-validation.yml` — `run: bash apps/web-platform/infra/zot-disk-heartbeat-redaction.test.sh` (single-line `run:` registration is required; a multi-line block de-registers the suite).
- `scripts/test-all.sh` — `run_suite "scripts/zot-last-err-redact-7500" bash scripts/followthroughs/zot-last-err-redact-7500.test.sh` (followthrough suites are registered by hand; `scripts/lint-orphan-test-suites.sh` reddens an unregistered one).
- `knowledge-base/engineering/architecture/diagrams/model.c4` — `zotRegistry -> betterstack "Ships disk-state observability — df% of /var/lib/zot + resize2fs before/after + zot health — as one SOLEUR_ZOT_DISK event …"`.
- `knowledge-base/engineering/architecture/decisions/ADR-141-…md` — `## Amendment — <date> (#N)` convention (ADR-140/142/149 carry such sections).

### Institutional learnings applied

- `knowledge-base/project/learnings/2026-09-08-every-field-my-alarm-trusted-came-from-the-region-it-did-not-trust.md` — every verdict field read from the head, cut at the FIRST ` zot_last_err=`; anchored patterns, never greedy.
- `knowledge-base/project/learnings/2026-09-10-every-instrument-i-verified-was-verified-inside-its-own-blind-spot.md` — the lsblk walk must COUNT leaves (`__AMBIGUOUS__` on forks); the suite carries the forked and the partitioned fixtures.
- `knowledge-base/project/learnings/2026-08-17-an-empty-read-is-three-states-and-my-guard-shipped-two-fail-opens.md` — query failed / answered-empty / answered-with-rows are three states; the probe never passes on absence.
- `knowledge-base/project/learnings/2026-08-11-my-fixture-shared-the-bug-so-the-test-could-not-see-it.md` — probe fixtures carry the producer's real envelope (`{"dt":…,"raw":"{\"message\":\"SOLEUR_ZOT_DISK …\"}"}`) and every field the probe reads.
- `knowledge-base/project/learnings/2026-07-24-guest-luks-store-must-gate-consumer-on-mount-and-guard-suite-must-pin-fail-loud-semantics.md` — the reboot fallback exists; this plan makes it visible and defers closing it.
- `knowledge-base/project/learnings/2026-07-16-refuting-a-hypothesis-by-reasoning-while-its-discriminator-is-invisible.md` — the ledger's `luks` claim rests on one job log; this plan builds the discriminator rather than re-asserting the claim.
- `knowledge-base/project/learnings/2026-05-12-plan-time-parsing-pattern-needs-codebase-precedent-grep.md` — every shell shape below is copied from a named precedent, not invented.

### CLAUDE.md conventions

`hr-verify-repo-capability-claim-before-assert` (every "the runner cannot X" above names the file grepped); `cq-cite-content-anchor-not-line-number` (the ledger fix and every anchor in this plan); `cq-test-fixtures-synthesized-only` (all boot ids, aliases and tokens in fixtures are fabricated); `hr-observability-as-plan-quality-gate` / `hr-no-ssh-fallback-in-runbooks` (no SSH anywhere; the discoverability command is hermetic); `wg-use-closes-n-in-pr-body-not-title-to` + the ops-remediation sharp edge (`Ref #8386`, never `Closes`); `hr-technical-fork-is-not-an-operator-question` (the two extra fields).

## Open Code-Review Overlap

- #7942 (Two mutation batteries in plugins/soleur/test/ are named *.mutation.sh and run in no gate) touches `scripts/test-all.sh` and `.github/workflows/infra-validation.yml`. **Acknowledge:** a different concern (mutation-battery naming); this plan adds two `run:`/`run_suite` registrations and does not touch the `*.mutation.sh` set. The scope-out remains open.

## Problem Statement

`scripts/encryption-posture-ledger.json` says `hcloud_volume.registry` is LUKS and that live verification is unavailable pending a tracker that closed a month ago without an emitter. The only host-side facts about the store that leave the host are `pcent`/`fs_size_gb` (a filesystem exists somewhere) and `SOLEUR_PRIVATE_NIC zot_store_mounted=true|false` (a `mountpoint -q` boolean). Neither names the device, and neither says LUKS. The fstab `nofail` line is fail-open by design (a reboot must not wedge) and so are the reopen unit's device-absent and non-LUKS arms; its empty-key arm does fail the unit, but no reader outside the host sees a `systemd` unit state. Meanwhile zot's `--restart unless-stopped` re-binds whatever directory is there. So the claim "OCI blobs + cosign signatures are unreadable without the Doppler-held LUKS passphrase" is asserted by a record and verified by nothing that runs.

## Proposed Solution

### 1. Emitter contract (cloud-init-registry.yml, `zot-disk-heartbeat.sh`)

FIVE fields, inserted into the `LINE=` assembly immediately before `host=$(hostname)` (so all five are inside the trusted region and `zot_last_err` stays last).

**On the fifth field, because it was cut and then reinstated on a better argument.** Plan review cut `store_mount_base` as a second carrier — no property in the list, no probe verdict reading it, sentinels already mirrored into `store_mount_devid`. The observability review overturned that with the sibling's own recorded rationale: on the `__NOMATCH__` path the base is *"the only field naming the backing kernel device, which separates 'failed open onto the root disk' from 'attached to some other volume'"* (`inngest-bootstrap.sh`, the `__UNREADABLE__` arm's comment). That is a real discrimination, and on a blind surface with one-shot delivery it is exactly what `hr-observability-as-plan-quality-gate`'s affected-surface clause requires — structured fields that separate every competing root cause in ONE event. So the field returns, but as **`store_backing_dev`** rather than `store_mount_base`: it carries the device the `yes` verdict actually rests on (the `cryptsetup status` `device:` line on a mapper mount; the resolved base on a non-mapper mount), which the base alone does not name on the partitioned case, and which nothing else in the row carries. `STORE_MOUNT_BASE` stays an unemitted shell variable feeding the devid reverse map. Every variable is bound to its default at the top of the measurement block, before any command; every command is `timeout 5`-bounded (P3 — the script runs `set -u` and its absence is itself an alarm).

**A `PATH` append goes at the TOP of the script, beside `set -u` — not mid-file — as a LITERAL: `PATH="$PATH:/usr/sbin:/sbin"`.**

**No runtime env seam, and this is a security constraint rather than a style one.** The cron line is `*/5 * * * * root … doppler run --project soleur-registry --config prd -- /usr/local/bin/zot-disk-heartbeat.sh`, and `doppler run` injects EVERY secret in that config as an environment variable. So an env-overridable `ZOT_SBIN_DIRS="$${ZOT_SBIN_DIRS:-…}"` would let anyone who can write a secret into `soleur-registry/prd` append a directory to root's `PATH` — and because cron's own `PATH` (`/usr/bin:/bin`) contains neither `cryptsetup` nor `blkid`, that directory would win the FIRST resolution of both. Root code execution every five minutes, from a config-store write. The same argument retires `ZOT_BYID_DIR`: steering the by-id reverse map lets a config write make `store_mount_devid` match `store_expected_devid` on any host. Both seams are therefore **render-time**, not runtime: the suite already extracts the script to a temp file and applies the template `sed` lines, so it substitutes `/usr/sbin:/sbin` → `$BIN/sbin` and the by-id glob root → `$TMP/by-id` there. (The inngest sibling's `PROBE_BYID_DIR`/`PROBE_DATA_MOUNT` runtime seams are the same class; noting it, not widening scope to fix it here.) The append still needs pinning or it could be deleted at green — the render-time substitution is what lets the suite do that. A one-line comment on the `/etc/cron.d/zot-disk-heartbeat` block points here, because this template now carries a THIRD cron-PATH model and the next reader must not have to discover that. Measured on the planning host, and independently corroborated in-repo for `blkid` only (`cloud-init-inngest.yml` and `cloud-init-git-data.yml` both hardcode `/usr/sbin/blkid`; nothing in the repo pins `cryptsetup`, `findmnt` or `lsblk`): `cryptsetup` and `blkid` resolve under `/usr/sbin`, `findmnt`/`lsblk` under `/usr/bin`. The plan does NOT depend on that split being exactly right on Ubuntu 24.04 — the append adds both `sbin` dirs and keeps the inherited `PATH`, so it is correct under either layout; what it depends on is the append existing at all. And `/etc/cron.d/zot-disk-heartbeat`'s `*/5 * * * * root … doppler run … zot-disk-heartbeat.sh` line sets NO `PATH` — unlike its two siblings in the same template (`zot-log-shipper` and the NIC guard both pin `PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin`, the second recording that "two committed models of cron's PATH contradict each other here and nothing asserted either"). Under cron's narrow model both LUKS discriminators return 127 and every row would read `store_luks=unknown` forever — an R2 FAIL that costs a second host replace to correct, behind a dispatcher that is dead. APPEND so the suite's `PATH="$BIN:$PATH"` stubs still win; absolute paths would silently defeat the harness.

**Exit codes are captured, not discarded.** `|| true` clobbers the rc the `__NOMOUNT__`/`unknown` arms discriminate on, so each measurement uses `rc=0; out=$(timeout 5 <cmd> 2>/dev/null) || rc=$?` (safe under `set -u`; this script sets no `-e`), then branches on `$rc` AND `$out`.

| Field | Source | Values |
|---|---|---|
| `store_mount_src` | `timeout 5 findmnt -no SOURCE /var/lib/zot \| head -1` (exact target, no `-T`). **This shape is NEW, not copied:** `inngest-bootstrap.sh` uses `… \| head -1 \|\| true` with no rc capture and no `__NOMOUNT__` arm, so the rc-discriminating form below has no precedent in-repo and is stated as an original design rather than an inherited one. `head -1` is retained from the precedent — a stacked mount otherwise yields a two-line value the charset guard would downgrade to `__UNREADABLE__` instead of reading the top mount. | the source (e.g. `/dev/mapper/registry`, `/dev/sdb`); `__NOMOUNT__` when findmnt exits 1 with empty output (measured: not a mountpoint); `__UNREADABLE__` on any other rc, on empty output with rc 0, or when the output contains a byte outside `[A-Za-z0-9_./:-]` (the row is POSTed unescaped inside `{"message":"…"}`; a bracketed bind-mount source `X[/sub]` is a shape this emitter does not decode and says so). |

| `store_mount_devid` | reverse map of base over the LITERAL `/dev/disk/by-id/scsi-0HC_Volume_*` (the suite substitutes that root at render time; NOT env-overridable — see the security note in §1), counting hits | `scsi-0HC_Volume_<id>`; `__NOMATCH__` (0 hits); `__AMBIGUOUS__` (>1 hit or base ambiguous); `__UNREADABLE__` (base unreadable or whitespace in the result); `n/a` when src is a sentinel. |
| `store_backing_dev` | the `device:` line of the same `cryptsetup status` call (`sed -n 's/^[[:space:]]*device:[[:space:]]*//p' \| head -1`) on a mapper mount; `$STORE_MOUNT_SRC` itself when the mount is a plain block device | the device path the LUKS verdict was taken against (`/dev/sdb1`, `/dev/sdb`); `__UNREADABLE__` when cryptsetup exited 0 with a LUKS `type:` line but no `device:` line; `n/a` when src is a sentinel. **This is the field that separates "failed open onto the root disk" from "attached to some other volume" on the `__NOMATCH__` path** — nothing else in the row names it. |
| `store_expected_devid` | the Terraform-rendered literal `scsi-0HC_Volume_${registry_volume_id}` (single `$` — templatefile interpolation, the same var `registry-luks-open.sh` uses) | always present; the probe requires it to match `^scsi-0HC_Volume_[0-9]+$`. |
| `store_luks` | the luks-monitor chain | `absent` — src is `__NOMOUNT__` (the store is a root-fs directory); `yes` — src is `/dev/mapper/<name>` AND `timeout 5 cryptsetup status "<name>"` exits 0 with a `type:` line containing `LUKS` AND `timeout 5 blkid -o value -s TYPE "$STORE_BACKING_DEV"` prints `crypto_LUKS`, where `STORE_BACKING_DEV` is the `device:` line of that same `cryptsetup status` output (`sed -n 's/^[[:space:]]*device:[[:space:]]*//p' | head -1`), exactly as `luks-monitor.sh` derives `real_dev`; `no` — src is a block device that is not a mapper, OR cryptsetup exits 0 without a LUKS `type:` line, OR (cryptsetup exits 4 — documented "wrong device specified", i.e. a device-mapper node that is not a crypt mapping — AND blkid prints a non-empty type), OR blkid prints a non-empty type other than `crypto_LUKS`; `unknown` — src is `__UNREADABLE__`, base is a sentinel, cryptsetup exits with any other code (1 = wrong parameters, which is also what a non-root run returns; 2 = no permission; 3 = out of memory; 5 = busy; 124 = timeout; 127 = absent), rc 4 with blkid silent, or blkid prints nothing. **The positive plaintext verdict always rests on blkid's answer about the BASE device, never on a cryptsetup exit code alone** — an exit code says the tool refused, a blkid type says what the bytes are. |

**The blkid read targets the cryptsetup-reported BACKING device (`$STORE_BACKING_DEV`), never `/dev/$STORE_MOUNT_BASE`.** `STORE_MOUNT_BASE` is the base DISK (the `lsblk -s` leaf), so on a partitioned volume — a shape Phase 1 fixtures explicitly (`registry` → `sdb1` → `sdb`) — the `crypto_LUKS` signature lives on `sdb1` and `blkid /dev/sdb` prints a partition-table type or nothing. That would read `unknown`/`no` on a correctly encrypted store. Base stays the input to the devid reverse map (the by-id aliases name the DISK); the LUKS signature question is asked of the device cryptsetup itself names. If the `device:` line is unreadable while cryptsetup exited 0 with a LUKS `type:` line, the value is `unknown`, never `yes`.

**The row-length ceiling is derived at Phase 0.8, never invented.** Measured offline at plan time: the current `LINE=` assignment is 876 bytes of template text, 848 of it ahead of ` zot_last_err=`, with 26 unexpanded `$VAR` references — so the live trusted region's real length is not derivable from the template alone, and Better Stack's per-message limit is not derivable from this repo at all. Phase 0.8 reads one live row and records both numbers; the suite's ceiling is (measured limit − measured current length), and if the limit cannot be established the suite asserts only that the four fields are present and ahead of the tail. A ceiling picked from nothing would be a guard whose number means nothing, on the failure mode with the worst recovery (a rejected payload darks the heartbeat, which is itself the alarm, and costs a second replace).

Rules restated from the siblings. The first three are each traced to a measured production break in `0d97ede5c` (#8019 / #8017, probe_schema=8) and the 2026-09-10 learning; (d)-(f) are restated because they are cheap to get wrong here, NOT because each has its own recorded incident — the earlier draft claimed "each was wrong once before" for all six and only three carry that provenance. (a) `lsblk -inso` — `-i` ASCII glyphs, `-s` inverse tree, NO `-d`, count leaves not max-depth nodes; (b) the by-id walk is scoped to the Hetzner namespace and COUNTS; (c) the emit is unconditional — no `if` before `LINE=`; (d) templatefile escaping: every shell `${…}` in the copied block becomes `$${…}`, every `%{` would become `%%{` (none is used), bare `$0`/`$1`/`$(…)` are safe; (e) `cryptsetup` output is matched on its `type:` line, never on the exit code alone; (f) values are single space-free tokens — a whitespace guard maps anything else to `__UNREADABLE__`.

**Scoped out, deliberately: escrow recoverability.** `luks-monitor.sh` — the workspaces probe, the one store whose row reads `available` today — runs FIVE steps, and this emitter copies only the first three (mount → mapper → `crypto_LUKS` on the backing device). Its step 4 reads the passphrase (`doppler secrets get WORKSPACES_LUKS_KEY --plain --config prd_workspaces_luks`) and re-tests it with `cryptsetup luksOpen --test-passphrase`, and its step 5 asserts the header UUID resolves. So what `store_luks=yes` will mean here is precisely **"the store is on a LUKS device"** — NOT "we can still unlock it" and NOT "the header is intact". A registry host whose Doppler-held `REGISTRY_LUKS_KEY` had drifted, or whose header was damaged, would report `store_luks=yes` right up until the next replace failed to reopen the mapper. Not folded in because: the escrow re-test is a per-tick `doppler secrets get` of a passphrase on a 5-min cron (the workspaces probe runs DAILY for that reason), and a `--test-passphrase` against the live mapper's backing device on every tick is a different risk posture than a read-only `status`. The ledger's `live_verification` text and the ADR-141 amendment both state this scope explicitly, so nobody reads `available` as escrow assurance; widening it to the workspaces shape is named in the deferral issue with the daily-cadence question attached.

### 2. Ledger row (`scripts/encryption-posture-ledger.json`, `hcloud_volume.registry`)

- `evidence`: content-anchored — the `cryptsetup luksFormat --batch-mode --type luks2 --key-file - "$DEV"` and `cryptsetup luksOpen --key-file - "$DEV" registry` calls in the runcmd LUKS block, the `/dev/mapper/registry /var/lib/zot ext4 defaults,nofail 0 2` fstab line, the `registry-luks-open.sh` write_files block; key: `random_password.registry_luks` + `doppler_secret.registry_luks_key` (`zot-registry.tf`). Plus a `CORRECTED 2026-09-19 (#8386)` clause saying the previous citation was line-numbered and that the record does not repeat it.
- `live_verification`: `unavailable:` + a reason of this shape — "the host-side emitter EXISTS in code since #8386 (SOLEUR_ZOT_DISK trusted-region fields store_mount_src / store_mount_base / store_mount_devid / store_expected_devid / store_luks, readable off-box via scripts/betterstack-query.sh --grep SOLEUR_ZOT_DISK) but has NOT been observed on a boot: the change is inert until a registry-host-replace, which is dead while #8361 holds the apply workflow over GitHub's 512,000 B limit and, once repaired, needs a workflow_dispatch re-fire. Flip to `available` (and live_coverage_floor to 2) ONLY in the commit that records the observed boot — scripts/followthroughs/registry-luks-live-8386.sh exits 5 ACTION REQUIRED with that instruction the day a real boot's row reads store_luks=yes on the expected volume. Tracked #8386."
- `live_coverage_floor` unchanged at 1.
- One honesty note in the row: `disclosed_as: not-publicly-claimed` is **asserted, not linted**, for a `luks` row — `check_at_rest` hands a `luks` mechanism to `check_luks_row`, which returns before `check_disclosed_as_not_encrypted` runs. Nothing guards the claim, and a grep of `docs/legal/**` and the Article 30 register found no registry-volume at-rest claim today, so the lagging ledger opens no live compliance window; the note exists so the next editor knows the field is unguarded.

### 3. Follow-through probe (`scripts/followthroughs/registry-luks-live-8386.sh`)

Template: `zot-last-err-redact-7500.sh` (xtrace refusal, secret preflight, `--since "${SOLEUR_FT_WINDOW:-24h}" --grep SOLEUR_ZOT_DISK --limit "${SOLEUR_FT_LIMIT:-5000}"`, envelope anchor, double decode with `dt` sorted, `NEWEST_BOOT` via the `[0-9a-fA-F-]+` class, one awk pass over the head only). It emits counts, verdict tokens and boot ids only — never row text — because the sweeper posts its output on a public issue. **And on the FAIL verdicts (V1/V4) it withholds the volume alias and `store_mount_src` too**: "named Hetzner volume X is mounted unencrypted right now" on a public tracker is an advertisement, and the rule "never row text" does not by itself cover the verdict PROSE. Those verdicts name the branch marker and which disjunct fired, and point at the private Better Stack read for the detail.

**Secrets: the Better Stack three, and nothing else.** An earlier draft split the undelivered verdict three ways using `gh run list --workflow=registry-host-replace-dispatch.yml`. That is unreachable: `.github/workflows/scheduled-followthrough-sweeper.yml` declares `permissions: contents: read` + `issues: write` and `GH_TOKEN` is `secrets.GITHUB_TOKEN`, so an Actions-runs query 403s and every delivery state would collapse into one degraded message anyway. Widening a deliberately read-only sweeper's permissions to enrich three comment texts that read identically is not worth it, so the split is deleted rather than fixed: ONE undelivered verdict, whose message names the apply-file byte count and the re-fire command and points at the Actions tab for the run history.

**Guard chain (prose, in order — each exits with its own branch marker, none is a verdict).** Secret unset → 2. Query non-zero → 2 (channel or auth). Zero rows → 2 `channel_dark`. No row carries the direct-POST envelope prefix → 2. Decode failure → 2. Host filter (`host=soleur-registry `) leaves zero rows while the marker matched some → 2. No usable `boot_id` → 3. **The newest surviving row's `dt` is more than 30 minutes old (six missed ticks) → 3 `producer_silent`** — a host that WAS emitting and stopped is otherwise indistinguishable from a dark warehouse once the window rolls past its last row. The awk pass produced no integers → 3.

**Host scoping precedes boot selection**, as defence in depth: `zot_envelope_anchor` already admits only the direct-POST producer envelope, so a second host would have to emit a producer-shaped row to contaminate the set — not a shape production emits today. The filter costs one `grep -F` and removes the class the 7500 probe records as a known open gap.

**Counts on the newest boot** (head only): `D` rows carrying `store_luks=`, `Y` rows reading `store_luks=yes`, `P` rows reading `store_luks=no`.

`P` counts `no` — a store MOUNTED from something that is not a LUKS container — and deliberately NOT `absent`. The store mounts through a `nofail` fstab line plus the `registry-luks-open.service` oneshot, so the first tick or two of a legitimate boot can land before the mount and read `absent`; counting that as permanent plaintext would FAIL every correct replace. `no` is never explainable by a boot race. `P` is kept rather than folded into the newest-row check (one reviewer proposed that) because the two are not equivalent: a boot that reads `no` for hours and then recovers has a `yes` newest row, and only `P` remembers the window. Residual, stated rather than hidden: `absent` ON THE NEWEST ROW is still V4, so a sweep landing inside the post-replace mount race posts one FAIL on a correct boot — rare, self-correcting on the next sweep, and fail-loud in the safe direction.

**Verdict table — evaluated top to bottom, and the order is load-bearing.**

| # | Condition | Exit | Sweeper heading |
|---|---|---|---|
| V1 | `P > 0` | 1 | FAIL — the store was measured mounted and not LUKS on this boot. **First, deliberately:** a real plaintext reading must not be suppressed by a later arm (a malformed rendered alias, say) that would otherwise grade the same boot CANNOT ESTABLISH. |
| V2 | `D == 0` | 3; **2** if the newest row is under 30 min old and this is the first sweep past `earliest`; **5** once more than 30 days have elapsed since `earliest` | CANNOT ESTABLISH / ACTION REQUIRED — the undelivered family. One state, and the exit encodes the urgency of waiting rather than a different state. The message carries `wc -c` of `.github/workflows/apply-web-platform-infra.yml` in the checkout (or `unreadable` — it is message content, never a branch, so a rename by #8362 cannot change a verdict), whether that is over or under 512,000 B, and the re-fire command `gh workflow run registry-host-replace-dispatch.yml -f reason='deliver #8386 registry posture emitter' -f tracker=8386`. At 30 days: "undelivered for `<N>` days — this is a delivery failure, not a wait." |
| V3 | `D > 0` and the NEWEST row carries no `store_luks=` | 3 | CANNOT ESTABLISH — a partial/truncated producer row. Without this arm the empty value reads `!= yes` and posts a public FAIL for a producer defect. |
| V4 | the newest row's `store_expected_devid` fails `^scsi-0HC_Volume_[0-9]+$`, OR `store_luks != yes`, OR `store_mount_src != /dev/mapper/registry`, OR `store_mount_devid != store_expected_devid` | 1 | FAIL — not measured encrypted on the declared volume. A malformed rendered alias belongs here, not in its own arm: an empty `registry_volume_id` renders `scsi-0HC_Volume_` into `registry-luks-open.sh`'s `DEV` too, so that host genuinely has no opened mapper and FAIL is the true reading. The message names which disjunct fired. |
| V5 | newest row good, `Y < 3` | 3 | CANNOT ESTABLISH — "boot `<id>` too young: `<Y>` of 3 confirming rows". |
| V6 | newest good, `Y >= 3`, ledger reads `other` | 5 | ACTION REQUIRED — "observed boot `<id>` encrypted on `<alias>`; flip `hcloud_volume.registry` live_verification to `available` AND raise `live_coverage_floor` to 2 in a one-line PR, then this closes." |
| V7 | as V6, ledger reads `available` | **5** | ACTION REQUIRED — "evidence complete: boot `<id>` measured encrypted on the declared volume across `<Y>` rows, and the ledger reads `available`. closing #8386 is a reviewed decision, taken after the boot is confirmed in the Better Stack read." **Deliberately NOT exit 0.** Source 2457081 is shared and multi-tenant (`scripts/lib/betterstack-sources.sh` calls it "Shared, multi-tenant, and chatty"): the web hosts and the Inngest node ship to it, a Better Stack source has ONE ingest token, and `host=`/`boot_id` are producer-controlled INSIDE the message while only `dt` is ingest-assigned. Any holder of that token can synthesize three producer-shaped rows on a fresh boot id. That is acceptable authority for "stop waiting, a human should look"; it is not acceptable authority for unattended closure of a security tracker plus a ledger flip to `available`. Exit 0 returns when the emitter moves to a single-tenant source (the `BS_GIT_DATA_SOURCE_ID` pattern) — named in the deferral issue. |

**The ledger read happens only on the V6/V7 path**, after V1-V5 have been excluded — which is what keeps its failure arm from overlapping every other verdict. The reader is a `python3` one-liner printing exactly one of three literals, `available` / `other` / `__UNREADABLE__`; `__UNREADABLE__` (file missing, JSON malformed, no `hcloud_volume.registry` row or no `at_rest.live_verification` key) exits 3, never `other`. "Could not read" and "read, and it is not available" are different states and must not collapse.

`unknown` / `__UNREADABLE__` / `__AMBIGUOUS__` / `__NOMATCH__` on the NEWEST row land in V4 — a confident PASS needs a confident measurement. On earlier rows of the same boot they are ignored (measurement faults are transient).

**V6 requires TWO things, not three.** An earlier draft also required the flip PR to land the standing Better Stack alert; that made the honest-record property (P5) hostage to the alert's own blocker — the alert needs `-target=` lines in the over-limit apply workflow, so if that file is still over the limit when the boot is observed, the ledger could never be corrected. The standing watcher is therefore the deferral issue's own follow-through, enrolled independently, and V6's message says so.

**Staleness escalation applies to EVERY exit-3 branch, not just the undelivered one.** The sweeper never escalates a long-lived 2/3 on its own. Scoping the clock to V2 would leave a STRUCTURALLY BROKEN probe — an awk dialect change, a `jq` upgrade, a renamed field — parked on V3 / V5 / the integer guard / `producer_silent` forever, all exit 3, indistinguishable from legitimately waiting to anyone not diffing daily comments. So whenever the probe is about to exit 3 AND more than 30 days have elapsed since the `earliest=` constant in its own header, it exits 5 instead, with its normal message plus "in this state for `<N>` days — treat this as a defect, not a wait" and the branch marker named.

Tracker directive for the #8386 body (Phase 5): `<!-- soleur:followthrough script=scripts/followthroughs/registry-luks-live-8386.sh earliest=<merge date + 1 day, T00:00:00Z> secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD -->` + the `follow-through` label. All three names are already in the sweeper's `env:` map; the directive is what authorizes forwarding them, and no workflow edit is needed.

### 4. Delivery

Merge → `registry-host-replace-dispatch.yml` push run → it dispatches `apply-web-platform-infra.yml` → `startup_failure` (#8361) → dispatcher run FAILS → watermark stays at `f5ad46390`. After PR #8362 merges, a `workflow_dispatch` re-fire (reason + `tracker=8386`) delivers every template change since the watermark in ONE replace. The probe's R5 branch surfaces the moment that re-fire becomes possible; Phase 5 additionally asks for it on #8361. Nothing in this plan touches `apply-web-platform-infra.yml`.

## Implementation Phases

### Phase 0 — Preconditions (measure, do not assume)

0.1 `bash apps/web-platform/infra/registry-userdata-budget.sh` — record headroom (expected ≈18,588 B).
0.2 `bash apps/web-platform/infra/zot-disk-heartbeat-redaction.test.sh` — green baseline; note its extraction + stub harness is the template.
0.3 `bash apps/web-platform/infra/registry-boot-guard.test.sh` — green; note the assertion count (105 floor).
0.4 `grep -n 'run: bash apps/web-platform/infra/zot-disk-heartbeat-redaction.test.sh' .github/workflows/infra-validation.yml` and `grep -n 'zot-last-err-redact-7500' scripts/test-all.sh` — the two registration sites.
0.5 `findmnt -no SOURCE "$(mktemp -d)"; echo rc=$?` → empty, rc=1 (the `__NOMOUNT__` arm's premise); `command -v timeout lsblk findmnt blkid cryptsetup`.
0.6 Read `apps/web-platform/infra/inngest-bootstrap.sh` from `data_mount_src=n/a` through the whitespace guard after `_devid_hits` — this is the block to copy.
0.7 `python3 scripts/lint-encryption-posture.py --repo-sweep` (the `.github/workflows/ci.yml` invocation, verified) — green baseline.
0.8 **Row-budget measurement (read-only).** Under the credential the sweeper already holds: `scripts/betterstack-query.sh --since 1h --grep SOLEUR_ZOT_DISK --limit 1` → record the LIVE row's total byte length and the length ahead of ` zot_last_err=`; and record Better Stack's documented per-message ingest limit (cite the doc URL). Derive the suite's ceiling as (limit − current). If the limit cannot be established from the vendor docs, say so and drop the ceiling assertion to "the four fields are present and precede the tail" rather than inventing a number. Offline floor already measured at plan time: the `LINE=` template is 876 B, 848 B ahead of the tail, 26 unexpanded `$VAR`s.
0.9 `grep -n 'unrendered TF interpolation' -B8 apps/web-platform/infra/zot-disk-heartbeat-redaction.test.sh` — read the four `sed -i 's|\${…}|…|g'` render lines and the T1 assertion that no `${…}` survives. Phase 2.2 adds a FIFTH template var to that block, so this suite must gain a fifth render line or T1 fails by construction.

### Phase 1 — RED: emitter behavioural suite + structural guard

1.1 **Extend `apps/web-platform/infra/zot-disk-heartbeat-redaction.test.sh` rather than creating a second suite.** It already extracts THIS script, applies the strip read from `zot-registry.tf`, asserts valid bash, runs under `PATH="$BIN:$PATH"`, captures the POSTed body through the `curl` stub, and carries an anti-vacuity floor and a positive control — and once the posture block ships, its EXISTING cases execute that block too, so it needs the new stubs regardless or the dev box's real `findmnt`/`cryptsetup` run during a redaction case. A second file would duplicate ~80 lines of harness and a second `infra-validation.yml` registration to test the same extracted script at the same emit chokepoint. Its header gains a second stated property. Add a fifth render line `sed -i 's|\${registry_volume_id}|100000003|g' "$HB"` beside the existing four (Phase 0.9), and add these stubs: `findmnt` (env-driven: `HB_FINDMNT_OUT`, `HB_FINDMNT_RC`), `lsblk` (prints the fixture tree for `-inso NAME`; exits 64 on any other argv), `cryptsetup` (`HB_CRYPT_OUT`, `HB_CRYPT_RC`; exits 64 unless argv is `status <name>`), `blkid` (`HB_BLKID_OUT`), `timeout` passthrough is NOT stubbed (real coreutils), a by-id dir under `$TMP` with `scsi-0HC_Volume_<fabricated>` symlinks to `$TMP/dev/sdb`, substituted into the extracted script at render time (not exported). `curl` stub captures `--data-raw`. Cases (each asserts on the captured body, and asserts the five fields sit BEFORE ` zot_last_err=`):
   - healthy: src `/dev/mapper/registry`, tree `registry\n`-sdb`, one alias → `store_luks=yes store_mount_devid=scsi-0HC_Volume_<fab>`;
   - no mount (findmnt rc 1, empty) → `store_mount_src=__NOMOUNT__ store_luks=absent store_mount_devid=n/a`;
   - findmnt rc 124 → `__UNREADABLE__` / `store_luks=unknown`;
   - raw ext4 mount (src `/dev/sdb`, blkid `ext4`) → `store_luks=no`, devid still resolved;
   - mapper over a non-LUKS device (cryptsetup rc 0, `type: n/a`) → `no`;
   - **cryptsetup rc 0 with a LUKS `type:` line AND a `device:` line, but blkid on that device prints `ext4` → `no`.** This is the case that makes the blkid conjunct load-bearing: without it, deleting `&& blkid … = crypto_LUKS` from the `yes` chain leaves every other case green while the emitter reports `yes` for a dm node that is not a crypt mapping;
   - findmnt rc 0 with EMPTY output → `__UNREADABLE__` (the contract names this arm; it needs a case);
   - findmnt rc 1 with NON-EMPTY output → `__UNREADABLE__` (the `__NOMOUNT__` arm is rc 1 AND empty; its complement must be pinned or the conjunction is untested);
   - `lsblk` absent from PATH (rc 127) and `lsblk` rc≠0 → base `__UNREADABLE__`, devid `__UNREADABLE__`, `store_luks=unknown`;
   - mount source is a mapper whose name is NOT `registry` (e.g. `/dev/mapper/other`), chain otherwise healthy → the emitter reports `store_luks=yes` (it measures the device, not the name) while probe V4 FAILs on `store_mount_src != /dev/mapper/registry`. Pin BOTH sides so the emitter/probe seam is not left to inference;
   - cryptsetup rc 4 with blkid `ext4` → `no`; rc 4 with blkid silent → `unknown`; rc 1 → `unknown`; cryptsetup absent from PATH (rc 127) → `unknown`, row still emitted;
   - forked tree (`md0\n|-sdb\n`-sdc`) → `__AMBIGUOUS__` base and devid, `store_luks=unknown`;
   - partitioned chain (`registry\n`-sdb1\n  `-sdb`, cryptsetup `device: /dev/sdb1`, blkid on `/dev/sdb1` = `crypto_LUKS`, blkid on `/dev/sdb` = empty) → base `sdb`, devid resolved from `sdb`, and `store_luks=yes` (the case that pins the backing-device read);
   - cryptsetup exits 0 with a LUKS `type:` line but NO `device:` line → `unknown`, never `yes`;
   - two aliases to the same device → devid `__AMBIGUOUS__`; zero aliases → `__NOMATCH__`;
   - bracketed src `/dev/sdb[/sub]` → `__UNREADABLE__`;
   - sbin resolution: cryptsetup/blkid stubs placed in `$BIN/sbin` ONLY (absent from `$BIN`), run with `PATH="$BIN:/usr/bin:/bin"` after the suite's render step has substituted the literal `/usr/sbin:/sbin` → `$BIN/sbin` in the extracted script — must still read `store_luks=yes`. Render-time, never an env read (see the security note in §1). Deleting the append must redden this case;
   - `store_expected_devid` present and equal to the fixture's rendered value (the suite renders `${registry_volume_id}` the way the redaction suite renders its template vars);
   - EVERY case: exactly one POST, exit 0, no field value contains a space, `"` or `\`, and the assembled row's length BEFORE ` zot_last_err=` is under 2,000 bytes (a truncated row would lose the new fields and read to the probe as "never delivered").
   Anti-vacuity floor (`MIN_ASSERTIONS`) and a positive control, as the redaction suite has.
1.2 No new registration: the extended suite is already wired as the single-line `run: bash apps/web-platform/infra/zot-disk-heartbeat-redaction.test.sh` in `.github/workflows/infra-validation.yml`. Raise its `MIN_ASSERTIONS`/`EXPECTED_MIN` floor to the newly measured count.
1.3 **Split the anti-vacuity floor per property, and add an exact-token assertion helper.** The suite's existing `EXPECTED_MIN=39` is one integer over one property; after the fold it spans two, so deleting every posture case would still clear a raised total. Introduce `CASES_REDACT`/`CASES_POSTURE` counters with their own floors, each set to the count that property actually reports. The existing `assert_emit` is substring-only (`store_luks=yes` also matches `store_luks=yesX`), so add an exact-token `assert_field` with its own reject control and `USED_` counter.
1.3b `registry-boot-guard.test.sh`: add `store_mount_src= store_backing_dev= store_mount_devid= store_expected_devid= store_luks=` to the presence loop (five), plus a structural assertion that the script contains the literal `PATH="$PATH:/usr/sbin:/sbin"` and contains NO `ZOT_SBIN_DIRS`/`ZOT_BYID_DIR` env read (the anti-regression pin for §1's security note). Set `MIN_ASSERTIONS` to the count the suite actually reports after the edit (measured today: 105 passed against `MIN_ASSERTIONS=105`).
1.4 **New Phase 1.4 — the cross-copy parity guard** (`apps/web-platform/infra/store-vs-data-mount-parity.test.sh`). The plan accepts ~60 duplicated lines between `inngest-bootstrap.sh` and this template on the ground that the delivery substrates differ; "and nothing keeps them in sync" is not the only option. Precedent: `scripts/betterstack-ingest-parity.test.sh` (162 lines) asserts that two declarations agree without merging them, and derives its population rather than listing it. This guard derives BOTH resolution blocks (the `lsblk -inso` walk and the by-id reverse map, extracted from `inngest-bootstrap.sh` and from the heartbeat block extracted out of the template) and asserts they agree on the three invariants that have each been wrong once: leaf-counting rather than last-row, Hetzner-namespace scoping, and hit-counting rather than first-match. It is the cheapest item in this plan and the only one that pays out in year three.
1.5 Run all three: the extended suite reddens on the missing fields, the boot guard reddens on the four names plus the seam, the parity guard is green against the faithful copy and red against a mutated one.

### Phase 2 — GREEN: the emitter

2.1 At the TOP of the heartbeat script, beside `set -u`, add the LITERAL `PATH="$PATH:/usr/sbin:/sbin"` (no env indirection — §1's security note) plus the one-line pointer comment on the `/etc/cron.d/zot-disk-heartbeat` block. Then, after the log-shipper block and before the `zot_last_err is free-text` comment, add the posture block: defaults (`STORE_MOUNT_SRC=__UNREADABLE__ STORE_MOUNT_BASE=n/a STORE_MOUNT_DEVID=n/a STORE_LUKS=unknown`), the rc-capturing findmnt read with the rc-1 discrimination and charset guard, the copied lsblk/by-id block (renamed variables, literal by-id root, `$${…}` escapes), the cryptsetup + blkid chain, the whitespace guards.
2.2 Extend `LINE=`: insert `store_mount_src=$STORE_MOUNT_SRC store_mount_devid=$STORE_MOUNT_DEVID store_expected_devid=scsi-0HC_Volume_${registry_volume_id} store_luks=$STORE_LUKS ` before `host=$(hostname)`. The single `$` on `${registry_volume_id}` is correct and verified: it is in `zot-registry.tf`'s templatefile map and in `registry-userdata-budget.sh`'s 12-key stub map, exactly as `registry-luks-open.sh`'s `DEV=` line uses it. This is the fifth template var in the extracted block — Phase 0.9's render line exists for it.
2.3 Comments: rationale lines start with `# ` so the render-time strip removes them; keep them short — the budget script measures the STORED bytes.
2.4 Run: the extended redaction+posture suite, the boot guard, the parity guard, `registry-userdata-budget.test.sh`, `bash apps/web-platform/infra/registry-luks.test.sh`, `bash apps/web-platform/infra/private-nic-guard.test.sh`, and `terraform fmt -check`/`validate` are unaffected (no `.tf` change) — but the template must still render: `bash apps/web-platform/infra/registry-userdata-budget.sh` IS the offline render and fails on a bad `${…}`.

### Phase 3 — Probe + probe suite

3.1 Create `scripts/followthroughs/registry-luks-live-8386.sh` per §3 above: the guard chain as prose-ordered early exits, then verdicts V1-V7 in the stated order, with the ledger read performed only on the V6/V7 path. Read the expected-alias pattern and the four field names from constants at the top; the ledger read is `python3 - <<'PY' … json.load … PY` on `"$REPO_ROOT/scripts/encryption-posture-ledger.json"`; the apply-workflow byte read is `wc -c < "$REPO_ROOT/.github/workflows/apply-web-platform-infra.yml"`.
3.2 Create `scripts/followthroughs/registry-luks-live-8386.test.sh` from the 7500 harness: temp root with the probe, the parse lib, a stub `betterstack-query.sh`, a stub ledger file (available / other / malformed / absent) and a stub apply workflow file of controllable size (its bytes are message content, so the cases assert the TEXT, not a different verdict); every case pins a BRANCH MARKER (`registry-luks[#8386]: verdict=r<n>_…`) AND the exit code; fixtures are producer-shaped envelope rows with fabricated boot ids/aliases; a positive control at the bottom.
3.2b `bash scripts/lint-followthrough-varq-ban.sh` (the live gate over `scripts/followthroughs/`) AND `bash scripts/lint-followthrough-varq-ban.test.sh` (its own suite) — both are registered in `scripts/test-all.sh` and the new probe is in the live gate's scope.
3.3 **Derive the marker floor from the probe; never assert a hand-counted number.** `grep -c 'exit 3'` (and the same for 2 and 5) on the shipped probe, then assert the suite exercises at least that many DISTINCT branch markers per exit code, plus marker uniqueness across cases. Verdict-level markers alone are insufficient: exit 3 has ~9 sites and V2 spans exits 3/2/5, which is exactly the collapse the 7500 suite's header records (deleting the named guard left it 6/0 green because four cases shared one integer). V2's three exits get sub-markers.
3.4 Cover every verdict and guard: V1, V2 (all three exits incl. the 30-day escalation and both apply-file sizes as message text), V3, V4 (each disjunct), V5, V6, V7, plus channel_dark, stub rc 7, envelope-only, zero-after-host-filter, no boot_id, `producer_silent`, unreadable ledger, and a structurally-broken-probe case (below).
3.5 Register: `run_suite "scripts/registry-luks-live-8386" bash scripts/followthroughs/registry-luks-live-8386.test.sh` in `scripts/test-all.sh` beside the 7500 line; `bash scripts/lint-orphan-test-suites.sh` → `orphan test suites: none`.

### Phase 4 — Records

4.1 Ledger row rewrite per §2; `python3 scripts/lint-encryption-posture.py --repo-sweep` green; AC-L2.
4.2 ADR-141: append `## Amendment — 2026-09-19 (#8386): the registry emitter exists in code; the arm trigger is the observed boot, not the merge` (≤ 16 lines). It MUST also (a) restate the emitter blocker set as #6894 / **#8386** / #6897 — the ADR's frontmatter still reads `blockers: [6894, 6895, 6897]` and #6895 closed without an emitter, so a reader tracing the arm trigger lands on a closed issue; and (b) state explicitly that the DEFERRED vendor-side Better Stack alert does NOT discharge ADR-141's Decision 1, whose Layer B reconcile rides `scheduled-terraform-drift.yml` (ADR-033 single-substrate). Without (b) the next reader treats #6923 as satisfied by an exploration alert, which is a detector, not the reconcile.
4.3 `model.c4` — TWO edges move, not one. (a) `zotRegistry -> betterstack`: "SINCE #8386 the SOLEUR_ZOT_DISK row also carries the at-rest posture of /var/lib/zot (store_mount_src / store_mount_devid / store_expected_devid / store_luks), the registry's runner-reachable Layer B signal (ADR-141)". (b) `github -> betterstack` already enumerates its consumers ("the zot restart-loop recurrence alarm … and follow-through soak probes") and the model's own convention — see the `inngest -> betterstack` edge's SAFETY-CRITICAL INPUT annotation — is to mark a read that GATES something; this read gates a security ledger row, so the registry posture probe is named there with that annotation. Run `cd apps/web-platform && ./node_modules/.bin/vitest run test/c4-code-syntax.test.ts test/c4-render.test.ts` and `bash plugins/soleur/test/c4-count-parity.test.sh`.

### Phase 5 — Enrollment (automated, in-pipeline; runs at /ship)

5.1 `gh issue edit 8386 --add-label follow-through` and append the tracker directive from §3 to the #8386 body (`gh issue view 8386 --json body`, append, `gh issue edit --body-file`), with `earliest=` set to the UTC day after the merge.
5.2 `gh issue comment 6923 --body` — "#6895 (blocker line 2) is CLOSED by #6926 without an emitter; the registry emitter is #8386. Your arm criterion (a ledger row flipped to `available`) is satisfied by the flip commit that follows the first observed boot, not by #8386's merge." (comment only; the body is not edited).
5.3 `gh issue comment 8361 --body` — "When this lands, the registry template has an undelivered change behind the dispatcher watermark (`f5ad46390`): re-fire `gh workflow run registry-host-replace-dispatch.yml -f reason='deliver #8386 registry posture emitter' -f tracker=8386`. #8386's probe will read ACTION REQUIRED until then."
5.4 File the deferral issue (see Non-Goals) and cite it from the PR body.
5.5 PR body: `Ref #8386` (never `Closes`), the delivery statement from §4, the deferral issue.

## Files to Edit

- `apps/web-platform/infra/cloud-init-registry.yml` — the `zot-disk-heartbeat.sh` write_files block: the literal `PATH="$PATH:/usr/sbin:/sbin"` append beside `set -u`, the posture measurement block, five new `LINE=` fields, and a one-line pointer comment on the `/etc/cron.d/zot-disk-heartbeat` block (this template now carries a third cron-PATH model).
- `apps/web-platform/infra/registry-boot-guard.test.sh` — presence loop (five field names), the literal-PATH pin, the no-env-seam anti-regression assertion, and `MIN_ASSERTIONS`.
- `apps/web-platform/infra/zot-disk-heartbeat-redaction.test.sh` — a fifth `sed -i 's|\${registry_volume_id}|…|g'` render line (without it the suite's own T1 "render left no unrendered TF interpolation" assertion fails by construction), the four posture stubs, the posture cases, and a raised anti-vacuity floor.
- `scripts/encryption-posture-ledger.json` — row `hcloud_volume.registry` (`evidence`, `live_verification`).
- `.github/workflows/infra-validation.yml` — one `run: bash apps/web-platform/infra/store-vs-data-mount-parity.test.sh` line for the new parity guard (file is 141,091 B; far from the limit). The extended redaction+posture suite is already registered.
- `scripts/test-all.sh` — one `run_suite` line for the probe suite.
- `knowledge-base/engineering/architecture/decisions/ADR-141-encryption-posture-layer-b-live-reconcile-deferred.md` — amendment section.
- `knowledge-base/engineering/architecture/diagrams/model.c4` — BOTH the `zotRegistry -> betterstack` (producer) and `github -> betterstack` (consumer) edge descriptions.

## Files to Create

- `apps/web-platform/infra/store-vs-data-mount-parity.test.sh`
- `scripts/followthroughs/registry-luks-live-8386.sh`
- `scripts/followthroughs/registry-luks-live-8386.test.sh`

Pipeline-written files that will also appear in the diff (for any diff-scope reasoning): `knowledge-base/project/plans/2026-09-19-feat-registry-host-at-rest-posture-emitter-plan.md`, `knowledge-base/project/specs/feat-one-shot-8386-registry-posture-emitter/tasks.md`, `knowledge-base/project/specs/feat-one-shot-8386-registry-posture-emitter/decision-challenges.md`, `knowledge-base/project/specs/feat-one-shot-8386-registry-posture-emitter/session-state.md`, `knowledge-base/INDEX.md`, and any learning file.

## Alternative Approaches Considered

| Alternative | Why not |
|---|---|
| Flip `live_verification` to `available` in this PR (the issue's literal wording) | `available` is counted by the Layer A floor and defined by ADR-141 as "a HOST probe exists"; the host will not run the probe until a replace that has no date. The `inngest_redis_luks` row records the lagging-record discipline for exactly this window. Cost of the honest route: one one-line follow-up PR, which the probe's R6 branch nags for daily. |
| Read the expected volume id on the runner (Terraform output / Hetzner API) | The sweeper runner has neither credential (env map grepped); adding one widens a read-only sweeper's blast radius for one comparison the row can carry itself. |
| `cryptsetup status … device:` as the devid source instead of the lsblk walk | Covers only the mapper case; the walk also names the device on the raw-mount and partition cases and is the sibling contract (#8017) with a measured fork fixture. `cryptsetup status` is still used — for the LUKS type. |
| A standing Better Stack alert in this PR | Needs `-target=` lines in the 513,306 B apply workflow; deferred (tracking issue). |
| Close the reboot fallback (a launch-time mount gate that survives reboot) | A separate change to the zot launch path with its own downtime analysis; the emitter first makes the window measurable. Deferred (same tracking issue). |
| A sweeper-run probe that re-fires the dispatcher itself | Probes verify; a daily unattended production host replace from a read-only sweeper is the wrong authority (ADR-199 class). The probe names the command instead. |

## Non-Goals / Deferred (tracking issue filed in Phase 5.4)

One issue, `chore(registry): standing at-rest posture alert + escrow re-test + reboot-surviving launch gate — after #8361`, carrying its OWN follow-through directive so it is not hostage to #8386's closure: (a) `logtail_exploration` + `logtail_exploration_alert` `registry_store_not_luks` on `SOLEUR_ZOT_DISK` rows whose head lacks `store_luks=yes ` (mirror `inngest_luks_wrong_volume`, paused until the first observed boot, `query_period` two heartbeats) plus the two `-target=` lines and the `inngest-luks-wrong-volume-alert.test.sh`-shaped suite; (b) a zot launch gate on `/var/lib/zot` being backed by `/dev/mapper/registry` that runs on every container start, not only first boot; (c) the escrow half of the workspaces probe — a passphrase re-test (`cryptsetup luksOpen --test-passphrase`) and a header-UUID resolution check — at a cadence the risk posture justifies (the workspaces sibling runs DAILY, not per-tick), so `store_luks=yes` can eventually mean "and we can still unlock it". It owns the standing watcher outright. This matters because a PASS is terminal for #8386's probe (the sweeper never re-grades an issue it closed on exit 0), so if the alert rode #8386's flip PR it would be blocked by the same over-limit workflow that blocks itself — and the ledger could never be corrected. The flip PR therefore does two things (live_verification + live_coverage_floor); the watcher lands here. Re-evaluate when: #8361 is closed and the apply workflow is under 490,000 B. Milestone: the one `knowledge-base/product/roadmap.md` names for infrastructure hardening.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly — the registry serves container images to the fleet, not to users. The failure shapes are (a) a `set -u`/unbounded-call defect darks the heartbeat and pages "registry host down" falsely (operator time, no user artifact), (b) a false `store_luks=yes` lets #8386 close over a plaintext store, leaving the ledger asserting an at-rest control that does not hold (a supply-chain trust artifact: private image layers and cosign signatures readable from a seized volume).
- **If this leaks, the user's data is exposed via:** no user data lives on this volume. The row adds a device alias (`scsi-0HC_Volume_<id>`) to a log source that already carries the host's boot id and image digest; the alias is not a credential and grants nothing.
- **Brand-survival threshold:** `aggregate pattern` — a wrong at-rest claim is a class-level trust problem, not a single user's incident.

## Observability

```yaml
liveness_signal:
  what: "the SOLEUR_ZOT_DISK row itself (its ABSENCE is already alarmed by the zot restart-loop alarm's PRODUCER-SILENT exit 3 and the disk heartbeat); the new fields ride it, so a darked emitter is the same alarm"
  cadence: "every 5 minutes (/etc/cron.d/zot-disk-heartbeat under doppler run)"
  alert_target: "scheduled-zot-restart-loop.yml → [ci/zot-telemetry-silent] issue + Sentry monitor; Better Stack disk heartbeat"
  configured_in: "apps/web-platform/infra/cloud-init-registry.yml (cron.d block), scripts/zot-restart-loop-alarm.sh, .github/workflows/scheduled-zot-restart-loop.yml"

error_reporting:
  destination: "OFF-BOX, and only off-box: the measurement faults ARE the row — the sentinels (__NOMOUNT__ / __UNREADABLE__ / __AMBIGUOUS__ / __NOMATCH__ / unknown) ride the SOLEUR_ZOT_DISK POST to Better Stack Logs source 2457081, this host's sole producer surface. The [zot] stderr breadcrumbs are NOT a route: /etc/cron.d/zot-disk-heartbeat does not pipe through `logger -t` (its zot-log-shipper sibling does) and this host runs no Vector, so host journald reaches no sink and is lost on replace. A failed POST is observable only by ABSENCE — scripts/zot-restart-loop-alarm.sh PRODUCER_SILENT (exit 3) / INGEST_DARK (exit 4)."
  fail_loud: "a row whose store_luks is unknown or whose devid is a sentinel is R2 (FAIL) on the newest boot in the probe; the daily sweeper posts it on #8386"

failure_modes:
  - mode: "store came back as a root-fs directory or a raw ext4 mount after a reboot (the fail-open reopen path)"
    detection: "in-surface: the row's store_luks=absent|no with store_mount_src naming the actual source — emitted from the host, discriminating root-fs (NOMOUNT) vs raw device vs wrong-volume (devid != expected) in one row"
    alert_route: "while #8386 is open: the daily follow-through sweeper (R2 FAIL comment on the tracker); after close: #6923 Layer B reconcile and the deferred Better Stack alert (tracking issue, Non-Goals)"
  - mode: "posture measurement itself fails (cryptsetup/blkid/lsblk timeout or absent)"
    detection: "store_luks=unknown / __UNREADABLE__ sentinels on the row; the heartbeat still lands (unconditional emit)"
    alert_route: "probe R2 on the newest boot → sweeper FAIL comment; distinguishable from plaintext by the sentinel name"
  - mode: "emitter never delivered (apply dead, dispatcher never re-fired, or a successful dispatch that coalesced the delta away)"
    detection: "probe V2 — one undelivered verdict whose message carries the apply-file byte count, whether it is over or under 512,000 B, and the re-fire command; exit 3 while waiting, 2 while a fresh row is still arriving, 5 once 30 days have elapsed"
    alert_route: "sweeper comment on #8386; CANNOT ESTABLISH while waiting, ACTION REQUIRED at 30 days"
  - mode: "boot observed encrypted but the ledger still reads unavailable"
    detection: "probe V6 (the ledger reader returning the literal `other`); an unreadable ledger returns `__UNREADABLE__` and exits 3, never mistaken for `other`"
    alert_route: "sweeper ACTION REQUIRED comment naming the flip PR's two required parts (live_verification + live_coverage_floor)"
  - mode: "the store regresses AFTER #8386 closes"
    detection: "the DEFERRAL issue carries its own follow-through directive pointing at THIS SAME probe — it needs no -target=, no new secret (all three BETTERSTACK_QUERY_* are already in the sweeper env map) and no apply, so it is enrollable the day it is written and is NOT gated on #8361. A daily re-grade therefore continues after #8386 closes. The standing Better Stack alert and #6923 Layer B supersede it later."
    alert_route: "daily sweeper comment on the deferral issue (FAIL on exit 1); Better Stack exploration alert → operator email once it lands"
  - mode: "a new field carries a byte that breaks the POSTed JSON (space, quote, backslash), or the row outgrows the ingest limit"
    detection: "pre-merge: the suite's every-case charset assertion and the Phase-0.8-derived length ceiling; live: the row is rejected by ingest and the probe's `producer_silent` guard fires on the newest row's `dt` age"
    alert_route: "CI red pre-merge; [ci/zot-telemetry-silent] live"

logs:
  where: "Better Stack Logs source 2457081 (SOLEUR_ZOT_DISK rows, --grep SOLEUR_ZOT_DISK); host journald for the cron's stderr"
  retention: "Better Stack Logs plan retention (source 2457081); journald is lost on host replace"

discoverability_test:
  command: "bash apps/web-platform/infra/zot-disk-heartbeat-redaction.test.sh"
  # CORRECTED 2026-09-20 (ship Check 10): this field LED with the property prose below,
  # which no substring matcher can ever match — so the check could run the command, see it
  # pass, and still report expectation drift. `discoverability_test` exists so an operator
  # can compare one command's output against a stated token; a field that only describes
  # the property pushes that judgement back onto the reader. The literal comes first now;
  # the property is what the literal MEANS and is retained verbatim after it. The COMMA
  # after the literal is load-bearing: Check 10 tokenizes this field on commas (and
  # backticks/quotes) and substring-matches each token, so a literal that is not
  # delimiter-terminated is swallowed into one unmatchable run of prose — which is
  # exactly how the prose-only form failed.
  expected_output: "RESULT: PASS, with zero FAIL lines and BOTH per-property floors satisfied; the discriminating assertion is that all five posture fields are present AND positioned ahead of ` zot_last_err=` on EVERY path, including each measurement-failure path — not merely that a count was reported. The LIVE read is `scripts/betterstack-query.sh --since 1h --grep SOLEUR_ZOT_DISK --limit 12` under BETTERSTACK_QUERY_* — the probe wraps it."
```

## Encryption Posture

```yaml
at_rest:
  - store: hcloud_volume.registry
    mechanism: luks
    evidence: "apps/web-platform/infra/cloud-init-registry.yml — content anchors: `cryptsetup luksFormat --batch-mode --type luks2 --key-file - \"$DEV\"`, `cryptsetup luksOpen --key-file - \"$DEV\" registry`, fstab `/dev/mapper/registry /var/lib/zot ext4 defaults,nofail 0 2`, the registry-luks-open.sh write_files block; key: random_password.registry_luks + doppler_secret.registry_luks_key (zot-registry.tf). This plan changes the ROW'S CITATION and its live_verification text, not the mechanism."
    defends_against: "a seized/RMA'd or snapshot-imaged Hetzner block volume: OCI blobs + cosign signatures are unreadable without the Doppler-held passphrase"
    does_not_defend: "a leaked credential, an app-layer read on the unlocked live host, exfiltration via a compromised zot process — and, until the deferred launch gate lands, the reboot window in which zot serves a root-fs directory, which becomes MEASURABLE ONCE DELIVERED (#8386, see live_verification) and is still not PREVENTED"
    disclosed_as: not-publicly-claimed
    live_verification: "unavailable:the host-side emitter EXISTS in code since #8386 but has NOT been observed on a boot — flip to available only in the commit that records one, per scripts/followthroughs/registry-luks-live-8386.sh. Tracked #8386."
in_transit:
  - connection: "registry host → Better Stack Logs ingest (the SOLEUR_ZOT_DISK POST)"
    enforced_at: "cloud-init-registry.yml zot-disk-heartbeat.sh `post()` — `curl -fsS -m 10 -H \"Authorization: Bearer $TOKEN\" … \"${betterstack_ingest_url}\"` (an https:// URL rendered from zot-registry.tf)"
    tls: "HTTPS (TLS 1.2+, curl default against the vendor endpoint)"
    cert_verification: on
    does_not_defend: "the ingest token (soleur-registry/prd) if the host is compromised; row contents are readable by anyone holding the source's query credentials"
    disclosed_as: not-publicly-claimed
```

No `exception` block: no plaintext-exception and no `cert_verification: off` is introduced. The store is pre-existing; no new store or connection is created. **The `live_verification` and `does_not_defend` strings above are the ones §2 lands in the ledger, abbreviated only where noted — AC-L1/AC-L2 run against the committed row, and a plan whose own sample fails its own criterion is the defect.**

## Infrastructure (IaC)

### Terraform changes

None. `hcloud_server.registry.user_data` re-renders from the edited template through the existing `base64gzip(replace(templatefile(…), local.registry_rationale_strip, ""))` chain in `zot-registry.tf`; `registry_volume_id` is already in the templatefile map (no new var — `registry-userdata-budget.sh`'s 12-key map is unchanged). No providers, secrets or vendor resources.

### Apply path

(c) replace — the only path for this cloud-init-only host (ADR-096), already automated by `registry-host-replace-dispatch.yml` → `scripts/registry-replace-preflight.sh` → `apply-web-platform-infra.yml` `registry_host_replace`. This PR dispatches nothing itself: the merge-triggered dispatcher run will fail on the `startup_failure` apply (#8361) and leave the watermark where it is; the delivering run is the post-#8361 `workflow_dispatch` re-fire (Phase 5.3, probe R5). Blast radius when it runs: the registry host is destroyed and recreated; the store volume is preserved (asserted in the apply log); the fleet's pull path is down for the replace window (see Downtime & Cutover).

### Distinctness / drift safeguards

`user_data` is ForceNew with no `ignore_changes` by design. Stored payload stays well under the 32,768 B cap (AC-E5 measures it). The dispatcher watermark coalesces every undelivered template change into one replace; a green dispatcher run is not proof of delivery — the probe's `store_luks=` presence on the newest boot is.

### Vendor-tier reality check

No vendor resource is created. Better Stack Logs ingest grows by roughly 150 bytes per 5-minute row.

## Downtime & Cutover

Same shape as the sibling plan `knowledge-base/project/plans/2026-09-18-fix-registry-heartbeat-phase-b-delivery-field-plan.md` §Downtime & Cutover, and not repeated in full: the delivering operation is `-/+ hcloud_server.registry` by the dispatcher (pull path down for the replace window — measured apply job 1 min 51 s on 2026-09-17 plus ≤ ~3 min boot-to-serving; web containers keep serving; volume preserved). Zero-downtime paths do not exist for this host (single host, volume attaches to one server, no SSH). **This PR schedules no replace of its own**: the re-fire after #8361 is the one that carries this change together with every other undelivered template change since `f5ad46390`, so this plan adds no additional outage window. Rollback: none to the old host; recovery is a fresh replace from the preserved volume.

## Architecture Decision (ADR/C4)

No new ADR: the change extends an existing emitter under the ADR-140/141/211 contracts and reuses the ADR-142 device-binding vocabulary; the lagging-flip discipline is already recorded in the ledger's `inngest_redis_luks` row. **ADR-141 gets an amendment** (Phase 4.2) because its arm trigger text ("when an emitter #6894/#6895/#6897 lands a runner-reachable signal") would otherwise read as satisfied by this merge.

**C4 completeness check (all three model files read):** actors — none new (the registry host, GitHub Actions runner and Better Stack are modeled: `zotRegistry`, `github`, `betterstack`); external systems — none new; containers/stores — `hcloud_volume.registry` is a Terraform resource inside the modeled `zotRegistry` system, not a separate C4 container; relationships — `zotRegistry -> betterstack` and `github -> betterstack` already exist and their descriptions name `SOLEUR_ZOT_DISK`; BOTH are extended, not falsified (Phase 4.3). The producer edge enumerates the row's content ("df% … resize2fs … zot health") and gains the posture fields; the consumer edge enumerates its readers ("the zot restart-loop recurrence alarm … and follow-through soak probes") and gains this probe, annotated as a read that GATES something — the model's own convention, per the `inngest -> betterstack` edge's SAFETY-CRITICAL INPUT marker. `views.c4` and `spec.c4` carry no `SOLEUR_ZOT_DISK` reference (`grep -c` = 0). Counts: `bash plugins/soleur/test/c4-count-parity.test.sh` → ALL TESTS PASSED at plan time; no cron, monitor or heartbeat slug is added, so no derived count moves.

## Guard Contract

### Guard 1 — registry-luks-live-8386.sh (the follow-through probe)

**Property.** The probe exits 0 only when, among rows this host produced, the newest real boot's newest `SOLEUR_ZOT_DISK` row — read from the trusted head — measures `/var/lib/zot` as a LUKS mapper on the well-formed Terraform-declared volume, at least three rows on that boot confirm `store_luks=yes`, no row on that boot reads `store_luks=no`, and the ledger reader returns the literal `available`; every other state exits 1/2/3/5 with its own branch marker, and no state is reachable by absence, by an unreadable input, or by another host's row.

**Assembly.** One chokepoint chain, in this order — the order is part of the property, not an implementation detail: `betterstack-query.sh --grep SOLEUR_ZOT_DISK --limit` (the only row source) → the envelope-prefix filter (the only admission of rows) → the jq double-decode carrying `dt` (the only sort) → the `host=soleur-registry ` filter → `NEWEST_BOOT` from the head with the `[0-9a-fA-F-]+` class → the newest-row `dt` age guard → ONE awk pass over `head = substr($0, 1, index(" zot_last_err=") - 1)` producing `D`, `Y`, `P` and the newest row's four values → the integer guard → verdicts V1…V5 → (only now) the three-state ledger reader → V6/V7. A field read outside that awk pass, a second row source, or a ledger read hoisted above V5 is the defect this contract forbids.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the head cut (read fields from the whole row): fixture whose TAIL carries ` store_luks=yes store_mount_devid=<expected>` on a boot whose head says `store_luks=no` | RED (must be V1 FAIL, not V7) |
| 2 | Harness/dispatch: replace `got="$(run_probe …)"` with `got="$want"` in the suite | RED (positive control + branch-marker assertions prove the probe ran) |
| 3 | Boot scoping off: an OLDER boot with a good row newer in the file than the newest boot's bad row | RED (must grade the newest boot) |
| 4 | Hoist the ledger read above V1: good newest row, one earlier `no`, ledger `available` | RED (must be V1, not V7) |
| 5 | `P` count removed: newest row `yes` ×3, an earlier row on the same boot `no` | RED (must be V1) |
| 6 | Expected-alias check removed: `store_expected_devid=__UNREADABLE__` equal to `store_mount_devid=__UNREADABLE__` | RED (equality alone would pass; must be V4) |
| 7 | Guard's own dispatch: the awk pass emits nothing (dialect error) | RED (integer guard → exit 3, never 0) |
| 8 | Evidence-depth floor removed: newest boot has exactly ONE `yes` row, ledger `available` | RED (must be V5 exit 3) |
| 9 | V3 removed: `D > 0` with the newest row carrying no `store_luks=` at all | RED (must be exit 3, not a FAIL) |
| 10 | Ledger reader's three-state collapse: ledger file deleted in the stub root | RED (must be exit 3 `__UNREADABLE__`, never V6) |
| 11 | `producer_silent` guard removed: newest row's `dt` two hours old, otherwise perfect | RED (must be exit 3, not V7) |
| 12 | Host filter removed: a producer-shaped row from `host=soleur-registry-2` carrying a newer boot | RED (must grade this host's boot) |
| 13 | `absent` folded back into `P` (the M2 control must then fail) | RED |
| 14 | Staleness clock scoped to V2 only: a structurally broken probe (its awk emits nothing) with `earliest` 40 days past | RED unless it exits **5** — a permanently broken probe must not read as one legitimately waiting |

**Must-PASS controls (not mutations — they are the other half of the battery, and counting them in a "caught N of N" tally would overstate it):**

| # | Input | Expected |
|---|---|---|
| M1 | Rows carrying extra unknown fields, one earlier row `unknown` among 3+ `yes`, a Vector-shipped row merely quoting the marker, and an apply-workflow stub at 400,000 B | GREEN V7 |
| M2 | Newest boot's FIRST row `absent`, the next three `yes`, ledger `available` | GREEN V7 — a boot-race tick is not a plaintext reading |

**Anchor.** The alias the probe accepts is not a committed constant — it is the row's own `store_expected_devid`, rendered by Terraform from state, so a repo diff cannot change what the probe expects; the ledger read is against the sweeper's checkout of `main`, and the flip is a reviewed PR. **Two residuals, recorded rather than implied.** (1) Both sides of the comparison ride ONE row, over ONE ingest token, with a producer-controlled in-message `host=` discriminator — so the probe's PASS authority, which auto-closes a security tracker, is bounded by the `soleur-registry/prd` ingest token rather than by an independent channel. Closing that needs a runner-side read of Hetzner state, which the sweeper has no token for; it is ADR-141 Layer B's job (#6923), not this probe's. (2) The expected literal is frozen into user_data at host birth, so a volume swapped without a host replace reads as a permanent mismatch. One committed constant DOES appear in the verdicts — `store_mount_src != /dev/mapper/registry` in V4 — and it is a mapper NAME fixed by the same template, not the volume identity.

### Guard 2 — the extended zot-disk-heartbeat-redaction.test.sh (emitter behaviour) + registry-boot-guard.test.sh (emitter shape)

**Property.** For every fixture shape (healthy, no mount, findmnt rc0-empty, findmnt rc1-non-empty, unreadable, raw ext4, non-LUKS mapper, cryptsetup rc 0/1/4/127, LUKS-with-no-`device:`-line, blkid-disagrees, lsblk rc127, forked tree, partitioned chain, 0/1/2 aliases, bracketed source, non-`registry` mapper name, sbin-only tools), the shipped `zot-disk-heartbeat.sh` — extracted from the template and rendered exactly as Terraform renders it — POSTs exactly one row whose trusted head carries all five posture fields with the value the fixture dictates, contains no space/quote/backslash inside any value, stays inside the Phase-0.8-derived length ceiling, and exits 0; and the `LINE=` assignment names each of those four fields with `zot_last_err` still last.

**Assembly.** Two files, one property, and saying so is the point: the behavioural half's chokepoint is the single `LINE=` assembly and its one `post()` call (captured by the `curl` stub's `--data-raw`), reached through `extract_block` on `- path: /usr/local/bin/zot-disk-heartbeat.sh` plus the strip regex read FROM `zot-registry.tf` and the five render `sed` lines — so a second copy of the heartbeat, a changed strip, or an unrendered template var reddens it before any case runs. The structural half is `registry-boot-guard.test.sh`'s `LINE_ASSIGN` (the FIRST `grep -F 'LINE="SOLEUR_ZOT_DISK'` hit, one physical line) and its field-name loop. Neither half alone covers the property: the behavioural half cannot see a field renamed in both the script and its own expectations, and the structural half cannot see a value computed wrongly.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the `PATH="$PATH:/usr/sbin:/sbin"` append and run the sbin-only fixture | RED — `store_luks=unknown` instead of `yes` |
| 1d | Reintroduce an env-read seam (`PATH="$PATH:$${ZOT_SBIN_DIRS:-/usr/sbin:/sbin}"`) | RED — the boot guard's no-env-seam assertion; the script runs under `doppler run`, where every config secret is an env var |
| 2 | Replace an rc capture with `|| true` and run the no-mount case | RED — `__NOMOUNT__` collapses into `__UNREADABLE__` |
| 3 | Point the blkid read at `/dev/$STORE_MOUNT_BASE` instead of the cryptsetup `device:` line, and run the partitioned-chain fixture (signature on `sdb1`) | RED — `unknown`/`no` on a correctly encrypted store |
| 4 | Move `store_luks=$STORE_LUKS` after `zot_last_err=` | RED — both halves: the order assertion and the boot guard's last-field pin |
| 5 | Forked lsblk fixture with the leaf count replaced by last-row | RED — `__AMBIGUOUS__` expected, a confident `sdc` emitted |
| 6 | Delete the by-id hit COUNT (take the first alias) with two aliases present | RED — `__AMBIGUOUS__` expected |
| 7 | Suite dispatch: neuter `assert()` | RED — the anti-vacuity floor |
| 8 | Omit the fifth render line while `${registry_volume_id}` is in the block | RED — the suite's own T1 "render left no unrendered TF interpolation" |
| 9 | Rename `store_luks=` to `store_luks_state=` in `LINE=` | RED — the boot guard's field loop |

**Must-PASS controls (not mutations):**

| # | Input | Expected |
|---|---|---|
| M1 | A SIXTH emitted field added after `host=` but before `zot_last_err=` | GREEN for the order pin — and the charset + length assertions must still quantify over it, because the loop is over every `key=value` in the head, not a fixed five |
| M2 | A healthy fixture whose alias id has 10 digits, and one whose `zot_last_err` tail is 3 KB | GREEN (only the head's shape and length are asserted; the tail is free text by contract) |

### Guard 3 — store-vs-data-mount-parity.test.sh (the two MOUNT-SOURCE resolutions agree)

**Property.** Every block in the repo that resolves *a mount source to the Hetzner volume alias backing it* — an `lsblk -s` inverse walk plus a `scsi-0HC_Volume_*` reverse map — agrees on the three invariants that were each wrong in production and were fixed together in `0d97ede5c` (#8019 / probe_schema=8): the walk counts LEAVES rather than taking the last row, the reverse map is scoped to the Hetzner namespace, and it COUNTS hits rather than accepting the first match.

**Assembly.** The population is DERIVED, never listed — precedent `scripts/betterstack-ingest-parity.test.sh`, whose header records that a hand-written six-file array modelled one of two sources and so "reports agreement it never checked". **The derivation is scoped to the RESOLUTION shape, not to any `scsi-0HC_Volume_*` glob, and that distinction is the guard's correctness.** Measured on the tree: ten-plus files mention that glob, and `apps/web-platform/infra/git-data-bootstrap.sh` deliberately does a first-match `break` over it — correctly, because it answers a DIFFERENT question ("which attached volume is LUKS?", discriminated by `cryptsetup isLuks`) rather than "which volume backs this mount?". A guard scoped to the glob would redden code that is right by design, which is the precedent's other recorded failure mode ("would have failed on a correct tree"). So the predicate is: blocks containing BOTH an `lsblk` inverse walk (`-s` with `-o NAME`) AND a `scsi-0HC_Volume_*` reverse map within the same function. Today that is `inngest-bootstrap.sh` and, after this plan, the heartbeat block extracted from `cloud-init-registry.yml`. `MIN_FILES` is the count measured at write time, and the suite PRINTS what it derived so a future third member is visible rather than silently averaged in.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Change the registry copy's awk to take the last row instead of counting leaves | RED |
| 2 | Drop the `scsi-0HC_Volume_` namespace scope from ONE copy | RED |
| 3 | Replace `_devid_hits` counting with a first-match `break` in ONE copy | RED |
| 4 | Guard's own dispatch: the derivation finds zero files (a path rename) | RED — the `MIN_FILES` floor, never a silent green |
| 5 | Add a THIRD file carrying a mount-source resolution with a first-match `break` | RED — the guard quantifies over what it derives, not over two |

**Must-PASS controls (not mutations):**

| # | Input | Expected |
|---|---|---|
| M1 | `git-data-bootstrap.sh`'s first-match LUKS-SELECTION walk, present on the tree today | GREEN — it is not a mount-source resolution, and a guard that reddens here is scoped to the wrong predicate |
| M2 | The two copies differ in variable NAMES (`data_mount_base` vs `STORE_MOUNT_BASE`), comments and whitespace | GREEN — parity is over the three invariants, not over bytes |

## Test Scenarios

- **E1** healthy host fixture → body contains `store_mount_src=/dev/mapper/registry store_backing_dev=/dev/sdb store_mount_devid=scsi-0HC_Volume_<fab> store_expected_devid=scsi-0HC_Volume_<fab> store_luks=yes host=`, and NO `store_mount_base=` (that one stays an unemitted shell variable).
- **E2** reboot fallback (findmnt rc 1) → `store_mount_src=__NOMOUNT__ … store_luks=absent`.
- **E3** raw ext4 mount → `store_luks=no`, devid still resolved.
- **E4** every measurement tool absent from PATH → one POST, sentinels, exit 0.
- **E5** sbin-only tools, with the suite's render step pointing the literal at the stub dir → `store_luks=yes`; delete the append → RED; reintroduce an env-read seam → RED on the boot guard.
- **E6** partitioned chain (signature on `sdb1`, `blkid /dev/sdb` empty) → `store_luks=yes` via the cryptsetup `device:` line.
- **P1** probe: pre-delivery window (no `store_luks=` on the newest boot) → V2 exit 3; the same fixture with the apply stub at 400,000 B → still V2, message text differs; with `earliest` 40 days past → exit 5.
- **P2** probe: delivered + good (3 `yes` rows) + ledger `other` → 5 V6 with the two-part flip instruction; ledger `available` → 0 V7; the same fixtures with one `yes` row → 3 V5 in both.
- **P3** probe: forged tail, devid mismatch, `__UNREADABLE__` equality, malformed expected alias, newest `absent` → V4 FAIL each, distinct reason tokens; an earlier-row `no` → V1 even when the newest row is `yes`; an earlier-row `absent` among 3 `yes` → V7.
- **P4** probe: channel dark → 2; stub rc 7 → 2; envelope-only quoting rows → 2; zero rows after the host filter → 2; no usable boot_id → 3; newest row 2 h old → 3 `producer_silent`; ledger absent → 3.
- **P5** probe: newest row carries no `store_luks=` while earlier rows do → V3 exit 3, never a FAIL.
- **S1** `registry-boot-guard.test.sh` green at its newly measured floor; the extended redaction+posture suite green with its existing redaction cases unchanged in semantics; the parity guard green, and red under each of its three mutations.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC-E1 `bash apps/web-platform/infra/zot-disk-heartbeat-redaction.test.sh` exits 0 with the posture cases added (≥ 14 new cases), its anti-vacuity floor raised to the count it actually reports, and every pre-existing redaction case unchanged in semantics.
- [ ] AC-E2 `grep -F 'LINE="SOLEUR_ZOT_DISK' apps/web-platform/infra/cloud-init-registry.yml | head -1` contains, in this order, `store_mount_src=$STORE_MOUNT_SRC store_mount_base=$STORE_MOUNT_BASE store_backing_dev=$STORE_BACKING_DEV store_mount_devid=$STORE_MOUNT_DEVID store_expected_devid=scsi-0HC_Volume_${registry_volume_id} store_luks=$STORE_LUKS host=$(hostname) zot_last_err=$ZOT_LAST_ERR"`, ends with `zot_last_err=$ZOT_LAST_ERR"`, and DOES contain `store_mount_base=` (emitted per the #8386 review CTO ruling: the only field that makes a `__NOMATCH__` row auditable).
- [ ] AC-E3 `bash apps/web-platform/infra/registry-boot-guard.test.sh` exits 0; its `MIN_ASSERTIONS` equals the count that run reports (measured on `origin/main` today: 105 passed at `MIN_ASSERTIONS=105`), never a hand tally.
- [ ] AC-E4 the redaction suite's render map has five `sed -i` lines, the fifth rendering `${registry_volume_id}`, and its T1 "render left no unrendered TF interpolation" assertion passes. (This suite IS edited — the render map grows by one line and the posture cases are added; what must not change is any existing case's semantics.)
- [ ] AC-E5 `bash apps/web-platform/infra/registry-userdata-budget.sh` renders (this IS the offline templatefile render — a bad `$${…}` escape fails here) and reports `headroom` ≥ 15,000 B; `bash apps/web-platform/infra/registry-userdata-budget.test.sh` exits 0.
- [ ] AC-E6 in the extracted, rendered heartbeat script: `grep -cE 'timeout [0-9]+ (findmnt|lsblk|cryptsetup|blkid)'` ≥ 4; `grep -c 'PATH="$PATH:/usr/sbin:/sbin"'` = 1 AND `grep -cE 'ZOT_SBIN_DIRS|ZOT_BYID_DIR'` = 0 (no runtime env seam reaches a script that runs under `doppler run` as root); every one of the four measurement command substitutions uses the `rc=0; … || rc=$?` form and none is `|| true`-suffixed (`grep -cE '\|\| true' ` over those four lines = 0); and **no `exit` statement lies between the posture block's first line and the `LINE=` assignment** — asserted with POSIX-portable awk and an anchored start pattern, because `\s` is a gawk extension that mawk (Ubuntu's `/usr/bin/awk`) matches as a literal `s`: `awk '/^STORE_MOUNT_SRC=/{f=1} f && /^[[:space:]]*exit([[:space:]]|$)/{c++} /^LINE=/{exit c} END{exit c}'` → exit status 0.
- [ ] AC-E7 the emitted row's head (everything before ` zot_last_err=`) is within the Phase-0.8-derived ceiling on every case; if Phase 0.8 could not establish Better Stack's per-message limit, this AC degrades to "the four fields are present and precede the tail" and Phase 0.8 records why.
- [ ] AC-G1 `bash apps/web-platform/infra/store-vs-data-mount-parity.test.sh` exits 0, reports the file count it derived (≥ 2) and the three invariants it checked, and is registered by a single-line `run: bash apps/web-platform/infra/store-vs-data-mount-parity.test.sh` in `.github/workflows/infra-validation.yml` (`grep -c` = 1).
- [ ] AC-P1 `bash scripts/followthroughs/registry-luks-live-8386.test.sh` exits 0 with every verdict (V1-V7, including V2's three exit codes and V7's exit 5) and every guard-chain exit pinned by BOTH its exit code and its branch marker; the distinct-marker count per exit code is DERIVED from the shipped probe (`grep -c 'exit 3'` etc.) rather than hand-asserted; marker uniqueness across cases is asserted; the must-PASS controls M1/M2 are present and green; plus a positive control; registered in `scripts/test-all.sh` (`grep -c 'registry-luks-live-8386.test.sh' scripts/test-all.sh` = 1); `bash scripts/lint-orphan-test-suites.sh` prints `orphan test suites: none`.
- [ ] AC-P2 the probe's header carries the tracker directive verbatim with exactly the three Better Stack names (`grep -c 'secrets=BETTERSTACK_QUERY_HOST,BETTERSTACK_QUERY_USERNAME,BETTERSTACK_QUERY_PASSWORD' scripts/followthroughs/registry-luks-live-8386.sh` ≥ 1) and `grep -c 'GH_TOKEN\|gh run list' scripts/followthroughs/registry-luks-live-8386.sh` = 0 — the sweeper has no `actions: read`, so an Actions query would 403 and the arm that depended on it is deleted, not degraded. `grep -c 'ssh ' scripts/followthroughs/registry-luks-live-8386.sh` = 0.
- [ ] AC-P2b the exit-2 "query non-zero" arm never echoes `betterstack-query.sh`'s stdout or stderr into its message (`BETTERSTACK_QUERY_PASSWORD` is bound in that process; the xtrace refusal covers tracing only, not output pass-through). Asserted by a suite case whose stub prints a credential-shaped token on both streams and exits 7, then greps the probe's combined output for its absence.
- [ ] AC-P3 `bash -x` refusal: `BETTERSTACK_QUERY_PASSWORD=x bash -x scripts/followthroughs/registry-luks-live-8386.sh; echo $?` → 78.
- [ ] AC-P4 the shell lints CI runs over `scripts/` pass with the new files present, each by its OWN invocation (exact forms from `.github/workflows/ci.yml` and `scripts/test-all.sh`): `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt`; `python3 scripts/lint-shell-trace-credential-refusal.py --changed --base origin/main`; `python3 scripts/lint-trap-tempfile-ownership.py` and `--check-highwater`; `bash scripts/lint-followthrough-varq-ban.sh`; `python3 scripts/lint-window-closure-assertion.py --allowlist scripts/lint-window-closure-assertion.allowlist.txt`; `python3 scripts/lint-credential-path-literals.py`. No baseline/allowlist/highwater file is edited to make a new script pass — fix the script instead, asserted mechanically: `git diff --name-only origin/main...HEAD | grep -cE '(baseline|highwater|allowlist)'` = 0.
- [ ] AC-L1 `python3 scripts/lint-encryption-posture.py --repo-sweep` (the CI invocation) exits 0; `python3 -c "import json;r=[s for s in json.load(open('scripts/encryption-posture-ledger.json'))['stores'] if s['store']=='hcloud_volume.registry'][0]['at_rest'];print(r['live_verification'].startswith('unavailable:'), '#8386' in r['live_verification'], 'registry-luks-live-8386.sh' in r['live_verification'])"` → `True True True`; `live_coverage_floor` is still 1. **The plan's own `## Encryption Posture` block quotes the same row text, so it must satisfy this AC too** — a plan whose sample fails its own criterion is the defect, not the criterion.
- [ ] AC-L2 the row's `evidence` and `live_verification` contain no `.yml:<digit>` shape (`import re; print(bool(re.search(r'\.yml:[0-9]', r['evidence']+r['live_verification'])))` → `False`); `evidence` contains both `cryptsetup luksFormat --batch-mode --type luks2` and `cryptsetup luksOpen --key-file - "$DEV" registry` and the `CORRECTED 2026-09-19 (#8386)` clause; and `does_not_defend` says the reboot window is *measurable once delivered*, not *now MEASURED* — at merge the emitter is undelivered, and that phrasing is the ledger lying in the other direction.
- [ ] AC-R1 `grep -c '^## Amendment — 2026-09-19 (#8386)' knowledge-base/engineering/architecture/decisions/ADR-141-encryption-posture-layer-b-live-reconcile-deferred.md` = 1, and that section contains both `#8386` in a restated blocker set and an explicit sentence that the deferred vendor-side alert does not discharge the `scheduled-terraform-drift.yml` reconcile.
- [ ] AC-R2 BOTH C4 edges carry the change, pinned by anchor not by a bare token: the `zotRegistry -> betterstack` line contains `store_luks`, and the `github -> betterstack` line names the registry posture probe among its consumers (`awk` the two edge lines and grep each — a repo-wide `grep -c 'store_luks' model.c4 ≥ 1` cannot tell one edge from two). `cd apps/web-platform && ./node_modules/.bin/vitest run test/c4-code-syntax.test.ts test/c4-render.test.ts` green; `bash plugins/soleur/test/c4-count-parity.test.sh` green.
- [ ] AC-R3 `git diff --name-only origin/main...HEAD | grep -c 'apply-web-platform-infra.yml'` = 0 (the byte-limited workflow is untouched) and `grep -c 'scheduled-followthrough-sweeper.yml'` = 0 (the sweeper's permissions are not widened).
- [ ] AC-R4 `python3 scripts/lint-guard-contract.py knowledge-base/project/plans/2026-09-19-feat-registry-host-at-rest-posture-emitter-plan.md` exits 0; `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` exits 0.
- [ ] AC-R5 the PR body contains `Ref #8386` and does not contain `Closes #8386`.

### Post-merge (automated by /ship and the sweeper — no operator step)

**None of these is a merge gate.** AC-S4 in particular turns on #8361 landing and on a host replace running, i.e. on work this plan does not own — it is recorded so the closure criterion is visible, and the sweeper is what asserts it. Every PRE-merge criterion above is a deterministic command over this repo or a hermetic suite; none asserts the absence of an ambient signal (`cq-ac-must-not-depend-on-concurrent-sessions`).

- [ ] AC-S1 #8386 carries the `follow-through` label and the directive line (`gh issue view 8386 --json body,labels`), `earliest=` ≥ the merge day + 1.
- [ ] AC-S2 #6923 and #8361 each carry the comment from Phase 5.2 / 5.3 (`gh issue view <n> --json comments --jq '.comments[-1].body' | grep -c 8386` ≥ 1). #6923's comment says the OBSERVED BOOT arms it and the ledger flip is the bookkeeping consequence — not that the flip is the arm criterion, which would leave #6923 disarmed if the flip PR stalled.
- [ ] AC-S3 the deferral issue exists with the `deferred-scope-out` label, owns the standing `store_luks != yes` alert AND the reboot-surviving launch gate, and is cited in the PR body.
- [ ] AC-S4 (delivery, days later — the sweeper's job, recorded so the criterion is visible): the first sweep after #8361 reads V2 with the under-the-limit message; after the re-fire, V6 on a real boot; after the two-part flip PR, V7 (exit 5, ACTION REQUIRED — deliberately not an auto-close, see §3), and #8386's closure is a reviewed decision rather than a sweeper action, with `live_coverage_floor` reading 2. The deferral issue's own directive then keeps the daily re-grade running.

## Dependencies & Risks

- **#8361 / PR #8362** — delivery blocker. No ETA; the plan degrades to "merged, measured undelivered" rather than to a false claim.
- **Merge conflicts with #8362** — none expected: disjoint files (this plan does not touch the apply workflow).
- **Templatefile escaping** — a missed `$${…}` fails the offline render (AC-E5) before it can fail a dispatch.
- **D-state block devices** — `blkid`/`lsblk` on a sick disk are bounded by `timeout 5`; the heartbeat's `-m 10` curl and `exit 0` remain.
- **cryptsetup exit-code semantics** — matched on the `type:` line for `yes`; rc 4 (documented "wrong device specified") yields `no` only when blkid independently reports a non-LUKS type; anything else is `unknown`, never `no`. The suite stubs each shape; the live semantics are confirmed by the first observed row (a `unknown` on a healthy host would be R2 and would surface the discrepancy rather than hide it).
- **Public sweeper output** — the probe prints counts, verdict tokens, boot ids and aliases only; an alias is not a secret (it is the volume's by-id name), and no row text is echoed.
- **The reboot fallback stays open** — measured, not prevented; tracked.
- **A successful NIC-guard self-heal emits no distinct marker.** The 5-min guard reopens the mapper and restarts zot, but its success is only inferable as `store_luks=absent → yes` across two rows; nothing says "the backstop fired". Recorded as a residual rather than fixed here (the guard is a different write_files block with its own suite).
- **The sweeper has no per-verdict dedup** (`scripts/sweep-followthroughs.sh` records this: "A general per-verdict dedup is tracked separately; it changes the contract for every enrolled probe"), and 56 trackers already comment daily. V2 is the steady state for an unbounded period while #8361 is open, so #8386 will accrete an identical daily comment until delivery — the training signal that makes a tracker stop being read. Accepted rather than fixed here: the fix benefits all 56 trackers and belongs in the sweeper, not in this PR. The 30-day escalation is retained because at that point the message changes from "waiting" to "this is a delivery failure", which is a different disposition, not louder noise.
- **A PASS is terminal for this probe.** The sweeper never re-grades an issue it closed on exit 0 (its closed-set reopen fires only on exit 1, inside `CLOSED_LOOKBACK_DAYS` and under `REOPEN_MAX`), so the flip PR is the only place the standing watcher can be enrolled — which is why R6's text makes the alert one of that PR's three required parts rather than a separate nicety.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** CTO advisory (2026-09-19): (a) lagging ledger flip is correct — flipping at merge would make the Layer A floor count a probe that has never run; keep the probe's undelivered (3) and unflipped (5) branches distinguishable so the sweeper's daily comment is not the same remediation twice → adopted (R4/R5/R6 are distinct exits with distinct markers). (b) `store_expected_devid` on the row is acceptable: measured side is kernel state, expected side is the Terraform render; it catches "mapper/mount on a device other than the declared volume" and does not catch a consistent TF-state swap, which is #6923 territory; no better off-box source exists → adopted, and the residual is recorded in Guard 1's Anchor. (c) the watermark reasoning was incomplete: after #8361 nothing fires the dispatcher unless a push touches the template → adopted as R5 + Phase 5.3 + the ledger reason text. (d) fail-arm hazards: bind every var before measuring and run a case with every stub absent (E4); escape `${…}` as `$${…}` (AC-E5 renders); map cryptsetup rc 4 → `no` and other non-zero → `unknown`; charset-guard findmnt output (bracketed bind-mount sources); re-run the budget test → all adopted into §1 and the suites. Complexity medium; no capability gaps; no new ADR.

### Plan Review (2026-09-19)

**Panel:** dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer (per-mechanism, against the Property and Cut lists), architecture-strategist, spec-flow-analyzer (twice — once on the draft, once re-reviewing the folds), plus a scoped advisor consult (ADR-083) and the CTO under a devex lens. Named-panel relevance gate computed independently of Phase 2.5: the mechanical UI-surface scan over `## Files to Create` + `## Files to Edit` returned no hit (no `components/**/*.tsx`, no `app/**/page.tsx|layout.tsx`), and a fresh read of the body found no product/market/design language — so `cpo`, `cmo` and `ux-design-lead` did not activate; `cto` did, on the code/infra Files-to-Edit trigger.

**All findings classified Mechanical and auto-applied** (eng-panel correctness/simplification, one right answer each; none drops operator-requested scope, adds a sub-processor or paid dependency, adds a recurring cost, or touches an irreversible data operation). The single User-Challenge in this plan predates the panel and is persisted separately — see `knowledge-base/project/specs/feat-one-shot-8386-registry-posture-emitter/decision-challenges.md`.

The load-bearing changes the panel produced, all verified against the repo before applying:

1. **The R5 family is deleted, not fixed.** Kieran measured that the sweeper declares `permissions: contents: read` + `issues: write`, so the `gh run list --workflow=…` the three-way split depended on would 403 on every run; spec-flow had separately shown its conclusion space was incomplete (`in_progress`, `skipped`, `timed_out`, `startup_failure`, `neutral` matched no arm) and that R5b/R5c were unsatisfiable as phrased. DHH, code-simplicity and the CTO had independently asked for the collapse. Both panels firing on one scope means prefer delete: one undelivered verdict, no `GH_TOKEN`, no `gh` stub, no widened sweeper permissions, and an eleven-arm table down to seven.
2. **Kieran's second P0:** the redaction suite asserts that no `${…}` survives its render map, and Phase 2.2 adds a fifth template var to the block it extracts — so that suite was guaranteed red and was missing from Files to Edit. Fixed, and it absorbed the posture cases entirely (code-simplicity: the same extracted script at the same chokepoint, and its existing cases will execute the posture block anyway, so it needs the stubs regardless) — removing a file and a CI registration.
3. **`store_mount_base` leaves the row** (DHH + code-simplicity): no property in the list, no probe consumer, and its sentinels already mirror into `store_mount_devid`. Four emitted fields.
4. **The PATH append is a literal, pinned by a RENDER-time substitution** — spec-flow found that the original case could never pass (stubs in `$BIN/sbin`, append to the absolute `/usr/sbin`), and the proposed fix was a `ZOT_SBIN_DIRS` env seam; `security-sentinel` then showed that seam is a root-RCE surface, because the script runs under `doppler run --config prd` where every secret in the config becomes an environment variable and cron's own PATH contains neither `cryptsetup` nor `blkid`. The seam moved to render time, which pins the append without giving a config-store write root's PATH. `ZOT_BYID_DIR` went the same way.
5. **The row-length ceiling is derived, not invented** (architecture): 2,000 was a number from nowhere guarding the worst-recovery failure mode. Phase 0.8 measures the live row and the vendor limit, and says so if it cannot.
6. **The ADR-141 amendment gained two mandatory clauses** (architecture): restate the blocker set as #6894/#8386/#6897 (the frontmatter still names the closed #6895), and state that the deferred vendor alert does not discharge Decision 1's `scheduled-terraform-drift.yml` reconcile.
7. **The flip PR does two things, not three** (code-simplicity + CTO): requiring it to also land the standing alert made the honest-record property hostage to the alert's own blocker, so the ledger could never have been corrected while that workflow stayed over the limit. The watcher moved to the deferral issue's own follow-through.
8. **A cross-copy parity guard was added** (CTO): the plan accepts ~60 duplicated lines between two delivery substrates; `scripts/betterstack-ingest-parity.test.sh` is the in-repo precedent for asserting two declarations agree without merging them, and the three invariants it would pin have each been wrong in production once.

Smaller mechanical fixes: AC-E6's `\s` is a gawk extension that mawk matches as a literal `s` (measured: `gawk --posix` matched `sexit 0`), and the AC was additionally vacuous on a quoted default; the `findmnt` rc-discriminating shape is NEW rather than inherited and now says so while keeping the precedent's `head -1`; `P` counts `store_luks=no` only, with the boot-race residual stated; V3 was added for the truncated-row fall-through; a `producer_silent` guard distinguishes "was emitting, stopped" from a dark warehouse; both C4 edges move, and AC-R2 pins each by anchor; #6923's arm criterion is the observed boot, not the flip.

**One finding was partially rejected, with reasons.** DHH argued the `P` count is redundant with the `Y >= 3` floor and should go. It is not: a boot that reads `no` for hours and then recovers presents a `yes` newest row with `Y >= 3`, and only `P` remembers the window. Kept, and the rationale is recorded at §3 rather than left as a silent disagreement.

Product / Legal / Marketing / Sales / Finance / Support / Operations: not relevant — no user-facing surface, no legal document, no vendor or spend change (the ledger's `disclosed_as` stays `not-publicly-claimed`).

## References

- Issue #8386; blockers/related: #8361 (PR #8362), #6923, #6895 (PR #6926), #6894, #8017 (PR #8314), #7500 (PR #7954), #7456, #7960 (probe precedent), #7695.
- ADR-140, ADR-141, ADR-142, ADR-117, ADR-199, ADR-211, ADR-096, ADR-169 (what authorizes destroying the sole pull path — the dispatcher's authorization decision; the earlier draft cited ADR-190 here, which is about zot HTTP deadlines and never mentions the dispatcher).
- Sibling plan: `knowledge-base/project/plans/2026-09-18-fix-registry-heartbeat-phase-b-delivery-field-plan.md`.
- Runbook: `knowledge-base/engineering/operations/runbooks/followthrough-convention.md`.
