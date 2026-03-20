import { createClient, createServiceClient } from "@/lib/supabase/server";
import { NextResponse } from "next/server";

export async function POST() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const serviceClient = createServiceClient();
  const { data, error } = await serviceClient
    .from("users")
    .update({ tc_accepted_at: new Date().toISOString() })
    .eq("id", user.id)
    .is("tc_accepted_at", null) // idempotency guard: no-op if already accepted
    .select("id");

  if (error) {
    console.error("[accept-terms] Failed to record acceptance:", error);
    return NextResponse.json(
      { error: "Failed to record acceptance" },
      { status: 500 },
    );
  }

  if (!data || data.length === 0) {
    // Either already accepted (idempotent no-op) or user row missing.
    // Check which case to distinguish success from failure.
    const { data: existing } = await serviceClient
      .from("users")
      .select("tc_accepted_at")
      .eq("id", user.id)
      .single();

    if (existing?.tc_accepted_at) {
      return NextResponse.json({ ok: true }); // already accepted
    }

    console.error("[accept-terms] User row not found for:", user.id);
    return NextResponse.json(
      { error: "User profile not found. Please try again shortly." },
      { status: 404 },
    );
  }

  return NextResponse.json({ ok: true });
}
