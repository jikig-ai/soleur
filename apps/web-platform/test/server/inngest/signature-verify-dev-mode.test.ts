import { beforeAll, describe, expect, it } from "vitest";
import type { NextRequest } from "next/server";

// Positive-control sibling to signature-verify.test.ts. Asserts that the
// SAME shape of bad-signature request that returns 401 in cloud mode does
// NOT return 401 when INNGEST_DEV=1 — proves the cloud-mode 401 path is
// gated on the mode flag, not an unconditional reject. See Inngest's
// InngestCommHandler validateSignature short-circuit:
//   if (this._mode && !this._mode.isCloud) return { success: true };
//
// Lives in its own file (not the same describe as the cloud-mode tests)
// because route.ts:24 and server/inngest/client.ts:17,42 capture INNGEST_DEV
// at module-init time. Per-test env stubbing is a no-op once the module is
// cached; per-test module-cache resets force cold re-load (the root cause
// #3817 Fix 2 fixes). File-scope env + a `beforeAll` pre-warm of
// `importRoute` gives exactly one module-init pass per file, paid against
// the hook's 60s budget instead of the first test's 16s testTimeout
// (full-suite contention pushes the cold import past 16s). See #5113.
process.env.INNGEST_SIGNING_KEY =
  "signkey-test-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
process.env.INNGEST_EVENT_KEY =
  "evtkey-test-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
process.env.INNGEST_DEV = "1";

async function importRoute() {
  return await import("@/app/api/inngest/route");
}

function makePostRequest(headers: Record<string, string> = {}): NextRequest {
  return new Request("http://localhost/api/inngest?fnId=noop&stepId=step", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      ...headers,
    },
    body: JSON.stringify({ event: { name: "noop", data: {} }, events: [], ctx: {} }),
  }) as unknown as NextRequest;
}

describe("app/api/inngest/route.ts — signature verification (dev mode positive control)", () => {
  // Pre-warm the route module graph (Inngest SDK + 52 function modules) so the
  // first test doesn't pay the cold-import cost against testTimeout (16s) under
  // full-suite contention. Mirrors the pdfjs-dist pre-warm in
  // pdf-text-extract.test.ts (#4097 Fix 3). See #5113.
  beforeAll(async () => {
    await importRoute();
  }, 60_000);

  it("POST without signature is NOT 401 in dev mode (mode-flip positive control)", async () => {
    const { POST } = await importRoute();
    const res = await POST(makePostRequest(), undefined);
    expect(res.status).not.toBe(401);
  });
});
