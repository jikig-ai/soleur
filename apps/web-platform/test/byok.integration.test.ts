/**
 * BYOK per-tenant isolation — DB + crypto integration test.
 *
 * Opt-in via BYOK_INTEGRATION_TEST=1. Runs against the real Supabase dev
 * project; requires `doppler run -p soleur -c dev` to provide env vars.
 *
 *   cd apps/web-platform && \
 *     doppler run -p soleur -c dev -- \
 *     BYOK_INTEGRATION_TEST=1 ./node_modules/.bin/vitest run test/byok.integration.test.ts
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
// this test. `beforeAll`/`afterAll` throw if any target email does not match
// — enforces hr-destructive-prod-tests-allowlist / cq-destructive-prod-tests-allowlist.
const SYNTHETIC_EMAIL_PATTERN = /^byok-isolation-[a-f0-9]{16}@soleur\.test$/;

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
    throw new Error(
      `[byok.integration] ${name} is required. Run with: ` +
        "doppler run -p soleur -c dev -- BYOK_INTEGRATION_TEST=1 ./node_modules/.bin/vitest run",
    );
  }
  return value;
}

describe.skipIf(!INTEGRATION_ENABLED)("BYOK per-tenant isolation (integration)", () => {
  let service: SupabaseClient;
  let supabaseUrl: string;
  let anonKey: string;

  const userA = {
    id: "" as string,
    email: syntheticEmail(),
    password: randomBytes(16).toString("hex"),
  };
  const userB = {
    id: "" as string,
    email: syntheticEmail(),
    password: randomBytes(16).toString("hex"),
  };

  // Captured in Phase 3 (seed), read in Phase 6 (self-decrypt).
  let seededPlaintext = "";

  beforeAll(async () => {
    supabaseUrl =
      process.env.SUPABASE_URL || requireEnv("NEXT_PUBLIC_SUPABASE_URL");
    anonKey = requireEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY");
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
      expect(error, `createUser(${user.email}) failed`).toBeNull();
      expect(data.user?.id).toBeTruthy();
      user.id = data.user!.id;

      // The RLS policy keys off public.users.id (FK'd to auth.users.id).
      // Seed the public row so api_keys inserts don't violate the FK.
      const { error: profileError } = await service
        .from("users")
        .upsert(
          { id: user.id, email: user.email },
          { onConflict: "id" },
        );
      expect(profileError, `upsert public.users for ${user.email}`).toBeNull();
    }
  }, 30_000);

  afterAll(async () => {
    if (!service) return;
    for (const user of [userA, userB]) {
      if (!user.id) continue;
      assertSynthetic(user.email);
      // public.users cascades to api_keys; auth.users cascades to public.users.
      const { error } = await service.auth.admin.deleteUser(user.id);
      // Swallow "not found" — cleanup is idempotent.
      if (error && !/not found/i.test(error.message)) {
        throw new Error(
          `afterAll: deleteUser(${user.email}) failed: ${error.message}`,
        );
      }
    }
  }, 30_000);

  test("AC 3.a — user A's encrypted BYOK key is stored via service client", async () => {
    seededPlaintext = "sk-ant-api03-test-" + randomBytes(8).toString("hex");
    const { encrypted, iv, tag } = encryptKey(seededPlaintext, userA.id);

    const { error } = await service.from("api_keys").upsert(
      {
        user_id: userA.id,
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

    expect(error).toBeNull();
  });

  test("AC 3.b SELECT — user B cannot read user A's encrypted key via RLS", async () => {
    const userBClient = createClient(supabaseUrl, anonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { error: signInErr } = await userBClient.auth.signInWithPassword({
      email: userB.email,
      password: userB.password,
    });
    expect(signInErr).toBeNull();

    // RLS silently filters rows — PostgREST returns 200 with [] for
    // table queries (per learning 2026-04-07-supabase-postgrest-anon-key-schema-listing-401).
    const { data, error } = await userBClient
      .from("api_keys")
      .select("id, encrypted_key, iv, auth_tag, user_id")
      .eq("user_id", userA.id);

    expect(error).toBeNull();
    expect(data).toEqual([]);
  });

  test("AC 3.b INSERT — user B cannot INSERT a row claiming user A's user_id", async () => {
    // The api_keys RLS policy is `for all using (auth.uid() = user_id)` with
    // no explicit WITH CHECK. Per Postgres semantics, WITH CHECK falls back
    // to USING, so INSERTs claiming another tenant's user_id are rejected.
    const userBClient = createClient(supabaseUrl, anonKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { error: signInErr } = await userBClient.auth.signInWithPassword({
      email: userB.email,
      password: userB.password,
    });
    expect(signInErr).toBeNull();

    const { error } = await userBClient.from("api_keys").insert({
      user_id: userA.id, // spoof attempt
      provider: "bedrock", // distinct provider so it's not a unique-constraint collision
      encrypted_key: "ZmFrZQ==",
      iv: "ZmFrZQ==",
      auth_tag: "ZmFrZQ==",
      is_valid: false,
      key_version: 2,
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

    // Column-type drift guard: encrypted_key/iv/auth_tag are TEXT columns
    // storing base64 strings (migration 003). A regression back to bytea
    // would cause PostgREST to return "\x..."-prefixed hex, and the test
    // below would throw for the WRONG reason — catch that at the boundary.
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
