---
title: "fix: web-2 LUKS evidence rule is immutability-based, a reboot is not required (#9372)"
type: fix
date: 2026-10-08
slug: web2-luks-evidence-immutability-not-reboot
branch: feat-one-shot-web2-luks-immutability-evidence
issue: 9372
closes: none
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# fix: web-2 LUKS evidence rule is immutability-based, a reboot is not required (#9372)

Plan detail level: MINIMAL (lead's brief). One small PR. The PR body says `Ref #9372` and `Ref #6931`, never `Closes`. **Amended 2026-10-08 on the owner's decision: the soak-marker writer (`w2l_judge`) is IN scope**, so the new evidence rule is the same in the #6931 grader and in the marker writer.

The owner decided on 2026-10-07 (verbatim): "Immutability is the principle I want to encode", and chose to amend the evidence criterion instead of rebooting web-2. Today two consumers of `scripts/lib/web2-luks-rows.sh` require a reboot: the #6931 grader (`scripts/followthroughs/web2-luks-live-6931.sh`, arm 4 requires the newest probe row's `boot_id` to differ from the readiness row's) and the marker-absent branch of `w2l_judge` (`RED reason=reboot_not_seen`), which the daily `web2_marker` job uses to earn `WORKSPACES_LUKS_CUTOVER_AT`. This change replaces both with the owner's rule through ONE lib helper, deletes the now-unused `w2l_reboot_seen` and the `reboot_not_seen` reason, records the rule and exactly what the marker gates in ADR-263, and corrects the two runbooks that state the reboot requirement. It states nothing about the volume being LUKS-backed, reborn or encrypted: that claim stays gated on the grader's PASS over real rows.

## Enhancement Summary

**Deepened on:** 2026-10-08 (lean pass, per the lead's MINIMAL brief; no multi-agent fan-out); **re-planned the same day** for the owner's decision to include the marker writer.
**Checks run:** User-Brand Impact halt (present, threshold `single-user incident`, now naming the weight coupling), Observability halt (section present), PAT-shaped variable halt (no hits), Guard Contract halt (`python3 scripts/lint-guard-contract.py` exit 0, two guards, assembly names the chokepoints rather than members), Scope Check halt (one unfenced section, all rows mapped), encryption-posture and IaC gates (no `.tf`, migration or cloud-init file touched: skipped), downtime gate (none: no serving surface changes).

### Key Improvements
1. The strict `luks_arm` predicate lives in ONE lib helper, `w2l_ready_arm`, and both consumers call it. I ran its jq against synthesized rows: with an older `formatted` and a newer `noop` readiness row it prints `noop` (newest wins), and it prints nothing for an empty or unparseable body (both consumers then fail closed).
2. Tree-wide grep (2026-10-08) of `w2l_judge`, `w2l_reboot_seen`, `reboot_not_seen`: the only consumers are the lib, the grader and its test, `workspaces-luks-verify.yml` (one call at line 1148, one reason in the not-live list at lines 1184-1186) and the verify suite. Nothing else calls `w2l_reboot_seen`, so it is deleted, with its test rows.
3. Measured baselines: grader suite 82 `[ok]` (floor 82); verify suite 329 passed against a stored floor of 325 (run, 57 s, rc 0); `EXPECTED_IDS` of the grader suite holds 44 ids against a label that already reads 46.
4. Every line citation was re-read from the files in this pass (listed in Research Insights).

### New Considerations Discovered
- The marker is not only a label: `lb-weight-gate.sh` lines 236-261 (B.6-B.10, ADR-143 D3 coupling #2) require it, aged at least 3 days, before a web-2 weight flip; after this change it can be earned without a reboot (see "What the marker gates").
- The scripts `web2-rebirth.sh` (line 363) and `web2-luks-rebirth.yml` (line 24, a comment) still print or say "nothing is claimed until the graded reboot proof". They are deleted by the cleanup PR (closing row 5) and their suite pins the string, so they are left stale and recorded as superseded in the addendum.
- The owner's `luks_arm` list (`formatted|opened`) is stricter than `w2l_ready_verdict` (`formatted|opened|noop`). `w2l_ready_verdict` is left alone because `web2-rebirth-ready-poll.sh` and `web2-rebirth.test.sh` line 314 depend on its behaviour for `noop`; the strict rule is the separate helper.

## Research Insights

**Premise validation (Phase 0.6).** `gh issue view` on 2026-10-08: #9372 OPEN, #6931 OPEN, #9750 OPEN (the broader skills/agents/gates work, out of scope). The files the brief names all exist on this branch: the grader, its test, `scripts/lib/web2-luks-rows.sh`, both runbooks and ADR-263 (798 lines, last section `## Addendum — 2026-10-07 (#9372, the reboot workflow)`). The mechanism (amend the criterion) does not sit in ADR-263's Alternatives table; ADR-263 only records the reboot proof as a decision made on 2026-10-05, which this addendum supersedes in part.

**Property list (Phase 0.6b).**

1. The #6931 grader PASSes only on the CURRENT instance's own graded rows: green readiness row from a fresh boot that opened the volume, green probe rows on at least 3 distinct days, no non-green probe row after the readiness row.
2. No reboot is required for a PASS or for earning the marker.
3. The grader and the marker writer apply the same readiness predicate, defined once.
4. The recorded decision (ADR) and the operator docs (runbooks) say the same thing as the code, including what the marker gates.

**Cut list.** (a) A new "instance identity" mechanism (server id in rows): cut, the per-instance readiness row already scopes the window (`w2l_soak_scan` counts only probe rows younger than the readiness row, and a replaced instance emits a newer readiness row that restarts the soak). (b) A tracking issue for the marker gap: cut, the gap is closed in this PR (owner decision 2026-10-08). (c) Changing `w2l_ready_verdict` to be strict: cut, it would ripple into `web2-rebirth-ready-poll.sh` and `web2-rebirth.test.sh` line 314 (a `noop` row is asserted to be refused as "not formatted"); a separate helper keeps the blast radius to the two consumers. (d) Editing the stale rebirth-workflow text (`web2-rebirth.sh` line 363, `web2-luks-rebirth.yml` line 24): cut, deleted by the cleanup PR. (e) Any change to the encryption-posture ledger, Article 30, `live_coverage_floor`, the `web-host-reboot` workflow/scripts, the #6931 directive: forbidden by the brief.

**Exact old behaviour (read in full 2026-10-08).**

- Grader `scripts/followthroughs/web2-luks-live-6931.sh`: header lines 19-21 describe arm 4; the helper source guard at lines 67-68 requires `w2l_reboot_seen`; the arm itself is lines 140-144: `if ! w2l_reboot_seen "$verdict" "$rverdict"; then unmet "no GREEN probe row carries a boot_id that differs from the readiness row's ..."`. `w2l_reboot_seen` (lib lines 263-268) is true only when both GREEN verdicts print a known `boot_id` and the two differ. Result: a green soak on the boot that formatted the volume reads `NOT YET` (and `FAIL` once the window `earliest + 4 d` closes).
- The grader takes the readiness verdict from `w2l_ready_verdict`, which accepts `luks_arm` in `formatted|opened|noop` (lib line 242). The owner's rule is `formatted|opened`, so `noop` (the provisioner re-ran on an already-open mapper, so nothing in this boot opened the volume) is not enough. The grader never sees `luks_arm` today because the GREEN verdict string does not carry it.
- Test file `scripts/followthroughs/web2-luks-live-6931.test.sh` (82 `[ok]` lines, `FLOOR=82` at line 365): T04, T04b, T04c, T04e (lines 145-152) pin `NOT YET` for unknown/equal boot ids; T04d (line 154) pins PASS when the newest probe row is on a new boot; arms `a_ready_unknown` and `a_no_reboot` (lines 315-316) and their replays `arm 2 a_no_reboot; arm 2 a_ready_unknown` (lines 328-329) encode the old rule; mutants at lines 344 ("the reboot proof is skipped") and 345 ("accepts an unknown READINESS boot_id", on the lib line) target it; `EXPECTED_IDS` at line 261 and the label at line 264.
- Marker writer, `w2l_judge` (lib lines 276-294): with the marker absent it requires a GREEN readiness verdict (`w2l_ready_verdict`, which accepts `noop`), then at lines 291-292 `if [[ "$marker" != present ]] && ! w2l_reboot_seen "$pv" "$rv"; then printf 'RED reason=reboot_not_seen\n'; return 0; fi`. The workflow `.github/workflows/workspaces-luks-verify.yml` treats that reason as NOT LIVE (a notice, exit 0, marker stays absent): lines 1184-1186 (two comment lines and `|| "$reason" == reboot_not_seen` in the condition). With the marker present the judge never looks at the readiness arm or the boot ids (the probe row alone keeps it).
- Verify suite `apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh`: scenarios S40 (line 1788), S53 (1846), S54 (1847) expect `not_live reboot_not_seen` (probe/readiness fixtures `p_unk`+`r_unk`, `p_ok`+`r_boot_a`, `p_ok`+`r_unk`); mutant row 22 (lines 2008-2009) deletes the `w2l_reboot_seen` line and expects S40 S53 S54 to redden; mutant rows 12, 13, 13b (lines 1986-1991) pin the not-live condition text including `reboot_not_seen`; fixture comments at lines 1617 and 1621 and the Guard 3 PROPERTY comment at lines 1325-1331 describe the reboot proof; `G3_EXPECTED_IDS` at line 1851 and the `-eq 58` / "(58 ids" assertion at line 1862; floor `WF_MIN_ASSERTIONS=325` at line 2250. S10 (line 1784, a probe on a different boot is GREEN) and mutant row 16 (line 1999, an unreadable `boot_id` must not crash the judge) stay valid.

**New predicate.** PASS requires all of: (1) newest readiness row GREEN and at least 72 h old (unchanged); (2) that row's `luks_arm` is `formatted` or `opened` (new, replaces arm 4); (3) GREEN probe rows in at least 3 distinct 24 h buckets counted from the readiness row, newest probe row GREEN and at most 26 h old (unchanged); (4) no non-green probe row at or after the readiness row (unchanged). `boot_id` is no longer graded by either consumer. The marker writer (marker absent) requires: GREEN readiness verdict, then `w2l_ready_arm` true (new, replaces `reboot_not_seen`), then probe not older than the readiness row (unchanged), then the newest probe row GREEN and fresh (unchanged); with the marker present the probe row alone keeps it, a newer readiness row is still a rebirth, and any RED deletes the marker (all unchanged). A reboot is neither required nor penalised: an unplanned reboot is covered by the existing red-row rule, because a probe row that fails to reopen the volume is a non-green row and spoils the soak.

**What the marker gates (lb-weight gate coupling #2), stated explicitly.** `WORKSPACES_LUKS_CUTOVER_AT` (Doppler `soleur/prd_workspaces_luks_marker`) is written only by the `web2_marker` job of `workspaces-luks-verify.yml`. `apps/web-platform/infra/lb-weight-gate.sh` lines 236-261 (B.6-B.10, ADR-143 D3 coupling #2) require it to be present, ISO-8601, not in the future and at least `WORKSPACES_LUKS_SOAK_DAYS` (default 3) old before a web-2 weight flip passes (consumed through `lb-weight-gate-with-marker.sh`, #9358); that is the fence that keeps a plaintext web-2 from being pooled, because the only way user data reaches web-2 is a flip. The check is shape-only (it does not verify provenance). **Loosening this PR makes:** before, the marker could be earned only after a probe row on a boot other than the readiness row's (a reboot); after, it is earned on the first `web2_marker` run where the newest readiness row is GREEN with `luks_arm` in `formatted|opened` and the newest probe row is GREEN, fresh and not older than the readiness row. The current web-2 (a GREEN readiness row and one OK probe row already exist) can therefore earn the marker on the first scheduled run after merge, with no reboot, and the gate's 3-day soak runs from that first-green timestamp. Unchanged: the judge keeps the first-green timestamp, deletes the marker on any RED, the marker-present path judges the probe row alone. Not claimed: the marker alone does not pool web-2 (Condition B also needs `GIT_DATA_STORE_ENABLED` and the git-data marker, and no flip orchestrator consumes the marker yet, #9358). The judge does not count distinct days; the three-day count is the grader's arm and the gate's soak age on the marker. Side effect to state in the runbook: once the marker is present the never-pooled gate of the `web-host-reboot` workflow refuses every web-2 reboot by design.

**Census check (the edit moves these, nothing else).**

| Census | Moves? | Action |
|---|---|---|
| `FLOOR` in the grader test (line 365) | yes | measure the new `[ok]` count (expected 85: -2 retired mutants, +2 new mutants, +T04f run+said, +T04g run) and set `FLOOR` to the measured value |
| `EXPECTED_IDS` (line 261) and the "(N ids)" label (line 264) | yes | add `T04f T04g`; the label at line 264 reads 46 while the list holds 44 today (measured 2026-10-08), so after the two additions list and label agree at 46 (confirm by running the suite) |
| `scripts/suite-shard-legs.tsv` (`scripts/web2-luks-live-6931 4`), `scripts/suite-durations.tsv` | no | no suite added or removed |
| `scripts/guard-vacuity-floor.test.sh` PROMOTED_FILES, `scripts/test-all.sh` registration (line 5265) | no | the suite is already registered; the file does not move |
| `plugins/soleur/test/fixture-relative-assert.baseline.txt` rows for the grader test (line 373, count 1) and the lib (line 388, count 1) | possibly | run `bash plugins/soleur/test/fixture-relative-assert.test.sh`; regenerate deliberately only if a row moved |
| `G3_EXPECTED_IDS` (line 1851) and the `-eq 58` / "(58 ids" assertion (line 1862) in the verify suite | yes | add `S59 S60`; 58 -> 60 in both places |
| `WF_MIN_ASSERTIONS=325` in the verify suite (line 2250; measured green today 329) | yes | expected green 332 (+S59, +S60, +mutant 22b; mutant 22 is replaced one for one); set the floor to the measured green count, which the comment above it demands ("EXACT") |
| Verify-suite mutant rows 12, 13, 13b, 22 | yes | rows 12/13/13b: drop `\|\| "$reason" == reboot_not_seen` from the pinned condition text; row 22 replaced (Phase 2b) |
| `scripts/test-all.sh`, shard legs, durations for the verify suite | no | no suite added or removed |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "append a dated addendum to ADR-263 (append-only, do not edit old bodies) recording the decision and the new evidence rule" | Phase 3, ADR-263 addendum | mapped |
| 2 | "change the #6931 grader scripts/followthroughs/web2-luks-live-6931.sh arm 4 ... to match, with its tests, keeping every other arm and the anti-vacuity floors" | Phase 1 (lib helper + grader) and Phase 2 (tests) | mapped |
| 3 | "update ... web2-luks-rebirth-9372.md and web-host-reboot.md where they state the reboot requirement" | Phase 3, both runbooks | mapped |
| 4 | "do NOT claim the volume is LUKS-backed/reborn/encrypted anywhere until the amended rule is actually met by graded rows" | Acceptance Criteria (added-lines grep) | mapped |
| 5 | "INCLUDE the soak-marker writer (w2l_judge ...) in this PR, so the new evidence rule is the same in the #6931 grader and in the marker writer" (owner decision, relayed 2026-10-08) | Phase 1 (judge) and Phase 2b (verify suite, workflow condition) | mapped |
| 6 | "State in the plan and the ADR-263 addendum exactly what the marker gates (lb-weight gate coupling #2) so the loosening is explicit" | Research Insights "What the marker gates" and Phase 3.1 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `w2l_ready_arm` helper in the lib, called by the grader and by `w2l_judge` | "luks_arm in formatted|opened" and "defined ONCE in the lib helper" | asked |
| Delete `w2l_reboot_seen` and the `reboot_not_seen` reason (lib, workflow condition, verify-suite rows) | "prefer deleting if nothing else uses it, and then remove its test rows too" | asked |
| Lib comment edits (header lines 33-37, above the deleted function) and verify-suite comment edits (lines 1325-1331, 1617, 1621) | "update ... where they state the reboot requirement" | asked (the comments state the reboot proof is required; leaving them would make them false) |
| Edit the `web-host-reboot.md` "marker consequence" paragraph | "update ... web-host-reboot.md where they state the reboot requirement" | asked (it says the marker needs a probe row on a different boot) |

### Split Assessment

- Subsystems touched: 4 (`scripts/`, `.github/workflows/`, `apps/web-platform/infra/` for the verify suite, `knowledge-base/`)
- Planned files: 8 edits | Estimated changed lines: about 250
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR, despite hitting the 4-root threshold: the grader and the marker writer share one lib predicate and must change atomically (a split would leave the two readers disagreeing about "green", the drift the shared lib exists to prevent), the workflow edit is a one-clause deletion of a dead reason, and the owner decided the scope on 2026-10-08.

## User-Brand Impact

- **If this lands broken, the user experiences:** a false green on the #6931 grader (for example an arm dropped without replacement) lets the later ledger/Article 30 change (step 7, a separate PR) say that user workspaces are on an encrypted volume when the evidence is incomplete; a false marker (the judge earning `WORKSPACES_LUKS_CUTOVER_AT` on a non-LUKS web-2) removes the fence in `lb-weight-gate.sh` that keeps a plaintext web-2 from being pooled, so user workspace data could land on an unencrypted volume; a false red only delays the claim and the flip.
- **If this leaks, the user's data is exposed via:** nothing leaks here (no credential, row text or secret is read or written); the exposure is a mis-stated encryption posture to customers and the DPO record, and user workspace data reaching an unencrypted web-2 volume if the marker were earned wrongly, both driven by a weakened gate.
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** the grader gates the encryption claim a customer relies on and the marker gates where user data may land, so one wrong PASS or one wrong marker is a brand-level incident, not an aggregate pattern; the owner's decision of 2026-10-07 is the sign-off on the rule itself, and `soleur:engineering:review:user-impact-reviewer` runs at review time against the diff.

CPO sign-off: carried from the owner decision of 2026-10-07 (the owner holds the product call here); no fresh CPO spawn in this lean run.

## Domain Review

**Domains relevant:** none beyond the owner-decided rule

No cross-domain implications in this diff: it is infrastructure/tooling plus documentation. The Legal and Compliance surfaces (encryption-posture ledger, Article 30, `live_coverage_floor`) are explicitly NOT touched and stay gated behind the grader's PASS in the separate step 7 PR.

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-263 by appending `## Addendum — 2026-10-08 (#9372, evidence rule: immutability, not reboot)` after the last section (line 796 onward). Append-only: no old body is edited (the old sentences at the "Live conversion" paragraph and the "What this change altered outside the workflow" paragraph are superseded by name inside the addendum).

### C4 views

No C4 impact. Checked against all three model files (`model.c4`, `views.c4`, `spec.c4`): no external human actor, external system, container, data store or actor-to-surface access relationship changes (the grader and the marker writer still read Better Stack with the same credentials through the same helper; the marker write path and its Doppler config are untouched). `model.c4` mentions `web2-luks-rows` only in edge prose that this change does not alter. Run `bash plugins/soleur/test/c4-count-parity.test.sh` as the cardinality check.

### Sequencing

The addendum states the rule as adopted now and the claim as pending: web-2 stays "provisioned, proof pending" until the grader reports PASS over real rows. ADR-263 stays `status: adopting`.

## Guard Contract

### Guard 1 — #6931 web-2 LUKS soak grader (arm 4 replaced)

**Property.** The grader exits 0 only when the CURRENT web-2 instance's newest readiness row is green with `luks_arm` in `formatted|opened`, at least 3 distinct 24 h buckets of green probe rows follow it, the newest probe row is green and fresh, and no non-green probe row follows it, and it never requires or depends on a `boot_id` difference.

**Assembly.** One chokepoint decides: the single exit-0 path at the end of `scripts/followthroughs/web2-luks-live-6931.sh`, reached only through the readiness verdict (`w2l_ready_verdict`), the new `luks_arm` check (`w2l_ready_arm`), the red-row check and distinct-day count (`w2l_soak_scan`), and the newest-probe verdict (`w2l_probe_verdict`); all four are read through `scripts/lib/web2-luks-rows.sh`, whose queries are the hot-plus-archive union (`remote(...) UNION ALL s3Cluster(...)`), so cold-tier rows count the same as hot ones. The same lib also feeds `w2l_judge` (Guard 2), and both call `w2l_ready_arm`, so the readiness predicate has one definition. Test side: the registered scenario ids, the `run_arms_quiet` replay, and the mutant list in `web2-luks-live-6931.test.sh`.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Restore the old arm 4 (re-add `if ! w2l_reboot_seen "$verdict" "$rverdict"; then unmet ...`) | RED: T04b and the replay arm `a_no_reboot` expect exit 0 and now get exit 2 |
| 2 | Skip the new check (`if false; then` in place of `if ! rarm="$(w2l_ready_arm ...)"; then`) | RED: T04f (`noop` readiness) and replay arm `a_noop` expect exit 2 and now get exit 0 |
| 3 | Dispatch: make `w2l_ready_arm` print nothing and return 1, or return a constant `formatted` | RED: nothing-printed turns every PASS arm into NOT YET (T01, T03, T04g, replay `a_pass`); constant `formatted` is caught by T04f |
| 4 | Second member after a compliant first: an older `formatted` readiness row with a NEWER `noop` row (T04f) | RED if the helper reads the oldest row instead of the newest (the grader would PASS) |
| 5 | Accept `noop` inside the helper (`[[ "$a" == formatted \|\| "$a" == opened \|\| "$a" == noop ]]`) | RED: T04f, replay arm `a_noop` (and verify-suite S59) |
| 6 | Zero out the soak (`SOAK_DAYS=0`), skip the red-row check, skip the distinct-days check (existing mutants, kept) | RED: the existing replay arms still catch them, proving this edit did not weaken any other arm |

**Harness rows.** (H1) Flip T04b's expectation back to `run 2 "NOT YET"` in the suite: the suite must go RED against the shipped grader. (H2) Delete the registered id `T04f` from the run but not from `EXPECTED_IDS`: the registered-set assertion must go RED. Must-PASS inputs that are not the canonical fixture: T04g (`luks_arm=opened` where the canonical default is `formatted`, which the contract permits), and T04b/T04c/T04e (probe rows on the readiness boot, an unknown newest boot, an unknown readiness boot: all PASS under the new rule).

**Anchor.** The stored values are the test file's `FLOOR` and `EXPECTED_IDS`; one diff can edit both the grader and its floor, so they prove consistency, not integrity. The external anchor is the review of this PR's diff against the ADR addendum text (the rule is written in two places that must agree), plus the replay's control run on the unmutated grader. Set identity (registered ids) accompanies the numeric floor, so a substitution that keeps the count still reds.

### Guard 2 — web-2 soak-marker writer (`w2l_judge`, reboot requirement replaced)

**Property.** `WORKSPACES_LUKS_CUTOVER_AT` is earned only when the CURRENT web-2 instance's newest readiness row is GREEN with `luks_arm` in `formatted|opened` and the newest probe row is GREEN, fresh and not older than that readiness row, is kept only while the probe row stays GREEN, is deleted on any RED, and never depends on a `boot_id` difference.

**Assembly.** One chokepoint decides: `w2l_judge` in `scripts/lib/web2-luks-rows.sh`, called from exactly one place, the `web2_marker` step of `.github/workflows/workspaces-luks-verify.yml` (line 1148), whose verdict word alone selects write, keep, delete, not-live or fault (the `case "$verdict"` that follows). The judge composes `w2l_probe_verdict`, `w2l_ready_verdict`, `w2l_ready_arm` (new, shared with the grader) and the age join, over the hot-plus-archive union in `w2l_sql_probe` / `w2l_sql_ready`. The not-live list in the workflow (`no_probe_row`, `no_ready_row`, `probe_predates_ready`) is the only place that downgrades a RED to a notice, and it no longer names `reboot_not_seen`. Test side: the 60 registered scenarios, the mutation rows against the lib and the extracted step body, and the pristine-baseline byte check.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Restore the old rule: after the age join, return `RED reason=reboot_not_seen` when the two GREEN verdicts carry the same `boot_id` (mutant 22, replaced) | RED: S40 and S53 expect `green marker_written` and now get `not_live` |
| 2 | Drop the arm check from the judge (delete the `w2l_ready_arm` line) | RED: S59 (`noop` readiness, marker absent) expects `red ready_luks_arm` and now gets `green marker_written` |
| 3 | Dispatch: make the judge skip the whole earn branch (the `else` that reads the readiness verdict) | RED: S06, S09, S16, S27 (existing rows, kept) |
| 4 | Accept `noop` inside the shared helper (mutant 22b) | RED: S59 |
| 5 | Second member after a compliant first: the not-live condition is widened back to name a removed reason, or a RED reason is added after `probe_predates_ready` | RED: mutants 12, 13, 13b still pin the exact condition and redden S17, S26, S27, S29, S33 |
| 6 | Existing rows 1-21 (stale, non-LUKS, escrow, instance join, keep without readiness, delete skipped, fault arms) | RED, unchanged: proves the edit did not weaken any other judge arm |

**Harness rows.** (H1) Flip S53's expectation back to `not_live reboot_not_seen` in the suite: the suite must go RED against the shipped lib. (H2) Skip scenario S59 from the run but leave it in `G3_EXPECTED_IDS`: the registered-set assertion (mutation row 21) must go RED. Must-PASS inputs that are not the canonical fixture: S60 (`luks_arm=opened`, canonical is `formatted`), S40/S53/S54 (unknown and equal `boot_id`s now earn the marker).

**Anchor.** Stored values: `G3_EXPECTED_IDS`, the `-eq 60` count and `WF_MIN_ASSERTIONS` live in the same file as the code they guard, so a diff can move both; the external anchor is review of this diff against the ADR addendum's statement of the rule and of what the marker gates, plus the pristine-baseline byte-identity check (the sandbox copies are compared after all mutation rows) and a green run of the unmutated battery before every mutant (the existing CONTROL scenario S01).

## Files to Edit

- `scripts/lib/web2-luks-rows.sh` — add `w2l_ready_arm`; make `w2l_judge` call it (marker-absent branch) and drop its `w2l_reboot_seen` line (291-292 with the comment on 291); delete `w2l_reboot_seen` (lines 258-268 with its comment); rewrite the two comments that say the reboot proof is required (header lines 33-37; the `w2l_judge` header comment lines 270-275 gains one line on the arm). Every other function is untouched.
- `scripts/followthroughs/web2-luks-live-6931.sh` — header lines 19-21 (arm 4), helper guard lines 67-68, arm lines 140-144.
- `scripts/followthroughs/web2-luks-live-6931.test.sh` — see Phase 2.
- `.github/workflows/workspaces-luks-verify.yml` — lines 1184-1186: delete the two comment lines about `reboot_not_seen` and `|| "$reason" == reboot_not_seen` from the not-live condition. No other line.
- `apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh` — see Phase 2b.
- `knowledge-base/engineering/architecture/decisions/ADR-263-guest-side-fresh-boot-luks-for-web-hosts.md` — append the addendum.
- `knowledge-base/engineering/operations/runbooks/web2-luks-rebirth-9372.md` — see Phase 3.
- `knowledge-base/engineering/operations/runbooks/web-host-reboot.md` — see Phase 3.

No files created except this plan and `knowledge-base/project/specs/feat-one-shot-web2-luks-immutability-evidence/tasks.md`. Not touched, by instruction: the encryption-posture ledger, Article 30, `live_coverage_floor`, `.github/workflows/web-host-reboot.yml` and `scripts/web-host-reboot*`, the #6931 directive, `web2-rebirth.sh` / `web2-luks-rebirth.yml` (stale text left for the cleanup PR), `w2l_ready_verdict`, the marker write path and its Doppler config.

## Open Code-Review Overlap

None. Checked 2026-10-08 with the two-stage `gh issue list --label code-review --state open --json ...` + `jq --arg path` query for every path under Files to Edit that is code or test (the lib, the grader and its test, `workspaces-luks-verify.yml`, the verify suite) and for `lb-weight-gate`: no open code-review issue names any of them.

## Implementation Phases

### Phase 1 — Lib helper, judge and grader

1.1 In `scripts/lib/web2-luks-rows.sh`, add directly after `w2l_ready_newest_age` (it reads the same row `w2l_ready_verdict` judges: newest well-formed row, `sort_by(.age) | .[0]`). The predicate is defined here and nowhere else:

```bash
# w2l_ready_arm <ready.jsonl> — "this instance's fresh boot opened the volume" (#9372, owner rule 2026-10-07), the ONE definition
# both consumers use (w2l_judge, marker absent; the #6931 follow-through). Prints luks_arm of the NEWEST readiness row (nothing when
# there is none or the body is unparseable); returns 0 only for formatted|opened. noop is NOT accepted: the provisioner found the
# mapper already open, so nothing in this boot opened the volume.
w2l_ready_arm() {
  local a
  _w2l_body_ok "$1" || return 1
  a="$(jq -r -s "${_W2L_JQ_DEFS}"'
    [ .[] | classify_ready ] | sort_by(.age) | (.[0] | select(.kind == "row") | .f.luks_arm // empty)' "$1" 2>/dev/null)" || a=""
  printf '%s\n' "$a"
  [[ "$a" == formatted || "$a" == opened ]]
}
```

1.2 `w2l_judge`: in the marker-absent branch, right after `ra` is read from the GREEN readiness verdict (line ~287), add `w2l_ready_arm "$2" >/dev/null || { printf 'RED reason=ready_luks_arm\n'; return 0; }`; delete the comment and the `w2l_reboot_seen` line at 291-292. The marker-present path is unchanged (the probe row alone keeps the marker). Delete `w2l_reboot_seen` (lines 258-268) and its comment. Rewrite the header comment lines 33-37 to say `boot_id` is printed and ignored by every judge, and add one line to the `w2l_judge` header comment naming the arm check.

1.3 Grader: header arm 4 becomes "the readiness row's `luks_arm` is `formatted` or `opened` (this instance's fresh boot opened the volume); a reboot is NOT required (ADR-263 addendum 2026-10-08)"; in the `declare -F` guard replace `w2l_reboot_seen` with `w2l_ready_arm`; replace lines 140-144 with:

```bash
# The fresh-boot proof (ADR-263 addendum 2026-10-08): this instance's own readiness row says its first boot opened the volume.
# `noop` does not evidence that (see w2l_ready_arm). No reboot is needed.
if ! rarm="$(w2l_ready_arm "$tmp/ready.jsonl")"; then
  unmet "the readiness row reports luks_arm=${rarm:-unknown}, not formatted or opened: this instance's fresh boot is not evidenced to have opened the volume."
fi
```

Keep the PASS line and every other arm byte-identical. The comment lines must contain no `doppler|curl|WORKSPACES_LUKS_CUTOVER_AT|W2L_MARKER` token and no `JSONExtract` (T36/T37 scan the comment-stripped code, but keep the whole file clean).

1.4 `.github/workflows/workspaces-luks-verify.yml` lines 1184-1186: delete the two `reboot_not_seen` comment lines and `|| "$reason" == reboot_not_seen` from the condition, leaving `if [[ "$state" == absent && ( "$reason" == no_probe_row || "$reason" == no_ready_row || "$reason" == probe_predates_ready ) ]]; then`. A new RED `ready_luks_arm` with the marker absent falls to the RED arm (exit 1, issue filed), the same treatment as the existing `ready_luks_arm` for `luks_arm=none` (S16).

### Phase 2 — Grader tests (`web2-luks-live-6931.test.sh`)

2.1 Flip T04, T04b, T04c, T04e (lines 145-152) from `run 2 "NOT YET"` to `run 0 PASS` and retitle: an unknown or equal `boot_id` does not matter. T04b is the headline: "every probe row carries the readiness row's boot_id (no reboot): three GREEN days PASS". T04d stays PASS. Rewrite the comment at lines 143-144.
2.2 Add T04f: an older readiness row `luks_arm=formatted` plus a NEWER row `luks_arm=noop` (two `rdy` lines, ages `5*D` and `4*D`), soak probes as in T01: `run 2 "NOT YET"` and `said ... 'luks_arm=noop'`. Add T04g: `rdy $((4 * D)) "luks_arm=opened"`: `run 0 PASS`.
2.3 Replay (`run_arms_quiet`): `arm 2 a_no_reboot; arm 2 a_ready_unknown` (lines 328-329) become `arm 0 ...`; add `a_noop` (`arm 2 a_noop` plus a `[[ "$out" == *"luks_arm=noop"* ]]` named-reason check, as line 319 does for the stale-newest reason). Update the comment at line 318.
2.4 Mutants: delete lines 344 and 345 (the grader no longer calls `w2l_reboot_seen`, which is deleted). Add "the luks_arm check is skipped" (probe: `if ! rarm="$(w2l_ready_arm "$tmp/ready.jsonl")"; then` to `if false; then`) and "noop is accepted" (lib: `[[ "$a" == formatted || "$a" == opened ]]` to `[[ "$a" == formatted || "$a" == opened || "$a" == noop ]]`). Each lands exactly once, parses, and reddens at least one replayed arm.
2.5 `EXPECTED_IDS` gains `T04f T04g` (44 -> 46, matching the existing "(46 ids)" label); set `FLOOR` to the measured `[ok]` count (expected 85).

### Phase 2b — Verify suite (`apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh`)

2b.1 Scenarios that encode the old rule flip to GREEN (all three are `scn <id> <probe> <ready> none ...`):

| Scenario (line) | Fixtures | Old expectation | New expectation |
|---|---|---|---|
| S40 (1788) | `p_unk` + `r_unk` | `0 0 0 none not_live reboot_not_seen` | `0 1 0 iso green marker_written`; rename `...-is-GREEN` |
| S53 (1846) | `p_ok` + `r_boot_a` (same boot) | `0 0 0 none not_live reboot_not_seen` | `0 1 0 iso green marker_written`; rename `...-is-GREEN` |
| S54 (1847) | `p_ok` + `r_unk` | `0 0 0 none not_live reboot_not_seen` | `0 1 0 iso green marker_written`; rename `...-is-GREEN` |

S10 (1784) stays; S01-S03, S13, S31, S32, S41, S47 stay GREEN (their readiness fixtures carry `luks_arm=formatted`).
2b.2 Add fixtures `r_noop` (`g3_ready 259200 1 ok $G3_UUID_A 1 noop`) and `r_opened` (`... 1 opened`) beside `r_armnone` (line 1622), and scenarios S59 (`p_ok r_noop none 1 0 0 none red ready_luks_arm`, a RED with the marker absent, like S16) and S60 (`p_ok r_opened none 0 1 0 iso green marker_written`, the must-PASS row). `G3_EXPECTED_IDS` (line 1851) gains `S59 S60`; line 1862 `58` -> `60` in both the count and the label.
2b.3 Mutation rows: replace row 22 (lines 2008-2009) with "22 the old reboot requirement is restored (equal boot ids refused)" on `$LIB`, ids `S40 S53`: insert, after the `probe_predates_ready` line of `w2l_judge`, a return of `RED reason=reboot_not_seen` when `${pv%% age_s=*}` equals `${rv%% age_s=*}` and the marker is absent. Add "22b noop accepted by the shared arm helper" on `$LIB`, id `S59` (same edit as the grader's mutant). Rows 12, 13 and 13b (lines 1986-1991): remove `|| "$reason" == reboot_not_seen` from every pinned condition string so each still lands exactly once against the edited workflow. Row 16 (line 1999, S40) stays and is now stronger: S40 is a GREEN-writing scenario.
2b.4 Comments: rewrite the Guard 3 PROPERTY comment (lines 1325-1331) to drop the reboot proof and state the arm rule; edit the fixture comments at lines 1617 (`r_ok`) and 1621 (`r_boot_a`).
2b.5 Set `WF_MIN_ASSERTIONS` (line 2250) to the measured green count (expected 332; measured 329 today against a stored 325) and add a history line (`#9372 immutability rule: S40/S53/S54 flipped, S59/S60 and mutation row 22b added`).

### Phase 3 — ADR addendum and runbooks

3.1 ADR-263: append `## Addendum — 2026-10-08 (#9372, evidence rule: immutability, not reboot)` after line 798. Content, in this order, each a short paragraph:

- **Decision.** The owner decided on 2026-10-07: "Immutability is the principle I want to encode"; the evidence criterion is amended and web-2 is not rebooted to satisfy it. Supersedes the reboot-proof requirement recorded in the "Live conversion" paragraph (the sentence ending "the soak-marker judge and the follow-through both require it") and in "What this change altered outside the workflow" (2026-10-05 addendum): `w2l_reboot_seen` and the `reboot_not_seen` reason are removed.
- **The rule.** Evidence is the CURRENT instance's own: its readiness row is green (`luks=1`, `luks_arm` in `formatted|opened`, `escrow=ok`) and its fresh boot opened the volume; probe rows are green (`device_type=crypto_LUKS`, `mount_source=/dev/mapper/workspaces`, escrow ok) on at least 3 distinct days on that instance; any non-green probe row after the readiness row spoils it; a reboot is not required. Instance identity is the per-instance readiness row (rows carry no server id): a replaced instance emits a newer readiness row and the soak restarts. `noop` is not accepted. The predicate is defined once, in `w2l_ready_arm`, and used by the grader and by `w2l_judge`.
- **What the marker gates (coupling #2).** The text of "What the marker gates" in this plan's Research Insights, condensed: `WORKSPACES_LUKS_CUTOVER_AT` is the fence in `lb-weight-gate.sh` (B.6-B.10) that keeps a plaintext web-2 from being pooled; after this addendum web-2 can earn it without a reboot, on the same readiness evidence the grader uses, with the gate's 3-day soak running from the first-green timestamp; the marker alone does not pool web-2; once present, the `web-host-reboot` never-pooled gate refuses web-2 reboots by design.
- **What is unchanged.** Every other judge and grader arm, the 72 h minimum, the 26 h freshness, the window rule, deletion of the marker on RED, the #6931 directive (`earliest` 2026-10-10T20:10:00Z). The `web-host-reboot` workflow is no longer part of the evidence path and is retired in the cleanup PR (closing row 5); `web2-rebirth.sh` and `web2-luks-rebirth.yml` still carry text saying nothing is claimed until a "graded reboot proof", which is superseded by this addendum and deleted by the same cleanup.
- **Status of the claim.** As of this addendum the rule is NOT yet met by graded rows: the current web-2 (server 169271252, created 2026-10-07T20:05:37Z) has a readiness row (boot dd08ac9d, `luks=1 luks_arm=opened escrow=ok`) and one OK probe row; web-2 remains "provisioned, proof pending" until the #6931 grader reports PASS. No statement here is evidence for the encryption-posture ledger, Article 30 or any customer-facing sentence.

3.2 `web2-luks-rebirth-9372.md`: (a) add a dated amendment block directly under the existing "Status correction, 2026-10-07" paragraph (do not rewrite it) giving the new rule in one paragraph and listing which statements below it supersedes; (b) rewrite the sentence at lines 142-144 ("the proof is a later luks-monitor probe row on a `boot_id` other than the readiness row's ... and required by the soak marker") to the new rule, keeping "web-2 is *provisioned, proof pending*"; (c) in the "The reboot and its evidence: a separate workflow" section add one sentence that a dispatch is no longer needed to satisfy the grader or the marker; (d) closing row 2 and row 6: replace "the graded reboot proof" with "the graded #6931 PASS" and replace "cannot pass before about 2026-10-18" with the earliest the new rule allows ("the #6931 directive's `earliest`, 2026-10-10T20:10:00Z, plus the three-bucket soak"). Do not alter row 5 or its deletion list.

3.3 `web-host-reboot.md`: add a dated amendment block under the Status line: a reboot is no longer required for the #6931 grade or the marker; the runbook stays accurate for the workflow's own mechanics until it is retired in the cleanup PR; do NOT dispatch it to satisfy either. Append "(superseded for the grade, see the amendment)" to the intro sentence saying the workflow "exists so the graded reboot evidence ... can be gathered". Rewrite "The marker consequence" (line 177) so it no longer says the marker needs a probe row on a different boot: the marker can be earned without a reboot, and once present the never-pooled gate refuses every reboot of web-2 by design.

### Phase 4 — Verify and ship hygiene

4.1 Run the Acceptance Criteria commands. 4.2 PR body: `Ref #9372`, `Ref #6931`; no `Closes`. No dispatch, no Doppler write, no token mint, no Terraform apply, no `git push` from the planning phase.

## Observability

The graded surfaces are the follow-through sweeper's run of the grader and the daily `web2_marker` job of `workspaces-luks-verify.yml`; this change alters one predicate inside each and adds no new emitter, queue or service.

```yaml
liveness_signal:
  what: the daily follow-through sweeper runs scripts/followthroughs/web2-luks-live-6931.sh and the tracker #6931 receives its verdict word (PASS, NOT YET, FAIL or CANNOT ESTABLISH)
  cadence: daily
  alert_target: the follow-through tracker issue #6931 (the sweeper comments on it; FAIL reopens or flags it)
  configured_in: .github/workflows/scheduled-followthrough-sweeper.yml
error_reporting:
  destination: the sweeper run log and the #6931 tracker comment; a Better Stack read fault prints NOT YET with the scrubbed class on stderr and never FAILs
  fail_loud: exit 1 with "FAIL:" (spoiled or window closed), exit 3 with "CANNOT ESTABLISH:" (credentials or helper missing), exit 78 under xtrace
failure_modes:
  - mode: the new luks_arm check reads an empty value (helper regression) so every run reads NOT YET
    detection: the registered must-PASS scenarios T01, T03, T04g and the replay arm a_pass go RED in CI; at runtime the window rule turns a permanent NOT YET into FAIL at earliest + 4 days
    alert_route: CI red on the PR; FAIL on tracker #6931
  - mode: the readiness row reports luks_arm=noop on the current instance
    detection: NOT YET naming luks_arm=noop on every sweep, FAIL when the window closes; the daily web2_marker run reports outcome red reason=ready_luks_arm and files its issue
    alert_route: tracker #6931 and the web2_marker issue/Sentry check-in in workspaces-luks-verify.yml
  - mode: the marker judge earns the marker on a wrong readiness row (predicate regression)
    detection: verify-suite scenarios S59/S60 and mutation row 22b in CI; at runtime the next RED probe row deletes the marker and the run goes red
    alert_route: CI red on the PR; the web2_marker issue
logs:
  where: the scheduled-followthrough-sweeper workflow run log
  retention: GitHub Actions default run-log retention
discoverability_test:
  command: bash scripts/followthroughs/web2-luks-live-6931.sh
  expected_output: PASS or NOT YET or FAIL or CANNOT ESTABLISH
  credentials_required: BETTERSTACK_QUERY_HOST, BETTERSTACK_QUERY_USERNAME and BETTERSTACK_QUERY_PASSWORD (read-only Better Stack Telemetry credentials) - the grade reads live rows and no unauthenticated probe reads the same rows
```

## Acceptance Criteria

- [ ] `bash scripts/followthroughs/web2-luks-live-6931.test.sh` prints `0 failed`, its `[ok]` count equals `FLOOR`, and the registered-id assertion passes with `T04f` and `T04g` present.
- [ ] `bash apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh` prints `0 failed`, its passed count is at least `WF_MIN_ASSERTIONS` (set to the measured green count), and the registered-scenario assertion reads 60 ids including `S59` and `S60`.
- [ ] No reboot rule is left in code: `git grep -n -E 'w2l_reboot_seen|reboot_not_seen' -- scripts apps .github ':!*.test.sh'` prints nothing (ADR bodies and plans are outside the pathspec: append-only history; the only test-file mention allowed is the restored-rule text inside verify-suite mutation row 22).
- [ ] The predicate is defined once: `git grep -n -E '"\$a" == formatted' -- scripts ':!*.test.sh'` prints exactly one line (in `w2l_ready_arm`), and both `scripts/followthroughs/web2-luks-live-6931.sh` and `w2l_judge` call `w2l_ready_arm`.
- [ ] Every other judge arm is unchanged: `git diff origin/main -U0 -- scripts/lib/web2-luks-rows.sh` shows only comment lines, the added `w2l_ready_arm`, the added arm-check line in `w2l_judge`, and the deleted `w2l_reboot_seen` function and `w2l_judge` reboot line.
- [ ] Regression suites pass unchanged: `bash scripts/web-host-reboot.test.sh`, `bash scripts/web2-rebirth.test.sh`, `bash apps/web-platform/infra/lb-weight-gate-with-marker.test.sh`, `bash plugins/soleur/test/fixture-relative-assert.test.sh` (baseline regenerated deliberately only if a row moved), `bash plugins/soleur/test/c4-count-parity.test.sh`.
- [ ] `python3 scripts/lint-guard-contract.py knowledge-base/project/plans/2026-10-08-fix-web2-luks-evidence-immutability-not-reboot-plan.md` exits 0.
- [ ] The PR changes only the eight Files to Edit (plus the plan, tasks and, if it moved, the fixture baseline): `git diff --name-only origin/main` is a subset of them.
- [ ] No claim of an encrypted or LUKS-backed volume was added: `git diff origin/main -U0 | grep '^+' | grep -v '^+++' | grep -i -E 'is LUKS-backed|now (on|LUKS)|is encrypted|reborn onto|has been reborn'` prints nothing.
- [ ] The ADR addendum is append-only and states what the marker gates: `git diff origin/main -- knowledge-base/engineering/architecture/decisions/ADR-263-*.md | grep '^-' | grep -v '^---'` prints nothing, and the added text names `WORKSPACES_LUKS_CUTOVER_AT`, `lb-weight-gate`, "coupling #2" and that web-2 can earn the marker without a reboot.
- [ ] Untouched by instruction: `git diff --name-only origin/main | grep -E 'web-host-reboot\.(yml|sh)|web-host-reboot-evidence|web2-rebirth|web2-luks-rebirth\.yml|encryption-posture|live_coverage_floor|article-30|compliance-posture'` prints nothing, and the diff of `.github/workflows/workspaces-luks-verify.yml` is exactly the removal at lines 1184-1186.
- [ ] No tracking issue is filed for the marker gap (the gap is closed here).
- [ ] PR body carries `Ref #9372` and `Ref #6931` and no `Closes`/`Fixes`/`Resolves`.

## Test Scenarios

- Given web-2's readiness row is 4 d old, `luks_arm=formatted`, and three daily GREEN probe rows all carry the readiness `boot_id` (no reboot), when the grader runs, then it exits 0 (`PASS`).
- Given the same with an unknown readiness `boot_id` or an unknown newest probe `boot_id`, then PASS (boot ids are not graded).
- Given the newest readiness row is `luks_arm=noop` (an older one was `formatted`), then exit 2 `NOT YET` naming `luks_arm=noop`, and `FAIL` once `earliest + 4 d` has passed.
- Given `luks_arm=opened`, then PASS.
- Given a non-green probe row after the readiness row (T14-T16), then `FAIL` at once, unchanged.
- Given 2 distinct days, a young readiness row, a stale newest probe row, a 503 on either read, then the existing `NOT YET` / `FAIL` outcomes are unchanged.
- Given the marker is absent, a GREEN `luks_arm=formatted` readiness row and a GREEN probe row on the SAME `boot_id` (or unknown ids), when `web2_marker` runs, then it writes the marker once (`green marker_written`; S53, S40, S54).
- Given the marker is absent and the readiness row is `luks_arm=noop`, then `red ready_luks_arm`, exit 1, nothing written (S59); `luks_arm=opened` writes it (S60).
- Given the marker is present, then the probe row alone keeps it, a `noop` or unknown-boot readiness row is irrelevant, and any RED deletes it (S02, S13, S31, S04 and siblings, unchanged).

## Sharp Edges

- The owner's rule says `luks_arm` in `formatted|opened`, while `w2l_ready_verdict` also accepts `noop`. The strict list is in `w2l_ready_arm` only; `w2l_ready_verdict` is deliberately not tightened because `web2-rebirth-ready-poll.sh` and `web2-rebirth.test.sh` line 314 depend on its `noop` behaviour. If the owner wants `noop` accepted, drop `w2l_ready_arm`, S59, T04f and mutants 22b/"noop accepted", and keep only the reboot removals.
- A fresh `web2_marker` run after merge may write the marker immediately for the current web-2; that is the intended loosening, and the PR description must say so in one sentence. The never-pooled gate of `web-host-reboot.yml` will then refuse web-2 reboots (by design); the cleanup PR retires that workflow.
- The `[ok]`/passed counts are stored floors in the same file as the code they guard; measure them by running the suites, never by arithmetic from this plan. The verify suite's stored floor (325) sits below its measured green count (329) today, so the "EXACT" comment above it is already out of date; set it to the measured count in this edit.
- A mutant whose old string no longer exists reds the suite ("the edit did not land exactly once"): that is why mutant lines 344-345 (grader suite) and rows 12/13/13b/22 (verify suite) are edited in the same change as the code they pin; copy every new mutant string from the final text.
- The addendum, runbook text and any commit message must keep the claim conditional ("when the grader reports PASS"); the first draft of any sentence containing "is LUKS-backed" is a defect (see the Acceptance Criteria grep).
- A plan whose `## User-Brand Impact` section is empty or a placeholder fails `deepen-plan` Phase 4.6; this one is filled.

## References

#9372, #6931, #9750 (out of scope). `knowledge-base/engineering/architecture/decisions/ADR-263-guest-side-fresh-boot-luks-for-web-hosts.md`; `knowledge-base/engineering/operations/runbooks/web2-luks-rebirth-9372.md`; `knowledge-base/engineering/operations/runbooks/web-host-reboot.md`; `scripts/followthroughs/web2-luks-live-6931.sh`; `scripts/followthroughs/web2-luks-live-6931.test.sh`; `scripts/lib/web2-luks-rows.sh`; `.github/workflows/workspaces-luks-verify.yml`; `apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh`; `apps/web-platform/infra/lb-weight-gate.sh` (lines 236-261).
