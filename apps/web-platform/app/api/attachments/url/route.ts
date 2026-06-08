import { NextResponse } from "next/server";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { reportSilentFallback } from "@/server/observability";
import { toPublicStorageUrl } from "@/lib/supabase/public-storage-url";

const UUID_RE = /^[0-9a-f-]{36}$/i;

export async function POST(request: Request) {
  const { valid: originValid, origin } = validateOrigin(request);
  if (!originValid) return rejectCsrf("api/attachments/url", origin);

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
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
  if (!body.storagePath.startsWith(`${user.id}/`)) {
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
      p_user_id: user.id,
    });
    if (memberErr || !isMember) {
      reportSilentFallback(memberErr ?? null, {
        feature: "attachments",
        op: "url-route",
        message: "workspace_cutover_deny",
        extra: {
          userId: user.id,
          conversationId: conversationSegment,
          workspaceId: conversation.workspace_id,
        },
      });
      return NextResponse.json({ error: "not_a_workspace_member" }, { status: 403 });
    }
  }

  const { data, error } = await service.storage
    .from("chat-attachments")
    .createSignedUrl(body.storagePath, 3_600); // 1 hour expiry

  if (error || !data) {
    return NextResponse.json({ error: "not_found" }, { status: 404 });
  }

  // The client renders this URL as <img src> (attachment-display.tsx). The
  // service client signs against the raw SUPABASE_URL host, which CSP img-src
  // (built from NEXT_PUBLIC_SUPABASE_URL) blocks → broken preview. Rewrite to
  // the public host so it passes CSP. Same class as the workspace-logo proxy.
  return NextResponse.json({ url: toPublicStorageUrl(data.signedUrl) });
}
