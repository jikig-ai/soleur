# Tasks — feat-one-shot-12269-max-entries-build

Plan: `knowledge-base/project/plans/2026-11-09-ci-max-entries-build-measured-experiment-plan.md`
Issue: #12269 (tracker — stays OPEN under both branches; the PR does NOT close it) | Draft PR: #12495
Epic: #11556 lever E | Prior ruling: CTO 2026-11-06 (defer to measured experiment)

## Phase 1 — Longer-window decision gate (measurement only)

- [x] 1.1 Compute `SINCE` (~28d back) and count discarded speculation: `gh run list --repo jikig-ai/soleur --event merge_group --workflow ci.yml --status cancelled --created ">=<SINCE-date>" --json databaseId,conclusion,createdAt --limit 400 | jq 'length'` — FLIP signal if `>= 2`.
- [x] 1.2 Merge count for drain context: `gh pr list --repo jikig-ai/soleur --state merged --search "merged:>=<SINCE-date>" --json number --limit 500 | jq 'length'`.
- [x] 1.3 Demand share: `bash scripts/ci-demand-census.sh --start <w0> --end <w1> --summary` over >= 4 non-overlapping 12h windows spread across the period; compute `BY_WORKFLOW ci.yml merge_group` share of summed `TOTAL_JOB_MINUTES` — FLIP signal if `>= 40%`.
- [x] 1.4 Read the standing `ci-wallclock-p90` tracker body for the current `test` merge_group p50/p90 row (context only — never a FLIP trigger).
- [x] 1.5 Write the numbers + verdict (FLIP or DECLINE) into the plan's `## Decision Gate Result` section.

## Phase 2 — Verdict-independent hardening + record

- [x] 2.1 `tests/scripts/test-audit-ruleset-bypass.sh`: add `max_entries_to_build ∈ {1,2}` to the `_mq_guard2` safety-values block (~L901-905, beside the `max_entries_to_merge` pin); add `T-mq-1.m14` (→ `4` in tf+DR+README → RED on safety value) and a `{1,2}` must-PASS row.
- [x] 2.2 `infra/github/README.md`: `max_entries_to_build` params-table note gains "Sanctioned values per Guard 2: {1,2}" + experiment pointer (value cell unchanged unless 3B).
- [x] 2.3 `scripts/followthroughs/mq-lever-e-verdict-12269.sh`: new probe — reads live `max_entries_to_build` from `infra/github/ruleset-ci-required.tf`; value==2 arm counts `--status cancelled` `merge_group` `ci.yml` runs since `earliest − 28d` (`>=1` → exit 5; `0` → exit 0); value==1 arm compares `test` merge_group p50 in the watch tracker body vs the before-window floor, requiring the row's window to postdate the flip (else exit 3 re-poll); every `gh` failure → exit 3; prints one `REEVAL key=value…` line.
- [x] 2.4 `scripts/followthroughs/mq-lever-e-verdict-12269.test.sh`: fixture suite covering both value arms, the exit-5/exit-0/exit-3 routing, and the postdate check (no network).
- [x] 2.5 ADR-270 dated addendum: gate criteria, window numbers, verdict, {1,2} pin, and (3B) serialization + stall-coverage hazards or (3A) decline + re-eval enrollment.

## Phase 3 — Branch execution

### 3A — DECLINE branch (expected)

- [ ] 3A.1 Comment Phase-1 numbers + verdict on #12269.
- [ ] 3A.2 NO param edits — verify `git diff origin/main...HEAD -G'max_entries_to_build( *= *)[0-9]|MAX_ENTRIES_TO_BUILD' --name-only` is empty.
- [ ] 3A.3 After merge (probe on `main`): `follow-through` label + column-0 unfenced directive `<!-- soleur:followthrough script=scripts/followthroughs/mq-lever-e-verdict-12269.sh earliest=2026-12-15T00:00:00Z secrets=GH_TOKEN -->` on the #12269 body.

### 3B — FLIP branch (only on Phase-1 FLIP signal)

- [x] 3B.1 `infra/github/ruleset-ci-required.tf`: `max_entries_to_build = 1` + comment update.
- [x] 3B.2 `scripts/create-ci-required-ruleset.sh`: `"max_entries_to_build": 1`.
- [x] 3B.3 `infra/github/README.md`: value cell `1` + note (experiment outcome, revert recipe).
- [x] 3B.4 `.github/workflows/merge-queue-stall-check.yml`: `MAX_ENTRIES_TO_BUILD: '1'` + mirror comments (note narrowed `position <= 1` aging window).
- [ ] 3B.5 Post-merge: verify `apply-github-infra.yml` applies clean; next queued entry builds normally; file directive on #12269 with `earliest=<merge>+21d`.
- [ ] 3B.6 If soak verdict is revert (Phase 4 of plan): one PR reverting the four surface values to `2`; ADR-270 addendum line.

## Phase 4 — Verification

- [ ] 4.1 `bash tests/scripts/test-audit-ruleset-bypass.sh` green incl. m14 + must-PASS rows.
- [ ] 4.2 `bash scripts/followthroughs/mq-lever-e-verdict-12269.test.sh` green.
- [ ] 4.3 `plugins/soleur/test/merge-queue-stall-check.test.sh` S8 green (env mirror == live `.tf`).
- [ ] 4.4 AC sweep: AC1-AC12 per the branch taken; PR body uses `Ref #12269`.
