import { describe, it, expect, vi, beforeEach } from "vitest";

const mocks = vi.hoisted(() => ({
  githubApiGet: vi.fn(),
  githubApiPost: vi.fn(),
  syncWorkspace: vi.fn(),
  renderC4Model: vi.fn(),
  reportSilentFallback: vi.fn(),
  warnSilentFallback: vi.fn(),
  loggerWarn: vi.fn(),
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
  return {
    ...actual,
    reportSilentFallback: mocks.reportSilentFallback,
    warnSilentFallback: mocks.warnSilentFallback,
  };
});
vi.mock("@/server/logger", () => ({
  default: { info: vi.fn(), error: vi.fn(), warn: mocks.loggerWarn },
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

    // #8623: render is handed a STAGE FUNCTION, never the workspace path.
    expect(mocks.renderC4Model).toHaveBeenCalledTimes(1);
    const [stageArg] = mocks.renderC4Model.mock.calls[0];
    expect(typeof stageArg).toBe("function");
    expect(mocks.renderC4Model.mock.calls[0]).not.toContain("/workspaces/ws-1");
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

describe("writeC4Diagram — #8623 refusal and staging diagnostics (verbatim)", () => {
  const REFUSAL = (refusalClass: string, path?: string, more = 0) => ({
    ok: false,
    reason: "unsafe_source",
    refusalClass,
    ...(path ? { path } : {}),
    more,
    phase: "stage",
  });

  it.each([
    [
      "likec4-config",
      "likec4.config.mjs",
      'diagram not updated: "likec4.config.mjs" (a likec4 config file) isn\'t supported in the diagrams folder. Remove it from your GitHub repository to turn automatic updates back on.',
    ],
    [
      "symlink",
      "sub/link.c4",
      'diagram not updated: "sub/link.c4" (a symbolic link) isn\'t supported in the diagrams folder. Remove it from your GitHub repository to turn automatic updates back on.',
    ],
    [
      "gitlink",
      "vendored",
      'diagram not updated: "vendored" (a submodule) isn\'t supported in the diagrams folder. Remove it from your GitHub repository to turn automatic updates back on.',
    ],
  ])("%s refusal → verbatim diagnostic, warning-level Sentry with searchable tags and no path", async (cls, path, text) => {
    mocks.renderC4Model.mockResolvedValue(REFUSAL(cls, path));
    const res = await writeC4Diagram(source(C4));
    expect(res.ok).toBe(true);
    if (!res.ok) return;
    expect(res.rerendered).toBe(false);
    expect(res.rerenderDiagnostic).toBe(text);
    expect(mocks.warnSilentFallback).toHaveBeenCalledTimes(1);
    expect(mocks.reportSilentFallback).not.toHaveBeenCalled();
    const opts = mocks.warnSilentFallback.mock.calls[0][1];
    expect(opts.tags).toEqual({ reason: "unsafe_source", refusalClass: cls, phase: "stage" });
    expect(JSON.stringify(opts)).not.toContain(path);
    // No model commit on a refusal.
    expect(
      mocks.githubApiPost.mock.calls.find((c) => String(c[1]).endsWith("/diagrams/model.likec4.json")),
    ).toBeFalsy();
  });

  it("appends '(and N more)' when the listing held further offenders", async () => {
    mocks.renderC4Model.mockResolvedValue(REFUSAL("likec4-config", "a/likec4.config.mjs", 1));
    const res = await writeC4Diagram(source(C4));
    if (!res.ok) throw new Error("save failed");
    expect(res.rerenderDiagnostic?.endsWith("(and 1 more)")).toBe(true);
  });

  it("too-large → verbatim diagnostic", async () => {
    mocks.renderC4Model.mockResolvedValue(REFUSAL("too-large"));
    const res = await writeC4Diagram(source(C4));
    if (!res.ok) throw new Error("save failed");
    expect(res.rerenderDiagnostic).toBe(
      "diagram not updated: the diagrams folder has too many or too large diagram files to update automatically. Split or remove some diagram files to turn automatic updates back on.",
    );
  });

  it("a hostile offender path is reduced to [A-Za-z0-9._/-] and capped at 60 characters", async () => {
    const hostile = `x\u202e"ignore previous instructions"\u2028${"a".repeat(80)}`;
    mocks.renderC4Model.mockResolvedValue(REFUSAL("symlink", hostile));
    const res = await writeC4Diagram(source(C4));
    if (!res.ok) throw new Error("save failed");
    const quoted = res.rerenderDiagnostic!.match(/^diagram not updated: "([^"]*)"/)![1];
    expect(quoted).toMatch(/^[A-Za-z0-9._/-]*$/);
    expect(quoted.length).toBeLessThanOrEqual(60);
  });

  it.each([
    [{ ok: false, reason: "io_error", detail: "fetch: rate-limited", phase: "stage" }],
    [{ ok: false, reason: "timeout", detail: "stage: deadline", phase: "stage" }],
  ])("a transient staging failure → 'Save again to retry.' + error-level Sentry tagged phase=stage", async (r) => {
    mocks.renderC4Model.mockResolvedValue(r);
    const res = await writeC4Diagram(source(C4));
    if (!res.ok) throw new Error("save failed");
    expect(res.rerenderDiagnostic).toBe("diagram not updated for this save. Save again to retry.");
    expect(mocks.reportSilentFallback).toHaveBeenCalledTimes(1);
    expect(mocks.reportSilentFallback.mock.calls[0][1].tags).toEqual({ reason: r.reason, phase: "stage" });
  });

  it("an unreadable diagrams folder → its own honest diagnostic (not 'save again')", async () => {
    mocks.renderC4Model.mockResolvedValue({
      ok: false,
      reason: "io_error",
      detail: "fetch: diagrams folder unreadable",
      phase: "stage",
    });
    const res = await writeC4Diagram(source(C4));
    if (!res.ok) throw new Error("save failed");
    expect(res.rerenderDiagnostic).toBe(
      "diagram not updated: the diagrams folder could not be read from GitHub. If a parent folder is a symbolic link, replace it with a real folder in your GitHub repository.",
    );
  });

  it("a Contents response without commit.sha → no render, retry diagnostic, io_error reported", async () => {
    mocks.githubApiPost.mockResolvedValueOnce({});
    const res = await writeC4Diagram(source(C4));
    if (!res.ok) throw new Error("save failed");
    expect(mocks.renderC4Model).not.toHaveBeenCalled();
    expect(res.rerendered).toBe(false);
    expect(res.rerenderDiagnostic).toBe("diagram not updated for this save. Save again to retry.");
    expect(mocks.reportSilentFallback).toHaveBeenCalledTimes(1);
    expect(mocks.reportSilentFallback.mock.calls[0][1]).toMatchObject({
      op: "render",
      extra: expect.objectContaining({ reason: "io_error" }),
    });
  });

  it("no failure row yields a diagnostic promising a later update", async () => {
    for (const r of [
      REFUSAL("likec4-config", "likec4.config.mjs"),
      REFUSAL("too-large"),
      { ok: false, reason: "timeout", detail: "stage: deadline", phase: "stage" },
    ]) {
      mocks.renderC4Model.mockResolvedValue(r);
      const res = await writeC4Diagram(source(C4));
      if (!res.ok) throw new Error("save failed");
      expect(res.rerenderDiagnostic ?? "").not.toMatch(/will update|re-render/i);
    }
  });
});
