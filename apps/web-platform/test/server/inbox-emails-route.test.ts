import { describe, it, expect, vi, beforeEach } from "vitest";

// Phase 5a RED — GET /api/inbox/emails (operator-inbox-delegation).
// Contract (plan row `app/api/inbox/emails/route.ts`):
//   - withUserRateLimit (401 unauth at the wrapper) + user-context Supabase
//     client (NEVER createServiceClient — that silently bypasses RLS).
//   - Returns full rows under { items }.
//   - Excludes unfinalized stubs: `.or("mail_class.not.is.null,statutory_class.not.is.null")`.
//   - Excludes probe rows unless `?include_probes=1` (strict === "1").
//     Probe exclusion uses `.or("mail_class.is.null,mail_class.neq.probe")`
//     because PostgREST `neq` drops NULL mail_class rows — which would hide
//     statutory fast-path rows finalized before any mail_class write.
//   - Excludes archived unless `?status=archived` (strict equality; any
//     other value = default view).
//   - Server-side ordering contract: unacknowledged statutory first
//     (statutory_class NOT NULL AND status = 'new'), then received_at DESC.
//   - mig 111: reads gated SOLELY by workspace-owner RLS — no `.eq("user_id")`.
//   - HTTP-only exports: GET is the only HTTP verb exported
//     (cq-nextjs-route-files-http-only-exports).

// withUserRateLimit hashes the user id for Sentry scoping; the hasher
// throws when the pepper env is unset (precedent: with-user-rate-limit.test.ts).
vi.hoisted(() => {
  process.env.SENTRY_USERID_PEPPER = "test-pepper";
});

const { mockGetUser, queryState, recorded } = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  queryState: {
    result: { data: [] as unknown[], error: null as { code?: string } | null },
    // L1: the default view is TWO queries — the uncapped pinned statutory
    // query resolves from its own slot.
    pinnedResult: {
      data: [] as unknown[],
      error: null as { code?: string } | null,
    },
  },
  recorded: {
    from: [] as string[],
    select: [] as string[],
    eq: [] as unknown[][],
    neq: [] as unknown[][],
    not: [] as unknown[][],
    or: [] as string[],
    order: [] as unknown[][],
    limit: [] as unknown[],
  },
}));

vi.mock("@/lib/supabase/server", () => {
  // Thenable builder (L1): the pinned query awaits after .order(...) while
  // the rest/archived queries chain .limit(...) — the builder must be
  // awaitable at either point. The pinned query is recognized by its
  // `.not("statutory_class","is",null)` + `.eq("status","new")` shape.
  function makeBuilder() {
    const local = { eq: [] as unknown[][], not: [] as unknown[][] };
    const builder: Record<string, unknown> = {};
    builder.select = vi.fn((cols: string) => {
      recorded.select.push(cols);
      return builder;
    });
    builder.eq = vi.fn((...args: unknown[]) => {
      recorded.eq.push(args);
      local.eq.push(args);
      return builder;
    });
    builder.neq = vi.fn((...args: unknown[]) => {
      recorded.neq.push(args);
      return builder;
    });
    builder.not = vi.fn((...args: unknown[]) => {
      recorded.not.push(args);
      local.not.push(args);
      return builder;
    });
    builder.or = vi.fn((expr: string) => {
      recorded.or.push(expr);
      return builder;
    });
    builder.order = vi.fn((...args: unknown[]) => {
      recorded.order.push(args);
      return builder;
    });
    builder.limit = vi.fn((n: number) => {
      recorded.limit.push(n);
      return builder;
    });
    builder.then = (
      onFulfilled: (v: unknown) => unknown,
      onRejected?: (e: unknown) => unknown,
    ) => {
      const isPinnedQuery =
        local.not.some((a) => a[0] === "statutory_class") &&
        local.eq.some((a) => a[0] === "status" && a[1] === "new");
      const result = isPinnedQuery
        ? queryState.pinnedResult
        : queryState.result;
      return Promise.resolve(result).then(onFulfilled, onRejected);
    };
    return builder;
  }
  return {
    createClient: vi.fn(async () => ({
      auth: { getUser: mockGetUser },
      from: (table: string) => {
        recorded.from.push(table);
        return makeBuilder();
      },
    })),
    createServiceClient: vi.fn(() => {
      throw new Error("service client must never be used by this route (RLS bypass)");
    }),
  };
});

vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
  // userid-pseudonymize re-exports the hasher from observability; the
  // rate-limit wrapper calls it for Sentry scoping.
  hashUserId: vi.fn((v: string) => `hashed-${v}`),
}));

async function importRoute() {
  return await import("@/app/api/inbox/emails/route");
}

function makeRequest(url: string): Request {
  return new Request(url, { method: "GET" });
}

function resetRecorded() {
  recorded.from.length = 0;
  recorded.select.length = 0;
  recorded.eq.length = 0;
  recorded.neq.length = 0;
  recorded.not.length = 0;
  recorded.or.length = 0;
  recorded.order.length = 0;
  recorded.limit.length = 0;
}

const FINALIZED_OR = "mail_class.not.is.null,statutory_class.not.is.null";
const PROBE_EXCLUSION_OR = "mail_class.is.null,mail_class.neq.probe";
// L1: De-Morgan exclusion of the pinned shape from the capped rest query.
const PINNED_EXCLUSION_OR = "statutory_class.is.null,status.neq.new";

const BASE = "https://app.soleur.ai/api/inbox/emails";

describe("GET /api/inbox/emails", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    resetRecorded();
    queryState.result = { data: [], error: null };
    queryState.pinnedResult = { data: [], error: null };
    mockGetUser.mockResolvedValue({ data: { user: { id: "u1" } } });
  });

  it("returns 401 when unauthenticated and never touches the table", async () => {
    mockGetUser.mockResolvedValue({ data: { user: null } });
    const { GET } = await importRoute();
    const res = await GET(makeRequest(BASE));
    expect(res.status).toBe(401);
    expect(recorded.from).toHaveLength(0);
  });

  it("default view: finalized-only + probe-excluded + archived-excluded + owner-scoped + received_at DESC + L1 cap shape", async () => {
    const { GET } = await importRoute();
    const res = await GET(makeRequest(BASE));
    expect(res.status).toBe(200);

    expect(recorded.from).toContain("email_triage_items");
    // Unfinalized-stub exclusion.
    expect(recorded.or).toContain(FINALIZED_OR);
    // Probe exclusion (NULL-safe — plain .neq would drop mail_class IS NULL
    // statutory rows).
    expect(recorded.or).toContain(PROBE_EXCLUSION_OR);
    // Pinned shape excluded from the capped rest query (no duplicates).
    expect(recorded.or).toContain(PINNED_EXCLUSION_OR);
    // Archived exclusion.
    expect(recorded.neq).toContainEqual(["status", "archived"]);
    // mig 111: workspace-shared reads gated SOLELY by RLS — NO `.eq("user_id")`
    // filter (it would re-narrow below RLS and hide the shared inbox).
    expect(recorded.eq).not.toContainEqual(["user_id", "u1"]);
    // DB-side base ordering.
    expect(recorded.order).toContainEqual(["received_at", { ascending: false }]);
    // L1: pinned statutory query runs (uncapped) + the rest query is the
    // ONLY capped one — exactly one .limit(100) across the default view.
    expect(recorded.not).toContainEqual(["statutory_class", "is", null]);
    expect(recorded.eq).toContainEqual(["status", "new"]);
    expect(recorded.limit).toEqual([100]);
  });

  it("include_probes=1 (strict) includes probe rows", async () => {
    const { GET } = await importRoute();
    await GET(makeRequest(`${BASE}?include_probes=1`));
    expect(recorded.or).toContain(FINALIZED_OR);
    expect(recorded.or).not.toContain(PROBE_EXCLUSION_OR);
  });

  it("include_probes=true is NOT the opt-in (strict === \"1\")", async () => {
    const { GET } = await importRoute();
    await GET(makeRequest(`${BASE}?include_probes=true`));
    expect(recorded.or).toContain(PROBE_EXCLUSION_OR);
  });

  it("status=archived shows archived rows only (single query, capped at 100)", async () => {
    const { GET } = await importRoute();
    await GET(makeRequest(`${BASE}?status=archived`));
    expect(recorded.eq).toContainEqual(["status", "archived"]);
    expect(recorded.neq).not.toContainEqual(["status", "archived"]);
    expect(recorded.limit).toEqual([100]);
    // Archived rows are never pinned — no statutory pinned query runs.
    expect(recorded.not).not.toContainEqual(["statutory_class", "is", null]);
  });

  it("any other status value falls back to the default view (strict equality)", async () => {
    const { GET } = await importRoute();
    await GET(makeRequest(`${BASE}?status=new`));
    // Default-view shape: archived exclusion + pinned/rest split — the
    // param value is NEVER applied as an eq filter (the only eq on status
    // is the pinned query's own hardcoded 'new').
    expect(recorded.neq).toContainEqual(["status", "archived"]);
    expect(recorded.or).toContain(PINNED_EXCLUSION_OR);
    expect(recorded.eq).not.toContainEqual(["status", "archived"]);
  });

  it("pins unacknowledged statutory rows first, then received_at DESC (merged pinned-first; cap can never hide a statutory clock)", async () => {
    // L1: two queries — the uncapped pinned statutory query merges ahead of
    // the capped rest query. Acknowledged statutory rows are NOT pinned
    // (they come back from the rest query).
    queryState.pinnedResult = {
      data: [
        { id: "b", statutory_class: "dsar", status: "new", received_at: "2026-06-10T09:00:00Z" },
        { id: "d", statutory_class: "dsar", status: "new", received_at: "2026-06-10T07:00:00Z" },
      ],
      error: null,
    };
    queryState.result = {
      data: [
        { id: "a", statutory_class: null, status: "new", received_at: "2026-06-10T10:00:00Z" },
        { id: "c", statutory_class: "breach", status: "acknowledged", received_at: "2026-06-10T08:00:00Z" },
      ],
      error: null,
    };
    const { GET } = await importRoute();
    const res = await GET(makeRequest(BASE));
    expect(res.status).toBe(200);
    const json = await res.json();
    expect(json.items.map((r: { id: string }) => r.id)).toEqual(["b", "d", "a", "c"]);
  });

  it("returns 500 on rest-query error", async () => {
    queryState.result = { data: [], error: { code: "XX000" } };
    const { GET } = await importRoute();
    const res = await GET(makeRequest(BASE));
    expect(res.status).toBe(500);
  });

  it("returns 500 on pinned-query error", async () => {
    queryState.pinnedResult = { data: [], error: { code: "XX000" } };
    const { GET } = await importRoute();
    const res = await GET(makeRequest(BASE));
    expect(res.status).toBe(500);
  });

  it("exports GET as the only HTTP verb (cq-nextjs-route-files-http-only-exports)", async () => {
    const mod = await importRoute();
    expect(mod.GET).toBeTypeOf("function");
    for (const verb of ["POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"]) {
      expect((mod as Record<string, unknown>)[verb]).toBeUndefined();
    }
  });
});
