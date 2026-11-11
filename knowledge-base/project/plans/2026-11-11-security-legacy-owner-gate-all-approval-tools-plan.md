---
title: "security: Owner-only legacy approval card for every approval-required tool"
date: 2026-11-11
slug: security-legacy-owner-gate-all-approval-tools
branch: feat-one-shot-12597-legacy-owner-gate-all-approval-tools
issue: 12597
closes: 12597
type: security
priority: p1
domain: engineering
lane: single-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# security: Owner-only legacy approval card for every approval-required tool

Closes #12597. Ref #12197 (epic). Draft PR #12646.

## Enhancement Summary

**Deepened on:** 2026-11-11 (after a seven-reviewer plan review and a sharp-edges pass)
**Sections enhanced:** 14 (Overview, Property List, Scope Check, Phase 1-4, Guard Contract, Observability, Acceptance
Criteria, User-Brand Impact, Sharp Edges, Test Scenarios)
**Agents used:** security-sentinel, test-design-reviewer, user-impact-reviewer, observability-coverage-reviewer,
learnings-researcher, a verify-the-negative / post-edit self-audit pass, and the CTO agent for every technical fork
(rulings S1-S6, O1-O5, U1).

### Key Improvements

1. The legacy card's Approve is honoured only if the user is still the Owner when they answer (Phase 1.1b, CTO S1). This
   closes the demotion-while-waiting residual, which now covers sends and shares that cannot be undone.
2. The cap re-check moved after the role deny (CTO S3), so a member at the cap still sees the right deny and log key.
3. The cap-race test now uses ONE `createCanUseTool` instance with explicit sync points. As first written it would have been
   RED on correct code, because the pending counter is per instance.
4. Observability: the timeout gets `code: "role_read_timeout"` (the CPO's "reason" condition), new `stage` fields, a
   `conversationId` on the member deny, a warn line on every legacy card issued, layer citations, and a discoverability probe
   that prints 0 on `main` and 1 after.
5. Two more battery rows: over-widening (`G1-LO9`) and the answer-time re-read (`G1-LO10`). The floors are now
   366 / 360 / 784, and the legacy file has 98 tests.
6. Copy: the leader-prompt sentence at `agent-runner.ts:1656` is also swept; the earlier AC10 grep would have failed on it.

### New Considerations Discovered

- A per-workspace flag override is a fourth trigger, and it refuses that workspace's members indefinitely (Overview, ADR
  rollback pointers, PR body).
- Five pre-existing findings are outside this property and were filed as follow-ups (#12660-#12664; see Research Insights).
- AC20 adds a pre-merge, read-only production check that no real Owner was misread as a member since #12567.

## Overview

When the approval flow gives no verdict on the legacy runner (the approval-queue flag is off or unreadable, or the
approval dependency is missing), the in-memory review card goes to the session's own user. Since #12197 D1 (PR #12567)
that card is shown only to the workspace Owner for `github_push_branch`. The other seven approval-required tools still
show it to a member, who can then approve their own outbound email, suppression, pull request, workflow run, public KB
share or autonomy change. This plan extends the existing Owner check to every tool in `APPROVAL_REQUIRED_TOOLS`, per
the CTO ruling of 2026-11-11 (the brief), and records the change in ADR-309.

The approval-queue flag is ON in production (ADR-309, 2026-11-09 addendum), so this fallback runs in four states: the
flag read fails, the flag is turned off fleet-wide (rollback), the flag is turned off for one workspace (the flag is read
per workspace, `orgId: identity.workspaceId` in `server/approval/flag.ts:30-38`, and `soleur:flag-set-role` can flip one),
or the dependency is absent. In each of them a member could otherwise approve their own action. In the per-workspace
case, the members of that workspace are refused for as long as the override stands, not only during a rollback.

The code change is about 30 lines in one file. Most of the work is tests: eight existing test files go red on the
widened predicate (measured, see Research Insights), and the mutation battery gets ten rows and new floor values.

Plan review added one property (CTO F10): the role read adds a second await between the pending-card cap check and the
card. The flag read inside `runApprovalGate` already opened the same gap on the legacy path, so two calls could both pass
the cap and stack a sixth card. The widened block re-checks the cap after the role read, which closes both. The same gap
on the approval-queue path is tracked in #12657.

## Research Reconciliation — Spec vs. Codebase

| Claim (brief / issue) | Reality on this branch | Plan response |
|---|---|---|
| Fix-size "~30 lines / 2 files" (issue body) | The source change is ~30 lines in `server/permission-callback.ts`, but a scratch-copy probe with only the predicate widened turns 48 tests red in 8 files | Files to Edit lists all 8 test files plus the battery, ADR-309, `ops.ts`, `tools.ts`, `agent-runner.ts`, `github-tools.ts` comment/copy lines |
| "all 8 in APPROVAL_REQUIRED_TOOLS" | `server/approval/tools.ts:17-26` lists 8; all 8 are `gated` in `server/tool-tiers.ts` (`TOOL_TIER_MAP`), pinned by `test/approval/tools-census.test.ts:18,25` | Tests iterate `APPROVAL_REQUIRED_TOOLS` itself; a precondition test asserts the list is non-empty and each member is `gated` with a `SAMPLES` input; the exact set stays pinned by `tools-census.test.ts` |
| "Update gate-flow.test.ts if its legacy expectations change" | They do: `"%s: absent, disabled and a throwing flag read behave identically"` (test.each over the 7 non-push tools, `gate-flow.test.ts:308`) goes red for all 7, because "absent" is now a deny | Rewrite it over all 8 tools: flag off and flag-throws (Owner) still match each other and show today's card; "absent" is pinned as a deny in the legacy file. Count 7 -> 8, so the battery FLOOR for gate-flow goes 129 -> 130 |
| Mutation battery: "Raise MIN_MUTANTS and the FLOOR[...] entry of each changed test file" | `legacy-push-owner-fallback.test.ts` has NO FLOOR entry today (no row targets it). The battery also has `MIN_KILLED=350` and `MIN_CHECKS=763` literals whose comment derives them from the row and control counts | Add a new FLOOR entry (exact count), raise MIN_MUTANTS, MIN_KILLED and MIN_CHECKS by the exact delta and update the derivation comment |
| "Keep readRoleBounded and the deadline constant (rename only)" | `PUSH_ROLE_READ_DEADLINE_MS` (`permission-callback.ts:397`) is exported and imported only by the legacy test | Rename to `OWNER_ROLE_READ_DEADLINE_MS` (CTO F2); value stays 5_000 |
| "PUSH_DISCLOSURE stays accurate; check settings copy" | `lib/web-egress-disclosure.ts:16-17` claims Owner approval only for a push an agent asks for; no settings surface names the other seven tools as approvable by a member (grep of `app/`, `components/`, `lib/` for approval copy) | No settings copy change. Three model-visible tool descriptions say who approves in other words: `github_trigger_workflow` (`server/github-tools.ts:544`, "Requires founder approval via review gate."), `email_send` (`server/email-triage-tools.ts:296-297`) and `email_reply` (`:356`), both "the operator approves". All three are aligned to the push tool's Owner wording (CTO F5, F11) |

## Research Insights

### Premise Validation

- #12597 is OPEN, not closed by any PR; the only open change naming it is this branch's draft PR #12646
  (`collision-precheck.sh 12597` -> `prs=12646 foreign=none`).
- #12197 (epic) is OPEN. #12600 (post-session `syncPush`) is OPEN and is a separate path; out of scope here.
- The cited code exists on this branch: the push-only block at `server/permission-callback.ts:1644-1697`
  (`if (toolName === GITHUB_PUSH_BRANCH_TOOL) {`), `readRoleBounded` at `:398`, the comment to delete at `:1648-1649`.
- ADR corpus check for the mechanism: ADR-309's 2026-11-10 inline addendum (in the 2026-11-05 #11635 addendum's "Fail
  closed" bullet) explicitly rejected passing `approvalFailClosed` on the legacy runner ("it would also refuse the other
  seven tools for solo Owners") and names #12597 as the accepted residual. Extending the Owner check is the mechanism that
  addendum chose for push; it is not a rejected alternative.

### Property List

1. On the legacy runner, when the approval flow gives no verdict for an approval-required tool, the in-memory card is
   emitted only to a session user whose bounded role read returned `owner`.
2. Every other outcome (member, failed role read, timed-out role read, missing dependency) is the static
   `APPROVAL_UNAVAILABLE_DENY` with no card, no `waiting_for_user` write and no offline notification.
3. An abort (Stop, or the session ending) during the role read is the existing expired-gate deny, not the unavailable text,
   and is not reported as a failed read.
4. The role read never holds a turn longer than the deadline.
5. Gated tools outside the approval-required set keep today's card for any user, with no role read.
6. A failed read and a missing dependency reach Sentry (existing ops); a member deny reaches the logs.
7. The test population is the shared list, so a ninth approval-required tool is covered without a test edit.
8. The pending-card cap (`MAX_PENDING_GATES`, 5) still holds when calls overlap during the role read: no more than five
   cards are open at once on the legacy path (CTO F10).
9. An Approve on the legacy card is honoured only if the answering user is still the workspace Owner when they answer:
   the role is read again after Approve, with the same deadline and the same fail-closed outcomes (CTO S1). This replaces
   the push-only demotion-while-waiting residual ADR-309 accepted on 2026-11-10.

### Cut List

- `approvalFailClosed` on the legacy runner -> property 1/2 -> already rejected in ADR-309 (2026-11-10 addendum): it would
  deny solo Owners too. Not used.
- A new role-read mechanism -> property 1/4 -> `approval.viewerRole()` (RPC `is_workspace_owner`, `server/approval/gate.ts:127-137`)
  and `readRoleBounded` already exist. Reused.
- New Sentry ops / alert rules -> property 6 -> `viewerRoleFailed` and `gateFailed` (`server/approval/ops.ts`) already carry
  `toolName`. Reused; `apps/web-platform/infra/sentry/**` is not touched.
- A new settings disclosure sentence -> no property needs it (no settings copy describes the seven tools as member-approvable).

### Follow-up issues filed at plan time (Mandated-By wg-when-an-audit-identifies-pre-existing)

- #12657: the pending-card cap check-then-await gap on the approval-queue path (CTO F10).
- #12660: any signed-in user can fire platform routines marked `manualTrigger: "confirm"` (CTO S4; pre-existing, outside
  this property).
- #12661: the `legacy` grant kind binds no workspace (CTO S2; named as a residual in the ADR addendum).
- #12662: `is_workspace_owner` / `is_workspace_member` do not bind `p_user_id` to `auth.uid()` (CTO S5; low priority).
- #12663: re-check the approval-exempt reasons for public repositories (CTO S6).
- #12664: own Sentry ops and paging rules for `wiring-absent` and the legacy role-read failure (CTO O5).

None blocks this PR; none is fixed in it.

### Measured blast radius (scratch-copy probe, 2026-11-11)

The app tree was copied to the session scratchpad (the battery's own copy layout: `node_modules` and `plugins/` symlinked),
only the predicate was widened there (`toolName === GITHUB_PUSH_BRANCH_TOOL` -> `isApprovalRequiredTool(toolName)`), and
vitest ran 136 test files that touch the permission callback, the agent runner or the cc dispatcher. The worktree was not
edited. Result: 48 failing tests in 8 files; nothing else turned red (two unrelated suites failed only because the scratch
copy has no `.github/` tree and no seccomp host support).

| File | Red | Why |
|---|---|---|
| `test/permission-callback-platform-gate-expiry.test.ts` | 31 | `makeCtx` gives an Owner approval dep only for push; every `email_send` case now denies (wiring absent) |
| `test/approval/gate-flow.test.ts` | 7 | the "absent, disabled and a throwing flag read behave identically" test.each |
| `test/canusertool-tiered-gating.test.ts` | 5 | `create_pull_request` through `startAgentSession`; `is_workspace_owner` answers `{data:null}` so the role read throws |
| `test/approval/cc-approval-fail-closed.test.ts` | 1 | "approvalFailClosed UNSET ... approval absent: a required tool still reaches the in-memory review card" |
| `test/approval/legacy-push-owner-fallback.test.ts` | 1 | the "narrow scope: email_send with a member still gets the card" pin |
| `test/agent-runner-tools.test.ts` | 1 | `create_pull_request` through `startAgentSession` (same rpc mock) |
| `test/agent-runner-kb-share-tools.test.ts` | 1 | `kb_share_create` through `startAgentSession` (same rpc mock) |
| `test/build-allowed-tools-census.test.ts` | 1 | `email_send` through `startAgentSession` (same rpc mock) |

The four `startAgentSession` files share `configureInstallationRpc` (`test/helpers/agent-runner-mocks.ts:52-61`), which
answers every RPC except `resolve_workspace_installation_id` with `{data: null}`. `viewerRole()` treats a non-boolean as a
failed read (`server/approval/gate.ts:135`), so the role is `unavailable` and the call is denied: correct fail-closed
behaviour, so the fix belongs in the tests, per file (CTO F3).

### Relevant files

- `apps/web-platform/server/permission-callback.ts:1596-1697` the gated branch: approval flow, cc fail-closed switch, legacy Owner check; `:397-430` `readRoleBounded`.
- `apps/web-platform/server/approval/tools.ts:17-37` the shared list, `isApprovalRequiredTool`, `GITHUB_PUSH_BRANCH_TOOL` (still used by `cc-github-push.ts:48` and `github-tools.ts:30`).
- `apps/web-platform/server/approval/ops.ts:134-141` `viewerRoleFailed` doc comment naming the `legacy-push-owner-check` stage.
- `apps/web-platform/server/agent-runner.ts` comment "(push: Owner only, #12197 D1)" next to `approval: createApprovalGateDeps(`.
- `apps/web-platform/server/approval/gate-flow.ts` module comment "(except `github_push_branch`, whose card only the workspace Owner may answer, #12197 D1)".
- `apps/web-platform/test/approval-guard1-mutation.test.sh` rows (python `M(...)` table, section 5 is the permission-callback gated branch), `FLOOR` map (`:975-1009`), `MIN_MUTANTS` (`:962`), `MIN_KILLED` / `EXPECT_*` (`:1131-1135`), `MIN_CHECKS` and its derivation comment (`:1141-1143`). CI runs it in the web-platform group (`scripts/test-all.sh:7391`, ~12-15 min).
- `knowledge-base/engineering/architecture/decisions/ADR-309-durable-action-bound-approval-requests.md` (inline addendum in the #11635 "Fail closed" bullet; dated addenda before `## Diagram`).

### Institutional learnings applied

- The predecessor PR's control floor for `gate-flow.test.ts` (130) sat above the real passed count (129) and voided the
  battery in CI (commit "fix(test): guard1 control floor for gate-flow.test.ts is 129"). Floors are set from the counted
  JSON report after the tests land, never from a planned number.
- `2026-08-10-my-sweep-missed-two-red-suites-and-my-battery-certified-garbage-mutations.md`: sweep by `git grep` on the
  changed symbols, not by directory; check the mutated bytes landed as intended (`--check-anchors`).
- `2026-11-08-a-one-line-log-field-rename-needed-a-guard-suite-whose-rows-assert-the-path-they-name.md`: table-driven rows
  must each assert the path they name, and the row count is asserted at collection time.
- `2026-07-24-count-vs-floor-guard-single-value-fixtures-cannot-discriminate-operator.md`: test the wrong-operator
  directions separately (hence two role-weakening rows).
- `2026-11-08-a-strict-read-reached-one-of-two-role-providers...md`: the role fact has one provider here
  (`approval.viewerRole()`); no second reader is added.
- `2026-03-20-review-gate-promise-leak-abort-timeout.md`: deadline tests with fake timers must restore real timers in
  `afterEach`, or a hung case leaks fake timers into later cases.

### Conventions

- Rule ids cited: `hr-type-widening-cross-consumer-grep`, `cq-union-widening-grep-three-patterns`,
  `cq-test-fixtures-synthesized-only`, `cq-silent-fallback-must-mirror-to-sentry`, `cq-cite-content-anchor-not-line-number`.
- Before every commit: `npx markdownlint-cli2 --fix` on every touched `.md` (ADR-309, this plan, tasks, decision record).

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "widen the existing Owner check from `toolName === GITHUB_PUSH_BRANCH_TOOL` to every tool where `isApprovalRequiredTool(toolName)`" | Phase 1.1 | mapped |
| 2 | "Keep readRoleBounded and the deadline constant (a rename to a tool-neutral name is fine, rename only)" | Phase 1.2 (`OWNER_ROLE_READ_DEADLINE_MS`) | mapped |
| 3 | "Delete the comment \"Other approval-required tools keep the in-memory card\"" | Phase 1.1, AC2 | mapped |
| 4 | "amend ADR-309's legacy-runner divergence note (append-only dated addendum)" | Phase 4, AC9 | mapped |
| 5 | "a member, a failed or timed-out role read, or a missing dependency gets the static deny APPROVAL_UNAVAILABLE_DENY with no card, no status write, no offline notification; Stop/abort keeps the existing gateExpiredDeny" | Phase 1.1 (control flow unchanged), Phase 2.1 cases 2-9 | mapped |
| 6 | "every approval-required tool (driven from the shared list, never a hand-copied one) is checked for: member denied, role read error denied, timeout denied, no dependency denied and reported, abort, and Owner gets the card" | Phase 2.1, AC5, AC14 | mapped |
| 7 | "Tools in APPROVAL_EXEMPT_TOOLS keep the card for a member" | Phase 2.1 exempt describe | mapped |
| 8 | "Update test/approval/gate-flow.test.ts if its legacy expectations change" | Phase 2.2 | mapped |
| 9 | "add rows ... for: the predicate narrowed back to push only, `role !== \"owner\"` weakened, the catch block allowing, the deadline removed" | Phase 3.1 rows `G1-LO1`..`G1-LO5` | mapped |
| 10 | "Raise MIN_MUTANTS and the FLOOR[...] entry of each changed test file by exactly the delta" | Phase 3.2, AC8 | mapped |
| 11 | "Run --check-anchors and an --only run for the new rows locally; rely on CI for the full battery" | Phase 3.3 | mapped |
| 12 | "PUSH_DISCLOSURE in apps/web-platform/lib/web-egress-disclosure.ts stays accurate; check whether any settings copy now under-describes" | Research Reconciliation (no change), AC11 | mapped |
| 13 | "keep closed-set copy tests exact" | Phase 2.6 (description pins); no closed-set copy test changes | mapped |
| 14 | CONSTRAINTS (legal bytes, sha256, PROVISIONAL, infra/sentry, no production writes, flag untouched) | Phase 5, AC11 | mapped |
| 15 | "PR body: \"Closes #12597\", \"Ref #12197\". Skip the feature tweet." | AC13 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Phase 1.1 predicate, comment, fail-closed flow | "widen the existing Owner check ... to every tool where `isApprovalRequiredTool(toolName)`" | asked |
| Phase 1.1 cap re-check, row `G1-LO7`, cap-race test | (none) | inferred — justification: CTO F10; the widening adds the role-read await that lets two calls both pass the pending-card cap, so the change itself would open a sixth-card stack without it |
| Phase 1.2 rename | "a rename to a tool-neutral name is fine, rename only" | asked |
| Phase 1.3 log/warn wording | (none) | inferred — justification: CTO F1'; the warn text says "a push", which is false for seven tools once the block widens |
| Phase 1.4 tool descriptions (trigger, email_send, email_reply) | "check whether any settings copy now under-describes (email/other approval-required tools)" | asked |
| Phase 1.5 comment sweep | "Delete the comment \"Other approval-required tools keep the in-memory card\"" | asked |
| Phase 2.1-2.2 tests | "extend apps/web-platform/test/approval/legacy-push-owner-fallback.test.ts ... Update test/approval/gate-flow.test.ts" | asked |
| Phase 2.3-2.5 other red suites | (none) | inferred — justification: measured by the scratch-copy probe (48 red tests in 8 files); the suite cannot be green without them |
| Phase 2.6b dev probe stub dependency | (none) | inferred — justification: CTO F12; without it the real-SDK probe only exercises the wiring-defect branch and still prints ok |
| Phase 3 rows `G1-LO6`, `G1-LO8`, `G1-LO9` | (none) | inferred — justification: the plan skill's Phase 2.12 (the Guard Contract section below); an ORDER property needs a reorder row, and every mutation-matrix row must be a row that turns tests RED |
| Phase 3.2 floors | "Raise MIN_MUTANTS and the FLOOR[...] entry of each changed test file by exactly the delta" | asked |
| Phase 4 ADR-309 addendum | "amend ADR-309's legacy-runner divergence note (append-only dated addendum)" | asked |

### Split Assessment

- Subsystems touched: 2 — `apps/web-platform` (server, test, scripts) and `knowledge-base` (ADR-309 plus this plan's records)
- Planned files: 20 edited, 0 created outside `knowledge-base/project/` | Estimated changed lines: ~650 (source ~70, tests ~500, battery ~40, ADR ~40)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — under every threshold, and splitting would ship the widened gate with a red suite or the tests without the gate.

## Implementation Phases

### Phase 1 — Source (`apps/web-platform/server/`)

1.1 `permission-callback.ts`, legacy fallback block (content anchor: `if (toolName === GITHUB_PUSH_BRANCH_TOOL) {`):

- Change the predicate to `if (isApprovalRequiredTool(toolName)) {`. Nothing else in the block's control flow changes: the
  missing-dependency report, the bounded role read, the abort check before the role check, the `role !== "owner"` deny.
- Replace the block comment. Delete the sentence "Other approval-required tools keep the in-memory card (ADR-309, legacy
  runner divergence)." The new comment says: #12597 (CTO ruling 2026-11-11, extends #12197 D1); for every approval-required
  tool only the workspace Owner may answer the card when the flow gives no verdict; a member, a failed or timed-out role read
  or a missing dependency is a static deny (no card, no status write, no offline notification); PUSH_DISCLOSURE relies on it
  for the push.
- Cap re-check (CTO F10, placement re-ruled S3): inside the widened block, AFTER the `role !== "owner"` deny (so the
  order is: role read, abort check, role deny, cap re-check, then the card), repeat the pending-card cap:
  `if (pendingGates >= MAX_PENDING_GATES) {` with the same `log.warn` decision `platform-gate-too-many-pending` plus one
  extra field `stage: "after-role-read"` (CTO O2; the decision key is unchanged), the same `logPermissionDecision` reason
  ("too many pending approvals") and the same `PLATFORM_GATE_TOO_MANY_PENDING_MESSAGE` deny as the first check (~`:1587`).
  A member is refused by the role deny first, so a member at the cap still sees the unavailable deny and is logged under
  `platform-gate-push-owner-required` (security review). A one-line comment says why: the role read is an await, so a
  call that passed the first check may find the cap full when it resumes. This is enough because nothing is awaited
  between this check and `pendingGates++`: after the Owner check the path is `sendToClient` (sync), `notifyOfflineUser`
  (not awaited) and `holdForUser`, whose body increments the counter before its first await (~`:484`). Keep it that way;
  an await added in between reopens the race. The first check at ~`:1587` stays where it is. The queue-on path has the
  same pre-existing gap, tracked in #12657 (not fixed here).
- Abort during the role read (CTO O2): pass `stage: "owner-role-read"` in the `fields` argument of that
  `gateExpiredDeny(...)` call, so this abort can be told apart from an abort on an undelivered card (same decision
  `platform-gate-aborted`).
- Legacy card issued (CTO O4): when the widened block admits the call, log one warn line before the card is sent:
  decision `platform-gate-legacy-card-issued`, with `tool`, `role` (always `owner` here), `conversationId` and `repo`.
  Card emission is otherwise logged only at info, which Vector drops, so this is the only production trace if a
  regression ever let a non-Owner reach the card. With the flag on in production it fires rarely.
- Timeout code (CTO O1): the deadline's `reject(new Error("viewer role read timed out"))` in `readRoleBounded` becomes an
  Error carrying `code: "role_read_timeout"` (for example
  `Object.assign(new Error("viewer role read timed out"), { code: "role_read_timeout" })`). `describeError`
  (`server/approval/ops.ts:216-224`) already ships `code`, and `viewerRole`'s own throws carry none, so the Sentry event's
  `code` alone tells a timeout from a failed read (the "reason" of the CPO's condition). The abort Error is never
  reported, so it needs no code. `G1-LO5`'s anchor follows the new bytes.

1.1b Re-read the role after Approve (CTO S1). In the same function, after `selection === "Approve"` and before the allow:
when the widened block admitted this call (a local such as `let ownerChecked = false` set to `true` once the role check
passes, so the two checks cannot drift apart), call `readRoleBounded(() => approvalDeps.viewerRole(), [options.signal,
ctx.controllerSignal])` again. An abort gives `gateExpiredDeny(..., "aborted", ...)` with `stage: "owner-role-answer"`; a
role other than `owner` gives `APPROVAL_UNAVAILABLE_DENY` with the member-deny warn (decision
`platform-gate-push-owner-required`, plus `stage: "on-answer"`); a failed or timed-out read gives the same deny plus the
`viewerRoleFailed` report with `tags: { stage: "legacy-push-owner-check" }` and `extra: { outcome: "denied-on-answer" }`.
Rejected answers skip the re-read (nothing is performed). Cost: one bounded RPC per approved call. The queue-on path
already re-checks when the Owner decides. The status lifecycle is unchanged: the re-read runs after `holdForUser`
returned, so `pendingGates` and the restore write are already settled.

- Remove `GITHUB_PUSH_BRANCH_TOOL` from the import on `:38` (now unused here; keep its export in `tools.ts`).
- Update the comment above `if (deps.approval && isApprovalRequiredTool(toolName)) {` ("(push: Owner only, #12197 D1)" ->
  "(Owner only, #12597)").

1.2 Rename `PUSH_ROLE_READ_DEADLINE_MS` -> `OWNER_ROLE_READ_DEADLINE_MS` (declaration, default parameter of
`readRoleBounded`, its doc comment: "the legacy card's Owner check", not "push card"). Value stays `5_000`. Then
`git grep -n PUSH_ROLE_READ_DEADLINE_MS` must return nothing outside `knowledge-base/project/`.

1.3 Observability names (CTO F1', re-ruled at plan review: both query handles stay, only free text changes):

- KEEP the pino log decision key `platform-gate-push-owner-required` byte for byte (a production log-query handle; the
  line already carries `tool`), and ADD `conversationId: ctx.conversationId` to that warn (CTO O3: an opaque id that
  `gateExpiredDeny` and the Sentry report already carry, so a member's "my email never sent" can be found in Better
  Stack without SSH). The new block comment must not quote the decision key, or the discoverability probe's count moves;
- KEEP the Sentry tag `stage: "legacy-push-owner-check"` and `extra.outcome: "denied-no-card"` byte for byte (the report
  carries `toolName`);
- reword the `logPermissionDecision` reason `` `push owner required (${role})` `` -> `` `owner required (${role})` ``
  (debug-only: `server/permission-log.ts` returns early unless `SOLEUR_DEBUG_PERMISSION_LAYER === "1"`, so no production
  history splits);
- reword the warn message -> "Platform tool gate refused: only the workspace Owner may approve an approval-required action
  when the approval flow gives no verdict";
- in `server/approval/ops.ts` (the `viewerRoleFailed` doc comment) and in the ADR addendum, say that both handles keep
  their push-era names and now cover every approval-required tool (#12597), told apart by `tool` / `toolName`.

1.4 `server/github-tools.ts` `github_trigger_workflow` description: "Requires founder approval via review gate." ->
"Requires the workspace Owner's approval." (CTO F5). `server/email-triage-tools.ts` (CTO F11): the `email_send`
description (`:296-297`, "the operator approves the exact recipient + body") and the `email_reply` description (`:356`,
"the operator approves") say that the workspace Owner approves; rewrite both `email_send` literals so the joined text
reads "the workspace Owner approves the exact recipient + body before it sends", and fix the comment at `:288`. The
leader system prompt at `server/agent-runner.ts:1656` ("All three are gated: the operator approves the exact recipient
and body before anything sends") gets the same change: the model reads the prompt as well as the tool description (learning
`2026-06-05-llm-facing-claim-correction-must-sweep-tool-desc-and-prompt-addendum.md`). Keep the rest of each sentence. The four
approval-required tool descriptions that name an approver then match (measured:
`git grep -n "approv" apps/web-platform/server/*-tools.ts`).

1.5 Comment-only sweeps (`git grep -n "12197 D1" apps/web-platform/server`, measured: 7 hits in 4 files, plus
`approval/tools.ts:30`, which says "#12197" without "D1"):
`agent-runner.ts:2263` ("(push: Owner only, #12197 D1)" -> "(Owner only, #12597)"); `permission-callback.ts` doc comments
of the `approval` and `approvalFailClosed` dependency fields (`:305`, `:314`, both "except `github_push_branch`, whose card
only the workspace Owner may answer"), the `readRoleBounded` doc comment (`:396`, "the legacy push card's Owner check"),
and the comment above the approval-flow call (`:1597`, Phase 1.1); `approval/gate-flow.ts:18` module comment (the "except
`github_push_branch`" clause now covers every approval-required tool); `approval/ops.ts:137` (Phase 1.3);
`approval/tools.ts` `GITHUB_PUSH_BRANCH_TOOL` doc comment (drop the claim that the Owner rule is push-specific; it is the
push tool's name, used by the cc push builder and the github tools). Each rewritten comment says every approval-required
tool's card is Owner-only (#12597). Checked by AC15.

### Phase 2 — Tests (write first: Phase 2.1 and 2.2 are RED on `main`'s source, GREEN after Phase 1)

2.1 `test/approval/legacy-push-owner-fallback.test.ts` (keep the file name: the battery FLOOR keys on it).

- Rewrite the header docblock (all eight tools; drop "narrow scope pin").
- Replace "the constant names the push tool" with a precondition (CTO F8, amended at plan review): `APPROVAL_REQUIRED_TOOLS`
  is non-empty; each member has `SAMPLES[tool].input` and `TOOL_TIER_MAP[tool] === "gated"`;
  `Object.keys(APPROVAL_EXEMPT_TOOLS)` is non-empty and disjoint from the list. No literal 8 here: Property 7 says a ninth
  tool needs no edit in this file, and `test/approval/tools-census.test.ts` already pins the exact set. No "the source
  array is the imported list" self-comparison either (it always passes); a hand-copied list is caught by AC5's grep and by
  the exact FLOOR.
- `describe("legacy fallback: only the Owner may answer the in-memory card for every approval-required tool (#12597)")`
  with `test.each(APPROVAL_REQUIRED_TOOLS)` (never a hand-copied array). Titles are load-bearing: the battery's `kill`
  names are substrings of them, so use exactly these (the `%s` is the full tool name):
  1. `"%s: Owner gets the card and the answer is honoured"` — two role reads (one when the card is issued, one after
     Approve, Phase 1.1b), one card, `abortableReviewGate` once, allow, no report, and one warn with
     `decision: "platform-gate-legacy-card-issued"` (CTO O4).
  2. `"%s: a member gets the static deny, with no card, status write or notification"` — `APPROVAL_UNAVAILABLE_DENY`, `expectNoWrites()`, warn with `decision: "platform-gate-push-owner-required"`, `role: "member"`, `conversationId` (CTO O3), and no `platform-gate-legacy-card-issued` warn.
  3. `"%s: the flag read throws and the user is a member: static deny, no card"` — `expectNoWrites()` and `viewerRole`
     called once (today's test asserts both), so the deny comes from the role check and not from a short-circuit on the
     flag error.
  4. `"%s: the flag read throws and the user is the Owner: the card is still emitted"` (CTO F6) — also assert
     `viewerRole` was called once, so the case cannot pass on a path that skips the role read.
  5. `"%s: the role read fails: static deny, no card, viewerRoleFailed reported with its stage"` — one report, op key `viewerRoleFailed`, context `objectContaining({ toolName: tool, workspaceId: WORKSPACE_ID, tags: { stage: "legacy-push-owner-check" }, extra: { outcome: "denied-no-card" } })` (keeps today's `workspaceId` pin), `logPermissionDecision(..., "deny", "owner required (unavailable)")`. The callback
     RESOLVES to the static deny: `await expect(call(...)).resolves.toEqual({ behavior: "deny", message: APPROVAL_UNAVAILABLE_DENY })`,
     so a throw out of the catch block cannot pass as a deny (learning `2026-06-04-per-cause-mint-fallback...`).
  6. `"%s: a role read that never settles ends at the deadline: static deny, viewerRoleFailed reported"` — fake timers.
     Start the call, attach `const settled = vi.fn(); pending.then(settled, settled)`, then
     `await vi.advanceTimersByTimeAsync(OWNER_ROLE_READ_DEADLINE_MS + 1); await vi.advanceTimersByTimeAsync(0)` (the second
     advance drains the deny chain) and assert `settled` was called with
     `{ behavior: "deny", message: APPROVAL_UNAVAILABLE_DENY }`, plus one report whose context matches the same
     `objectContaining({ toolName: tool, workspaceId: WORKSPACE_ID, tags: { stage: "legacy-push-owner-check" }, extra: { outcome: "denied-no-card" } })`
     as case 5 (AC14), and whose error carries `code: "role_read_timeout"` (CTO O1; case 5's report has no code, which
     is what tells them apart). `G1-LO5` is then killed by the `settled` assertion, not by a timeout (test-design review). Keep an
     explicit `2_000` ms test timeout only as a backstop, and `afterEach(() => vi.useRealTimers())` at file level.
  7. `"%s: no approval dependency: static deny, no card, reported as a wiring defect"` — exactly one report, op key `gateFailed`, context `objectContaining({ toolName: tool, extra: { stage: "wiring-absent" } })` (AC14).
  8. `"%s: Stop pressed while the role is read: denied as aborted, no card, no notification, no status write, no report"`
     — the abort is fired from inside `viewerRole` on the per-call `options.signal`. Assert `res.message` matches
     `/expired before it was answered/` and `log.warn` was called with
     `objectContaining({ decision: "platform-gate-aborted", reason: "aborted", delivered: false, stage: "owner-role-read" })` (the public contract
     `permission-callback-platform-gate-expiry.test.ts` already uses); `message !== APPROVAL_UNAVAILABLE_DENY` alone lets
     any other deny pass.
  9. `"%s: the session ends while the role is read: denied as aborted, no card, no notification, no status write, no report"`
     — as case 8 (same assertions), but the abort comes from `ctx.controllerSignal` (the session controller), not the
     per-call `options.signal`. Both signals are checked by the same `||`, and only a test per signal pins each operand.
     Today's `setup` builds `controllerSignal: new AbortController().signal` and keeps no handle, so `setup` gains a
     `controller` option (an `AbortController` whose signal becomes `ctx.controllerSignal`).
  10. `"%s: the Owner is demoted while the card waits: Approve is refused"` (CTO S1) — `viewerRole` answers `owner`, then
      `member`; the user answers Approve; the call resolves to `APPROVAL_UNAVAILABLE_DENY`, the stub handler did not run,
      `viewerRole` was called twice, and a warn with `decision: "platform-gate-push-owner-required"`, `role: "member"`,
      `stage: "on-answer"` was logged. In the same test, a second call answered Reject calls `viewerRole` only once (a
      Reject performs nothing, so it skips the re-read).
- `describe("legacy fallback: the pending-card cap holds across the role read (#12597, CTO F10)")`, one test (tool
  `APPROVAL_REQUIRED_TOOLS[0]`, read from the list): `"two Owner calls racing for the last pending slot: one card, one too-many-pending deny"`.
  Ruled by the CTO (F10b): the original "5 cards already open" form is denied by the first check before any await, so it
  could not kill the row. Harness requirements (test-design review):
  - ONE `createCanUseTool(ctx)` instance for all six calls. Today's `call` builds a new instance per call
    (`legacy-push-owner-fallback.test.ts:89-90`), and `pendingGates` is local to each instance, so six instances means six
    counters and the test would be RED on correct code. Extend `setup` to return the instance (or a `shared: true` option).
  - Each held gate is a deferred promise that rejects when its third argument (the call signal) aborts. Each of the six
    calls gets its own call `AbortController`.
  - Name the cap once: `const CAP = 5; // MAX_PENDING_GATES in permission-callback.ts (module-private)`.
  Steps, in this order, so a mutant fails on an assertion and never on the 16 s global timeout:
  1. start CAP - 1 = 4 holder calls (Owner role, answered at once) and
     `await vi.waitFor(() => expect(abortableReviewGate).toHaveBeenCalledTimes(4))`;
  2. start calls A and B whose `viewerRole` returns a deferred promise, and
     `await vi.waitFor(() => expect(viewerRole).toHaveBeenCalledTimes(6))` (both got past the first cap check);
  3. `dA.resolve("owner"); dB.resolve("owner")` in the same tick, then
     `await vi.waitFor(() => expect(cards().length).toBeGreaterThanOrEqual(5))`;
  4. FIRST assert `cards()` has length 5 and `abortableReviewGate` was called 5 times;
  5. then `const loser = await Promise.race([pA, pB])` resolves to a deny whose `message` matches
     `/^Too many approvals are already waiting/`, and `log.warn` was called exactly once in this test with
     `objectContaining({ decision: "platform-gate-too-many-pending" })`. Do not assert which of A or B lost;
  6. cleanup: abort all six call controllers and `await Promise.allSettled(...)` on the five held calls.
  `PLATFORM_GATE_TOO_MANY_PENDING_MESSAGE` and `MAX_PENDING_GATES` are module-private
  (`permission-callback.ts:365,369`): match the text, do not add an export. Explicit `2_000` ms timeout. Without the
  re-check there are 6 cards and step 4 fails.
- `describe("gated tools outside the approval-required set keep the in-memory card")`:
  `test.each(Object.keys(APPROVAL_EXEMPT_TOOLS))("%s: a member still gets the card and no role is read")`. Add the exempt
  names to the harness's `platformToolNames`; use a small synthesized input (`{ title: "t", body: "b" }`-shaped is enough:
  `buildPlainGateMessage` has a default arm). Every exempt tool goes through `buildPlainGateMessage`, which always
  returns a card (`tool-tiers.ts:576-590`), so one shared synthesized input is used and there is no per-tool map (a map
  keyed by tool name would also break AC5).
- Expected count: 1 precondition + 10 x 8 per-tool + 16 exempt + 1 cap race = 98. The FLOOR is the number the JSON
  report prints, not this estimate. (The Reject-skips-the-re-read assertion goes inside case 10 as a second call, not a
  separate test.)
- All harness changes (the shared instance, the `controller` option, deferred gates) stay inside this file; do not touch
  `test/approval/fixtures.ts`.

2.2 `test/approval/gate-flow.test.ts`: replace the filtered test.each at the "push tool is left out" comment with
`test.each(TOOL_NAMES)("%s: a disabled and a throwing flag read behave identically (an Owner gets today's card); absent is the unavailable deny")`:
off and boom transcripts equal each other, and EACH of them separately shows exactly one `review_gate` frame
(`expect(offT.frames).toEqual(["review_gate"])` and the same for `boomT`), one gate call, and that nothing of the
approval path ran (no submit, no `resolveServerDerived`, empty `rpcLog`, no waiter). Today the `review_gate` assertion sits
on the `absent` harness, which now becomes the deny, so it must move onto off and boom: under `G1-F2` both run the flow
and their transcripts still equal each other, so only these per-harness assertions kill it (Kieran review). `absent` returns
`{ behavior: "deny", message: APPROVAL_UNAVAILABLE_DENY }` with no frames. Update the comment above it. Count 7 -> 8.
Two existing battery rows name the OLD title as their detector: `G1-F1-flag-read-error-turns-flow-on` and
`G1-F2-flag-off-still-runs-the-flow` (kill `"absent, disabled and a throwing flag read behave identically"`). Change both
kill names to `"a disabled and a throwing flag read behave identically"` in the same commit (Phase 3.1). Under either
mutant the flow runs for the off or the boom harness in all eight cases, so every case the new substring matches fails
(the exact-count rule holds); keep the "one `review_gate` frame" and "nothing of the approval path ran" assertions, they
are what kills G1-F2 now that off is compared with boom instead of with absent.

2.3 `test/permission-callback-platform-gate-expiry.test.ts`: make `makeCtx` default to an Owner approval dep whose flag is
off (`{ isEnabled: async () => false, viewerRole: async () => "owner", grants: new ExecutionGrants() }`), still overridable
through `opts.extra`; drop the push-only special case in the "a gated tool outside the probed eight" test.each. The role
read adds no status write, so the status-lifecycle assertions are unchanged.

2.4 `test/approval/cc-approval-fail-closed.test.ts`, describe "approvalFailClosed UNSET": rename it to say the legacy
runner is NOT byte-identical any more; "approval absent" now asserts the unavailable deny, no card, and one wiring-absent
event; "flag off" keeps the card (the harness's viewer role must be the Owner; set it explicitly if the default is not).

2.5 The four `startAgentSession` files (`canusertool-tiered-gating`, `agent-runner-tools`, `agent-runner-kb-share-tools`,
`build-allowed-tools-census`): per file (CTO F3), after the shared rpc setup (`configureInstallationRpc(...)` in
`canusertool-tiered-gating.test.ts:258`; `createSupabaseMockImpl(..., { mockRpc })` in the other three, which calls it
internally at `helpers/agent-runner-mocks.ts:103`), capture `const base = mockRpc.getMockImplementation()` and re-install an
implementation that answers `is_workspace_owner` with `{ data: true, error: null }` and delegates every other RPC name to
`base` (the session user owns the workspace, as for every solo
founder). Give each override a one-line comment: "the legacy no-verdict card is Owner-only (#12597); the shared rpc mock
answers null for this RPC". Do NOT change `test/helpers/agent-runner-mocks.ts`. In `build-allowed-tools-census.test.ts` check first that the
change does not alter its count of 47 (it is in the battery FLOOR table).

In `canusertool-tiered-gating.test.ts` (not a FLOOR file), the override is strict: it answers `true` only when the RPC's
arguments name the fixture's workspace and user, and `{ data: false, error: null }` otherwise (spec-flow review). This
proves the production wiring passes the right workspace to the role read, which a blanket `true` cannot. Add one
`startAgentSession` case there in which `is_workspace_owner` answers `false` (a member): `create_pull_request` is denied
with `APPROVAL_UNAVAILABLE_DENY` and no `review_gate` frame is sent. The other three files keep the blanket `true`.

2.6 `test/github-tools-read-builder.test.ts`: one `it` pinning that the `github_trigger_workflow` description contains
"Requires the workspace Owner's approval." and not "founder approval" (not a battery FLOOR file). In the same file, or
in `test/server/email-triage-tools.test.ts` (the existing suite for that builder; not a FLOOR file), pin the
`email_send` and `email_reply` descriptions: each names the workspace Owner as the approver and no longer says
"the operator approves" (CTO F11). Assert on the JOINED description string (the `email_send` text is split across two
literals). Do not create a new test file.

2.6b `scripts/dev-probe-approval-gate.ts` (CTO F12): declare the stub as a TYPED value, not inside the
`as unknown as CanUseToolContext` cast (`:~289`), because `tsc` cannot check anything behind that cast:
`const approval: ApprovalGateDeps = { isEnabled: async () => false, workspaceId: "probe-ws", grants: new ExecutionGrants(), viewerRole: async () => "owner", resolveServerDerived: ..., submit: ..., readStatus: ..., consume: ... }`,
where each of the last four throws `new Error("probe: flag off, must not run")` (`ApprovalGateDeps`, `gate-types.ts:14-36`,
requires them). Then set `deps.approval = approval`. This puts all eight cases back on the in-memory card and the Reject
approver (`gateCalls > 0`), so the `:283` comment stays true. The stub must not add a second `return "Reject"; },` or
`seen.push(toolName);` (rows `P9` and `P11` anchor on them), and `--check-anchors` must still show each `P1`-`P11` anchor
exactly once. The probe needs a model and the network, so it is not run here.

2.7 The O4 warn line and the S1 re-read add one `log.warn` and one `viewerRole` call on every legacy card path. Any test
that asserts an exact `log.warn` count or an exact `viewerRole` call count on such a path moves by one: fix it in its file
and name it in the PR body; the Phase 2.7 run below enumerates them (measured blast of the predicate alone was 48 tests in
8 files; these two additions are not in that number).

Run every file above plus the unchanged neighbours that drive the callback (`canusertool-decisions`,
`approval/permission-callback-gated-branch`, `approval/gate-flow-payload`, `approval/gate-flow-requester`,
`approval/gate-flow-resolver-snapshot`, `approval/runner-census`, `approval/tools-census`) with the JSON reporter, and
record each file's passed count.

### Phase 3 — Mutation battery (`test/approval-guard1-mutation.test.sh`)

3.1 Add `T_LPO = "test/approval/legacy-push-owner-fallback.test.ts"` and a new row group comment
"# ---- 5b. The legacy runner's Owner check (#12597) ----" after section 5. Rows (anchors are the post-Phase-1 text;
`--check-anchors` proves each occurs exactly `count` times):

| Id | Edit (file `PC`) | Kill names (substrings of the full test name) | Notes |
|---|---|---|---|
| `G1-LO1-owner-check-narrowed-to-push` | `if (isApprovalRequiredTool(toolName)) {\n          let role` -> `if (toolName === "mcp__soleur_platform__github_push_branch") {\n          let role` | `mcp__soleur_platform__email_send: a member gets the static deny`, `mcp__soleur_platform__workspace_set_autonomous: a member gets the static deny` | `blast=` set from the MEASURED fraction (see below), not a planned one |
| `G1-LO2-unavailable-role-passes` | `if (role !== "owner") {` -> `if (role === "member") {` | `: the role read fails`, `: no approval dependency` | an unreadable role reaches the card |
| `G1-LO3-member-role-passes` | `if (role !== "owner") {` -> `if (role === "unavailable") {` | `: a member gets the static deny` | a member reaches the card |
| `G1-LO4-role-read-failure-allows` | `} catch (err) {\n              // An abort is not a failed read` -> same with `role = "owner";` inserted as the first statement | `: the role read fails` | the catch block allows |
| `G1-LO5-role-read-deadline-removed` | the multi-line `const timer = setTimeout(() => {` statement in `readRoleBounded` as it reads AFTER Phase 1.1 (its `reject(...)` now passes the Error carrying `code: "role_read_timeout"`), written byte for byte in `E(...)` with its 4-space indent (count 1) -> `const timer = undefined as unknown as ReturnType<typeof setTimeout>;` (same indent) | `: a role read that never settles ends at the deadline` | killed by case 6's `settled` assertion (the 2 s timeout is only a backstop) |
| `G1-LO6-abort-checked-after-the-role-deny` | ONE contiguous edit: the "Stop pressed (or the session ended) while the role was read" comment + its `if (... aborted) { return gateExpiredDeny(...) }` block + the whole `if (role !== "owner") { ... }` block that directly follows it (adjacent again after S3 moved the cap re-check after the role deny); the replacement is the same two blocks in reverse order. No `nth` (`const gateId = randomUUID();` occurs 5 times) | `: Stop pressed while the role is read`, `: the session ends while the role is read` | REORDER row (ORDER property 3); a delete-only row cannot see it |
| `G1-LO7-cap-not-rechecked-after-the-role-read` | the cap re-check block deleted. The anchor takes in the closing lines of the role-deny block just before it (its `return { behavior: "deny" as const, message: APPROVAL_UNAVAILABLE_DENY };` and closing brace), because `if (pendingGates >= MAX_PENDING_GATES) {` occurs twice after Phase 1 (count 1, proven by `--check-anchors`) | `racing for the last pending slot` | CTO F10, S3; 6 cards open instead of 5 |
| `G1-LO8-owner-check-matches-first-tool-only` | `if (isApprovalRequiredTool(toolName)) {\n          let role` -> `if (toolName === "mcp__soleur_platform__email_send") {\n          let role` | `mcp__soleur_platform__github_push_branch: a member gets the static deny`, `mcp__soleur_platform__workspace_set_autonomous: a member gets the static deny` | Guard matrix row 2: a compliant first member (`APPROVAL_REQUIRED_TOOLS[0]`), then the rest. Measured `blast=` as for `G1-LO1` |
| `G1-LO9-owner-check-widened-to-every-gated-tool` | `if (isApprovalRequiredTool(toolName)) {\n          let role` -> `if (true) {\n          let role` | `: a member still gets the card and no role is read` | over-widening direction (property 5): every exempt tool now reads the role and refuses the member. 16 of 98 fail, default blast. Raised by the test-design review and the learnings pass (`2026-09-04-a-10-of-10-mutation-score...`) |
| `G1-LO10-role-not-reread-after-approve` | the Phase 1.1b re-read block deleted (anchor: its unique comment line plus the block, count 1) | `: the Owner is demoted while the card waits` | CTO S1 (property 9); 8 of 98 fail, default blast |

Blast bound for `G1-LO1` and `G1-LO8` (advisor consult, then plan review): under either mutant, seven tools skip the role
read, so all ten per-tool cases fail for them. The Owner and flag-throws-Owner cases assert one role read. Both abort
cases trigger the abort from inside `viewerRole`, which never runs, so the card is shown. The others reach the card. That
is 7 x 10 = 70 of 98 (0.71) for `G1-LO8`, and 71 of 98 (0.72) for `G1-LO1`, whose push-only predicate also skips the
cap-race case's tool (`email_send`), so that case's "both role reads started" assertion fails too. Both are above the
default 0.5. Procedure: land both rows with `blast=0.80`, run
`--only 'G1-LO1|G1-LO8'`, read `failed/total` from each verdict detail, then set `blast=` to that fraction plus a margin of
0.05 (one more tool's worth), rounded UP to two decimals. Add a comment naming the measurement and the formula, e.g.
`# N/98 measured; = 10 cases x (tools - 1) / total + 0.05 margin`. CTO devex review: without the margin, the next tool added
to the list raises the fraction and reds this row from a PR that never touched it. The other eight rows stay at the
default 0.5. From the plan's case list, each fails at most 24 of 98: `G1-LO2` 24, `G1-LO3` 16 (24 if the work phase routes the 1.1b
answer-time check through the same comparison), `G1-LO4` 16, `G1-LO5` 8, `G1-LO6` 16, `G1-LO7` 1, `G1-LO9` 16, `G1-LO10` 8.

Also in 3.1: re-point the kill names of the existing rows `G1-F1` and `G1-F2` to the renamed gate-flow title (Phase 2.2).
Then `grep -n "behave identically" apps/web-platform/test/approval-guard1-mutation.test.sh` shows only the new substring.
Before committing, grep the battery for every other test title this plan renames or rewrites (the cc-approval-fail-closed
"approvalFailClosed UNSET" cases, the legacy file's old titles); today none of them is a kill name, and the check proves it
still holds.

Each `kill` substring must match only tests that fail under its mutant (the judge credits a title only when every case it
matches failed): `: a member gets the static deny` must not also match the flag-throws member case, whose title is
deliberately different.

3.2 Floors (each an exact count, from the reports of Phase 2.7 and the `--only` run):

| Literal | Before | After | Delta source |
|---|---|---|---|
| `FLOOR["test/approval/legacy-push-owner-fallback.test.ts"]` | absent | the file's passed count (expected 98) | new control file |
| `FLOOR["test/approval/gate-flow.test.ts"]` | 129 | 130 (expected) | Phase 2.2, 7 -> 8 cases; replace the "was 130" comment |
| `MIN_MUTANTS` | 356 | 366 | +10 rows (`G1-LO1`..`G1-LO10`); update its comment |
| `MIN_KILLED` | 350 | 360 | +10 must-kill rows |
| `MIN_CHECKS` | 763 | 784 | +1 control, +10 named-detector checks, +10 mutants; rewrite the derivation comment (19 harness + 36 controls + 360 named + harness b = 416; + 366 mutants + 2 = 784) |

`EXPECT_EQUIV=4` and `EXPECT_RESID=2` do not change. If any other FLOOR file's count moves (check
`build-allowed-tools-census` 47, `permission-callback-gated-branch` 3), set that floor to its new exact count too.

After the final commit, re-read every literal (`grep -n` each `FLOOR[...]` entry touched, `MIN_MUTANTS`, `MIN_KILLED`,
`MIN_CHECKS`), re-run the `--only` command of 3.3, and confirm each value equals the JSON pass count for its file and the
derivation comment recomputed from the row table, not this plan's 98 (learning
`2026-10-09-a-probe-loop-left-its-last-value-in-the-committed-floor...`: a probe loop's last value was committed as a floor).

3.3 Run locally, and only these: `bash apps/web-platform/test/approval-guard1-mutation.test.sh --check-anchors`, then
`bash apps/web-platform/test/approval-guard1-mutation.test.sh --only 'G1-LO|G1-F[12]-'` (it runs every control file,
then the ten new rows plus `G1-F1` and `G1-F2`, whose kill names move in this PR; expect 12 KILLED, exit 0). A row counts
as KILLED only when its verdict detail shows a `FAIL` line whose title contains one of its kill substrings; a
`floor/fatal` or timeout label, or a non-zero exit with no `FAIL` line, counts as SURVIVED however the summary prints it
(learning `2026-09-18-my-mutation-harness-counted-a-crash-as-a-kill...`). Never run the full battery locally; CI's
web-platform group runs it. Expected added CI time: about 2 min on the 12-15 min group (ten targeted runs of one file).

### Phase 4 — ADR-309 (append-only, CTO F7)

4.1 Add one forward pointer after the 2026-11-10 inline addendum, deleting nothing. That addendum ends partway through a
continuation line of the "Fail closed" bullet (the one ending "(the residual this bullet accepts; #12597).)*", which starts
with two spaces). Appending to that line would turn it into a `-`/`+` pair in the diff, so put the pointer on a NEW
two-space-indented continuation line right after it (Kieran review). Use the sibling inline note's form:
`*(Forward pointer, 2026-11-11, #12597, PR #12646; fires on the merge of the pull request that carries it: that residual is
closed; see the 2026-11-11 addendum below.)*`.

4.1b Rollback pointers (user-impact review): the sections an operator reads when rolling back would otherwise become
misleading. Add a new-line, additions-only pointer in the same form under `## Rollback and post-deploy verification`
("Rollback is: flag off, keep the schema") and after consequence (1) of `## Flag lifecycle` ("A flag read error on the FIRST
gated call of a turn takes the same path as flag off"). Each says: after #12597, flag off (fleet-wide or for one
workspace) refuses every member of a multi-member workspace for all eight approval-required tools and adds one role read
of up to 5 s per gated call; the log query `decision=platform-gate-push-owner-required role=member` measures it; an
app-only rollback to a pre-merge image is what reopens #12597. Then the AC9 numstat check still prints `0`.

4.2 Append `## Addendum — 2026-11-11 (Ref #12597, epic Ref #12197): the legacy no-verdict card is Owner-only for every
approval-required tool` after the 2026-11-09 "the legacy push is no longer byte-identical" addendum and before
`## Diagram`. Content: what changed (predicate, all eight tools), the fail-closed outcomes, abort, the 5 s bound
(`OWNER_ROLE_READ_DEADLINE_MS`), that the Sentry stage tag keeps its old value and the report's `toolName` names the tool,
that exempt gated tools are unchanged, the accepted cost (a solo Owner whose flag read AND role read both fail is refused
until a later conversation), the cap re-check
after the role read (CTO F10; the queue-on path's pre-existing gap is #12657), the effect on rollback (architecture
review: turning the flag off now refuses every member of a multi-member workspace for all eight tools, and adds one
`is_workspace_owner` read of up to 5 s per gated call; redeploying a pre-merge image is what reopens #12597), and the pins
(`test/approval/legacy-push-owner-fallback.test.ts`, battery rows `G1-LO1`..`G1-LO10`). Ruled by CTO agent, 2026-11-11.
Also state:

- the per-workspace flag override as a fourth trigger (Overview);
- that the "refused until a later conversation" cost comes from the deny copy ("Do not retry in this conversation"), not
  the mechanism: the role is read on every call, so a retry would work once the database recovers;
- that the Owner-only rule covers the eight listed approval-required tools, not repo or GitHub writes in general (the
  exempt list's reasons were not re-reviewed for this property; security review);
- only new facts. Do not describe the 2026-11-09 or 2026-11-10 conditions as already applied, and list the solo-Owner
  cost as open (learning
  `2026-11-10-a-copy-sentence-that-promises-enforcement-must-be-checked-on-every-runner-and-flag-state.md`);
- the answer-time role re-read (Phase 1.1b, CTO S1), which REPLACES the push-only demotion-while-waiting residual the
  2026-11-10 addendum accepted (so that residual is closed, not carried over);
- a second residual (CTO S2): the role is read for the workspace the session started in, while `kb_share_create` and
  `workspace_set_autonomous` re-resolve the workspace when they run, and the `legacy` grant kind binds no workspace. It
  gives no capability beyond the UI today (the autonomy RPC checks the Owner on the workspace it resolves; any member can
  already create a share in their active workspace); tracked in #12661.

4.3 `npx markdownlint-cli2 --fix` on ADR-309; confirm the diff on it is additions only (AC9: zero deleted lines in
`git diff --numstat`, whitespace included).

### Phase 5 — Verification and constraints

- `git diff --name-only origin/main...HEAD` contains nothing under `docs/legal/`, the Eleventy legal mirrors,
  `apps/web-platform/infra/sentry/`, and no edit of `apps/web-platform/server/legal-acceptance/texts/founder-acceptance-record.md`
(the only tracked file of that name; the brief calls it the knowledge-base record); its sha256 is
  `10d283e02d4543d291468750655bbaf4375f807a585cd5138724a362b993a287`; `LEGAL_COPY.PROVISIONAL` stays `true`.
- No production write; the approval-queue flag is not read, changed or scripted.
- `npx tsc --noEmit` in `apps/web-platform`.

## Files to Edit

- `apps/web-platform/server/permission-callback.ts`
- `apps/web-platform/server/approval/ops.ts` (doc comment)
- `apps/web-platform/server/approval/tools.ts` (doc comment)
- `apps/web-platform/server/approval/gate-flow.ts` (comment)
- `apps/web-platform/server/agent-runner.ts` (comment, and the email approver sentence in the leader prompt at `:1656`)
- `apps/web-platform/server/github-tools.ts` (trigger-workflow description)
- `apps/web-platform/server/email-triage-tools.ts` (`email_send`, `email_reply` descriptions)
- `apps/web-platform/scripts/dev-probe-approval-gate.ts` (stub Owner approval dependency, CTO F12)
- `apps/web-platform/test/approval/legacy-push-owner-fallback.test.ts`
- `apps/web-platform/test/approval/gate-flow.test.ts`
- `apps/web-platform/test/permission-callback-platform-gate-expiry.test.ts`
- `apps/web-platform/test/approval/cc-approval-fail-closed.test.ts`
- `apps/web-platform/test/canusertool-tiered-gating.test.ts`
- `apps/web-platform/test/agent-runner-tools.test.ts`
- `apps/web-platform/test/agent-runner-kb-share-tools.test.ts`
- `apps/web-platform/test/build-allowed-tools-census.test.ts`
- `apps/web-platform/test/github-tools-read-builder.test.ts`
- `apps/web-platform/test/server/email-triage-tools.test.ts`
- `apps/web-platform/test/approval-guard1-mutation.test.sh`
- `knowledge-base/engineering/architecture/decisions/ADR-309-durable-action-bound-approval-requests.md`

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-12597-legacy-owner-gate-all-approval-tools/decision-challenges.md` (decision record; created at plan time)
- `knowledge-base/project/specs/feat-one-shot-12597-legacy-owner-gate-all-approval-tools/tasks.md`

No new source or test file.

## Open Code-Review Overlap

Checked 95 open `code-review` issues against every planned path. Two mention a planned file for an unrelated concern:

- #3454 (pdf_metadata as an agent-callable MCP tool; names `agent-runner-tools.test`): Acknowledge. Different concern;
  this plan only adds an rpc override in that file.
- #3242 (tool_use WS event lacks a raw name field; names `server/agent-runner.ts`): Acknowledge. Different concern; this
  plan edits one comment in that file.

## User-Brand Impact

**If this lands broken, the user experiences:** either (a) a member of a multi-member workspace can still approve their
own outbound email, suppression, pull request, workflow run, public KB share or autonomy change while the approval queue
is off or its flag read fails, or (b) a solo founder (the Owner of their own workspace) has their email, PR, workflow,
KB-share and autonomy requests refused with "not performed, do not retry" whenever the queue falls back, or (c) after an
operator turns the flag off (fleet-wide rollback or a per-workspace override), every member of a multi-member workspace is
refused all eight approval-required tools for as long as it stays off.

Which tests pin each: (a) Phase 2.1 cases 2, 3, 5-9 for every tool, the strict-RPC member case in Phase 2.5, battery rows
`G1-LO1`-`G1-LO8` and `G1-LO10` (case 10, demotion while waiting), AC14, AC16; (b) cases 1 and 4 and the strict-RPC Owner case, plus the exempt cases and `G1-LO9` for the
tools that must keep the card; (c) is intended behaviour, disclosed in the ADR rollback pointers (Phase 4.1b) and the PR
body.

**If this leaks, the user's data / workflow is exposed via:** an email sent to a third party, a public share link to a
private KB document, a workflow run with repository secrets, or an autonomy flip, each approved by someone who is not
the workspace Owner.

**Brand-survival threshold:** single-user incident. One member-approved email or public share in a team workspace is
the incident. `requires_cpo_signoff: true`; `soleur:engineering:review:user-impact-reviewer` runs at review.

## Guard Contract

### Guard 1 — legacy no-verdict Owner check

**Property.** On the legacy runner, an approval-required tool that the approval flow gave no verdict for reaches the
in-memory card only when the session user's bounded role read returned `owner`; any other outcome is the static
unavailable deny with no card, status write or notification, and an abort during the read is the expired-gate deny. An
Approve on that card is honoured only if a second bounded role read, made after the answer, still returns `owner`.

**Assembly.** One chokepoint: the gated tier of `createCanUseTool` (`server/permission-callback.ts`), after
`runApprovalGate` returned `null` and the cc `approvalFailClosed` switch did not fire, before the single platform
`review_gate` emission (`const gateId = randomUUID();` that follows the Owner check). Membership is decided by one predicate,
`isApprovalRequiredTool` over `APPROVAL_REQUIRED_TOOLS` (`server/approval/tools.ts`); the role fact has one provider,
`approval.viewerRole()` (`server/approval/gate.ts`). The subagent path (`options.agentID`) passes the same branch. Exactly two production callers build `createCanUseTool`
(`git grep -n "createCanUseTool(" -- apps/web-platform/server apps/web-platform/app apps/web-platform/lib`):
`server/agent-runner.ts` (the legacy runner, always passes `approval: createApprovalGateDeps(...)`) and
`server/cc-dispatcher.ts` (sets `approvalFailClosed`, so it returns before this check). Two dev probes under `scripts/`
also call it and are not production: `dev-probe-approval-gate.ts` (given a stub dependency, Phase 2.6b) and
`dev-probe-destroy-ask.ts` (`platformToolNames: []`, unaffected). So no caller runs without the
dependency for Owners in normal operation. The
earlier exits (non-interactive, unreviewable input, pending cap) deny before it and are unchanged.

**Mutation matrix.** (Battery rows except where noted; each must turn the named tests RED.)

| # | Mutation (design-derived) | Must go RED |
|---|---|---|
| 1 | Dispatch narrowed: predicate back to the push tool only (`G1-LO1`) | member cases for the seven non-push tools |
| 2 | Second member after a compliant first: predicate matches only `APPROVAL_REQUIRED_TOOLS[0]` (`G1-LO8`) | member cases for every tool after the first, push included |
| 3 | Role comparison lets `unavailable` through (`G1-LO2`) | role-read-fails and no-dependency cases, all tools |
| 4 | Role comparison lets `member` through (`G1-LO3`) | member cases, all tools |
| 5 | The catch block sets `owner` (`G1-LO4`) | role-read-fails cases, all tools |
| 6 | The deadline is removed (`G1-LO5`) | never-settles cases, all tools (LIFETIME property) |
| 7 | REORDER: the abort check moved after the role deny (`G1-LO6`) | Stop-during-read and session-ends-during-read cases, all tools (ORDER property: the abort must be decided before the role) |
| 8 | The cap re-check after the role read removed (`G1-LO7`) | the cap-race case (property 8) |
| 9 | Over-widening: the Owner check applied to every gated tool (`G1-LO9`) | the exempt-tool member cases (property 5) |
| 10 | The answer-time role re-read removed (`G1-LO10`) | the demotion-while-waiting cases, all tools (property 9) |

**Harness rows.**

- Suite edit that must go RED: replacing either `test.each` source with a hand-copied shorter list drops the file's
  passed count below its exact FLOOR, and the battery's control run HALTs ("not green with at least N tests"). A
  hand-copied list of full length (literal names or fixture keys such as `TOOLS.emailSend`) is caught by AC5, which
  requires every `.each(` source in the file to be the imported list. No in-file assertion catches it.
- Must-PASS inputs that are not the canonical case: the Owner whose flag read throws still gets the card (case 4), and
  every exempt gated tool keeps the card for a member with no role read. A guard that denied everything would turn these RED.

**Anchor.** The FLOOR and MIN_* literals live in the same file as the rows, so one diff can lower both; they prove
consistency, not integrity. What must move outside the commit for a weakening to pass: the PR diff review of those literal
lines (any decrease is visible as a `-` line on a number), and set identity is held separately by
`test/approval/tools-census.test.ts` (the eight names, sorted, equal the fixtures' `TOOLS`) and by AC5's check that every
`.each(` source in the legacy file is the imported list, so a count-preserving substitution of the population fails there.

## Observability

```yaml
liveness_signal:
  what: "pino warn decision=platform-gate-legacy-card-issued (tool, role=owner, conversationId) each time the legacy fallback issues a card for an approval-required tool (CTO O4); Sentry op approval-viewer-role-failed (tag stage=legacy-push-owner-check) on a failed or timed-out role read; Sentry op approval-gate-failed (extra.stage=wiring-absent) on a missing dependency"
  cadence: "event-driven, per gated call that reaches the legacy fallback (rare: the approval-queue flag is ON in production)"
  alert_target: "Sentry issue stream for apps/web-platform, recorded, NOT paged (no rule matches either op; issue-alerts.tf has rules only for gate_unanswered and approval-key-unavailable); pino warns shipped to Better Stack by the Vector app-container source (level >= 40)"
  configured_in: "apps/web-platform/server/approval/ops.ts (op table), apps/web-platform/server/permission-callback.ts (call sites), apps/web-platform/infra/vector.toml (app_container_warn_filter, unchanged)"
error_reporting:
  destination: "Sentry via reportApprovalOp: warnSilentFallback (viewerRoleFailed, warning level) and reportSilentFallback (gateFailed, error level), each with its pino mirror (layer 2)"
  fail_loud: "yes: a failed role read and a missing dependency are reported; the call is denied, never allowed"
failure_modes:
  - mode: "role read RPC errors, returns a non-boolean, or the tenant is null (at card issue, or after Approve per Phase 1.1b)"
    detection: "Sentry captureMessage approval-viewer-role-failed with tags.stage=legacy-push-owner-check, toolName, extra.outcome=denied-no-card or denied-on-answer, no error code; plus its pino warn mirror (layer 2) shipped by the Vector app-container source"
    alert_route: "Sentry issue stream, recorded, not paged; Better Stack"
  - mode: "role read exceeds 5 s"
    detection: "the same Sentry event with code=role_read_timeout (CTO O1; describeError ships code), plus its pino mirror (layer 2) via Vector"
    alert_route: "Sentry issue stream, recorded, not paged; Better Stack"
  - mode: "approval dependency not wired on the legacy runner (blocks all eight tools for every user, Owners included)"
    detection: "Sentry captureMessage approval-gate-failed (error level) with extra.stage=wiring-absent and toolName, plus its pino error mirror (layer 2) via Vector"
    alert_route: "Sentry issue stream, recorded, not paged; own ops and a paging rule are follow-up #12664 (infra/sentry is out of scope here)"
  - mode: "member asks for an approval-required tool while the flow gives no verdict, or an Owner demoted while the card waited answers Approve"
    detection: "pino warn (layer 2) decision=platform-gate-push-owner-required, role, tool, conversationId (stage=on-answer for the answer-time refusal), shipped by the Vector app-container source. The logPermissionDecision reason is debug only (SOLEUR_DEBUG_PERMISSION_LAYER=1) and off in production"
    alert_route: "Better Stack logs (expected behaviour, not an alert)"
  - mode: "Stop pressed or the session ended during the role read"
    detection: "pino warn (layer 2) decision=platform-gate-aborted, delivered=false, stage=owner-role-read (stage=owner-role-answer during the answer-time read), conversationId, via Vector"
    alert_route: "Better Stack logs (expected behaviour, not an alert)"
  - mode: "a call that passed the first pending-card check finds the cap full after its role read"
    detection: "pino warn (layer 2) decision=platform-gate-too-many-pending with stage=after-role-read (CTO O2), via Vector"
    alert_route: "Better Stack logs (expected behaviour, not an alert)"
logs:
  where: "pino logger (sec: true) at warn or error, shipped to Better Stack by the Vector app-container source; logPermissionDecision lines are debug level and never shipped"
  retention: "Better Stack plan default (unchanged by this PR)"
discoverability_test:
  command: "grep -c platform-gate-legacy-card-issued apps/web-platform/server/permission-callback.ts"
  expected_output: "1"
```

The probe prints `0` on `main` and `1` after this change, so it tells the two apart (the earlier probe on
`platform-gate-push-owner-required` printed `1` on both, and now that the answer-time refusal reuses that key its count
also moves). The new block comment must not quote the probed key.

## Architecture Decision (ADR/C4)

### ADR

Amend ADR-309 (append-only): a forward pointer in the 2026-11-10 inline addendum and a new dated addendum section
(Phase 4). It extends the 2026-11-10 decision from one tool to the whole approval-required set; no new ADR, because the
decision (Owner-only no-verdict card on the legacy runner, reusing `viewerRole`) is unchanged in kind and only its scope
grows.

### C4 views

No C4 impact, checked against all three model files (`model.c4`, `views.c4`, `spec.c4`): external human actors (the
`founder` Owner actor already describes multi-Owner workspaces; a workspace member is not a separate actor and the change
removes a capability, it adds no access edge), external systems (none new: the role read is the existing
`is_workspace_owner` RPC on Supabase), containers and stores (`approvalStore` and its `webapp`/`engine` edges describe
the queue-on path, which is unchanged; nothing models the legacy in-memory card), and actor-to-surface relationships (no
edge grants a member approval). `bash plugins/soleur/test/c4-count-parity.test.sh` ran green on 2026-11-11 (13 passed,
0 failed); the work phase re-runs it.

### Sequencing

None: the ADR addendum describes the state on merge.

## Acceptance Criteria

### Pre-merge (PR)

- [x] AC1 `git grep -n "toolName === GITHUB_PUSH_BRANCH_TOOL" apps/web-platform/server` returns nothing, and the legacy
  block's predicate is `isApprovalRequiredTool(toolName)` (`grep -c "if (isApprovalRequiredTool(toolName)) {" apps/web-platform/server/permission-callback.ts` prints `1`).
- [x] AC2 `git grep -n "Other approval-required tools keep the" apps/web-platform` returns nothing.
- [x] AC3 `git grep -n PUSH_ROLE_READ_DEADLINE_MS -- apps` returns nothing; `OWNER_ROLE_READ_DEADLINE_MS = 5_000` exists.
- [x] AC4 Both query handles are kept (CTO F1'): `git grep -c "legacy-push-owner-check" apps/web-platform/server/permission-callback.ts`
  and `git grep -c "platform-gate-push-owner-required" apps/web-platform/server/permission-callback.ts` each print the
  number of call sites (2 each: card issue and answer time, Phase 1.1b; 1 each if the work phase routes both through one
  helper), never 0; `git grep -n "push owner required" apps/web-platform/server` returns nothing (reason reworded).
- [x] AC5 `apps/web-platform/test/approval/legacy-push-owner-fallback.test.ts` iterates `APPROVAL_REQUIRED_TOOLS` and
  `APPROVAL_EXEMPT_TOOLS` by import, and nothing else: with `F=apps/web-platform/test/approval/legacy-push-owner-fallback.test.ts`,
  `grep -cE '\.each\((APPROVAL_REQUIRED_TOOLS|Object\.keys\(APPROVAL_EXEMPT_TOOLS\))\)' "$F"` equals
  `grep -cE '\.each\(' "$F"` and is at least 2; `grep -cE '\bTOOLS\.|mcp__soleur_platform__' "$F"` prints `0`. Its JSON
  report shows every case passed, and that count is the FLOOR. (The old literal-only grep already printed 0 on today's file,
  which names tools by fixture key, so it could not fail.)
- [x] AC6 The eight files listed in the probe table pass, with the per-file fixes in Phase 2.3-2.5; `test/helpers/agent-runner-mocks.ts` is unchanged (`git diff --quiet origin/main...HEAD -- apps/web-platform/test/helpers/agent-runner-mocks.ts`, merge-base form so a sibling merge to main cannot flip it).
- [x] AC7 RED-before-GREEN, isolated to the predicate: with Phase 1.2-1.5 and the cap re-check applied and only the 1.1
  predicate still `toolName === GITHUB_PUSH_BRANCH_TOOL`, the ten per-tool cases fail for the seven non-push tools and pass
  for the push tool. (Before 1.2-1.3 the push cases also fail, on the renamed constant and the reworded reason, so that run
  cannot show the predicate is tested.) Then the cap-race case fails with the re-check removed and passes with it. After
  Phase 1 everything passes.
- [ ] AC8 Battery: `--check-anchors` exits 0, and the probe rows `P1`-`P11` still find their anchors after Phase 2.6b;
  `--only 'G1-LO|G1-F[12]-'` exits 0 with `killed=12`, each KILLED backed by a `FAIL` line naming a kill substring; the
  FLOOR entry for the legacy file equals its control passed count;
  `MIN_MUTANTS=366`, `MIN_KILLED=360`, `MIN_CHECKS=784` (or the exact values the
  derivation gives if any other count moved, with the comment showing the arithmetic); CI's web-platform group runs the full
  battery green.
- [x] AC8b The existing rows `G1-F1` and `G1-F2` name `"a disabled and a throwing flag read behave identically"`, and
  every `kill` substring in the battery is among the control-passed names (the control's own check; proven by the
  `--only` run of AC8, which checks every row's names and runs `G1-F1` and `G1-F2` themselves).
- [x] AC9 `git diff --numstat origin/main...HEAD -- knowledge-base/engineering/architecture/decisions/ADR-309-durable-action-bound-approval-requests.md | awk '{print $2}'` prints `0` (zero deleted lines; the old `^-[^-]` grep skipped deleted bullets and blank lines).
- [x] AC10 `server/github-tools.ts` contains "Requires the workspace Owner's approval." twice (push and trigger) and no
  "founder approval via review gate"; pinned in `github-tools-read-builder.test.ts`. `git grep -n "operator approves" apps/web-platform/server`
  returns nothing (without the leading "the", so it also catches the `email_send` text split across two literals at
  `email-triage-tools.ts:296-297`; measured today: 3 hits, `agent-runner.ts:1656`, `email-triage-tools.ts:297`, `:356`); the leader-prompt sentence at `agent-runner.ts:1656` names the workspace Owner; the
  joined `email_send` and `email_reply` descriptions name the workspace Owner, pinned in
  `test/server/email-triage-tools.test.ts` (CTO F11).
- [x] AC11 No change under `docs/legal/`, the Eleventy legal mirrors or `apps/web-platform/infra/sentry/`;
  `sha256sum apps/web-platform/server/legal-acceptance/texts/founder-acceptance-record.md` equals `10d283e02d4543d291468750655bbaf4375f807a585cd5138724a362b993a287`;
  `LEGAL_COPY.PROVISIONAL` is still `true`; `lib/web-egress-disclosure.ts` is unchanged.
- [x] AC12 `npx tsc --noEmit` passes; markdownlint-cli2 passes on every touched `.md`.
- [ ] AC13 PR body contains `Closes #12597` and `Ref #12197`; no feature tweet; neither the PR body nor the ADR addendum
  claims gate (j) of the #12365 ruling is discharged; the PR body has one line on the rollback effect (flag off, fleet-wide
  or per workspace, refuses members for all eight tools). AC9 also holds for the Phase 4.1b pointers.
- [x] AC14 (CPO condition) For every approval-required tool the legacy test asserts: a failed role read and a timed-out
  role read each produce exactly one `viewerRoleFailed` report whose context carries `toolName` equal to the tool,
  `workspaceId`, and `tags.stage` `legacy-push-owner-check`; a missing dependency produces exactly one `gateFailed` report with
  `toolName` equal to the tool and `extra.stage` `wiring-absent`. These reach Sentry through `reportApprovalOp` ->
  `warnSilentFallback` (`viewerRoleFailed`, warning level) or `reportSilentFallback` (`gateFailed`, error level), the
  existing sinks pinned by `test/approval/approval-ops-real-sink.test.ts`.
- [x] AC15 The push-only comment sweep is complete: ``git grep -n 'except `github_push_branch`' apps/web-platform/server``
  and `git grep -n "push: Owner only" apps/web-platform/server` both return nothing (Phase 1.5).
- [x] AC16 (CTO F10, S3) `grep -c "if (pendingGates >= MAX_PENDING_GATES) {" apps/web-platform/server/permission-callback.ts`
  prints `2`, and the second one sits after the role deny (the member-deny case at the cap logs
  `platform-gate-push-owner-required`, not `platform-gate-too-many-pending`). The legacy test's cap-race case shows exactly one new card and one too-many-pending deny, after asserting that
  both role reads started. Follow-up #12657 is open for the queue-on path.
- [x] AC17 (CTO F12) `scripts/dev-probe-approval-gate.ts` declares `const approval: ApprovalGateDeps = {...}` as a typed
  value outside the context cast (`grep -c "const approval: ApprovalGateDeps" apps/web-platform/scripts/dev-probe-approval-gate.ts`
  prints `1`), with `viewerRole` answering `owner` and the flag off, and `npx tsc --noEmit` passes. The probe itself is
  not run here (it needs a model and the network).
- [x] AC18 (CTO S1) Every approval-required tool's demotion case (Phase 2.1 case 10) passes; `G1-LO10` is KILLED.
- [x] AC19 (CTO O1-O4) The timeout report carries `code: "role_read_timeout"` (case 6); the re-check warn carries
  `stage: "after-role-read"`; the abort-during-read warn carries `stage: "owner-role-read"`; the member-deny warn carries
  `conversationId`; `grep -c platform-gate-legacy-card-issued apps/web-platform/server/permission-callback.ts` prints `1`.
- [x] AC20 (CTO U1, pre-merge, run by the agent, read-only) Count Better Stack events with
  `decision=platform-gate-push-owner-required` and `role=member` since #12567 merged (ddc35e5a64). If 0, record "0 (weak
  evidence: the flag is on in production)" in the PR body and do no database read. For each hit, map `repo` to its
  workspace and count that workspace's members with Supabase REST GETs using the prd service-role key sent through curl
  `--config -` on stdin (preflight Check 1's pattern): `workspaces?select=id&repo_url=ilike.*<owner>/<repo>`, then
  `workspace_members?select=role&workspace_id=eq.<id>`. GET only; never `DATABASE_URL` or psql. Record only counts,
  never names or emails. STOP the merge if any hit is in a single-member workspace (a real Owner was misread as a
  member), or if a repo maps to 0 or more than 1 workspace or a read fails (unverified). Amended by the CTO agent,
  2026-11-11 (decision-challenges.md, row "AC20 mechanism").
  Measured 2026-11-11 about 18:30Z: 0 events across the hot table and the s3 archive since 2026-11-10 18:00:47Z (69,891 rows); positive control: `permission`-context warn lines reach the archive (2026-10-19 09:15Z). Recorded "0 (weak evidence: the flag is on in production)"; no database read.

### Post-merge (operator)

None. No production write, flag change or deploy step is part of this change beyond the normal release.

## Domain Review

**Domains relevant:** Engineering, Legal, Product

### Engineering

**Status:** reviewed
**Assessment:** CTO ruling of 2026-11-11 (the brief) plus rulings F1'-F12 (F1' replaces F1, F10b corrects F10) on this
plan's forks, recorded in `decision-challenges.md`. Plan review: DHH, Kieran, code-simplicity, architecture-strategist,
spec-flow and the CTO devex lens, plus a sharp-edges pass. Mechanical findings are applied; the rest are recorded in the
decision file.

### Legal

**Status:** reviewed
**Assessment:** CLO (2026-11-11): discharged; no legal document, disclosure or compliance record changes. PUSH_DISCLOSURE
stays accurate (it makes no claim about the other seven tools). Privacy Policy 4.15, GDPR Policy 3.17 and DPD 2.3(ah)
describe only the durable queue, never the in-memory fallback, so nothing published is falsified; the Terms' "you
authorize each instance", Article 30 PA-28 TOM (1) and PA-38 (d) still fit. Do NOT claim in the PR body or the ADR
addendum that this discharges gate (j) of the #12365 ruling ("single-member workspaces only"): that gate is about the
durable queue. Optional, not in scope: a merge-conditioned one-line note on the #11303 row of
`knowledge-base/legal/compliance-posture.md`.

### GDPR gate (plan-skill Phase 2.7)

Invoked on trigger (b), the single-user-incident threshold. None of the planned paths match the canonical
regulated-data regex. The five v1 checks (Art. 6, Art. 5(1)(e), Art. 17 and its caller-site check, Chapter V, Art. 9)
found nothing: no schema, migration, foreign key, vendor or new processing. The output is advisory, and it is not
legal review.

### Product/UX Gate

**Tier:** none (no UI file in Files to Edit; the mechanical UI-surface override does not fire)
**Decision:** reviewed; CPO plan-time sign-off given with one condition (below)
**Agents invoked:** soleur:product:cpo
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

#### Findings

CPO (2026-11-11), signed off with conditions. Keep `APPROVAL_UNAVAILABLE_DENY` as is: do not add "ask the Owner", because
the in-memory card lives in the member's own session and the Owner has nothing to approve there. The fail-closed cost for
solo Owners (flag read and role read failing together, most likely one shared database outage) is acceptable at this
threshold: a wrongly allowed email or public share cannot be undone, a refused action can be retried. Condition: a failed
or timed-out role read and a missing dependency must each reach Sentry with the tool name and reason. They do, through
`reportApprovalOp` (`server/approval/ops.ts`), which forwards `ctx.toolName` as the `tool` field and calls
`warnSilentFallback` (Sentry, warning level) for a failed or timed-out read, and `reportSilentFallback` (error level)
for a missing dependency; AC14 and test cases 5-7 pin it for every tool.

## Test Scenarios

- Owner, flag off: card, Approve allows (all 8 tools).
- Member, flag off: static deny, nothing written (all 8).
- Flag read throws: member denied, Owner gets the card (all 8).
- Role read throws / non-boolean / null tenant: static deny, `viewerRoleFailed` with stage and tool (all 8).
- Role read never settles: deny at 5 s, reported (all 8).
- No dependency: deny, `gateFailed` wiring-absent (all 8).
- Stop during the role read: expired deny, no report, nothing written (all 8).
- Session ends (controller abort) during the role read: expired deny, no report, nothing written (all 8).
- Four cards open, two Owner calls finish their role reads together: one new card, one too-many-pending deny.
- `startAgentSession` (tiered-gating file): the Owner RPC answers `true` only for the fixture workspace and user; a member
  (`false`) is denied `create_pull_request` with no card.
- Exempt gated tool, member: card, no role read (all 16).
- cc dispatcher (`approvalFailClosed`): unchanged, returns before the legacy check (existing `cc-approval-fail-closed` cases).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan` Phase 4.6.
- Kill names are substrings of full test names. Changing a test title after the rows land makes the control run report
  "a named detector test is not among the passed tests" and fails the battery. Copy the titles from Phase 2.1 exactly.
  This applies to EXISTING rows too: renaming the gate-flow dormancy test orphans `G1-F1` and `G1-F2` unless their kill
  names move with it (Phase 2.2 / 3.1).
- The never-settles case uses fake timers; a mutant that removes the deadline leaves that promise pending forever. Its
  `settled` assertion fails first (the kill); the file-level `afterEach(() => vi.useRealTimers())` and the 2 s backstop
  timeout keep the hang from leaking into later cases (which would turn a KILLED into UNRESOLVED via the blast bound).
- The cap-race case needs ONE `createCanUseTool` instance: the pending counter is per instance, and today's harness makes a
  new one per call.
- `const gateId = randomUUID();` occurs 5 times in `permission-callback.ts` (measured with `grep -c`); the reorder row
  must not anchor on it. `G1-LO6` is one contiguous edit over the abort block, the cap re-check and the role-deny block,
  verified by `--check-anchors`.
- `G1-LO1` and `G1-LO8` fail most of the file by design; a guessed `blast=` reads UNRESOLVED (exit 3). Measure it (Phase 3.1).
- After Phase 1, `if (pendingGates >= MAX_PENDING_GATES) {` occurs twice. `G1-LO7`'s anchor must include the line before
  the re-check, or `--check-anchors` reports a count of 2.
- The cap re-check is correct only while nothing is awaited between it and `holdForUser`'s `pendingGates++`. A later
  change that adds an await there (for example awaiting `notifyOfflineUser`) reopens the race, and the cap-race test is
  what catches it.
- The G1-F2 kill depends on the off and boom harnesses each asserting one `review_gate` frame and no submit. Their
  transcripts equal each other under that mutant, so the equality check alone does not kill it (Phase 2.2).
- Floors are lower bounds compared with `-lt`; a floor above the real count voids the battery (the #12567 CI failure),
  a floor below it hides a dropped case. Set each to the exact JSON count.
- `build-allowed-tools-census.test.ts` is a FLOOR file (47): the rpc override must not add or remove a test there.
- A future `startAgentSession` test that calls an approval-required tool will be denied ("not performed, do not retry")
  because the shared rpc mock answers `is_workspace_owner` with null. That is the fail-closed default working: add the
  per-file Owner override, do not change the helper.
