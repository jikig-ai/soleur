import { describe, it, expect, vi, beforeEach } from "vitest";

const mocks = vi.hoisted(() => ({
  githubApiGet: vi.fn(),
  githubApiPost: vi.fn(),
  syncWorkspace: vi.fn(),
  renderC4Model: vi.fn(),
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

// The validated bytes renderC4Model now returns (#4976) — the writer commits
// these directly, no on-disk re-read.
const RENDERED_JSON = '{"_stage":"layouted"}';

beforeEach(() => {
  Object.values(mocks).forEach((m) => m.mockReset());
  // Defaults: blob sha resolves, commits succeed, sync ok, render ok (carrying
  // the validated bytes the writer commits).
  mocks.githubApiGet.mockResolvedValue({ sha: "blobsha", type: "file" });
  mocks.githubApiPost.mockResolvedValue({ commit: { sha: "commit123" } });
  mocks.syncWorkspace.mockResolvedValue({ ok: true });
  mocks.renderC4Model.mockResolvedValue({
    ok: true,
    durationMs: 12,
    json: RENDERED_JSON,
  });
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
    expect(jsonCommit).toBeDefined();
    // #4976: the writer commits EXACTLY the bytes renderC4Model returned — the
    // base64 `content` decodes back to render.json (pins producer→consumer).
    const committedContent = (jsonCommit![2] as { content: string }).content;
    expect(Buffer.from(committedContent, "base64").toString("utf8")).toBe(
      RENDERED_JSON,
    );
    // two syncs: one after the .c4 commit, one after the JSON commit
    expect(mocks.syncWorkspace.mock.calls.length).toBe(2);

    // Ordering is load-bearing for failure isolation: the .c4 source commit AND
    // its first sync MUST complete before the render/JSON commit runs.
    const srcPost = mocks.githubApiPost.mock.invocationCallOrder[0];
    const jsonPostIdx = mocks.githubApiPost.mock.calls.findIndex((c) =>
      String(c[1]).endsWith("/diagrams/model.likec4.json"),
    );
    const jsonPost = mocks.githubApiPost.mock.invocationCallOrder[jsonPostIdx];
    const renderCall = mocks.renderC4Model.mock.invocationCallOrder[0];
    expect(srcPost).toBeLessThan(renderCall);
    expect(renderCall).toBeLessThan(jsonPost);
  });

  it("AC2c: an oversized regenerated model is NOT committed (size cap)", async () => {
    // Cap is enforced on the RETURNED bytes now (#4976), not a mocked fd-stat.
    mocks.renderC4Model.mockResolvedValue({
      ok: true,
      durationMs: 12,
      json: "x".repeat(8 * 1024 * 1024), // > 4 MB cap
    });
    const res = await writeC4Diagram(source(C4));
    expect(res.ok).toBe(true);
    if (!res.ok) return;
    expect(res.rerendered).toBe(false);
    const jsonCommit = mocks.githubApiPost.mock.calls.find((c) =>
      String(c[1]).endsWith("/diagrams/model.likec4.json"),
    );
    expect(jsonCommit).toBeFalsy();
    expect(mocks.reportSilentFallback).toHaveBeenCalled();
  });

  it("AC2: render failure does NOT roll back the .c4 commit — returns rerendered:false + reports", async () => {
    mocks.renderC4Model.mockResolvedValue({ ok: false, reason: "non_zero_exit", detail: "exit=1" });
    const res = await writeC4Diagram(source(C4));
    expect(res.ok).toBe(true);
    if (!res.ok) return;
    expect(res.rerendered).toBe(false);
    // A non-source-fault failure carries NO source-blaming diagnostic.
    expect(res.rerenderDiagnostic).toBeUndefined();
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

  it("AC2d: an empty_model render surfaces a user-facing rerenderDiagnostic + NO json commit (#4966)", async () => {
    mocks.renderC4Model.mockResolvedValue({
      ok: false,
      reason: "empty_model",
      detail:
        "Line 135: Could not resolve reference to ElementKind named 'container'.\nLine 147: Could not resolve reference to ElementKind named 'system'.",
    });
    const res = await writeC4Diagram(source(C4));
    expect(res.ok).toBe(true);
    if (!res.ok) return;
    expect(res.rerendered).toBe(false);
    // The actionable cause is surfaced to the client (the first unresolved
    // reference + the spec.c4 hint), not a silent stale banner.
    expect(res.rerenderDiagnostic).toContain("Re-render failed");
    expect(res.rerenderDiagnostic).toContain("Could not resolve reference");
    expect(res.rerenderDiagnostic).toContain("spec.c4");
    // The empty model was NEVER committed over the good one.
    const jsonCommit = mocks.githubApiPost.mock.calls.find((c) =>
      String(c[1]).endsWith("/diagrams/model.likec4.json"),
    );
    expect(jsonCommit).toBeFalsy();
    expect(mocks.reportSilentFallback).toHaveBeenCalled();
  });

  it("AC2e: a non-source-fault failure (oversized model) carries NO rerenderDiagnostic", async () => {
    mocks.renderC4Model.mockResolvedValue({
      ok: true,
      durationMs: 12,
      json: "x".repeat(8 * 1024 * 1024),
    });
    const res = await writeC4Diagram(source(C4));
    expect(res.ok).toBe(true);
    if (!res.ok) return;
    expect(res.rerendered).toBe(false);
    // No likec4 diagnostic for an internal failure — the user's source is fine.
    expect(res.rerenderDiagnostic).toBeUndefined();
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
