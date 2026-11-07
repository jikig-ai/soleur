# Tasks: feat-one-shot-11635-cc-approval-gate

Ref #11635, Ref #9601. Plan: knowledge-base/project/plans/2026-11-05-feat-cc-approval-gate-and-execution-grants-plan.md

CI is the ship gate: do not wait on the slow local `--affected` battery; run only the targeted files below.

## Phase 1 - RED tests first

- 1.1 Create `apps/web-platform/test/approval/cc-approval-fail-closed.test.ts` (real `createCanUseTool`, mirror `permission-callback-gated-branch.test.ts`):
  - 1.1.1 `it.each` over the live `APPROVAL_REQUIRED_TOOLS`: switch set + no `approval` -> deny, no card, `isEnabled` unread, one Sentry error `stage: "wiring-absent"`
  - 1.1.2 switch set + flag false / rejecting / true (gate verdict) / sticky `enforcing` then false
  - 1.1.3 switch unset: byte-identical review card (approval absent; flag off)
  - 1.1.4 cap reached, non-interactive, unreviewable input (`email_send`, invalid recipient), aborted signals, support persona: deny + no card
  - 1.1.5 three exempt CRM writes: switch set, approval wired, flag seam true -> `isEnabled` unread, card shown, Reject denies; approval absent same
  - 1.1.6 non-vacuity: eight tools, every one `gated` in `TOOL_TIER_MAP`
- 1.2 Edit `apps/web-platform/test/approval/tools-census.test.ts`: derived cc registration sweep `describe` (Guard 2) reusing the existing `beforeAll` cc-dispatcher import; fix the stale comment
- 1.3 Edit `apps/web-platform/test/approval/runner-census.test.ts`: replace the stale cc negative assertion with three presence pins (one `new ExecutionGrants()`, same identifier as `grants:` to `createApprovalGateDeps(`, `approvalFailClosed: true`); keep the "cc registers no slice-1 tool" census
- 1.4 Edit `apps/web-platform/test/cc-dispatcher-real-factory.test.ts`: new wiring `describe` (`mockClear()` first; distinct grants per invocation; `enforcing === false`; switch; workspaceId; no required tool in final `allowedTools`)
- 1.5 Run the four files; confirm RED for the right reason

## Phase 2 - GREEN

- 2.1 `apps/web-platform/server/permission-callback.ts`: `approvalFailClosed?: boolean` dep + single deny site after the existing gate block (keep the two Guard 1 battery anchor lines byte-identical)
- 2.2 `apps/web-platform/server/cc-dispatcher.ts`: imports; one `new ExecutionGrants()` inside `realSdkQueryFactory` before `ccDeps`; `approval: createApprovalGateDeps({...workspacePath, grants})` and `approvalFailClosed: true` in `ccDeps`; reword `readCcMcpAllowlist` comment + message (keep throw, `/approval/i`, `approval-required tool "<name>"`)
- 2.3 Apply each Guard 1 mutation row once; confirm the named test reds; restore
- 2.4 Run every test exercising `realSdkQueryFactory` plus `test/approval/*` files that drive `createCanUseTool`

## Phase 3 - ADR, comments, verification

- 3.1 ADR-309: dated addendum, make universal statements consistent, correct the sentinel bullet, add `11635` to `related`
- 3.2 `apps/web-platform/server/workspace-settings-tools.ts` header comment
- 3.3 Run `test/repo-wide-containment.test.ts` (and any `test/repo-wide-contain*`), `bash apps/web-platform/test/approval-guard1-mutation.test.sh --check-anchors`, `bash plugins/soleur/test/c4-count-parity.test.sh`, `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`, ESLint on changed files
- 3.4 Grep the diff's added lines for any `#<number>` other than the two permitted refs and for any number the brief excludes
- 3.5 PR body: `Ref #11635`, `Ref #9601`, no close keyword
