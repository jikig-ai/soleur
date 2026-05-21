import { describe, it, expect, vi, beforeEach } from "vitest";
import { createHmac } from "node:crypto";

// #4224 — periodic workspace reconciliation. Tests the `push` dispatch
// branch added to `app/api/webhooks/github/route.ts` AFTER founder lookup
// + workflow_run gate, BEFORE the HEADER_TO_ACTION_CLASS lookup. The
// branch dispatches `platform/workspace.reconcile.requested` to an Inngest
// function (see `server/inngest/functions/workspace-reconcile-on-push.ts`).

const {
  mockInsert,
  mockDeleteEq,
  mockUsersMaybeSingle,
  mockLogger,
  mockInngestSend,
  mockIsGranted,
  mockSentryCaptureMessage,
  mockSentryCaptureException,
} = vi.hoisted(() => ({
  mockInsert: vi.fn(),
  mockDeleteEq: vi.fn(),
  mockUsersMaybeSingle: vi.fn(),
  mockLogger: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
  mockInngestSend: vi.fn(),
  mockIsGranted: vi.fn(),
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
      if (table === "users") {
        return {
          select: () => ({
            eq: () => ({ maybeSingle: mockUsersMaybeSingle }),
          }),
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

vi.mock("@/server/scope-grants/is-granted", () => ({
  isGranted: mockIsGranted,
  isDenied: vi.fn(),
}));

vi.mock("@sentry/nextjs", () => ({
  captureMessage: mockSentryCaptureMessage,
  captureException: mockSentryCaptureException,
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
}));

import { POST } from "@/app/api/webhooks/github/route";

const SECRET = "test-webhook-secret-push";
const ZEROS = "0000000000000000000000000000000000000000";
const HEAD_SHA = "abc1234567890abcdef1234567890abcdef12345";
const BEFORE_SHA = "def4567890abcdef1234567890abcdef12345678";

function sign(body: string): string {
  return "sha256=" + createHmac("sha256", SECRET).update(body).digest("hex");
}

function makePushRequest(opts: {
  ref?: string;
  before?: string;
  after?: string;
  defaultBranch?: string | null;
  installationId?: number | null;
  deliveryId?: string;
  omitDefaultBranchField?: boolean;
}): Request {
  const body: Record<string, unknown> = {
    ref: opts.ref ?? "refs/heads/main",
    before: opts.before ?? BEFORE_SHA,
    after: opts.after ?? HEAD_SHA,
  };
  if (!opts.omitDefaultBranchField) {
    body.repository = { default_branch: opts.defaultBranch ?? "main" };
  }
  if (opts.installationId !== null) {
    body.installation = { id: opts.installationId ?? 42 };
  }
  const raw = JSON.stringify(body);
  const headers = new Headers();
  headers.set("x-hub-signature-256", sign(raw));
  headers.set("x-github-delivery", opts.deliveryId ?? "delivery-push-1");
  headers.set("x-github-event", "push");
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
  mockUsersMaybeSingle.mockResolvedValue({
    data: { id: "founder-push-1" },
    error: null,
  });
  mockIsGranted.mockResolvedValue({ tier: "draft_one_click" });
  mockInngestSend.mockResolvedValue(undefined);
});

describe("POST /api/webhooks/github — push dispatch (#4224)", () => {
  it("Case 1: default-branch push (ref matches default) dispatches reconcile event", async () => {
    const req = makePushRequest({});
    const res = await POST(req);
    expect(res.status).toBe(200);
    expect(mockInngestSend).toHaveBeenCalledTimes(1);
    expect(mockInngestSend).toHaveBeenCalledWith(
      expect.objectContaining({
        id: "github-delivery-push-1",
        name: "platform/workspace.reconcile.requested",
        data: expect.objectContaining({
          founderId: "founder-push-1",
          installationId: 42,
          deliveryId: "delivery-push-1",
          defaultBranch: "main",
          headSha: HEAD_SHA,
          beforeSha: BEFORE_SHA,
        }),
      }),
    );
    // Scope-grant check must NOT fire — GitHub App install IS the consent surface.
    expect(mockIsGranted).not.toHaveBeenCalled();
  });

  it("Case 2: tag push (refs/tags/v1) is dropped without dispatch", async () => {
    const req = makePushRequest({ ref: "refs/tags/v1" });
    const res = await POST(req);
    expect(res.status).toBe(200);
    expect(mockInngestSend).not.toHaveBeenCalled();
  });

  it("Case 3: branch deletion (after=zeros) is dropped without dispatch", async () => {
    const req = makePushRequest({ after: ZEROS });
    const res = await POST(req);
    expect(res.status).toBe(200);
    expect(mockInngestSend).not.toHaveBeenCalled();
  });

  it("Case 4: initial default-branch creation (before=zeros, after non-zero, ref=default) SHOULD dispatch", async () => {
    const req = makePushRequest({ before: ZEROS });
    const res = await POST(req);
    expect(res.status).toBe(200);
    expect(mockInngestSend).toHaveBeenCalledTimes(1);
    expect(mockInngestSend).toHaveBeenCalledWith(
      expect.objectContaining({
        name: "platform/workspace.reconcile.requested",
        data: expect.objectContaining({ beforeSha: ZEROS, headSha: HEAD_SHA }),
      }),
    );
  });

  it("Case 5: non-default branch push (feature branch) is dropped without dispatch", async () => {
    const req = makePushRequest({ ref: "refs/heads/feature-x" });
    const res = await POST(req);
    expect(res.status).toBe(200);
    expect(mockInngestSend).not.toHaveBeenCalled();
  });

  it("Case 6: ref=main but repository.default_branch=develop is dropped (operator's default is develop)", async () => {
    const req = makePushRequest({ ref: "refs/heads/main", defaultBranch: "develop" });
    const res = await POST(req);
    expect(res.status).toBe(200);
    expect(mockInngestSend).not.toHaveBeenCalled();
  });

  it("Case 7: malformed payload (missing repository.default_branch) drops with pino warn, no Sentry error", async () => {
    const req = makePushRequest({ omitDefaultBranchField: true });
    const res = await POST(req);
    expect(res.status).toBe(200);
    expect(mockInngestSend).not.toHaveBeenCalled();
    expect(mockLogger.warn).toHaveBeenCalled();
    expect(mockSentryCaptureException).not.toHaveBeenCalled();
  });

  it("Case 8: no installation.id — drop (existing behavior, no inngest)", async () => {
    const req = makePushRequest({ installationId: null });
    const res = await POST(req);
    expect(res.status).toBe(200);
    expect(mockInngestSend).not.toHaveBeenCalled();
  });

  it("Case 9: unmapped installation_id → 404; zero inngest.send; releaseDedupRow called", async () => {
    mockUsersMaybeSingle.mockResolvedValueOnce({ data: null, error: null });
    const req = makePushRequest({ installationId: 9999 });
    const res = await POST(req);
    expect(res.status).toBe(404);
    expect(mockInngestSend).not.toHaveBeenCalled();
    // 404 (4xx, GitHub won't retry) does NOT release the dedup row in the
    // existing route shape — verify the established invariant.
    // (Plan §Phase 1 Kieran #1 actually requires releaseDedupRow on 404 for push;
    // we assert that here.)
    expect(mockDeleteEq).toHaveBeenCalledWith("delivery_id", "delivery-push-1");
  });

  it("dispatches with releaseDedupRow on inngest.send failure (release-on-error invariant)", async () => {
    mockInngestSend.mockRejectedValueOnce(new Error("inngest unreachable"));
    const req = makePushRequest({});
    const res = await POST(req);
    expect(res.status).toBe(500);
    expect(mockDeleteEq).toHaveBeenCalledWith("delivery_id", "delivery-push-1");
  });
});
