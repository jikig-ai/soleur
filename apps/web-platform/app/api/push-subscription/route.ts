import { NextResponse } from "next/server";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";

export async function POST(request: Request) {
  const { valid: originValid, origin } = validateOrigin(request);
  if (!originValid) return rejectCsrf("api/push-subscription", origin);

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const body = await request.json().catch(() => null);
  if (
    !body?.endpoint ||
    typeof body.endpoint !== "string" ||
    !body?.keys?.p256dh ||
    !body?.keys?.auth
  ) {
    return NextResponse.json(
      { error: "Missing endpoint or keys (p256dh, auth)" },
      { status: 400 },
    );
  }

  // Validate endpoint is HTTPS to prevent SSRF via arbitrary URLs
  if (!body.endpoint.startsWith("https://")) {
    return NextResponse.json(
      { error: "Push endpoint must use HTTPS" },
      { status: 400 },
    );
  }

  const service = createServiceClient();
  const { error } = await service.from("push_subscriptions").upsert(
    {
      user_id: user.id,
      endpoint: body.endpoint,
      p256dh: body.keys.p256dh,
      auth: body.keys.auth,
      last_used_at: new Date().toISOString(),
    },
    { onConflict: "user_id,endpoint" },
  );

  if (error) {
    return NextResponse.json(
      { error: "Failed to save subscription" },
      { status: 500 },
    );
  }

  return NextResponse.json({ success: true });
}

export async function DELETE(request: Request) {
  const { valid: originValid, origin } = validateOrigin(request);
  if (!originValid) return rejectCsrf("api/push-subscription", origin);

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const body = await request.json().catch(() => null);
  if (!body?.endpoint || typeof body.endpoint !== "string") {
    return NextResponse.json(
      { error: "Missing endpoint" },
      { status: 400 },
    );
  }

  const service = createServiceClient();
  const { error } = await service
    .from("push_subscriptions")
    .delete()
    .eq("user_id", user.id)
    .eq("endpoint", body.endpoint);

  if (error) {
    return NextResponse.json(
      { error: "Failed to remove subscription" },
      { status: 500 },
    );
  }

  return NextResponse.json({ success: true });
}
