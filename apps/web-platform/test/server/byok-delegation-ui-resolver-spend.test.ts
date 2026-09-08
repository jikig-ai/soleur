import { describe, it, expect, vi, beforeEach } from "vitest";
import { readFileSync, readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { join } from "node:path";

// #7829 PR-1 — the Funded pane's spend figures.
//
// `byok-delegation-ui-resolver.ts` selected `cost_cents` from
// `public.audit_byok_use`. That column has never existed: mig
// `037_audit_byok_use.sql` declares `token_count int NOT NULL` and
// `unit_cost_cents int NOT NULL` (see its `CREATE TABLE IF NOT EXISTS
// public.audit_byok_use` block), and the only later additions are
// `workspace_id` (059), `delegation_id` + `attribution_shift_reason` (064).
// PostgREST answered 42703 (undefined_column) on every read, the resolver
// never bound the `error`, and `todaySpentCents` / `mtdSpentCents` /
// `capRemainingCents` rendered 0 / 0 / full-cap for every grantor, forever.
//
// These tests are BEHAVIOURAL, not a source grep:
//   1. they capture the literal select-string the resolver hands PostgREST and
//      check every name in it against the column set PARSED OUT OF THE
//      MIGRATIONS (so the assertion tracks the schema, not a copy of it);
//   2. they feed the resolver real `token_count` / `unit_cost_cents` rows and
//      assert the totals equal the cap RPC's own window expression
//      `SUM(au.token_count * au.unit_cost_cents)`
//      (`084_byok_delegation_withdrawals.sql`, `INTO v_hourly_spent` /
//      `INTO v_daily_spent`);
//   3. they drive a mocked PostgREST 42703 and assert the resolver reports a
//      DEGRADED figure (null) rather than a confident `$0.00`, and mirrors the
//      error to Sentry so `pg_code` can discriminate 42703 from 42501.

const { mockFrom, mockIsByokDelegationsEnabled, mockReportSilentFallback } = vi.hoisted(
  () => ({
    mockFrom: vi.fn(),
    mockIsByokDelegationsEnabled: vi.fn(),
    mockReportSilentFallback: vi.fn(),
  }),
);

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: vi.fn(() => ({ from: mockFrom })),
}));

vi.mock("@/lib/feature-flags/server", () => ({
  isByokDelegationsEnabled: mockIsByokDelegationsEnabled,
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
}));

import {
  resolveGrantorDelegations,
  resolveGranteeDelegation,
  resolveGranteeAcceptanceStatus,
} from "@/server/byok-delegation-ui-resolver";
import type { Identity } from "@/lib/feature-flags/server";

// ─── The declared column set, parsed from the migrations ─────────────────────

const MIGRATIONS_DIR = fileURLToPath(new URL("../../supabase/migrations/", import.meta.url));

/**
 * Every column `public.audit_byok_use` actually has: the `CREATE TABLE` block in
 * 037 plus every forward `ALTER TABLE public.audit_byok_use … ADD COLUMN`.
 * `.down.sql` files are skipped — the runner never executes them
 * (`run-migrations.sh` `*.down.sql) continue ;;`), so a column they drop is
 * still live.
 */
function declaredAuditColumns(): Set<string> {
  const cols = new Set<string>();

  const create = readFileSync(join(MIGRATIONS_DIR, "037_audit_byok_use.sql"), "utf8");
  const block = create.match(
    /CREATE TABLE IF NOT EXISTS public\.audit_byok_use\s*\(([\s\S]*?)\n\);/,
  );
  if (!block) throw new Error("037: audit_byok_use CREATE TABLE block not found");
  for (const line of block[1].split("\n")) {
    const name = line.trim().match(/^([a-z_][a-z0-9_]*)\s+\S/);
    if (name) cols.add(name[1]);
  }

  for (const file of readdirSync(MIGRATIONS_DIR).sort()) {
    if (!file.endsWith(".sql") || file.endsWith(".down.sql")) continue;
    const sql = readFileSync(join(MIGRATIONS_DIR, file), "utf8");
    // Each `ALTER TABLE public.audit_byok_use … ;` statement, then the columns
    // it adds. Scoped per-statement so an ALTER on another table cannot leak in.
    for (const stmt of sql.matchAll(/ALTER TABLE public\.audit_byok_use\b[\s\S]*?;/g)) {
      for (const add of stmt[0].matchAll(/ADD COLUMN\s+(?:IF NOT EXISTS\s+)?([a-z_][a-z0-9_]*)/g)) {
        cols.add(add[1]);
      }
    }
  }
  return cols;
}

// Non-vacuity floor for the parser: if it silently returns garbage the
// select-string assertions below become meaningless.
describe("audit_byok_use column set (parsed from the migrations)", () => {
  it("contains the real cost columns and does NOT contain cost_cents", () => {
    const cols = declaredAuditColumns();
    for (const c of [
      "id",
      "invocation_id",
      "founder_id",
      "ts",
      "token_count",
      "unit_cost_cents",
      "workspace_id",
      "delegation_id",
      "attribution_shift_reason",
    ]) {
      expect(cols, `expected declared column ${c}`).toContain(c);
    }
    expect(cols).not.toContain("cost_cents");
  });
});

// ─── Chainable PostgREST stub ────────────────────────────────────────────────

interface Result {
  data: unknown;
  error: unknown;
}

type Chain = Record<string, ReturnType<typeof vi.fn>> & {
  then: (onFulfilled: (v: Result) => unknown, onRejected?: (e: unknown) => unknown) => Promise<unknown>;
};

/**
 * A thenable query builder: every filter method returns `this`, and awaiting the
 * builder (which is what the resolver does on the list reads) resolves to
 * `result`. `.select` keeps its call history so a test can read back the literal
 * column list the resolver asked PostgREST for.
 */
function makeChain(result: Result): Chain {
  const obj = {} as Chain;
  for (const m of ["select", "eq", "in", "is", "gte", "order", "limit", "range"]) {
    (obj as Record<string, unknown>)[m] = vi.fn(() => obj);
  }
  (obj as Record<string, unknown>).maybeSingle = vi.fn(async () => result);
  (obj as Record<string, unknown>).single = vi.fn(async () => result);
  obj.then = (onFulfilled, onRejected) =>
    Promise.resolve(result).then(onFulfilled, onRejected);
  return obj;
}

const OK = (data: unknown): Result => ({ data, error: null });

/** A PostgREST error in the shape `sqlStateFromError` reads (`{ code, … }`). */
const PGRST = (code: string, message: string): Result => ({
  data: null,
  error: { code, message, details: null, hint: null },
});

const UNDEFINED_COLUMN = () =>
  PGRST("42703", 'column audit_byok_use.cost_cents does not exist');

/** Install a per-table script and hand back the chains for inspection. */
function primeTables(byTable: Record<string, Result>): Record<string, Chain> {
  const chains: Record<string, Chain> = {};
  for (const [table, result] of Object.entries(byTable)) {
    chains[table] = makeChain(result);
  }
  mockFrom.mockImplementation((table: string) => {
    const c = chains[table];
    if (!c) throw new Error(`unexpected from(${table})`);
    return c;
  });
  return chains;
}

const IDENTITY: Identity = { userId: "grantor-1", role: "prd", orgId: "org-1" };

const NOW = new Date();
const isoAgo = (hours: number) =>
  new Date(NOW.getTime() - hours * 60 * 60 * 1000).toISOString();

// Two delegations, one grantee each.
const DELEGATIONS = [
  {
    id: "d1",
    grantee_user_id: "grantee-1",
    daily_cap_cents: 50_000,
    hourly_cap_cents: 10_000,
    created_at: isoAgo(72),
    revoked_at: null,
  },
  {
    id: "d2",
    grantee_user_id: "grantee-2",
    daily_cap_cents: 50_000,
    hourly_cap_cents: 10_000,
    created_at: isoAgo(72),
    revoked_at: null,
  },
];

const USERS = [
  { id: "grantee-1", email: "ada@example.com" },
  { id: "grantee-2", email: "bob@example.com" },
];

// Production-shaped rows (`cost-writer.ts` writes a whole-turn cost into
// `unit_cost_cents`), plus one older-than-24h row so the today/MTD split is
// actually exercised.
const AUDIT_ROWS = [
  { delegation_id: "d1", token_count: 8_000, unit_cost_cents: 3, ts: isoAgo(1) },
  { delegation_id: "d1", token_count: 10, unit_cost_cents: 10, ts: isoAgo(48) },
  { delegation_id: "d2", token_count: 5, unit_cost_cents: 4, ts: isoAgo(2) },
];

// The cap RPC's own arithmetic (084, `INTO v_daily_spent`).
// Mirrors migration 137's delegation windows EXACTLY. 137 corrected them to
// SUM(au.unit_cost_cents) — unit_cost_cents holds the whole turn's cost, so the
// old product was cents-times-tokens and tripped any real cap on the first
// turn. The pane's figure and the cap that refuses the turn must not disagree,
// so if one moves the other moves with it (ADR-208 Decision 3).
const rpcWindowSum = (rows: typeof AUDIT_ROWS) =>
  rows.reduce((acc, r) => acc + r.unit_cost_cents, 0);

beforeEach(() => {
  vi.clearAllMocks();
  mockIsByokDelegationsEnabled.mockResolvedValue(true);
});

describe("resolveGrantorDelegations — audit_byok_use spend", () => {
  it("selects only columns audit_byok_use actually declares", async () => {
    const chains = primeTables({
      byok_delegations: OK(DELEGATIONS),
      users: OK(USERS),
      audit_byok_use: OK(AUDIT_ROWS),
    });

    await resolveGrantorDelegations("grantor-1", "ws-1", "org-1", IDENTITY);

    const selectArg = chains.audit_byok_use.select.mock.calls[0][0] as string;
    const declared = declaredAuditColumns();
    const asked = selectArg.split(",").map((s) => s.trim().split(":").pop()!.trim());
    expect(asked.length).toBeGreaterThan(0);
    for (const col of asked) {
      expect(declared, `select("${selectArg}") names undeclared column "${col}"`).toContain(col);
    }
    // And it must ask for the two the cap RPC multiplies.
    expect(asked).toContain("token_count");
    expect(asked).toContain("unit_cost_cents");
  });

  it("sums unit_cost_cents — migration 137's corrected window expression", async () => {
    primeTables({
      byok_delegations: OK(DELEGATIONS),
      users: OK(USERS),
      audit_byok_use: OK(AUDIT_ROWS),
    });

    const rows = await resolveGrantorDelegations("grantor-1", "ws-1", "org-1", IDENTITY);
    const d1 = rows.find((r) => r.id === "d1")!;
    const d2 = rows.find((r) => r.id === "d2")!;

    const d1Today = rpcWindowSum([AUDIT_ROWS[0]]); 
    const d1Mtd = rpcWindowSum([AUDIT_ROWS[0], AUDIT_ROWS[1]]); 
    const d2Today = rpcWindowSum([AUDIT_ROWS[2]]); 

    expect(d1.todaySpentCents).toBe(d1Today);
    expect(d1.mtdSpentCents).toBe(d1Mtd);
    expect(d1.capRemainingCents).toBe(50_000 - d1Today);
    expect(d2.todaySpentCents).toBe(d2Today);
    expect(d2.mtdSpentCents).toBe(d2Today);
    expect(d2.capRemainingCents).toBe(50_000 - d2Today);
  });

  it("42703 on the spend read → degraded (null), never a confident $0.00", async () => {
    primeTables({
      byok_delegations: OK(DELEGATIONS),
      users: OK(USERS),
      audit_byok_use: UNDEFINED_COLUMN(),
    });

    const rows = await resolveGrantorDelegations("grantor-1", "ws-1", "org-1", IDENTITY);
    expect(rows).toHaveLength(2);
    for (const r of rows) {
      expect(r.todaySpentCents).toBeNull();
      expect(r.mtdSpentCents).toBeNull();
      expect(r.capRemainingCents).toBeNull();
    }

    const call = mockReportSilentFallback.mock.calls.find(
      (c) => (c[1] as { op?: string }).op === "resolveGrantorDelegations.audit-spend",
    );
    expect(call, "audit-spend read was not mirrored to Sentry").toBeDefined();
    expect((call![0] as { code: string }).code).toBe("42703");
    expect((call![1] as { feature: string }).feature).toBe("byok-delegations");
  });

  it("42501 on the spend read is mirrored with its own SQLSTATE (discriminable)", async () => {
    primeTables({
      byok_delegations: OK(DELEGATIONS),
      users: OK(USERS),
      audit_byok_use: PGRST("42501", "permission denied for table audit_byok_use"),
    });

    const rows = await resolveGrantorDelegations("grantor-1", "ws-1", "org-1", IDENTITY);
    expect(rows[0].todaySpentCents).toBeNull();
    const call = mockReportSilentFallback.mock.calls.find(
      (c) => (c[1] as { op?: string }).op === "resolveGrantorDelegations.audit-spend",
    );
    expect((call![0] as { code: string }).code).toBe("42501");
  });

  it("mirrors a failed byok_delegations read instead of returning [] silently", async () => {
    primeTables({
      byok_delegations: PGRST("42501", "permission denied for table byok_delegations"),
      users: OK(USERS),
      audit_byok_use: OK([]),
    });

    const rows = await resolveGrantorDelegations("grantor-1", "ws-1", "org-1", IDENTITY);
    expect(rows).toEqual([]);
    const ops = mockReportSilentFallback.mock.calls.map((c) => (c[1] as { op?: string }).op);
    expect(ops).toContain("resolveGrantorDelegations.delegations");
  });

  it("mirrors a failed grantee-name read (display falls back to Unknown)", async () => {
    primeTables({
      byok_delegations: OK(DELEGATIONS),
      users: PGRST("42501", "permission denied for table users"),
      audit_byok_use: OK(AUDIT_ROWS),
    });

    const rows = await resolveGrantorDelegations("grantor-1", "ws-1", "org-1", IDENTITY);
    expect(rows[0].granteeDisplayName).toBe("Unknown");
    const ops = mockReportSilentFallback.mock.calls.map((c) => (c[1] as { op?: string }).op);
    expect(ops).toContain("resolveGrantorDelegations.grantee-users");
  });
});

  it("SCOPES the audit read to this grantor's own delegations and to the month", async () => {
    // The chain mock resolves to the canned result whatever the filters are, so
    // nothing here fails on its own — these assertions ARE the coverage.
    // Without them, deleting `.in("delegation_id", ...)` stays green while the
    // query pulls every tenant's audit rows into memory (the per-delegation map
    // lookups keep every other assertion passing), and deleting `.gte("ts", ...)`
    // silently turns MTD into all-time on an unbounded read.
    const chains = primeTables({
      byok_delegations: OK(DELEGATIONS),
      users: OK(USERS),
      audit_byok_use: OK(AUDIT_ROWS),
    });

    await resolveGrantorDelegations("grantor-1", "ws-1", "org-1", IDENTITY);

    const audit = chains.audit_byok_use;
    expect(audit.in, "tenant-isolation filter is applied").toHaveBeenCalledWith(
      "delegation_id",
      expect.arrayContaining(["d1", "d2"]),
    );
    expect(audit.gte, "month window is applied").toHaveBeenCalledWith("ts", expect.any(String));
  });

describe("resolveGranteeDelegation — audit_byok_use spend", () => {
  const GRANTEE_DELEGATION = {
    id: "d1",
    grantor_user_id: "grantor-1",
    daily_cap_cents: 50_000,
    hourly_cap_cents: 10_000,
  };

  it("selects only columns audit_byok_use actually declares", async () => {
    const chains = primeTables({
      byok_delegations: OK(GRANTEE_DELEGATION),
      users: OK({ email: "owner@example.com" }),
      audit_byok_use: OK([AUDIT_ROWS[0]]),
    });

    await resolveGranteeDelegation("grantee-1", "ws-1", "org-1", IDENTITY);

    const selectArg = chains.audit_byok_use.select.mock.calls[0][0] as string;
    const declared = declaredAuditColumns();
    const asked = selectArg.split(",").map((s) => s.trim().split(":").pop()!.trim());
    for (const col of asked) {
      expect(declared, `select("${selectArg}") names undeclared column "${col}"`).toContain(col);
    }
    expect(asked).toContain("token_count");
    expect(asked).toContain("unit_cost_cents");
  });

  it("sums unit_cost_cents over the rolling 24h window", async () => {
    primeTables({
      byok_delegations: OK(GRANTEE_DELEGATION),
      users: OK({ email: "owner@example.com" }),
      audit_byok_use: OK([AUDIT_ROWS[0]]),
    });

    const d = await resolveGranteeDelegation("grantee-1", "ws-1", "org-1", IDENTITY);
    expect(d!.todaySpentCents).toBe(rpcWindowSum([AUDIT_ROWS[0]]));
    expect(d!.capRemainingCents).toBe(50_000 - rpcWindowSum([AUDIT_ROWS[0]]));
  });

  it("42703 on the spend read → degraded (null) + Sentry mirror", async () => {
    primeTables({
      byok_delegations: OK(GRANTEE_DELEGATION),
      users: OK({ email: "owner@example.com" }),
      audit_byok_use: UNDEFINED_COLUMN(),
    });

    const d = await resolveGranteeDelegation("grantee-1", "ws-1", "org-1", IDENTITY);
    expect(d!.todaySpentCents).toBeNull();
    expect(d!.capRemainingCents).toBeNull();

    const call = mockReportSilentFallback.mock.calls.find(
      (c) => (c[1] as { op?: string }).op === "resolveGranteeDelegation.audit-spend",
    );
    expect(call, "grantee audit-spend read was not mirrored").toBeDefined();
    expect((call![0] as { code: string }).code).toBe("42703");
  });

  it("mirrors a failed delegation read and a failed grantor-name read", async () => {
    primeTables({
      byok_delegations: PGRST("42501", "permission denied for table byok_delegations"),
      users: OK({ email: "owner@example.com" }),
      audit_byok_use: OK([]),
    });
    expect(await resolveGranteeDelegation("grantee-1", "ws-1", "org-1", IDENTITY)).toBeNull();
    expect(
      mockReportSilentFallback.mock.calls.map((c) => (c[1] as { op?: string }).op),
    ).toContain("resolveGranteeDelegation.delegation");

    vi.clearAllMocks();
    mockIsByokDelegationsEnabled.mockResolvedValue(true);
    primeTables({
      byok_delegations: OK(GRANTEE_DELEGATION),
      users: PGRST("42501", "permission denied for table users"),
      audit_byok_use: OK([]),
    });
    const d = await resolveGranteeDelegation("grantee-1", "ws-1", "org-1", IDENTITY);
    expect(d!.grantorDisplayName).toBe("Unknown");
    expect(
      mockReportSilentFallback.mock.calls.map((c) => (c[1] as { op?: string }).op),
    ).toContain("resolveGranteeDelegation.grantor-user");
  });
});

describe("resolveGranteeAcceptanceStatus — both reads are mirrored", () => {
  it("mirrors a failed acceptance read and a failed withdrawal read", async () => {
    primeTables({
      byok_delegation_acceptances: PGRST("42501", "permission denied"),
      byok_delegation_withdrawals: PGRST("42501", "permission denied"),
    });

    const s = await resolveGranteeAcceptanceStatus("grantee-1", "d1");
    expect(s.accepted).toBe(false);

    const ops = mockReportSilentFallback.mock.calls.map((c) => (c[1] as { op?: string }).op);
    expect(ops).toContain("resolveGranteeAcceptanceStatus.acceptance");
    expect(ops).toContain("resolveGranteeAcceptanceStatus.withdrawal");
  });
});


// ─── PostgREST truncation: a short page must not render as a real figure ─────
//
// `max_rows = 1000` (`apps/web-platform/supabase/config.toml`) truncates with
// HTTP 200 and a NULL error, so an unpaginated read yields a CONFIDENT
// UNDER-COUNT — the same class as the $0.00 these tests were written for, only
// wearing the shape of a success. It is NEWLY reachable: while the select named
// `cost_cents` every read 42703'd and the degraded path always fired.
describe("resolveGrantorDelegations — spend read paging", () => {
  /** A chain that hands back a different page per await, like a real range scan. */
  function makePagedChain(pages: Result[]): Chain {
    const obj = {} as Chain;
    for (const m of ["select", "eq", "in", "is", "gte", "order", "limit", "range"]) {
      (obj as Record<string, unknown>)[m] = vi.fn(() => obj);
    }
    let i = 0;
    obj.then = (onFulfilled, onRejected) => {
      const page = pages[Math.min(i, pages.length - 1)];
      i += 1;
      return Promise.resolve(page).then(onFulfilled, onRejected);
    };
    return obj;
  }

  const row = (n: number) => ({
    delegation_id: "d1",
    token_count: 7,
    unit_cost_cents: 1,
    ts: isoAgo(n % 20),
  });
  const FULL_PAGE = Array.from({ length: 1000 }, (_, i) => row(i));

  function primeWithAudit(auditChain: Chain) {
    const others: Record<string, Chain> = {
      byok_delegations: makeChain(OK(DELEGATIONS)),
      users: makeChain(OK(USERS)),
    };
    mockFrom.mockImplementation((table: string) => {
      if (table === "audit_byok_use") return auditChain;
      const c = others[table];
      if (!c) throw new Error(`unexpected from(${table})`);
      return c;
    });
    return auditChain;
  }

  it("pages past max_rows instead of summing only the first page", async () => {
    const audit = primeWithAudit(
      makePagedChain([OK(FULL_PAGE), OK([row(1), row(2), row(3)])]),
    );

    const rows = await resolveGrantorDelegations("grantor-1", "ws-1", "org-1", IDENTITY);
    const d1 = rows.find((r) => r.id === "d1");

    // 1000 + 3 rows at 1 cent each. An unpaginated read reports 1000 and looks fine.
    expect(d1?.mtdSpentCents, "every page is summed, not just the first").toBe(1003);
    expect(audit.range).toHaveBeenNthCalledWith(1, 0, 999);
    expect(audit.range).toHaveBeenNthCalledWith(2, 1000, 1999);
    // Without a stable total order, `.range` is not a window and pages can
    // repeat or skip rows — the sum would then be wrong in either direction.
    expect(audit.order, "paging needs a unique total order").toHaveBeenCalledWith(
      "id",
      { ascending: true },
    );
  });

  it("degrades to unavailable — never a short number — when the page bound is hit", async () => {
    // Every page comes back full, so the scan never terminates naturally.
    const audit = primeWithAudit(makePagedChain([OK(FULL_PAGE)]));

    const rows = await resolveGrantorDelegations("grantor-1", "ws-1", "org-1", IDENTITY);
    const d1 = rows.find((r) => r.id === "d1");

    expect(d1?.mtdSpentCents, "an honest unknown, not a number we know is short").toBeNull();
    expect(d1?.todaySpentCents).toBeNull();
    expect(d1?.capRemainingCents).toBeNull();

    const ops = mockReportSilentFallback.mock.calls.map((c) => (c[1] as { op?: string }).op);
    expect(ops, "the operator hears about it").toContain(
      "resolveGrantorDelegations.audit-spend",
    );
    expect(audit.range.mock.calls.length, "bounded — it does not page forever").toBe(50);
  });
});
