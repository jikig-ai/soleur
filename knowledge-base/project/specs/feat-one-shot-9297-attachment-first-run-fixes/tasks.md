# Tasks: fix attachments on a fresh conversation and first-run flow (Ref #9297)

Plan: `knowledge-base/project/plans/2026-09-30-fix-attachment-first-run-and-fresh-conversation-presign-plan.md`

PR body uses `Ref #9297`, never `Closes`. Items 4-6 of #9297 are out of scope.

## Phase 0 - RED (tests first)

- [ ] 0.0 Read the plan's 'Phase 0 harness notes' first (PostgREST-faithful presign mock, anchor mutations, D2 seams from `ws-handler-cc-session-id-wiring.test.ts`, real-ChatInput mount, per-assertion RED stubs). Label characterization tests (they pass pre-fix) as such.
- [ ] 0.1 `apps/web-platform/test/presign-route.test.ts`: unmaterialized lowercase UUID -> 200; `"new"`, `../x`, short and UPPERCASE uuid -> 404 with no DB lookup and no storage call; lookup DB error (new error-returning `mockQueryChain` variant) -> 500 `upload_failed`; extra body fields never change `storagePath`; other-user row non-member -> 403; co-member -> 200. Re-point the existing "404 when user does not own" test at a non-UUID id.
- [ ] 0.2 NEW `apps/web-platform/test/ws-deferred-attachments-only.test.ts` (not `ws-deferred-creation.test.ts`, which #9051 edits heavily): pending session + `chat` with empty content and one attachment materializes and dispatches `""` + attachments on both the soleur-go and legacy branches; `@mention` + attachments materializes; empty without attachments and `@mention`-only still error.
- [ ] 0.3 `apps/web-platform/test/attachment-error-copy.test.ts`: every presign code maps to human copy that is not the raw code; unknown falls back (no source-grep drift test).
- [ ] 0.4 `apps/web-platform/test/chat-input-attachments.test.tsx`: `conversationId={null}` -> paperclip `aria-disabled` (focusable, described-by text), drop/paste stage nothing with the availability message, dragover/drop default prevented, `fetch` never called; real id is sent in the presign body; presign error codes render human copy on the tile; storage failure renders the generic copy.
- [ ] 0.5 `apps/web-platform/test/first-run-send.test.ts`: files+empty -> one send; files+message -> upload before the single send; no files -> message only; all-fail + message -> message still sent once; all-fail + no message -> no send; id change or socket close between upload and send -> refs not sent, `first-run-send-dropped` captured; upload throw never rejects (`first-run-upload-failed` captured).
- [ ] 0.6 `apps/web-platform/test/chat-surface-first-run-attachments.test.tsx`: no resend on re-render (under `<React.StrictMode>`); pending files never consumed for `conversationId="abc"`, sidebar variant or a resumed session (msg path still sends); `ChatInput` gets the real id, `null` before `realConversationId`.
- [ ] 0.7 Run the new/changed tests and confirm each fails for the stated reason.

## Phase 1 - Composer gate and tile copy

- [ ] 1.1 Create `apps/web-platform/lib/attachment-error-copy.ts`.
- [ ] 1.2 `apps/web-platform/components/chat/chat-input.tsx`: `conversationId?: string | null` (`null` = unavailable); `aria-disabled` paperclip + described-by; gate `validateAndAddFiles`; `preventDefault` on dragover/drop; render mapped copy. No `"new"` literal here.

## Phase 2 - Server tolerance

- [ ] 2.1 `apps/web-platform/app/api/attachments/presign/route.ts`: strict lowercase 8-4-4-4-12 UUID shape check BEFORE any DB call (404 otherwise), then `.maybeSingle()` with `error` checked first (500 + `reportSilentFallback(op: "presign-lookup")`), absent row -> tolerant own-folder path.
- [ ] 2.2 `apps/web-platform/server/ws-handler.ts`: in the `chat` pending branch only: guard uses `(msg.attachments?.length ?? 0) === 0`; attachments-only first message pre-validated (`${userId}/${pending.id}/` prefix, no `..`, resolvable type) BEFORE `createConversation`; `attachments-pending-id-diverged` capture when `resolvedId !== pendingId`. Keep the hunks contiguous (PR #9051 also edits this file).
- [ ] 2.3 `apps/web-platform/lib/attachment-constants.ts`: export `CONVERSATION_ID_RE` (lowercase, anchored) and use it in the route.

## Phase 3 - First-run flow

- [ ] 3.0 `apps/web-platform/app/(dashboard)/dashboard/page.tsx`: add `fr=1` to the chat URL when files are staged; fix the stale header comments in `lib/pending-attachments.ts` and `lib/upload-attachments.ts`.
- [ ] 3.1 Create `apps/web-platform/lib/first-run-send.ts` (uses `reportSilentFallback` from `lib/client-observability.ts`, never `@/server/*`; deadline, post-upload readiness check, `{ sent, retry }` result).
- [ ] 3.2 `apps/web-platform/components/chat/chat-surface.tsx`: localized hunks only (state removal, single effect calling `runFirstRunSend` with the `fr=1` + `filesEligible` gate, `liveRef`, bounded re-arm and `firstRunBusy` composer disable, `<ChatInput conversationId>` expression, import swap incl. removing the unused `Sentry` import). Do not reformat.

## Phase 4 - Verify

- [ ] 4.1 Run the listed vitest files plus `test/upload-attachments.test.ts`, `test/pending-attachments.test.ts`, `test/chat-surface-sidebar.test.tsx`, `test/chat-surface-awaiting-input.test.tsx`.
- [ ] 4.2 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` and `bash scripts/constraint-gates.sh`.
- [ ] 4.3 `git diff origin/main...HEAD -- apps/web-platform/components/chat/chat-surface.tsx` stays localized (advisory).
- [ ] 4.4 QA (Playwright, dev): fresh chat attach `.md` -> delivered; dashboard first-run with files and empty message -> exactly one user message with the attachment; files-only first message on both routing paths; record the upload-first delay with throttled network and the rail title.
- [ ] 4.5 At ship: tick #9297 items 1-3 (leave 4-6), PR body `Ref #9297`, link #9316 and #9318, render `decision-challenges.md`.
