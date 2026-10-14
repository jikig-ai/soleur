import { NextResponse } from "next/server";
import { createServiceClient } from "@/lib/supabase/server";
import { encryptKey } from "@/server/byok";
import { validateToken } from "@/server/token-validators";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import logger from "@/server/logger";
import { verifiedUserId } from "@/server/request-auth";
import * as Sentry from "@sentry/nextjs";

export async function POST(request: Request) {
  const { valid: originValid, origin } = validateOrigin(request);
  if (!originValid) return rejectCsrf("api/keys", origin);

  // Authenticate — middleware-verified identity (x-soleur-auth-user-id);
  // absent header falls back to getUser() inside verifiedUserId (fail-closed).
  const userId = await verifiedUserId(request);

  if (!userId) {
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
  if (!apiKey) {
    return NextResponse.json(
      { error: "Missing or invalid key" },
      { status: 400 },
    );
  }

  // #9648 B-0 — explicit allowlists, no silent coercion. The old ternaries
  // folded any unrecognized value into the default ("anthropic"/"api_key"),
  // which would POST the caller's key to api.anthropic.com for validation
  // under a provider the caller never named. Absent keeps the defaults
  // (existing callers omit both fields); a present-but-unrecognized value
  // is a 400 — BEFORE validateToken sees the key.
  const provider =
    body.provider === undefined || body.provider === "anthropic"
      ? "anthropic"
      : body.provider === "openai"
        ? "openai"
        : null;
  if (provider === null) {
    logger.warn(
      { route: "api/keys", rejectedProvider: typeof body.provider },
      "POST /api/keys rejected unknown provider",
    );
    return NextResponse.json(
      {
        error: "Unknown provider",
        code: "unknown_provider",
        allowed: ["anthropic", "openai"],
      },
      { status: 400 },
    );
  }

  // feat-operator-cc-oauth — credential type. Absent ⇒ 'api_key' (back-
  // compat; both onboarding + settings POST this route without the field
  // today). Present-but-unknown ⇒ 400, same shape as provider above.
  const credentialType =
    body.credential_type === undefined || body.credential_type === "api_key"
      ? "api_key"
      : body.credential_type === "oauth_token"
        ? "oauth_token"
        : null;
  if (credentialType === null) {
    return NextResponse.json(
      { error: "Unknown credential_type", code: "unknown_credential_type" },
      { status: 400 },
    );
  }

  if (credentialType === "oauth_token" && body.provider !== undefined && body.provider !== "anthropic") {
    // store_oauth_credential hardcodes provider='anthropic_oauth' — a
    // caller asserting another provider gets a stored row for a different
    // vendor than it named. Reject rather than silently discard.
    return NextResponse.json(
      { error: "oauth_token is anthropic-only", code: "provider_credential_mismatch" },
      { status: 400 },
    );
  }

  if (credentialType === "oauth_token") {
    // AUTHORITATIVE operator-authorization fence (AC5/AC8). The UI hides the
    // toggle for non-operators, but THIS server-side check — not UI hiding —
    // is the gate. Requires: caller in ADMIN_USER_IDS (operator/internal
    // account) AND the kill-switch on. Either off ⇒ feature inert (403).
    const isOperator =
      process.env.ADMIN_USER_IDS?.split(",").includes(userId) ?? false;
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
    const { encrypted, iv, tag } = encryptKey(apiKey, userId);
    const service = createServiceClient();
    const { error: rpcError } = await service.rpc("store_oauth_credential", {
      p_user_id: userId,
      p_encrypted: encrypted.toString("base64"),
      p_iv: iv.toString("base64"),
      p_tag: tag.toString("base64"),
    });

    if (rpcError) {
      logger.error({ err: rpcError }, "Failed to store oauth credential");
      Sentry.captureException(rpcError, {
        tags: { feature: "api-keys", op: "store-oauth" },
        extra: { userId, provider: "anthropic_oauth" },
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
  const valid = await validateToken(provider, apiKey);
  if (!valid) {
    return NextResponse.json({ valid: false });
  }

  // Encrypt and store
  const { encrypted, iv, tag } = encryptKey(apiKey, userId);

  const service = createServiceClient();
  const { error: dbError } = await service
    .from("api_keys")
    .upsert(
      {
        user_id: userId,
        provider,
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
      extra: { userId, provider },
    });
    return NextResponse.json(
      { error: "Failed to store key" },
      { status: 500 },
    );
  }

  return NextResponse.json({ valid: true });
}
