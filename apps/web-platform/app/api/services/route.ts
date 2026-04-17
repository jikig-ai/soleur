import { NextResponse } from "next/server";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { encryptKey } from "@/server/byok";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { validateToken } from "@/server/token-validators";
import { PROVIDER_CONFIG, EXCLUDED_FROM_SERVICES_UI } from "@/server/providers";
import { SlidingWindowCounter } from "@/server/rate-limiter";
import type { Provider } from "@/lib/types";
import logger from "@/server/logger";
import * as Sentry from "@sentry/nextjs";

// Rate limit: 10 token submissions per minute per user
// (each submission hits a third-party API for validation)
const tokenLimiter = new SlidingWindowCounter({
  windowMs: 60_000,
  maxRequests: 10,
});

function isValidServiceProvider(provider: string): provider is Provider {
  return (
    provider in PROVIDER_CONFIG &&
    !EXCLUDED_FROM_SERVICES_UI.has(provider as Provider)
  );
}

export async function POST(request: Request) {
  const { valid: originValid, origin } = validateOrigin(request);
  if (!originValid) return rejectCsrf("api/services", origin);

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  if (!tokenLimiter.isAllowed(user.id)) {
    return NextResponse.json(
      { error: "Too many requests. Please wait before adding another service." },
      { status: 429 },
    );
  }

  const body = await request.json().catch(() => null);
  if (!body?.provider || typeof body.provider !== "string") {
    return NextResponse.json(
      { error: "Missing or invalid provider" },
      { status: 400 },
    );
  }
  if (!body?.token || typeof body.token !== "string") {
    return NextResponse.json(
      { error: "Missing or invalid token" },
      { status: 400 },
    );
  }

  const provider = body.provider as string;
  const token: string = body.token.trim();

  if (token.length > 4_096) {
    return NextResponse.json(
      { error: "Token exceeds maximum length" },
      { status: 400 },
    );
  }

  if (!isValidServiceProvider(provider)) {
    return NextResponse.json(
      { error: "Unsupported provider" },
      { status: 400 },
    );
  }

  const valid = await validateToken(provider, token);
  if (!valid) {
    return NextResponse.json({ valid: false, error: "Token validation failed" });
  }

  const { encrypted, iv, tag } = encryptKey(token, user.id);

  const service = createServiceClient();
  const { error: dbError } = await service
    .from("api_keys")
    .upsert(
      {
        user_id: user.id,
        provider,
        encrypted_key: encrypted.toString("base64"),
        iv: iv.toString("base64"),
        auth_tag: tag.toString("base64"),
        is_valid: true,
        validated_at: new Date().toISOString(),
        key_version: 2,
        updated_at: new Date().toISOString(),
      },
      { onConflict: "user_id,provider" },
    );

  if (dbError) {
    logger.error({ err: dbError, userId: user.id }, "Failed to store service token");
    Sentry.captureException(dbError, {
      tags: { feature: "services", op: "store" },
      extra: { userId: user.id, provider },
    });
    return NextResponse.json(
      { error: "Failed to store token" },
      { status: 500 },
    );
  }

  return NextResponse.json({ valid: true, provider });
}

export async function GET() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { data, error } = await supabase
    .from("api_keys")
    .select("provider, is_valid, validated_at, updated_at")
    .eq("user_id", user.id);

  if (error) {
    logger.error({ err: error, userId: user.id }, "Failed to list services");
    Sentry.captureException(error, {
      tags: { feature: "services", op: "list" },
      extra: { userId: user.id },
    });
    return NextResponse.json(
      { error: "Failed to load services" },
      { status: 500 },
    );
  }

  const services = (data ?? [])
    .filter((row) => !EXCLUDED_FROM_SERVICES_UI.has(row.provider as Provider))
    .map((row) => {
      const config = PROVIDER_CONFIG[row.provider as Provider];
      return {
        provider: row.provider,
        label: config?.label ?? row.provider,
        category: config?.category ?? "infrastructure",
        isValid: row.is_valid,
        validatedAt: row.validated_at,
        updatedAt: row.updated_at,
      };
    });

  return NextResponse.json({ services });
}

export async function DELETE(request: Request) {
  const { valid: originValid, origin } = validateOrigin(request);
  if (!originValid) return rejectCsrf("api/services", origin);

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const body = await request.json().catch(() => null);
  if (!body?.provider || typeof body.provider !== "string") {
    return NextResponse.json(
      { error: "Missing or invalid provider" },
      { status: 400 },
    );
  }

  const provider = body.provider as string;
  if (!isValidServiceProvider(provider)) {
    return NextResponse.json(
      { error: "Unsupported provider" },
      { status: 400 },
    );
  }

  const service = createServiceClient();
  const { error: dbError } = await service
    .from("api_keys")
    .delete()
    .eq("user_id", user.id)
    .eq("provider", provider);

  if (dbError) {
    logger.error({ err: dbError, userId: user.id }, "Failed to delete service token");
    Sentry.captureException(dbError, {
      tags: { feature: "services", op: "delete" },
      extra: { userId: user.id, provider },
    });
    return NextResponse.json(
      { error: "Failed to disconnect service" },
      { status: 500 },
    );
  }

  return NextResponse.json({ deleted: true, provider });
}
