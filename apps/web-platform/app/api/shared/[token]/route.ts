import { NextResponse } from "next/server";
import path from "path";
import { createServiceClient } from "@/lib/supabase/server";
import {
  readContent,
  KbNotFoundError,
  KbAccessDeniedError,
} from "@/server/kb-reader";
import {
  shareEndpointThrottle,
  extractClientIpFromHeaders,
  logRateLimitRejection,
} from "@/server/rate-limiter";
import logger from "@/server/logger";

export async function GET(
  request: Request,
  { params }: { params: Promise<{ token: string }> },
) {
  // Rate limiting.
  const clientIp = extractClientIpFromHeaders(request.headers);
  if (!shareEndpointThrottle.isAllowed(clientIp)) {
    logRateLimitRejection("share-endpoint", clientIp);
    return NextResponse.json(
      { error: "Too many requests" },
      { status: 429 },
    );
  }

  const { token } = await params;
  const serviceClient = createServiceClient();

  // Look up share link.
  const { data: shareLink, error: fetchError } = await serviceClient
    .from("kb_share_links")
    .select("document_path, user_id, revoked")
    .eq("token", token)
    .single();

  if (fetchError || !shareLink) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  if (shareLink.revoked) {
    return NextResponse.json(
      { error: "This link has been disabled" },
      { status: 410 },
    );
  }

  // Resolve owner's workspace.
  const { data: owner } = await serviceClient
    .from("users")
    .select("workspace_path, workspace_status")
    .eq("id", shareLink.user_id)
    .single();

  if (!owner?.workspace_path || owner.workspace_status !== "ready") {
    return NextResponse.json(
      { error: "Document no longer available" },
      { status: 404 },
    );
  }

  // Read the document using the path from the share record (NOT from the request).
  try {
    const kbRoot = path.join(owner.workspace_path, "knowledge-base");
    const result = await readContent(kbRoot, shareLink.document_path);
    logger.info(
      { event: "shared_page_viewed", token, documentPath: shareLink.document_path },
      "shared: document viewed",
    );
    return NextResponse.json({
      content: result.content,
      path: shareLink.document_path,
    });
  } catch (err) {
    if (err instanceof KbAccessDeniedError) {
      logger.warn(
        { token, path: shareLink.document_path },
        "shared: path traversal attempt blocked",
      );
      return NextResponse.json({ error: "Access denied" }, { status: 403 });
    }
    if (err instanceof KbNotFoundError) {
      return NextResponse.json(
        { error: "Document no longer available" },
        { status: 404 },
      );
    }
    logger.error({ err, token }, "shared: unexpected error");
    return NextResponse.json(
      { error: "An unexpected error occurred" },
      { status: 500 },
    );
  }
}
