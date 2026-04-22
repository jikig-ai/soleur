import { describe, test, expect, vi, beforeEach } from "vitest";

// RED phase for #2776 — `conversations_list`, `conversation_archive`,
// `conversation_unarchive` MCP tools.
//
// Contract (from plan 2026-04-22-refactor-drain-web-platform-code-review-2775-2776-2777-plan.md):
//   buildConversationsTools({ userId }) returns tools scoped to the
//   authenticated user's currently connected `repo_url`. Each tool:
//     - resolves repoUrl = await getCurrentRepoUrl(userId)
//     - if null → returns { error: "disconnected", code: "no_repo_connected" }
//       with isError: true (NOT a silent empty list)
//     - archive/unarchive UPDATE WHERE (id, user_id, repo_url) — three-column
//       backstop so a cross-repo cached id fails closed as "not found".

const { mockUserRepoUrl } = vi.hoisted(() => ({
  mockUserRepoUrl: vi.fn(
    () => "https://github.com/acme/repo" as string | null,
  ),
}));

vi.mock("@/server/current-repo-url", () => ({
  getCurrentRepoUrl: (...args: unknown[]) => {
    void args;
    return Promise.resolve(mockUserRepoUrl());
  },
}));

vi.mock("@anthropic-ai/claude-agent-sdk", () => ({
  tool: vi.fn(
    (
      name: string,
      description: string,
      schema: unknown,
      handler: Function,
    ) => ({ name, description, schema, handler }),
  ),
}));

// Predicate-aware Supabase query builder mock — captures .eq() args per
// handler invocation so archive/unarchive assertions can pin the exact
// three-column WHERE filter fired by the tool.
type Predicate = { col: string; val: unknown };

function buildSelectChain(
  rows: Record<string, unknown>[],
  predicates: Predicate[],
) {
  const chain: Record<string, unknown> = {};
  const append = (col: string, val: unknown) => {
    predicates.push({ col, val });
    return chain;
  };
  chain.select = vi.fn(() => chain);
  chain.eq = vi.fn((col: string, val: unknown) => append(col, val));
  chain.in = vi.fn(() => chain);
  chain.is = vi.fn(() => chain);
  chain.not = vi.fn(() => chain);
  chain.order = vi.fn(() => chain);
  chain.limit = vi.fn(() => chain);
  chain.then = (resolve: (v: unknown) => void) =>
    resolve({ data: rows, error: null });
  return chain;
}

function buildUpdateChain(
  returned: Record<string, unknown> | null,
  predicates: Predicate[],
  updatePayload: { current: Record<string, unknown> | null },
) {
  const chain: Record<string, unknown> = {};
  const append = (col: string, val: unknown) => {
    predicates.push({ col, val });
    return chain;
  };
  chain.update = vi.fn((payload: Record<string, unknown>) => {
    updatePayload.current = payload;
    return chain;
  });
  chain.eq = vi.fn((col: string, val: unknown) => append(col, val));
  chain.select = vi.fn(() => chain);
  chain.then = (resolve: (v: unknown) => void) =>
    resolve({ data: returned ? [returned] : [], error: null });
  return chain;
}

function setupSupabaseMock(opts: {
  listRows?: Record<string, unknown>[];
  archivedRow?: Record<string, unknown> | null;
  predicates?: Predicate[];
  updatePayload?: { current: Record<string, unknown> | null };
}) {
  const predicates = opts.predicates ?? [];
  const updatePayload = opts.updatePayload ?? { current: null };
  const fromMock = vi.fn((table: string) => {
    if (table !== "conversations") throw new Error(`unexpected table ${table}`);
    // First call → list SELECT; subsequent calls → update UPDATE.
    // Tests spawn new mocks per test, so the first `from("conversations")`
    // invocation in a test wins.
    if (!fromMock.mock.calls[0] || fromMock.mock.calls.length === 1) {
      // We decide by whether listRows was provided.
      if (opts.listRows !== undefined) {
        return buildSelectChain(opts.listRows, predicates);
      }
      return buildUpdateChain(opts.archivedRow ?? null, predicates, updatePayload);
    }
    return buildUpdateChain(opts.archivedRow ?? null, predicates, updatePayload);
  });
  return {
    from: fromMock,
    predicates,
    updatePayload,
  };
}

const { mockServiceClient } = vi.hoisted(() => ({
  mockServiceClient: vi.fn(),
}));

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => mockServiceClient(),
}));

async function importBuilder() {
  return await import("@/server/conversations-tools");
}

type ToolStub = {
  name: string;
  description: string;
  schema: Record<string, unknown>;
  handler: (args: Record<string, unknown>) => Promise<{
    content: Array<{ text: string }>;
    isError?: boolean;
  }>;
};

async function getTool(name: string, userId = "u1"): Promise<ToolStub> {
  const { buildConversationsTools } = await importBuilder();
  const tools = buildConversationsTools({ userId }) as unknown as ToolStub[];
  const t = tools.find((x) => x.name === name);
  if (!t) throw new Error(`tool ${name} not found`);
  return t;
}

describe("conversations_list MCP tool", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockUserRepoUrl.mockReturnValue("https://github.com/acme/repo");
  });

  test("returns rows scoped by user_id AND repo_url", async () => {
    const predicates: Predicate[] = [];
    mockServiceClient.mockReturnValue(
      setupSupabaseMock({
        listRows: [
          {
            id: "conv-1",
            status: "active",
            domain_leader: "cto",
            last_active: "2026-04-22T00:00:00Z",
            created_at: "2026-04-22T00:00:00Z",
            archived_at: null,
          },
        ],
        predicates,
      }),
    );
    const t = await getTool("conversations_list");
    const res = await t.handler({});
    expect(res.isError).toBeFalsy();
    const payload = JSON.parse(res.content[0].text);
    expect(payload).toHaveLength(1);
    expect(payload[0].id).toBe("conv-1");
    // Verify three-column scope applied.
    const byCol = Object.fromEntries(predicates.map((p) => [p.col, p.val]));
    expect(byCol["user_id"]).toBe("u1");
    expect(byCol["repo_url"]).toBe("https://github.com/acme/repo");
  });

  test("disconnected user short-circuits with typed error (not empty list)", async () => {
    mockUserRepoUrl.mockReturnValue(null);
    mockServiceClient.mockReturnValue(setupSupabaseMock({ listRows: [] }));
    const t = await getTool("conversations_list");
    const res = await t.handler({});
    expect(res.isError).toBe(true);
    const payload = JSON.parse(res.content[0].text);
    expect(payload.code).toBe("no_repo_connected");
    expect(payload.error).toBe("disconnected");
  });

  test("closure user-binding: distinct builders scope to their userId", async () => {
    const predicates: Predicate[] = [];
    mockServiceClient.mockReturnValue(
      setupSupabaseMock({ listRows: [], predicates }),
    );
    const toolA = await getTool("conversations_list", "user-a");
    await toolA.handler({});
    // Fresh predicate array per call via a second mock setup.
    const predicatesB: Predicate[] = [];
    mockServiceClient.mockReturnValue(
      setupSupabaseMock({ listRows: [], predicates: predicatesB }),
    );
    const toolB = await getTool("conversations_list", "user-b");
    await toolB.handler({});
    expect(predicates.some((p) => p.col === "user_id" && p.val === "user-a")).toBe(true);
    expect(predicatesB.some((p) => p.col === "user_id" && p.val === "user-b")).toBe(true);
  });

  test("honors default limit=50", async () => {
    const predicates: Predicate[] = [];
    const chainMock = setupSupabaseMock({ listRows: [], predicates });
    mockServiceClient.mockReturnValue(chainMock);
    const t = await getTool("conversations_list");
    await t.handler({});
    // The chain's .limit() was called once.
    const from = chainMock.from.mock.results[0].value as Record<
      string,
      ReturnType<typeof vi.fn>
    >;
    expect((from.limit as ReturnType<typeof vi.fn>).mock.calls[0][0]).toBe(50);
  });
});

describe("conversation_archive MCP tool", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockUserRepoUrl.mockReturnValue("https://github.com/acme/repo");
  });

  test("archive round-trip: sets archived_at to ISO timestamp (pinned post-state)", async () => {
    const predicates: Predicate[] = [];
    const updatePayload: { current: Record<string, unknown> | null } = {
      current: null,
    };
    mockServiceClient.mockReturnValue(
      setupSupabaseMock({
        archivedRow: {
          id: "conv-1",
          archived_at: "2026-04-22T12:34:56.789Z",
        },
        predicates,
        updatePayload,
      }),
    );
    const t = await getTool("conversation_archive");
    const res = await t.handler({ conversationId: "conv-1" });
    expect(res.isError).toBeFalsy();
    const payload = JSON.parse(res.content[0].text);
    // Pin the exact post-state shape — archived_at is a non-null ISO string.
    expect(payload.archived_at).toEqual(
      expect.stringMatching(/^\d{4}-\d{2}-\d{2}T/),
    );
    expect(payload.id).toBe("conv-1");
    // Three-column WHERE backstop fired.
    const byCol = Object.fromEntries(predicates.map((p) => [p.col, p.val]));
    expect(byCol["id"]).toBe("conv-1");
    expect(byCol["user_id"]).toBe("u1");
    expect(byCol["repo_url"]).toBe("https://github.com/acme/repo");
    // UPDATE payload sets archived_at to a non-null ISO string.
    expect(updatePayload.current?.archived_at).toEqual(
      expect.stringMatching(/^\d{4}-\d{2}-\d{2}T/),
    );
  });

  test("cross-repo cached id fails closed (0 rows → not found)", async () => {
    mockServiceClient.mockReturnValue(
      setupSupabaseMock({ archivedRow: null }),
    );
    const t = await getTool("conversation_archive");
    const res = await t.handler({ conversationId: "conv-wrong-repo" });
    expect(res.isError).toBe(true);
    const payload = JSON.parse(res.content[0].text);
    expect(payload.code).toBe("not_found");
  });

  test("cross-user cached id fails closed (0 rows → not found)", async () => {
    mockServiceClient.mockReturnValue(
      setupSupabaseMock({ archivedRow: null }),
    );
    const t = await getTool("conversation_archive", "user-a");
    const res = await t.handler({ conversationId: "conv-of-user-b" });
    expect(res.isError).toBe(true);
    const payload = JSON.parse(res.content[0].text);
    expect(payload.code).toBe("not_found");
  });

  test("disconnected user short-circuits with typed error", async () => {
    mockUserRepoUrl.mockReturnValue(null);
    mockServiceClient.mockReturnValue(
      setupSupabaseMock({ archivedRow: null }),
    );
    const t = await getTool("conversation_archive");
    const res = await t.handler({ conversationId: "conv-1" });
    expect(res.isError).toBe(true);
    const payload = JSON.parse(res.content[0].text);
    expect(payload.code).toBe("no_repo_connected");
  });
});

describe("conversation_unarchive MCP tool", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockUserRepoUrl.mockReturnValue("https://github.com/acme/repo");
  });

  test("unarchive sets archived_at to null (pinned post-state)", async () => {
    const updatePayload: { current: Record<string, unknown> | null } = {
      current: null,
    };
    mockServiceClient.mockReturnValue(
      setupSupabaseMock({
        archivedRow: { id: "conv-1", archived_at: null },
        updatePayload,
      }),
    );
    const t = await getTool("conversation_unarchive");
    const res = await t.handler({ conversationId: "conv-1" });
    expect(res.isError).toBeFalsy();
    const payload = JSON.parse(res.content[0].text);
    expect(payload.archived_at).toBe(null);
    expect(payload.id).toBe("conv-1");
    // UPDATE payload sets archived_at to null exactly.
    expect(updatePayload.current?.archived_at).toBe(null);
  });

  test("three-column WHERE backstop", async () => {
    const predicates: Predicate[] = [];
    mockServiceClient.mockReturnValue(
      setupSupabaseMock({
        archivedRow: { id: "conv-1", archived_at: null },
        predicates,
      }),
    );
    const t = await getTool("conversation_unarchive");
    await t.handler({ conversationId: "conv-1" });
    const byCol = Object.fromEntries(predicates.map((p) => [p.col, p.val]));
    expect(byCol["id"]).toBe("conv-1");
    expect(byCol["user_id"]).toBe("u1");
    expect(byCol["repo_url"]).toBe("https://github.com/acme/repo");
  });
});

describe("conversation_update_status MCP tool", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockUserRepoUrl.mockReturnValue("https://github.com/acme/repo");
  });

  test("update round-trip: sets status to exact value (pinned post-state)", async () => {
    const updatePayload: { current: Record<string, unknown> | null } = {
      current: null,
    };
    mockServiceClient.mockReturnValue(
      setupSupabaseMock({
        archivedRow: { id: "conv-1", status: "completed" },
        updatePayload,
      }),
    );
    const t = await getTool("conversation_update_status");
    const res = await t.handler({
      conversationId: "conv-1",
      status: "completed",
    });
    expect(res.isError).toBeFalsy();
    const payload = JSON.parse(res.content[0].text);
    expect(payload.status).toBe("completed");
    expect(payload.id).toBe("conv-1");
    // UPDATE payload sets status to the exact value (pin post-state per
    // cq-mutation-assertions-pin-exact-post-state).
    expect(updatePayload.current?.status).toBe("completed");
  });

  test("three-column WHERE backstop (cross-repo fail closed)", async () => {
    const predicates: Predicate[] = [];
    mockServiceClient.mockReturnValue(
      setupSupabaseMock({
        archivedRow: { id: "conv-1", status: "active" },
        predicates,
      }),
    );
    const t = await getTool("conversation_update_status");
    await t.handler({ conversationId: "conv-1", status: "active" });
    const byCol = Object.fromEntries(predicates.map((p) => [p.col, p.val]));
    expect(byCol["id"]).toBe("conv-1");
    expect(byCol["user_id"]).toBe("u1");
    expect(byCol["repo_url"]).toBe("https://github.com/acme/repo");
  });

  test("0 rows returns not_found (cross-repo cached id)", async () => {
    mockServiceClient.mockReturnValue(
      setupSupabaseMock({ archivedRow: null }),
    );
    const t = await getTool("conversation_update_status");
    const res = await t.handler({
      conversationId: "conv-wrong-repo",
      status: "completed",
    });
    expect(res.isError).toBe(true);
    const payload = JSON.parse(res.content[0].text);
    expect(payload.code).toBe("not_found");
  });

  test("disconnected user short-circuits with typed error", async () => {
    mockUserRepoUrl.mockReturnValue(null);
    mockServiceClient.mockReturnValue(
      setupSupabaseMock({ archivedRow: null }),
    );
    const t = await getTool("conversation_update_status");
    const res = await t.handler({
      conversationId: "conv-1",
      status: "completed",
    });
    expect(res.isError).toBe(true);
    const payload = JSON.parse(res.content[0].text);
    expect(payload.code).toBe("no_repo_connected");
  });
});
