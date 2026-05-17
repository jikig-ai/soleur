import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { NextRequest } from "next/server";

// PR-F Phase 2 (#3244, #3940). Signature-verify gate on /api/inngest POST.
//
// The Inngest SDK enforces HMAC signature verification on inbound POST when
// (a) signingKey is configured AND (b) the runtime mode is "cloud" — not
// "dev". Self-hosted Hetzner production runs cloud mode by setting
// INNGEST_DEV=0 so the route handler validates `x-inngest-signature` against
// INNGEST_SIGNING_KEY on every step-execution POST. ADR-030 invariant I4.
//
// Test asserts: without a valid signature, the handler returns 401 BEFORE
// any function dispatches. Phase 2 ships with functions:[] empty (Phase 3
// fills cfoOnPaymentFailed in), so "before dispatch" is implicit; once
// Phase 3 lands the same gate guards the CFO function from forged events.

const ORIGINAL_ENV = {
  INNGEST_SIGNING_KEY: process.env.INNGEST_SIGNING_KEY,
  INNGEST_EVENT_KEY: process.env.INNGEST_EVENT_KEY,
  INNGEST_DEV: process.env.INNGEST_DEV,
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
  process.env.INNGEST_SIGNING_KEY =
    "signkey-test-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
  process.env.INNGEST_EVENT_KEY =
    "evtkey-test-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
  // Force cloud mode so the SDK actually validates signatures. In "dev"
  // mode (the SDK's local default) validateSignature short-circuits to
  // success — see node_modules/inngest/components/InngestCommHandler.js
  // ("if (this._mode && !this._mode.isCloud) return { success: true }").
  process.env.INNGEST_DEV = "0";
});

afterEach(() => {
  restoreEnv("INNGEST_SIGNING_KEY");
  restoreEnv("INNGEST_EVENT_KEY");
  restoreEnv("INNGEST_DEV");
});

async function importRoute() {
  return await import("@/app/api/inngest/route");
}

function makePostRequest(headers: Record<string, string> = {}): NextRequest {
  // inngest/next's `serve()` types the handler signature as accepting
  // `NextRequest`; the runtime treats it as a standard Fetch Request via
  // duck-typing. Casting here keeps the test under tsc --noEmit without
  // pulling in next/server's runtime.
  return new Request("http://localhost/api/inngest?fnId=noop&stepId=step", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      ...headers,
    },
    body: JSON.stringify({ event: { name: "noop", data: {} }, events: [], ctx: {} }),
  }) as unknown as NextRequest;
}

describe("app/api/inngest/route.ts — signature verification", () => {
  it("exports GET, POST, PUT handlers", async () => {
    const route = await importRoute();
    expect(typeof route.GET).toBe("function");
    expect(typeof route.POST).toBe("function");
    expect(typeof route.PUT).toBe("function");
  });

  it("POST without x-inngest-signature header returns 401", async () => {
    const { POST } = await importRoute();
    const res = await POST(makePostRequest(), undefined);
    expect(res.status).toBe(401);
  });

  it("POST with malformed x-inngest-signature returns 401", async () => {
    const { POST } = await importRoute();
    const res = await POST(
      makePostRequest({ "x-inngest-signature": "this-is-not-a-valid-signature" }),
      undefined,
    );
    expect(res.status).toBe(401);
  });

  it("POST with valid-shaped but wrong-HMAC signature returns 401", async () => {
    const { POST } = await importRoute();
    // Right shape (t=<unix>&s=<64-hex>), wrong HMAC.
    const t = Math.floor(Date.now() / 1000);
    const sig = `t=${t}&s=${"0".repeat(64)}`;
    const res = await POST(
      makePostRequest({ "x-inngest-signature": sig }),
      undefined,
    );
    expect(res.status).toBe(401);
  });

  it("POST with stale-timestamp signature returns 401", async () => {
    const { POST } = await importRoute();
    // Timestamp 10 minutes in the past — Inngest's signature freshness window
    // is 5 minutes (allowExpiredSignatures defaults to false). Even with a
    // correctly-shaped HMAC field, this MUST be rejected.
    const stale = Math.floor(Date.now() / 1000) - 600;
    const sig = `t=${stale}&s=${"a".repeat(64)}`;
    const res = await POST(
      makePostRequest({ "x-inngest-signature": sig }),
      undefined,
    );
    expect(res.status).toBe(401);
  });
});
