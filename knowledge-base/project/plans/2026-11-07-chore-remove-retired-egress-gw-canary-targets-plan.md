---
title: "chore(infra): remove the retired egress-gw canary -target lines and census INTENDED_DESTROYS entries after the destroy applies"
date: 2026-11-07
slug: remove-retired-egress-gw-canary-targets
branch: feat-one-shot-12270-remove-retired-canary-targets
issue: 12270
type: chore
priority: p3
domain: engineering
lane: cross-domain
brand_survival_threshold: none
---

## Overview

The throwaway canary alert pair (`logtail_exploration.egress_gw_probe_silent_canary` and `logtail_exploration_alert.egress_gw_probe_silent_canary`) was destroyed by the push-triggered apply of the retirement merge (#12268, merge `d8758629231f84feb18400915bb3b6715cd6642f`, apply run 42369320061: `Plan: 0 to add, 0 to change, 2 to destroy`, then `Apply complete! Resources: 0 added, 0 changed, 2 destroyed.`). Two bare `-target` lines in `.github/workflows/apply-web-platform-infra.yml` and two `INTENDED_DESTROYS` entries in `tests/scripts/test-infra-privileged-tier-census.sh` were kept for exactly that one apply and are now dead. This change removes them together (the suites cannot be split green), re-derives every pinned number the removal moves from real runs, and brings the runbook, ADR-218 and the probe's RETIREMENT status line to the end state by appending, never rewriting dated records.

The change is delete-only and expected to move very little: the resource-count pins already moved in #12268, so this change touches no alert or exploration count. What it does move is one derived set and one exact number in the probe test (`EXPECTED_REFERRERS`, `MIN_ASSERTIONS`), measured below.

**Authorization boundary (owner's binding rules).** This session prepares the PR only: plan, work, review, compound, ship up to a green CI, then STOP BEFORE MERGE and ask for an explicit per-command go-ahead naming the merge. No `gh pr merge`, no auto-merge, no apply, no workflow dispatch, no Better Stack write of any kind (read-only GETs are allowed). No `[ack-destroy]` line anywhere: the removal plans 0 destroys, and if any run shows a destroy the work stops and reports. `Ref #12189` only, never a closing keyword next to #12189 or #12242; the PR may close its own work item #12270.

## Research Insights

**Premise Validation (Phase 0.6).** Checked with `gh`, `git` and read-only probes on 2026-11-07, all held:

- Issue #12270 is OPEN (labels `priority/p3-low`, `type/chore`, `domain/engineering`, `observability`); its re-evaluation criterion is "the apply run of the retirement merge is green and the canary alert is absent from the live listing". Apply run 42369320061 (event `push`, head sha `d8758629231f84feb18400915bb3b6715cd6642f`, conclusion `success`) logged both `Destroying...` / `Destruction complete` lines for the two canary addresses and `Apply complete! Resources: 0 added, 0 changed, 2 destroyed.` It is the latest apply on main (`gh run list --workflow apply-web-platform-infra.yml`); no later infra-path merge exists.
- Live state, read-only: the soak probe run at 2026-11-07T11:55Z (about 8 minutes after the destroy) printed `verdict=pass ... canary=fired canary_alert_live=0 canary_declared=0 prod_alert=ok ... rows_in_window=soleur-web-2:3,soleur-web-platform:3` and exited 0. So the alert is absent from the vendor listing, the production alert is present and healthy, and the vendor kept listing the canary incident after its alert was deleted (this answers Unverified A of the runbook; the work phase re-reads it once and writes the observed line, not this one).
- Current main: no canary address is left in `apps/web-platform/infra/betterstack-logs-alerts.tf` (`git grep -nE 'probe_silent_canary|probe-silent-canary' -- apps/web-platform/infra/*.tf` returns nothing). `git grep` over the whole tree finds the address only in the sites classified below.
- Issue #12189 (tracker) is OPEN; #12242 (the canary's mirror issue) is OPEN, last mirror comment 11:46:59Z (one second before the destroy), its next 15-minute tick had not posted at 12:01Z; #12271 (probe transport extraction, deferred) is OPEN and untouched here. Neither #12189 nor #12242 is closed by hand; the probe now returns `pass`, so the daily sweeper can close #12189 by itself.
- Collision pre-check (`collision-precheck.sh 12270`) exited 10 on one hit, benign: PR #12306 is this branch's own draft WIP PR. **Open PR #12292** (`feat-relay-probe-alerts`, "Better Stack log alerts for the session relay probes") is not a duplicate but sits on a pre-retirement base: it still counts the canary pair (19 to 22) in the structure suite, the ceiling suite, the send-failed anchor, ADR-218 and the runbook, and it edits `apply-web-platform-infra.yml`. It is not edited or commented on here. Whichever of the two merges second must re-sync and re-derive the shared counts; this change touches no alert or exploration count (the merged retirement already moved them), so it does not move #12292's arithmetic, only the textual neighbourhood of the `-target` list. Three older open PRs (#10928, #10678, #7390) also touch `apply-web-platform-infra.yml`: read-only note, no action.
- ADR corpus (Phase 0.6 item 4): the mechanism "remove retained destroy targets and census rows after the destroy applied" is the documented #11653 then #11785 sequence and the #12189 amendment's own follow-up #12270; no ADR rejects it.

**Measured evidence that the removal plans 0 destroys (key fact a).**

1. The apply run above: both canary resources refreshed, destroyed, and the state no longer holds them. (A direct `terraform state list` against the R2 backend was not run: no backend credential name appears in the Doppler config listing; the apply log carries the evidence.)
2. A local experiment with terraform 1.9.8 (CI pins 1.10.5; the behaviour of an unmatched `-target` address is the same) in a scratch directory: with a resource in state and its block deleted, a kept `-target` plans `1 to destroy` and applies it (this reproduces the #12268 window); afterwards the same kept bare `-target`, with no configuration and no state, plans `No changes` with `-detailed-exitcode` 0 and a structured plan with 0 delete actions; with the target removed the plan is also `No changes`; and a `-target=logtail_exploration.egress_gw_probe_silent_canary` of a provider type that is not even declared plans `No changes` (exit 0). So removing the lines cannot create a destroy, and a leftover line would also be a no-op; the lines are dead weight, not a risk.
3. The #11785 precedent (`32b7ee7d78`, apply run 41306010098): the removal of the four retained dead-man targets ended `No changes` and `Apply complete! Resources: 0 added, 0 changed, 0 destroyed.`
4. The apply's destroy guard fails closed: it counts delete actions in the structured plan (`tests/scripts/lib/destroy-guard-filter-web-platform.jq`), and a destroy without a standalone `[ack-destroy]` line in the head commit message halts the apply before anything is destroyed. This PR carries no such line, so any unexpected destroy halts rather than applies.

**Edit-site classification (key facts b and c).** Found by `git grep -nE 'probe_silent_canary|probe-silent-canary|silent-canary'` repo-wide; every hit read.

| Site | Names the canary as | Decision |
|---|---|---|
| `.github/workflows/apply-web-platform-infra.yml` lines 659-660 | two live `-target` lines | LIVE: delete both (nothing else in the file names the canary) |
| `tests/scripts/test-infra-privileged-tier-census.sh` lines 1239-1242 | two `INTENDED_DESTROYS` entries and their 2-line comment | LIVE: delete entries and comment; the four ghcr entries stay (the ceiling suite's M29 anchor starts at the first ghcr entry) |
| `apps/web-platform/infra/betterstack-alert-structure.test.sh` lines 588-597 | a comment saying the dict's only `logtail_*` entries are the canary addresses until #12270 | LIVE (false after the change): rewrite to the end state; the code is unchanged (it reads the dict by awk and sed and an empty list is its documented end state) |
| same file, lines 14 and 98-99 | true historical comments ("floors went to 19 while it lived; #12189 deleted it") | HISTORICAL: keep (CTO ruling T2) |
| `apps/web-platform/test/infra/egress-gw-alert.test.sh` G2c row (~290-294), header (34-36), mutation rows (~709-714) | guards against the canary coming back; they read only the `.tf` | HISTORICAL/guard: unchanged (CTO ruling T1). The suite does read the workflow, but only the deny, silent and fail `-target` lines through end-anchored regexes (`egress_gw_probe_silent \\$` never matches a canary line) and none of its mutation rows anchors on a canary line; re-run, counts expected unchanged and compared |
| `scripts/followthroughs/egress-gw-probe-silent-12180.sh` RETIREMENT header and STATUS line (~174) | the procedure record; STATUS says the targets and entries "stay until #12270" and item (10) is "pending the apply" | STATUS line is LIVE-false: update the comment line only (CTO ruling T4); procedure tokens stay; no code line, `APPLY_FLOOR_EPOCH=1793967363` and `CANARY_*` literals untouched |
| `scripts/followthroughs/egress-gw-probe-silent-12180.test.sh` `EXPECTED_REFERRERS` and `MIN_ASSERTIONS` | derived referrer set and exact assertion total | LIVE: shrink the set by the two files that stop naming the canary; re-pin the total from the printed count |
| `knowledge-base/engineering/operations/runbooks/cron-egress-blocked.md` retirement record (~1023-1045) | dated record with present-tense sentences now false | append a dated update and bracketed pointers (CTO ruling T3) |
| `knowledge-base/engineering/architecture/decisions/ADR-218-...md` 2026-11-06 amendment (~745-757) | dated amendment saying the targets "stay ... for this one apply" | append a new dated amendment plus bracketed pointers (T3) |
| `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` line ~332 | already past tense ("fired and was retired by #12189") | HISTORICAL: unchanged |
| `.github/workflows/infra-validation.yml` comment ~996 | already past tense ("was retired in #12189") | unchanged; the step name/run lines are pinned by the guard |
| `apps/web-platform/infra/betterstack-logs-alerts.tf`, ceiling suite, send-failed suite | no canary address left | unchanged; counts unchanged |
| `knowledge-base/project/{plans,learnings,specs}` | history | excluded from every sweep AC |

**Probe, floor and followthrough (key fact d), verified by reading.** The probe script reads neither the apply workflow nor the census (`grep -n 'apply-web-platform-infra\|INTENDED_DESTROYS\|census' scripts/followthroughs/egress-gw-probe-silent-12180.sh` hits comment lines only); `canary_declared` is derived from the `.tf` (already 0). `APPLY_FLOOR_EPOCH` stays: it is the recurrence floor for the tracker's lifetime and the issue says not to touch it. The tracker's directive (`script=scripts/followthroughs/egress-gw-probe-silent-12180.sh`) is a path, not a hash, so a comment-only edit changes nothing the sweeper executes. The egress suite mutates a copy of the probe for its `PROD_NAME` row, which reads code lines only.

**Baseline run (Phase 0 evidence, this worktree, before any edit; concurrent run, all exit 0).**

| Suite | Result | Pinned figure |
|---|---|---|
| `apps/web-platform/infra/betterstack-alert-structure.test.sh` | 110 passed, 0 failed | floor 110 |
| `apps/web-platform/test/infra/logs-alert-query-period-ceiling.test.sh` | 116 passed, 0 failed, 116 cases | `EXPECT_BLOCKS` 18, `MIN_PASSES` 116 |
| `apps/web-platform/test/infra/egress-gw-alert.test.sh` | 128 passed, 0 failed | floor 128 |
| `apps/web-platform/test/infra/betterstack-send-failed-alert-mutation.test.sh` | 39 passed, 0 failed (38 cases) | n/a |
| `scripts/followthroughs/egress-gw-probe-silent-12180.test.sh` | 429 assertions, 0 failed | `MIN_ASSERTIONS` 429 |
| `tests/scripts/test-infra-privileged-tier-census.sh` | 422 passed, 0 failed | n/a |
| `plugins/soleur/test/worktree-manager-bare-sync.test.sh` | ALL TESTS PASSED (Failed: 0) | census F7 population floor 40 |
| `apps/web-platform/infra/luks-monitor-install.test.sh` (reads the census dict) | 187 passed, 0 failed | exact floor, read at work time |

**Rehearsal (plan-time, scratch copy of the whole tree under the session scratchpad, never the worktree; the work phase re-derives everything in the real worktree).** The two target lines and the two census entries were deleted in a scratch git copy of `HEAD`; the derived referrer command `git grep -lE 'silent_canary|probe-silent-canary' -- ':(top)' ':(top,exclude)knowledge-base/project' ':(top,exclude)scripts/followthroughs'` then lists exactly five files: `betterstack-alert-structure.test.sh`, `egress-gw-alert.test.sh`, `ADR-218`, `betterstack-log-query.md`, `cron-egress-blocked.md` (the apply workflow and the census drop out). Rehearsal results: ceiling suite 116 passed, 0 failed, 116 cases (unchanged); egress-gw-alert suite 128 passed, 0 failed, floor 128 (unchanged); send-failed mutation suite 39 passed, 0 failed, 38 cases (unchanged); census 422 passed, 0 failed with `IPT_BASE_REF=HEAD` (unchanged: G4c, G4f and G4g stay green with the entries gone and the targets gone together); probe test 427 assertions ran against its old pin of 429 (so the pin moves by exactly 2); the structure suite 110 passed, 0 failed, floor 110 (unchanged). Guard 1 rows 1-3 were also driven on a scratch copy with `--presence-only`: re-adding both canary targets, re-adding only the exploration target, and adding a third undeclared `logtail_exploration.zz_retired_x` target each exit 1 with `[FAIL] apply parity: -target=logtail_* line(s) naming no enumerated resource: ...` naming exactly the added address(es), and the restored copy exits 0. `luks-monitor-install.test.sh` 187 passed, 0 failed (unchanged from the baseline); the work phase re-derives all of these in the real worktree.

**Property List (Phase 0.6b).**

1. The apply allowlist and the census name no address that has neither configuration nor state: the window opened by #12268 is closed.
2. Removing the lines plans no destroy, so no `[ack-destroy]` exists anywhere in the branch.
3. Every pinned number the removal moves is the number a real run prints, and the pins still go red when a member is added or removed.
4. No document claims the targets or entries are kept, and no dated record is rewritten.
5. Nothing in this session writes to Better Stack, and #12189, #12242 close through their own mechanisms.

**Cut List (Phase 0.6b).**

| Mechanism | Property | Disposition |
|---|---|---|
| Trimming or renaming the G2c row and the canary-naming mutation rows of `egress-gw-alert.test.sh` | none | CUT (CTO T1): they guard a canary returning and do not read the removed lines |
| Rewording the true historical comment at structure-suite lines 98-99 to shrink the referrer set to four | none | CUT (CTO T2): editing a comment to fit a count is rejected |
| A new committed must-PASS row for the structure suite's census-fed exemption path | 3 | CUT (CTO T5): the suite fails closed when the list is empty; the earlier ruling cut the same row |
| A real production `terraform plan` before the go-ahead | 2 | CUT (CTO T6): disproportionate; evidence above; the post-merge apply is the check |
| Probe transport extraction (#12271) and any `APPLY_FLOOR_EPOCH` change | none | OUT OF SCOPE: tracked (#12271) / explicitly forbidden by the issue |
| `repo-research-analyst` and the community-registry overlap search | none | SKIPPED (taste): delete-only change; sites found by a repo-wide grep |

**Applicable institutional learnings** (under `knowledge-base/project/learnings/`).

- `2026-11-06-a-single-merge-ack-needs-a-recovery-line-and-i-wrote-two-claims-the-panel-measured.md`: the direct precursor; the runbook says do not start #12270 until the apply log shows `2 destroyed` (satisfied); cite recorded evidence, not session readings.
- `2026-07-17-target-scoped-terraform-apply-makes-resource-deletion-a-silent-noop.md` and `2026-07-17-unmanaged-is-not-dead-and-a-plan-premise-about-a-repo-setting-is-checkable.md`: in a `-target` apply a deletion happens only while the address is targeted; `[ack-destroy]` must sit alone on a body line. Here neither applies (no destroy), which is why no commit carries the line.
- `2026-10-15-a-new-nonpaging-marker-moved-a-pin-in-a-suite-the-affected-gate-never-selects.md` and `2026-10-14-my-stubs-checked-the-shape-of-argv-and-never-the-value-and-a-glob-registered-suite-degrades-the-affected-gate.md`: `--affected` does not select `apps/web-platform/test/infra/*.test.sh`, so the pinned-count batteries there go unseen locally. This is why Phase 3 names every suite explicitly rather than trusting the affected gate (the gap behind "CI found a regression the local gate missed").
- `2026-11-06-a-pinned-floor-needs-its-value-pinned-and-an-unreachable-backstop-must-be-driven-through-a-mutated-copy.md`, `2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md`: re-derive pins from the printed count and drive backstops through a mutated copy.
- `2026-09-27-a-retirement-census-by-name-missed-the-consumer-that-pinned-the-id.md`: sweep by identifier as well as by name (`silent_canary`, `probe-silent-canary`, `egress-gw-probe-canary-absent`, `CANARY_NAME`, `CANARY_RESOURCE`).
- `2026-06-05-followthrough-pr-body-prose-closes-keyword-autocloses-tracker.md` and `2026-06-29-auto-closes-meta-content-in-commit-body-trips-github-autoclose-on-hand-rolled-merge.md`: no closing keyword near #12189 or #12242 in the title, body or any commit message; assert `closingIssuesReferences` lists only #12270.
- `2026-09-14-i-tested-both-endpoints-and-left-the-wire-between-them-unpinned.md`: the remedy for a ratchet failure is the code, never the baseline.
- Locale: `comm` and `join` collate by the ambient locale; `plugins/soleur/test/worktree-manager-bare-sync.test.sh` Test F7 scans every tracked script that contains `LC_ALL=C sort|uniq` and fails any non-comment `comm`/`join` with a `-<digit>` option that lacks `LC_ALL=C` directly in front of it. This change writes no new `comm`/`join`; if any is written, `LC_ALL=C` is pinned on it (and F7 is run). The existing structure-suite `comm` pair is plain `sort -u` on both sides and is untouched.

## Research Reconciliation — Spec vs. Codebase

| Brief or issue claim | Reality (measured) | Plan response |
|---|---|---|
| "comments in infra-validation.yml" are an edit site | the comment already reads "its throwaway canary pair was retired in #12189" (past tense, accurate) | no edit |
| "betterstack-log-query.md" is an edit site | the egress bullet is already past tense and points to the runbook | no edit |
| "the egress-gw-alert suite G2c exact-count rows and mutation rows" move | G2c and its mutation rows read only the `.tf`; the suite's workflow reads cover only the deny, silent and fail lines (end-anchored), never a canary line, and nothing reads the census | unchanged; run and compare (expected 128 / floor 128); CTO T1 |
| "the stray-target check in betterstack-alert-structure.test.sh" needs a change | the code is correct for the empty list (the documented end state after #11785); only a comment is false | comment rewrite only; run proves no count moves (expected 110) |
| "census G4c" moves | G4c is a base-relative verdict; the dict entries are read, not counted; no census total is pinned to the dict length | run proves 422 unchanged |
| Issue item 3: "RETIREMENT header STATUS line ... runbook ... ADR-218 amendment" say the targets are kept | confirmed false after the change | STATUS comment edit; runbook and ADR appended with bracketed pointers |
| The issue says "No Better Stack write is needed; do not touch `APPLY_FLOOR_EPOCH`" | confirmed; the probe reads neither workflow nor census | no probe code change |
| The brief's EXPECTED_REFERRERS derivation shrinks | confirmed by rehearsal: 7 referrers to 5 | re-derive in the worktree from the printed list |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "remove the now-dead canary `-target` lines from apply-web-platform-infra.yml" [issue #12270 / brief] | Phase 1.1, Files to Edit 1 | mapped |
| 2 | "the two canary entries from INTENDED_DESTROYS in tests/scripts/test-infra-privileged-tier-census.sh, together in one PR" [brief] | Phase 1.2, Files to Edit 2 | mapped |
| 3 | "Verify state with gh first (the #12270 body, current main, no canary address left in betterstack-logs-alerts.tf)" [brief] | Research Insights, Phase 0.1 | mapped |
| 4 | "Re-derive every count, floor and mutation row the removal touches from runs, never edit to fit" [brief] | Phase 3.1-3.3, Guard Contract | mapped |
| 5 | "census G4c, the structure suite stray-target check, the egress-gw-alert suite, the probe test's derived referrer set (EXPECTED_REFERRERS) and its MIN_ASSERTIONS" [brief] | Phase 1.2-1.4, Phase 3 | mapped |
| 6 | "plus the runbook and ADR-218 retirement wording (append, do not rewrite dated records)" [brief] | Phase 2.1, 2.2 | mapped |
| 7 | "RETIREMENT header STATUS line in `scripts/followthroughs/egress-gw-probe-silent-12180.sh`" [issue #12270] | Phase 1.5 | mapped |
| 8 | "STOP BEFORE MERGE and ask for the explicit per-command go-ahead naming the merge" [brief] | Phase 4.6 | mapped |
| 9 | "No [ack-destroy] line should be needed: the plan must show 0 destroys; if it shows any, stop and report" [brief] | Research Insights (evidence), AC 6, the post-go-ahead step in 4.7 | mapped |
| 10 | "Use `Ref #12189` only" ; "Do not close the mirror issue #12242 or the tracker #12189 by hand" [brief] | Phase 4.4, AC 8 | mapped |
| 11 | "Pin LC_ALL=C on any comm or join you write" ; "Run the FULL guard suites locally, including plugins/soleur/test/worktree-manager-bare-sync.test.sh, and re-sync with origin/main before the final push" [brief] | Phase 3.1, 3.4, 4.1 | mapped |
| 12 | "Do not edit or comment on that PR" (#12292) [brief] | Non-Goals; recorded in Research Insights | mapped |
| 13 | "At the end report exactly what is left for the owner and print the resume prompt" [brief] | Phase 4.7 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Delete the two workflow target lines | "remove the now-dead canary `-target` lines" | asked |
| Delete the two census entries and their comment | "the two canary entries from INTENDED_DESTROYS" | asked |
| Rewrite the structure suite's false comment block | "the structure suite stray-target check" | asked |
| Shrink `EXPECTED_REFERRERS`, re-pin `MIN_ASSERTIONS` | "the probe test's derived referrer set (EXPECTED_REFERRERS) and its MIN_ASSERTIONS" | asked |
| STATUS comment update in the probe script | "RETIREMENT header STATUS line" | asked |
| Runbook and ADR-218 append | "the runbook and ADR-218 retirement wording (append, do not rewrite dated records)" | asked |
| Bracketed pointers on now-false sentences | "append, do not rewrite dated records" | inferred - justification: the ADR already uses the pattern and without a pointer the runbook still tells an on-call reader "Do not start #12270"; pointers only add text (CTO T3) |
| Scratch-copy mutation battery, recorded in the PR body | "Every count/floor/mutation row the removal moves must be re-derived from a real run (mutation battery included)" | asked |
| Explicit suite list instead of `--affected` | "Run the FULL guard suites locally" | asked |

### Split Assessment

- Subsystems touched: 3 - `.github/workflows` + `tests/scripts` (apply allowlist and census), `apps/web-platform/infra` + `scripts/followthroughs` (guard suites and probe), `knowledge-base/engineering` (runbook and ADR).
- Planned files: 8 edits | Estimated changed lines: about 120 (deletions and comment prose, plus about 60 lines of appended dated text)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly. This edits an infra apply allowlist, CI guard suites and documentation; no user-facing surface. The worst case is a red CI or a halted infra apply (the destroy guard fails closed), which delays the next infra deploy but loses no data.

**If this leaks, the user's data is exposed via:** no vector. No secret, credential, user record or user-facing content is read, written or printed; the read-only probe prints a projected status line only, and no secret value enters any artifact.

**Brand-survival threshold:** none

threshold: none, reason: the diff touches `.github/workflows/apply-web-platform-infra.yml` and `apps/web-platform/infra/` guard files (sensitive-path regex) but only deletes two dead target lines, two dead census entries and edits comments and tests; it adds no resource, credential, permission, network path or data store, and the apply's destroy guard still fails closed on any destroy.

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** The CTO agent ruled six technical forks on 2026-11-07 (rows T1-T6 in `knowledge-base/project/specs/feat-one-shot-12270-remove-retired-canary-targets/decision-challenges.md`): leave the egress suite's canary-naming rows alone, rewrite only the false structure-suite comment, append plus bracketed pointers in runbook and ADR, update the probe STATUS comment only, add no exemption-path row, and require no production plan. Other domains (product, marketing, legal, finance, sales, support, operations) have no implication: no user-facing surface, no data processing, no spend change. GDPR gate (2.7): not triggered (no schema, auth, API route, data movement or LLM use). Architecture gate (2.10): not triggered - no architectural decision is made or changed; ADR-218 is appended as a record of an already-decided end state, and `plugins/soleur/test/c4-count-parity.test.sh` is run as the C4 evidence (the change moves no count the `.c4` files embed: no alert, exploration, workflow or monitor is added or removed). Encryption gate (2.11): not triggered (no store or connection). Infrastructure-as-Code routing (2.8): not triggered (no new infrastructure; two dead lines are removed from an existing IaC allowlist). Task design (2.9.3): not triggered (no new autonomous task surface). Soak follow-through enrollment (2.9.1): not triggered (this change declares no soak criterion; the existing tracker #12189 is already enrolled and its probe now reads `pass`).

## Observability

```yaml
liveness_signal:
  what: the push-triggered apply run for the merge commit of this change, in particular the plan step's destroy count and the apply's final summary line
  cadence: once per merge that touches apps/web-platform/infra/** or the apply workflow
  alert_target: the apply workflow's notify-apply-failure job (ops email through the notify-ops-email action) plus the destroy guard, which fails the run closed on any unacked destroy
  configured_in: .github/workflows/apply-web-platform-infra.yml (jobs preflight, apply, notify-apply-failure; the destroy-guard step reads tests/scripts/lib/destroy-guard-filter-web-platform.jq)
error_reporting:
  destination: GitHub Actions run log of the apply workflow (no application runtime path is touched); failure surfaces through notify-apply-failure
  fail_loud: "::error::" lines from the destroy guard and a red apply run; locally, each guard suite exits non-zero and prints its [FAIL]/FATAL line
failure_modes:
  - mode: the post-merge plan unexpectedly shows a destroy (a leftover address in state that this analysis missed)
    detection: the destroy guard counts delete actions in the structured plan and halts without a standalone [ack-destroy] line; the run is red
    alert_route: notify-apply-failure ops email; the work stops and reports, no ack is added
  - mode: a guard suite reads the removed lines or entries and reds in CI (the class that bit the previous retirement)
    detection: the explicit suite list in Phase 3 plus the CI required checks
    alert_route: PR check status; fix the code, never the pin
  - mode: a stale canary token is re-introduced later
    detection: the probe test's explicit EXPECTED_REFERRERS set and the structure suite's stray-target check go red
    alert_route: CI on the introducing PR
logs:
  where: GitHub Actions logs of the apply workflow run (gh run view <id> --log) and of the CI checks
  retention: GitHub default run-log retention (90 days)
discoverability_test:
  command: bash -c 'n=$(git grep -lE "probe_silent_canary" -- .github/workflows/apply-web-platform-infra.yml tests/scripts/test-infra-privileged-tier-census.sh | wc -l); echo "canary_target_files=$n"'
  expected_output: canary_target_files=0
```

## Infrastructure (IaC)

Not triggered as a new-infrastructure change: no server, service, secret, vendor account, DNS record, firewall rule or monitor is added. The edit removes two dead lines from the existing Terraform apply allowlist and two dead entries from its census.

### Terraform changes

None to any `.tf` file (`apps/web-platform/infra/betterstack-logs-alerts.tf` already declares no canary). No provider, version pin or variable changes.

### Apply path

The merge's push-triggered apply (`apps/web-platform/infra/**` and the workflow file are in its `paths:`) plans the main allow-list; expected outcome `No changes` for the logtail addresses and 0 destroys. Expected downtime: none.

### Host fan-out

None; no `terraform_data` SSH provisioner is touched.

### Distinctness / drift safeguards

No `dev != prd` or `ignore_changes` change. The shared concurrency group (`apply-web-platform-infra.yml` and `apply-deploy-pipeline-fix.yml`) is unchanged; because this change plans no destroy, the single-merge `[ack-destroy]` fragility documented for #12268 does not arise.

### Vendor-tier reality check

No Better Stack write; no free-tier gate affected.

## Implementation Phases

### Phase 0 - Baseline and state re-read (read-only)

- 0.1 `gh issue view 12270 12189 12242 --json state`, `gh run view 42369320061 --json conclusion,headSha` and the log lines `Plan: 0 to add, 0 to change, 2 to destroy` / `Apply complete! Resources: 0 added, 0 changed, 2 destroyed.`; `git fetch origin main` and `git log --oneline HEAD..origin/main` (note anything that touches the files below). Re-run the soak probe read-only once, in the documented form: `doppler run -p soleur -c prd_terraform -- bash -c 'BETTERSTACK_API_TOKEN="$BETTERSTACK_API_TOKEN_READONLY" bash scripts/followthroughs/egress-gw-probe-silent-12180.sh'`; record the printed line (it carries no secret). Re-read the latest comment on #12242 for the mirror's behaviour after the destroy.
- 0.2 Freeze the census: `git grep -nE 'silent_canary|probe-silent-canary|egress-gw-probe-canary-absent' -- ':(top)' ':(top,exclude)knowledge-base/project'`; every hit is either edited below or an expected survivor listed in AC 4.
- 0.3 Re-run the baseline table above in the worktree (the numbers there are the plan-time reading; the work phase prints its own).

### Phase 1 - Code and guards (one atomic commit; the suites cannot be split green)

Commit subject: `chore(infra): remove the retired egress-gw canary -target lines and census entries (Ref #12189)`. The message carries no `[ack-destroy]` and no closing keyword.

- 1.1 `.github/workflows/apply-web-platform-infra.yml`: delete exactly the two lines `-target=logtail_exploration.egress_gw_probe_silent_canary \` and `-target=logtail_exploration_alert.egress_gw_probe_silent_canary \` from the main plan's list (lines 659-660). Add no comment inside the backslash-continued list (a `#` line there makes the next line a command name). `git diff --stat` must show 2 deletions in this file.
- 1.2 `tests/scripts/test-infra-privileged-tier-census.sh`: delete the two entries and the 2-line `# #12189:` comment inside `INTENDED_DESTROYS["apps/web-platform/infra"]`; leave the four ghcr entries, `RETIRED_STATE_ABSENT`, `G4_PROTECTED` and every floor untouched.
- 1.3 `apps/web-platform/infra/betterstack-alert-structure.test.sh`: rewrite the comment block above `CENSUS_SH` (currently ~588-597) to the end state: the retired destroy-target list is read from the census; after #12270 it has no `logtail_*` entry, which is the legitimate end state (as after #11785), and any bare `-target=logtail_*` line naming no enumerated resource is a stray. No code line changes. Lines 14 and 98-99 stay (CTO T2).
- 1.4 `scripts/followthroughs/egress-gw-probe-silent-12180.test.sh`: remove `apply-web-platform-infra.yml` and `test-infra-privileged-tier-census.sh` from `EXPECTED_REFERRERS`, after re-deriving the set from the worktree's own `git grep` output (the rehearsal says five files; the worktree decides); update the two comment blocks that say the set "shrinks again when #12270 removes the kept targets" and "#12270 lowers it again by the same rule" to the past tense; set `MIN_ASSERTIONS` to the printed total and confirm the delta equals exactly the referrer rows removed (each removed referrer drops one "RETIREMENT header names the referrer" row) - rehearsal: the probe test, unchanged otherwise, printed `FATAL: only 427 assertions ran (floor 429)` once `EXPECTED_REFERRERS` was cut to five files, i.e. 429 minus 2 = 427, exactly the two removed "RETIREMENT header names the referrer" rows. The `for site in ...` list of header tokens stays (the header still describes the procedure).
- 1.5 `scripts/followthroughs/egress-gw-probe-silent-12180.sh`: replace the single `#   STATUS after #12189:` comment line with a STATUS line that reflects #12270 (sites 1-7 done; sites 2 and 3 done by #12270; site 8 deferred to #12271; site 9 unchanged; site 10 as observed in Phase 0.1). It must stay a `#` line inside the `# RETIREMENT:` block (the test's sed range ends at the first non-comment line) and keep every token the test requires. No code line changes; `APPLY_FLOOR_EPOCH` byte-identical.
- 1.6 Unchanged by design, each proven by a run in Phase 3: `egress-gw-alert.test.sh`, `logs-alert-query-period-ceiling.test.sh`, `betterstack-send-failed-alert-mutation.test.sh`, `betterstack-logs-alerts.tf`, `infra-validation.yml`, `betterstack-log-query.md`.

### Phase 2 - Documents (second commit)

- 2.1 `knowledge-base/engineering/operations/runbooks/cron-egress-blocked.md`, section `### Egress gateway (Better Stack alerts)` (the heading stays; the egress guard pins its slug): after the `Canary retirement record (#12189)` paragraph append a dated `Update 2026-11-07 (#12270)` paragraph stating, from the Phase 0 reads: apply run 42369320061 destroyed both resources (`2 destroyed`), the two bare `-target` lines and the two census entries are gone, and the plan after the removal is a no-op for these addresses; the observed probe line; the observed answer to Unverified A (the vendor kept listing the incident after the alert was deleted, if the Phase 0.1 read still shows it) and the observed state of B (mirror issue #12242 and its incident, as read, not assumed). Add the pointer `[Update 2026-11-07 (#12270): the present-tense statements above that the two bare targets and census entries stay, and "do not start #12270 until ...", are superseded by the update paragraph below]` as ONE standalone new line (blank-line separated) directly after the retirement-record paragraph, never inside an existing hard-wrapped line (the runbook wraps its paragraphs, so a mid-line insertion would show as a `-`/`+` pair and break AC 7). The update paragraph states that it supersedes both bullets of `Unverified after the canary's deletion` (A and B) with what was observed. No original word is deleted or reworded. If B shows the incident still open, state it plainly as an owner item (resolving it is a Better Stack write needing the owner's per-command go-ahead) and do not do it.
- 2.2 `knowledge-base/engineering/architecture/decisions/ADR-218-native-better-stack-logs-alerts-are-terraform-managed-via-the-logtail-provider.md`: append `## Amendment 2026-11-07 (#12270, Ref #12189): the kept canary targets and census entries are removed; window closed` at the end of the file. Content: the destroy applied (run 42369320061, `2 destroyed`); the two `-target` lines and two `INTENDED_DESTROYS` entries are removed in one change; the removal plans 0 destroys and carries no `[ack-destroy]`; no alert, exploration or census count moves (stated, with the Terraform-managed count staying at 18); the probe and `APPLY_FLOOR_EPOCH` are unchanged; the structure suite's apply-parity check now reads an empty tolerance list; remaining open items by number only (#12271, the mirror issue #12242 and tracker #12189 closing through their own mechanisms). Put ONE standalone bracketed pointer line `[Amendment 2026-11-07 (#12270): the statements in the 2026-11-06 amendment that the two bare targets and census entries stay until #12270 are superseded by the amendment below]` at the end of the 2026-11-06 amendment's last paragraph as its own new line (blank-line separated), never inside an existing line. No original word is deleted or reworded. This is an amendment to an existing ADR, not a new ADR: no ordinal is claimed.

### Phase 3 - Verification (local; read-only except the worktree edits)

Because `--affected` does not select `apps/web-platform/test/infra/*.test.sh` (learnings above), every suite is run by name and the affected runner is run in addition.

- 3.1 Run, in the worktree, each of: the structure suite, the ceiling suite, the egress-gw-alert suite (full run, not `MUT_SKIP=1`), the send-failed mutation suite, the probe test, the census (`tests/scripts/test-infra-privileged-tier-census.sh`), `apps/web-platform/infra/luks-monitor-install.test.sh`, `plugins/soleur/test/worktree-manager-bare-sync.test.sh`, `plugins/soleur/test/terraform-target-parity.test.ts` (via the repo's runner), `tests/scripts/test-destroy-guard-counter-web-platform.sh`, `tests/scripts/test-destroy-guard-regex-parity.sh`, `plugins/soleur/test/c4-count-parity.test.sh`, `scripts/test-affected-kb-consumers.test.sh` and every per-alert guard under `apps/web-platform/test/infra/*alert*.test.sh` (derive the list: `git ls-files 'apps/web-platform/test/infra/*alert*.test.sh'` and `git grep -l logtail_exploration -- tests scripts apps/web-platform/test apps/web-platform/infra plugins`). Expected, to be confirmed by the printed output and compared with the baseline table: structure 110, ceiling 116, egress 128, send-failed 39, census 422 (all unchanged); probe 427 (429 minus the two removed referrer rows; the pin is set to the printed number). Any number that differs from its expectation is investigated, never edited to fit.
- 3.2 `bash plugins/soleur/scripts/affected-tests.sh --explain` then the affected run for the branch, `bash scripts/pre-push-ratchet-lane.sh` (the cheap local net), and the full-tree gate the repo's `test` context runs where the local machine can bear it; whatever cannot run locally is named in the PR body as left to CI, never claimed.
- 3.3 Real-tree scratch mutants for the Guard Contract matrix, each in a scratch copy under the session scratchpad (never the worktree), results (RED or GREEN as predicted, with the failing fragment) recorded in the PR body: the subset that exercises what this change moves: Guard 1 rows 1, 3, 4 (record the measured result) and 5, and Guard 2 rows 1, 3 and 5. The other rows are variations covered by the committed batteries (M-23b, M-29, M-g4-7, the probe test's own negative controls), re-confirmed by running those suites; the plan-time rehearsal already drove Guard 1 rows 1-3 RED (see Research Insights).
- 3.4 Locale check: if any `comm` or `join` was added or changed (none planned), pin `LC_ALL=C` immediately in front of it and run `plugins/soleur/test/worktree-manager-bare-sync.test.sh` (Test F7). Lints: `python3 scripts/lint-guard-contract.py <this plan>`, `python3 scripts/lint-infra-no-human-steps.py` on each changed `.md`, markdown lint on the changed docs.
- 3.5 Sweep AC: `git grep -nE 'probe_silent_canary|probe-silent-canary' -- ':(top)' ':(top,exclude)knowledge-base/project'` lists only the expected survivors (AC 4).

### Phase 4 - Ship preparation (stops before merge)

- 4.1 Re-sync before the final push: `git fetch origin main`, merge `origin/main` into the branch (no stash; commit WIP first), re-run Phase 3.1 and re-derive the probe test's set and total on the merged tree (a sibling merge, in particular #12292 if it lands first, changes the textual neighbourhood and may add referrers or counts). The first push happens only after this.
- 4.2 No `[ack-destroy]` in any commit message (`git log origin/main..HEAD --format=%B | grep -c '\[ack-destroy\]'` must print 0).
- 4.3 Review (`soleur:review`), fix findings, compound, then `soleur:ship` up to CI green.
- 4.4 Open the PR. The first line of the PR body answers "does merging this alone mutate production?": the merge triggers the push apply (the workflow file and `apps/web-platform/infra/**` are in its `paths:`), which is expected to plan 0 destroys and change nothing; any destroy halts the apply (no ack line exists) and the work stops. The body carries `Ref #12189` and may carry `Closes #12270`; assert `gh pr view <N> --json closingIssuesReferences` lists only #12270; no closing keyword near #12189 or #12242 in the title, body or any commit message (including the squash body). The body records the Phase 3 numbers, the scratch mutant results and the T6 condition (the post-merge apply must plan 0 destroys; the postmerge check cites the `No changes` or `0 to destroy` line). The body declares no new filings; if it ever does, the net-issue-flow gate's override marker is `<!-- gate-override: net-issue-flow -->`.
- 4.5 Wait for CI green. Do not push again while the change waits in a merge queue.
- 4.6 STOP. Ask the owner for an explicit per-command go-ahead that names the merge. No merge, no auto-merge, no apply, no workflow dispatch.
- 4.7 Report exactly what is left for the owner and print the resume prompt. Left for after the owner's go-ahead (not this session): watch the push-triggered apply with a Monitor and cite its `No changes` / `0 to destroy` line (any destroy: stop, no ack); re-run the read-only probe; #12189 and #12242 close through their own mechanisms (if the vendor keeps the canary incident open, that is the owner item: a Better Stack resolve needs the owner's per-command go-ahead).

## Files to Edit

1. `.github/workflows/apply-web-platform-infra.yml`
2. `tests/scripts/test-infra-privileged-tier-census.sh`
3. `apps/web-platform/infra/betterstack-alert-structure.test.sh`
4. `scripts/followthroughs/egress-gw-probe-silent-12180.test.sh`
5. `scripts/followthroughs/egress-gw-probe-silent-12180.sh` (one comment line)
6. `knowledge-base/engineering/operations/runbooks/cron-egress-blocked.md`
7. `knowledge-base/engineering/architecture/decisions/ADR-218-native-better-stack-logs-alerts-are-terraform-managed-via-the-logtail-provider.md`

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-12270-remove-retired-canary-targets/tasks.md` (derived from this plan)
- `knowledge-base/project/specs/feat-one-shot-12270-remove-retired-canary-targets/decision-challenges.md` (written during planning)

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` was queried for each path in Files to Edit; no open code-review issue names these files. (Open PR #12292 overlaps on `apply-web-platform-infra.yml`, the structure suite, ADR-218 and the runbook; that is a PR collision, recorded above, not a code-review issue, and it is acknowledged, not folded in.)

## Guard Contract

### Guard 1 - Window closure: no bare retired target, no census tolerance for one

**Property.** After this change no bare `-target` line in the apply allowlist names an address that has neither configuration nor state, and the census tolerance dict names none, so a re-added retired line is red and not silently honoured.

**Assembly.** The workflow's target lines and the census dict are two inputs read by distinct readers that do not share a chokepoint, so each is named: (a) the structure suite's apply-parity stray check (`logtail_targets_of` over the workflow, minus the awk/sed extraction of the census `INTENDED_DESTROYS` keys); (b) census G4c (a base-declared deletion is honoured only while its root still targets it bare), G4f (protected addresses) and G4g; (c) the ceiling suite's absence checks for the four #11631 targets and its census-dict extraction (positive controls M5c-M5e); (d) `luks-monitor-install.test.sh`'s absence check on the census dict. No single member list is the assembly: the stray check quantifies over every `-target=logtail_*` line, so a third or fourth leftover is as red as the first.

**Mutation matrix:**

| # | Mutation (scratch copy of the real post-change tree) | Expected |
|---|---|---|
| 1 | Re-add both canary target lines to the workflow, entries stay removed | RED in the structure suite stray check naming both addresses |
| 2 | Re-add only the exploration target line (one member short, after the compliant removal) | RED in the stray check naming that one address |
| 3 | Add a third bare `-target=logtail_exploration.zz_retired_x` for an undeclared address (a second stray after the compliant state) | RED in the stray check |
| 4 | Re-add the two census entries only (targets stay removed) | per suite, measured at work time and recorded: census, structure suite, ceiling suite and `luks-monitor-install.test.sh` GREEN (a stale entry is tolerated by design: G4c only checks base-declared deletions, the structure suite uses the list only as an exemption, the ceiling suite checks only the four #11631 rows); the probe test RED (the census rejoins the derived referrer set, six files against five expected, and the total moves) |
| 5 | Own dispatch: make the census extraction return nothing while two targets are re-added | RED (an empty extraction leaves the targets as strays; never a vacuous green) |

**Harness rows:**

- A suite edit that must go red: change the structure suite's `logtail_targets_of` regex so it no longer matches `logtail_exploration_alert.` addresses; the pristine tree then goes red through the untargeted-resource check (`_untg`), which shows the extraction is load-bearing (scratch only; the committed suite is re-run and must stay 110/110).
- A must-PASS input that is not the canonical: reorder the four ghcr census entries, or change a value string; the structure suite, the census and the ceiling suite stay GREEN.
- A scorer control: the existing wrong-fragment row of the structure suite must still grade a wrong-reason red as WRONG.

**Anchor.** The census dict and the workflow are both edited by this diff, so the guards prove consistency, not integrity. What lies outside the commit: the merge-base declaration read by census G4c, the apply's own structured destroy count (0 expected, any destroy halts with no ack present), and the apply log line cited by the postmerge check.

### Guard 2 - The probe test's derived referrer set and exact assertion total

**Property.** The set of files that still name the canary (outside plan history and the probe) equals the explicit `EXPECTED_REFERRERS` set, each referrer is named in the probe's RETIREMENT header, and `MIN_ASSERTIONS` equals the number of assertions that actually run.

**Assembly.** One derivation, `git -C "$HERE" grep -lE 'silent_canary|probe-silent-canary'` with `:(top)` and two excludes; consumers: the per-referrer "RETIREMENT header names the referrer" loop, the set-equality row (sorted with `LC_ALL=C` on both sides), the header-token `for site` list, and the exact total (`-lt` and `-ne` arms of the floor). The set is compared whole, so one extra and one missing referrer both fail.

**Mutation matrix:**

| # | Mutation (scratch copy) | Expected |
|---|---|---|
| 1 | Add the canary token to a new tracked file outside the excludes | RED (the derived set grows past `EXPECTED_REFERRERS`) |
| 2 | Drop one expected referrer from `EXPECTED_REFERRERS` while its file still names the canary | RED (set mismatch row) |
| 3 | Re-add one deleted target line to the workflow | RED (the workflow re-joins the derived set) |
| 4 | Add a second extra referrer after the compliant first fix (two files) | RED (not only the first extra is checked) |
| 5 | Raise `MIN_ASSERTIONS` by 1, then lower it by 1 | FATAL both ways with two different fragments: raised hits the `-lt` arm (`only N assertions ran (floor N+1)`), lowered hits the `-ne` arm (`expected exactly`) |
| 6 | Own dispatch: remove the `git grep` population (run from a directory that is not a checkout) | the skip row passes by design, but the referrer loop then runs zero times and the total drops by about five, so the suite exits 1 via the exact pin (never "0 checked" and exit 0); in a checkout with an emptied population the explicit set is RED |

**Harness rows:**

- A suite edit that must go red: delete the set-equality `if`; the guard's own source-pin rows or the negative controls detect the missing row (re-run; total changes and `MIN_ASSERTIONS` FATALs).
- A must-PASS input that is not the canonical: reorder the lines of `EXPECTED_REFERRERS`; the sorted comparison keeps it GREEN.

**Anchor.** Both numbers are stored values in the file the diff edits, so the guard proves consistency. What lies outside: the printed total and referrer list recorded in the PR body with the command that produced them, the reviewer's re-run, and the required CI check on the merged tree after the Phase 4.1 re-sync.

## Acceptance Criteria

1. Every Phase 3.1 suite exits 0 on the worktree, with the printed counts recorded in the PR body next to the baseline table; structure 110, ceiling 116, egress 128, send-failed 39 and census 422 are unchanged unless a run shows otherwise and the reason is written down; the probe test prints its new total, which equals the baseline 429 minus exactly the number of removed referrer rows (rehearsal: 427, two fewer referrer rows), with `MIN_ASSERTIONS` set to that printed number.
2. `plugins/soleur/test/worktree-manager-bare-sync.test.sh` passes (census F7 included), run on the merged-with-`origin/main` tree.
3. `git diff origin/main...HEAD --stat` shows exactly the Files to Edit plus the plan file and the spec directory files (`tasks.md`, `decision-challenges.md`), and any archive move `soleur:ship` makes; `.github/workflows/apply-web-platform-infra.yml` shows only 2 deletions; no `.tf` file is touched.
4. `git grep -nE 'probe_silent_canary|probe-silent-canary' -- ':(top)' ':(top,exclude)knowledge-base/project'` lists only: the structure suite (historical comments), `egress-gw-alert.test.sh` (guard rows), `egress-gw-probe-silent-12180.sh` and its test (the probe's own literals and header), ADR-218, `cron-egress-blocked.md`, `betterstack-log-query.md`, and neither the apply workflow nor the census.
5. `APPLY_FLOOR_EPOCH=1793967363` is byte-identical (`git diff origin/main...HEAD -- scripts/followthroughs/egress-gw-probe-silent-12180.sh` shows only `#` comment lines changed).
6. `git log origin/main..HEAD --format=%B | grep -c '\[ack-destroy\]'` prints 0, and no run, local or CI, shows a destroy in the plan for this change; if any does, work stops and the finding is reported.
7. Dated records are appended to, never rewritten: `git diff origin/main...HEAD -- <runbook> <ADR-218>` shows only added lines (the two bracketed pointers are standalone inserted lines; `git diff` shows no `-` line in either file). ADR-218 gains exactly one new `## Amendment 2026-11-07 (#12270...` section at the end of the file.
8. Closing semantics: `gh pr view <N> --json closingIssuesReferences` lists only #12270; the title, body and every commit message contain no `Closes`/`Fixes`/`Resolves` next to #12189 or #12242; #12189 and #12242 are not touched by this session (no comment is required by the plan; any comment is a GitHub comment, not a Better Stack write).
9. No Better Stack write, no apply, no workflow dispatch, no merge, no auto-merge happened in the session; read-only probe runs are the only vendor calls.
10. The Guard Contract scratch mutants of Phase 3.3 were run on a scratch copy and their RED/GREEN results (including the measured Guard 1 row 4) are in the PR body; `python3 scripts/lint-guard-contract.py` on this plan passes.
11. The PR body's first line answers whether merging alone mutates production (the push apply runs, expected 0 destroys) and states the T6 condition for the postmerge check.
12. CI is green on the final merged tree after the last `origin/main` sync; the session then stops and asks the owner for the per-command merge go-ahead.

## Test Scenarios

- Given the post-change tree, when the structure suite runs, then apply parity reports every enumerated resource targeted and no stray `-target=logtail_*` line, with an empty census tolerance list.
- Given the two target lines are re-added to the workflow, when the structure suite runs, then it is RED naming both canary addresses (Guard 1 row 1).
- Given a third undeclared bare logtail target, when the structure suite runs, then it is RED (Guard 1 row 3).
- Given the post-change tree, when the census runs against the merge-base, then G4c, G4f and G4g are green and the total is unchanged.
- Given a new file names the canary, when the probe test runs, then the referrer-set row is RED (Guard 2 row 1).
- Given the post-merge apply, when it plans, then there are 0 destroys (postmerge, owner-authorized merge only).

## Non-Goals

- Editing, commenting on or rebasing PR #12292 or the three older PRs that touch the apply workflow (10928, 10678, 7390).
- Any `.tf` change, any resource-count pin change, any `APPLY_FLOOR_EPOCH` change, and the probe transport extraction (#12271).
- Closing #12189 or #12242 by hand, resolving the canary's vendor incident, or any Better Stack write.
- Running an apply, dispatching a workflow, merging, or enabling auto-merge.

## Dependencies & Risks

- **Risk: a sibling PR merges first and moves the neighbourhood.** #12292 edits the same workflow, suites and docs on a pre-retirement base. Mitigation: Phase 4.1 re-sync and re-derivation; whichever of the two merges second re-derives the shared counts; this change moves none of them.
- **Risk: the probe test's derived set differs in CI from the local reading** (the derivation uses `git grep`, which sees tracked files only). Mitigation: derive from the final tracked tree (`git grep` reads tracked files; a new untracked file is the real gap, so `git add` first); the ADR amendment and runbook update both keep naming the canary, which keeps those two in the set by design.
- **Risk: the mirror issue #12242 stays open** because the vendor keeps the incident open. Not a defect of this change; reported as an owner item with the exact action (a Better Stack resolve needs the owner's per-command go-ahead), never done in this session.
- **Risk: the local affected gate misses `apps/web-platform/test/infra/*.test.sh`.** Mitigation: the explicit suite list in Phase 3.1.
- **Risk: terraform version difference** (local 1.9.8 experiment vs CI 1.10.5). The unmatched-target behaviour is long-standing; the CI apply itself is the decisive check and halts closed on a destroy.

## References & Research

- Issue #12270; tracker #12189; mirror #12242; parent #12180; deferred #12271; collision PR #12292.
- Retirement plan: `knowledge-base/project/plans/archive/20261107-001506-2026-11-06-chore-retire-egress-gw-probe-silent-canary-plan.md`.
- Sibling sequence: PR #11653 then #11785 (`32b7ee7d78`, apply run 41306010098).
- Apply run 42369320061 (retirement merge) and `gh api` repository setting `squash_merge_commit_message` (not needed: no ack line).
- Runbook `knowledge-base/engineering/operations/runbooks/cron-egress-blocked.md` (section Egress gateway (Better Stack alerts)); ADR-218.

## Sharp Edges

- A bare `-target` on an address with no configuration and no state plans `No changes`; the removal cannot create a destroy. A destroy appearing in the post-merge plan means state still holds something this analysis missed: stop, do not add `[ack-destroy]`.
- `MIN_ASSERTIONS` is an exact pin: derive it from the printed total after the referrer set is final, and say in the commit message that it was derived from a deletion, not fitted to a baseline.
- The census dict extraction in the structure suite is an awk range over `INTENDED_DESTROYS = {` to the first `^}`; do not reformat that dict or add a closing brace at column 0 inside it.
- Keep every bracketed pointer a pure insertion; a hunk with a `-` line in a dated record breaks AC 7.
- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6; this one declares `none` with the sensitive-path scope-out line.
- Never print a credential: the read-only probe prints a projected status line only; the `doppler run` form is the one the runbook documents.
