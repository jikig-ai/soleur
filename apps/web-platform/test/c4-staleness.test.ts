import { describe, it, expect, vi, beforeEach } from "vitest";

// Derived staleness for GET /api/kb/c4/project (#8966 PR-B). The banner becomes
// a RECOMPUTED fact: the newest `model.likec4.json` commit's dir listing —
// fetched via `contents/<dir>?ref=<commitSha>` — is content-diffed against the
// current Contents listing (already fetched by the route), so a dropped
// `c4_diagram_saved` frame, a remount, or an out-of-band source push can no
// longer lose the banner.
//
// The comparator is pure — this suite pins set/sha semantics directly against
// it, and drives the orchestrator through an injected GitHub `get` so the call
// plan (commits → at-commit contents → per-subdir recursive trees → grace tip)
// is covered without a network.

import {
  STALE_GRACE_MS,
  deriveDiagramStale,
  sourceSnapshot,
  snapshotsEqual,
} from "@/server/c4-staleness";

const DIR = "knowledge-base/engineering/architecture/diagrams"; // canonical dir — no chars needing per-segment encoding

// ─── sourceSnapshot: which listing entries participate in the compare ─────────

describe("sourceSnapshot — the likec4-relevant content of a dir listing", () => {
  it("keys source files and subdir tree shas; drops .md, model.likec4.json, and likec4-ignored dirs", () => {
    const snap = sourceSnapshot([
      { name: "model.c4", type: "file", sha: "s1" },
      { name: "extra.likec4", type: "file", sha: "s2" },
      { name: "dots.like-c4", type: "file", sha: "s3" },
      { name: "README.md", type: "file", sha: "s4" },
      { name: "model.likec4.json", type: "file", sha: "s5" },
      { name: "nested", type: "dir", sha: "d1" },
      { name: "node_modules", type: "dir", sha: "d2" },
    ]);
    expect(snap.get("f:model.c4")).toBe("s1");
    expect(snap.get("f:extra.likec4")).toBe("s2");
    expect(snap.get("f:dots.like-c4")).toBe("s3");
    expect(snap.get("d:nested")).toBe("d1");
    expect(snap.has("f:README.md")).toBe(false);
    expect(snap.has("f:model.likec4.json")).toBe(false);
    // likec4 never reads node_modules: its churn must not flag stale.
    expect(snap.has("d:node_modules")).toBe(false);
  });

  it("ignores a file named exactly like an extension (`.c4`)", () => {
    const snap = sourceSnapshot([{ name: ".c4", type: "file", sha: "s1" }]);
    expect(snap.size).toBe(0);
  });
});

describe("snapshotsEqual — the comparator", () => {
  const base = () =>
    new Map([
      ["f:model.c4", "s1"],
      ["f:views.c4", "s2"],
      ["d:nested", "d1"],
    ]);

  it("equal set + equal shas → equal (not stale)", () => {
    expect(snapshotsEqual(base(), base())).toBe(true);
  });

  it("a modified source (sha differs) → not equal", () => {
    const b = base();
    b.set("f:model.c4", "s1b");
    expect(snapshotsEqual(base(), b)).toBe(false);
  });

  it("an added source → not equal", () => {
    const b = base();
    b.set("f:new.c4", "s9");
    expect(snapshotsEqual(base(), b)).toBe(false);
  });

  it("a deleted source → not equal", () => {
    const b = base();
    b.delete("f:views.c4");
    expect(snapshotsEqual(base(), b)).toBe(false);
  });

  it("a nested-source change surfaces via the subdir tree sha → not equal", () => {
    const b = base();
    b.set("d:nested", "d1b");
    expect(snapshotsEqual(base(), b)).toBe(false);
  });

  it("an .md-only diff is invisible to the comparator", () => {
    // Neither side keys non-source files, so a README churn cannot flip the
    // verdict in either direction.
    expect(
      snapshotsEqual(
        sourceSnapshot([{ name: "README.md", type: "file", sha: "a" }]),
        sourceSnapshot([{ name: "README.md", type: "file", sha: "b" }]),
      ),
    ).toBe(true);
  });
});

// ─── deriveDiagramStale: the bounded call plan over an injected transport ────

type Call = string;
type Responder = (path: string) => unknown;

function fakeGet(handlers: Record<string, Responder>, calls: Call[]) {
  return async <T>(_inst: number, path: string): Promise<T> => {
    calls.push(path);
    for (const [match, fn] of Object.entries(handlers)) {
      if (path.includes(match)) return fn(path) as T;
    }
    throw new Error(`unexpected github path: ${path}`);
  };
}

const MODEL_COMMIT = {
  sha: "commit-model",
  commit: { tree: { sha: "tree-root" }, committer: { date: "2026-09-20T00:00:00Z" } },
};

// A repo whose dir listing at the model commit had sources {a.c4, spec.c4}
// and whose current listing still matches → not stale.
function wiredRepo(over: {
  commits?: Responder;
  dirCommits?: Responder;
  atCommit?: Responder;
  trees?: Record<string, Responder>;
} = {}) {
  const calls: Call[] = [];
  const get = fakeGet(
    {
      [`/commits?path=${DIR}/model.likec4.json`]: over.commits ?? (() => [MODEL_COMMIT]),
      [`/commits?path=${DIR}&per_page=1`]: over.dirCommits ?? (() => [
        { sha: "tip", commit: { committer: { date: "2020-01-01T00:00:00Z" } } },
      ]),
      [`/contents/${DIR}?ref=commit-model`]:
        over.atCommit ??
        (() => [
          { name: "a.c4", type: "file", sha: "sa" },
          { name: "spec.c4", type: "file", sha: "ss" },
          { name: "model.likec4.json", type: "file", sha: "sm" },
          { name: "README.md", type: "file", sha: "sr" },
        ]),
      ...(over.trees ?? {}),
    },
    calls,
  );
  const currentEntries = [
    { name: "a.c4", type: "file", sha: "sa" },
    { name: "spec.c4", type: "file", sha: "ss" },
    { name: "model.likec4.json", type: "file", sha: "sm2" },
    { name: "README.md", type: "file", sha: "sr2" },
  ];
  return { calls, get, currentEntries };
}

const ARGS = {
  installationId: 1,
  owner: "o",
  repo: "r",
  githubDir: DIR,
};

describe("deriveDiagramStale", () => {
  beforeEach(() => vi.clearAllMocks());

  it("identical source set+shas → stale:false (model.likec4.json / .md shas never enter the compare)", async () => {
    const { calls, get, currentEntries } = wiredRepo();
    const v = await deriveDiagramStale({ get, ...ARGS, currentEntries });
    expect(v).toBe(false);
    // Clean path is bounded: model-commit lookup + at-commit dir listing.
    expect(calls).toEqual([
      `/repos/o/r/commits?path=${DIR}/model.likec4.json&per_page=1`,
      `/repos/o/r/contents/${DIR}?ref=commit-model`,
    ]);
  });

  it("a modified source sha → stale:true; dir tip older than the grace window", async () => {
    const { get, currentEntries } = wiredRepo();
    currentEntries[0] = { name: "a.c4", type: "file", sha: "sa-CHANGED" };
    const v = await deriveDiagramStale({
      get, ...ARGS, currentEntries,
      now: () => Date.parse("2026-09-26T00:00:00Z"),
    });
    expect(v).toBe(true);
  });

  it("an added source in the listing → stale:true", async () => {
    const { get, currentEntries } = wiredRepo();
    currentEntries.push({ name: "new.likec4", type: "file", sha: "sn" });
    const v = await deriveDiagramStale({
      get, ...ARGS, currentEntries,
      now: () => Date.parse("2026-09-26T00:00:00Z"),
    });
    expect(v).toBe(true);
  });

  it("a source deleted out-of-band → stale:true", async () => {
    const { get, currentEntries } = wiredRepo();
    const kept = currentEntries.filter((e) => e.name !== "spec.c4");
    const v = await deriveDiagramStale({
      get, ...ARGS, currentEntries: kept,
      now: () => Date.parse("2026-09-26T00:00:00Z"),
    });
    expect(v).toBe(true);
  });

  it("a diff whose dir tip is younger than the render budget → ABSENT (in-flight two-commit window)", async () => {
    const now = Date.parse("2026-09-26T12:00:00Z");
    const { get, currentEntries } = wiredRepo({
      dirCommits: () => [
        // The dir's tip commit is seconds old — a save's source commit just
        // landed and its model commit is still rendering.
        { sha: "tip", commit: { committer: { date: new Date(now - 5_000).toISOString() } } },
      ],
    });
    currentEntries[0] = { name: "a.c4", type: "file", sha: "sa-CHANGED" };
    const v = await deriveDiagramStale({
      get, ...ARGS, currentEntries, now: () => now,
    });
    expect(v).toBeUndefined();
  });

  it("a diff whose dir tip is OLDER than the grace window → stale:true", async () => {
    const now = Date.parse("2026-09-26T12:00:00Z");
    const { get, currentEntries } = wiredRepo({
      dirCommits: () => [
        { sha: "tip", commit: { committer: { date: new Date(now - STALE_GRACE_MS - 1_000).toISOString() } } },
      ],
    });
    currentEntries[0] = { name: "a.c4", type: "file", sha: "sa-CHANGED" };
    const v = await deriveDiagramStale({
      get, ...ARGS, currentEntries, now: () => now,
    });
    expect(v).toBe(true);
  });

  it("no model commit at all (pre-render dir) → ABSENT, and no listing call is issued", async () => {
    const { calls, get, currentEntries } = wiredRepo({ commits: () => [] });
    const v = await deriveDiagramStale({ get, ...ARGS, currentEntries });
    expect(v).toBeUndefined();
    expect(calls).toEqual([`/repos/o/r/commits?path=${DIR}/model.likec4.json&per_page=1`]);
  });

  it("an at-commit listing that is not a directory → ABSENT + report (never a false verdict)", async () => {
    const { get, currentEntries } = wiredRepo({
      atCommit: () => ({ type: "file", sha: "x" }), // the dir was a file then
    });
    const report = vi.fn();
    const v = await deriveDiagramStale({
      get, ...ARGS, currentEntries, report: report as never,
    });
    expect(v).toBeUndefined();
    expect(report).toHaveBeenCalledTimes(1);
  });

  it("any GitHub failure → ABSENT + report with the stale-derivation op", async () => {
    const { get, currentEntries } = wiredRepo({
      commits: () => { throw new Error("rate limited"); },
    });
    const report = vi.fn();
    const v = await deriveDiagramStale({
      get, ...ARGS, currentEntries, report: report as never,
    });
    expect(v).toBeUndefined();
    expect(report).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ feature: "c4-project-read", op: "stale-derivation" }),
    );
  });

  it("a deadline overrun → ABSENT + report (the GET must not wait on a slow GitHub day)", async () => {
    const calls: Call[] = [];
    const get = async <T>(_inst: number, path: string): Promise<T> => {
      calls.push(path);
      return new Promise<T>(() => {}); // never resolves
    };
    const report = vi.fn();
    const v = await deriveDiagramStale({
      get, ...ARGS, currentEntries: [],
      deadlineMs: 25,
      report: report as never,
    });
    expect(v).toBeUndefined();
    expect(report).toHaveBeenCalledWith(
      null, // the deadline failure carries no thrown error by design
      expect.objectContaining({ op: "stale-derivation" }),
    );
  });

  // ─── the subdir recursion: non-source nested churn is not stale ──────────

  it("a nested .md churn (subdir tree sha moved, no source moved) → stale:false", async () => {
    const { get, currentEntries, calls } = wiredRepo({
      atCommit: () => [
        { name: "a.c4", type: "file", sha: "sa" },
        { name: "spec.c4", type: "file", sha: "ss" },
        { name: "nested", type: "dir", sha: "d1" },
      ],
      trees: {
        // Both sides' nested trees differ ONLY in a .md blob — the recursion
        // keys isSourceName paths only, so the compare is equal.
        "/git/trees/d1": () => ({
          tree: [
            { path: "n.c4", type: "blob", sha: "sn1" },
            { path: "README.md", type: "blob", sha: "m1" },
          ],
        }),
        "/git/trees/d2": () => ({
          tree: [
            { path: "n.c4", type: "blob", sha: "sn1" },
            { path: "README.md", type: "blob", sha: "m2-CHANGED" },
          ],
        }),
      },
    });
    currentEntries.push({ name: "nested", type: "dir", sha: "d2" });
    const v = await deriveDiagramStale({
      get, ...ARGS, currentEntries,
      now: () => Date.parse("2026-09-26T00:00:00Z"),
    });
    expect(v).toBe(false);
    // The recursion issued exactly one tree call per side.
    expect(calls.filter((c) => c.includes("/git/trees/"))).toEqual([
      `/repos/o/r/git/trees/d1?recursive=1`,
      `/repos/o/r/git/trees/d2?recursive=1`,
    ]);
  });

  it("a nested SOURCE change (subdir tree sha moved, source blob changed) → stale:true", async () => {
    const { get, currentEntries } = wiredRepo({
      atCommit: () => [
        { name: "a.c4", type: "file", sha: "sa" },
        { name: "nested", type: "dir", sha: "d1" },
      ],
      trees: {
        "/git/trees/d1": () => ({ tree: [{ path: "deep/n.c4", type: "blob", sha: "sn1" }] }),
        "/git/trees/d2": () => ({ tree: [{ path: "deep/n.c4", type: "blob", sha: "sn2" }] }),
      },
    });
    currentEntries.splice(2, currentEntries.length - 2); // drop model/json+md for clarity
    currentEntries.push({ name: "nested", type: "dir", sha: "d2" });
    const v = await deriveDiagramStale({
      get, ...ARGS, currentEntries,
      now: () => Date.parse("2026-09-26T00:00:00Z"),
    });
    expect(v).toBe(true);
  });

  it("a new subdir containing only non-source files → stale:false", async () => {
    const { get, currentEntries } = wiredRepo({
      atCommit: () => [
        { name: "a.c4", type: "file", sha: "sa" },
        { name: "spec.c4", type: "file", sha: "ss" },
      ],
      trees: {
        "/git/trees/d2": () => ({
          tree: [
            { path: "notes.md", type: "blob", sha: "m1" },
            { path: "node_modules", type: "tree", sha: "x" },
          ],
        }),
      },
    });
    currentEntries.push({ name: "docs", type: "dir", sha: "d2" });
    const v = await deriveDiagramStale({
      get, ...ARGS, currentEntries,
      now: () => Date.parse("2026-09-26T00:00:00Z"),
    });
    expect(v).toBe(false);
  });

  it("a new subdir CONTAINING a source → stale:true", async () => {
    const { get, currentEntries } = wiredRepo({
      trees: {
        "/git/trees/d2": () => ({
          tree: [{ path: "extra.c4", type: "blob", sha: "se" }],
        }),
      },
    });
    currentEntries.push({ name: "more", type: "dir", sha: "d2" });
    const v = await deriveDiagramStale({
      get, ...ARGS, currentEntries,
      now: () => Date.parse("2026-09-26T00:00:00Z"),
    });
    expect(v).toBe(true);
  });

  it("a nested source inside an ignored dir (node_modules under a subdir) cannot flag stale", async () => {
    const { get, currentEntries } = wiredRepo({
      atCommit: () => [
        { name: "a.c4", type: "file", sha: "sa" },
        { name: "spec.c4", type: "file", sha: "ss" },
        { name: "pkg", type: "dir", sha: "d1" },
      ],
      trees: {
        // Sources live only under a nested node_modules — invisible to likec4.
        "/git/trees/d1": () => ({
          tree: [{ path: "node_modules/x.c4", type: "blob", sha: "i1" }],
        }),
        "/git/trees/d2": () => ({
          tree: [{ path: "node_modules/x.c4", type: "blob", sha: "i2" }],
        }),
      },
    });
    currentEntries.push({ name: "pkg", type: "dir", sha: "d2" });
    const v = await deriveDiagramStale({
      get, ...ARGS, currentEntries,
      now: () => Date.parse("2026-09-26T00:00:00Z"),
    });
    expect(v).toBe(false);
  });

  it("a truncated subdir tree → ABSENT + report (a non-answer, never a verdict)", async () => {
    const { get, currentEntries } = wiredRepo({
      atCommit: () => [
        { name: "a.c4", type: "file", sha: "sa" },
        { name: "spec.c4", type: "file", sha: "ss" },
        { name: "nested", type: "dir", sha: "d1" },
      ],
      trees: {
        "/git/trees/d1": () => ({ truncated: true }),
        "/git/trees/d2": () => ({ tree: [] }),
      },
    });
    currentEntries.push({ name: "nested", type: "dir", sha: "d2" });
    const report = vi.fn();
    const v = await deriveDiagramStale({
      get, ...ARGS, currentEntries, report: report as never,
      now: () => Date.parse("2026-09-26T00:00:00Z"),
    });
    expect(v).toBeUndefined();
    expect(report).toHaveBeenCalledTimes(1);
  });
});
