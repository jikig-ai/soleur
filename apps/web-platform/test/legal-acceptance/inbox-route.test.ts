/**
 * GET /api/inbox with the founder's legal rows (CTO ruling T7, 2026-11-08; Ref #12197).
 *   - the legal rows are derived only for the ACTIVE view (the archived view never carries them);
 *   - a legal read failure still answers 200 with the other items, and reports pageReadFailed (the legal rows are omitted);
 *   - a non-founder / flag-off user gets no legal row and no legal_acceptance read.
 */
import { beforeEach, describe, expect, it, vi } from "vitest";

vi.hoisted(() => {
  process.env.SENTRY_USERID_PEPPER = "test-pepper";
});

const FOUNDER = "00000000-0000-4000-8000-0000000000aa";
const KEY = "founder-acceptance-record";

const h = vi.hoisted(() => ({
  enabled: { value: true },
  reports: [] as unknown[][],
  reads: [] as string[],
  legalResult: { value: { data: [] as unknown, error: null as unknown } },
}));

vi.mock("@/server/with-user-rate-limit", () => ({
  withUserRateLimit: (handler: (req: Request, user: { id: string }) => Promise<Response>) => (req: Request) =>
    handler(req, { id: FOUNDER }),
}));
vi.mock("@/lib/supabase/server", () => ({
  createClient: async () => ({
    from: (t: string) => {
      h.reads.push(t);
      const b: Record<string, unknown> = {};
      b.select = () => b;
      b.eq = () => b;
      b.in = () => Promise.resolve(h.legalResult.value);
      return b;
    },
  }),
}));
vi.mock("@/server/inbox-sources", () => ({
  fetchInboxSources: async (_s: unknown, o: { archived: boolean }) => ({ inboxRows: [], emailRows: [], archived: o.archived }),
}));
vi.mock("@/server/approval/inbox-enrich", () => ({ enrichApprovalInboxRows: async (_s: unknown, rows: unknown[]) => rows }));
vi.mock("@/server/observability", () => ({ reportSilentFallback: vi.fn() }));
vi.mock("@/server/legal-acceptance/surface", () => ({ isLegalSurfaceEnabled: async () => h.enabled.value }));
vi.mock("@/server/approval/ops", () => ({
  reportLegalOp: (...a: unknown[]) => {
    h.reports.push(a);
  },
}));

import { GET } from "@/app/api/inbox/route";

const get = (qs = "") => GET(new Request(`http://localhost/api/inbox${qs}`));

beforeEach(() => {
  h.enabled.value = true;
  h.reports.length = 0;
  h.reads.length = 0;
  h.legalResult.value = { data: [], error: null };
});

describe("GET /api/inbox legal rows", () => {
  it("the founder with a pending text gets a NEEDS YOU legal row in the active view", async () => {
    const res = await get();
    expect(res.status).toBe(200);
    const { items } = (await res.json()) as { items: { kind: string; id: string; severity: string; outstanding: boolean }[] };
    expect(items).toEqual([expect.objectContaining({ kind: "legal", id: KEY, severity: "action_required", outstanding: true })]);
  });

  it("the archived view never carries legal rows and never reads legal_acceptance", async () => {
    const res = await get("?status=archived");
    expect(res.status).toBe(200);
    expect(((await res.json()) as { items: unknown[] }).items).toEqual([]);
    expect(h.reads).toEqual([]);
  });

  it("a non-founder (gate closed) gets no legal row and no legal_acceptance read", async () => {
    h.enabled.value = false;
    const res = await get();
    expect(((await res.json()) as { items: unknown[] }).items).toEqual([]);
    expect(h.reads).toEqual([]);
  });

  it("a legal read failure still answers 200 with the other items and reports pageReadFailed", async () => {
    h.legalResult.value = { data: null, error: { code: "XX000" } };
    const res = await get();
    expect(res.status).toBe(200);
    expect(((await res.json()) as { items: unknown[] }).items).toEqual([]);
    expect(h.reports).toHaveLength(1);
    expect(h.reports[0][0]).toBe("pageReadFailed");
    expect(h.reports[0][2]).toMatchObject({ extra: { read: "legal_acceptance_inbox" } });
  });
});
