# Tasks — feat-one-shot-6940-7632-cutover-followups

Plan: `knowledge-base/project/plans/2026-10-07-fix-inngest-cutover-followups-6940-plan.md`

## Phase 1 — registry probe emits trigger type (TDD)

- [x] 1.1 Extend `apps/web-platform/infra/inngest-registry-probe.test.sh` FIRST (failing):
      fixture builder accepts per-function `triggers` arrays; new cases — CRON type/value
      preserved in `.functions`; EVENT-only preserved; id-only fixture → `triggers: []`;
      `function_ids`/`function_count`/`registry_empty` unchanged; stdout stays one pure
      JSON object.
- [x] 1.2 `apps/web-platform/infra/inngest-registry-probe.sh`:
      `FUNCTIONS_GQL_QUERY` → `query RegistryProbe { functions { id slug triggers { type value } } }`;
      emit `functions: [{id, slug, triggers: [{type, value}]}]` with `.triggers[]?`/`// []`
      tolerance; keep the fail-loud non-array gate; update the header contract comment.

## Phase 2 — zero-run discovery in `op=verify` (TDD)

- [x] 2.1 `apps/web-platform/infra/cutover-inngest-workflow.test.sh` FIRST (failing):
      update `MTR_CALL` literal (call passes `"$MTR_BODY"`), the `MTR_PREV` neighbour pin,
      and the `inngest-doublefire-probe?from=` site count 2 → 3; new asserts — discovery
      gated on flag + both window vars; `function_ids=${ZERO_RUN_IDS}`; no `until=` on the
      new URL; single bounded curl (no new `for attempt in 1 2`); failure path is
      `::warning::` (never `exit 1`); step env maps `CUTOVER_DISCOVERY_LOOKBACK_S`; extraction
      cases for `zero_run_cron_ids` (cron-only filter, observed subtraction, shape check,
      empty → no call).
- [x] 2.2 `scripts/cutover-inngest.sh`: capture `REG_BODY="$BODY"` after the verify registry
      precondition (~:2863); new column-0 pure helper `zero_run_cron_ids`; discovery block in
      the verify arm between the SCOPE CAVEAT echo and the `missed_tick_report` call; call
      becomes `missed_tick_report "$MTR_GATE" "$MTR_BODY" "$CRON_PERIOD" "${CUTOVER_WINDOW_FROM:-}" "${CUTOVER_WINDOW_UNTIL:-}"`.
- [x] 2.3 `.github/workflows/cutover-inngest.yml`: map
      `CUTOVER_DISCOVERY_LOOKBACK_S: ${{ vars.CUTOVER_DISCOVERY_LOOKBACK_S }}` in the run step
      env; add the dated item-2 deferral comment (AC-V4 precondition + dormant `exit 1`).

## Phase 3 — records

- [x] 3.1 Annotate ADR-146 §Deferred item 1 as landed (dated note, matching the existing
      `[2026-09-25, #6939:]` pattern).
- [ ] 3.2 Commit; PR body carries `Closes #7632` (verified-pin evidence) + `Ref #6940`.

## Exit

- [ ] `bash apps/web-platform/infra/inngest-registry-probe.test.sh` green
- [ ] `bash apps/web-platform/infra/cutover-inngest-workflow.test.sh` green (raise the
      anti-deletion floor by the assertion delta added)
- [ ] `bash scripts/test-all.sh --affected` (or the repo's affected-suites runner) green
