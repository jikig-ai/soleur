import { describe, it, expect, vi, beforeEach } from "vitest";
import { createHmac } from "node:crypto";

const {
  mockInsert,
  mockLogger,
  mockSentryCaptureMessage,
  mockSentryCaptureException,
} = vi.hoisted(() => ({
  mockInsert: vi.fn(),
  mockLogger: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
  mockSentryCaptureMessage: vi.fn(),
  mockSentryCaptureException: vi.fn(),
}));

vi.mock("@/lib/supabase/server", () => ({
  createServiceClient: () => ({
    from: () => ({ insert: mockInsert }),
  }),
}));

vi.mock("@/server/logger", () => ({
  default: mockLogger,
  createChildLogger: () => mockLogger,
}));

vi.mock("@sentry/nextjs", () => ({
  captureMessage: mockSentryCaptureMessage,
  captureException: mockSentryCaptureException,
}));

import { POST } from "@/app/api/internal/kb-drift-ingest/route";

const SECRET = "kb-drift-test-key";

function makeRequest(body: object | string, opts: { signature?: string; omit?: boolean } = {}): Request {
  const raw = typeof body === "string" ? body : JSON.stringify(body);
  const headers = new Headers();
  if (!opts.omit) {
    const sig =
      opts.signature ?? "sha256=" + createHmac("sha256", SECRET).update(raw).digest("hex");
    headers.set("x-soleur-kb-drift-signature", sig);
  }
  return new Request("https://soleur.ai/api/internal/kb-drift-ingest", {
    method: "POST",
    headers,
    body: raw,
  });
}

const validPayload = {
  findings: [
    {
      kind: "broken-link",
      source_path: "knowledge-base/legal/foo.md",
      target: "missing.md",
      source_ref: "link-deadbeef00000000",
    },
    {
      kind: "broken-anchor",
      source_path: "AGENTS.core.md",
      target: "apps/web-platform/lib/gone.ts:42",
      source_ref: "anchor-cafef00d00000000",
    },
  ],
  counts: { broken_link: 1, broken_anchor: 1 },
};

beforeEach(() => {
  vi.clearAllMocks();
  process.env.KB_DRIFT_INGEST_SIGNING_KEY = SECRET;
  process.env.KB_DRIFT_OPERATOR_FOUNDER_ID = "operator-founder-1";
  mockInsert.mockResolvedValue({ error: null });
});

describe("POST /api/internal/kb-drift-ingest — HMAC", () => {
  it("returns 401 on bad signature", async () => {
    const res = await POST(makeRequest(validPayload, { signature: "sha256=deadbeef" }));
    expect(res.status).toBe(401);
    expect(mockInsert).not.toHaveBeenCalled();
  });

  it("returns 401 on missing signature", async () => {
    const res = await POST(makeRequest(validPayload, { omit: true }));
    expect(res.status).toBe(401);
  });

  it("returns 500 when signing key is unset", async () => {
    delete process.env.KB_DRIFT_INGEST_SIGNING_KEY;
    const res = await POST(makeRequest(validPayload));
    expect(res.status).toBe(500);
  });

  it("returns 500 when operator founder id is unset", async () => {
    delete process.env.KB_DRIFT_OPERATOR_FOUNDER_ID;
    const res = await POST(makeRequest(validPayload));
    expect(res.status).toBe(500);
  });
});

describe("POST /api/internal/kb-drift-ingest — payload shape", () => {
  it("returns 400 on malformed JSON", async () => {
    const res = await POST(makeRequest("<<not json>>"));
    expect(res.status).toBe(400);
  });

  it("returns 400 when findings array is missing", async () => {
    const res = await POST(makeRequest({ counts: { broken_link: 0, broken_anchor: 0 } }));
    expect(res.status).toBe(400);
  });

  it("returns 400 when a finding lacks required fields", async () => {
    const bad = {
      findings: [{ kind: "broken-link" }],
      counts: { broken_link: 0, broken_anchor: 0 },
    };
    const res = await POST(makeRequest(bad));
    expect(res.status).toBe(400);
  });
});

describe("POST /api/internal/kb-drift-ingest — dedup + insert", () => {
  it("inserts each finding with the right shape", async () => {
    const res = await POST(makeRequest(validPayload));
    expect(res.status).toBe(200);
    expect(mockInsert).toHaveBeenCalledTimes(2);
    expect(mockInsert).toHaveBeenCalledWith(
      expect.objectContaining({
        user_id: "operator-founder-1",
        source: "kb-drift",
        source_ref: "link-deadbeef00000000",
        owning_domain: "knowledge",
        status: "draft",
        urgency: "low",
        trust_tier: "internal_infra_auto",
      }),
    );
  });

  it("silently skips PG_UNIQUE_VIOLATION (idempotent re-runs)", async () => {
    mockInsert
      .mockResolvedValueOnce({ error: { code: "23505" } })
      .mockResolvedValueOnce({ error: null });
    const res = await POST(makeRequest(validPayload));
    expect(res.status).toBe(200);
    const body = (await res.json()) as { inserted: number; deduped: number; total: number };
    expect(body.inserted).toBe(1);
    expect(body.deduped).toBe(1);
    expect(body.total).toBe(2);
  });

  it("returns 500 on non-conflict DB error", async () => {
    mockInsert.mockResolvedValueOnce({ error: { code: "08006", message: "conn lost" } });
    const res = await POST(makeRequest(validPayload));
    expect(res.status).toBe(500);
  });
});
