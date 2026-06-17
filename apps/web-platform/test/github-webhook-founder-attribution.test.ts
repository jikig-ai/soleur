import { describe, test, expect, vi, beforeEach } from "vitest";
import { createHmac } from "node:crypto";

// ---------------------------------------------------------------------------
// ADR-044 Amendment 2026-06-17b — webhook founder attribution matrix.
//
// Mirrors the mock shape of test/webhook-subscription.test.ts: hoisted mocks,
// `vi.mock` of the route's dependencies, route imported AFTER the mocks.
//
// The route resolves non-push founders via `resolveSoloFounderForInstallation`
// (server/resolve-founder-for-installation.ts). The load-bearing scenario is
// the `>1` (ambiguous) fail-closed drop: NO founder selected, Sentry
// `op:founder-ambiguous`, dedup released, 404, ZERO inngest.send, ZERO
// isGranted. Cross-tenant misattribution is the brand-survival hazard.
// ---------------------------------------------------------------------------

const WEBHOOK_SECRET = "test-webhook-secret";

const {
  mockInsert,
  mockDeleteEq,
  mockLogger,
  mockCaptureException,
  mockCaptureMessage,
  mockIsGranted,
  mockInngestSend,
  mockSendWithRetry,
  mockResolveFounder,
} = vi.hoisted(() => ({
  mockInsert: vi.fn(),
  mockDeleteEq: vi.fn(),
  mockLogger: { info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() },
  mockCaptureException: vi.fn(),
  mockCaptureMessage: vi.fn(),
  mockIsGranted: vi.fn(),
  mockInngestSend: vi.fn(),
  mockSendWithRetry: vi.fn(),
  mockResolveFounder: vi.fn(),
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
      // No `users` table access should ever occur in this route after the
      // cutover; return a throwing chain so any stray `users` read fails loud.
      throw new Error(`Unexpected table access in webhook route: ${table}`);
    },
  }),
}));

vi.mock("@/server/logger", () => ({
  default: mockLogger,
  createChildLogger: () => mockLogger,
}));

vi.mock("@sentry/nextjs", () => ({
  captureException: mockCaptureException,
  captureMessage: mockCaptureMessage,
}));

vi.mock("@/server/scope-grants/is-granted", () => ({
  isGranted: mockIsGranted,
}));

vi.mock("@/server/resolve-founder-for-installation", () => ({
  resolveSoloFounderForInstallation: mockResolveFounder,
}));

vi.mock("@/server/inngest/client", () => ({
  inngest: { send: mockInngestSend },
}));

vi.mock("@/server/inngest/send-with-retry", () => ({
  sendInngestWithRetry: mockSendWithRetry,
}));

vi.mock("@/lib/safety/redaction-allowlist", () => ({
  redactGithubSourcedText: (s: string) => s,
}));

// ---------------------------------------------------------------------------
// Import route handler AFTER mocks
// ---------------------------------------------------------------------------

import { POST } from "@/app/api/webhooks/github/route";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const INSTALLATION_ID = 424242;
const FOUNDER_ID = "11111111-1111-1111-1111-111111111111";
const DELIVERY_ID = "delivery-abc";

function sign(body: string): string {
  const hex = createHmac("sha256", WEBHOOK_SECRET).update(body).digest("hex");
  return `sha256=${hex}`;
}

function makeRequest(
  event: string,
  payload: Record<string, unknown>,
  deliveryId = DELIVERY_ID,
): Request {
  const body = JSON.stringify(payload);
  return new Request("https://app.soleur.ai/api/webhooks/github", {
    method: "POST",
    headers: {
      "x-github-event": event,
      "x-github-delivery": deliveryId,
      "x-hub-signature-256": sign(body),
    },
    body,
  });
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("GitHub webhook — founder attribution (ADR-044 amendment)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    process.env.GITHUB_APP_WEBHOOK_SECRET = WEBHOOK_SECRET;
    // Dedup insert succeeds; release delete succeeds.
    mockInsert.mockResolvedValue({ error: null });
    mockDeleteEq.mockResolvedValue({ error: null });
    // sendInngestWithRetry invokes its first-arg sender by default.
    mockSendWithRetry.mockImplementation(async (sender: () => Promise<unknown>) => {
      await sender();
    });
    mockInngestSend.mockResolvedValue(undefined);
    mockIsGranted.mockResolvedValue({ tier: "startup" });
  });

  // Scenario 1 — single solo match → correct founder.
  test("single solo match → correct founder, isGranted with that id, dispatch", async () => {
    mockResolveFounder.mockResolvedValue({ kind: "found", founderId: FOUNDER_ID });
    const res = await POST(
      makeRequest("pull_request", {
        installation: { id: INSTALLATION_ID },
        action: "opened",
      }),
    );
    expect(res.status).toBe(200);
    expect(mockResolveFounder).toHaveBeenCalledWith(
      INSTALLATION_ID,
      expect.anything(),
    );
    expect(mockIsGranted).toHaveBeenCalledWith(
      expect.anything(),
      FOUNDER_ID,
      "engineering.pr_review_pending",
    );
    expect(mockSendWithRetry).toHaveBeenCalledTimes(1);
    // founderId dispatched is byte-equal to the resolver's returned id (P0-1).
    const sentPayload = mockInngestSend.mock.calls[0][0];
    expect(sentPayload.data.founderId).toBe(FOUNDER_ID);
    expect(sentPayload.data.installationId).toBe(INSTALLATION_ID);
  });

  // Scenario 2 — zero match → 404 + dedup released, no dispatch.
  test("zero match → 404, releaseDedupRow, zero inngest.send", async () => {
    mockResolveFounder.mockResolvedValue({ kind: "none" });
    const res = await POST(
      makeRequest("pull_request", { installation: { id: INSTALLATION_ID } }),
    );
    expect(res.status).toBe(404);
    expect(mockDeleteEq).toHaveBeenCalledTimes(1);
    expect(mockSendWithRetry).not.toHaveBeenCalled();
    expect(mockIsGranted).not.toHaveBeenCalled();
    expect(mockLogger.warn).toHaveBeenCalled();
  });

  // Scenario 3 — >1 solo match → fail-closed drop (LOAD-BEARING).
  test(">1 ambiguous → Sentry founder-ambiguous, 404, dedup released, ZERO dispatch & ZERO isGranted", async () => {
    mockResolveFounder.mockResolvedValue({ kind: "ambiguous", count: 2 });
    const res = await POST(
      makeRequest("pull_request", { installation: { id: INSTALLATION_ID } }),
    );
    expect(res.status).toBe(404);
    expect(mockCaptureException).toHaveBeenCalledTimes(1);
    const sentryOpts = mockCaptureException.mock.calls[0][1];
    expect(sentryOpts.tags.op).toBe("founder-ambiguous");
    expect(sentryOpts.tags.feature).toBe("github-webhook");
    expect(sentryOpts.level).toBe("error");
    expect(mockDeleteEq).toHaveBeenCalledTimes(1);
    expect(mockSendWithRetry).not.toHaveBeenCalled();
    expect(mockInngestSend).not.toHaveBeenCalled();
    expect(mockIsGranted).not.toHaveBeenCalled();
  });

  // Scenario 4 — team workspace sharing install is NOT a founder.
  // (Resolver excludes the team row → returns the single solo founder.)
  test("team sharing install excluded → resolver returns single solo founder, dispatch", async () => {
    mockResolveFounder.mockResolvedValue({ kind: "found", founderId: FOUNDER_ID });
    const res = await POST(
      makeRequest("issues", { installation: { id: INSTALLATION_ID }, action: "opened" }),
    );
    expect(res.status).toBe(200);
    expect(mockIsGranted).toHaveBeenCalledWith(
      expect.anything(),
      FOUNDER_ID,
      "triage.p0p1_issue",
    );
    expect(mockSendWithRetry).toHaveBeenCalledTimes(1);
  });

  // Scenario 5 — push dispatches reconcile without a users read, no founderId in payload.
  test("push → reconcile dispatch, no users read, no founderId in payload", async () => {
    const res = await POST(
      makeRequest("push", {
        installation: { id: INSTALLATION_ID },
        ref: "refs/heads/main",
        before: "a".repeat(40),
        after: "b".repeat(40),
        repository: { default_branch: "main", full_name: "octo/repo" },
      }),
    );
    expect(res.status).toBe(200);
    // Push must NOT call the founder resolver at all.
    expect(mockResolveFounder).not.toHaveBeenCalled();
    expect(mockSendWithRetry).toHaveBeenCalledTimes(1);
    const sentPayload = mockInngestSend.mock.calls[0][0];
    expect(sentPayload.data.founderId).toBeUndefined();
    expect(sentPayload.data.installationId).toBe(INSTALLATION_ID);
    expect(sentPayload.v).toBe("3");
  });

  // Scenario 6 — DB error on resolver → 500 + dedup released.
  test("resolver db-error → 500, Sentry, dedup released", async () => {
    mockResolveFounder.mockResolvedValue({ kind: "db-error" });
    const res = await POST(
      makeRequest("pull_request", { installation: { id: INSTALLATION_ID } }),
    );
    expect(res.status).toBe(500);
    expect(mockCaptureException).toHaveBeenCalledTimes(1);
    expect(mockDeleteEq).toHaveBeenCalledTimes(1);
    expect(mockSendWithRetry).not.toHaveBeenCalled();
    expect(mockIsGranted).not.toHaveBeenCalled();
  });

  // Scenario 11 — same-user double-solo-row drift trips ambiguous (P0-2 / R7).
  test("same-user double-solo-row drift → ambiguous fail-closed (P0-2)", async () => {
    // The resolver collapses to ambiguous; from the route's view this is the
    // same fail-closed branch as scenario 3 — the drift the dropped mig-052
    // UNIQUE used to make impossible.
    mockResolveFounder.mockResolvedValue({ kind: "ambiguous", count: 2 });
    const res = await POST(
      makeRequest("pull_request", { installation: { id: INSTALLATION_ID } }),
    );
    expect(res.status).toBe(404);
    expect(mockCaptureException.mock.calls[0][1].tags.op).toBe(
      "founder-ambiguous",
    );
    expect(mockSendWithRetry).not.toHaveBeenCalled();
  });

  // Scenario 12 — resolver reached for a non-PR action class (security.cve_alert).
  test("repository_advisory → resolver fires, dispatch proceeds (all action classes)", async () => {
    mockResolveFounder.mockResolvedValue({ kind: "found", founderId: FOUNDER_ID });
    const res = await POST(
      makeRequest("repository_advisory", {
        installation: { id: INSTALLATION_ID },
        action: "published",
      }),
    );
    expect(res.status).toBe(200);
    expect(mockResolveFounder).toHaveBeenCalledWith(
      INSTALLATION_ID,
      expect.anything(),
    );
    expect(mockIsGranted).toHaveBeenCalledWith(
      expect.anything(),
      FOUNDER_ID,
      "security.cve_alert",
    );
    expect(mockSendWithRetry).toHaveBeenCalledTimes(1);
  });
});
