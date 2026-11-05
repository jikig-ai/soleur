# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-11-05-feat-boundary-prefix-deferred-item-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
- No run_subagent capability in the planning subagent session: install-under-amendment vs accepted-gap recorded `pending - assumed: arm (b) accepted-gap`; plan Phase 0 makes the soleur:engineering:cto consult the blocking first implementation step.
- No plan-review/deepen-plan subagent fan-out possible; substituted inline (premise validation, sharp-edges catalogue pass, halt gates 4.6-4.13).
- `test-all.sh --print-selection` timed out at 90s locally (sibling worktree queue); command shape verified via --help.

### Decisions
- Third arm discovered (a'): `glob_decide` rejects `src=floor` durations before the 25% rate check — two disqualifiers; a `measured` ≤10s duration would make the verdict `always_on`, not `glob`. The 1222ms value is a generated `default-weight` placeholder.
- Assumed default = accepted-gap (48% selection ~2× the ruled 25% bar; floor duration blocks any verdict; argv-bearer-sweep same-class residual already documented).
- #10859 entry conditions verified: window OPEN/paused (fresh probe `units=115 p95=269s max=279s`, red merge_group 42084778935 `new-pair`, no bot PR — p95 over the 240s ceiling, another #12129 datapoint); rename-carry design UNMET/stale; jobs-API canary MET (run 39937846319, `failure` 110s).
- #10865 measurement to be posted during implementation (Phase 2), not planning.
- cto_spawns=1 (2026-11-05, technical-ruling gate, 2 rows in one spawn): Ruled arm (a') measured-verdict — expected `always_on` install (ALWAYS_ON_SUITES at test-affected-paths.sh:132; edge block :4165 stays; 25% constant NOT amended; >10s measured → baselined → accepted-gap docs); rename-carry entry condition dissolved as vacuous under strict zero (conditional on strict zero holding).

### Components Invoked
soleur:plan, soleur:deepen-plan (inline), collision-precheck.sh, ratchet-observation-window-10865.sh (read-only probe)

## Work Phase
- Status: complete (2026-11-05)
- Arm executed: (a') measured-verdict — suite-durations.tsv floor→measured 718 (CI merge_group medians 677/1057/718); glob-rate verdict `always_on` (over-25-percent); ALWAYS_ON_SUITES install; _MIN_ALWAYS_ON_DECLARED 111→112 + f1 pin; justifications row; 13 accept rows + 3 kb-consumers rows deleted (always_on exits gap accounting); edge block :4165 stays per AC 6.
- Rider repair: accept row for real-sdk-ask-probe-workflow.test.sh → approval/ops.ts (EXCLUDED mention) — un-pauses main red the window sits on.
- Verify: ratchet exit=0 live=0; always-on-ledger 14/0; fast-tier-budget 9/0; kb-consumers 31/0; selector emits always_on.
- Comments posted: #10448 resolution, #10865 probe verbatim, #10859 entry-condition status (rename-carry dissolved, canary met, window open), #12129 p95 datapoint.
- Untouched: ci.yml continue-on-error, required-checks.txt, ruleset-ci-required.tf, pr-fanout-ledger.txt, CI_PR_AFFECTED, activation lock — all zero-diff (flip stays held for budget owner).
- Incident: edited test-all.sh mid-flight under the background --print-selection run → byte-offset syntax error, rc=2; re-ran after edits landed (documented hazard, work SKILL §1172).
- Commits: 97206b0baf (duration promotion), 4b039c2332 (install+drain+repair), 03556feee8 (tasks tick); pushed, draft PR #12199.

## Review Phase
- Class: code (.sh diffs) → 8 core seats + structural-enumeration (guard-shaped) + test-design (edited anti-vacuity assertion) = 10 seats; semgrep→shellcheck substitute (bash-only); user-impact skipped (threshold none); design-risk no.
- Pre-checks: merge-tree rc=0 vs origin/main; mergeable=MERGEABLE/BEHIND; prepush-secret-scan CLEAN (8 scanned); collision-precheck exit=10 — foreign test-all.sh procs in sibling worktrees only (feat-one-shot-12013, feat-swe2-flash, feat-one-shot-12120), no duplicate-scope PR.
- PANEL_SHA=e22d57880403cad842d1c6e6627e3915b0b3329c. Seats spawned background parallel 2026-11-05.
- Review finding (performance-oracle P3): the work-time glob-rate receipt's rate columns are post-install (rows generated after the ALWAYS_ON edit landed in the tree) — annotated in glob-rate.marker; verdict rests on the PR5d readings per the CTO ruling.
- Review finding (security P2, FIXED): the ops.ts rider was first dispositioned as an accept row, but the suite's TABLE-STALE check makes the file's existence verdict-relevant — re-dispositioned as a delete-sensitive edge declaration (test-affected-paths.sh :789), accept row removed, matching all ~20 sibling classification-table rows.

## Compound Phase
- Learning authored: knowledge-base/project/learnings/2026-11-05-a-receipt-generated-after-the-install-measures-the-install.md (9 session errors, each with recovery+prevention).
- Deviation analyst: 3 plan deviations, all recorded — (a) glob-rate receipt is post-install basis (annotated; verdict rests on PR5d readings per ruling); (b) ops.ts rider re-dispositioned accept→delete-sensitive edge (security P2); (c) surgical suite-durations promotion instead of full regen (~40 unrelated floor promotions avoided; receipt documents why).
- Workflow proposal (not corpus-edited here — scoped PR): "evidence receipts for a selection-rate verdict must be generated before the install they evidence; a queued/background measurement reads the tree it lands on, not the tree it was launched against." Candidate for the activation runbook or drain rubric.
- Review tally: 10 seats, 1 P2 (fixed), ~10 P3 (all fixed or recorded advisories). Ratchet exit=0 live=0 on final HEAD. QA PASS 5/5.
