import { NextResponse } from "next/server";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { encryptKey } from "@/server/byok";
import { validateToken } from "@/server/token-validators";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import logger from "@/server/logger";
import * as Sentry from "@sentry/nextjs";

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

  // feat-operator-cc-oauth — credential type. Absent/anything-else ⇒
  // 'api_key' (back-compat; both onboarding + settings POST this route
  // without the field today).
  const credentialType: "api_key" | "oauth_token" =
    body.credential_type === "oauth_token" ? "oauth_token" : "api_key";

  if (credentialType === "oauth_token") {
    // AUTHORITATIVE operator-authorization fence (AC5/AC8). The UI hides the
    // toggle for non-operators, but THIS server-side check — not UI hiding —
    // is the gate. Requires: caller in ADMIN_USER_IDS (operator/internal
    // account) AND the kill-switch on. Either off ⇒ feature inert (403).
    const isOperator =
      process.env.ADMIN_USER_IDS?.split(",").includes(user.id) ?? false;
    const ccOauthEnabled =
      process.env.CC_OAUTH_ENABLED === "1" ||
      process.env.CC_OAUTH_ENABLED === "true";
    if (!isOperator || !ccOauthEnabled) {
      return NextResponse.json({ error: "Forbidden" }, { status: 403 });
    }

    // FR6 / deepen-plan P1: NO validation probe in v1 — `setup-token` tokens
    // can't be validated by the `/v1/models` api-key GET. Write succeeds;
    // the first run validates loudly (the operator is the only user). Store
    // via the service_role-only SECURITY DEFINER RPC, which hardcodes
    // provider='anthropic_oauth' so a regressed caller cannot overwrite the
    // raw-REST 'anthropic' row through this path.
    const { encrypted, iv, tag } = encryptKey(apiKey, user.id);
    const service = createServiceClient();
    const { error: rpcError } = await service.rpc("store_oauth_credential", {
      p_user_id: user.id,
      p_encrypted: encrypted.toString("base64"),
      p_iv: iv.toString("base64"),
      p_tag: tag.toString("base64"),
    });

    if (rpcError) {
      logger.error({ err: rpcError }, "Failed to store oauth credential");
      Sentry.captureException(rpcError, {
        tags: { feature: "api-keys", op: "store-oauth" },
        extra: { userId: user.id, provider: "anthropic_oauth" },
      });
      return NextResponse.json(
        { error: "Failed to store key" },
        { status: 500 },
      );
    }

    return NextResponse.json({ valid: true });
  }

  // ---- api_key path (unchanged) ----
  // Validate against Anthropic API
  const valid = await validateToken("anthropic", apiKey);
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
    Sentry.captureException(dbError, {
      tags: { feature: "api-keys", op: "store" },
      extra: { userId: user.id, provider: "anthropic" },
    });
    return NextResponse.json(
      { error: "Failed to store key" },
      { status: 500 },
    );
  }

  return NextResponse.json({ valid: true });
}
