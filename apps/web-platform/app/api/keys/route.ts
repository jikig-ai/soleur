import { NextResponse } from "next/server";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { encryptKey, validateAnthropicKey } from "@/server/byok";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import logger from "@/server/logger";

export async function POST(request: Request) {
  const { valid: originValid, origin } = validateOrigin(request);
  if (!originValid) return rejectCsrf("api/keys", origin);

  // Authenticate
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  // Parse body
  const body = await request.json().catch(() => null);
  if (!body?.key || typeof body.key !== "string") {
    return NextResponse.json(
      { error: "Missing or invalid key" },
      { status: 400 },
    );
  }

  const apiKey: string = body.key.trim();

  // Validate against Anthropic API
  const valid = await validateAnthropicKey(apiKey);
  if (!valid) {
    return NextResponse.json({ valid: false });
  }

  // Encrypt and store
  const { encrypted, iv, tag } = encryptKey(apiKey, user.id);

  const service = createServiceClient();
  const { error: dbError } = await service
    .from("api_keys")
    .upsert(
      {
        user_id: user.id,
        provider: "anthropic",
        encrypted_key: encrypted.toString("base64"),
        iv: iv.toString("base64"),
        auth_tag: tag.toString("base64"),
        is_valid: true,
        key_version: 2,
        updated_at: new Date().toISOString(),
      },
      { onConflict: "user_id,provider" },
    );

  if (dbError) {
    logger.error({ err: dbError }, "Failed to store API key");
    return NextResponse.json(
      { error: "Failed to store key" },
      { status: 500 },
    );
  }

  return NextResponse.json({ valid: true });
}
