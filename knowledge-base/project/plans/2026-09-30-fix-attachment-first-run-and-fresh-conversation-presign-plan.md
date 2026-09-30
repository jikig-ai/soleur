---
title: "fix: attachments on a fresh conversation and first-run flow (#9297 items 1-3 + new bug)"
date: 2026-09-30
slug: attachment-first-run-and-fresh-conversation-presign
branch: feat-one-shot-9297-attachment-first-run-fixes
issue: 9297
ref: 9297
type: fix
lane: cross-domain
---

# fix: attachments on a fresh conversation and first-run flow

Ref #9297 (NOT `Closes` — items 4-6 stay deferred and the issue stays open).

## Overview

Four user-visible defects in the chat attachment path, all rooted in one fact the
brief did not name: **a conversation row does not exist until the first `chat`
message** (deferred creation — see Research Reconciliation).

| ID | Defect | Where |
|----|--------|-------|
| A (new) | Fresh chat: attach a `.md`, send -> tile shows raw `conversation_not_found`, message goes out WITHOUT the file | `chat-surface.tsx` passes the route id `"new"` to `<ChatInput conversationId>`; `chat-input.tsx` presigns against it |
| B1 (#9297 item 1) | First-run composer submit with files and an EMPTY message uploads nothing | pending-files effect gated on `initialMsgSent`, which only flips when `msgParam` is set |
| B2 (#9297 item 2) | First-run: `sendMessage(msgParam)` fires before uploads finish, then a SECOND empty message carries the files | same two effects |
| C (#9297 item 3) | Presign error codes (`file_too_large`, `conversation_not_found`, ...) render raw on attachment tiles | `chat-input.tsx` `uploadAttachments` catch |

Out of scope, untouched: duplicate detection, KB-tree delete/rename for `.md`,
size cap / encoding hint (items 4-6).

## Research Reconciliation — Brief vs. Codebase

| Brief claim | Reality (verified on this branch) | Plan response |
|-------------|-----------------------------------|---------------|
| "Use `realConversationId` once the server has created the row" | `session_started` returns a **pending UUID** (`ws-handler.ts` `start_session (deferred creation)`); `realConversationId` is set from it, but the `conversations` row is only inserted by `createConversation` in the `chat` case ("Materialize pending conversation on first real message"). Presign against the pending UUID still 404s `conversation_not_found` for the FIRST message. | `realConversationId` is necessary but not sufficient. Presign must also accept an unmaterialized, UUID-shaped id (D1 below). |
| "Reorder to upload first and send once" (items 1-2) | Today's order (send first, upload after) exists precisely because presign needs the row. Also the first `chat` is rejected when the @-stripped text is empty ("Please include a message along with the @-mention"), so a files-only first message fails even if uploaded. | Lift both server preconditions minimally: presign tolerance (D1) and attachments-only first message (D2). Then upload-first/send-once is physically possible. |
| "A copy proposal for presign codes is in decision-challenges.md" | The archived file's proposal is for the **client validator** message (`"<name>" isn't supported. You can attach images, PDFs, .md or .txt files.`) and the 3s toast length, not presign-code copy. | Reuse its wording for `unsupported_file_type` only; author the rest here; record as Taste (not silently final). Validator message and toast duration stay unchanged (out of scope). |
| `chat-surface.tsx` ~line 1223 passes `conversationId` | Confirmed (`<ChatInput conversationId={conversationId}>`). | Fix in place. |

## Premise Validation

`gh issue view 9297`: OPEN, items 1-3 still unchecked. Cited symbols exist on the
branch (`chat-surface.tsx` effects at the `initialMsgSent` block,
`chat-input.tsx` `uploadAttachments`, `presign/route.ts` lookup). No ADR covers
the presign route or attachment deferral (`grep -il presign` over
`knowledge-base/engineering/architecture/decisions` hits only unrelated ADRs), so
no rejected-alternative conflict. Open draft PR #9051 (codex lifecycle) touches
`chat-surface.tsx`, `ws-handler.ts`, `ws-client.ts` (see Risks).

## Property List and Cut List (Mechanism Minimality)

Properties (observable outcomes):

1. P1 - Attaching on a fresh conversation delivers the file with the first message.
2. P2 - A first-run submit with files and no text uploads the files and sends exactly one message.
3. P3 - A first-run submit with files and text uploads first, then sends ONE message carrying both.
4. P4 - The composer never requests a presign for the route sentinel `"new"`.
5. P5 - Every presign failure code on a tile shows human copy; raw codes never render.

Cut list:

- New "materialize conversation" WS/HTTP action -> buys P1 but presign tolerance (D1) already buys it with a smaller surface. Cut.
- Client-side retry-on-404 loop around presign -> buys P1 only probabilistically; D1 is deterministic. Cut.
- In-process check of the WS session's pending id from the presign route -> `app/api/support/route.ts` documents that routes deliberately do not import ws-handler's `sessions` map (module-graph isolation). Cut.
- New failure-notice UI for first-run upload failure -> would escalate the UX tier to BLOCKING (new visible element). Cut; tracked as follow-up (see Deferrals).
- Global error-code registry shared with `ws-zod-schemas` -> presign codes are an HTTP vocabulary, not the WS `errorCode` enum. Cut; a small local map.

## Decisions

- **D1 - Presign tolerates an unmaterialized conversation id.** Order in `presign/route.ts` (review P0: `conversations.id` is a `uuid` column, so `.eq("id", "new")` is a Postgres 22P02 error, not an empty result):
  1. **Shape check BEFORE any DB call.** `conversationId` must match a strict lowercase `^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$` (structural, not v4-only: existing fixtures use `11111111-2222-3333-4444-555555555555`; lowercase-only because the DB `eq` normalises case while the storage path and the attachment-pipeline prefix check are case-sensitive). No match (`"new"`, garbage, `../x`, uppercase) -> 404 `conversation_not_found`, **no lookup, no storage call**. The regex is load-bearing: `conversationId` is interpolated into the storage path.
  2. `.maybeSingle()`; check `error` FIRST: a real DB error -> 500 `upload_failed` + `reportSilentFallback` (`feature: "attachments"`, `op: "presign-lookup"`); it must NOT fall through to the tolerant branch.
  3. Row exists -> existing own/co-member logic unchanged (membership check intact).
  4. No row (shape already proven) -> continue; path stays `${userId}/${conversationId}/<uuid>.<ext>`, caller-prefixed, so it can only write into the caller's own folder.
  No new `logger.info` on the tolerant branch (hot-path noise). Only `filename/contentType/sizeBytes/conversationId` influence the path; `workspaceId` or any other body field must not (tested). Residual: an authenticated user can mint URLs under arbitrary own-folder UUIDs (orphans covered by the account-delete purge; a per-user rate limit is a later item).
- **D2 - Attachments-only first message materializes the conversation.** `ws-handler.ts` `chat` case: change the guard to reject only when the @-stripped text is empty AND `msg.attachments` is empty. One line. Existing conversations already accept `("", attachments)`.
- **D3 - Composer contract (trimmed after plan review).** The route sentinel `"new"` lives in ONE place, `chat-surface.tsx`, which passes `realConversationId ?? (conversationId === "new" ? null : conversationId)` (comment the `auth_ok` -> `session_started` gap there). `ChatInput.conversationId?: string | null`: `null` = attachments unavailable; `undefined` keeps legacy behaviour so existing composer tests are unaffected. When unavailable: the paperclip uses `aria-disabled="true"` with a no-op click (stays focusable) and a visually hidden `aria-describedby` text plus `title`; the single `validateAndAddFiles` choke point rejects drop/paste with "Attachments are available once the conversation starts."; dragover/drop still `preventDefault` so the browser never navigates to a dropped file. No `"new"` literal and no `uploadAttachments` guard inside `ChatInput` (the gate is the only path to staging; if the id later resets to `null` with files staged, the presign returns `invalid_request` and the generic tile copy renders - still never a presign for `"new"`).
- **D4 - First-run flow extracted to `lib/first-run-send.ts`** (dependency-injected; it owns the existing sanitized batch Sentry capture, so the now-unused `Sentry` import in `chat-surface.tsx` is removed in the same edit, lint would flag it; it also takes `getLive(): { conversationId: string | null; connected: boolean }` re-read AFTER the upload) so the chat-surface diff is one effect swap plus one import and the ordering rules are unit-testable. Two reviewers (simplicity, DHH) preferred inlining; kept because the effect block is the conflict hotspot with #9051 and the helper keeps it to a contiguous swap. The mounted chat-surface test is slimmed to what only a mount can prove (once-guard, id prop).
- **D5 - Tile copy via `lib/attachment-error-copy.ts`**, keyed by presign error code with a generic fallback; raw server strings and XHR messages never render. No source-grepping drift test (brittle; the generic fallback already covers a new code).

Alternative considered and NOT taken (recorded as User-Challenge in
`knowledge-base/project/specs/feat-one-shot-9297-attachment-first-run-fixes/decision-challenges.md`):
client-only fix (disable attach until the first message is sent, keep send-then-upload
for first-run). Zero server surface, but it cannot deliver P1-P3 and leaves item 2 unfixed.

## Open Code-Review Overlap

Open `code-review` issues naming planned files: #3374 (ws-handler slot_reclaimed frame), #2191 (ws-handler timer helper), #3243 (cc-dispatcher decomposition; `ws-handler.ts` mentioned), #2961 (conversations.repo_url trigger). Disposition: **Acknowledge** all four — none concern the `chat` materialization guard, presign, or composer; folding any would widen a hunk in `ws-handler.ts` that PR #9051 is also editing.

## Files to Edit

- `apps/web-platform/app/api/attachments/presign/route.ts` - D1 (maybeSingle, UUID-shaped tolerance, lookup-error 500 + Sentry mirror).
- `apps/web-platform/server/ws-handler.ts` - D2, single-line guard in the `chat` case (`Materialize pending conversation on first real message`).
- `apps/web-platform/components/chat/chat-input.tsx` - D3 (prop type, `aria-disabled` paperclip + described-by text, `validateAndAddFiles` gate, dragover/drop `preventDefault`) + D5 (tile copy).
- `apps/web-platform/components/chat/chat-surface.tsx` - MINIMAL hunks only: (1) drop the `initialMsgSent`/`pendingFilesHandled` state, (2) replace the two effects (`sendMessage(msgParam)` + pending-files upload) with one effect calling `runFirstRunSend` (plus a `liveRef` and removal of the unused `Sentry` import), (3) `conversationId` prop expression on `<ChatInput>`, (4) import swap. No reflow, no renames.
- Tests: `apps/web-platform/test/presign-route.test.ts`, `apps/web-platform/test/chat-input-attachments.test.tsx`. (D2 tests go in a NEW file, not `ws-deferred-creation.test.ts`: PR #9051 edits that file in 10+ hunks incl. its hoisted mocks.)

## Files to Create

- `apps/web-platform/lib/attachment-error-copy.ts` - `attachmentErrorCopy(code?: string): string`.
- `apps/web-platform/lib/first-run-send.ts` - `runFirstRunSend(deps)`.
- `apps/web-platform/test/attachment-error-copy.test.ts`
- `apps/web-platform/test/ws-deferred-attachments-only.test.ts` - D2 tests; copy the hoisted-mock setup from `test/ws-deferred-creation.test.ts`.
- `apps/web-platform/test/first-run-send.test.ts`
- `apps/web-platform/test/chat-surface-first-run-attachments.test.tsx` - mounts `ChatSurface` with `createWebSocketMock` (see `test/mocks/use-websocket.ts`), seeds `setPendingFiles`, asserts `sendMessage` call count/args.
- `knowledge-base/project/specs/feat-one-shot-9297-attachment-first-run-fixes/decision-challenges.md`
- `knowledge-base/project/specs/feat-one-shot-9297-attachment-first-run-fixes/tasks.md`

## Implementation Phases (tests first: cq-write-failing-tests-before)

### Phase 0 - RED (write all failing tests; run; confirm each fails for the stated reason)

1. `presign-route.test.ts`:
   - valid lowercase UUID, no row -> 200 + `uploadUrl`, `storagePath` starts `${TEST_USER_ID}/${id}/` (currently 404).
   - `"new"`, `"../../etc/x"`, a short uuid and an UPPERCASE uuid -> 404 `conversation_not_found`, and `mockFrom` AND `mockCreateSignedUploadUrl` are NOT called (kills the mutation "move the shape check after the lookup": a real Postgres 22P02 would 500 there, which `mockQueryChain(null)` alone cannot show).
   - lookup returns a DB error for a valid UUID -> 500 `upload_failed`, no signed URL (guards "error treated as not-found -> tolerant"); needs a new error-returning variant of the `mockQueryChain` helper (its `maybeSingle` terminal already exists; `setupConversationOwnership` itself needs no change).
   - extra body fields (`workspaceId`, `userId`) never change `storagePath`.
   - row owned by another user, non-member -> still 403 `not_a_workspace_member`; co-member -> 200 (unchanged).
   - The existing "404 when user does not own the conversation" test uses a valid UUID with `null` data; re-point it at a non-UUID id (its intent, "unknown conversation", is preserved) rather than deleting it.
2. `ws-deferred-attachments-only.test.ts` (new file): pending session + `chat` with `content: ""` and one `attachments` entry -> `createConversation` path runs, no "Please include a message" error, and the dispatch receives `""` content plus the attachments on BOTH branches (soleur-go `pendingRouting.kind !== "legacy"` and the legacy leader path); `"@cto "` + attachments -> materializes (positive case); `content: ""` and NO attachments -> still the error; `"@cto "` + no attachments -> still the error.
3. `attachment-error-copy.test.ts`: every presign code in the route (`invalid_request`, `unauthorized`, `unsupported_file_type`, `file_too_large`, `conversation_not_found`, `not_a_workspace_member`, `upload_failed`) maps to a non-empty string that is not the code itself; unknown/undefined -> generic fallback (this one test is what proves raw codes never render).
4. `chat-input-attachments.test.tsx` (extend): with `conversationId={null}` -> paperclip has `aria-disabled="true"` (still focusable, described-by text present), clicking it opens no picker, dropping/pasting a file shows the availability message and stages nothing, dragover/drop default is prevented, `fetch` never called (mutation rows: remove the `validateAndAddFiles` gate -> red; drop the `preventDefault` -> red); with `conversationId="0a1b..."` -> presign body carries that id; presign 404 `conversation_not_found` -> tile shows the human copy and not the raw code; `file_too_large` likewise; storage 403 -> generic fallback copy (update the existing assertions near the "non-2xx XHR status" and "XHR upload failure" cases only if they assert raw strings).
5. `first-run-send.test.ts` (injected `upload`/`send` fakes): files + "" -> upload once, `send("", refs)` exactly once; files + "hi" -> upload called BEFORE send (order asserted via a shared call log), `send("hi", refs)` once; no files + "hi" -> `send("hi")` once, `upload` never; no files + no msg -> nothing; all uploads fail + "hi" -> `send("hi")` once (text not lost); all fail + no msg -> no send; id changes between upload and send (reconnect) -> refs not sent, `first-run-send-dropped` captured; socket closed between upload and send -> no send, captured; `upload` throws -> same as all-fail, never rejects, and the Sentry capture carries `op: "first-run-upload-failed"` with the file counts (so first-run loss is countable).
6. `chat-surface-first-run-attachments.test.tsx`: `conversationId="new"`, `?msg=hi`, pending files set, `sessionConfirmed` + `realConversationId` set -> re-render does not re-send (ref guard; mount under `<React.StrictMode>`); pending files are NEVER consumed or sent for `conversationId="abc"`, for `variant="sidebar"`, and for a resumed session (`resumedFrom` set) — the `msgParam` path still sends; `<ChatInput>` receives the real id (mock `ChatInput` to capture the prop), `null` while `realConversationId` is null. The ordering rules themselves are covered in item 5, not re-tested here.

Expected RED reasons: items 1-2, 4 and 6 fail on behaviour; 3 and 5 fail on missing modules. Item 1 also pins that a body `workspaceId`/extra field cannot change `storagePath`.

### Phase 1 - Composer gate + tile copy (A, C)

`attachment-error-copy.ts`: table (author's proposal, Taste-tagged in decision-challenges.md):

| code | tile copy |
|------|-----------|
| `file_too_large` | "File is empty or larger than 20 MB." (from `MAX_ATTACHMENT_SIZE`; the route also returns this code for `sizeBytes <= 0`) |
| `unsupported_file_type` | "This file type isn't supported. You can attach images, PDFs, .md or .txt files." (wording from the archived CPO proposal) |
| `conversation_not_found` | "This conversation isn't ready for attachments yet. Remove the file and attach it again." (the tile has no retry affordance; nearly unreachable after D1) |
| `not_a_workspace_member` | "You don't have access to attach files to this conversation." |
| `unauthorized` | "Your session expired. Sign in again to attach files." |
| `invalid_request`, `upload_failed`, unknown / network | "Upload failed. Check your connection and try again." |

`chat-input.tsx`: `const attachmentsUnavailable = conversationId === null`; gate in `validateAndAddFiles` (covers button/drop/paste), `aria-disabled` paperclip; in the catch, render `attachmentErrorCopy(err instanceof Error ? err.message : undefined)` (presign failures already throw `new Error(err.error || "Presign failed")`, so the message IS the code; storage-phase messages are not codes and fall to the generic copy).

### Phase 2 - Server tolerance (D1, D2)

As specified under Decisions. `route.ts` keeps the `// Inline lookup` comment and adds a short note that an absent row is the expected state for a fresh conversation. `reportSilentFallback` on lookup error uses `feature: "attachments", op: "presign-lookup"` (cq-silent-fallback-must-mirror-to-sentry).

### Phase 3 - First-run flow (B1, B2)

`first-run-send.ts`:

```ts
export async function runFirstRunSend(d: {
  msgParam: string | null; files: File[]; conversationId: string | null;
  getLive: () => { conversationId: string | null; connected: boolean };
  upload: (files: File[], conversationId: string) => Promise<AttachmentRef[]>;
  send: (content: string, attachments?: AttachmentRef[]) => void;
}): Promise<void>
```

Rules: no files -> `msgParam && send(msgParam)`. Files: `uploaded = await upload(...)` (errors swallowed after the existing sanitized Sentry capture); `uploaded.length > 0` -> ONE `send(msgParam ?? "", uploaded)`; else `msgParam && send(msgParam)`.

`chat-surface.tsx` effect (replaces the two existing effects, same dependency style). Review P0: the pending-file store is module-global (5-minute TTL), so files are consumed ONLY for a fresh full-variant `"new"` conversation, never for an existing, resumed or sidebar chat; the `msgParam` path keeps its old (ungated) behaviour:

```ts
const firstRunStartedRef = useRef(false);
const liveRef = useRef({ conversationId: realConversationId, connected: status === "connected" });
liveRef.current = { conversationId: realConversationId, connected: status === "connected" };
useEffect(() => {
  if (firstRunStartedRef.current || !sessionConfirmed) return;
  const filesEligible = conversationId === "new" && variant === "full" && !resumedFrom;
  const files = filesEligible ? getPendingFiles() : [];
  if (!msgParam && files.length === 0) return;
  if (files.length > 0 && !realConversationId) return; // wait; msg-only path must not wait
  firstRunStartedRef.current = true;
  if (files.length > 0) clearPendingFiles();
  if (msgParam) router.replace(pathname, { scroll: false });
  void runFirstRunSend({ msgParam, files, conversationId: realConversationId, getLive: () => liveRef.current, upload: uploadPendingFiles, send: sendMessage });
}, [sessionConfirmed, msgParam, realConversationId, conversationId, variant, resumedFrom, sendMessage, router, pathname]);
```

`runFirstRunSend` rules: no files -> `msgParam && send(msgParam)`. Files: `uploaded = await upload(...)`; then re-read `getLive()`: if `!connected` (the socket can close during a multi-second upload; `sendMessage` would add an optimistic bubble and silently not send) or the id changed (a reconnect mints a NEW pending id, so refs uploaded under the old prefix would fail the pipeline prefix check) -> do not send the refs; report Sentry `op: "first-run-send-dropped"` (distinct `op`, countable) and send nothing further; otherwise `uploaded.length > 0` -> ONE `send(msgParam ?? "", uploaded)`, else `msgParam && send(msgParam)`. Upload errors are swallowed after the sanitized batch Sentry capture (`op: "first-run-upload-failed"`). The once-guard is a ref (not state) so React StrictMode's double effect and an in-flight upload cannot produce a second send.

### Phase 4 - Verify

`cd apps/web-platform && npx vitest run test/presign-route.test.ts test/chat-input-attachments.test.tsx test/ws-deferred-attachments-only.test.ts test/ws-deferred-creation.test.ts test/attachment-error-copy.test.ts test/first-run-send.test.ts test/chat-surface-first-run-attachments.test.tsx test/upload-attachments.test.ts test/pending-attachments.test.ts test/chat-surface-sidebar.test.tsx test/chat-surface-awaiting-input.test.tsx` then the full `npx vitest run` shard for `test/chat-*` and `test/ws-*`, `./node_modules/.bin/tsc --noEmit` (never `npm run -w`; the repo root declares no workspaces), and the repo lint command from `package.json`. Then QA via `soleur:qa` (Playwright against dev): fresh `/dashboard/chat/new`, attach a `.md`, send -> file delivered, no tile error; dashboard first-run with files and empty message -> exactly one user message with the attachment. Blocking QA checks (promoted from Risks): (a) a files-only first message on BOTH routing paths (soleur-go `pendingRouting` and the legacy leader path) produces a sensible user bubble and agent reply; (b) record, with the network throttled, what the user sees between first-run submit and the first message render (upload-first delay) and the rail title for a files-only first message.

## Acceptance Criteria

- [ ] On `/dashboard/chat/new`, after `session_started`, attaching a `.md` and sending delivers the file with the first message; no tile error (presign called with the real/pending UUID, never `"new"`).
- [ ] Before `session_started` (no id yet) the paperclip is disabled and drop/paste stage nothing; `fetch` is never called with `conversationId: "new"` (test asserts on the presign request body).
- [ ] Presign: unmaterialized lowercase-UUID id -> 200; `"new"`/garbage/traversal/uppercase -> 404 with no DB lookup and no storage call; DB lookup error -> 500 and never reaches the tolerant branch; existing row owned by another user, non-member -> 403.
- [ ] `ws-handler.ts` `chat` on a pending session accepts `content: ""` only when `attachments.length > 0`; the empty-without-attachments and `@mention`-only errors are unchanged.
- [ ] Pending files are consumed only for a fresh full-variant `"new"` conversation (never for an existing, resumed or sidebar chat).
- [ ] First-run with files + empty message: files uploaded, exactly ONE `sendMessage("", refs)`; with files + message: upload completes BEFORE the single `sendMessage(msg, refs)`; no second empty message.
- [ ] First-run with all uploads failing and a message: the message is still sent once; with no message: nothing sent, Sentry capture preserved.
- [ ] No attachment tile renders a raw code (for each presign code and for an unknown code the tile text is the mapped/fallback copy, never the code).
- [ ] A files-only first message is accepted on both routing paths (soleur-go and legacy leader) and renders a sensible bubble and reply (QA evidence in the PR).
- [ ] Paperclip while unavailable: `aria-disabled="true"`, focusable, has described-by text; dragover/drop default prevented.
- [ ] `chat-surface.tsx` diff stays localized to the hunks named under Files to Edit (advisory, reviewer-checked against the merge base: `git diff origin/main...HEAD -- apps/web-platform/components/chat/chat-surface.tsx`; the two-dot form goes red when a sibling PR such as #9051 touches the file on main).
- [ ] PR body says `Ref #9297` (not Closes/Fixes); #9297 items 1-3 checked off in the issue body at ship; items 4-6 untouched.
- [ ] `./node_modules/.bin/tsc --noEmit` (run from `apps/web-platform`) and the listed vitest files green.

## Test Scenarios (beyond the ACs)

- Non-new route (`conversationId="abc"`): composer receives `realConversationId ?? "abc"`; unchanged behaviour.
- Sidebar variant (`variant="sidebar"`) shares the same composer and the same gate.

## User-Brand Impact

**If this lands broken, the user experiences:** a file they attached to a chat message silently not reaching the agent, or a raw error code on the attachment tile (the reported bug); in the worst case a first message that fails to send at all.
**If this leaks, the user's [data] is exposed via:** not applicable beyond today's exposure - the tolerant presign branch only mints a signed upload URL under the CALLER's own `${userId}/` folder (UUID-validated so the id cannot traverse the path); an existing row owned by someone else still goes through the membership check; reads remain governed by the unchanged storage RLS (mig 045/068, own-folder or workspace-member).
**Brand-survival threshold:** aggregate pattern

Reasoning: the authorization relaxation is bounded to the caller's own folder and cannot cross a user/workspace boundary; the worst realistic outcome is orphaned own-folder objects (purged by `account-delete.ts` `chat-attachments/<userId>/` sweep) and dropped-attachment UX, neither a single-user incident.

## Domain Review

**Domains relevant:** Engineering, Product (Legal: advisory note only)

### Engineering

**Status:** reviewed (inline; the plan-review panel and deepen-plan cover architecture/security)
**Assessment:** Deferred conversation creation is the structural cause; fix is two narrow server preconditions plus client gating. Main risk is the presign authorization relaxation (mitigated: caller-prefixed path, strict UUID, DB error does not fall through) and merge conflict with #9051.

### Legal / Privacy (advisory)

**Status:** reviewed (inline)
**Assessment:** No new data category, processor, or purpose; `gdpr-gate` surface hit (API route) but the change narrows to own-folder storage writes. Unmaterialized uploads are covered by the existing account-delete storage purge. There is still no TTL sweep for uploads never followed by a send (pre-existing: upload always preceded send).

### Product/UX Gate

**Tier:** advisory
**Decision:** auto-accepted (pipeline)
**Agents invoked:** none
**Skipped specialists:** soleur:marketing:copywriter (headless; tile copy is Taste-tagged in decision-challenges.md for operator review)
**Pencil available:** N/A (no new UI surface)

#### Findings

The mechanical UI-surface glob matches `components/**/*.tsx`, which would force BLOCKING, but the diff is within the "Excluded: pure copy or style tweaks with no structural/layout change" carve-out: a disabled state on an existing control, error-tile copy, and no new component, layout, or visible element. Same call as the predecessor PR (#9290 plan). Tripwire: any new visible element (e.g. a first-run upload-failure notice) re-opens the gate to BLOCKING and needs a `.pen` wireframe first. Design of record: `knowledge-base/product/design/concierge/chat-composer-repo-setup-states.pen`.

## Observability

```yaml
liveness_signal:
  what: presign route reachable and rejecting unauthenticated/cross-origin POSTs (403)
  cadence: on demand (route has no scheduler); Sentry events tagged feature=attachments
  alert_target: Sentry issue alerts for feature=attachments (existing)
  configured_in: apps/web-platform/app/api/attachments/presign/route.ts (Sentry.captureException / reportSilentFallback)
error_reporting:
  destination: Sentry via reportSilentFallback(feature=attachments, op=presign-lookup) for lookup errors; existing op=presign for signed-URL failures
  fail_loud: lookup error returns 500 upload_failed and never proceeds
failure_modes:
  - mode: presign DB lookup errors (would previously read as conversation_not_found)
    detection: Sentry feature=attachments op=presign-lookup
    alert_route: Sentry -> existing attachments alert
  - mode: client tile shows generic fallback copy for a code with no entry
    detection: attachment-error-copy unknown-code fallback test in CI
    alert_route: CI failure
  - mode: first-run upload fails client-side
    detection: existing Sentry capture in upload-attachments.ts (sanitized, feature tag kb-chat)
    alert_route: Sentry
logs:
  where: Sentry (no new logger line on the hot path)
  retention: per existing logger/Sentry retention
discoverability_test:
  command: grep -c "presign-lookup" apps/web-platform/app/api/attachments/presign/route.ts
  expected_output: 1
```

## Architecture Decision (ADR/C4)

No new ADR: this refines an existing endpoint's precondition; it moves no ownership/tenancy boundary, adds no substrate, and reverses no ADR (grep of the ADR corpus for presign/deferred-creation found none on point). C4: "no C4 impact" checked against all three files (`model.c4` 888 lines, `views.c4`, `spec.c4`) for external actors (founder/end-user: already modeled), external systems (Supabase Storage/Postgres behind `api`, the WebSocket `webapp -> engine` edge: already modeled), containers/data stores (no new), and actor-to-surface access relationships (unchanged; own-folder write only). No `.c4` edit, so `c4-count-parity` is unaffected.

## Risks

- **Merge conflict with open draft PR #9051** (`feat(codex): wire Web lifecycle and history safeguards`): it edits `chat-surface.tsx`, `ws-handler.ts`, `ws-client.ts`, `lib/types.ts`. Mitigations: hunks are small and localized (listed above); the `chat-surface.tsx` effect swap is contiguous lines; the `ws-handler.ts` change is one line; no edits to `ws-client.ts`/`types.ts`. Whichever PR lands second merges main first and re-runs the Phase 4 test list. Do not reformat either file.
- **Presign authorization relaxation (D1):** reviewed for path traversal (strict UUID), cross-user write (caller-prefixed path), oracle strength (404-vs-403 becomes 200-vs-403, same information as today), and DB-error fallthrough (explicit 500). Orphan objects from never-sent uploads are a pre-existing class.
- **Empty first message (D2):** the agent receives empty text plus the attachment context block; identical to the existing-conversation attachments-only path. Verify in QA that the rail title for a files-only first message is acceptable (`use-conversations.ts` falls back to "Untitled conversation"); if not, that is a separate copy decision, not a blocker.
- **Context-path two-tab race** (see Test Scenarios): pending-id prefix vs resolved row id; pre-existing, unchanged.
- **Silent first-run file loss** (all or some uploads fail; with a message the text is still sent without the files, without one nothing is sent): no new UI in this PR; the Sentry capture carries a distinct `op` so it is countable; tracked in #9316 with the UX/CPO recommendation (hold the send and re-stage failed files as error tiles in the composer). Explicit operator Taste item, not an auto-accepted default.
- **Upload-first latency:** the first user bubble now appears only after uploads finish (up to 5 x 20 MB, no progress UI). Accepted for this PR and measured in QA; an optimistic bubble reusing the existing uploading tile state is the candidate follow-up (Taste, see decision-challenges.md).
- **Files cleared before upload:** `clearPendingFiles()` and `router.replace` run before the upload starts (same as today); a navigation or refresh mid-upload loses both. Unchanged, documented.

## Deferrals

- First-run upload-failure surfacing (no user-visible signal when all pending uploads fail and there is no message) - needs a BLOCKING-tier UX decision; tracked in #9316 (created during planning; the CPO/UX panel recommended the current Phase 4 milestone because first-run is the activation path, so the milestone was moved from "Post-MVP / Later" to Phase 4; hold-and-re-stage is the recommended behaviour).
- #9297 items 4-6: unchanged, remain on #9297.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan` Phase 4.6; it is filled above.
- `conversationId` is interpolated into a storage path: any future loosening of the UUID regex is a path-traversal change, not a style change.
- Do not test the route's tolerant branch with a v4-only regex or fixture; existing fixtures are non-v4 hex UUIDs.
- Hook `useWebSocket` in tests via `createWebSocketMock` (`test/mocks/use-websocket.ts`) so a hook field addition fails at compile time, not at N runtime failures.
- Do not add `vi.useFakeTimers()` to `chat-input-attachments.test.tsx` (documented hang with user-event v14).
- PR body: `Ref #9297`; never `Closes`.

## Research Insights

- Learnings applied: `2026-04-11-service-role-idor-untrusted-ws-attachments` (WS re-validates storagePath prefix; presign is not the only gate), `2026-05-05-image-placeholder-leak-and-cc-attachment-drop` (attachments must flow through both dispatch paths), `2026-04-18-test-mock-factory-drift-guard-and-jsdom-layout-traps`, `2026-04-06-vitest-mock-hoisting-requires-vi-hoisted`, `supabase-query-builder-mock-thenable-20260407` (presign test mocks use `mockQueryChain` from `test/helpers/mock-supabase.ts`, which already exposes a `maybeSingle` terminal; the route test must switch its ownership helper to drive `maybeSingle` for both the row and the DB-error cases), `2026-04-28-chat-input-xhr-flake-and-negative-space-assertion`, `2026-05-04-flag-boundary-creates-new-error-class-mapper-must-handle` (error mapper in lockstep with new codes; covered by the generic fallback rather than a source-grep test).
- Key code anchors (content, not line numbers): `ws-handler.ts` "Materialize pending conversation on first real message"; `ws-client.ts` `case "session_started"` (sets `realConversationId` to the pending id, `setSessionKind("fresh")`); `app/api/support/route.ts` header comment on not importing `sessions`; `account-delete.ts` storage-purge step for `chat-attachments/<userId>/`.
- Verified at plan time: `validateFiles` already rejects unsupported/empty/oversize/>5 files on the dashboard first-run form, so `pending-attachments` only ever holds valid files.
