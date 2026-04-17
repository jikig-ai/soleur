// Table-name-dispatching Supabase from() mock for KB share tests.
// Closes issue #2468 (ordinal-position mocks are brittle — they break when
// the route reorders queries).
//
// Usage (inside a test file that has its own vi.hoisted + vi.mock for
// @/lib/supabase/server):
//
//   import { shareSupabaseFromMock } from "./helpers/share-mocks";
//
//   // in beforeEach:
//   mocks.mockServiceFrom.mockImplementation(
//     shareSupabaseFromMock({
//       users: { workspacePath: tmpWorkspace, workspaceStatus: "ready" },
//       kb_share_links: { shareRow: { ... }, insertSpy, updateSpy },
//     }),
//   );
//
// Tests declare intent by TABLE NAME, not by call index. Reordering
// queries inside the route handler is no longer a test-breaking change.

import type { Mock } from "vitest";
import { vi } from "vitest";

export interface UsersRowFixture {
  workspacePath?: string;
  workspaceStatus?: "ready" | "provisioning" | "error" | string | null;
  repoUrl?: string | null;
  githubInstallationId?: number | null;
  // Escape hatch for tests that need a different row shape.
  override?: Record<string, unknown>;
}

/**
 * Value OR a getter function — use the getter when a test file mutates the
 * row in a `let shareRow = ...` between beforeEach and the assertion. The
 * mock resolves the getter at CALL time, not at mock-build time, so tests
 * can set up the mock once in beforeEach and mutate the captured var in
 * each test body.
 */
type ValueOrGetter<T> = T | (() => T);

function resolve<T>(v: ValueOrGetter<T>): T {
  return typeof v === "function" ? (v as () => T)() : v;
}

export interface KbShareLinksFixture {
  /** Row returned by `.single()` after a token lookup or existing-share probe. */
  shareRow?: ValueOrGetter<Record<string, unknown> | null>;
  /** Error returned by `.single()` — defaults to null when shareRow is provided. */
  shareError?: ValueOrGetter<{ message: string } | null | undefined>;
  /** Spy used for `.insert(...)` calls. Default is a no-op returning { error: null }. */
  insertSpy?: Mock;
  /** Spy used for `.update(...)` calls. Default is a no-op returning { error: null }. */
  updateSpy?: Mock;
  /** Spy used for `.delete()` calls. Default is a no-op returning { error: null }. */
  deleteSpy?: Mock;
  /** Data returned by the query-chain awaitable (for list queries that do NOT call .single()). */
  listData?: unknown[];
}

export interface ShareSupabaseFromMockOpts {
  users?: UsersRowFixture | null;
  kb_share_links?: KbShareLinksFixture;
}

/**
 * Build an implementation function suitable for mockServiceFrom.mockImplementation(...).
 * Dispatches the returned chain based on the table name passed to from().
 *
 * Unknown tables throw so the test fails fast with a clear "Unmocked table: X"
 * instead of producing confusing downstream undefineds.
 */
export function shareSupabaseFromMock(
  opts: ShareSupabaseFromMockOpts = {},
): (table: string) => unknown {
  return function from(table: string): unknown {
    switch (table) {
      case "users":
        return usersChain(opts.users ?? null);
      case "kb_share_links":
        return kbShareLinksChain(opts.kb_share_links ?? {}, opts.users ?? null);
      default:
        throw new Error(
          `shareSupabaseFromMock: unmocked table "${table}" — configure it in the helper call`,
        );
    }
  };
}

function usersChain(row: UsersRowFixture | null) {
  const data =
    row === null
      ? null
      : {
          workspace_path: row.workspacePath,
          workspace_status: row.workspaceStatus ?? "ready",
          repo_url: row.repoUrl ?? null,
          github_installation_id: row.githubInstallationId ?? null,
          ...row.override,
        };
  return {
    select: vi.fn().mockReturnValue({
      eq: vi.fn().mockReturnValue({
        single: vi.fn().mockResolvedValue({
          data,
          error: data === null ? new Error("user not found") : null,
        }),
      }),
    }),
  };
}

function kbShareLinksChain(
  fixture: KbShareLinksFixture,
  usersFixture: UsersRowFixture | null,
) {
  const usersNested = usersFixture
    ? {
        workspace_path: usersFixture.workspacePath,
        workspace_status: usersFixture.workspaceStatus ?? "ready",
      }
    : null;
  // When a route uses PostgREST embedded resources (e.g.,
  // `.select("…, users!inner(…)")`) the nested row appears under
  // `shareRow.users`. Auto-attach the users fixture so tests don't have
  // to know which query shape the route uses. If the shareRow already
  // defines `users`, it wins — an explicit override beats the default.
  const attachUsers = <T extends Record<string, unknown> | null>(
    row: T,
  ): T => {
    if (!row || !usersNested) return row;
    if ("users" in row) return row;
    return { ...row, users: usersNested } as T;
  };
  const single = vi.fn().mockImplementation(async () => {
    const row = attachUsers(resolve(fixture.shareRow ?? null));
    const errOverride = fixture.shareError
      ? resolve(fixture.shareError)
      : undefined;
    return {
      data: row,
      error:
        errOverride !== undefined
          ? errOverride
          : row
            ? null
            : new Error("share not found"),
    };
  });
  const maybeSingle = vi.fn().mockImplementation(async () => ({
    data: attachUsers(resolve(fixture.shareRow ?? null)),
    error: fixture.shareError ? resolve(fixture.shareError) ?? null : null,
  }));
  // List query (order(...)) awaits to { data, error } directly.
  const orderThenable = (() => {
    const p: PromiseLike<{ data: unknown[]; error: null }> = {
      then: (onfulfilled) =>
        Promise.resolve({ data: fixture.listData ?? [], error: null }).then(
          onfulfilled,
        ),
    };
    return p;
  })();

  const eqChain: Record<string, unknown> = {
    single,
    maybeSingle,
    order: vi.fn().mockReturnValue(orderThenable),
  };
  eqChain.eq = vi.fn().mockReturnValue(eqChain);

  return {
    select: vi.fn().mockReturnValue(eqChain),
    insert: fixture.insertSpy ?? vi.fn().mockResolvedValue({ error: null }),
    update: vi.fn().mockReturnValue({
      eq: vi.fn().mockReturnValue(
        fixture.updateSpy ? fixture.updateSpy() : { error: null },
      ),
    }),
    delete: fixture.deleteSpy ?? vi.fn().mockResolvedValue({ error: null }),
  };
}
