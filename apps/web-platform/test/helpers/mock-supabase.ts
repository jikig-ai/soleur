import type { Mock } from "vitest";
import { vi } from "vitest";

/** Return type of mockQueryChain — provides type safety at call sites. */
export interface MockQueryChain {
  select: Mock;
  eq: Mock;
  neq: Mock;
  not: Mock;
  in: Mock;
  is: Mock;
  like: Mock;
  ilike: Mock;
  gt: Mock;
  gte: Mock;
  lt: Mock;
  lte: Mock;
  order: Mock;
  limit: Mock;
  range: Mock;
  insert: Mock;
  update: Mock;
  upsert: Mock;
  delete: Mock;
  single: Mock;
  maybeSingle: Mock;
  then: (onfulfilled?: (v: unknown) => unknown) => Promise<unknown>;
}

/**
 * Create a thenable query chain mock matching Supabase JS v2 query builder.
 *
 * All chaining methods (.select, .eq, .in, .order, etc.) return `this`.
 * The chain is PromiseLike — `await chain.select().eq()` resolves to { data, error }.
 * `.single()` returns a separate thenable resolving to { data, error }.
 *
 * **Usage with vi.hoisted():**
 * The helper exports a utility function, not a pre-built vi.mock() factory.
 * Test files must declare their own vi.hoisted() + vi.mock() blocks.
 *
 * ```ts
 * import { mockQueryChain } from "./helpers/mock-supabase";
 *
 * const { mockFrom } = vi.hoisted(() => ({ mockFrom: vi.fn() }));
 * vi.mock("@/lib/supabase/server", () => ({
 *   createServiceClient: vi.fn(() => ({ from: mockFrom })),
 * }));
 *
 * // In tests:
 * mockFrom.mockReturnValue(mockQueryChain({ id: "123" }));
 * ```
 *
 * **Caveat:** Some modules call createClient() at module scope (e.g., agent-runner.ts).
 * For those, mockFrom must be wired inside the vi.mock() factory, not in beforeEach.
 */
export function mockQueryChain<T>(
  data: T,
  error: { message: string } | null = null,
  count: number | null = null,
): MockQueryChain {
  const result = count === null ? { data, error } : { data, error, count };

  const chain = {} as MockQueryChain;

  const chainingMethods: (keyof MockQueryChain)[] = [
    "select",
    "eq",
    "neq",
    "not",
    "in",
    "is",
    "like",
    "ilike",
    "gt",
    "gte",
    "lt",
    "lte",
    "order",
    "limit",
    "range",
    "insert",
    "update",
    "upsert",
    "delete",
  ];

  for (const method of chainingMethods) {
    (chain[method] as Mock) = vi.fn(() => chain);
  }

  // PromiseLike: allows `await chain.select().eq()`
  chain.then = (onfulfilled?: (v: unknown) => unknown) =>
    Promise.resolve(result).then(onfulfilled);

  // Terminal: `.single()` returns a separate thenable
  chain.single = vi.fn(() => ({
    then: (onfulfilled?: (v: unknown) => unknown) =>
      Promise.resolve(result).then(onfulfilled),
  }));

  // Terminal: `.maybeSingle()` — same shape as single but returns
  // `{ data: null, error: null }` on no-rows (caller maps to its own
  // domain error). Phase 3 byok-lease (#4229) switched to maybeSingle
  // so api_keys absence triggers MissingByokKeyError rather than
  // ByokLeaseError{fetch_failed}.
  chain.maybeSingle = vi.fn(() => ({
    then: (onfulfilled?: (v: unknown) => unknown) =>
      Promise.resolve(result).then(onfulfilled),
  }));

  return chain;
}

/**
 * Single shared `.from()`-agnostic chain for KB owner-route tests (kb/content
 * GET+HEAD binary serving) where the route resolves the ACTIVE workspace via
 * `resolveActiveWorkspaceKbRoot` (ADR-044, #4543). The resolver reads
 * user_session_state → workspaces → users in one pass; returning the same
 * superset row for every table makes a `mockFrom.mockReturnValue(...)` mock
 * satisfy all three: `current_workspace_id: null` → solo (== caller, so the
 * organizations hop is skipped), `repo_status: "ready"` → connected,
 * `workspace_status: "ready"` → ready. Pass overrides to exercise the gates
 * (e.g. `{ workspace_status: "provisioning" }` → 503). `.maybeSingle()` is
 * required (the resolver uses it, not `.single()`).
 *
 * Per-table assertion coverage of the resolver itself lives in
 * `test/server/kb-active-workspace-scoping.test.ts` (strict per-table
 * dispatcher); these owner-route tests only need the resolution to succeed so
 * the file-serving path under test runs.
 */
export function kbSoloActiveWorkspaceChain(
  data: Record<string, unknown> = {},
  error: { message: string } | null = null,
) {
  const merged = {
    current_workspace_id: null,
    repo_status: "ready",
    workspace_status: "ready",
    ...data,
  };
  const term = {
    then: (onfulfilled?: (v: unknown) => unknown) =>
      Promise.resolve({ data: error ? null : merged, error }).then(onfulfilled),
  };
  const chain = {
    select: vi.fn(() => chain),
    eq: vi.fn(() => chain),
    single: vi.fn(() => term),
    maybeSingle: vi.fn(() => term),
  };
  return chain;
}

/**
 * Build a thenable for a Supabase `.rpc(name, args)` call.
 *
 * PostgREST RPC responses do NOT carry a `count` header; the body itself
 * is the payload (e.g. `[{ total: "0.042", n: 2 }]` for a `RETURNS TABLE`
 * function). Use this when mocking `service.rpc(...)` in place of the
 * chained `service.from(...).select(..., { count: "exact" })` pattern.
 *
 * ```ts
 * const { mockFrom, mockRpc } = vi.hoisted(() => ({
 *   mockFrom: vi.fn(),
 *   mockRpc: vi.fn(),
 * }));
 * vi.mock("@/lib/supabase/service", () => ({
 *   createServiceClient: vi.fn(() => ({ from: mockFrom, rpc: mockRpc })),
 * }));
 *
 * mockRpc.mockReturnValueOnce(mockRpcResult([{ total: "0.042", n: 2 }]));
 * ```
 */
export function mockRpcResult<T>(
  data: T,
  error: { message: string; code?: string } | null = null,
): { then: (onfulfilled?: (v: unknown) => unknown) => Promise<unknown> } {
  const resolved = error ? { data: null, error } : { data, error };
  return {
    then: (onfulfilled?: (v: unknown) => unknown) =>
      Promise.resolve(resolved).then(onfulfilled),
  };
}

// --- list_conversations_enriched RPC mock (migration 125) ---------------------
//
// The conversation-rail hook (`useConversations`) now fetches its list via ONE
// `supabase.rpc("list_conversations_enriched", {...})` call that returns each
// conversation PLUS four message snippets — replacing the old
// `.from("conversations")` + unbounded `.from("messages").in(ids)` fan-out.
//
// `makeEnrichedListRpc` is a faithful JS mirror of that SQL RPC for hook tests:
// it filters the fixture conversations by the RPC args (archive/status/domain,
// plus repo_url/workspace_id ONLY when a fixture actually carries that field —
// so lenient fixtures that omit scope columns are not accidentally emptied),
// sorts by last_active desc then created_at desc, applies the limit, and
// attaches the snippet fields computed the same way the LATERAL joins do
// (first user message, first assistant message, last message content + leader).

interface FixtureMessage {
  conversation_id: string;
  // Accepts `string` so tests whose message fixtures type role loosely can be
  // passed directly; only "user"/"assistant" are matched by the derivation.
  role: string;
  content: string;
  leader_id?: string | null;
  created_at?: string;
}

type EnrichedSnippets = {
  first_user_content: string | null;
  first_assistant_content: string | null;
  last_content: string | null;
  last_leader: string | null;
};

/** Attach first-user / first-assistant / last-content / last-leader snippets. */
export function enrichConversationFixtures<T extends { id: string }>(
  conversations: readonly T[],
  messages: FixtureMessage[],
): (T & EnrichedSnippets)[] {
  return conversations.map((c) => {
    const msgs = messages
      .filter((m) => m.conversation_id === c.id)
      .slice()
      .sort((a, b) => (a.created_at ?? "").localeCompare(b.created_at ?? ""));
    const firstUser = msgs.find((m) => m.role === "user");
    const firstAssistant = msgs.find((m) => m.role === "assistant");
    const last = msgs[msgs.length - 1];
    return {
      ...c,
      first_user_content: firstUser?.content ?? null,
      first_assistant_content: firstAssistant?.content ?? null,
      last_content: last?.content ?? null,
      last_leader: last?.leader_id ?? null,
    };
  });
}

/** A `vi.fn()` suitable for `client.rpc` that serves `list_conversations_enriched`. */
export function makeEnrichedListRpc<T extends { id: string }>(
  conversations: readonly T[],
  messages: FixtureMessage[] = [],
): Mock {
  return vi.fn((name: string, args: Record<string, unknown> = {}) => {
    if (name !== "list_conversations_enriched") {
      return Promise.resolve({
        data: null,
        error: { message: `unexpected rpc: ${name}` },
      });
    }
    const pRepo = args.p_repo_url as string | null | undefined;
    const pWs = args.p_workspace_id as string | null | undefined;
    const pArchive = (args.p_archive as string | undefined) ?? "active";
    const pStatus = args.p_status as string | null | undefined;
    const pDomain = args.p_domain as string | null | undefined;
    const pLimit = args.p_limit as number | undefined;

    let rows = conversations.filter((row) => {
      const c = row as Record<string, unknown>;
      // repo_url / workspace_id: only enforced when the fixture defines the
      // field (undefined = "test didn't scope"; mirrors the old lenient mocks).
      if (pRepo != null && c.repo_url !== undefined && (c.repo_url ?? null) !== pRepo) {
        return false;
      }
      if (pWs != null && c.workspace_id !== undefined && (c.workspace_id ?? null) !== pWs) {
        return false;
      }
      const archived = (c.archived_at ?? null) !== null;
      if (pArchive === "archived" ? !archived : archived) return false;
      if (pStatus != null && c.status !== pStatus) return false;
      if (pDomain != null) {
        if (pDomain === "general") {
          if ((c.domain_leader ?? null) !== null) return false;
        } else if (c.domain_leader !== pDomain) {
          return false;
        }
      }
      return true;
    });

    rows = rows.slice().sort((a, b) => {
      const ca = a as Record<string, unknown>;
      const cb = b as Record<string, unknown>;
      const byActive = String(cb.last_active ?? "").localeCompare(String(ca.last_active ?? ""));
      if (byActive !== 0) return byActive;
      return String(cb.created_at ?? "").localeCompare(String(ca.created_at ?? ""));
    });
    if (pLimit != null) rows = rows.slice(0, pLimit);

    return Promise.resolve({
      data: enrichConversationFixtures(rows, messages),
      error: null,
    });
  });
}
