---
title: "fix: git-data first-boot bootstrap tolerates a late volume attachment (bounded, fail-closed wait)"
date: 2026-10-13
slug: git-data-bootstrap-volume-attach-race
branch: feat-one-shot-git-data-bootstrap-attach-race
issue: 10138
type: fix
priority: p1-high
domain: engineering
brand_survival_threshold: aggregate pattern
lane: cross-domain
---

## Review-round amendment (2026-10-13) — supersedes the design sections below where they differ

The 10-seat review panel and a simplicity pass returned, and the CTO agent ruled on the four forks
the simplicity seat raised (ruled 2026-10-13, recorded in `decision-challenges.md`). The shipped
design is smaller than the one this plan describes:

- **Section-1 LUKS wait: deleted.** The bootstrap's LUKS glob is unchanged from `main`; the
  `luks-discover` sentinels, `_gd_luks_scan` and their tests are gone. The `luks_open` heredoc is the
  first-boot LUKS wait.
- **The `GIT_DATA_ATTACH_WAIT_S` seam: deleted.** The bound is the literal 300 s (30 passes of
  `sleep 10`); there is no `-u` strip, no census C2 change and no seam tests. Tests drive the bound
  through the pass on which the link lands.
- **`udevadm settle`: dropped from the helper and from the heredoc loop; one settle follows the
  heredoc loop**, ahead of the single-shot probes that gate `luksFormat`. The helper charges 10 s
  and sleeps 10 s, so counted time is real time.
- **Added:** `timeout 10` on the plaintext size probe, and a log line naming the last measured state
  before the unchanged FATAL.
- **Tests pruned** to one row per distinct property, each mutation row asserting its own reason; the
  heredoc loop is pinned in B18 (`sleep 1`, the counter, the exact bound, the post-loop settle).
- Acceptance criteria and scenarios below that name the seam, the section-1 wait, `luks-discover`
  or the in-loop settle describe the superseded design and are not part of what shipped.

## Enhancement Summary

**Deepened on:** 2026-10-13
**Sections enhanced:** Research Insights (deepen pass), Downtime & Cutover (new), Sharp Edges
**Passes used:** plan-time reviews already folded in (CTO D1-D5, code-simplicity, architecture); deepen-time mechanical gates 4.6-4.12 and 4.55 (all pass), citation verification (issues, ADRs, rule ids, files), precedent diff against `git-data-luks-reopen.sh`, adjacency check of the census C2 regex. No further research fan-out: the plan is a bounded edit to one script, one template, and one rehearsal root, already reviewed by three seats, and the repo's own suites are the authority.

### Key Improvements

1. Census C2 pins the bootstrap invocation's `env -u` list by an adjacency regex; the new `-u` must be inserted before `-u GIT_DATA_PLAINTEXT_DEV`, never between it and `GIT_DATA_PLAINTEXT_VOLUME_ID=` (Sharp Edges).
2. The helper's seam validation follows the repo precedent spelling (`case ''|*[!0-9]*`, `_i=$((_i + 1))`) from `git-data-luks-reopen.sh`, with a length cap, instead of a new idiom.
3. An explicit Downtime & Cutover section: the only offline-inducing operations are the post-merge replace/rotate, on a host that serves nothing today.

### New Considerations Discovered

- The by-id link wait must not weaken the existing identity pinning (`_pt_same` re-checks the device number before `--setro`, `dumpe2fs` and `dmsetup create`); the wait only decides WHEN `_pt_dev`/`_pt_mm` are resolved, never skips those re-checks.

## Overview

The first-boot bootstrap script for the git-data host resolves its plaintext-volume device link exactly once and exits when the link is not yet there. The real rotate run 38384137515 (2026-10-13) lost the race: cloud-init reached the plaintext check about 70 s before Hetzner finished attaching the volume, and the host died at the named FATAL `plaintext_unverified reason=source`. This plan adds a bounded, fail-closed wait (default 300 s, an env seam for tests, `udevadm settle` on each pass) at the plaintext link and at the LUKS discovery, hardens the real first-boot LUKS wait in the cloud-init template, makes the rung-2 rehearsal harness reproduce a late attachment, and records the exact rehearsal evidence the changed payload needs before the rotate may be re-dispatched. Nothing here is dispatched or run against a host; each dispatch the plan names is gated on an explicit go-ahead that names the command.

## Research Insights

**Premise validation (Phase 0.6, 2026-10-13).** Cited items checked with `gh` and `git grep` on this branch: #10138 OPEN (the rotate re-dispatch waits on it), #10207 OPEN and draft (plan-only, 4 doc files, no code yet), #10210 OPEN draft (this PR), #10175 OPEN, #10166 CLOSED (rotate marker landed), #10137 CLOSED. `git-data-bootstrap.sh` lines 421-427 and 90-101 match the brief. `git_data_rung2_bound_files` lists 20 inputs including `git-data-bootstrap.sh` and `cloud-init-git-data.yml`; the current digest is `bfb0e5c2ecf05fa1d4bced4304b9211137d0c65e1a25b95c41f9b50bcbef554c` and equals `RUNG2_TEMPLATE_SHA256` in the committed evidence (measured 2026-10-13, `bash scripts/git-data-rung2-gate-verdict.sh` prints RELEASED). ADR corpus grep for the mechanism (wait/settle/attach): ADR-115 and the 2026-09-23 inngest post-mortem record the same class (Hetzner attaches resources after the server starts; the fix there is a bounded counted wait, never a clock); nothing rejects a bounded wait.

**Measurements (read-only `gh run view --log`, no dispatch).**

| Run | Server create | Attachment durations (LUKS / plaintext) | Notes |
|---|---|---|---|
| 38384137515 (rotate, failed), 2026-10-13 | 10:36:13 | 65 s / 125 s | bootstrap FATAL 10:37:11; plaintext attach reported complete 10:38:19; boot poll 10:38:24-10:48:18, VERDICT=silent |
| 38140050880 (rotate, earlier), 2026-10-11 | 12:50:31 | 33 s / 33 s | with server_network 16 s |
| 36118115758 (replace), 2026-09-25 | 09:24:42 | 33 s / 33 s | with server_network 16 s |
| 38356246710 (rung-2 rehearsal), 2026-10-13 | 06:27:20 / 06:28:46 | 33 s / 17 s, then 33 s / 32 s | no server_network in the rehearsal root; apply complete 06:29:20, evidence captured 06:30:16 (tail <= 56 s) |

Five prior boots attached both volumes in 17-33 s; the failing boot took 65 s and 125 s. The race was latent and the real run hit its tail. Hetzner serialising per-server actions is a hypothesis (unmeasured); the bound must not rely on it.

**Property List.**

- P1. A plaintext-volume attachment that lands within the bound no longer kills first boot, and the verification verdict equals the on-time case.
- P2. A volume that never attaches (or attaches after the bound) ends in the same named FATAL, no store marker is written, and the plaintext-empty verification is never skipped.
- P3. LUKS device discovery at first boot tolerates a late attachment.
- P4. The wait is bounded, testable without wall-clock time, and its bound cannot be changed from Doppler.
- P5. The rung-2 evidence for the new payload exercises the late-attach path before the rotate is re-dispatched.
- P6. The boot-completion poll budget still fits.
- P7. The half-rotated host's recovery is documented and reported, not executed.

**Cut List (mechanism -> property -> what already covers it).**

- Terraform ordering fix (boot after attach): cut; the attachments need the server id, and an existing volume cannot be attached at server create.
- Raise the workflow's 20 x 30 s boot poll or the 50-minute job timeout: cut; no property needs it (budget section).
- New `boot_complete` field for the wait duration: cut by ruling D4; a FATAL after the bound already pages.
- Capture-script change: cut; a PASS under a deliberate late attach proves the wait ran (the old code FATALs under the same delay).
- Non-destroying re-run of first boot on the existing server: cut; user_data is ForceNew and runcmd is once-per-instance (recovery section).
- A seam inside the cloud-init heredoc: cut by ruling D2 (literal bound, no seam, no extra `env -u` strip).

### Deepen-pass verification (2026-10-13)

- **Gates:** 4.6 User-Brand Impact present, threshold `aggregate pattern`, sensitive path (`apps/web-platform/infra/`) with a non-`none` threshold: pass. 4.7 Observability: five fields present, `discoverability_test.command` is `bash scripts/git-data-rung2-gate-verdict.sh` (allowlisted verb, no ssh, measured 1.7 s against the 15 s cap), `expected_output` is the literals `RELEASED or HOLD`: pass. 4.8 PAT-shaped variables: none. 4.9 UI: no UI-surface file, skipped. 4.10 Encryption Posture: both at_rest entries carry non-empty `does_not_defend`; the plaintext-exception row has `tracking_issue` and `expires_on` (2026-11-12, within 90 days): pass. 4.11 `python3 scripts/lint-guard-contract.py` over the plan: 4 guard entries, exit 0; adequacy read: the Assembly of each guard names a chokepoint (the helper, the single heredoc loop, the single invocation line, the single address pair), not a snapshot of members. 4.12 Scope Check: one unfenced section, no `unmapped`, no empty justification. 4.55 Downtime: section added below.
- **Citations resolved live:** #10138, #10207, #10210, #10175 OPEN; #10166 and #10137 CLOSED; #9949, #8571 and #6897 OPEN (read with `gh issue view`). ADR-115, ADR-149, ADR-152, ADR-193, ADR-231 and ADR-239 exist under `knowledge-base/engineering/architecture/decisions/`. Rule ids: `cq-write-failing-tests-before` is an active rule; `wg-architecture-decision-is-a-plan-deliverable` is in `scripts/migrated-rule-ids.txt` (migrated into plan Phase 2.10, still active). Every suite named in Acceptance Criteria exists at the cited path.
- **Negative claims checked against code:** (a) "the extracted store-verify unit does not contain section 1": the unit begins at the `BEGIN store-verify unit` sentinel (line 362) and section 1 is lines 67-117, confirmed; (b) "B19d pins the `luksOpen --key-file -` spelling": `git-data-luks.test.sh` mutation sed targets `cryptsetup luksOpen --key-file - "$luks_dev"`, confirmed; (c) "no hash-bound file was forgotten": `git_data_rung2_bound_files` output (20 inputs) contains only `cloud-init-git-data.yml` and `git-data-bootstrap.sh` among the files this plan edits.
- **Precedent diff (helper vs `git-data-luks-reopen.sh`):** the reopen script validates its wait with `case "$DEVICE_WAIT" in ''|*[!0-9]*) ... exit 2`, makes it `readonly`, and counts with `_i=$((_i + 1))` and a `die` after the bound. The new helper matches that shape (case validation, counter arithmetic, named refusal) and differs deliberately in two ways: it takes a predicate (two call sites) and charges 10 s per pass because it sleeps and settles. No precedent exists for a seam stripped by `env -u` inside a helper; the strip is the census C2 contract.
- **Semantic-change test audit (full enumeration, not a sample):** `grep -rlE "scsi-0HC_Volume|GIT_DATA_PLAINTEXT_DEV|_pt_link"` over `apps/web-platform/infra/*.test.sh`, `tests/scripts/*.sh` and `scripts/*.test.sh` returns 27 files on 2026-10-13. Those about OTHER hosts or volumes (inngest, registry, workspaces, web-host, luks-monitor, zot, fresh-boot-parity, lint-encryption-posture, host-state and the replace/dark-gate suites) do not read git-data-bootstrap.sh. The git-data ones and their disposition: `git-data-bootstrap-store-verify.test.sh` (this plan's suite), `git-data-luks.test.sh` (B18/B19d, planned edits), `git-data-store-device-census.test.sh` (C2, planned edit), `git-data-plaintext-snapshot-loopback.test.sh` (drives the snapshot recipe on loopback devices, not the by-id resolution; re-run, no edit expected), `git-data-render-strip-parity.test.sh` and `git-data-rung2-rehearsal.test.sh` (render and harness pins; re-run, the latter gets planned rows), `git-data-luks-reopen.test.sh` (its own script, unchanged), `store-vs-data-mount-parity.test.sh` (scopes the reverse map to the `scsi-0HC_Volume_*` shape, unaffected). Each is in the Acceptance Criteria run list or is named here.

**Institutional precedents used.** `git-data-luks-reopen.sh` (`GIT_DATA_REOPEN_DEVICE_WAIT`, validated integer, readonly); `cloud-init-inngest.yml` `soleur-inngest-nic-wait` (loop counter, never the clock, `waited_s`); the `#8211` guard conventions in `git-data-bootstrap-store-verify.test.sh` (sentinel extraction, landed-check, instrument self-test, floor equals count).

## Research Reconciliation — Spec vs. Codebase

| Brief claim | Reality (measured/read 2026-10-13) | Plan response |
|---|---|---|
| The LUKS step (bootstrap lines 91-98) "only survived by timing". | Bootstrap section 1 runs only when the mapper is not already mounted; at first boot the `luks_open` heredoc mounts it first, so that glob is practically unreachable on a first boot. The real first-boot LUKS wait is the heredoc's 30 x 1 s loop (`cloud-init-git-data.yml` ~line 1152), pinned by `git-data-luks.test.sh` B18 (`_i -lt 30`); the LUKS attach (65 s from create) beat it. | Patch both (rulings D1, D2); B18's pinned literal moves with the template. |
| The rehearsal harness may attach volumes before first boot, which would explain the miss. | False. `rung2-rehearsal/rehearsal.tf` attaches via separate `hcloud_volume_attachment` resources after `hcloud_server`, same as prod. The difference is latency (17-33 s vs the 65/125 s outlier) and that the rehearsal root has no `hcloud_server_network`. | Add a deliberate late attachment to the harness (ruling D3) so the required paid run exercises the wait. |
| 300 s wait plus the rest of bootstrap must fit the 20-poll (~10 min) boot poll. | The poll starts only after `terraform apply` returns, and apply blocks until both attachments finish, so the wait overlaps the apply's own attach wait. Post-attach tail measured <= 56 s. | No workflow change (ruling D5); arithmetic recorded below. |
| Recovery by re-running first boot through an existing non-SSH path. | None exists: `user_data` is ForceNew (no `ignore_changes` in `git-data.tf`), runcmd is once-per-instance, ADR-115 excludes git-data from the reboot primitive; the runbook's rule is "read first, never another replace; the fix is forward". | Report only (recovery section); a payload fix needs a new server regardless. |
| #10207 "is a different scope". | Disjoint files, but its `boot_complete`-newer-than-server-creation refusal (`stale_boot_complete`) would wedge a rotate on a host whose first boot failed (the current state). | Overlap section; PR comment to #10207 (ruling D5). |

## Problem Statement

Cloud-init first boot starts when the server is created; Hetzner attaches block volumes afterwards as separate actions. `git-data-bootstrap.sh` (a) resolves `/dev/disk/by-id/scsi-0HC_Volume_<plaintext id>` once with `realpath -e` and `exit 1` when it is absent (lines 421-427), and (b) in section 1 scans the by-id glob once for a LUKS device. The `luks_open` heredoc waits 30 s for its device and then falls through. In run 38384137515 the plaintext attachment finished about 70 s after the bootstrap reached the check. The failure is fail-closed (nothing was served, no marker written) but it destroyed a host build and left the d6 gate reading `d6_last_rotate_failed 38384137515`.

## Proposed Solution

Rulings are recorded in `knowledge-base/project/specs/feat-one-shot-git-data-bootstrap-attach-race/decision-challenges.md` (CTO, 2026-10-13).

1. **One helper, own sentinels (D1).** In `git-data-bootstrap.sh`, above section 1, define `_gd_attach_wait <label> <predicate-function>` between `# ---- BEGIN attach-wait helper ----` / `# ---- END attach-wait helper ----`. It reads the seam as `${GIT_DATA_ATTACH_WAIT_S-300}` (unset means 300; an EMPTY value is refused, so `:-` is wrong) and validates it as `^[0-9]{1,4}$`, evaluating it as `10#$v` so `08` cannot abort as invalid octal; an invalid value is its own named FATAL (`attach_wait_invalid`) and `exit 1`, never a default, before the first probe. It probes at once (bound 0 still probes exactly once); on a miss runs `udevadm settle --timeout=5 || true`, `sleep 5`, and adds 10 to a counter with `waited=$((waited + 10))` (iteration count, never the clock; real wall time is approximately the bound, because settle, sleep and the probe each take their own time and the 10 s per pass is a conservative charge); returns 0 when the predicate holds, 1 after the bound. `set -euo pipefail` rules (architecture review, 2026-10-13): predicates are `&&` chains with an explicit `return`, because errexit is off inside `if`/`while` and only the last status counts; no `local x=$(...)` (it masks the status); no `((n++))` from 0; and the helper is called directly, never inside `$( )`, so its `exit 1` and the caller's `_pt_dev` assignment survive (the caller re-resolves `_pt_dev` after the wait returns). It logs one line on entry and one on resolution to the runcmd detail (not a FATAL, so no off-box emit).
2. **Plaintext site.** The predicate is the existing `realpath -e` + `stat -L %F = block special file` test plus `blockdev --getsize64 > 0` (matches the heredoc; refuses a half-initialised node). The wait runs only inside `if [ -n "$_pt_id" ]` after the numeric-id check; on `return 1` the existing FATAL sentence is emitted byte-identically (`plaintext_unverified reason=source — <link> does not resolve to a block device`). `_plaintext_volume`, `_plaintext_empty` and the whole snapshot verification are untouched, so a timeout can never read as "absent".
3. **LUKS site in bootstrap section 1.** The block gets its own `# ---- BEGIN luks-discover unit ----` / `# ---- END luks-discover unit ----` sentinels, because the store-verify unit starts at section 7b and section 1 sits behind `mountpoint -q`, so the suite needs a second extraction to drive it. The predicate re-runs the whole by-id glob + `cryptsetup isLuks` scan on every pass (not "some volume exists": the plaintext volume can attach first). The loop spelling and `cryptsetup luksOpen --key-file - "$luks_dev"` stay byte-identical (B19d pins them); the existing `no LUKS-formatted volume found` FATAL fires after the bound.
4. **First-boot LUKS wait in the template (D2).** In the `luks_open` heredoc raise the 30-iteration literal to 300 (counted at 1 s per pass, `-b "$DEV"` and size > 0 predicate kept, `udevadm settle --timeout=2 || true` on every 10th pass only, so the worst case is about 300 + 30 x 2 = 360 s rather than 300 x 6 s; FATAL-on-absent fall-through kept via isLuks rc=4). `git-data-luks.test.sh` B18 `(i)` is updated to pin the new literal, with its mutation arm.
5. **Seam strip.** Add `-u GIT_DATA_ATTACH_WAIT_S` to the `env -u` list of the bootstrap invocation (`cloud-init-git-data.yml` ~line 1333); `git-data-store-device-census.test.sh` C2 gains the row.
6. **Rehearsal harness (D3).** `rung2-rehearsal/variables.tf` gains `rehearsal_attach_delay_s` (number, default 0, validated 0-240). `rehearsal.tf` gains `terraform_data.rehearsal_attach_delay_luks` and `terraform_data.rehearsal_attach_delay_pt` (NO `count`, so the addresses carry no `[0]` suffix that the plan-shape create regex would refuse; the sleep length is `var.rehearsal_phase == "payload" ? var.rehearsal_attach_delay_s : 0`, so the seed phase sleeps 0; local-exec `sleep` with the value passed in `environment`, not in `triggers_replace`, which is only the server id so a differing `-var` between plan and destroy cannot replace it). `hcloud_volume_attachment.rehearsal_luks` waits floor(delay/2) s and `hcloud_volume_attachment.rehearsal` waits the full delay. The workflow sets `TF_VAR_rehearsal_attach_delay_s: "150"` once at job level (one line; the workflow is byte-budgeted by ADR-231, so rationale goes to the runbook). At 150: LUKS lands about T+100, bootstrap starts about T+105, plaintext lands about T+175, so the new wait runs about 70 s; the old code would FATAL at luks_open (30 s wait vs a 75 s delay) and again at the plaintext link. `scripts/git-data-rung2-plan-shape.sh` (host-only mode) admits a replace of the two new `terraform_data` addresses (exact match; they are plain rehearsal-scoped creates in the seed plan, which additive mode already admits) and its suite gains rows. Residual risk, stated plainly: the host-only assertion runs only on a paid (`!dry_run`) run, and a dry run covers only the seed plan, so a plan-shape refusal of the new addresses would surface after the seed host is spent and costs one of the 2 rehearsals; the mitigation is fixtures in `tests/scripts/test-git-data-rung2-plan-shape.sh` hand-built from a real `terraform show -json` of the rehearsal root, plus the local `terraform validate`/plan checks, not a claim that a dry run proves it.
7. **Docs.** Runbook entry in `git-data-luks-cutover-5274.md` (dated, measured/inherited labels), the rehearsal runbook section on the delay, and an ADR-239 amendment.

## Boot-budget analysis

- Poll start: after `terraform apply` returns (apply blocks until both attachments finish). In run 38384137515 the poll began 10:38:24, 5 s after the last attachment completed.
- The wait overlaps the apply's attach wait. It adds to the poll window only through its post-attach tail: <= 56 s measured (rehearsal 38356246710: apply complete 06:29:20, evidence captured 06:30:16). Worst case from the wait itself: roughly one 5 s sleep + 5 s settle after the attach.
- Existing independent tail: the `luks_reopen_unit` convergence wait of up to 420 s inside bootstrap (pre-existing, unchanged). 56 s typical + 420 s worst case = 476 s < the 20 x ~31 s = ~620 s poll. Fits; no workflow change.
- Bound sizing: 300 s = 2.4 x the worst observed attach (125 s). Failure path: FATAL at ~300 s after bootstrap start, inside the poll window, same verdict path as today.
- Job timeout 50 min (replace/rotate job) and rehearsal job 217 min: unchanged. The rehearsal run lengthens by about 75-150 s per payload-phase boot (two boots); the rehearsal apply steps allow 15/25/15 min and the capture deadline is 16 min (read from the workflow on 2026-10-13), so +150 s is absorbed; `git-data-rung2-rehearsal.test.sh` pins those relations.
- user_data budget: stored 30,112 B of 32,768 B, headroom 2,656 B (measured 2026-10-13, `bash apps/web-platform/infra/git-data-userdata-budget.sh --json`). Comments are render-stripped, so only executable lines count; re-measure after the edit (AC).

## Implementation Phases

**Phase 0 — RED first (`cq-write-failing-tests-before`).** In `git-data-bootstrap-store-verify.test.sh`: add the extraction rows for the new helper sentinels, a `sleep` stub (logs, and on its Nth call materialises the by-id link so no wall time passes), `blockdev --getsize64` support in the blockdev stub, and the rows below; confirm they are RED against the current script.

**Phase 1 — bootstrap helper, sites, seam strip.** Edit `git-data-bootstrap.sh` (helper, plaintext site, LUKS site), the `env -u` line in `cloud-init-git-data.yml`, and `git-data-store-device-census.test.sh` C2.

**Phase 2 — heredoc wait.** Edit the `luks_open` heredoc literal and settle call; update `git-data-luks.test.sh` B18 (i) and its mutation; re-run `git-data-runcmd-rehearsal.test.sh` (it executes template segments) and the template strip/parity suites.

**Phase 3 — rehearsal harness.** `variables.tf`, `rehearsal.tf`, workflow `TF_VAR` line, `git-data-rung2-plan-shape.sh` + `tests/scripts/test-git-data-rung2-plan-shape.sh` rows, `git-data-rung2-rehearsal.test.sh` rows. Before any paid run: `terraform validate` and a plan-only check in the rehearsal root with the variable at 0 and at 150; confirm the seed-phase sleep is 0 (CTO constraint: a harness bug burns one of the 2 rehearsals allowed per payload hash). A local plan cannot reproduce the payload plan (it needs seed state), so the plan-shape fixtures carry that proof.

**Phase 4 — docs and ADR.** Runbook entries, rehearsal runbook note, ADR-239 amendment via `soleur:architecture`.

**Phase 5 — measurement and handoff.** Floor bump (`MIN_ASSERTIONS` = measured count, equal to passes + fails), budget re-measure, compute and record the new payload digest, PR comment on #10207, mark PR ready. No dispatch.

## Files to Edit

- `apps/web-platform/infra/git-data-bootstrap.sh` (helper + two sites)
- `apps/web-platform/infra/cloud-init-git-data.yml` (heredoc wait literal + settle; `env -u` strip)
- `apps/web-platform/infra/git-data-bootstrap-store-verify.test.sh` (rows, stubs, allowlist row for `blockdev --getsize64` as a pre-`--setro` identity probe, floor)
- `apps/web-platform/infra/git-data-luks.test.sh` (B18 (i) literal + mutation)
- `apps/web-platform/infra/git-data-store-device-census.test.sh` (C2 strip row, its floor)
- `apps/web-platform/infra/rung2-rehearsal/rehearsal.tf`, `apps/web-platform/infra/rung2-rehearsal/variables.tf`
- `apps/web-platform/infra/git-data-rung2-rehearsal.test.sh` (rows for the delay resources and phase gating)
- `.github/workflows/git-data-rung2-rehearsal.yml` (one `TF_VAR_rehearsal_attach_delay_s` line; no rationale prose, ADR-231)
- `scripts/git-data-rung2-plan-shape.sh`, `tests/scripts/test-git-data-rung2-plan-shape.sh`
- `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md` (dated entry; recovery order)
- `knowledge-base/engineering/operations/runbooks/git-data-rung2-rehearsal.md` (the deliberate late attachment, what a PASS now implies)
- `knowledge-base/engineering/architecture/decisions/ADR-239-git-data-serves-from-luks-at-birth.md` (amendment)

## Files to Create

None in source. Spec artifacts only: `knowledge-base/project/specs/feat-one-shot-git-data-bootstrap-attach-race/{decision-challenges.md,tasks.md}`.

Not edited, by design: `apply-web-platform-infra.yml` (sibling #10207 owns it), `scripts/lib/git-data-store-dirty-scan.sh`, `scripts/lib/git-data-boot-signal-poll.sh`, `scripts/followthroughs/git-data-rung2-evidence-capture.sh`, `apps/web-platform/infra/git-data-rung2-boot-evidence.env` (evidence is produced afterwards, alone, by its own PR).

## Open Code-Review Overlap

None. Queried open `code-review` issues (200 limit) for each file in Files to Edit on 2026-10-13; zero matches.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing today (inherited from #10175, 2026-10-13: the store flag is off and no repository is served from git-data). After the flip, a host that cannot finish first boot refuses every store action, so a Delete Account is refused and logged as an Art. 17 event until the host boots (runbook "If the fresh host fails a boot check"). Artifact: the user's repositories on the LUKS volume, unreachable until a good boot.
**If this leaks, the user's data is exposed via:**

- **Operator running the rotate (artifact: the half-rotated host's LUKS volume 107125716 and its passphrase):** a re-run destroys the volume; that it holds no user repository is inferred, not read (runbook entry, 2026-10-13), and whether the rotate's precondition can read a never-booted host is unverified.
- **Future served user (artifact: the plaintext legacy volume's contents):** a regression that skips or weakens the plaintext-empty check after a timeout, so a populated plaintext volume is served as verified; the wait returns only for a block device of size above zero, the FATAL is unchanged, and the Guard 1 rows drive the suite RED on an edit that removes either.
- **Art. 17 deleter (artifact: the erasure marker and `boot_complete` booleans):** a rehearsal evidence PR claiming the wait ran when the delay was not applied; the evidence file does not record the delay, so the evidence PR states it from the run log (rehearsal runbook).

**Brand-survival threshold:** aggregate pattern (planner default, challengeable; recorded as taste). Reason: fail-closed by construction, no user-facing path while the store flag is off, and the one dangerous edit is mutation-tested. The host's own evidence file calls it the store for every connected user's source code, so the threshold becomes `single-user incident` (with CPO sign-off) before the store flag flips; it does not need to for this fix.

## Observability

```yaml
liveness_signal:
  what: "Better Stack + Sentry stage=boot_complete from host soleur-git-data (once per boot, with plaintext_empty/fence_on_mapper/erasure_probe terminal booleans)"
  cadence: "once per host boot (and the rung-2 capture reads it per rehearsal boot)"
  alert_target: "Sentry rule git_data_boot_fatal; the boot poll's VERDICT line in the apply run"
  configured_in: "apps/web-platform/infra/git-data-bootstrap.sh (emit at the end), apps/web-platform/infra/issue-alerts.tf"
error_reporting:
  destination: "Sentry project web-platform (baked DSN) and Better Stack git-data source, stage=bootstrap"
  fail_loud: "log FATAL: plaintext_unverified reason=source — <link> does not resolve to a block device (unchanged text), after the bound"
failure_modes:
  - mode: "plaintext volume never attaches within the bound"
    detection: "stage=bootstrap level=fatal row with the unchanged FATAL sentence, in Sentry and Better Stack"
    alert_route: "Sentry git_data_boot_fatal rule; the replace/rotate poll ends VERDICT=silent or fatal"
  - mode: "invalid GIT_DATA_ATTACH_WAIT_S reaches the host"
    detection: "stage=bootstrap level=fatal row naming attach_wait_invalid; the seam is also stripped by env -u, pinned by census C2"
    alert_route: "same Sentry rule"
  - mode: "LUKS volume never attaches within the heredoc's 300 s"
    detection: "stage=luks_open level=fatal (isLuks rc=4 branch) from luks_err"
    alert_route: "same Sentry rule"
  - mode: "wait loop silently returns success on a miss"
    detection: "the mutation rows in git-data-bootstrap-store-verify.test.sh (CI), not a runtime signal"
    alert_route: "CI infra-validation job fails the PR"
logs:
  where: "runcmd detail file /run/git-data-runcmd.log, shipped as the fatal's cause only on failure; Better Stack git-data source"
  retention: "Better Stack source retention (inherited, not re-measured)"
discoverability_test:
  command: bash scripts/git-data-rung2-gate-verdict.sh
  expected_output: RELEASED or HOLD
```

The discoverability command prints the rung-2 gate's current verdict for the tree under test: HOLD after the payload edit (until the new evidence lands), RELEASED once the evidence PR merges.

## Encryption Posture

```yaml
at_rest:
  - store: "hcloud_volume.git_data_luks (served store, /dev/mapper/git-data)"
    mechanism: luks
    evidence: "apps/web-platform/infra/cloud-init-git-data.yml luks_open heredoc (cryptsetup luksFormat/luksOpen, passphrase via Doppler env, stdin only); unchanged by this plan except the device-wait literal"
    defends_against: "a seized or RMA'd disk; a raw volume snapshot"
    does_not_defend: "a leaked Doppler token holding GIT_DATA_LUKS_KEY; an unlocked running host; a root-level compromise of the host"
    disclosed_as: "ADR-239 (internal); public wording is under the CLO ruling tracked at #10138"
    live_verification: "available: boot_complete luks_mounted=yes fence_on_mapper=yes erasure_probe=yes"
  - store: "hcloud_volume.git_data (retained plaintext rollback copy, never mounted, read through a dm snapshot)"
    mechanism: plaintext-exception
    evidence: "git-data-bootstrap.sh 7b step 2; this plan only changes WHEN the link is resolved, never how the volume is read"
    defends_against: "nothing at rest (the exception is the retention window; the bootstrap proves it holds no repository before serving)"
    does_not_defend: "anyone with Hetzner API read of the detached or attached volume reading its blocks"
    disclosed_as: "ADR-239 Amendment 2026-10-12 (retention end re-opened, #6897)"
    live_verification: "available: boot_complete plaintext_empty=yes plaintext_volume=present"
in_transit: []
exception:
  justification: "retained plaintext rollback volume, destroy gated on a named operator command (inherited from #10138, 2026-10-13)"
  tracking_issue: "#10138"
  reevaluate_when: "the wipe PR lands, or 2026-11-05 (CLO notice threshold in the #10138 CTO ruling, inherited 2026-10-13)"
  expires_on: 2026-11-12
```

No new store and no new network connection are introduced; the rehearsal's two `terraform_data` resources hold no data.

## Guard Contract

### Guard 1 — Attach wait is bounded and fail-closed (bootstrap helper and both call sites)

**Property.** A rendered plaintext volume id ends in either the full snapshot verification (verdict identical to the on-time case) or the unchanged named FATAL after at most the configured bound, and no path past a timeout sets the volume absent, writes the marker, or skips verification.

**Assembly.** Every code path that resolves a by-id volume link in the payload set: `git-data-bootstrap.sh` section 1 (LUKS glob + `cryptsetup isLuks`, the predicate), the plaintext link site in 7b step 2 (`_pt_link` / `_pt_dev`), and the helper both flow through (chokepoint `_gd_attach_wait`). Also in the assembly, as separate guards below, the `luks_open` heredoc literal and the `env -u` strip. `git-data-luks-reopen.sh` resolves the by-id pin at reboot with its own 30 s wait and is out of scope (unchanged, its own suite).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | after the bound, fall through to verification instead of the FATAL (helper returns 0 on timeout) | RED: never-appears fixture exits 0 or writes the marker |
| 2 | on timeout set `_pt_id=""` / treat as absent (the exact fail-open forbidden) | RED: never-appears fixture reports rc 0 and `plaintext_volume=absent` |
| 3 | helper never called at the plaintext site (dispatch removed) | RED: the late-link fixture FATALs instead of proceeding (dead-arm check on the helper itself) |
| 4 | helper never called at the LUKS site, kept at the plaintext site (a second member after a compliant first) | RED: the late-LUKS fixture FATALs |
| 5 | bound ignored (hard-coded large loop), seam dropped | RED: the small-bound never-appears fixture exceeds the sleep-call cap |
| 6 | the wait call moved AFTER the first `realpath -e` resolution (REORDER, not delete) | RED: the late-link fixture still FATALs, because `_pt_dev` was resolved before the link existed |
| 7 | `udevadm settle` removed from the helper | RED: calls.log carries no `udevadm\|settle` before the first probe retry |
| 8 | invalid seam value falls back to 300 instead of FATAL | RED: the `abc` and `-5` fixtures expect `attach_wait_invalid` |
| 9 | the site probes once then only sleeps (predicate not re-evaluated each pass) | RED: the late-link fixture FATALs |
| 10 | success predicate loosened to `-e` (drops block-special and size > 0) | RED: the zero-size and regular-file fixtures must still FATAL |

**Harness rows.** (a) Suite-side edit that must RED it: set the `sleep` stub to never materialise the link and assert the never-appears row still passes only because of the FATAL (a stub that makes every run pass is caught by the paired late-link row going RED). (b) Must-PASS inputs that are not the canonical fixture: the link appears on the 1st sleep, on the last sleep before the bound, through a symlink chain (`by-id -> ../../x -> node`), and with bound 0 plus an already-present link (one probe, no sleep). (c) Floor: `MIN_ASSERTIONS` equals `passes + fails` after the change (floor == count, per ADR-193), plus the canary rows already present.

**Anchor.** The suite floor is a count; it is paired with set identity (every new row is named in the suite and the landed-check per mutation). What outside the commit must move for a weakening to pass: `scripts/guard-vacuity-floor.test.sh` builds a mutant from the floor block, and `infra-validation.yml` runs this suite on every PR; a weakened floor needs both to move.

### Guard 2 — The first-boot LUKS wait keeps a pinned, bounded literal

**Property.** The `luks_open` heredoc waits at most a fixed, literal number of passes for its device and still ends in the isLuks rc=4 FATAL when the device is absent; it never formats a device it could not probe.

**Assembly.** The single wait loop in the `luks_open` heredoc of `cloud-init-git-data.yml`; its pin is `git-data-luks.test.sh` B18 (i); the rung-2 runcmd rehearsal executes the template segment.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | literal changed in either direction (`-lt 30000`, or back to `-lt 30`) | RED: B18 (i) pins the exact literal, not a floor |
| 2 | `-gt 0` relaxed to `-ge 0` (presence, not usability) | RED: existing B18 (i) comparison arm |
| 3 | `udevadm settle` call removed from the loop | RED: new B18 row for the settle call |

**Harness rows.** A suite-edit row that deletes the pin and expects the arm to report a dead guard.

**Anchor.** Pinned literal in the suite; changing both the template and the pin in one commit proves consistency, not integrity. The outside check is the rung-2 hash: any template edit re-HOLDs the gate and forces a fresh rehearsal that must boot with the new literal.

### Guard 3 — The test seam cannot be set from Doppler

**Property.** `GIT_DATA_ATTACH_WAIT_S` is removed from the environment of the production bootstrap invocation before the script reads it.

**Assembly.** The single bootstrap `doppler run ... /usr/bin/env -u ... bash /usr/local/bin/git-data-bootstrap.sh` line in `cloud-init-git-data.yml`; census C2 in `git-data-store-device-census.test.sh` quantifies over the strip list.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `-u GIT_DATA_ATTACH_WAIT_S` removed, or its name misspelled | RED: C2 per-seam row (exact name) |
| 2 | the strip moved before `doppler run` (env stripped, then re-injected) | RED: C2 "env -u runs AFTER doppler run" |
| 3 | the invocation line reshaped so C2 extracts nothing (the guard's own dispatch) | RED: C2 "could not find the bootstrap's doppler invocation" |
| 4 | the new `-u` added while an existing seam's `-u` (e.g. `GIT_DATA_PLAINTEXT_DEV`) is dropped (a second member after a compliant first) | RED: C2 per-seam rows for the pre-existing seams |

**Harness rows.** Must-PASS: the strip list in a different order.

**Anchor.** Census floor and the template are edited together; the outside anchor is the rung-2 hash and the `-u` list's presence in the rehearsal's rendered user_data.

### Guard 4 — The rehearsal's late attachment is payload-phase only and defaults to zero

**Property.** The deliberate delay is applied only in the payload phase, is 0 unless set, and cannot replace or delay the seed phase or any production address.

**Assembly.** `rehearsal.tf` (two `terraform_data` resources and the two attachment dependencies), `variables.tf` validation, the workflow's single `TF_VAR_` line, `scripts/git-data-rung2-plan-shape.sh` admitted-replace list. Every address contains `.rehearsal` (existing contract in `git-data-rung2-rehearsal.test.sh`).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | the phase gate removed (seed phase sleeps the full delay) | RED: rehearsal suite row requiring `rehearsal_phase == "payload" ? ... : 0` |
| 2 | variable default changed from 0 | RED: default row |
| 3 | delay value placed in `triggers_replace` | RED: row that requires triggers to be exactly the server id |
| 4 | the plaintext attachment loses its `depends_on` (only the LUKS one delayed) | RED: row requiring BOTH attachments depend on a delay resource (D3: the LUKS path must be exercised too) |
| 5 | plan-shape admits a replace of any `terraform_data.*` (glob), or the create regex is widened to accept `[0]` | RED: plan-shape suite exact-match rows |

**Harness rows.** A must-PASS plan JSON with the two delay resources replaced alongside the three host replaces; a suite edit that removes the new plan-shape rows must trip that suite's floor.

**Anchor.** The harness is not hash-bound; the outside checks are the plan-shape suite fixtures (before merge) and the workflow's host-only plan-shape assertion (on the paid run; the dry run does not cover it).

## Infrastructure (IaC)

### Terraform changes

`rung2-rehearsal` root only: two `terraform_data` resources (built-in provider, no new provider pin), one variable, two `depends_on` edges. Production roots (`git-data.tf`, `modules/git-data-userdata`) are untouched. No new secret or sensitive variable.

### Apply path

Production: none by this PR (code only; the host changes only when an operator-authorized replace or rotate runs). Rehearsal: cloud-init-only on a throwaway host via the existing workflow; additive plan asserted by `git-data-rung2-plan-shape.sh additive` on dry run.

### Host fan-out

No `terraform_data` SSH provisioner is introduced (local-exec `sleep` on the runner). No fleet sibling is affected.

### Distinctness / drift safeguards

`rehearsal_phase` gating; the variable default 0 so an un-set run is the old behaviour; state of the rehearsal root is already per-run.

### Vendor-tier reality check

Hetzner attach latency is variable (17-125 s measured); the delay is a floor for the harness, not a claim about Hetzner.

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-239 (`soleur:architecture`, not a new ADR): a dated amendment recording that first boot may begin before volume attachments finish and that the bootstrap and the luks_open heredoc wait for them under a counted bound, fail-closed, with the seam stripped from production. This is an in-PR task (Phase 4), not a follow-up issue.

### C4 views

No C4 change. Checked against all three model files (`model.c4`, `views.c4`, `spec.c4`) on 2026-10-13: external actors, none new (no human role is added); external systems, none new (Hetzner control plane, Doppler, Sentry and Better Stack are modelled; the edges `gitDataStore -> sentry` and `gitDataStore -> betterstack` already describe boot-stage fatals); data stores, none new (`gitDataStore` is unchanged); actor-to-surface access relationships, none changed. Derived counts: `bash plugins/soleur/test/c4-count-parity.test.sh` exits with ALL TESTS PASSED (measured 2026-10-13).

### Sequencing

The amendment describes the target state and is written in this PR; its status line follows ADR-239's existing `adopting`/`accepted` handling and is not changed by this PR.

## Downtime & Cutover

- **Offline-inducing operations:** only the post-merge, separately authorized `git-data-host-replace` / `git-data-host-rotate` dispatches (this PR itself changes code and a throwaway rehearsal root). They destroy and recreate `hcloud_server.git_data`; the rotate also recreates the LUKS volume and passphrase.
- **Surface affected:** git-data transport and Art. 17 erasures only. Measured by inheritance (2026-10-13, #10175 and the runbook's flag text): `GIT_DATA_STORE_ENABLED` is off and the store serves no user repository, so the live cost is a window in which every Delete Account is refused and logged (runbook "What a user sees while git-data is not serving").
- **Zero-downtime evaluation:** blue-green is not available (one host, two volumes that attach to one server at a time, a fixed private address); `state mv` and expand-contract do not apply to a host whose payload changed (ForceNew). The default is therefore the existing replace route, run only while the flag is off, which is also why the fix must land and be rehearsed before the flip.
- **Bounded window:** the rotate's recorded duration is at least 12 min 15 s of a failed boot (inherited from the runbook's table, run 35979304442); this plan's change adds no time to a healthy boot (wait overlaps the apply's own attach wait, see Boot-budget analysis).
- **Residual downtime acceptance:** none requested here; each dispatch is gated on an explicit go-ahead naming the command. Per-stage verification and rollback: the poll's VERDICT, the `plan_only=true` dry run first, and the runbook's forward-only rule for a failed boot.

## Domain Review

**Domains relevant:** Engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Ruled by CTO agent, 2026-10-13, on forks D1-D5 (decision-challenges.md). Added constraints: the helper retries the whole predicate each pass (not "something exists"); validate the bound before the first probe; at bound 0 probe once; a harness bug burns one of two rehearsals per payload hash, so validate and plan-check the rehearsal root before any paid run; all edits to the two hash-bound files must land before the rehearsal; do not recommend a plain replace "just to test"; the "Hetzner serialises actions" claim is unmeasured and the bound must not depend on it.

Legal: no new exposure from this change (inherited 2026-10-13: the plaintext volume's retention end is under the CLO's ruling at #10138); schedule coupling noted in Risks. Product/UX: no user-facing surface; mechanical UI-surface override did not fire (no component, page or layout path in Files to Edit). GDPR gate: no schema, auth or API route touched and none of the four expansion triggers applies.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "add a bounded wait (default about 300s, overridable by an env seam for tests, with `udevadm settle`) so the plaintext link, and the LUKS device discovery, tolerate a late attachment" | Proposed Solution 1-4; Files to Edit (bootstrap, cloud-init) | mapped |
| 2 | "while staying FAIL-CLOSED (still the same named FATAL after the bound; never skip the plaintext-empty verification)" | Proposed Solution 2; Guard 1 | mapped |
| 3 | "Add tests in apps/web-platform/infra/git-data-bootstrap-store-verify.test.sh (link appears late -> proceeds; never appears -> same FATAL after the bound; MIN_ASSERTIONS floor and mutation rows per that suite's conventions)" | Phase 0; Test Scenarios; Guard 1 | mapped |
| 4 | "Check the total boot budget: ... a 300s wait plus the rest of bootstrap must fit, or say what has to change" | Boot-budget analysis | mapped |
| 5 | "The plan must say exactly what evidence file, hash and rehearsal run is needed afterwards, which workflow/command produces it, who dispatches it" | Rung-2 evidence section | mapped |
| 6 | "must check whether the rehearsal harness (rung2-rehearsal/rehearsal.tf etc.) can reproduce a late attachment, or whether it attaches volumes before first boot" | Research Reconciliation row 2; Proposed Solution 6; Guard 4 | mapped |
| 7 | "check whether the half-rotated host's current state ... has a documented recovery ... and whether recovery can avoid another destroying replace ... report it, do not execute it" | Recovery section | mapped |
| 8 | "A sibling PR #10207 ... note any overlap in the plan" | Overlap section | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| bootstrap helper + sites | "add a bounded wait (default about 300s ...)" | asked |
| luks_open heredoc wait (D2) | "the LUKS device discovery" | asked (the first-boot LUKS discovery is the heredoc, per Research Reconciliation row 1) |
| `env -u` strip + census row | "overridable by an env seam for tests" | inferred — justification: a Doppler key of that name would otherwise reach production bootstrap (the census C2 contract strips every seam) |
| rehearsal late-attachment harness (D3) | "check whether the rehearsal harness ... can reproduce a late attachment" | inferred — justification: the rehearsal that must run anyway is the only pre-prod proof of the new path; ruled in by the CTO (D3); separable if the operator objects |
| plan-shape script change | none | inferred — justification: the workflow's own additive/host-only plan assertion would refuse the two new rehearsal resources |
| ADR-239 amendment | none | inferred — justification: `wg-architecture-decision-is-a-plan-deliverable` (recorded architecture must not lag the change) |
| runbook entries | "report it" (recovery) and "exactly what evidence file, hash and rehearsal run is needed" | asked |
| PR comment on #10207 | "note any overlap in the plan" | asked |

### Split Assessment

- Subsystems touched: 5 — apps/web-platform, scripts, tests, .github, knowledge-base
- Planned files: 17 | Estimated changed lines: ~650
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the root-count threshold fires, the file and line thresholds do not. A split along "payload + tests" vs "rehearsal harness + plan-shape" is possible, but both halves must be on main before the single paid rehearsal can prove the fix, so the split adds a merge cycle on the critical path without reducing risk (taste, challengeable; recorded in decision-challenges.md).

## Acceptance Criteria

- [x] `git-data-bootstrap.sh` contains one `# ---- BEGIN attach-wait helper ----` / `# ---- END attach-wait helper ----` pair; the plaintext site and the LUKS site both call `_gd_attach_wait`; `bash -n` passes on the helper and on the whole script.
- [x] The plaintext FATAL sentence and the `no LUKS-formatted volume found` sentence are byte-identical to `origin/main` (static row compares them).
- [x] `bash apps/web-platform/infra/git-data-bootstrap-store-verify.test.sh` exits 0 with `MIN_ASSERTIONS` equal to `passes + fails` (the pre-change count is 412; the new rows add to it; record the measured final number in the PR).
- [x] Every mutation row in Guard 1 has a landed-check, an instrument self-test, and drives the suite RED when applied; the `sleep`-stub never-appears fixture proves `sleep` was called at most ceil(bound/10) times.
- [x] Late-link fixture: the link appears on the Nth `sleep` and the run proceeds to marker + all booleans, with `plaintext_volume=present plaintext_empty=yes` equal to the R1 on-time verdict.
- [x] Never-appears fixture: rc != 0, `FATAL: plaintext_unverified reason=source` with the unchanged sentence, no marker, FATAL emitted at stage=bootstrap, and no `blockdev --setro`, `dmsetup` or `mount` call.
- [x] `GIT_DATA_ATTACH_WAIT_S` of `abc`, `-5` and the empty string is refused (own FATAL, no probe); `0` probes once and, with the link present, proceeds.
- [x] `git-data-luks.test.sh` (B18 (i) literal 300 + mutation), `git-data-store-device-census.test.sh` (C2 strip row), `git-data-runcmd-rehearsal.test.sh`, `git-data-template-strip.test.sh`, `git-data-render-strip-parity.test.sh`, `git-data-rung2-rehearsal.test.sh`, `store-vs-data-mount-parity.test.sh`, `git-data-luks-reopen.test.sh`, `git-data-plaintext-snapshot-loopback.test.sh` (root/loopback needed; run where available), `tests/scripts/test-git-data-rung2-plan-shape.sh`, `tests/scripts/test-git-data-birth-readiness-gate.sh`, `scripts/guard-vacuity-floor.test.sh` and `plugins/soleur/test/terraform-target-parity.test.ts` pass locally.
- [x] `diff <(git diff --name-only origin/main...HEAD) <(bash -c 'source tests/scripts/lib/git-data-birth-readiness-gate.sh; git_data_rung2_bound_files apps/web-platform/infra/cloud-init-git-data.yml')` shows exactly `cloud-init-git-data.yml` and `git-data-bootstrap.sh` among the hash-bound inputs touched (reviewed 2026-10-13: tests, `rehearsal.tf`, `plan-shape.sh` and the workflow are not bound).
- [x] `bash apps/web-platform/infra/git-data-userdata-budget.sh --json` still reports `stored` <= 32,768 and `plugins/soleur/test/cloud-init-user-data-size.test.ts` passes; the measured headroom is recorded in the PR (pre-change 2,656 B).
- [x] `terraform validate` and a plan-only check of `rung2-rehearsal` with the delay variable at 0 and at 150 pass; the seed-phase sleep is 0; `git-data-rung2-rehearsal.test.sh` (which pins every poll's step bound above its deadline and the job ceiling above the step sum) passes with the documented +150 s per payload-phase boot absorbed by the existing apply step bounds (15/25/15 min; measured payload applies took 33 s and 34 s on 2026-10-13).
- [x] `bash scripts/git-data-rung2-gate-verdict.sh` on the PR head prints a line starting `git_data_rung2_rehearsal_gate: HOLD` (the payload moved the hash, so the committed evidence no longer matches); on `origin/main` before the merge it prints RELEASED.

### Handoff checklist (record-keeping, not pass/fail gates)

- The new payload digest (`git_data_rung2_user_data_sha256 apps/web-platform/infra/cloud-init-git-data.yml` at the PR head) is in the PR body.
- A PR comment exists on #10207 describing the `stale_boot_complete` wedge on a failed-boot host (no file of #10207 is edited here).
- The PR body lists the rehearsal, replace and rotate commands as unrun and gated on a go-ahead that names each command; no dispatch, apply, Doppler write, wipe or destroy was run from this branch.

## Test Scenarios

- Given the plaintext link is absent on probe 1 and appears after the 2nd `sleep`, when the unit runs with the default bound, then the verification verdict equals the on-time run and `udevadm settle` was called before each retry.
- Given the link never appears and the bound is 20, when the unit runs, then it FATALs with the unchanged sentence after at most 2 sleeps and writes no marker.
- Given the link appears but points at a regular file or a zero-size node, then the wait does not return success on it (still FATAL after the bound).
- Given an empty `GIT_DATA_PLAINTEXT_VOLUME_ID`, then no wait runs (no `sleep` call, `plaintext_volume=absent` as before).
- Given a LUKS device that appears on the 3rd pass while the plaintext volume is present from the start, then the extracted `luks-discover` unit finds the LUKS device (predicate re-scans every pass) rather than FATALing on "no LUKS volume".
- Given the heredoc template, then its wait literal is exactly the pinned value, counted, with a settle call, and still FATALs on absence (B18).
- Given the cloud-init bootstrap invocation, then `-u GIT_DATA_ATTACH_WAIT_S` is in the strip list after `doppler run` (C2).
- Given a rehearsal plan in the seed phase, then both delay resources sleep 0; in the payload phase they sleep the configured delay, are replaced with the host in the replace arm, and plan-shape admits exactly those two replaces.
- Verification (read-only, local, no dispatch): `bash apps/web-platform/infra/git-data-bootstrap-store-verify.test.sh` (about 35 s today), the other suites above, `bash scripts/git-data-rung2-gate-verdict.sh`.

## Rung-2 evidence the changed payload needs (post-merge; nothing here is run by this plan)

Editing `git-data-bootstrap.sh` and `cloud-init-git-data.yml` moves `git_data_rung2_user_data_sha256` (today `bfb0e5c2ecf05fa1d4bced4304b9211137d0c65e1a25b95c41f9b50bcbef554c`, measured 2026-10-13, equal to the committed evidence). The rotate job's own step "Rung-2 rehearsal interlock (refuses an un-rehearsed payload on the live host)" then refuses; so do `git_data_host_create` and the plain replace.

- **Evidence file:** `apps/web-platform/infra/git-data-rung2-boot-evidence.env`, regenerated (not edited by hand).
- **Hash:** `RUNG2_TEMPLATE_SHA256` = `git_data_rung2_user_data_sha256 apps/web-platform/infra/cloud-init-git-data.yml` evaluated at the `head_sha` of the rehearsal run (the merge commit of this PR on `main`, or later if other bound files change). The value is unknowable until the edit lands; the PR body records the digest at PR head, and the gate re-hashes the run's tree itself (`RUN_HASH_MISMATCH` otherwise).
- **Producing run:** `git-data-rung2-rehearsal.yml` dispatched from `main` (the gate refuses any other `head_branch`), `dry_run=false`, three boots on one address (seed, payload with the deliberate late attachment, replace arm). The run uploads the artifact `git-data-rung2-boot-evidence`; the run must conclude `success`.
- **Landing it:** an evidence-only PR (the runbook's "After a PASS": download, `mv`, append the Sentry ack only if the job summary said ACK REQUIRED, commit alone, validate with `git_data_rung2_rehearsal_gate`, `gh pr create`). Provenance guard 4 holds on any evidence commit that also touches a bound file, so no hash-bound merge may land between the run and the evidence PR; each such merge costs another paid run (cap 2 per payload hash). If the planned wipe PR (hash-bound per the #10138 CTO ruling, 2026-10-13, inherited) is ready before the dispatch, batch both under one rehearsal; do not hold this fix for it.
- **Commands, each dispatched only with the operator's go-ahead naming the command (none run here):**
  1. optional dry run: `gh workflow run git-data-rung2-rehearsal.yml --ref main -f confirm=REHEARSE-GIT-DATA -f dry_run=true`
  2. paid run: `gh workflow run git-data-rung2-rehearsal.yml --ref main -f confirm=REHEARSE-GIT-DATA -f dry_run=false` (plus the `web-platform-infra-apply` environment approval)
  3. after the evidence PR merges and, if #10207 merged as drafted, a plain replace first: `gh workflow run apply-web-platform-infra.yml --ref main -f apply_target=git-data-host-replace -f reason="<why, #10138>"` (plan-only variant: add `-f plan_only=true`)
  4. the rotate: `gh workflow run apply-web-platform-infra.yml --ref main -f apply_target=git-data-host-rotate -f confirm=ROTATE-GIT-DATA -f plan_only=true`, then the same with `plan_only=false` (destructive: destroys the LUKS volume and re-mints the passphrase; any escrow of the previous key goes stale, no claim about re-escrow, #9949)
- **What a PASS means here:** the payload boot ran with the plaintext attachment delayed about 150 s and the LUKS attachment about 75 s, and still emitted `boot_complete` with every terminal boolean `yes`. The old code would FATAL under the same delay, so a PASS implies the wait ran. It is an inference (no new field, ruling D4), not a measurement of the wait; one rehearsal at 150 s does not prove the 300 s bound.
- **Gate-clearing check, local, no SSH:** `bash scripts/git-data-rung2-gate-verdict.sh` prints RELEASED once the evidence PR is merged.

## Half-rotated host: recovery, reported not executed

State (inherited from the brief and the run log, 2026-10-13): new server 170081857 (failed first boot, old payload), new LUKS volume 107125716 created and keyed (inferred 2026-10-13: runcmd is `set -e`, so the bootstrap only ran after the heredoc's luksFormat/luksOpen succeeded), plaintext volume 106867358 attached (never mounted; the check died before `blockdev --setro`), old server and old LUKS volume 107102614 destroyed by the rotate, new pin published to Doppler with `pin_load` skipped (inherited from the runbook's "Boot order on the replace" section, 2026-10-13; not re-read from Doppler here), `d6_last_rotate_failed 38384137515`.

- **Documented recovery:** `git-data-luks-cutover-5274.md` "If the fresh host fails a boot check after step 3" says start with a read, never another replace; the fix is forward (PR, rehearsal, evidence PR, replace) and takes hours to days; `git-data-birth.md` states that a half-built host is not completed in place ("That host must be replaced, not completed"). #10138 records the same ordering and the dispatch commands (CTO ruling 2026-10-13). Neither document covers an attach-race failure specifically; Phase 4 adds a dated entry.
- **Can it avoid another destroying replace? No for the server, yes for the LUKS volume.** `user_data` is ForceNew and has no `ignore_changes` (git-data.tf), so the fix reaches a host only as a new server; there is no non-SSH way to re-run first boot (runcmd once-per-instance, ADR-115 excludes git-data from the reboot primitive). The half-rotated server holds no store data (flag off, store empty). A plain `git-data-host-replace` destroys and recreates only that server and keeps both volumes and the keyed LUKS volume; a rotate destroys the LUKS volume and re-mints the passphrase again, but only a successful rotate carrying the `Rotate completed (d6 marker)` supersedes the d6 failure, so a rotate is still required to discharge D6.
- **Order (ruled D5):** fix PR, rehearsal, evidence PR, then the rotate directly; if #10207 merged as drafted, a plain replace first (it produces a `boot_complete` newer than the server), then the rotate. A plain replace "just to test" is not recommended (it adds a host build with no gate benefit).
- **Read-only checks to run before any dispatch (no mutation):** `gh run view 38384137515 --log` (done; timeline above), Sentry events d0ea5097b7c04ebeb30b44e534f13be6 and fb7acfa69ca546f5946988caa7fd73cd (inherited from the brief), the pin and `GIT_DATA_STORE_ENABLED` flag state read-only through the existing cutover `mode=proof` route if the operator names it.
- **No claim is made about passphrase loss, re-escrow or reopening.** The previous key's escrow state is outside this plan.

## Overlap with sibling PR #10207

- Files: disjoint. #10207 edits `apply-web-platform-infra.yml`, `git-data-cutover.yml` (message), and creates `scripts/lib/git-data-store-dirty-scan.sh` plus its test; this plan edits none of them. Neither plan's files are in the 20 hash-bound inputs of the other, so #10207 does not void the rung-2 evidence and this plan does not conflict on rebase.
- Behavioural overlap (blocking for the recovery, not for either merge): #10207's layer 3 requires the newest `boot_complete` to be strictly newer than the current server's creation time. Server 170081857 never booted, so the next rotate would be refused (`stale_boot_complete`) until a plain replace yields a `boot_complete`. Ruled D5: this PR does not edit #10207; a PR comment suggests not blocking a host that has no `boot_complete` after its creation. The ordering above covers both outcomes.
- Both PRs must merge before the rotate re-dispatch; this plan adds the rehearsal to that critical path.

## Dependencies & Risks

- Dependency: the rehearsal run needs the harness change merged first (same PR) and the `web-platform-infra-apply` environment approval.
- Risk (cap): only 2 rehearsals per payload hash; any later edit to a bound file, even a comment, costs one. Mitigation: all payload edits land before the dispatch; the harness is validated locally first.
- Risk: the delay resource lengthens the rehearsal by about 150 s per payload-phase boot; verified against the capture deadlines in the work phase.
- Risk: a bound of 300 s is 2.4 x the worst observed attach; a slower attach still ends in the named FATAL (fail-closed), so the failure mode is unchanged, not worse.
- Schedule coupling (inherited 2026-10-13, #10138): the CLO ruled no extension of the plaintext volume past 2026-11-12 and asked to be told if the wipe PR cannot land by about 2026-11-05. This fix, the rehearsal and the rotate sit ahead of the flip chain; if the sequence above slips, tell the CLO (operator-only schedule decision, not made here).
- Risk: the `blockdev --getsize64` call is a new origin-naming call before `--setro`; the suite's origin-call allowlist must classify it as a read-only identity probe or the Guard 1 row 7 check goes RED (planned in Phase 0).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6; this one declares `aggregate pattern`.
- `MIN_ASSERTIONS` is checked against the call-site counter and must equal `passes + fails`; bump it by the measured number, never by estimate.
- `git-data-luks.test.sh` B19d pins the exact `cryptsetup luksOpen --key-file - "$luks_dev"` spelling; wrapping the LUKS loop in the helper must not change that line.
- The extracted store-verify unit does not contain section 1; the helper must be defined above it and prepended to the harness prelude, or every runtime row sources a unit that calls an undefined function.
- The workflow file is byte-budgeted (ADR-231): one `TF_VAR_` line, rationale in the runbook.
- Evidence must be committed alone; a PR that also touches a bound file is HELD by provenance guard 4.
- The census C2 row pins `-u GIT_DATA_PLAINTEXT_DEV GIT_DATA_PLAINTEXT_VOLUME_ID='${git_data_volume_id}' bash /usr/local/bin/git-data-bootstrap.sh` as an adjacency regex (`git-data-store-device-census.test.sh` ~line 263): add `-u GIT_DATA_ATTACH_WAIT_S` EARLIER in the list, never between `-u GIT_DATA_PLAINTEXT_DEV` and `GIT_DATA_PLAINTEXT_VOLUME_ID=`.
- Seam validation spelling: copy the precedent from `git-data-luks-reopen.sh` (`case ... ''|*[!0-9]*)`), add a length cap, and do the arithmetic only after validation (a non-numeric operand under `set -e` aborts rather than being caught).
- `_pt_same` re-checks the device number through link and node before `--setro`, `dumpe2fs` and `dmsetup create`; resolving `_pt_dev`/`_pt_mm` later (after the wait) must not remove or reorder those re-checks, and the suite's `>= 7` stat-read row must stay green.
