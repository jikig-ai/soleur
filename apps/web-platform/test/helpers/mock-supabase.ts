import type { Mock } from "vitest";
import { vi } from "vitest";

/** Return type of mockQueryChain — provides type safety at call sites. */
export interface MockQueryChain {
  select: Mock;
  eq: Mock;
  neq: Mock;
  in: Mock;
  is: Mock;
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
    "in",
    "is",
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

  return chain;
}
