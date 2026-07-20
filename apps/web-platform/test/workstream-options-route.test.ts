import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// Route tests for GET /api/workstream/issues/options. The accessor is stubbed.
// Asserts auth-gating and that it serves the accessor's payload verbatim (the
// accessor is degrade-safe, so the route never 502s).

const getUser = vi.fn();
vi.mock("@/lib/supabase/server", () => ({
  createClient: async () => ({ auth: { getUser } }),
}));

const getWorkstreamIssueOptions = vi.fn();
vi.mock("@/server/workstream/get-workstream-issue-options", () => ({
  getWorkstreamIssueOptions: (...a: unknown[]) =>
    getWorkstreamIssueOptions(...a),
}));

import { GET } from "@/app/api/workstream/issues/options/route";

beforeEach(() => {
  vi.clearAllMocks();
  getUser.mockResolvedValue({ data: { user: { id: "user-9" } } });
  getWorkstreamIssueOptions.mockResolvedValue({
    labels: [{ name: "bug", color: "d73a4a" }],
    assignees: [{ login: "harry" }],
    milestones: [{ number: 1, title: "v1" }],
  });
});
afterEach(() => vi.clearAllMocks());

describe("GET /api/workstream/issues/options", () => {
  it("401s an unauthenticated caller", async () => {
    getUser.mockResolvedValue({ data: { user: null } });
    const res = await GET();
    expect(res.status).toBe(401);
    expect(getWorkstreamIssueOptions).not.toHaveBeenCalled();
  });

  it("serves the accessor payload for the session user", async () => {
    const res = await GET();
    expect(res.status).toBe(200);
    expect(getWorkstreamIssueOptions).toHaveBeenCalledWith("user-9");
    const json = (await res.json()) as {
      labels: unknown[];
      assignees: unknown[];
      milestones: unknown[];
    };
    expect(json.labels).toEqual([{ name: "bug", color: "d73a4a" }]);
    expect(json.assignees).toEqual([{ login: "harry" }]);
    expect(json.milestones).toEqual([{ number: 1, title: "v1" }]);
  });
});
