/**
 * #4672: the gate's `onRequested` hook sends the generic push for a NEW request (the split half of
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
import { ExecutionGrants } from "@/server/approval/grants";
import { notifyApprovalExpired, notifyApprovalRequested } from "@/server/approval/notify";

const EXPIRES_AT = "2026-10-29T10:42:00Z";

const deps = (notifyRequested?: (id: string, workspaceId: string, expiresAt: string | null) => Promise<boolean>) =>
  createApprovalGateDeps({
    userId: USER_ID,
    workspaceId: WORKSPACE_ID,
    repoSlug: "acme/repo",
    workspacePath: "/tmp/ws",
    grants: new ExecutionGrants(),
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
    await deps(notify).onRequested!({ approvalId: APPROVAL_ID, created: true, notify: true, expiresAt: EXPIRES_AT });
    expect(notify).toHaveBeenCalledWith(APPROVAL_ID, WORKSPACE_ID, EXPIRES_AT);
  });

  it("a new request inside the workspace's coalescing window (notify=false) is not pushed", async () => {
    const notify = vi.fn(async () => true);
    await deps(notify).onRequested!({ approvalId: APPROVAL_ID, created: true, notify: false, expiresAt: EXPIRES_AT });
    expect(notify).not.toHaveBeenCalled();
  });

  it("a re-ask that found the existing request does NOT push again", async () => {
    const notify = vi.fn(async () => true);
    await deps(notify).onRequested!({ approvalId: APPROVAL_ID, created: false, notify: true, expiresAt: EXPIRES_AT });
    expect(notify).not.toHaveBeenCalled();
  });

  it("throws when nothing reached the Owner, so the gate reports approval-notify-failed", async () => {
    await expect(
      deps(async () => false).onRequested!({ approvalId: APPROVAL_ID, created: true, notify: true, expiresAt: EXPIRES_AT }),
    ).rejects.toThrow();
  });
});

describe("notifyApprovalRequested", () => {
  it("finds the RPC-written inbox row by (workspace_id, source, dedup_key = the approval id) and dispatches that row with the expiry", async () => {
    expect(await notifyApprovalRequested(APPROVAL_ID, WORKSPACE_ID, EXPIRES_AT)).toBe(true);
    expect(h.filters).toEqual([
      ["inbox_item.workspace_id", WORKSPACE_ID],
      ["inbox_item.source", "approval_required"],
      ["inbox_item.dedup_key", APPROVAL_ID],
    ]);
    expect(h.dispatch).toHaveBeenCalledWith("55555555-5555-4555-8555-555555555555", { kind: "requested", approvalExpiresAt: EXPIRES_AT });
  });

  it("the expired kind looks the row up by workspace too and carries no date", async () => {
    expect(await notifyApprovalExpired(APPROVAL_ID, WORKSPACE_ID)).toBe(true);
    expect(h.filters[0]).toEqual(["inbox_item.workspace_id", WORKSPACE_ID]);
    expect(h.dispatch).toHaveBeenCalledWith("55555555-5555-4555-8555-555555555555", { kind: "expired", approvalExpiresAt: null });
  });

  it("no inbox row (or a read error) means no dispatch and false", async () => {
    h.inboxRow.value = { data: null, error: null };
    expect(await notifyApprovalRequested(APPROVAL_ID, WORKSPACE_ID, EXPIRES_AT)).toBe(false);
    h.inboxRow.value = { data: { id: "x" }, error: { message: "boom" } };
    expect(await notifyApprovalRequested(APPROVAL_ID, WORKSPACE_ID, EXPIRES_AT)).toBe(false);
    expect(h.dispatch).not.toHaveBeenCalled();
  });

  it("reports the dispatch result as is", async () => {
    h.dispatch.mockResolvedValue(false);
    expect(await notifyApprovalRequested(APPROVAL_ID, WORKSPACE_ID, EXPIRES_AT)).toBe(false);
  });
});
