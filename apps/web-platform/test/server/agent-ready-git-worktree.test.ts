import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { mkdtemp, rm, mkdir, writeFile, symlink } from "node:fs/promises";
import { realpathSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { execFile } from "node:child_process";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

// Spy the self-stop / inconclusive emits without standing up Sentry.
const { mockSelfStop, mockInconclusive } = vi.hoisted(() => ({
  mockSelfStop: vi.fn(),
  mockInconclusive: vi.fn(),
}));
vi.mock("@/server/repo-resolver-divergence", () => ({
  reportAgentReadinessSelfStop: mockSelfStop,
  reportAgentReadinessProbeInconclusive: mockInconclusive,
}));

import {
  hostGitRevParseOutcome,
  buildGitProbeEnv,
  evaluateAgentReadiness,
  isLstatValidKind,
  type GitRevParseRunner,
  type GitRevParseOutcome,
} from "@/server/git-worktree-validity";

// #5733 deliverable A — the host `git rev-parse --is-inside-work-tree` confirm
// for the corrupt-`dir-valid` slice the sync lstat verdict cannot adjudicate, the
// hardened/ceiling-pinned probe env, and the shared `evaluateAgentReadiness` gate
// (fail-OPEN on inconclusive, emit + honest-block on a confirmed not-a-worktree).

describe("git probe env hardening (#5733 AC1/AC2)", () => {
  let dir: string;
  beforeEach(async () => {
    dir = await mkdtemp(join(tmpdir(), "agentready-env-"));
  });
  afterEach(async () => {
    await rm(dir, { recursive: true, force: true });
    vi.clearAllMocks();
  });

  it("AC2: GIT_CEILING_DIRECTORIES is the absolute, symlink-resolved parent", async () => {
    const real = join(dir, "realroot");
    await mkdir(join(real, "ws"), { recursive: true });
    const symRoot = join(dir, "symroot");
    await symlink(real, symRoot);
    const ws = join(symRoot, "ws"); // parent component is a symlink

    const built = buildGitProbeEnv(ws);
    expect(built).not.toBeNull();
    // The ceiling resolves the symlinked `/workspaces` component (realpath), so
    // host git cannot ascend past the real parent into a parent `.git`.
    expect(built!.env.GIT_CEILING_DIRECTORIES).toBe(realpathSync(real));
  });

  it("AC1: hardened env carries NO installation token / askpass and pins the safe git flags", async () => {
    const ws = join(dir, "ws");
    await mkdir(ws, { recursive: true });
    // Even if the ambient env holds a credential, the probe env must strip it.
    const prevToken = process.env.GIT_INSTALLATION_TOKEN;
    const prevAskpass = process.env.GIT_ASKPASS;
    process.env.GIT_INSTALLATION_TOKEN = "ghs_should_never_reach_probe";
    process.env.GIT_ASKPASS = "/tmp/askpass.sh";
    try {
      const built = buildGitProbeEnv(ws);
      expect(built).not.toBeNull();
      const env = built!.env;
      expect(env.GIT_INSTALLATION_TOKEN).toBeUndefined();
      expect(env.GIT_ASKPASS).toBeUndefined();
      expect(env.GIT_USERNAME).toBeUndefined();
      expect(env.GIT_CONFIG_NOSYSTEM).toBe("1");
      expect(env.GIT_CONFIG_GLOBAL).toBe("/dev/null");
      expect(env.GIT_TERMINAL_PROMPT).toBe("0");
    } finally {
      if (prevToken === undefined) delete process.env.GIT_INSTALLATION_TOKEN;
      else process.env.GIT_INSTALLATION_TOKEN = prevToken;
      if (prevAskpass === undefined) delete process.env.GIT_ASKPASS;
      else process.env.GIT_ASKPASS = prevAskpass;
    }
  });

  it("returns null (→ inconclusive) when the workspace parent cannot be resolved", () => {
    expect(buildGitProbeEnv(join(dir, "does", "not", "exist", "ws"))).toBeNull();
  });

  it("FIX 2: ambient git-exec hooks (GIT_DIR / GIT_SSH_COMMAND / …) do NOT survive; PATH+HOME do", async () => {
    const ws = join(dir, "ws");
    await mkdir(ws, { recursive: true });
    // A `...process.env` spread would let these leak into `git -C <path> rev-parse`.
    // GIT_DIR is the critical one: it would make the probe resolve via an UNRELATED
    // repo (returning "true" for the wrong dir → a false PASS that re-darkens the
    // strand). The minimal allowlist must drop ALL of them.
    const keys = [
      "GIT_DIR",
      "GIT_SSH_COMMAND",
      "GIT_PROXY_COMMAND",
      "GIT_EXTERNAL_DIFF",
      "GIT_CONFIG_COUNT",
    ] as const;
    const saved: Record<string, string | undefined> = {};
    for (const k of keys) saved[k] = process.env[k];
    process.env.GIT_DIR = "/some/other/repo/.git";
    process.env.GIT_SSH_COMMAND = "ssh -i /tmp/evil";
    process.env.GIT_PROXY_COMMAND = "/tmp/proxy";
    process.env.GIT_EXTERNAL_DIFF = "/tmp/diff";
    process.env.GIT_CONFIG_COUNT = "1";
    try {
      const built = buildGitProbeEnv(ws);
      expect(built).not.toBeNull();
      const env = built!.env;
      for (const k of keys) expect(env[k]).toBeUndefined();
      // PATH + HOME ARE copied (git must be findable; a sane home).
      expect(env.PATH).toBe(process.env.PATH);
      expect(env.HOME).toBe(process.env.HOME);
    } finally {
      for (const k of keys) {
        if (saved[k] === undefined) delete process.env[k];
        else process.env[k] = saved[k];
      }
    }
  });
});

// review P3 (FIX 8) — the "lstat-valid `.git` kind" predicate is shared across the
// 3 `reportAgentReadinessSelfStop({ gitValid })` emit sites; assert its truth table.
describe("isLstatValidKind (#5733 FIX 8 — shared lstat-valid kind predicate)", () => {
  it("true for the two lstat-valid kinds (dir-valid, file-pointer)", () => {
    expect(isLstatValidKind("dir-valid")).toBe(true);
    expect(isLstatValidKind("file-pointer")).toBe(true);
  });
  it("false for the non-lstat-valid kinds (absent, dir-invalid, other)", () => {
    expect(isLstatValidKind("absent")).toBe(false);
    expect(isLstatValidKind("dir-invalid")).toBe(false);
    expect(isLstatValidKind("other")).toBe(false);
  });
});

describe("hostGitRevParseOutcome (#5733 AC1) — real git integration", () => {
  let dir: string;
  beforeEach(async () => {
    dir = await mkdtemp(join(tmpdir(), "agentready-rp-"));
  });
  afterEach(async () => {
    await rm(dir, { recursive: true, force: true });
  });

  it('a healthy clone → "worktree"', async () => {
    const ws = join(dir, "healthy");
    await mkdir(ws, { recursive: true });
    await execFileAsync("git", ["-C", ws, "init", "-q"]);
    expect(await hostGitRevParseOutcome(ws)).toBe("worktree");
  });

  it('a `dir-valid` `.git` (HEAD+objects present) git cannot resolve → "not-a-worktree"', async () => {
    // The exact corrupt-`dir-valid` shape: lstat sees HEAD+objects (dir-valid),
    // but with no `refs`/config git rev-parse exits 128 "not a git repository".
    const ws = join(dir, "corrupt");
    await mkdir(join(ws, ".git", "objects"), { recursive: true });
    await writeFile(join(ws, ".git", "HEAD"), "ref: refs/heads/main\n");
    expect(await hostGitRevParseOutcome(ws)).toBe("not-a-worktree");
  });

  it("the ceiling blocks ascension into a REAL parent repo (no false worktree)", async () => {
    // Parent is a real git repo; the child has only a corrupt `.git`. Without the
    // ceiling, git would ascend and falsely report the child a work tree.
    const parent = join(dir, "parent");
    await mkdir(parent, { recursive: true });
    await execFileAsync("git", ["-C", parent, "init", "-q"]);
    const child = join(parent, "child");
    await mkdir(join(child, ".git", "objects"), { recursive: true });
    await writeFile(join(child, ".git", "HEAD"), "ref: refs/heads/main\n");
    expect(await hostGitRevParseOutcome(child)).toBe("not-a-worktree");
  });

  it('a spawn failure (ENOENT) → "inconclusive" (never a confirmed strand)', async () => {
    const ws = join(dir, "ws-enoent");
    await mkdir(ws, { recursive: true });
    const failing: GitRevParseRunner = () => {
      const e = new Error("spawn git ENOENT") as NodeJS.ErrnoException;
      e.code = "ENOENT";
      return Promise.reject(e);
    };
    expect(await hostGitRevParseOutcome(ws, failing)).toBe("inconclusive");
  });

  it('a timeout (killed) → "inconclusive"', async () => {
    const ws = join(dir, "ws-timeout");
    await mkdir(ws, { recursive: true });
    const timing: GitRevParseRunner = () => {
      const e = new Error("timed out") as NodeJS.ErrnoException & {
        killed: boolean;
        signal: NodeJS.Signals;
      };
      e.killed = true;
      e.signal = "SIGKILL";
      return Promise.reject(e);
    };
    expect(await hostGitRevParseOutcome(ws, timing)).toBe("inconclusive");
  });
});

describe("evaluateAgentReadiness (#5733 AC3/AC4) — shared gate", () => {
  let dir: string;
  beforeEach(async () => {
    dir = await mkdtemp(join(tmpdir(), "agentready-eval-"));
    vi.clearAllMocks();
  });
  afterEach(async () => {
    await rm(dir, { recursive: true, force: true });
  });

  async function dirValidWs(name: string): Promise<string> {
    const p = join(dir, name);
    await mkdir(join(p, ".git", "objects"), { recursive: true });
    await writeFile(join(p, ".git", "HEAD"), "ref: refs/heads/main\n");
    return p;
  }

  const baseCtx = {
    userId: "user-1",
    activeWorkspaceId: "754ee124",
    connected: true,
    dbReady: true,
  };
  const probeOf =
    (...outcomes: GitRevParseOutcome[]): ((p: string) => Promise<GitRevParseOutcome>) => {
      let i = 0;
      return () => Promise.resolve(outcomes[Math.min(i++, outcomes.length - 1)]);
    };

  it('dir-valid + "worktree" → ready, no emit', async () => {
    const ws = await dirValidWs("ok");
    expect(await evaluateAgentReadiness(ws, baseCtx, probeOf("worktree"))).toBe(
      "ready",
    );
    expect(mockSelfStop).not.toHaveBeenCalled();
    expect(mockInconclusive).not.toHaveBeenCalled();
  });

  it('dir-valid + "not-a-worktree" → block + self-stop (gitValid=true, gitRevParseValid=false)', async () => {
    const ws = await dirValidWs("strand");
    expect(
      await evaluateAgentReadiness(ws, baseCtx, probeOf("not-a-worktree")),
    ).toBe("block");
    expect(mockSelfStop).toHaveBeenCalledTimes(1);
    expect(mockSelfStop).toHaveBeenCalledWith(
      expect.objectContaining({
        userId: "user-1",
        activeWorkspaceId: "754ee124",
        gitValid: true,
        gitRevParseValid: false,
        gitKind: "dir-valid",
        source: "host-pre-heal",
      }),
    );
    expect(mockInconclusive).not.toHaveBeenCalled();
  });

  it('dir-valid + inconclusive twice → ready (FAIL-OPEN) + breadcrumb, NOT the self-stop', async () => {
    const ws = await dirValidWs("blip");
    const probe = vi.fn(probeOf("inconclusive", "inconclusive"));
    expect(await evaluateAgentReadiness(ws, baseCtx, probe)).toBe("ready");
    expect(probe).toHaveBeenCalledTimes(2); // re-probed once
    expect(mockInconclusive).toHaveBeenCalledTimes(1);
    expect(mockSelfStop).not.toHaveBeenCalled();
  });

  it("inconclusive then worktree on re-probe → ready, no emit", async () => {
    const ws = await dirValidWs("recover");
    const probe = vi.fn(probeOf("inconclusive", "worktree"));
    expect(await evaluateAgentReadiness(ws, baseCtx, probe)).toBe("ready");
    expect(probe).toHaveBeenCalledTimes(2);
    expect(mockInconclusive).not.toHaveBeenCalled();
    expect(mockSelfStop).not.toHaveBeenCalled();
  });

  it("not connected → ready WITHOUT probing (repo-less keeps cheap routing)", async () => {
    const ws = await dirValidWs("repoless");
    const probe = vi.fn(probeOf("not-a-worktree"));
    expect(
      await evaluateAgentReadiness(ws, { ...baseCtx, connected: false }, probe),
    ).toBe("ready");
    expect(probe).not.toHaveBeenCalled();
    expect(mockSelfStop).not.toHaveBeenCalled();
  });

  it("not DB-ready → ready WITHOUT probing (honest RepoNotReadyError owns that)", async () => {
    const ws = await dirValidWs("notready");
    const probe = vi.fn(probeOf("not-a-worktree"));
    expect(
      await evaluateAgentReadiness(ws, { ...baseCtx, dbReady: false }, probe),
    ).toBe("ready");
    expect(probe).not.toHaveBeenCalled();
  });

  it("a non-dir-valid shape (absent `.git`) → ready WITHOUT the host confirm (lstat verdict owns it)", async () => {
    const ws = join(dir, "absent");
    await mkdir(ws, { recursive: true });
    const probe = vi.fn(probeOf("not-a-worktree"));
    expect(await evaluateAgentReadiness(ws, baseCtx, probe)).toBe("ready");
    expect(probe).not.toHaveBeenCalled();
  });
});
