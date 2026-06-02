# Tasks — fix interactive `messages` workspace_id RLS INSERT

Plan: `knowledge-base/project/plans/2026-06-02-fix-interactive-messages-workspace-id-rls-insert-plan.md`

## Phase 1 — RED (failing tests first)

- [x] 1.1 Reuse the EXISTING capture seam: `cc-dispatcher-harness.ts:116-118,143-145` already spies `messages.insert` via `opts.mockMessagesInsert`; `cc-dispatcher.test.ts:1085-1091` already reads `insertMock.mock.calls`. Ensure conversation mock returns a `workspace_id`. Mirror for agent-runner via `agent-runner-mocks.ts`. (No new mock infra.)
- [x] 1.2 T1 — cc-dispatcher user-row INSERT asserts `workspace_id` == conversation's `workspace_id`. (RED)
- [x] 1.3 T2 — cc-dispatcher assistant-row INSERT (via `buildRow`/1572) asserts `workspace_id`. (RED)
- [x] 1.4 T3 — agent-runner `saveMessage` INSERT asserts `workspace_id`. (RED)
- [x] 1.5 T4 — agent-runner `sendUserMessage` INSERT asserts `workspace_id`. (RED)
- [x] 1.6 T5 — source-grep sweep test: every `.from("messages").insert` in `apps/web-platform/server/` has a `workspace_id` key; negative-control fixture proves non-vacuous. (RED)
- [x] 1.7 T6 — conversation `workspace_id` read failure → `reportSilentFallback` + throw (no NULL insert).

## Phase 2 — GREEN (implementation)

- [x] 2.1 cc-dispatcher: after ownership probe (~1395), read `conversations.workspace_id` via the existing `tenant` mint; pass to user INSERT (1449).
- [x] 2.2 cc-dispatcher: add `workspaceId` param to `buildRow` (433/449); set `workspace_id` on assistant row.
- [x] 2.3 agent-runner `saveMessage` (447): fetch parent conversation `workspace_id` via minted tenant; add to INSERT payload.
- [x] 2.4 agent-runner `sendUserMessage`: add `workspace_id` to existing conversation `.select` (2426-2431) and to INSERT (2438).
- [x] 2.5 Confirm `insert-draft-card.ts` unchanged (already correct).
- [x] 2.6 Rewrite stale comments (cc-dispatcher 1428-1431, 1552-1556; agent-runner 440-445, 2435-2436) to post-059 workspace-member contract.

## Phase 3 — Verify & ship

- [x] 3.1 Run cc-dispatcher + agent-runner test suites → all GREEN.
- [ ] 3.2 Prod RLS verification (read-only) via Doppler `prd` + Supabase REST GET (plan §Verification); confirm policy + NOT NULL + conversation `workspace_id` populated.
- [ ] 3.3 Confirm derived `workspace_id` satisfies `is_workspace_member(workspace_id, auth.uid())` WITH CHECK.
- [ ] 3.4 File follow-up issue: `094_*` duplicate migration prefix collision (renumber + check prod apply order). Do NOT renumber here.
- [ ] 3.5 Ship: PR with `Closes #<issue>`, post-deploy success signal (fresh message persists; Sentry signatures stop).
