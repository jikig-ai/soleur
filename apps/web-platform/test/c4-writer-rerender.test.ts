import { describe, it, expect, vi, beforeEach } from "vitest";

const mocks = vi.hoisted(() => ({
  githubApiGet: vi.fn(),
  githubApiPost: vi.fn(),
  syncWorkspace: vi.fn(),
  renderC4Model: vi.fn(),
  readFile: vi.fn(),
  reportSilentFallback: vi.fn(),
}));

vi.mock("@/server/github-api", () => ({
  githubApiGet: mocks.githubApiGet,
  githubApiPost: mocks.githubApiPost,
  GitHubApiError: class GitHubApiError extends Error {
    statusCode: number;
    constructor(msg: string, statusCode: number) {
      super(msg);
      this.statusCode = statusCode;
    }
  },
}));
vi.mock("@/server/workspace-sync", () => ({ syncWorkspace: mocks.syncWorkspace }));
vi.mock("@/server/c4-render", () => ({ renderC4Model: mocks.renderC4Model }));
vi.mock("node:fs/promises", () => ({ readFile: mocks.readFile }));
vi.mock("@/server/observability", async () => {
  const actual = await vi.importActual<typeof import("@/server/observability")>(
    "@/server/observability",
  );
  return { ...actual, reportSilentFallback: mocks.reportSilentFallback };
});
vi.mock("@/server/logger", () => ({
  default: { info: vi.fn(), error: vi.fn(), warn: vi.fn() },
}));
vi.mock("@sentry/nextjs", () => ({ captureException: vi.fn() }));

import { writeC4Diagram } from "@/server/c4-writer";

const BASE = {
  userId: "user-1",
  installationId: 42,
  owner: "jikig-ai",
  repo: "soleur",
  workspacePath: "/workspaces/ws-1",
};

function source(relativePath: string, content = "model { }") {
  return { ...BASE, relativePath, content };
}

beforeEach(() => {
  Object.values(mocks).forEach((m) => m.mockReset());
  // Defaults: blob sha resolves, commits succeed, sync ok, render ok, JSON read ok.
  mocks.githubApiGet.mockResolvedValue({ sha: "blobsha", type: "file" });
  mocks.githubApiPost.mockResolvedValue({ commit: { sha: "commit123" } });
  mocks.syncWorkspace.mockResolvedValue({ ok: true });
  mocks.renderC4Model.mockResolvedValue({ ok: true, durationMs: 12 });
  mocks.readFile.mockResolvedValue('{"_stage":"layouted"}');
});

const C4 = "engineering/architecture/diagrams/model.c4";
const MD = "engineering/architecture/diagrams/c4-model.md";

describe("writeC4Diagram — Layer 2 re-render", () => {
  it("AC1: a .c4 save re-renders, commits model.likec4.json, re-syncs, returns rerendered:true", async () => {
    const res = await writeC4Diagram(source(C4));
    expect(res.ok).toBe(true);
    if (!res.ok) return;
    expect(res.rerendered).toBe(true);

    // render called against the workspace
    expect(mocks.renderC4Model).toHaveBeenCalledWith("/workspaces/ws-1");
    // a SECOND commit to the model.likec4.json path
    const jsonCommit = mocks.githubApiPost.mock.calls.find((c) =>
      String(c[1]).endsWith("/diagrams/model.likec4.json"),
    );
    expect(jsonCommit).toBeTruthy();
    // two syncs: one after the .c4 commit, one after the JSON commit
    expect(mocks.syncWorkspace.mock.calls.length).toBe(2);
  });

  it("AC2: render failure does NOT roll back the .c4 commit — returns rerendered:false + reports", async () => {
    mocks.renderC4Model.mockResolvedValue({ ok: false, reason: "non_zero_exit", detail: "exit=1" });
    const res = await writeC4Diagram(source(C4));
    expect(res.ok).toBe(true);
    if (!res.ok) return;
    expect(res.rerendered).toBe(false);
    // the .c4 source commit still happened (first post)
    const srcCommit = mocks.githubApiPost.mock.calls.find((c) =>
      String(c[1]).endsWith("/diagrams/model.c4"),
    );
    expect(srcCommit).toBeTruthy();
    // NO json commit
    const jsonCommit = mocks.githubApiPost.mock.calls.find((c) =>
      String(c[1]).endsWith("/diagrams/model.likec4.json"),
    );
    expect(jsonCommit).toBeFalsy();
    // failure surfaced (not swallowed)
    expect(mocks.reportSilentFallback).toHaveBeenCalled();
  });

  it("AC2b: JSON commit/sync failure after a successful render still returns rerendered:false (no .c4 regression)", async () => {
    // render ok, but the second sync (after JSON commit) fails
    mocks.syncWorkspace
      .mockResolvedValueOnce({ ok: true })
      .mockResolvedValueOnce({ ok: false, error: new Error("sync boom") });
    const res = await writeC4Diagram(source(C4));
    expect(res.ok).toBe(true);
    if (!res.ok) return;
    expect(res.rerendered).toBe(false);
    expect(mocks.reportSilentFallback).toHaveBeenCalled();
  });

  it("AC3: a .md save does NOT spawn the renderer and reports rerendered:true (layout unchanged)", async () => {
    const res = await writeC4Diagram(source(MD, "# page"));
    expect(res.ok).toBe(true);
    if (!res.ok) return;
    expect(mocks.renderC4Model).not.toHaveBeenCalled();
    expect(res.rerendered).toBe(true);
    // exactly one commit (the .md), one sync
    expect(mocks.githubApiPost.mock.calls.length).toBe(1);
    expect(mocks.syncWorkspace.mock.calls.length).toBe(1);
  });

  it("OUT_OF_SCOPE path is unchanged (no render, no commit)", async () => {
    const res = await writeC4Diagram(source("engineering/architecture/secrets.c4"));
    expect(res.ok).toBe(false);
    if (res.ok) return;
    expect(res.code).toBe("OUT_OF_SCOPE");
    expect(mocks.githubApiPost).not.toHaveBeenCalled();
    expect(mocks.renderC4Model).not.toHaveBeenCalled();
  });

  it("first-sync failure (after .c4 commit) returns SYNC_FAILED and never renders", async () => {
    mocks.syncWorkspace.mockResolvedValueOnce({ ok: false, error: new Error("first sync boom") });
    const res = await writeC4Diagram(source(C4));
    expect(res.ok).toBe(false);
    if (res.ok) return;
    expect(res.code).toBe("SYNC_FAILED");
    expect(mocks.renderC4Model).not.toHaveBeenCalled();
  });
});
