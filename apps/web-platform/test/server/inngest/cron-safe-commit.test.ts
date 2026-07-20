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

// #6714 — marker 1 (SOLEUR_CRON_PERSIST_RESULT) is emitted on ALL THREE terminal
// paths. Spying here lets each site be asserted at its OWN site (AC25) rather
// than by a repo-wide grep, which a comment would satisfy.
const { persistResultMock } = vi.hoisted(() => ({ persistResultMock: vi.fn() }));

vi.mock("@/server/cron-liveness-marker", () => ({
  emitCronPersistResult: persistResultMock,
  emitCronPersistSkipped: vi.fn(),
  emitCommunityDigestFile: vi.fn(),
  emitCronTier2Deferred: vi.fn(),
  emitCronDedupSkip: vi.fn(),
}));

import {
  DEFAULT_MAX_DELETIONS,
  SYNTHETIC_CHECK_NAMES,
  enableAutoMergeSquash,
  parsePorcelainZ,
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
  // Isolate from host git config (signing, hooks, templates) so fixture
  // commit SHAs are deterministic on any machine (review P2b).
  GIT_CONFIG_GLOBAL: "/dev/null",
  GIT_CONFIG_SYSTEM: "/dev/null",
  GIT_CONFIG_NOSYSTEM: "1",
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
  // Register for cleanup IMMEDIATELY so a mid-creation throw cannot leak
  // the tmpdir (review P3).
  const fixture: Fixture = { repo: join(root, "repo"), remote: join(root, "remote.git"), root };
  fixtures.push(fixture);
  const remote = fixture.remote;
  const repo = fixture.repo;
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
  /** #5111 mergeMode "direct": override the PUT …/merge handler (e.g. throw). */
  merge?: (params: Record<string, unknown>) => Promise<unknown>;
  /** When set, GET issues returns one open scheduled issue with this number. */
  scheduledIssueNumber?: number;
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
    if (route === "PUT /repos/{owner}/{repo}/pulls/{pull_number}/merge") {
      if (overrides?.merge) return overrides.merge(params);
      return { data: {} };
    }
    if (route === "GET /repos/{owner}/{repo}/issues") {
      return {
        data: overrides?.scheduledIssueNumber
          ? [{ number: overrides.scheduledIssueNumber }]
          : [],
      };
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
    // Anti-vacuity (review P2a): structural exclusion is SILENT by design —
    // if it were allowlist-driven instead, these .claude/ deletions would
    // fire safe-commit-paths-dropped and this assertion turns red.
    const dropCalls = reportSilentFallbackMock.mock.calls.filter(
      (c) => c[1]?.op === "safe-commit-paths-dropped",
    );
    expect(dropCalls).toHaveLength(0);
    // #6714 R21/AC15 — `paths` is populated FROM the allowlist-matched scan, so
    // it must equal what actually entered the commit. Cross-checked against
    // `git show --name-only` (above) rather than a hand-written literal: that is
    // what makes this behavioral and not a restatement of the test's own input.
    if (result.status === "committed") {
      expect(result.paths?.slice().sort()).toEqual(files);
      expect(result.resumed).toBeUndefined(); // a real scan, not a resume
    }
    // marker 1, site 3 — the committed arm.
    expect(persistResultMock).toHaveBeenCalledWith(
      expect.objectContaining({ status: "committed", files: 2, stage: null }),
    );
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
    // Anti-vacuity: the .claude/ change is structurally excluded, not
    // allowlist-dropped — no paths-dropped warning may fire.
    const dropCalls = reportSilentFallbackMock.mock.calls.filter(
      (c) => c[1]?.op === "safe-commit-paths-dropped",
    );
    expect(dropCalls).toHaveLength(0);
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

    const octokit = makeOctokitStub({ scheduledIssueNumber: 9 });
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
    // Operator-visibility contract: the guard abort comments on the run's
    // scheduled issue (review: this was previously untested).
    expect(octokit.request).toHaveBeenCalledWith(
      "POST /repos/{owner}/{repo}/issues/{issue_number}/comments",
      expect.objectContaining({
        issue_number: 9,
        body: expect.stringContaining("PR withheld: deletion guard"),
      }),
    );
  });
});

describe("safeCommitAndPr — porcelain -z parsing (AC4c, unit)", () => {
  it("rename entries (two NUL fields, dest first) do not misalign subsequent entries", () => {
    const raw = [
      "R  knowledge-base/marketing/file-2-renamed.md",
      "knowledge-base/marketing/file-2.md",
      " M knowledge-base/marketing/file-9.md",
      "?? a.b", // 3-char path
      "UU knowledge-base/marketing/conflict.md",
      "",
    ].join("\0");
    const entries = parsePorcelainZ(raw);
    expect(entries.map((e) => e.path)).toEqual([
      "knowledge-base/marketing/file-2-renamed.md",
      "knowledge-base/marketing/file-9.md",
      "a.b",
      "knowledge-base/marketing/conflict.md",
    ]);
    expect(entries[0]).toMatchObject({ x: "R", y: " " });
    expect(entries[3]).toMatchObject({ x: "U", y: "U" });
  });

  it("empty status output parses to zero entries", () => {
    expect(parsePorcelainZ("")).toEqual([]);
  });

  it("a pre-staged index (e.g. git mv) is rejected loudly — the commit would otherwise carry the whole index around the allowlist", async () => {
    const f = await makeFixture();
    await tgit(f.repo, "mv", "knowledge-base/marketing/file-2.md", "knowledge-base/marketing/file-2-renamed.md");

    const octokit = makeOctokitStub();
    const result = await safeCommitAndPr(baseConfig(f, octokit));

    expect(result.status).toBe("failed");
    if (result.status === "failed") {
      expect(result.stage).toBe("dirty-index");
    }
    // Nothing was pushed.
    const remoteBranches = await tgit(f.repo, "ls-remote", "--heads", "origin");
    expect(remoteBranches).not.toContain("ci/");
  });
});

describe("enableAutoMergeSquash — idempotent replay tolerance", () => {
  it("treats 'already enabled' GraphQL errors as enabled (alreadyEnabled flagged)", async () => {
    const graphql = vi.fn(async () => {
      throw new Error("Pull request Auto merge is already enabled");
    });
    const result = await enableAutoMergeSquash({ graphql } as never, "PR_node");
    expect(result).toMatchObject({ enabled: true, alreadyEnabled: true, cleanStatus: false });
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

    // #6714 R21/AC15 — the two arms of the `paths` contract, from ONE run pair.
    if (first.status === "committed") {
      expect(first.paths).toContain("knowledge-base/marketing/file-8.md");
      expect(first.resumed).toBeUndefined();
    }
    if (second.status === "committed") {
      // The replay branch skips the allowlist scan entirely, so there is nothing
      // to report. `resumed` is what licenses a liveness check to stay GREEN on
      // an UNDETERMINED `paths` — the artifact above demonstrably landed (same
      // sha, one commit), so reading undefined as "nothing committed" would
      // false-RED a healthy run.
      expect(second.resumed).toBe(true);
      expect(second.paths).toBeUndefined();
    }
  });
});

describe("safeCommitAndPr — persist-result marker sites (#6714 AC25)", () => {
  it("emits the no-changes arm at its own site when nothing is committable", async () => {
    const f = await makeFixture();
    // No writes at all — the working tree is clean, so the scan finds nothing.
    const result = await safeCommitAndPr(baseConfig(f, makeOctokitStub()));

    expect(result.status).toBe("no-changes");
    // marker 1, site 2. `files: 0` and `pr: null` are what distinguish this from
    // a healthy commit in Better Stack — before the marker, "no-changes" and
    // "committed" were indistinguishable on every operator-reachable surface.
    expect(persistResultMock).toHaveBeenCalledWith({
      cron: "cron-test-fixture",
      status: "no-changes",
      files: 0,
      pr: null,
      stage: null,
    });
  });

  it("emits the failed arm at its own site, carrying the failing stage", async () => {
    const f = await makeFixture();
    await writeFile(join(f.repo, "knowledge-base/marketing/file-9.md"), "change\n");
    const octokit = makeOctokitStub({
      prCreate: async () => {
        throw new Error("boom");
      },
    });

    const result = await safeCommitAndPr(baseConfig(f, octokit));

    expect(result.status).toBe("failed");
    // marker 1, site 1. `stage` is the field that makes a failure triageable
    // without Inngest step history (which ADR-030 binds to 127.0.0.1:8288).
    const failedCalls = persistResultMock.mock.calls.filter(
      (c) => c[0]?.status === "failed",
    );
    expect(failedCalls).toHaveLength(1);
    expect(failedCalls[0][0]).toMatchObject({
      status: "failed",
      files: 0,
      pr: null,
      stage: "pr-create",
    });
  });
});

describe("safeCommitAndPr — crash-window resume (review P2: checkout-B before commit)", () => {
  it("falls through to the scan when HEAD is on the ci/ branch with NO commit ahead of origin/main", async () => {
    const f = await makeFixture();
    // Simulate a prior attempt that crashed after `checkout -B` but before
    // `commit`: HEAD on the target branch at main's tip, work still dirty.
    await tgit(f.repo, "checkout", "-B", "ci/test-fixture-2026-06-10-110003");
    await writeFile(join(f.repo, "knowledge-base/marketing/file-1.md"), "crash-window change\n");

    const result = await safeCommitAndPr(baseConfig(f, makeOctokitStub()));

    expect(result.status).toBe("committed");
    // The work was actually committed (not skipped by a naive branch-name
    // resume), with exactly one commit ahead of origin/main.
    const count = await tgit(f.repo, "rev-list", "origin/main..HEAD", "--count");
    expect(count).toBe("1");
    const shown = await tgit(f.repo, "show", "--name-only", "--format=", "HEAD");
    expect(shown).toContain("knowledge-base/marketing/file-1.md");
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

// ---------------------------------------------------------------------------
// #5111 option surface — branchName/commitBody/prTitle/prBody/prDraft/prLabels/
// syntheticChecks/mergeMode. Defaults-unchanged regression: every pre-#5111
// describe above runs config WITHOUT these options and must stay green.
// ---------------------------------------------------------------------------

describe("safeCommitAndPr — #5111 option surface", () => {
  it("exports the 7 canonical synthetic CI check names (consolidated from the 5 per-cron copies)", () => {
    expect([...SYNTHETIC_CHECK_NAMES]).toEqual([
      "test",
      "dependency-review",
      "e2e",
      "skill-security-scan PR gate",
      "enforce",
      "cla-check",
      "cla-evidence",
    ]);
  });

  it("honors a branchName override (result, local HEAD, remote ref)", async () => {
    const f = await makeFixture();
    await writeFile(join(f.repo, "knowledge-base/marketing/file-0.md"), "cluster change\n");

    const result = await safeCommitAndPr({
      ...baseConfig(f, makeOctokitStub()),
      branchName: "self-healing/auto-abc12345-2026-06-10",
    });

    expect(result.status).toBe("committed");
    if (result.status === "committed") {
      expect(result.branch).toBe("self-healing/auto-abc12345-2026-06-10");
    }
    const head = await tgit(f.repo, "rev-parse", "--abbrev-ref", "HEAD");
    expect(head).toBe("self-healing/auto-abc12345-2026-06-10");
    const remoteBranches = await tgit(f.repo, "ls-remote", "--heads", "origin");
    expect(remoteBranches).toContain("self-healing/auto-abc12345-2026-06-10");
  });

  it("rejects a non-refname-safe branchName at stage checkout before any git mutation", async () => {
    const f = await makeFixture();
    await writeFile(join(f.repo, "knowledge-base/marketing/file-0.md"), "change\n");

    const result = await safeCommitAndPr({
      ...baseConfig(f, makeOctokitStub()),
      branchName: "bad:branch.name",
    });

    expect(result.status).toBe("failed");
    if (result.status === "failed") {
      expect(result.stage).toBe("checkout");
    }
    // Nothing was committed or pushed.
    const head = await tgit(f.repo, "rev-parse", "--abbrev-ref", "HEAD");
    expect(head).toBe("main");
    const remoteBranches = await tgit(f.repo, "ls-remote", "--heads", "origin");
    expect(remoteBranches).not.toContain("bad");
  });

  it("commitBody lands as the commit message's second paragraph (compound-promote trailers)", async () => {
    const f = await makeFixture();
    await writeFile(join(f.repo, "knowledge-base/marketing/file-1.md"), "change\n");

    const result = await safeCommitAndPr({
      ...baseConfig(f, makeOctokitStub()),
      commitBody: "Promotion-Source: cluster-abc\nPromotion-Cluster-Hash: abc12345",
    });

    expect(result.status).toBe("committed");
    const body = await tgit(f.repo, "log", "-1", "--format=%B");
    expect(body).toBe(
      "fix(test): fixture commit\n\nPromotion-Source: cluster-abc\nPromotion-Cluster-Hash: abc12345",
    );
  });

  it("prTitle/prBody/prDraft/prLabels pass through to PR create + labels endpoints", async () => {
    const f = await makeFixture();
    await writeFile(join(f.repo, "knowledge-base/marketing/file-2.md"), "change\n");

    const octokit = makeOctokitStub();
    const result = await safeCommitAndPr({
      ...baseConfig(f, makeOctokitStub()),
      octokit: octokit as never,
      prTitle: "self-healing(auto): promote cluster abc12345 2026-06-10",
      prBody: "Automated promotion proposal — human review required.",
      prDraft: true,
      prLabels: ["self-healing/auto"],
      mergeMode: "none",
    });

    expect(result.status).toBe("committed");
    expect(octokit.request).toHaveBeenCalledWith(
      "POST /repos/{owner}/{repo}/pulls",
      expect.objectContaining({
        title: "self-healing(auto): promote cluster abc12345 2026-06-10",
        body: "Automated promotion proposal — human review required.",
        draft: true,
      }),
    );
    expect(octokit.request).toHaveBeenCalledWith(
      "POST /repos/{owner}/{repo}/issues/{issue_number}/labels",
      expect.objectContaining({
        issue_number: 42,
        labels: ["self-healing/auto"],
      }),
    );
  });

  it("a prBody override still carries the dropped-path ⚠️ marker (loud-truncation invariant survives)", async () => {
    const f = await makeFixture();
    await writeFile(join(f.repo, "knowledge-base/marketing/file-3.md"), "change\n");
    // Outside allowlist, not structural — dropped loudly.
    await writeFile(join(f.repo, "plugins/soleur/docs/page.md"), "# changed\n");

    const octokit = makeOctokitStub();
    const result = await safeCommitAndPr({
      ...baseConfig(f, makeOctokitStub()),
      octokit: octokit as never,
      prBody: "Custom body stem.",
    });

    expect(result.status).toBe("committed");
    const prCall = octokit.request.mock.calls.find(
      (c) => c[0] === "POST /repos/{owner}/{repo}/pulls",
    );
    expect(prCall).toBeDefined();
    const body = (prCall![1] as { body: string }).body;
    expect(body).toContain("Custom body stem.");
    expect(body).toContain("⚠️");
    expect(body).toContain("plugins/soleur/docs/page.md");
  });

  it("syntheticChecks posts one completed/success check-run per name on the head SHA", async () => {
    const f = await makeFixture();
    await writeFile(join(f.repo, "knowledge-base/marketing/file-4.md"), "change\n");

    const octokit = makeOctokitStub();
    const result = await safeCommitAndPr({
      ...baseConfig(f, makeOctokitStub()),
      octokit: octokit as never,
      syntheticChecks: { names: SYNTHETIC_CHECK_NAMES, summary: "Snapshot only, no code changes" },
      mergeMode: "direct",
    });

    expect(result.status).toBe("committed");
    const headSha = await tgit(f.repo, "rev-parse", "HEAD");
    const checkCalls = octokit.request.mock.calls.filter(
      (c) => c[0] === "POST /repos/{owner}/{repo}/check-runs",
    );
    expect(checkCalls).toHaveLength(SYNTHETIC_CHECK_NAMES.length);
    for (const name of SYNTHETIC_CHECK_NAMES) {
      expect(octokit.request).toHaveBeenCalledWith(
        "POST /repos/{owner}/{repo}/check-runs",
        expect.objectContaining({
          name,
          head_sha: headSha,
          status: "completed",
          conclusion: "success",
          output: expect.objectContaining({ summary: "Snapshot only, no code changes" }),
        }),
      );
    }
  });

  it("mergeMode 'direct' merges via PUT without arming auto-merge", async () => {
    const f = await makeFixture();
    await writeFile(join(f.repo, "knowledge-base/marketing/file-5.md"), "change\n");

    const octokit = makeOctokitStub();
    const result = await safeCommitAndPr({
      ...baseConfig(f, makeOctokitStub()),
      octokit: octokit as never,
      mergeMode: "direct",
    });

    expect(result.status).toBe("committed");
    expect(octokit.request).toHaveBeenCalledWith(
      "PUT /repos/{owner}/{repo}/pulls/{pull_number}/merge",
      expect.objectContaining({ pull_number: 42, merge_method: "squash" }),
    );
    expect(octokit.graphql).not.toHaveBeenCalled();
  });

  it("mergeMode 'direct' falls back to arming auto-merge when the direct merge fails", async () => {
    const f = await makeFixture();
    await writeFile(join(f.repo, "knowledge-base/marketing/file-6.md"), "change\n");

    const octokit = makeOctokitStub({
      merge: async () => {
        throw new Error("Required status check is expected");
      },
    });
    const result = await safeCommitAndPr({
      ...baseConfig(f, makeOctokitStub()),
      octokit: octokit as never,
      mergeMode: "direct",
    });

    expect(result.status).toBe("committed");
    // Anti-vacuity: the direct PUT must have been ATTEMPTED first — an
    // option-ignoring helper (pre-#5111 auto mode) would arm auto-merge
    // without ever hitting the merge endpoint and still satisfy the
    // graphql assertion below.
    expect(octokit.request).toHaveBeenCalledWith(
      "PUT /repos/{owner}/{repo}/pulls/{pull_number}/merge",
      expect.objectContaining({ pull_number: 42 }),
    );
    expect(octokit.graphql).toHaveBeenCalledWith(
      expect.stringContaining("enablePullRequestAutoMerge"),
      expect.objectContaining({ pullRequestId: "PR_node_42" }),
    );
    // The fell-back state is Sentry-visible (armed auto-merge can silently
    // disarm on conflict — the #5138 watchdog class).
    const fellBack = reportSilentFallbackMock.mock.calls.filter(
      (c) => c[1]?.op === "safe-commit-direct-merge-fell-back",
    );
    expect(fellBack).toHaveLength(1);
  });

  it("mergeMode 'direct' returns failed/auto-merge when both direct merge and arming fail (PR stays open + loud)", async () => {
    const f = await makeFixture();
    await writeFile(join(f.repo, "knowledge-base/marketing/file-7.md"), "change\n");

    const octokit = makeOctokitStub({
      merge: async () => {
        throw new Error("Pull Request is not mergeable");
      },
      graphql: async () => {
        throw new Error("auto-merge is not allowed on this repository");
      },
      scheduledIssueNumber: 11,
    });
    const result = await safeCommitAndPr({
      ...baseConfig(f, makeOctokitStub()),
      octokit: octokit as never,
      mergeMode: "direct",
    });

    expect(result.status).toBe("failed");
    if (result.status === "failed") {
      expect(result.stage).toBe("auto-merge");
      // Anti-vacuity: the failure message must carry BOTH rungs of the
      // direct ladder — an option-ignoring auto-mode helper also fails at
      // stage auto-merge with the same comment, but its message has no
      // "direct merge failed" prefix.
      expect(result.message).toContain("direct merge failed");
    }
    expect(octokit.request).toHaveBeenCalledWith(
      "PUT /repos/{owner}/{repo}/pulls/{pull_number}/merge",
      expect.objectContaining({ pull_number: 42 }),
    );
    // Operator visibility: the PR-needs-manual-merge comment landed.
    expect(octokit.request).toHaveBeenCalledWith(
      "POST /repos/{owner}/{repo}/issues/{issue_number}/comments",
      expect.objectContaining({
        issue_number: 11,
        body: expect.stringContaining("manual merge"),
      }),
    );
  });

  it("mergeMode 'none' creates the PR but never touches merge endpoints (compound-promote drafts)", async () => {
    const f = await makeFixture();
    await writeFile(join(f.repo, "knowledge-base/marketing/file-8.md"), "change\n");

    const octokit = makeOctokitStub();
    const result = await safeCommitAndPr({
      ...baseConfig(f, makeOctokitStub()),
      octokit: octokit as never,
      mergeMode: "none",
    });

    expect(result.status).toBe("committed");
    if (result.status === "committed") {
      expect(result.prNumber).toBe(42);
    }
    expect(octokit.graphql).not.toHaveBeenCalled();
    expect(octokit.request).not.toHaveBeenCalledWith(
      "PUT /repos/{owner}/{repo}/pulls/{pull_number}/merge",
      expect.anything(),
    );
  });
});
