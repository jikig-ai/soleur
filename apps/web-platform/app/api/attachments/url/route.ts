import { NextResponse } from "next/server";
import { createServiceClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { reportSilentFallback } from "@/server/observability";
import { verifiedUserId } from "@/server/request-auth";
import { toPublicStorageUrl } from "@/lib/supabase/public-storage-url";
import { fileExtension } from "@/lib/attachment-constants";

const UUID_RE = /^[0-9a-f-]{36}$/i;

// Extensions rendered inline as <img> (attachment-display.tsx). Everything
// else (pdf, md, txt) is a file chip and is signed for DOWNLOAD only.
const INLINE_IMAGE_EXTENSIONS = new Set(["png", "jpeg", "jpg", "gif", "webp"]);

// Filename for Content-Disposition: strip path separators, quotes and
// control/line-separator characters, cap the length.
function downloadName(raw: unknown, storagePath: string): string {
  const candidate =
    typeof raw === "string" && raw.trim() !== ""
      ? raw
      : storagePath.slice(storagePath.lastIndexOf("/") + 1);
  return candidate
    // eslint-disable-next-line no-control-regex
    .replace(/[/\\"\x00-\x1f\x7f\u0085\u2028\u2029\u202a-\u202e\u2066-\u2069\u200b\ufeff]/g, "_")
    .slice(0, 255);
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

  // Non-image types are signed with `download`, which forces
  // `Content-Disposition: attachment`: a markdown/text/PDF attachment is never
  // rendered inline on the storage origin, and the chip saves under its real
  // filename instead of `<uuid>.<ext>`.
  const bucket = service.storage.from("chat-attachments");
  const { data, error } = INLINE_IMAGE_EXTENSIONS.has(fileExtension(body.storagePath))
    ? await bucket.createSignedUrl(body.storagePath, 3_600) // 1 hour expiry
    : await bucket.createSignedUrl(body.storagePath, 3_600, {
        download: downloadName(body.filename, body.storagePath),
      });

  if (error || !data) {
    return NextResponse.json({ error: "not_found" }, { status: 404 });
  }

  // The client renders this URL as <img src> (attachment-display.tsx). The
  // service client signs against the raw SUPABASE_URL host, which CSP img-src
  // (built from NEXT_PUBLIC_SUPABASE_URL) blocks → broken preview. Rewrite to
  // the public host so it passes CSP. Same class as the workspace-logo proxy.
  return NextResponse.json({ url: toPublicStorageUrl(data.signedUrl) });
}
