import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import type { BoardIssueInput } from "@/lib/workstream";

// The accessor's IO collaborators are ALL mocked — there are NO live network
// calls. We assert the empty-vs-throw contract and the mapping wiring.

const readCurrentRepoUrlResult = vi.fn();
const resolveInstallationId = vi.fn();
const resolveEffectiveInstallationId = vi.fn();
const listRepoIssues = vi.fn();
const fetchBoardStatusMap = vi.fn();
const reportSilentFallback = vi.fn();
const getAppSlug = vi.fn();

vi.mock("@/server/current-repo-url", () => ({
  readCurrentRepoUrlResult: (...a: unknown[]) => readCurrentRepoUrlResult(...a),
}));
vi.mock("@/server/resolve-installation-id", () => ({
  resolveInstallationId: (...a: unknown[]) => resolveInstallationId(...a),
}));
vi.mock("@/server/cc-effective-installation", () => ({
  resolveEffectiveInstallationId: (...a: unknown[]) =>
    resolveEffectiveInstallationId(...a),
}));
vi.mock("@/server/github-read-tools", () => ({
  listRepoIssues: (...a: unknown[]) => listRepoIssues(...a),
  fetchBoardStatusMap: (...a: unknown[]) => fetchBoardStatusMap(...a),
}));
vi.mock("@/server/observability", () => ({
  reportSilentFallback: (...a: unknown[]) => reportSilentFallback(...a),
}));
vi.mock("@/server/github-app", () => ({
  getAppSlug: (...a: unknown[]) => getAppSlug(...a),
}));

import {
  getWorkstreamIssues,
  resolveBoardReadContext,
  streamWorkstreamIssues,
} from "@/server/workstream/get-workstream-issues";
import type { WorkstreamFeedEvent } from "@/lib/workstream-feed";

function rawIssue(over: Partial<BoardIssueInput> = {}): BoardIssueInput {
  return {
    number: 5652,
    title: "Tighten the gap",
    body: "the body",
    assignees: ["harry"],
    labels: ["domain/engineering", "priority/p1-high", "in-progress"],
    state: "open",
    state_reason: null,
    created_at: "2026-06-20T09:00:00.000Z",
    updated_at: "2026-06-21T09:00:00.000Z",
    ...over,
  };
}

beforeEach(() => {
  readCurrentRepoUrlResult.mockResolvedValue({
    url: "https://github.com/acme/widgets",
    degraded: false,
  });
  resolveInstallationId.mockResolvedValue(123);
  resolveEffectiveInstallationId.mockResolvedValue(123);
  listRepoIssues.mockResolvedValue([]);
  fetchBoardStatusMap.mockResolvedValue(new Map());
  getAppSlug.mockResolvedValue("soleur-ai");
});
afterEach(() => {
  vi.clearAllMocks();
  vi.unstubAllEnvs();
});

describe("getWorkstreamIssues", () => {
  it("returns [] (honest empty) when no repo is connected — no reader call (AC3)", async () => {
    readCurrentRepoUrlResult.mockResolvedValue({ url: null, degraded: false });
    const out = await getWorkstreamIssues("u1");
    expect(out).toEqual([]);
    expect(listRepoIssues).not.toHaveBeenCalled();
    expect(reportSilentFallback).not.toHaveBeenCalled();
  });

  it("returns [] (honest empty) for a connected repo whose reader yields zero issues (AC3)", async () => {
    listRepoIssues.mockResolvedValue([]);
    const out = await getWorkstreamIssues("u1");
    expect(out).toEqual([]);
    expect(reportSilentFallback).not.toHaveBeenCalled();
  });

  it("THROWS + mirrors (op:repo-unresolved) BEFORE the throw on a P2 degraded read (AC1)", async () => {
    const { WorkstreamDegradedError } = await import("@/lib/workstream");
    readCurrentRepoUrlResult.mockResolvedValue({ url: null, degraded: true });
    // mirror-precedes-throw: the report fires and no install/list call happens.
    await expect(getWorkstreamIssues("u1")).rejects.toBeInstanceOf(
      WorkstreamDegradedError,
    );
    expect(reportSilentFallback).toHaveBeenCalledWith(
      expect.any(Error),
      expect.objectContaining({ feature: "workstream", op: "repo-unresolved" }),
    );
    expect(resolveInstallationId).not.toHaveBeenCalled();
    expect(listRepoIssues).not.toHaveBeenCalled();
  });

  it("THROWS + mirrors (op:no-installation) when repo present but installation is null (P1, AC2)", async () => {
    const { WorkstreamDegradedError } = await import("@/lib/workstream");
    resolveEffectiveInstallationId.mockResolvedValue(null);
    await expect(getWorkstreamIssues("u1")).rejects.toBeInstanceOf(
      WorkstreamDegradedError,
    );
    expect(listRepoIssues).not.toHaveBeenCalled();
    expect(reportSilentFallback).toHaveBeenCalledWith(
      expect.any(Error),
      expect.objectContaining({ feature: "workstream", op: "no-installation" }),
    );
  });

  it("maps the reader output via the pure mapper for a connected repo", async () => {
    listRepoIssues.mockResolvedValue([rawIssue()]);
    const out = await getWorkstreamIssues("u1");
    expect(listRepoIssues).toHaveBeenCalledWith(123, "acme", "widgets");
    expect(out).toHaveLength(1);
    expect(out[0]).toMatchObject({
      id: "5652",
      title: "Tighten the gap",
      description: "the body",
      status: "in_progress",
      priority: "high",
      assigneeRole: "cto",
      user: { name: "harry", initials: "HA" },
      live: true,
    });
  });

  it("propagates (throws) a GitHub reader error — never masquerades as empty", async () => {
    listRepoIssues.mockRejectedValue(new Error("GitHub API 403"));
    await expect(getWorkstreamIssues("u1")).rejects.toThrow("GitHub API 403");
  });

  it("prefers the canonical board Status over label derivation (Phase 2)", async () => {
    vi.stubEnv("SOLEUR_KANBAN_ORG", "acme");
    vi.stubEnv("SOLEUR_KANBAN_PROJECT_NUMBER", "2");
    listRepoIssues.mockResolvedValue([rawIssue()]); // labels would derive in_progress
    fetchBoardStatusMap.mockResolvedValue(new Map([[5652, "Pending"]]));
    const out = await getWorkstreamIssues("u1");
    expect(fetchBoardStatusMap).toHaveBeenCalledWith(123, "acme", 2, "acme/widgets");
    expect(out[0].status).toBe("pending"); // board Status wins over the in-progress label
  });

  it("falls back to label derivation + mirrors to Sentry when the board read fails", async () => {
    vi.stubEnv("SOLEUR_KANBAN_ORG", "acme");
    vi.stubEnv("SOLEUR_KANBAN_PROJECT_NUMBER", "2");
    listRepoIssues.mockResolvedValue([rawIssue()]);
    fetchBoardStatusMap.mockRejectedValue(new Error("GitHub API 403"));
    const out = await getWorkstreamIssues("u1");
    expect(out[0].status).toBe("in_progress"); // label fallback, never throws
    expect(reportSilentFallback).toHaveBeenCalledWith(
      expect.any(Error),
      expect.objectContaining({ feature: "workstream", op: "board-status-read" }),
    );
  });

  it("skips the board read when the repo owner is not the configured board org", async () => {
    vi.stubEnv("SOLEUR_KANBAN_ORG", "jikig-ai");
    vi.stubEnv("SOLEUR_KANBAN_PROJECT_NUMBER", "2");
    listRepoIssues.mockResolvedValue([rawIssue()]);
    const out = await getWorkstreamIssues("u1");
    expect(fetchBoardStatusMap).not.toHaveBeenCalled();
    expect(out[0].status).toBe("in_progress"); // label derivation
  });

  // --- Creator attribution (PART A) ---------------------------------------

  it("threads the GitHub author into creator (human author)", async () => {
    listRepoIssues.mockResolvedValue([rawIssue({ authorLogin: "octocat" })]);
    const out = await getWorkstreamIssues("u1");
    expect(out[0].creator).toEqual({
      login: "octocat",
      isSoleur: false,
      display: { name: "octocat", initials: "OC" },
    });
  });

  it("detects the slug-derived Soleur bot + surfaces the marker initiator", async () => {
    listRepoIssues.mockResolvedValue([
      rawIssue({
        authorLogin: "soleur-ai[bot]",
        body: "Optimize static pages\n<!-- soleur:initiated-by harry -->",
      }),
    ]);
    const out = await getWorkstreamIssues("u1");
    expect(out[0].creator?.isSoleur).toBe(true);
    expect(out[0].creator?.initiatorLogin).toBe("harry");
  });

  it("degrades gracefully (author rendered as human, no throw) + mirrors when getAppSlug fails", async () => {
    getAppSlug.mockRejectedValue(new Error("GH /app 500"));
    listRepoIssues.mockResolvedValue([
      rawIssue({ authorLogin: "soleur-ai[bot]" }),
    ]);
    const out = await getWorkstreamIssues("u1");
    // botSlug unresolved → biases to human (isSoleur false); never throws.
    expect(out[0].creator?.isSoleur).toBe(false);
    expect(reportSilentFallback).toHaveBeenCalledWith(
      expect.any(Error),
      expect.objectContaining({
        feature: "workstream",
        op: "workstream-botslug-degrade",
      }),
    );
  });
});

// --- Progressive feed (streamWorkstreamIssues) -------------------------------
//
// The streamed accessor emits delta frames: meta → issues* (one per upstream
// REST page, plus ONE reconcile `issues` frame carrying the full re-mapped
// cards for already-emitted issues whose column/`live` changed once board
// precedence lands) → done. A mid-loop failure emits `error` then rethrows;
// an aborted consumer (isAborted) stops the upstream walk silently.
// Degradation semantics are unchanged: resolution throws
// WorkstreamDegradedError BEFORE the stream exists (route maps it to a real
// 502, never an SSE body).

function collect(): { events: WorkstreamFeedEvent[]; emit: (e: WorkstreamFeedEvent) => void } {
  const events: WorkstreamFeedEvent[] = [];
  return { events, emit: (e) => events.push(e) };
}

async function streamFor(userId = "u1") {
  const ctx = await resolveBoardReadContext(userId);
  const { events, emit } = collect();
  await streamWorkstreamIssues(ctx, emit);
  return events;
}

describe("resolveBoardReadContext", () => {
  it("throws WorkstreamDegradedError on a degraded repo-url read (before any stream)", async () => {
    const { WorkstreamDegradedError } = await import("@/lib/workstream");
    readCurrentRepoUrlResult.mockResolvedValue({ url: null, degraded: true });
    await expect(resolveBoardReadContext("u1")).rejects.toBeInstanceOf(
      WorkstreamDegradedError,
    );
    expect(reportSilentFallback).toHaveBeenCalledWith(
      expect.any(Error),
      expect.objectContaining({ feature: "workstream", op: "repo-unresolved" }),
    );
  });

  it("returns kind:empty when no repo is connected", async () => {
    readCurrentRepoUrlResult.mockResolvedValue({ url: null, degraded: false });
    const ctx = await resolveBoardReadContext("u1");
    expect(ctx.kind).toBe("empty");
    expect(ctx.board).toEqual({ onKanbanOrg: false, projectWritable: false });
  });

  it("computes board meta from the resolved owner + env (single repo read)", async () => {
    vi.stubEnv("SOLEUR_KANBAN_ORG", "acme");
    vi.stubEnv("SOLEUR_KANBAN_PROJECT_WRITABLE", "1");
    const ctx = await resolveBoardReadContext("u1");
    expect(ctx.board).toEqual({ onKanbanOrg: true, projectWritable: true });
    // One repo-URL resolution — meta rides ctx, no second DB read.
    expect(readCurrentRepoUrlResult).toHaveBeenCalledTimes(1);
  });

  it("throws WorkstreamDegradedError when installation is unresolvable", async () => {
    const { WorkstreamDegradedError } = await import("@/lib/workstream");
    resolveEffectiveInstallationId.mockResolvedValue(null);
    await expect(resolveBoardReadContext("u1")).rejects.toBeInstanceOf(
      WorkstreamDegradedError,
    );
    expect(reportSilentFallback).toHaveBeenCalledWith(
      expect.any(Error),
      expect.objectContaining({ feature: "workstream", op: "no-installation" }),
    );
  });
});

describe("streamWorkstreamIssues", () => {
  it("emits meta → issues per page → done, one frame per non-empty page", async () => {
    const page1 = [rawIssue({ number: 1 }), rawIssue({ number: 2 })];
    const page2 = [rawIssue({ number: 3 })];
    listRepoIssues.mockImplementation(
      async (_id: number, _o: string, _r: string, hooks?: { onBatch?: (items: BoardIssueInput[]) => void }) => {
        hooks?.onBatch?.(page1);
        hooks?.onBatch?.([]); // all-PR page → no frame
        hooks?.onBatch?.(page2);
        return [...page1, ...page2];
      },
    );
    const events = await streamFor();
    const types = events.map((e) => e.type);
    expect(types).toEqual(["meta", "issues", "issues", "done"]);
    expect(events[0]).toEqual({
      type: "meta",
      board: { onKanbanOrg: false, projectWritable: false },
    });
    const frames = events.filter((e) => e.type === "issues");
    expect(frames[0].issues.map((i) => i.id)).toEqual(["1", "2"]);
    expect(frames[1].issues.map((i) => i.id)).toEqual(["3"]);
    expect(events.at(-1)).toEqual({ type: "done", openTruncated: false });
  });

  it("emits meta + done only for an honest-empty board (no repo connected)", async () => {
    readCurrentRepoUrlResult.mockResolvedValue({ url: null, degraded: false });
    const events = await streamFor();
    expect(events.map((e) => e.type)).toEqual(["meta", "done"]);
    expect(listRepoIssues).not.toHaveBeenCalled();
  });

  it("propagates the open-page-cap flag into done.openTruncated", async () => {
    listRepoIssues.mockImplementation(
      async (_id: number, _o: string, _r: string, hooks?: { onBatch?: (i: BoardIssueInput[]) => void; onOpenTruncated?: () => void }) => {
        hooks?.onBatch?.([rawIssue({ number: 1 })]);
        hooks?.onOpenTruncated?.();
        return [rawIssue({ number: 1 })];
      },
    );
    const events = await streamFor();
    expect(events.at(-1)).toEqual({ type: "done", openTruncated: true });
  });

  it("emits ONE reconcile `issues` frame with the full re-mapped card for ONLY already-emitted issues that changed (AC5)", async () => {
    vi.stubEnv("SOLEUR_KANBAN_ORG", "acme");
    vi.stubEnv("SOLEUR_KANBAN_PROJECT_NUMBER", "2");
    let resolveMap!: (m: Map<number, string>) => void;
    fetchBoardStatusMap.mockImplementation(
      () => new Promise<Map<number, string>>((r) => (resolveMap = r)),
    );
    const early = rawIssue({ number: 1, labels: ["domain/engineering"] }); // label → backlog
    const late = rawIssue({ number: 2, labels: ["domain/engineering"] });
    listRepoIssues.mockImplementation(
      async (_id: number, _o: string, _r: string, hooks?: { onBatch?: (items: BoardIssueInput[]) => void }) => {
        hooks?.onBatch?.([early]); // emitted BEFORE the map lands → backlog
        resolveMap(new Map([[1, "In review"], [2, "Pending"]]));
        // A macrotask yield flushes the readBoardStatuses → reconcile microtask
        // chain, mirroring the real network-await gap between upstream pages.
        await new Promise((r) => setTimeout(r, 0));
        hooks?.onBatch?.([late]); // emitted AFTER → carries board status inline
        return [early, late];
      },
    );
    const events = await streamFor();
    const types = events.map((e) => e.type);
    expect(types).toEqual(["meta", "issues", "issues", "issues", "done"]);
    const frames = events.filter((e) => e.type === "issues");
    // The reconcile frame carries the FULL re-mapped card (whole-object upsert).
    expect(frames[1].issues).toEqual([
      expect.objectContaining({ id: "1", status: "in_review" }),
    ]);
    // The late page needed no reconcile — it emitted with board status inline.
    expect(frames[2].issues[0].status).toBe("pending");
  });

  it("still flushes the reconcile before done when the map lands after the last page", async () => {
    vi.stubEnv("SOLEUR_KANBAN_ORG", "acme");
    vi.stubEnv("SOLEUR_KANBAN_PROJECT_NUMBER", "2");
    let resolveMap!: (m: Map<number, string>) => void;
    fetchBoardStatusMap.mockImplementation(
      () => new Promise<Map<number, string>>((r) => (resolveMap = r)),
    );
    const early = rawIssue({ number: 1, labels: ["domain/engineering"] });
    listRepoIssues.mockImplementation(
      async (
        _id: number,
        _o: string,
        _r: string,
        hooks?: { onBatch?: (items: BoardIssueInput[]) => void },
      ) => {
        hooks?.onBatch?.([early]);
        // The map lands only AFTER the page loop returns — the post-loop
        // `await boardPromise` is what pins reconcile-before-done.
        setTimeout(() => resolveMap(new Map([[1, "In review"]])), 0);
        return [early];
      },
    );
    const events = await streamFor();
    const types = events.map((e) => e.type);
    expect(types).toEqual(["meta", "issues", "issues", "done"]);
    expect(events[2]).toEqual({
      type: "issues",
      issues: [expect.objectContaining({ id: "1", status: "in_review" })],
    });
  });

  it("stops the upstream walk silently when the consumer aborted (no error frame, no throw)", async () => {
    let aborted = false;
    listRepoIssues.mockImplementation(
      async (
        _id: number,
        _o: string,
        _r: string,
        hooks?: { onBatch?: (items: BoardIssueInput[]) => void },
      ) => {
        hooks?.onBatch?.([rawIssue({ number: 1 })]);
        aborted = true; // consumer went away mid-feed
        hooks?.onBatch?.([rawIssue({ number: 2 })]); // fires the abort check
        return [];
      },
    );
    const ctx = await resolveBoardReadContext("u1");
    const { events, emit } = collect();
    await expect(
      streamWorkstreamIssues(ctx, emit, () => aborted),
    ).resolves.toBeUndefined();
    // Only the pre-abort batch emitted; no error frame, no done.
    expect(events.map((e) => e.type)).toEqual(["meta", "issues"]);
  });

  it("emits error then rethrows when the page loop fails mid-feed", async () => {
    listRepoIssues.mockImplementation(
      async (_id: number, _o: string, _r: string, hooks?: { onBatch?: (items: BoardIssueInput[]) => void }) => {
        hooks?.onBatch?.([rawIssue({ number: 1 })]);
        throw new Error("GitHub API 403");
      },
    );
    const ctx = await resolveBoardReadContext("u1");
    const { events, emit } = collect();
    await expect(streamWorkstreamIssues(ctx, emit)).rejects.toThrow(
      "GitHub API 403",
    );
    expect(events.map((e) => e.type)).toEqual(["meta", "issues", "error"]);
    expect(events.at(-1)).toEqual({
      type: "error",
      code: "workstream_query_error",
    });
  });
});
