/**
 * #12469 T1: `listPullRequests`, the metadata-only pull request list reader behind `github_list_pull_requests`.
 *
 * Pinned: the request path and query (built with URLSearchParams, `per_page + 1` so `has_more` is exact), the closed `state`
 * set, the `per_page` clamp, `has_more` at the boundaries (with a mock that HONOURS the `per_page` query, so the `+1` fetch is
 * proven and not assumed), the explicit 0-results text, no `body` key, per-field caps counted in characters, and owner/repo
 * validation before any request is made.
 */
import { beforeEach, describe, expect, it, vi } from "vitest";

const h = vi.hoisted(() => ({ githubApiGet: vi.fn() }));

vi.mock("@/server/github-api", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/server/github-api")>();
  return { ...actual, githubApiGet: h.githubApiGet };
});

import { listPullRequests, PR_LIST_STATES } from "@/server/github-read-tools";

type Row = Record<string, unknown>;

function row(n: number, over: Row = {}): Row {
  return {
    number: n,
    title: `PR ${n}`,
    state: "open",
    user: { login: "alice" },
    labels: [{ name: "bug" }],
    updated_at: "2026-11-09T08:00:00Z",
    html_url: `https://github.com/o/r/pull/${n}`,
    draft: false,
    head: { ref: `feat-${n}` },
    body: "SECRET BODY THAT MUST NOT BE RETURNED",
    ...over,
  };
}

/** A GitHub that honours the `per_page` query: returns min(per_page, total) rows. */
function serve(total: number) {
  h.githubApiGet.mockImplementation(async (_id: number, path: string) => {
    const per = Number(new URL(`https://x${path}`).searchParams.get("per_page"));
    return Array.from({ length: Math.min(per, total) }, (_v, i) => row(i + 1));
  });
}

beforeEach(() => {
  h.githubApiGet.mockReset();
});

describe("listPullRequests request shape", () => {
  it("hits /repos/<o>/<r>/pulls with state, newest-updated order and per_page + 1, for the given installation", async () => {
    serve(0);
    await listPullRequests(4242, "o", "r", { state: "closed", per_page: 5 });
    expect(h.githubApiGet).toHaveBeenCalledTimes(1);
    const [id, path] = h.githubApiGet.mock.calls[0];
    expect(id).toBe(4242);
    const url = new URL(`https://x${path}`);
    expect(url.pathname).toBe("/repos/o/r/pulls");
    expect(url.searchParams.get("state")).toBe("closed");
    expect(url.searchParams.get("per_page")).toBe("6");
    expect(url.searchParams.get("sort")).toBe("updated");
    expect(url.searchParams.get("direction")).toBe("desc");
    expect(path.startsWith("/")).toBe(true);
    expect(path.startsWith("//")).toBe(false);
  });

  it("defaults to state=open and per_page 10 (fetches 11)", async () => {
    serve(0);
    await listPullRequests(1, "o", "r");
    const url = new URL(`https://x${h.githubApiGet.mock.calls[0][1]}`);
    expect(url.searchParams.get("state")).toBe("open");
    expect(url.searchParams.get("per_page")).toBe("11");
  });

  it("the state set is exactly open, closed, all; anything else is refused before any request", async () => {
    expect([...PR_LIST_STATES]).toEqual(["open", "closed", "all"]);
    for (const bad of ["merged", "OPEN", "open&per_page=100", "", "all "]) {
      await expect(listPullRequests(1, "o", "r", { state: bad })).rejects.toThrow(/state must be one of/);
    }
    expect(h.githubApiGet).not.toHaveBeenCalled();
  });

  it.each([0, -1, 500, Number.NaN])("per_page %s is clamped into 1..50 (never forwarded raw)", async (bad) => {
    serve(0);
    await listPullRequests(1, "o", "r", { per_page: bad });
    const per = Number(new URL(`https://x${h.githubApiGet.mock.calls[0][1]}`).searchParams.get("per_page"));
    expect(per).toBeGreaterThanOrEqual(2); // clamp lower bound 1, plus the extra row
    expect(per).toBeLessThanOrEqual(51);
  });

  it("per_page 500 is exactly 50 (+1)", async () => {
    serve(0);
    await listPullRequests(1, "o", "r", { per_page: 500 });
    expect(new URL(`https://x${h.githubApiGet.mock.calls[0][1]}`).searchParams.get("per_page")).toBe("51");
  });

  it.each([
    ["a/b", "r"],
    ["o", "../x"],
    ["o", "r?x=1"],
    ["..", "r"],
    ["o", ""],
    ["", "r"],
    ["o", "r/pulls"],
  ])("owner %j / repo %j is refused before any request", async (owner, repo) => {
    await expect(listPullRequests(1, owner, repo)).rejects.toThrow(/unsafe owner or repo/);
    expect(h.githubApiGet).not.toHaveBeenCalled();
  });

  it("passes fetch options through only when given (a plain call has exactly two arguments)", async () => {
    serve(0);
    await listPullRequests(1, "o", "r");
    expect(h.githubApiGet.mock.calls[0]).toHaveLength(2);
    await listPullRequests(1, "o", "r", {}, { redirect: "manual" });
    expect(h.githubApiGet.mock.calls[1][2]).toEqual({ redirect: "manual" });
  });
});

describe("listPullRequests has_more at the boundaries", () => {
  it.each([
    [10, 10, false],
    [11, 10, true],
    [50, 50, false],
    [51, 50, true],
    [3, 5, false],
    [6, 5, true],
  ])("%d PRs on GitHub, per_page %d => has_more %s", async (total, perPage, expectMore) => {
    serve(total);
    const out = await listPullRequests(1, "o", "r", { per_page: perPage });
    expect(out.has_more).toBe(expectMore);
    expect(out.pull_requests).toHaveLength(Math.min(total, perPage));
    expect(out.summary).toContain(expectMore ? "more available" : `(state=open)`);
  });
});

describe("listPullRequests result shape", () => {
  it("returns metadata only: no body key, the documented fields, labels as names", async () => {
    serve(1);
    const out = await listPullRequests(1, "o", "r");
    expect(out.pull_requests[0]).toEqual({
      number: 1,
      title: "PR 1",
      state: "open",
      user: "alice",
      labels: ["bug"],
      updated_at: "2026-11-09T08:00:00Z",
      html_url: "https://github.com/o/r/pull/1",
      draft: false,
      head_ref: "feat-1",
    });
    expect(JSON.stringify(out)).not.toContain("SECRET BODY");
    expect(JSON.stringify(out)).not.toContain('"body"');
  });

  it("an empty result is an explicit statement, not a bare empty list", async () => {
    serve(0);
    const out = await listPullRequests(1, "o", "r");
    expect(out.summary).toBe("0 pull requests (state=open)");
    expect(out.pull_requests).toEqual([]);
    expect(out.has_more).toBe(false);
  });

  it("a non-array 200 is a malformed answer and THROWS: it must never read as '0 pull requests'", async () => {
    h.githubApiGet.mockResolvedValue({ message: "weird" });
    await expect(listPullRequests(1, "o", "r", { state: "all" })).rejects.toThrow(/unexpected shape/);
    h.githubApiGet.mockResolvedValue(null);
    await expect(listPullRequests(1, "o", "r")).rejects.toThrow(/unexpected shape/);
  });

  it("a deleted author (user: null) and a missing head do not crash", async () => {
    h.githubApiGet.mockResolvedValue([row(1, { user: null, head: null, labels: null })]);
    const out = await listPullRequests(1, "o", "r");
    expect(out.pull_requests[0].user).toBe("");
    expect(out.pull_requests[0].head_ref).toBe("");
    expect(out.pull_requests[0].labels).toEqual([]);
  });

  it("oversize attacker-controlled fields are cut with a marker, counted in characters (multi-byte included)", async () => {
    const longTitle = "T".repeat(5000);
    const emoji = "😀".repeat(400); // 400 code points, 800 UTF-16 units
    h.githubApiGet.mockResolvedValue([
      row(1, { title: longTitle, head: { ref: "r".repeat(1000) }, user: { login: "u".repeat(500) }, labels: Array.from({ length: 40 }, (_v, i) => ({ name: `l${i}` })) }),
      row(2, { title: emoji }),
    ]);
    const out = await listPullRequests(1, "o", "r");
    const [a, b] = out.pull_requests;
    expect(a.title.endsWith("…[truncated]")).toBe(true);
    expect(Array.from(a.title.replace("…[truncated]", "")).length).toBe(300);
    expect(a.head_ref.startsWith("r".repeat(255))).toBe(true);
    expect(a.head_ref.endsWith("…[truncated]")).toBe(true);
    expect(Array.from(a.user.replace("…[truncated]", "")).length).toBe(100);
    expect(a.labels).toHaveLength(20);
    // 400 emoji > 300 cap: cut at 300 code points, not 300 UTF-16 units (which would split a surrogate pair)
    expect(Array.from(b.title.replace("…[truncated]", "")).length).toBe(300);
    expect(b.title).not.toMatch(/[\ud800-\udbff](?![\udc00-\udfff])/);
  });
});
