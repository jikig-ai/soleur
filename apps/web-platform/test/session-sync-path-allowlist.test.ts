// ---------------------------------------------------------------------------
// Path-allowlist tests for session-sync auto-commit behavior (#2905).
//
// The autonomous loop's `syncPull` and `syncPush` previously ran `git add -A`
// before committing, which swept ambient working-tree state (`.claude/settings.json`
// drift, stray `.claude/worktrees/*` markers, doc edits) into whatever feature
// branch the loop happened to be on. These tests pin the path-scoped behavior:
// only `knowledge-base/**` paths get auto-committed; everything else stays dirty.
// ---------------------------------------------------------------------------

import { describe, test, expect, vi, beforeEach } from "vitest";
import { stripHostGitBlock } from "./helpers/host-git-block";

process.env.NEXT_PUBLIC_SUPABASE_URL ??= "https://test.supabase.co";
process.env.SUPABASE_SERVICE_ROLE_KEY ??= "test-service-role-key";

// Track every execFileSync call across tests for assertion.
type Call = { cmd: string; args: string[] };
const calls: Call[] = [];

// Controlled git-status-porcelain output per test.
let porcelainOutput = "";

vi.mock("child_process", async () => {
  // D38(1): the connected-repo runner is async; the sync stub drives `execFile` through the adapter.
  const { execFileFromSync } = await import("./helpers/exec-file-from-sync");
  const execFileSync = vi.fn((cmd: string, rawArgs: string[], _opts?: unknown) => {
    const args = stripHostGitBlock(rawArgs);
    calls.push({ cmd, args });
    if (args[0] === "remote") {
      // Pretend a remote exists so syncPull/syncPush proceed.
      return Buffer.from("origin\tgit@github.com:test/test.git (fetch)\n");
    }
    if (args[0] === "status" && args[1].startsWith("--porcelain")) {
      return Buffer.from(porcelainOutput);
    }
    if (args[0] === "rev-list") {
      return Buffer.from("1\n");
    }
    return Buffer.from("");
  });
  return { execFileSync, execFile: vi.fn(execFileFromSync(execFileSync)) };
});

vi.mock("fs", () => ({
  readdirSync: vi.fn(() => []),
  lstatSync: vi.fn(() => {
    throw Object.assign(new Error("ENOENT"), { code: "ENOENT" }); // host-git shape guard: the fake workspace has no .git
  }),
}));

vi.mock("@supabase/supabase-js", () => ({
  createClient: vi.fn(),
}));

// PR-C §2.1 (#3244): session-sync.ts now imports `getFreshTenantClient`
// + `RuntimeAuthError` from `@/lib/supabase/tenant` instead of
// `createServiceClient` from `@/lib/supabase/service`. Recursive mock
// chain so any combination of `.select().eq().single() / .maybeSingle()`
// or `.update().eq()` resolves to the same shape — both the auth probe
// (`.maybeSingle()`) and the 4 migrated sites (`.single()`/`.eq()`).
// `vi.hoisted` is required for the class — `vi.mock` factories run
// BEFORE top-level `class`/`const` declarations execute.
const { FakeRuntimeAuthError } = vi.hoisted(() => ({
  FakeRuntimeAuthError: class FakeRuntimeAuthError extends Error {},
}));
vi.mock("@/lib/supabase/tenant", () => {
  const eqChain: {
    maybeSingle: () => Promise<{ data: { id: string } | null; error: null }>;
    single: () => Promise<{
      data: { github_installation_id: number; kb_sync_history: never[] };
      error: null;
    }>;
    then: (resolve: (v: { error: null }) => unknown) => unknown;
  } = {
    maybeSingle: async () => ({ data: { id: "user-1" }, error: null }),
    single: async () => ({
      data: { github_installation_id: 1234, kb_sync_history: [] },
      error: null,
    }),
    // `.update().eq()` returns a thenable; consumer `await`s it directly.
    then: (resolve: (v: { error: null }) => unknown) =>
      resolve({ error: null }),
  };
  const fromChain = {
    select: () => ({ eq: () => eqChain }),
    update: () => ({ eq: () => eqChain }),
  };
  return {
    getFreshTenantClient: vi.fn(async () => ({
      from: () => fromChain,
      // ADR-044: resolveInstallationId reads the credential via the
      // resolve_workspace_installation_id RPC (was a users SELECT).
      rpc: async () => ({ data: 1234, error: null }),
    })),
    RuntimeAuthError: FakeRuntimeAuthError,
  };
});

vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
  // R2-B: the pull's outer catch-all now writes its pull-held line (obs F3), whose warning mirror this reaches
  mirrorWarnWithDebounce: vi.fn(),
}));

vi.mock("../server/git-auth", () => ({
  gitWithInstallationAuth: vi.fn(async () => Buffer.from("")),
}));

// Capture log messages so vacuous-absence tests can assert that the
// allowlist was actually evaluated (vs. an early-return elsewhere).
// Hoisted via `vi.hoisted` because `vi.mock(...)` runs before
// top-level `const` declarations execute.
const { logInfo } = vi.hoisted(() => ({ logInfo: vi.fn() }));
vi.mock("../server/logger", () => ({
  createChildLogger: () => ({
    info: logInfo,
    warn: vi.fn(),
    error: vi.fn(),
    debug: vi.fn(),
  }),
}));

import { assertConnectedRepoArgv, MERGE_CONFIG_PINS, mergeArgv } from "../server/connected-repo-git";
import { syncPull, syncPush } from "../server/session-sync";
import { AUTO_MERGE_MSG_PULL } from "../server/kb-sync-pull";

// ADR-044 PR-B: syncPull/syncPush take an injected service client + resolved
// workspace id. A minimal stub satisfies writeRepoColsToWorkspace's chain.
const STUB_SERVICE = {
  from: () => ({
    update: () => ({
      eq: () => ({
        select: () => Promise.resolve({ data: [{ id: "user-1" }], error: null }),
      }),
    }),
  }),
} as never;

beforeEach(() => {
  calls.length = 0;
  porcelainOutput = "";
  logInfo.mockClear();
});

function loggedSkip(): boolean {
  // The SUT logs this exact string when it computed an empty allowlist
  // and chose to skip the auto-commit. Used by TS-2/TS-3 to discriminate
  // "evaluated allowlist and got []" from a vacuous "didn't reach this code path".
  return logInfo.mock.calls.some(
    (call) => call[1] === "No allowlisted changes to commit — skipping auto-commit",
  );
}

function gitAddCalls(): Call[] {
  return calls.filter((c) => c.cmd === "git" && c.args[0] === "add");
}

function gitCommitCalls(): Call[] {
  return calls.filter((c) => c.cmd === "git" && c.args[0] === "commit");
}

describe("session-sync path allowlist (#2905)", () => {
  test("TS-1: mixed dirty workspace stages only knowledge-base paths", async () => {
    // `git status --porcelain=v1 -z` returns NUL-separated entries:
    //   " M .claude/settings.json"      — modified, NOT allowlisted
    //   "?? knowledge-base/overview/vision.md" — untracked, allowlisted
    porcelainOutput =
      " M .claude/settings.json\0?? knowledge-base/overview/vision.md\0";

    await syncPull("user-1", "/tmp/workspace", STUB_SERVICE, "user-1");

    const adds = gitAddCalls();
    expect(adds).toHaveLength(1);
    // Must NOT use -A; must pass `--` then explicit paths.
    expect(adds[0].args).not.toContain("-A");
    expect(adds[0].args).toContain("--");
    expect(adds[0].args).toContain("knowledge-base/overview/vision.md");
    expect(adds[0].args).not.toContain(".claude/settings.json");

    const commits = gitCommitCalls();
    expect(commits).toHaveLength(1);
    expect(commits[0].args).toContain("Auto-commit before sync pull");
  });

  test("TS-2: only non-allowlisted dirty paths produce no commit (syncPull)", async () => {
    porcelainOutput = " M .claude/settings.json\0";

    await syncPull("user-1", "/tmp/workspace", STUB_SERVICE, "user-1");

    expect(gitAddCalls()).toHaveLength(0);
    expect(gitCommitCalls()).toHaveLength(0);
    // Positive proof: the SUT actually evaluated the allowlist and got [].
    // Without this, "no commit" could mean "bailed at hasRemote" or any
    // earlier early-return, not "allowlist was empty".
    expect(loggedSkip()).toBe(true);
  });

  test("TS-2b: only non-allowlisted dirty paths produce no commit (syncPush)", async () => {
    porcelainOutput = " M .github/workflows/ci.yml\0";

    await syncPush("user-1", "/tmp/workspace", STUB_SERVICE, "user-1");

    expect(gitAddCalls()).toHaveLength(0);
    expect(gitCommitCalls()).toHaveLength(0);
    expect(loggedSkip()).toBe(true);
  });

  test("TS-3: stray .claude/worktrees/* marker is rejected", async () => {
    porcelainOutput = "?? .claude/worktrees/agent-deadbeef\0";

    await syncPull("user-1", "/tmp/workspace", STUB_SERVICE, "user-1");

    expect(gitAddCalls()).toHaveLength(0);
    expect(gitCommitCalls()).toHaveLength(0);
    expect(loggedSkip()).toBe(true);
  });

  test("TS-3b: stray .claude/worktrees/* with allowlisted sibling — only allowlisted staged", async () => {
    porcelainOutput =
      "?? .claude/worktrees/agent-deadbeef\0 M knowledge-base/foo.md\0";

    await syncPush("user-1", "/tmp/workspace", STUB_SERVICE, "user-1");

    const adds = gitAddCalls();
    expect(adds).toHaveLength(1);
    expect(adds[0].args).toContain("knowledge-base/foo.md");
    expect(adds[0].args.some((a) => a.includes(".claude/worktrees/"))).toBe(false);
  });

  test("TS-1b: rename-syntax tracks destination path only (cross-allowlist boundary)", async () => {
    // Under `git status --porcelain=v1 -z`, a rename emits the destination
    // first then the source as a separate NUL entry: "R  <new>\0<old>\0".
    // Source is OUTSIDE the allowlist (`docs/`), destination is INSIDE.
    // The parser must skip the source entry; otherwise the source might
    // either match the allowlist (false positive) or be misparsed.
    porcelainOutput = "R  knowledge-base/new.md\0docs/old.md\0";

    await syncPull("user-1", "/tmp/workspace", STUB_SERVICE, "user-1");

    const adds = gitAddCalls();
    expect(adds).toHaveLength(1);
    expect(adds[0].args).toContain("knowledge-base/new.md");
    // The "old" path must not be staged in any form.
    expect(adds[0].args).not.toContain("docs/old.md");
    expect(adds[0].args.some((a) => a.startsWith("docs/"))).toBe(false);
  });

  test("TS-1c: paths with whitespace and quotes round-trip via -z (no C-quoting)", async () => {
    // Without -z, git C-quotes paths containing tabs/newlines/quotes,
    // breaking `git add --` (the quoted form is not the on-disk filename).
    // With -z, the path is emitted verbatim. This pins the contract.
    porcelainOutput =
      ' M knowledge-base/has space.md\0?? knowledge-base/has\t"quote".md\0';

    await syncPush("user-1", "/tmp/workspace", STUB_SERVICE, "user-1");

    const adds = gitAddCalls();
    expect(adds).toHaveLength(1);
    expect(adds[0].args).toContain("knowledge-base/has space.md");
    expect(adds[0].args).toContain('knowledge-base/has\t"quote".md');
  });

  test("forbidden flags (--force/--amend/--hard) never reach git", async () => {
    // The wrapper rejects --force/--amend/--hard/--no-verify on any
    // allowed subcommand. None of session-sync's call sites use these
    // flags today; this test pins that invariant against future drift.
    porcelainOutput = " M knowledge-base/foo.md\0";
    await syncPush("user-1", "/tmp/workspace", STUB_SERVICE, "user-1");
    for (const c of calls) {
      if (c.cmd !== "git") continue;
      expect(c.args).not.toContain("--force");
      expect(c.args).not.toContain("--amend");
      expect(c.args).not.toContain("--hard");
      expect(c.args).not.toContain("--no-verify");
    }
  });

  test("destructive subcommands (rm/reset/clean/checkout) are not invoked", async () => {
    // Belt-and-suspenders: even with allowlisted paths, the wrapper's
    // subcommand allowlist must keep `git rm`/`git reset`/`git clean`/
    // `git checkout` off the connected-repo write path.
    porcelainOutput = " M knowledge-base/foo.md\0";
    await syncPush("user-1", "/tmp/workspace", STUB_SERVICE, "user-1");
    const gitArgs0 = calls.filter((c) => c.cmd === "git").map((c) => c.args[0]);
    expect(gitArgs0).not.toContain("rm");
    expect(gitArgs0).not.toContain("reset");
    expect(gitArgs0).not.toContain("clean");
    expect(gitArgs0).not.toContain("checkout");
    expect(gitArgs0).not.toContain("branch");
  });

  test("D21: syncPush runs ONE status per turn, and that one run still sees an unmerged entry (no add, no commit)", async () => {
    porcelainOutput = "M  knowledge-base/a.md\0?? knowledge-base/new.md\0";
    await syncPush("user-1", "/tmp/fake-workspace", STUB_SERVICE, "user-1");
    expect(calls.filter((c) => c.args[0] === "status")).toHaveLength(1);
    expect(calls.filter((c) => c.args[0] === "add")[0]?.args).toEqual(["add", "--", "knowledge-base/a.md", "knowledge-base/new.md"]);
    calls.length = 0;
    porcelainOutput = "UU knowledge-base/a.md\0?? knowledge-base/new.md\0";
    await syncPush("user-1", "/tmp/fake-workspace", STUB_SERVICE, "user-1");
    expect(calls.filter((c) => c.args[0] === "status")).toHaveLength(1);
    expect(calls.filter((c) => c.args[0] === "add" || c.args[0] === "commit")).toEqual([]);
  });

  test("auto-commit never invokes 'git add -A' or 'git add .'", async () => {
    porcelainOutput =
      " M .claude/settings.json\0 M knowledge-base/foo.md\0 M .github/workflows/x.yml\0";

    await syncPush("user-1", "/tmp/workspace", STUB_SERVICE, "user-1");

    const adds = gitAddCalls();
    expect(adds).toHaveLength(1);
    // Tight invariant: the staged argv MUST be exactly add + -- + paths.
    // Rejects "-A", "-u", ".", ":", and any future regression to a sweep flag.
    expect(adds[0].args).toEqual(["add", "--", "knowledge-base/foo.md"]);
  });
});

// #12600 (CTO rulings R12, R19, R20): the only two workspace WRITE verbs the KB sync adds, each behind an exact-argv
// guard. Every other argv for these verbs throws before git runs.
describe("connected-repo argv guard: update-ref --no-deref and unpack-objects -q (#12600)", () => {
  const A = "a".repeat(40);
  const B = "b".repeat(40);
  test.each([
    [["update-ref", "--no-deref", "refs/heads/main", A, B]],
    [["update-ref", "--no-deref", "refs/heads/trunk", A, B]],
    [["update-ref", "--no-deref", "refs/remotes/origin/main", A]],
    [["unpack-objects", "-q"]],
  ])("accepts the guarded shape %j", (argv) => {
    expect(() => assertConnectedRepoArgv(argv)).not.toThrow();
  });
  test.each([
    [["update-ref", "--no-deref", "refs/heads/main", A]], // CAS old value mandatory on refs/heads
    [["update-ref", "--no-deref", "refs/remotes/origin/main", A, B]],
    [["update-ref", "--no-deref", "refs/heads/main", A, B, "extra"]],
    [["update-ref", "--no-deref", "refs/tags/v1", A, B]],
    [["update-ref", "--no-deref", "refs/heads/main", "HEAD", B]],
    [["update-ref", "--no-deref", "refs/heads/main", A.toUpperCase(), B]],
    [["update-ref", "--no-deref", "refs/heads/bad..name", A, B]],
    [["update-ref", "--no-deref", "refs/heads/main", A, "0".repeat(39)]],
    [["update-ref", "-d", "refs/heads/main"]],
    [["update-ref", "--stdin"]],
    [["update-ref", "--no-deref", "-m", "x", "refs/heads/main", A, B]],
    [["update-ref", "--no-deref", "refs/remotes/upstream/main", A]],
    [["update-ref", "--no-deref", "HEAD", A, B]],
    [["update-ref", "--no-deref", "refs/heads/main", "0".repeat(40), B]], // all-zero new value (D13)
    [["update-ref", "--no-deref", "refs/heads/main", A, "0".repeat(40)]], // all-zero old value ("must not exist")
    [["update-ref", "--no-deref", "refs/remotes/origin/main", "0".repeat(40)]],
    [["unpack-objects"]],
    [["unpack-objects", "-q", "--strict"]],
    [["unpack-objects", "-n"]],
    [["update-ref", "--no-deref", "refs/heads/main", A, B, "--force"]],
  ])("refuses %j", (argv) => {
    expect(() => assertConnectedRepoArgv(argv)).toThrow();
  });
  test.each([
    [["update-ref", "refs/heads/main", A, B]],
    [["update-ref", "refs/remotes/origin/main", A]],
    [["update-ref", "-m", "x", "--no-deref", "refs/heads/main", A, B]],
  ])("refuses %j for the missing --no-deref (R19), not for another shape reason", (argv) => {
    expect(() => assertConnectedRepoArgv(argv)).toThrow(/--no-deref/);
  });
  test("other verbs keep their existing checks (destructive verbs and forbidden flags still refuse)", () => {
    expect(() => assertConnectedRepoArgv(["reset", "--hard"])).toThrow();
    expect(() => assertConnectedRepoArgv(["checkout", "main"])).toThrow();
    expect(() => assertConnectedRepoArgv(["commit", "--amend"])).toThrow();
    expect(() => assertConnectedRepoArgv(["status", "--porcelain=v1", "-z"])).not.toThrow();
  });
});

// TX1-e, shape half (#12718, D26(2), D26(5)): the session-start merge is ONE exact argv. Equality with the in-memory `T` is
// the kb-sync-pull row (test/kb-sync-pull.test.ts); here only the shape.
describe("connected-repo argv guard: the pinned session-start merge (#12718)", () => {
  const T = "c".repeat(40);
  const MERGE = ["merge", "--no-edit", "--autostash", "--no-overwrite-ignore", "-m", AUTO_MERGE_MSG_PULL, T];
  test("the pins, then the merge of a 40-hex target, pass", () => {
    expect(mergeArgv(T)).toEqual([...MERGE_CONFIG_PINS, ...MERGE]);
    expect(() => assertConnectedRepoArgv(mergeArgv(T))).not.toThrow();
  });
  test("every D26(2) pin is present, each behind its own -c", () => {
    const pins = MERGE_CONFIG_PINS.filter((_, i) => i % 2 === 1);
    expect(MERGE_CONFIG_PINS.filter((_, i) => i % 2 === 0).every((c) => c === "-c")).toBe(true);
    expect(pins).toEqual([
      "merge.verifySignatures=false",
      "gpg.program=/bin/false",
      "gpg.ssh.program=/bin/false",
      "gpg.x509.program=/bin/false",
      "merge.renormalize=false",
      // R2-B (data-sec P3-1): no directory-rename relocation of an upstream path onto an ignored local one
      "merge.directoryRenames=false",
      "merge.default=text",
      "rerere.enabled=false",
      "rerere.autoUpdate=false",
      "merge.stat=false",
      "maintenance.auto=false",
      "gc.auto=0",
      "core.hooksPath=/dev/null",
    ]);
  });
  const without = (drop: string): string[] => mergeArgv(T).filter((a) => a !== drop);
  test.each([
    ["the merge without its pins", MERGE],
    ["a missing pin", [...MERGE_CONFIG_PINS.slice(2), ...MERGE]],
    ["an extra -c pin", ["-c", "core.fsmonitor=x", ...MERGE_CONFIG_PINS, ...MERGE]],
    ["a -c pin on another verb", [...MERGE_CONFIG_PINS, "commit", "-m", "x"]],
    ["--ff-only", [...MERGE_CONFIG_PINS, "merge", "--ff-only", T]],
    ["merge --abort", [...MERGE_CONFIG_PINS, "merge", "--abort"]],
    ["a bare merge --abort", ["merge", "--abort"]],
    ["no --no-overwrite-ignore", without("--no-overwrite-ignore")],
    ["no --autostash", without("--autostash")],
    ["another message", [...MERGE_CONFIG_PINS, "merge", "--no-edit", "--autostash", "--no-overwrite-ignore", "-m", "x", T]],
    ["a ref name target", [...MERGE_CONFIG_PINS, ...MERGE.slice(0, -1), "refs/remotes/origin/main"]],
    ["an all-zero target", mergeArgv("0".repeat(40))],
    ["a second target", [...mergeArgv(T), T]],
    ["an option-shaped target", [...MERGE_CONFIG_PINS, ...MERGE.slice(0, -1), "--strategy=ours"]],
    ["no merge.directoryRenames=false pin (pull shape)", without("merge.directoryRenames=false").filter((a, i, all) => !(a === "-c" && all[i + 1] === "-c"))],
    ["merge.directoryRenames=true", mergeArgv(T).map((a) => (a === "merge.directoryRenames=false" ? "merge.directoryRenames=true" : a))],
    ["no merge.directoryRenames=false pin (self-heal shape)", mergeArgv(T, { autostash: false }).map((a) => (a === "merge.directoryRenames=false" ? "merge.directoryRenames=conflict" : a))],
  ])("refuses %s", (_name, argv) => {
    expect(() => assertConnectedRepoArgv(argv)).toThrow(/pinned session-start merge/);
  });
});
