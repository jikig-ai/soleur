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

- [ ] 1.0 Do the Phase 1.2-1.3 renames first (constant, reason, warn text), so the RED run isolates the predicate (AC7).
- [ ] 1.1 Rewrite `apps/web-platform/test/approval/legacy-push-owner-fallback.test.ts` per plan Phase 2.1: the precondition,
  nine per-tool cases over `APPROVAL_REQUIRED_TOOLS` with the exact titles (including the session-ends case), exempt-tool
  cases over `APPROVAL_EXEMPT_TOOLS`, the cap-race case (4 open cards, 2 deferred Owner role reads, CTO F10b),
  file-level `afterEach(() => vi.useRealTimers())`, and a 2 s timeout on the never-settles case. Expected 90 tests.
- [ ] 1.2 Rewrite the gate-flow dormancy test.each over all eight tools (plan Phase 2.2). Off and boom EACH assert one
  `review_gate` frame and no submit.
- [ ] 1.3 Run both files with only the predicate unwidened: the nine per-tool cases fail for the seven non-push tools,
  the push cases pass (AC7). Run the cap-race case without the re-check: it fails.

## 2. Source

- [ ] 2.1 `server/permission-callback.ts`: predicate to `isApprovalRequiredTool(toolName)`; new block comment; delete the
  "Other approval-required tools keep the in-memory card" sentence; cap re-check after the abort check (CTO F10); drop
  the `GITHUB_PUSH_BRANCH_TOOL` import; update the comment above the approval-flow call (Phase 1.1).
- [ ] 2.2 Rename `PUSH_ROLE_READ_DEADLINE_MS` to `OWNER_ROLE_READ_DEADLINE_MS` (Phase 1.2).
- [ ] 2.3 Log decision / reason / message renames; keep the Sentry stage tag; `ops.ts` doc comment (Phase 1.3).
- [ ] 2.4 `github_trigger_workflow` description; `email_send` / `email_reply` descriptions (Phase 1.4, CTO F5, F11).
- [ ] 2.5 Comment sweeps: `agent-runner.ts`, `permission-callback.ts:305,:314,:396`, `approval/gate-flow.ts`,
  `approval/ops.ts`, `approval/tools.ts` (Phase 1.5, AC15).
- [ ] 2.6 `scripts/dev-probe-approval-gate.ts`: stub Owner approval dependency, flag off (Phase 2.6b, CTO F12).

## 3. Remaining red suites

- [ ] 3.1 `permission-callback-platform-gate-expiry.test.ts`: default Owner approval dep in `makeCtx` (Phase 2.3).
- [ ] 3.2 `approval/cc-approval-fail-closed.test.ts`: the "approvalFailClosed UNSET" cases (Phase 2.4).
- [ ] 3.3 Per-file `is_workspace_owner -> true` override in `agent-runner-tools`, `agent-runner-kb-share-tools`,
  `build-allowed-tools-census`; a STRICT override (fixture workspace and user only) plus a member case in
  `canusertool-tiered-gating` (Phase 2.5); shared helper unchanged.
- [ ] 3.4 Description pins: `github-tools-read-builder.test.ts` (trigger) and `test/server/email-triage-tools.test.ts`
  (email_send, email_reply) (Phase 2.6).
- [ ] 3.5 Run every file in plan Phase 2.7 with the JSON reporter; record each passed count.

## 4. Mutation battery

- [ ] 4.1 Add rows `G1-LO1`..`G1-LO8` and `T_LPO`; re-point `G1-F1` / `G1-F2` kill names (Phase 3.1).
- [ ] 4.2 `--check-anchors` (P1-P11 included); then `--only 'G1-LO1|G1-LO8'` at `blast=0.80` to measure; set each `blast=`
  to the measured fraction + 0.05.
- [ ] 4.3 Set the FLOOR entries (legacy file: its JSON count, expected 90), `MIN_MUTANTS` 364, `MIN_KILLED` 358,
  `MIN_CHECKS` 780 and their comments to exact values (Phase 3.2).
- [ ] 4.4 `--only 'G1-LO|G1-F[12]-'`: ten KILLED, exit 0. Do not run the full battery locally.

## 5. ADR and records

- [ ] 5.1 ADR-309: forward pointer on a NEW indented line after the 2026-11-10 inline addendum; new
  `## Addendum — 2026-11-11` section before `## Diagram`, including the cap re-check, #12657 and the rollback effect
  (Phase 4). Additions only (AC9, `--numstat`).
- [ ] 5.2 Re-run `bash plugins/soleur/test/c4-count-parity.test.sh`.
- [ ] 5.3 markdownlint-cli2 on every touched `.md`.

## 6. Verification

- [ ] 6.1 AC1-AC17 of the plan.
- [ ] 6.2 `npx tsc --noEmit` in `apps/web-platform`.
- [ ] 6.3 PR body: `Closes #12597`, `Ref #12197`; no gate (j) discharge claim; no feature tweet.
