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
 * - getUserApiKey:  select().eq().eq().eq().limit().maybeSingle() -> { data, error }
 *                   (Phase 3 #4229 — byok-lease switched to maybeSingle so
 *                   `data === null && error === null` triggers
 *                   MissingByokKeyError vs ByokLeaseError{fetch_failed}).
 * - getUserServiceTokens: await select().eq().eq() -> { data, error }
 */
export function createApiKeysMock(
  rows: Record<string, unknown>[] = [DEFAULT_API_KEY_ROW],
) {
  const createChain = (): Record<string, unknown> => ({
    data: rows,
    error: null,
    eq: () => createChain(),
    limit: () => ({
      single: () => ({ data: rows[0] ?? null, error: null }),
      maybeSingle: () => ({ data: rows[0] ?? null, error: null }),
    }),
    then: (resolve: (v: unknown) => void) => resolve({ data: rows, error: null }),
  });
  return { select: () => createChain() };
}

/**
 * Configure a `tenant.rpc` mock so `resolve_workspace_installation_id`
 * resolves to the given installation id (ADR-044: agent-runner reads the
 * ACTIVE workspace's installation via the membership-scoped definer RPC, not
 * `users.github_installation_id`). All other RPC names resolve `{ data: null,
 * error: null }`. Pass `null` for the "App revoked / no installation" cases.
 */
export function configureInstallationRpc(
  mockRpc: ReturnType<typeof vi.fn>,
  installationId: number | null,
) {
  mockRpc.mockImplementation((fnName: string) =>
    fnName === "resolve_workspace_installation_id"
      ? Promise.resolve({ data: installationId, error: null })
      : Promise.resolve({ data: null, error: null }),
  );
}

/**
 * Build a `mockFrom` implementation covering the tables agent-runner touches.
 * Pass optional overrides per table name.
 *
 * When `opts.mockRpc` is provided it is configured (via
 * `configureInstallationRpc`) to resolve the active-workspace installation id
 * from `userData.github_installation_id` — keeping the per-test installation
 * value in ONE place even though the credential now comes from the RPC rather
 * than the `users` row.
 */
export function createSupabaseMockImpl(
  mockFrom: ReturnType<typeof vi.fn>,
  opts: {
    userData?: Record<string, unknown>;
    apiKeyRows?: Record<string, unknown>[];
    mockRpc?: ReturnType<typeof vi.fn>;
    /**
     * Optional spy wired onto `messages`.insert so tests can assert the
     * captured INSERT payload (e.g. that it carries `workspace_id`). When
     * omitted, a default no-op insert returning `{ error: null }` is used.
     */
    mockMessagesInsert?: ReturnType<typeof vi.fn>;
    /**
     * workspace_id returned from the `conversations` SELECT(s) that the
     * messages-workspace_id RLS fix added to `saveMessage` and
     * `sendUserMessage`. Default "ws-test"; per-path tests can override to
     * assert the INSERT payload carries the conversation's workspace_id.
     */
    conversationWorkspaceId?: string;
  } = {},
) {
  const userData = opts.userData ?? {
    workspace_path: "/tmp/test-workspace",
    repo_status: null,
    github_installation_id: null,
    repo_url: null,
  };
  const conversationWorkspaceId = opts.conversationWorkspaceId ?? "ws-test";

  if (opts.mockRpc) {
    configureInstallationRpc(
      opts.mockRpc,
      (userData.github_installation_id as number | null) ?? null,
    );
  }

  mockFrom.mockImplementation((table: string) => {
    if (table === "api_keys") {
      return createApiKeysMock(opts.apiKeyRows ?? [DEFAULT_API_KEY_ROW]);
    }
    if (table === "users") {
      // Supports both call shapes agent-runner now uses:
      //   - .select("workspace_path, ...").eq("id", userId).single()  (inline read)
      //   - .select("repo_url").eq("id", userId).maybeSingle()        (legacy)
      return {
        select: () => ({
          eq: () => ({
            single: () => ({ data: userData, error: null }),
            maybeSingle: () => ({ data: userData, error: null }),
          }),
        }),
      };
    }
    if (table === "workspaces") {
      // ADR-044 read-cutover: getCurrentRepoUrl reads workspaces.repo_url
      // for the active workspace. Mirror userData.repo_url so the existing
      // repo-scope expectations hold (active ws == solo ws in unit tests).
      return {
        select: () => ({
          eq: () => ({
            single: () => ({ data: { repo_url: userData.repo_url ?? null }, error: null }),
            maybeSingle: () => ({ data: { repo_url: userData.repo_url ?? null }, error: null }),
          }),
        }),
      };
    }
    if (table === "user_session_state") {
      // resolveCurrentWorkspaceId reads current_workspace_id; null → the
      // helper falls back to the solo workspace (= userId).
      return {
        select: () => ({
          eq: () => ({
            single: () => ({ data: { current_workspace_id: null }, error: null }),
            maybeSingle: () => ({ data: { current_workspace_id: null }, error: null }),
          }),
        }),
      };
    }
    if (table === "conversations") {
      // Chainable .eq so updateConversationFor's
      //   .update(...).eq("id", ...).eq("user_id", ...)[.select("id")]
      // composite-key pattern resolves. `.select("id")` returns a
      // single-row `data: [{ id }]` so the wrapper's `expectMatch: true`
      // path treats the update as matching.
      const conversationsUpdateChain: Record<string, unknown> = {
        error: null,
        eq: vi.fn(),
        select: vi.fn(() =>
          Promise.resolve({ data: [{ id: "mock" }], error: null }),
        ),
      };
      (conversationsUpdateChain.eq as ReturnType<typeof vi.fn>).mockReturnValue(
        conversationsUpdateChain,
      );
      // SELECT chain for the workspace_id reads added by the messages-
      // workspace_id RLS fix:
      //   saveMessage:      .select("workspace_id").eq("id", …).single()
      //   sendUserMessage:  .select("domain_leader, session_id, workspace_id")
      //                       .eq("id", …).eq("user_id", …).single()
      // `.eq` returns the same chain (composite-key) and `.single()`
      // terminates with a conversation row carrying workspace_id.
      const conversationsSelectChain: Record<string, unknown> = {
        eq: vi.fn(),
        single: vi.fn(() => ({
          data: {
            domain_leader: "cpo",
            session_id: null,
            workspace_id: conversationWorkspaceId,
          },
          error: null,
        })),
      };
      (conversationsSelectChain.eq as ReturnType<typeof vi.fn>).mockReturnValue(
        conversationsSelectChain,
      );
      return {
        update: vi.fn(() => conversationsUpdateChain),
        select: vi.fn(() => conversationsSelectChain),
      };
    }
    if (table === "messages") {
      return {
        insert: opts.mockMessagesInsert ?? (() => ({ error: null })),
        // `loadConversationHistory` reads prior messages via
        //   .select(...).eq("conversation_id", …).order("created_at", …)
        // which is awaited directly (thenable) → empty history by default.
        select: () => {
          const chain: Record<string, unknown> = {
            eq: () => chain,
            order: () => Promise.resolve({ data: [], error: null }),
            then: (resolve: (v: unknown) => void) =>
              resolve({ data: [], error: null }),
          };
          return chain;
        },
      };
    }
    return {
      select: () => ({
        eq: () => ({
          single: () => ({ data: null, error: null }),
          maybeSingle: () => ({ data: null, error: null }),
        }),
      }),
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
