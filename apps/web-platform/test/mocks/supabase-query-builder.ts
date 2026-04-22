import { vi } from "vitest";

/**
 * Shared Supabase query-builder mock.
 *
 * Covers the union shape of the three previously-duplicated inline helpers
 * (`command-center.test.tsx`, `start-fresh-onboarding.test.tsx`,
 * `update-status.test.tsx`). The builder is thenable so `await query` lands
 * on `{ data, error, count }` like the real PostgREST client, and also
 * supports the terminator methods (`single()`, `maybeSingle()`) and the
 * chain methods (`select`, `eq`, `in`, `is`, `not`, `order`, `limit`,
 * `update`) used across the test suite.
 *
 * Deliberate non-consumer: `ws-deferred-creation.test.ts` keeps its own
 * predicate-aware recursive `chain` because it inspects `.eq()` args
 * inside `start_session` — a different need from the query-terminator
 * shape this helper covers. See plan
 * `2026-04-22-refactor-drain-web-platform-code-review-2775-2776-2777-plan.md`
 * §Non-Goals for rationale.
 */

export interface BuildSupabaseQueryBuilderOpts {
  data?: unknown[];
  error?: { message: string } | null;
  singleRow?: unknown;
  count?: number;
}

export function buildSupabaseQueryBuilder(
  opts: BuildSupabaseQueryBuilderOpts = {},
) {
  const data = opts.data ?? [];
  const error = opts.error ?? null;
  const singleRow = opts.singleRow ?? null;
  const count = opts.count ?? data.length;

  // `result` is what the thenable resolves to (for `.eq().eq().then(...)`
  // style chains). `single` / `maybeSingle` each resolve with { data: <row>,
  // error: null } — matching the real PostgREST shape.
  const result = { data, error, count };

  type Builder = {
    select: ReturnType<typeof vi.fn>;
    eq: ReturnType<typeof vi.fn>;
    in: ReturnType<typeof vi.fn>;
    is: ReturnType<typeof vi.fn>;
    not: ReturnType<typeof vi.fn>;
    order: ReturnType<typeof vi.fn>;
    limit: ReturnType<typeof vi.fn>;
    single: ReturnType<typeof vi.fn>;
    maybeSingle: ReturnType<typeof vi.fn>;
    update: ReturnType<typeof vi.fn>;
    then: (onfulfilled: (value: unknown) => unknown) => Promise<unknown>;
  };

  const builder = {} as Builder;
  builder.select = vi.fn(() => builder);
  builder.eq = vi.fn(() => builder);
  builder.in = vi.fn(() => builder);
  builder.is = vi.fn(() => builder);
  builder.not = vi.fn(() => builder);
  builder.order = vi.fn(() => builder);
  builder.limit = vi.fn(() => builder);
  builder.single = vi.fn().mockResolvedValue({ data: singleRow, error: null });
  builder.maybeSingle = vi
    .fn()
    .mockResolvedValue({ data: singleRow, error: null });
  builder.update = vi.fn(() => builder);
  builder.then = (onfulfilled: (value: unknown) => unknown) =>
    Promise.resolve(result).then(onfulfilled);
  return builder;
}

export type SupabaseQueryBuilderMock = ReturnType<
  typeof buildSupabaseQueryBuilder
>;
