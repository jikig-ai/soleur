# Session State

## Plan Phase

- Plan file: /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-10321-10136-dormant-probe-ledger/knowledge-base/project/plans/2026-10-15-fix-dormant-probe-ledger-10321-10136-plan.md
- Status: complete

### Errors

- Agent fan-outs unavailable in the planning subagent (no Task/spawn tool): research, domain review, advisor consult and plan-review panel were done inline; deepen-plan halt-gates verified inline. Technical forks recorded `pending - assumed:` for the main-context CTO gate.
- `lint-infra-no-human-steps.py` flagged first draft; reworded, now clean.
- Sharp-edges pass was a targeted skim, not a full read.

### Decisions

- #10321: assumed standing Better Stack alert `registry_zot_log_credential_shape` for the credential-shape check (matches CTO 2026-10-14 ruling for sibling #7530); sweeper read-surface and scheduled-workflow alternatives cut.
- #10136 raw-key: verified inngest v1.45.1 `HandleSigningKey` accepts raw OR `signkey-prod-<sha256>`; plan hashes the bearer client-side in `list-runs.ts` — removes wire exposure with zero auth risk.
- Ledger scope: only the Inngest `connections[]` row's `does_not_defend` rewritten; `hcloud_volume.git_data`, `docs/legal/**`, CLO-ruling strings untouched.
- Dormant-probe audit at plan time: 7 trackers closed outside lookback — header corrections on #7455/#8978/#6407/#6459/#3950 probes, #6500 already honest, #8706 deleted per its own RETIREMENT instruction.
- Merge-mutation disclosed: `apply-web-platform-infra.yml` is push-triggered on `infra/**` — merging creates the alert pair; tier-cap refusal routes to #10321.

### Components Invoked

- `soleur:plan` (full pipeline, inline research), `soleur:deepen-plan` (halt gates inline, lint-guard-contract.py + lint-infra-no-human-steps.py green)
- cto_spawns=1 (batched, six technical rows, all ruled 2026-10-15; technical-ruling-gate PASS 8 rows)

## Work Phase (in progress)

- Phase 1 DONE: `list-runs.ts` hashes the bearer client-side (`hashSigningKey` replica; stricter-than-SDK fail-closed on non-hex/odd-length — measured: node:crypto update('hex') silently drops bad chars, hash.js tolerates them); new vitest `test/lib/inngest-list-runs-signing-key.test.ts` 4/4 green; mutation RED observed on raw-bearer revert.
- Phase 2 DONE: ledger `connections[5]` (Inngest) `does_not_defend` rewritten — 1-line diff; `lint-encryption-posture.py` PASS. `exception.*` verbatim, no other row touched.
- Phase 3 IN PROGRESS: `betterstack-logs-alerts.tf` — appended `registry_zot_log_credential_shape` local SQL + exploration + alert (value=0 higher_than, 300/900/1800, runbook URL local); fmt applied. `apply-web-platform-infra.yml` — both `-target=` lines added after `egress_gw_probe_fail` pair (lines 665-666). Mutation-test count bump 13→14 in `betterstack-send-failed-alert-mutation.test.sh` (line 271).
- REMAINING: runbook row in `betterstack-log-query.md` standing-alarms list (~line 29, append after last `logtail_exploration_alert` bullet); Phase 4 header notes on 4 dormant probes (8978/6407/6459/3950) + delete `luks-monitor-host-timer-8706.{sh,test.sh}` + ADR-184 (~line 321 enrollment paragraph) + ADR-218 dated amendments + `followthrough-convention.md` clause; then gates + commit + `soleur:review` + ship.
- DONE since last note: `registry-zot-credential-shape-alert.test.sh` written + GREEN 27/27 incl. 7 mutation rows (fixes applied: `\\\\\$2` bash escaping for bcrypt, `''))` vs `'')`, col floor 5); registered `run: bash` step in `infra-validation.yml` after registry-store-not-luks step + runbook `paths:` entry at ~line 236; runbook `registry-zot-credential-shape-10321.md` written (rotate-first, counts-only, 3 shapes).
- KEY: alert is the 14th managed Logs alert on current main (#10320 still open — becomes 15th if it lands first; sequencing note in PR body). Fixture digest verified vs vendored SDK: `signkey-prod-0123…cdef` → `signkey-prod-4884fdaa…c837`.
- DONE since: runbook row added to betterstack-log-query.md; #8706 suite deleted per its own RETIREMENT (files + run_suite line+comment in test-all.sh + tsv/.n rows); dated STATUS headers added to 4 dormant probes (8978/6407/6459/3950); audit re-verified (all 7 trackers CLOSED-COMPLETED).
- REMAINING: zot-7440 header "stays enrolled" correction; ADR-184 (~line 321) + ADR-218 dated amendments; followthrough-convention.md dormant-detector clause; gates (lint-shell-trace-credential-refusal on touched shells, lint-orphan-test-suites, check-adr-ordinals, markdownlint, lint-guard-contract, fixture baseline if flagged); commit+push; soleur:review; QA; compound; ship (PR #10371 draft exists; Closes #10321, Ref #10136).
- ALL PHASES DONE + committed 57d1e2af8e pushed. Gates green: encryption lint, adr-ordinals, orphan-suites, shell-trace-refusal (5 probes), lint-guard-contract (2 guards), markdownlint. New suite 27/27 + 7 mutation rows RED/GREEN verified.
- NEXT: soleur:review on branch diff origin/main...HEAD (PR #10371 draft); resolve findings; QA (no UI surface — test scenarios are unit/structural); compound; ship. PR body needs: first-line prod-mutation statement (merge auto-applies the alert pair via push-triggered apply — intended), Closes #10321, Ref #10136/#7455/#7530/#9139, Residuals block, Sequencing (#10320/#10352/#10356).
