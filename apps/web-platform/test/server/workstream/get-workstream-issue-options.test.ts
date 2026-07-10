import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// The picker-options accessor for the edit-fields drawer. Reads the connected
// repo's labels/assignees/milestones through the SAME workspace resolution the
// write accessor uses (resolveContext). DEGRADE-SAFE: any failure yields empty
// arrays + reportSilentFallback, never throws the whole board. Labels are
// filtered to NON-status only (the labels editor never touches status labels).

const resolveContext = vi.fn();
vi.mock("@/server/workstream/mutate-workstream-issue", async (io) => ({
  ...(await io<typeof import("@/server/workstream/mutate-workstream-issue")>()),
  resolveContext: (...a: unknown[]) => resolveContext(...a),
}));

const reportSilentFallback = vi.fn();
vi.mock("@/server/observability", () => ({
  reportSilentFallback: (...a: unknown[]) => reportSilentFallback(...a),
}));

import { getWorkstreamIssueOptions } from "@/server/workstream/get-workstream-issue-options";

function fakeOctokit(over: {
  labels?: Array<{ name: string; color?: string | null }>;
  assignees?: Array<{ login: string }>;
  milestones?: Array<{ number: number; title: string }>;
} = {}) {
  return {
    rest: {
      issues: {
        listLabelsForRepo: vi.fn(async () => ({
          data: over.labels ?? [
            { name: "bug", color: "d73a4a" },
            { name: "in-progress", color: "cccccc" },
            { name: "domain/engineering", color: "0e8a16" },
          ],
        })),
        listAssignees: vi.fn(async () => ({
          data: over.assignees ?? [{ login: "harry" }, { login: "ada" }],
        })),
        listMilestones: vi.fn(async () => ({
          data: over.milestones ?? [
            { number: 1, title: "v1" },
            { number: 2, title: "v2" },
          ],
        })),
      },
    },
  };
}

beforeEach(() => {
  vi.clearAllMocks();
  resolveContext.mockResolvedValue({
    owner: "acme",
    repo: "widgets",
    octokit: fakeOctokit(),
    botSlug: "soleur-ai",
  });
});
afterEach(() => vi.clearAllMocks());

describe("getWorkstreamIssueOptions", () => {
  it("returns labels (NON-status only), assignees, and milestones", async () => {
    const out = await getWorkstreamIssueOptions("u");
    expect(out.labels.map((l) => l.name)).toContain("bug");
    expect(out.labels.map((l) => l.name)).toContain("domain/engineering");
    // status labels are filtered out (owned by the status control).
    expect(out.labels.map((l) => l.name)).not.toContain("in-progress");
    expect(out.assignees).toEqual([{ login: "harry" }, { login: "ada" }]);
    expect(out.milestones).toEqual([
      { number: 1, title: "v1" },
      { number: 2, title: "v2" },
    ]);
  });

  it("degrades to empty arrays + reports when resolution throws (never throws)", async () => {
    resolveContext.mockRejectedValue(new Error("no repo"));
    const out = await getWorkstreamIssueOptions("u");
    expect(out).toEqual({ labels: [], assignees: [], milestones: [] });
    expect(reportSilentFallback).toHaveBeenCalled();
  });

  it("degrades to empty arrays when a list call throws", async () => {
    const octo = fakeOctokit();
    octo.rest.issues.listMilestones = vi.fn(async () => {
      throw new Error("502");
    });
    resolveContext.mockResolvedValue({
      owner: "acme",
      repo: "widgets",
      octokit: octo,
      botSlug: null,
    });
    const out = await getWorkstreamIssueOptions("u");
    expect(out).toEqual({ labels: [], assignees: [], milestones: [] });
    expect(reportSilentFallback).toHaveBeenCalled();
  });
});
