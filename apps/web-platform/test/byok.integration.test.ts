/**
 * BYOK per-tenant isolation — DB + crypto integration test.
 *
 * Opt-in via BYOK_INTEGRATION_TEST=1. Runs against the real Supabase dev
 * project; requires `doppler run -p soleur -c dev` to provide env vars.
 *
 *   cd apps/web-platform && \
 *     doppler run -p soleur -c dev -- \
 *     env BYOK_INTEGRATION_TEST=1 ./node_modules/.bin/vitest run test/byok.integration.test.ts
 *
 * Covers AC 3 of issue #1449 — the in-memory byok.test.ts suite already
 * covers AC 1 (per-user HKDF) and AC 2 (crypto-layer cross-user fail). The
 * gap closed here is the DB-layer invariant (RLS on `api_keys`) plus an
 * end-to-end crypto check against bytes that round-tripped through Postgres.
 */

import { afterAll, beforeAll, describe, expect, test } from "vitest";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { randomBytes } from "crypto";
import { decryptKey, encryptKey } from "../server/byok";

const INTEGRATION_ENABLED = process.env.BYOK_INTEGRATION_TEST === "1";

// Only synthetic emails matching this pattern may be created or deleted by
// this test. Enforces hr-destructive-prod-tests-allowlist.
const SYNTHETIC_EMAIL_PATTERN = /^byok-isolation-[a-f0-9]{16}@soleur\.test$/;

// v2 = HKDF-derived per-user DEK. See migration 009_byok_hkdf_per_user_keys.
const CURRENT_KEY_VERSION = 2;

// Harmless base64 payload for the INSERT-spoof test (never decrypted).
const FAKE_B64 = "ZmFrZQ==";

function syntheticEmail(): string {
  return `byok-isolation-${randomBytes(8).toString("hex")}@soleur.test`;
}

function assertSynthetic(email: string): void {
  if (!SYNTHETIC_EMAIL_PATTERN.test(email)) {
    throw new Error(
      `Refusing to touch non-synthetic email "${email}" — this test only ` +
        "manipulates byok-isolation-*@soleur.test accounts.",
    );
  }
}

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`[byok.integration] ${name} is required`);
  }
  return value;
}

describe.skipIf(!INTEGRATION_ENABLED)("BYOK per-tenant isolation (integration)", () => {
  let service: SupabaseClient;
  let userBClient: SupabaseClient;

  const userA = {
    id: "",
    email: syntheticEmail(),
    password: randomBytes(16).toString("hex"),
  };
  const userB = {
    id: "",
    email: syntheticEmail(),
    password: randomBytes(16).toString("hex"),
  };

  // Seeded in beforeAll so test ordering is structural, not incidental.
  let seededPlaintext = "";

  beforeAll(async () => {
    const supabaseUrl = requireEnv("NEXT_PUBLIC_SUPABASE_URL");
    const anonKey = requireEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY");
    const serviceRoleKey = requireEnv("SUPABASE_SERVICE_ROLE_KEY");

    service = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    for (const user of [userA, userB]) {
      assertSynthetic(user.email);
      const { data, error } = await service.auth.admin.createUser({
        email: user.email,
        password: user.password,
        email_confirm: true,
      });
      // Assign id BEFORE asserting so afterAll can clean up even if
      // the post-create assertion surfaces a flaky error.
      if (data.user?.id) user.id = data.user.id;
      expect(error, `createUser(${user.email}) failed`).toBeNull();
      expect(user.id).toBeTruthy();

      // Trigger-regression canary: on_auth_user_created (migrations 001:115)
      // auto-creates the public.users row. A silent trigger regression would
      // break production signup; this SELECT catches it here instead.
      const { data: profile, error: profileError } = await service
        .from("users")
        .select("id, email")
        .eq("id", user.id)
        .single();
      expect(profileError, `public.users row missing for ${user.email}`).toBeNull();
      expect(profile?.email).toBe(user.email);
    }

    // Seed user A's ciphertext once so the remaining assertions are all
    // atomic reads. Mirrors the production write path in app/api/keys/route.ts.
    seededPlaintext = "sk-ant-api03-test-" + randomBytes(8).toString("hex");
    const { encrypted, iv, tag } = encryptKey(seededPlaintext, userA.id);

    const { error: seedError } = await service.from("api_keys").upsert(
      {
        user_id: userA.id,
        provider: "anthropic",
        encrypted_key: encrypted.toString("base64"),
        iv: iv.toString("base64"),
        auth_tag: tag.toString("base64"),
        is_valid: true,
        key_version: CURRENT_KEY_VERSION,
        updated_at: new Date().toISOString(),
      },
      { onConflict: "user_id,provider" },
    );
    expect(seedError, "seed upsert failed").toBeNull();

    // Sign in as user B once. Each sign-in counts against Supabase's
    // per-IP rate limit, so we reuse this client across the RLS tests.
    userBClient = createClient(supabaseUrl, anonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { error: signInErr } = await userBClient.auth.signInWithPassword({
      email: userB.email,
      password: userB.password,
    });
    expect(signInErr).toBeNull();
  }, 30_000);

  afterAll(async () => {
    if (!service) return;
    for (const user of [userA, userB]) {
      if (!user.id) continue;
      assertSynthetic(user.email);
      // Round-trip the allowlist against Supabase's record so a bug that
      // left user.id pointing at a pre-existing UUID while user.email still
      // held the synthetic string cannot slip through.
      const { data: check } = await service.auth.admin.getUserById(user.id);
      if (check?.user?.email && check.user.email !== user.email) {
        throw new Error(
          `afterAll: auth.users.email for ${user.id} (${check.user.email}) ` +
            `does not match synthetic email ${user.email}`,
        );
      }
      // public.users cascades to api_keys; auth.users cascades to public.users.
      const { error } = await service.auth.admin.deleteUser(user.id);
      if (error && !/not found/i.test(error.message)) {
        throw new Error(
          `afterAll: deleteUser(${user.email}) failed: ${error.message}`,
        );
      }
    }
  }, 30_000);

  test("AC 3.a — user A's seeded ciphertext is visible to the service client", async () => {
    const { data, error } = await service
      .from("api_keys")
      .select("user_id, provider, encrypted_key, iv, auth_tag, key_version")
      .eq("user_id", userA.id)
      .eq("provider", "anthropic")
      .single();
    expect(error).toBeNull();
    expect(data?.key_version).toBe(CURRENT_KEY_VERSION);
    expect(data?.encrypted_key).toBeTruthy();
  });

  test("AC 3.b SELECT — user B cannot read user A's encrypted key via RLS", async () => {
    // PostgREST returns 200 with [] for RLS-filtered table queries (per
    // learning 2026-04-07-supabase-postgrest-anon-key-schema-listing-401).
    const { data, error } = await userBClient
      .from("api_keys")
      .select("id, encrypted_key, iv, auth_tag, user_id")
      .eq("user_id", userA.id);

    expect(error).toBeNull();
    expect(data).toEqual([]);
  });

  test("AC 3.b INSERT — user B cannot INSERT a row claiming user A's user_id", async () => {
    // The api_keys RLS policy is `FOR ALL USING (auth.uid() = user_id)` with
    // no WITH CHECK clause (001_initial_schema.sql:40-42). Postgres evaluates
    // the USING expression against each candidate row for write operations
    // too, so an INSERT claiming a foreign user_id fails because
    // auth.uid() = userA.id is false when the session is user B.
    const { error } = await userBClient.from("api_keys").insert({
      user_id: userA.id, // spoof attempt
      provider: "bedrock", // distinct provider so it is not a unique-constraint collision
      encrypted_key: FAKE_B64,
      iv: FAKE_B64,
      auth_tag: FAKE_B64,
      is_valid: false,
      key_version: CURRENT_KEY_VERSION,
    });

    // Don't assert a specific PostgREST code/message — they drift across
    // versions. Invariant: the insert did not succeed.
    expect(error).not.toBeNull();
  });

  test("AC 3.c — leaked ciphertext cannot be decrypted with user B's userId", async () => {
    const { data, error } = await service
      .from("api_keys")
      .select("encrypted_key, iv, auth_tag")
      .eq("user_id", userA.id)
      .eq("provider", "anthropic")
      .single();
    expect(error).toBeNull();
    expect(data).not.toBeNull();

    // Column-type drift guard: encrypted_key/iv/auth_tag are TEXT base64
    // (migration 003). A regression back to bytea would cause PostgREST to
    // return "\x..."-prefixed hex; catch that at the boundary so the
    // decryptKey throw below is for the RIGHT reason.
    expect(typeof data!.encrypted_key).toBe("string");
    expect(data!.encrypted_key.startsWith("\\x")).toBe(false);

    const encrypted = Buffer.from(data!.encrypted_key, "base64");
    const iv = Buffer.from(data!.iv, "base64");
    const tag = Buffer.from(data!.auth_tag, "base64");

    expect(() => decryptKey(encrypted, iv, tag, userB.id)).toThrow();
  });

  test("AC 3.d — user A can decrypt their own ciphertext (round-trip sanity)", async () => {
    // Without this, a bug that broke ALL decryption (not just cross-tenant)
    // would pass the other tests tautologically.
    const { data, error } = await service
      .from("api_keys")
      .select("encrypted_key, iv, auth_tag")
      .eq("user_id", userA.id)
      .eq("provider", "anthropic")
      .single();
    expect(error).toBeNull();
    expect(data).not.toBeNull();

    const encrypted = Buffer.from(data!.encrypted_key, "base64");
    const iv = Buffer.from(data!.iv, "base64");
    const tag = Buffer.from(data!.auth_tag, "base64");

    const decrypted = decryptKey(encrypted, iv, tag, userA.id);
    expect(decrypted).toBe(seededPlaintext);
  });
});
