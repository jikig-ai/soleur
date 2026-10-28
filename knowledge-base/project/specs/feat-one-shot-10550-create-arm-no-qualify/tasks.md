# Tasks: create-arm no-qualify investigation (Ref #10550)

Plan: `knowledge-base/project/plans/2026-10-28-fix-create-arm-no-qualify-evidence-and-offer-telemetry-plan.md`

## Phase 0: offline probe (scratchpad only, no cron, not in the diff)

- 0.1 Check key availability by name (`doppler secrets --only-names -p soleur -c ci`); if none, record "probe not run: no key"
- 0.2 Arm 0: unmodified prompt via `prepareCreate` over all 7 patterns; run `checkCreate` offline on any create
- 0.3 Arm 1: arm 0 plus the six non-owned pattern bodies in a nonce fence (hand-assembled prompt)
- 0.4 Apply the decision rule; post ONE finding comment on #10550 (no closure); file a follow-up only if a rule fires

## Phase 1: `create_offered` (tests first)

- 1.1 Grep every consumer of `CreateVerdict` / `CreateRefusal` / step output (`hr-type-widening-cross-consumer-grep`)
- 1.2 Failing tests: arm suite (`offered` 6/0/absent cases, mutation rows), handler suite (opened, persist refusal, legacy memo, JSON round trip, key pins, `CREATE_ONLY_KEYS`), marker suite (`ALLOWED`, `CREATE_KEYS`), one bar-sentence assertion
- 1.3 `selectOffered` helper and `CreateStepVerdict` in `compound-promote-create-arm.ts`; stamp at one site
- 1.4 Handler: annotation, hoisted `createOffered` assigned right after `create-propose`, `createMarker` spread
- 1.5 Marker type and comment bullet in `compound-promote-marker.ts`
- 1.6 `BASELINE_DECLARED_PROBES` 87 -> 88 with its comment (re-read the value on origin/main first)

## Phase 2: docs

- 2.1 Runbook: `create_offered` row; reconcile the `create_no_action_reason` row and the "there is no call" sentences
- 2.2 `betterstack-log-query.md`: field sentence and recipe column list

## Phase 3: ship and stop

- 3.1 tsc from `apps/web-platform`, vitest suites, `c4-count-parity.test.sh`, preflight-discoverability suite
- 3.2 PR body: "Ref #10550", measurement only, effect unmeasured until an operator-authorised live-fire clears
- 3.3 Merge, verify deploy serves the merge SHA, run `soleur:postmerge`
- 3.4 STOP: ask the operator for the go-ahead naming the one manual fire; do not run `soleur:trigger-cron`
