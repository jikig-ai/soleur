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
import {
  APPROVAL_ID,
  CONVERSATION_ID,
  OTHER_WORKSPACE_ID,
  REQUESTER_EMAIL,
  REQUESTER_ID,
  SAMPLES,
  TOOLS,
  USER_ID,
  WORKSPACE_ID,
  makeLabelerClient,
  type FakeLabelerWorld,
} from "./fixtures";

const h = vi.hoisted(() => ({
  user: { value: { id: "00000000-0000-4000-8000-000000000007" } as { id: string } | null },
  row: { value: null as Record<string, unknown> | null },
  rowError: { value: null as unknown },
  count: { value: 1 },
  countError: { value: null as unknown },
  fromCalls: [] as string[],
  /** Columns of every select on approval_request (#9601: the row read must include requested_by_user_id). */
  selectCols: [] as string[],
  /** The service-role client the requester labeler reads through (#9601). */
  serviceClient: { value: null as unknown },
  serviceCalls: { value: 0 },
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
          if (table === "approval_request" && !opts?.head) h.selectCols.push(_c);
          if (opts?.head) return { eq: () => ({ eq: async () => ({ count: h.count.value, error: h.countError.value }) }) };
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

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => {
    h.serviceCalls.value++;
    return h.serviceClient.value;
  },
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
    revoked_at: null,
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
  h.countError.value = null;
  h.fromCalls.length = 0;
  h.selectCols.length = 0;
  h.serviceClient.value = null;
  h.serviceCalls.value = 0;
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
    // Fixed header: the model-influenceable conversation title is never read or shown.
    expect(screen.getByText("From your agent")).toBeTruthy();
    expect(document.body.textContent).not.toContain("Q4 pallet pricing follow-ups");
    expect(h.fromCalls).not.toContain("conversations");
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

  it("a failed count read is reported (not silently shown as 1) and the card still renders", async () => {
    h.countError.value = { message: "boom", code: "XX000" };
    render(await run());
    expect(h.report).toHaveBeenCalledWith(
      "landingReadFailed",
      expect.anything(),
      expect.objectContaining({ approvalId: APPROVAL_ID, extra: { read: "request-count" } }),
    );
    expect(screen.queryByTestId("approval-request-count")).toBeNull();
    expect(screen.getByTestId("approval-request-card")).toBeTruthy();
  });

  it("an approved, unconsumed row renders 'ask again' with a Revoke control, not 'released'", async () => {
    h.row.value = stored({ status: "approved", decided_at: new Date().toISOString(), decided_by: USER_ID });
    render(await run());
    expect(screen.getByTestId("approval-request-card").getAttribute("data-approval-state")).toBe("approved_late");
    expect(screen.getByRole("button", { name: "Revoke approval" })).toBeTruthy();
  });

  it("a revoked row (rejected with revoked_at) renders the revoked state", async () => {
    h.row.value = stored({ status: "rejected", decided_at: "2026-10-28T10:01:00Z", decided_by: USER_ID, revoked_at: "2026-10-28T10:30:00Z" });
    render(await run());
    expect(screen.getByTestId("approval-request-card").getAttribute("data-approval-state")).toBe("revoked");
    expect(screen.queryAllByRole("button")).toHaveLength(0);
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
    expect(h.report).toHaveBeenCalledWith(
      "landingReadFailed",
      expect.anything(),
      expect.objectContaining({ approvalId: APPROVAL_ID, extra: { read: "row" } }),
    );
  });
});

// ---------------------------------------------------------------------------------------------------------------------
// #9601: the requester line. The REAL labeler runs against the strict PostgREST fake at the service-client seam (never a
// mocked labeler), and only after the Owner-RLS read succeeded.
// ---------------------------------------------------------------------------------------------------------------------
describe("the requester line (#9601)", () => {
  const world = (over: Partial<FakeLabelerWorld> = {}): FakeLabelerWorld => ({
    members: [
      { workspace_id: WORKSPACE_ID, user_id: USER_ID, role: "owner" },
      { workspace_id: WORKSPACE_ID, user_id: REQUESTER_ID, role: "member" },
    ],
    authEmails: { [REQUESTER_ID]: REQUESTER_EMAIL },
    publicEmails: { [REQUESTER_ID]: "attacker-controlled@example.com" },
    ...over,
  });
  const useWorld = (w: FakeLabelerWorld) => {
    const fake = makeLabelerClient(w);
    h.serviceClient.value = fake.client;
    return fake;
  };
  const line = () => screen.queryByTestId("approval-requester");
  const labelReports = () => h.report.mock.calls.filter((c) => c[0] === "requesterLabelFailed");

  it("the row read selects requested_by_user_id", async () => {
    useWorld(world());
    await run();
    expect(h.selectCols.some((c) => c.includes("requested_by_user_id"))).toBe(true);
  });

  it("a current member who requested: the Owner sees their auth email (never the public users address)", async () => {
    const fake = useWorld(world());
    h.row.value = stored({ requested_by_user_id: REQUESTER_ID });
    render(await run());
    expect(line()?.textContent).toBe(`Requested by ${REQUESTER_EMAIL}`);
    expect(document.body.textContent).not.toContain("attacker-controlled");
    // Scoped to the ROW's workspace.
    expect(fake.queries[0].filters).toContainEqual({ op: "eq", col: "workspace_id", val: WORKSPACE_ID });
    // The Approve/Deny controls are unaffected.
    expect(screen.getByRole("button", { name: "Approve" })).toBeTruthy();
  });

  it("the Owner is the requester: 'you', and no service-role read at all", async () => {
    useWorld(world());
    h.row.value = stored({ requested_by_user_id: USER_ID });
    render(await run());
    expect(line()?.textContent).toBe("Requested by you");
    expect(h.serviceCalls.value).toBe(0);
  });

  it("a requester who left the workspace: the fixed fallback", async () => {
    useWorld(world({ members: [{ workspace_id: WORKSPACE_ID, user_id: USER_ID, role: "owner" }] }));
    h.row.value = stored({ requested_by_user_id: REQUESTER_ID });
    render(await run());
    expect(line()?.textContent).toBe("Requested by a workspace member");
  });

  it("an erased requester (NULL): the fixed fallback, with no query", async () => {
    const fake = useWorld(world());
    h.row.value = stored({ requested_by_user_id: null });
    render(await run());
    expect(line()?.textContent).toBe("Requested by a workspace member");
    expect(fake.queries).toHaveLength(0);
  });

  it("a requester who is a member of ANOTHER workspace only: the fallback, not their address", async () => {
    useWorld(world({ members: [{ workspace_id: WORKSPACE_ID, user_id: USER_ID, role: "owner" }, { workspace_id: OTHER_WORKSPACE_ID, user_id: REQUESTER_ID, role: "member" }] }));
    h.row.value = stored({ requested_by_user_id: REQUESTER_ID });
    render(await run());
    expect(line()?.textContent).toBe("Requested by a workspace member");
  });

  it("a lookup failure: no line, no 500, the card still decides, and the failure is reported without the address", async () => {
    const fake = useWorld(world({ membershipError: { code: "57014", message: `timeout ${REQUESTER_EMAIL}` } }));
    h.row.value = stored({ requested_by_user_id: REQUESTER_ID });
    render(await run());
    expect(line()).toBeNull();
    expect(screen.getByRole("button", { name: "Approve" })).toBeTruthy();
    expect(screen.getByRole("button", { name: "Deny" })).toBeTruthy();
    expect(fake.queries[0].terminal).toBe("await");
    expect(labelReports()).toHaveLength(1);
    // The thrown value is handed to the (mocked) ops helper raw; the real helper keeps only {code, fn, errName}. What the
    // landing page itself puts in the context must carry no address.
    expect(JSON.stringify(h.report.mock.calls.map((c) => c[2]))).not.toContain(REQUESTER_EMAIL);
    expect((labelReports()[0][1] as { code?: string }).code).toBe("57014");
  });

  it("a lookup that times out still renders Approve and Deny, with no line", async () => {
    const ctl = new AbortController();
    const spy = vi.spyOn(AbortSignal, "timeout").mockImplementation(() => ctl.signal);
    try {
      let hungReads = 0;
      h.serviceClient.value = {
        from: () => {
          hungReads += 1;
          return { select: () => ({ eq: () => ({ in: () => ({ abortSignal: () => new Promise(() => {}) }) }) }) };
        },
        auth: { admin: { getUserById: () => new Promise(() => {}) } },
      };
      h.row.value = stored({ requested_by_user_id: REQUESTER_ID });
      const pending = run();
      await vi.waitFor(() => expect(hungReads).toBe(1));
      ctl.abort();
      render(await pending);
      expect(line()).toBeNull();
      expect(screen.getByRole("button", { name: "Approve" })).toBeTruthy();
      expect(labelReports()).toHaveLength(1);
    } finally {
      spy.mockRestore();
    }
  });

  it("a scrubbed row (details removed) shows no line and makes no lookup", async () => {
    const fake = useWorld(world());
    h.row.value = stored({ canonical_action: null, status: "consumed", requested_by_user_id: REQUESTER_ID });
    render(await run());
    expect(screen.getByTestId("approval-request-card").getAttribute("data-approval-state")).toBe("details_removed");
    expect(line()).toBeNull();
    expect(fake.queries).toHaveLength(0);
  });

  it("a row read that carries no requested_by_user_id value behaves as an erased requester (the fixed fallback, no query)", async () => {
    const fake = useWorld(world());
    const row = stored();
    expect("requested_by_user_id" in row).toBe(false);
    h.row.value = row;
    render(await run());
    expect(line()?.textContent).toBe("Requested by a workspace member");
    expect(fake.queries).toHaveLength(0);
  });

  describe("two or more requests for the conversation and action", () => {
    it("another member's request with count 2: no line and the labeler is not asked (no service-role read)", async () => {
      h.count.value = 2;
      const fake = useWorld(world());
      h.row.value = stored({ requested_by_user_id: REQUESTER_ID });
      render(await run());
      expect(line()).toBeNull();
      expect(fake.queries).toHaveLength(0);
      expect(fake.authCalls).toEqual([]);
      expect(h.serviceCalls.value).toBe(0);
      expect(screen.getByRole("button", { name: "Approve" })).toBeTruthy();
    });

    it("an erased requester with count 2: no line either (the fallback literal is a label too)", async () => {
      h.count.value = 3;
      useWorld(world());
      h.row.value = stored({ requested_by_user_id: null });
      render(await run());
      expect(line()).toBeNull();
    });

    it("the Owner is the requester with count 2: the literal you stays", async () => {
      h.count.value = 2;
      useWorld(world());
      h.row.value = stored({ requested_by_user_id: USER_ID });
      render(await run());
      expect(line()?.textContent).toBe("Requested by you");
      expect(h.serviceCalls.value).toBe(0);
    });

    it("an unavailable count (read error) is suppress-safe: no line for another member, the error is reported", async () => {
      h.countError.value = { code: "57014" };
      const fake = useWorld(world());
      h.row.value = stored({ requested_by_user_id: REQUESTER_ID });
      render(await run());
      expect(line()).toBeNull();
      expect(fake.queries).toHaveLength(0);
      expect(h.report.mock.calls.some((c) => c[0] === "landingReadFailed")).toBe(true);
    });

    it("an unavailable count still shows 'you' for the requester", async () => {
      h.countError.value = { code: "57014" };
      useWorld(world());
      h.row.value = stored({ requested_by_user_id: USER_ID });
      render(await run());
      expect(line()?.textContent).toBe("Requested by you");
    });
  });

  it("an invisible row (not found for a non-Owner) makes no service-role read", async () => {
    useWorld(world());
    h.row.value = null;
    await expect(run()).rejects.toBeInstanceOf(NotFound);
    expect(h.serviceCalls.value).toBe(0);
  });

  it("the Owner-only RLS read gates the label: migration 180's select policy is is_workspace_owner(workspace_id, auth.uid())", async () => {
    const { readFileSync } = await import("node:fs");
    const { join } = await import("node:path");
    const sql = readFileSync(join(__dirname, "../../supabase/migrations/180_approval_request.sql"), "utf8");
    const at = sql.indexOf("CREATE POLICY approval_request_owner_select");
    expect(at).toBeGreaterThan(-1);
    expect(sql.slice(at, at + 400)).toContain("is_workspace_owner(workspace_id, auth.uid())");
  });
});
