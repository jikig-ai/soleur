import { beforeAll, describe, expect, it } from "vitest";
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
//
// File-scope env writes are intentional and load-bearing — `route.ts:24` and
// `server/inngest/client.ts:17,42` capture INNGEST_SIGNING_KEY + INNGEST_DEV
// at module-init time (top-level `const`). Per-test env stubbing is
// ineffective once the module is cached; per-test module-cache resets force
// cold re-loads (~5s each under contention; PR #3985 timeout bump was a
// stop-gap, not a fix). The dev-mode positive-control test lives in
// signature-verify-dev-mode.test.ts so each file captures its env exactly
// once. See #3817 Fix 2. A `beforeAll` pre-warm pays the cold-import cost
// against its own 60s hook budget so the first test never races
// testTimeout (16s) under full-suite contention. See #5113.
process.env.INNGEST_SIGNING_KEY =
  "signkey-test-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
process.env.INNGEST_EVENT_KEY =
  "evtkey-test-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
process.env.INNGEST_DEV = "0";

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

describe("app/api/inngest/route.ts — signature verification (cloud mode)", () => {
  // Pre-warm the route module graph (Inngest SDK + 52 function modules) so the
  // first test doesn't pay the cold-import cost against testTimeout (16s) under
  // full-suite contention. Mirrors the pdfjs-dist pre-warm in
  // pdf-text-extract.test.ts (#4097 Fix 3). See #5113.
  beforeAll(async () => {
    await importRoute();
  }, 60_000);

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
