/**
 * #11636 (ADR-309): the registrar that decides whether the approval-gated `github_push_branch` tool joins the cc
 * `soleur_platform` server for one cold Query. Fast by design: it imports the registrar alone (never cc-dispatcher) and
 * drives every precondition through injected seams, plus one case through the PRODUCTION flag path (getRuntimeFlag mocked).
 *
 * The properties pinned here: registered only when ALL of persona, repo, installation, entitlement, flag and the default
 * branch lookup hold; every false precondition has its own machine reason; the lookup (a network round trip) never runs on
 * the dark path; the flag is read with the SAME identity as the gate; the returned tool set is exactly the one FQN.
 */
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const h = vi.hoisted(() => ({
  reportSilentFallback: vi.fn(),
  infoSilentFallback: vi.fn(),
  getRuntimeFlag: vi.fn(),
}));

vi.mock("@/server/observability", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/server/observability")>();
  return { ...actual, reportSilentFallback: h.reportSilentFallback, infoSilentFallback: h.infoSilentFallback };
});
vi.mock("@/lib/feature-flags/server", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/lib/feature-flags/server")>();
  return { ...actual, getRuntimeFlag: h.getRuntimeFlag };
});

import {
  CC_GRANT_WIRED_APPROVAL_TOOLS,
  CC_PUSH_FLAG_TIMEOUT_MS,
  CC_PUSH_PROMPT_ADDENDUM,
  resolveCcGithubPushRegistration,
  type ResolveCcGithubPushArgs,
} from "@/server/cc-github-push";
import { ExecutionGrants } from "@/server/approval/grants";
import { RESOLVE_TIMEOUT_MS } from "@/server/resolve-protected-branches";

const FQN = "mcp__soleur_platform__github_push_branch";
const USER = "00000000-0000-4000-8000-0000000000aa";
const WS = "00000000-0000-4000-8000-0000000000bb";

type Seams = Pick<ResolveCcGithubPushArgs, "isEnabled" | "lookupDefaultBranch" | "buildTool">;

function make(over: Partial<ResolveCcGithubPushArgs> = {}, seams: Seams = {}) {
  const isEnabled = vi.fn(async () => true);
  const lookupDefaultBranch = vi.fn(async () => "trunk" as unknown);
  const buildTool = vi.fn((opts: Record<string, unknown>) => ({ name: "github_push_branch", opts }));
  const args: ResolveCcGithubPushArgs = {
    userId: USER,
    workspaceId: WS,
    persona: "command_center",
    owner: "example-org",
    repo: "example-repo",
    installationId: 4242,
    workspacePath: "/ws/path",
    webEgressEntitled: true,
    grants: new ExecutionGrants(),
    isEnabled,
    lookupDefaultBranch,
    buildTool: buildTool as unknown as ResolveCcGithubPushArgs["buildTool"],
    ...seams,
    ...over,
  };
  return { args, isEnabled, lookupDefaultBranch, buildTool };
}

beforeEach(() => {
  h.reportSilentFallback.mockReset();
  h.infoSilentFallback.mockReset();
  h.getRuntimeFlag.mockReset();
});
afterEach(() => {
  vi.useRealTimers();
});

describe("the grant-wired constant", () => {
  it("is exactly the push FQN (the one approval-required tool a cc builder is wired for)", () => {
    expect([...CC_GRANT_WIRED_APPROVAL_TOOLS]).toEqual([FQN]);
  });
});

describe("registers when every precondition holds", () => {
  it("registered, tool set exactly the one FQN, built closed-over with requireGrant true and the looked-up default branch", async () => {
    const { args, isEnabled, lookupDefaultBranch, buildTool } = make();
    const r = await resolveCcGithubPushRegistration(args);
    expect(r).toMatchObject({ registered: true, reason: "registered", toolNames: [FQN] });
    expect(r.tools).toHaveLength(1);
    expect(isEnabled).toHaveBeenCalledTimes(1);
    expect(lookupDefaultBranch).toHaveBeenCalledTimes(1);
    expect(lookupDefaultBranch.mock.calls[0].slice(0, 3)).toEqual([4242, "example-org", "example-repo"]);
    expect(buildTool).toHaveBeenCalledTimes(1);
    const opts = buildTool.mock.calls[0][0] as Record<string, unknown>;
    expect(opts).toMatchObject({
      installationId: 4242,
      owner: "example-org",
      repo: "example-repo",
      workspacePath: "/ws/path",
      defaultBranch: "trunk",
      requireGrant: true,
    });
  });

  it("hands the SAME grants object it was given to the builder (never a fresh one)", async () => {
    const grants = new ExecutionGrants();
    const { args, buildTool } = make({ grants });
    await resolveCcGithubPushRegistration(args);
    expect((buildTool.mock.calls[0][0] as { grants: unknown }).grants).toBe(grants);
  });

  it("reads the flag with the SAME identity as the gate: { userId, workspaceId }", async () => {
    const { args, isEnabled } = make();
    await resolveCcGithubPushRegistration(args);
    expect(isEnabled).toHaveBeenCalledWith({ userId: USER, workspaceId: WS });
  });

  it("emits exactly one Sentry-visible outcome event carrying every discriminating field", async () => {
    const { args } = make();
    await resolveCcGithubPushRegistration(args);
    expect(h.infoSilentFallback).toHaveBeenCalledTimes(1);
    const [err, opts] = h.infoSilentFallback.mock.calls[0];
    expect(err).toBeNull();
    expect(opts).toMatchObject({ feature: "cc-push-registration", tags: { reason: "registered" } });
    expect(opts.extra).toMatchObject({
      registered: true,
      reason: "registered",
      flagEnabled: true,
      entitled: true,
      persona: "command_center",
      hasRepo: true,
      hasInstallation: true,
      defaultBranchResolved: true,
    });
    expect(h.reportSilentFallback).not.toHaveBeenCalled();
  });

  it("a degraded forwarder is irrelevant: only the entitlement boolean is an input (push is server-side)", async () => {
    // The registrar has no forwarder parameter at all; entitled true alone registers.
    const { args } = make({ webEgressEntitled: true });
    expect((await resolveCcGithubPushRegistration(args)).registered).toBe(true);
    expect(Object.keys(args)).not.toContain("webEgress");
  });
});

/** Each row makes ONE precondition false (all others true) and must NOT reach the lookup or the builder. */
describe("does not register, and says why", () => {
  const rows: Array<{ name: string; over: Partial<ResolveCcGithubPushArgs>; seams?: Seams; reason: string; flagRead: boolean }> = [
    { name: "persona support with every other precondition true", over: { persona: "support" }, reason: "support-persona", flagRead: false },
    { name: "no owner", over: { owner: "" }, reason: "no-repo-or-installation", flagRead: false },
    { name: "no repo", over: { repo: "" }, reason: "no-repo-or-installation", flagRead: false },
    { name: "no installation", over: { installationId: null }, reason: "no-repo-or-installation", flagRead: false },
    { name: "not entitled to web egress", over: { webEgressEntitled: false }, reason: "not-entitled", flagRead: false },
    {
      name: "flag off",
      over: {},
      seams: { isEnabled: vi.fn(async () => false) },
      reason: "flag-off",
      flagRead: true,
    },
  ];

  it.each(rows)("$name -> $reason; lookup and builder not called", async ({ over, seams, reason, flagRead }) => {
    const { args, isEnabled, lookupDefaultBranch, buildTool } = make(over, seams ?? {});
    const r = await resolveCcGithubPushRegistration(args);
    expect(r).toEqual({ registered: false, reason, tools: [], toolNames: [] });
    expect(lookupDefaultBranch).not.toHaveBeenCalled();
    expect(buildTool).not.toHaveBeenCalled();
    // The flag is the LAST cheap check: an earlier-false precondition pays no flag read either.
    if (!flagRead) expect(isEnabled).not.toHaveBeenCalled();
    expect(h.infoSilentFallback).toHaveBeenCalledTimes(1);
    expect(h.infoSilentFallback.mock.calls[0][1]).toMatchObject({ feature: "cc-push-registration", tags: { reason } });
    expect(h.infoSilentFallback.mock.calls[0][1].extra).toMatchObject({ registered: false, reason });
  });

  it("a second precondition false after a compliant first one still refuses (entitled true, flag off; then entitled false, flag on)", async () => {
    const a = make({ webEgressEntitled: true }, { isEnabled: vi.fn(async () => false) });
    expect((await resolveCcGithubPushRegistration(a.args)).reason).toBe("flag-off");
    const b = make({ webEgressEntitled: false }, { isEnabled: vi.fn(async () => true) });
    expect((await resolveCcGithubPushRegistration(b.args)).reason).toBe("not-entitled");
  });

  it("the outcome event for a dark path records which preconditions held (support persona: persona recorded, flagEnabled false)", async () => {
    const { args } = make({ persona: "support" });
    await resolveCcGithubPushRegistration(args);
    expect(h.infoSilentFallback.mock.calls[0][1].extra).toMatchObject({ persona: "support", flagEnabled: false });
  });
});

describe("a flag read that does not return exactly true never registers (fail closed)", () => {
  const cases: Array<{ name: string; seam: () => Promise<unknown>; reason: string }> = [
    { name: "throws", seam: async () => { throw new Error("flagsmith down"); }, reason: "flag-error" },
    { name: "returns undefined", seam: async () => undefined, reason: "flag-off" },
    { name: "returns the string 'true'", seam: async () => "true", reason: "flag-off" },
    { name: "returns 1", seam: async () => 1, reason: "flag-off" },
  ];

  it.each(cases)("$name -> $reason (seam-only: the real seam never throws)", async ({ seam, reason }) => {
    const { args, lookupDefaultBranch, buildTool } = make({}, { isEnabled: vi.fn(seam) as unknown as Seams["isEnabled"] });
    const r = await resolveCcGithubPushRegistration(args);
    expect(r).toEqual({ registered: false, reason, tools: [], toolNames: [] });
    expect(lookupDefaultBranch).not.toHaveBeenCalled();
    expect(buildTool).not.toHaveBeenCalled();
    if (reason === "flag-error") {
      expect(h.reportSilentFallback).toHaveBeenCalledTimes(1);
      expect(h.reportSilentFallback.mock.calls[0][1]).toMatchObject({ feature: "cc-dispatcher", op: "cc-push-flag-resolve" });
    }
  });

  it("a flag read that never settles is bounded: not registered (flag-error) after the timeout, reported", async () => {
    vi.useFakeTimers();
    const { args, lookupDefaultBranch } = make({}, { isEnabled: vi.fn(() => new Promise<boolean>(() => {})) });
    const p = resolveCcGithubPushRegistration(args);
    await vi.advanceTimersByTimeAsync(CC_PUSH_FLAG_TIMEOUT_MS + 10);
    expect(await p).toEqual({ registered: false, reason: "flag-error", tools: [], toolNames: [] });
    expect(lookupDefaultBranch).not.toHaveBeenCalled();
    expect(h.reportSilentFallback.mock.calls[0][1]).toMatchObject({ op: "cc-push-flag-resolve" });
  });
});

describe("the production flag path (no isEnabled override)", () => {
  const prod = (over: Partial<ResolveCcGithubPushArgs> = {}) => {
    const { args, lookupDefaultBranch, buildTool } = make(over);
    delete (args as { isEnabled?: unknown }).isEnabled;
    return { args, lookupDefaultBranch, buildTool };
  };

  it("getRuntimeFlag true -> registered, read for 'approval-queue' with the gate's identity", async () => {
    h.getRuntimeFlag.mockResolvedValue(true);
    const { args } = prod();
    expect((await resolveCcGithubPushRegistration(args)).registered).toBe(true);
    expect(h.getRuntimeFlag).toHaveBeenCalledTimes(1);
    expect(h.getRuntimeFlag.mock.calls[0][0]).toBe("approval-queue");
    expect(h.getRuntimeFlag.mock.calls[0][1]).toMatchObject({ userId: USER, orgId: WS });
  });

  it("getRuntimeFlag false -> not registered (flag-off)", async () => {
    h.getRuntimeFlag.mockResolvedValue(false);
    const { args, lookupDefaultBranch } = prod();
    expect((await resolveCcGithubPushRegistration(args)).reason).toBe("flag-off");
    expect(lookupDefaultBranch).not.toHaveBeenCalled();
  });

  it("getRuntimeFlag throws -> not registered (the real seam swallows it and answers false)", async () => {
    h.getRuntimeFlag.mockRejectedValue(new Error("flagsmith down"));
    const { args, buildTool } = prod();
    const r = await resolveCcGithubPushRegistration(args);
    expect(r.registered).toBe(false);
    expect(buildTool).not.toHaveBeenCalled();
  });
});

describe("the default branch is looked up fail-closed, only after every other precondition", () => {
  it("lookup throws -> not registered (default-branch-unresolved), reported under its own op, never a 'main' fallback", async () => {
    const { args, buildTool } = make({}, { lookupDefaultBranch: vi.fn(async () => { throw new Error("404"); }) });
    const r = await resolveCcGithubPushRegistration(args);
    expect(r).toEqual({ registered: false, reason: "default-branch-unresolved", tools: [], toolNames: [] });
    expect(buildTool).not.toHaveBeenCalled();
    expect(h.reportSilentFallback).toHaveBeenCalledTimes(1);
    expect(h.reportSilentFallback.mock.calls[0][1]).toMatchObject({ feature: "cc-dispatcher", op: "cc-push-default-branch-resolve" });
    expect(h.infoSilentFallback.mock.calls[0][1].extra).toMatchObject({ reason: "default-branch-unresolved", defaultBranchResolved: false });
  });

  it("lookup never settles -> bounded by the 3 s resolve timeout, signal aborted, not registered", async () => {
    vi.useFakeTimers();
    let seen: AbortSignal | undefined;
    const { args, buildTool } = make({}, {
      lookupDefaultBranch: vi.fn((_i: number, _o: string, _r: string, signal: AbortSignal) => {
        seen = signal;
        return new Promise<unknown>(() => {});
      }),
    });
    const p = resolveCcGithubPushRegistration(args);
    await vi.advanceTimersByTimeAsync(RESOLVE_TIMEOUT_MS + 10);
    expect((await p).reason).toBe("default-branch-unresolved");
    expect(seen?.aborted).toBe(true);
    expect(buildTool).not.toHaveBeenCalled();
  });

  it.each([
    ["undefined", undefined],
    ["an empty string", ""],
    ["a non-string", 42],
    ["a path-traversal name", "../etc"],
    ["a name with a space", "a b"],
    ["a name starting with a slash", "/main"],
    ["an over-long name", "a".repeat(300)],
  ])("lookup returns an unsafe value (%s) -> not registered", async (_n, value) => {
    const { args, buildTool } = make({}, { lookupDefaultBranch: vi.fn(async () => value) });
    expect((await resolveCcGithubPushRegistration(args)).reason).toBe("default-branch-unresolved");
    expect(buildTool).not.toHaveBeenCalled();
  });

  it("a slash-separated safe name is accepted and closed over", async () => {
    const { args, buildTool } = make({}, { lookupDefaultBranch: vi.fn(async () => "release/2026.11") });
    expect((await resolveCcGithubPushRegistration(args)).registered).toBe(true);
    expect((buildTool.mock.calls[0][0] as { defaultBranch: string }).defaultBranch).toBe("release/2026.11");
  });
});

describe("the real builder (lazy import of github-tools)", () => {
  it("with no buildTool override, a registered result carries the real SDK tool named github_push_branch", async () => {
    const { args } = make();
    delete (args as { buildTool?: unknown }).buildTool;
    const r = await resolveCcGithubPushRegistration(args);
    expect(r.registered).toBe(true);
    expect(r.tools.map((t) => t.name)).toEqual(["github_push_branch"]);
    expect(r.toolNames).toEqual([FQN]);
    // The registrar's literal and the builder module's exported constant are the same name.
    const { GITHUB_PUSH_BRANCH_TOOL_FQN } = await import("@/server/github-tools");
    expect(GITHUB_PUSH_BRANCH_TOOL_FQN).toBe(FQN);
  }, 30_000);
});

describe("the prompt addendum", () => {
  it("states the approval step, that a pending/denied/unavailable result means nothing was pushed, and forbids a success claim", () => {
    expect(CC_PUSH_PROMPT_ADDENDUM).toMatch(/github_push_branch/);
    expect(CC_PUSH_PROMPT_ADDENDUM).toMatch(/approv/i);
    expect(CC_PUSH_PROMPT_ADDENDUM).toMatch(/HEAD/);
    expect(CC_PUSH_PROMPT_ADDENDUM).toMatch(/pending|denied|unavailable/i);
    expect(CC_PUSH_PROMPT_ADDENDUM).toMatch(/not (?:been )?pushed|no push|nothing was pushed|NOT pushed/i);
    expect(CC_PUSH_PROMPT_ADDENDUM).toMatch(/never claim|do not claim|Never say/i);
    expect(CC_PUSH_PROMPT_ADDENDUM).toMatch(/pushed/);
    expect(CC_PUSH_PROMPT_ADDENDUM.length).toBeLessThan(900);
  });
});
