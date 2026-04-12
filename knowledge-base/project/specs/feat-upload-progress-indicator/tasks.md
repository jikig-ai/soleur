# Tasks: Upload Progress Indicator

## Phase 1: Setup

- [ ] 1.1 Read and understand current `chat-input.tsx` upload flow
- [ ] 1.2 Read and understand existing test file `chat-input-attachments.test.tsx`

## Phase 2: Core Implementation (TDD)

- [ ] 2.1 Write failing tests for XHR upload progress behavior
  - [ ] 2.1.1 Test: progress updates incrementally during upload (not just 0/50/100)
  - [ ] 2.1.2 Test: progress shows percentage text during upload
  - [ ] 2.1.3 Test: completion state shows "Uploaded" text when progress hits 100
  - [ ] 2.1.4 Test: error state preserved on upload failure
  - [ ] 2.1.5 Test: multiple files show individual progress
- [ ] 2.2 Add `uploadWithProgress` helper function using XMLHttpRequest
  - File: `apps/web-platform/components/chat/chat-input.tsx`
- [ ] 2.3 Replace `fetch()` PUT in `uploadAttachments` with `uploadWithProgress`
  - Map presign phase to 0-10%, upload phase to 10-100%
  - File: `apps/web-platform/components/chat/chat-input.tsx`
- [ ] 2.4 Update progress UI in attachment preview strip
  - Add percentage label alongside progress bar
  - Add completion state ("Uploaded" or checkmark) at 100%
  - File: `apps/web-platform/components/chat/chat-input.tsx`
- [ ] 2.5 Update existing tests to mock XHR instead of second `fetch()` call
  - File: `apps/web-platform/test/chat-input-attachments.test.tsx`

## Phase 3: Testing

- [ ] 3.1 Run full test suite and verify no regressions
- [ ] 3.2 Manual QA: attach single image, verify progress bar fills smoothly
- [ ] 3.3 Manual QA: attach PDF (larger file), verify percentage increments
- [ ] 3.4 Manual QA: attach multiple files, verify sequential progress
- [ ] 3.5 Manual QA: test drag-and-drop and paste attachment flows still work
