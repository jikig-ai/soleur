import { vi } from "vitest";

/**
 * Shared mock scaffolding for agent-runner test files.
 *
 * vi.mock() declarations stay in each test file (vitest hoists them).
 * This helper provides the Supabase mock implementation and query helpers
 * that both agent-runner-tools.test.ts and agent-runner-cost.test.ts share.
 */

export const DEFAULT_API_KEY_ROW = {
  id: "key-1",
  provider: "anthropic",
  encrypted_key: Buffer.from("test").toString("base64"),
  iv: Buffer.from("test-iv-1234").toString("base64"),
  auth_tag: Buffer.from("test-tag-1234567").toString("base64"),
  key_version: 2,
};

/**
 * Creates a chainable mock for the `api_keys` table that supports both:
 * - getUserApiKey:  select().eq().eq().eq().limit().single() -> { data, error }
 * - getUserServiceTokens: await select().eq().eq() -> { data, error }
 */
export function createApiKeysMock(
  rows: Record<string, unknown>[] = [DEFAULT_API_KEY_ROW],
) {
  const createChain = (): Record<string, unknown> => ({
    data: rows,
    error: null,
    eq: () => createChain(),
    limit: () => ({ single: () => ({ data: rows[0] ?? null, error: null }) }),
    then: (resolve: (v: unknown) => void) => resolve({ data: rows, error: null }),
  });
  return { select: () => createChain() };
}

/**
 * Build a `mockFrom` implementation covering the tables agent-runner touches.
 * Pass optional overrides per table name.
 */
export function createSupabaseMockImpl(
  mockFrom: ReturnType<typeof vi.fn>,
  opts: {
    userData?: Record<string, unknown>;
    apiKeyRows?: Record<string, unknown>[];
  } = {},
) {
  const userData = opts.userData ?? {
    workspace_path: "/tmp/test-workspace",
    repo_status: null,
    github_installation_id: null,
    repo_url: null,
  };

  mockFrom.mockImplementation((table: string) => {
    if (table === "api_keys") {
      return createApiKeysMock(opts.apiKeyRows ?? [DEFAULT_API_KEY_ROW]);
    }
    if (table === "users") {
      // Supports both call shapes agent-runner now uses:
      //   - .select("workspace_path, ...").eq("id", userId).single()  (inline read)
      //   - .select("repo_url").eq("id", userId).maybeSingle()        (getCurrentRepoUrl)
      return {
        select: () => ({
          eq: () => ({
            single: () => ({ data: userData, error: null }),
            maybeSingle: () => ({ data: userData, error: null }),
          }),
        }),
      };
    }
    if (table === "conversations") {
      // Chainable .eq so updateConversationFor's
      //   .update(...).eq("id", ...).eq("user_id", ...)
      // composite-key pattern resolves; the terminal value still has
      // `{ error: null }` for awaiters of the chain.
      const conversationsUpdateChain: Record<string, unknown> = {
        error: null,
        eq: vi.fn(),
      };
      (conversationsUpdateChain.eq as ReturnType<typeof vi.fn>).mockReturnValue(
        conversationsUpdateChain,
      );
      return {
        update: vi.fn(() => conversationsUpdateChain),
      };
    }
    if (table === "messages") {
      return { insert: () => ({ error: null }) };
    }
    return {
      select: () => ({ eq: () => ({ single: () => ({ data: null, error: null }) }) }),
      update: () => ({ eq: () => ({ error: null }) }),
      insert: () => ({ error: null }),
    };
  });
}

/**
 * Build a mock for `query()` that yields a single result event and stops.
 */
export function createQueryMock(
  mockQuery: ReturnType<typeof vi.fn>,
  result: Record<string, unknown> = { type: "result", session_id: "sess-1" },
) {
  mockQuery.mockReturnValue({
    async *[Symbol.asyncIterator]() {
      yield result;
    },
    next: vi.fn(),
    return: vi.fn(),
    throw: vi.fn(),
  } as any);
}
