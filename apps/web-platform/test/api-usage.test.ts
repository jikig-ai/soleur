import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";
import { mockQueryChain } from "./helpers/mock-supabase";

const { mockFrom } = vi.hoisted(() => ({ mockFrom: vi.fn() }));

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: vi.fn(() => ({ from: mockFrom })),
}));

import {
  loadApiUsageForUser,
  computeMonthStartIso,
  resolveDomainLabel,
  formatUsd,
  MAX_USAGE_ROWS,
} from "@/server/api-usage";

const VALID_UUID = "11111111-1111-1111-1111-111111111111";

describe("loadApiUsageForUser", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.useFakeTimers();
    // Fixed anchor avoids the month-rollover flake documented in the plan.
    vi.setSystemTime(new Date("2026-04-17T12:00:00Z"));
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  test("returns empty rows + 0 MTD when user has no conversations", async () => {
    const listChain = mockQueryChain([], null);
    const monthChain = mockQueryChain([], null, 0);
    mockFrom.mockImplementationOnce(() => listChain).mockImplementationOnce(() => monthChain);

    const result = await loadApiUsageForUser(VALID_UUID);

    expect(result).not.toBeNull();
    expect(result!.rows).toEqual([]);
    expect(result!.mtdTotalUsd).toBe(0);
    expect(result!.mtdCount).toBe(0);
  });

  test("returns rows + MTD total when current-month conversations exist", async () => {
    const now = new Date();
    const thisMonth = new Date(
      Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 15, 12, 0, 0),
    ).toISOString();
    const listChain = mockQueryChain(
      [
        {
          id: "c1",
          domain_leader: "cmo",
          created_at: thisMonth,
          input_tokens: 100,
          output_tokens: 200,
          total_cost_usd: "0.004200",
        },
        {
          id: "c2",
          domain_leader: "cto",
          created_at: thisMonth,
          input_tokens: 500,
          output_tokens: 700,
          total_cost_usd: "0.012500",
        },
      ],
      null,
    );
    const monthChain = mockQueryChain(
      [{ total_cost_usd: "0.004200" }, { total_cost_usd: "0.012500" }],
      null,
      2,
    );
    mockFrom.mockImplementationOnce(() => listChain).mockImplementationOnce(() => monthChain);

    const result = await loadApiUsageForUser(VALID_UUID);

    expect(result).not.toBeNull();
    expect(result!.rows).toHaveLength(2);
    expect(result!.rows[0].domainLabel).toBe("Marketing");
    expect(result!.rows[1].domainLabel).toBe("Engineering");
    expect(result!.rows[0].costUsd).toBe(0.0042);
    expect(result!.mtdTotalUsd).toBeCloseTo(0.0167, 6);
    expect(result!.mtdCount).toBe(2);
  });

  test("returns rows with MTD=0 when only prior-month conversations exist", async () => {
    const priorMonth = "2020-01-15T12:00:00.000Z";
    const listChain = mockQueryChain(
      [
        {
          id: "c1",
          domain_leader: "cmo",
          created_at: priorMonth,
          input_tokens: 100,
          output_tokens: 200,
          total_cost_usd: "0.004200",
        },
      ],
      null,
    );
    const monthChain = mockQueryChain([], null, 0);
    mockFrom.mockImplementationOnce(() => listChain).mockImplementationOnce(() => monthChain);

    const result = await loadApiUsageForUser(VALID_UUID);

    expect(result).not.toBeNull();
    expect(result!.rows).toHaveLength(1);
    expect(result!.mtdTotalUsd).toBe(0);
    expect(result!.mtdCount).toBe(0);
  });

  test("month query uses UTC boundary", async () => {
    const listChain = mockQueryChain([], null);
    const monthChain = mockQueryChain([], null, 0);
    mockFrom.mockImplementationOnce(() => listChain).mockImplementationOnce(() => monthChain);

    await loadApiUsageForUser(VALID_UUID);

    // This test's timezone-decision contract: month boundary is UTC midnight
    // of month-1. See plan §"Timezone Decision (Kieran P0)".
    expect(monthChain.gte).toHaveBeenCalledWith(
      "created_at",
      "2026-04-01T00:00:00.000Z",
    );
  });

  test("list query enforces order, limit, and cost > 0 filter (AC3 regression guard)", async () => {
    const listChain = mockQueryChain([], null);
    const monthChain = mockQueryChain([], null, 0);
    mockFrom.mockImplementationOnce(() => listChain).mockImplementationOnce(() => monthChain);

    await loadApiUsageForUser(VALID_UUID);

    expect(listChain.order).toHaveBeenCalledWith("created_at", {
      ascending: false,
    });
    expect(listChain.limit).toHaveBeenCalledWith(MAX_USAGE_ROWS);
    expect(listChain.gt).toHaveBeenCalledWith("total_cost_usd", 0);
    expect(listChain.eq).toHaveBeenCalledWith("user_id", VALID_UUID);
  });

  test("month-scope query enforces cost > 0 filter and defensive limit", async () => {
    const listChain = mockQueryChain([], null);
    const monthChain = mockQueryChain([], null, 0);
    mockFrom.mockImplementationOnce(() => listChain).mockImplementationOnce(() => monthChain);

    await loadApiUsageForUser(VALID_UUID);

    expect(monthChain.gt).toHaveBeenCalledWith("total_cost_usd", 0);
    expect(monthChain.eq).toHaveBeenCalledWith("user_id", VALID_UUID);
    // Defensive cap — see MTD_SCOPE_LIMIT in server/api-usage.ts.
    expect(monthChain.limit).toHaveBeenCalledWith(1000);
  });

  test("resolves domain labels: known → domain, null → '—', unknown → '—'", async () => {
    const thisMonth = new Date().toISOString();
    const listChain = mockQueryChain(
      [
        { id: "c1", domain_leader: "cfo", created_at: thisMonth, input_tokens: 0, output_tokens: 0, total_cost_usd: "0.001" },
        { id: "c2", domain_leader: null, created_at: thisMonth, input_tokens: 0, output_tokens: 0, total_cost_usd: "0.001" },
        { id: "c3", domain_leader: "legacy-removed-leader", created_at: thisMonth, input_tokens: 0, output_tokens: 0, total_cost_usd: "0.001" },
      ],
      null,
    );
    const monthChain = mockQueryChain([], null, 3);
    mockFrom.mockImplementationOnce(() => listChain).mockImplementationOnce(() => monthChain);

    const result = await loadApiUsageForUser(VALID_UUID);

    expect(result).not.toBeNull();
    expect(result!.rows[0].domainLabel).toBe("Finance");
    expect(result!.rows[1].domainLabel).toBe("—");
    expect(result!.rows[2].domainLabel).toBe("—");
  });

  test("returns null when list query errors", async () => {
    const listChain = mockQueryChain(null, { message: "boom" });
    const monthChain = mockQueryChain([], null, 0);
    mockFrom.mockImplementationOnce(() => listChain).mockImplementationOnce(() => monthChain);

    const result = await loadApiUsageForUser(VALID_UUID);
    expect(result).toBeNull();
  });

  test("returns null when month query errors", async () => {
    const listChain = mockQueryChain([], null);
    const monthChain = mockQueryChain(null, { message: "boom" }, null);
    mockFrom.mockImplementationOnce(() => listChain).mockImplementationOnce(() => monthChain);

    const result = await loadApiUsageForUser(VALID_UUID);
    expect(result).toBeNull();
  });

  test("returns null when both queries error", async () => {
    const listChain = mockQueryChain(null, { message: "boom" });
    const monthChain = mockQueryChain(null, { message: "boom" }, null);
    mockFrom.mockImplementationOnce(() => listChain).mockImplementationOnce(() => monthChain);

    const result = await loadApiUsageForUser(VALID_UUID);
    expect(result).toBeNull();
  });

  test("coerces PostgREST NUMERIC strings to numbers", async () => {
    const thisMonth = new Date().toISOString();
    const listChain = mockQueryChain(
      [
        {
          id: "c1",
          domain_leader: "cmo",
          created_at: thisMonth,
          input_tokens: "1234", // should be coerced
          output_tokens: "5678",
          total_cost_usd: "0.123456",
        },
      ],
      null,
    );
    const monthChain = mockQueryChain([{ total_cost_usd: "0.123456" }], null, 1);
    mockFrom.mockImplementationOnce(() => listChain).mockImplementationOnce(() => monthChain);

    const result = await loadApiUsageForUser(VALID_UUID);

    expect(result).not.toBeNull();
    expect(typeof result!.rows[0].inputTokens).toBe("number");
    expect(typeof result!.rows[0].outputTokens).toBe("number");
    expect(typeof result!.rows[0].costUsd).toBe("number");
    expect(result!.rows[0].costUsd).toBeCloseTo(0.123456, 6);
  });

  test("throws on non-UUID input before hitting Supabase", async () => {
    await expect(loadApiUsageForUser("not-a-uuid")).rejects.toThrow();
    expect(mockFrom).not.toHaveBeenCalled();
  });

  test("throws on empty string input", async () => {
    await expect(loadApiUsageForUser("")).rejects.toThrow();
    expect(mockFrom).not.toHaveBeenCalled();
  });
});

describe("computeMonthStartIso", () => {
  test("2026-04-01T04:00:00Z → April (UTC) — already in April boundary", () => {
    const iso = computeMonthStartIso(new Date("2026-04-01T04:00:00Z"));
    expect(iso).toBe("2026-04-01T00:00:00.000Z");
  });

  test("2026-03-31T23:30:00Z → March (still March in UTC)", () => {
    const iso = computeMonthStartIso(new Date("2026-03-31T23:30:00Z"));
    expect(iso).toBe("2026-03-01T00:00:00.000Z");
  });

  test("2026-04-17T12:00:00Z → April", () => {
    const iso = computeMonthStartIso(new Date("2026-04-17T12:00:00Z"));
    expect(iso).toBe("2026-04-01T00:00:00.000Z");
  });
});

describe("resolveDomainLabel", () => {
  test("known leader id → department name", () => {
    expect(resolveDomainLabel("cmo")).toBe("Marketing");
    expect(resolveDomainLabel("cto")).toBe("Engineering");
  });

  test("null → '—'", () => {
    expect(resolveDomainLabel(null)).toBe("—");
  });

  test("undefined → '—'", () => {
    expect(resolveDomainLabel(undefined)).toBe("—");
  });

  test("unknown legacy id → '—'", () => {
    expect(resolveDomainLabel("legacy-removed-leader")).toBe("—");
  });

  test("empty string → '—'", () => {
    expect(resolveDomainLabel("")).toBe("—");
  });
});

describe("formatUsd", () => {
  test("0 → $0.00", () => {
    expect(formatUsd(0)).toBe("$0.00");
  });

  test("sub-cent uses 4dp", () => {
    expect(formatUsd(0.0043)).toBe("$0.0043");
    expect(formatUsd(0.0001)).toBe("$0.0001");
  });

  test("exactly 0.01 uses 2dp", () => {
    expect(formatUsd(0.01)).toBe("$0.01");
  });

  test("non-sub-cent uses 2dp", () => {
    expect(formatUsd(4.27)).toBe("$4.27");
    expect(formatUsd(12.5)).toBe("$12.50");
  });

  test("negative clamps to $0.00", () => {
    expect(formatUsd(-1)).toBe("$0.00");
  });

  test("NaN clamps to $0.00", () => {
    expect(formatUsd(NaN)).toBe("$0.00");
  });
});

// relativeTime itself is tested in @/lib/relative-time's own suite; api-usage
// re-exports it so consumers have a single import site, but we don't
// double-cover the helper's unit behavior here.
