import { NextResponse } from "next/server";
import { createServiceClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import logger from "@/server/logger";
import { reportSilentFallback } from "@/server/observability";
import { verifiedUserId } from "@/server/request-auth";
import * as Sentry from "@sentry/nextjs";
import { randomUUID } from "crypto";
import {
  ATTACHMENT_EXTENSION_BY_TYPE,
  CONVERSATION_ID_RE,
  MAX_AGENT_READABLE_PDF_SIZE,
  MAX_ATTACHMENT_SIZE,
  isPdfAttachment,
  resolveAttachmentContentType,
} from "@/lib/attachment-constants";

export async function POST(request: Request) {
  const { valid: originValid, origin } = validateOrigin(request);
  if (!originValid) return rejectCsrf("api/attachments/presign", origin);

  // Authenticate — middleware-verified identity (x-soleur-auth-user-id);
  // absent header falls back to getUser() inside verifiedUserId (fail-closed).
  const userId = await verifiedUserId(request);

  if (!userId) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  // Parse body
  const body = await request.json().catch(() => null);
  if (
    !body ||
    typeof body.filename !== "string" ||
    typeof body.contentType !== "string" ||
    typeof body.sizeBytes !== "number" ||
    typeof body.conversationId !== "string"
  ) {
    return NextResponse.json({ error: "invalid_request" }, { status: 400 });
  }

  const { filename, sizeBytes, conversationId } = body;

  // Validate file type. The server re-resolves the canonical type from the
  // (filename, reported type) pair: the client is untrusted, and cached old
  // clients still send the raw browser-reported `file.type` (which is "" or
  // application/octet-stream for a .md). Everything below — the PDF cap and
  // the storage-path extension — derives from the RESOLVED type.
  const contentType = resolveAttachmentContentType({
    contentType: body.contentType,
    filename,
  });
  if (!contentType) {
    return NextResponse.json({ error: "unsupported_file_type" }, { status: 400 });
  }

  // Validate file size
  // Closes #3332: PDFs are bounded by the agent-readable cap (24 MB raw)
  // alongside the generic 20 MB attachment cap. `contentType` is the RESOLVED
  // type (see above), so the PDF branch keys on the type the server decided,
  // not on the client's reported value; `isPdfAttachment` also honours a `.pdf`
  // filename as a second signal.
  // Number.isFinite catches NaN/Infinity from a coerced sizeBytes.
  if (!Number.isFinite(sizeBytes) || sizeBytes <= 0) {
    return NextResponse.json({ error: "file_too_large" }, { status: 400 });
  }
  const isPdf = isPdfAttachment({ contentType, filename });
  if (isPdf && sizeBytes > MAX_AGENT_READABLE_PDF_SIZE) {
    return NextResponse.json({ error: "file_too_large" }, { status: 400 });
  }
  if (sizeBytes > MAX_ATTACHMENT_SIZE) {
    return NextResponse.json({ error: "file_too_large" }, { status: 400 });
  }

  // Shape check BEFORE any DB call. `conversationId` is interpolated into the
  // storage path below, and `conversations.id` is a uuid column, so a non-uuid
  // (`"new"`, `../x`) would be a Postgres 22P02 error rather than an empty
  // result. No match -> 404 with no lookup and no storage call.
  //
  // Contract: a 404 here no longer proves the conversation exists. A fresh
  // conversation has no row until its first `chat` message (deferred creation),
  // so this shape check plus the attachment pipeline's
  // `${userId}/${conversationId}/` prefix check (unchanged) are the gate.
  if (!CONVERSATION_ID_RE.test(conversationId)) {
    return NextResponse.json({ error: "conversation_not_found" }, { status: 404 });
  }

  // Verify conversation read-eligibility (own OR workspace co-member).
  // Mirrors mig 068 storage.objects SELECT policy: own-folder branch OR
  // is_attachment_path_workspace_member via conversations.workspace_id.
  // Inline lookup (no shared TS helper file — DHH P0-2 + code-simplicity
  // P0-1 + architecture P1-1 convergence per plan §Phase 3).
  const service = createServiceClient();
  const { data: conversation, error: lookupErr } = await service
    .from("conversations")
    .select("id, user_id, workspace_id")
    .eq("id", conversationId)
    .maybeSingle();

  // A real DB error must NOT fall through to the tolerant (no-row) branch.
  if (lookupErr) {
    reportSilentFallback(lookupErr, {
      feature: "attachments",
      op: "presign-lookup",
      extra: { userId, conversationId },
    });
    return NextResponse.json({ error: "upload_failed" }, { status: 500 });
  }

  // No row is the expected state for a fresh conversation: the path stays
  // caller-prefixed (`${userId}/...`), so it can only write into the caller's
  // own folder. An existing row still goes through the membership check.
  if (conversation && conversation.user_id !== userId) {
    const { data: isMember, error: memberErr } = await service.rpc("is_workspace_member", {
      p_workspace_id: conversation.workspace_id,
      p_user_id: userId,
    });
    if (memberErr || !isMember) {
      reportSilentFallback(memberErr ?? null, {
        feature: "attachments",
        op: "presign-route",
        message: "workspace_cutover_deny",
        extra: { userId, conversationId, workspaceId: conversation.workspace_id },
      });
      return NextResponse.json({ error: "not_a_workspace_member" }, { status: 403 });
    }
  }

  // Generate storage path
  const ext = ATTACHMENT_EXTENSION_BY_TYPE[contentType];
  const storagePath = `${userId}/${conversationId}/${randomUUID()}.${ext}`;

  // Create signed upload URL
  const { data, error } = await service.storage
    .from("chat-attachments")
    .createSignedUploadUrl(storagePath);

  if (error || !data) {
    logger.error({ err: error, storagePath }, "Failed to create signed upload URL");
    if (error) {
      Sentry.captureException(error, {
        tags: { feature: "attachments", op: "presign" },
        extra: { storagePath, userId },
      });
    } else {
      Sentry.captureMessage("signed upload URL returned no data", {
        level: "error",
        tags: { feature: "attachments", op: "presign" },
        extra: { storagePath, userId },
      });
    }
    return NextResponse.json({ error: "upload_failed" }, { status: 500 });
  }

  return NextResponse.json({
    uploadUrl: data.signedUrl,
    storagePath,
  });
}
