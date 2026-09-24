// #8623: pinning the render to its own commit means an older render can finish
// last. The model PUT carries the rendered commit's model sha, so the newer
// model on HEAD makes it fail (409) and the HEAD re-list decides retry vs
// superseded. Driven against a STATEFUL fake that enforces the Contents PUT
// `sha` precondition (test/helpers/fake-github-trees.ts); the real
// stageCommittedC4Sources runs, only the likec4 spawn is replaced.
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  createFakeGitHub,
  FakeGitHubApiError,
  type FakeGitHub,
} from "./helpers/fake-github-trees";

const h = vi.hoisted(() => ({
  fake: null as FakeGitHub | null,
  gates: [] as Array<() => void>,
  rendered: [] as string[],
  reportSilentFallback: vi.fn(),
  warnSilentFallback: vi.fn(),
  loggerWarn: vi.fn(),
  postOverride: null as null | ((path: string) => void),
}));

vi.mock("@/server/github-api", () => ({
  githubApiGet: (...a: [number, string, { signal?: AbortSignal }?]) => h.fake!.get(...a),
  githubApiPost: (i: number, path: string, body: { content: string; sha?: string }, m?: string) => {
    h.postOverride?.(path);
    return h.fake!.post(i, path, body, m);
  },
  GitHubApiError: FakeGitHubApiError,
}));
vi.mock("@/server/workspace-sync", () => ({ syncWorkspace: async () => ({ ok: true }) }));
vi.mock("@/server/observability", async () => {
  const actual = await vi.importActual<typeof import("@/server/observability")>("@/server/observability");
  return {
    ...actual,
    reportSilentFallback: h.reportSilentFallback,
    warnSilentFallback: h.warnSilentFallback,
  };
});
vi.mock("@/server/logger", () => ({
  default: { info: vi.fn(), error: vi.fn(), warn: h.loggerWarn },
}));
vi.mock("@sentry/nextjs", () => ({ captureException: vi.fn() }));
// Replace only the likec4 spawn: run the REAL stage function into a temp dir,
// then "render" the staged model.c4 bytes as the model, gated so the test
// decides which render finishes first.
vi.mock("@/server/c4-render", () => ({
  renderC4Model: async (stage: (d: string, s: AbortSignal) => Promise<{ ok: boolean }>) => {
    const dir = mkdtempSync(join(tmpdir(), "c4-conc-"));
    try {
      const staged = await stage(join(dir, "src"), new AbortController().signal);
      if (!staged.ok) return { ...staged, phase: "stage" };
      const src = readFileSync(join(dir, "src", "model.c4"), "utf8");
      h.rendered.push(src);
      await new Promise<void>((r) => h.gates.push(r));
      return { ok: true, durationMs: 1, json: `rendered:${src}` };
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  },
}));

import { writeC4Diagram } from "@/server/c4-writer";

const D = "knowledge-base/engineering/architecture/diagrams";
const MODEL = `${D}/model.likec4.json`;
const C4 = "engineering/architecture/diagrams/model.c4";

function save(content: string) {
  return writeC4Diagram({
    userId: "00000000-0000-0000-0000-000000000001",
    installationId: 1,
    owner: "o",
    repo: "r",
    workspacePath: "/workspaces/ws-1",
    relativePath: C4,
    content,
  });
}

beforeEach(() => {
  h.fake = createFakeGitHub({
    [`${D}/model.c4`]: { mode: "100644", content: "v0" },
    [MODEL]: { mode: "100644", content: "rendered:v0" },
  });
  h.gates = [];
  h.rendered = [];
  h.postOverride = null;
  for (const f of [h.reportSilentFallback, h.warnSilentFallback, h.loggerWarn]) f.mockReset();
});
afterEach(() => {
  h.fake = null;
});

describe("writeC4Diagram — concurrent saves (#8623)", () => {
  it("two saves of the SAME file finishing in reverse order leave the NEWER model on HEAD", async () => {
    const a = save("vA");
    await vi.waitFor(() => expect(h.gates.length).toBe(1));
    const b = save("vB");
    await vi.waitFor(() => expect(h.gates.length).toBe(2));
    expect(h.rendered).toEqual(["vA", "vB"]);

    h.gates[1](); // B's render finishes first
    const rb = await b;
    h.gates[0](); // A's (older) render finishes last
    const ra = await a;

    expect(rb).toMatchObject({ ok: true, rerendered: true });
    expect(ra).toMatchObject({ ok: true, rerendered: false });
    if (ra.ok) expect(ra.rerenderDiagnostic).toBeUndefined();
    expect(h.fake!.fileAt(h.fake!.head(), MODEL)).toBe("rendered:vB");
    // Superseded is not an incident: a warn line (ships to Better Stack), no Sentry.
    expect(h.loggerWarn).toHaveBeenCalledWith(
      expect.objectContaining({ event: "c4_rerender_superseded" }),
      expect.any(String),
    );
    expect(h.reportSilentFallback).not.toHaveBeenCalled();
  });

  it("a 409 whose HEAD holds the SAME sources (model changed elsewhere, README too) retries once and lands", async () => {
    const a = save("vA");
    await vi.waitFor(() => expect(h.gates.length).toBe(1));
    // Another writer touches the model and a README; the sources are unchanged.
    h.fake!.commit({
      [MODEL]: { mode: "100644", content: "someone-else" },
      [`${D}/README.md`]: { mode: "100644", content: "docs" },
    });
    h.gates[0]();
    const ra = await a;
    expect(ra).toMatchObject({ ok: true, rerendered: true });
    expect(h.fake!.fileAt(h.fake!.head(), MODEL)).toBe("rendered:vA");
    const modelPuts = h.fake!.calls.filter((c) => c === `PUT /repos/o/r/contents/${MODEL}`);
    expect(modelPuts).toHaveLength(2);
  });

  it("a second 409 after the retry is reported once as commit-json and never loops", async () => {
    h.postOverride = (path) => {
      if (path.endsWith("model.likec4.json")) {
        h.fake!.calls.push(`PUT ${path}`);
        throw new FakeGitHubApiError("sha mismatch", 409);
      }
    };
    const a = save("vA");
    await vi.waitFor(() => expect(h.gates.length).toBe(1));
    h.gates[0]();
    const ra = await a;
    expect(ra).toMatchObject({ ok: true, rerendered: false });
    const modelPuts = h.fake!.calls.filter((c) => c === `PUT /repos/o/r/contents/${MODEL}`);
    expect(modelPuts).toHaveLength(2);
    expect(h.reportSilentFallback).toHaveBeenCalledTimes(1);
    expect(h.reportSilentFallback.mock.calls[0][1]).toMatchObject({ op: "commit-json" });
  });

  it("the model PUT carries the RENDERED commit's model sha, not a fresh HEAD read", async () => {
    const a = save("vA");
    await vi.waitFor(() => expect(h.gates.length).toBe(1));
    h.gates[0]();
    await a;
    // The only reads of the model path are listings — never a Contents GET of
    // model.likec4.json before the PUT.
    expect(h.fake!.calls.some((c) => c.startsWith(`GET /repos/o/r/contents/${MODEL}`))).toBe(false);
  });

  it("a committed likec4 config is refused end to end: no model commit, class diagnostic", async () => {
    h.fake!.commit({ [`${D}/likec4.config.mjs`]: { mode: "100644", content: "boom" } });
    const res = await save("vA");
    expect(res).toMatchObject({ ok: true, rerendered: false });
    if (res.ok) expect(res.rerenderDiagnostic).toContain('"likec4.config.mjs" (a likec4 config file)');
    expect(h.fake!.calls.filter((c) => c.includes("/git/blobs/"))).toHaveLength(0);
    expect(h.fake!.fileAt(h.fake!.head(), MODEL)).toBe("rendered:v0");
  });
});
