/**
 * #4672: the push and email for an approval request are GENERIC for every gated tool. Nothing from the stored
 * row title, the request or the agent can reach a lock screen or an inbox preview (privacy notice scope #8532), and the
 * dispatch half is split from the insert (`dispatchInboxPush`) so the RPC-written row is pushed after the RPC returns.
 */
import { beforeEach, describe, expect, it, vi } from "vitest";
import { APPROVAL_ID, CONVERSATION_ID, USER_ID, WORKSPACE_ID } from "./fixtures";

const h = vi.hoisted(() => ({
  sendNotification: vi.fn(),
  resendSend: vi.fn(),
  tables: {} as Record<string, { data: unknown; error?: unknown }>,
  subs: { value: [{ id: "sub-1", endpoint: "https://push.example.test/1", p256dh: "k", auth: "a" }] as unknown[] },
  owners: { value: [{ user_id: "00000000-0000-4000-8000-0000000000a1" }] as unknown[] },
  inserts: [] as Array<Record<string, unknown>>,
  getUserById: vi.fn(),
  report: vi.fn(),
  capture: vi.fn(),
}));

vi.mock("web-push", () => ({
  default: { setVapidDetails: vi.fn(), sendNotification: h.sendNotification },
  setVapidDetails: vi.fn(),
  sendNotification: h.sendNotification,
}));
vi.mock("resend", () => ({
  Resend: vi.fn().mockImplementation(function (this: Record<string, unknown>) {
    this.emails = { send: h.resendSend };
  }),
}));
vi.mock("@sentry/nextjs", () => ({ captureException: h.capture, captureMessage: vi.fn() }));
vi.mock("@/server/logger", () => ({
  default: { info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() },
  createChildLogger: () => ({ info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() }),
}));
vi.mock("@/server/observability", async (orig) => ({
  ...(await orig<typeof import("@/server/observability")>()),
  reportSilentFallback: (...a: unknown[]) => h.report(...a),
}));
vi.mock("@/lib/supabase/service", () => ({
  serverUrl: () => "https://test.supabase.co",
  createServiceClient: () => ({
    auth: { admin: { getUserById: h.getUserById } },
    from: (table: string) => {
      // Production forbids this read (migration 180 REVOKEs every privilege on approval_request from service_role), so a
      // fake that quietly answers it would only hide a regression. Throw instead.
      if (table === "approval_request") throw new Error("service role must not read approval_request");
      const res = () => h.tables[table] ?? { data: null, error: null };
      const chain: Record<string, unknown> = {};
      const self = () => chain;
      for (const m of ["select", "eq", "update", "in", "delete", "order", "limit"]) chain[m] = self;
      chain.maybeSingle = async () => res();
      chain.single = async () => res();
      chain.insert = (row: Record<string, unknown>) => {
        h.inserts.push(row);
        return { select: () => ({ single: async () => ({ data: { id: "inserted-id" }, error: null }) }) };
      };
      // `await supabase.from(t).select().eq()` (push subscriptions / owners) resolves through then()
      chain.then = (ok: (v: unknown) => unknown) => {
        if (table === "push_subscriptions") return Promise.resolve({ data: h.subs.value, error: null }).then(ok);
        if (table === "workspace_members") return Promise.resolve({ data: h.owners.value, error: null }).then(ok);
        return Promise.resolve(res()).then(ok);
      };
      return chain;
    },
  }),
}));

import { dispatchInboxPush, notifyInboxItem } from "@/server/notifications";

const INBOX_ID = "55555555-5555-4555-8555-555555555555";
const SECRET_TITLE = "Approval needed: send email to maria.keller@acme-logistics.example, subject “Q4 pricing”";

function inboxRow(over: Record<string, unknown> = {}) {
  return {
    id: INBOX_ID,
    workspace_id: WORKSPACE_ID,
    user_id: null,
    severity: "action_required",
    source: "approval_required",
    title: SECRET_TITLE,
    source_ref: { approvalId: APPROVAL_ID, conversationId: CONVERSATION_ID },
    ...over,
  };
}

const pushBody = () => JSON.parse(h.sendNotification.mock.calls[0][1] as string);
const emailArg = () => h.resendSend.mock.calls[0][0] as { subject: string; html: string; to: string[] };

beforeEach(() => {
  vi.stubEnv("VAPID_PUBLIC_KEY", "pub");
  vi.stubEnv("VAPID_PRIVATE_KEY", "priv");
  vi.stubEnv("RESEND_API_KEY", "re_test");
  vi.stubEnv("NEXT_PUBLIC_APP_URL", "https://test.example");
  h.sendNotification.mockReset().mockResolvedValue({});
  h.resendSend.mockReset().mockResolvedValue({ error: null });
  h.getUserById.mockReset().mockResolvedValue({ data: { user: { email: "owner@example.test", user_metadata: { full_name: "Dana Whitfield" } } } });
  h.report.mockReset();
  h.capture.mockReset();
  h.inserts.length = 0;
  h.subs.value = [{ id: "sub-1", endpoint: "https://push.example.test/1", p256dh: "k", auth: "a" }];
  h.owners.value = [{ user_id: "00000000-0000-4000-8000-0000000000a1" }];
  h.tables = {
    inbox_item: { data: inboxRow() },
    workspaces: { data: { name: "Jikigai" } },
  };
});

describe("dispatchInboxPush: the push", () => {
  it("sends the fixed copy-deck strings and links to the landing page by approval id", async () => {
    expect(await dispatchInboxPush(INBOX_ID)).toBe(true);
    const b = pushBody();
    expect(b.title).toBe("Approval needed");
    expect(b.body).toBe("A request needs your decision. Open to review.");
    expect(b.data.url).toBe(`https://test.example/dashboard/approvals/${APPROVAL_ID}`);
    expect(b.data.inboxItemId).toBe(INBOX_ID);
  });

  it("is content-free: the stored row title (which names the action) never reaches the payload, whatever it says", async () => {
    await dispatchInboxPush(INBOX_ID);
    const raw = JSON.stringify(pushBody());
    for (const leaked of ["maria.keller", "acme-logistics", "Q4 pricing", "send email", SECRET_TITLE]) expect(raw).not.toContain(leaked);
  });

  it("is the same text for all eight action types (it never reads the request)", async () => {
    const seen = new Set<string>();
    for (const tool of ["email_send", "email_reply", "email_suppress", "github_push_branch", "create_pull_request", "github_trigger_workflow", "kb_share_create", "workspace_set_autonomous"]) {
      h.sendNotification.mockClear();
      h.tables.inbox_item = { data: inboxRow({ title: `Approval needed: ${tool} something specific` }) };
      await dispatchInboxPush(INBOX_ID);
      const b = pushBody();
      seen.add(`${b.title}|${b.body}`);
    }
    expect(seen.size).toBe(1);
  });

  it("the expired kind uses the expired copy", async () => {
    await dispatchInboxPush(INBOX_ID, { kind: "expired" });
    expect(pushBody().title).toBe("Approval request expired");
    expect(pushBody().body).toBe("A request expired before it was decided. Nothing was run.");
  });

  it("a broadcast row (user_id null) goes to every workspace Owner; a targeted row goes to that user", async () => {
    h.owners.value = [{ user_id: "00000000-0000-4000-8000-0000000000a1" }, { user_id: "00000000-0000-4000-8000-0000000000a2" }];
    await dispatchInboxPush(INBOX_ID);
    expect(h.sendNotification).toHaveBeenCalledTimes(2);
    h.sendNotification.mockClear();
    h.tables.inbox_item = { data: inboxRow({ user_id: USER_ID }) };
    await dispatchInboxPush(INBOX_ID);
    expect(h.sendNotification).toHaveBeenCalledTimes(1);
  });
});

describe("dispatchInboxPush: the email fallback", () => {
  beforeEach(() => {
    h.subs.value = []; // no device registered: email is the only channel
  });

  it("sends the fixed subject and body; interpolates only first name, workspace name and the expiry", async () => {
    expect(await dispatchInboxPush(INBOX_ID, { approvalExpiresAt: "2026-10-29T10:42:00Z" })).toBe(true);
    const e = emailArg();
    expect(e.subject).toBe("Soleur: a request needs your decision");
    expect(e.html).toContain("Hi Dana,");
    expect(e.html).toContain("A request from one of your agents in Jikigai needs your decision.");
    expect(e.html).toContain("Thu 29 Oct, 10:42 UTC");
    expect(e.html).toContain("Open request");
    expect(e.html).toContain(`https://test.example/dashboard/approvals/${APPROVAL_ID}`);
    expect(e.html).toContain("Request details are left out of this email on purpose.");
  });

  it("is content-free: nothing from the row title or the request reaches the subject or the body", async () => {
    await dispatchInboxPush(INBOX_ID);
    const raw = JSON.stringify(emailArg());
    for (const leaked of ["maria.keller", "acme-logistics", "Q4 pricing", "send email to"]) expect(raw).not.toContain(leaked);
  });

  it("escapes an attacker-controlled workspace name and first name at the HTML sink", async () => {
    h.tables.workspaces = { data: { name: `<script>alert(1)</script> & Co` } };
    h.getUserById.mockResolvedValue({ data: { user: { email: "owner@example.test", user_metadata: { given_name: "<img src=x onerror=1>" } } } });
    await dispatchInboxPush(INBOX_ID);
    const html = emailArg().html;
    expect(html).not.toContain("<script>");
    expect(html).not.toContain("<img src=x");
    expect(html).toContain("&lt;script&gt;");
  });

  it("degrades to 'Hi,' and 'your workspace' when the names are unavailable, and still sends", async () => {
    h.tables.workspaces = { data: null };
    h.getUserById.mockResolvedValue({ data: { user: { email: "owner@example.test", user_metadata: {} } } });
    await dispatchInboxPush(INBOX_ID);
    expect(emailArg().html).toContain("Hi,");
    expect(emailArg().html).toContain("in your workspace needs your decision");
  });

  it("the expired kind uses the expired subject and body", async () => {
    await dispatchInboxPush(INBOX_ID, { kind: "expired" });
    expect(emailArg().subject).toBe("Soleur: a request expired and nothing was run");
    expect(emailArg().html).toContain("Nothing was run. If you still want it done, ask your agent again in Soleur.");
  });
});

describe("dispatchInboxPush: no approval_request table read (R2)", () => {
  it("succeeds while the service client throws on from('approval_request'), and carries the PASSED expiry", async () => {
    h.subs.value = [];
    expect(await dispatchInboxPush(INBOX_ID, { approvalExpiresAt: "2026-10-29T10:42:00Z" })).toBe(true);
    expect(emailArg().html).toContain("Thu 29 Oct, 10:42 UTC");
  });

  it("without a passed expiry the copy has no date (it is never looked up)", async () => {
    h.subs.value = [];
    expect(await dispatchInboxPush(INBOX_ID)).toBe(true);
    expect(emailArg().html).not.toContain("10:42 UTC");
  });
});

describe("dispatchInboxPush: contract of the split", () => {
  it("returns false (never throws) when the row cannot be read, and reports it", async () => {
    h.tables.inbox_item = { data: null, error: { message: "nope" } };
    expect(await dispatchInboxPush(INBOX_ID)).toBe(false);
    expect(h.report).toHaveBeenCalledWith(expect.anything(), expect.objectContaining({ op: "inbox-item-dispatch-lookup" }));
  });

  it("keeps the deep-link guard: a row with no resolvable target is not pushed and is reported", async () => {
    h.tables.inbox_item = { data: inboxRow({ source_ref: { approvalId: "../../admin" } }) };
    expect(await dispatchInboxPush(INBOX_ID)).toBe(false);
    expect(h.sendNotification).not.toHaveBeenCalled();
    expect(h.report).toHaveBeenCalledWith(null, expect.objectContaining({ op: "inbox-item-bad-deeplink" }));
  });

  it("a delivery failure on an action_required row is mirrored to Sentry through the existing op and returns false", async () => {
    h.subs.value = [];
    h.getUserById.mockResolvedValue({ data: null, error: { message: "no user" } });
    expect(await dispatchInboxPush(INBOX_ID)).toBe(false);
    expect(h.capture).toHaveBeenCalled();
    expect((h.capture.mock.calls[0][1] as { tags: { op: string } }).tags.op).toBe("notify-inbox-action-required");
  });

  it("non-approval rows keep the existing generic inbox copy (no regression)", async () => {
    h.tables.inbox_item = { data: inboxRow({ source: "system", severity: "info", title: "Weekly summary ready", source_ref: null }) };
    await dispatchInboxPush(INBOX_ID);
    const b = pushBody();
    expect(b.title).toBe("Weekly summary ready");
    expect(b.body).toBe("New update in your Soleur inbox.");
  });
});

describe("notifyInboxItem accepts the widened source", () => {
  it("inserts an approval_required row (the union is widened, the insert is unchanged)", async () => {
    const id = await notifyInboxItem({
      workspaceId: WORKSPACE_ID,
      userId: USER_ID,
      severity: "action_required",
      source: "approval_required",
      title: "An action needs your approval",
      sourceRef: { approvalId: APPROVAL_ID },
      deepLinkPath: `/dashboard/approvals/${APPROVAL_ID}`,
      dispatch: false,
    });
    expect(id).toBe("inserted-id");
    expect(h.inserts[0]).toMatchObject({ source: "approval_required" });
  });
});
