import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// `listRepoIssues` is exercised against a mocked `githubApiGet` — there are NO
// live network calls. We assert the PR-filter, the SPLIT request shape (all open
// issues via state=open, then a windowed state=closed for the Done column),
// pagination (full page → next fetch; short page → stop), the open-cap Sentry
// mirror, the closed-window bound, and `name:null` label coercion.

const githubApiGet = vi.fn();
const reportSilentFallback = vi.fn();

vi.mock("@/server/github-api", () => ({
  githubApiGet: (...a: unknown[]) => githubApiGet(...a),
}));
vi.mock("@/server/observability", () => ({
  reportSilentFallback: (...a: unknown[]) => reportSilentFallback(...a),
}));

import { listRepoIssues } from "@/server/github-read-tools";

interface RawIssue {
  number: number;
  title: string;
  body: string | null;
  assignees: Array<{ login: string }>;
  labels: Array<{ name: string | null } | string>;
  state: string;
  state_reason: string | null;
  created_at: string;
  updated_at: string;
  pull_request?: unknown;
}

function rawIssue(over: Partial<RawIssue> = {}): RawIssue {
  return {
    number: 1,
    title: "An issue",
    body: "body",
    assignees: [{ login: "harry" }],
    labels: [{ name: "bug" }],
    state: "open",
    state_reason: null,
    created_at: "2026-06-20T09:00:00.000Z",
    updated_at: "2026-06-21T09:00:00.000Z",
    ...over,
  };
}

const path = (i: number) => githubApiGet.mock.calls[i][1] as string;
const paths = () => githubApiGet.mock.calls.map((c) => c[1] as string);
const callsMatching = (needle: string) =>
  githubApiGet.mock.calls.filter((c) => (c[1] as string).includes(needle));
const fullPage = () => Array.from({ length: 100 }, (_, i) => rawIssue({ number: i + 1 }));
// The real `page` param — matched with a leading `&` so it can't collide with
// the `page=1` substring inside `per_page=100`.
const pageOf = (p: string) => Number(/&page=(\d+)/.exec(p)?.[1] ?? 0);

beforeEach(() => {
  githubApiGet.mockReset();
  githubApiGet.mockResolvedValue([]); // default: every state/page empty
  reportSilentFallback.mockReset();
});
afterEach(() => {
  vi.clearAllMocks();
});

describe("listRepoIssues", () => {
  it("filters out items carrying a pull_request key, keeps plain issues", async () => {
    githubApiGet.mockImplementation((_i: unknown, p: string) =>
      Promise.resolve(
        p.includes("state=open")
          ? [
              rawIssue({ number: 10, title: "A real issue" }),
              rawIssue({ number: 11, title: "A PR", pull_request: { url: "x" } }),
            ]
          : [],
      ),
    );

    const out = await listRepoIssues(123, "acme", "widgets");

    expect(out).toHaveLength(1);
    expect(out[0].number).toBe(10);
    expect(out[0].title).toBe("A real issue");
  });

  it("reads ALL open issues, then a windowed recently-updated closed set", async () => {
    await listRepoIssues(123, "acme", "widgets");

    // Empty repo: open page 1 (short) + closed page 1 (short) = 2 calls.
    expect(githubApiGet).toHaveBeenCalledTimes(2);
    expect(path(0)).toContain("/repos/acme/widgets/issues");
    expect(path(0)).toContain("state=open");
    expect(path(1)).toContain("state=closed");
    // Done column shows the most-recently-updated closures first.
    expect(path(1)).toContain("sort=updated");
    expect(path(1)).toContain("direction=desc");
    // Both use the max page size.
    expect(paths().every((p) => p.includes("per_page=100"))).toBe(true);
  });

  it("pages open issues: a full first page triggers a second fetch; a short page stops", async () => {
    const short = [rawIssue({ number: 101 })];
    githubApiGet.mockImplementation((_i: unknown, p: string) => {
      if (p.includes("state=open")) {
        if (pageOf(p) === 1) return Promise.resolve(fullPage());
        if (pageOf(p) === 2) return Promise.resolve(short);
      }
      return Promise.resolve([]);
    });

    const out = await listRepoIssues(123, "acme", "widgets");

    const openCalls = callsMatching("state=open");
    expect(openCalls).toHaveLength(2);
    expect(openCalls[0][1] as string).toContain("page=1");
    expect(openCalls[1][1] as string).toContain("page=2");
    expect(out.filter((i) => i.state === "open")).toHaveLength(101);
  });

  it("mirrors a Sentry fallback when the OPEN read hits its page cap (active columns truncated)", async () => {
    // Every open page comes back full → the 20-page open cap is hit.
    githubApiGet.mockImplementation((_i: unknown, p: string) =>
      Promise.resolve(p.includes("state=open") ? fullPage() : []),
    );

    await listRepoIssues(123, "acme", "widgets");

    expect(callsMatching("state=open")).toHaveLength(20); // MAX_OPEN_PAGES
    expect(reportSilentFallback).toHaveBeenCalledTimes(1);
    const ctx = reportSilentFallback.mock.calls[0][1] as { op: string };
    expect(ctx.op).toBe("list-repo-issues-open-cap");
  });

  it("windows the CLOSED read to a bounded page count WITHOUT a truncation warning", async () => {
    // Every closed page comes back full → the closed window stops at its cap,
    // but that is intentional (old closures aren't actionable) → no Sentry.
    githubApiGet.mockImplementation((_i: unknown, p: string) =>
      Promise.resolve(
        p.includes("state=closed")
          ? Array.from({ length: 100 }, (_, i) => rawIssue({ number: i + 1, state: "closed" }))
          : [],
      ),
    );

    await listRepoIssues(123, "acme", "widgets");

    expect(callsMatching("state=closed")).toHaveLength(3); // MAX_CLOSED_PAGES
    expect(reportSilentFallback).not.toHaveBeenCalled();
  });

  it('coerces a label object with name:null to "" via normalizeLabel', async () => {
    githubApiGet.mockImplementation((_i: unknown, p: string) =>
      Promise.resolve(
        p.includes("state=open")
          ? [rawIssue({ number: 5, labels: [{ name: null }, { name: "blocked" }, "raw-string"] })]
          : [],
      ),
    );

    const out = await listRepoIssues(123, "acme", "widgets");

    expect(out[0].labels).toEqual(["", "blocked", "raw-string"]);
  });
});
