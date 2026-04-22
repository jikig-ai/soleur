import { describe, test, expect, vi, beforeEach } from "vitest";

// RED phase for plan 2026-04-22-fix-command-center-stale-conversations-after-repo-swap.
//
// Contract:
//   lookupConversationForPath accepts a third `repoUrl` argument and adds
//   .eq("repo_url", repoUrl) to the query. When repoUrl is null/empty the
//   helper short-circuits to { ok: true, row: null } without issuing a query
//   (no connected repo means no resumable thread).

const { mockFrom, mockReportSilentFallback } = vi.hoisted(() => ({
  mockFrom: vi.fn(),
  mockReportSilentFallback: vi.fn(),
}));

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: vi.fn(() => ({ from: mockFrom })),
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
  warnSilentFallback: vi.fn(),
}));

async function importHelper() {
  return await import("@/server/lookup-conversation-for-path");
}

function mockSingleChain(result: { data: unknown; error: unknown }) {
  const calls = { eq: [] as Array<[string, unknown]> };
  const chain = {
    select: vi.fn(() => chain),
    eq: vi.fn((col: string, val: unknown) => {
      calls.eq.push([col, val]);
      return chain;
    }),
    is: vi.fn(() => chain),
    order: vi.fn(() => chain),
    limit: vi.fn(() => chain),
    maybeSingle: vi.fn(async () => result),
  };
  mockFrom.mockImplementation(() => chain);
  return { chain, calls };
}

describe("lookupConversationForPath — repo_url scoping", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  test("adds .eq('repo_url', repoUrl) to the query", async () => {
    const { calls } = mockSingleChain({
      data: {
        id: "conv-new",
        context_path: "overview/vision.md",
        last_active: "2026-04-22T00:00:00Z",
        messages: [{ count: 1 }],
      },
      error: null,
    });

    const { lookupConversationForPath } = await importHelper();
    await lookupConversationForPath(
      "u1",
      "overview/vision.md",
      "https://github.com/acme/new",
    );

    // Exact post-state pin per cq-mutation-assertions-pin-exact-post-state.
    const repoEq = calls.eq.find(([col]) => col === "repo_url");
    expect(repoEq).toBeDefined();
    expect(repoEq?.[1]).toBe("https://github.com/acme/new");
  });

  test("returns ONLY the current-repo row when two rows share (user_id, context_path)", async () => {
    // Predicate-aware mock: simulate two rows keyed by repo_url. Only
    // the row whose stored repo_url matches the .eq("repo_url", ...)
    // predicate may be returned — if the helper omits the predicate,
    // the mock returns the OLD row and the assertion fails.
    const storedByRepo: Record<string, Record<string, unknown>> = {
      "https://github.com/acme/old": {
        id: "conv-old-repo",
        context_path: "overview/vision.md",
        last_active: "2026-04-17T00:00:00Z",
        messages: [{ count: 5 }],
      },
      "https://github.com/acme/new": {
        id: "conv-new-repo",
        context_path: "overview/vision.md",
        last_active: "2026-04-22T00:00:00Z",
        messages: [{ count: 1 }],
      },
    };
    const predicates: Array<[string, unknown]> = [];
    const chain: Record<string, unknown> = {};
    Object.assign(chain, {
      select: vi.fn(() => chain),
      eq: vi.fn((col: string, val: unknown) => {
        predicates.push([col, val]);
        return chain;
      }),
      is: vi.fn(() => chain),
      order: vi.fn(() => chain),
      limit: vi.fn(() => chain),
      maybeSingle: vi.fn(async () => {
        const repoPred = predicates.find(([c]) => c === "repo_url");
        if (!repoPred) {
          // Helper omitted the repo_url predicate — return the OLD row
          // so the test catches the regression.
          return { data: storedByRepo["https://github.com/acme/old"], error: null };
        }
        return { data: storedByRepo[String(repoPred[1])] ?? null, error: null };
      }),
    });
    mockFrom.mockImplementation(() => chain);

    const { lookupConversationForPath } = await importHelper();
    const result = await lookupConversationForPath(
      "u1",
      "overview/vision.md",
      "https://github.com/acme/new",
    );

    expect(result.ok).toBe(true);
    if (!result.ok) throw new Error("unreachable");
    expect(result.row?.id).toBe("conv-new-repo");
  });

  test("null repoUrl short-circuits to { ok: true, row: null } without querying", async () => {
    mockSingleChain({ data: null, error: null });

    const { lookupConversationForPath } = await importHelper();
    const result = await lookupConversationForPath(
      "u1",
      "overview/vision.md",
      null,
    );

    expect(result).toEqual({ ok: true, row: null });
    // No connected repo → no Supabase round-trip at all.
    expect(mockFrom).not.toHaveBeenCalled();
  });

  test("empty-string repoUrl short-circuits to { ok: true, row: null } without querying", async () => {
    mockSingleChain({ data: null, error: null });

    const { lookupConversationForPath } = await importHelper();
    const result = await lookupConversationForPath(
      "u1",
      "overview/vision.md",
      "",
    );

    expect(result).toEqual({ ok: true, row: null });
    expect(mockFrom).not.toHaveBeenCalled();
  });
});
