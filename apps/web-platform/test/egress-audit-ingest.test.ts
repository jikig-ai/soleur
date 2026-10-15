import { readFileSync } from "node:fs";
import path from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// #9545 PR1 — POST /api/internal/egress-audit-ingest.
// Route order (ruled by the CTO agent): loopback Host + no forwarding headers (401),
// missing secret (2xx drop, never 5xx), bearer (401), body cap (413), JSON/zod (400),
// per-row bucket bounds, workspace -> org lookup, per-org flag, RPC.
// Synthetic data only: hosts are *.example.test, ids are random-looking constants.

const ORIG = {
  cur: process.env.EGRESS_AUDIT_INGEST_TOKEN,
  prev: process.env.EGRESS_AUDIT_INGEST_TOKEN_PREVIOUS,
};

const {
  mockRpc,
  mockIn,
  mockFrom,
  mockGetRuntimeFlag,
  mockReport,
  mockWarnDebounced,
} = vi.hoisted(() => ({
  mockRpc: vi.fn(),
  mockIn: vi.fn(),
  mockFrom: vi.fn(),
  mockGetRuntimeFlag: vi.fn(),
  mockReport: vi.fn(),
  mockWarnDebounced: vi.fn(),
}));

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => ({
    from: mockFrom,
    rpc: mockRpc,
  }),
}));
vi.mock("@/lib/feature-flags/server", () => ({
  getRuntimeFlag: mockGetRuntimeFlag,
}));
vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReport,
  mirrorWarnWithDebounce: mockWarnDebounced,
}));

import { POST } from "@/app/api/internal/egress-audit-ingest/route";

const TOKEN = "current-token-0123456789abcdef";
const PREVIOUS = "previous-token-0123456789abcd";
const WS_A = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const WS_B = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
const ORG_A = "0a0a0a0a-0a0a-4a0a-8a0a-0a0a0a0a0a0a";
const ORG_B = "0b0b0b0b-0b0b-4b0b-8b0b-0b0b0b0b0b0b";

const floor15 = (ms: number): string =>
  new Date(Math.floor(ms / 900_000) * 900_000).toISOString().replace(/\.\d{3}Z$/, "Z");

function row(ws: string, over: Record<string, unknown> = {}) {
  const b = floor15(Date.now() - 3600_000);
  return {
    workspace_id: ws,
    bucket_start: b,
    requested_host: "a.example.test",
    decision: "allowed",
    source_host: "web-1",
    request_count: 3,
    bytes_out: 10,
    first_seen: b,
    last_seen: b,
    ...over,
  };
}

function req(
  body: unknown,
  opts: { auth?: string | null; host?: string; extra?: Record<string, string>; raw?: string } = {},
): Request {
  const headers = new Headers({ "content-type": "application/json" });
  headers.set("host", opts.host ?? "127.0.0.1:3000");
  const auth = "auth" in opts ? opts.auth : `Bearer ${TOKEN}`;
  if (auth) headers.set("authorization", auth);
  for (const [k, v] of Object.entries(opts.extra ?? {})) headers.set(k, v);
  return new Request("http://127.0.0.1:3000/api/internal/egress-audit-ingest", {
    method: "POST",
    headers,
    body: opts.raw ?? JSON.stringify(body),
  });
}

const json = async (r: Response) => (await r.json()) as Record<string, unknown>;

beforeEach(() => {
  vi.clearAllMocks();
  process.env.EGRESS_AUDIT_INGEST_TOKEN = TOKEN;
  delete process.env.EGRESS_AUDIT_INGEST_TOKEN_PREVIOUS;
  // workspaces lookup: both workspaces exist, in different orgs.
  mockIn.mockResolvedValue({
    data: [
      { id: WS_A, organization_id: ORG_A },
      { id: WS_B, organization_id: ORG_B },
    ],
    error: null,
  });
  mockFrom.mockReturnValue({ select: () => ({ in: mockIn }) });
  mockGetRuntimeFlag.mockResolvedValue(true);
  mockRpc.mockResolvedValue({
    data: { accepted: 1, skipped_unknown: 0, skipped_toggle_off: 0, skipped_invalid: 0 },
    error: null,
  });
});

afterEach(() => {
  if (ORIG.cur === undefined) delete process.env.EGRESS_AUDIT_INGEST_TOKEN;
  else process.env.EGRESS_AUDIT_INGEST_TOKEN = ORIG.cur;
  if (ORIG.prev === undefined) delete process.env.EGRESS_AUDIT_INGEST_TOKEN_PREVIOUS;
  else process.env.EGRESS_AUDIT_INGEST_TOKEN_PREVIOUS = ORIG.prev;
});

describe("authentication", () => {
  it("accepts the current token", async () => {
    const res = await POST(req([row(WS_A)]));
    expect(res.status).toBe(202);
    expect(mockRpc).toHaveBeenCalledTimes(1);
  });

  it("accepts the previous token during rotation", async () => {
    process.env.EGRESS_AUDIT_INGEST_TOKEN_PREVIOUS = PREVIOUS;
    const res = await POST(req([row(WS_A)], { auth: `Bearer ${PREVIOUS}` }));
    expect(res.status).toBe(202);
  });

  it("with both tokens configured, the current token still passes and an unrelated one fails", async () => {
    process.env.EGRESS_AUDIT_INGEST_TOKEN_PREVIOUS = PREVIOUS;
    expect((await POST(req([row(WS_A)]))).status).toBe(202);
    expect((await POST(req([row(WS_A)], { auth: "Bearer not-the-token-0123456789abcdef" }))).status).toBe(401);
  });

  it("rejects an unrelated token, a missing header and a previous token that is not configured", async () => {
    expect((await POST(req([row(WS_A)], { auth: "Bearer not-the-token-0123456789abcdef" }))).status).toBe(401);
    expect((await POST(req([row(WS_A)], { auth: null }))).status).toBe(401);
    expect((await POST(req([row(WS_A)], { auth: `Bearer ${PREVIOUS}` }))).status).toBe(401);
    expect(mockRpc).not.toHaveBeenCalled();
  });

  it("returns a bare 401 with no detail", async () => {
    const res = await POST(req([row(WS_A)], { auth: "Bearer wrong" }));
    expect(res.status).toBe(401);
    expect(await json(res)).toEqual({ error: "Unauthorized" });
  });

  it("a missing secret never returns 5xx: it answers 2xx and drops the batch", async () => {
    delete process.env.EGRESS_AUDIT_INGEST_TOKEN;
    const res = await POST(req([row(WS_A)]));
    expect(res.status).toBeLessThan(300);
    expect(res.status).toBeGreaterThanOrEqual(200);
    expect(mockRpc).not.toHaveBeenCalled();
    expect(mockWarnDebounced).toHaveBeenCalled();
  });

  it("in production the global env mirror of the flag being on is refused (a Flagsmith outage must not open collection)", async () => {
    vi.stubEnv("NODE_ENV", "production");
    vi.stubEnv("FLAG_EGRESS_AUDIT_COLLECTION", "1");
    try {
      const res = await POST(req([row(WS_A)]));
      expect(res.status).toBe(202);
      expect(mockRpc).not.toHaveBeenCalled();
      expect(mockGetRuntimeFlag).not.toHaveBeenCalled();
      expect(mockWarnDebounced.mock.calls.map((c) => c[3])).toContain("env-fallback-on");
    } finally {
      vi.unstubAllEnvs();
    }
  });

  it("outside production the env mirror does not block ingest", async () => {
    vi.stubEnv("FLAG_EGRESS_AUDIT_COLLECTION", "1");
    try {
      expect((await POST(req([row(WS_A)]))).status).toBe(202);
      expect(mockRpc).toHaveBeenCalledTimes(1);
    } finally {
      vi.unstubAllEnvs();
    }
  });

  it("an empty configured secret is treated as missing", async () => {
    process.env.EGRESS_AUDIT_INGEST_TOKEN = "";
    const res = await POST(req([row(WS_A)], { auth: "Bearer " }));
    expect(res.status).toBeLessThan(300);
    expect(mockRpc).not.toHaveBeenCalled();
  });

  it("compares tokens in constant time (source assertion)", () => {
    const src = readFileSync(path.join(__dirname, "../server/egress-audit-ingest.ts"), "utf8");
    expect(src).toMatch(/timingSafeEqual/);
    expect(src).not.toMatch(/token\s*===|===\s*token|header\s*===/i);
  });
});

describe("network surface", () => {
  it.each(["127.0.0.1:3000", "localhost:3000", "[::1]:3000", "127.0.0.1"])("accepts loopback Host %s", async (host) => {
    const res = await POST(req([row(WS_A)], { host }));
    expect(res.status).toBe(202);
  });

  it.each(["app.soleur.ai", "evil.example.test:3000", "127.0.0.1.evil.example.test", ""])(
    "rejects non-loopback Host %j",
    async (host) => {
      const res = await POST(req([row(WS_A)], { host }));
      expect(res.status).toBe(401);
      expect(mockRpc).not.toHaveBeenCalled();
    },
  );

  // The route's proxy-marker rule rests on how Next.js decorates a request (it adds x-forwarded-*
  // itself). That was measured on 16.3.x. A minor upgrade must re-measure, so this fails loudly
  // instead of silently 401ing every batch or silently weakening the check.
  it("pins the Next.js minor the proxy-marker rule was measured on (re-measure the injected headers on upgrade)", () => {
    const pkg = JSON.parse(readFileSync(path.join(__dirname, "../node_modules/next/package.json"), "utf8")) as { version: string };
    expect(pkg.version).toMatch(/^16\.3\./);
  });

  it.each(["forwarded", "cf-connecting-ip", "cf-ray", "x-real-ip"])(
    "rejects a request carrying %s (it arrived through a proxy)",
    async (name) => {
      const res = await POST(req([row(WS_A)], { extra: { [name]: "203.0.113.9" } }));
      expect(res.status).toBe(401);
      expect(mockRpc).not.toHaveBeenCalled();
    },
  );

  it("rejects a multi-hop x-forwarded-for chain", async () => {
    const res = await POST(req([row(WS_A)], { extra: { "x-forwarded-for": "203.0.113.9, 172.17.0.1" } }));
    expect(res.status).toBe(401);
    expect(mockRpc).not.toHaveBeenCalled();
  });

  // Measured on Next 16.3.8: the framework adds all four x-forwarded-* headers to EVERY request
  // it serves, including Vector's. A check on them 401s every legitimate batch.
  it("accepts the x-forwarded-* headers Next.js adds to a request from Vector", async () => {
    const res = await POST(
      req([row(WS_A)], {
        extra: {
          "x-forwarded-for": "172.17.0.1",
          "x-forwarded-host": "127.0.0.1:3000",
          "x-forwarded-proto": "http",
          "x-forwarded-port": "3000",
        },
      }),
    );
    expect(res.status).toBe(202);
    expect(mockRpc).toHaveBeenCalledTimes(1);
  });
});

describe("body validation", () => {
  it("rejects an oversize body with 413 before parsing", async () => {
    const res = await POST(req(null, { raw: "[" + " ".repeat(600 * 1024) + "]" }));
    expect(res.status).toBe(413);
    expect(mockRpc).not.toHaveBeenCalled();
  });

  it("rejects malformed JSON and a non-array body with 400", async () => {
    expect((await POST(req(null, { raw: "{not json" }))).status).toBe(400);
    expect((await POST(req({ rows: [] }))).status).toBe(400);
    expect(mockRpc).not.toHaveBeenCalled();
  });

  it("counts the body in bytes: a multi-byte body under the character count but over the byte cap is 413", async () => {
    // 300k two-byte characters = 600 kB > 512 kB cap, but only 300k characters.
    const res = await POST(req(null, { raw: "[\"" + "é".repeat(300_000) + "\"]" }));
    expect(res.status).toBe(413);
  });

  it("rejects a chunked body that exceeds the cap without a content-length", async () => {
    const big = "[" + " ".repeat(600 * 1024) + "]";
    const stream = new ReadableStream<Uint8Array>({
      start(c) {
        const enc = new TextEncoder().encode(big);
        for (let i = 0; i < enc.length; i += 16 * 1024) c.enqueue(enc.slice(i, i + 16 * 1024));
        c.close();
      },
    });
    const headers = new Headers({ host: "127.0.0.1:3000", authorization: `Bearer ${TOKEN}` });
    const r = new Request("http://127.0.0.1:3000/api/internal/egress-audit-ingest", {
      method: "POST",
      headers,
      body: stream,
      // @ts-expect-error duplex is required by undici for a stream body
      duplex: "half",
    });
    expect((await POST(r)).status).toBe(413);
  });

  it("drops each malformed row and counts it, without failing the good rows", async () => {
    const bad = [
      row("not-a-uuid"),
      row(WS_A.toUpperCase()),
      row(WS_A, { requested_host: "" }),
      row(WS_A, { requested_host: "h".repeat(254) }),
      row(WS_A, { requested_host: "has space.example.test" }),
      row(WS_A, { requested_host: "nul\u0000.example.test" }),
      row(WS_A, { request_count: -1 }),
      row(WS_A, { request_count: 1.5 }),
      row(WS_A, { bucket_start: "yesterday" }),
      row(WS_A, { source_host: "Web_1" }),
      row(WS_A, { decision: "" }),
      row(WS_A, { decision: "TCP_DENIED" }),
      { ...row(WS_A), user_id: "extra-key-not-allowed" },
    ];
    const res = await POST(req([...bad, row(WS_A, { requested_host: "ok.example.test" })]));
    expect(res.status).toBe(202);
    const sent = mockRpc.mock.calls[0][1].p_rows as { requested_host: string }[];
    expect(sent.map((r) => r.requested_host)).toEqual(["ok.example.test"]);
    expect((await json(res)).dropped_invalid).toBe(bad.length);
    expect(mockWarnDebounced.mock.calls.map((c) => c[3])).toContain("rows-invalid");
  });

  it("accepts the overflow row and bracketed IPv6 hosts", async () => {
    const res = await POST(
      req([row(WS_A, { requested_host: "(other)", decision: "denied" }), row(WS_A, { requested_host: "[2001:db8::1]:443" })]),
    );
    expect(res.status).toBe(202);
    expect((mockRpc.mock.calls[0][1].p_rows as unknown[]).length).toBe(2);
  });

  it("rejects more rows than the per-request cap", async () => {
    const rows = Array.from({ length: 501 }, (_, i) => row(WS_A, { requested_host: `h${i}.example.test` }));
    expect((await POST(req(rows))).status).toBe(400);
  });

  it("accepts an empty batch without calling the database", async () => {
    const res = await POST(req([]));
    expect(res.status).toBe(202);
    expect(mockRpc).not.toHaveBeenCalled();
  });
});

describe("bucket bounds", () => {
  it("drops a row older than 30 days or later than now + one bucket + skew, and counts it", async () => {
    const old = floor15(Date.now() - 31 * 86400_000);
    const future = floor15(Date.now() + 3 * 3600_000);
    const res = await POST(
      req([
        row(WS_A, { bucket_start: old, requested_host: "old.example.test" }),
        row(WS_A, { bucket_start: future, requested_host: "future.example.test" }),
        row(WS_A, { requested_host: "ok.example.test" }),
      ]),
    );
    expect(res.status).toBe(202);
    const sent = mockRpc.mock.calls[0][1].p_rows as { requested_host: string }[];
    expect(sent.map((r) => r.requested_host)).toEqual(["ok.example.test"]);
    expect((await json(res)).dropped_bounds).toBe(2);
    expect(mockWarnDebounced).toHaveBeenCalled();
  });

  it("accepts a buffered row two hours old after an app outage", async () => {
    const twoHours = floor15(Date.now() - 2 * 3600_000);
    const res = await POST(req([row(WS_A, { bucket_start: twoHours })]));
    expect(res.status).toBe(202);
    expect(mockRpc).toHaveBeenCalledTimes(1);
  });
});

describe("workspace resolution and the per-org flag", () => {
  it("skips a workspace the lookup does not return and counts it, without losing the rest", async () => {
    mockIn.mockResolvedValue({ data: [{ id: WS_A, organization_id: ORG_A }], error: null });
    const res = await POST(req([row(WS_A), row(WS_B, { requested_host: "b.example.test" })]));
    expect(res.status).toBe(202);
    const sent = mockRpc.mock.calls[0][1].p_rows as { workspace_id: string }[];
    expect(sent.map((r) => r.workspace_id)).toEqual([WS_A]);
    expect((await json(res)).skipped_unknown).toBe(1);
  });

  it("evaluates the flag per organisation and drops rows for orgs where it is off", async () => {
    mockGetRuntimeFlag.mockImplementation(async (_name: string, id: { orgId: string | null }) => id.orgId === ORG_A);
    const res = await POST(req([row(WS_A), row(WS_B, { requested_host: "b.example.test" })]));
    expect(res.status).toBe(202);
    const sent = mockRpc.mock.calls[0][1].p_rows as { workspace_id: string }[];
    expect(sent.map((r) => r.workspace_id)).toEqual([WS_A]);
    expect((await json(res)).skipped_flag_off).toBe(1);
    const call = mockGetRuntimeFlag.mock.calls.find((c) => c[1].orgId === ORG_A)!;
    expect(call[0]).toBe("egress-audit-collection");
    expect(call[1]).toMatchObject({ role: "prd", orgId: ORG_A, userId: null });
  });

  it("(org A off, org B on) writes only org B; (both on) writes both", async () => {
    mockGetRuntimeFlag.mockImplementation(async (_n: string, id: { orgId: string | null }) => id.orgId === ORG_B);
    await POST(req([row(WS_A), row(WS_B, { requested_host: "b.example.test" })]));
    expect((mockRpc.mock.calls[0][1].p_rows as { workspace_id: string }[]).map((r) => r.workspace_id)).toEqual([WS_B]);
    mockRpc.mockClear();
    mockGetRuntimeFlag.mockResolvedValue(true);
    await POST(req([row(WS_A), row(WS_B, { requested_host: "b.example.test" })]));
    expect(
      (mockRpc.mock.calls[0][1].p_rows as { workspace_id: string }[]).map((r) => r.workspace_id).sort(),
    ).toEqual([WS_A, WS_B]);
  });

  it("with the flag injected off for every org it answers 2xx and writes nothing", async () => {
    mockGetRuntimeFlag.mockResolvedValue(false);
    const res = await POST(req([row(WS_A), row(WS_B)]));
    expect(res.status).toBe(202);
    expect(mockRpc).not.toHaveBeenCalled();
    expect((await json(res)).skipped_flag_off).toBe(2);
  });

  it("a failing flag evaluation fails closed (drops, 2xx)", async () => {
    mockGetRuntimeFlag.mockRejectedValue(new Error("flagsmith down"));
    const res = await POST(req([row(WS_A)]));
    expect(res.status).toBe(202);
    expect(mockRpc).not.toHaveBeenCalled();
    const call = mockWarnDebounced.mock.calls.find((c) => c[3] === "flag-eval");
    expect(call).toBeTruthy();
    expect(call![1]).toMatchObject({ feature: "egress-audit-ingest", op: "flag-eval" });
  });

  it("looks workspaces up in chunks of at most 100 ids", async () => {
    const ids = Array.from({ length: 250 }, (_, i) => `${i.toString(16).padStart(8, "0")}-0000-4000-8000-000000000000`);
    mockIn.mockImplementation(async (_c: string, chunk: string[]) => ({
      data: chunk.map((id) => ({ id, organization_id: ORG_A })),
      error: null,
    }));
    await POST(req(ids.map((id) => row(id))));
    expect(mockIn.mock.calls.map((c) => (c[1] as string[]).length)).toEqual([100, 100, 50]);
  });

  it("a failing workspace lookup returns 5xx so Vector retries, and is mirrored without host or workspace values", async () => {
    mockIn.mockResolvedValue({ data: null, error: { message: "db down", code: "08006" } });
    const res = await POST(req([row(WS_A, { requested_host: "secret-host.example.test" })]));
    expect(res.status).toBeGreaterThanOrEqual(500);
    expect(mockReport).toHaveBeenCalled();
    const serialized = JSON.stringify(mockReport.mock.calls);
    expect(serialized).not.toContain("secret-host.example.test");
    expect(serialized).not.toContain(WS_A);
    expect(mockReport.mock.calls[0][1]).toMatchObject({ feature: "egress-audit-ingest", op: "workspace-lookup" });
  });
});

describe("database write", () => {
  it("sends rows to the RPC and reports its counts", async () => {
    mockRpc.mockResolvedValue({
      data: { accepted: 1, skipped_unknown: 0, skipped_toggle_off: 1, skipped_invalid: 0 },
      error: null,
    });
    const res = await POST(req([row(WS_A), row(WS_A, { requested_host: "c.example.test" })]));
    expect(res.status).toBe(202);
    expect(mockRpc.mock.calls[0][0]).toBe("ingest_egress_audit_rollup");
    const body = await json(res);
    expect(body.accepted).toBe(1);
    expect(body.skipped_toggle_off).toBe(1);
  });

  it("mirrors RPC-skipped rows as counts only", async () => {
    mockRpc.mockResolvedValue({
      data: { accepted: 0, skipped_unknown: 2, skipped_toggle_off: 0, skipped_invalid: 3 },
      error: null,
    });
    await POST(req([row(WS_A, { requested_host: "secret-host.example.test" })]));
    const call = mockWarnDebounced.mock.calls.find((c) => c[3] === "rows-skipped");
    expect(call).toBeTruthy();
    expect(call![1].extra).toEqual({ skipped_unknown: 2, skipped_invalid: 3 });
    expect(JSON.stringify(mockWarnDebounced.mock.calls)).not.toContain("secret-host.example.test");
  });

  it("an RPC error returns 5xx (retryable) and mirrors reason codes only", async () => {
    mockRpc.mockResolvedValue({ data: null, error: { message: "boom", code: "XX000" } });
    const res = await POST(req([row(WS_A, { requested_host: "secret-host.example.test" })]));
    expect(res.status).toBeGreaterThanOrEqual(500);
    expect(mockReport.mock.calls[0][1]).toMatchObject({ feature: "egress-audit-ingest", op: "rpc" });
    const serialized = JSON.stringify(mockReport.mock.calls);
    expect(serialized).not.toContain("secret-host.example.test");
    expect(serialized).not.toContain(WS_A);
  });

  it("debounces the reject mirror: one call key per reason, never per request", async () => {
    await POST(req([row(WS_A)], { auth: "Bearer wrong-1" }));
    await POST(req([row(WS_A)], { auth: "Bearer wrong-2" }));
    const keys = mockWarnDebounced.mock.calls.map((c) => `${c[2]}:${c[3]}`);
    expect(new Set(keys).size).toBe(1);
    const serialized = JSON.stringify(mockWarnDebounced.mock.calls);
    expect(serialized).not.toContain("wrong-1");
  });
});
