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
  mockResolveFounder,
  mockLogger,
  mockInngestSend,
  mockIsGranted,
  mockSentryCaptureMessage,
  mockSentryCaptureException,
} = vi.hoisted(() => ({
  mockInsert: vi.fn(),
  mockDeleteEq: vi.fn(),
  // ADR-044 Amendment 2026-06-17b: PUSH must NOT call the founder resolver at
  // all (the reconcile fan-out re-derives workspaces). The resolver is mocked
  // only to assert it is never invoked on the push path (Test Scenario 5).
  mockResolveFounder: vi.fn(),
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
  fullName?: string | null;
  installationId?: number | null;
  deliveryId?: string;
  omitDefaultBranchField?: boolean;
  omitFullName?: boolean;
}): Request {
  const body: Record<string, unknown> = {
    ref: opts.ref ?? "refs/heads/main",
    before: opts.before ?? BEFORE_SHA,
    after: opts.after ?? HEAD_SHA,
  };
  if (!opts.omitDefaultBranchField) {
    const repository: Record<string, unknown> = {
      default_branch: opts.defaultBranch ?? "main",
    };
    // ADR-044: repository.full_name is required for the reconcile fan-out;
    // present by default, omittable to exercise the fail-closed path.
    if (!opts.omitFullName) {
      repository.full_name = opts.fullName ?? "jikig-ai/soleur";
    }
    body.repository = repository;
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
  mockResolveFounder.mockResolvedValue({ kind: "found", founderId: "founder-push-1" });
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
        v: "3",
        data: expect.objectContaining({
          installationId: 42,
          deliveryId: "delivery-push-1",
          defaultBranch: "main",
          headSha: HEAD_SHA,
          beforeSha: BEFORE_SHA,
          fullName: "jikig-ai/soleur",
        }),
      }),
    );
    // `founderId` is dropped from the v=3 payload (ADR-044 Amendment 2026-06-17b).
    expect(mockInngestSend.mock.calls[0][0].data.founderId).toBeUndefined();
    // PUSH must NOT resolve a founder (the reconcile re-derives workspaces).
    expect(mockResolveFounder).not.toHaveBeenCalled();
    // Scope-grant check must NOT fire — GitHub App install IS the consent surface.
    expect(mockIsGranted).not.toHaveBeenCalled();
  });

  it("Case 1b: reconcilable push missing repository.full_name fails closed (no dispatch, P0-2)", async () => {
    const req = makePushRequest({ omitFullName: true });
    const res = await POST(req);
    expect(res.status).toBe(200); // received, but not dispatched
    expect(mockInngestSend).not.toHaveBeenCalled();
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

  it("Case 9: unmapped installation_id on PUSH → dispatches (no founder gate); reconcile re-derives workspaces", async () => {
    // ADR-044 Amendment 2026-06-17b: push no longer 404s on an unmapped
    // installation. The founder reverse-lookup was removed from the push path;
    // the reconcile fan-out keys on (installation_id, repo_url) and benignly
    // finds zero workspaces for an uninstalled/unconnected install (the
    // "no-workspace-match" skip lives in the consumer, not the route). So the
    // route dispatches and 200s regardless of founder.
    const req = makePushRequest({ installationId: 9999 });
    const res = await POST(req);
    expect(res.status).toBe(200);
    expect(mockResolveFounder).not.toHaveBeenCalled();
    expect(mockInngestSend).toHaveBeenCalledTimes(1);
    expect(mockInngestSend.mock.calls[0][0].data.installationId).toBe(9999);
    expect(mockDeleteEq).not.toHaveBeenCalled();
  });

  it("dispatches with releaseDedupRow on inngest.send failure (release-on-error invariant)", async () => {
    mockInngestSend.mockRejectedValueOnce(new Error("inngest unreachable"));
    const req = makePushRequest({});
    const res = await POST(req);
    expect(res.status).toBe(500);
    expect(mockDeleteEq).toHaveBeenCalledWith("delivery_id", "delivery-push-1");
  });

  it("retries on transient fetch error and succeeds on push path", async () => {
    mockInngestSend
      .mockRejectedValueOnce(new TypeError("fetch failed"))
      .mockResolvedValueOnce(undefined);
    const req = makePushRequest({});
    const res = await POST(req);
    expect(res.status).toBe(200);
    expect(mockInngestSend).toHaveBeenCalledTimes(2);
    expect(mockDeleteEq).not.toHaveBeenCalled();
  });

  it("releases dedup row after all retries exhausted on push path", async () => {
    const fetchError = new TypeError("fetch failed");
    mockInngestSend
      .mockRejectedValueOnce(fetchError)
      .mockRejectedValueOnce(fetchError)
      .mockRejectedValueOnce(fetchError);
    const req = makePushRequest({});
    const res = await POST(req);
    expect(res.status).toBe(500);
    expect(mockInngestSend).toHaveBeenCalledTimes(3);
    expect(mockDeleteEq).toHaveBeenCalledWith("delivery_id", "delivery-push-1");
  });
});
