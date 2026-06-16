// #5426 — KB-sync protected-branch trigger fix.
//
// Phase 1: classifyPushError — pure classifier over git/GitHub push-rejection
// stderr. Distinguishes a protected-branch rejection (→ side-branch + PR
// fallback) from a persistent non-protection reject that must NOT loop
// (`shallow update not allowed`) from transient/other (existing best-effort
// retry). Fixtures are synthesized from real GitHub stderr shapes per
// cq-test-fixtures-synthesized-only.
//
// Phase 2: the protected-fallback path in `syncPush`. Mocked-git behavioral
// tests assert the COMMAND SEQUENCE (tree-overlay accretion, ordering of the
// default reset relative to the side-branch push + PR), the create-or-update
// PR contract against the user's own repo, and the observability ops. Git is
// fully mocked, so these assert the git argv sequence the fallback issues — the
// shape that distinguishes tree-overlay from `checkout -B`-from-default and
// from cherry-pick (the understated R1 defect AC4 guards).

import { describe, test, expect, vi, beforeEach } from "vitest";

process.env.NEXT_PUBLIC_SUPABASE_URL ??= "https://test.supabase.co";
process.env.SUPABASE_SERVICE_ROLE_KEY ??= "test-service-role-key";

const {
  reportSilentFallbackSpy,
  warnSilentFallbackSpy,
  gitWithInstallationAuthSpy,
  getCurrentRepoUrlSpy,
  findOpenPullRequestSpy,
  createPullRequestSpy,
  resolveInstallationIdSpy,
} = vi.hoisted(() => ({
  reportSilentFallbackSpy: vi.fn(),
  warnSilentFallbackSpy: vi.fn(),
  gitWithInstallationAuthSpy: vi.fn<(argv: string[]) => Promise<Buffer>>(),
  getCurrentRepoUrlSpy: vi.fn<() => Promise<string | null>>(),
  findOpenPullRequestSpy: vi.fn(),
  createPullRequestSpy: vi.fn(),
  resolveInstallationIdSpy: vi.fn<() => Promise<number | null>>(),
}));

// execFileSync (sync connected-repo wrapper): `remote -v` returns a remote so
// hasRemote() passes; `rev-list` returns 1 so hasLocalCommits() says yes;
// `status -z` returns one allowlisted KB path so the auto-commit add/commit run.
vi.mock("child_process", () => ({
  execFileSync: vi.fn((_cmd: string, args: string[]) => {
    if (args[0] === "remote") {
      return Buffer.from("origin\tgit@github.com:acme/widgets.git (fetch)\n");
    }
    if (args[0] === "rev-list") return Buffer.from("1\n");
    if (args[0] === "status") {
      return Buffer.from("A  knowledge-base/notes.md\0");
    }
    return Buffer.from("");
  }),
}));

vi.mock("fs", () => ({ readdirSync: vi.fn(() => []) }));

vi.mock("@supabase/supabase-js", () => ({ createClient: vi.fn() }));

vi.mock("@/lib/supabase/tenant", () => {
  class FakeRuntimeAuthError extends Error {}
  const fakeRow = { id: "user-1", kb_sync_history: [] };
  const eqChain: Record<string, unknown> = {};
  eqChain.eq = () => eqChain;
  eqChain.single = async () => ({ data: fakeRow, error: null });
  eqChain.maybeSingle = async () => ({ data: fakeRow, error: null });
  eqChain.then = (resolve: (v: unknown) => void) => resolve({ error: null });
  const fromChain = {
    select: () => ({ eq: () => eqChain }),
    update: () => ({ eq: () => eqChain }),
  };
  return {
    getFreshTenantClient: vi.fn(async () => ({
      from: () => fromChain,
      rpc: async () => ({ error: null }),
    })),
    RuntimeAuthError: FakeRuntimeAuthError,
  };
});

vi.mock("@/server/observability", () => ({
  reportSilentFallback: reportSilentFallbackSpy,
  warnSilentFallback: warnSilentFallbackSpy,
  hashUserId: (s: string) => `hash-${s}`,
}));

vi.mock("../../server/git-auth", () => ({
  gitWithInstallationAuth: gitWithInstallationAuthSpy,
}));

vi.mock("../../server/current-repo-url", () => ({
  getCurrentRepoUrl: getCurrentRepoUrlSpy,
}));

vi.mock("../../server/github-app", () => ({
  findOpenPullRequest: findOpenPullRequestSpy,
  createPullRequest: createPullRequestSpy,
}));

vi.mock("../../server/resolve-installation-id", () => ({
  resolveInstallationId: resolveInstallationIdSpy,
}));

vi.mock("../../server/logger", () => ({
  default: { info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() },
  createChildLogger: () => ({
    info: vi.fn(),
    warn: vi.fn(),
    error: vi.fn(),
    debug: vi.fn(),
  }),
}));

import { classifyPushError, syncPush } from "@/server/session-sync";

function pushErr(message: string, stderr?: string): Error {
  const e = new Error(message);
  if (stderr !== undefined) {
    (e as Error & { stderr?: string }).stderr = stderr;
  }
  return e;
}

const PROTECTED_STDERR = [
  "remote: error: GH006: Protected branch update failed for refs/heads/main.",
  "remote: error: Changes must be made through a pull request.",
  " ! [remote rejected] main -> main (protected branch hook declined)",
].join("\n");

// Records every gitWithInstallationAuth argv in order so tests can assert the
// command SEQUENCE (the shape that distinguishes tree-overlay from
// checkout-B-from-default and from cherry-pick).
let gitCalls: string[][];

interface GitMockOpts {
  /** bare `git push` outcome: "protected" | "shallow" | "auth" | "ok" */
  initialPush?: "protected" | "shallow" | "auth" | "ok";
  /** does origin/soleur/kb-sync already exist? */
  sideExists?: boolean;
  /** make the side-branch push fail (co-member non-ff race) */
  sideBranchPushFails?: boolean;
  /** value returned for `rev-list --count origin/<default>..HEAD` */
  commitRange?: string;
  /** `diff --cached --quiet` exits 0 (no overlay diff → no commit) */
  noStagedChanges?: boolean;
  /** what `symbolic-ref --short refs/remotes/origin/HEAD` resolves to */
  defaultRef?: string;
}

function makeGitMock(opts: GitMockOpts = {}) {
  const defaultRef = opts.defaultRef ?? "origin/main";
  return async (args: string[]): Promise<Buffer> => {
    gitCalls.push(args);

    // bare `git push` (the pre-fallback push attempt)
    if (args[0] === "push" && args.length === 1) {
      switch (opts.initialPush ?? "protected") {
        case "protected":
          throw pushErr("Command failed: git push", PROTECTED_STDERR);
        case "shallow":
          throw pushErr(
            "Command failed: git push",
            " ! [remote rejected] main -> main (shallow update not allowed)",
          );
        case "auth":
          throw pushErr(
            "Command failed: git push",
            "fatal: Authentication failed for 'https://github.com/acme/widgets.git/'",
          );
        case "ok":
          return Buffer.from("");
      }
    }

    // side-branch refspec push
    if (args[0] === "push") {
      if (opts.sideBranchPushFails) {
        throw pushErr("push failed", " ! [rejected] (non-fast-forward)");
      }
      return Buffer.from("");
    }

    if (
      args[0] === "symbolic-ref" &&
      args[args.length - 1] === "refs/remotes/origin/HEAD"
    ) {
      return Buffer.from(`${defaultRef}\n`);
    }
    if (args[0] === "rev-parse" && args[1] === "HEAD") {
      return Buffer.from("defHEAD\n");
    }
    if (args[0] === "rev-parse" && args.includes("--verify")) {
      if (opts.sideExists) return Buffer.from("sidesha\n");
      throw new Error("not a valid ref");
    }
    if (args[0] === "rev-list") {
      return Buffer.from(`${opts.commitRange ?? "1"}\n`);
    }
    if (args[0] === "fetch" && args[args.length - 1] === "soleur/kb-sync") {
      if (opts.sideExists) return Buffer.from("");
      throw new Error("couldn't find remote ref soleur/kb-sync");
    }
    if (args[0] === "fetch") return Buffer.from("");
    if (args[0] === "diff") {
      // exit 0 (no diff) → no commit; exit 1 (changes) → commit
      if (opts.noStagedChanges) return Buffer.from("");
      throw new Error("changes staged");
    }
    // checkout / commit / reset → no output
    return Buffer.from("");
  };
}

/** Index of the first git call whose argv joins to `needle` (or -1). */
function gitIdx(needle: string): number {
  return gitCalls.findIndex((a) => a.join(" ") === needle);
}

beforeEach(() => {
  gitCalls = [];
  reportSilentFallbackSpy.mockReset();
  warnSilentFallbackSpy.mockReset();
  gitWithInstallationAuthSpy.mockReset();
  getCurrentRepoUrlSpy.mockReset();
  getCurrentRepoUrlSpy.mockResolvedValue("https://github.com/acme/widgets");
  findOpenPullRequestSpy.mockReset();
  findOpenPullRequestSpy.mockResolvedValue(null);
  createPullRequestSpy.mockReset();
  createPullRequestSpy.mockResolvedValue({
    number: 7,
    htmlUrl: "https://github.com/acme/widgets/pull/7",
    url: "https://api.github.com/repos/acme/widgets/pulls/7",
  });
  resolveInstallationIdSpy.mockReset();
  resolveInstallationIdSpy.mockResolvedValue(42);
});

describe("classifyPushError", () => {
  test("GH006 protected-branch rejection → protected_branch", () => {
    const err = pushErr("Command failed: git push", PROTECTED_STDERR);
    expect(classifyPushError(err)).toBe("protected_branch");
  });

  test("required-approving-review tail still classifies protected_branch", () => {
    const err = pushErr(
      "push failed",
      "remote: error: GH006: Protected branch update failed for refs/heads/main.\nremote: error: At least 1 approving review is required by reviewers with write access.",
    );
    expect(classifyPushError(err)).toBe("protected_branch");
  });

  test("required-status-check tail still classifies protected_branch", () => {
    const err = pushErr(
      "push failed",
      ' ! [remote rejected] main -> main (protected branch hook declined)\nremote: error: Required status check "ci" is expected.',
    );
    expect(classifyPushError(err)).toBe("protected_branch");
  });

  test("require-PR tail without GH006 prefix still classifies protected_branch", () => {
    // Defensive: GitHub always prefixes with GH006 today, but a require-PR-only
    // protection config whose stderr drops the prefix must still route to the
    // fallback, not loop the divergence treadmill.
    const err = pushErr(
      "push failed",
      " ! [remote rejected] main -> main\nremote: error: Changes must be made through a pull request.",
    );
    expect(classifyPushError(err)).toBe("protected_branch");
  });

  test("shallow clone reject → persistent_other (must not loop)", () => {
    const err = pushErr(
      "push failed",
      " ! [remote rejected] main -> main (shallow update not allowed)\nerror: failed to push some refs",
    );
    expect(classifyPushError(err)).toBe("persistent_other");
  });

  test("auth failure → other (existing best-effort retry)", () => {
    const err = pushErr(
      "Command failed: git push",
      "remote: Invalid username or password.\nfatal: Authentication failed for 'https://github.com/owner/repo.git/'",
    );
    expect(classifyPushError(err)).toBe("other");
  });

  test("network failure → other", () => {
    const err = pushErr(
      "Command failed: git push",
      "fatal: unable to access 'https://github.com/owner/repo.git/': Could not resolve host: github.com",
    );
    expect(classifyPushError(err)).toBe("other");
  });

  test("non-Error input does not throw and classifies other", () => {
    expect(classifyPushError("some string")).toBe("other");
    expect(classifyPushError(undefined)).toBe("other");
  });
});

describe("syncPush — protected-branch fallback (#5426 Phase 2)", () => {
  // AC2 — pushes soleur/kb-sync to the USER's repo + opens a PR, base resolved
  // dynamically (never hardcoded main).
  test("AC2: protected push → side branch + create PR in the user's repo", async () => {
    gitWithInstallationAuthSpy.mockImplementation(makeGitMock());

    await syncPush("user-1", "/tmp/ws");

    expect(gitIdx("push origin HEAD:refs/heads/soleur/kb-sync")).toBeGreaterThan(
      -1,
    );
    expect(createPullRequestSpy).toHaveBeenCalledTimes(1);
    expect(createPullRequestSpy).toHaveBeenCalledWith(
      42,
      "acme",
      "widgets",
      "soleur/kb-sync",
      "main",
      expect.stringMatching(/knowledge-base/i),
      expect.any(String),
    );
  });

  test("AC2: base is the RESOLVED default branch, never hardcoded main", async () => {
    gitWithInstallationAuthSpy.mockImplementation(
      makeGitMock({ defaultRef: "origin/develop" }),
    );

    await syncPush("user-1", "/tmp/ws");

    expect(createPullRequestSpy).toHaveBeenCalledWith(
      42,
      "acme",
      "widgets",
      "soleur/kb-sync",
      "develop",
      expect.any(String),
      expect.any(String),
    );
    // reset target also tracks the resolved default
    expect(gitIdx("reset --hard origin/develop")).toBeGreaterThan(-1);
  });

  // AC3 — after success, default is reset to origin and HEAD restored to it,
  // and the reset happens ONLY AFTER the side-branch push + PR.
  test("AC3: default reset to origin happens after side-branch push + PR", async () => {
    gitWithInstallationAuthSpy.mockImplementation(makeGitMock());

    await syncPush("user-1", "/tmp/ws");

    const sidePush = gitIdx("push origin HEAD:refs/heads/soleur/kb-sync");
    const checkoutDefault = gitIdx("checkout main");
    const reset = gitIdx("reset --hard origin/main");
    expect(sidePush).toBeGreaterThan(-1);
    expect(reset).toBeGreaterThan(sidePush);
    expect(checkoutDefault).toBeGreaterThan(sidePush);
    expect(reset).toBeGreaterThan(checkoutDefault);
  });

  // AC4 — tree-overlay accretion: build soleur/kb-sync FROM the existing side
  // branch (preserving its prior commits) via `checkout <defaultHead> --
  // knowledge-base`, never `checkout -B` from default and never cherry-pick.
  test("AC4: accretes via tree-overlay onto the durable side branch (not checkout-B-from-default, not cherry-pick)", async () => {
    // First fallback — side branch absent → branch from origin/default.
    gitWithInstallationAuthSpy.mockImplementation(
      makeGitMock({ sideExists: false }),
    );
    await syncPush("user-1", "/tmp/ws");
    expect(gitIdx("checkout -f -B soleur/kb-sync origin/main")).toBeGreaterThan(
      -1,
    );
    expect(gitIdx("checkout defHEAD -- knowledge-base")).toBeGreaterThan(-1);
    expect(createPullRequestSpy).toHaveBeenCalledTimes(1);

    // Second fallback — side branch now exists → branch from the SIDE branch
    // (preserves prior commits), reuse the open PR.
    gitCalls = [];
    findOpenPullRequestSpy.mockResolvedValue({
      number: 7,
      htmlUrl: "https://github.com/acme/widgets/pull/7",
      url: "https://api.github.com/repos/acme/widgets/pulls/7",
    });
    createPullRequestSpy.mockClear();
    gitWithInstallationAuthSpy.mockImplementation(
      makeGitMock({ sideExists: true }),
    );
    await syncPush("user-1", "/tmp/ws");

    expect(
      gitIdx("checkout -f -B soleur/kb-sync origin/soleur/kb-sync"),
    ).toBeGreaterThan(-1);
    expect(gitIdx("checkout -f -B soleur/kb-sync origin/main")).toBe(-1);
    expect(gitIdx("checkout defHEAD -- knowledge-base")).toBeGreaterThan(-1);
    // never cherry-pick
    expect(gitCalls.some((a) => a[0] === "cherry-pick")).toBe(false);
    // PR reused, not recreated
    expect(createPullRequestSpy).not.toHaveBeenCalled();
  });

  // AC5 — unprotected path unchanged: bare push succeeds → no fallback at all.
  test("AC5: unprotected default → direct push, no fallback", async () => {
    gitWithInstallationAuthSpy.mockImplementation(
      makeGitMock({ initialPush: "ok" }),
    );

    await syncPush("user-1", "/tmp/ws");

    expect(createPullRequestSpy).not.toHaveBeenCalled();
    expect(gitCalls.some((a) => a[0] === "checkout")).toBe(false);
    expect(gitCalls.some((a) => a[0] === "reset")).toBe(false);
    // no failure op
    expect(
      reportSilentFallbackSpy.mock.calls.some(
        ([, ctx]) =>
          (ctx as { op?: string }).op === "kb-sync.protected-fallback-failed",
      ),
    ).toBe(false);
  });

  // AC6 — failure preserves writes: a side-branch push failure must NOT reset
  // default, must restore HEAD to default, and must emit the failure op.
  test("AC6: side-branch push failure preserves writes (no reset) + emits failure op", async () => {
    gitWithInstallationAuthSpy.mockImplementation(
      makeGitMock({ sideBranchPushFails: true }),
    );

    await syncPush("user-1", "/tmp/ws");

    // default NOT reset (writes survive on default for next-session retry)
    expect(gitIdx("reset --hard origin/main")).toBe(-1);
    // PR never attempted (failed before it)
    expect(createPullRequestSpy).not.toHaveBeenCalled();
    // restored back to default branch so the workspace isn't parked on the side branch
    expect(gitIdx("checkout main")).toBeGreaterThan(-1);
    // failure op emitted, discriminated as a ran-and-failed fallback
    const failed = reportSilentFallbackSpy.mock.calls.filter(
      ([, ctx]) =>
        (ctx as { op?: string }).op === "kb-sync.protected-fallback-failed",
    );
    expect(failed).toHaveLength(1);
    expect((failed[0][1] as { extra?: { reason?: string } }).extra?.reason).toBe(
      "fallback_failed",
    );
  });

  // AC7 — idempotent re-entry: empty range + no overlay diff + open PR exists →
  // no-op reuse, NOT reported as failure, success warn emitted.
  test("AC7: idempotent empty re-entry reuses PR and is not a failure", async () => {
    findOpenPullRequestSpy.mockResolvedValue({
      number: 7,
      htmlUrl: "https://github.com/acme/widgets/pull/7",
      url: "https://api.github.com/repos/acme/widgets/pulls/7",
    });
    gitWithInstallationAuthSpy.mockImplementation(
      makeGitMock({ sideExists: true, commitRange: "0", noStagedChanges: true }),
    );

    await syncPush("user-1", "/tmp/ws");

    // no commit when overlay produced no diff
    expect(gitCalls.some((a) => a[0] === "commit")).toBe(false);
    // PR reused, not recreated
    expect(createPullRequestSpy).not.toHaveBeenCalled();
    // not a failure
    expect(
      reportSilentFallbackSpy.mock.calls.some(
        ([, ctx]) =>
          (ctx as { op?: string }).op === "kb-sync.protected-fallback-failed",
      ),
    ).toBe(false);
    // success warn op fired
    expect(
      warnSilentFallbackSpy.mock.calls.some(
        ([, ctx]) =>
          (ctx as { op?: string }).op === "kb-sync.push-protected-fallback",
      ),
    ).toBe(true);
  });

  // Observability — success entry op carries PR url + commit count.
  test("success emits kb-sync.push-protected-fallback warn with PR url + commit count", async () => {
    gitWithInstallationAuthSpy.mockImplementation(
      makeGitMock({ commitRange: "2" }),
    );

    await syncPush("user-1", "/tmp/ws");

    const warn = warnSilentFallbackSpy.mock.calls.find(
      ([, ctx]) =>
        (ctx as { op?: string }).op === "kb-sync.push-protected-fallback",
    );
    expect(warn).toBeDefined();
    expect(warn![1]).toEqual(
      expect.objectContaining({
        feature: "session-sync",
        op: "kb-sync.push-protected-fallback",
        extra: expect.objectContaining({
          prUrl: "https://github.com/acme/widgets/pull/7",
          commitCount: 2,
        }),
      }),
    );
  });

  // Classification routing — persistent_other does NOT enter the fallback and
  // gets a distinct failure op (no infinite retry loop).
  test("persistent_other (shallow) → failure op, no fallback git work", async () => {
    gitWithInstallationAuthSpy.mockImplementation(
      makeGitMock({ initialPush: "shallow" }),
    );

    await syncPush("user-1", "/tmp/ws");

    // fallback never ran (no default-branch resolution)
    expect(gitCalls.some((a) => a[0] === "symbolic-ref")).toBe(false);
    expect(createPullRequestSpy).not.toHaveBeenCalled();
    const failed = reportSilentFallbackSpy.mock.calls.filter(
      ([, ctx]) =>
        (ctx as { op?: string }).op === "kb-sync.protected-fallback-failed",
    );
    expect(failed).toHaveLength(1);
    // same op as a failed fallback, but discriminated via reason so Sentry can
    // tell "never attempted" from "ran and failed"
    expect((failed[0][1] as { extra?: { reason?: string } }).extra?.reason).toBe(
      "persistent_other",
    );
  });

  // Classification routing — `other` (auth/network) falls through to the
  // existing outer-catch best-effort retry (op:syncPush), no fallback.
  test("other (auth) → outer catch op:syncPush, no fallback", async () => {
    gitWithInstallationAuthSpy.mockImplementation(
      makeGitMock({ initialPush: "auth" }),
    );

    await syncPush("user-1", "/tmp/ws");

    expect(gitCalls.some((a) => a[0] === "symbolic-ref")).toBe(false);
    expect(createPullRequestSpy).not.toHaveBeenCalled();
    const syncPushOp = reportSilentFallbackSpy.mock.calls.filter(
      ([, ctx]) => (ctx as { op?: string }).op === "syncPush",
    );
    expect(syncPushOp).toHaveLength(1);
  });
});
