import { NextResponse } from "next/server";
import { createServiceClient } from "@/lib/supabase/server";
import { encryptKey } from "@/server/byok";
import { validateToken } from "@/server/token-validators";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import logger from "@/server/logger";
import { classifyCliDroppedValue, isAcceptableSubscriptionToken } from "@/server/oauth-token-shape";
import { verifiedUserId } from "@/server/request-auth";
import { hashUserId } from "@/server/observability";
import { isCcOauthEnabled } from "@/server/cc-oauth-flag";
import * as Sentry from "@sentry/nextjs";

// #11524 — remove the caller's stored subscription token (provider
// 'anthropic_oauth') with no replacement. Goes through the service-role-only
// delete_oauth_credential RPC (migration 179), which hardcodes the provider
// (ADR-048 write boundary), so this path can never touch the user's
// 'anthropic' api_key fallback. Deliberately NO operator / CC_OAUTH_ENABLED
// fence: a user can always erase their own stored secret, including after the
// kill-switch is flipped off. Nothing is created, copied or converted.
export async function DELETE(request: Request) {
  const { valid: originValid, origin } = validateOrigin(request);
  if (!originValid) return rejectCsrf("api/keys", origin);

  const userId = await verifiedUserId(request);
  if (!userId) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  // The body must be EXACTLY { credential_type: "oauth_token" }: a bare or
  // mistyped DELETE can never reach the RPC, and the provider is never taken
  // from input. The body is never logged.
  const body: unknown = await request.json().catch(() => null);
  const keys =
    body !== null && typeof body === "object" && !Array.isArray(body)
      ? Object.keys(body)
      : [];
  if (
    keys.length !== 1 ||
    (body as Record<string, unknown>).credential_type !== "oauth_token"
  ) {
    return NextResponse.json(
      {
        error: "Unsupported credential_type",
        code: "unsupported_credential_type",
      },
      { status: 400 },
    );
  }

  const service = createServiceClient();
  const { data, error: rpcError } = await service.rpc(
    "delete_oauth_credential",
    { p_user_id: userId },
  );

  if (rpcError) {
    logger.error({ err: rpcError }, "Failed to remove oauth credential");
    Sentry.captureException(rpcError, {
      tags: { feature: "api-keys", op: "delete-oauth" },
      extra: { userIdHash: hashUserId(userId), provider: "anthropic_oauth" },
    });
    return NextResponse.json(
      { error: "Failed to remove token" },
      { status: 500 },
    );
  }

  const deleted = data === true;
  // Audit: op + outcome only. Never the token value, never the request body.
  // A real erasure (deleted: true) is emitted at WARN on purpose:
  // apps/web-platform/infra/vector.toml `app_container_warn_filter` ships only
  // pino level >= 40 to Better Stack, so an info line would be dropped before
  // the drain; erasures are low-volume, so the extra level is cheap. An
  // idempotent no-op (deleted: false) erased nothing and stays at INFO.
  // Verified in server/logger.ts: the logMethod hook mirrors every log at or
  // above SENTRY_BREADCRUMB_LEVEL (default warn) to a Sentry breadcrumb
  // carrying this object ({ deleted } included), so at the default threshold
  // the WARN erasure is mirrored and no explicit breadcrumb is added. The pino formatter pseudonymises the top-level
  // `userId` to `userIdHash` (ADR-029) in the Better Stack output; the
  // breadcrumb mirror sees the raw args before that formatter, but
  // sentry.server.config.ts beforeBreadcrumb -> scrubSentryBreadcrumb renames
  // `userId` to `userIdHash` before send. Do not hash it here too.
  if (deleted) {
    logger.warn(
      { feature: "api-keys", op: "oauth-credential-removed", userId, deleted },
      "Subscription token removed",
    );
  } else {
    logger.info(
      { feature: "api-keys", op: "oauth-credential-removed", userId, deleted },
      "Subscription token removal was a no-op",
    );
  }

  return NextResponse.json({ deleted });
}

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
    if (!isOperator || !isCcOauthEnabled()) {
      return NextResponse.json({ error: "Forbidden" }, { status: 403 });
    }

    // #11086 — shape gate (after the operator fence so a non-operator never
    // learns anything about shape). The bundled CLI silently drops a value that
    // is not shaped like a real subscription token and then reports "Not
    // logged in", so reject it here with an actionable message instead of
    // storing a credential that can never work. The message never echoes any
    // part of the submitted value.
    if (!isAcceptableSubscriptionToken(apiKey)) {
      const looksLikeApiKey = classifyCliDroppedValue(apiKey) === "api_key_shaped";
      return NextResponse.json(
        {
          error: looksLikeApiKey
            ? "That looks like an API key, not a subscription token. Run claude setup-token and paste the token it prints (it starts with sk-ant-oat)."
            : "That does not look like a subscription token. It should start with sk-ant-oat and contain no spaces; copy it again from claude setup-token.",
          code: "oauth_token_shape_invalid",
        },
        { status: 400 },
      );
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
        extra: { userIdHash: hashUserId(userId), provider: "anthropic_oauth" },
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
