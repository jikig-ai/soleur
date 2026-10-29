/**
 * #4672 task 3.1: the away-user landing page (server component).
 *
 *   - signed out: sign-in redirect that returns to the same path; NO request read before authentication;
 *   - a missing row, a non-Owner (RLS returns no row) and a malformed id are the SAME not-found;
 *   - renders any existing row regardless of the approval-queue flag (AC1: "existing rows stay renderable");
 *   - shows the EXACT canonical text re-verified against the bound hash; a row that does not verify gets no buttons.
 */
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, render, screen } from "@testing-library/react";
import { canonicalizeAction, computeActionHash } from "@/server/approval/canonical";
import { APPROVAL_ID, CONVERSATION_ID, SAMPLES, TOOLS, USER_ID, WORKSPACE_ID } from "./fixtures";

const h = vi.hoisted(() => ({
  user: { value: { id: "00000000-0000-4000-8000-000000000007" } as { id: string } | null },
  row: { value: null as Record<string, unknown> | null },
  rowError: { value: null as unknown },
  count: { value: 1 },
  fromCalls: [] as string[],
  flag: vi.fn(),
  report: vi.fn(),
}));

class NotFound extends Error {}
class Redirect extends Error {
  constructor(public to: string) {
    super(to);
  }
}
vi.mock("next/navigation", () => ({
  notFound: () => {
    throw new NotFound("notFound");
  },
  redirect: (to: string) => {
    throw new Redirect(to);
  },
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: async () => ({
    auth: { getUser: async () => ({ data: { user: h.user.value } }) },
    from: (table: string) => {
      h.fromCalls.push(table);
      const chain = {
        select: (_c: string, opts?: { head?: boolean }) => {
          if (opts?.head) return { eq: () => ({ eq: async () => ({ count: h.count.value, error: null }) }) };
          return {
            eq: () => ({
              maybeSingle: async () =>
                table === "approval_request"
                  ? { data: h.row.value, error: h.rowError.value }
                  : { data: { title: "Q4 pallet pricing follow-ups" }, error: null },
            }),
          };
        },
      };
      return chain;
    },
  }),
}));

vi.mock("@/server/approval/flag", () => ({
  isApprovalQueueEnabled: (...a: unknown[]) => h.flag(...a),
}));

vi.mock("@/server/approval/ops", async (orig) => ({
  ...(await orig<typeof import("@/server/approval/ops")>()),
  reportApprovalOp: (...a: unknown[]) => h.report(...a),
}));

import ApprovalPage from "@/app/(dashboard)/dashboard/approvals/[id]/page";

const s = SAMPLES[TOOLS.emailSend];
const action = canonicalizeAction(TOOLS.emailSend, s.input, s.server);
const hash = computeActionHash({ toolName: TOOLS.emailSend, workspaceId: WORKSPACE_ID, conversationId: CONVERSATION_ID, action });

function stored(over: Record<string, unknown> = {}) {
  return {
    id: APPROVAL_ID,
    workspace_id: WORKSPACE_ID,
    conversation_id: CONVERSATION_ID,
    tool_name: TOOLS.emailSend,
    action_sha256: hash,
    status: "pending",
    expires_at: "2099-01-01T00:00:00Z",
    created_at: "2026-10-28T10:00:00Z",
    decided_at: null,
    decided_by: null,
    consumed_at: null,
    canonical_action: action,
    ...over,
  };
}

const run = async (id = APPROVAL_ID) => ApprovalPage({ params: Promise.resolve({ id }) });

beforeEach(() => {
  h.user.value = { id: USER_ID };
  h.row.value = stored();
  h.rowError.value = null;
  h.count.value = 1;
  h.fromCalls.length = 0;
  h.flag.mockReset();
  h.report.mockReset();
});
afterEach(cleanup);

describe("authentication", () => {
  it("signed out: redirects to sign-in carrying the SAME path, and reads no request first", async () => {
    h.user.value = null;
    await expect(run()).rejects.toMatchObject({ to: `/login?redirectTo=${encodeURIComponent(`/dashboard/approvals/${APPROVAL_ID}`)}` });
    expect(h.fromCalls).toEqual([]);
  });

  it("the carried path survives the repo's same-origin allowlist (the login form re-validates it)", async () => {
    const { safeReturnTo } = await import("@/lib/safe-return-to");
    expect(safeReturnTo(`/dashboard/approvals/${APPROVAL_ID}`)).toBe(`/dashboard/approvals/${APPROVAL_ID}`);
  });
});

describe("not found is identical for every way the viewer cannot see the request", () => {
  it("a malformed id", async () => {
    await expect(run("not-a-uuid")).rejects.toBeInstanceOf(NotFound);
    expect(h.fromCalls).toEqual([]);
  });
  it("no row visible (an unknown id, or a non-Owner whose RLS hides it)", async () => {
    h.row.value = null;
    await expect(run()).rejects.toBeInstanceOf(NotFound);
  });
});

describe("rendering", () => {
  it("shows the exact canonical action text, the countdown and Approve/Deny for a pending request", async () => {
    render(await run());
    expect(screen.getByRole("heading", { level: 1 }).textContent).toBe("Approval request");
    expect(screen.getByText(/Q4 pallet pricing follow-ups/)).toBeTruthy();
    const block = screen.getByTestId("approval-bound-block").textContent ?? "";
    expect(block).toContain(String(s.input.to));
    expect(block).toContain(String(s.input.body));
    expect(screen.getByRole("button", { name: "Approve" })).toBeTruthy();
    expect(screen.getByRole("button", { name: "Deny" })).toBeTruthy();
  });

  it("renders an existing row WITHOUT consulting the approval-queue flag (AC1)", async () => {
    render(await run());
    expect(h.flag).not.toHaveBeenCalled();
    expect(screen.getByTestId("approval-request-card")).toBeTruthy();
  });

  it("shows the request count header from request 2", async () => {
    h.count.value = 3;
    render(await run());
    expect(screen.getByTestId("approval-request-count").textContent).toContain("request 3");
  });

  it("a resolved request shows its final state with no buttons", async () => {
    h.row.value = stored({ status: "rejected", decided_at: "2026-10-28T10:01:00Z", decided_by: USER_ID });
    render(await run());
    expect(screen.getByTestId("approval-request-card").getAttribute("data-approval-state")).toBe("denied");
    expect(screen.queryAllByRole("button")).toHaveLength(0);
  });

  it("a scrubbed row renders 'Details removed per retention policy' and no text", async () => {
    h.row.value = stored({ canonical_action: null, status: "consumed" });
    render(await run());
    expect(screen.getByTestId("approval-request-card").getAttribute("data-approval-state")).toBe("details_removed");
    expect(screen.queryByTestId("approval-bound-block")).toBeNull();
  });

  it("a row whose stored text no longer hashes to the bound value shows NO card and NO buttons (fail closed)", async () => {
    const tampered = structuredClone(action) as unknown as { fields: Record<string, unknown> };
    tampered.fields.body = "something else entirely";
    h.row.value = stored({ canonical_action: tampered });
    render(await run());
    expect(screen.getByTestId("approval-unverifiable")).toBeTruthy();
    expect(screen.queryByTestId("approval-request-card")).toBeNull();
    expect(screen.queryAllByRole("button")).toHaveLength(0);
    expect(document.body.textContent).not.toContain("something else entirely");
  });

  it("a row for a different conversation than the one it was hashed for does not verify either", async () => {
    h.row.value = stored({ conversation_id: "00000000-0000-4000-8000-000000000004" });
    render(await run());
    expect(screen.getByTestId("approval-unverifiable")).toBeTruthy();
  });

  it("a read error is reported with its own op and surfaces as an error, never as not-found", async () => {
    h.rowError.value = { message: "boom", code: "XX000" };
    await expect(run()).rejects.not.toBeInstanceOf(NotFound);
    expect(h.report).toHaveBeenCalledWith("landingReadFailed", expect.anything(), expect.objectContaining({ approvalId: APPROVAL_ID }));
  });
});
