/**
 * #4672 task 3.1: the inbox row and the nav badge for `approval_required` rows (wireframe 06), plus the GET /api/inbox
 * enrichment that gives the row its text and expiry chip from the request itself.
 */
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, fireEvent, render, screen } from "@testing-library/react";
import { countOutstandingActionRequired, mergeAndRank, type InboxItemRowData } from "@/lib/inbox-severity";
import { canonicalizeAction, computeActionHash } from "@/server/approval/canonical";
import { enrichApprovalInboxRows } from "@/server/approval/inbox-enrich";
import { APPROVAL_ID, CONVERSATION_ID, SAMPLES, TOOLS, WORKSPACE_ID } from "./fixtures";

const mockPush = vi.fn();
vi.mock("next/navigation", () => ({ useRouter: () => ({ push: mockPush }) }));

const reportOp = vi.fn();
vi.mock("@/server/approval/ops", async (orig) => ({
  ...(await orig<typeof import("@/server/approval/ops")>()),
  reportApprovalOp: (...a: unknown[]) => reportOp(...a),
}));

import { InboxItemRow } from "@/components/inbox/inbox-item-row";

const STATIC_TITLE = "An action needs your approval";
const row = (over: Partial<InboxItemRowData> = {}): InboxItemRowData => ({
  id: "11111111-1111-4111-8111-111111111111",
  severity: "action_required",
  source: "approval_required",
  title: STATIC_TITLE,
  source_ref: { approvalId: APPROVAL_ID, conversationId: CONVERSATION_ID },
  status: "unread",
  created_at: "2026-10-28T10:00:00.000Z",
  read_at: null,
  acted_at: null,
  archived_at: null,
  ...over,
});

beforeEach(() => {
  mockPush.mockClear();
  reportOp.mockClear();
  global.fetch = vi.fn().mockResolvedValue({ ok: true, json: async () => ({ ok: true }) }) as unknown as typeof fetch;
});
afterEach(cleanup);

describe("nav badge count (shared countOutstandingActionRequired)", () => {
  it("a pending approval row counts, a decided one (acted) and an expired one (FYI) do not", () => {
    const pending = row();
    const decided = row({ id: "22222222-2222-4222-8222-222222222222", acted_at: "2026-10-28T10:05:00Z", status: "read" });
    const expired = row({ id: "33333333-3333-4333-8333-333333333333", severity: "attention" });
    expect(countOutstandingActionRequired(mergeAndRank([pending, decided, expired], []))).toBe(1);
  });
});

describe("InboxItemRow for approval_required", () => {
  const pendingInfo = { status: "pending" as const, expiresAt: new Date(Date.now() + 38 * 60_000 + 30_000).toISOString() };

  it("navigates to the landing page built from the approval id", () => {
    render(<InboxItemRow item={row({ title: "Approval needed: send email to a@example.test", approval: pendingInfo })} />);
    fireEvent.click(screen.getByRole("button", { name: /approval needed/i }));
    expect(mockPush).toHaveBeenCalledWith(`/dashboard/approvals/${APPROVAL_ID}`);
  });

  it("shows the expiry chip and the open-to-decide line, and NO Approve or Deny on the row", () => {
    render(<InboxItemRow item={row({ approval: pendingInfo })} />);
    expect(screen.getByTestId("approval-row-expiry").textContent).toMatch(/^Expires in 3[78]m$/);
    expect(screen.getByText("Open to see the exact action and decide")).toBeTruthy();
    expect(screen.queryByRole("button", { name: /^(approve|deny)$/i })).toBeNull();
  });

  it("an un-acted approval row can be neither marked done nor archived (it leaves NEEDS YOU only when decided or expired)", () => {
    render(<InboxItemRow item={row({ approval: pendingInfo })} />);
    expect(screen.queryByRole("button", { name: "Mark done" })).toBeNull();
    expect(screen.queryByRole("button", { name: "Archive item" })).toBeNull();
  });

  it("an expired (FYI) row says the request ran nothing and can be archived", () => {
    render(
      <InboxItemRow
        item={row({ severity: "attention", title: "Approval expired: send email to a@example.test. This request ran nothing.", approval: { status: "expired", expiresAt: "2026-10-28T10:00:00Z" } })}
      />,
    );
    expect(screen.getByText(/This request ran nothing\. Saved for your agent/)).toBeTruthy();
    expect(screen.getByRole("button", { name: "Archive item" })).toBeTruthy();
    expect(screen.queryByTestId("approval-row-expiry")).toBeNull();
  });

  it("a decided row (acted) offers Archive again", () => {
    render(<InboxItemRow item={row({ acted_at: "2026-10-28T10:05:00Z", status: "read", approval: { status: "approved", expiresAt: "2026-10-29T10:00:00Z" } })} />);
    expect(screen.getByRole("button", { name: "Archive item" })).toBeTruthy();
  });

  it("other sources keep their Mark done and Archive controls (no regression)", () => {
    render(<InboxItemRow item={row({ source: "system", source_ref: null, title: "billing failed" })} />);
    expect(screen.getByRole("button", { name: "Mark done" })).toBeTruthy();
  });

  it("an approval row title longer than the sanitizer's default 200-character cap is shown in full; other rows are still capped", () => {
    const long = "Approval needed: send email to " + "a".repeat(400) + "@example.test";
    const { unmount } = render(<InboxItemRow item={row({ title: long, approval: pendingInfo })} />);
    expect(document.body.textContent).toContain(long);
    unmount();
    render(<InboxItemRow item={row({ source: "system", source_ref: null, title: "b".repeat(400) })} />);
    expect(document.body.textContent).not.toContain("b".repeat(201));
  });

  it("renders the title as plain text (the row text comes from the server, never markup)", () => {
    render(<InboxItemRow item={row({ title: "Approval needed: <b>x</b>" })} />);
    expect(document.querySelector("b")).toBeNull();
  });

  it("an approval row title makes an invisible direction override visible instead of dropping it silently", () => {
    const title = "Approval needed: send email to ok@example.test" + String.fromCharCode(0x202e) + "txt.evil";
    render(<InboxItemRow item={row({ title, approval: pendingInfo })} />);
    expect(document.body.textContent).toContain("<U+202E>");
  });

  it("a malformed approval id builds no deep link (one shared UUID check)", () => {
    render(<InboxItemRow item={row({ source_ref: { approvalId: "../x" }, title: "Approval needed: send email" })} />);
    fireEvent.click(screen.getByText(/approval needed/i));
    expect(mockPush).not.toHaveBeenCalled();
  });
});

describe("enrichApprovalInboxRows (GET /api/inbox)", () => {
  const s = SAMPLES[TOOLS.emailSend];
  const action = canonicalizeAction(TOOLS.emailSend, s.input, s.server);
  const hash = computeActionHash({ toolName: TOOLS.emailSend, workspaceId: WORKSPACE_ID, conversationId: CONVERSATION_ID, action });
  const stored = (over: Record<string, unknown> = {}) => ({
    id: APPROVAL_ID,
    workspace_id: WORKSPACE_ID,
    conversation_id: CONVERSATION_ID,
    tool_name: TOOLS.emailSend,
    action_sha256: hash,
    status: "pending",
    expires_at: "2026-10-29T10:00:00Z",
    created_at: "2026-10-28T10:00:00Z",
    decided_at: null,
    decided_by: null,
    consumed_at: null,
    revoked_at: null,
    canonical_action: action,
    ...over,
  });
  const client = (data: unknown, error: unknown = null) => {
    const inFn = vi.fn(async () => ({ data, error }));
    return { c: { from: vi.fn(() => ({ select: vi.fn(() => ({ in: inFn })) })) }, inFn };
  };

  it("names the action in full from the stored canonical object and adds the expiry facts", async () => {
    const { c } = client([stored()]);
    const [out] = await enrichApprovalInboxRows(c, [row()]);
    expect(out.title).toBe(`Approval needed: send email to ${String(s.input.to)}, subject “${String(s.input.subject)}”`);
    expect(out.approval).toEqual({ status: "pending", expiresAt: "2026-10-29T10:00:00Z" });
  });

  it("states per request status: expired says the request ran nothing; approved-then-expired says the agent never asked again", async () => {
    const [a] = await enrichApprovalInboxRows(client([stored({ status: "expired" })]).c, [row()]);
    expect(a.title.endsWith("This request ran nothing.")).toBe(true);
    expect(a.title.startsWith("Approval expired: ")).toBe(true);
    const [b] = await enrichApprovalInboxRows(client([stored({ status: "expired", decided_at: "2026-10-28T11:00:00Z" })]).c, [row()]);
    expect(b.title.startsWith("You approved this, but your agent never asked again: ")).toBe(true);
  });

  it("a revoked row (rejected with revoked_at) reads 'You revoked', a plain denial reads 'You denied'", async () => {
    const [rev] = await enrichApprovalInboxRows(
      client([stored({ status: "rejected", decided_at: "2026-10-28T11:00:00Z", revoked_at: "2026-10-28T11:30:00Z" })]).c,
      [row()],
    );
    expect(rev.title.startsWith("You revoked: send email to ")).toBe(true);
    const [den] = await enrichApprovalInboxRows(client([stored({ status: "rejected", decided_at: "2026-10-28T11:00:00Z" })]).c, [row()]);
    expect(den.title.startsWith("You denied: send email to ")).toBe(true);
  });

  it("keeps the static title when the stored text no longer verifies against the bound hash", async () => {
    const tampered = structuredClone(action) as unknown as { fields: Record<string, unknown> };
    tampered.fields.to = "someone.else@example.test";
    const [out] = await enrichApprovalInboxRows(client([stored({ canonical_action: tampered })]).c, [row()]);
    expect(out.title).toBe(STATIC_TITLE);
  });

  it("keeps the static title for a scrubbed row, and for a row the viewer cannot read (RLS returns nothing)", async () => {
    const [scrubbed] = await enrichApprovalInboxRows(client([stored({ canonical_action: null })]).c, [row()]);
    expect(scrubbed.title).toBe(STATIC_TITLE);
    const [hidden] = await enrichApprovalInboxRows(client([]).c, [row()]);
    expect(hidden.title).toBe(STATIC_TITLE);
    expect(hidden.approval).toBeUndefined();
  });

  it("a failed read leaves every row untouched and reports its own op", async () => {
    const r = row();
    const out = await enrichApprovalInboxRows(client(null, { message: "boom" }).c, [r]);
    expect(out).toEqual([r]);
    expect(reportOp).toHaveBeenCalledWith("inboxEnrichFailed", expect.anything(), {});
  });

  it("does no read at all when there is no approval row, and never touches other sources", async () => {
    const other = row({ source: "system", source_ref: null, title: "billing failed" });
    const { c, inFn } = client([]);
    expect(await enrichApprovalInboxRows(c, [other])).toEqual([other]);
    expect(inFn).not.toHaveBeenCalled();
  });

  it("asks only for the ids the rows point at (one batched read)", async () => {
    const { c, inFn } = client([stored()]);
    await enrichApprovalInboxRows(c, [row(), row({ id: "44444444-4444-4444-8444-444444444444" })]);
    expect(inFn).toHaveBeenCalledTimes(1);
    expect(inFn).toHaveBeenCalledWith("id", [APPROVAL_ID]);
  });
});
