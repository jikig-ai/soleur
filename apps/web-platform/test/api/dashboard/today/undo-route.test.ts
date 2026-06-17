/**
 * PR-B (#4379) AC9 + AC14 — POST /api/dashboard/today/[id]/undo
 *
 * Covers:
 *   - Happy path full reversal across 5 reversal-kinds.
 *   - GitHub-side already-deleted (404) → idempotent already_absent.
 *   - GitHub installation revoked (401) → failed_4xx in ledger.
 *   - Partial failure → 207 + rewrite reversal_handles to still-failing
 *     subset; undone_at stays NULL.
 *   - Merged-PR guard → failed_410_merged (terminal).
 *   - Double-click idempotency: reversal_handles IS NULL → 409
 *     "Already undone."
 *   - Owner-mismatch / no-auth gates.
 */

import { describe, test, expect, vi, beforeEach } from "vitest";

const {
  mockGetUser,
  mockTenantFrom,
  mockServiceFrom,
  mockValidateOrigin,
  mockCreateGitHubAppClient,
  mockResolveInstallationId,
} = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  mockTenantFrom: vi.fn(),
  mockServiceFrom: vi.fn(),
  mockValidateOrigin: vi.fn(() => ({
    valid: true,
    origin: "https://app.soleur.ai",
  })),
  mockCreateGitHubAppClient: vi.fn(),
  mockResolveInstallationId: vi.fn(),
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({
    auth: { getUser: mockGetUser },
    from: mockTenantFrom,
  })),
}));
vi.mock("@/lib/supabase/service", () => ({
  getServiceClient: vi.fn(() => ({ from: mockServiceFrom })),
}));
vi.mock("@/lib/auth/validate-origin", () => ({
  validateOrigin: mockValidateOrigin,
  rejectCsrf: vi.fn(
    () => new Response(JSON.stringify({ error: "Forbidden" }), { status: 403 }),
  ),
}));
vi.mock("@/server/github/app-client", () => ({
  createGitHubAppClient: mockCreateGitHubAppClient,
}));
// ADR-044 PR-2 (#5462): the install id is now resolved via the membership-checked
// `resolveInstallationId` RPC (was a direct `users.github_installation_id` read).
vi.mock("@/server/resolve-installation-id", () => ({
  resolveInstallationId: mockResolveInstallationId,
}));
vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
}));

const FOUNDER_ID = "founder-123";
const MESSAGE_ID = "msg-001";

interface ServiceState {
  actionSend: {
    id: string;
    user_id: string;
    message_id: string;
    reversal_handles: unknown[] | null;
    artifact_url: string | null;
    undone_at: string | null;
  } | null;
  installationId: number | null;
}

interface CapturedUpdate {
  patch: Record<string, unknown>;
}

function setupTenantChain(found: boolean) {
  const chain = {
    from: vi.fn((_t?: string) => chain),
    select: vi.fn((_c?: string) => chain),
    eq: vi.fn((_c?: string, _v?: unknown) => chain),
    maybeSingle: vi.fn(async () => ({
      data: found ? { id: MESSAGE_ID } : null,
      error: null,
    })),
  };
  (mockTenantFrom as unknown as { mockImplementation: (impl: (table: string) => unknown) => void }).mockImplementation((table: string) => chain.from(table));
}

function setupServiceChain(state: ServiceState) {
  const captured: { updates: CapturedUpdate[] } = { updates: [] };

  const sendReadChain = {
    select: vi.fn(() => sendReadChain),
    eq: vi.fn(() => sendReadChain),
    maybeSingle: vi.fn(async () => ({
      data: state.actionSend,
      error: null,
    })),
    update: vi.fn((patch: Record<string, unknown>) => {
      const u = { patch };
      captured.updates.push(u);
      const eqChain = {
        eq: vi.fn(() => eqChain),
        is: vi.fn(() => Promise.resolve({ error: null })),
      };
      return eqChain;
    }),
  };
  (mockServiceFrom as unknown as { mockImplementation: (impl: (table: string) => unknown) => void }).mockImplementation((table: string) => {
    if (table === "action_sends") return sendReadChain;
    throw new Error(`unexpected service-role table ${table}`);
  });
  // ADR-044 PR-2: the install id is resolved via the membership-checked RPC
  // (mocked), not a `users` service read. `null` → 403 unauthorized.
  mockResolveInstallationId.mockResolvedValue(state.installationId);
  return captured;
}

interface OctokitMockBehavior {
  // map route to either a data response, or an Error-with-status to throw
  routes: Record<string, { data?: unknown; throwStatus?: number }>;
}

function setupOctokit(behavior: OctokitMockBehavior) {
  const requestSpy = vi.fn(async (route: string, _params: unknown) => {
    const cfg = behavior.routes[route];
    if (!cfg) {
      const err: Error & { status?: number } = new Error(
        `unexpected route ${route}`,
      );
      err.status = 500;
      throw err;
    }
    if (cfg.throwStatus !== undefined) {
      const err: Error & { status?: number } = new Error(`status ${cfg.throwStatus}`);
      err.status = cfg.throwStatus;
      throw err;
    }
    return { data: cfg.data };
  });
  mockCreateGitHubAppClient.mockResolvedValue({ request: requestSpy });
  return requestSpy;
}

function makeRequest() {
  return new Request("https://app.soleur.ai/api/dashboard/today/msg-001/undo", {
    method: "POST",
    headers: { Origin: "https://app.soleur.ai" },
  });
}
const paramsPromise = Promise.resolve({ id: MESSAGE_ID });

beforeEach(() => {
  vi.clearAllMocks();
  mockGetUser.mockResolvedValue({ data: { user: { id: FOUNDER_ID } } });
  mockValidateOrigin.mockReturnValue({
    valid: true,
    origin: "https://app.soleur.ai",
  });
});

describe("POST /api/dashboard/today/[id]/undo", () => {
  test("happy path 5-kind reversal: all reverted, undone_at set, reversal_handles cleared", async () => {
    setupTenantChain(true);
    const captured = setupServiceChain({
      actionSend: {
        id: "as-1",
        user_id: FOUNDER_ID,
        message_id: MESSAGE_ID,
        reversal_handles: [
          {
            kind: "pr_comment",
            owner: "acme",
            repo: "repo",
            commentId: 100,
            issueNumber: 7,
          },
          {
            kind: "pr_review_comment",
            owner: "acme",
            repo: "repo",
            commentId: 101,
            prNumber: 7,
          },
          {
            kind: "issue_label",
            owner: "acme",
            repo: "repo",
            issueNumber: 42,
            labelName: "soleur/triage",
          },
          {
            kind: "branch",
            owner: "acme",
            repo: "repo",
            branchRef: "soleur/fix-cve",
          },
          {
            kind: "pr",
            owner: "acme",
            repo: "repo",
            prNumber: 99,
            branchRef: "soleur/cve-bump",
          },
        ],
        artifact_url: "https://github.com/acme/repo/issues/7",
        undone_at: null,
      },
      installationId: 99,
    });
    setupOctokit({
      routes: {
        "DELETE /repos/{owner}/{repo}/issues/comments/{comment_id}": { data: {} },
        "DELETE /repos/{owner}/{repo}/pulls/comments/{comment_id}": { data: {} },
        "DELETE /repos/{owner}/{repo}/issues/{issue_number}/labels/{name}": { data: {} },
        "DELETE /repos/{owner}/{repo}/git/refs/{ref}": { data: {} },
        "GET /repos/{owner}/{repo}/pulls/{pull_number}": { data: { merged: false } },
        "PATCH /repos/{owner}/{repo}/pulls/{pull_number}": { data: { state: "closed" } },
      },
    });
    const { POST } = await import("@/app/api/dashboard/today/[id]/undo/route");
    const res = await POST(makeRequest(), { params: paramsPromise });
    expect(res.status).toBe(200);
    const body = (await res.json()) as {
      allSucceeded: boolean;
      elements: { status: string }[];
    };
    expect(body.allSucceeded).toBe(true);
    expect(body.elements).toHaveLength(5);
    expect(body.elements.every((e) => e.status === "reverted")).toBe(true);
    // undone_at + reversal_handles cleared in a single UPDATE.
    expect(captured.updates).toHaveLength(1);
    const u = captured.updates[0].patch;
    expect(typeof u.undone_at).toBe("string");
    expect(u.reversal_handles).toBeNull();
  });

  test("idempotent absent: GitHub returns 404 → status already_absent (still counts as success)", async () => {
    setupTenantChain(true);
    const captured = setupServiceChain({
      actionSend: {
        id: "as-2",
        user_id: FOUNDER_ID,
        message_id: MESSAGE_ID,
        reversal_handles: [
          {
            kind: "pr_comment",
            owner: "acme",
            repo: "repo",
            commentId: 100,
            issueNumber: 7,
          },
        ],
        artifact_url: "https://github.com/acme/repo/issues/7#issuecomment-100",
        undone_at: null,
      },
      installationId: 99,
    });
    setupOctokit({
      routes: {
        "DELETE /repos/{owner}/{repo}/issues/comments/{comment_id}": {
          throwStatus: 404,
        },
      },
    });
    const { POST } = await import("@/app/api/dashboard/today/[id]/undo/route");
    const res = await POST(makeRequest(), { params: paramsPromise });
    expect(res.status).toBe(200);
    const body = (await res.json()) as {
      allSucceeded: boolean;
      elements: { status: string }[];
    };
    expect(body.allSucceeded).toBe(true);
    expect(body.elements[0].status).toBe("already_absent");
    expect(captured.updates[0].patch.undone_at).toBeTruthy();
  });

  test("partial failure: one element 5xx → 207 + reversal_handles rewritten to still-failing subset", async () => {
    setupTenantChain(true);
    const captured = setupServiceChain({
      actionSend: {
        id: "as-3",
        user_id: FOUNDER_ID,
        message_id: MESSAGE_ID,
        reversal_handles: [
          {
            kind: "issue_label",
            owner: "acme",
            repo: "repo",
            issueNumber: 42,
            labelName: "soleur/triage",
          },
          {
            kind: "pr_comment",
            owner: "acme",
            repo: "repo",
            commentId: 100,
            issueNumber: 42,
          },
        ],
        artifact_url: "https://github.com/acme/repo/issues/42",
        undone_at: null,
      },
      installationId: 99,
    });
    setupOctokit({
      routes: {
        "DELETE /repos/{owner}/{repo}/issues/{issue_number}/labels/{name}": {
          data: {},
        },
        "DELETE /repos/{owner}/{repo}/issues/comments/{comment_id}": {
          throwStatus: 500,
        },
      },
    });
    const { POST } = await import("@/app/api/dashboard/today/[id]/undo/route");
    const res = await POST(makeRequest(), { params: paramsPromise });
    expect(res.status).toBe(207);
    const body = (await res.json()) as {
      allSucceeded: boolean;
      elements: { status: string }[];
    };
    expect(body.allSucceeded).toBe(false);
    expect(body.elements.map((e) => e.status)).toEqual([
      "reverted",
      "failed_5xx",
    ]);
    // Rewrite contains only the still-failing element; undone_at NOT set.
    const u = captured.updates[0].patch;
    expect(Array.isArray(u.reversal_handles)).toBe(true);
    expect((u.reversal_handles as unknown[]).length).toBe(1);
    expect(u.undone_at).toBeUndefined();
  });

  test("merged-PR guard: PR pulls merged=true → failed_410_merged, terminal", async () => {
    setupTenantChain(true);
    setupServiceChain({
      actionSend: {
        id: "as-4",
        user_id: FOUNDER_ID,
        message_id: MESSAGE_ID,
        reversal_handles: [
          {
            kind: "pr",
            owner: "acme",
            repo: "repo",
            prNumber: 99,
            branchRef: "soleur/cve-bump",
          },
        ],
        artifact_url: "https://github.com/acme/repo/pull/99",
        undone_at: null,
      },
      installationId: 99,
    });
    setupOctokit({
      routes: {
        "GET /repos/{owner}/{repo}/pulls/{pull_number}": {
          data: { merged: true },
        },
      },
    });
    const { POST } = await import("@/app/api/dashboard/today/[id]/undo/route");
    const res = await POST(makeRequest(), { params: paramsPromise });
    expect(res.status).toBe(207);
    const body = (await res.json()) as {
      elements: { status: string }[];
    };
    expect(body.elements[0].status).toBe("failed_410_merged");
  });

  test("already-undone double-click: reversal_handles IS NULL → 409", async () => {
    setupTenantChain(true);
    setupServiceChain({
      actionSend: {
        id: "as-5",
        user_id: FOUNDER_ID,
        message_id: MESSAGE_ID,
        reversal_handles: null,
        artifact_url: "https://github.com/acme/repo/issues/7",
        undone_at: "2026-05-25T13:00:00Z",
      },
      installationId: 99,
    });
    const { POST } = await import("@/app/api/dashboard/today/[id]/undo/route");
    const res = await POST(makeRequest(), { params: paramsPromise });
    expect(res.status).toBe(409);
    const body = (await res.json()) as { error: string; copy: string };
    expect(body.error).toBe("already_undone");
    expect(body.copy).toBe("Already undone.");
  });

  test("installation revoked: 401 propagates as failed_4xx in ledger", async () => {
    setupTenantChain(true);
    setupServiceChain({
      actionSend: {
        id: "as-6",
        user_id: FOUNDER_ID,
        message_id: MESSAGE_ID,
        reversal_handles: [
          {
            kind: "issue_label",
            owner: "acme",
            repo: "repo",
            issueNumber: 42,
            labelName: "soleur/triage",
          },
        ],
        artifact_url: "https://github.com/acme/repo/issues/42",
        undone_at: null,
      },
      installationId: 99,
    });
    setupOctokit({
      routes: {
        "DELETE /repos/{owner}/{repo}/issues/{issue_number}/labels/{name}": {
          throwStatus: 401,
        },
      },
    });
    const { POST } = await import("@/app/api/dashboard/today/[id]/undo/route");
    const res = await POST(makeRequest(), { params: paramsPromise });
    expect(res.status).toBe(207);
    const body = (await res.json()) as {
      elements: { status: string }[];
    };
    expect(body.elements[0].status).toBe("failed_4xx");
  });

  test("owner mismatch → 403", async () => {
    setupTenantChain(false);
    const { POST } = await import("@/app/api/dashboard/today/[id]/undo/route");
    const res = await POST(makeRequest(), { params: paramsPromise });
    expect(res.status).toBe(403);
  });

  test("no auth → 401", async () => {
    mockGetUser.mockResolvedValue({ data: { user: null } });
    const { POST } = await import("@/app/api/dashboard/today/[id]/undo/route");
    const res = await POST(makeRequest(), { params: paramsPromise });
    expect(res.status).toBe(401);
  });

  test("no installation id → 403 github_installation_unauthorized", async () => {
    setupTenantChain(true);
    setupServiceChain({
      actionSend: {
        id: "as-7",
        user_id: FOUNDER_ID,
        message_id: MESSAGE_ID,
        reversal_handles: [
          { kind: "issue_label", owner: "acme", repo: "repo", issueNumber: 1, labelName: "x" },
        ],
        artifact_url: null,
        undone_at: null,
      },
      installationId: null,
    });
    const { POST } = await import("@/app/api/dashboard/today/[id]/undo/route");
    const res = await POST(makeRequest(), { params: paramsPromise });
    expect(res.status).toBe(403);
    const body = (await res.json()) as { error: string };
    expect(body.error).toBe("github_installation_unauthorized");
  });
});
