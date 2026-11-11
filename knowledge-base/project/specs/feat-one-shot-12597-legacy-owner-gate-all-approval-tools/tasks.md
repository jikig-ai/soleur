---
title: "Tasks: Owner-only legacy approval card for every approval-required tool"
issue: 12597
branch: feat-one-shot-12597-legacy-owner-gate-all-approval-tools
plan: knowledge-base/project/plans/2026-11-11-security-legacy-owner-gate-all-approval-tools-plan.md
lane: single-domain
---

# Tasks: Owner-only legacy approval card for every approval-required tool (#12597)

Plan: `knowledge-base/project/plans/2026-11-11-security-legacy-owner-gate-all-approval-tools-plan.md`.
Decisions: `decision-challenges.md` in this directory.

## 1. Tests first (RED on the current source)

- [x] 1.0 Do the Phase 1.2-1.3 renames first (constant, reason, warn text), so the RED run isolates the predicate (AC7).
- [x] 1.1 Rewrite `apps/web-platform/test/approval/legacy-push-owner-fallback.test.ts` per plan Phase 2.1: the precondition,
  ten per-tool cases over `APPROVAL_REQUIRED_TOOLS` with the exact titles (including the session-ends and the
  demotion-while-waiting cases), exempt-tool cases over `APPROVAL_EXEMPT_TOOLS` (one shared input), and the cap-race case
  (ONE `createCanUseTool` instance, 4 held cards, 2 deferred Owner role reads, `vi.waitFor` sync points, CTO F10b). Add a
  `setup` `controller` option, the `settled` assertion in case 6 (with `code: "role_read_timeout"`), and the aborted-warn
  assertions in cases 8-9. File-level `afterEach(() => vi.useRealTimers())`. Expected 98 tests.
- [x] 1.2 Rewrite the gate-flow dormancy test.each over all eight tools (plan Phase 2.2). Off and boom EACH assert one
  `review_gate` frame and no submit.
- [x] 1.3 Run both files with only the predicate unwidened: the ten per-tool cases fail for the seven non-push tools,
  the push cases pass (AC7). Run the cap-race case without the re-check: it fails.

## 2. Source

- [x] 2.1 `server/permission-callback.ts`: predicate to `isApprovalRequiredTool(toolName)`; new block comment; delete the
  "Other approval-required tools keep the in-memory card" sentence; cap re-check AFTER the role deny (CTO F10, S3) with
  `stage: "after-role-read"`; `stage: "owner-role-read"` on the abort; the `platform-gate-legacy-card-issued` warn (O4);
  the timeout Error gets `code: "role_read_timeout"` (O1); drop the `GITHUB_PUSH_BRANCH_TOOL` import; update the comment
  above the approval-flow call (Phase 1.1).
- [x] 2.1b Re-read the role after Approve when the widened block admitted the call (Phase 1.1b, CTO S1).
- [x] 2.2 Rename `PUSH_ROLE_READ_DEADLINE_MS` to `OWNER_ROLE_READ_DEADLINE_MS` (Phase 1.2).
- [x] 2.3 Log decision / reason / message renames; keep the Sentry stage tag; add `conversationId` to the member-deny
  warn (O3); `ops.ts` doc comment (Phase 1.3).
- [x] 2.4 `github_trigger_workflow` description; `email_send` / `email_reply` descriptions (both literals of
  `email_send`) and the `agent-runner.ts:1656` leader-prompt sentence (Phase 1.4, CTO F5, F11).
- [x] 2.5 Comment sweeps: `agent-runner.ts`, `permission-callback.ts:305,:314,:396`, `approval/gate-flow.ts`,
  `approval/ops.ts`, `approval/tools.ts` (Phase 1.5, AC15).
- [x] 2.6 `scripts/dev-probe-approval-gate.ts`: typed `const approval: ApprovalGateDeps` stub, Owner, flag off, the
  four flow functions throwing (Phase 2.6b, CTO F12).

## 3. Remaining red suites

- [x] 3.1 `permission-callback-platform-gate-expiry.test.ts`: default Owner approval dep in `makeCtx` (Phase 2.3).
- [x] 3.2 `approval/cc-approval-fail-closed.test.ts`: the "approvalFailClosed UNSET" cases (Phase 2.4).
- [x] 3.3 Per-file `is_workspace_owner -> true` override in `agent-runner-tools`, `agent-runner-kb-share-tools`,
  `build-allowed-tools-census`; a STRICT override (fixture workspace and user only) plus a member case in
  `canusertool-tiered-gating` (Phase 2.5); shared helper unchanged.
- [x] 3.4 Description pins: `github-tools-read-builder.test.ts` (trigger) and `test/server/email-triage-tools.test.ts`
  (email_send, email_reply) (Phase 2.6).
- [x] 3.5 Fix any exact `log.warn` / `viewerRole` call-count assertion moved by O4 or S1 (Phase 2.7), then run every
  file in plan Phase 2.7 with the JSON reporter and record each passed count.

## 4. Mutation battery

- [ ] 4.1 Add rows `G1-LO1`..`G1-LO10` and `T_LPO`; re-point `G1-F1` / `G1-F2` kill names (Phase 3.1).
- [ ] 4.2 `--check-anchors` (P1-P11 included); then `--only 'G1-LO1|G1-LO8'` at `blast=0.80` to measure; set each `blast=`
  to the measured fraction + 0.05.
- [ ] 4.3 Set the FLOOR entries (legacy file: its JSON count, expected 98), `MIN_MUTANTS` 366, `MIN_KILLED` 360,
  `MIN_CHECKS` 784 and their comments to exact values (Phase 3.2); re-read every literal after the final commit.
- [ ] 4.4 `--only 'G1-LO|G1-F[12]-'`: twelve KILLED, each backed by a `FAIL` line naming a kill substring, exit 0. Do not
  run the full battery locally.

## 5. ADR and records

- [x] 5.1 ADR-309: forward pointer on a NEW indented line after the 2026-11-10 inline addendum; new
  `## Addendum — 2026-11-11` section before `## Diagram`, including the cap re-check, #12657, the answer-time re-read,
  the #12661 residual and the rollback effect (Phase 4.2); rollback pointers under `## Rollback and post-deploy
  verification` and `## Flag lifecycle` (Phase 4.1b). Additions only (AC9, `--numstat`).
- [x] 5.2 Re-run `bash plugins/soleur/test/c4-count-parity.test.sh`.
- [x] 5.3 markdownlint-cli2 on every touched `.md`.

## 6. Verification

- [ ] 6.1 AC1-AC20 of the plan. AC20 is a read-only pre-merge production check (Better Stack count, then a DB member
  count per hit) that the agent runs itself; record only counts.
- [ ] 6.2 `npx tsc --noEmit` in `apps/web-platform`.
- [ ] 6.3 PR body: `Closes #12597`, `Ref #12197`; no gate (j) discharge claim; no feature tweet; one rollback-effect
  line; the AC20 result; the follow-ups #12657, #12660-#12664.
