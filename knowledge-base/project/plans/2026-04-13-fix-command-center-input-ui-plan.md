# fix: Command Center Input UI — Size Alignment & Attachment Support

**Type:** fix + enhancement
**Branch:** feat-command-center-input-ui
**PR:** #2133

## Problem

The Command Center first-run input has two issues:

1. **Size mismatch:** The text input and submit button are different heights. The button uses explicit `h-[44px]` but the input relies on `py-3` padding (~38px rendered height). They also sit too close together with only `gap-2` (8px).
2. **Missing attachments:** The initial prompt input doesn't support file uploads, while the conversation chat input (`chat-input.tsx`) has full attachment support (paperclip button, drag/drop, paste, progress tracking).

## Root Cause

**Sizing:** `apps/web-platform/app/(dashboard)/dashboard/page.tsx:282-298` — The input has no explicit height, the button has `h-[44px]`, and the container uses `flex items-end gap-2`.

**Attachments:** The presign API (`app/api/attachments/presign/route.ts`) requires a `conversationId` which doesn't exist during the first-run flow. The command center navigates to `/dashboard/chat/new?msg=<text>` which creates the conversation server-side. Files can't be uploaded until after navigation.

## Solution

### Part 1: Fix input/button alignment

In `apps/web-platform/app/(dashboard)/dashboard/page.tsx`:

- Add `min-h-[44px]` to the text input to match the button height
- Change container from `gap-2` to `gap-3` for better visual spacing
- Change `items-end` to `items-center` for vertical centering

### Part 2: Add attachment support via two-step send

[Updated 2026-04-13 — revised after plan review found fatal presign sequencing bug]

Architecture: Add file selection UI to the command center form. On submit, store files in a module-level singleton, navigate to chat/new. The chat page sends the text message first (which materializes the conversation and produces a real `conversationId`), then uploads files via presign API and sends them as a follow-up message.

**Why two-step send:** The presign API (`app/api/attachments/presign/route.ts:62-71`) validates `conversationId` against the `conversations` DB table. During the first-run flow, the conversation row is not created until the first `chat` message materializes it (deferred creation in `ws-handler.ts`). Uploading files before the text message would fail with `404 conversation_not_found`.

**Files to create:**

- `apps/web-platform/lib/pending-attachments.ts` — Module-level store for `File[]` that survives client-side SPA navigation. Simple get/set/clear API with a staleness guard (files older than 5 minutes are discarded on `get`).

**Files to modify:**

- `apps/web-platform/app/(dashboard)/dashboard/page.tsx` — Add paperclip button, hidden file input, attachment preview strip, drag/drop, and paste handlers to the first-run form. Reuse validation from `lib/attachment-constants.ts`. On submit, store `File[]` via pending-attachments, revoke preview URLs, then navigate.

- `apps/web-platform/app/(dashboard)/dashboard/chat/[conversationId]/page.tsx` — After initial text message is sent and `sessionConfirmed`, check for pending files. Upload via presign API (using the now-materialized `conversationId`), then send as a follow-up message. Clear pending files after consumption. Handle upload failures gracefully (send text-only, show error toast).

- `apps/web-platform/lib/ws-client.ts` — Expose the `conversationId` from `session_started` message (currently ignored at line 314). The chat page needs the real UUID for presign calls when `conversationId` param is `"new"`.

## Implementation Tasks

### Phase 1: Fix sizing (dashboard/page.tsx)

- [ ] Add `min-h-[44px]` to the `<input>` element at line 282
- [ ] Change container `gap-2` → `gap-3` at line 281
- [ ] Change `items-end` → `items-center` at line 281

### Phase 2: Create pending-attachments bridge

- [ ] Create `apps/web-platform/lib/pending-attachments.ts`:
  - `setPendingFiles(files: File[]): void` — stores files with current timestamp
  - `getPendingFiles(): File[]` — returns files if < 5 min old, otherwise clears and returns `[]`
  - `clearPendingFiles(): void`
  - Module-level `let pendingFiles: { files: File[]; timestamp: number } | null = null`

### Phase 3: Add attachment UI to command center form

- [ ] Add state: `attachments` (`PendingAttachment[]` — reuse type pattern from chat-input), `attachError`
- [ ] Add `validateAndAddFiles()` — import constants from `lib/attachment-constants.ts`, same validation logic as chat-input
- [ ] Add `removeAttachment()` — revoke preview URLs, remove from state
- [ ] Add hidden `<input type="file">` with same accept types as chat-input
- [ ] Add paperclip button (same styling as chat-input: `h-[44px] w-[44px] rounded-xl border border-neutral-700`)
- [ ] Add attachment preview strip above the input row (same styling as chat-input)
- [ ] Add drag/drop handlers on the form container
- [ ] Add paste handler on the text input
- [ ] Update `handleFirstRunSend`: store `File[]` via `setPendingFiles()` before `router.push`
- [ ] Update submit button disabled state: allow submit when attachments exist even without text

### Phase 4: Expose conversationId from ws-client

- [ ] In `apps/web-platform/lib/ws-client.ts`, capture `conversationId` from `session_started` message (line ~314) and expose it via the hook return value
- [ ] Add `realConversationId` (or similar) to the `useWebSocket` return type

### Phase 5: Consume pending files on chat page

- [ ] In `chat/[conversationId]/page.tsx`, import `getPendingFiles`/`clearPendingFiles`
- [ ] After initial text message is sent (`initialMsgSent === true`), check for pending files
- [ ] If files exist:
  1. Wait for `realConversationId` from ws-client (the materialized UUID)
  2. Upload each file via presign API using the real conversationId
  3. Send as follow-up message: `sendMessage("", uploadedRefs)`
  4. Handle upload failures: log error, show toast, continue without attachments
- [ ] Clear pending files after consumption (success or failure)
- [ ] Import `uploadWithProgress` from `components/chat/chat-input.tsx` — or extract to shared util if not already exported

### Phase 6: Tests

- [ ] Update `apps/web-platform/test/command-center.test.tsx`:
  - Test input and button have matching min-height
  - Test paperclip button renders and triggers file input
  - Test file validation (type, size, count limits)
  - Test attachment preview strip renders for selected files
  - Test files are stored via pending-attachments on submit
  - Test preview URL cleanup on submit and unmount
- [ ] Add `apps/web-platform/test/pending-attachments.test.ts`:
  - Test set/get/clear lifecycle
  - Test staleness guard (files older than 5 min discarded)
  - Test clear empties the store

## Acceptance Criteria

- [ ] Text input and submit button render at the same height (44px)
- [ ] Gap between input and button is visually comfortable (12px / gap-3)
- [ ] Paperclip button appears to the left of the text input
- [ ] Clicking paperclip opens file picker with same allowed types as chat (PNG, JPEG, GIF, WebP, PDF)
- [ ] Selected files show preview strip with thumbnails/icons and remove buttons
- [ ] File validation enforces same limits as chat (5 files, 20MB each)
- [ ] Drag/drop files onto the form works
- [ ] Pasting images works
- [ ] Submitting with attachments navigates to chat/new and files are uploaded and sent with the first message
- [ ] Submitting without attachments works as before (no regression)

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — UI fix and feature parity enhancement within existing patterns.

## Test Scenarios

1. **Size alignment:** Render first-run form, verify input and button heights match
2. **Attachment selection:** Click paperclip, select a PNG — verify preview appears
3. **Validation - bad type:** Select a .exe file — verify error message
4. **Validation - too large:** Select a 25MB file — verify error message
5. **Validation - too many:** Select 6 files — verify error after 5th
6. **Remove attachment:** Select file, click X on preview — verify removed
7. **Submit with text only:** Type message, submit — verify navigates to chat/new (no regression)
8. **Submit with text + files:** Type message, attach file, submit — verify navigates and file appears in chat
9. **Submit with files only:** Attach file without text, submit — verify allowed if text is empty but files exist (or verify button stays disabled — decide during implementation based on chat-input behavior)
10. **Drag and drop:** Drag image onto form — verify preview appears
11. **Paste:** Paste screenshot — verify preview appears

## Alternative Approaches Considered

| Approach | Pros | Cons | Decision |
|----------|------|------|----------|
| Zustand store for pending files | Reactive, well-known pattern | New dependency, overkill for one-shot data | Rejected |
| React Context in layout | No new deps | Layout modification, provider nesting, reactivity not needed | Rejected |
| IndexedDB for file storage | Survives page reload | Async, complex, files don't survive reload anyway since `router.push` is SPA | Rejected |
| Upload at command center (create temp conversation) | Files uploaded before navigation | Requires creating a conversation server-side before user sees chat, complex rollback | Rejected |
| **Module-level singleton** | **Simple, no deps, survives SPA nav, consumed once** | **Doesn't survive page reload** | **Chosen** |

## Non-Goals

- Drag/drop or paste on the command center's other states (conversation list, foundation cards) — only the first-run form
- Upload progress indicator on the command center form — files are small enough that upload happens after navigation
- Matching the exact chat-input textarea (auto-resize, @-mentions) — the command center input stays as a single-line text input
