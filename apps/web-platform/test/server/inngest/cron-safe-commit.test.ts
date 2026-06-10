// #5091 — safeCommitAndPr unit tests against a scratch git fixture repo.
//
// The helper is the deterministic replacement for the prompt-level
// MANDATORY FINAL STEP commit blocks (destructive PR #5026: blanket add
// staged 654 structural deletions). These tests drive REAL git in a tmpdir
// (local bare remote for push) with a stubbed octokit, proving the plan's
// AC4 invariants: structural-exclusion filtering, the deletion guard,
// porcelain -z rename parsing, deterministic replay-stable commit SHAs,
// 422-tolerant PR create, refname validity, and replay-resume.

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { execFile } from "node:child_process";
import { mkdtemp, mkdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, dirname } from "node:path";
import { promisify } from "node:util";

const execFileP = promisify(execFile);

const { reportSilentFallbackMock, warnSilentFallbackMock } = vi.hoisted(() => ({
  reportSilentFallbackMock: vi.fn(),
  warnSilentFallbackMock: vi.fn(),
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: reportSilentFallbackMock,
  warnSilentFallback: warnSilentFallbackMock,
}));

import {
  DEFAULT_MAX_DELETIONS,
  safeCommitAndPr,
  type SafeCommitResult,
} from "@/server/inngest/functions/_cron-safe-commit";

// ---------------------------------------------------------------------------
// Fixture harness — real git repo + local bare "origin"
// ---------------------------------------------------------------------------

// Deterministic identity/date for SEED commits so two fixtures with identical
// content produce identical parent SHAs (needed for the double-run SHA test).
const SEED_ENV = {
  GIT_AUTHOR_NAME: "fixture",
  GIT_AUTHOR_EMAIL: "fixture@example.test",
  GIT_COMMITTER_NAME: "fixture",
  GIT_COMMITTER_EMAIL: "fixture@example.test",
  GIT_AUTHOR_DATE: "2026-06-01T00:00:00Z",
  GIT_COMMITTER_DATE: "2026-06-01T00:00:00Z",
};

const RUN_STARTED_AT = "2026-06-10T11:00:03.123Z";

async function tgit(cwd: string, ...args: string[]): Promise<string> {
  const { stdout } = await execFileP("git", args, {
    cwd,
    env: { ...process.env, ...SEED_ENV },
    maxBuffer: 10 * 1024 * 1024,
  });
  return stdout.trim();
}

interface Fixture {
  repo: string;
  remote: string;
  root: string;
}

const fixtures: Fixture[] = [];

// ~15 tracked seed files: 10 under the allowed marketing prefix, 4 under the
// structurally-excluded .claude/ prefix, 1 plugin doc.
const SEED_FILES: Record<string, string> = {
  ".claude/settings.json": '{"permissions":{}}\n',
  ".claude/extra-1.json": "{}\n",
  ".claude/extra-2.json": "{}\n",
  ".claude/extra-3.json": "{}\n",
  "plugins/soleur/docs/page.md": "# doc\n",
  ...Object.fromEntries(
    Array.from({ length: 10 }, (_, i) => [
      `knowledge-base/marketing/file-${i}.md`,
      `seed content ${i}\n`,
    ]),
  ),
};

async function makeFixture(): Promise<Fixture> {
  const root = await mkdtemp(join(tmpdir(), "safe-commit-fixture-"));
  const remote = join(root, "remote.git");
  const repo = join(root, "repo");
  await execFileP("git", ["init", "--bare", remote]);
  await execFileP("git", ["init", "-b", "main", repo]);
  for (const [rel, content] of Object.entries(SEED_FILES)) {
    await mkdir(dirname(join(repo, rel)), { recursive: true });
    await writeFile(join(repo, rel), content, "utf-8");
  }
  await tgit(repo, "add", "--", ...Object.keys(SEED_FILES));
  await tgit(repo, "commit", "-m", "seed");
  await tgit(repo, "remote", "add", "origin", remote);
  await tgit(repo, "push", "-u", "origin", "main");
  const fixture = { repo, remote, root };
  fixtures.push(fixture);
  return fixture;
}

afterEach(async () => {
  vi.clearAllMocks();
  while (fixtures.length) {
    const f = fixtures.pop()!;
    await rm(f.root, { recursive: true, force: true });
  }
});

// ---------------------------------------------------------------------------
// Octokit stub
// ---------------------------------------------------------------------------

type OctokitStub = {
  request: ReturnType<typeof vi.fn>;
  graphql: ReturnType<typeof vi.fn>;
};

function makeOctokitStub(overrides?: {
  prCreate?: (params: Record<string, unknown>) => Promise<unknown>;
  prList?: () => Promise<unknown>;
  graphql?: () => Promise<unknown>;
}): OctokitStub {
  const request = vi.fn(async (route: string, params: Record<string, unknown>) => {
    if (route === "POST /repos/{owner}/{repo}/pulls") {
      if (overrides?.prCreate) return overrides.prCreate(params);
      return { data: { number: 42, node_id: "PR_node_42" } };
    }
    if (route === "GET /repos/{owner}/{repo}/pulls") {
      if (overrides?.prList) return overrides.prList();
      return { data: [] };
    }
    if (route === "GET /repos/{owner}/{repo}/issues") {
      return { data: [] };
    }
    return { data: {} };
  });
  const graphql = vi.fn(async () => {
    if (overrides?.graphql) return overrides.graphql();
    return {};
  });
  return { request, graphql };
}

function baseConfig(fixture: Fixture, octokit: OctokitStub) {
  return {
    spawnCwd: fixture.repo,
    installationToken: "synthetic-token",
    cronName: "cron-test-fixture",
    commitMessage: "fix(test): fixture commit",
    prTitle: "fix(test): fixture PR",
    prBody: "Automated fixture PR body.",
    allowedPaths: ["knowledge-base/marketing/"] as const,
    runStartedAt: RUN_STARTED_AT,
    scheduledIssueLabel: "scheduled-test-fixture",
    octokit: octokit as never,
  };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("safeCommitAndPr — constants", () => {
  it("DEFAULT_MAX_DELETIONS is 10 (divergence from issue-suggested 50 recorded in plan)", () => {
    expect(DEFAULT_MAX_DELETIONS).toBe(10);
  });
});

describe("safeCommitAndPr — structural exclusion + allowlist (AC4a)", () => {
  it("commits ONLY allowed-path changes; .claude/ deletions are structurally excluded with zero guarded deletions", async () => {
    const f = await makeFixture();
    // Contamination class: every tracked .claude/ file deleted (4 files) —
    // analogous to the settings-overlay/symlink class; must never stage.
    for (const rel of Object.keys(SEED_FILES).filter((p) => p.startsWith(".claude/"))) {
      await rm(join(f.repo, rel));
    }
    // 2 legit changes inside the allowlist.
    await writeFile(join(f.repo, "knowledge-base/marketing/file-0.md"), "updated 0\n");
    await writeFile(join(f.repo, "knowledge-base/marketing/new-article.md"), "new\n");

    const octokit = makeOctokitStub();
    const result = await safeCommitAndPr(baseConfig(f, octokit));

    expect(result.status).toBe("committed");
    const shown = await tgit(f.repo, "show", "--name-only", "--format=", "HEAD");
    const files = shown.split("\n").filter(Boolean).sort();
    expect(files).toEqual([
      "knowledge-base/marketing/file-0.md",
      "knowledge-base/marketing/new-article.md",
    ]);
    // The deletion guard must NOT have fired for structurally excluded paths.
    const guardCalls = reportSilentFallbackMock.mock.calls.filter(
      (c) => c[1]?.op === "safe-commit-deletion-guard",
    );
    expect(guardCalls).toHaveLength(0);
  });

  it("warns to Sentry when non-structural paths are dropped by the allowlist filter", async () => {
    const f = await makeFixture();
    await writeFile(join(f.repo, "knowledge-base/marketing/file-1.md"), "updated\n");
    // Outside allowlist AND not structural — must be dropped LOUDLY.
    await writeFile(join(f.repo, "plugins/soleur/docs/page.md"), "# changed\n");

    const octokit = makeOctokitStub();
    const result = await safeCommitAndPr(baseConfig(f, octokit));

    expect(result.status).toBe("committed");
    const dropCalls = reportSilentFallbackMock.mock.calls.filter(
      (c) => c[1]?.op === "safe-commit-paths-dropped",
    );
    expect(dropCalls).toHaveLength(1);
  });

  it("returns no-changes when only structurally-excluded paths changed", async () => {
    const f = await makeFixture();
    await writeFile(join(f.repo, ".claude/settings.json"), '{"overlay":true}\n');

    const octokit = makeOctokitStub();
    const result = await safeCommitAndPr(baseConfig(f, octokit));

    expect(result.status).toBe("no-changes");
    expect(octokit.request).not.toHaveBeenCalledWith(
      "POST /repos/{owner}/{repo}/pulls",
      expect.anything(),
    );
  });
});

describe("safeCommitAndPr — deletion guard (AC4b)", () => {
  it("aborts with failed/deletion-guard when >DEFAULT_MAX_DELETIONS deletions land inside allowedPaths", async () => {
    const f = await makeFixture();
    // 10 seed marketing files + need 11 deletions: add one more tracked file first.
    await writeFile(join(f.repo, "knowledge-base/marketing/file-10.md"), "extra\n");
    await tgit(f.repo, "add", "--", "knowledge-base/marketing/file-10.md");
    await tgit(f.repo, "commit", "-m", "extra tracked file");
    for (let i = 0; i <= 10; i++) {
      await rm(join(f.repo, `knowledge-base/marketing/file-${i}.md`));
    }

    const octokit = makeOctokitStub();
    const result = await safeCommitAndPr(baseConfig(f, octokit));

    expect(result.status).toBe("failed");
    if (result.status === "failed") {
      expect(result.stage).toBe("deletion-guard");
    }
    // No branch was pushed to the remote.
    const remoteBranches = await tgit(f.repo, "ls-remote", "--heads", "origin");
    expect(remoteBranches).not.toContain("ci/");
    // Loud Sentry signal with the count.
    const guardCalls = reportSilentFallbackMock.mock.calls.filter(
      (c) => c[1]?.op === "safe-commit-deletion-guard",
    );
    expect(guardCalls).toHaveLength(1);
    expect(guardCalls[0][1].extra.deletionCount).toBe(11);
    expect(guardCalls[0][1].extra.max).toBe(DEFAULT_MAX_DELETIONS);
  });
});

describe("safeCommitAndPr — porcelain -z rename parsing (AC4c)", () => {
  it("staged rename entries (two NUL fields, dest first) do not misalign subsequent entries", async () => {
    const f = await makeFixture();
    // Staged rename: R entry carries "dest\0src\0" under -z.
    await tgit(f.repo, "mv", "knowledge-base/marketing/file-2.md", "knowledge-base/marketing/file-2-renamed.md");
    // A worktree modification that scans AFTER the rename entry — if the
    // parser misaligns on the rename's second field, this path is garbled.
    await writeFile(join(f.repo, "knowledge-base/marketing/file-9.md"), "post-rename change\n");

    const octokit = makeOctokitStub();
    const result = await safeCommitAndPr(baseConfig(f, octokit));

    expect(result.status).toBe("committed");
    const shown = await tgit(f.repo, "show", "--name-status", "--format=", "HEAD");
    expect(shown).toContain("file-2-renamed.md");
    expect(shown).toContain("file-9.md");
  });
});

describe("safeCommitAndPr — deterministic commit identity (AC4d)", () => {
  it("pins bot identity + GIT_*_DATE to runStartedAt; double run on identical fixtures yields identical SHAs", async () => {
    const fa = await makeFixture();
    const fb = await makeFixture();
    for (const f of [fa, fb]) {
      await writeFile(join(f.repo, "knowledge-base/marketing/file-3.md"), "identical change\n");
    }

    const ra = await safeCommitAndPr(baseConfig(fa, makeOctokitStub()));
    const rb = await safeCommitAndPr(baseConfig(fb, makeOctokitStub()));
    expect(ra.status).toBe("committed");
    expect(rb.status).toBe("committed");

    const [shaA, shaB] = await Promise.all([
      tgit(fa.repo, "rev-parse", "HEAD"),
      tgit(fb.repo, "rev-parse", "HEAD"),
    ]);
    expect(shaA).toBe(shaB);

    const meta = await tgit(fa.repo, "log", "-1", "--format=%an|%ae|%at|%ct");
    const [name, email, authorEpoch, committerEpoch] = meta.split("|");
    expect(name).toBe("github-actions[bot]");
    expect(email).toBe("41898282+github-actions[bot]@users.noreply.github.com");
    const expectedEpoch = String(Math.floor(new Date(RUN_STARTED_AT).getTime() / 1000));
    expect(authorEpoch).toBe(expectedEpoch);
    expect(committerEpoch).toBe(expectedEpoch);
  });
});

describe("safeCommitAndPr — branch refname (AC4f)", () => {
  it("derives a refname-valid ci/ branch from cronName + runStartedAt (no colon, no dot)", async () => {
    const f = await makeFixture();
    await writeFile(join(f.repo, "knowledge-base/marketing/file-4.md"), "change\n");

    const result = await safeCommitAndPr(baseConfig(f, makeOctokitStub()));
    expect(result.status).toBe("committed");
    if (result.status === "committed") {
      expect(result.branch).toBe("ci/test-fixture-2026-06-10-110003");
      expect(result.branch).not.toMatch(/[:.]/);
    }
  });
});

describe("safeCommitAndPr — PR create + auto-merge (AC4e)", () => {
  it("treats 422 'A pull request already exists' as success and recovers the PR number", async () => {
    const f = await makeFixture();
    await writeFile(join(f.repo, "knowledge-base/marketing/file-5.md"), "change\n");

    const octokit = makeOctokitStub({
      prCreate: async () => {
        const err = new Error(
          "Validation Failed: A pull request already exists for jikig-ai:ci/test-fixture-2026-06-10-110003.",
        ) as Error & { status: number };
        err.status = 422;
        throw err;
      },
      prList: async () => ({ data: [{ number: 7, node_id: "PR_node_7" }] }),
    });

    const result = await safeCommitAndPr(baseConfig(f, octokit));
    expect(result.status).toBe("committed");
    if (result.status === "committed") {
      expect(result.prNumber).toBe(7);
    }
    // Auto-merge fired against the recovered node id.
    expect(octokit.graphql).toHaveBeenCalledWith(
      expect.stringContaining("enablePullRequestAutoMerge"),
      expect.objectContaining({ pullRequestId: "PR_node_7" }),
    );
  });

  it("falls back to direct merge when auto-merge reports clean status", async () => {
    const f = await makeFixture();
    await writeFile(join(f.repo, "knowledge-base/marketing/file-6.md"), "change\n");

    const octokit = makeOctokitStub({
      graphql: async () => {
        throw new Error('["Pull request is in clean status"]');
      },
    });

    const result = await safeCommitAndPr(baseConfig(f, octokit));
    expect(result.status).toBe("committed");
    expect(octokit.request).toHaveBeenCalledWith(
      "PUT /repos/{owner}/{repo}/pulls/{pull_number}/merge",
      expect.objectContaining({ pull_number: 42 }),
    );
  });

  it("returns failed/pr-create (never throws) on a hard PR-create error", async () => {
    const f = await makeFixture();
    await writeFile(join(f.repo, "knowledge-base/marketing/file-7.md"), "change\n");

    const octokit = makeOctokitStub({
      prCreate: async () => {
        const err = new Error("Server Error") as Error & { status: number };
        err.status = 500;
        throw err;
      },
    });

    const result = await safeCommitAndPr(baseConfig(f, octokit));
    expect(result.status).toBe("failed");
    if (result.status === "failed") {
      expect(result.stage).toBe("pr-create");
    }
    const failCalls = reportSilentFallbackMock.mock.calls.filter(
      (c) => c[1]?.op === "safe-commit-failed",
    );
    expect(failCalls.length).toBeGreaterThanOrEqual(1);
  });
});

describe("safeCommitAndPr — replay resume (AC4g)", () => {
  it("a second invocation after success re-pushes the SAME sha and recovers the PR instead of reporting no-changes", async () => {
    const f = await makeFixture();
    await writeFile(join(f.repo, "knowledge-base/marketing/file-8.md"), "change\n");

    const first = await safeCommitAndPr(baseConfig(f, makeOctokitStub()));
    expect(first.status).toBe("committed");
    const shaAfterFirst = await tgit(f.repo, "rev-parse", "HEAD");

    // Replay: workspace persists (memoized setup), HEAD now on the ci/ branch.
    const octokit = makeOctokitStub({
      prCreate: async () => {
        const err = new Error("A pull request already exists") as Error & { status: number };
        err.status = 422;
        throw err;
      },
      prList: async () => ({ data: [{ number: 42, node_id: "PR_node_42" }] }),
    });
    const second = await safeCommitAndPr(baseConfig(f, octokit));

    expect(second.status).toBe("committed");
    if (second.status === "committed") {
      expect(second.prNumber).toBe(42);
    }
    const shaAfterSecond = await tgit(f.repo, "rev-parse", "HEAD");
    expect(shaAfterSecond).toBe(shaAfterFirst);
    // Exactly one commit beyond origin/main — no duplicate commit was created.
    const count = await tgit(f.repo, "rev-list", "origin/main..HEAD", "--count");
    expect(count).toBe("1");
  });
});

describe("safeCommitAndPr — workspace lost (non-throwing)", () => {
  it("returns failed/workspace-lost when spawnCwd no longer exists", async () => {
    const octokit = makeOctokitStub();
    const result: SafeCommitResult = await safeCommitAndPr({
      ...baseConfig({ repo: "/tmp/definitely-gone-safe-commit", remote: "", root: "" }, octokit),
    });
    expect(result.status).toBe("failed");
    if (result.status === "failed") {
      expect(result.stage).toBe("workspace-lost");
    }
  });
});
