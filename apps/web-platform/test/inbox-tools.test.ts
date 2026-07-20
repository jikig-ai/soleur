import { describe, expect, it, vi, beforeEach } from "vitest";
import type { EmailTriageItem } from "@/components/inbox/email-triage-row";
import type { InboxItemRowData } from "@/lib/inbox-severity";

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

const fetchInboxSources = vi.fn();
vi.mock("@/server/inbox-sources", () => ({
  fetchInboxSources: (...args: unknown[]) => fetchInboxSources(...args),
}));

const reportSilentFallback = vi.fn();
vi.mock("@/server/observability", () => ({
  reportSilentFallback: (...args: unknown[]) => reportSilentFallback(...args),
}));

import { buildInboxTools } from "@/server/inbox-tools";

type ToolStub = {
  name: string;
  handler: (args: { status?: "archived" }) => Promise<{
    content: Array<{ type: "text"; text: string }>;
    isError?: true;
  }>;
};

function getListTool(userId = "u1"): ToolStub {
  const t = buildInboxTools({ userId }).find(
    (x) => (x as unknown as ToolStub).name === "inbox_list",
  );
  if (!t) throw new Error("inbox_list not found");
  return t as unknown as ToolStub;
}

const STATUTORY: EmailTriageItem = {
  id: "stat",
  message_id: null,
  sender: "regulator@example.gov",
  subject: "DSAR",
  summary: null,
  mail_class: null,
  statutory_class: "dsar",
  rule_id: null,
  status: "new",
  status_changed_at: null,
  acknowledged_at: null,
  received_at: "2026-06-01T00:00:00.000Z",
  created_at: "2026-06-01T00:00:00.000Z",
};

const NATIVE: InboxItemRowData = {
  id: "native",
  severity: "info",
  source: "task_completed",
  title: "Chief Legal Officer finished",
  source_ref: { conversationId: "c1" },
  status: "unread",
  created_at: "2026-07-04T00:00:00.000Z",
  read_at: null,
  acted_at: null,
  archived_at: null,
};

describe("inbox_list agent tool (agent-native parity)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    getFreshTenantClient.mockResolvedValue({});
    fetchInboxSources.mockResolvedValue({
      inboxRows: [NATIVE],
      emailRows: [STATUTORY],
    });
  });

  it("returns the untrusted envelope then the merged, ranked payload", async () => {
    const res = await getListTool().handler({});
    expect(res.isError).toBeUndefined();
    expect(res.content).toHaveLength(2);
    expect(res.content[0].text).toMatch(/UNTRUSTED/);
    const items = JSON.parse(res.content[1].text) as Array<{ id: string; pinned: boolean }>;
    // Statutory pinned first (same order the operator sees).
    expect(items[0].id).toBe("stat");
    expect(items[0].pinned).toBe(true);
    expect(items.map((i) => i.id)).toContain("native");
  });

  it("passes archived through to the shared fetch helper", async () => {
    await getListTool().handler({ status: "archived" });
    expect(fetchInboxSources).toHaveBeenCalledWith(expect.anything(), {
      archived: true,
    });
  });

  it("mirrors + returns a tool error on query failure", async () => {
    fetchInboxSources.mockRejectedValueOnce(new Error("boom"));
    const res = await getListTool().handler({});
    expect(res.isError).toBe(true);
    expect(reportSilentFallback).toHaveBeenCalled();
  });
});
