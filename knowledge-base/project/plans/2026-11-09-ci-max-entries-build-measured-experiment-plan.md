---
title: "ci: measured experiment — max_entries_to_build 2→1 on the merge queue (lever E, epic #11556)"
date: 2026-11-09
slug: ci-max-entries-build-measured-experiment
branch: feat-one-shot-12269-max-entries-build
issue: 12269
type: chore
priority: p3-low
domain: engineering
lane: cross-domain
brand_survival_threshold: none
requires_cpo_signoff: false
---

## Enhancement Summary

**Deepened on:** 2026-11-09
**Sections enhanced:** Encryption Posture (full-schema form), Acceptance Criteria (pre/post-merge split + value-assertion ACs), probe spec (postdate check), rule-ID citations
**Review coverage:** `Reviewed-Coverage: sequential-fallback` — all skill/agent fan-outs executed inline in this process (no subagent roster on this harness): deepen-plan halt gates §4.6–4.13 run mechanically; plan-review lenses (overengineering / correctness / simplicity / devex) applied inline.

### Key Improvements
1. Encryption Posture block rewritten to the sibling plan's full-schema "no store/connection introduced" form (deepen-plan §4.10 halt-safe).
2. AC7/AC8 rewritten as per-surface value assertions (`grep` on live value) instead of token-diff greps — test-fixture literals would false-positive a `-G'max_entries_to_build'` diff scan.
3. AC split into `### Pre-merge (PR)` / `### Post-merge` and probe gained the tracker-window postdate check (sharp-edges: diff-scope ACs, sample-after-X).

### New Considerations Discovered
- The executed lever-1 evaluation (issue comment 6717099123) already recommends **decline at current traffic** on a 12h window — the plan therefore gates the flip on a ~28-day re-instrumented window rather than assuming it.
- A fourth live parity surface beyond the issue's named three exists: `.github/workflows/merge-queue-stall-check.yml:172` `MAX_ENTRIES_TO_BUILD` (S8-asserted mirror; flip narrows stall coverage to `position <= 1`).
- Sweeper exit vocabulary verified: exit 5 = ACTION REQUIRED (designed nag), exit 1 = every-sweep FAIL comment (banned spam shape) — the probe computes the verdict and uses 0/5/3 only.
- `follow-through` label verified to exist; `--status cancelled`/`--created`/`--event`/`--json` verified against `gh run list --help`.

### Gate Results (deepen-plan)
- §4.6 User-Brand Impact: PASS (section present, `none`, no sensitive-path match).
- §4.7 Observability: PASS (5 fields, `grep` allowlisted, literal `expected_output "1"`).
- §4.8 PAT-shaped variables: PASS (no hits).
- §4.9 UI wireframe: SKIP (no UI surface).
- §4.10 Encryption Posture: PASS (full schema, no store/connection).
- §4.11 Guard Contract: PASS (`lint-guard-contract.py` rc=0, 1 entry).
- §4.12 Scope Check: PASS (one unfenced section; all asks mapped; inferred rows justified).
- §4.13 Task Design: SKIP (no new autonomous-task surface — probe enrolls in the existing sweeper).
- §4.5 network-outage: SKIP (no connectivity-symptom content; no SSH-provisioned apply target).
- §4.55 downtime/cutover: SKIP (GitHub-side ruleset parameter applies in place; no serving-surface offline operation).

## Overview

Issue #12269 is a deferred lever from the congestion-relief plan (#12250, tracker #12089, epic #11556 lever E): evaluate whether lowering the merge queue's `max_entries_to_build` from 2 to 1 reduces hosted-runner demand enough to justify the serialized merge drain it causes. The issue prescribes a measured experiment, gated on the umbrella-consolidation soak data, with named instruments (`.github/workflows/wallclock-p90-watch.yml`, `scripts/ci-demand-census.sh`) and named parity surfaces (ruleset `.tf`, DR skeleton, README, Guard-2 suite T-mq-1) if the flip is taken.

## Research Insights

**Premise Validation (Phase 0.6).** Cited refs verified: issue #12269 is OPEN (labels `priority/p3-low`, `type/chore`, `domain/engineering`, `meta/machinery`); #12250 (umbrella consolidation) MERGED 2026-11-07T02:50:25Z; tracker #12089 CLOSED 2026-11-08 as COMPLETED with the post-merge census posted; epic #11556 OPEN; sibling #9729 OPEN (parallel live session in `.worktrees/feat-one-shot-9729-s4-evidence-rerun`, untouched per dispatch scope). The issue's Method step 1 — "re-evaluate AFTER the #12250 umbrella-consolidation soak data exists" — has already run: deruelle's lever-1 evaluation on #12269 (mirrored from #12089 comment 6717099123, window 2026-11-07T15:00Z → 11-08T03:00Z) measured **zero cancelled `merge_group` `ci.yml` builds in 12h** (22 completed: 22 success / 1 failure / 0 cancelled; 363 counted job-min/run; `test` merge_group p50 2926s ≈ 49 min/candidate) and recommended **decline the flip at current traffic** — the waste premise did not materialize and serialization works against the wallclock goal — while noting the 12h sample is one traffic regime, not a base rate, and any pursuit needs a longer re-instrumented window. The premise is therefore not stale-as-resolved but resolved-as-evidenced: the plan's shape is a **longer-window decision gate → decline-with-record (expected) OR flip-with-parity-work (contingent)**, not an unconditional flip. Mechanism vs ADR corpus: the knob is owned by ADR-270 (`max_entries_to_build = 2` recorded with "raise to 3 only after the canary shows contention is not binding"; `2026-11-04` runner-minute audit measures ~375 job-min/candidate pre-fold, ~363 post-fold); a dated addendum is the established ADR-270 pattern (the 2026-10-31 #11678 addendum). No rejected alternative is being revived — the ADR itself gates changes on measurement, and this plan IS the measurement path. Collision precheck: PR #12495 is this branch's own auto-created draft (not a foreign duplicate); foreign `test-all.sh` pid 2143658 belongs to the sibling #9729 worktree (out of scope, left alone).

**Property List (Phase 0.6b).** (P1) A durable, evidence-backed verdict on lever E — decline or flip — recorded where a future engineer looks (ADR-270 + the issue), not lost in a closed tracker. (P2) If the verdict is flip: all Guard-2 parity surfaces and the stall-probe mirror move together so the value change is `0 destroy` and revertible. (P3) A re-arm path for the deferred lever that does not depend on memory — the 12h decline is one traffic regime, and the evaluation itself asks for a longer window before a final verdict. **Cut List:** (a) the unconditional 2→1 flip — buys "halve speculative demand" which the post-soak measurement shows produces no waste at current traffic (0 cancelled builds); not cut outright but demoted to a conditional branch behind a decision gate, because the issue mandates a measured experiment rather than a presumed outcome and the evaluation requests a longer window; (b) a new dedicated monitor/dashboard for queue speculation — `wallclock-p90-watch.yml` already ratchets merge_group-surface p90 weekly and `ci-demand-census.sh` already measures per-event job demand; a new instrument buys no property an existing one lacks; (c) a perpetual exit-1 followthrough probe that pings until waste appears — the followthrough convention explicitly bans the "watch for upstream" spam shape (~30 comments/month), so the re-arm is a dated re-evaluation trigger instead.

**Value-Proposition Measurement (Phase 0.6c).** The issue's claimed saving is "~25-30 job slots at peak per concurrent candidate". Measured anchors (all in-repo): `knowledge-base/engineering/audits/2026-11-04-ci-runner-minute-accounting.md` — ~375 job-min per `merge_group` `ci.yml` run pre-fold; post-fold census on #12089 — 363 counted job-min/run, 29 dispatches/run, ≈25% of all-repo demand in the window. Counter-side measured: speculation costed **zero** discarded builds in the 12h window — every speculative build ran to conclusion and merged. The unmeasured remainder is whether a longer window (the evaluation's own caveat) shows a different regime — that is what Phase 1 of this plan measures.

**Relevant file paths (verified present on this branch).**
- `infra/github/ruleset-ci-required.tf:271-275` — `merge_queue { ... max_entries_to_build = 2 ... }` (all 7 params explicit; comment block at 249-270 explains each knob and names T-mq-1).
- `scripts/create-ci-required-ruleset.sh:117-120` — DR skeleton JSON mirror (`"max_entries_to_build": 2`).
- `infra/github/README.md` — params table row `max_entries_to_build | 2` + the "Guard 2 compares all three" contract (~lines 104-113).
- `tests/scripts/test-audit-ruleset-bypass.sh` — Guard 2 / T-mq-1: 7-param three-source parity + safety values (`max_entries_to_merge ∈ {1,3}` pin at ~L893-913, `merge_method == SQUASH`, `check_response_timeout_minutes > STALL_THRESHOLD_MINUTES` derived from the stall workflow, CodeQL-absent). Fixtures `_mq_write_queue_block` (~L1108) and `t_mq_param_parity_noncanonical_pass` (~L1177) carry self-consistent literal `= 2` — not live-derived.
- `.github/workflows/merge-queue-stall-check.yml:172` — `MAX_ENTRIES_TO_BUILD: '2'` env mirror (comment at 121-122, 169 names it a mirror of the `.tf`); the aging window is `position <= MAX_ENTRIES_TO_BUILD` (~L216-223), so a flip narrows probe coverage to position 1 — a real observability consequence, not just a string edit.
- `plugins/soleur/test/merge-queue-stall-check.test.sh` — S8 derives `TF_BUILD` from the live `.tf` (L48,136-140) and asserts env equality (L1449): auto-follows a flip, no fixture edit.
- `plugins/soleur/scripts/admin-merge-ready.test.sh:402` — `_mq_rule` fixture is a static synthetic ruleset literal (`max_entries_to_merge: 1` already diverges from live `3`); NOT parity-derived — no edit required.
- `.github/workflows/apply-github-infra.yml` — post-merge apply path for `infra/github/**` (value-only queue edits need no `[ack-destroy]`; the ack gates nested-block shrinks).
- `scripts/ci-demand-census.sh`, `scripts/watch-wallclock-p90-11774.sh`, `scripts/required-check-wallclock-bounds.tsv`, `.github/workflows/wallclock-p90-watch.yml` — the instruments of record; census covers ≤12h/window, non-overlapping windows sum; watch runs Fridays 09:07 UTC and rewrites its standing tracker.
- `knowledge-base/engineering/architecture/decisions/ADR-270-merge-queue-with-advisory-codeql-and-post-merge-alert-gate.md` — parameter authority; addendum pattern exists (2026-10-31 #11678, ~L1004); `max_entries_to_build` documented at ~L220, L462, L578, L902, L980.
- `knowledge-base/engineering/operations/runbooks/followthrough-convention.md` — directive shape (`<!-- soleur:followthrough script=… earliest=… secrets=… -->` at column 0, `follow-through` label, ban on perpetual ping probes), `.github/workflows/scheduled-followthrough-sweeper.yml` — `secrets=GH_TOKEN` is already wired (env L119-120).

**Institutional learnings applied.** `2026-10-31-verify-platform-semantics-before-scoping-a-knob-issue` (verify GitHub merge-queue semantics against docs/live behavior before scoping a knob change — done: grouped merging, `ALLGREEN`, queue-off state machine all read from Guard-2 + ADR-270, not assumed); `2026-06-30-github-merge-queue-adoption-wire-all-ruleset-producers` (every ruleset producer surface must move together — the parity set is enumerated, not implied); `2026-06-30-merge-queue-iac-provider-schema-probe-and-positional-rule-readers` (DR skeleton and positional readers must mirror the tf); `workflow-patterns/2026-10-07-merge-queue-silent-ejection-re-enqueue` (queue ejection semantics inform the serialization-hazard analysis); followthrough-convention L168 (no perpetual ping probes — dated trigger chosen instead); `2026-10-24-a-ruling-premise-and-my-own-brief-were-unverified-claims` (the decline recommendation is itself re-verified by this plan's longer window before being recorded as final).

**External research:** skipped (Phase 1.6) — strong local context; all instruments, guard mechanics, the parameter ADR, and a prior measurement exist in-repo. Community discovery (1.5) and functional-overlap (1.5b) spawns replaced by sequential inline assessment — no uncovered stacks (bash/HCL/GHA internal machinery) and no plausible community artifact for a repo-specific merge-queue parameter experiment. `Reviewed-Coverage: sequential-fallback` applies to all agent fan-outs in this run.

## Research Reconciliation — Spec vs. Codebase

| Issue / brief claim | Verified reality | Plan response |
|---|---|---|
| "Re-evaluate AFTER the #12250 umbrella-consolidation soak data exists" | Re-evaluation already ran (issue comment 6717099123, window 11-07T15:00Z→11-08T03:00Z): 0 cancelled `merge_group` `ci.yml` builds in 12h, recommendation "decline the flip at current traffic", caveat "one traffic regime, not a base rate" | Plan keeps the decision gate but re-instruments it on a ~28-day window per the evaluation's own caveat; verdict is produced by Phase 1, not presumed |
| "Lowering `max_entries_to_build` 2→1 halves queue-side speculative demand" | True arithmetically (2→1 concurrent candidate builds), but the *waste* it would halve measured at zero: every speculative build ran to conclusion and merged | The flip is demoted to a contingent branch (Phase 3B), gated on discarded-build evidence in the longer window |
| "The Guard-2 sanctioned pin covers `max_entries_to_merge ∈ {1,3}` only" | Verified at `tests/scripts/test-audit-ruleset-bypass.sh` ~L893-913: safety values pin `max_entries_to_merge ∈ {1,3}`, `merge_method == SQUASH`, `check_response_timeout_minutes > stall threshold`; `max_entries_to_build` is parity-only | Phase 2 adds `max_entries_to_build ∈ {1,2}` to the same safety block + a `T-mq-1.m14` mutation row, mirroring the #11678 {1,3} rationale (a value-only 1↔2 change then needs no guard edit) |
| "a `max_entries_to_build` change needs its own parity-guard work (ruleset + DR skeleton + README + T-mq-1)" | Verified: parity compares the `.tf` block, the DR skeleton in `scripts/create-ci-required-ruleset.sh`, and the README table across all 7 params; a FOURTH live surface exists the issue does not name — `.github/workflows/merge-queue-stall-check.yml:172` `MAX_ENTRIES_TO_BUILD` (S8-asserted mirror) | Files-to-Edit lists all four parity surfaces plus the stall-probe mirror; the coverage-narrowing consequence (`position <= 1`) is called out in the ADR addendum |
| "Rollback is trivial (value-only Terraform revert)" | Verified: `apply-github-infra.yml` auto-applies `infra/github/*.tf` on merge to main; a value-only queue edit is `0 destroy` (no `[ack-destroy]` needed — that gate covers nested-block shrinks) | Phase 4 records the revert recipe (same four surfaces + README/ADR, merge, auto-apply) |

## Problem Statement / Motivation

Epic #11556 targets cutting PR required-check wall-clock from ~1h to ≤20 min. Lever E (the queue-side demand knob) was deferred from the congestion-relief plan (#12250) by CTO ruling 2026-11-06 because its net sign was unmeasured: `max_entries_to_build = 2` runs up to two candidate builds concurrently (~363 counted job-min each post-fold), which is either wasted speculation when a build is discarded, or paid-for drain speed when it is not. The first post-soak measurement found the waste premise absent — but on a 12-hour window the evaluation itself declined to call a base rate. Left un-executed, the lever sits in limbo: nobody knows whether it is a live option or a dead one, and the next congestion episode re-asks the same question.

## Proposed Solution

A two-branch measured experiment honoring the issue's method exactly:

1. **Phase 1 — longer-window decision gate.** Re-run the evaluation's core queries over a ~28-day trailing window (the "longer window with discarded-build attribution" the prior evaluation requested): cancelled vs completed `merge_group` `ci.yml` runs, merges/day drain, merge_group share of repo job-minutes via `scripts/ci-demand-census.sh`, and `test` merge_group p50/p90 from the `wallclock-p90-watch` tracker table.
2. **Phase 2 — verdict-independent hardening + record (runs in both branches).** Add the `max_entries_to_build ∈ {1,2}` sanctioned pin to Guard-2 (`_mq_guard2`) with a `T-mq-1.m14` mutation row; write the dated ADR-270 addendum recording the verdict and evidence; ship the followthrough verdict probe `scripts/followthroughs/mq-lever-e-verdict-12269.sh`.
3. **Phase 3A — decline branch (expected).** Post the verdict comment on #12269; enroll the dated re-evaluation directive on the issue (probe exits `5` — ACTION REQUIRED — only if cancelled speculative builds have appeared by the re-eval date, else `0` and the tracker closes with the measured verdict).
4. **Phase 3B — flip branch (contingent).** Only if Phase 1 finds recurring discarded builds or a dominant merge_group demand share: move all four parity surfaces + the stall-probe env mirror to `1` in one diff; auto-apply on merge; enroll the post-flip soak probe (keep-vs-revert verdict after a ~21-day soak).
5. **Phase 4 — revert recipe** (recorded, used only under 3B if the soak verdict is revert): value-only revert of the same surfaces.

## Technical Considerations

- **Decision-gate criteria (ruled, assumed defaults — `decision-challenges.md` row T1).** FLIP iff, over the trailing ~28-day window: `cancelled merge_group ci.yml runs >= 2` (recurring discarded speculation — the direct waste signal) OR `merge_group ci.yml counted job-minutes >= 40%` of all-repo counted job-minutes (speculative demand dominating the spend; baseline measured ≈25%). Otherwise DECLINE. A `test` merge_group p50 materially above the ~49 min/candidate floor is evidence *against* the flip (serialization worsens drain) and never triggers it.
- **Serialization hazard (why the flip is gated).** At ~49 min per candidate build, `max_entries_to_build = 1` serializes drain: with `max_entries_to_merge = 3` grouped landings, a depth-2+ queue pays one extra candidate build per landing slot. The stall probe's aging window also narrows to `position <= 1` — deeper stalled entries lose coverage. Both are recorded in the ADR addendum under 3B.
- **`check_response_timeout_minutes` interplay.** The 120-min timeout bounds a candidate's check response, not queue dwell; serialized drain raises dwell but does not directly threaten the timeout unless depth grows past ~2 builds × ~49 min plus check tail. Recorded as a watched metric in the 3B soak probe (queue-depth evidence), not a gate.
- **Guard-2 mechanics (verified, not assumed).** `_mq_guard2` reads the seven-param tf/DR/README triple, then applies safety values. The `{1,2}` pin goes in the same `if` block as `max_entries_to_merge ∈ {1,3}` (~L901-905). Fixtures `_mq_write_queue_block` (~L1108) and `t_mq_param_parity_noncanonical_pass` (~L1177) are self-consistent (all three fixture sources agree internally) and stay GREEN at either live value — no edit needed; noted so nobody "fixes" them.
- **Followthrough probe semantics (verified against `scripts/sweep-followthroughs.sh` header).** exit 0 = PASS comment + auto-close; exit 1 = FAIL comment every sweep (spam — banned shape); exit 5 = ACTION REQUIRED, never closes (nags until the label is removed — the designed alarm); exit 2/3 = TRANSIENT. The probe therefore computes the verdict itself: waste/drain-bad → 5; premise-still-absent/keep → 0; any `gh` read failure → 3. `earliest=` silences it until the re-eval/soak date — no perpetual ping.
- **Directive timing.** The directive gate resolves `script=` under the main checkout — the probe must reach `main` before the directive is filed on #12269. Ordering: this PR merges the probe → work phase then adds the `follow-through` label + inline `<!-- soleur:followthrough … -->` directive at column 0 (outside any fence) on the issue body.
- **No `Closes #12269` in the PR body** under either branch — the issue is the tracker and must stay open until the followthrough resolves it. PR body uses `Ref #12269` (`wg-use-closes-n-in-pr-body-not-title-to` governs issues the PR resolves; this one deliberately does not resolve it).
- **Instrument limits.** `ci-demand-census.sh` covers ≤12h per call — a 28-day window means ~56 consecutive non-overlapping calls, so the gate instead uses it on a representative set of ≥4 non-overlapping 12h windows spread across the period (documented in the verdict comment), while the cheap `gh run list` counts cover the full window. The watch tracker already carries p50/p90 history.

## Implementation Phases

### Phase 1 — Longer-window decision gate (measurement only, no code change)

- `SINCE=$(date -u -d '-28 days' +%Y-%m-%dT%H:%M:%SZ)`; count discarded speculation:
  `gh run list --repo jikig-ai/soleur --event merge_group --workflow ci.yml --status cancelled --created ">=${SINCE%%T*}" --json databaseId,conclusion,createdAt --limit 400 | jq 'length'` — FLIP signal if `>= 2`.
- Drain + demand share: merge count via `gh pr list --repo jikig-ai/soleur --state merged --search "merged:>=${SINCE%%T*}" --json number --limit 500 | jq 'length'`; `bash scripts/ci-demand-census.sh --start <w0> --end <w1> --summary` over ≥4 spread 12h windows → `BY_WORKFLOW ci.yml merge_group` share of `TOTAL_JOB_MINUTES` — FLIP signal if `>= 40%`.
- `test` merge_group p50/p90: read the standing `ci-wallclock-p90` tracker body (the watch rewrites it) for the current merge_group-surface row — recorded as context, never a FLIP trigger.
- Record the raw numbers into `## Decision Gate Result` on this plan (or the session state) before branching.

### Phase 2 — Verdict-independent hardening + record

- `tests/scripts/test-audit-ruleset-bypass.sh`: add `max_entries_to_build ∈ {1,2}` to the `_mq_guard2` safety-values block (mirroring the `max_entries_to_merge` comment: the set is deliberately {1,2} so an unsanctioned raise still fails while a value-only 1↔2 experiment needs no guard edit); add mutation row `T-mq-1.m14` — `max_entries_to_build -> 4` in tf+DR+README (parity holds, unsanctioned value) → RED on the safety value; add a must-PASS row asserting `{1,2}` members pass (covers the reject-everything guard class).
- `infra/github/README.md`: extend the `max_entries_to_build` params-table note — "Sanctioned values per Guard 2: {1,2}; 2→1 deferred experiment on #12269 measured decline-at-current-traffic (see ADR-270 addendum)".
- `knowledge-base/engineering/architecture/decisions/ADR-270-…md`: append a dated addendum — verdict + the window's numbers + gate criteria + (3B only) the stall-probe coverage narrowing and serialization hazard, and the pointer that the live value is the `.tf`.
- `scripts/followthroughs/mq-lever-e-verdict-12269.sh` (+ `mq-lever-e-verdict-12269.test.sh`): reads the live `max_entries_to_build` from `infra/github/ruleset-ci-required.tf` (grep, same derivation as the S8 suite), then: **value==2 arm** — count `--status cancelled` `merge_group` `ci.yml` runs since `earliest − 28d` (env-derived window); `>=1` → exit 5 (waste appeared: re-evaluate the flip), `0` → exit 0 (premise still absent: tracker closes with verdict); **value==1 arm** — compare `test` merge_group p50 in the current watch tracker body vs the recorded before-window floor — the tracker's row carries a measurement window, so the probe must verify the row's window POSTDATES the flip merge and exit 3 (re-poll next sweep) rather than accept a pre-flip row as the after-sample; materially worse → exit 5 (revert warranted), else exit 0 (keep). Any `gh` failure → exit 3. Prints one `REEVAL key=value…` line for the tracker comment. Suite drives both arms on fixtures (no network — the sibling `.test.sh` pattern).

### Phase 3A — Decline branch (expected outcome)

- Comment the Phase-1 numbers + verdict on #12269 (decline-at-current-traffic confirmed on the longer window).
- Add the `follow-through` label + the directive `<!-- soleur:followthrough script=scripts/followthroughs/mq-lever-e-verdict-12269.sh earliest=2026-12-15T00:00:00Z secrets=GH_TOKEN -->` (assumed date — `decision-challenges.md` row T2; ~5 weeks out gives a different traffic regime) at column 0 in the issue body.
- No `.tf`/DR/README param change; the README note and ADR addendum from Phase 2 carry the record.

### Phase 3B — Flip branch (contingent on Phase 1 FLIP signal)

- `infra/github/ruleset-ci-required.tf`: `max_entries_to_build = 1`; update the comment block (value + measured-experiment provenance).
- `scripts/create-ci-required-ruleset.sh`: `"max_entries_to_build": 1`.
- `infra/github/README.md`: params-table value `1` + note (experiment outcome; revert recipe).
- `.github/workflows/merge-queue-stall-check.yml`: `MAX_ENTRIES_TO_BUILD: '1'` + the two mirror comments (~L121-122, ~L169) noting the narrowed aging window.
- Merge → `apply-github-infra.yml` auto-applies (no `[ack-destroy]`; value-only). First-merge_group canary: next queued entry builds normally; only one `merge_group` ci.yml run in flight at a time.
- Post-merge enrollment on #12269: `follow-through` label + directive with `earliest=<merge date + 21d>` (soak end; the probe's value==1 arm reads it as the soak-verdict date).

### Phase 4 — Revert recipe (3B only, executed only if the soak verdict is revert)

- One PR reverting the four 3B surface values `1` → `2` (tf, DR skeleton, README, stall env mirror) — identical file set, reverse direction; auto-apply on merge; ADR-270 addendum line recording the revert and its evidence.

## Files to Edit

- `tests/scripts/test-audit-ruleset-bypass.sh` — `{1,2}` safety pin in `_mq_guard2` (~L901-905) + `T-mq-1.m14` mutation row + a `{1,2}` must-PASS row. (Phase 2, both branches)
- `infra/github/README.md` — `max_entries_to_build` params-table note (sanctioned set + experiment pointer); value cell only under 3B. (Phase 2 + 3B)
- `knowledge-base/engineering/architecture/decisions/ADR-270-merge-queue-with-advisory-codeql-and-post-merge-alert-gate.md` — dated addendum (verdict, evidence, hazards, revert pointer). (Phase 2 + 3B/4)
- `infra/github/ruleset-ci-required.tf` — `max_entries_to_build` `2 → 1` + comment update. (3B only)
- `scripts/create-ci-required-ruleset.sh` — `"max_entries_to_build": 2 → 1`. (3B only)
- `.github/workflows/merge-queue-stall-check.yml` — `MAX_ENTRIES_TO_BUILD` `'2' → '1'` + mirror comments. (3B only)

## Files to Create

- `scripts/followthroughs/mq-lever-e-verdict-12269.sh` — verdict probe (dual-arm: waste re-check under value 2; drain keep/revert under value 1). (Phase 2)
- `scripts/followthroughs/mq-lever-e-verdict-12269.test.sh` — fixture suite for the probe's arm routing and exit codes. (Phase 2)

Explicitly NOT edited (checked, verified non-parity): `plugins/soleur/scripts/admin-merge-ready.test.sh:402` `_mq_rule` fixture (static synthetic literal — its `max_entries_to_merge: 1` already diverges from live `3`); `plugins/soleur/test/merge-queue-stall-check.test.sh` (S8 derives the mirror from the live `.tf`); `plugins/soleur/test/sync-pr-behind.test.sh:216` fixture (`=5`, unrelated synthetic); `knowledge-base/engineering/audits/2026-11-04-ci-runner-minute-accounting.md` (point-in-time audit).

## Open Code-Review Overlap

None. Queried 94 open `code-review` issues against every Files-to-Edit/Create path (two-stage `--json` + `jq --arg`). The only hits were generic `scripts/followthroughs/` mentions in unrelated probe issues (#11312, #10464, #10463, #10462, #8435) — none touch the merge-queue surface or this plan's files.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly — the surface is this repo's own merge queue. Worst realistic breakage under 3B: serialized merge drain lengthens contributor-facing merge latency (a workflow regression on our own repo, not a user-facing artifact); under 3A: a probe mis-verdict either loses a re-arm signal or files a spurious ACTION REQUIRED comment on an internal issue.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no user-data surface — the probe reads public-repo run metadata with `GH_TOKEN` (issues:write on the sweeper job), writes nothing outside the tracker comment.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** `none` and not `single-user incident` — unlike the sibling #12250 change (required-context renames could pend-forever → 100% merge blockage), a `max_entries_to_build` value change cannot pend a required check: every sanctioned value keeps the queue functional, Guard-2 enforces parity + the sanctioned set pre-merge, and revert is a value-only diff. No sensitive-path-regex path is touched (`infra/github/` is not `apps/*/infra/`; the stall workflow name matches no credential token in the regex).

## Observability

```yaml
liveness_signal:
  what: "weekly wallclock-p90 watch ratchet over required checks on both surfaces (pull_request + merge_group) + merge-queue-stall-check filings"
  cadence: "watch Fridays 09:07 UTC (.github/workflows/wallclock-p90-watch.yml); stall probe on its existing schedule"
  alert_target: "standing ci-wallclock-p90 tracker issue body rewrite + auto-filed SUSPECTED-stall issues"
  configured_in: ".github/workflows/wallclock-p90-watch.yml; .github/workflows/merge-queue-stall-check.yml"

error_reporting:
  destination: "GitHub issues — watch tracker rewrite + stall-check auto-filed issues + the follow-through verdict comment on #12269"
  fail_loud: "watch exits 1 on a p90 above bound x (1+margin) and names offenders; stall check files an issue on a >45min pending head entry; probe exit 5 comments ACTION REQUIRED every sweep until the label is removed"

failure_modes:
  - mode: "3B serialization regresses drain (enqueue→merge and merge_group p50 above the before-window floor)"
    detection: "wallclock-p90 watch merge_group-surface p90 breach + the value==1 arm of scripts/followthroughs/mq-lever-e-verdict-12269.sh at soak end"
    alert_route: "watch tracker + ACTION REQUIRED comment on #12269 → revert recipe (Phase 4)"
  - mode: "decline verdict falsified later (cancelled speculative builds appear under a new traffic regime)"
    detection: "value==2 arm of the verdict probe at the re-eval date counting --status cancelled merge_group ci.yml runs"
    alert_route: "ACTION REQUIRED comment on #12269 every sweep until the label is removed"
  - mode: "probe blind spot — stall coverage narrows to position<=1 under 3B"
    detection: "recorded limitation in the ADR addendum; deeper-entry stalls surface via checks_timed_out ejection comments and queue-jump runbook"
    alert_route: "merge-queue-stall-check issue + ADR-270 addendum note"

logs:
  where: "gh run list --event merge_group history + watch tracker body (rewritten weekly) + #12269 comments"
  retention: "GitHub Actions retention for run records; tracker/issue history is permanent"

discoverability_test:
  command: "grep -cE '^[[:space:]]+max_entries_to_build[[:space:]]+=' infra/github/ruleset-ci-required.tf"
  expected_output: "1"
```

## Encryption Posture

Detection fired via `infra/github/ruleset-ci-required.tf` (`.tf$` glob). The change edits a scalar `merge_queue` parameter on an existing GitHub ruleset resource (and only under the contingent 3B branch) — no persistent store is introduced and no new cross-component/network connection is created.

```yaml
at_rest:
  mechanism: "none — no persistent store is introduced (a merge_queue build-concurrency integer is configuration, not data)"
  evidence: "the diff edits a numeric parameter, doc text, a guard pin, and a probe script; no volume/db/bucket/queue/cache/log-sink resource is added"
  defends_against: "n/a — there is no stored data to defend"
  does_not_defend: "the queue/run metadata GitHub itself persists is outside this change and unchanged by it"
  disclosed_as: "not a data store — no docs/legal disclosure needed"
  live_verification: "terraform plan post-merge shows an in-place parameter update on the existing ruleset and nothing else"
in_transit:
  tls: "unchanged — same Terraform->GitHub-API provider channel and same GitHub Actions runners"
  cert_verification: "on (platform default — no new endpoint, credential, or connection is introduced)"
  does_not_defend: "check-run contents remain as exposed to repo collaborators as before"
  disclosed_as: "no new connection — nothing to disclose"
exception: ~
```

## Guard Contract

### Guard 1 — `max_entries_to_build` sanctioned pin in Guard-2 (`_mq_guard2`, `tests/scripts/test-audit-ruleset-bypass.sh`)

**Property.** A `max_entries_to_build` value outside `{1,2}` fails T-mq-1 even when all three parity sources agree, while `{1,2}` passes with parity intact — mirroring the `max_entries_to_merge ∈ {1,3}` pin so a value-only 1↔2 experiment never needs a guard edit.

**Assembly.** The single chokepoint is the safety-values block inside `_mq_guard2` (immediately after the three-source parity diff, alongside the existing `max_entries_to_merge`/`merge_method`/timeout checks) — every T-mq-1 evaluation, live (`t_mq_param_parity_real`) or fixtured (`_mq_mutation`, `_mq_off_row`, `t_mq_param_parity_noncanonical_pass`), flows through `_mq_guard2`. The pin reads the already-parsed `tf_p` param list (parity upstream guarantees DR and README agree before safety values are evaluated, so one read covers all three sources).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `max_entries_to_build` → `4` in tf+DR+README (parity holds, unsanctioned value) — T-mq-1.m14 | RED on the safety value |
| 2 | `max_entries_to_build` → `0` in tf+DR+README (parity holds, would disable speculation entirely — an unsanctioned value the {1,2} set excludes) | RED on the safety value |
| 3 | The pin's `if` line deleted from `_mq_guard2` while a `=4` fixture is presented (guard's own dispatch: the check never fires) | RED — the m14 row exists precisely to catch this; without the pin the m14 fixture goes GREEN and the suite fails |
| 4 | Harness row: mutation battery sed pattern for m14 narrowed so only the tf literal is rewritten (DR+README keep `=2`) | RED on the upstream parity diff — proves the row's failure signature comes from the safety value only when parity genuinely holds |
| 5 | must-PASS, non-canonical: `max_entries_to_build = 1` in all three sources (the post-flip shape, parity holds) | GREEN — a pin that rejects everything reds this row |

**Anchor.** The sanctioned set is enforced against the live `.tf` parsed each run; the {1,2} literal lives in the same suite that contains the mutation rows exercising it — the suite's own m14/m0 rows are the outside-the-value check, and the set-identity property (exactly {1,2}, not `>=1`) is what rows 1-2 test.

## Architecture Decision (ADR/C4)

### ADR

Amend `ADR-270-merge-queue-with-advisory-codeql-and-post-merge-alert-gate.md` with a dated addendum (in-scope task, Phase 2): the lever-E verdict — gate criteria, the longer-window numbers, the {1,2} sanctioned pin, and (3B) the serialization/stall-coverage hazards plus the revert pointer; (3A) the decline-at-current-traffic record with the re-eval enrollment. New decision → recorded on the ADR that owns the parameter; no new ADR is created.

### C4 views

**No C4 impact**, verified by reading all three model files this session (`model.c4` — 1113 lines, element census + `plugin -> github` edge; `views.c4` — include lists; `spec.c4` — full). Enumeration: (a) external human actors — contributor/PR author, public issue reader, founder — all already modeled, none added; (b) external systems — `github` already modeled as the code-hosting/CI edge; no new vendor, webhook, or data store; (c) containers/data stores — none touched; (d) access relationships — none change. A merge-queue build-concurrency integer is below the model's abstraction (operational detail of the `plugin -> github` CI surface, same class as the #12250 verdict recorded in that plan's §C4).

### Sequencing

The addendum is authored in THIS change with the verdict it records — under 3A it is final on merge; under 3B it is written describing the experiment and updated by the Phase-4 revert line if the soak verdict is revert. Not deferred to a follow-up issue.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Re-evaluate AFTER the #12250 umbrella-consolidation soak data exists (single-moving-part attribution)." [issue #12269 Method 1] | Phase 1 decision gate | mapped |
| 2 | "Instruments of record: `.github/workflows/wallclock-p90-watch.yml` + `scripts/ci-demand-census.sh` (before/after windows on merge_group-surface job demand and queue dwell)." [issue #12269 Method 2] | Phase 1 measurement set; Phase 3B soak probe | mapped |
| 3 | "a `max_entries_to_build` change needs its own parity-guard work (ruleset + DR skeleton + README + T-mq-1)" [issue #12269 Method 3] | Files-to-Edit (four parity surfaces + stall mirror); Phase 2 guard pin; Phase 3B surface moves | mapped |
| 4 | "Rollback is trivial (value-only Terraform revert)." [issue #12269 Method 4] | Phase 4 revert recipe | mapped |
| 5 | "Lowering `merge_queue.max_entries_to_build` from 2 to 1 halves queue-side speculative demand … The net sign on both wallclock surfaces is unmeasured — this is a measured experiment, not a presumed win." [issue #12269 Hypothesis] | Two-branch design: gate decides decline (3A) vs flip (3B) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Phase 1 longer-window measurement | "re-instrumented on a longer window with discarded-build attribution" (issue comment 6717099123) + "Re-evaluate AFTER the #12250 umbrella-consolidation soak data exists" | asked |
| Phase 2 `{1,2}` Guard-2 pin + T-mq-1.m14 | "a `max_entries_to_build` change needs its own parity-guard work (ruleset + DR skeleton + README + T-mq-1)" | asked |
| Phase 2 ADR-270 addendum | — | inferred — justification: `wg-architecture-decision-is-a-plan-deliverable`; the verdict changes what the parameter-owning ADR records and must not lag the change |
| Phase 2/3 followthrough verdict probe + directive | — | inferred — justification: a soak-gated/re-eval closure without enrollment rots (ship Phase 5.5 gate class; followthrough-convention) — the evaluation's "at current traffic" qualifier needs a re-arm that is not memory |
| Phase 3A verdict comment + label on #12269 | "Ref #11556" (issue) + the tracker's standing-report convention | asked (tracker-comment convention) |
| Phase 3B stall-probe env mirror move | — | inferred — justification: S8 asserts `MAX_ENTRIES_TO_BUILD` equals the `.tf` value; unedited it fails post-flip — enforcement contract, not scope growth |
| Phase 4 revert recipe | "Rollback is trivial (value-only Terraform revert)" | asked |

### Split Assessment

- Subsystems touched: 3 — `infra/` (tf + README), `tests/` (Guard-2 suite), `scripts/` (probe); `knowledge-base/` artifacts excluded per convention
- Planned files: ≤8 | Estimated changed lines: ~220
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: Phase 1 gate executed and recorded — the ~28-day window's cancelled/completed `merge_group` `ci.yml` counts, merge count, census share over ≥4 spread 12h windows, and the verdict (FLIP or DECLINE) are written into the plan's `## Decision Gate Result` (or session state) and the #12269 verdict comment.
- [ ] AC2: `tests/scripts/test-audit-ruleset-bypass.sh` carries the `max_entries_to_build ∈ {1,2}` safety pin + `T-mq-1.m14` + the `{1,2}` must-PASS row; `bash tests/scripts/test-audit-ruleset-bypass.sh` is green including the new rows.
- [ ] AC3: `infra/github/README.md` names the {1,2} sanctioned set on the `max_entries_to_build` row; Guard-2 T-mq-1 stays green (parity holds on live sources).
- [ ] AC4: `scripts/followthroughs/mq-lever-e-verdict-12269.sh` exists, is executable, routes both value arms correctly in `mq-lever-e-verdict-12269.test.sh` (fixture-driven, no network), and maps verdicts to exit 0/5/3 exactly as specced.
- [ ] AC5: ADR-270 carries a dated addendum recording the gate criteria, the window's numbers, the verdict, and (3B) the serialization + stall-coverage hazards or (3A) the decline + re-eval enrollment.
- [ ] AC6: #12269 carries the verdict comment AND the `follow-through` label AND a column-0 unfenced `<!-- soleur:followthrough script=scripts/followthroughs/mq-lever-e-verdict-12269.sh earliest=<date> secrets=GH_TOKEN -->` directive — filed only after the probe reached `main` (3A: `earliest=2026-12-15T00:00:00Z`; 3B: `earliest=<merge>+21d`).
- [ ] AC7 (3B only): all four parity surfaces + the stall mirror read `1` post-merge — `grep -oE 'max_entries_to_build *= *[0-9]+' infra/github/ruleset-ci-required.tf` ends in `= 1`; `grep '"max_entries_to_build"' scripts/create-ci-required-ruleset.sh` shows `: 1`; the README value cell on the `max_entries_to_build` row is `` `1` ``; `grep 'MAX_ENTRIES_TO_BUILD' .github/workflows/merge-queue-stall-check.yml` shows `'1'` (merge-base diff scoped to these four files shows no OTHER numeric-value edit).
- [ ] AC8 (3A only): the live values are unchanged — the same four reads show `= 2` / `: 2` / `` `2` `` / `'2'` respectively (pin and docs only; test-suite fixtures are not live surfaces).
- [ ] AC9: PR body says `Ref #12269`, not `Closes` — the issue remains open as the tracker under both branches.
- [ ] AC10: `plugins/soleur/test/merge-queue-stall-check.test.sh` S8 green (env mirror equals the live `.tf` under whichever value ships).

### Post-merge (operator/agent after merge)

- [ ] AC11: the `follow-through` label + column-0 unfenced directive on #12269 are filed ONLY after `scripts/followthroughs/mq-lever-e-verdict-12269.sh` exists on `main` (the directive gate resolves `script=` under the main checkout); verify with `gh issue view 12269 --json labels,body`.
- [ ] AC12 (3B only): the post-merge `apply-github-infra.yml` run for this SHA applies clean (`gh run list --workflow apply-github-infra.yml --branch main --limit 3`), and the next queued `merge_group` entry builds normally with one candidate build in flight.

## Domain Review

**Domains relevant:** Engineering (home domain — see below)

### Engineering

**Status:** covered by prior ruling
**Assessment:** The Engineering assessment question fires (infrastructure-adjacent CI change, an ADR addendum), but the engineering rulings this plan needs already exist: the 2026-11-06 CTO ruling mandated exactly this measured experiment and named its guard/parity obligations, and the post-soak lever-1 evaluation (issue comment 6717099123) supplied the measurement methodology and initial verdict. Technical open points (gate thresholds, re-eval date, {1,2} pin) are recorded as `pending - assumed` rows in `knowledge-base/project/specs/feat-one-shot-12269-max-entries-build/decision-challenges.md` — subagent spawn unavailable in this harness (sequential-fallback).

All other domains assessed NONE semantically: Marketing (no content/brand surface), Product (no user-facing surface; mechanical UI-surface override scan of Files to Edit/Create found no `components/**`/`app/**` path → override does not fire, tier NONE), Legal (no legal docs, no regulated-data surface — Phase 2.7 GDPR gate: no schema/auth/API/`.sql` touch; none of the (a)-(d) extension triggers — the probe reads only public-repo run metadata), Sales, Support, Finance (runner-minute demand is engineering accounting owned by `ci-demand-census.sh` per ADR-276 D7, not budgeting/reporting), Operations (no vendor/procurement/provisioning — the `.tf` edit rides the existing apply workflow).

## Test Scenarios

- Given a 28-day window with `>= 2` cancelled `merge_group` `ci.yml` runs, when Phase 1 runs, then the verdict is FLIP and Phase 3B executes. (decision logic)
- Given a window with 0-1 cancelled runs and merge_group share < 40%, when Phase 1 runs, then the verdict is DECLINE and Phase 3A executes with no param edit. (decision logic)
- Given `max_entries_to_build = 4` written into all three parity sources, when T-mq-1 runs, then the suite fails RED on the safety value — not on parity. (guard mutation, m14)
- Given `max_entries_to_build = 1` in all three sources, when T-mq-1 runs, then parity + safety pass GREEN. (must-PASS)
- Given the probe runs against a live `.tf` at `2` with >= 1 cancelled run in the window, when the sweeper invokes it, then exit 5 → ACTION REQUIRED comment, issue stays open. (fixture)
- Given the probe runs at `2` with 0 cancelled runs, then exit 0 → PASS comment + tracker closes. (fixture)
- Given the probe runs at `1` with the tracker p50 materially above the before-window floor, then exit 5 (revert warranted). (fixture)
- Given any `gh` read failure in the probe, then exit 3 → TRANSIENT, tracker untouched. (fixture)
- Given a `gh` fixture run for `gh run list --event merge_group --status cancelled --created` returning the canned cancelled-run set, the cancelled count lands in the printed `REEVAL` line. (CLI-verification: `--status cancelled` is a documented `gh run list` filter — verified against `gh run list --help` in this repo's CI environment)

## Decision Gate Result

(Filled by the work phase — Phase 1 numbers land here before the branch is chosen.)

## Dependencies, Risks & Non-Goals

- **Depends on:** merged #12250 (soak baseline exists), the instruments of record (`wallclock-p90-watch.yml`, `ci-demand-census.sh`, the standing tracker), `apply-github-infra.yml` auto-apply, the sweeper's `secrets=GH_TOKEN` wiring (already present).
- **Risk — one-regime verdict repeats:** the 28-day window is longer, not infinite; mitigated by the re-eval enrollment rather than a final "never" verdict.
- **Risk — probe false-5 on API blips:** every `gh` failure is exit 3 TRANSIENT, never 0/5 — the probe cannot false-close or false-alarm on a read failure.
- **Risk — directive filed before the probe reaches main:** sequencing is explicit in Phase 2/3 (probe merges in this PR; label + directive applied after merge).
- **Non-goals:** changing `max_entries_to_merge`, `min_entries_to_merge*`, `grouping_strategy`, or `check_response_timeout_minutes` (all ruled 10-31/11-03); touching sibling #9729's stage-4 suite work; building any new dashboard/monitor; closing #12269 before its followthrough resolves.

## Deferred

- The actual 2→1 flip, if Phase 1 declines — deferred to the re-eval trigger on #12269 itself (not a new issue; the tracker IS the deferral).
- A dedicated merge-queue-dwell metric — the watch tracker + census already cover the surfaces; new instrumentation was cut in Phase 0.6b.
