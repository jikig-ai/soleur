---
title: "Service-role IDOR via untrusted WebSocket attachment metadata"
date: 2026-04-11
category: security-issues
tags: [supabase, websocket, idor, service-role, attachments]
symptoms: "Code review agents flagged that client-supplied storagePath in WS messages bypasses RLS when passed to service-role Supabase Storage download"
module: server/agent-runner.ts
---

# Learning: Service-role IDOR via untrusted WebSocket attachment metadata

## Problem

When implementing chat attachments, the presign API route correctly validates ownership (user owns the conversation) and generates safe storage paths. However, the WebSocket chat handler accepted `msg.attachments` from the client and passed `att.storagePath` directly to `supabase().storage.download()` using the service-role client. Since service-role bypasses RLS, a malicious client could craft a WS message with an arbitrary `storagePath` (e.g., `../other-user-id/conv/secret.pdf`) to read any user's attachments.

The same pattern applied to `att.filename` (path separator injection risk) and `att.contentType` (no server-side allowlist check on the WS path).

## Solution

Added server-side validation in `sendUserMessage` before any service-role operation:

1. Validate `storagePath` starts with `${userId}/${conversationId}/` and reject `..` sequences
2. Validate `contentType` against the same allowlist used by the presign endpoint
3. Sanitize `filename` by stripping path separators (`/`, `\`)
4. Derive file extensions from `contentType` (trusted) instead of `filename` (untrusted)
5. Added `..` rejection to the signed URL endpoint as well

## Key Insight

When a presign endpoint generates safe paths but a separate code path (WebSocket handler) accepts the same metadata from the client, the second path must re-validate everything. The presign endpoint's validation does not transfer to the WS path. Every service-role operation that touches user-supplied data needs its own input validation, regardless of whether a "safe" path was generated elsewhere.

The general pattern: **if a service-role client will act on data, validate it at the point of use, not just at the point of generation.**

## Session Errors

1. **Bare repo path confusion** -- Attempted to read files from the bare repo root instead of the worktree. **Prevention:** Already covered by AGENTS.md worktree rules; this was a minor navigation error corrected in seconds.

2. **Test regression from signature change** -- Adding optional `attachments` parameter to `sendMessage` caused existing test to fail because `handleSend` passed `undefined` through. **Prevention:** When adding optional parameters to existing functions, verify the calling code doesn't forward `undefined` to mock assertions that use exact matching (`toHaveBeenCalledWith`).

3. **IDOR via unvalidated storagePath** -- Client-supplied `storagePath` in WS attachments passed to service-role download without ownership check. **Prevention:** Every service-role operation on user-supplied data must validate ownership at point of use (added to this learning as a constitution promotion candidate).

4. **Untrusted filename/contentType** -- WS attachment metadata accepted without server-side validation on the WS path. **Prevention:** Validate all fields from untrusted sources (WS, HTTP body) before any server-side operation, even when a separate endpoint generates "safe" values.

## Tags

category: security-issues
module: server/agent-runner.ts, server/ws-handler.ts
