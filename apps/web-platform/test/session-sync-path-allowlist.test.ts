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

process.env.NEXT_PUBLIC_SUPABASE_URL ??= "https://test.supabase.co";
process.env.SUPABASE_SERVICE_ROLE_KEY ??= "test-service-role-key";

// Track every execFileSync call across tests for assertion.
type Call = { cmd: string; args: string[] };
const calls: Call[] = [];

// Controlled git-status-porcelain output per test.
let porcelainOutput = "";

vi.mock("child_process", () => ({
  execFileSync: vi.fn((cmd: string, args: string[], _opts?: unknown) => {
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
  }),
}));

vi.mock("fs", () => ({
  readdirSync: vi.fn(() => []),
}));

vi.mock("@supabase/supabase-js", () => ({
  createClient: vi.fn(),
}));

vi.mock("@/lib/supabase/service", () => ({
  createServiceClient: vi.fn(() => ({
    from: vi.fn(() => ({
      select: vi.fn(() => ({
        eq: vi.fn(() => ({
          single: vi.fn(async () => ({
            data: { github_installation_id: 1234, kb_sync_history: [] },
            error: null,
          })),
        })),
      })),
      update: vi.fn(() => ({
        eq: vi.fn(async () => ({ error: null })),
      })),
    })),
  })),
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

import { syncPull, syncPush } from "../server/session-sync";

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

    await syncPull("user-1", "/tmp/workspace");

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

    await syncPull("user-1", "/tmp/workspace");

    expect(gitAddCalls()).toHaveLength(0);
    expect(gitCommitCalls()).toHaveLength(0);
    // Positive proof: the SUT actually evaluated the allowlist and got [].
    // Without this, "no commit" could mean "bailed at hasRemote" or any
    // earlier early-return, not "allowlist was empty".
    expect(loggedSkip()).toBe(true);
  });

  test("TS-2b: only non-allowlisted dirty paths produce no commit (syncPush)", async () => {
    porcelainOutput = " M .github/workflows/ci.yml\0";

    await syncPush("user-1", "/tmp/workspace");

    expect(gitAddCalls()).toHaveLength(0);
    expect(gitCommitCalls()).toHaveLength(0);
    expect(loggedSkip()).toBe(true);
  });

  test("TS-3: stray .claude/worktrees/* marker is rejected", async () => {
    porcelainOutput = "?? .claude/worktrees/agent-deadbeef\0";

    await syncPull("user-1", "/tmp/workspace");

    expect(gitAddCalls()).toHaveLength(0);
    expect(gitCommitCalls()).toHaveLength(0);
    expect(loggedSkip()).toBe(true);
  });

  test("TS-3b: stray .claude/worktrees/* with allowlisted sibling — only allowlisted staged", async () => {
    porcelainOutput =
      "?? .claude/worktrees/agent-deadbeef\0 M knowledge-base/foo.md\0";

    await syncPush("user-1", "/tmp/workspace");

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

    await syncPull("user-1", "/tmp/workspace");

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

    await syncPush("user-1", "/tmp/workspace");

    const adds = gitAddCalls();
    expect(adds).toHaveLength(1);
    expect(adds[0].args).toContain("knowledge-base/has space.md");
    expect(adds[0].args).toContain('knowledge-base/has\t"quote".md');
  });

  test("auto-commit never invokes 'git add -A' or 'git add .'", async () => {
    porcelainOutput =
      " M .claude/settings.json\0 M knowledge-base/foo.md\0 M .github/workflows/x.yml\0";

    await syncPush("user-1", "/tmp/workspace");

    const adds = gitAddCalls();
    expect(adds).toHaveLength(1);
    // Tight invariant: the staged argv MUST be exactly add + -- + paths.
    // Rejects "-A", "-u", ".", ":", and any future regression to a sweep flag.
    expect(adds[0].args).toEqual(["add", "--", "knowledge-base/foo.md"]);
  });
});
