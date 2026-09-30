import { describe, expect, it, vi } from "vitest";
import type { WorkstreamIssue } from "@/lib/workstream";
import {
  applyStatusOverrides,
  fetchWorkstreamIssuesFeed,
  formatWorkstreamSseFrame,
  mergeStreamedIssues,
  parseWorkstreamSseChunks,
  type WorkstreamFeedEvent,
} from "@/lib/workstream-feed";

// Pure-helper tests for the progressive workstream feed (delta `issues` frames
// with upsert-by-id; never cumulative snapshots mid-stream — learning
// 2026-04-13). The fetcher tests drive a mocked `fetch` returning a real
// ReadableStream so chunk boundaries are exercised end-to-end.

function issue(over: Partial<WorkstreamIssue> = {}): WorkstreamIssue {
  return {
    id: "1",
    title: "Seed",
    description: "",
    status: "backlog",
    priority: "medium",
    assigneeRole: null,
    createdAt: "2026-09-01T00:00:00.000Z",
    updatedAt: "2026-09-01T00:00:00.000Z",
    ...over,
  };
}

function sseResponse(frames: string): Response {
  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      controller.enqueue(new TextEncoder().encode(frames));
      controller.close();
    },
  });
  return new Response(stream, {
    status: 200,
    headers: { "content-type": "text/event-stream; charset=utf-8" },
  });
}

describe("formatWorkstreamSseFrame / parseWorkstreamSseChunks", () => {
  it("round-trips every frame type", () => {
    const events: WorkstreamFeedEvent[] = [
      { type: "meta", board: { onKanbanOrg: true, projectWritable: false } },
      { type: "issues", issues: [issue({ id: "7" })] },
      {
        type: "statuses",
        overrides: [{ id: "7", status: "in_review", live: false }],
      },
      { type: "done", openTruncated: false },
      { type: "error", code: "workstream_query_error" },
    ];
    const buffer = events.map(formatWorkstreamSseFrame).join("");
    const { events: parsed, rest } = parseWorkstreamSseChunks(buffer);
    expect(rest).toBe("");
    expect(parsed).toEqual(events);
  });

  it("threads the unterminated tail across a chunk boundary", () => {
    const frame = formatWorkstreamSseFrame({
      type: "done",
      openTruncated: true,
    });
    const cut = Math.floor(frame.length / 2);
    const first = parseWorkstreamSseChunks(frame.slice(0, cut));
    expect(first.events).toHaveLength(0);
    expect(first.rest).toBe(frame.slice(0, cut));
    const second = parseWorkstreamSseChunks(first.rest + frame.slice(cut));
    expect(second.events).toEqual([
      { type: "done", openTruncated: true },
    ]);
    expect(second.rest).toBe("");
  });

  it("drops a malformed frame and keeps parsing (never throws)", () => {
    const buffer =
      "data: {not json\n\n" +
      formatWorkstreamSseFrame({ type: "done", openTruncated: false });
    const { events } = parseWorkstreamSseChunks(buffer);
    expect(events).toEqual([{ type: "done", openTruncated: false }]);
  });
});

describe("mergeStreamedIssues", () => {
  it("upserts streamed issues by id into an empty current", () => {
    const merged = mergeStreamedIssues(undefined, {
      issues: [issue({ id: "1" }), issue({ id: "2" })],
    });
    expect(merged.issues.map((i) => i.id)).toEqual(["1", "2"]);
  });

  it("replaces a same-id entry with the streamed copy, keeps order", () => {
    const cur = { issues: [issue({ id: "1", title: "old" }), issue({ id: "9" })] };
    const merged = mergeStreamedIssues(cur, {
      issues: [issue({ id: "1", title: "new" })],
    });
    expect(merged.issues).toHaveLength(2);
    expect(merged.issues[0].title).toBe("new");
    expect(merged.issues[1].id).toBe("9");
  });

  it("preserves optimistic SOLAA-N* temp cards across a mid-stream commit", () => {
    const temp = issue({ id: "SOLAA-N3", title: "optimistic" });
    const merged = mergeStreamedIssues(
      { issues: [temp, issue({ id: "1" })] },
      { issues: [issue({ id: "1" }), issue({ id: "2" })] },
    );
    expect(merged.issues.map((i) => i.id)).toContain("SOLAA-N3");
    expect(merged.issues.map((i) => i.id)).toEqual(
      expect.arrayContaining(["1", "2"]),
    );
  });

  it("carries the board meta through", () => {
    const merged = mergeStreamedIssues(undefined, {
      issues: [issue({ id: "1" })],
      board: { onKanbanOrg: true, projectWritable: false },
    });
    expect(merged.board).toEqual({
      onKanbanOrg: true,
      projectWritable: false,
    });
  });
});

describe("applyStatusOverrides", () => {
  it("patches only the listed ids (status + live)", () => {
    const out = applyStatusOverrides(
      [issue({ id: "1" }), issue({ id: "2", status: "in_progress" })],
      [{ id: "1", status: "in_review", live: true }],
    );
    expect(out[0].status).toBe("in_review");
    expect(out[0].live).toBe(true);
    expect(out[1].status).toBe("in_progress"); // untouched
    expect(out).toHaveLength(2);
  });

  it("clears live when the override says false", () => {
    const out = applyStatusOverrides(
      [issue({ id: "1", status: "in_progress", live: true })],
      [{ id: "1", status: "pending", live: false }],
    );
    expect(out[0].status).toBe("pending");
    expect(out[0].live).toBeUndefined();
  });
});

describe("fetchWorkstreamIssuesFeed", () => {
  const KEY = ["/api/workstream/issues"] as const;

  it("requests text/event-stream and resolves {issues, board} at done", async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      sseResponse(
        formatWorkstreamSseFrame({
          type: "meta",
          board: { onKanbanOrg: false, projectWritable: false },
        }) +
          formatWorkstreamSseFrame({
            type: "issues",
            issues: [issue({ id: "1" }), issue({ id: "2" })],
          }) +
          formatWorkstreamSseFrame({
            type: "issues",
            issues: [issue({ id: "3" })],
          }) +
          formatWorkstreamSseFrame({ type: "done", openTruncated: false }),
      ),
    );
    vi.stubGlobal("fetch", fetchMock);

    const partials: string[] = [];
    const out = await fetchWorkstreamIssuesFeed(KEY, (p) =>
      partials.push(p.issues.map((i) => i.id).join(",")),
    );

    expect(fetchMock).toHaveBeenCalledWith("/api/workstream/issues", {
      headers: { Accept: "text/event-stream" },
    });
    expect(out.issues.map((i) => i.id)).toEqual(["1", "2", "3"]);
    expect(out.board).toEqual({ onKanbanOrg: false, projectWritable: false });
    // Progressive commits fired per issues frame while the stream was open.
    expect(partials).toEqual(["1,2", "1,2,3"]);
  });

  it("throws when the stream ends without a done frame (truncated is loud)", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(
        sseResponse(
          formatWorkstreamSseFrame({
            type: "issues",
            issues: [issue({ id: "1" })],
          }),
        ),
      ),
    );
    await expect(fetchWorkstreamIssuesFeed(KEY)).rejects.toThrow();
  });

  it("throws on an error frame after partial issues", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(
        sseResponse(
          formatWorkstreamSseFrame({
            type: "issues",
            issues: [issue({ id: "1" })],
          }) +
            formatWorkstreamSseFrame({
              type: "error",
              code: "workstream_query_error",
            }),
        ),
      ),
    );
    await expect(fetchWorkstreamIssuesFeed(KEY)).rejects.toThrow(
      /workstream_query_error/,
    );
  });

  it("falls back to res.json() when the response is not SSE (older deploy/proxy)", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(
        new Response(JSON.stringify({ issues: [issue({ id: "5" })] }), {
          status: 200,
          headers: { "content-type": "application/json" },
        }),
      ),
    );
    const out = await fetchWorkstreamIssuesFeed(KEY);
    expect(out.issues.map((i) => i.id)).toEqual(["5"]);
  });

  it("throws on !ok like jsonFetcher", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(
        new Response("{}", { status: 502, statusText: "Bad Gateway" }),
      ),
    );
    await expect(fetchWorkstreamIssuesFeed(KEY)).rejects.toThrow(/502/);
  });
});
