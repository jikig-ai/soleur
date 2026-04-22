import type { Mock } from "vitest";

/**
 * Configure a set of already-hoisted `vi.fn()` mocks to reproduce the
 * PostgREST `.update().eq().in().select()` chain used by Stripe webhook
 * tests. Three webhook handler tests
 * (stripe-webhook-invoice.test.ts, stripe-webhook-plan-tier.test.ts,
 * webhook-subscription.test.ts) previously hand-rolled near-identical
 * thenable-with-chain mocks. A drift in `@supabase/supabase-js`'s client
 * shape would fail one and silently pass the others — per the test-design
 * review finding for PR #2617.
 *
 * Tests still `vi.hoisted(() => ({ mockUpdate: vi.fn(), ... }))` so the
 * mock references are available inside `vi.mock()` factories. Inside
 * `beforeEach`, call `configureSupabaseUpdateChain({ ... })` to set the
 * default chain behavior — one matched row, no error at any level.
 *
 * Shape reproduced:
 *
 *   supabase.from(table)
 *     .update(patch).eq(col, val).in(col, values).select("id")  // guarded, returns {data, error}
 *     .update(patch).eq(col, val)                               // legacy, returns {error}
 *     .update(patch).eq(col, val).in(col, values)               // awaitable intermediate
 *
 * Override individual mock return values in a specific test to assert zero
 * matched rows (`mockSelect.mockResolvedValue({data: [], error: null})`),
 * an error at `.eq()` (`mockEq.mockResolvedValue({error: ...})`), etc.
 */
export interface SupabaseUpdateChainMocks {
  mockUpdate: Mock;
  mockEq: Mock;
  mockIn: Mock;
  mockSelect: Mock;
}

export interface ConfigureOptions extends SupabaseUpdateChainMocks {
  /** ID(s) returned from the terminal `.select("id")` call. Default
   *  one row `{id: "user-123"}`. */
  matchedRowIds?: string[];
}

export function configureSupabaseUpdateChain(opts: ConfigureOptions): void {
  const { mockUpdate, mockEq, mockIn, mockSelect, matchedRowIds } = opts;
  const rows = (matchedRowIds ?? ["user-123"]).map((id) => ({ id }));

  mockSelect.mockResolvedValue({ data: rows, error: null });

  mockIn.mockImplementation(() => {
    const result: { data: { id: string }[]; error: null } = {
      data: rows,
      error: null,
    };
    return {
      select: mockSelect,
      then: (resolve: (value: typeof result) => unknown) => resolve(result),
    };
  });

  mockEq.mockImplementation(() => {
    const result: { error: null } = { error: null };
    return {
      in: mockIn,
      then: (resolve: (value: typeof result) => unknown) => resolve(result),
    };
  });

  mockUpdate.mockReturnValue({ eq: mockEq });
}
