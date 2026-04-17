import { NextResponse } from "next/server";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import logger from "@/server/logger";
import * as Sentry from "@sentry/nextjs";
import { randomUUID } from "crypto";
import {
  ALLOWED_ATTACHMENT_TYPES,
  MAX_ATTACHMENT_SIZE,
} from "@/lib/attachment-constants";

function getExtension(contentType: string): string {
  const map: Record<string, string> = {
    "image/png": "png",
    "image/jpeg": "jpeg",
    "image/gif": "gif",
    "image/webp": "webp",
    "application/pdf": "pdf",
  };
  return map[contentType] || "bin";
}

export async function POST(request: Request) {
  const { valid: originValid, origin } = validateOrigin(request);
  if (!originValid) return rejectCsrf("api/attachments/presign", origin);

  // Authenticate
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
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

  const { filename, contentType, sizeBytes, conversationId } = body;

  // Validate file type
  if (!ALLOWED_ATTACHMENT_TYPES.has(contentType)) {
    return NextResponse.json({ error: "unsupported_file_type" }, { status: 400 });
  }

  // Validate file size
  if (sizeBytes <= 0 || sizeBytes > MAX_ATTACHMENT_SIZE) {
    return NextResponse.json({ error: "file_too_large" }, { status: 400 });
  }

  // Verify conversation ownership
  const service = createServiceClient();
  const { data: conversation } = await service
    .from("conversations")
    .select("id")
    .eq("id", conversationId)
    .eq("user_id", user.id)
    .single();

  if (!conversation) {
    return NextResponse.json({ error: "conversation_not_found" }, { status: 404 });
  }

  // Generate storage path
  const ext = getExtension(contentType);
  const storagePath = `${user.id}/${conversationId}/${randomUUID()}.${ext}`;

  // Create signed upload URL
  const { data, error } = await service.storage
    .from("chat-attachments")
    .createSignedUploadUrl(storagePath);

  if (error || !data) {
    logger.error({ err: error, storagePath }, "Failed to create signed upload URL");
    if (error) {
      Sentry.captureException(error, {
        tags: { feature: "attachments", op: "presign" },
        extra: { storagePath, userId: user.id },
      });
    } else {
      Sentry.captureMessage("signed upload URL returned no data", {
        level: "error",
        tags: { feature: "attachments", op: "presign" },
        extra: { storagePath, userId: user.id },
      });
    }
    return NextResponse.json({ error: "upload_failed" }, { status: 500 });
  }

  return NextResponse.json({
    uploadUrl: data.signedUrl,
    storagePath,
  });
}
