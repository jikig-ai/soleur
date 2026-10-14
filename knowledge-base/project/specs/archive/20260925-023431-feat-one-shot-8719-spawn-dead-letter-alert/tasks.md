# Tasks: page on agent-on-spawn-requested leader-loop dead-letters (#8719)

Plan: `knowledge-base/project/plans/2026-09-25-feat-agent-on-spawn-dead-letter-sentry-alert-plan.md`

## Phase 1: Emitter (RED first)

- [x] 1.1 Write `apps/web-platform/test/server/spawn-dead-letter.test.ts` (Guard 3): real logger
  and observability, `@sentry/nextjs` mocked; `vi.stubEnv` `SENTRY_BREADCRUMB_LEVEL=warn` and
  `LOG_LEVEL=info` + `vi.resetModules()` before importing; breadcrumb positive control; must-pass
  inputs (Error, string, `null`, `undefined`, `Object.create(null)`, StepError-shaped,
  PostgREST-shaped); `pg_code` for a direct `{ code: "42501" }`; `userIdHash` present and the
  synthetic founder uuid absent; `safeToolName` cases; throwing-reporter case via `vi.doMock`
- [x] 1.2 Write `apps/web-platform/test/sentry-spawn-dead-letter-alert-op-contract.test.ts`: Guard 1
  (tags, set equality, literal six-reason pin, `logic_type`, `enabled`, `match`, `monitor_ids`,
  `ActiveMembers`, root-wide unique `frequency_minutes`, paste-ready failure message) and Guard 2
  (rows matching `/notif/i` are exactly the promised four, each `true` in `PAGES_OPERATOR`)
- [x] 1.3 Leader-loop suite: move `deadletterCall()` to module scope; add `not.toBeInstanceOf(Error)`
  and `tags` assertions (400, 404/413/422, AC10 truncated, AC10 tool-invalid with
  `extra.tool/turn/model`, the stop-reason `it.each`); add the message-conditioned forced-throw
  case (`mock.results` throw entry, dead-letter result returned, `persist-failure` memoized); fix
  the stale comment
- [x] 1.4 Run the suites; confirm they fail for the expected reason
- [x] 1.5 Create `apps/web-platform/lib/failure-reason.ts` (move the union, add `PAGES_OPERATOR` with
  six `true` rows and per-row rationale); `failure-reason-copy.ts` imports and re-exports the type
  and updates its header checklist; no copy text changes
- [x] 1.6 Create `apps/web-platform/server/spawn-dead-letter.ts` (literals, derived paged set,
  `reportSpawnDeadLetter` with outer try/catch whose catch logs `{ err }` and sends a tagged
  `report failed` message in nested tries, `toMessagePathError` built field by field,
  `toReportExtra` renaming `founderId` → `userId`, `safeToolName`, header citing #8629 and naming
  `anthropic-credit.ts`)
- [x] 1.7 `agent-on-spawn-requested.ts`: import `FailureReason` from `@/lib/failure-reason` and delete
  the private union; `persistFailure` → `reportSpawnDeadLetter`; drop the `reportSilentFallback`
  import; `leader_tool_invalid` passes `extra: { turn, model, tool: safeToolName(tu.name) }`; fix
  the stale comment
- [x] 1.8 `./node_modules/.bin/tsc --noEmit`, the four vitest suites, and the dependency-cruiser gate
  green (rule half of the contract test stays red until 2.1)

## Phase 2: Rule

- [x] 2.1 Append `sentry_alert.spawn_agent_dead_letter` to `apps/web-platform/infra/sentry/issue-alerts.tf`
  (frequency 1442, four triggers, feature/op `eq`, reason `in` six values, `ActiveMembers`), with a
  comment block including how to read a `leader_class_disabled` email
- [x] 2.2 `terraform fmt -check`; `terraform init -backend=false && terraform validate`
- [x] 2.3 README line 5 counts → 35/35 and owned count → 33 (32 in issue-alerts.tf); history note
- [x] 2.4 `model.c4` `sentry -> founder`: "32 of the 34"
- [x] 2.5 Run `sentry-monitors-audit.test.sh` (T25), `c4-count-parity.test.sh`,
  `c4-code-syntax.test.ts`, `c4-render.test.ts`

## Phase 3: Reference snapshot

- [x] 3.1 Regenerate `apps/web-platform/infra/sentry/alert-reference.json` via the projection (PR
  round-trip artifact or local plan); never hand-edit
- [ ] 3.2 `sentry-alert-reference-gate.sh` green on the PR

## Phase 4: Ship and verify

- [x] 4.1 PR body first line: merging applies the rule (`apply-sentry-infra.yml`) and deploys the
  emitter (`web-platform-release.yml`); `Closes #8719`; render `decision-challenges.md` DC-1/DC-2
- [x] 4.2 Comment on #8629 that `server/spawn-dead-letter.ts` joins `server/anthropic-credit.ts` as a
  message-path workaround to revert when the fleet-wide fix lands
- [x] 4.3 ~~File a tracking issue~~ Fixed inline instead (one line): the `persist-failure` warn was
  the only other handler log line carrying `founderId`, and it goes to the Inngest ctx logger (not
  pino), so the `userId` rename never runs there. The field is dropped; `actionSendId` identifies the
  row. Leader-loop test "#8719: a failed persist-failure write logs actionSendId, never the raw
  founder id" pins it (reds with the field restored).
- [ ] 4.4 Post-merge: `apply-sentry-infra.yml` run for the merge commit concludes `success`
  (including live fidelity)
