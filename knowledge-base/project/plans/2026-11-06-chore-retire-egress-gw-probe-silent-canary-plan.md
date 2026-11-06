---
title: "chore(infra): retire the egress-gw probe-silence canary alert pair (Ref #12189)"
date: 2026-11-06
slug: retire-egress-gw-probe-silent-canary
branch: feat-one-shot-12189-retire-egress-gw-canary
issue: 12189
type: chore
priority: p2
domain: engineering
lane: cross-domain
brand_survival_threshold: none
---

## Enhancement Summary

**Deepened on:** 2026-11-06. **Method:** the plan was already CTO-ruled and panel-reviewed (DHH, Kieran, code-simplicity) before this pass; deepen-plan ran the halt gates and a verification sweep instead of a broad agent fan-out, because the change is delete-only and every claim is checkable against the repo.

**Key improvements carried in:** (1) the probe test's derived-referrer row and exact `MIN_ASSERTIONS` pin were found to move with the retirement and are now in Files to Edit under a follow-up CTO ruling; (2) the census insertion point is pinned after the existing ghcr entries (a mutation anchor in the ceiling suite depends on it); (3) managed versus live alert counts are stated separately; (4) the Observability block carries a credential-free discoverability command.

**Gate dispositions.** 4.4 precedent: #11653 then #11785 are the sibling sequence (cited). 4.5 network: not triggered (the only keyword hit was a prose label, removed). 4.55 downtime: not triggered (Better Stack Logs only, no host). 4.6 user-brand: present, `none` with a scope-out line for the infra path. 4.7 observability: present with the 5-field block. 4.8 PAT: no match. 4.9 UI: no UI file. 4.10 encryption posture: not triggered (no store or connection is introduced; the `.tf` edit is a deletion). 4.11 guard contract: lint green, assemblies name the readers and the dict they share, matrices derived from the design. 4.12 scope check: one unfenced section, all rows mapped. 4.13 task design: no new autonomous task.

**Verified live in this pass:** #12270, #12271, #12242, #12190 and #12268 are OPEN; #12180 is CLOSED; #12244 is MERGED; the only AGENTS rule id cited (`wg-when-deferring-a-capability-create-a`) exists; `apply-deploy-pipeline-fix.yml` mentions no `logtail` resource (zero hits) and `scheduled-terraform-drift.yml` applies nothing of this root; the latest main apply read "0 added, 0 changed, 0 destroyed".

## Overview

The throwaway canary alert pair added by the #12180 inversion has done its job: the follow-through probe for tracker #12189 reads the canary as fired and every other check as held, and its only remaining ask is the pair's removal. This change removes the pair from the Better Stack logs-alerts Terraform, keeps the two bare apply targets for exactly one apply so the destroy is planned, and moves every count guard and document that describes the pair to the post-removal state.

## Research Insights

**Premise Validation (Phase 0.6).** Checked and held: tracker #12189 is OPEN (label `follow-through`, milestone Post-MVP / Later) and its parent #12180 is CLOSED; the canary's mirror issue #12242 is OPEN (`[ci/betterstack-incident] soleur-egress-gw-probe-silent-canary-prd`); every file the brief names exists on `origin/main` (the canary pair, both `-target` lines, the probe and its RETIREMENT header, the five guard suites, the runbook, ADR-218). The collision pre-check exited 10 on two hits, both benign: PR #12268 is this branch's own WIP PR, and a `test-all.sh` process belongs to the unrelated worktree `feat-one-shot-12231-star-suites-last`. Three other open PRs touch `apply-web-platform-infra.yml` (#10928, #10678, #7390); this plan does not edit that file (the two targets stay as they are), so no conflict arises. The most recent push-apply on main (run 42270411966, 2026-11-06T18:24Z) ended "0 added, 0 changed, 0 destroyed", so the next apply's only destroys are the intended pair. Not independently re-read: the brief's probe reading (`quiet_age_s` about 29500, rows on both hosts) needs read-only credentials; the work phase re-runs it once before asking for the merge go-ahead (Phase 4). ADR check: the 2026-11-05 and 2026-11-06 amendments of ADR-218 prescribe exactly this deletion once the canary has fired and the soak held; the rejected alternatives there are the poller as a first move and dropping `treat_as_zero`, neither touched here.

**Property List (Phase 0.6b).**

1. The Terraform no longer declares the canary pair, and the next apply destroys exactly those two live resources and nothing else.
2. Every pinned count that describes the logs-alert resource set reads the post-removal number, and still goes red when a block is added or removed.
3. The destroy is authorized once and narrowly: a standalone `[ack-destroy]` line in the merge commit, with the two bare `-target` lines honoured for this apply only.
4. The soak probe can still end in exit 0 (vendor keeps the canary incident after its alert is deleted) or in the distinct "retired, incident unreadable" exit 5 (vendor drops it); both paths and the unverified residual are written down.
5. No document describes the canary as live or pending without a pointer to the end state.
6. Nothing in this session writes to Better Stack, and tracker #12189 and mirror issue #12242 close through their own mechanisms (the sweeper, the mirror), never by hand and never through a closing keyword.

**Cut List (Phase 0.6b).**

| Mechanism | Property it would buy | Disposition |
|---|---|---|
| A retirement-window pin in `egress-gw-alert.test.sh` (kept targets present, probe canary literals unchanged) | 3 | CUT (CTO ruling): the census G4c and the structure suite's apply-parity stray check already hold the window; the pin would need deleting again in the follow-up PR |
| Probe transport extraction onto `scripts/lib/bearer-curl.sh` (RETIREMENT item 8) | none of the six | DEFERRED to #12271 (CTO ruling): a refactor of the live verdict path does not belong in the same change as an irreversible destroy |
| Removing the two `-target` lines in this PR | 1 | CUT: a bare target on an address with no configuration is what plans the delete; removal is #12270 after the apply |
| Re-pinning `APPLY_FLOOR_EPOCH` | none | CUT (the brief and RETIREMENT item 9): the floor stays the recurrence floor for the tracker's lifetime |
| New committed census mutation rows for the real-tree "target dropped, entry kept" case | 3 | CUT: row M-g4-7 already covers that shape on a synthetic tree; the real-tree case is run once against a scratch copy and recorded in the PR body |
| Heartbeat poller (#12190) | none | NOT TRIGGERED: the canary fired |
| Community-registry functional-overlap search | none | SKIPPED: a delete-only retirement adds no capability to overlap |

**Applicable institutional learnings** (all under `knowledge-base/project/learnings/`).

- `2026-07-17-target-scoped-terraform-apply-makes-resource-deletion-a-silent-noop.md`: in a `-target`-scoped apply a deletion only happens if the address is still targeted; that is why the two lines stay for one apply.
- `2026-09-27-an-import-block-breaks-terraform-test-and-a-count-ack-reaches-every-destroy.md`: `[ack-destroy]` acks every destroy in the plan, not just the intended ones; the prior apply's "0 destroyed" (above) is what bounds it here.
- `2026-09-27-a-retirement-census-by-name-missed-the-consumer-that-pinned-the-id.md`: search the retirement census by identifiers as well as names (`silent_canary`, `probe-silent-canary`, the incident name `soleur-egress-gw-probe-silent-canary-prd`, the probe literals `CANARY_NAME` / `CANARY_RESOURCE`), then run the guards against the planned deletion.
- `2026-07-24-count-vs-floor-guard-single-value-fixtures-cannot-discriminate-operator.md` and `2026-08-04-a-count-framed-ratchet-cannot-see-a-rename.md`: a `>=` floor tolerates growth and a count cannot see a swap; the exact `==` pins and the base-relative G4c carry those two directions (Guard 1).
- `2026-06-05-followthrough-pr-body-prose-closes-keyword-autocloses-tracker.md`: no closing keyword next to #12189 or #12242 in the title, body or any commit message; the ship step asserts `closingIssuesReferences` is empty.
- `2026-09-14-i-tested-both-endpoints-and-left-the-wire-between-them-unpinned.md`: the remedy for a ratchet failure is the code, never the baseline; no positional-rooted `mv` is added to any test helper, and the edits to `egress-gw-alert.test.sh` are deletions plus count flips.
- `2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md`: the Guard Contract below is written before the edits.

**Merge-message mechanism (verified).** The repo squash-merges with `COMMIT_MESSAGES` as the body (`gh api repos/jikig-ai/soleur` returned `squash_merge_commit_message: COMMIT_MESSAGES`), so a branch commit whose message carries `[ack-destroy]` on its own line lands that line in the merge commit body. The precedent is #11653 (commit `d83641f64d`, whose squash body carries `[ack-destroy]` on its own line), and the apply's gate matches `(^|\n)\[ack-destroy\]($|\n)` against the head commit message.

**Mirror mechanism (verified).** `scripts/betterstack-incident-mirror.sh` closes a mirror issue only when its incident id is no longer in the vendor's open list (`GET /api/v2/incidents?resolved=false`); it posts "Still open" every 15 minutes while the incident stays open, and files a fresh issue at the next run if a human closes it.

**CTO rulings** are recorded as rows in `knowledge-base/project/specs/feat-one-shot-12189-retire-egress-gw-canary/decision-challenges.md`.

## Research Reconciliation — Spec vs. Codebase

| Claim (brief or RETIREMENT header) | Reality on `origin/main` | Plan response |
|---|---|---|
| "adjust ... `count == 19` -> 18 in the egress-gw alert test" | `count == 19` is `assert s.count(old) == 19` in `betterstack-send-failed-alert-mutation.test.sh` (the exploration `values = [local.vector_prd_source_id]` line). `egress-gw-alert.test.sh` carries different counts: 4 resources and 4 names to 2 and 2, 2 consumers of the production SQL local to 1, and an eight-block mute-knob row to six | Each site is named in Files to Edit with its own number; none is edited to fit, each is re-derived from a run |
| RETIREMENT (6): "re-derive PRESENCE_ROWS and MUT_ROWS at BOTH write sites each" | Each constant has one literal (`PRESENCE_ROWS=85`, `MUT_ROWS=78`); the floor mutation row derives its sed anchor from the declaration at run time | One literal each; the values come from a `MUT_SKIP=1` run (presence) and a full run minus presence (mutation rows) |
| RETIREMENT (4): "EXPECT_BLOCKS 19 -> 18 and re-derive MIN_PASSES" | The ceiling suite has no canary-specific case (no `silent_canary` text in it); `MIN_PASSES=116` is the measured pass count | EXPECT_BLOCKS flips; MIN_PASSES changes only if the full run prints a different count whose delta is explained |
| RETIREMENT (2): keep BOTH `-target` lines for one apply | `apply-web-platform-infra.yml` needs no edit for that; the two lines are already there | The workflow is not edited; the census INTENDED_DESTROYS entries are what make the structure suite accept the bare targets |
| RETIREMENT (7) lists `infra-validation.yml` | The only canary text there is a comment above the egress guard step ("its throwaway canary pair") | Comment-only edit |
| RETIREMENT (8): extract the probe's transport copies "in this change" | Not in the operator's scope list; the probe is the live verdict path | Deferred to #12271 (CTO) |
| Brief: mirror issue "must self-close" | It closes only when the incident leaves the vendor's open list, and whether the vendor resolves or drops the incident with its alert is unverified | Documented as the second unverified residual; post-merge read-only check; no hand close |
| RETIREMENT header (the sections it points at): "ADR-218's canary note and its 2026-11-06 amendment (the amendment records the end state)" | The ADR is "appended, not edited" by its own convention | New dated amendment plus inline superseded pointers (CTO) |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "delete the canary alert resource and its paired resource from the Better Stack logs-alerts Terraform (betterstack-logs-alerts.tf)" [brief] | Phase 1 task 1.1; Files to Edit entry 1 | mapped |
| 2 | "keep the two -target lines for one apply" [brief] | No edit to `apply-web-platform-infra.yml`; Phase 1 task 1.2 (INTENDED_DESTROYS); Guard 2 | mapped |
| 3 | "adjust INTENDED_DESTROYS, the floors 19->18, EXPECT_BLOCKS 19->18 and `count == 19` -> 18 in the egress-gw alert test and related guards" [brief] | Phase 1 tasks 1.2 to 1.6; Guard 1 | mapped |
| 4 | "update the runbook cron-egress-blocked.md and the ADR-218 amendment as the RETIREMENT header requires" [brief] | Phase 2 tasks 2.1, 2.3, 2.4 | mapped |
| 5 | "record in the runbook the unverified residual that exit 0 depends on the vendor keeping the canary incident after the canary alert is deleted (if not, the probe returns the distinct 'canary retired, incident unreadable' exit 5 and the tracker is closed by hand citing the last sweep comment that read canary=fired)" [brief] | Phase 2 task 2.1 (residual A) | mapped |
| 6 | "The merge commit needs a standalone [ack-destroy] line" [brief] | Phase 4 task 4.3 | mapped |
| 7 | "Do not touch APPLY_FLOOR_EPOCH" [brief] | Non-goal; AC 3 asserts the line is byte-identical | mapped |
| 8 | "Fix code, never ratchet baselines (the repo-wide fixture-relative ratchet counts positional-rooted mv in test helpers)" [brief] | Phase 1 task 1.6 constraint; AC 9 | mapped |
| 9 | "Mirror issue for the canary incident must self-close; do not close it by hand" [brief] | Phase 2 task 2.1 (residual B); Phase 5 verification; AC 12 | mapped |
| 10 | "use \"Ref #12189\" in the PR body, never Closes" [brief] | Phase 4 task 4.4; AC 13 | mapped |
| 11 | "no Better Stack writes of any kind from this session (no manual resolve, pause or delete); the destroy happens only through the merged PR's apply" [brief] | Non-goal; Phase 4 stop line | mapped |
| 12 | "Prepare the PR through review and CI, then STOP before merge/auto-merge and before any apply or workflow dispatch, and ask the operator for an explicit per-command go-ahead naming the merge" [brief] | Phase 4 task 4.6 | mapped |
| 13 | "Do not push during the merge-queue wait" [brief] | Phase 4 task 4.6 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Files to Edit 1 (`betterstack-logs-alerts.tf`) | "delete the canary alert resource and its paired resource" | asked |
| Files to Edit 2 (census INTENDED_DESTROYS) | "adjust INTENDED_DESTROYS" | asked |
| Files to Edit 3 to 5 (structure floors, EXPECT_BLOCKS, `== 19` anchor) | "the floors 19->18, EXPECT_BLOCKS 19->18 and `count == 19` -> 18" | asked |
| Files to Edit 6 (`egress-gw-alert.test.sh`) | "in the egress-gw alert test and related guards" | asked |
| Files to Edit 7 (`infra-validation.yml` comment) | "as the RETIREMENT header requires" (header site 7 names it) | asked |
| Files to Edit 8 and 9 (runbooks) | "update the runbook cron-egress-blocked.md" (and the header's site 7 for `betterstack-log-query.md`) | asked |
| Files to Edit 10 (ADR-218 amendment) | "the ADR-218 amendment" | asked |
| Files to Edit 11 (probe STATUS comment line) | — | inferred — justification: the probe's own test pins the RETIREMENT header and a reader of the header would otherwise read the finished sites as pending; one comment-only line, no token removed (CTO ruling) |
| Phase 4 task 4.1 (pre-merge probe re-read and tracker comment) | "the last sweep comment that read canary=fired" | inferred — justification: no sweeper comment exists yet (first scheduled read is after 2026-11-07T00:00Z) and the only `canary=fired` comment predates the soak, so the by-hand fallback needs a current citation (CTO ruling) |
| Phase 5 (post-merge read-only verification) | "Mirror issue for the canary incident must self-close" | asked |
| Guard Contract (two guards) | "adjust ... related guards" | asked |
| Deferral issues #12270, #12271 | — | inferred — justification: `wg-when-deferring-a-capability-create-a` requires a tracking issue for each deferral (the later target removal; the CTO-deferred transport extraction) |

### Split Assessment

- Subsystems touched: 5 - apps/web-platform, .github, tests, scripts, knowledge-base
- Planned files: 12 edited (plus 3 planning artifacts) | Estimated changed lines: about 450
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR - the root count trips the threshold but the roots are not independent seams: the count suites flip together (the structure suite reads the census file's INTENDED_DESTROYS as its single source, the probe test derives its referrer set across roots, and the destroy and its guards must land in one commit or main goes red); the documents describe the same state. The only separable piece, the probe transport extraction, is already split off as #12271.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing directly; the failure is an internal detection gap. If the apply destroyed the production `soleur-egress-gw-probe-silent-prd` pair instead of the canary pair, a silent egress-gateway host would no longer page, so an agent-sandbox network fault could persist unnoticed (the probe's `prod_alert=absent` finding and the structure suite's name pins guard that).
- **If this leaks, the user's data / workflow / money is exposed via:** no vector; the change reads and writes no user data, adds no credential and exposes no secret (the probe prints counts and fixed tokens only, and its read-only token stays in Doppler).
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** none, because the deleted resources are a throwaway positive control with no user data, the production alert and the probe both stay armed, and the destroy is bounded by a prior clean apply and the `[ack-destroy]` count gate.

threshold: none, reason: the diff touches infra and workflow-adjacent paths but only deletes a throwaway internal canary alert pair; no user data, credential or user-facing surface is involved and the production alert is untouched.

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** The CTO ruled on the five technical forks (probe transport extraction deferred, G2b deleted wholesale without a window pin, ADR amendment appended, probe STATUS line, pre-merge evidence refresh); rulings are persisted in `decision-challenges.md`. No product, marketing, legal, finance, sales or support surface is touched: infrastructure and tooling change only, so the Product/UX gate does not fire (no UI file in Files to Edit).

## Architecture Decision (ADR/C4)

No new architectural decision: this retires a throwaway control that ADR-218's 2026-11-05 and 2026-11-06 amendments already scheduled for deletion. The ADR deliverable is an end-state amendment (Phase 2 task 2.4), written in this plan, not deferred. C4: the Better Stack container description in `knowledge-base/engineering/architecture/diagrams/model.c4` names no canary, no alert count and no `egress_gw_probe_silent*` resource (checked by reading the container description and running `plugins/soleur/test/c4-count-parity.test.sh` in Phase 3); no actor, external system or access relationship changes, so no `.c4` edit.

## Observability

Delete-only change: no new code or infra surface. Phase 2.9 permits skipping the schema for a delete-only plan; the schema is nevertheless filled in below so the deepen-plan gate reads a complete block, and it describes what the retirement leaves behind.

```yaml
liveness_signal:
  what: the production alert soleur-egress-gw-probe-silent-prd (missing roster hosts, higher_than 0) plus the follow-through probe verdict line
  cadence: alert evaluated every 300 s over a 900 s window; probe read by the daily follow-through sweeper
  alert_target: email via the Better Stack Logs alert; ACTION REQUIRED comment on tracker #12189 from the sweeper
  configured_in: apps/web-platform/infra/betterstack-logs-alerts.tf (egress_gw_probe_silent) and scripts/followthroughs/egress-gw-probe-silent-12180.sh
error_reporting:
  destination: the apply job log and its notify-apply-failure job (Better Stack and GitHub), the sweeper comment on #12189
  fail_loud: a refused alert delete fails the apply step closed with state unchanged; a probe read failure is exit 3 (cannot establish), never a pass
failure_modes:
  - mode: the apply destroys something other than the canary pair
    detection: destroy gate demands [ack-destroy]; the run log must read 2 destroyed; the probe prints prod_alert=absent if the production alert is lost
    alert_route: apply failure notification plus ACTION REQUIRED on #12189
  - mode: the vendor keeps the canary incident open after its alert is deleted
    detection: read-only incident API (the probe's canary field) and the mirror issue #12242 staying open
    alert_route: comment on #12189 (RETIREMENT item 10); resolve is an owner-gated Better Stack write
  - mode: the vendor drops the canary incident with its alert
    detection: probe exits 5 with the retired message
    alert_route: sweeper ACTION REQUIRED comment on #12189; close by hand citing the last canary=fired comment
logs:
  where: GitHub Actions run logs for apply-web-platform-infra.yml and the sweeper; Better Stack Logs for the egress-gw-probe rows
  retention: GitHub Actions default retention; Better Stack plan retention
discoverability_test:
  command: grep -cE '^resource "logtail_exploration_alert" "egress_gw_probe_silent(_canary)?" \{' apps/web-platform/infra/betterstack-logs-alerts.tf
  expected_output: "1"
```

The command is credential-free and proves the declared end state (only the production alert header remains; it prints 2 before the retirement). The live end state is verified by the read-only checks in Phase 5.

## Infrastructure (IaC)

### Terraform changes

`apps/web-platform/infra/betterstack-logs-alerts.tf` only: delete `logtail_exploration_alert.egress_gw_probe_silent_canary`, `logtail_exploration.egress_gw_probe_silent_canary` and `local.egress_gw_probe_silent_canary_sql`. No provider, version or variable change; no new secret.

### Apply path

Existing per-merge push-triggered apply (`apply-web-platform-infra.yml`, `-target` scoped). The two canary `-target` lines stay for exactly this apply; the plan shows 2 destroyed (alert first, then its exploration) and the standalone `[ack-destroy]` line in the merge commit authorizes it. Blast radius: Better Stack Logs only; no host, no downtime. The destroy happens only through the merged PR's apply, never from this session. If the vendor refuses the alert delete (for example because an incident is open) the apply step fails closed and state is unchanged; recovery is a reviewed follow-up, not a Better Stack write from a session.

### Host fan-out

Not applicable: no `terraform_data` provisioner is touched.

### Distinctness / drift safeguards

No `dev != prd` surface. The structure suite's apply-parity stray check reads INTENDED_DESTROYS, so a leftover bare logtail target after the later cleanup (#12270) goes red.

### Vendor-tier reality check

Deleting two resources only lowers the live Logs-alert count (20 once the canary was applied, 19 after, per ADR-218); no tier gate is involved.

## Implementation Phases

### Phase 0 - Baseline (read-only)

- 0.1 In the worktree, record the pre-change pass counts so every floor is re-derived from a run: `bash apps/web-platform/test/infra/logs-alert-query-period-ceiling.test.sh` (116 of 116), `MUT_SKIP=1 bash apps/web-platform/test/infra/egress-gw-alert.test.sh` (85 passed, floor 85), and the full run of the same suite (floor 85 + 78).
- 0.2 `git grep -nE 'silent_canary|probe-silent-canary|egress-gw-probe-canary-absent' -- ':(top)'` to freeze the retirement census by name AND by identifier (`soleur-egress-gw-probe-silent-canary-prd`, `CANARY_NAME`, `CANARY_RESOURCE`, `canary_declared`); every hit outside `knowledge-base/project/` and the probe is either edited in Phase 1/2 or is an expected survivor listed in AC 4.

### Phase 1 - Terraform and guards (one atomic commit; the suites cannot be split green)

Commit message: `chore(infra): retire the egress-gw probe-silence canary alert pair (Ref #12189)`.

- 1.1 `apps/web-platform/infra/betterstack-logs-alerts.tf`: delete the `egress_gw_probe_silent_canary_sql` local with its three-line THROWAWAY comment, the "THROWAWAY CANARY (#12180)" comment block, and both canary resources (alert and exploration). Reword, in the past tense, the two comment spots that describe the canary as live: the egress block header ("a throwaway canary alert runs the same query against an identifier no host emits and must fire") and the silent-alert block ("which is what the canary below is for ... until the canary has fired"). New text: the canary (#12180) fired and was retired by #12189; the evaluator delivers a non-zero value for this shape on an empty count; the INFERRED zero-fill label and the sentence the guard pins (`The INFERRED mechanism is that`) stay untouched.
- 1.2 `tests/scripts/test-infra-privileged-tier-census.sh`: append to `INTENDED_DESTROYS["apps/web-platform/infra"]`, AFTER the four existing ghcr entries (the ceiling suite's M29 mutation anchors on the text `"apps/web-platform/infra": {` followed by the first ghcr entry, so nothing may be inserted before it), the two entries `logtail_exploration_alert.egress_gw_probe_silent_canary` and `logtail_exploration.egress_gw_probe_silent_canary`, each valued `"#12189 retire the #12180 canary pair"`. Do not touch the existing ghcr entries or any census floor.
- 1.3 `apps/web-platform/infra/betterstack-alert-structure.test.sh`: `CENSUS_FLOOR_ALERTS` and `CENSUS_FLOOR_EXPLORATIONS` 19 to 18; rewrite the header line (rows 1-4, "at least 19 ... 18 once the canary pair is deleted"), the two-line comment above the floors, and the apply-parity comment block (it says INTENDED_DESTROYS "is now empty of logtail_* addresses", false once the two entries land) to the end state. `GUARD_CENSUS_FLOOR`, `PRESENCE_ROWS`, `MUT_ROWS` stay.
- 1.4 `apps/web-platform/test/infra/logs-alert-query-period-ceiling.test.sh`: `EXPECT_BLOCKS` 19 to 18. Run the suite; change `MIN_PASSES` only if the printed count differs, and then only to that count with the delta explained in the commit message.
- 1.5 `apps/web-platform/test/infra/betterstack-send-failed-alert-mutation.test.sh`: `assert s.count(old) == 19` to `== 18`; the comment above it ("NINETEEN explorations ... deleted by its follow-up, which returns this count to eighteen") to "EIGHTEEN", with the canary removed from the list.
- 1.6 `apps/web-platform/test/infra/egress-gw-alert.test.sh` (CTO ruling: delete G2b wholesale, no window pin): remove the G2b block (canary derivation, assignment and consumer rows, the replace-target and resolver-collision rows, the canary alert and exploration pins, the canary-equals-production comparisons, the emitter scan with its anti-vacuity row) and the canary rows from the resource-header loop; drop the `CANARY_NAME` / `CANARY_RESOURCE` probe-literal equalities but keep `PROD_NAME` and `EMITTER_TAG`; set the exact-count row to two `egress_gw_probe_silent*` resources and two name literals (rename it from "production pair + one canary pair"); change "exactly two consumers of the production SQL local" to exactly one (and its failure text); the mute-knob row from eight blocks to six; delete every canary mutation row, the four planted-identifier file-type rows and the `CANRES`, `CANEXPL`, `CANLINE` prelude constants; remove the emitter-scan plumbing (`INFRA`, `EGW_GUARD_INFRA`, the `scan-empty` directory) if nothing else reads it, and the header prose about the canary, named explicitly: the file-header bullet for `egress_gw_probe_silent_canary`, the "The canary pair runs the SAME query ..." paragraph, and "All eight resources are in the apply workflow's MAIN plan" (now six). Keep `recovery_period`-style production-side rows (relabel the one titled "canary: a window drift on the production side alone") and re-word the "third consumer" row to a "second consumer" with its new expected fragment. Order: do the named deletions and count flips first, run the suite, and edit anything beyond that only where it goes red or where this task names it (each such edit gets a one-line reason in the commit message). Re-derive `PRESENCE_ROWS` and `MUT_ROWS` from runs (never from arithmetic on the deleted rows). Constraint (the brief): no positional-rooted `mv` appears in any helper.
- 1.7 `.github/workflows/infra-validation.yml`: comment-only edit above the "Run egress gateway alerts drift guard" step (drop "its throwaway canary pair"); the step's `name`/`run` lines are pinned by the guard and stay byte-identical.

### Phase 2 - Documents (second commit)

- 2.1 `knowledge-base/engineering/operations/runbooks/cron-egress-blocked.md` (the `### Egress gateway (Better Stack alerts)` section; the heading must stay, the egress guard pins its slug): replace the "Canary (throwaway, #12180)" paragraph with a retired-canary paragraph (the pair was deleted by #12189 through the merge apply; the soak probe stays as the reproduction); drop the "A green alert is not evidence of health until the canary below has fired" bullet in favor of "the canary fired (comment link) and is retired"; keep the decision table 1:1 with the probe's verdicts (the probe code is unchanged, so its canary-live branches still emit them) and add one lead-in line saying the canary-live rows are reachable only until the destroy applies; update the pass row and the retired row to the end state; replace the "Deleting the canary" recipe with a past-tense retirement record, and sweep the section by grep (`grep -n -i canary` over it, which also finds the "cannot separate them" line in the evaluator paragraph, the "The canary shares the production query shape" sentence, the "Two limits that follow" passage and the not-measured list) so every remaining canary mention is past tense (what changed, that two `-target` lines and two INTENDED_DESTROYS entries remain until #12270). Add the two residuals under a clearly labelled "Unverified after the canary's deletion" paragraph: **A.** exit 0 depends on the vendor still listing the canary incident after its alert is deleted; if it does not, the probe returns the distinct exit 5 "canary retired, incident unreadable", and tracker #12189 is closed by hand citing the latest comment on #12189 that read `canary=fired`, removing its `follow-through` label so the sweeper stops scanning it; do not build the poller on that evidence. **B.** the canary's mirror issue #12242 closes itself only when the incident leaves the vendor's open list; if the vendor keeps the incident open after the alert is gone, the mirror keeps posting "Still open" every 15 minutes, a hand close files a fresh P1 at the next run, and resolving the incident is a Better Stack write that needs the owner's per-command go-ahead; say so on tracker #12189. Wording must pass `scripts/lint-infra-no-human-steps.py` (no human actor beside an infra imperative).
- 2.2 `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` (the egress bullet around "A throwaway canary alert ... must fire. Until it has fired"): past tense, point to the runbook section for the end state; keep the `rows_in_window` / `doppler run` guidance.
- 2.3 `scripts/followthroughs/egress-gw-probe-silent-12180.sh`: ONE comment line inside the `# RETIREMENT:` block recording the state after this PR (sites 1, 3b, 4, 5, 6 and 7 done by #12189's change; sites 2 and 3 (the two `-target` lines and the two INTENDED_DESTROYS entries) pending in #12270; site 10 (the mirror issue closing itself) pending the apply and confirmed after it; site 8 deferred to #12271; site 9 unchanged). Remove no token the probe test greps for; no code line changes (CTO ruling). The block's sed range in the probe test starts at `# RETIREMENT:` and ends at the first non-comment line, so the new line must be a `#` line inside it.
- 2.4 `knowledge-base/engineering/architecture/decisions/ADR-218-...logtail-provider.md`: append a new dated amendment (2026-11-06, #12189, Ref #12180) that records the end state: the canary fired (`canary=fired` read 2026-11-06 in the tracker comment), the soak held, the pair was deleted by the merge apply with `[ack-destroy]`; alert counts stated separately (Terraform-managed 19 to 18; live 20 to 19, the ADR's 2026-11-05 live read of 19 plus the canary); the Enforcement pins of the 2026-11-05 amendment that no longer exist; the canary decision table retired; one line pointing to the runbook section for the two residuals (they are written once, there); the remaining pending cleanup (#12270). Leave every earlier paragraph untouched, but add short bracketed `[Amendment 2026-11-06 (#12189): superseded by the amendment below]` pointers on the now-false sentences (the "Alert count" paragraph, the "Canary and decision rule" paragraph, the "Enforcement" paragraph, and the 2026-11-06 amendment's "Exit 0 and the canary" paragraph).

### Phase 3 - Verification (local, read-only, no push)

- 3.1 Run every touched suite to green (list in AC 1), then every other suite that names logtail resources (derived, not typed: `git grep -l logtail_exploration -- tests scripts apps/web-platform/test apps/web-platform/infra plugins`, about 20 `*alert*.test.sh` guards, so an orphan guard that also reads the alert set is not missed). Re-derive floors from the printed counts only.
- 3.2 Real-tree scratch mutants for the Guard Contract matrix, each in a scratch copy under the scratchpad directory (never the worktree), results recorded in the PR body: three runs: Guard 1 row 1 (the exact pins go red while the floors stay green), Guard 2 row 1 (targets dropped, entries kept; the CTO-ruled case) and Guard 2 row 2 (entries dropped, targets kept). The other matrix rows are covered by the existing committed batteries (M-10b, M-g4-7, the egress suite's own rows) and are re-confirmed by running those suites.
- 3.3 `python3 scripts/lint-guard-contract.py knowledge-base/project/plans/2026-11-06-chore-retire-egress-gw-probe-silent-canary-plan.md`, `python3 scripts/lint-infra-no-human-steps.py` on each changed `.md`, `plugins/soleur/test/c4-count-parity.test.sh`, and the repo's affected-suite runner for the changed paths (the fixture-relative and argv-bearer ratchets run there).
- 3.4 Probe test (CTO follow-up ruling): `git grep -lE 'silent_canary|probe-silent-canary' -- ':(top)' ':(top,exclude)knowledge-base/project' ':(top,exclude)scripts/followthroughs'` lists the survivors (expected: the apply workflow, the census file, both runbooks and ADR-218, plus any file whose edited comments still name the token). In `egress-gw-probe-silent-12180.test.sh` replace the `ref_n -ge 6` anti-vacuity row with an explicit expected-referrer-set assertion equal to that measured list (stricter than a floor: a vacuous or an extra referrer both fail), then re-pin `MIN_ASSERTIONS` to the printed total after checking the change equals exactly (old referrer count minus new) plus any rows deliberately added. Both numbers are derived from live repo state after a deletion, not baseline ratchets; say so in the commit message, and name that the later `-target` removal (#12270) shrinks the set again. Keeping canary tokens in comments only to hold 6 and 430 is rejected.

### Phase 4 - Ship preparation (stops before merge)

- 4.1 Re-run the probe once, read-only (`doppler run -p soleur -c prd_terraform -- bash -c 'BETTERSTACK_API_TOKEN="$BETTERSTACK_API_TOKEN_READONLY" bash scripts/followthroughs/egress-gw-probe-silent-12180.sh'`, the form the runbook documents; the remap keeps it on the read-only token) and post its single `SOLEUR_EGRESS_GW_SILENT_SOAK` line, in a code fence under a one-line prose lead (never a `### Sweeper run` heading, which the sweeper's own markers use), as a comment on #12189 as the current `canary=fired` citation. A GitHub comment is not a Better Stack write. If the credentials are unavailable, say so in the PR body and keep the 12:33Z comment as the citation.
- 4.2 Reference #12270 and #12271 from the ADR amendment and the probe STATUS line (the issues were filed during planning).
- 4.3 Add an empty commit `chore(infra): ack the two intended destroys of the retired egress-gw canary pair (Ref #12189)` whose body has `[ack-destroy]` on its own line, followed by a sentence naming what the merge deletes (the canary alert and its exploration; nothing else in the plan is destructive). No other commit message in the branch carries that line.
- 4.4 Open the PR for review. The first line of the PR body answers "does merging this alone mutate production?": yes, the push-triggered apply destroys exactly two Better Stack Logs resources (the canary alert and its exploration) and the merge click is the authorization. The body carries `Ref #12189` (no closing keyword near #12189 or #12242, in the title, the body or any commit message); assert `gh pr view <N> --json closingIssuesReferences` is empty. The body also notes that between the merge and the apply landing the sweeper may post an ACTION REQUIRED exit-5 "delete the canary" comment on #12189; that is the expected pre-apply reading, not a regression.
- 4.5 Run review and fix findings; wait for CI to be green.
- 4.6 STOP. Ask the operator for an explicit per-command go-ahead that names the merge. No merge, no auto-merge, no apply, no workflow dispatch, no push while the change waits in the merge queue.

### Phase 5 - After the operator's go-ahead (agent-run, read-only)

- 5.1 Watch the push-triggered apply (a Monitor on the run, not a background poll): expect "Plan: 0 to add, 0 to change, 2 to destroy" and "Apply complete! Resources: 0 added, 0 changed, 2 destroyed".
- 5.2 Read-only checks with the read-only token: `soleur-egress-gw-probe-silent-canary-prd` absent from `GET /api/v2/alerts`; `soleur-egress-gw-probe-silent-prd` present, unpaused, `higher_than 0`.
- 5.3 Mirror issue #12242: wait for the mirror's next 15-minute runs; it must close on its own. If the incident is still open in the vendor list, comment on #12189 (RETIREMENT item 10) and surface the owner-gated resolve; do not close #12242 by hand.
- 5.4 The next sweep (or a read-only probe run) returns exit 0 (tracker closed by the sweeper) or the distinct retired exit 5 (tracker closed by hand citing the last `canary=fired` comment, `follow-through` label removed).
- #12270 (removing the kept targets and entries) is its own tracked task after 5.2 holds; it is outside this PR and this session.

## Files to Edit

1. `apps/web-platform/infra/betterstack-logs-alerts.tf`
2. `tests/scripts/test-infra-privileged-tier-census.sh`
3. `apps/web-platform/infra/betterstack-alert-structure.test.sh`
4. `apps/web-platform/test/infra/logs-alert-query-period-ceiling.test.sh`
5. `apps/web-platform/test/infra/betterstack-send-failed-alert-mutation.test.sh`
6. `apps/web-platform/test/infra/egress-gw-alert.test.sh`
7. `.github/workflows/infra-validation.yml` (comment only)
8. `knowledge-base/engineering/operations/runbooks/cron-egress-blocked.md`
9. `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md`
10. `knowledge-base/engineering/architecture/decisions/ADR-218-native-better-stack-logs-alerts-are-terraform-managed-via-the-logtail-provider.md`
11. `scripts/followthroughs/egress-gw-probe-silent-12180.sh` (one comment line)
12. `scripts/followthroughs/egress-gw-probe-silent-12180.test.sh` (CTO follow-up ruling: its derived-referrer row and exact `MIN_ASSERTIONS` pin are derived from live repo state and move with the retirement)

Not edited, on purpose: `.github/workflows/apply-web-platform-infra.yml` (the two `-target` lines stay), `APPLY_FLOOR_EPOCH`, the probe's code, `scripts/test-all.sh`, `scripts/suite-shard-legs.tsv`, `scripts/suite-durations.tsv`, `scripts/test-affected-kb-consumers.baseline.txt` and `tests/scripts/test-argv-bearer-sweep.sh` (they name the probe file, not the canary).

## Files to Create

1. `knowledge-base/project/specs/feat-one-shot-12189-retire-egress-gw-canary/tasks.md`
2. `knowledge-base/project/specs/feat-one-shot-12189-retire-egress-gw-canary/decision-challenges.md` (already written in planning)

## Open Code-Review Overlap

None. (Queried the open `code-review` issues for every path in Files to Edit; no body names any of them.)

## Guard Contract

### Guard 1 — Resource-set count pins

**Property.** Every pinned number that describes the logs-alert resource set equals the declared set after the retirement, and a block added or removed in either direction turns at least one pin red.

**Assembly.** Six separate readers of `betterstack-logs-alerts.tf`, no shared chokepoint, so each is named: (a) `CENSUS_FLOOR_ALERTS` and `CENSUS_FLOOR_EXPLORATIONS` in `betterstack-alert-structure.test.sh` (`-ge` floors, so they see removal only; row M-10b removes one pair and requires red); (b) `EXPECT_BLOCKS` (exact) in `logs-alert-query-period-ceiling.test.sh`; (c) `assert s.count(old) == N` (exact) in `betterstack-send-failed-alert-mutation.test.sh`; (d) the exact-count rows of `egress-gw-alert.test.sh` (two `egress_gw_probe_silent*` resources, two name literals, one consumer of the production SQL local, six blocks in the mute-knob row); (e) the assertion floors `PRESENCE_ROWS` and `MUT_ROWS` of the same suite; (f) the probe test's derived-referrer anti-vacuity floor. Pair identity (a swap that keeps every count) is carried by the census G4c, which compares the merge-base declarations to HEAD and refuses any deletion that is not a `removed` block or an INTENDED_DESTROYS entry whose target still exists.

**Mutation matrix:**

| # | Mutation (scratch copy of the real post-change tree) | Expected |
|---|---|---|
| 1 | Re-add the canary pair to the `.tf` (a revert of the deletion alone, every test edit kept) | RED in (b), (c) and (d); (a) stays GREEN, which is why the exact pins exist |
| 2 | Delete one permanent pair (for example `egress_gw_deny_spike`) | RED in (a) (17 below 18), (b), (c) and (d)'s block row |
| 3 | Add a second differently-named pair (`egress_gw_probe_silent_canary2`) after the compliant 18 | RED in (b), (c) and (d) (resource count 4, not 2) |
| 4 | Own dispatch: run the egress suite against an empty or unreadable `.tf` through its seam | RED or FATAL (never "0 checked" and rc 0) |

**Harness rows:**

- The existing `mutate_floor_red` row (bump `PRESENCE_ROWS` by one, expect red) must still locate its sed anchor after the edit and still resolve red.
- Must-PASS inputs that are not the canonical tree: the existing comment-only and whitespace-reflow rows must stay green after the edit.
- A scorer control: the existing "wrong fragment" row must still grade as a wrong-reason red.

**Anchor.** The pins are stored values compared with the same diff's tree; what lives outside the commit is the merge-base declaration read by G4c and the apply's own destroy count (2) gated by `[ack-destroy]`.

### Guard 2 — Kept-target window (INTENDED_DESTROYS and the bare targets)

**Property.** The two canary targets are honoured as bare destroys for exactly this apply, and no other bare logtail target or silent deletion passes.

**Assembly.** The census INTENDED_DESTROYS dict is the single source; it is read by (a) census G4c (base-declared minus HEAD-declared minus `removed` blocks minus entries whose root still targets them bare), (b) census G4f (protected addresses), and (c) the structure suite's apply-parity stray check, which extracts every `"logtail_...": ` key from that dict with an awk/sed pass and exempts those targets from the stray list. The workflow's two target lines are the other half.

**Mutation matrix:**

| # | Mutation (scratch copy of the real post-change tree) | Expected |
|---|---|---|
| 1 | Delete both target lines, keep the two entries | RED in G4c (the deletion is never planned) |
| 2 | Keep both target lines, drop the two entries | RED in the structure suite's stray check (and in G4c) |
| 3 | Keep the alert entry and drop the exploration entry (one member short) | RED in the stray check naming the exploration target |
| 4 | Add a third bare logtail target for an undeclared address with no entry (a second member after a compliant first) | RED in the stray check |
| 5 | Own dispatch: make the INTENDED_DESTROYS extraction return nothing while the targets remain | RED (an empty extraction leaves the targets as strays, never a vacuous green) |

**Harness rows:**

- Must-PASS: reorder the two entries, or change their value text; both suites stay GREEN.
- Suite edit that must go red: change the extraction regex in the structure suite so it no longer matches `logtail_exploration_alert.` keys; the stray check goes RED.

**Anchor.** The entries are stored values; the independent anchor is the merge-base declaration read by G4c and the standalone `[ack-destroy]` line in the merge commit message, which the apply compares with its own plan's destroy count.

## Acceptance Criteria

Pre-merge (this session):

- [ ] 1. These suites pass on the final tree, with every floor re-derived from the printed counts: `bash apps/web-platform/infra/betterstack-alert-structure.test.sh`, `bash apps/web-platform/test/infra/logs-alert-query-period-ceiling.test.sh`, `bash apps/web-platform/test/infra/betterstack-send-failed-alert-mutation.test.sh`, `bash apps/web-platform/test/infra/egress-gw-alert.test.sh`, `bash tests/scripts/test-infra-privileged-tier-census.sh`, `bash scripts/followthroughs/egress-gw-probe-silent-12180.test.sh`, and `bash plugins/soleur/test/c4-count-parity.test.sh`.
- [ ] 2. No `egress_gw_probe_silent_canary` resource header and no `egress_gw_probe_silent_canary_sql` local remain outside `knowledge-base/` and `scripts/followthroughs/` (`git grep -nE 'resource "logtail_exploration(_alert)?" "egress_gw_probe_silent_canary"|egress_gw_probe_silent_canary_sql' -- ':(top,exclude)knowledge-base' ':(top,exclude)scripts/followthroughs'` prints nothing; the probe header's RETIREMENT item 1 still names them).
- [ ] 3. `git diff --name-only origin/main` equals exactly the 12 Files to Edit plus the planning artifacts; in particular `apply-web-platform-infra.yml` is absent (the two `-target` lines stay) and `APPLY_FLOOR_EPOCH=1793967363` is byte-identical (the probe diff is one added comment line).
- [ ] 4. The measured survivor list of `git grep -lE 'silent_canary|probe-silent-canary' -- ':(top)' ':(top,exclude)knowledge-base/project' ':(top,exclude)scripts/followthroughs'` equals the expected-referrer set asserted in the probe test (Phase 3.4); every canary mention in the two runbooks and ADR-218 prose outside the new amendment's own text is past tense or carries a superseded pointer.
- [ ] 5. `CENSUS_FLOOR_ALERTS=18`, `CENSUS_FLOOR_EXPLORATIONS=18`, `EXPECT_BLOCKS=18`, `assert s.count(old) == 18`; `egress-gw-alert.test.sh` carries the counts 2, 2, 1 and six blocks; `PRESENCE_ROWS` and `MUT_ROWS` equal the printed counts of a `MUT_SKIP=1` run and of a full run minus that.
- [ ] 6. The three scratch-copy runs of Phase 3.2 (Guard 1 row 1, Guard 2 rows 1 and 2) were made against the real tree and their outcomes (RED or GREEN as stated in the matrix) are in the PR body; the remaining matrix rows are covered by the committed batteries named there; the scratch copies are not committed.
- [ ] 7. `python3 scripts/lint-guard-contract.py <this plan>` and `python3 scripts/lint-infra-no-human-steps.py` over every changed `.md` pass.
- [ ] 8. The runbook states both residuals (exit 0 depends on the vendor keeping the canary incident; the mirror issue closes only when the incident leaves the open list) as unverified, with the by-hand close path and the owner-gated resolve path.
- [ ] 9. No positional-rooted `mv` is added to any test helper (`git diff origin/main -U0 -- '*.test.sh' | grep -E '^\+.*\bmv\b'` prints nothing), and no baseline file under `scripts/` or `tests/` changed (`git diff --name-only origin/main | grep -E 'baseline|\.tsv$'` prints nothing).
- [ ] 10. ADR-218 has a new dated amendment and bracketed superseded pointers; no earlier amendment text is otherwise changed (`git diff origin/main -U0 -- <ADR>` shows additions plus the pointer insertions only).
- [ ] 11. `egress-gw-probe-silent-12180.test.sh` carries the expected-referrer set and a re-pinned `MIN_ASSERTIONS` whose change equals (old referrer count minus new) plus any deliberately added rows; the commit message calls both derived-count flips and names #12270 as the next shrink.
- [ ] 12. No Better Stack write was made from the session: no resolve, pause or delete call, and #12242 is still open when the PR is prepared.
- [ ] 13. The PR body says `Ref #12189`; `gh pr view <N> --json closingIssuesReferences` is empty; exactly one commit message in the branch has `[ack-destroy]` on its own line; the PR body's first line says that merging destroys two Better Stack resources via the push-triggered apply.
- [ ] 14. Review findings are resolved and CI is green; the session stops with a request for an explicit per-command go-ahead naming the merge.

Post-merge (agent-run, read-only, only after the go-ahead):

- [ ] 15. The merge apply reports 2 destroyed (alert and exploration) and 0 added, 0 changed.
- [ ] 16. The live alert listing no longer carries `soleur-egress-gw-probe-silent-canary-prd`; the production alert is present, unpaused and `higher_than 0`.
- [ ] 17. #12242 closes on its own, or the vendor-kept-incident case is reported on #12189 and surfaced for an owner-gated resolve.
- [ ] 18. Tracker #12189 is closed by the sweeper (exit 0) or by hand per the retired exit 5 path.

## Test Scenarios

- Given the post-change tree, when the five guard suites and the census run, then all pass with the new numbers (integration, shell suites).
- Given the canary pair is re-added to the `.tf` alone, when the exact-count pins run, then `EXPECT_BLOCKS`, the `== 18` anchor and the egress exact-count row go red (integration, scratch tree).
- Given one permanent pair is removed, when the structure suite runs, then the census floor goes red (integration; row M-10b already covers this, re-confirmed at 18).
- Given the two target lines are removed while the INTENDED_DESTROYS entries remain, when the census runs, then G4c goes red (integration, scratch tree).
- Given the two entries are removed while the targets remain, when the structure suite runs, then the apply-parity stray check goes red (integration, scratch tree).
- Given the probe runs against a `.tf` without the canary and the vendor still lists the canary incident and every other check held, then it exits 0; given the vendor lists no canary incident, then it exits 5 with the retired message (unit; both already covered by `egress-gw-probe-silent-12180.test.sh`, re-run unchanged).
- Given the work phase cannot read the probe credentials, when it prepares the PR, then the PR body records that and keeps the 12:33Z citation (the fallback citation).
- Regression: the production silent alert's name, windows, channels, `higher_than 0`, `treat_as_zero` and INFERRED label are still pinned and still red when mutated (the retained production-side mutation rows).

## Non-Goals

- No Better Stack write of any kind from this session; no apply, no workflow dispatch, no merge before the go-ahead.
- No removal of the two `-target` lines or of the INTENDED_DESTROYS entries (that is #12270, after the apply).
- No probe code change and no transport extraction (#12271); no `APPLY_FLOOR_EPOCH` change.
- No heartbeat poller (#12190): the canary fired.
- No change to the production alert, the fail alert, the deny-spike alert, or the Sentry detectors.

## Dependencies & Risks

- **Vendor behavior after the alert delete (unverified).** The canary incident may stay open, resolve, or disappear. Open: probe exit 0 and tracker closes, but #12242 keeps posting until an owner-gated resolve. Resolved: both close. Gone: probe exit 5 retired path, tracker closed by hand, mirror closes. All three are documented (Phase 2 task 2.1) and the post-merge checks distinguish them.
- **`[ack-destroy]` breadth.** It acks every destroy in the targeted plan. Mitigation: the last main apply was clean ("0 destroyed"), and Phase 5 task 5.1 checks "2 to destroy" in the run log; a plan with any other destroy fails the stated expectation and is reported, not acked silently.
- **Merge-time message loss.** If the squash message did not carry the standalone line, the apply fails closed at the destroy gate (no destroy happens); the PR body and Phase 4 task 4.3 make the line a dedicated commit so the `COMMIT_MESSAGES` setting carries it.
- **Other workflows triggered by the same edit.** Editing `betterstack-logs-alerts.tf` also matches the push paths of `apply-deploy-pipeline-fix.yml`; its `-target` graph (deploy-pipeline `terraform_data` resources) reaches no `logtail_*` resource (zero mentions), so it cannot perform or pre-empt the destroy, and `scheduled-terraform-drift.yml` does not apply this root. Only `apply-web-platform-infra.yml` applies the pair.
- **Conflicts with the three open PRs touching the workflow.** None edited here; low.

**Sweeper action per probe exit code** (`scripts/sweep-followthroughs.sh`): exit 0 comments PASS and closes the tracker (it never reopens it); exit 5 comments ACTION REQUIRED and leaves the tracker open (a closed tracker stays closed); exit 2 and 3 are not-yet and cannot-establish and leave it open. Consequence for this change: between the merge and the apply landing, the probe reads a checkout without the canary but a live canary alert (`canary_alert_live=1`), which is the exit-5 "delete the canary" finding, never a pass; exit 0 becomes reachable only after the live alert is gone and the vendor still lists the incident (residual A).
- **Exact floors drift.** `PRESENCE_ROWS`, `MUT_ROWS`, `MIN_PASSES` and the probe test's `MIN_ASSERTIONS` are exact; re-derive from runs. The probe test's `ref_n >= 6` anti-vacuity floor moves only as a derived count with a stated reason.

## References & Research

- Tracker #12189; parent #12180 (closed); canary mirror #12242; fallback poller #12190; follow-ups #12270 and #12271.
- Probe and its RETIREMENT header: `scripts/followthroughs/egress-gw-probe-silent-12180.sh`; probe test: `scripts/followthroughs/egress-gw-probe-silent-12180.test.sh`.
- Precedent sequences: #11653 (`d83641f64d`, retire with kept targets and `[ack-destroy]`) then #11785 (`32b7ee7d78`, remove the retained targets and census rows).
- ADR-218 (2026-11-05 and 2026-11-06 amendments); runbook `knowledge-base/engineering/operations/runbooks/cron-egress-blocked.md`.
- Prior plans: `knowledge-base/project/plans/archive/20261106-090533-2026-11-05-fix-egress-gw-probe-silent-invert-metric-plan.md` and `knowledge-base/project/plans/archive/20261106-172530-2026-11-06-fix-egress-gw-probe-apply-floor-and-informational-resolver-plan.md`.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6; this plan carries all four lines plus the `threshold: none` scope-out because the diff touches infra paths.
- Do not add a `discoverability_test` block that declares credentials to this plan: `plugins/soleur/test/preflight-discoverability-test.test.ts` counts plans declaring them against a fixed baseline, and "never ratchet baselines" applies. This plan skips the Observability schema as delete-only.
- Do not write `Closes`, `Fixes` or `Resolves` next to #12189 or #12242 anywhere (title, body, commit messages): the tracker closes through the sweeper and the mirror issue through the mirror.
- The probe test greps the `# RETIREMENT:` block with a sed range that ends at the first non-comment line: the new STATUS line must be a `#` line inside that block, and no site token it greps for may be removed.
