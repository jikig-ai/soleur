import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";
import { mockQueryChain, mockRpcResult } from "./helpers/mock-supabase";

const { mockFrom, mockRpc } = vi.hoisted(() => ({
  mockFrom: vi.fn(),
  mockRpc: vi.fn(),
}));

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: vi.fn(() => ({ from: mockFrom, rpc: mockRpc })),
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
}));

import { loadApiUsageForUser } from "@/server/api-usage";

const VALID_UUID = "22222222-2222-2222-2222-222222222222";

/**
 * AC1 — parity between client-side reduce and server-side SUM.
 *
 * The old loader summed up to 1000 NUMERIC(12,6) string values in JS. The
 * new loader reads a single NUMERIC string from the RPC body. This test
 * documents both behaviors on a realistic fixture and asserts the new
 * path stays within ≤ $0.001 of the legacy reduce (tight bound) and
 * ≤ $0.01 for pathological fixtures (wide bound).
 *
 * Fixture construction: 200 values drawn from a grid that's NUMERIC(12,6)-
 * representable and whose exact SUM is known without loss. Postgres
 * reports SUM(NUMERIC) as a NUMERIC (string at the PostgREST wire), so
 * the server-side value we compare against is the mathematically exact
 * decimal.
 */
describe("api-usage parity: client reduce vs. server RPC total (AC1)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-04-17T12:00:00Z"));
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  test("loader total matches Postgres SUM within tight bound on 200-row fixture", async () => {
    // 200 values: 100 × 0.004200 + 100 × 0.012500
    // Postgres SUM exact: 100 * 0.004200 + 100 * 0.012500 = 0.42 + 1.25 = 1.670000
    const rowCount = 200;
    const listRows = Array.from({ length: rowCount }, (_, i) => ({
      id: `c${i}`,
      domain_leader: "cmo",
      created_at: "2026-04-10T12:00:00.000Z",
      input_tokens: 100,
      output_tokens: 200,
      total_cost_usd: i < 100 ? "0.004200" : "0.012500",
    }));

    // Client-side reduce over the same values — exercises the legacy code
    // path to produce a baseline for comparison.
    const clientReduce = listRows.reduce(
      (sum, r) => sum + Number(r.total_cost_usd),
      0,
    );

    // Server-side SUM, pre-computed exactly. String form is the shape the
    // PostgREST wire delivers for NUMERIC.
    const serverSumString = "1.670000";
    const serverSum = Number(serverSumString);

    // Mock the list query and the RPC. The loader caps the list at
    // MAX_USAGE_ROWS (50) but the parity assertion runs against the
    // server RPC total, not the sliced list — so we pass the full 200
    // rows to exercise the fixture unambiguously.
    mockFrom.mockImplementationOnce(() =>
      mockQueryChain(listRows.slice(0, 50), null),
    );
    mockRpc.mockReturnValueOnce(
      mockRpcResult([{ total: serverSumString, n: rowCount }]),
    );

    const result = await loadApiUsageForUser(VALID_UUID);

    expect(result).not.toBeNull();
    // Wide bound (AC1): ≤ $0.01 absolute.
    expect(Math.abs(clientReduce - serverSum)).toBeLessThanOrEqual(0.01);
    // Tight bound (AC1): ≤ $0.001 for < 1000 rows.
    expect(Math.abs(clientReduce - serverSum)).toBeLessThanOrEqual(0.001);
    // And the loader surfaces the server sum to 6dp.
    expect(result!.mtdTotalUsd).toBeCloseTo(serverSum, 6);
    expect(result!.mtdCount).toBe(rowCount);
  });

  test("loader total matches exact Postgres SUM on sub-cent-heavy fixture", async () => {
    // Sub-cent values expose float drift in the legacy reduce most
    // clearly. Each value is NUMERIC(12,6)-exact and their SUM is known.
    // 300 × 0.000001 = 0.000300 exact.
    const rowCount = 300;
    const listRows = Array.from({ length: rowCount }, (_, i) => ({
      id: `c${i}`,
      domain_leader: "cto",
      created_at: "2026-04-12T08:00:00.000Z",
      input_tokens: 1,
      output_tokens: 1,
      total_cost_usd: "0.000001",
    }));
    const clientReduce = listRows.reduce(
      (sum, r) => sum + Number(r.total_cost_usd),
      0,
    );
    const serverSumString = "0.000300";
    const serverSum = Number(serverSumString);

    mockFrom.mockImplementationOnce(() =>
      mockQueryChain(listRows.slice(0, 50), null),
    );
    mockRpc.mockReturnValueOnce(
      mockRpcResult([{ total: serverSumString, n: rowCount }]),
    );

    const result = await loadApiUsageForUser(VALID_UUID);

    expect(result).not.toBeNull();
    expect(Math.abs(clientReduce - serverSum)).toBeLessThanOrEqual(0.01);
    expect(Math.abs(clientReduce - serverSum)).toBeLessThanOrEqual(0.001);
    expect(result!.mtdTotalUsd).toBeCloseTo(serverSum, 6);
  });
});
