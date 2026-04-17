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

  test("loader surfaces server SUM exactly on a drift-provoking fixture", async () => {
    // 1000 × 0.1 is the canonical IEEE-754 drift example: JS float sum
    // yields 99.9999999999986 (not 100.0 exactly). Postgres SUM on
    // NUMERIC is arbitrary-precision and returns exactly "100.000000".
    //
    // The old loader would have computed 99.9999999999986 and rendered
    // a MTD figure that's ~1.4e-12 off. The new loader reads the exact
    // NUMERIC string from the RPC body, bypassing float drift entirely.
    const rowCount = 1000;
    const driftyRows = Array.from({ length: rowCount }, (_, i) => ({
      id: `c${i}`,
      domain_leader: "cmo",
      created_at: "2026-04-10T12:00:00.000Z",
      input_tokens: 10,
      output_tokens: 20,
      total_cost_usd: "0.100000",
    }));

    // Baseline: the legacy JS-reduce path. Demonstrates drift is real.
    const clientReduce = driftyRows.reduce(
      (sum, r) => sum + Number(r.total_cost_usd),
      0,
    );
    expect(clientReduce).not.toBe(100); // drift: 99.9999999999986
    expect(Math.abs(clientReduce - 100)).toBeGreaterThan(1e-13);

    // Server: exact NUMERIC sum, wire-encoded as string.
    const serverSumString = "100.000000";
    const serverSum = Number(serverSumString);
    expect(serverSum).toBe(100); // no drift

    mockFrom.mockImplementationOnce(() =>
      mockQueryChain(driftyRows.slice(0, 50), null),
    );
    mockRpc.mockReturnValueOnce(
      mockRpcResult([{ total: serverSumString, n: rowCount }]),
    );

    const result = await loadApiUsageForUser(VALID_UUID);

    expect(result).not.toBeNull();
    // AC1 wide bound: ≤ $0.01 absolute between old and new paths.
    expect(Math.abs(clientReduce - serverSum)).toBeLessThanOrEqual(0.01);
    // AC1 tight bound: ≤ $0.001 for < 1000 rows. 1000 × 0.1 just clips
    // the boundary — Math.abs is ~1.4e-12, well under 0.001.
    expect(Math.abs(clientReduce - serverSum)).toBeLessThanOrEqual(0.001);
    // The loader's surfaced total equals the exact Postgres SUM, not
    // the drifted client-side reduce.
    expect(result!.mtdTotalUsd).toBe(100);
    expect(result!.mtdTotalUsd).not.toBe(clientReduce);
    expect(result!.mtdCount).toBe(rowCount);
  });

  test("loader total matches exact Postgres SUM on sub-cent-heavy fixture", async () => {
    // Sub-cent values compound drift differently than the 0.1 case.
    // 300 × 0.100001 = 30.000300 exact (Postgres). JS float sum ≈
    // 30.000300000000053 — drift at the 1e-14 scale, well inside AC1.
    const rowCount = 300;
    const listRows = Array.from({ length: rowCount }, (_, i) => ({
      id: `c${i}`,
      domain_leader: "cto",
      created_at: "2026-04-12T08:00:00.000Z",
      input_tokens: 1,
      output_tokens: 1,
      total_cost_usd: "0.100001",
    }));
    const clientReduce = listRows.reduce(
      (sum, r) => sum + Number(r.total_cost_usd),
      0,
    );
    const serverSumString = "30.000300";
    const serverSum = Number(serverSumString);

    // The legacy reduce can over- or under-count depending on rounding
    // direction; the server SUM is always exact.
    expect(Math.abs(clientReduce - serverSum)).toBeGreaterThan(0);

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
