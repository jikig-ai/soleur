import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { listInngestRunsForFounder } from "@/lib/inngest/list-runs";

// #10136 — the app->inngest hop is plain HTTP on the private network, so the
// Authorization bearer must be the HASHED signing key (the SDK's own wire form:
// signkey-prod-<sha256>), never the raw key. The fixture digest below is the
// exact output of the vendored SDK's `hashSigningKey`
// (node_modules/inngest/helpers/strings.js) on the same input — verified by
// executing the vendored function, not re-derived.

const FOUNDER = "123e4567-e89b-12d3-a456-426614174000";
const RAW_KEY =
  "signkey-prod-0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
const HASHED_KEY =
  "signkey-prod-4884fdaafea47c29fea7159d0daddd9c085d6200e1359e85bb81736af6b7c837";
const BARE_HEX_KEY = "abcdef0123456789";
const BARE_HEX_HASHED =
  "eb9bfb0760ae28afdd80e2a5354756b4b5c3bcfa0afc5e96b4ae7b36c8faa380";

interface CapturedCall {
  url: string;
  authorization: string | undefined;
}

let calls: CapturedCall[];

const envBackup: Record<string, string | undefined> = {};

function setEnv(key: string, value: string | undefined) {
  if (!(key in envBackup)) envBackup[key] = process.env[key];
  if (value === undefined) delete process.env[key];
  else process.env[key] = value;
}

beforeEach(() => {
  calls = [];
  setEnv("INNGEST_BASE_URL", "http://10.0.1.40:8288");
  vi.stubGlobal(
    "fetch",
    vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input);
      calls.push({
        url,
        authorization: (init?.headers as Record<string, string> | undefined)?.[
          "Authorization"
        ],
      });
      const body = url.includes("/runs")
        ? { data: [{ id: "r1", started_at: null, ended_at: null, status: "ok" }] }
        : { data: [{ id: "e1", data: { founderId: FOUNDER } }] };
      return new Response(JSON.stringify(body), { status: 200 });
    }),
  );
});

afterEach(() => {
  vi.unstubAllGlobals();
  for (const [k, v] of Object.entries(envBackup)) {
    if (v === undefined) delete process.env[k];
    else process.env[k] = v;
    delete envBackup[k];
  }
});

describe("listInngestRunsForFounder signing-key wire form (#10136)", () => {
  it("sends the hashed bearer on every request; the raw key appears nowhere", async () => {
    setEnv("INNGEST_SIGNING_KEY", RAW_KEY);
    const runs = await listInngestRunsForFounder({ founderId: FOUNDER, limit: 5 });
    expect(runs).toHaveLength(1);
    expect(calls.length).toBeGreaterThanOrEqual(2);
    for (const call of calls) {
      expect(call.authorization).toBe(`Bearer ${HASHED_KEY}`);
      expect(call.authorization).not.toContain(RAW_KEY);
      // The raw 64-hex body must not appear even prefix-stripped.
      expect(call.authorization).not.toContain(RAW_KEY.slice("signkey-prod-".length));
    }
  });

  it("bare-hex key (no signkey- prefix) sends the bare sha256 bearer per SDK semantics", async () => {
    setEnv("INNGEST_SIGNING_KEY", BARE_HEX_KEY);
    await listInngestRunsForFounder({ founderId: FOUNDER, limit: 5 });
    for (const call of calls) {
      expect(call.authorization).toBe(`Bearer ${BARE_HEX_HASHED}`);
      expect(call.authorization).not.toContain(BARE_HEX_KEY);
    }
  });

  it("non-hex key body fails closed: named error, zero requests emitted", async () => {
    setEnv("INNGEST_SIGNING_KEY", "signkey-prod-zz-not-hex");
    await expect(
      listInngestRunsForFounder({ founderId: FOUNDER, limit: 5 }),
    ).rejects.toThrow("inngest_signing_key_malformed");
    expect(calls).toHaveLength(0);
  });

  it("odd-length hex body fails closed the same way", async () => {
    setEnv("INNGEST_SIGNING_KEY", "signkey-prod-abc");
    await expect(
      listInngestRunsForFounder({ founderId: FOUNDER, limit: 5 }),
    ).rejects.toThrow("inngest_signing_key_malformed");
    expect(calls).toHaveLength(0);
  });
});
