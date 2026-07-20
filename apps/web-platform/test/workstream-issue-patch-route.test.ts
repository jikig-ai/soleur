import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// Route tests for PATCH /api/workstream/issues/[number]. The accessor verbs are
// stubbed (real WorkstreamWriteError/classifyWriteError stay live). Asserts the
// route dispatches {title|status|state_reason|reopen} to the ONE accessor,
// never accepts owner/repo, returns the canonical issue, and maps failures.

const getUser = vi.fn();
vi.mock("@/lib/supabase/server", () => ({
  createClient: async () => ({ auth: { getUser: getUser } }),
}));

const updateWorkstreamIssueTitle = vi.fn();
const setWorkstreamIssueStatus = vi.fn();
const reopenWorkstreamIssue = vi.fn();
const updateWorkstreamIssueFields = vi.fn();
vi.mock("@/server/workstream/mutate-workstream-issue", async (io) => ({
  ...(await io<typeof import("@/server/workstream/mutate-workstream-issue")>()),
  updateWorkstreamIssueTitle: (...a: unknown[]) =>
    updateWorkstreamIssueTitle(...a),
  setWorkstreamIssueStatus: (...a: unknown[]) => setWorkstreamIssueStatus(...a),
  reopenWorkstreamIssue: (...a: unknown[]) => reopenWorkstreamIssue(...a),
  updateWorkstreamIssueFields: (...a: unknown[]) =>
    updateWorkstreamIssueFields(...a),
}));

import { PATCH } from "@/app/api/workstream/issues/[number]/route";
import { __resetWorkstreamWriteThrottleForTest } from "@/server/workstream/workstream-write-throttle";

function req(body: unknown): Request {
  return new Request("http://localhost/api/workstream/issues/42", {
    method: "PATCH",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}
const ctx = (n = "42") => ({ params: Promise.resolve({ number: n }) });

beforeEach(() => {
  vi.clearAllMocks();
  __resetWorkstreamWriteThrottleForTest();
  getUser.mockResolvedValue({ data: { user: { id: "user-9" } } });
  updateWorkstreamIssueTitle.mockResolvedValue({ id: "42", title: "New" });
  setWorkstreamIssueStatus.mockResolvedValue({ id: "42", status: "blocked" });
  reopenWorkstreamIssue.mockResolvedValue({ id: "42", status: "ready" });
  updateWorkstreamIssueFields.mockResolvedValue({ id: "42", title: "New" });
});
afterEach(() => vi.clearAllMocks());

describe("PATCH /api/workstream/issues/[number]", () => {
  it("401s an unauthenticated caller", async () => {
    getUser.mockResolvedValue({ data: { user: null } });
    const res = await PATCH(req({ title: "x" }), ctx());
    expect(res.status).toBe(401);
  });

  it("400s a non-numeric issue number", async () => {
    const res = await PATCH(req({ title: "x" }), ctx("not-a-number"));
    expect(res.status).toBe(400);
  });

  it("dispatches a title edit to updateWorkstreamIssueTitle (AC2)", async () => {
    const res = await PATCH(req({ title: "New title" }), ctx());
    expect(res.status).toBe(200);
    expect(updateWorkstreamIssueTitle).toHaveBeenCalledWith(
      "user-9",
      42,
      "New title",
    );
    const json = (await res.json()) as { issue: { id: string } };
    expect(json.issue.id).toBe("42");
  });

  it("dispatches a status change to the ONE setIssueStatus primitive (AC2)", async () => {
    await PATCH(req({ status: "blocked" }), ctx());
    expect(setWorkstreamIssueStatus).toHaveBeenCalledWith(
      "user-9",
      42,
      "blocked",
      undefined,
    );
  });

  it("dispatches a close (status=done + state_reason) (AC10)", async () => {
    await PATCH(req({ status: "done", state_reason: "not_planned" }), ctx());
    expect(setWorkstreamIssueStatus).toHaveBeenCalledWith(
      "user-9",
      42,
      "done",
      "not_planned",
    );
  });

  it("dispatches an explicit reopen to reopenWorkstreamIssue (AC10)", async () => {
    await PATCH(req({ reopen: true }), ctx());
    expect(reopenWorkstreamIssue).toHaveBeenCalledWith("user-9", 42);
  });

  it("never accepts owner/repo from the body (AC5)", async () => {
    await PATCH(
      req({ status: "ready", owner: "attacker", repo: "evil" }),
      ctx(),
    );
    const args = setWorkstreamIssueStatus.mock.calls[0];
    expect(args).toEqual(["user-9", 42, "ready", undefined]);
  });

  it("422s an empty title", async () => {
    const res = await PATCH(req({ title: "   " }), ctx());
    expect(res.status).toBe(422);
    expect(updateWorkstreamIssueTitle).not.toHaveBeenCalled();
  });

  it("400s when no actionable field is present", async () => {
    const res = await PATCH(req({}), ctx());
    expect(res.status).toBe(400);
  });

  it("422s an out-of-enum status instead of a silent Backlog no-op (security nit)", async () => {
    const res = await PATCH(req({ status: "bogus" }), ctx());
    expect(res.status).toBe(422);
    expect(setWorkstreamIssueStatus).not.toHaveBeenCalled();
  });

  it("422s a combined title+status body rather than dropping the title", async () => {
    const res = await PATCH(req({ title: "x", status: "ready" }), ctx());
    expect(res.status).toBe(422);
    expect(updateWorkstreamIssueTitle).not.toHaveBeenCalled();
    expect(setWorkstreamIssueStatus).not.toHaveBeenCalled();
  });

  it("502s and Sentry-mirrors on a write failure", async () => {
    setWorkstreamIssueStatus.mockRejectedValue(
      Object.assign(new Error("boom"), { status: 500 }),
    );
    const res = await PATCH(req({ status: "ready" }), ctx());
    expect(res.status).toBe(502);
  });

  it("maps a 403 (read-only install) honestly (AC14)", async () => {
    setWorkstreamIssueStatus.mockRejectedValue(
      Object.assign(new Error("no"), { status: 403 }),
    );
    const res = await PATCH(req({ status: "ready" }), ctx());
    expect(res.status).toBe(403);
  });

  it("dispatches a body edit to updateWorkstreamIssueFields", async () => {
    await PATCH(req({ body: "new body" }), ctx());
    expect(updateWorkstreamIssueFields).toHaveBeenCalledWith("user-9", 42, {
      body: "new body",
    });
  });

  it("dispatches labels/assignees/milestone together in one fields call", async () => {
    await PATCH(
      req({ labels: ["bug"], assignees: ["harry"], milestone: 3 }),
      ctx(),
    );
    expect(updateWorkstreamIssueFields).toHaveBeenCalledWith("user-9", 42, {
      labels: ["bug"],
      assignees: ["harry"],
      milestone: 3,
    });
  });

  it("allows milestone:null (clear) through as a field", async () => {
    await PATCH(req({ milestone: null }), ctx());
    expect(updateWorkstreamIssueFields).toHaveBeenCalledWith("user-9", 42, {
      milestone: null,
    });
  });

  it("allows an empty body (unlike title)", async () => {
    const res = await PATCH(req({ body: "" }), ctx());
    expect(res.status).toBe(200);
    expect(updateWorkstreamIssueFields).toHaveBeenCalledWith("user-9", 42, {
      body: "",
    });
  });

  it("422s a non-array assignees", async () => {
    const res = await PATCH(req({ assignees: "harry" }), ctx());
    expect(res.status).toBe(422);
    expect(updateWorkstreamIssueFields).not.toHaveBeenCalled();
  });

  it("422s a non-string-array labels", async () => {
    const res = await PATCH(req({ labels: [1, 2] }), ctx());
    expect(res.status).toBe(422);
    expect(updateWorkstreamIssueFields).not.toHaveBeenCalled();
  });

  it("422s a non-positive / non-integer milestone", async () => {
    expect((await PATCH(req({ milestone: 0 }), ctx())).status).toBe(422);
    expect((await PATCH(req({ milestone: -3 }), ctx())).status).toBe(422);
    expect((await PATCH(req({ milestone: 1.5 }), ctx())).status).toBe(422);
    expect((await PATCH(req({ milestone: "x" }), ctx())).status).toBe(422);
    expect(updateWorkstreamIssueFields).not.toHaveBeenCalled();
  });

  it("422s combining a field with title (keeps title atomic)", async () => {
    const res = await PATCH(req({ title: "x", body: "y" }), ctx());
    expect(res.status).toBe(422);
    expect(updateWorkstreamIssueFields).not.toHaveBeenCalled();
    expect(updateWorkstreamIssueTitle).not.toHaveBeenCalled();
  });

  it("422s combining a field with status (keeps status atomic)", async () => {
    const res = await PATCH(req({ status: "ready", labels: ["bug"] }), ctx());
    expect(res.status).toBe(422);
    expect(updateWorkstreamIssueFields).not.toHaveBeenCalled();
    expect(setWorkstreamIssueStatus).not.toHaveBeenCalled();
  });

  it("never accepts owner/repo alongside a fields edit (AC5)", async () => {
    await PATCH(
      req({ body: "hi", owner: "attacker", repo: "evil" }),
      ctx(),
    );
    expect(updateWorkstreamIssueFields).toHaveBeenCalledWith("user-9", 42, {
      body: "hi",
    });
  });

  it("throttles after the per-user budget (429) (AC15)", async () => {
    let last = 200;
    for (let i = 0; i < 60; i++) {
      last = (await PATCH(req({ status: "ready" }), ctx())).status;
      if (last === 429) break;
    }
    expect(last).toBe(429);
  });
});
