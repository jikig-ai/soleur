import { NextResponse } from "next/server";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";

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

  // Verify the storage path belongs to this user and reject path traversal
  if (!body.storagePath.startsWith(`${user.id}/`) || body.storagePath.includes("..")) {
    return NextResponse.json({ error: "unauthorized" }, { status: 403 });
  }

  const service = createServiceClient();
  const { data, error } = await service.storage
    .from("chat-attachments")
    .createSignedUrl(body.storagePath, 3_600); // 1 hour expiry

  if (error || !data) {
    return NextResponse.json({ error: "not_found" }, { status: 404 });
  }

  return NextResponse.json({ url: data.signedUrl });
}
