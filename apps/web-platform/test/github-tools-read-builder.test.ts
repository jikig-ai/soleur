/**
 * #12469 T3: `buildGithubReadTools`, the six read-only GitHub tools of the Command Center.
 *
 * Pinned: the exact tool set (and what is deliberately absent), no owner/repo/installation schema key, framing as untrusted data
 * on every result, the hardening that applies ONLY when `hardening` is passed (per-field redaction, format-character stripping,
 * caps, fail-closed redirects, per-call revalidation, the fixed 401/403/429/404 texts and a mirror that carries class name and
 * status only), and that the legacy composition is untouched when it is not.
 */
import { beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("@anthropic-ai/claude-agent-sdk", () => ({
  tool: vi.fn((name: string, description: string, schema: Record<string, unknown>, handler: Function) => ({
    name,
    description,
    schema,
    handler,
  })),
}));

const r = vi.hoisted(() => ({
  readIssue: vi.fn(),
  readIssueComments: vi.fn(),
  readPullRequest: vi.fn(),
  listPullRequestComments: vi.fn(),
  listPullRequests: vi.fn(),
  readCiStatus: vi.fn(),
}));

vi.mock("@/server/github-read-tools", async (importOriginal) => {
  // The readers are mocked; the closed `state` set is the REAL constant (the schema is compared against it).
  const actual = await importOriginal<typeof import("@/server/github-read-tools")>();
  return {
    PR_LIST_STATES: actual.PR_LIST_STATES,
    readIssue: r.readIssue,
    readIssueComments: r.readIssueComments,
    readPullRequest: r.readPullRequest,
    listPullRequestComments: r.listPullRequestComments,
    listPullRequests: r.listPullRequests,
  };
});
vi.mock("@/server/ci-tools", () => ({ readCiStatus: r.readCiStatus, readWorkflowLogs: vi.fn() }));
vi.mock("@/server/github-app", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/server/github-app")>();
  return { ...actual, createPullRequest: vi.fn(), createIssue: vi.fn() };
});
vi.mock("@/server/trigger-workflow", () => ({ triggerWorkflow: vi.fn() }));
vi.mock("@/server/push-branch", () => ({ pushBranch: vi.fn() }));

import {
  buildGithubReadTools,
  GITHUB_ACCESS_NEEDS_RECONNECT,
  GITHUB_RATE_LIMITED,
  GITHUB_READ_TOOL_NAMES,
  GITHUB_REPO_CHANGED,
  GITHUB_REPO_UNVERIFIABLE,
  GITHUB_READ_FAILED,
  type GithubRevalidation,
  type GithubReadFault,
} from "@/server/github-tools";
import { GitHubApiError } from "@/server/github-app";
import { UNTRUSTED_PREAMBLES } from "@/server/untrusted-content";
import { PR_LIST_STATES } from "@/server/github-read-tools";

type Resp = { content: Array<{ type: "text"; text: string }>; isError?: true };
type ToolStub = { name: string; schema: Record<string, unknown>; handler: (a: Record<string, unknown>) => Promise<Resp> };

const SIX = [
  "github_list_pull_requests",
  "github_read_pr",
  "github_read_issue",
  "github_read_issue_comments",
  "github_list_pr_comments",
  "github_read_ci_status",
];

function make(over: { revalidate?: () => Promise<GithubRevalidation>; redact?: boolean; owner?: string; repo?: string; hardened?: boolean } = {}) {
  const faults: GithubReadFault[] = [];
  const revalidate = over.revalidate ?? (async () => "current" as const);
  // `hardening` is REQUIRED by the type (the cc builder cannot be built unhardened). The legacy composition is exercised through
  // the cast below only to prove the shared code path stays byte-identical when it is absent; production reaches that path
  // through buildGithubTools.
  const opts = {
    installationId: 7,
    owner: over.owner ?? "o",
    repo: over.repo ?? "r",
    ...(over.hardened === false
      ? {}
      : { hardening: { onFault: (f: GithubReadFault) => faults.push(f), revalidate, redact: over.redact } }),
  };
  const built = buildGithubReadTools(opts as unknown as Parameters<typeof buildGithubReadTools>[0]);
  const byName = (n: string) => {
    const t = (built.tools as unknown as ToolStub[]).find((x) => x.name === n);
    if (!t) throw new Error(`${n} not built`);
    return t;
  };
  return { built, faults, byName };
}

const text = (resp: Resp) => resp.content.map((c) => c.text).join("\n");
const json = (resp: Resp) => JSON.parse(resp.content[1].text);

beforeEach(() => {
  for (const f of Object.values(r)) f.mockReset();
});

describe("the cc builder cannot be built unhardened (type level, checked by tsc)", () => {
  it("`hardening` is REQUIRED on buildGithubReadTools", () => {
    // @ts-expect-error hardening is required: tsc fails this directive (unused) if the option ever becomes optional again.
    const build = () => buildGithubReadTools({ installationId: 1, owner: "o", repo: "r" });
    expect(typeof build).toBe("function"); // never called: the point is the directive above
  });
});

describe("the tool set", () => {
  it("is exactly the six read tools, in order, with matching FQNs", () => {
    const { built } = make();
    expect((built.tools as unknown as ToolStub[]).map((t) => t.name)).toEqual(SIX);
    expect(built.toolNames).toEqual(SIX.map((n) => `mcp__soleur_platform__${n}`));
    expect([...GITHUB_READ_TOOL_NAMES]).toEqual(SIX);
    expect(new Set(built.toolNames).size).toBe(6);
  });

  it("excludes the workflow-logs tool and every write tool", () => {
    const names = (make().built.tools as unknown as ToolStub[]).map((t) => t.name);
    for (const banned of ["github_read_workflow_logs", "create_issue", "create_pull_request", "github_trigger_workflow", "github_push_branch", "github_list_issues"]) {
      expect(names).not.toContain(banned);
    }
  });

  it("no tool schema carries an owner, repo or installation key (the repo is closed over server-side)", () => {
    for (const t of make().built.tools as unknown as ToolStub[]) {
      const keys = Object.keys(t.schema).map((k) => k.toLowerCase());
      for (const k of keys) expect(k).not.toMatch(/owner|repo|installation|url|path/);
    }
  });

  it("the list tool's state schema accepts exactly the reader's closed set", () => {
    const state = make().byName("github_list_pull_requests").schema.state as { safeParse: (v: unknown) => { success: boolean } };
    for (const ok of PR_LIST_STATES) expect(state.safeParse(ok).success).toBe(true);
    expect(state.safeParse(undefined).success).toBe(true); // defaults to open
    for (const bad of ["merged", "OPEN", "", "open&x=1"]) expect(state.safeParse(bad).success).toBe(false);
  });

  it("an unsafe owner or repo throws at build time (hardened)", () => {
    for (const [owner, repo] of [["a/../b", "r"], ["o", "x?y"], ["..", "r"], ["o", ""], ["", "r"]]) {
      expect(() => make({ owner, repo })).toThrow(/unsafe owner or repo/);
    }
  });
});

describe("every result is framed as untrusted data", () => {
  const CASES: Array<[string, Record<string, unknown>, ReturnType<typeof vi.fn>, unknown]> = [
    ["github_list_pull_requests", {}, r.listPullRequests, { summary: "0 pull requests (state=open)", has_more: false, pull_requests: [] }],
    ["github_read_pr", { pull_number: 1 }, r.readPullRequest, { number: 1, title: "t" }],
    ["github_read_issue", { issue_number: 1 }, r.readIssue, { number: 1, title: "t" }],
    ["github_read_issue_comments", { issue_number: 1 }, r.readIssueComments, [{ id: 1, body: "b" }]],
    ["github_list_pr_comments", { pull_number: 1 }, r.listPullRequestComments, [{ id: 1, body: "b" }]],
    ["github_read_ci_status", {}, r.readCiStatus, [{ id: 1, name: "ci" }]],
  ];
  it.each(CASES)("%s returns the github preamble first, then round-tripping JSON", async (name, args, reader, payload) => {
    reader.mockResolvedValue(payload);
    const resp = await make().byName(name).handler(args);
    expect(resp.isError).toBeUndefined();
    expect(resp.content[0].text).toBe(UNTRUSTED_PREAMBLES.github);
    expect(JSON.parse(resp.content[1].text)).toEqual(payload);
  });

  it("each hardened read passes the fail-closed redirect option to its reader; the unhardened build does not", async () => {
    r.readIssue.mockResolvedValue({ number: 1 });
    await make().byName("github_read_issue").handler({ issue_number: 1 });
    expect(r.readIssue).toHaveBeenLastCalledWith(7, "o", "r", 1, { redirect: "manual" });
    await make({ hardened: false }).byName("github_read_issue").handler({ issue_number: 1 });
    expect(r.readIssue).toHaveBeenLastCalledWith(7, "o", "r", 1);
  });
});

describe("hardening of the content", () => {
  it("redact: an email and a ghs_ token in a body are replaced, ids/urls/timestamps are not touched", async () => {
    const token = "ghs_" + "A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8"; // synthesized shape
    r.readPullRequest.mockResolvedValue({
      number: 1234567,
      title: `Fix for bob@example.com`,
      body: `contact alice@example.com and use ${token}`,
      html_url: "https://github.com/o/r/pull/1234567",
      updated_at: "2026-11-09T08:00:00Z",
      head_ref: "feat-1",
    });
    const out = json(await make().byName("github_read_pr").handler({ pull_number: 1 }));
    expect(out.body).not.toContain("alice@example.com");
    expect(out.body).not.toContain(token);
    expect(out.title).not.toContain("bob@example.com");
    expect(out.number).toBe(1234567);
    expect(out.html_url).toBe("https://github.com/o/r/pull/1234567");
    expect(out.updated_at).toBe("2026-11-09T08:00:00Z");
  });

  it("redact: false leaves the text as read (only the format characters and caps still apply)", async () => {
    r.readIssue.mockResolvedValue({ body: "alice@example.com" });
    const out = json(await make({ redact: false }).byName("github_read_issue").handler({ issue_number: 1 }));
    expect(out.body).toBe("alice@example.com");
  });

  it("invisible format characters (tag characters, bidi, zero-width) are stripped from text fields", async () => {
    const hidden = "\u{E0049}\u{E0047}‮​﻿";
    r.readIssue.mockResolvedValue({ title: `visible${hidden}text`, body: `b${hidden}ody`, labels: [`l${hidden}x`] });
    const out = json(await make().byName("github_read_issue").handler({ issue_number: 1 }));
    expect(out.title).toBe("visibletext");
    expect(out.body).toBe("body");
    expect(out.labels).toEqual(["lx"]);
  });

  it("the two comment tools are capped: oversize rows are cut per field and the response stays under the budget", async () => {
    const rows = Array.from({ length: 50 }, (_v, i) => ({ id: i, kind: "conversation", user: "u", body: "x".repeat(10_000), created_at: "t", html_url: "https://github.com/o/r/1" }));
    r.listPullRequestComments.mockResolvedValue(rows);
    r.readIssueComments.mockResolvedValue(rows);
    for (const [name, args] of [["github_list_pr_comments", { pull_number: 1 }], ["github_read_issue_comments", { issue_number: 1 }]] as const) {
      const resp = await make().byName(name).handler(args);
      expect(resp.content[1].text.length).toBeLessThanOrEqual(64_000 + 400);
      expect(resp.content[1].text).toContain("…[truncated]");
    }
  });

  it("a multi-byte body is cut by characters: no lone surrogate survives the cut", async () => {
    r.readIssue.mockResolvedValue({ body: "😀".repeat(5000) });
    const out = json(await make().byName("github_read_issue").handler({ issue_number: 1 }));
    expect(out.body).not.toMatch(/[\ud800-\udbff](?![\udc00-\udfff])/);
    expect(Array.from(out.body.replace("…[truncated]", "")).length).toBe(4096);
  });

  it("the unhardened build neither redacts nor caps nor strips (legacy output unchanged)", async () => {
    r.readIssue.mockResolvedValue({ body: "alice@example.com​" + "z".repeat(9000) });
    const out = json(await make({ hardened: false }).byName("github_read_issue").handler({ issue_number: 1 }));
    expect(out.body).toContain("alice@example.com​");
    expect(out.body.length).toBe("alice@example.com​".length + 9000);
  });
});

describe("per-call revalidation", () => {
  it("a REAL switch refuses with the fixed text, calls no reader and reports once", async () => {
    const { byName, faults } = make({ revalidate: async () => "changed" });
    const resp = await byName("github_read_issue").handler({ issue_number: 1 });
    expect(resp.isError).toBe(true);
    expect(text(resp)).toContain(GITHUB_REPO_CHANGED);
    expect(r.readIssue).not.toHaveBeenCalled();
    expect(faults).toEqual([{ tool: "github_read_issue", errName: "RepoChanged" }]);
  });

  it("an UNVERIFIABLE read is a different refusal (a blip is not a switch): own text, own fault class", async () => {
    const { byName, faults } = make({ revalidate: async () => "unverifiable" });
    const resp = await byName("github_read_pr").handler({ pull_number: 1 });
    expect(resp.isError).toBe(true);
    expect(text(resp)).toContain(GITHUB_REPO_UNVERIFIABLE);
    expect(text(resp)).not.toContain(GITHUB_REPO_CHANGED);
    expect(r.readPullRequest).not.toHaveBeenCalled();
    expect(faults).toEqual([{ tool: "github_read_pr", errName: "RevalidateUnverifiable" }]);
  });

  it("a revalidation that THROWS is the unverifiable refusal, never a pass", async () => {
    const { byName, faults } = make({ revalidate: async () => { throw new Error("db blip"); } });
    const resp = await byName("github_read_pr").handler({ pull_number: 1 });
    expect(resp.isError).toBe(true);
    expect(text(resp)).toContain(GITHUB_REPO_UNVERIFIABLE);
    expect(r.readPullRequest).not.toHaveBeenCalled();
    expect(faults[0].errName).toBe("RevalidateUnverifiable");
  });

  it.each([true, false, "yes", "ok", undefined, null, 1] as unknown[])("an answer other than the exact words is NOT a pass: %j", async (answer) => {
    const { byName } = make({ revalidate: (async () => answer) as unknown as () => Promise<GithubRevalidation> });
    const resp = await byName("github_read_ci_status").handler({});
    expect(resp.isError).toBe(true);
    expect(r.readCiStatus).not.toHaveBeenCalled();
  });

  it("revalidation runs on EVERY call, not once at build", async () => {
    const revalidate = vi.fn(async () => "current" as const);
    r.readIssue.mockResolvedValue({});
    const { byName } = make({ revalidate });
    await byName("github_read_issue").handler({ issue_number: 1 });
    await byName("github_read_issue").handler({ issue_number: 2 });
    expect(revalidate).toHaveBeenCalledTimes(2);
  });

  // ALL six tools go through the hardened wrapper: a tool that bypassed `run` (or dropped the fetch option) would have no
  // revalidation, no redaction, no redirect refusal and no fault mirror, and a test on three of six cannot see which three.
  const ALL: Array<[string, Record<string, unknown>, ReturnType<typeof vi.fn>]> = [
    ["github_list_pull_requests", {}, r.listPullRequests],
    ["github_read_pr", { pull_number: 1 }, r.readPullRequest],
    ["github_read_issue", { issue_number: 1 }, r.readIssue],
    ["github_read_issue_comments", { issue_number: 1 }, r.readIssueComments],
    ["github_list_pr_comments", { pull_number: 1 }, r.listPullRequestComments],
    ["github_read_ci_status", {}, r.readCiStatus],
  ];

  it.each(ALL)("%s: a switch refuses it and its reader is never called", async (name, args, reader) => {
    const { byName, faults } = make({ revalidate: async () => "changed" });
    const resp = await byName(name).handler(args);
    expect(resp.isError).toBe(true);
    expect(text(resp)).toContain(GITHUB_REPO_CHANGED);
    expect(reader).not.toHaveBeenCalled();
    expect(faults).toEqual([{ tool: name, errName: "RepoChanged" }]);
  });

  it.each(ALL)("%s: its reader receives the fail-closed redirect option as the LAST argument", async (name, args, reader) => {
    reader.mockResolvedValue(name === "github_list_pull_requests" ? { summary: "0", has_more: false, pull_requests: [] } : []);
    await make().byName(name).handler(args);
    const last = reader.mock.calls[0].at(-1);
    expect(last).toEqual({ redirect: "manual" });
  });

  it.each(ALL)("%s: the unhardened composition passes NO fetch option", async (name, args, reader) => {
    reader.mockResolvedValue(name === "github_list_pull_requests" ? { summary: "0", has_more: false, pull_requests: [] } : []);
    await make({ hardened: false }).byName(name).handler(args);
    expect(reader.mock.calls[0].some((a) => a !== null && typeof a === "object" && "redirect" in (a as object))).toBe(false);
  });

  it.each(ALL)("%s: a result is size-capped and redacted by the shared wrapper (title/body redacted, format chars stripped)", async (name, args, reader) => {
    const dirty = { title: "t bob@example.com\u200B", body: "b alice@example.com" };
    reader.mockResolvedValue(
      name === "github_list_pull_requests"
        ? { summary: "1", has_more: false, pull_requests: [dirty] }
        : name === "github_read_pr" || name === "github_read_issue"
          ? dirty
          : [dirty],
    );
    const resp = await make().byName(name).handler(args);
    const dump = resp.content[1].text;
    expect(dump).not.toMatch(/bob@example\.com|alice@example\.com/);
    expect(dump).not.toContain("\u200B");
  });
});

describe("faults: fixed texts, and a mirror that carries class name and status only", () => {
  const err = (status: number, message = `GitHub API request failed: ${status} /repos/secret-org/secret-repo/issues/1`) => new GitHubApiError(message, status);

  it.each([500, 502, 503])("a %d mirrors once and the model sees the error text", async (status) => {
    r.readIssue.mockRejectedValue(err(status));
    const { byName, faults } = make();
    const resp = await byName("github_read_issue").handler({ issue_number: 1 });
    expect(resp.isError).toBe(true);
    expect(faults).toHaveLength(1);
    expect(faults[0]).toEqual({ tool: "github_read_issue", errName: "GitHubApiError", status });
  });

  it("a network fault (no status) mirrors with the class name only", async () => {
    r.readCiStatus.mockRejectedValue(new TypeError("fetch failed"));
    const { byName, faults } = make();
    expect((await byName("github_read_ci_status").handler({})).isError).toBe(true);
    expect(faults).toEqual([{ tool: "github_read_ci_status", errName: "TypeError" }]);
  });

  it.each([401, 403])("a %d returns the fixed reconnect text (not caused by Agent web access) and mirrors", async (status) => {
    r.readPullRequest.mockRejectedValue(err(status, `GitHub API ${status} for /repos/secret-org/secret-repo/pulls/1: "Resource not accessible"`));
    const { byName, faults } = make();
    const resp = await byName("github_read_pr").handler({ pull_number: 1 });
    expect(text(resp)).toBe(GITHUB_ACCESS_NEEDS_RECONNECT);
    expect(text(resp)).toMatch(/not caused by Agent web access/);
    expect(faults).toHaveLength(1);
  });

  it("a 429 and a rate-limit 403 map to the retry-shortly text, not to a reconnect case", async () => {
    const { byName, faults } = make();
    r.readIssue.mockRejectedValueOnce(err(429));
    expect(text(await byName("github_read_issue").handler({ issue_number: 1 }))).toContain(GITHUB_RATE_LIMITED);
    r.readIssue.mockRejectedValueOnce(err(403, 'GitHub API 403 for /repos/o/r/issues/1: "You have exceeded a secondary rate limit"'));
    const second = text(await byName("github_read_issue").handler({ issue_number: 1 }));
    expect(second).toContain(GITHUB_RATE_LIMITED);
    expect(second).not.toContain(GITHUB_ACCESS_NEEDS_RECONNECT);
    expect(faults).toHaveLength(2);
  });

  it("a 3xx fails closed with a fixed text and mirrors", async () => {
    r.readIssue.mockRejectedValue(err(302));
    const { byName, faults } = make();
    const resp = await byName("github_read_issue").handler({ issue_number: 1 });
    expect(resp.isError).toBe(true);
    expect(text(resp)).toMatch(/redirect/i);
    expect(faults).toEqual([{ tool: "github_read_issue", errName: "GitHubApiError", status: 302 }]);
  });

  it.each([404, 422, 400, 410])("a plain %d does NOT mirror", async (status) => {
    r.readIssue.mockRejectedValue(err(status));
    const { byName, faults } = make();
    const resp = await byName("github_read_issue").handler({ issue_number: 1 });
    expect(resp.isError).toBe(true);
    expect(faults).toEqual([]);
  });

  it("the fault object NEVER carries the repo name, a path, args, a body or a message", async () => {
    r.readPullRequest.mockRejectedValue(err(500, "GitHub API request failed: 500 /repos/secret-org/secret-repo/pulls/42"));
    const { byName, faults } = make({ owner: "secret-org", repo: "secret-repo" });
    await byName("github_read_pr").handler({ pull_number: 42 });
    const dump = JSON.stringify(faults);
    expect(dump).not.toMatch(/secret-org|secret-repo|pulls|42/);
    expect(Object.keys(faults[0]).sort()).toEqual(["errName", "status", "tool"]);
  });

  it("read_pr on an issue number answers with the read_issue hint", async () => {
    r.readPullRequest.mockRejectedValueOnce(err(404));
    r.readIssue.mockResolvedValueOnce({ number: 9 });
    const a = await make().byName("github_read_pr").handler({ pull_number: 9 });
    expect(text(a)).toBe("#9 is an issue; use github_read_issue");
  });

  it("read_issue has NO pull-request hint: GitHub serves a PR through /issues/N with a 200, so an issue 404 never means 'it is a PR' (and costs no second request)", async () => {
    r.readIssue.mockRejectedValueOnce(err(404));
    r.readPullRequest.mockResolvedValue({ number: 9 });
    const resp = await make().byName("github_read_issue").handler({ issue_number: 9 });
    expect(text(resp)).toContain("Error reading issue");
    expect(r.readPullRequest).not.toHaveBeenCalled();
  });

  it("a revoked/uninstalled installation (the token mint throws a plain Error) gets the reconnect text, not a raw message", async () => {
    r.readIssue.mockRejectedValue(new Error("GitHub installation token request failed: 404"));
    const { byName, faults } = make();
    const resp = await byName("github_read_issue").handler({ issue_number: 1 });
    expect(text(resp)).toBe(GITHUB_ACCESS_NEEDS_RECONNECT);
    expect(faults).toHaveLength(1);
  });

  it.each([
    "GITHUB_APP_PRIVATE_KEY is not set",
    "GITHUB_APP_ID is not set",
    "error:1E08010C:DECODER routines::unsupported",
    "Unexpected token < in JSON at position 0",
  ])("a non-GitHub-API fault (%s) is NEVER forwarded to the model: a fixed text, and it mirrors", async (message) => {
    r.readIssue.mockRejectedValue(new Error(message));
    const { byName, faults } = make();
    const resp = await byName("github_read_issue").handler({ issue_number: 1 });
    expect(text(resp)).toBe(`Error reading issue: ${GITHUB_READ_FAILED}`);
    expect(text(resp)).not.toContain(message);
    expect(faults).toHaveLength(1);
  });

  it("a 404 whose probe also 404s (or throws) falls back to the plain error and still does not mirror", async () => {
    r.readPullRequest.mockRejectedValue(err(404));
    r.readIssue.mockRejectedValue(err(404));
    const { byName, faults } = make();
    const resp = await byName("github_read_pr").handler({ pull_number: 9 });
    expect(text(resp)).toContain("Error reading PR");
    expect(faults).toEqual([]);
  });
});

describe("the unhardened build is the legacy behaviour", () => {
  it("no revalidation, no mirror, no new error texts: a 403 keeps the reader's message", async () => {
    r.readIssue.mockRejectedValue(new GitHubApiError("GitHub API 403 for /repos/o/r/issues/1", 403));
    const resp = await make({ hardened: false }).byName("github_read_issue").handler({ issue_number: 1 });
    expect(text(resp)).toBe("Error reading issue: GitHub API 403 for /repos/o/r/issues/1");
    expect(text(resp)).not.toContain(GITHUB_ACCESS_NEEDS_RECONNECT);
  });
});
