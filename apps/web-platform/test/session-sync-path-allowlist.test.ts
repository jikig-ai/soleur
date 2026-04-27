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

vi.mock("../server/logger", () => ({
  createChildLogger: () => ({
    info: vi.fn(),
    warn: vi.fn(),
    error: vi.fn(),
    debug: vi.fn(),
  }),
}));

import { syncPull, syncPush } from "../server/session-sync";

beforeEach(() => {
  calls.length = 0;
  porcelainOutput = "";
});

function gitAddCalls(): Call[] {
  return calls.filter((c) => c.cmd === "git" && c.args[0] === "add");
}

function gitCommitCalls(): Call[] {
  return calls.filter((c) => c.cmd === "git" && c.args[0] === "commit");
}

describe("session-sync path allowlist (#2905)", () => {
  test("TS-1: mixed dirty workspace stages only knowledge-base paths", async () => {
    // `git status --porcelain` returns:
    //   " M .claude/settings.json"      — modified, NOT allowlisted
    //   "?? knowledge-base/overview/vision.md" — untracked, allowlisted
    porcelainOutput =
      " M .claude/settings.json\n?? knowledge-base/overview/vision.md\n";

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
    porcelainOutput = " M .claude/settings.json\n";

    await syncPull("user-1", "/tmp/workspace");

    expect(gitAddCalls()).toHaveLength(0);
    expect(gitCommitCalls()).toHaveLength(0);
    // Pull itself proceeds (gitWithInstallationAuth would have been called).
  });

  test("TS-2b: only non-allowlisted dirty paths produce no commit (syncPush)", async () => {
    porcelainOutput = " M .github/workflows/ci.yml\n";

    await syncPush("user-1", "/tmp/workspace");

    expect(gitAddCalls()).toHaveLength(0);
    expect(gitCommitCalls()).toHaveLength(0);
  });

  test("TS-3: stray .claude/worktrees/* marker is rejected", async () => {
    porcelainOutput = "?? .claude/worktrees/agent-deadbeef\n";

    await syncPull("user-1", "/tmp/workspace");

    expect(gitAddCalls()).toHaveLength(0);
    expect(gitCommitCalls()).toHaveLength(0);
  });

  test("TS-3b: stray .claude/worktrees/* with allowlisted sibling — only allowlisted staged", async () => {
    porcelainOutput =
      "?? .claude/worktrees/agent-deadbeef\n M knowledge-base/foo.md\n";

    await syncPush("user-1", "/tmp/workspace");

    const adds = gitAddCalls();
    expect(adds).toHaveLength(1);
    expect(adds[0].args).toContain("knowledge-base/foo.md");
    expect(adds[0].args.some((a) => a.includes(".claude/worktrees/"))).toBe(false);
  });

  test("TS-1b: rename-syntax tracks destination path only", async () => {
    // Git rename in porcelain v1: "R  old -> new"
    porcelainOutput =
      "R  knowledge-base/old.md -> knowledge-base/new.md\n";

    await syncPull("user-1", "/tmp/workspace");

    const adds = gitAddCalls();
    expect(adds).toHaveLength(1);
    expect(adds[0].args).toContain("knowledge-base/new.md");
    // The "old" path is on the left side of the arrow — must not be staged.
    expect(adds[0].args).not.toContain("knowledge-base/old.md");
  });

  test("auto-commit never invokes 'git add -A' or 'git add .'", async () => {
    porcelainOutput =
      " M .claude/settings.json\n M knowledge-base/foo.md\n M .github/workflows/x.yml\n";

    await syncPush("user-1", "/tmp/workspace");

    for (const c of gitAddCalls()) {
      expect(c.args).not.toContain("-A");
      expect(c.args).not.toEqual(["add", "."]);
    }
  });
});
