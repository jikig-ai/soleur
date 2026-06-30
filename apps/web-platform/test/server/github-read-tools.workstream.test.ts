import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// `listRepoIssues` is exercised against a mocked `githubApiGet` — there are NO
// live network calls. We assert the PR-filter, the request shape (state=all +
// per_page=100), pagination (full page → next fetch; short page → stop), and
// the `name:null` label coercion via normalizeLabel.

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

beforeEach(() => {
  githubApiGet.mockReset();
  reportSilentFallback.mockReset();
});
afterEach(() => {
  vi.clearAllMocks();
});

describe("listRepoIssues", () => {
  it("filters out items carrying a pull_request key, keeps plain issues", async () => {
    githubApiGet.mockResolvedValueOnce([
      rawIssue({ number: 10, title: "A real issue" }),
      rawIssue({ number: 11, title: "A PR masquerading", pull_request: { url: "x" } }),
    ]);

    const out = await listRepoIssues(123, "acme", "widgets");

    expect(out).toHaveLength(1);
    expect(out[0].number).toBe(10);
    expect(out[0].title).toBe("A real issue");
  });

  it("requests state=all and per_page=100", async () => {
    githubApiGet.mockResolvedValueOnce([]);

    await listRepoIssues(123, "acme", "widgets");

    expect(githubApiGet).toHaveBeenCalledTimes(1);
    const path = githubApiGet.mock.calls[0][1] as string;
    expect(path).toContain("/repos/acme/widgets/issues");
    expect(path).toContain("state=all");
    expect(path).toContain("per_page=100");
  });

  it("pages: a full first page triggers a second fetch; a short page stops", async () => {
    const fullPage = Array.from({ length: 100 }, (_, i) =>
      rawIssue({ number: i + 1 }),
    );
    const shortPage = [rawIssue({ number: 101 })];
    githubApiGet
      .mockResolvedValueOnce(fullPage)
      .mockResolvedValueOnce(shortPage);

    const out = await listRepoIssues(123, "acme", "widgets");

    expect(githubApiGet).toHaveBeenCalledTimes(2);
    expect((githubApiGet.mock.calls[0][1] as string)).toContain("page=1");
    expect((githubApiGet.mock.calls[1][1] as string)).toContain("page=2");
    expect(out).toHaveLength(101);
  });

  it("coerces a label object with name:null to \"\" via normalizeLabel", async () => {
    githubApiGet.mockResolvedValueOnce([
      rawIssue({ number: 5, labels: [{ name: null }, { name: "blocked" }, "raw-string"] }),
    ]);

    const out = await listRepoIssues(123, "acme", "widgets");

    expect(out[0].labels).toEqual(["", "blocked", "raw-string"]);
  });
});
