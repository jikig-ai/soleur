/**
 * #4672 task 3.2: the gate's `onRequested` hook sends the generic push for a NEW request (the split half of
 * notifyInboxItem), finds the RPC-written inbox row by its dedup key, and reports (through the gate's own
 * approval-notify-failed op) when nothing reached the Owner. A re-ask never pushes twice.
 */
import { beforeEach, describe, expect, it, vi } from "vitest";
import { APPROVAL_ID, USER_ID, WORKSPACE_ID } from "./fixtures";

const h = vi.hoisted(() => ({
  dispatch: vi.fn(),
  inboxRow: { value: { data: { id: "55555555-5555-4555-8555-555555555555" }, error: null } as { data: unknown; error: unknown } },
  filters: [] as Array<[string, string]>,
}));

vi.mock("@/server/notifications", () => ({ dispatchInboxPush: (...a: unknown[]) => h.dispatch(...a) }));
vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => ({
    from: (table: string) => {
      const c: Record<string, unknown> = {};
      c.select = () => c;
      c.eq = (col: string, val: string) => {
        h.filters.push([`${table}.${col}`, val]);
        return c;
      };
      c.maybeSingle = async () => h.inboxRow.value;
      return c;
    },
  }),
}));

import { createApprovalGateDeps } from "@/server/approval/gate";
import { notifyApprovalRequested } from "@/server/approval/notify";

const deps = (notifyRequested?: (id: string) => Promise<boolean>) =>
  createApprovalGateDeps({
    userId: USER_ID,
    workspaceId: WORKSPACE_ID,
    repoSlug: "acme/repo",
    workspacePath: "/tmp/ws",
    isEnabled: async () => true,
    serviceClient: () => ({ rpc: async () => ({ data: null, error: null }) }),
    notifyRequested,
  });

beforeEach(() => {
  h.dispatch.mockReset().mockResolvedValue(true);
  h.filters.length = 0;
  h.inboxRow.value = { data: { id: "55555555-5555-4555-8555-555555555555" }, error: null };
});

describe("createApprovalGateDeps.onRequested", () => {
  it("pushes for a newly created request", async () => {
    const notify = vi.fn(async () => true);
    await deps(notify).onRequested!({ approvalId: APPROVAL_ID, created: true });
    expect(notify).toHaveBeenCalledWith(APPROVAL_ID);
  });

  it("a re-ask that found the existing request does NOT push again", async () => {
    const notify = vi.fn(async () => true);
    await deps(notify).onRequested!({ approvalId: APPROVAL_ID, created: false });
    expect(notify).not.toHaveBeenCalled();
  });

  it("throws when nothing reached the Owner, so the gate reports approval-notify-failed", async () => {
    await expect(deps(async () => false).onRequested!({ approvalId: APPROVAL_ID, created: true })).rejects.toThrow();
  });
});

describe("notifyApprovalRequested", () => {
  it("finds the RPC-written inbox row by source and dedup key (the approval id) and dispatches that row", async () => {
    expect(await notifyApprovalRequested(APPROVAL_ID)).toBe(true);
    expect(h.filters).toEqual([
      ["inbox_item.source", "approval_required"],
      ["inbox_item.dedup_key", APPROVAL_ID],
    ]);
    expect(h.dispatch).toHaveBeenCalledWith("55555555-5555-4555-8555-555555555555");
  });

  it("no inbox row (or a read error) means no dispatch and false", async () => {
    h.inboxRow.value = { data: null, error: null };
    expect(await notifyApprovalRequested(APPROVAL_ID)).toBe(false);
    h.inboxRow.value = { data: { id: "x" }, error: { message: "boom" } };
    expect(await notifyApprovalRequested(APPROVAL_ID)).toBe(false);
    expect(h.dispatch).not.toHaveBeenCalled();
  });

  it("reports the dispatch result as is", async () => {
    h.dispatch.mockResolvedValue(false);
    expect(await notifyApprovalRequested(APPROVAL_ID)).toBe(false);
  });
});
