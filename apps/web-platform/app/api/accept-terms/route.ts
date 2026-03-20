import type { SupabaseClient } from "@supabase/supabase-js";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { NextResponse } from "next/server";
import { TC_VERSION } from "@/lib/legal/tc-version";

async function getRedirectDestination(
  supabase: SupabaseClient,
  userId: string,
): Promise<string> {
  const { data: keys } = await supabase
    .from("api_keys")
    .select("id")
    .eq("user_id", userId)
    .eq("provider", "anthropic")
    .eq("is_valid", true)
    .limit(1);

  return !keys || keys.length === 0 ? "/setup-key" : "/dashboard";
}

export async function POST() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const serviceClient = createServiceClient();

  // Idempotency: skip write if user already accepted the current version
  const { data: existing } = await serviceClient
    .from("users")
    .select("tc_accepted_version")
    .eq("id", user.id)
    .single();

  if (existing?.tc_accepted_version === TC_VERSION) {
    const redirect = await getRedirectDestination(supabase, user.id);
    return NextResponse.json({ ok: true, redirect });
  }

  const { data, error } = await serviceClient
    .from("users")
    .update({
      tc_accepted_at: new Date().toISOString(),
      tc_accepted_version: TC_VERSION,
    })
    .eq("id", user.id)
    .select("id");

  if (error) {
    console.error("[accept-terms] Failed to record acceptance:", error);
    return NextResponse.json(
      { error: "Failed to record acceptance" },
      { status: 500 },
    );
  }

  if (!data || data.length === 0) {
    console.error("[accept-terms] User row not found for:", user.id);
    return NextResponse.json(
      { error: "User profile not found. Please try again shortly." },
      { status: 404 },
    );
  }

  const redirect = await getRedirectDestination(supabase, user.id);
  return NextResponse.json({ ok: true, redirect });
}
