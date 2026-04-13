# Tasks: Upload Progress Indicator

## Phase 1: Setup

- [x] 1.1 Read and understand current `chat-input.tsx` upload flow
- [x] 1.2 Read and understand existing test file `chat-input-attachments.test.tsx`

## Phase 2: Core Implementation (TDD)

- [x] 2.1 Write failing tests for XHR upload progress behavior
  - [x] 2.1.1 Test: progress updates incrementally during upload (not just 0/50/100)
  - [x] 2.1.2 Test: progress shows percentage text during upload
  - [x] 2.1.3 Test: completion state shows "Uploaded" text when progress hits 100
  - [x] 2.1.4 Test: error state preserved on upload failure
  - [x] 2.1.5 Test: multiple files show individual progress (covered by sequential upload pattern)
  - [x] 2.1.6 Test: removing attachment during upload aborts XHR
- [x] 2.2 Add `uploadWithProgress` helper function using XMLHttpRequest
  - Returns `{ promise, xhr }` for abort support
  - File: `apps/web-platform/components/chat/chat-input.tsx`
- [x] 2.3 Replace `fetch()` PUT in `uploadAttachments` with `uploadWithProgress`
  - Direct 0-100% progress mapping from XHR events
  - Store active XHR in ref map for abort support
  - File: `apps/web-platform/components/chat/chat-input.tsx`
- [x] 2.4 Update `removeAttachment` to abort in-flight XHR
  - File: `apps/web-platform/components/chat/chat-input.tsx`
- [x] 2.5 Update progress UI in attachment preview strip
  - Add percentage label alongside progress bar
  - Use `transition: width 150ms ease` (not `transition-all`)
  - Add completion state ("Uploaded") at 100%
  - File: `apps/web-platform/components/chat/chat-input.tsx`
- [x] 2.6 Update existing tests to mock XHR instead of second `fetch()` call
  - Use global XHR stub pattern from plan
  - File: `apps/web-platform/test/chat-input-attachments.test.tsx`

## Phase 3: Testing

- [x] 3.1 Run full test suite and verify no regressions (987 pass, 0 fail)
- [ ] 3.2 Manual QA: attach single image, verify progress bar fills smoothly
- [ ] 3.3 Manual QA: attach PDF (larger file), verify percentage increments
- [ ] 3.4 Manual QA: attach multiple files, verify sequential progress
- [ ] 3.5 Manual QA: test drag-and-drop and paste attachment flows still work
- [ ] 3.6 Manual QA: remove attachment during upload, verify abort
