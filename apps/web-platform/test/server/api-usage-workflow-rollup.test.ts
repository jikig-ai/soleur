/**
 * Phase 2.3 (#1055) — `loadApiUsageForUser`'s per-workflow rollup arm.
 *
 * Scenarios T1-T3 and T6-T10 from the plan
 * (`knowledge-base/project/plans/20260908-094911-2026-09-07-feat-per-workflow-agent-cost-observability-plan.md (archived under knowledge-base/project/plans/archive/)`).
 *
 * SCOPE LIMIT, stated so nobody reads more into a green run than is there:
 * these tests mock the Supabase client, so they CANNOT prove `Σ buckets =
 * is_total` — that invariant is asserted SQL-side against dev in Phase 1.6
 * (AC1/AC2). What they prove is the LOADER's behaviour over fixtures: that it
 * reads the headline from the `is_total` row rather than re-deriving it, that
 * it never sums in JS, that `null` and `[]` stay distinguishable, and that the
 * `sum_user_mtd_cost` fallback is reached ONLY in the rejection arm and ONLY
 * sequentially.
 */

import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";
import { mockQueryChain, mockRpcResult } from "../helpers/mock-supabase";

const { mockFrom, mockRpc, mockTenantFrom, FakeRuntimeAuthError, mockReport } =
  vi.hoisted(() => ({
    mockFrom: vi.fn(),
    mockRpc: vi.fn(),
    mockTenantFrom: vi.fn(),
    FakeRuntimeAuthError: class FakeRuntimeAuthError extends Error {},
    mockReport: vi.fn(),
  }));

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: vi.fn(() => ({ from: mockFrom, rpc: mockRpc })),
}));

vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: vi.fn(async () => ({ from: mockTenantFrom })),
  RuntimeAuthError: FakeRuntimeAuthError,
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReport,
}));

import { loadApiUsageForUser, MAX_USAGE_ROWS } from "@/server/api-usage";
import { WORKFLOW_COPY } from "@/lib/messages/workflow-copy";

const VALID_UUID = "33333333-3333-3333-3333-333333333333";
const ROLLUP_FN = "sum_user_mtd_cost_by_workflow";
const TOTAL_FN = "sum_user_mtd_cost";

function probeOk() {
  return {
    select: () => ({
      eq: () => ({
        maybeSingle: () => Promise.resolve({ data: { id: "ok" }, error: null }),
      }),
    }),
  };
}

/** One `{bucket,total,n,is_total}` wire row. NUMERIC arrives as a string. */
function bucketRow(bucket: string, total: string, n: number) {
  return { bucket, total, n, is_total: false };
}
function totalRow(total: string, n: number) {
  return { bucket: null, total, n, is_total: true };
}

/** Route `mockRpc` by function name so call ORDER is asserted, not assumed. */
function routeRpc(
  handlers: Record<string, () => ReturnType<typeof mockRpcResult>>,
) {
  mockRpc.mockImplementation((name: string) => {
    const h = handlers[name];
    if (!h) throw new Error(`unexpected rpc: ${name}`);
    return h();
  });
}

function useList(rows: unknown[], error: { message: string } | null = null) {
  const chain = mockQueryChain(error ? null : rows, error);
  mockTenantFrom.mockImplementation((table: string) =>
    table === "users" ? probeOk() : chain,
  );
  return chain;
}

describe("loadApiUsageForUser — per-workflow rollup", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-04-17T12:00:00Z"));
    useList([]);
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  // ── T1 ────────────────────────────────────────────────────────────────
  test("T1: 3 workflows + 1 legacy — 4 bucket rows, headline from the is_total row", async () => {
    useList([]);
    routeRpc({
      [ROLLUP_FN]: () =>
        mockRpcResult([
          totalRow("10.000000", 10),
          bucketRow("one-shot", "5.000000", 4),
          bucketRow("plan", "3.000000", 3),
          bucketRow("work", "1.500000", 2),
          bucketRow("legacy", "0.500000", 1),
        ]),
    });

    const result = await loadApiUsageForUser(VALID_UUID);

    expect(result).not.toBeNull();
    expect(result!.byWorkflow).toHaveLength(4);
    expect(result!.byWorkflow!.map((r) => r.bucket)).toEqual([
      "one-shot",
      "plan",
      "work",
      "legacy",
    ]);
    // Headline is the is_total row — never rows[0], never a second query.
    expect(result!.mtdTotalUsd).toBe(10);
    expect(result!.mtdCount).toBe(10);
    // The is_total row is not itself a bucket.
    expect(result!.byWorkflow!.some((r) => r.bucket === null)).toBe(false);
    // Labels come from the editorial map, not the wire value.
    expect(result!.byWorkflow![0].label).toBe(WORKFLOW_COPY["one-shot"].label);
    expect(result!.byWorkflow![3].label).toBe(WORKFLOW_COPY.legacy.label);
    // Per-row average (2.4.6a) — division, not accumulation.
    expect(result!.byWorkflow![0].avgUsd).toBeCloseTo(1.25, 6);
    expect(result!.byWorkflow![0].count).toBe(4);
  });

  // ── AC8 ───────────────────────────────────────────────────────────────
  test("AC8: the happy path never calls sum_user_mtd_cost", async () => {
    useList([]);
    routeRpc({
      [ROLLUP_FN]: () =>
        mockRpcResult([totalRow("1.000000", 1), bucketRow("plan", "1.000000", 1)]),
    });

    await loadApiUsageForUser(VALID_UUID);

    expect(mockRpc).toHaveBeenCalledTimes(1);
    expect(mockRpc).toHaveBeenCalledWith(ROLLUP_FN, {
      uid: VALID_UUID,
      since: "2026-04-01T00:00:00.000Z",
    });
    expect(mockRpc).not.toHaveBeenCalledWith(TOTAL_FN, expect.anything());
  });

  // ── T2 ────────────────────────────────────────────────────────────────
  test("T2: more than MAX_USAGE_ROWS across two months — one window, list capped, rollup uncapped", async () => {
    const rows = Array.from({ length: MAX_USAGE_ROWS }, (_, i) => ({
      id: `c${i}`,
      domain_leader: "cto",
      created_at: "2026-04-10T12:00:00.000Z",
      input_tokens: 1,
      output_tokens: 1,
      total_cost_usd: "0.100000",
    }));
    const chain = useList(rows);
    // 120 in-month conversations; the prior-month ones are excluded by the
    // `since` predicate identically for buckets and total — the loader must
    // not re-derive either from the 50-row list.
    routeRpc({
      [ROLLUP_FN]: () =>
        mockRpcResult([
          totalRow("12.000000", 120),
          bucketRow("one-shot", "7.000000", 70),
          bucketRow("work", "5.000000", 50),
        ]),
    });

    const result = await loadApiUsageForUser(VALID_UUID);

    expect(chain.limit).toHaveBeenCalledWith(MAX_USAGE_ROWS);
    expect(result!.rows).toHaveLength(MAX_USAGE_ROWS);
    // Headline and buckets both come from the aggregate, so the 50-row cap
    // cannot leak into either.
    expect(result!.mtdCount).toBe(120);
    expect(result!.mtdTotalUsd).toBe(12);
    expect(
      result!.byWorkflow!.reduce((s, r) => s + r.count, 0),
    ).toBe(120);
    // Both calls carry the SAME month boundary.
    expect(mockRpc).toHaveBeenCalledWith(ROLLUP_FN, {
      uid: VALID_UUID,
      since: "2026-04-01T00:00:00.000Z",
    });
  });

  // ── T3 ────────────────────────────────────────────────────────────────
  test("T3: a $0.004200 bucket surfaces as 0.0042, not 0", async () => {
    useList([]);
    routeRpc({
      [ROLLUP_FN]: () =>
        mockRpcResult([
          totalRow("0.004200", 1),
          bucketRow("brainstorm", "0.004200", 1),
        ]),
    });

    const result = await loadApiUsageForUser(VALID_UUID);

    expect(result!.byWorkflow![0].totalUsd).toBe(0.0042);
    expect(result!.byWorkflow![0].avgUsd).toBe(0.0042);
    expect(result!.mtdTotalUsd).toBe(0.0042);
  });

  // ── T6 ────────────────────────────────────────────────────────────────
  test("T6: aggregate REJECTS, list succeeds — byWorkflow null, headline via the sequential fallback", async () => {
    useList([]);
    const boom = Object.assign(new Error("rollup exploded"), { code: "57014" });
    mockRpc.mockImplementation((name: string) => {
      if (name === ROLLUP_FN) return Promise.reject(boom);
      if (name === TOTAL_FN) return mockRpcResult([{ total: "4.270000", n: 9 }]);
      throw new Error(`unexpected rpc: ${name}`);
    });

    const result = await loadApiUsageForUser(VALID_UUID);

    // Degradation, not fail-whole: a rejecting promise must not throw past
    // the `.error` handling (this is why the batch is allSettled).
    expect(result).not.toBeNull();
    expect(result!.byWorkflow).toBeNull();
    expect(result!.mtdTotalUsd).toBe(4.27);
    expect(result!.mtdCount).toBe(9);

    // Sequential: the fallback is issued AFTER the rollup settles, so there
    // are exactly two calls and the second is the fallback.
    expect(mockRpc).toHaveBeenCalledTimes(2);
    expect(mockRpc).toHaveBeenNthCalledWith(1, ROLLUP_FN, expect.anything());
    expect(mockRpc).toHaveBeenNthCalledWith(2, TOTAL_FN, {
      uid: VALID_UUID,
      since: "2026-04-01T00:00:00.000Z",
    });

    // AC6: one report on the dedicated tag, never folded into the
    // dashboard-keyed `loadApiUsageForUser` op.
    const wfReports = mockReport.mock.calls.filter(
      (c) => (c[1] as { op?: string }).op === "mtd-by-workflow",
    );
    expect(wfReports).toHaveLength(1);
    expect(wfReports[0][1]).toMatchObject({ feature: "api-usage" });
  });

  test("T6b: aggregate returns an `.error` (not a rejection) — same degradation", async () => {
    useList([]);
    mockRpc.mockImplementation((name: string) => {
      if (name === ROLLUP_FN)
        return mockRpcResult(null, { code: "42501", message: "denied" });
      if (name === TOTAL_FN) return mockRpcResult([{ total: "1.000000", n: 1 }]);
      throw new Error(`unexpected rpc: ${name}`);
    });

    const result = await loadApiUsageForUser(VALID_UUID);

    expect(result).not.toBeNull();
    expect(result!.byWorkflow).toBeNull();
    expect(result!.mtdTotalUsd).toBe(1);
    expect(
      mockReport.mock.calls.filter(
        (c) => (c[1] as { op?: string }).op === "mtd-by-workflow",
      ),
    ).toHaveLength(1);
  });

  test("T6c: aggregate AND fallback both fail — whole-section null, today's exact behaviour", async () => {
    useList([]);
    mockRpc.mockImplementation((name: string) => {
      if (name === ROLLUP_FN)
        return mockRpcResult(null, { code: "42501", message: "denied" });
      if (name === TOTAL_FN)
        return mockRpcResult(null, { code: "XX000", message: "boom" });
      throw new Error(`unexpected rpc: ${name}`);
    });

    const result = await loadApiUsageForUser(VALID_UUID);
    expect(result).toBeNull();
  });

  // ── T7 ────────────────────────────────────────────────────────────────
  test("T7: zero buckets yields [] — distinct from null", async () => {
    useList([]);
    // ROLLUP over an empty input still emits the super-aggregate row.
    routeRpc({ [ROLLUP_FN]: () => mockRpcResult([totalRow("0", 0)]) });

    const result = await loadApiUsageForUser(VALID_UUID);

    expect(result!.byWorkflow).toEqual([]);
    expect(result!.byWorkflow).not.toBeNull();
    expect(result!.mtdTotalUsd).toBe(0);
    expect(result!.mtdCount).toBe(0);
  });

  // ── T9 ────────────────────────────────────────────────────────────────
  test("T9: NUMERIC strings coerced with Number(); `unrouted` renders under its label and no sentinel reaches TS", async () => {
    useList([]);
    routeRpc({
      [ROLLUP_FN]: () =>
        mockRpcResult([
          totalRow("2.500000", 5),
          bucketRow("unrouted", "1.500000", 3),
          bucketRow("review", "1.000000", 2),
        ]),
    });

    const result = await loadApiUsageForUser(VALID_UUID);

    const unrouted = result!.byWorkflow!.find((r) => r.bucket === "unrouted")!;
    expect(typeof unrouted.totalUsd).toBe("number");
    expect(typeof unrouted.count).toBe("number");
    expect(typeof unrouted.avgUsd).toBe("number");
    expect(unrouted.totalUsd).toBe(1.5);
    expect(unrouted.avgUsd).toBeCloseTo(0.5, 6);
    expect(unrouted.label).toBe("No workflow started");
    // The storage sentinel never crosses the boundary.
    const serialized = JSON.stringify(result!.byWorkflow);
    expect(serialized).not.toContain("__unrouted__");
    expect(serialized).not.toContain("__legacy__");
    // Headline is the aggregate's own total, never a JS sum of the parts.
    expect(result!.mtdTotalUsd).toBe(2.5);
  });

  // ── T10 ───────────────────────────────────────────────────────────────
  test("T10: 8 buckets sorted by total desc, tie-broken by bucket name asc", async () => {
    useList([]);
    // Deliberately shuffled, with a two-way tie at 1.000000 — PostgREST
    // issues `SELECT * FROM fn(...)` with no outer ORDER BY, so the TS sort
    // is the contract the UI actually gets.
    routeRpc({
      [ROLLUP_FN]: () =>
        mockRpcResult([
          bucketRow("work", "1.000000", 1),
          totalRow("20.000000", 30),
          bucketRow("legacy", "4.000000", 4),
          bucketRow("brainstorm", "1.000000", 1),
          bucketRow("one-shot", "9.000000", 9),
          bucketRow("unrouted", "0.500000", 1),
          bucketRow("plan", "2.000000", 2),
          bucketRow("review", "0.500000", 1),
          bucketRow("drain-labeled-backlog", "2.000000", 2),
        ]),
    });

    const result = await loadApiUsageForUser(VALID_UUID);

    expect(result!.byWorkflow!.map((r) => r.bucket)).toEqual([
      "one-shot",
      "legacy",
      "drain-labeled-backlog",
      "plan",
      "brainstorm",
      "work",
      "review",
      "unrouted",
    ]);
    expect(result!.byWorkflow).toHaveLength(8);

    // The headline must come from the `is_total` row even though it arrives at
    // index 1 here, NOT from `workflowData[0]` (which is the "work" bucket at
    // 1.000000). Without this pair of assertions the whole suite passes against
    // a loader that reads `rows[0]`: T1 pins the headline but seeds `is_total`
    // first, and this test seeds it second but only checked ordering -- so the
    // two fixtures between them left the sourcing unpinned. Mutation-verified:
    // swapping the `.find()` for `[0]` reds exactly here.
    expect(result!.mtdTotalUsd).toBe(20);
    expect(result!.mtdCount).toBe(30);

    // No raw slug survives into the rendered label column.
    for (const row of result!.byWorkflow!) {
      expect(row.label).not.toMatch(/[._-]/);
    }
  });

  // ── T8 ────────────────────────────────────────────────────────────────
  // --- REVIEW: fixture-shape gaps found by mutation --------------------------
  //
  // Each of these mutants passed the whole suite before. They are FIXTURE
  // gaps, not assertion gaps: the producer can emit these shapes and no
  // fixture instantiated them.

  test("an unmapped bucket renders its raw key AND mirrors to Sentry", async () => {
    // Mutant: deleting the entire `workflow-bucket-unmapped` block passed
    // 115/115. `workflow-copy.test.ts` covers the LABEL fallback but nothing
    // covered the Sentry mirror that `cq-silent-fallback-must-mirror-to-sentry`
    // requires. Reachable on a partial deploy: migration 032's CHECK enum can
    // widen ahead of the bundle (`drain-prs` is the named candidate).
    routeRpc({
      [ROLLUP_FN]: () =>
        mockRpcResult([
          totalRow("3.000000", 3),
          bucketRow("plan", "2.000000", 2),
          bucketRow("drain-prs", "1.000000", 1),
        ]),
    });

    const result = await loadApiUsageForUser(VALID_UUID);

    // The row is KEPT — dropping it would lose money under "Nothing is left out".
    expect(result!.byWorkflow!.map((r) => r.bucket)).toContain("drain-prs");
    expect(mockReport).toHaveBeenCalledWith(
      null,
      expect.objectContaining({
        op: "workflow-bucket-unmapped",
        extra: expect.objectContaining({ bucket: "drain-prs" }),
      }),
    );
  });

  test("a bucket with zero conversations yields avgUsd 0, never NaN", async () => {
    // Mutant: `count > 0 ? totalUsd / count : 0` -> `totalUsd / count` passed
    // 39/39. No fixture had n = 0, so NaN reached the UI untested.
    routeRpc({
      [ROLLUP_FN]: () =>
        mockRpcResult([
          totalRow("1.000000", 1),
          bucketRow("plan", "1.000000", 1),
          bucketRow("work", "0.000000", 0),
        ]),
    });

    const result = await loadApiUsageForUser(VALID_UUID);
    const work = result!.byWorkflow!.find((r) => r.bucket === "work")!;
    expect(work.avgUsd).toBe(0);
    expect(Number.isNaN(work.avgUsd)).toBe(false);
  });

  test("the headline comes from is_total even when the buckets do NOT sum to it", async () => {
    // Mutants M3b/M4/M5: re-deriving the headline in JS (summing buckets), or
    // finding the total row via `bucket === null` instead of `is_total`, or
    // falling back to `workflowData[0]`, ALL passed. Every fixture satisfied
    // Sigma(buckets) == is_total for MONEY, so nothing separated the two
    // signals. Here they deliberately disagree: a JS re-derivation yields 2.00
    // and the is_total row says 5.00.
    routeRpc({
      [ROLLUP_FN]: () =>
        mockRpcResult([
          bucketRow("plan", "1.000000", 1),
          totalRow("5.000000", 9),
          bucketRow("work", "1.000000", 1),
        ]),
    });

    const result = await loadApiUsageForUser(VALID_UUID);
    expect(result!.mtdTotalUsd).toBe(5);
    expect(result!.mtdCount).toBe(9);
  });

  test("an is_total row carrying a NON-null bucket is still the headline", async () => {
    // Pins that the discriminator is `is_total`, not `bucket === null`.
    routeRpc({
      [ROLLUP_FN]: () =>
        mockRpcResult([
          { bucket: "legacy", total: "7.000000", n: 4, is_total: true },
          bucketRow("plan", "1.000000", 1),
        ]),
    });

    const result = await loadApiUsageForUser(VALID_UUID);
    expect(result!.mtdTotalUsd).toBe(7);
    expect(result!.mtdCount).toBe(4);
    // ...and it is not ALSO rendered as a bucket.
    expect(result!.byWorkflow!.map((r) => r.bucket)).toEqual(["plan"]);
  });

  test("T8: conversations SELECT errors — whole-section null preserved", async () => {
    useList([], { message: "boom" });
    routeRpc({
      [ROLLUP_FN]: () =>
        mockRpcResult([totalRow("1.000000", 1), bucketRow("plan", "1.000000", 1)]),
    });

    const result = await loadApiUsageForUser(VALID_UUID);
    expect(result).toBeNull();
  });
});
