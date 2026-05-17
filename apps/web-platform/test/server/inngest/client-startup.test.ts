import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// PR-F Phase 2 (#3244, #3940). Module-load-time env-var validation for
// apps/web-platform/server/inngest/client.ts.
//
// Why this matters: the Inngest client signs outbound `inngest.send` envelopes
// with INNGEST_EVENT_KEY and the route handler at /api/inngest verifies
// inbound POSTs with INNGEST_SIGNING_KEY. Both are load-bearing for the
// trust boundary between the Stripe webhook → Inngest dev/prd substrate.
// A silent default (empty string / undefined / placeholder) would expose
// the runtime trigger surface to forged events. ADR-030 I4 requires startup-
// time signature-verify config; throwing at module load is its first half.
//
// Env-mutation discipline mirrors supabase-service.test.ts — capture ORIGINAL_*
// at top-level (before vitest workers reuse this file) and restore in afterEach,
// because vitest reuses workers across files and env leaks (see #3638).

const ORIGINAL_ENV = {
  INNGEST_SIGNING_KEY: process.env.INNGEST_SIGNING_KEY,
  INNGEST_EVENT_KEY: process.env.INNGEST_EVENT_KEY,
  INNGEST_BASE_URL: process.env.INNGEST_BASE_URL,
};

function restoreEnv(key: keyof typeof ORIGINAL_ENV) {
  if (ORIGINAL_ENV[key] === undefined) {
    delete process.env[key];
  } else {
    process.env[key] = ORIGINAL_ENV[key];
  }
}

beforeEach(() => {
  vi.resetModules();
  // Default-good baseline; each test mutates from here.
  process.env.INNGEST_SIGNING_KEY = "signkey_test_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
  process.env.INNGEST_EVENT_KEY = "evtkey_test_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
  delete process.env.INNGEST_BASE_URL;
});

afterEach(() => {
  restoreEnv("INNGEST_SIGNING_KEY");
  restoreEnv("INNGEST_EVENT_KEY");
  restoreEnv("INNGEST_BASE_URL");
});

describe("server/inngest/client.ts — module-load env validation", () => {
  it("throws at import when INNGEST_SIGNING_KEY is missing", async () => {
    delete process.env.INNGEST_SIGNING_KEY;
    await expect(import("@/server/inngest/client")).rejects.toThrow(
      /INNGEST_SIGNING_KEY/,
    );
  });

  it("throws at import when INNGEST_SIGNING_KEY is empty string", async () => {
    process.env.INNGEST_SIGNING_KEY = "";
    await expect(import("@/server/inngest/client")).rejects.toThrow(
      /INNGEST_SIGNING_KEY/,
    );
  });

  it("throws at import when INNGEST_EVENT_KEY is missing", async () => {
    delete process.env.INNGEST_EVENT_KEY;
    await expect(import("@/server/inngest/client")).rejects.toThrow(
      /INNGEST_EVENT_KEY/,
    );
  });

  it("throws at import when INNGEST_EVENT_KEY is empty string", async () => {
    process.env.INNGEST_EVENT_KEY = "";
    await expect(import("@/server/inngest/client")).rejects.toThrow(
      /INNGEST_EVENT_KEY/,
    );
  });

  it("throws at import when INNGEST_BASE_URL is set but malformed", async () => {
    process.env.INNGEST_BASE_URL = "not a url";
    await expect(import("@/server/inngest/client")).rejects.toThrow(
      /INNGEST_BASE_URL/,
    );
  });

  it("loads successfully when all required env vars are set and base URL is omitted", async () => {
    // INNGEST_BASE_URL is optional — production self-hosted deploys set it,
    // Inngest Cloud deploys leave it unset and the SDK defaults to api.inngest.com.
    const mod = await import("@/server/inngest/client");
    expect(mod.inngest).toBeDefined();
  });

  it("loads successfully when INNGEST_BASE_URL is a valid URL (self-hosted shape)", async () => {
    process.env.INNGEST_BASE_URL = "http://127.0.0.1:8288";
    const mod = await import("@/server/inngest/client");
    expect(mod.inngest).toBeDefined();
  });
});
