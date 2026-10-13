# Feature: Chat Attachments

## Problem Statement

Users cannot share visual context (screenshots, mockups, PDFs) with AI domain leader agents in chat conversations. Communication is text-only, limiting the quality of agent responses for tasks that benefit from visual input — error screenshots, competitor page analysis, contract review, design feedback.

## Goals

- Users can upload images and PDFs in any chat conversation
- Uploaded files are displayed inline in the chat message thread
- AI agents can process uploaded images and PDFs via Claude's vision and PDF capabilities
- Upload experience supports paperclip button, drag-and-drop, and clipboard paste

## Non-Goals

- Video/audio file support (Claude cannot process video; defer until user demand)
- Knowledge base file upload (separate issue — different UI surface, shared infra)
- Per-user storage quotas (needs pricing model input; defer to billing feature)
- Offline attachment access (PWA cache for attachments is Phase 4+)
- Direct multimodal Agent SDK integration (blocked by SDK accepting string-only prompts)

## Functional Requirements

### FR1: File Upload via Presigned URL

User selects a file (paperclip button, drag-drop, or paste). Client requests a presigned upload URL from the server, validates file type and size, then uploads directly to Supabase Storage. No file bytes pass through the application server.

### FR2: Attachment Display in Chat

Uploaded images render as inline thumbnails in the message bubble. PDFs render as a named file card with download link. Both user and assistant messages can reference attachments. Conversation history API returns attachment metadata.

### FR3: AI Agent Processing

Server downloads the uploaded file from Supabase Storage to the workspace filesystem, then references the file path in the agent prompt text. The agent processes the file using Claude's native vision (images) or PDF reading capabilities.

### FR4: Chat Input UX

Paperclip icon button in the chat input area opens the native file picker. Drag-and-drop onto the chat area shows a drop zone overlay. Clipboard paste (Ctrl+V / Cmd+V with image data) attaches the pasted image. Upload progress is shown inline.

### FR5: Attachment Lifecycle

Attachments are scoped to the conversation. When a conversation is deleted (including GDPR account deletion), all associated Supabase Storage objects are purged. No orphaned files.

## Technical Requirements

### TR1: Supabase Storage Bucket

Create a `chat-attachments` bucket with RLS policies scoped to conversation ownership. Signed URLs for downloads with reasonable expiry. Storage objects keyed by `{user_id}/{conversation_id}/{uuid}.{ext}`.

### TR2: Database Schema

New `message_attachments` table with FK to `messages`. Columns: id, message_id, storage_path, filename, content_type, size_bytes, created_at. Non-breaking addition — existing message queries unchanged.

### TR3: CSP Update

Add Supabase Storage origin to `img-src` directive in `lib/csp.ts`. Add `media-src` if needed for future file types.

### TR4: File Validation

Server-side validation in presign endpoint: allowed MIME types (image/png, image/jpeg, image/gif, image/webp, application/pdf), max 20 MB per file. Reject with typed error codes (`file_too_large`, `unsupported_file_type`).

### TR5: Error Handling

All Supabase Storage calls must destructure `{ error }`. Upload failures surfaced via typed `WSErrorCode`. Storage errors sanitized through `error-sanitizer.ts` before client delivery.

### TR6: WebSocket Protocol Extension

Extend `WSMessage` `chat` type with optional `attachments` array field containing storage paths, filenames, content types, and sizes. No binary data over WebSocket.

### TR7: Session Key Composite Pattern

Attachment upload state (progress, pending files) must use composite key `(userId, conversationId, leaderId)` to avoid collision in multi-leader sessions.
