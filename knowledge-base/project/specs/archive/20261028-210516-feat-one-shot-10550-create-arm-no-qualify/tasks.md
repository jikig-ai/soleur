# Tasks: create-arm no-qualify investigation (Ref #10550)

Plan: `knowledge-base/project/plans/2026-10-28-fix-create-arm-no-qualify-evidence-and-offer-telemetry-plan.md`

## Phase 0: offline probe (scratchpad only, no cron, not in the diff)

- 0.1 `doppler run -p soleur -c ci --only-secrets ANTHROPIC_API_KEY -- <script>` only; never a `prd*` config; if unusable record "probe not run"
- 0.2 No `markerSource`/`markerRunId`; no `set -x`; model output to a 0600 scratchpad file, counts only on the terminal
- 0.3 Arm 0: unmodified prompt via `prepareCreate`, all 7 patterns, 2 calls; `checkCreate` offline on any create (label "prod readers not exercised")
- 0.4 Arm 1: arm 0 plus the six non-owned pattern bodies (lstat, `PII_REGEX` and `CREDENTIAL_RE`, nonce fence), 3 calls
- 0.5 Apply the decision rule; post ONE finding comment on #10550 (no closure); file a follow-up only if a rule fires

## Phase 1: `create_offered` (tests first)

- 1.1 Consumer grep (`CreateVerdict`, `CreateRefusal`, step output) and the marker-name grep over tests, plugin tests and scripts; run what it names
- 1.2 Characterization test against the PRE-refactor code (post args, `checkCreate` context, guard order); keep it green across the refactor
- 1.3 Failing tests: arm suite (fixture of four patterns: same-run, ledger-owned, two offered; `not.toHaveProperty` rows; `toEqual` sites incl. line 230), handler suite (opened, persist refusal, memo-seeded legacy shape, bad values, JSON round trip, strip before persist, key pins, `CREATE_ONLY_KEYS`, H3 pre-call rows), marker suite (emit rows, negative probes), census Guard 3d (`createOffered =`), one bar-sentence assertion
- 1.4 `selectOffered` + `proposeInner` returning `{verdict, offeredCount?}` + `CreateStepVerdict`; stamp inside the `try`
- 1.5 Handler: annotation, hoisted `createOffered` assigned right after `create-propose` (outside the callback, range-guarded), strip before persist, `createMarker` spread
- 1.6 Marker type and comment bullet in `compound-promote-marker.ts`

## Phase 2: docs

- 2.1 Runbook: `create_offered` row; reconcile the `create_no_action_reason` row and the "there is no call" sentences
- 2.2 `betterstack-log-query.md`: field sentence and recipe column list
- 2.3 ADR-300: dated addendum line

## Phase 3: ship and stop

- 3.1 `./node_modules/.bin/tsc --noEmit` and the whole compound-promote suites from `apps/web-platform`; `c4-count-parity.test.sh` and `lint-betterstack-emitter-read.sh` from the root
- 3.2 PR body: "Ref #10550", measurement only, effect unmeasured until an operator-authorised live-fire clears
- 3.3 Merge, verify deploy serves the merge SHA, run `soleur:postmerge`
- 3.4 STOP: ask the operator for the go-ahead naming the one manual fire; do not run `soleur:trigger-cron`
