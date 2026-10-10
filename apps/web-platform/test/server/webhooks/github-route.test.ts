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
  mockReportSilentFallback,
  mockGithubApiGet,
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
  mockReportSilentFallback: vi.fn(),
  mockGithubApiGet: vi.fn(),
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
  reportSilentFallback: mockReportSilentFallback,
}));

// ADR-276 S3 (#9728): the draft-PR CI-run filter resolves draftness with an
// installation-token head-SHA lookup. Mock the shared installation-token GET
// helper so no test mints a token or touches the network.
vi.mock("@/server/github-api", () => ({
  githubApiGet: mockGithubApiGet,
}));

import { POST } from "@/app/api/webhooks/github/route";

const SECRET = "test-webhook-secret-123";

function sign(body: string): string {
  return "sha256=" + createHmac("sha256", SECRET).update(body).digest("hex");
}

// ADR-044 Amendment 2026-06-18 (BUG 1): the non-push founder resolver is now
// repo-scoped. A non-push event with NO `repository.full_name` drops via the
// pre-compose none/404 guard WITHOUT issuing the resolver SELECT. So every
// non-push request that expects to REACH the resolver must carry a
// `repository.full_name`. We default it into object bodies that don't already
// set `repository`, so existing tests still exercise the resolver path.
const DEFAULT_FULL_NAME = "octo/repo";

function withDefaultRepo(body: object): object {
  if ("repository" in body) return body;
  return { ...body, repository: { full_name: DEFAULT_FULL_NAME } };
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
  const resolvedBody =
    typeof opts.body === "string" ? opts.body : withDefaultRepo(opts.body);
  const raw =
    typeof resolvedBody === "string" ? resolvedBody : JSON.stringify(resolvedBody);
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
  mockGithubApiGet.mockReset();
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
    // The dedup INSERT now happens post-isGranted, immediately before dispatch
    // (drop-before-dedup reorder) — the 23505 replay short-circuit is preserved.
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
    expect(mockInsert).not.toHaveBeenCalled();
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
    const payload = {
      installation: { id: 42 },
      action: "opened",
      pull_request: { number: 7 },
      // Repo-scoped resolver (ADR-044 Amendment 2026-06-18) requires full_name;
      // set it explicitly so the asserted rawBody matches the dispatched body.
      repository: { full_name: "octo/repo" },
    };
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

  it("ignores workflow_run with non-failure conclusion (200, no inngest, NO dedup row)", async () => {
    const req = makeRequest({
      body: { installation: { id: 42 }, workflow_run: { conclusion: "success" } },
      event: "workflow_run",
    });
    const res = await POST(req);
    expect(res.status).toBe(200);
    expect(mockInngestSend).not.toHaveBeenCalled();
    // Drop-before-dedup: the dominant no-op case writes NO processed_github_events row.
    expect(mockInsert).not.toHaveBeenCalled();
  });

  it("fires inngest for workflow_run with failure conclusion (and writes the dedup row)", async () => {
    const req = makeRequest({
      body: { installation: { id: 42 }, workflow_run: { conclusion: "failure" } },
      event: "workflow_run",
    });
    const res = await POST(req);
    expect(res.status).toBe(200);
    expect(mockInsert).toHaveBeenCalledWith({ delivery_id: "delivery-abc-123" });
    expect(mockInngestSend).toHaveBeenCalledWith(
      expect.objectContaining({ name: "engineering.ci_failed" }),
    );
    // INSERT-strictly-before-dispatch invariant (non-push): the dedup claim
    // must precede inngest.send. Fails loud if a future reorder moves it after.
    expect(mockInsert.mock.invocationCallOrder[0]).toBeLessThan(
      mockInngestSend.mock.invocationCallOrder[0],
    );
  });

  it("returns 200 with NO dedup row when payload has no installation.id (drop)", async () => {
    // Raw-string body bypasses withDefaultRepo; no installation → drop before dispatch.
    const raw = JSON.stringify({ action: "opened", repository: { full_name: "octo/repo" } });
    const req = makeRequest({ body: raw, event: "pull_request" });
    const res = await POST(req);
    expect(res.status).toBe(200);
    expect(mockInsert).not.toHaveBeenCalled();
    expect(mockInngestSend).not.toHaveBeenCalled();
  });

  it("ignores unsupported x-github-event headers with 200 (NO dedup row)", async () => {
    const req = makeRequest({ body: { installation: { id: 42 } }, event: "ping" });
    const res = await POST(req);
    expect(res.status).toBe(200);
    expect(mockInngestSend).not.toHaveBeenCalled();
    expect(mockInsert).not.toHaveBeenCalled();
  });
});

// ---------------------------------------------------------------------------
// ADR-044 Amendment 2026-06-18 (BUG 1) — repo-scoped non-push founder resolver.
// ---------------------------------------------------------------------------
describe("POST /api/webhooks/github — repo-scoped founder resolution (BUG 1)", () => {
  // AC1/AC2: a non-push event under a multi-repo org install resolves the
  // founder for the EVENT's repo and dispatches (no 404). The resolver is
  // mocked to return `found` for the matching repo; the route must compose the
  // repo_url from `repository.full_name` and pass it as the 2nd positional arg.
  it("passes the composed+normalized repo_url to the resolver and dispatches", async () => {
    const req = makeRequest({
      body: {
        installation: { id: 42 },
        action: "opened",
        repository: { full_name: "octo/Hello-World" },
      },
      event: "pull_request",
    });
    const res = await POST(req);
    expect(res.status).toBe(200);
    // 2nd positional arg is the normalized repo_url (NOT request-supplied raw).
    expect(mockResolveFounder).toHaveBeenCalledWith(
      42,
      "https://github.com/octo/Hello-World",
      expect.anything(),
    );
    expect(mockInngestSend).toHaveBeenCalledTimes(1);
  });

  // AC4: a non-push event with NO repository.full_name drops via the pre-compose
  // none/404 guard AND does NOT issue the resolver SELECT (resolver not called).
  // It must NOT be an ambiguous throw — it is a deterministic 404.
  it("non-push with no repository.full_name → 404 and does NOT call the resolver", async () => {
    // Bypass withDefaultRepo by passing a raw string body that omits repository.
    const raw = JSON.stringify({ installation: { id: 42 }, action: "opened" });
    const req = makeRequest({ body: raw, event: "pull_request" });
    const res = await POST(req);
    expect(res.status).toBe(404);
    expect(mockResolveFounder).not.toHaveBeenCalled();
    expect(mockInngestSend).not.toHaveBeenCalled();
    // Drop-before-dedup: no dedup row is written on the pre-dispatch 404 path,
    // so there is nothing to release.
    expect(mockInsert).not.toHaveBeenCalled();
    expect(mockDeleteEq).not.toHaveBeenCalled();
  });

  // AC4b: the ACTUAL prod signal (WEB-PLATFORM-3M) — an UNMAPPED event
  // (`check_suite`) reaches the resolver at route.ts:313 BEFORE the actionClass
  // guard. Under a multi-repo org install the repo-scoped resolver returns
  // `found` → the event falls through to the actionClass guard (no mapping) →
  // {received:true} 200 ignore, NOT a 404-storm.
  it("unmapped check_suite under multi-repo org install → resolver found → 200 ignore (NOT 404)", async () => {
    mockResolveFounder.mockResolvedValueOnce({ kind: "found", founderId: "f-cs" });
    const req = makeRequest({
      body: {
        installation: { id: 122213433 },
        action: "completed",
        repository: { full_name: "octo/some-repo" },
      },
      event: "check_suite",
    });
    const res = await POST(req);
    expect(res.status).toBe(200);
    // The resolver WAS reached (the bug: it used to return ambiguous → 404).
    expect(mockResolveFounder).toHaveBeenCalledWith(
      122213433,
      "https://github.com/octo/some-repo",
      expect.anything(),
    );
    // Unmapped event → no dispatch, no isGranted (falls through actionClass).
    expect(mockInngestSend).not.toHaveBeenCalled();
    expect(mockIsGranted).not.toHaveBeenCalled();
    // Drop-before-dedup: the unmapped-event 200-ignore is a NEW pre-dispatch
    // drop under this reorder (dedup-first code WOULD have inserted here) —
    // no processed_github_events row is written.
    expect(mockInsert).not.toHaveBeenCalled();
  });

  // AC4c: a db-error from the repo-scoped resolver returns 500 (re-drivable).
  // GitHub retries 5xx, not 4xx — this distinction from the 404 of none/ambiguous
  // is load-bearing for redelivery. Drop-before-dedup: this is a pre-dispatch
  // path, so NO dedup row is written (and none released).
  it("repo-scoped resolver db-error → 500, no dedup row written (re-drivable)", async () => {
    mockResolveFounder.mockResolvedValueOnce({ kind: "db-error" });
    const req = makeRequest({
      body: {
        installation: { id: 42 },
        action: "opened",
        repository: { full_name: "octo/repo" },
      },
      event: "pull_request",
    });
    const res = await POST(req);
    expect(res.status).toBe(500);
    // Drop-before-dedup: db-error is a pre-dispatch path — no row written, none released.
    expect(mockInsert).not.toHaveBeenCalled();
    expect(mockDeleteEq).not.toHaveBeenCalled();
    expect(mockInngestSend).not.toHaveBeenCalled();
  });
});

// ---------------------------------------------------------------------------
// ADR-276 S3 (#9728) — draft-PR CI-run filter. Under Option R every draft PR
// push's ci.yml `pull_request` run concludes `failure` BY DESIGN (the `test`
// aggregator exits 1: "draft: full battery owed at ready"). The Soleur App is
// subscribed to `workflow_run` on this repo, so without this filter each draft
// push raises an engineering.ci_failed ("Spawn fix agent") card.
// ---------------------------------------------------------------------------
describe("POST /api/webhooks/github — draft-PR CI-run filter (ADR-276 S3)", () => {
  const HEAD_SHA = "0123456789abcdef0123456789abcdef01234567";
  // The filter is scoped to the repository whose ci.yml carries the draft-light job.
  const SCOPED_REPO = "jikig-ai/soleur";
  const LOOKUP_PATH = `/repos/${SCOPED_REPO}/commits/${HEAD_SHA}/pulls?per_page=100`;

  function ciRunBody(run: Record<string, unknown> = {}): object {
    return {
      installation: { id: 42 },
      repository: { full_name: SCOPED_REPO },
      workflow_run: {
        name: "CI",
        path: ".github/workflows/ci.yml",
        event: "pull_request",
        conclusion: "failure",
        head_sha: HEAD_SHA,
        // The realistic case: GitHub leaves pull_requests[] empty for most
        // runs, so the filter must NOT depend on it.
        pull_requests: [],
        ...run,
      },
    };
  }

  function pr(over: Record<string, unknown> = {}): Record<string, unknown> {
    return { number: 7, state: "open", draft: true, head: { sha: HEAD_SHA }, ...over };
  }

  function post(body: object) {
    return POST(makeRequest({ body, event: "workflow_run" }));
  }

  function expectCardRaised() {
    expect(mockInsert).toHaveBeenCalledWith({ delivery_id: "delivery-abc-123" });
    expect(mockInngestSend).toHaveBeenCalledWith(
      expect.objectContaining({ name: "engineering.ci_failed" }),
    );
  }

  it("drops a CI pull_request failure whose head-SHA PR is a draft: 200, NO dedup row, NO inngest, NO Sentry", async () => {
    mockGithubApiGet.mockResolvedValueOnce([pr()]);
    const res = await post(ciRunBody());
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ received: true });
    expect(mockGithubApiGet).toHaveBeenCalledTimes(1);
    // The call carries the deadline signal: without it a hung lookup could outlive GitHub's 10 s delivery window.
    expect(mockGithubApiGet).toHaveBeenCalledWith(
      42,
      LOOKUP_PATH,
      expect.objectContaining({ signal: expect.any(AbortSignal) }),
    );
    expect(mockInsert).not.toHaveBeenCalled();
    expect(mockInngestSend).not.toHaveBeenCalled();
    expect(mockSentryCaptureException).not.toHaveBeenCalled();
    expect(mockSentryCaptureMessage).not.toHaveBeenCalled();
    expect(mockReportSilentFallback).not.toHaveBeenCalled();
    expect(mockLogger.info).toHaveBeenCalledWith(
      expect.objectContaining({ deliveryId: "delivery-abc-123", prNumber: 7, headSha: HEAD_SHA }),
      expect.stringContaining("draft PR CI run"),
    );
  });

  it("matches on head.sha among several PRs of the commit (an unrelated PR does not make it ambiguous)", async () => {
    mockGithubApiGet.mockResolvedValueOnce([
      pr({ number: 3, draft: false, head: { sha: "f".repeat(40) } }),
      pr({ number: 9 }),
    ]);
    const res = await post(ciRunBody());
    expect(res.status).toBe(200);
    expect(mockInngestSend).not.toHaveBeenCalled();
    expect(mockInsert).not.toHaveBeenCalled();
  });

  it("does not look up anything when there is no scope grant (lookup only runs where a card would be raised)", async () => {
    mockIsGranted.mockResolvedValueOnce(null);
    const res = await post(ciRunBody());
    expect(res.status).toBe(200);
    expect(mockGithubApiGet).not.toHaveBeenCalled();
    expect(mockInsert).not.toHaveBeenCalled();
  });

  it("non-draft PR: unchanged (card raised, dedup row claimed first)", async () => {
    mockGithubApiGet.mockResolvedValueOnce([pr({ draft: false })]);
    const res = await post(ciRunBody());
    expect(res.status).toBe(200);
    expectCardRaised();
    expect(mockInsert.mock.invocationCallOrder[0]).toBeLessThan(
      mockInngestSend.mock.invocationCallOrder[0],
    );
    expect(mockReportSilentFallback).not.toHaveBeenCalled();
  });

  it("a draft that is CLOSED or has a different head.sha is not a match: unchanged (card raised), no Sentry", async () => {
    mockGithubApiGet.mockResolvedValueOnce([
      pr({ number: 5, state: "closed" }),
      pr({ number: 6, head: { sha: "e".repeat(40) } }),
    ]);
    const res = await post(ciRunBody());
    expect(res.status).toBe(200);
    expectCardRaised();
    expect(mockReportSilentFallback).not.toHaveBeenCalled();
  });

  it("no PR found for the SHA (e.g. already merged or force-pushed away): unchanged (card raised)", async () => {
    mockGithubApiGet.mockResolvedValueOnce([]);
    const res = await post(ciRunBody());
    expect(res.status).toBe(200);
    expectCardRaised();
  });

  it("another workflow's failure is unchanged and triggers NO lookup", async () => {
    const res = await post(ciRunBody({ name: "Deploy", path: ".github/workflows/deploy.yml" }));
    expect(res.status).toBe(200);
    expect(mockGithubApiGet).not.toHaveBeenCalled();
    expectCardRaised();
  });

  it("a differently-named workflow with NO path in the payload is unchanged and triggers NO lookup", async () => {
    const res = await post(ciRunBody({ name: "Deploy", path: undefined }));
    expect(res.status).toBe(200);
    expect(mockGithubApiGet).not.toHaveBeenCalled();
    expectCardRaised();
  });

  it("a workflow merely NAMED CI but at another path is unchanged and triggers NO lookup", async () => {
    const res = await post(ciRunBody({ path: ".github/workflows/other.yml" }));
    expect(res.status).toBe(200);
    expect(mockGithubApiGet).not.toHaveBeenCalled();
    expectCardRaised();
  });

  it.each(["push", "merge_group", "workflow_dispatch", "schedule"])(
    "CI failure on a %s run is unchanged and triggers NO lookup",
    async (event) => {
      const res = await post(ciRunBody({ event }));
      expect(res.status).toBe(200);
      expect(mockGithubApiGet).not.toHaveBeenCalled();
      expectCardRaised();
    },
  );

  it("lookup error: fails OPEN (card raised) and mirrors the failure to Sentry via reportSilentFallback", async () => {
    const boom = new Error("GitHub API 502");
    mockGithubApiGet.mockRejectedValueOnce(boom);
    const res = await post(ciRunBody());
    expect(res.status).toBe(200);
    expectCardRaised();
    expect(mockReportSilentFallback).toHaveBeenCalledTimes(1);
    expect(mockReportSilentFallback).toHaveBeenCalledWith(
      boom,
      expect.objectContaining({ feature: "github-webhook", op: "draft-ci-lookup" }),
    );
  });

  it("lookup returning a non-array body: fails OPEN and mirrors to Sentry", async () => {
    mockGithubApiGet.mockResolvedValueOnce({ message: "weird" });
    const res = await post(ciRunBody());
    expect(res.status).toBe(200);
    expectCardRaised();
    expect(mockReportSilentFallback).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ feature: "github-webhook", op: "draft-ci-lookup" }),
    );
  });

  it("multiple matching open PRs for the head SHA: ambiguous, fails OPEN and mirrors to Sentry", async () => {
    mockGithubApiGet.mockResolvedValueOnce([pr({ number: 7 }), pr({ number: 8 })]);
    const res = await post(ciRunBody());
    expect(res.status).toBe(200);
    expectCardRaised();
    expect(mockReportSilentFallback).toHaveBeenCalledWith(
      null,
      expect.objectContaining({ feature: "github-webhook", op: "draft-ci-ambiguous" }),
    );
  });

  it("another repository's draft CI failure (a customer installation with its own `CI` workflow): unchanged, NO lookup, card raised", async () => {
    const res = await post({ ...ciRunBody(), repository: { full_name: "octo/repo" } });
    expect(res.status).toBe(200);
    expect(mockGithubApiGet).not.toHaveBeenCalled();
    expectCardRaised();
    expect(mockReportSilentFallback).not.toHaveBeenCalled();
  });

  it("a lookup that never answers is abandoned at 5 s: fails OPEN (card raised) and is mirrored as draft-ci-lookup", async () => {
    vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout"] });
    try {
      mockGithubApiGet.mockReturnValueOnce(new Promise(() => {}));
      let settled = false;
      const pending = post(ciRunBody()).then((r) => {
        settled = true;
        return r;
      });
      await vi.advanceTimersByTimeAsync(4_999);
      expect(settled).toBe(false);
      await vi.advanceTimersByTimeAsync(1);
      const res = await pending;
      expect(res.status).toBe(200);
      expectCardRaised();
      expect(mockReportSilentFallback).toHaveBeenCalledWith(
        expect.objectContaining({ message: expect.stringContaining("exceeded 5000 ms") }),
        expect.objectContaining({ feature: "github-webhook", op: "draft-ci-lookup" }),
      );
    } finally {
      vi.useRealTimers();
    }
  });

  it("an aborted fetch (AbortError from the shared helper) fails OPEN and is mirrored", async () => {
    mockGithubApiGet.mockRejectedValueOnce(Object.assign(new Error("This operation was aborted"), { name: "AbortError" }));
    const res = await post(ciRunBody());
    expect(res.status).toBe(200);
    expectCardRaised();
    expect(mockReportSilentFallback).toHaveBeenCalledWith(
      expect.objectContaining({ name: "AbortError" }),
      expect.objectContaining({ op: "draft-ci-lookup" }),
    );
  });

  it.each([["39 hex", "a".repeat(39)], ["65 hex", "a".repeat(65)], ["upper-case", "A".repeat(40)], ["empty", ""]])(
    "head_sha of the wrong shape (%s): no lookup, fails OPEN, mirrored",
    async (_label, sha) => {
      const res = await post(ciRunBody({ head_sha: sha }));
      expect(res.status).toBe(200);
      expect(mockGithubApiGet).not.toHaveBeenCalled();
      expectCardRaised();
      expect(mockReportSilentFallback).toHaveBeenCalledWith(
        null,
        expect.objectContaining({ op: "draft-ci-input" }),
      );
    },
  );

  it("malformed head_sha: no lookup (nothing unvalidated reaches the API path), fails OPEN, mirrored", async () => {
    const res = await post(ciRunBody({ head_sha: "../../x?y=1" }));
    expect(res.status).toBe(200);
    expect(mockGithubApiGet).not.toHaveBeenCalled();
    expectCardRaised();
    expect(mockReportSilentFallback).toHaveBeenCalledWith(
      null,
      expect.objectContaining({ feature: "github-webhook", op: "draft-ci-input" }),
    );
  });

  it("a non-failure CI pull_request conclusion is still dropped by the conclusion gate before any lookup", async () => {
    const res = await post(ciRunBody({ conclusion: "success" }));
    expect(res.status).toBe(200);
    expect(mockGithubApiGet).not.toHaveBeenCalled();
    expect(mockInsert).not.toHaveBeenCalled();
    expect(mockInngestSend).not.toHaveBeenCalled();
  });
});
