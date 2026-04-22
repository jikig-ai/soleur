import { describe, test, expect, vi, beforeEach } from "vitest";

// RED phase for plan 2026-04-22-fix-command-center-stale-conversations-after-repo-swap
// Phase 4.2.
//
// Contract:
//   After a user disconnects their repo (users.repo_url = null), any call
//   through the KB-chat resume path MUST return "no row" — no stale pre-
//   disconnect conversation may be returned. This guards the exact failure
//   mode the bug reproduces: opening overview/vision.md in a freshly-
//   connected repo accidentally resumes the la-chatte thread.

const { mockFrom } = vi.hoisted(() => ({ mockFrom: vi.fn() }));

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: vi.fn(() => ({ from: mockFrom })),
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
  warnSilentFallback: vi.fn(),
}));

function mockDb(stored: {
  repo_url: string;
  row: {
    id: string;
    context_path: string;
    last_active: string;
    messages: Array<{ count: number }>;
  };
}) {
  // Emulates: only rows whose repo_url matches the .eq("repo_url", ...)
  // predicate pass through. Any other predicate short-circuits to miss.
  const chain: Record<string, unknown> = {};
  const predicates: Array<[string, unknown]> = [];

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
      // Without a repo_url predicate, the pre-fix code would return the
      // orphaned row — reproducing the bug. We represent that by returning
      // the stored row when no repo_url filter was applied.
      if (!repoPred) {
        return { data: stored.row, error: null };
      }
      if (repoPred[1] === stored.repo_url) {
        return { data: stored.row, error: null };
      }
      return { data: null, error: null };
    }),
  });
  mockFrom.mockImplementation(() => chain);
  return { predicates };
}

describe("lookupConversationForPath — disconnect hides conversations", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  test("null repoUrl (disconnected) returns no row even if a matching path exists", async () => {
    mockDb({
      repo_url: "https://github.com/acme/la-chatte",
      row: {
        id: "conv-la-chatte-vision",
        context_path: "overview/vision.md",
        last_active: "2026-04-17T00:00:00Z",
        messages: [{ count: 5 }],
      },
    });

    const { lookupConversationForPath } = await import(
      "@/server/lookup-conversation-for-path"
    );
    const result = await lookupConversationForPath(
      "u1",
      "overview/vision.md",
      null,
    );

    expect(result).toEqual({ ok: true, row: null });
  });

  test("reconnecting to a DIFFERENT repo does not resume the disconnected repo's thread", async () => {
    mockDb({
      repo_url: "https://github.com/acme/la-chatte",
      row: {
        id: "conv-la-chatte-vision",
        context_path: "overview/vision.md",
        last_active: "2026-04-17T00:00:00Z",
        messages: [{ count: 5 }],
      },
    });

    const { lookupConversationForPath } = await import(
      "@/server/lookup-conversation-for-path"
    );
    const result = await lookupConversationForPath(
      "u1",
      "overview/vision.md",
      "https://github.com/acme/au-chat-chat",
    );

    expect(result).toEqual({ ok: true, row: null });
  });

  test("reconnecting to the SAME repo restores the original thread", async () => {
    mockDb({
      repo_url: "https://github.com/acme/la-chatte",
      row: {
        id: "conv-la-chatte-vision",
        context_path: "overview/vision.md",
        last_active: "2026-04-17T00:00:00Z",
        messages: [{ count: 5 }],
      },
    });

    const { lookupConversationForPath } = await import(
      "@/server/lookup-conversation-for-path"
    );
    const result = await lookupConversationForPath(
      "u1",
      "overview/vision.md",
      "https://github.com/acme/la-chatte",
    );

    expect(result.ok).toBe(true);
    if (!result.ok) throw new Error("unreachable");
    expect(result.row?.id).toBe("conv-la-chatte-vision");
  });
});
