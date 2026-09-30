import { NextResponse } from "next/server";
import { createServiceClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { reportSilentFallback } from "@/server/observability";
import { verifiedUserId } from "@/server/request-auth";
import { toPublicStorageUrl } from "@/lib/supabase/public-storage-url";
import {
  INLINE_ATTACHMENT_EXTENSIONS,
  fileExtension,
  sanitizeAttachmentFilename,
} from "@/lib/attachment-constants";

const UUID_RE = /^[0-9a-f-]{36}$/i;

// Filename for Content-Disposition: the shared sanitizer plus quotes (the
// header value is quoted), falling back to the path basename.
function downloadName(raw: unknown, storagePath: string): string {
  const candidate =
    typeof raw === "string" && raw.trim() !== ""
      ? raw
      : storagePath.slice(storagePath.lastIndexOf("/") + 1);
  return sanitizeAttachmentFilename(candidate).replace(/"/g, "_");
}

export async function POST(request: Request) {
  const { valid: originValid, origin } = validateOrigin(request);
  if (!originValid) return rejectCsrf("api/attachments/url", origin);

  const userId = await verifiedUserId(request);

  if (!userId) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  const body = await request.json().catch(() => null);
  if (!body?.storagePath || typeof body.storagePath !== "string") {
    return NextResponse.json({ error: "invalid_request" }, { status: 400 });
  }

  // Path-traversal reject (independent of own/co-member determination).
  if (body.storagePath.includes("..")) {
    return NextResponse.json({ error: "unauthorized" }, { status: 403 });
  }

  // Path-segment SSRF guard widened to own OR workspace co-member.
  // Path shape: {userId}/{conversationId}/{filename}. The own-folder check
  // mirrors mig 068's INSERT/UPDATE/DELETE policy (segment-1 must equal the
  // caller). The co-member branch mirrors the SELECT policy (segment-2 must
  // resolve to a conversation in a workspace the caller is a member of).
  const service = createServiceClient();
  if (!body.storagePath.startsWith(`${userId}/`)) {
    const segments = body.storagePath.split("/");
    const conversationSegment = segments[1];
    if (!conversationSegment || !UUID_RE.test(conversationSegment)) {
      return NextResponse.json({ error: "unauthorized" }, { status: 403 });
    }
    const { data: conversation } = await service
      .from("conversations")
      .select("id, user_id, workspace_id")
      .eq("id", conversationSegment)
      .single();
    if (!conversation) {
      return NextResponse.json({ error: "unauthorized" }, { status: 403 });
    }
    const { data: isMember, error: memberErr } = await service.rpc("is_workspace_member", {
      p_workspace_id: conversation.workspace_id,
      p_user_id: userId,
    });
    if (memberErr || !isMember) {
      reportSilentFallback(memberErr ?? null, {
        feature: "attachments",
        op: "url-route",
        message: "workspace_cutover_deny",
        extra: {
          userId,
          conversationId: conversationSegment,
          workspaceId: conversation.workspace_id,
        },
      });
      return NextResponse.json({ error: "not_a_workspace_member" }, { status: 403 });
    }
  }

  // Only images (thumbnails) and PDFs (the browser viewer) are rendered inline.
  // Every other extension is signed for DOWNLOAD (`Content-Disposition:
  // attachment`), so a markdown/text attachment is never rendered on the
  // storage origin and an unrecognised suffix fails closed.
  const ext = fileExtension(body.storagePath);
  const bucket = service.storage.from("chat-attachments");
  let inline = INLINE_ATTACHMENT_EXTENSIONS.has(ext);
  if (inline) {
    // The suffix is client-chosen and so is the stored Content-Type (own-folder
    // INSERT policy; the bucket has no allowed_mime_types), so a `.pdf` path can
    // hold text/html. Serve inline only when the STORED type agrees with the
    // suffix; anything else, or a lookup failure, is a forced download.
    const { data: info } = await bucket.info(body.storagePath);
    const stored = String(
      (info as { contentType?: string; content_type?: string } | null)?.contentType ??
        (info as { content_type?: string } | null)?.content_type ??
        "",
    ).toLowerCase();
    inline = ext === "pdf" ? stored === "application/pdf" : stored.startsWith("image/");
  }
  const { data, error } = await bucket.createSignedUrl(body.storagePath, 3_600); // 1 hour expiry

  if (error || !data) {
    return NextResponse.json({ error: "not_found" }, { status: 404 });
  }

  // The client renders this URL as <img src> (attachment-display.tsx). The
  // service client signs against the raw SUPABASE_URL host, which CSP img-src
  // (built from NEXT_PUBLIC_SUPABASE_URL) blocks → broken preview. Rewrite to
  // the public host so it passes CSP. Same class as the workspace-logo proxy.
  const publicUrl = toPublicStorageUrl(data.signedUrl);
  if (inline) return NextResponse.json({ url: publicUrl });

  // Set `download` ourselves rather than via createSignedUrl's option: that
  // option concatenates the name into the query string and only runs
  // `encodeURI`, which leaves `&`, `#` and `+` raw, so "Q&A #1.md" would save as
  // "Q". searchParams.set percent-encodes every one of them.
  const downloadUrl = new URL(publicUrl);
  downloadUrl.searchParams.set("download", downloadName(body.filename, body.storagePath));
  return NextResponse.json({ url: downloadUrl.toString() });
}
