import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, test, expect, vi, beforeEach } from "vitest";

// Phase 5a RED — `server/email-triage-tools.ts` agent-native parity
// (plan row + AC11). Contract:
//   buildEmailTriageTools({ userId }) returns EXACTLY two read tools:
//     - email_triage_list: params { includeProbes?, status? } mirroring
//       GET /api/inbox/emails filter semantics EXACTLY (finalized-only,
//       NULL-safe probe exclusion, archived opt-in, statutory-pinned-first
//       ordering, owner scope via userId closure + RLS).
//     - email_triage_get: param { id }; returns the row PLUS server-side
//       derived dueDate/dueLabel/catalogExcerpt from the statutory registry
//       (the agent must never invent statutory periods).
//   FR9 boundary: NO write/status tool — no email_triage_set_status, no
//   acknowledge/archive tool. Status transitions are operator-UI-only in
//   v1 (#4671/#4672).

const { mockGetFreshTenantClient, queryState, recorded } = vi.hoisted(() => ({
  mockGetFreshTenantClient: vi.fn(),
  queryState: {
    listResult: { data: [] as unknown[], error: null as unknown },
    getResult: { data: null as unknown, error: null as unknown },
  },
  recorded: {
    from: [] as string[],
    eq: [] as unknown[][],
    neq: [] as unknown[][],
    or: [] as string[],
    order: [] as unknown[][],
  },
}));

vi.mock("@anthropic-ai/claude-agent-sdk", () => ({
  tool: vi.fn(
    (name: string, description: string, schema: unknown, handler: Function) => ({
      name,
      description,
      schema,
      handler,
    }),
  ),
}));

vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: (...args: unknown[]) => mockGetFreshTenantClient(...args),
}));

function makeTenantStub() {
  function makeBuilder() {
    const builder: Record<string, unknown> = {};
    builder.select = vi.fn(() => builder);
    builder.eq = vi.fn((...args: unknown[]) => {
      recorded.eq.push(args);
      return builder;
    });
    builder.neq = vi.fn((...args: unknown[]) => {
      recorded.neq.push(args);
      return builder;
    });
    builder.or = vi.fn((expr: string) => {
      recorded.or.push(expr);
      return builder;
    });
    builder.order = vi.fn((...args: unknown[]) => {
      recorded.order.push(args);
      return Promise.resolve(queryState.listResult);
    });
    builder.maybeSingle = vi.fn(() => Promise.resolve(queryState.getResult));
    return builder;
  }
  return {
    from: (table: string) => {
      recorded.from.push(table);
      return makeBuilder();
    },
  };
}

type ToolStub = {
  name: string;
  description: string;
  schema: Record<string, unknown>;
  handler: (args: Record<string, unknown>) => Promise<{
    content: Array<{ type: "text"; text: string }>;
    isError?: true;
  }>;
};

async function buildTools(userId = "u1"): Promise<ToolStub[]> {
  const { buildEmailTriageTools } = await import("@/server/email-triage-tools");
  return buildEmailTriageTools({ userId }) as unknown as ToolStub[];
}

async function getTool(name: string, userId = "u1"): Promise<ToolStub> {
  const tools = await buildTools(userId);
  const t = tools.find((x) => x.name === name);
  if (!t) throw new Error(`tool ${name} not found`);
  return t;
}

function parsePayload(res: { content: Array<{ text: string }> }): unknown {
  return JSON.parse(res.content[0].text);
}

const FINALIZED_OR = "mail_class.not.is.null,statutory_class.not.is.null";
const PROBE_EXCLUSION_OR = "mail_class.is.null,mail_class.neq.probe";

describe("buildEmailTriageTools", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    recorded.from.length = 0;
    recorded.eq.length = 0;
    recorded.neq.length = 0;
    recorded.or.length = 0;
    recorded.order.length = 0;
    queryState.listResult = { data: [], error: null };
    queryState.getResult = { data: null, error: null };
    mockGetFreshTenantClient.mockResolvedValue(makeTenantStub());
  });

  test("returns exactly two READ tools — list + get, no write/status tool (FR9 boundary)", async () => {
    const tools = await buildTools();
    expect(tools).toHaveLength(2);
    const names = tools.map((t) => t.name);
    expect(names).toContain("email_triage_list");
    expect(names).toContain("email_triage_get");
    for (const name of names) {
      expect(name).not.toMatch(/set_status|acknowledge|archive|update|write/);
    }
  });

  test("email_triage_list mirrors the route's default filters (finalized + probe-excluded + archived-excluded + owner scope)", async () => {
    const list = await getTool("email_triage_list");
    await list.handler({});
    expect(recorded.from).toContain("email_triage_items");
    expect(recorded.or).toContain(FINALIZED_OR);
    expect(recorded.or).toContain(PROBE_EXCLUSION_OR);
    expect(recorded.neq).toContainEqual(["status", "archived"]);
    expect(recorded.eq).toContainEqual(["user_id", "u1"]);
    expect(recorded.order).toContainEqual(["received_at", { ascending: false }]);
  });

  test("email_triage_list includeProbes=true drops the probe exclusion", async () => {
    const list = await getTool("email_triage_list");
    await list.handler({ includeProbes: true });
    expect(recorded.or).toContain(FINALIZED_OR);
    expect(recorded.or).not.toContain(PROBE_EXCLUSION_OR);
  });

  test("email_triage_list status='archived' flips to the archived view", async () => {
    const list = await getTool("email_triage_list");
    await list.handler({ status: "archived" });
    expect(recorded.eq).toContainEqual(["status", "archived"]);
    expect(recorded.neq).not.toContainEqual(["status", "archived"]);
  });

  test("email_triage_list pins unacknowledged statutory rows first (route ordering parity)", async () => {
    queryState.listResult = {
      data: [
        { id: "a", statutory_class: null, status: "new", received_at: "2026-06-10T10:00:00Z" },
        { id: "b", statutory_class: "dsar", status: "new", received_at: "2026-06-10T09:00:00Z" },
        { id: "c", statutory_class: "breach", status: "acknowledged", received_at: "2026-06-10T08:00:00Z" },
        { id: "d", statutory_class: "dsar", status: "new", received_at: "2026-06-10T07:00:00Z" },
      ],
      error: null,
    };
    const list = await getTool("email_triage_list");
    const res = await list.handler({});
    const rows = parsePayload(res) as Array<{ id: string }>;
    expect(rows.map((r) => r.id)).toEqual(["b", "d", "a", "c"]);
  });

  test("userId is captured in closure — different builders scope to their own user", async () => {
    const list = await getTool("email_triage_list", "u2");
    await list.handler({});
    expect(mockGetFreshTenantClient).toHaveBeenCalledWith("u2");
    expect(recorded.eq).toContainEqual(["user_id", "u2"]);
  });

  test("email_triage_get derives dueDate/dueLabel/catalogExcerpt from the statutory registry", async () => {
    // Jan 31 + one calendar month clamps to Feb 28 (2026 is not a leap
    // year) — GDPR Art. 12(3) semantics straight from computeDueDate.
    queryState.getResult = {
      data: {
        id: "e1",
        statutory_class: "dsar",
        rule_id: "dsar-art15",
        status: "new",
        received_at: "2026-01-31T10:00:00.000Z",
      },
      error: null,
    };
    const get = await getTool("email_triage_get");
    const res = await get.handler({ id: "e1" });
    const row = parsePayload(res) as Record<string, unknown>;
    expect(row.dueDate).toBe("2026-02-28T10:00:00.000Z");
    expect(row.dueLabel).toBe(
      "due 28 Feb 2026 — respond within one calendar month (GDPR Art. 12(3))",
    );
    expect(row.catalogExcerpt).toContain("one calendar month");
  });

  test("email_triage_get on a non-statutory row adds no derived clock fields", async () => {
    queryState.getResult = {
      data: {
        id: "e2",
        statutory_class: null,
        rule_id: null,
        status: "new",
        received_at: "2026-06-01T10:00:00.000Z",
        mail_class: "vendor",
      },
      error: null,
    };
    const get = await getTool("email_triage_get");
    const res = await get.handler({ id: "e2" });
    const row = parsePayload(res) as Record<string, unknown>;
    expect(row.dueDate).toBeUndefined();
    expect(row.dueLabel).toBeUndefined();
    expect(row.catalogExcerpt).toBeUndefined();
  });

  test("email_triage_get returns typed not_found error when no owned row matches", async () => {
    const get = await getTool("email_triage_get");
    const res = await get.handler({ id: "missing" });
    expect(res.isError).toBe(true);
    expect(parsePayload(res)).toMatchObject({ code: "not_found" });
  });
});

describe("registration + tiering (AC11)", () => {
  test("TOOL_TIER_MAP maps both reads to auto-approve and contains NO email_triage write entry", async () => {
    const { TOOL_TIER_MAP, getToolTier } = await import("@/server/tool-tiers");
    expect(getToolTier("mcp__soleur_platform__email_triage_list")).toBe("auto-approve");
    expect(getToolTier("mcp__soleur_platform__email_triage_get")).toBe("auto-approve");
    const writeEntries = Object.keys(TOOL_TIER_MAP).filter(
      (k) => /email_triage/.test(k) && !/email_triage_(list|get)$/.test(k),
    );
    expect(writeEntries).toEqual([]);
  });

  test("agent-runner registers both tools + the Email triage inbox prompt block; no write tool registered (grep)", () => {
    const source = readFileSync(
      join(__dirname, "..", "..", "server", "agent-runner.ts"),
      "utf-8",
    );
    expect(source).toMatch(/buildEmailTriageTools/);
    expect(source).toContain("mcp__soleur_platform__email_triage_list");
    expect(source).toContain("mcp__soleur_platform__email_triage_get");
    expect(source).toContain("## Email triage inbox");
    // FR9 boundary — grep-asserted: no write-tool name anywhere.
    expect(source).not.toMatch(/email_triage_set_status|email_triage_acknowledge|email_triage_archive/);
  });
});
