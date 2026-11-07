# Tasks: approval card names the requester; reattach withholds action text (Ref #9601)

Plan: `knowledge-base/project/plans/2026-11-07-feat-approval-card-requester-and-reattach-redaction-plan.md`. All paths under `apps/web-platform/` unless stated. Run commands from `apps/web-platform`.

## Phase 0: Setup and RED tests (no source change)

- 0.0 Land signature-only, deliberately fail-open stubs first (`canSeeAction = () => true`, labeler returns `undefined`, `RequesterLabelFn` exported, `ReemitArgs.requesterLabel` optional until Phase 2) so the new tests are red on assertions; add the strict PostgREST fake to `test/approval/fixtures.ts`.
- 0.1 Create `test/approval/card-visibility.test.ts` (synchronous truth table for `canSeeAction` / `requesterKind`: owner true; equal non-empty ids true; NULL, `undefined`, empty, unequal, case-differing false; `self` for any role).
- 0.2 Create `test/approval/reattach-redaction.test.ts` driving the real `reemitLiveApprovals` (scenarios 1-10 of the plan's Test Scenarios, canary strings, positive-control assertion that the Owner frame contains the canary, serialized-frame absence checks, mocked report/logger sinks).
- 0.3 Create `test/approval/requester-label.test.ts` (membership scope, NULL/empty id, empty email, 321-char and no-`@` emails -> fallback, error -> undefined plus one report without the email, workspace-keyed memoisation of success and failure, lazy default client, never throws).
- 0.4 Create `test/approval/gate-flow-requester.test.ts` (first send: Owner requester "you", member requester "you", Owner viewer with a row raised by another member -> label, member viewer -> no key, labeler throws -> key omitted, dep absent -> no key).
- 0.5 Create `test/approval/render-sink-scan.test.ts` (whole-`server/` recursive scan: allowed `renderApprovalView(` callers and exact counts; the three literal reattach lines each once; files-scanned floor; every allowed caller found; direct importers of `requester-label` pinned to gate.ts, ws-handler.ts and the landing page).
- 0.6 Extend `test/approval/wire-parity.test.ts`, `test/chat-state-machine-approval.test.ts`, `test/components/approval-request-card.test.tsx`, `test/chat-surface-approval.test.tsx`, `test/approval/landing-page.test.tsx`, `test/server/ws-handler-approval.test.ts` (add the `h.serviceFrom` seam; seed a conversation owned by the viewing member), `test/ws-zod-schemas.test.ts`, `test/approval/gate-flow-payload.test.ts`, `test/approval/gate-deps.test.ts`, `test/approval/approval-ops-real-sink.test.ts` (stub the required `requesterLabel`), `test/chat-message-exhaustiveness.test-d.ts`, `test/feature-map.md` (plan Test Scenarios). Do NOT rename or edit existing named tests (Guard-1 battery rows rely on their names).
- 0.7 Run the new and extended files on the unchanged tree; record the failing names for the PR test plan.

## Phase 1: Wire, copy and state

- 1.1 `lib/types.ts`: `view: ApprovalCardView | null`, `requester?: string` on `approval_request`.
- 1.2 `lib/ws-zod-schemas.ts`: `view: approvalCardViewSchema.nullable()`, `requester: z.string().min(1).max(320).optional()`.
- 1.3 `lib/approval-copy.ts`: `REQUESTER_SELF`, `REQUESTER_FALLBACK`, `requestedBy`, `memberWaitingRedacted`, `memberWaitingOwn` (CPO wording; no outcome words).

## Phase 2: Server

- 2.1 `server/approval/card-visibility.ts`: `canSeeAction`, `requesterKind` (pure, synchronous) and the shared `RequesterLabelFn` type.
- 2.2 `server/approval/ops.ts`: `requesterLabelFailed` (warn, unique op and message).
- 2.3 `server/approval/requester-label.ts`: `createRequesterLabeler(getClient?, opts?)` returning `label(workspaceId, viewerUserId, requestedBy)`: `isUuid` on every id, one `workspace_members` query proving the viewer is an Owner and the requester a member of the ROW's workspace, email from `auth.admin.getUserById` (NOT `public.users.email`), shape check (1-320 chars, one `@`, no whitespace or control characters), one 2 second deadline per call (injectable signal), timeout trips the instance, memo keyed by workspace and requester, never throws, one report helper.
- 2.4 `.service-role-allowlist`: add `apps/web-platform/server/approval/requester-label.ts` with a comment.
- 2.5 `server/approval/reattach.ts`: required `requesterLabel`; the three literal lines (`const mayView = canSeeAction(`, `toolName: mayView ? ... : "redacted",`, `view: mayView ? renderApprovalView(action) : null,`) after the hash and key-unavailable blocks; skip `approved` rows when `!mayView`, and skip any row when the `viewerRole` read failed and the viewer is not the verified requester (Ruled by CTO agent, 2026-11-07); `requester` appended last; keep the Guard-1 anchor lines byte-identical and run `bash apps/web-platform/test/approval-guard1-mutation.test.sh --check-anchors`.
- 2.6 `server/approval/gate-types.ts`, `gate.ts`, `gate-flow.ts`, `server/ws-handler.ts`: inject the labeler (gate.ts via the existing `serviceClient` seam; ws-handler via the lazy `supabase` proxy); first send keeps `view: renderApprovalView(action),` byte-identical and appends the conditional `requester` last after `agentWaiting: true,` with a short deadline on the lookup; the ws-handler `viewerRole` closure throws on a null tenant.
- 2.7 `server/approval/view-model.ts`: export `StoredApprovalRowWithRequester` (required `requested_by_user_id` key) for the landing page.

## Phase 3: Client

- 3.1 `lib/chat-state-machine.ts`: nullable view, `requester` copy-through (fresh card and upsert), null-safe `content` falling back to `APPROVAL_COPY.memberWaitingRedacted`.
- 3.2 `components/chat/approval-request-card.tsx`: `requester` prop, `detailsRemoved` predicate, withheld flag, pending title chosen independently of `view` (self / redacted / nonOwnerWaiting), defensive neutral strings for a withheld non-pending card, requester line outside the live region.
- 3.3 `components/chat/chat-surface.tsx`: pass `requester`.
- 3.4 `app/(dashboard)/dashboard/approvals/[id]/page.tsx` (server component, the only labeler caller) and `components/approvals/approval-landing.tsx` (plain `requester` prop, no server import): select `requested_by_user_id`, compute and pass `requester` (only when the view is non-null; failure omits it).

## Phase 4: Design and C4

- 4.1 The UX lead's `.pen` delta and PNG exports 19-22 are already committed (395ead6761); confirm they are non-empty and reference them in the PR body.
- 4.2 `knowledge-base/engineering/architecture/diagrams/model.c4`: edit the `webapp -> approvalStore` and `engine -> approvalStore` edge descriptions (one clause each).

## Phase 5: ADR and handover (edit both together)

- 5.1 Replace the item-1 block in `knowledge-base/engineering/architecture/decisions/ADR-309-durable-action-bound-approval-requests.md` and the identical block in `knowledge-base/project/specs/archive/20261029-164429-feat-hitl-approval-queue/flag-create-handover.md` (merge-conditional tense; limb (iii) open; cohort rule in force; no sentence saying the cohort is unblocked).
- 5.2 Add the ADR addendum dated 2026-11-07 (decision, invariants, accepted limitations a-h including creator-only attach and stale tabs, debt owed under item 6).
- 5.3 Run `bash scripts/markdown-lint.sh --repo-sweep` before committing markdown.

## Phase 6: Verification

- 6.1 Plan ACs 2-13: targeted vitest, `tsc --noEmit`, allowlist gate and self-test, `constraint-gates.sh`, `--check-anchors`, C4 tests, `lint-guard-contract.py`, anchor `grep -F` checks, no migration / DSAR allowlist / docs/legal / .github change, ADR lockstep diff, the two `112xx` greps (both must print nothing).
- 6.2 PR body: "Ref #9601" only, Changelog section, test plan notes that the slow local `--affected` battery was not awaited because CI is the ship gate, decision-challenges rows rendered, the prohibited words absent.
