---
title: "chore(infra): strip the dead plaintext-volume resolver arm (PLAIN_ID) from cloud-init-inngest.yml at the next planned inngest host replace"
date: 2026-10-12
slug: strip-inngest-plain-id-resolver
branch: feat-one-shot-9786-strip-plain-id-resolver
issue: 9786
type: chore
priority: p3-low
domain: engineering
lane: single-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
status: PARKED (prepare + review + hold as draft; do not merge until a host replace is scheduled)
---

# Strip the dead PLAIN_ID resolver arm from the Inngest cloud-init (PARKED change)

## Enhancement Summary

**Deepened on:** 2026-10-12
**Sections enhanced:** Research Reconciliation, Decisions (D6 added), Phases 0/3/4/5/6/7, Guard Contract, Scope Check, Encryption Posture, Acceptance Criteria, Risks
**Method:** plan-time research (repo-research reads of the cited files, learnings-researcher, read-only GitHub/CI evidence) plus a 6-seat plan-review panel (DHH, Kieran, code-simplicity per-mechanism, architecture-strategist, spec-flow, CTO devex lens), then the deepen-plan halt gates run mechanically: 4.6 User-Brand Impact (present, threshold single-user incident), 4.7 Observability (5 fields; the discoverability command `bash apps/web-platform/infra/inngest-userdata-budget.sh --json` measured 0.67 s, prints `stored_bytes`), 4.8 PAT sweep (no hits), 4.9 UI wireframe (no UI surface, skipped), 4.10 Encryption Posture (fields filled; placeholder `n/a` values replaced), 4.11 Guard Contract (`python3 scripts/lint-guard-contract.py` rc=0 after the matrix labels were fixed: 3 guards, rows counted), 4.12 Scope Check (restructured to the canonical Ask Mapping / Plan-Item Provenance / Split Assessment schema). A 40-agent fan-out was deliberately not run: the change is a deletion with an already 6-seat-reviewed design, and the agent panel would re-derive the same file reads.

### Key Improvements
1. Reconciled the brief's "merge replaces the host" reading against code: per-merge apply prunes `hcloud_server.inngest`; the park rationale is restated on verified grounds (latent replace, drift red, `server_touched` abort, and an unexercised new boot path).
2. Found the provision-rehearsal root as a second renderer of the same template (raw volumes, no pointer): the no-pointer arm is kept and re-pointed (D2) instead of deleted.
3. Plan review found D2 would make `luksFormat` newly reachable on the sole copy; D6 (refuse to format when the rendered config is `prd`, `blkid -p`) and UNP5 close it.
4. Test-suite assertions the first draft missed are now named (T1.8a 4->3, delete T1.8a2, G1.a 6->4, G1.b, loopback `run_arm` signature, floors set from measured/CI runs).

### New Considerations Discovered
- The AC5 test map is extracted by a regex anchored on its FIRST key; removing the key without moving the anchor yields an empty list.
- The `parked` label does not exist and must be created; autonomous merge paths must be verified to skip drafts/label before ship ends.
- Pointer verification must read the VALUE (`pointer=` on the `stage=resolve` row), not a Doppler name list; re-run at unpark.
- No automated bring-up exists for a brand-new blank prd volume after the strip (DR procedure to be written when needed).


Ref #9786. Follow-up of #8285 (retire the plaintext Redis AOF backstop). Draft PR #10081.

## Overview

#8285 destroyed the plaintext Redis AOF backstop volume (Hetzner id 106261946) on 2026-10-09 and kept
`hcloud_server.inngest` from replacing by pinning the cloud-init template input `inngest_volume_id` to the
literal retired id, so the rendered `user_data` stayed byte-identical (ADR-142 addendum, D1). The price is
dead code that still ships in `user_data`: the `PLAIN_ID` resolver arm, its pre-cutover blkid discriminator
and the `inngest_expect_luks` pre-recut branches in the boot-reopen script.

This plan **prepares** that removal (code, tests, ADR amendment), takes it through review, and **parks it**
as a reviewed draft PR. It does NOT merge, apply, replace, reboot, dispatch or write to production. The
change is a `user_data` edit, so it only takes effect when `hcloud_server.inngest` is next replaced
(`apply_target=inngest-host-replace`, maintenance window, explicit approval) - a window that is not
scheduled today (see Research Insights, Premise Validation).

Scope is exactly what #9786's body lists, plus one consumer the issue did not name (the provision-rehearsal
root, a second renderer of the same template) and one decision the removal forces (what the resolver does
when the pointer is absent - see Decision D2). Out of scope: web-2 workspaces volume, git_data volume, the
rehearsal volumes themselves, ADR-198 baked credentials, the `rollback)` arm in the image-baked
`inngest-luks-cutover.sh` (needs an image release + pin bump; named in the #9786 comment), and the
`inngest_expect_luks` Terraform variable (D4).

## Research Reconciliation - Spec vs. Codebase

| Claim (brief / issue) | Reality (verified on `origin/main` 0aae3f8680 + this worktree) | Plan response |
|---|---|---|
| "A merge of cloud-init-inngest.yml would make the per-merge apply plan a host replace." | The per-merge `apply` job is an explicit `-target=` allow-list that contains **no** `hcloud_server.*`; `hcloud_server.inngest` is in `OPERATOR_APPLIED_EXCLUSIONS` (`plugins/soleur/test/terraform-target-parity.test.ts`), and `inngest-host.tf`'s own precondition comment states `-target` PRUNES this resource on merge (so even its user_data-cap precondition is not evaluated there). `hcloud_server.inngest` has `ignore_changes = [ssh_keys]` only - no `user_data` - so the diff is a ForceNew replace *whenever the server is planned*. `hcloud_firewall_attachment.inngest` in the allow-list is a `removed {}` tombstone, not a live resource, so it does not pull the server in. | **Reading corrected, conclusion kept.** Merging does not itself replace the host. It plants a latent replace that (1) shows as `must be replaced` in the twice-daily untargeted `scheduled-terraform-drift.yml` plan and the unscoped `infra-validation.yml` plan, (2) makes every additive `apply_target=inngest-host` dispatch abort at `inngest_host_shape_gate reason=server_touched`, and (3) rides the next replace dispatch un-reviewed as part of whatever that window was for. All three are reasons to park; AC-P1 asserts them from code. |
| "There is no inngest-host-replace workflow on main." | There is no standalone workflow *file*, but `apply_target=inngest-host-replace` is a dispatch choice and job (`inngest_host_replace`) in `apply-web-platform-infra.yml`, gated by `inngest_host_replace_gate` (exact scoped recreate; refuses a Redis AOF volume destroy). Last non-skipped `inngest_host_replace` job: 2026-10-08T19:22Z (before the backstop retirement). No run since; no open issue/PR/plan names a window. | Record as the read-only window check; "no window planned" holds. |
| Issue: strip "the pre-cutover four-arm blkid discriminator over `$DEV`" | That discriminator is also the ONLY path that formats a blank volume on a host with no pointer. `inngest-provision-rehearsal/rehearsal.tf` renders the same `cloud-init-inngest.yml` with two RAW scratch volumes, `inngest_expect_luks="false"` and **no pointer** in its scratch Doppler env, and the live `inngest-provision-rehearsal.yml` gate (last 3 dispatches green, 2026-10-10/11) requires its first boot to reach `bootstrap-done`. A pointer-only resolver would refuse that boot. `hr-fresh-host-provisioning-reachable-from-terraform-apply` also requires a fresh host stay provisionable. | D2: the no-pointer arm is not deleted, it is re-pointed at the one remaining volume (`LUKS_ID`) and loses its ext4 arm. D6 (plan review, 4 of 6 seats): the format arm is refused when the rendered Doppler config is `prd`, because re-pointing otherwise turns an accidentally-safe state (pointer lost -> device wait on a destroyed volume refuses) into one where a lost pointer plus a blank-reading sole-copy volume runs `luksFormat`. |
| Issue: "`inngest_expect_luks` pre-recut branches in `inngest-luks-open.sh`" | `inngest_expect_luks` also appears in the first-boot stage (ARM 1 refusal + telemetry field `expect_luks=`) and in `variables.tf`, `rehearsal.tf`, three test suites. | D4: remove the two branches that read it; keep the template key, the variable and the telemetry field (a separate, tracked follow-up retires them). |
| Issue comment (2026-10-10): also remove the dead `rollback)` arm in `inngest-luks-cutover.sh` | That script is baked into the digest-pinned bootstrap image (`cloud-init-inngest-bootstrap.test.sh` GuardA requires byte-identity with the pinned tag; `.claude/hooks/grep-q-pipe-guard.test.sh` carries the same carrier note). Editing it needs a new image build and a pin bump. | Out of scope for this PR (non-goal N2). Consequence of dropping `INNGEST_LUKS_PLAIN_VOLUME_ID` from `/etc/default/inngest-luks-volumes`: a flagged cutover/rollback run refuses `volume-ids-unreadable` (fail-closed). See Risks R3. |
| AC5 floor 17 | Actual key count at the `inngest-host.tf` call site today is **18** (floor `-ge 17`, over-read bound `-le 18`). The test's map extraction is anchored on the literal `{ inngest_volume_id=` (first key) and would silently return an empty list when that key goes. | After the change the count is 17: floor stays 17, bound tightens to 17, anchor moves to `{ inngest_luks_volume_id=`. |
| `inngest-host-state`/ledger claim: rehearsal LUKS row opens "`inngest_luks_volume_id` ... as mapper `inngest-redis`" | Today the rehearsal's `inngest-redis` mapper sits on the *plain* scratch volume (`inngest_volume_id`), so the ledger row `hcloud_volume.rehearsal_inngest_luks` describes behaviour the code does not have. | D2 makes that row true. Not claimed as a goal; verified by `scripts/lint-encryption-posture.py` at work time. |

## Research Insights

### Premise Validation (Phase 0.6)

Checked: #9786 OPEN (priority p3-low, not closed by any merged PR); #8285 CLOSED, #9877 (PR B) MERGED
(f1e4cf2cb1); #8620 OPEN (root-disk encryption; inngest row names `apply_target=inngest-host-replace` as its
rebuild window, none scheduled); draft PR #10081 exists for this branch, `isDraft: true`,
`autoMergeRequest: null`. Cited paths exist on `origin/main`: `cloud-init-inngest.yml` (2230 lines),
`inngest-host.tf`, `inngest-userdata-budget.sh`, `inngest-boot-emitter.test.sh`,
`inngest-redis-luks.test.sh`, `inngest-redis-luks-loopback.test.sh`, `inngest-luks-cutover.sh`,
`inngest-provision-rehearsal/rehearsal.tf`. ADR corpus (Phase 0.6 item 4): ADR-142 addendum D1 already
records this exact deferral ("The dead plaintext resolver arm stays in `user_data` until the next replace
that is already scheduled for another reason (#9786)"), so the mechanism is not a rejected alternative -
it is the scheduled follow-through. Held: all premises. Stale: the brief's per-merge-replace reading
(Reconciliation row 1) and "no replace workflow" wording (row 2). Window check (read-only):
`gh run list --workflow=apply-web-platform-infra.yml` job census shows the last `inngest_host_replace`
execution on 2026-10-08 and three `inngest_backstop_retire` runs on 2026-10-09; no open issue, PR or plan
names a future window. Sibling replace-class work exists but is also unscheduled: #7827 (comment-only fix
in PR #8945 - comment lines are stripped from `user_data`, so likely render-identical), #9962 (PR #10073,
real `user_data` change), #6780, #8620.

### Property List (Phase 0.6b)

1. After the strip, `user_data` contains no reference to the retired plaintext volume id and no code path
   that can mount, open, format or probe a volume other than `inngest_luks_volume_id`.
2. A host with the pointer set to the LUKS volume boots through the same pointer arm as today (behaviour
   preserving for the only configuration production has).
3. A NON-production host (rendered Doppler config != `prd`, i.e. the provision-rehearsal) with NO pointer
   and a RAW LUKS-target volume still provisions: format, open, mkfs, mount, verify - and never against an
   ext4 or foreign signature. A production-config host (`prd`) NEVER runs `luksFormat` from the unpointed
   arm (D6); it opens an existing LUKS volume or refuses.
4. A host whose pointer is absent and whose volume is already `crypto_LUKS` opens it (never reformats).
5. Nothing can silently re-introduce the key or the pin: reintroduction reds a test.
6. The change cannot reach production before a replace is scheduled (parked draft, no auto-merge).

### Cut List (Phase 0.6b)

| Mechanism proposed/implied | Property it buys | Verdict |
|---|---|---|
| Keep `local.inngest_retired_plaintext_volume_id` as a dead pin | none once the key is gone | CUT (the D1 pin exists only to feed the key). `inngest-host.test.sh` D1 v2/v3 and rows keyed on it go with it; v1/v4 ("retired addresses stay undeclared and unreferenced") stay. |
| A new `FRESH_VOLUME` arm written from scratch | property 3 | CUT - the existing ARM 0/2/3/4 text over `$DEV` already is that arm; re-point `DEV` at `LUKS_ID`, delete only ARM 1. |
| Removing the pointer mechanism too (one volume, so no pointer needed) | none required by #9786 | CUT. The pointer arm is the production path (property 2); touching it widens the diff and the review. Fork P stays. |
| New alert/probe for the stripped boot | none needed | CUT. The existing `SOLEUR_INNGEST_LUKS_STAGE` stages, `logtail_exploration_alert.inngest_luks_wrong_volume` and the rehearsal capture already observe it (see Observability). |
| Removing `inngest_expect_luks` (variable, template key, rehearsal line, 3 suites) | none required by #9786 | CUT to follow-up (D4). |

### Institutional learnings applied

- `2026-10-06-which-files-feed-user-data-with-no-ignore-changes-decides-whether-a-mechanical-edit-is-a-host-replace.md`: `cloud-init-inngest.yml` is a file-exact `user_data` carrier; merging replaces nothing on the per-merge leg; the replace happens later on a different run. Sweep sibling suites that pin the file by TEXT (GuardA, `grep-q-pipe-guard.test.sh` row `cloud-init-inngest.yml | = | 4`).
- Template escaping traps (`2026-04-06-doppler-cli-checksum-cloud-init.md`, `2026-05-19-inngest-substrate-five-bug-cascade.md`, the #7695 `$$VAR` incident quoted in the file itself): deleting an arm can orphan `$$` pairs; `templatefile-bare-dollar-guard.test.sh` and T1.13/T1.14 are the gates.
- `2026-07-16-a-mutation-battery-only-covers-what-you-mutate.md`, `2026-07-15-false-comment-shipped-the-bug...`: deleting an arm leaves its test rows vacuous; prove each removed branch unreachable and each surviving anchor still bites (Guard Contract below).
- `2026-07-16-a-drift-guard-can-recreate-its-own-bug...`: the AC5 anchor on `{ inngest_volume_id=` is exactly this class.
- `2026-07-24-guest-luks-store-must-gate-consumer-on-mount...`: the strip must still fail loud, never fall back to plaintext.
- `cloud-init-user-data-size`: measure with terraform's own `base64gzip` (`inngest-userdata-budget.sh --json`), baseline measured today: stored 19,680 B, headroom 13,088 B of 32,768 B.

### Sibling-PR overlap (rebase plan)

| PR | State | Touches in `cloud-init-inngest.yml` | Overlap with this change |
|---|---|---|---|
| #10073 `condition-gate non-LUKS units on staged env files` (Closes #9962) | draft | one hunk at the `inngest-redis`-family unit text near line ~1418 (adds `ConditionPathExists=/etc/default/inngest-doppler`); also `inngest-bootstrap.sh`, `inngest-cutover-flip.{service,timer}`, `inngest-redis.service`, `inngest.test.sh`, `cloud-init-inngest-provision-unit.test.sh`, rehearsal-capture script | **None textual.** This plan's hunks are confined to (a) the boot-reopen script body (lines ~155-252) and (b) the first-boot LUKS stage heredoc (lines ~1590-1975). Disjoint from ~1418. Both change `user_data`, so both ride the same replace; whichever merges second rebases mechanically. Keep this plan's `inngest.test.sh` edits to zero. |
| automated bootstrap-pin-bump PRs (`build-inngest-bootstrap-image.yml` -> `bump-inngest-bootstrap-pin.sh`) | recurring | four image pins in this file | Already make `user_data` differ from deployed on every merge, so the drift/`server_touched` consequences are partly pre-existing; pin lines are outside this plan's two regions. |
| #8945 `[bot-fix] nft -f comment` (Ref #7827) | ready | comment-only hunk at line ~67 in the nftables unit | None. Whole comment lines are stripped by `inngest_rationale_strip`, so it is render-identical. |

Rebase rule for the parked PR: the diff is limited to the two regions above in this file; if a sibling
lands first, `git rebase origin/main` should apply without conflicts; re-run the targeted suites and
`inngest-userdata-budget.sh` after every rebase.

## User-Brand Impact

**If this lands broken, the user experiences:** the sole Inngest scheduler host comes up after a replace
with no mounted `/mnt/data` (the resolver refuses), `inngest-redis.service`'s mount guard declines to start,
and every scheduled agent, cron and armed reminder in the product stops firing until the host is repaired -
on a host with no SSH, no console and deny-all-public ingress. If the resolver instead formatted the wrong
device, the Redis AOF (queued and in-flight job payloads: user prompts and agent output) would be lost with
no second copy.

**If this leaks, the user's data is exposed via:** no new surface. The change removes code; it adds no
secret, port, endpoint or log field. The LUKS volume remains the only copy and the passphrase stays in
Doppler `soleur-inngest/prd` plus Terraform state. The one exposure-adjacent edge is that the stripped
resolver must never mount the encrypted store's ext4 sibling or a foreign signature in plaintext - covered
by the refuse arms and tests below.

**Brand-survival threshold:** single-user incident (host-replace blast radius: merging-then-replacing
replaces the sole scheduler; the Redis AOF volume is LUKS and the sole copy, retained across the replace but
dependent on the cloud-init resolver opening it correctly). The change is infra-only and parked; the
exposure window opens only when a replace is dispatched, and the plan makes the dispatch a separate,
explicitly approved act. `requires_cpo_signoff: true`; `soleur:engineering:review:user-impact-reviewer`
runs at review time.

## Open Code-Review Overlap

None. Queried open `code-review` issues for each file in Files to Edit (`jq --arg path ... contains($path)`);
zero matches.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "strip the dead plaintext-volume resolver arm (PLAIN_ID / rollback resolver) from apps/web-platform/infra/cloud-init-inngest.yml" [brief] | Phase 2 (Region A + Region B), D1, D2 | mapped |
| 2 | "plus the matching inngest_volume_id map key and its consumers named in the issue body (inngest-host.tf, inngest-userdata-budget.sh, inngest-boot-emitter.test.sh AC5 key-set parity floor, the inngest-redis-luks*.test.sh suites, inngest-luks-open.sh pre-recut branches)" [brief] | Phase 3 (3.1, 3.3, 3.4), Phase 4 (4.1, 4.2), Phase 2 Region A | mapped |
| 3 | "the plan must PREPARE the change (code + tests), take it through review, and open/keep the PR as a DRAFT clearly marked PARKED" [brief] | Phase 6 (6.1-6.5), D5 | mapped |
| 4 | "Do a read-only check whether any inngest host replace is planned (open issues/PRs/plans, workflow dispatch history)" [brief] | Research Insights - Premise Validation, Phase 0.2 | mapped |
| 5 | "the plan must verify this reading from hcloud_server.inngest lifecycle / ignore_changes and the destroy-guard in apply-web-platform-infra.yml" [brief] | Research Reconciliation row 1, AC-P1 | mapped |
| 6 | "the plan must name the overlap and keep this change's hunks narrowly scoped to the PLAIN_ID arm so a later rebase is mechanical" [brief] | Sibling-PR overlap table, Phase 2 hunk discipline, AC8 | mapped |
| 7 | "NEVER touch web-1 LUKS volume 106443278 ... do not pin it. Do not change prevent_destroy or delete_protection. Do not touch betteruptime_heartbeat.inngest_server_probe." [brief] | Non-Goals N4, AC11 | mapped |
| 8 | "state the host-replace blast radius honestly (merging would replace the sole-scheduler host; the Redis AOF volume is LUKS and sole copy)" [brief] | User-Brand Impact, Infrastructure (IaC) Apply path, Risks R1 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Region A / Region B edits in cloud-init-inngest.yml | asks 1-2 | asked |
| inngest-host.tf, inngest-userdata-budget.sh, inngest-boot-emitter.test.sh, luks suites | ask 2 | asked |
| inngest-provision-rehearsal/rehearsal.tf map line | - | inferred - justification: the rehearsal root renders the same template; leaving a key the template no longer reads is a misleading dead input in a second renderer |
| inngest-host.test.sh D1 rows and local deletion | - | inferred - justification: the pin local exists only to feed the removed key; its guard rows would be red against the new tree |
| D2 unpointed arm kept (re-pointed) | ask 1 (the issue's literal removal would break the provision-rehearsal gate and hr-fresh-host-provisioning-reachable-from-terraform-apply) | inferred - justification: enforcement contract - the live rehearsal gate and the fresh-host rule need a no-pointer boot |
| D6 `prd` guard on the format arm + `blkid -p` | - | inferred - justification: safety - D2 makes `luksFormat` newly reachable on the sole copy; plan review found the regression |
| MODE value rename | - | inferred - justification: a telemetry value naming a LUKS volume `plaintext_canonical` would be a false label (DC5) |
| variables.tf description edit | - | inferred - justification: an inert input that still reads as live is a maintainer trap (CTO review) |
| ledger rehearsal-row text | - | inferred - justification: the encryption-posture lint resolves these rows against the code the strip changes |
| ADR-142 amendment, ADR-199 pointer | - | inferred - justification: plan-skill Phase 2.10 - ADR-142 D1 recorded this deferral, so the resolution belongs with the change |
| `parked` label, base-SHA staleness rule, unpark checklist | ask 3 | asked |

### Split Assessment

- Subsystems touched: 3 - apps/web-platform/infra (cloud-init, tf, tests), scripts (ledger), knowledge-base (ADR/runbook)
- Planned files: 13 | Estimated changed lines: ~700 (mostly deletions)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Decisions

- **D1 - What "strip" removes (unreachable-after-strip, not merely PLAIN-named).** Everything reachable
  only when the plaintext volume could be canonical or staged: `PLAIN_ID`; `DEV` as the plaintext path;
  ARM 1 (ext4 mount) and its `EXPECT_LUKS` refusal; the whole "STAGING - the additive volume, pre-cutover
  only" block (`STAGING_DEV`, `STAGING_MAPPER`, `inngest-redis-staging`, `/mnt/data-luks`) because it runs
  only when `MODE != pointer` and its purpose (staging the second volume beside the plaintext store) is
  gone; the `INNGEST_LUKS_PLAIN_VOLUME_ID=` line; in the reopen script the `elif expect_luks` branch, the
  `reopen_skip_plaintext` emit and the staged-volume open. The pointer arm body is untouched.
- **D2 - The no-pointer arm survives, re-pointed at the one remaining volume.** `DEV` is redefined as
  `"$${BYID}$${LUKS_ID}"` so ARM 0 (bounded wait), ARM 2 (`crypto_LUKS` -> open + mount, never format), ARM 3
  (raw -> luksFormat/open/mkfs/mount) and ARM 4 (any other signature -> refuse) keep their text
  byte-for-byte. ARM 1 (ext4) is deleted, so an ext4 signature now falls to ARM 4's "unhandled signature"
  refusal - strictly safer than today (today ext4 mounts when `expect_luks=false`). `MODE` for the no-pointer
  world is renamed from `plaintext_canonical` to `unpointed` (it is a telemetry value; consumers verified:
  only the cloud-init file and the loopback suite name it). The `resolve` allowlist case becomes
  `""` -> unpointed, non-numeric -> refuse, `"$LUKS_ID"` -> pointer, `*` -> refuse (a pointer naming the
  retired plaintext id is now a third-id refusal). Why not "pointer required": it breaks the live
  provision-rehearsal gate and violates `hr-fresh-host-provisioning-reachable-from-terraform-apply`. Why not
  also drop the pointer: property 2 / Cut List.
- **D6 - The unpointed arm may not FORMAT on a production-config host (added at plan review).** Today a
  prod boot with a lost Doppler pointer dies harmlessly at ARM 0 (the retired plaintext device no longer
  exists). After D2 the same state would reach `LUKS_ID`, the sole copy; a damaged header reads as blank
  (blkid rc 0/2, empty type) and ARM 3 would `luksFormat` it. ARM 3 therefore gains one guard line at its
  top: `[ '${inngest_doppler_config}' = prd ]` -> `echo FATAL ... unpointed_raw_refused` + `exit 1` (**amended: now a `rehearsal_*` allowlist, see Review Round Amendments**). The
  value is already a template key (`prd` for prod, `rehearsal_<runid>` for the rehearsal), so no new key and
  AC5 stays at 17. ARM 2 (open an existing LUKS volume) stays available on `prd`, so a lost pointer with an
  intact volume still boots. The first-boot unpointed probe also switches from cached `blkid` to `blkid -p`
  (the pointer arm and the reopen script already use `-p`), so a stale cache from an aborted attempt cannot
  decide a destructive arm. Rejected: a new `inngest_fresh_provision` template key (key count 18, one more
  input to keep in parity across `.tf`, rehearsal and tests) and reusing `inngest_expect_luks` (defaults
  false and `T1.11c` pins that). Consequence, stated plainly: there is no automated bring-up path for a
  brand-new BLANK prd volume (the pointer arm refuses blank too, and the staging block that used to format
  the additive volume is deleted). That is a disaster-recovery procedure, to be written as a runbook step
  when it is ever needed (the volume carries `prevent_destroy` + delete protection); recorded in the ADR
  amendment, not built here.
- **D3 - `/etc/default/inngest-luks-volumes` keeps the ADDITIVE line only.** The cutover/flip units key
  `ConditionPathExists` on this file; leaving the file and dropping one line keeps unit activation
  unchanged. The image-baked `inngest-luks-cutover.sh` then refuses any flagged run with
  `volume-ids-unreadable` (`is_uint "$PLAIN_ID"` fails) - the cutover is complete, its dispatch is deleted,
  and a refuse is the fail-closed outcome.
- **D4 - `inngest_expect_luks` stays as an input.** Template key, `variables.tf` variable, `rehearsal.tf`
  line and the `expect_luks=` telemetry field stay, so the change remains narrow and Better Stack queries
  keyed on that field keep working. After the strip the value no longer gates behaviour. A tracking issue
  "retire the now-inert `inngest_expect_luks` input at the same replace window" is created at ship time
  (deferral-tracking gate), milestone per roadmap.
- **D5 - Merge-hold is enforced by process, not by code.** The PR stays `draft`, titled with a `PARKED`
  marker, body carries a "DO NOT MERGE until an approved `inngest-host-replace` window" block, no
  `gh pr merge --auto`, no ready-for-review. Rejected: adding a CI check that blocks the merge (new
  guard surface for a one-PR hold; the draft state already makes GitHub refuse to merge).

## Implementation Phases

### Phase 0 - Read-only preconditions (no edits)

- 0.1 HARD STOP GATE. Confirm prod boots in pointer mode (so property 2 is the production path): query
  Better Stack for the latest first-boot `SOLEUR_INNGEST_LUKS_STAGE stage=resolve` row, expect
  `mode=pointer pointer=106903269` (`scripts/betterstack-query.sh --grep 'stage=resolve'`, read-only
  token). The `pointer=` field is the VALUE check (a Doppler name-list read cannot show it). If it reads
  anything else, STOP and re-plan: the premise that the pre-cutover arm is dead is false. State this stop
  condition in the PR body too, and re-run it at unpark (today's result goes stale).
- 0.1b Confirm the cutover flag is terminal: the latest `SOLEUR_INNGEST_LUKS_CUTOVER` row reads
  `flag=done` (log read, not a Doppler read). A non-terminal flag would make the image-baked cutover timer
  refuse `volume-ids-unreadable` every 30 s after the strip (R3).
- 0.2 Re-run the window check (`gh run list` job census for `inngest_host_replace`, open issues/PRs/plans);
  record the result in the PR body. If a window has been scheduled by then, unpark per Phase 7.
- 0.3 Baselines (record, do not edit): `bash inngest-userdata-budget.sh --json`; AC5 key count (18);
  assertion floors of the suites touched (luks 64, loopback 85, host 99, boot-emitter verdict floor).

### Phase 1 - Tests first (`cq-write-failing-tests-before`)

Write the red tests before the cloud-init edit; each must fail on the current file.
- 1.1 `inngest-redis-luks.test.sh`: new structural assertions - no `PLAIN_ID`, no `inngest_volume_id`, no
  `INNGEST_LUKS_PLAIN_VOLUME_ID`, no `STAGING_`, no `reopen_skip_plaintext`, no `mount_ext4` in the template
  (comment-stripped view); `DEV=` is derived from `LUKS_ID`.
- 1.2 `inngest-host.test.sh`: D1 v2 becomes "zero `inngest_volume_id` assignments in any `*.tf` under the
  root" (reintroduction guard), v3 deleted; mutation rows updated (Guard Contract).
- 1.3 `inngest-boot-emitter.test.sh`: render map and anchor move to `{ inngest_luks_volume_id=`.
- 1.4 loopback arms (Phase 4) written as expected-fail first where the arm is new (UNP3-UNP5).

### Phase 2 - `cloud-init-inngest.yml` (two regions only)

Region A - `/usr/local/bin/inngest-luks-open.sh` (boot-reopen script):
- A1 delete `PLAIN_ID='${inngest_volume_id}'`; `DEV="$${BYID}$${LUKS_ID}"`; delete `STAGING_DEV`.
- A2 pointer branch: allowlist `case "$POINTER" in "$LUKS_ID") ;; *) fail reopen_pointer ...` (drop
  `"$PLAIN_ID"|`); message reworded to "is not this host's volume".
- A3 no-pointer path: keep `wait_dev "$DEV"`, `luks_type "$DEV"`; `crypto_LUKS` -> `open_as`; anything else
  -> `fail reopen_not_luks 1 "$${BLK_TYPE:-empty}" "the volume is not crypto_LUKS"` (deletes the
  `elif expect_luks` and `else emit reopen_skip_plaintext` arms).
- A4 delete the trailing "additive volume, staged under the NON-canonical name" block entirely.
- A5 keep `emit()` (its `expect_luks=${inngest_expect_luks}` field stays, D4). Re-count `$$` usage: bare `$`
  everywhere except before a brace (the #7695 rule).

Region B - first-boot LUKS stage heredoc (`LUKSEOF` block):
- B1 delete `PLAIN_ID='${inngest_volume_id}'`; `DEV="$${BYID}$${LUKS_ID}"`; delete `STAGING_DEV`,
  `STAGING_MAPPER`; update the "THE TWO VOLUMES" comment to "THE ONE VOLUME" (comment lines are stripped
  from `user_data`; keep the text honest anyway).
- B2 `STAGE=volume_ids`: keep the numeric check for `LUKS_ID`; delete the `PLAIN_ID` numeric check and the
  `PLAIN_ID != LUKS_ID` distinctness check.
- B3 `STAGE=resolve` case: as D2.
- B4 `luks_key_stage`: delete the `printf ... INNGEST_LUKS_PLAIN_VOLUME_ID=%s\nINNGEST_LUKS_ADDITIVE_VOLUME_ID=%s`
  pair's first field (D3): `printf 'INNGEST_LUKS_ADDITIVE_VOLUME_ID=%s\n' "$LUKS_ID"`; the following
  `grep -qx` assertion stays unchanged.
- B5 `if [ "$MODE" = pointer ]; then ... else ... fi`: the pointer arm is untouched. In the `else`
  (unpointed) arm delete ARM 1 (`ext4)` case and its `EXPECT_LUKS` refusal); keep ARM 0/2/4 unchanged;
  ARM 3 gains the D6 guard line (refuse when `'${inngest_doppler_config}' = prd`; **amended to the `rehearsal_*` allowlist**) as its first statement;
  the `blkid_probe` line gains `-p` (D6). `STAGE=` names for these arms are unchanged.
  Keep `EXPECT_LUKS='${inngest_expect_luks}'` and the `luks_emit` field (D4).
- B6 delete the `if [ "$MODE" != pointer ]; then ... STAGING ... fi` block (STAGING_* stages).
- B7 `STAGE=verify`: simplify `if [ "$MODE" = pointer ] || [ "${BLK_TYPE:-}" != ext4 ]` - with ext4
  unreachable the else branch (`mounted_from /mnt/data "$DEV"`) is dead; delete the else branch and keep the
  mapper checks unconditionally (both arms end on the mapper). Keep `luks_emit verify ... mode=$MODE`.
- B8 Do not touch any other region (nftables, zot, doppler, vector, bootstrap, restage units).

Hunk discipline: two regions, ~150 deleted lines, ~12 changed lines, zero added logic. A reviewer should be
able to read the diff as "deletions plus three re-pointed lines".

### Phase 3 - Terraform and measurement consumers

- 3.1 `inngest-host.tf`: delete `inngest_volume_id = local.inngest_retired_plaintext_volume_id` (and its
  4-line comment) from the `templatefile` map; delete the `locals { inngest_retired_plaintext_volume_id }`
  block and its lead-in comment, keeping the "Retired plaintext AOF backstop (#8285)" prose as a plain
  comment (the retired-address guard v1/v4 still keys on the resource names, not on the local). Update the
  `inngest_luks_volume_id` comment ("needs BOTH ids") to "the ONE volume's id". **Do not** touch
  `hcloud_volume_attachment`, `prevent_destroy`, `delete_protection`, `hcloud_server` lifecycle, or
  `betteruptime_heartbeat.inngest_server_probe`; **do not** pin the volume attachment.
- 3.2 `inngest-provision-rehearsal/rehearsal.tf`: delete only the `inngest_volume_id = hcloud_volume.rehearsal_inngest.id`
  map line (the root's own volumes/attachments are out of scope). Re-check `inngest-provision-rehearsal.test.sh`.
- 3.3 `inngest-userdata-budget.sh`: delete the `inngest_volume_id = "100000004"` stub and its header bullet
  only (`inngest_luks_volume_id` stays interpolated twice - once per reader - so its bullet is unchanged).
  Re-measure; expect stored bytes to drop slightly (the D6 guard line adds a few bytes; net must still be
  below the 19,680 B baseline). The stale measured-figures comment in `inngest-host.tf` is NOT touched
  (unasked; separate chore).
- 3.5 `variables.tf`: description-only edit on `variable "inngest_expect_luks"` marking it inert after the
  strip ("retired by #<tracker>; no longer gates any boot behaviour"). No default or type change (`T1.11c`
  pins `default = false`); a description is not part of any plan diff.
- 3.4 `inngest-boot-emitter.test.sh`: remove `inngest_volume_id="v", ` from `RENDER_EXPR`; anchor
  `grep -oE '\{ inngest_luks_volume_id=.*\}'`; floor stays `-ge 17`, bound `-le 17`; update the history
  comment ("18 -> 17: #9786 drops inngest_volume_id").

### Phase 4 - Test suites

- 4.1 `inngest-redis-luks.test.sh`: sed render line (`s/\${inngest_volume_id}/.../` removed); T1.10
  (`inngest_expect_luks` reaches BOTH readers) must still hold - reopen reader still carries the emit field,
  runcmd reader the `EXPECT_LUKS=` line; G4.d4 (pointer arm never references `"$DEV"`) stays and is now
  stronger; G4.e needle `'"$PLAIN_ID"|"$LUKS_ID")'` -> `'"$LUKS_ID")'`. Assertions the first draft missed
  (plan review, Kieran): **T1.8a** counts exactly 4 `fstab_set /mnt/data "$(DEV|MAPPER) ..."` writes - 3 after
  ARM 1 goes; **T1.8a2** asserts the `/mnt/data-luks` fstab write - delete it; **G1.a** blkid-site floor
  6 -> 4 with the accounting written beside it (reopen probe, `pointer_blkid_probe`, `pointer_mapper_probe`,
  unpointed `blkid_probe`); **G1.b** loop references `STAGING_MAPPER` - remove it; G1.e/G1.f/G1.g (staging
  mkfs/open/canonical-name) are deleted with the staging block, G1.e survives in its "every mkfs targets
  `$MAPPER`" form. New assertions from Phase 1.1 as ONE whole-file comment-stripped absence check (not
  per-reader tables) plus the `DEV` derivation assertion and the D6 guard-line assertion. Recompute the
  structural floor (64) from a measured run and write the delta beside it.
- 4.2 `inngest-redis-luks-loopback.test.sh`: render seds drop `inngest_volume_id`. `run_arm`'s positional
  signature is `<plain-loop> ... <staging-loop> <pointer>`: drop the plain/staging params and attach every
  fixture device at the `LUKS_ID` by-id alias (re-key the ARM0 assertion ~461, BOOT2 `ln -sf` ~315/~544, and
  the fixtures that inspect the staging mapper; PTR4 ~538 opens its fixture as `inngest-redis-staging` only
  to inspect it - give it a neutral inspection mapper name). Arms deleted: ARM1, REG, ST1-ST3, BOOT2
  pre-cutover staged reopen, the `PLAIN_ID` alias fixtures. Arms re-keyed (they ARE the unpointed arms after
  the `DEV` re-point, so no duplicate UNP rows are added for them): ARM0 (absent), ARM2 (LUKS opens, never
  formats), ARM3 (raw formats, rendered with a non-`prd` config), ARM4 (foreign signature refuses), ARM1b
  becomes "ext4 REFUSES regardless of expect_luks" (UNP3). Kept: ARM2b, PTR1, PTR2, PTR4, PTR3 re-keyed to a
  synthetic third id, BOOT2-under-pointer, mount-guard states. New arms: UNP3 (above), UNP4 (reopen unit,
  no pointer: LUKS opens; ext4 fails `reopen_not_luks`), UNP5 (no pointer + RAW volume + rendered config
  `prd` REFUSES, nothing formatted - the D6 mutation guard). Floor: the suite needs root/losetup and its own
  header says the current 85 is projected, so the new floor is set from the FIRST CI run with the per-arm
  delta documented; never lowered without accounting. CI is the authority; locally run it only if the
  harness reports available.
- 4.3 `inngest-host.test.sh`: D1 rewrite (Guard Contract 2; `d1_violations` globs `"$dir"/*.tf`
  non-recursively, so reintroduction in `rehearsal.tf` is covered by `inngest-provision-rehearsal.test.sh`,
  not by D1); update `INNGEST_HOST_MIN_ASSERTIONS` (99) to the measured new count.
- 4.5 Ledger: the rehearsal rows in `scripts/encryption-posture-ledger.json` (`hcloud_volume.rehearsal_inngest`
  plaintext-exception row and `hcloud_volume.rehearsal_inngest_luks`) describe the pre-strip device roles;
  re-read both and update only the text the strip falsifies (the `_luks` row becomes true). Verify with
  `python3 scripts/lint-encryption-posture.py` + its test. Rehearsal volume resources are NOT edited.
- 4.4 Sweep sibling suites that pin this file by text (carrier checklist): `templatefile-bare-dollar-guard.test.sh`,
  `cloud-init-inngest-bootstrap.test.sh` (GuardA / pins), `cloud-init-inngest-provision-unit.test.sh`,
  `inngest.test.sh` (grep it for `PLAIN`, `inngest-luks-volumes`, stage names - read-only; expect zero edits),
  `inngest-provision-rehearsal.test.sh`, `journald-config.test.sh`, `.claude/hooks/grep-q-pipe-guard.test.sh`
  (row `cloud-init-inngest.yml | = | 4` must still read 4), `plugins/soleur/test/cloud-init-user-data-size.test.ts`,
  `scripts/lint-encryption-posture.test.sh` + `python3 scripts/lint-encryption-posture.py` (ledger anchors
  `cryptsetup luksFormat --batch-mode` and `luksOpen --key-file - "$DEV" inngest-redis` must still resolve),
  `scripts/guard-vacuity-floor.test.sh`.

### Phase 5 - Architecture record

- 5.1 Amend ADR-142's 2026-10 addendum (D1) with a short dated note (keep it to a few lines): "Resolved by
  #9786 (parked; applies at the next replace). The input and dead arm are removed. The no-pointer arm
  resolves the single LUKS volume ('one candidate, no choice to make', so ADR-142 section 2's 'a pointer, never
  a signature' still holds where a choice exists) and may not format when the rendered config is `prd`
  (D6). D1's byte-identical-user_data principle is knowingly abandoned at the window." Status "adopting".
  Add a superseded-by pointer in ADR-199 where it describes ARM 1 / `reopen_skip_plaintext` / `expect_luks`
  (~lines 238-262). No rejected-alternatives prose in the ADR (settled in this plan).
- 5.2 C4: no change (see Architecture Decision section).
- 5.3 Runbook sweep: `knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md` and
  `inngest-server.md` - grep for `mode=plaintext_canonical`, `INNGEST_LUKS_PLAIN_VOLUME_ID`,
  `reopen_skip_plaintext`, `staging_`; edit only live-procedure references (history stays history). Add the
  two behaviour notes an operator would otherwise trip on: an unpointed non-LUKS reopen now FAILS
  (`reopen_not_luks`) where it used to skip with exit 0; and a blank volume on a `prd` host has no automated
  bring-up (D6). The image-baked `inngest-redis-bootstrap.sh` mount-guard's "pre-recut plaintext" state is
  now unreachable but is a baked carrier: left alone (N2 family).

### Phase 6 - Review and park (the ship phase STOPS HERE)

- 6.1 Targeted local suites only (Test Scenarios); CI is the authority for the full battery.
- 6.2 Push; run `soleur:review` on the diff (agents: architecture-strategist, code-simplicity-reviewer,
  security-sentinel, user-impact-reviewer (threshold = single-user incident), observability-coverage-reviewer,
  test-design-reviewer, data-integrity-guardian for the luksFormat arm). Resolve findings in-branch.
- 6.3 Commits: `chore(infra): strip the dead PLAIN_ID resolver arm from cloud-init-inngest.yml (Ref #9786)`
  with trailer `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`. Never `Closes`/`Fixes`.
- 6.4 PR #10081: retitle `PARKED: chore(infra): strip the dead PLAIN_ID resolver arm (Ref #9786)`; body =
  summary, the merge-consequence bullets (Reconciliation row 1), the Phase 0.1 hard-stop condition, the
  base SHA + date and the staleness rule (if more than a handful of commits have touched
  `apps/web-platform/infra/*inngest*` or the three guarded suites since the base, re-validate, do not
  rebase blindly; the diff is re-reviewed at unpark), the unpark checklist (Phase 7), `Ref #9786`, ends with
  the line `🤖 Generated with [Claude Code](https://claude.com/claude-code)`. Create (`gh label create parked --color D4C5F9 --description "PR intentionally held; do not merge"`; the label does not exist today - verified `gh label list`) and apply a `parked`
  label (autonomous merge paths - drain-prs, one-shot, merge-pr - must be verified to skip drafts and that
  label before ship ends; do not assume). Keep it `draft`. Do NOT mark ready. Do NOT arm auto-merge. Do NOT
  run `soleur:ship` Phase 6+ merge steps, `gh pr merge`, or `postmerge`. Link #10081 from #8620, #9786 and
  #10073 so the hold is discoverable.
- 6.5 Ship-time gates that apply to a draft: create ONE combined cleanup tracker (retire the now-inert
  `inngest_expect_luks` input; N2 `rollback)` arm + image release + pin bump - a third replace-class
  change; the rehearsal root's unused plain volume R4), re-evaluation criterion "when #10081 unparks",
  milestone per roadmap; compound/learning capture.
  `wg-block-pr-ready-on-undeferred-operator-steps` is satisfied by the explicit PARKED state.

### Phase 7 - Unpark checklist (documented in the PR body; NOT executed in this run)

> **Revised in the #10081 review fix rounds.** The first version asked for a rehearsal dispatch against the
> branch. `inngest-provision-rehearsal.yml` runs under `environment: web-platform-infra-apply`, which carries a
> main-only deployment-branch policy (the workflow says so: a branch dispatch could run a neutered plan-shape
> guard), so it CANNOT be dispatched from this branch. The rehearsal therefore runs from main after the merge,
> inside the same window, and the abort path is a revert BEFORE any replace dispatch. Round 2 added the
> #7228 inherited-`done` stall (the replace is not finished until the scheduler serves), the rehearsal's
> `dry_run=false` + confirm token, and narrowed what the capture script is claimed to automate.

When an approved `inngest-host-replace` window exists (or #8620 reaches the inngest rebuild window):
1. `git rebase origin/main` (apply the staleness rule); re-run Phase 4 suites + `inngest-userdata-budget.sh`.
2. Re-run Phase 0.1 and 0.1b immediately before the merge, and record both in the PR:
   - `pointer=106903269` read as a VALUE from the latest `stage=resolve` row **of the live host**. Select the
     live host by an EXACT host-name match applied to the query result (`host == soleur-inngest`), not by a
     `--grep` substring: `scripts/betterstack-query.sh --grep` is a substring OR-match, so `host=soleur-inngest`
     also matches `soleur-inngest-rehearsal-<run id>` rows, which read `mode=unpointed pointer=absent` and must
     not be mistaken for the live host (that mistake fails safe, as a STOP, but sends the check the wrong way).
   - **Zero rows fallback:** the live host emits `resolve` rows only at first boot, so a short window can return
     none. Widen the query window until the latest `stage=resolve` row for the live host appears. If none can be
     found at all (the last first boot is older than the log source retains), the second source is the Doppler
     VALUE of `INNGEST_LUKS_ACTIVE_VOLUME_ID` on `soleur-inngest/prd`, read through the approved read-only path
     and compared to `106903269` without printing it. If neither source confirms it, STOP: an unverified pointer
     is a third-id refusal on a host with no SSH.
   - The LUKS cutover flag (`INNGEST_LUKS_CUTOVER` on `soleur-inngest/prd`; its rows are
     `SOLEUR_INNGEST_LUKS_CUTOVER ... flag=`) reads `done`. D3 leaves the image-baked cutover script refusing every
     flagged run (`volume-ids-unreadable`); a refusal writes the terminal flag `aborted` (`PHASE` is still `init`
     at `assert_ids`, so never `copied`) and restores nothing unless a freeze record exists. At `done` the unit is
     a no-op (`noop-done`). Any other value is a STOP. This is a different flag from the scheduler's
     `INNGEST_CUTOVER_FLIP` (see step 5).
   - The scheduler's flag `INNGEST_CUTOVER_FLIP` (Doppler `soleur-inngest/prd`; the replace job's preflight step
     prints it) reads `done` or `flushed`. Those are the only two values whose stranded scheduler recovers with one
     `op=resume` dispatch. `armed` and `flipping` drive the FSM to `aborted` (`op=resume` accepts `done` only), and an
     unset or any other value makes the replaced host refuse EVERY prod start: for any of those, STOP, because the
     replace would leave the sole scheduler dark with no one-dispatch recovery.
3. Merge IMMEDIATELY before step 4, in the one window (merging alone plants the drift alert and the
   `server_touched` abort). Check the drift issue body stays under its 60,000-byte `head -c` cap (a `user_data`
   diff is large).
4. Dispatch `inngest-provision-rehearsal.yml` from main with `dry_run=false` and the confirm token
   `REHEARSE-INNGEST-PROVISION` (the default `dry_run=true` renders and asserts the plan and produces NO capture,
   so a default dispatch would clear this gate vacuously). It is the only end-to-end proof of the unpointed
   fresh-provision arm on a real boot; it never exercises the pointer arm. The capture script automates ONE
   check for this change: ZERO `stage=unpointed_raw_refused` rows (a row means the `rehearsal_*` allowlist and the
   rehearsal Doppler config disagree). The positive evidence is read by hand from Better Stack for the rehearsal
   host: `stage=resolve ... mode=unpointed` and `stage=verify`. **If either is wrong: revert the merge BEFORE any
   replace dispatch** (the live host is untouched until step 5).
5. Dispatch `apply_target=inngest-host-replace` under its own reviewer gate. **The replace is not finished when the
   dispatch reports success** (#7228, `inngest-server.md` "Inherited `done` after a host replace"):
   `INNGEST_CUTOVER_FLIP=done` lives in Doppler and outlives the host, while the `done-owner` marker lives on the
   root disk the replace destroys, so the new host inherits a `done` it never earned and `inngest-server` stays
   `activating http_code=000` until `gh workflow run cutover-inngest.yml -f op=resume` is dispatched AND
   approved (its environment carries a required reviewer; the replace job's `::warning::` prints this
   recovery). Then verify, positive: `stage=resolve ... mode=pointer pointer=106903269`, `stage=verify`,
   `inngest-luks-reopen-armed`, probe row `data_mount_devid=scsi-0HC_Volume_106903269`, AND the scheduler
   serving (probe `server_active=active`, or the `SERVING=yes` verdict of the host-state reader in
   `inngest-server.md`). Negative: zero `stage=unpointed_raw_refused`, zero `volume-ids-unreadable`, zero
   `inngest-luks-FAILED`, and the `SOLEUR_INNGEST_LUKS_CUTOVER` rows read `noop-done`. **Abort path:** a failed
   first boot leaves the sole scheduler dark with no SSH; recovery is a revert of this PR plus a second,
   separately approved `inngest-host-replace` dispatch, which strands on the same inherited `done` and needs the
   same `op=resume` (the pointer arm is byte-identical to main, so a failure here points at the rendered
   inputs, not the production path).
6. Fold #10073, any pending bootstrap-pin-bump PR and other pending `user_data` PRs into the same window
   deliberately, one dispatch. Saved Better Stack queries keyed on `mode=plaintext_canonical` must be
   re-keyed to `mode=unpointed`.

## Review Round Amendments (2026-10-12, #10081)

Appended; the decisions above are not rewritten. **D6 is amended from a denylist to an allowlist.** Where this
plan says the format arm refuses "when the rendered config is `prd`" (Decisions D6, the Phase 2 and Phase 3 text,
UNP5, AC14), the shipped guard is `case '${inngest_doppler_config}' in rehearsal_*) ;; *) ... exit 1 ;; esac`:
only a `rehearsal_*` config may format, so `prd`, an empty value and any value added later all refuse
(`unpointed_raw_refused`, with `STAGE=unpointed_raw_refused` set on the line before so the failure row names the
arm). The review found the one-literal denylist fails open for any other string. Test pins: T1.16g (shape), T1.16i
(the arm's own segment executed with the stage's state across seven configs), T1.16j (stage name), T1.16k (the
glob and rehearsal.tf's `rehearsal_<run id>` are one contract), loopback UNP5 and UNP5b. The structural-cause
finding (guards matching one spelling in one window) is closed by the whole-template closed-set pins T1.17f-i.

**D4 is reversed (review fix round 3, binding CTO ruling A).** The plan kept `inngest_expect_luks` as an inert
input and filed its retirement for "the same replace window". The code-simplicity reviewer dissented on that
scope-out and the CTO ruled it into this PR: nothing in the repo reads the `expect_luks=` field, and any later
retirement changes `user_data` again, replacing the sole scheduler a second time. Retired here: the `variables.tf`
variable, the template key, the `emit()` and `luks_emit` field and the `EXPECT_LUKS=` assignment (cloud-init), the
`inngest-host.tf`, `rehearsal.tf` and budget-script lines, and the test seds and params. The AC5 key set is **16**
(floor and bound in `inngest-boot-emitter.test.sh`); where this plan says 17 keys (Test Scenarios 1, AC5), read 16.
T1.10 is now a negative guard (no infra, script or workflow file names the input); T1.11a-c went with the
variable. This changes rendered `user_data` (the `expect_luks=` field leaves the stage rows); the production
pointer arm stays byte-identical.

## Files to Edit

- `apps/web-platform/infra/cloud-init-inngest.yml` (Regions A and B only)
- `apps/web-platform/infra/inngest-host.tf`
- `apps/web-platform/infra/inngest-userdata-budget.sh`
- `apps/web-platform/infra/inngest-boot-emitter.test.sh`
- `apps/web-platform/infra/inngest-redis-luks.test.sh`
- `apps/web-platform/infra/inngest-redis-luks-loopback.test.sh`
- `apps/web-platform/infra/inngest-host.test.sh`
- `apps/web-platform/infra/inngest-provision-rehearsal/rehearsal.tf` (one map line)
- `apps/web-platform/infra/variables.tf` (description-only edit on `inngest_expect_luks`, Phase 3.5)
- `scripts/encryption-posture-ledger.json` (rehearsal rows' text only, Phase 4.5, if the lint shows drift)
- `knowledge-base/engineering/architecture/decisions/ADR-142-inngest-redis-aof-zero-data-loss-luks-migration.md` (addendum note)
- `knowledge-base/engineering/architecture/decisions/ADR-199-destructive-clearance-requires-a-measured-empty-store-and-a-dark-host.md` (superseded-by pointer only)
- Runbook lines only if Phase 5.3 finds live-procedure references.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-9786-strip-plain-id-resolver/tasks.md` (plan tail)
- `knowledge-base/project/specs/feat-one-shot-9786-strip-plain-id-resolver/decision-challenges.md` (plan tail)

Explicitly NOT edited: `inngest-luks-cutover.sh`, `inngest-luks-cutover.test.sh`, `inngest-redis-bootstrap.sh`
(N2, image-baked), `variables.tf` beyond the one description, `inngest-redis-luks.tf`, `inngest.test.sh` (expect zero), `apply-web-platform-infra.yml`, `betterstack-logs-alerts.tf`.

## Architecture Decision (ADR/C4)

### ADR
Amend ADR-142's 2026-10 addendum (D1 follow-through; see Phase 5.1). No new ADR: the strip executes a
decision ADR-142 already recorded; D2 (re-pointing the no-pointer arm) is an implementation consequence
inside Fork P's existing "pointer decides, signature corroborates" contract, recorded in the amendment.

### C4 views
No C4 change. Checked all three model files (`model.c4`, `views.c4`, `spec.c4`): the only Inngest elements are
`inngest` (container), `inngestPostgres`, `inngestRedis` (description already states LUKS at rest; names no
plaintext volume) and the `views.c4` include line for `platform.infra.inngest*`. External actors/systems
touched by this change: none new (Hetzner, Doppler, Better Stack, zot are already modeled and no edge changes);
data stores touched: `inngestRedis` only, unchanged; actor-to-surface access relationships: none change.
Verify with `plugins/soleur/test/c4-count-parity.test.sh` (the cardinalities gate) at work time.

### Sequencing
The ADR note is written now with status "adopting - effective at the next host replace".

## Infrastructure (IaC)

### Terraform changes
`inngest-host.tf` (template map key + local removed), `inngest-provision-rehearsal/rehearsal.tf` (one map
line). No new resources, providers or variables; no sensitive values. `hcloud_server.inngest` plans a
ForceNew replace purely from the `user_data` diff.

### Apply path
`terraform apply -replace` via the existing `apply_target=inngest-host-replace` dispatch (option b), at an
approved window. NOT in this run. Expected downtime: the sole scheduler is dark for the replace (minutes);
the LUKS volume is retained and re-attached (`inngest_host_replace_gate` refuses a volume destroy).
Blast radius: every scheduled agent/cron/reminder for that interval; AOF is retained but is the SOLE copy.

### Host fan-out
Not applicable (no `terraform_data` SSH provisioners are edited; `plan-host-fanout` classification: the
inngest host is a singleton; web-1/web-2/git-data/registry are untouched).

### Distinctness / drift safeguards
`hcloud_server.inngest` keeps `ignore_changes = [ssh_keys]` (not widened to `user_data`); the user_data-cap
`precondition` (<= 32,768 B) is unchanged and this change only shrinks the payload; `prevent_destroy` and
`delete_protection` on the volume/passphrase pair are untouched; the volume attachment stays deliberately
unpinned. State-storage notes unchanged.

### Vendor-tier reality check
No vendor-tier-gated resource is created.

## Encryption Posture

```yaml
at_rest:
  store: hcloud_volume.inngest_redis_luks (Redis AOF, sole copy)
  mechanism: luks (guest-side cryptsetup luks2, passphrase in Doppler soleur-inngest/prd INNGEST_REDIS_LUKS_KEY and TF state)
  evidence: scripts/encryption-posture-ledger.json row hcloud_volume.inngest_redis_luks; apparatus anchors in cloud-init-inngest.yml (`cryptsetup luksFormat --batch-mode`, `cryptsetup luksOpen --key-file - "$DEV" inngest-redis`) - unchanged by this plan, re-verified by lint-encryption-posture.py
  defends_against: a seized/RMA'd/snapshot-imaged volume
  does_not_defend: a leaked credential, an app-layer read on the unlocked host, a root-disk read (the passphrase is cached at /etc/default/inngest-luks - tracked #8620), and loss of the sole copy
  disclosed_as: not-publicly-claimed
  live_verification: unavailable:no per-volume LUKS-type probe field yet (ledger row text); wrong-volume alert + resolve/verify stage rows are the runtime evidence
in_transit:
  - connection: none added or changed (no new socket, endpoint or peer)
    tls: unchanged - this change touches only on-host block-device resolution
    cert_verification: on (unchanged elsewhere)
    does_not_defend: no connection is introduced; the posture of existing connections is outside this change
    disclosed_as: not-publicly-claimed
```

This change removes the only code that could mount an unencrypted AOF volume on this host (ARM 1 ext4) and
makes an ext4 signature a hard refusal, so it strictly narrows the plaintext surface. No `exception` block
is required: no plaintext-exception and no `cert_verification: off` row.

## Observability

```yaml
liveness_signal:
  what: SOLEUR_INNGEST_LUKS_STAGE stage rows (resolve, luks_key_stage, mount_luks, fstab, verify) + inngest-luks-reopen-armed phone-home + hourly SOLEUR_INNGEST_SERVER_PROBE (data_mount_devid)
  cadence: per boot (stage rows), hourly (probe)
  alert_target: Better Stack (logtail_exploration_alert.inngest_luks_wrong_volume pages on a return to a non-LUKS devid; betteruptime_heartbeat.inngest_server_probe is NOT touched by this plan)
  configured_in: apps/web-platform/infra/cloud-init-inngest.yml (emitters), apps/web-platform/infra/betterstack-logs-alerts.tf (alert)
error_reporting:
  destination: journald tag inngest-luks-stage -> Vector Source 4 -> Better Stack; luks_err trap phones home inngest-luks-FAILED via inngest-boot-phone-home.sh
  fail_loud: yes - every refusal exits non-zero after emitting its stage; no stage removed here is the only reporter of a surviving failure
failure_modes:
  - mode: stripped resolver refuses (pointer names a third id, volume absent, signature not crypto_LUKS/blank)
    detection: stage=resolve / pointer_* / blkid_probe row followed by inngest-luks-FAILED
    alert_route: Better Stack query + the host-dark symptoms (no probe row); runbook inngest-luks-cutover-6894.md
  - mode: a regression re-mounts an ext4 volume plaintext
    detection: data_mount_devid != scsi-0HC_Volume_106903269 in the probe row
    alert_route: logtail_exploration_alert.inngest_luks_wrong_volume (paging)
  - mode: reopen unit fails on boot 2
    detection: inngest-luks-reopen-ARM-FAILED phone-home and 'Failed to start inngest-luks*' journal rows (rehearsal capture forbids them)
    alert_route: Better Stack + rehearsal capture script
logs:
  where: Better Stack Logs source for soleur-inngest (journald via Vector)
  retention: per Better Stack source retention (unchanged)
discoverability_test:
  command: bash apps/web-platform/infra/inngest-userdata-budget.sh --json
  expected_output: stored_bytes
```

Affected-surface note (blind surface: first-boot cloud-init on a no-SSH host): the stage rows carry
`mode=`, `blkid_type=`, `expect_luks=` and `detail=` in one event, so the competing hypotheses (pointer vs
unpointed, blank vs LUKS vs foreign) are discriminated by a single row. The `mode` value changes from
`plaintext_canonical` to `unpointed`; no alert or capture script keys on the old value (verified by grep).

## Guard Contract

### Guard 1 - AC5 key-set parity (`inngest-boot-emitter.test.sh`)
**Property.** The test's render map and the `inngest-host.tf` `templatefile` map carry the same key set, and
the extraction can never silently return an empty or over-read list.
**Assembly.** Three sources feed the key set: the `.tf` call site (awk range `templatefile(... {` to
`^  })`), the test's `RENDER_EXPR` map (extracted by a regex anchored on its FIRST key), and the template's
own `${...}` consumers. Chokepoint: the `comm` diff of the first two plus the floor/bound pair. The
second renderer (`rehearsal.tf`) is covered by `inngest-provision-rehearsal.test.sh`, not by this guard.
**Mutation matrix:**

| # | Mutation | Must go RED because |
|---|---|---|
| 1 | Re-add `inngest_volume_id` to the `.tf` map only | `comm` reports it missing from the test map |
| 2 | Re-add it to the test map only | `comm` reports it extra |
| 3 | Leave the extraction anchored on `{ inngest_volume_id=` after the key is removed | MAP_KEYS empty -> parity fails, naming the whole set missing (guard's own dispatch, non-vacuity) |
| 4 | Add a 19th key to both sides | over-read bound `-le 17` reds (second member after a compliant first) |
| 5 | Move the key to a second line of the render map | the single-line regex finds fewer keys; parity reds |
**Harness rows.** (H1) Break the `^  \}\)` range end in a scratch copy of the `.tf`: the over-read bound
must red. (H2, must-PASS non-canonical) a reordered but equal key set passes.
**Anchor.** The stored value is the floor/bound pair (17/17); a `>= N` floor survives substitution, so set
identity (`comm` empty) is the integrity check and the pair is only the anti-vacuity layer.

### Guard 2 - D1 retired-address + no-reintroduction (`inngest-host.test.sh`)
**Property.** Neither retired plaintext address is declared or referenced, and no `*.tf` in the infra root
assigns an `inngest_volume_id` template input (the pin local and the key are gone). The rehearsal root
(`inngest-provision-rehearsal/*.tf`) is a different directory and is guarded by
`inngest-provision-rehearsal.test.sh`, not by this scan.
**Assembly.** All `*.tf` directly under `apps/web-platform/infra` (the function globs `"$dir"/*.tf`, non-recursive),
comment- and `description =`-stripped; scan v1 (resource headers), v2' (zero `inngest_volume_id`
assignments), v4 (live `hcloud_volume.inngest_redis` references).
**Mutation matrix:**

| # | Mutation | Must go RED because |
|---|---|---|
| 1 | Re-declare `resource "hcloud_volume" "inngest_redis"` | v1 |
| 2 | Re-declare the attachment | v1 |
| 3 | Add `inngest_volume_id = "1"` to any `*.tf` (a second file after a compliant first) | v2' |
| 4 | Reference `hcloud_volume.inngest_redis.id` in an output | v4 |
| 5 | Empty root | "no .tf content scanned (fail closed)" |
**Harness rows.** (H1) neuter `d1_violations` to `return 0`: the RED rows must fail the suite. (H2,
must-PASS non-canonical) a fixture whose only mention of the retired address is in a comment and a
`description` passes.
**Anchor.** Merge-base diff (CI) is the independent anchor: a PR that re-adds the key must also edit this
suite's expectations in the same diff, which review reads.

### Guard 3 - Template structure after the strip (`inngest-redis-luks.test.sh`)
**Property.** The delivered template contains no code path that can mount, open, format or probe any device
other than `LUKS_ID`'s, and no ext4 mount.
**Assembly.** The two device readers (boot-reopen script, first-boot stage heredoc) and the one
`/etc/default/inngest-luks-volumes` writer; chokepoint: the comment-stripped view of the template.
**Mutation matrix:**

| # | Mutation | Must go RED because |
|---|---|---|
| 1 | Re-add `PLAIN_ID=` in either reader | absence assertion (per reader, not whole-file) |
| 2 | Re-add an ext4 arm that mounts `"$DEV"` | G-ext4 absence + loopback UNP3 |
| 3 | Re-add the staging block in the stage only (reopen still clean) | per-reader absence |
| 4 | Point `DEV=` back at a non-`LUKS_ID` expression | `DEV` derivation assertion |
| 5 | Reorder: move `luksFormat` before the privilege assertion | existing G1.d |
| 6 | Pointer allowlist re-gains `"$PLAIN_ID"|` | G4.e needle |
| 7 | Delete the D6 guard line from ARM 3 (the unpointed arm formats on a `prd` render) | UNP5 + the D6 line-presence assertion; this row satisfies the arm's precondition (raw volume, no pointer) and still must fail the property |
| 8 | Reintroduce a SECOND unguarded `luksFormat` on the canonical device elsewhere in the stage | the "every luksFormat is preceded by the prd guard in the same arm" per-site assertion (second member after a compliant first) |
**Harness rows.** (H1) Delete the new absence assertions' regex (empty needle): the anti-vacuity floor must
red. (H2, must-PASS non-canonical) a template whose comments still mention PLAIN_ID passes (comment-stripped
view).
**Anchor.** Exact assertion floor (recomputed, no slack) plus the CI merge-base diff.

## Domain Review

**Domains relevant:** Engineering (CTO/infra)

### Engineering
**Status:** reviewed (self-assessed in plan; CTO/terraform-architect to be spawned by plan-review/deepen)
**Assessment:** infra-only, no user-facing surface, no copy, no pricing, no legal text. The data-bearing
store is already declared in the encryption-posture ledger; this change narrows it. CLO/GDPR: the
`hr-gdpr-gate-on-regulated-data-surfaces` regex (schemas, migrations, auth, API routes, `.sql`) is not
matched; none of triggers (a)-(d) fires (no new processing activity, no new distribution surface); the
single-user-incident threshold is carried by the loss-of-AOF/dark-scheduler failure mode, not by a
data-protection change. Product/UX gate: NONE (no `components/**`, `app/**` files).

## Acceptance Criteria

### Pre-merge (PR / parked draft)

- AC1 `grep -c 'PLAIN_ID\|inngest_volume_id\|INNGEST_LUKS_PLAIN_VOLUME_ID\|STAGING_DEV\|STAGING_MAPPER\|reopen_skip_plaintext\|mount_ext4' apps/web-platform/infra/cloud-init-inngest.yml` comment-stripped = 0 (`grep -vE '^[[:space:]]*#'` view).
- AC2 The `templatefile` map in `inngest-host.tf` and in `rehearsal.tf` contains no `inngest_volume_id`; `inngest-host.tf` has 17 keys; `local.inngest_retired_plaintext_volume_id` is gone.
- AC3 `bash apps/web-platform/infra/inngest-boot-emitter.test.sh` green with floor 17 / bound 17 and the new anchor.
- AC4 `bash apps/web-platform/infra/inngest-redis-luks.test.sh` and `inngest-host.test.sh` green; floors updated to exact counts; the three guards' mutation rows demonstrably RED when applied to a scratch copy (record counts in the PR).
- AC5 `inngest-redis-luks-loopback.test.sh` re-keyed ARM0/2/3/4, UNP3-UNP5 and the kept PTR arms green in CI (locally only if the harness reports available); ARM1/ST*/REG removed, not skipped.
- AC6 `bash apps/web-platform/infra/inngest-userdata-budget.sh` exit 0 and stored bytes <= baseline 19,680 B (strictly smaller).
- AC7 The pointer arm hunk (`if [ "$MODE" = pointer ]; then ... STAGE=mount_luks ... luks_emit mount_luks 0 crypto_LUKS "mode=pointer"`) is byte-identical to `origin/main`'s (diff of that range empty).
- AC8 `git diff origin/main -- apps/web-platform/infra/cloud-init-inngest.yml` hunks all fall inside the two regions named in Phase 2 (no hunk between the boot-reopen script's end and the `LUKSEOF` start, and none after the `inngest-luks-reopen-armed` item). **Amended in the review fix round:** whole-line `# ` comments (stripped from the rendered `user_data` by `inngest_rationale_strip`) are exempt, so the stale lead-in comment above the `LUKSEOF` item and the comments at the `mkdir -p /mnt/data` item and the RESOLVE header are corrected there. No NON-comment hunk lies outside the two regions: the D6 guard and its `STAGE=` line sit inside Region B.
- AC9 `.claude/hooks/grep-q-pipe-guard.test.sh` still reads `cloud-init-inngest.yml | = | 4`; `templatefile-bare-dollar-guard.test.sh`, `cloud-init-inngest-bootstrap.test.sh`, `cloud-init-inngest-provision-unit.test.sh`, `inngest-provision-rehearsal.test.sh`, `journald-config.test.sh`, `cloud-init-user-data-size.test.ts`, `lint-encryption-posture` suite/lint, `c4-count-parity.test.sh` green.
- AC10 ADR-142 addendum amended (status "adopting"); `grep -rn "ADR-142" ` unchanged ordinal (no new ADR).
- AC11 No file outside the Files-to-Edit list changed (`git diff --name-only origin/main`); in particular none of `inngest-redis-luks.tf`, `inngest-luks-cutover.sh`, `inngest-redis-bootstrap.sh`, `apply-web-platform-infra.yml`, `betterstack-logs-alerts.tf`; `variables.tf` diff is one description line. **Amended in the review fix rounds:** comment-only, prose, ledger-text and documentation edits are exempt from the Files-to-Edit list, so these additional files carry them: `inngest-redis-luks.tf` and `betterstack-logs-alerts.tf` (comment wording), `betterstack-log-query.md`, `inngest-server.md` and `inngest-luks-cutover-6894.md` (runbook rows), ADR-142 and ADR-199 addenda, `.claude/hooks/grep-q-pipe-guard.test.sh` (line-number citations replaced by content anchors), `scripts/followthroughs/inngest-provision-rehearsal-capture.sh` and its test (a forbidden-row check for `stage=unpointed_raw_refused`), and `variables.tf` / `rehearsal.tf` comment blocks. The Non-Goals N4 files (`prevent_destroy`, `delete_protection`, `betteruptime_heartbeat.inngest_server_probe`) remain untouched.
- AC12 PR #10081: `isDraft == true`, `autoMergeRequest == null`, `parked` label, title begins `PARKED`, body has "DO NOT MERGE" block + base SHA/date + staleness rule, `Ref #9786` present, no closing keyword (`grep -iE '(close[sd]?|fix(e[sd])?|resolve[sd]?) #9786'` empty), last line is the Claude Code attribution line; commit trailers present.
- AC-P1 (park justification, one sentence plus anchors in the PR body): merging replaces nothing (`hcloud_server.inngest` in `OPERATOR_APPLIED_EXCLUSIONS`, no `hcloud_server.*` in the per-merge `-target` list, `ignore_changes = [ssh_keys]` only) but plants a latent replace that reds drift, aborts `inngest-host` at `server_touched`, and rides the next dispatch un-exercised; the new boot behaviour (D2/D6) has not run on a real boot. Note the automated bootstrap-pin-bump PRs already edit this file, so the first two consequences are partly pre-existing; the dominant park reason is the unexercised boot path.
- AC13 One combined tracker exists (N2 rollback arm + image release + pin bump; the rehearsal root's unused plain volume, which the operator excluded from this arc; DR bring-up for a blank `prd` volume; the duplicated reopen arms) with re-evaluation criterion "when #10081 lands". **Amended in review fix round 3:** `inngest_expect_luks` is NOT in the tracker any more; it was retired in this PR.
- AC14 UNP5 (no pointer + raw + rendered `prd` config) REFUSES and formats nothing; deleting the D6 guard line reds it (Guard 3 row 7).
- AC15 `scripts/lint-encryption-posture.py` + its test green, ledger rehearsal rows consistent with the new device roles.

### Post-merge (operator-run, NOT part of this run; documented in the PR for the unpark)

- Phase 7 checklist items 1-6. Nothing here is automated by this plan; the replace itself is the
  existing reviewer-gated dispatch.

## Test Scenarios

1. Render the template through `terraform console` with the 17-key map: output parses as YAML after the
   column-0 directive strip; every `write_files` shell script passes `bash -n` after templatefile unescape
   (T1.13) and no `$$` precedes an identifier (T1.14).
2. Loopback, pointer set to `LUKS_ID`, volume LUKS+ext4: mounts, `stage=verify mode=pointer` (unchanged).
3. Loopback, no pointer, raw volume, non-`prd` rendered config: luksFormat, open, mkfs, mount at `/mnt/data`, `stage=verify mode=unpointed` (re-keyed ARM3).
4. Loopback, no pointer, volume already LUKS with data: opens, never formats, data canary intact (re-keyed ARM2) - including with a `prd` rendered config.
5. Loopback, no pointer, ext4 volume: REFUSES via the unhandled-signature arm, nothing mounted (UNP3, one `expect_luks` value; the input gates nothing now).
5b. Loopback, no pointer, RAW volume, `prd` rendered config: REFUSES `unpointed_raw_refused`, nothing formatted (UNP5).
6. Loopback, pointer names a third id (including the retired plaintext id): REFUSES before any device derivation (PTR3').
7. Boot-reopen unit, pointer set: opens exactly the pointed volume; no pointer + LUKS: opens; no pointer + ext4: `reopen_not_luks` (UNP4).
8. Mutation battery per Guard Contract rows applied to scratch copies (never to the working tree) and restored; read each edited file back after any probing loop.

## Risks

- **R1 Dark scheduler on the replace** (single-user incident). Mitigation: pointer arm byte-identical (AC7);
  Phase 0.1 proves production resolves via pointer; rehearsal gate exercises the unpointed arm; replace
  stays behind its reviewer gate and maintenance window; park until then.
- **R2 The unpointed arm is the only path that can `luksFormat`, and after the strip it targets the sole
  copy.** The first draft called this "not new exposure"; plan review (4 seats) showed that wrong: today a
  prod boot with a lost pointer dies at ARM 0 because the retired device is gone, so formatting the sole copy
  is newly reachable after the re-point (a damaged header reads blank). Mitigated by D6 (ARM 3 refuses when
  the rendered config is `prd`; probe is `blkid -p`), UNP5 and Guard 3 rows 7-8. Residual: no automated
  bring-up for a blank prd volume (DR procedure written when needed); a half-provisioned volume
  (aborted between `luksFormat` and `mkfs`) is not recoverable by ARM 2 because the staging block's
  empty-mapper `mkfs` recovery is deleted - acceptable (only reachable on non-prd, where the volume is
  scratch and destroyed).
- **R3 Cutover units after the strip.** `INNGEST_LUKS_PLAIN_VOLUME_ID` is gone from the env file; any flagged
  run of the (image-baked) cutover script refuses `volume-ids-unreadable`. Acceptable: dispatch deleted,
  cutover complete; removal of the script arm is N2.
- **R4 Rehearsal root keeps an unused raw plain volume attached** after its map line is dropped. Harmless to
  the boot (unprobed); cleanup belongs to the rehearsal root (out of scope, noted in the PR).
- **R5 Merge-hold erosion.** A draft can be marked ready by habit. Mitigation: `PARKED` title, DO-NOT-MERGE
  body block, no auto-merge, and the Reconciliation-row-1 consequences written where a reviewer will read
  them.
- **R6 Two-sibling overlap.** #10073 also edits `user_data`; if it merges first the drift/`server_touched`
  consequences already exist and this change adds nothing new to them, but the replace window then carries
  two edits; reviewed per Phase 7 step 5.

## Non-Goals

- N1 Replacing the host, any `terraform apply`, reboot, dispatch, rehearsal dispatch or other production write in this run.
- N2 The `rollback)` arm and FSM text in `inngest-luks-cutover.sh` / its fixtures (image-baked; needs image release + pin bump + replace; tracked on #9786's comment).
- N3 Web-2 workspaces volume, git_data volume, rehearsal volumes, ADR-198 baked credentials.
- N4 Pinning the inngest volume attachment, changing `prevent_destroy`/`delete_protection`, touching `betteruptime_heartbeat.inngest_server_probe`, or web-1 LUKS volume 106443278.
- N5 (amended) Retiring the rehearsal root's unused plain volume (R4). `inngest_expect_luks` (D4) was originally listed here and was pulled INTO scope in review fix round 3.

## Sharp Edges

- A `## User-Brand Impact` section that is empty or carries placeholder text fails `deepen-plan` Phase 4.6; this plan fills all three lines.
- The boot-emitter AC5 anchor `{ inngest_volume_id=` is the FIRST key of the test map; removing the key without moving the anchor returns an empty list (the floor then catches it, but as "keys not extracted", not as "anchor stale").
- `templatefile` treats `$$` as a PID in bash: any line moved/kept must use bare `$VAR` and `$${...}` only before a brace. Re-run T1.13/T1.14 and `templatefile-bare-dollar-guard.test.sh` after every edit of the heredoc.
- Comment-only lines are stripped from `user_data` (`inngest_rationale_strip`): editing comments in the template is free in bytes but still part of the diff; keep stale comments (e.g. "THE TWO VOLUMES") honest anyway because the suites grep them.
- Do not run the mutation battery against the working tree; use scratch copies and read back any file a probing loop touched.
- Never use `git stash`; checkpoint with a WIP commit if work must be set aside.
- Prose in this repo's plan/PR text must not name a human actor performing an infrastructure imperative; the unpark checklist is phrased as dispatches/gates, not operator hands-on steps.
