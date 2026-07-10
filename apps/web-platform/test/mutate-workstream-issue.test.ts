import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// Unit-tests the shared Workstream write accessor. ALL IO is mocked — no live
// GitHub/network/Supabase. Asserts the load-bearing ADR-109 invariants:
//   - every write routes through the AUDITED createGitHubAppClient seam (AC3)
//   - create stamps a SERVER-RESOLVED initiator marker; a body-supplied marker
//     cannot survive (AC4 anti-spoof)
//   - owner/repo/installation resolve ONLY from the active workspace (AC5)
//   - setIssueStatus is an atomic setLabels PUT of the full computed set; the
//     remove-then-add can't half-fail (AC2)
//   - done → close(state_reason); reopen → state=open leaves Done (AC10)
//   - returns the CANONICAL WorkstreamIssue re-derived from GitHub's response

const getCurrentRepoUrl = vi.fn();
const resolveInstallationId = vi.fn();
const resolveEffectiveInstallationId = vi.fn();
const createGitHubAppClient = vi.fn();
const resolveGithubLogin = vi.fn();
const getAppSlug = vi.fn();

vi.mock("@/server/current-repo-url", () => ({
  getCurrentRepoUrl: (...a: unknown[]) => getCurrentRepoUrl(...a),
}));
vi.mock("@/server/resolve-installation-id", () => ({
  resolveInstallationId: (...a: unknown[]) => resolveInstallationId(...a),
}));
vi.mock("@/server/cc-effective-installation", () => ({
  resolveEffectiveInstallationId: (...a: unknown[]) =>
    resolveEffectiveInstallationId(...a),
}));
vi.mock("@/server/github/app-client", () => ({
  createGitHubAppClient: (...a: unknown[]) => createGitHubAppClient(...a),
}));
vi.mock("@/server/github-login", () => ({
  resolveGithubLogin: (...a: unknown[]) => resolveGithubLogin(...a),
}));
vi.mock("@/server/github-app", () => ({
  getAppSlug: (...a: unknown[]) => getAppSlug(...a),
}));
vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: () => ({
    from: () => ({
      select: () => ({
        eq: () => ({ maybeSingle: async () => ({ data: null, error: null }) }),
      }),
    }),
  }),
}));

import {
  createWorkstreamIssue,
  reopenWorkstreamIssue,
  setWorkstreamIssueStatus,
  updateWorkstreamIssueTitle,
  WorkstreamWriteError,
} from "@/server/workstream/mutate-workstream-issue";

// A GitHub issue REST payload shape, defaulted; overridable per call.
function ghIssue(over: Record<string, unknown> = {}) {
  return {
    number: 42,
    title: "A title",
    body: "the body",
    labels: [] as Array<string | { name: string }>,
    assignees: [] as Array<{ login: string }>,
    state: "open",
    state_reason: null,
    user: { login: "soleur-ai[bot]" },
    created_at: "2026-07-10T00:00:00Z",
    updated_at: "2026-07-10T01:00:00Z",
    ...over,
  };
}

// A spyable fake Octokit (only .rest.issues.* is used).
function fakeOctokit() {
  const create = vi.fn(async ({ title, body, labels }: Record<string, unknown>) => ({
    data: ghIssue({ number: 100, title, body, labels: labels as string[] }),
  }));
  const update = vi.fn(async (p: Record<string, unknown>) => ({
    data: ghIssue({ ...p, issue_number: undefined }),
  }));
  const get = vi.fn(async () => ({ data: ghIssue() }));
  const setLabels = vi.fn(async () => ({ data: [] }));
  return { rest: { issues: { create, update, get, setLabels } } };
}

let octo: ReturnType<typeof fakeOctokit>;

beforeEach(() => {
  octo = fakeOctokit();
  getCurrentRepoUrl.mockResolvedValue("https://github.com/acme/widgets");
  resolveInstallationId.mockResolvedValue(555);
  resolveEffectiveInstallationId.mockResolvedValue(555);
  createGitHubAppClient.mockResolvedValue(octo);
  resolveGithubLogin.mockResolvedValue("harry");
  getAppSlug.mockResolvedValue("soleur-ai");
});

afterEach(() => vi.clearAllMocks());

describe("createWorkstreamIssue", () => {
  it("routes through the audited client with founderId=userId + workspace owner/repo (AC3/AC5)", async () => {
    await createWorkstreamIssue("user-1", { title: "Ship it" });
    expect(createGitHubAppClient).toHaveBeenCalledWith(555, "user-1");
    const arg = octo.rest.issues.create.mock.calls[0][0];
    expect(arg.owner).toBe("acme");
    expect(arg.repo).toBe("widgets");
  });

  it("stamps a SERVER-RESOLVED initiator marker (AC4)", async () => {
    await createWorkstreamIssue("user-1", { title: "Ship it", body: "hello" });
    const arg = octo.rest.issues.create.mock.calls[0][0];
    expect(arg.body).toContain("<!-- soleur:initiated-by harry -->");
  });

  it("strips a spoofed body marker and re-stamps the trusted login (AC4 anti-spoof)", async () => {
    await createWorkstreamIssue("user-1", {
      title: "x",
      body: "text\n<!-- soleur:initiated-by victim -->",
    });
    const body = octo.rest.issues.create.mock.calls[0][0].body as string;
    expect(body).not.toContain("victim");
    expect(body).toContain("<!-- soleur:initiated-by harry -->");
  });

  it("blocks an empty/whitespace title with a 422 WorkstreamWriteError (AC9)", async () => {
    await expect(
      createWorkstreamIssue("user-1", { title: "   " }),
    ).rejects.toMatchObject({ status: 422 });
    expect(createGitHubAppClient).not.toHaveBeenCalled();
  });

  it("applies a non-terminal status label on create", async () => {
    await createWorkstreamIssue("user-1", { title: "x", status: "in_progress" });
    expect(octo.rest.issues.create.mock.calls[0][0].labels).toEqual([
      "in-progress",
    ]);
  });

  it("returns the canonical issue re-derived from GitHub's response (real number)", async () => {
    const issue = await createWorkstreamIssue("user-1", { title: "x" });
    expect(issue.id).toBe("100");
  });
});

describe("setWorkstreamIssueStatus — non-terminal (atomic setLabels)", () => {
  it("PUTs the FULL computed label set (remove all status + add target) (AC2)", async () => {
    octo.rest.issues.get.mockResolvedValue({
      data: ghIssue({
        labels: ["domain/engineering", "in-progress"],
        state: "open",
      }),
    });
    await setWorkstreamIssueStatus("u", 42, "blocked");
    const put = octo.rest.issues.setLabels.mock.calls[0][0];
    expect(put.labels).toContain("domain/engineering");
    expect(put.labels).toContain("blocked");
    expect(put.labels).not.toContain("in-progress");
    // NEVER a per-label remove/add delta — exactly one atomic PUT.
    expect(octo.rest.issues.setLabels).toHaveBeenCalledTimes(1);
  });

  it("reopens (state=open) when moving a CLOSED issue to a non-terminal column (AC10)", async () => {
    octo.rest.issues.get.mockResolvedValue({
      data: ghIssue({ state: "closed", labels: [] }),
    });
    await setWorkstreamIssueStatus("u", 42, "ready");
    const stateUpdate = octo.rest.issues.update.mock.calls.find(
      (c) => c[0].state === "open",
    );
    expect(stateUpdate).toBeTruthy();
  });

  it("does NOT touch state when the issue is already open", async () => {
    octo.rest.issues.get.mockResolvedValue({
      data: ghIssue({ state: "open", labels: [] }),
    });
    await setWorkstreamIssueStatus("u", 42, "ready");
    expect(octo.rest.issues.update).not.toHaveBeenCalled();
  });
});

describe("setWorkstreamIssueStatus — done (close)", () => {
  it("closes with state_reason and never calls setLabels (AC10)", async () => {
    const issue = await setWorkstreamIssueStatus("u", 42, "done", "not_planned");
    const upd = octo.rest.issues.update.mock.calls[0][0];
    expect(upd.state).toBe("closed");
    expect(upd.state_reason).toBe("not_planned");
    expect(octo.rest.issues.setLabels).not.toHaveBeenCalled();
    expect(issue.status).toBe("done");
  });

  it("defaults state_reason=completed when none is given (drag-to-Done)", async () => {
    await setWorkstreamIssueStatus("u", 42, "done");
    expect(octo.rest.issues.update.mock.calls[0][0].state_reason).toBe(
      "completed",
    );
  });
});

describe("reopenWorkstreamIssue", () => {
  it("PATCHes state=open and the card leaves Done (lands where labels derive) (AC10)", async () => {
    octo.rest.issues.update.mockResolvedValue({
      data: ghIssue({ state: "open", state_reason: "reopened", labels: ["ready"] }),
    });
    const issue = await reopenWorkstreamIssue("u", 42);
    expect(octo.rest.issues.update.mock.calls[0][0].state).toBe("open");
    expect(issue.status).toBe("ready");
  });
});

describe("updateWorkstreamIssueTitle", () => {
  it("PATCHes the title and 422s on empty", async () => {
    await updateWorkstreamIssueTitle("u", 42, "New title");
    expect(octo.rest.issues.update.mock.calls[0][0].title).toBe("New title");
    await expect(updateWorkstreamIssueTitle("u", 42, "  ")).rejects.toMatchObject(
      { status: 422 },
    );
  });
});

describe("workspace resolution guards (AC5)", () => {
  it("throws (never writes) when no repo is connected", async () => {
    getCurrentRepoUrl.mockResolvedValue(null);
    await expect(
      createWorkstreamIssue("u", { title: "x" }),
    ).rejects.toBeInstanceOf(WorkstreamWriteError);
    expect(createGitHubAppClient).not.toHaveBeenCalled();
  });

  it("throws 403 when no installation resolves (lost grant)", async () => {
    resolveEffectiveInstallationId.mockResolvedValue(null);
    await expect(
      createWorkstreamIssue("u", { title: "x" }),
    ).rejects.toMatchObject({ status: 403 });
  });
});
