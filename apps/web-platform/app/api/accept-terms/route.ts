import type { SupabaseClient } from "@supabase/supabase-js";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { NextResponse } from "next/server";
import { TC_VERSION } from "@/lib/legal/tc-version";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import logger from "@/server/logger";
import * as Sentry from "@sentry/nextjs";

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

export async function POST(request: Request) {
  const { valid, origin } = validateOrigin(request);
  if (!valid) return rejectCsrf("api/accept-terms", origin);

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
    logger.error({ err: error }, "Failed to record acceptance");
    Sentry.captureException(error, {
      tags: { feature: "accept-terms", op: "record" },
      extra: { userId: user.id },
    });
    return NextResponse.json(
      { error: "Failed to record acceptance" },
      { status: 500 },
    );
  }

  if (!data || data.length === 0) {
    logger.error({ userId: user.id }, "User row not found");
    // Data inconsistency — authenticated user has no row in `users`. No Error
    // object to capture; use captureMessage so the condition is still
    // observable in Sentry.
    Sentry.captureMessage("User row not found", {
      level: "error",
      tags: { feature: "accept-terms", op: "record" },
      extra: { userId: user.id },
    });
    return NextResponse.json(
      { error: "User profile not found. Please try again shortly." },
      { status: 404 },
    );
  }

  const redirect = await getRedirectDestination(supabase, user.id);
  return NextResponse.json({ ok: true, redirect });
}
