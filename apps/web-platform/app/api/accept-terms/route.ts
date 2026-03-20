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
  const { error } = await serviceClient
    .from("users")
    .update({ tc_accepted_at: new Date().toISOString() })
    .eq("id", user.id)
    .is("tc_accepted_at", null); // idempotency guard: no-op if already accepted

  if (error) {
    console.error("[accept-terms] Failed to record acceptance:", error);
    return NextResponse.json(
      { error: "Failed to record acceptance" },
      { status: 500 },
    );
  }

  return NextResponse.json({ ok: true });
}
