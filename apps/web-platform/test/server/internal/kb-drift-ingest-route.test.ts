import { describe, it, expect, vi, beforeEach } from "vitest";
import { createHmac } from "node:crypto";

const {
  mockInsertDraftCard,
  mockLogger,
  mockSentryCaptureMessage,
  mockSentryCaptureException,
} = vi.hoisted(() => ({
  mockInsertDraftCard: vi.fn(),
  mockLogger: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
  mockSentryCaptureMessage: vi.fn(),
  mockSentryCaptureException: vi.fn(),
}));

// #4579: the route now writes through the shared insertDraftCard helper
// (tenant-client, solo-pinned workspace_id) instead of createServiceClient.
vi.mock("@/server/messages/insert-draft-card", () => ({
  insertDraftCard: mockInsertDraftCard,
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

function makeRequest(
  body: object | string,
  opts: { signature?: string; omit?: boolean } = {},
): Request {
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
  mockInsertDraftCard.mockResolvedValue({ status: "inserted", id: "row-1" });
});

describe("POST /api/internal/kb-drift-ingest — HMAC", () => {
  it("returns 401 on bad signature", async () => {
    const res = await POST(makeRequest(validPayload, { signature: "sha256=deadbeef" }));
    expect(res.status).toBe(401);
    expect(mockInsertDraftCard).not.toHaveBeenCalled();
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

describe("POST /api/internal/kb-drift-ingest — digest + dedup", () => {
  it("inserts ONE digest card (not one per finding) with a content-hash source_ref and action_class", async () => {
    const res = await POST(makeRequest(validPayload));
    expect(res.status).toBe(200);
    expect(mockInsertDraftCard).toHaveBeenCalledTimes(1);
    const arg = mockInsertDraftCard.mock.calls[0][0];
    expect(arg).toMatchObject({
      founderId: "operator-founder-1",
      source: "kb-drift",
      owning_domain: "knowledge",
      tier: "external_low_stakes",
      urgency: "low",
      trust_tier: "internal_infra_auto",
      action_class: "knowledge.kb_drift",
    });
    expect(arg.source_ref).toMatch(/^digest-[0-9a-f]{64}$/); // full sha256, not truncated
    expect(arg.draft_preview).toContain("2 KB-drift findings — review");
    expect(arg.draft_preview).toContain("Broken link in knowledge-base/legal/foo.md");
    const body = (await res.json()) as { inserted: number; deduped: number; total: number };
    expect(body).toMatchObject({ inserted: 1, deduped: 0, total: 2 });
  });

  it("produces a STABLE source_ref for identical findings (idempotent dedup key)", async () => {
    await POST(makeRequest(validPayload));
    const ref1 = mockInsertDraftCard.mock.calls[0][0].source_ref;
    mockInsertDraftCard.mockClear();
    await POST(makeRequest(validPayload));
    const ref2 = mockInsertDraftCard.mock.calls[0][0].source_ref;
    expect(ref2).toBe(ref1);
  });

  it("maps helper dedup → deduped:1, inserted:0, and mirrors to Sentry", async () => {
    mockInsertDraftCard.mockResolvedValueOnce({ status: "deduped" });
    const res = await POST(makeRequest(validPayload));
    expect(res.status).toBe(200);
    const body = (await res.json()) as { inserted: number; deduped: number; total: number };
    expect(body).toMatchObject({ inserted: 0, deduped: 1, total: 2 });
    expect(mockSentryCaptureMessage).toHaveBeenCalledWith(
      "KB-drift digest deduped",
      expect.objectContaining({
        level: "info",
        tags: { feature: "kb-drift-ingest", op: "dedup-skip" },
      }),
    );
  });

  it("returns 500 (and does not crash) when the helper throws", async () => {
    mockInsertDraftCard.mockRejectedValueOnce(new Error("insertDraftCard failed (08006): conn lost"));
    const res = await POST(makeRequest(validPayload));
    expect(res.status).toBe(500);
  });

  it("empty findings → no insert, 200 with all-zero counts", async () => {
    const res = await POST(makeRequest({ findings: [], counts: { broken_link: 0, broken_anchor: 0 } }));
    expect(res.status).toBe(200);
    expect(mockInsertDraftCard).not.toHaveBeenCalled();
    const body = (await res.json()) as { inserted: number; deduped: number; total: number };
    expect(body).toMatchObject({ inserted: 0, deduped: 0, total: 0 });
  });

  it("strips the URL query string from a finding target before composing the preview", async () => {
    const payload = {
      findings: [
        {
          kind: "broken-link",
          source_path: "docs/x.md",
          target: "https://r2.example.com/asset.pdf?X-Amz-Signature=deadbeefcafef00ddeadbeefcafef00d&token=abc123",
          source_ref: "link-1111111111111111",
        },
      ],
      counts: { broken_link: 1, broken_anchor: 0 },
    };
    await POST(makeRequest(payload));
    const arg = mockInsertDraftCard.mock.calls[0][0];
    expect(arg.draft_preview).toContain("https://r2.example.com/asset.pdf");
    expect(arg.draft_preview).not.toContain("X-Amz-Signature");
    expect(arg.draft_preview).not.toContain("token=abc123");
  });
});
