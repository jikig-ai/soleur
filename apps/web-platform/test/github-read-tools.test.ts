import { describe, test, expect, vi, beforeEach } from "vitest";

// Mock `generateInstallationToken` so github-api.ts doesn't try to read
// GitHub App credentials. We spy on the underlying fetch, and assert that
// github-read-tools produces the expected narrowed shapes.
vi.mock("../server/github-app", () => ({
  generateInstallationToken: vi.fn(async () => "fake-token"),
  GitHubApiError: class extends Error {
    status: number;
    constructor(message: string, status: number) {
      super(message);
      this.status = status;
    }
  },
}));

import {
  readIssue,
  readIssueComments,
  readPullRequest,
  listPullRequestComments,
} from "../server/github-read-tools";

const ORIGINAL_FETCH = globalThis.fetch;

function mockFetchOnce(response: unknown, status = 200): void {
  globalThis.fetch = vi.fn(async () =>
    new Response(JSON.stringify(response), {
      status,
      headers: { "content-type": "application/json" },
    }),
  ) as typeof fetch;
}

function mockFetchSequence(responses: Array<{ body: unknown; status?: number }>): void {
  let i = 0;
  globalThis.fetch = vi.fn(async () => {
    const entry = responses[i++] ?? responses[responses.length - 1];
    return new Response(JSON.stringify(entry.body), {
      status: entry.status ?? 200,
      headers: { "content-type": "application/json" },
    });
  }) as typeof fetch;
}

beforeEach(() => {
  vi.resetAllMocks();
  globalThis.fetch = ORIGINAL_FETCH;
});

describe("readIssue narrowing", () => {
  test("returns only the agent-relevant fields", async () => {
    mockFetchOnce({
      number: 2831,
      title: "Test issue",
      state: "open",
      body: "Body text",
      labels: [{ name: "bug" }, { name: "priority/p1" }],
      assignees: [{ login: "alice" }],
      milestone: { title: "MVP" },
      created_at: "2026-01-01T00:00:00Z",
      updated_at: "2026-01-02T00:00:00Z",
      html_url: "https://github.com/o/r/issues/2831",
      user: { login: "octocat", avatar_url: "https://avatars.example/octocat", events_url: "https://api.github.com/events" },
    });

    const result = await readIssue(12345, "o", "r", 2831);

    expect(result).toEqual({
      number: 2831,
      title: "Test issue",
      state: "open",
      body: "Body text",
      labels: ["bug", "priority/p1"],
      assignees: ["alice"],
      milestone: "MVP",
      created_at: "2026-01-01T00:00:00Z",
      updated_at: "2026-01-02T00:00:00Z",
      html_url: "https://github.com/o/r/issues/2831",
      user: "octocat",
    });
    // Avatar URL and events_url must not leak through — they waste tokens.
    expect(JSON.stringify(result)).not.toContain("avatar");
    expect(JSON.stringify(result)).not.toContain("events_url");
  });

  test("truncates body at 10 KB with marker pointing to html_url", async () => {
    const longBody = "a".repeat(15_000);
    mockFetchOnce({
      number: 1,
      title: "Long",
      state: "open",
      body: longBody,
      labels: [],
      assignees: [],
      milestone: null,
      created_at: "2026-01-01T00:00:00Z",
      updated_at: "2026-01-01T00:00:00Z",
      html_url: "https://github.com/o/r/issues/1",
      user: { login: "u" },
    });

    const result = await readIssue(12345, "o", "r", 1);

    expect(result.body.length).toBeLessThan(longBody.length);
    expect(result.body).toContain("…(truncated, view full at https://github.com/o/r/issues/1)");
    // First 10 KB of content is preserved (marker adds a fixed suffix)
    expect(result.body.startsWith("a".repeat(10 * 1024))).toBe(true);
  });

  test("handles null body and labels as strings", async () => {
    mockFetchOnce({
      number: 1,
      title: "Empty",
      state: "open",
      body: null,
      labels: ["bug", "chore"],
      assignees: [],
      milestone: null,
      created_at: "2026-01-01T00:00:00Z",
      updated_at: "2026-01-01T00:00:00Z",
      html_url: "https://github.com/o/r/issues/1",
      user: { login: "u" },
    });

    const result = await readIssue(12345, "o", "r", 1);

    expect(result.body).toBe("");
    expect(result.labels).toEqual(["bug", "chore"]);
  });

  test("propagates REST errors via GitHubApiError", async () => {
    mockFetchOnce({ message: "Not Found" }, 404);

    await expect(readIssue(12345, "o", "r", 99999)).rejects.toThrow();
  });
});

describe("readIssueComments narrowing", () => {
  test("tags each comment kind=\"conversation\" and narrows shape", async () => {
    mockFetchOnce([
      {
        id: 1,
        user: { login: "alice", avatar_url: "https://avatars.example/alice" },
        body: "First comment",
        created_at: "2026-01-01T00:00:00Z",
        html_url: "https://github.com/o/r/issues/1#issuecomment-1",
      },
      {
        id: 2,
        user: { login: "bob" },
        body: null,
        created_at: "2026-01-02T00:00:00Z",
        html_url: "https://github.com/o/r/issues/1#issuecomment-2",
      },
    ]);

    const result = await readIssueComments(12345, "o", "r", 1);

    expect(result).toHaveLength(2);
    expect(result[0]).toEqual({
      id: 1,
      kind: "conversation",
      user: "alice",
      body: "First comment",
      created_at: "2026-01-01T00:00:00Z",
      html_url: "https://github.com/o/r/issues/1#issuecomment-1",
    });
    expect(result[1].body).toBe("");
    expect(JSON.stringify(result)).not.toContain("avatar");
  });

  test("clamps per_page at 50", async () => {
    const calls: string[] = [];
    globalThis.fetch = (async (input: RequestInfo | URL) => {
      calls.push(typeof input === "string" ? input : input.toString());
      return new Response("[]", { status: 200, headers: { "content-type": "application/json" } });
    }) as typeof fetch;

    await readIssueComments(12345, "o", "r", 1, { per_page: 500 });

    expect(calls[0]).toContain("per_page=50");
    expect(calls[0]).not.toContain("per_page=500");
  });
});

describe("readPullRequest narrowing", () => {
  test("includes PR-specific review state on top of issue fields", async () => {
    mockFetchOnce({
      number: 100,
      title: "Feature X",
      state: "open",
      body: "PR body",
      labels: [{ name: "type/feature" }],
      assignees: [],
      milestone: null,
      created_at: "2026-01-01T00:00:00Z",
      updated_at: "2026-01-02T00:00:00Z",
      html_url: "https://github.com/o/r/pull/100",
      user: { login: "author" },
      draft: false,
      merged: false,
      mergeable: true,
      mergeable_state: "clean",
      merged_at: null,
      head: { ref: "feat-x" },
      base: { ref: "main" },
    });

    const result = await readPullRequest(12345, "o", "r", 100);

    expect(result.draft).toBe(false);
    expect(result.merged).toBe(false);
    expect(result.mergeable).toBe(true);
    expect(result.mergeable_state).toBe("clean");
    expect(result.head_ref).toBe("feat-x");
    expect(result.base_ref).toBe("main");
    expect(result.merged_at).toBeNull();
    // Issue fields still present
    expect(result.number).toBe(100);
    expect(result.labels).toEqual(["type/feature"]);
  });
});

describe("listPullRequestComments", () => {
  test("merges review and conversation comments with correct kind tags", async () => {
    // First fetch: /pulls/:n/comments (review comments)
    // Second fetch: /issues/:n/comments (conversation comments)
    mockFetchSequence([
      {
        body: [
          {
            id: 10,
            user: { login: "reviewer" },
            body: "Review line note",
            created_at: "2026-01-03T00:00:00Z",
            html_url: "https://github.com/o/r/pull/100#discussion_r10",
          },
        ],
      },
      {
        body: [
          {
            id: 20,
            user: { login: "author" },
            body: "Convo reply",
            created_at: "2026-01-04T00:00:00Z",
            html_url: "https://github.com/o/r/pull/100#issuecomment-20",
          },
        ],
      },
    ]);

    const result = await listPullRequestComments(12345, "o", "r", 100);

    expect(result).toHaveLength(2);
    const review = result.find((c) => c.kind === "review");
    const convo = result.find((c) => c.kind === "conversation");
    expect(review?.id).toBe(10);
    expect(convo?.id).toBe(20);
  });

  test("returns partial data when one endpoint fails", async () => {
    mockFetchSequence([
      { body: { message: "Not Found" }, status: 404 }, // review comments fail
      {
        body: [
          {
            id: 20,
            user: { login: "author" },
            body: "Convo still works",
            created_at: "2026-01-04T00:00:00Z",
            html_url: "https://github.com/o/r/pull/100#issuecomment-20",
          },
        ],
      },
    ]);

    const result = await listPullRequestComments(12345, "o", "r", 100);

    expect(result).toHaveLength(1);
    expect(result[0].kind).toBe("conversation");
    expect(result[0].body).toBe("Convo still works");
  });
});
