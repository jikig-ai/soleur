import { describe, it, expect, vi, beforeEach } from "vitest";
import { Webhook } from "svix";

// Phase 3 (#5103) — Resend Inbound webhook route tests.
// Mirrors the vi.hoisted mock-bundle shape of test/server/webhooks/
// github-route.test.ts. Signatures are REAL svix signatures computed with
// the installed svix Webhook.sign (svix@1.92.2, webhook.d.ts:21) — the
// route's verify path is exercised for real, never mocked. No LLM, no
// network: the route is invoked directly via POST(request).
// All fixtures are synthesized (cq-test-fixtures-synthesized-only).

const {
  mockInsert,
  mockDeleteEq,
  mockLogger,
  mockInngestSend,
  mockSentryCaptureMessage,
  mockSentryCaptureException,
} = vi.hoisted(() => ({
  mockInsert: vi.fn(),
  mockDeleteEq: vi.fn(),
  mockLogger: { info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() },
  mockInngestSend: vi.fn(),
  mockSentryCaptureMessage: vi.fn(),
  mockSentryCaptureException: vi.fn(),
}));

vi.mock("@/lib/supabase/server", () => ({
  createServiceClient: () => ({
    from: (table: string) => {
      if (table === "processed_resend_events") {
        return {
          insert: mockInsert,
          delete: () => ({ eq: mockDeleteEq }),
        };
      }
      return {};
    },
  }),
}));

vi.mock("@/server/logger", () => ({
  default: mockLogger,
  createChildLogger: () => mockLogger,
}));

vi.mock("@/server/inngest/client", () => ({
  inngest: { send: mockInngestSend },
}));

vi.mock("@sentry/nextjs", () => ({
  captureMessage: mockSentryCaptureMessage,
  captureException: mockSentryCaptureException,
}));

// Avoid pulling realtime supabase deps in unrelated modules.
vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
}));

import { POST } from "@/app/api/webhooks/resend-inbound/route";
import { EMAIL_INBOUND_RECEIVED_EVENT } from "@/server/email-triage/events";

// svix accepts the whsec_-prefixed base64 secret format Resend issues.
const SECRET =
  "whsec_" + Buffer.from("resend-inbound-synthetic-secret!").toString("base64");
const SVIX_ID = "msg_synthetic_2abc123";

function receivedPayload(dataOverrides: Record<string, unknown> = {}): object {
  return {
    type: "email.received",
    created_at: "2026-06-11T08:00:00.000Z",
    data: {
      email_id: "ae2bd0b8-c10f-4885-9cdc-21cdf17616ae",
      created_at: "2026-06-11T07:59:58.123Z",
      from: "Synthetic Sender <synthetic-sender@example.com>",
      to: ["ops@soleur.ai"],
      cc: [],
      bcc: [],
      message_id: "<synthetic-msg-1@example.com>",
      subject: "Synthetic subject fixture",
      attachments: [{ filename: "doc.pdf", content_type: "application/pdf" }],
      ...dataOverrides,
    },
  };
}

type SvixHeader = "svix-id" | "svix-timestamp" | "svix-signature";

function makeRequest(
  opts: {
    body?: object | string;
    svixId?: string;
    timestamp?: Date;
    omitHeaders?: SvixHeader[];
    tamper?: boolean;
  } = {},
): Request {
  const raw =
    typeof opts.body === "string"
      ? opts.body
      : JSON.stringify(opts.body ?? receivedPayload());
  const svixId = opts.svixId ?? SVIX_ID;
  const ts = opts.timestamp ?? new Date();
  // svix signs over `${id}.${floor(ms/1000)}.${payload}` — the header must
  // carry the identical seconds value.
  const tsSeconds = String(Math.floor(ts.getTime() / 1000));
  let signature = new Webhook(SECRET).sign(svixId, ts, raw);
  if (opts.tamper) {
    const last = signature.slice(-1);
    signature = signature.slice(0, -1) + (last === "A" ? "B" : "A");
  }
  const headers = new Headers();
  const omit = opts.omitHeaders ?? [];
  if (!omit.includes("svix-id")) headers.set("svix-id", svixId);
  if (!omit.includes("svix-timestamp")) headers.set("svix-timestamp", tsSeconds);
  if (!omit.includes("svix-signature")) headers.set("svix-signature", signature);
  return new Request("https://app.soleur.ai/api/webhooks/resend-inbound", {
    method: "POST",
    headers,
    body: raw,
  });
}

beforeEach(() => {
  vi.clearAllMocks();
  process.env.RESEND_INBOUND_WEBHOOK_SECRET = SECRET;
  mockInsert.mockResolvedValue({ error: null });
  mockDeleteEq.mockResolvedValue({ error: null });
  mockInngestSend.mockResolvedValue(undefined);
});

describe("POST /api/webhooks/resend-inbound — secret + signature gates", () => {
  it("returns 500 + Sentry when RESEND_INBOUND_WEBHOOK_SECRET is unset — BEFORE verify", async () => {
    delete process.env.RESEND_INBOUND_WEBHOOK_SECRET;
    // Tampered signature: if verify ran first this would be a 401.
    const res = await POST(makeRequest({ tamper: true }));
    expect(res.status).toBe(500);
    expect(mockInsert).not.toHaveBeenCalled();
    expect(mockSentryCaptureMessage).toHaveBeenCalledWith(
      expect.any(String),
      expect.objectContaining({
        level: "error",
        tags: expect.objectContaining({ op: "secret" }),
      }),
    );
  });

  it("returns 401 when any svix-* header is missing", async () => {
    for (const header of [
      "svix-id",
      "svix-timestamp",
      "svix-signature",
    ] as SvixHeader[]) {
      const res = await POST(makeRequest({ omitHeaders: [header] }));
      expect(res.status).toBe(401);
    }
    expect(mockInsert).not.toHaveBeenCalled();
  });

  it("returns 401 on an invalid (tampered) signature", async () => {
    const res = await POST(makeRequest({ tamper: true }));
    expect(res.status).toBe(401);
    expect(mockInsert).not.toHaveBeenCalled();
    expect(mockInngestSend).not.toHaveBeenCalled();
  });

  it("returns 413 on an oversized body BEFORE verify", async () => {
    // > 256 KiB. Tampered signature: a 401 here would mean verify ran first.
    const huge = JSON.stringify({ pad: "x".repeat(262_144) });
    const res = await POST(makeRequest({ body: huge, tamper: true }));
    expect(res.status).toBe(413);
    expect(mockInsert).not.toHaveBeenCalled();
  });

  it("measures the cap in UTF-8 BYTES — multibyte payload near the boundary trips 413", async () => {
    // "é" is 1 UTF-16 code unit but 2 UTF-8 bytes: 140_000 of them inside
    // the JSON wrapper stay far under the cap in .length terms (~140k code
    // units) while exceeding 256 KiB on the wire. A .length-based check
    // would wrongly accept this body.
    const multibyte = JSON.stringify({ pad: "é".repeat(140_000) });
    expect(multibyte.length).toBeLessThan(262_144);
    expect(Buffer.byteLength(multibyte, "utf8")).toBeGreaterThan(262_144);
    const res = await POST(makeRequest({ body: multibyte, tamper: true }));
    expect(res.status).toBe(413);
    expect(mockInsert).not.toHaveBeenCalled();
  });

  it("rejects 413 from the Content-Length header alone, before reading the body", async () => {
    const req = makeRequest({ tamper: true });
    const headers = new Headers(req.headers);
    headers.set("content-length", String(262_145));
    // Body read would throw if attempted — proving the pre-read reject.
    const trapped = new Proxy(req, {
      get(target, prop, receiver) {
        if (prop === "text") {
          return () => {
            throw new Error("body must not be read on a declared-oversize request");
          };
        }
        if (prop === "headers") return headers;
        const value = Reflect.get(target, prop, receiver);
        return typeof value === "function" ? value.bind(target) : value;
      },
    });
    const res = await POST(trapped as Request);
    expect(res.status).toBe(413);
    expect(mockInsert).not.toHaveBeenCalled();
  });
});

describe("POST /api/webhooks/resend-inbound — pre-dedup classification", () => {
  it("returns 200 and inserts nothing for non-email.received event types", async () => {
    const res = await POST(
      makeRequest({
        body: { type: "email.delivered", data: { email_id: "x" } },
      }),
    );
    expect(res.status).toBe(200);
    expect(mockInsert).not.toHaveBeenCalled();
    expect(mockInngestSend).not.toHaveBeenCalled();
  });

  it("returns 400 on malformed JSON after verify — nothing claimed, nothing released", async () => {
    const res = await POST(makeRequest({ body: "{not-json" }));
    expect(res.status).toBe(400);
    expect(mockInsert).not.toHaveBeenCalled();
    expect(mockDeleteEq).not.toHaveBeenCalled();
  });
});

describe("POST /api/webhooks/resend-inbound — dedup (processed_resend_events)", () => {
  it("returns 500 on a non-23505 dedup insert failure", async () => {
    mockInsert.mockResolvedValueOnce({ error: { code: "08006", message: "conn lost" } });
    const res = await POST(makeRequest());
    expect(res.status).toBe(500);
    expect(mockInngestSend).not.toHaveBeenCalled();
    expect(mockSentryCaptureException).toHaveBeenCalled();
  });

  it("returns 200 without emitting on a duplicate svix_id (23505)", async () => {
    mockInsert.mockResolvedValueOnce({ error: { code: "23505" } });
    const res = await POST(makeRequest());
    expect(res.status).toBe(200);
    expect(mockInngestSend).not.toHaveBeenCalled();
    expect(mockDeleteEq).not.toHaveBeenCalled();
  });

  it("KEEPS the dedup row + 200 + Sentry warn when data.email_id is missing (deterministically unprocessable)", async () => {
    const res = await POST(
      makeRequest({ body: receivedPayload({ email_id: undefined }) }),
    );
    expect(res.status).toBe(200);
    expect(mockInsert).toHaveBeenCalledWith({ svix_id: SVIX_ID });
    // Row KEPT: a svix retry is byte-identical — release+500 would be a
    // 10-hour poison-retry storm.
    expect(mockDeleteEq).not.toHaveBeenCalled();
    expect(mockInngestSend).not.toHaveBeenCalled();
    expect(mockSentryCaptureMessage).toHaveBeenCalledWith(
      expect.any(String),
      expect.objectContaining({ level: "warning" }),
    );
  });

  it("releases the dedup row + 500 when inngest.send fails (transient — retry wanted)", async () => {
    mockInngestSend.mockRejectedValueOnce(new Error("inngest auth failed"));
    const res = await POST(makeRequest());
    expect(res.status).toBe(500);
    expect(mockDeleteEq).toHaveBeenCalledWith("svix_id", SVIX_ID);
  });
});

describe("POST /api/webhooks/resend-inbound — event emission", () => {
  it("happy path emits exactly one email/inbound.received event with v:1 and receivedAt passthrough", async () => {
    const res = await POST(makeRequest());
    expect(res.status).toBe(200);
    expect(mockInngestSend).toHaveBeenCalledTimes(1);
    expect(EMAIL_INBOUND_RECEIVED_EVENT).toBe("email/inbound.received");
    expect(mockInngestSend).toHaveBeenCalledWith(
      expect.objectContaining({
        id: `resend-${SVIX_ID}`,
        name: "email/inbound.received",
        v: "1",
        data: {
          v: "1",
          svixId: SVIX_ID,
          resendEmailId: "ae2bd0b8-c10f-4885-9cdc-21cdf17616ae",
          messageId: "<synthetic-msg-1@example.com>",
          sender: "Synthetic Sender <synthetic-sender@example.com>",
          subject: "Synthetic subject fixture",
          // RECEIVE timestamp passthrough from data.created_at — never
          // route-processing time.
          receivedAt: "2026-06-11T07:59:58.123Z",
          receivedAtSource: "payload",
          // Metadata ONLY — no content, no download URLs.
          attachments: [{ filename: "doc.pdf", contentType: "application/pdf" }],
        },
      }),
    );
    expect(mockDeleteEq).not.toHaveBeenCalled();
  });

  it("falls back to the svix-timestamp envelope when data.created_at is missing (+ Sentry warn)", async () => {
    // svix verify enforces a ±5-min replay tolerance against the wall
    // clock — the pinned timestamp must be "now", truncated to the seconds
    // the svix-timestamp header carries.
    const ts = new Date(Math.floor(Date.now() / 1000) * 1000);
    const res = await POST(
      makeRequest({
        body: receivedPayload({ created_at: undefined }),
        timestamp: ts,
      }),
    );
    expect(res.status).toBe(200);
    expect(mockInngestSend).toHaveBeenCalledTimes(1);
    const sent = mockInngestSend.mock.calls[0][0] as {
      data: { receivedAt: string; receivedAtSource: string };
    };
    expect(sent.data.receivedAtSource).toBe("envelope");
    expect(sent.data.receivedAt).toBe(ts.toISOString());
    expect(mockSentryCaptureMessage).toHaveBeenCalledWith(
      expect.any(String),
      expect.objectContaining({ level: "warning" }),
    );
  });

  it("empty / whitespace-only message_id → null (claim_key must not collapse on '')", async () => {
    for (const bad of ["", "   "]) {
      mockInngestSend.mockClear();
      const res = await POST(
        makeRequest({ body: receivedPayload({ message_id: bad }) }),
      );
      expect(res.status).toBe(200);
      const sent = mockInngestSend.mock.calls[0][0] as {
        data: { messageId: string | null };
      };
      expect(sent.data.messageId).toBeNull();
    }
  });

  it("missing or empty from → sender null, never '' (NULL-not-'' discipline)", async () => {
    for (const bad of [undefined, "", "   ", 42]) {
      mockInngestSend.mockClear();
      const res = await POST(
        makeRequest({ body: receivedPayload({ from: bad }) }),
      );
      expect(res.status).toBe(200);
      const sent = mockInngestSend.mock.calls[0][0] as {
        data: { sender: string | null };
      };
      expect(sent.data.sender).toBeNull();
      expect(sent.data.sender).not.toBe("");
    }
  });

  it("falls back to the envelope when data.created_at is unparseable", async () => {
    const ts = new Date(Math.floor(Date.now() / 1000) * 1000);
    const res = await POST(
      makeRequest({
        body: receivedPayload({ created_at: "not-a-timestamp" }),
        timestamp: ts,
      }),
    );
    expect(res.status).toBe(200);
    const sent = mockInngestSend.mock.calls[0][0] as {
      data: { receivedAt: string; receivedAtSource: string };
    };
    expect(sent.data.receivedAtSource).toBe("envelope");
    expect(sent.data.receivedAt).toBe(ts.toISOString());
  });
});
