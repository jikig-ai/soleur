import { describe, it, expect, vi, beforeEach } from "vitest";
import type { User } from "@supabase/supabase-js";

const rpc = vi.fn();
const inboxRows: { id: string }[] = [];
const emailRows: { id: string }[] = [];
const inCalls: { table: string; ids: string[] }[] = [];
let prefetchError: { code: string } | null = null;

// Supabase builder mock — .in() HONORS its id slice (query-driven, not
// seed-driven: a handler that queried the wrong ids fails these tests).
const from = vi.fn((table: string) => ({
  select: () => ({
    in: async (_col: string, ids: string[]) => {
      inCalls.push({ table, ids: [...ids] });
      if (prefetchError) return { data: null, error: prefetchError };
      const source = table === "inbox_item" ? inboxRows : emailRows;
      return { data: source.filter((r) => ids.includes(r.id)), error: null };
    },
  }),
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: async () => ({ rpc, from }),
}));

const reportSilentFallback = vi.fn();
vi.mock("@/server/observability", () => ({
  reportSilentFallback: (...a: unknown[]) => reportSilentFallback(...a),
}));

import { inboxBulkArchiveHandler } from "@/server/inbox-bulk-archive-handler";

const USER = { id: "user-1" } as User;
const U1 = "11111111-1111-4111-8111-111111111111";
const U2 = "22222222-2222-4222-8222-222222222222";
const U3 = "33333333-3333-4333-8333-333333333333";

function req(body: unknown): Request {
  return new Request("https://x.test/api/inbox/bulk-archive", {
    method: "POST",
    body: JSON.stringify(body),
  });
}

function seedInboxRow(
  id: string,
  overrides: Partial<{ severity: string; acted_at: string | null; status: string }> = {},
) {
  inboxRows.push({
    id,
    severity: "info",
    acted_at: "2026-09-30T00:00:00Z",
    status: "read",
    ...overrides,
  });
}

function seedEmailRow(
  id: string,
  overrides: Partial<{ status: string; statutory_class: string | null }> = {},
) {
  emailRows.push({ id, status: "new", statutory_class: null, ...overrides });
}

function outcomes(res: Response): Promise<
  { results: { id: string; kind: string; outcome: string; reason?: string }[] }
> {
  return res.json();
}

function outcomeFor(
  r: { id: string; kind: string; outcome: string; reason?: string }[],
  id: string,
) {
  return r.find((x) => x.id === id);
}

beforeEach(() => {
  rpc.mockReset();
  from.mockClear();
  reportSilentFallback.mockReset();
  inboxRows.length = 0;
  emailRows.length = 0;
  inCalls.length = 0;
  prefetchError = null;
});

describe("request validation", () => {
  it("rejects a malformed body (400) before touching the DB", async () => {
    const res = await inboxBulkArchiveHandler(req({ items: "nope" }), USER);
    expect(res.status).toBe(400);
    expect(rpc).not.toHaveBeenCalled();
    expect(from).not.toHaveBeenCalled();
  });

  it("rejects >200 items (400)", async () => {
    const items = Array.from({ length: 201 }, (_, i) => ({
      kind: "inbox",
      id: `00000000-0000-4000-8000-${String(i).padStart(12, "0")}`,
    }));
    const res = await inboxBulkArchiveHandler(req({ items }), USER);
    expect(res.status).toBe(400);
    expect(from).not.toHaveBeenCalled();
  });

  it("rejects a non-UUID id (400)", async () => {
    const res = await inboxBulkArchiveHandler(
      req({ items: [{ kind: "inbox", id: "not-a-uuid" }] }),
      USER,
    );
    expect(res.status).toBe(400);
  });

  it("rejects an unknown kind (400)", async () => {
    const res = await inboxBulkArchiveHandler(
      req({ items: [{ kind: "sms", id: U1 }] }),
      USER,
    );
    expect(res.status).toBe(400);
  });

  it("dedupes repeated ids into a single result", async () => {
    seedInboxRow(U1);
    rpc.mockResolvedValue({ error: null });
    const res = await inboxBulkArchiveHandler(
      req({ items: [{ kind: "inbox", id: U1 }, { kind: "inbox", id: U1 }] }),
      USER,
    );
    const body = await outcomes(res);
    expect(body.results).toHaveLength(1);
    expect(rpc).toHaveBeenCalledTimes(1);
  });
});

describe("eligibility classification (no RPC dispatched)", () => {
  it("statutory email → guarded + statutory, RPC never invoked", async () => {
    seedEmailRow(U1, { statutory_class: "dsar" });
    const res = await inboxBulkArchiveHandler(
      req({ items: [{ kind: "email", id: U1 }] }),
      USER,
    );
    const body = await outcomes(res);
    expect(outcomeFor(body.results, U1)).toMatchObject({
      outcome: "guarded",
      reason: "statutory",
    });
    expect(rpc).not.toHaveBeenCalled();
  });

  it("un-acted action_required inbox item → guarded + needs_action, RPC never invoked", async () => {
    seedInboxRow(U1, { severity: "action_required", acted_at: null });
    const res = await inboxBulkArchiveHandler(
      req({ items: [{ kind: "inbox", id: U1 }] }),
      USER,
    );
    const body = await outcomes(res);
    expect(outcomeFor(body.results, U1)).toMatchObject({
      outcome: "guarded",
      reason: "needs_action",
    });
    expect(rpc).not.toHaveBeenCalled();
  });

  it("acknowledged email → guarded + already_acknowledged", async () => {
    seedEmailRow(U1, { status: "acknowledged" });
    const res = await inboxBulkArchiveHandler(
      req({ items: [{ kind: "email", id: U1 }] }),
      USER,
    );
    const body = await outcomes(res);
    expect(outcomeFor(body.results, U1)).toMatchObject({
      outcome: "guarded",
      reason: "already_acknowledged",
    });
    expect(rpc).not.toHaveBeenCalled();
  });

  it("already-archived row → guarded + already_archived", async () => {
    seedInboxRow(U1, { status: "archived" });
    const res = await inboxBulkArchiveHandler(
      req({ items: [{ kind: "inbox", id: U1 }] }),
      USER,
    );
    const body = await outcomes(res);
    expect(outcomeFor(body.results, U1)).toMatchObject({
      outcome: "guarded",
      reason: "already_archived",
    });
  });
});

describe("dispatch + outcome mapping", () => {
  it("archives an eligible inbox item via set_inbox_item_state", async () => {
    seedInboxRow(U1);
    rpc.mockResolvedValue({ error: null });
    const res = await inboxBulkArchiveHandler(
      req({ items: [{ kind: "inbox", id: U1 }] }),
      USER,
    );
    expect(res.status).toBe(200);
    const body = await outcomes(res);
    expect(outcomeFor(body.results, U1)?.outcome).toBe("archived");
    expect(rpc).toHaveBeenCalledWith("set_inbox_item_state", {
      p_id: U1,
      p_action: "archived",
    });
  });

  it("archives an eligible email via set_email_triage_status", async () => {
    seedEmailRow(U1);
    rpc.mockResolvedValue({ error: null });
    const res = await inboxBulkArchiveHandler(
      req({ items: [{ kind: "email", id: U1 }] }),
      USER,
    );
    const body = await outcomes(res);
    expect(outcomeFor(body.results, U1)?.outcome).toBe("archived");
    expect(rpc).toHaveBeenCalledWith("set_email_triage_status", {
      p_id: U1,
      p_status: "archived",
    });
  });

  it("foreign-workspace id (invisible to RLS prefetch) → not_found, no RPC", async () => {
    // Nothing seeded — the row exists in the table but RLS hides it.
    const res = await inboxBulkArchiveHandler(
      req({ items: [{ kind: "inbox", id: U1 }] }),
      USER,
    );
    const body = await outcomes(res);
    expect(outcomeFor(body.results, U1)?.outcome).toBe("not_found");
    expect(rpc).not.toHaveBeenCalled();
  });

  it("RPC 42501 → not_found (no oracle)", async () => {
    seedInboxRow(U1);
    rpc.mockResolvedValue({ error: { code: "42501" } });
    const res = await inboxBulkArchiveHandler(
      req({ items: [{ kind: "inbox", id: U1 }] }),
      USER,
    );
    const body = await outcomes(res);
    expect(outcomeFor(body.results, U1)?.outcome).toBe("not_found");
  });

  it("RPC P0001 → conflict", async () => {
    seedInboxRow(U1);
    rpc.mockResolvedValue({ error: { code: "P0001" } });
    const res = await inboxBulkArchiveHandler(
      req({ items: [{ kind: "inbox", id: U1 }] }),
      USER,
    );
    const body = await outcomes(res);
    expect(outcomeFor(body.results, U1)?.outcome).toBe("conflict");
  });

  it("unexpected RPC error → error + Sentry mirror (ids only)", async () => {
    seedInboxRow(U1);
    rpc.mockResolvedValue({ error: { code: "XX000", message: "boom" } });
    const res = await inboxBulkArchiveHandler(
      req({ items: [{ kind: "inbox", id: U1 }] }),
      USER,
    );
    const body = await outcomes(res);
    expect(outcomeFor(body.results, U1)?.outcome).toBe("error");
    expect(reportSilentFallback).toHaveBeenCalled();
  });

  it("mixed batch returns per-item outcomes in request order", async () => {
    seedInboxRow(U1); // ok
    seedInboxRow(U2, { severity: "action_required", acted_at: null }); // guarded
    // U3 unseeded → not_found
    seedEmailRow(U3.slice(0, 8) + "4" + U3.slice(9), { statutory_class: "x" });
    rpc.mockResolvedValue({ error: null });
    const res = await inboxBulkArchiveHandler(
      req({
        items: [
          { kind: "inbox", id: U1 },
          { kind: "inbox", id: U2 },
          { kind: "inbox", id: U3 },
        ],
      }),
      USER,
    );
    const body = await outcomes(res);
    expect(body.results.map((r) => r.id)).toEqual([U1, U2, U3]);
    expect(body.results.map((r) => r.outcome)).toEqual([
      "archived",
      "guarded",
      "not_found",
    ]);
    expect(rpc).toHaveBeenCalledTimes(1);
  });
});

describe("prefetch chunking + failure", () => {
  it("chunks the id prefetch at 100 ids per .in() call", async () => {
    const ids = Array.from({ length: 150 }, (_, i) =>
      `00000000-0000-4000-8000-${String(i).padStart(12, "0")}`,
    );
    for (const id of ids) seedInboxRow(id);
    rpc.mockResolvedValue({ error: null });
    const res = await inboxBulkArchiveHandler(
      req({ items: ids.map((id) => ({ kind: "inbox", id })) }),
      USER,
    );
    expect(res.status).toBe(200);
    const inboxCalls = inCalls.filter((c) => c.table === "inbox_item");
    expect(inboxCalls.map((c) => c.ids.length)).toEqual([100, 50]);
    const body = await outcomes(res);
    expect(body.results).toHaveLength(150);
    expect(body.results.every((r) => r.outcome === "archived")).toBe(true);
  });

  it("prefetch error → 500 + Sentry mirror", async () => {
    prefetchError = { code: "XX000" };
    const res = await inboxBulkArchiveHandler(
      req({ items: [{ kind: "inbox", id: U1 }] }),
      USER,
    );
    expect(res.status).toBe(500);
    expect(reportSilentFallback).toHaveBeenCalled();
    expect(rpc).not.toHaveBeenCalled();
  });

  it("empty items array → 400", async () => {
    const res = await inboxBulkArchiveHandler(req({ items: [] }), USER);
    expect(res.status).toBe(400);
    expect(from).not.toHaveBeenCalled();
  });
});

describe("soft deadline", () => {
  it("flushes remaining items as error when the loop exceeds the deadline", async () => {
    seedInboxRow(U1);
    seedInboxRow(U2);
    seedInboxRow(U3);
    const base = Date.now();
    const now = vi.spyOn(Date, "now");
    // First iteration within budget; the deadline trips after the first
    // dispatch — remaining items flush as error without further RPC calls.
    now
      .mockReturnValueOnce(base) // deadline computation
      .mockReturnValueOnce(base) // item 1 check
      .mockReturnValue(base + 61_000); // all later checks → expired
    rpc.mockResolvedValue({ error: null });
    const res = await inboxBulkArchiveHandler(
      req({
        items: [
          { kind: "inbox", id: U1 },
          { kind: "inbox", id: U2 },
          { kind: "inbox", id: U3 },
        ],
      }),
      USER,
    );
    now.mockRestore();
    expect(res.status).toBe(200);
    const body = await outcomes(res);
    expect(body.results.map((r) => r.outcome)).toEqual([
      "archived",
      "error",
      "error",
    ]);
    expect(rpc).toHaveBeenCalledTimes(1);
  });
});
