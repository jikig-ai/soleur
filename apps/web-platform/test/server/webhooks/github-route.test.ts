import { describe, it, expect, vi, beforeEach } from "vitest";
import { createHmac } from "node:crypto";

// PR-H (#3244) Phase 3 — webhook route tests.
// Mirrors the mocking shape of stripe-payment-failed-inngest.test.ts.

const {
  mockInsert,
  mockDeleteEq,
  mockResolveFounder,
  mockLogger,
  mockInngestSend,
  mockIsGranted,
  mockIsDenied,
  mockSentryCaptureMessage,
  mockSentryCaptureException,
} = vi.hoisted(() => ({
  mockInsert: vi.fn(),
  mockDeleteEq: vi.fn(),
  // ADR-044 Amendment 2026-06-17b: the route no longer reads `users` for the
  // founder; it calls resolveSoloFounderForInstallation (discriminated union).
  mockResolveFounder: vi.fn(),
  mockLogger: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
  mockInngestSend: vi.fn(),
  mockIsGranted: vi.fn(),
  mockIsDenied: vi.fn(),
  mockSentryCaptureMessage: vi.fn(),
  mockSentryCaptureException: vi.fn(),
}));

vi.mock("@/lib/supabase/server", () => ({
  createServiceClient: () => ({
    from: (table: string) => {
      if (table === "processed_github_events") {
        return {
          insert: mockInsert,
          delete: () => ({ eq: mockDeleteEq }),
        };
      }
      // The route must NOT touch `users` after the cutover.
      throw new Error(`Unexpected table access in webhook route: ${table}`);
    },
  }),
}));

vi.mock("@/server/resolve-founder-for-installation", () => ({
  resolveSoloFounderForInstallation: mockResolveFounder,
}));

vi.mock("@/server/logger", () => ({
  default: mockLogger,
  createChildLogger: () => mockLogger,
}));

vi.mock("@/server/inngest/client", () => ({
  inngest: { send: mockInngestSend },
}));

vi.mock("@/server/scope-grants/is-granted", () => ({
  isGranted: mockIsGranted,
  isDenied: mockIsDenied,
}));

vi.mock("@sentry/nextjs", () => ({
  captureMessage: mockSentryCaptureMessage,
  captureException: mockSentryCaptureException,
}));

// Avoid bun pulling realtime supabase deps in unrelated modules.
vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
}));

import { POST } from "@/app/api/webhooks/github/route";

const SECRET = "test-webhook-secret-123";

function sign(body: string): string {
  return "sha256=" + createHmac("sha256", SECRET).update(body).digest("hex");
}

function makeRequest(opts: {
  body: object | string;
  signature?: string;
  deliveryId?: string;
  event?: string;
  omitSignature?: boolean;
  omitDelivery?: boolean;
  omitEvent?: boolean;
}): Request {
  const raw = typeof opts.body === "string" ? opts.body : JSON.stringify(opts.body);
  const headers = new Headers();
  if (!opts.omitSignature) headers.set("x-hub-signature-256", opts.signature ?? sign(raw));
  if (!opts.omitDelivery) headers.set("x-github-delivery", opts.deliveryId ?? "delivery-abc-123");
  if (!opts.omitEvent) headers.set("x-github-event", opts.event ?? "pull_request");
  return new Request("https://soleur.ai/api/webhooks/github", {
    method: "POST",
    headers,
    body: raw,
  });
}

beforeEach(() => {
  vi.clearAllMocks();
  process.env.GITHUB_APP_WEBHOOK_SECRET = SECRET;
  mockInsert.mockResolvedValue({ error: null });
  mockDeleteEq.mockResolvedValue({ error: null });
  mockResolveFounder.mockResolvedValue({ kind: "found", founderId: "founder-1" });
  mockIsGranted.mockResolvedValue({ tier: "draft_one_click" });
  mockIsDenied.mockReturnValue(false);
  mockInngestSend.mockResolvedValue(undefined);
});

describe("POST /api/webhooks/github — signature verification", () => {
  it("returns 401 on bad signature", async () => {
    const req = makeRequest({
      body: { installation: { id: 42 } },
      signature: "sha256=deadbeef",
    });
    const res = await POST(req);
    expect(res.status).toBe(401);
    expect(mockInsert).not.toHaveBeenCalled();
    expect(mockSentryCaptureMessage).toHaveBeenCalledWith(
      expect.stringContaining("signature verification failed"),
      expect.objectContaining({ level: "error" }),
    );
  });

  it("returns 401 on missing signature header", async () => {
    const req = makeRequest({ body: { installation: { id: 42 } }, omitSignature: true });
    const res = await POST(req);
    expect(res.status).toBe(401);
  });

  it("returns 500 when GITHUB_APP_WEBHOOK_SECRET is unset (fail-closed)", async () => {
    delete process.env.GITHUB_APP_WEBHOOK_SECRET;
    const req = makeRequest({ body: { installation: { id: 42 } } });
    const res = await POST(req);
    expect(res.status).toBe(500);
  });

  it("passes signature verification on good HMAC", async () => {
    const req = makeRequest({ body: { installation: { id: 42 }, action: "opened" } });
    const res = await POST(req);
    expect(res.status).toBe(200);
    expect(mockInsert).toHaveBeenCalledWith({ delivery_id: "delivery-abc-123" });
  });
});

describe("POST /api/webhooks/github — dedup (AC1)", () => {
  it("returns 200 without inngest.send on duplicate delivery_id (PG_UNIQUE_VIOLATION)", async () => {
    mockInsert.mockResolvedValueOnce({ error: { code: "23505" } });
    const req = makeRequest({ body: { installation: { id: 42 } } });
    const res = await POST(req);
    expect(res.status).toBe(200);
    expect(mockInngestSend).not.toHaveBeenCalled();
  });

  it("returns 500 on non-conflict DB error during dedup insert", async () => {
    mockInsert.mockResolvedValueOnce({ error: { code: "08006", message: "conn lost" } });
    const req = makeRequest({ body: { installation: { id: 42 } } });
    const res = await POST(req);
    expect(res.status).toBe(500);
  });
});

describe("POST /api/webhooks/github — scope-grant gate (AC2)", () => {
  it("returns 200 WITHOUT inngest.send when no active grant; logs at info level; no Sentry emission", async () => {
    mockIsGranted.mockResolvedValueOnce(null);
    const req = makeRequest({ body: { installation: { id: 42 } } });
    const res = await POST(req);
    expect(res.status).toBe(200);
    expect(mockInngestSend).not.toHaveBeenCalled();
    expect(mockLogger.info).toHaveBeenCalled();
    expect(mockSentryCaptureMessage).not.toHaveBeenCalled();
  });

  it("returns 404 when no founder owns the installation", async () => {
    mockResolveFounder.mockResolvedValueOnce({ kind: "none" });
    const req = makeRequest({ body: { installation: { id: 999 } } });
    const res = await POST(req);
    expect(res.status).toBe(404);
    expect(mockInngestSend).not.toHaveBeenCalled();
  });
});

describe("POST /api/webhooks/github — release-on-error (AC13)", () => {
  it("DELETEs processed_github_events row when inngest.send fails", async () => {
    mockInngestSend.mockRejectedValueOnce(new Error("inngest down"));
    const req = makeRequest({ body: { installation: { id: 42 } } });
    const res = await POST(req);
    expect(res.status).toBe(500);
    expect(mockDeleteEq).toHaveBeenCalledWith("delivery_id", "delivery-abc-123");
  });

  it("subsequent redelivery (same delivery_id) is processed after release", async () => {
    // First call: inngest fails -> release fires.
    mockInngestSend.mockRejectedValueOnce(new Error("transient"));
    const first = await POST(makeRequest({ body: { installation: { id: 42 } } }));
    expect(first.status).toBe(500);
    expect(mockDeleteEq).toHaveBeenCalled();

    // Second call (same delivery_id): mock resets dedup to clean state
    // because the test's mockInsert isn't a real DB. Verify the call
    // path still runs through inngest.send (does NOT 200-short-circuit).
    mockInsert.mockResolvedValueOnce({ error: null });
    mockInngestSend.mockResolvedValueOnce(undefined);
    const second = await POST(makeRequest({ body: { installation: { id: 42 } } }));
    expect(second.status).toBe(200);
    expect(mockInngestSend).toHaveBeenCalledTimes(2);
  });
});

describe("POST /api/webhooks/github — inngest.send retry on transient fetch failure", () => {
  it("retries on TypeError: fetch failed and succeeds on second attempt", async () => {
    mockInngestSend
      .mockRejectedValueOnce(new TypeError("fetch failed"))
      .mockResolvedValueOnce(undefined);
    const req = makeRequest({ body: { installation: { id: 42 } } });
    const res = await POST(req);
    expect(res.status).toBe(200);
    expect(mockInngestSend).toHaveBeenCalledTimes(2);
    expect(mockDeleteEq).not.toHaveBeenCalled();
  });

  it("releases dedup row after all retries exhausted", async () => {
    const fetchError = new TypeError("fetch failed");
    mockInngestSend
      .mockRejectedValueOnce(fetchError)
      .mockRejectedValueOnce(fetchError)
      .mockRejectedValueOnce(fetchError);
    const req = makeRequest({ body: { installation: { id: 42 } } });
    const res = await POST(req);
    expect(res.status).toBe(500);
    expect(mockInngestSend).toHaveBeenCalledTimes(3);
    expect(mockDeleteEq).toHaveBeenCalledWith("delivery_id", "delivery-abc-123");
  });

  it("does not retry on non-transient errors", async () => {
    mockInngestSend.mockRejectedValueOnce(new Error("inngest auth failed"));
    const req = makeRequest({ body: { installation: { id: 42 } } });
    const res = await POST(req);
    expect(res.status).toBe(500);
    expect(mockInngestSend).toHaveBeenCalledTimes(1);
  });
});

describe("POST /api/webhooks/github — payload & routing", () => {
  it("forwards rawBody + founderId + tier in inngest.send envelope", async () => {
    const payload = { installation: { id: 42 }, action: "opened", pull_request: { number: 7 } };
    const req = makeRequest({ body: payload, event: "pull_request" });
    await POST(req);
    expect(mockInngestSend).toHaveBeenCalledWith(
      expect.objectContaining({
        id: "github-delivery-abc-123",
        name: "engineering.pr_review_pending",
        data: expect.objectContaining({
          founderId: "founder-1",
          installationId: 42,
          deliveryId: "delivery-abc-123",
          githubEvent: "pull_request",
          tier: "draft_one_click",
          rawBody: JSON.stringify(payload),
        }),
      }),
    );
  });

  it("ignores workflow_run with non-failure conclusion (200, no inngest)", async () => {
    const req = makeRequest({
      body: { installation: { id: 42 }, workflow_run: { conclusion: "success" } },
      event: "workflow_run",
    });
    const res = await POST(req);
    expect(res.status).toBe(200);
    expect(mockInngestSend).not.toHaveBeenCalled();
  });

  it("fires inngest for workflow_run with failure conclusion", async () => {
    const req = makeRequest({
      body: { installation: { id: 42 }, workflow_run: { conclusion: "failure" } },
      event: "workflow_run",
    });
    const res = await POST(req);
    expect(res.status).toBe(200);
    expect(mockInngestSend).toHaveBeenCalledWith(
      expect.objectContaining({ name: "engineering.ci_failed" }),
    );
  });

  it("ignores unsupported x-github-event headers with 200", async () => {
    const req = makeRequest({ body: { installation: { id: 42 } }, event: "ping" });
    const res = await POST(req);
    expect(res.status).toBe(200);
    expect(mockInngestSend).not.toHaveBeenCalled();
  });
});
