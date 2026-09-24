# Tasks: page on agent-on-spawn-requested leader-loop dead-letters (#8719)

Plan: `knowledge-base/project/plans/2026-09-25-feat-agent-on-spawn-dead-letter-sentry-alert-plan.md`

## Phase 1: Emitter (RED first)

- [ ] 1.1 Write `apps/web-platform/test/server/spawn-dead-letter.test.ts` (Guard 3, real logger and
  observability, `@sentry/nextjs` mocked; must-pass inputs: Error, string, StepError-shaped object,
  PostgREST-shaped object; `pg_code` for a direct `{ code }` input)
- [ ] 1.2 Write `apps/web-platform/test/sentry-spawn-dead-letter-alert-op-contract.test.ts` (Guard 1
  rule contract with root-wide unique `frequency_minutes` and a paste-ready failure message; Guard 2
  `/notif/i` → `pagesOperator: true`, at least four matching rows)
- [ ] 1.3 Leader-loop suite: move `deadletterCall()` to module scope; add `not.toBeInstanceOf(Error)`
  and `tags` assertions (400, 404/413/422, AC10 truncated, AC10 tool-invalid with `extra.tool`,
  stop-reason `it.each`); add the forced-throw case; fix the stale comment
- [ ] 1.4 `failure-reason-copy.test.ts`: `pagesOperator` is a boolean on every row
- [ ] 1.5 Run the four suites; confirm they fail for the expected reason
- [ ] 1.6 Add required `pagesOperator` to `FailureReasonRow` and all 19 rows (six `true`, per the
  plan table); update the file header checklist; no `copy` text changes
- [ ] 1.7 Create `apps/web-platform/server/spawn-dead-letter.ts` (literals, derived paged set,
  `reportSpawnDeadLetter` with an outer try/catch, `toMessagePathError` returning
  `{ name, message, stack, code }`, "MESSAGE PATH ON PURPOSE" header citing #8629)
- [ ] 1.8 `agent-on-spawn-requested.ts`: import `FailureReason` type from the copy module and delete
  the private union; `persistFailure` → `reportSpawnDeadLetter`; drop the `reportSilentFallback`
  import; `leader_tool_invalid` passes `extra: { turn, model, tool }`; fix the stale comment
- [ ] 1.9 `./node_modules/.bin/tsc --noEmit` and the four vitest suites green (rule half of the
  contract test stays red until 2.1)

## Phase 2: Rule

- [ ] 2.1 Append `sentry_alert.spawn_agent_dead_letter` to `apps/web-platform/infra/sentry/issue-alerts.tf`
  (frequency 1442, four triggers, feature/op `eq`, reason `in` six values, `ActiveMembers`), with a
  comment block including how to read a `leader_class_disabled` email
- [ ] 2.2 `terraform fmt -check`; `terraform init -backend=false && terraform validate`
- [ ] 2.3 README line 5 counts → 35/35 and owned count → 33 (32 in issue-alerts.tf); history note
- [ ] 2.4 `model.c4` `sentry -> founder`: "32 of the 34"
- [ ] 2.5 Run `sentry-monitors-audit.test.sh` (T25), `c4-count-parity.test.sh`,
  `c4-code-syntax.test.ts`, `c4-render.test.ts`

## Phase 3: Reference snapshot

- [ ] 3.1 Regenerate `apps/web-platform/infra/sentry/alert-reference.json` via the projection (PR
  round-trip artifact or local plan); never hand-edit
- [ ] 3.2 `sentry-alert-reference-gate.sh` green on the PR

## Phase 4: Ship and verify

- [ ] 4.1 PR body first line: merging applies the rule (`apply-sentry-infra.yml`) and deploys the
  emitter (`web-platform-release.yml`); `Closes #8719`; render `decision-challenges.md` DC-1/DC-2
- [ ] 4.2 Post-merge: `apply-sentry-infra.yml` run for the merge commit concludes `success`
  (including live fidelity)
