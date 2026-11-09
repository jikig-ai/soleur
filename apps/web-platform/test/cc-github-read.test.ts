/**
 * #12469 T4/T8: the registrar that decides whether the six read-only GitHub tools join the cc `soleur_platform` server.
 * Imports the registrar alone (never cc-dispatcher) and drives every precondition through injected seams.
 *
 * Pinned: registered only when persona, entitlement, repo, installation AND a verified PUBLIC repository all hold; every other
 * case returns the empty set with its own machine reason; the visibility lookup (a network round trip) runs last and fails
 * CLOSED (error, timeout, missing field all count as private) and its failure rows come AFTER a passing public case, so a
 * registrar that registers on any answer cannot hide behind one compliant-looking member; unsafe owner/repo are refused; the
 * builder is imported lazily; a thrown builder is contained and reported; the outcome event's fields and message literals.
 */
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const h = vi.hoisted(() => ({
  reportSilentFallback: vi.fn(),
  infoSilentFallback: vi.fn(),
  mirrorWarnWithDebounce: vi.fn(),
  mirrorWithDebounce: vi.fn(),
  githubApiGet: vi.fn(),
}));

vi.mock("@/server/observability", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/server/observability")>();
  return {
    ...actual,
    reportSilentFallback: h.reportSilentFallback,
    infoSilentFallback: h.infoSilentFallback,
    mirrorWarnWithDebounce: h.mirrorWarnWithDebounce,
    mirrorWithDebounce: h.mirrorWithDebounce,
  };
});
vi.mock("@/server/github-api", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/server/github-api")>();
  return { ...actual, githubApiGet: h.githubApiGet };
});

import {
  CC_GITHUB_READ_TOOL_FQNS,
  ccGithubReadUnavailableLine,
  emitCcGithubReadOutcome,
  resolveCcGithubReadRegistration,
  type CcGithubReadRegistration,
  type ResolveCcGithubReadArgs,
} from "@/server/cc-github-read";
import { GITHUB_READ_TOOL_NAMES } from "@/server/github-tools";
import { RESOLVE_TIMEOUT_MS } from "@/server/resolve-protected-branches";

const USER = "00000000-0000-4000-8000-0000000000aa";
const SIX = [
  "mcp__soleur_platform__github_list_pull_requests",
  "mcp__soleur_platform__github_read_pr",
  "mcp__soleur_platform__github_read_issue",
  "mcp__soleur_platform__github_read_issue_comments",
  "mcp__soleur_platform__github_list_pr_comments",
  "mcp__soleur_platform__github_read_ci_status",
];

function make(over: Partial<ResolveCcGithubReadArgs> = {}) {
  const lookupVisibility = vi.fn(async () => false as unknown);
  const buildTools = vi.fn((opts: Record<string, unknown>) => ({
    tools: SIX.map((fqn) => ({ name: fqn.replace("mcp__soleur_platform__", ""), opts })),
  }));
  const args: ResolveCcGithubReadArgs = {
    userId: USER,
    persona: "command_center",
    owner: "example-org",
    repo: "example-repo",
    installationId: 4242,
    webEgressEntitled: true,
    revalidate: async () => "current" as const,
    lookupVisibility,
    buildTools: buildTools as unknown as ResolveCcGithubReadArgs["buildTools"],
    ...over,
  };
  return { args, lookupVisibility, buildTools };
}

beforeEach(() => {
  for (const f of Object.values(h)) f.mockReset();
});
afterEach(() => {
  vi.useRealTimers();
});

describe("the literal FQN list", () => {
  it("is the six read tools, equal to the builder's names, with no workflow-logs or write tool", () => {
    expect([...CC_GITHUB_READ_TOOL_FQNS]).toEqual(SIX);
    expect([...CC_GITHUB_READ_TOOL_FQNS]).toEqual(GITHUB_READ_TOOL_NAMES.map((n) => `mcp__soleur_platform__${n}`));
    expect(CC_GITHUB_READ_TOOL_FQNS.join(" ")).not.toMatch(/workflow_logs|create_|trigger|push/);
  });
});

describe("registers when every precondition holds", () => {
  it("returns exactly six tools and six names, closed over the repo, with hardening wired", async () => {
    const { args, buildTools, lookupVisibility } = make();
    const out = await resolveCcGithubReadRegistration(args);
    expect(out.registered).toBe(true);
    expect(out.reason).toBe("registered");
    expect(out.tools).toHaveLength(6);
    expect(out.toolNames).toEqual(SIX);
    expect(out.repoPrivate).toBe(false);
    expect(lookupVisibility).toHaveBeenCalledTimes(1);
    expect(lookupVisibility.mock.calls[0].slice(0, 3)).toEqual([4242, "example-org", "example-repo"]);
    const opts = buildTools.mock.calls[0][0] as Record<string, any>;
    expect(opts).toMatchObject({ installationId: 4242, owner: "example-org", repo: "example-repo" });
    expect(opts.hardening.redact).toBe(true);
    expect(typeof opts.hardening.revalidate).toBe("function");
    expect(typeof opts.hardening.onFault).toBe("function");
  });

  it("a different valid owner/repo registers too (the registrar is not pinned to one repo)", async () => {
    const { args } = make({ owner: "another.org", repo: "its_repo-2" });
    expect((await resolveCcGithubReadRegistration(args)).registered).toBe(true);
  });

  it("the revalidate seam handed to the builder is the caller's own function", async () => {
    const revalidate = vi.fn(async () => "current" as const);
    const { args, buildTools } = make({ revalidate });
    await resolveCcGithubReadRegistration(args);
    expect((buildTools.mock.calls[0][0] as any).hardening.revalidate).toBe(revalidate);
  });
});

describe("every dark state returns the empty set with its own reason, and never calls the lookup or the builder", () => {
  it.each([
    ["support-persona", { persona: "support" as const }],
    ["not-entitled", { webEgressEntitled: false }],
    ["no-repo-or-installation", { installationId: null }],
    ["no-repo-or-installation", { owner: "" }],
    ["no-repo-or-installation", { repo: "" }],
  ])("%s", async (reason, over) => {
    const { args, lookupVisibility, buildTools } = make(over as Partial<ResolveCcGithubReadArgs>);
    const out = await resolveCcGithubReadRegistration(args);
    expect(out).toMatchObject({ registered: false, reason, tools: [], toolNames: [] });
    expect(lookupVisibility).not.toHaveBeenCalled();
    expect(buildTools).not.toHaveBeenCalled();
  });

  it("ordering: persona, then entitlement, then repo/installation (a row failing SEVERAL conditions reports the first)", async () => {
    const { args } = make({ persona: "support", webEgressEntitled: false, installationId: null });
    expect((await resolveCcGithubReadRegistration(args)).reason).toBe("support-persona");
    const b = make({ webEgressEntitled: false, installationId: null });
    expect((await resolveCcGithubReadRegistration(b.args)).reason).toBe("not-entitled");
    const c = make({ installationId: null, owner: "" });
    expect((await resolveCcGithubReadRegistration(c.args)).reason).toBe("no-repo-or-installation");
  });

  it("the persona gate is an ALLOWLIST: any persona other than command_center is dark", async () => {
    const { args, lookupVisibility } = make({ persona: "some_future_persona" as never });
    expect((await resolveCcGithubReadRegistration(args)).reason).toBe("support-persona");
    expect(lookupVisibility).not.toHaveBeenCalled();
  });

  it.each([
    ["a/../b", "r"],
    ["o", "x?y"],
    ["..", "r"],
    ["o", "r/pulls"],
    ["o w", "r"],
  ])("unsafe owner %j / repo %j is refused before any request", async (owner, repo) => {
    const { args, lookupVisibility } = make({ owner, repo });
    const out = await resolveCcGithubReadRegistration(args);
    expect(out.reason).toBe("no-repo-or-installation");
    expect(lookupVisibility).not.toHaveBeenCalled();
  });
});

describe("the public-repo gate fails CLOSED (the failure rows come after a passing public case)", () => {
  it("a public repo registers (the compliant member first)", async () => {
    const { args } = make({ lookupVisibility: async () => false });
    expect((await resolveCcGithubReadRegistration(args)).registered).toBe(true);
  });

  it("private: true => repo-private (a normal dark state), builder never loaded", async () => {
    const { args, buildTools } = make({ lookupVisibility: async () => true as unknown });
    const out = await resolveCcGithubReadRegistration(args);
    expect(out).toMatchObject({ registered: false, reason: "repo-private", tools: [], toolNames: [], repoPrivate: true });
    expect(buildTools).not.toHaveBeenCalled();
  });

  it.each([
    ["a missing field", async () => undefined as unknown],
    ["a null field", async () => null as unknown],
    ["a string 'false'", async () => "false" as unknown],
    ["0", async () => 0 as unknown],
    ["an object", async () => ({}) as unknown],
  ])("%s => visibility-unknown (fail closed, NOT reported as private), builder never loaded", async (_label, lookupVisibility) => {
    const { args, buildTools } = make({ lookupVisibility });
    const out = await resolveCcGithubReadRegistration(args);
    expect(out).toMatchObject({ registered: false, reason: "visibility-unknown", tools: [], toolNames: [], repoPrivate: null });
    expect(buildTools).not.toHaveBeenCalled();
  });

  it("a lookup ERROR => visibility-unknown, reported once under its own op with class name and status only (never the repo)", async () => {
    const err = Object.assign(new Error("GitHub API request failed: 500 /repos/example-org/example-repo"), { statusCode: 500 });
    const { args } = make({ lookupVisibility: async () => { throw err; } });
    const out = await resolveCcGithubReadRegistration(args);
    expect(out.reason).toBe("visibility-unknown");
    expect(h.reportSilentFallback).toHaveBeenCalledTimes(1);
    const [first, ctx] = h.reportSilentFallback.mock.calls[0];
    expect(first).toBeNull();
    expect(ctx.op).toBe("cc-github-read-visibility-resolve");
    expect(ctx.extra).toEqual({ userId: USER, errName: "Error", status: 500 });
    expect(JSON.stringify(h.reportSilentFallback.mock.calls)).not.toMatch(/example-org|example-repo/);
  });

  it("a lookup TIMEOUT => visibility-unknown, the lookup is aborted, reported", async () => {
    vi.useFakeTimers();
    let aborted = false;
    const { args } = make({
      lookupVisibility: (_id, _o, _r, signal) =>
        new Promise<unknown>(() => {
          signal.addEventListener("abort", () => { aborted = true; });
        }),
    });
    const pending = resolveCcGithubReadRegistration(args);
    await vi.advanceTimersByTimeAsync(RESOLVE_TIMEOUT_MS + 1);
    const out = await pending;
    expect(out.reason).toBe("visibility-unknown");
    expect(aborted).toBe(true);
    expect(h.reportSilentFallback).toHaveBeenCalledTimes(1);
  });

  it("the real lookup is a bounded GET /repos/<o>/<r> with the installation token, redirects refused, answer read as `private`", async () => {
    h.githubApiGet.mockResolvedValue({ private: false });
    const { args } = make();
    delete (args as Partial<ResolveCcGithubReadArgs>).lookupVisibility;
    const out = await resolveCcGithubReadRegistration(args);
    expect(out.registered).toBe(true);
    expect(h.githubApiGet).toHaveBeenCalledWith(4242, "/repos/example-org/example-repo", { signal: expect.any(AbortSignal), redirect: "manual" });
  });

  it("the real lookup: private:true is repo-private; an error is visibility-unknown (both fail closed)", async () => {
    const { args } = make();
    delete (args as Partial<ResolveCcGithubReadArgs>).lookupVisibility;
    h.githubApiGet.mockResolvedValueOnce({ private: true });
    expect((await resolveCcGithubReadRegistration(args)).reason).toBe("repo-private");
    h.githubApiGet.mockRejectedValueOnce(new Error("boom"));
    expect((await resolveCcGithubReadRegistration(args)).reason).toBe("visibility-unknown");
  });
});

describe("containment", () => {
  it("a builder that THROWS falls back to the empty set and is reported once under its own op", async () => {
    const { args } = make({ buildTools: () => { throw new Error("build exploded for example-org/example-repo"); } });
    const out = await resolveCcGithubReadRegistration(args);
    expect(out).toMatchObject({ registered: false, reason: "registration-failed", tools: [], toolNames: [] });
    expect(h.reportSilentFallback).toHaveBeenCalledTimes(1);
    const [first, ctx] = h.reportSilentFallback.mock.calls[0];
    expect(first).toBeNull();
    expect(ctx.op).toBe("cc-github-read-registration-failed");
    expect(JSON.stringify(ctx)).not.toMatch(/example-org|example-repo|exploded/);
  });

  it("the tool-fault hook mirrors (debounced per user + fault class) under op cc-github-read-tool with tool, class name and status only", async () => {
    const { args, buildTools } = make();
    await resolveCcGithubReadRegistration(args);
    const hardening = (buildTools.mock.calls[0][0] as any).hardening;
    hardening.onFault({ tool: "github_read_pr", errName: "GitHubApiError", status: 502 });
    hardening.onFault({ tool: "github_read_issue", errName: "TypeError" });
    expect(h.mirrorWithDebounce).toHaveBeenCalledTimes(2);
    const [first, ctx, userKey, cls] = h.mirrorWithDebounce.mock.calls[0];
    expect(first).toBeNull();
    expect(ctx).toMatchObject({
      feature: "cc-dispatcher",
      op: "cc-github-read-tool",
      extra: { userId: USER, tool: "github_read_pr", errName: "GitHubApiError", status: 502 },
    });
    expect(userKey).toBe(USER);
    expect(cls).toBe("cc-github-read-tool:github_read_pr:GitHubApiError:502");
    expect(h.mirrorWithDebounce.mock.calls[1][1].extra).toEqual({ userId: USER, tool: "github_read_issue", errName: "TypeError" });
    expect(h.mirrorWithDebounce.mock.calls[1][3]).toBe("cc-github-read-tool:github_read_issue:TypeError:-");
  });

  it("a dark state never reaches the builder seam", async () => {
    // Behavioural only: the lazy `import("./github-tools")` is pinned by the source test below.
    const { args } = make({ webEgressEntitled: false, buildTools: () => { throw new Error("must not be reached"); } });
    expect((await resolveCcGithubReadRegistration(args)).reason).toBe("not-entitled");
  });
});

describe("the GitHub tool graph is imported lazily", () => {
  it("cc-github-read.ts has no value import of ./github-tools (type imports only), so the dark path never loads it", async () => {
    const { readFileSync } = await import("node:fs");
    const { resolve } = await import("node:path");
    const src = readFileSync(resolve(__dirname, "../server/cc-github-read.ts"), "utf8").replace(/\/\*[\s\S]*?\*\//g, "").replace(/^\s*\/\/.*$/gm, "");
    const staticImports = [...src.matchAll(/^import\s+(?!type\b)[^;]*?from\s+["']\.\/github-tools["'];?/gm)];
    expect(staticImports).toEqual([]);
    expect(src).toMatch(/await import\(["']\.\/github-tools["']\)/);
  });
});

describe("the outcome event (T8)", () => {
  const registered = (): CcGithubReadRegistration => ({ registered: true, reason: "registered", tools: [], toolNames: [...SIX], repoPrivate: false });
  const dark = (reason: CcGithubReadRegistration["reason"], repoPrivate: boolean | null = null): CcGithubReadRegistration => ({
    registered: false, reason, tools: [], toolNames: [], repoPrivate,
  });
  const base = { userId: USER, persona: "command_center" as const, entitled: true, forwarderLive: true };

  it("registered => ONE info event with every discriminating field", () => {
    emitCcGithubReadOutcome(registered(), base);
    expect(h.infoSilentFallback).toHaveBeenCalledTimes(1);
    const [first, ctx] = h.infoSilentFallback.mock.calls[0];
    expect(first).toBeNull();
    expect(ctx.feature).toBe("cc-github-read-registration");
    expect(ctx.message).toBe("cc github read tools outcome");
    expect(ctx.tags).toEqual({ reason: "registered", entitled: "true", persona: "command_center", toolCount: "6", forwarderLive: "true", repoPrivate: "false" });
    expect(ctx.extra).toMatchObject({ registered: true, toolCount: 6, forwarderLive: true, repoPrivate: false, entitled: true });
    expect(JSON.stringify(ctx)).not.toMatch(/example|owner|repo-name/);
  });

  it("repo-private => an info event with repoPrivate=true (a normal state, not an error)", () => {
    emitCcGithubReadOutcome(dark("repo-private", true), base);
    expect(h.infoSilentFallback).toHaveBeenCalledTimes(1);
    expect(h.infoSilentFallback.mock.calls[0][1].tags).toMatchObject({ reason: "repo-private", repoPrivate: "true", toolCount: "0" });
  });

  it("visibility-unknown => an info event with repoPrivate=null (never claimed private)", () => {
    emitCcGithubReadOutcome(dark("visibility-unknown", null), base);
    expect(h.infoSilentFallback).toHaveBeenCalledTimes(1);
    expect(h.infoSilentFallback.mock.calls[0][1].tags).toMatchObject({ reason: "visibility-unknown", repoPrivate: "null", toolCount: "0" });
  });

  it("every outcome event carries the userId in extra (pseudonymized at the emit boundary), so it joins to a tenant", () => {
    emitCcGithubReadOutcome(registered(), base);
    expect(h.infoSilentFallback.mock.calls[0][1].extra.userId).toBe(USER);
    emitCcGithubReadOutcome(dark("no-repo-or-installation"), base);
    expect(h.mirrorWarnWithDebounce.mock.calls[0][1].extra.userId).toBe(USER);
  });

  it("a degraded forwarder is visible in the same row", () => {
    emitCcGithubReadOutcome(registered(), { ...base, forwarderLive: false });
    expect(h.infoSilentFallback.mock.calls[0][1].tags.forwarderLive).toBe("false");
  });

  it("no-repo-or-installation => a debounced WARNING with its OWN message literal (never the info literal)", () => {
    emitCcGithubReadOutcome(dark("no-repo-or-installation"), base);
    expect(h.infoSilentFallback).not.toHaveBeenCalled();
    expect(h.mirrorWarnWithDebounce).toHaveBeenCalledTimes(1);
    const [first, ctx, key, cls] = h.mirrorWarnWithDebounce.mock.calls[0];
    expect(first).toBeNull();
    expect(ctx.message).toBe("cc github read tools unavailable");
    expect(ctx.message).not.toBe("cc github read tools outcome");
    expect(ctx.tags.reason).toBe("no-repo-or-installation");
    expect(key).toBe(USER);
    expect(cls).toBe("cc-github-read-unavailable");
  });

  it.each(["support-persona", "not-entitled", "registration-failed"] as const)("%s is silent", (reason) => {
    emitCcGithubReadOutcome(dark(reason), base);
    expect(h.infoSilentFallback).not.toHaveBeenCalled();
    expect(h.mirrorWarnWithDebounce).not.toHaveBeenCalled();
  });

  it("a non-entitled session emits nothing, whatever the reason", () => {
    emitCcGithubReadOutcome(registered(), { ...base, entitled: false });
    emitCcGithubReadOutcome(dark("no-repo-or-installation"), { ...base, entitled: false });
    expect(h.infoSilentFallback).not.toHaveBeenCalled();
    expect(h.mirrorWarnWithDebounce).not.toHaveBeenCalled();
  });
});

describe("the short guidance for an entitled session without tools", () => {
  const REASONS_WITH_LINE = ["no-repo-or-installation", "repo-private", "visibility-unknown", "registration-failed"] as const;

  it("every dark reason a live-forwarder entitled session can reach gets a truthful line; the others get none", () => {
    for (const reason of REASONS_WITH_LINE) expect(ccGithubReadUnavailableLine(reason), reason).toEqual(expect.any(String));
    for (const reason of ["registered", "support-persona", "not-entitled"] as const) expect(ccGithubReadUnavailableLine(reason), reason).toBeNull();
  });

  it("each line says gh does not work by design, retrying does not help, never ask for a token, and names the owner's remedy", () => {
    for (const reason of REASONS_WITH_LINE) {
      const line = ccGithubReadUnavailableLine(reason) as string;
      expect(line, reason).toMatch(/`gh` and git network commands in the shell do not work in this session by design/);
      expect(line, reason).toMatch(/retrying does not help/);
      expect(line, reason).toMatch(/Never ask the user for a token/);
      expect(line, reason).toMatch(/Settings > Scope Grants/);
      expect(line, reason).toMatch(/new conversation/);
    }
  });

  it("the reason-specific lead is accurate: connect a repo / public only / could not confirm public / platform fault", () => {
    expect(ccGithubReadUnavailableLine("no-repo-or-installation")).toMatch(/^GitHub tools are unavailable in this session: connect a repository in Workspace settings\./);
    expect(ccGithubReadUnavailableLine("repo-private")).toMatch(/limited to public repositories/i);
    expect(ccGithubReadUnavailableLine("visibility-unknown")).toMatch(/could not be confirmed that the repository is public/);
    expect(ccGithubReadUnavailableLine("visibility-unknown")).not.toMatch(/limited to public repositories/i);
    expect(ccGithubReadUnavailableLine("registration-failed")).toMatch(/platform fault/);
  });

  it("no line asks for a token or points at the project's own settings", () => {
    for (const reason of REASONS_WITH_LINE) {
      expect(ccGithubReadUnavailableLine(reason) as string, reason).not.toMatch(/project'?s own settings|set a (github )?token|paste (a|your) token/i);
    }
  });
});
