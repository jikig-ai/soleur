/**
 * GET /api/inbox with the founder's legal rows (CTO ruling T7, 2026-11-08; Ref #12197).
 *   - the legal rows are derived only for the ACTIVE view (the archived view never carries them);
 *   - a legal read failure still answers 200 with the other items, and reports pageReadFailed (the legal rows are omitted);
 *   - a non-founder / flag-off user gets no legal row and no legal_acceptance read;
 *   - the gate and the read are called with the AUTHENTICATED user's id (the fakes record their arguments);
 *   - the legal read starts before the other sources finish (it is concurrent with them, not after them).
 */
import { beforeEach, describe, expect, it, vi } from "vitest";

vi.hoisted(() => {
  process.env.SENTRY_USERID_PEPPER = "test-pepper";
});

const FOUNDER = "00000000-0000-4000-8000-0000000000aa";
const KEY = "founder-acceptance-record";

const h = vi.hoisted(() => ({
  user: { id: "" },
  enabled: { value: true },
  gateCalls: [] as unknown[][],
  reports: [] as unknown[][],
  reads: [] as string[],
  eq: [] as unknown[][],
  in: [] as unknown[][],
  readsWhenSourcesFinished: { value: -1 },
  inboxRows: [] as unknown[],
  emailRows: [] as unknown[],
  legalResult: { value: { data: [] as unknown, error: null as unknown } },
}));

vi.mock("@/server/with-user-rate-limit", () => ({
  withUserRateLimit: (handler: (req: Request, user: { id: string }) => Promise<Response>) => (req: Request) =>
    handler(req, { id: h.user.id }),
}));
vi.mock("@/lib/supabase/server", () => ({
  createClient: async () => ({
    from: (t: string) => {
      h.reads.push(t);
      const b: Record<string, unknown> = {};
      b.select = () => b;
      b.eq = (...a: unknown[]) => {
        h.eq.push(a);
        return b;
      };
      b.in = (...a: unknown[]) => {
        h.in.push(a);
        return Promise.resolve(h.legalResult.value);
      };
      return b;
    },
  }),
}));
vi.mock("@/server/inbox-sources", () => ({
  fetchInboxSources: async (_s: unknown, o: { archived: boolean }) => {
    // A macrotask later than the loader's first awaits: a legal read that runs concurrently has reached the store by now.
    await new Promise((r) => setTimeout(r, 0));
    h.readsWhenSourcesFinished.value = h.reads.length;
    return { inboxRows: h.inboxRows, emailRows: h.emailRows, archived: o.archived };
  },
}));
vi.mock("@/server/approval/inbox-enrich", () => ({ enrichApprovalInboxRows: async (_s: unknown, rows: unknown[]) => rows }));
vi.mock("@/server/observability", () => ({ reportSilentFallback: vi.fn() }));
vi.mock("@/server/legal-acceptance/surface", () => ({
  isLegalSurfaceEnabled: async (...a: unknown[]) => {
    h.gateCalls.push(a);
    return h.enabled.value;
  },
}));
vi.mock("@/server/approval/ops", () => ({
  reportLegalOp: (...a: unknown[]) => {
    h.reports.push(a);
  },
}));

import { GET } from "@/app/api/inbox/route";

const get = (qs = "") => GET(new Request(`http://localhost/api/inbox${qs}`));

const NATIVE = {
  id: "11111111-1111-4111-8111-111111111111",
  severity: "info",
  source: "task_completed",
  title: "Chief Legal Officer finished",
  source_ref: { conversationId: "c1" },
  status: "unread",
  created_at: "2026-07-01T10:00:00.000Z",
  read_at: null,
  acted_at: null,
  archived_at: null,
};
const STATUTORY_EMAIL = {
  id: "e-statutory",
  message_id: null,
  sender: "authority@example.com",
  subject: "subject",
  summary: null,
  mail_class: null,
  statutory_class: "dsar",
  rule_id: null,
  status: "new",
  status_changed_at: null,
  acknowledged_at: null,
  received_at: "2026-07-02T10:00:00.000Z",
  created_at: "2026-07-02T10:00:00.000Z",
};

type Item = { kind: string; id: string; severity: string; outstanding: boolean; pinned?: boolean };
const itemsOf = async (res: Response) => ((await res.json()) as { items: Item[] }).items;

beforeEach(() => {
  h.user.id = FOUNDER;
  h.enabled.value = true;
  h.gateCalls.length = 0;
  h.reports.length = 0;
  h.reads.length = 0;
  h.eq.length = 0;
  h.in.length = 0;
  h.readsWhenSourcesFinished.value = -1;
  h.inboxRows = [NATIVE];
  h.emailRows = [STATUTORY_EMAIL];
  h.legalResult.value = { data: [], error: null };
});

describe("GET /api/inbox legal rows", () => {
  it("the founder with a pending text gets a NEEDS YOU legal row in the active view, merged with the other items (statutory pin, legal NEEDS YOU, then FYI)", async () => {
    const res = await get();
    expect(res.status).toBe(200);
    const items = await itemsOf(res);
    expect(items.map((i) => [i.kind, i.id, i.severity])).toEqual([
      ["email", "e-statutory", "action_required"],
      ["legal", KEY, "action_required"],
      ["inbox", NATIVE.id, "info"],
    ]);
    expect(items[1]).toMatchObject({ outstanding: true, pinned: false });
  });

  it("the gate and the read are called with the AUTHENTICATED user's id", async () => {
    const other = "00000000-0000-4000-8000-0000000000bb";
    h.user.id = other;
    await get();
    expect(h.gateCalls).toEqual([[other]]);
    expect(h.eq).toEqual([["founder_id", other]]);
    expect(h.in).toEqual([["key", [KEY]]]);
  });

  it("the legal read runs concurrently with the other sources: it reached the store before they finished", async () => {
    await get();
    expect(h.readsWhenSourcesFinished.value).toBe(1);
    expect(h.reads).toEqual(["legal_acceptance"]);
  });

  it("the archived view never carries legal rows and never reads legal_acceptance", async () => {
    const res = await get("?status=archived");
    expect(res.status).toBe(200);
    expect((await itemsOf(res)).map((i) => i.kind)).toEqual(["email", "inbox"]);
    expect(h.reads).toEqual([]);
    expect(h.gateCalls).toEqual([]);
  });

  it("a non-founder (gate closed) gets no legal row and no legal_acceptance read, but still the other items", async () => {
    h.enabled.value = false;
    const res = await get();
    expect((await itemsOf(res)).map((i) => i.kind)).toEqual(["email", "inbox"]);
    expect(h.reads).toEqual([]);
  });

  it("a legal read failure still answers 200 with the other items and reports pageReadFailed", async () => {
    h.legalResult.value = { data: null, error: { code: "XX000" } };
    const res = await get();
    expect(res.status).toBe(200);
    expect((await itemsOf(res)).map((i) => i.kind)).toEqual(["email", "inbox"]);
    expect(h.reports).toHaveLength(1);
    expect(h.reports[0][0]).toBe("pageReadFailed");
    expect(h.reports[0][2]).toMatchObject({ extra: { read: "legal_acceptance_inbox", step: "read" } });
  });
});
