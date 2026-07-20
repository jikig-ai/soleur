import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// Route tests for POST/GET /api/workstream/issues. The accessor is partially
// mocked (createWorkstreamIssue/resolveWorkstreamBoardMeta stubbed; the real
// WorkstreamWriteError + classifyWriteError stay live). Asserts:
//   - 401 unauth (AC: session-gated)
//   - the route passes ONLY {title,body,status} to the accessor and NEVER an
//     owner/repo/login from the body (AC4 anti-spoof, AC5 no request owner/repo)
//   - 422 empty title (AC9), 502 on write failure, 429 throttle (AC15)
//   - GET returns { issues, board } (AC11/AC14 board meta)

const getUser = vi.fn();
vi.mock("@/lib/supabase/server", () => ({
  createClient: async () => ({ auth: { getUser: getUser } }),
}));

const createWorkstreamIssue = vi.fn();
const resolveWorkstreamBoardMeta = vi.fn();
vi.mock("@/server/workstream/mutate-workstream-issue", async (io) => ({
  ...(await io<typeof import("@/server/workstream/mutate-workstream-issue")>()),
  createWorkstreamIssue: (...a: unknown[]) => createWorkstreamIssue(...a),
  resolveWorkstreamBoardMeta: (...a: unknown[]) =>
    resolveWorkstreamBoardMeta(...a),
}));

const getWorkstreamIssues = vi.fn();
vi.mock("@/server/workstream/get-workstream-issues", () => ({
  getWorkstreamIssues: (...a: unknown[]) => getWorkstreamIssues(...a),
}));

const captureException = vi.fn();
// Explicit method set (not a spread of the real module — @sentry/nextjs
// re-exports via getters that `{...actual}` doesn't copy). These are the only
// Sentry methods reached by this file's code paths: the route GET/POST catch
// (captureException) and the write-rate limiter's rejection log (addBreadcrumb).
vi.mock("@sentry/nextjs", () => ({
  captureException: (...a: unknown[]) => captureException(...a),
  addBreadcrumb: vi.fn(),
}));

import { POST, GET } from "@/app/api/workstream/issues/route";
import { __resetWorkstreamWriteThrottleForTest } from "@/server/workstream/workstream-write-throttle";

function req(body: unknown): Request {
  return new Request("http://localhost/api/workstream/issues", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

beforeEach(() => {
  vi.clearAllMocks();
  __resetWorkstreamWriteThrottleForTest();
  getUser.mockResolvedValue({ data: { user: { id: "user-9" } } });
  createWorkstreamIssue.mockResolvedValue({ id: "321", title: "Made" });
  resolveWorkstreamBoardMeta.mockResolvedValue({
    onKanbanOrg: false,
    projectWritable: false,
  });
  getWorkstreamIssues.mockResolvedValue([]);
});

afterEach(() => vi.clearAllMocks());

describe("POST /api/workstream/issues", () => {
  it("401s an unauthenticated caller", async () => {
    getUser.mockResolvedValue({ data: { user: null } });
    const res = await POST(req({ title: "x" }));
    expect(res.status).toBe(401);
    expect(createWorkstreamIssue).not.toHaveBeenCalled();
  });

  it("creates via the accessor with userId + only title/body/status (AC4/AC5)", async () => {
    const res = await POST(
      req({
        title: "Real issue",
        body: "desc",
        status: "in_progress",
        // hostile fields the route MUST ignore:
        owner: "attacker",
        repo: "evil",
        initiatorLogin: "victim",
        installationId: 999,
      }),
    );
    expect(res.status).toBe(200);
    expect(createWorkstreamIssue).toHaveBeenCalledTimes(1);
    const [uid, input] = createWorkstreamIssue.mock.calls[0];
    expect(uid).toBe("user-9");
    expect(input).toEqual({
      title: "Real issue",
      body: "desc",
      status: "in_progress",
    });
    // Never forwards owner/repo/login/installationId.
    expect(input).not.toHaveProperty("owner");
    expect(input).not.toHaveProperty("repo");
    expect(input).not.toHaveProperty("initiatorLogin");
    const json = (await res.json()) as { issue: { id: string } };
    expect(json.issue.id).toBe("321");
  });

  it("422s an empty/whitespace title without calling the accessor (AC9)", async () => {
    const res = await POST(req({ title: "   " }));
    expect(res.status).toBe(422);
    expect(createWorkstreamIssue).not.toHaveBeenCalled();
  });

  it("422s an out-of-enum status (security nit)", async () => {
    const res = await POST(req({ title: "x", status: "bogus" }));
    expect(res.status).toBe(422);
    expect(createWorkstreamIssue).not.toHaveBeenCalled();
  });

  it("422s create with status=done (a new issue cannot be born closed)", async () => {
    const res = await POST(req({ title: "x", status: "done" }));
    expect(res.status).toBe(422);
    expect(createWorkstreamIssue).not.toHaveBeenCalled();
  });

  it("502s when the write fails", async () => {
    createWorkstreamIssue.mockRejectedValue(
      Object.assign(new Error("boom"), { status: 500 }),
    );
    const res = await POST(req({ title: "x" }));
    expect(res.status).toBe(502);
  });

  it("maps a 403 (read-only install) to 403 (AC14)", async () => {
    createWorkstreamIssue.mockRejectedValue(
      Object.assign(new Error("no write"), { status: 403 }),
    );
    const res = await POST(req({ title: "x" }));
    expect(res.status).toBe(403);
  });

  it("throttles after the per-user budget (429 slow-down) (AC15)", async () => {
    // Default budget is generous; exhaust it deterministically.
    let last = 200;
    for (let i = 0; i < 60; i++) {
      last = (await POST(req({ title: `t${i}` }))).status;
      if (last === 429) break;
    }
    expect(last).toBe(429);
  });
});

describe("GET /api/workstream/issues", () => {
  it("returns { issues, board } with board precedence meta (AC11)", async () => {
    getWorkstreamIssues.mockResolvedValue([{ id: "1" }]);
    resolveWorkstreamBoardMeta.mockResolvedValue({
      onKanbanOrg: true,
      projectWritable: false,
    });
    const res = await GET();
    expect(res.status).toBe(200);
    const json = (await res.json()) as {
      issues: unknown[];
      board: { onKanbanOrg: boolean; projectWritable: boolean };
    };
    expect(json.issues).toHaveLength(1);
    expect(json.board).toEqual({ onKanbanOrg: true, projectWritable: false });
  });

  it("502s when the read throws", async () => {
    getWorkstreamIssues.mockRejectedValue(new Error("gh down"));
    const res = await GET();
    expect(res.status).toBe(502);
    // A generic (non-degraded) error keeps its route-level Sentry capture.
    expect(captureException).toHaveBeenCalledTimes(1);
  });

  it("502s a degraded read but does NOT double-captureException it (AC5)", async () => {
    const { WorkstreamDegradedError } = await import("@/lib/workstream");
    // board meta resolves (beforeEach) so Promise.all rejects deterministically
    // on the accessor throw, not on a board-meta race.
    getWorkstreamIssues.mockRejectedValue(
      new WorkstreamDegradedError("workstream read degraded"),
    );
    const res = await GET();
    expect(res.status).toBe(502);
    const json = (await res.json()) as { error: string };
    expect(json.error).toBe("workstream_query_error");
    // Already mirrored at the degrade source — the route must NOT re-capture.
    expect(captureException).not.toHaveBeenCalled();
  });
});
