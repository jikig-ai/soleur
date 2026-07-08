import { describe, expect, it, vi, beforeEach } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// Beta-CRM agent tools (feat-beta-conversation-capture #6165, ADR-102 §5).
// Verifies the make-or-break agent-native invariants: userId closure-capture,
// writes route through the auth.uid()-pinned RPCs (never a raw table insert),
// the untrusted-content envelope precedes third-party PII, the error path is
// PII-safe (a SYNTHETIC error, never the raw PG error whose DETAIL carries
// name/company/body), and the stage enum is single-sourced (AC8 drift guard).

// The SDK tool() wrapper → plain object so the handler is directly invokable.
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

const getFreshTenantClient = vi.fn();
vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: (userId: string) => getFreshTenantClient(userId),
}));

const reportSilentFallback = vi.fn();
vi.mock("@/server/observability", () => ({
  reportSilentFallback: (...args: unknown[]) => reportSilentFallback(...args),
}));

import { buildCrmTools } from "@/server/crm/crm-tools";
import { STAGE_PROBABILITY } from "@/server/crm/stage-probability";

type ToolStub = {
  name: string;
  description: string;
  schema: Record<string, unknown>;
  handler: (args: Record<string, unknown>) => Promise<{
    content: Array<{ type: "text"; text: string }>;
    isError?: true;
  }>;
};

function getTool(name: string, userId = "user-a"): ToolStub {
  const t = buildCrmTools({ userId }).find(
    (x) => (x as unknown as ToolStub).name === name,
  );
  if (!t) throw new Error(`${name} not found`);
  return t as unknown as ToolStub;
}

// Chainable supabase-js mock; every read ends at .order()/.maybeSingle().
function makeTenant(result: { data: unknown; error: unknown }) {
  const rpc = vi.fn((_name: string, _params: Record<string, unknown>) => Promise.resolve(result));
  const q: Record<string, unknown> = {};
  q.select = vi.fn((..._a: unknown[]) => q);
  q.eq = vi.fn((..._a: unknown[]) => q);
  q.contains = vi.fn((..._a: unknown[]) => q);
  q.order = vi.fn((..._a: unknown[]) => Promise.resolve(result));
  q.maybeSingle = vi.fn(() => Promise.resolve(result));
  const insert = vi.fn((..._a: unknown[]) => q);
  q.insert = insert;
  const from = vi.fn((_table: string) => q);
  return { tenant: { from, rpc }, from, rpc, insert };
}

beforeEach(() => {
  vi.clearAllMocks();
});

describe("buildCrmTools — closure + schema hygiene", () => {
  it("exposes exactly the six crm_* tools", () => {
    const names = buildCrmTools({ userId: "u" }).map((t) => (t as unknown as ToolStub).name);
    expect(names.sort()).toEqual(
      [
        "crm_contact_get",
        "crm_contact_list",
        "crm_contact_set_stage",
        "crm_contact_upsert",
        "crm_note_append",
        "crm_note_list",
      ],
    );
  });

  it("no tool exposes userId/user_id as a schema input (closure-captured)", () => {
    for (const t of buildCrmTools({ userId: "u" })) {
      const keys = Object.keys((t as unknown as ToolStub).schema ?? {});
      expect(keys).not.toContain("userId");
      expect(keys).not.toContain("user_id");
      expect(keys).not.toContain("p_user_id");
    }
  });

  it("reads run on the closure userId's tenant client", async () => {
    const { tenant } = makeTenant({ data: [], error: null });
    getFreshTenantClient.mockResolvedValue(tenant);
    await getTool("crm_contact_list", "user-xyz").handler({});
    expect(getFreshTenantClient).toHaveBeenCalledWith("user-xyz");
  });
});

describe("reads — untrusted envelope precedes PII", () => {
  it("crm_contact_list emits the untrusted envelope as the first content block", async () => {
    const rows = [{ id: "c1", name: "Alice", company: "ACME" }];
    const { tenant } = makeTenant({ data: rows, error: null });
    getFreshTenantClient.mockResolvedValue(tenant);
    const res = await getTool("crm_contact_list").handler({});
    expect(res.content[0].text).toMatch(/UNTRUSTED third-party content/i);
    expect(res.content[1].text).toContain("Alice");
    expect(res.isError).toBeUndefined();
  });

  it("crm_note_list envelopes the note body and honors the lens filter", async () => {
    const { tenant, from } = makeTenant({ data: [{ id: "n1", body: "hi", lens: ["sales"] }], error: null });
    getFreshTenantClient.mockResolvedValue(tenant);
    const res = await getTool("crm_note_list").handler({ contactId: "11111111-1111-1111-1111-111111111111", lens: "sales" });
    expect(res.content[0].text).toMatch(/UNTRUSTED/i);
    // read went to interview_notes (not a raw contacts read)
    expect(from).toHaveBeenCalledWith("interview_notes");
    const q = from.mock.results[0].value as { contains: ReturnType<typeof vi.fn> };
    expect(q.contains).toHaveBeenCalledWith("lens", ["sales"]);
  });
});

describe("writes — route through the auth.uid()-pinned RPCs, never a raw insert", () => {
  it("crm_contact_upsert calls tenant.rpc('crm_contact_upsert', ...) with NO p_user_id and no raw insert", async () => {
    const { tenant, rpc, insert } = makeTenant({ data: "new-id", error: null });
    getFreshTenantClient.mockResolvedValue(tenant);
    const res = await getTool("crm_contact_upsert").handler({
      name: "Alice",
      company: "ACME",
      stage: "qualified",
      amount: 1000,
      currency: "USD",
    });
    expect(rpc).toHaveBeenCalledTimes(1);
    const [fn, params] = rpc.mock.calls[0] as [string, Record<string, unknown>];
    expect(fn).toBe("crm_contact_upsert");
    expect(params).not.toHaveProperty("p_user_id");
    expect(params.p_name).toBe("Alice");
    expect(params.p_stage).toBe("qualified");
    expect(insert).not.toHaveBeenCalled();
    expect(JSON.parse(res.content[0].text)).toEqual({ id: "new-id" });
  });

  it("crm_note_append and crm_contact_set_stage route to their RPCs", async () => {
    const { tenant, rpc } = makeTenant({ data: "note-id", error: null });
    getFreshTenantClient.mockResolvedValue(tenant);
    await getTool("crm_note_append").handler({
      contactId: "11111111-1111-1111-1111-111111111111",
      body: "prospect said X",
      lens: ["sales", "product"],
    });
    expect(rpc.mock.calls[0][0]).toBe("crm_note_append");
    expect((rpc.mock.calls[0][1] as Record<string, unknown>).p_lens).toEqual(["sales", "product"]);

    rpc.mockClear();
    await getTool("crm_contact_set_stage").handler({
      contactId: "11111111-1111-1111-1111-111111111111",
      toStage: "committed",
    });
    expect(rpc.mock.calls[0][0]).toBe("crm_contact_set_stage");
    expect((rpc.mock.calls[0][1] as Record<string, unknown>).p_to_stage).toBe("committed");
  });
});

describe("PII-safe error path (security P1-1)", () => {
  // A realistic Postgres error whose DETAIL carries third-party PII.
  const pgError = {
    code: "23514",
    message: 'new row for relation "beta_contacts" violates check constraint',
    details: "Failing row contains (uuid, user, Alice Example, ACME Corp, CTO, ...).",
    hint: null,
  };

  it("does NOT forward the raw PG error to Sentry; mirrors a synthetic PII-free error with only {op,userId,code}", async () => {
    const { tenant } = makeTenant({ data: null, error: pgError });
    getFreshTenantClient.mockResolvedValue(tenant);
    const res = await getTool("crm_contact_upsert", "user-a").handler({ name: "Alice Example", company: "ACME Corp" });

    expect(res.isError).toBe(true);
    // Agent-facing payload carries no row values.
    const payload = JSON.parse(res.content[0].text);
    expect(JSON.stringify(payload)).not.toMatch(/Alice|ACME/);
    expect(payload.code).toBe("constraint_violation"); // 23514 -> semantic code

    // Sentry mirror: first arg is a SYNTHETIC Error (not the pg error object),
    // and NOTHING passed to it contains the PII.
    expect(reportSilentFallback).toHaveBeenCalledTimes(1);
    const [errArg, ctx] = reportSilentFallback.mock.calls[0] as [unknown, Record<string, unknown>];
    expect(errArg).not.toBe(pgError);
    expect(errArg).toBeInstanceOf(Error);
    expect((errArg as Error).message).not.toMatch(/Alice|ACME|Failing row/);
    expect(JSON.stringify(ctx)).not.toMatch(/Alice|ACME|Failing row/);
    expect(ctx).toMatchObject({ feature: "crm-tools", op: "upsert", extra: { userId: "user-a", code: "constraint_violation" } });
  });

  it("maps a 42501 (not authorized) RPC error to the not_authorized code", async () => {
    const { tenant } = makeTenant({ data: null, error: { code: "42501", message: "not authorized", details: null } });
    getFreshTenantClient.mockResolvedValue(tenant);
    const res = await getTool("crm_contact_set_stage").handler({
      contactId: "11111111-1111-1111-1111-111111111111",
      toStage: "committed",
    });
    expect(res.isError).toBe(true);
    expect(JSON.parse(res.content[0].text).code).toBe("not_authorized");
  });
});

describe("AC8 — stage enum single-source drift guard", () => {
  it("Object.keys(STAGE_PROBABILITY) equals the migration stage CHECK set", () => {
    const migration = readFileSync(
      path.resolve(__dirname, "../supabase/migrations/126_beta_crm.sql"),
      "utf8",
    );
    const checkList = migration.match(/stage\s+text\s+NOT NULL DEFAULT 'new'\s*CHECK \(stage IN \(([^)]+)\)\)/i)?.[1];
    expect(checkList, "beta_contacts.stage CHECK not found").toBeTruthy();
    const migrationStages = (checkList as string)
      .split(",")
      .map((s) => s.trim().replace(/'/g, ""));
    expect(new Set(migrationStages)).toEqual(new Set(Object.keys(STAGE_PROBABILITY)));
  });
});
