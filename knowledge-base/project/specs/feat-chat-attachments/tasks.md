# Tasks: Chat Attachments

## Phase 1: Infrastructure + Upload API

- [ ] 1.1 Create migration `019_chat_attachments.sql`
  - [ ] 1.1.1 Create Supabase Storage bucket `chat-attachments` (private)
  - [ ] 1.1.2 Create `message_attachments` table with FK CASCADE to `messages`
  - [ ] 1.1.3 Add RLS policies (SELECT for conversation owner, no anon INSERT/UPDATE/DELETE)
  - [ ] 1.1.4 Add index on `message_id`
- [ ] 1.2 Update CSP `img-src` in `lib/csp.ts` to include Supabase Storage host
- [ ] 1.3 Create `app/api/attachments/presign/route.ts`
  - [ ] 1.3.1 CSRF validation (`validateOrigin`)
  - [ ] 1.3.2 Auth check (`supabase.auth.getUser()`)
  - [ ] 1.3.3 Conversation ownership verification
  - [ ] 1.3.4 File type + size validation (allowlist, 20MB max, 5 files max)
  - [ ] 1.3.5 Generate storage path and signed upload URL
  - [ ] 1.3.6 Return `{ uploadUrl, storagePath }`
- [ ] 1.4 Add `AttachmentRef` interface and extend `WSMessage` chat type in `lib/types.ts`
- [ ] 1.5 Extend `ChatMessage` in `ws-client.ts` with attachments
- [ ] 1.6 Update `sendMessage` in `ws-client.ts` to accept attachments
- [ ] 1.7 Extend `Message` interface in `lib/types.ts` with attachments
- [ ] 1.8 Add error sanitizer entries for upload errors
- [ ] 1.9 Add typed `WSErrorCode` values (`upload_failed`, `file_too_large`, `unsupported_file_type`, `too_many_files`)

## Phase 2: Client Upload UX

- [ ] 2.1 Extract chat input into `components/chat/chat-input.tsx`
- [ ] 2.2 Add file input handlers (paperclip button, drag-drop, clipboard paste) with client-side validation
- [ ] 2.3 Add attachment preview strip (thumbnails + file cards + remove button)
- [ ] 2.4 Implement presign -> upload -> send flow with progress indicators

## Phase 3: Server-Side Processing

- [ ] 3.1 Update WS chat handler to extract, validate (max 5), and forward `msg.attachments`
- [ ] 3.2 Update `sendUserMessage` (line 1187) to accept and persist attachment metadata
- [ ] 3.3 Download attachments from Storage to workspace filesystem
- [ ] 3.4 Build attachment context string for agent prompt
- [ ] 3.5 Update `startAgentSession` to include attachment context
- [ ] 3.6 Update message history API to join `message_attachments` and return signed download URLs

## Phase 4: Display + Polish

- [ ] 4.1 Update `MessageBubble` to render image thumbnails and PDF cards
- [ ] 4.2 Add click-to-expand for images (lightbox/modal)
- [ ] 4.3 Wire up attachment data from history API and WebSocket to message rendering
- [ ] 4.4 Add conversation-level storage cleanup (delete blobs before conversation DB row)

## Phase 5: Testing

- [ ] 5.1 Unit tests for presign endpoint (type validation, size validation, file count cap, auth, CSRF)
- [ ] 5.2 Unit tests for attachment metadata persistence
- [ ] 5.3 Integration test: upload -> display -> reload history
- [ ] 5.4 Test on mobile PWA (iOS Safari, Android Chrome)
- [ ] 5.5 Verify CSRF structural test includes new route
- [ ] 5.6 Test conversation deletion purges Storage objects
