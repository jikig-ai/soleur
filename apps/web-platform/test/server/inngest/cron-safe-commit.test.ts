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
import { chmod, mkdtemp, mkdir, readFile, rename, rm, symlink, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
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
  deriveBranchName,
  isPathAllowed,
  parsePorcelainZ,
  safeCommitAndPr,
  __safeCommitInternals,
  type SafeCommitResult,
} from "@/server/inngest/functions/_cron-safe-commit";
// #7849: the fixture git environment comes from the shared helper. SEED_ENV is layered ON TOP so
// its deterministic identity and dates still win -- two fixtures with identical content must
// produce identical parent SHAs for the double-run test. What the helper adds underneath is the
// discovery ceiling and the prefix sweep: the previous `{ ...process.env, ...SEED_ENV }` spread
// carried an inherited GIT_DIR straight through, and GIT_DIR beats both `cwd` and `git -C`.
import { gitFixtureEnv } from "../../../../../plugins/soleur/test/lib/git-fixture-env";
import { GIT_HARDENING_ARGS, GIT_HARDENING_ENV } from "@/server/inngest/functions/_git-hardening";

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
    env: { ...gitFixtureEnv(cwd), ...SEED_ENV },
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
  await execFileP("git", ["init", "--bare", remote], { env: gitFixtureEnv(remote) });
  await execFileP("git", ["init", "-b", "main", repo], { env: gitFixtureEnv(repo) });
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
    // maxRetries: a push can leave git's post-push housekeeping writing under
    // remote.git/ while teardown runs (observed once as ENOTEMPTY).
    await rm(f.root, { recursive: true, force: true, maxRetries: 5, retryDelay: 50 });
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

// ---------------------------------------------------------------------------
// #7122 Guard 3 — exact-path persistence + PR-body count. The community
// monitor persists ONE handler-authored dated digest; every other path the
// workspace dirtied is dropped, and in exactPaths mode no agent-chosen file
// name may reach the public PR body (count only). Row numbers are the plan's
// Guard 3 mutation matrix.
// ---------------------------------------------------------------------------

const DIGEST_BYTES = "# 2026-06-10\nrendered by the handler\n";
const DIGEST_DIR = "knowledge-base/support/community/";
const TODAY_DIGEST = `${DIGEST_DIR}2026-06-10-digest.md`;
const PRIOR_DIGEST = `${DIGEST_DIR}2026-06-09-digest.md`;

/** Commit a previously published digest so an edit to it is a TRACKED modification. */
async function seedPublishedDigest(f: Fixture): Promise<void> {
  await mkdir(join(f.repo, DIGEST_DIR), { recursive: true });
  await writeFile(join(f.repo, PRIOR_DIGEST), "# 2026-06-09\npublished\n");
  await tgit(f.repo, "add", "--", PRIOR_DIGEST);
  await tgit(f.repo, "commit", "-m", "seed published digest");
  await tgit(f.repo, "push", "origin", "main");
}

/**
 * An exactPaths config. `expectedContent` is REQUIRED by the helper in this mode, so
 * `digestContent` (the bytes the test writes to TODAY_DIGEST) defaults to the shared
 * DIGEST_BYTES fixture; a row that writes other bytes passes them here.
 */
function exactConfig(f: Fixture, octokit: OctokitStub, digestContent: string = DIGEST_BYTES) {
  return {
    ...baseConfig(f, octokit),
    allowedPaths: [] as readonly string[],
    exactPaths: [TODAY_DIGEST] as readonly string[],
    expectedContent: { [TODAY_DIGEST]: digestContent } as Readonly<Record<string, string>>,
  };
}

/** The `body` argument of the POST .../pulls call, or undefined if never called. */
function prBodyArg(octokit: OctokitStub): unknown {
  const call = octokit.request.mock.calls.find(
    (c) => c[0] === "POST /repos/{owner}/{repo}/pulls",
  );
  return (call?.[1] as { body?: unknown } | undefined)?.body;
}

describe("isPathAllowed — one shared predicate for the matched/dropped partitions", () => {
  it("allowedPaths: [] with exactPaths: [] matches nothing", () => {
    expect(isPathAllowed(TODAY_DIGEST, { allowedPaths: [], exactPaths: [] })).toBe(false);
    expect(isPathAllowed("knowledge-base/marketing/file-0.md", {})).toBe(false);
  });

  it("allowedPaths keeps bare startsWith prefix semantics", () => {
    const cfg = { allowedPaths: ["knowledge-base/marketing/"] };
    expect(isPathAllowed("knowledge-base/marketing/file-0.md", cfg)).toBe(true);
    expect(isPathAllowed("knowledge-base/marketing-evil.md", cfg)).toBe(false);
  });

  it("exactPaths matches by string equality only (no prefix, no suffix)", () => {
    const cfg = { allowedPaths: [], exactPaths: [TODAY_DIGEST] };
    expect(isPathAllowed(TODAY_DIGEST, cfg)).toBe(true);
    expect(isPathAllowed(`${TODAY_DIGEST}.evil`, cfg)).toBe(false);
    expect(isPathAllowed(`${DIGEST_DIR}2026-06-10-digest.m`, cfg)).toBe(false);
    expect(isPathAllowed(PRIOR_DIGEST, cfg)).toBe(false);
    expect(isPathAllowed(DIGEST_DIR, cfg)).toBe(false);
  });

  it("exactPaths branch rejects traversal, absolute and empty candidates even if listed", () => {
    for (const bad of ["../x.md", "a/../b.md", "/etc/passwd", "a/./b.md", ""]) {
      expect(isPathAllowed(bad, { exactPaths: [bad] }), `candidate ${JSON.stringify(bad)}`).toBe(false);
    }
  });
});

describe("safeCommitAndPr — #7122 exactPaths mode (Guard 3)", () => {
  it("G3-1: an edited published digest and a `.evil` sibling are dropped; the committed set is exactly [today digest]", async () => {
    const f = await makeFixture();
    await seedPublishedDigest(f);
    await writeFile(join(f.repo, PRIOR_DIGEST), "# 2026-06-09\nREWRITTEN\n");
    await writeFile(join(f.repo, TODAY_DIGEST), "# 2026-06-10\ntoday\n");
    await writeFile(join(f.repo, `${TODAY_DIGEST}.evil`), "evil\n");

    const octokit = makeOctokitStub();
    const result = await safeCommitAndPr(exactConfig(f, octokit, "# 2026-06-10\ntoday\n"));

    expect(result.status).toBe("committed");
    const shown = await tgit(f.repo, "show", "--name-only", "--format=", "HEAD");
    expect(shown.split("\n").filter(Boolean)).toEqual([TODAY_DIGEST]);
    if (result.status === "committed") expect(result.paths).toEqual([TODAY_DIGEST]);
    // Both dropped paths are still LOUD in Sentry (names go there, not to the PR).
    const dropCalls = reportSilentFallbackMock.mock.calls.filter(
      (c) => c[1]?.op === "safe-commit-paths-dropped",
    );
    expect(dropCalls).toHaveLength(1);
    expect(dropCalls[0][1].extra.droppedCount).toBe(2);
    expect(dropCalls[0][1].extra.sample).toEqual(
      expect.arrayContaining([PRIOR_DIGEST, `${TODAY_DIGEST}.evil`]),
    );
  });

  it("G3-3: a hostile file name never appears in the PR body; the marker is the count-only form", async () => {
    const f = await makeFixture();
    await mkdir(join(f.repo, DIGEST_DIR), { recursive: true });
    await writeFile(join(f.repo, TODAY_DIGEST), "# today\n");
    await writeFile(join(f.repo, "www.evil.example-free-money"), "x\n");

    const octokit = makeOctokitStub();
    const result = await safeCommitAndPr(exactConfig(f, octokit, "# today\n"));

    expect(result.status).toBe("committed");
    const body = prBodyArg(octokit);
    expect(body).toBeTypeOf("string");
    expect(body as string).not.toContain("www.evil.example-free-money");
    expect(body as string).toContain(
      "> ⚠️ 1 changed path(s) outside the persistence allowlist were NOT committed " +
        "(Sentry op `safe-commit-paths-dropped`)",
    );
    // Count-only: the marker line ends at the closing paren, no `:` name list.
    expect(body as string).not.toMatch(/safe-commit-paths-dropped`\):/);
  });

  it("G3-4: two stray files (one conforming, one hostile) render as `2 changed path(s)` and neither name", async () => {
    const f = await makeFixture();
    await mkdir(join(f.repo, DIGEST_DIR), { recursive: true });
    await writeFile(join(f.repo, TODAY_DIGEST), "# today\n");
    // Conforming-looking name (a plausible dated digest for another day) + a hostile one.
    await writeFile(join(f.repo, `${DIGEST_DIR}2026-06-11-digest.md`), "other day\n");
    await writeFile(join(f.repo, "www.evil.example-free-money"), "x\n");

    const octokit = makeOctokitStub();
    const result = await safeCommitAndPr(exactConfig(f, octokit, "# today\n"));

    expect(result.status).toBe("committed");
    const body = prBodyArg(octokit);
    expect(body).toBeTypeOf("string");
    expect(body as string).toContain("2 changed path(s) outside the persistence allowlist");
    expect(body as string).not.toContain("2026-06-11-digest.md");
    expect(body as string).not.toContain("www.evil.example-free-money");
  });

  it("G3-5: a predicate that ignores exactPaths would commit nothing — the real one commits the exact path", async () => {
    // Guard against vacuity: with allowedPaths: [] and exactPaths ignored, the
    // matched set is empty and the run is `no-changes` (RED liveness upstream).
    const f = await makeFixture();
    await mkdir(join(f.repo, DIGEST_DIR), { recursive: true });
    await writeFile(join(f.repo, TODAY_DIGEST), "# today\n");

    const octokit = makeOctokitStub();
    const result = await safeCommitAndPr(exactConfig(f, octokit, "# today\n"));

    expect(result.status).toBe("committed");
    expect(result.status === "committed" ? result.fileCount : 0).toBe(1);
    // And the mutation itself: the same fixture under an exactPaths-less config
    // matches nothing, which is exactly what an exactPaths-ignoring predicate yields.
    const f2 = await makeFixture();
    await mkdir(join(f2.repo, DIGEST_DIR), { recursive: true });
    await writeFile(join(f2.repo, TODAY_DIGEST), "# today\n");
    const ignoring = await safeCommitAndPr({
      ...baseConfig(f2, makeOctokitStub()),
      allowedPaths: [],
    });
    expect(ignoring.status).toBe("no-changes");
  });

  it("G3-6: the PR-body mock actually received a string body (harness is not vacuous)", async () => {
    const f = await makeFixture();
    await mkdir(join(f.repo, DIGEST_DIR), { recursive: true });
    await writeFile(join(f.repo, TODAY_DIGEST), "# today\n");

    const octokit = makeOctokitStub();
    await safeCommitAndPr(exactConfig(f, octokit, "# today\n"));

    const arg = prBodyArg(octokit);
    expect(arg).toBeTypeOf("string");
    expect((arg as string).length).toBeGreaterThan(0);
    // Self-check the extractor: a stub that never saw the PR POST yields undefined.
    expect(prBodyArg(makeOctokitStub())).toBeUndefined();
  });

  it("G3-7: allowedPaths mode keeps today's dropped-path marker BYTE-FOR-BYTE (names included)", async () => {
    const f = await makeFixture();
    await writeFile(join(f.repo, "knowledge-base/marketing/file-1.md"), "updated\n");
    await writeFile(join(f.repo, "plugins/soleur/docs/page.md"), "# changed\n");
    await writeFile(join(f.repo, "weird`name|x.md"), "x\n");

    const octokit = makeOctokitStub();
    await safeCommitAndPr(baseConfig(f, octokit));

    const body = prBodyArg(octokit);
    expect(body).toBeTypeOf("string");
    expect(body).toBe(
      "Automated PR from `cron-test-fixture` — committed handler-side via safeCommitAndPr (#5091).\n\n" +
        "> ⚠️ 2 changed path(s) outside the persistence allowlist were NOT committed " +
        "(Sentry op `safe-commit-paths-dropped`): `plugins/soleur/docs/page.md`, `weirdʼnameʼx.md`",
    );
  });
});


// ---------------------------------------------------------------------------
// #7122 P1-B — the handler's git steps run in a workspace the agent may have
// planted state in (clean filter + info/attributes, hooks, core.fsmonitor, a
// pushurl / insteadOf redirect, a pre-created branch ahead of origin/main). In
// exactPaths mode the handler must neither EXECUTE planted state nor push bytes it
// did not render. Every row plants state AFTER the seed so the fixture's own setup
// stays clean, and proves the effect with a marker file, never by reading config.
// ---------------------------------------------------------------------------

function marker(f: Fixture, name: string): string {
  return join(f.root, `marker-${name}`);
}

/** Plant a hook, a clean filter, an fsmonitor and a push redirect inside the repo's .git. */
async function plantHostileGitState(f: Fixture): Promise<{ evilRemote: string }> {
  const hooks = join(f.repo, ".git", "hooks");
  await mkdir(hooks, { recursive: true });
  for (const hook of ["pre-commit", "commit-msg", "post-commit", "pre-push", "reference-transaction"]) {
    await writeFile(join(hooks, hook), `#!/bin/sh\ntouch '${marker(f, `hook-${hook}`)}'\nexit 0\n`);
    await chmod(join(hooks, hook), 0o755);
  }
  const fsm = join(f.root, "fsmonitor.sh");
  await writeFile(fsm, `#!/bin/sh\ntouch '${marker(f, "fsmonitor")}'\nexit 0\n`);
  await chmod(fsm, 0o755);
  const filter = join(f.root, "filter.sh");
  await writeFile(filter, `#!/bin/sh\ntouch '${marker(f, "filter")}'\ncat >/dev/null\necho ATTACKER_CHOSEN_TEXT\n`);
  await chmod(filter, 0o755);
  const evilRemote = join(f.root, "evil.git");
  await execFileP("git", ["init", "--bare", evilRemote], { env: gitFixtureEnv(evilRemote) });
  const cfg = (k: string, v: string) =>
    execFileP("git", ["config", "--local", k, v], { cwd: f.repo, env: { ...gitFixtureEnv(f.repo), ...SEED_ENV } });
  await cfg("core.fsmonitor", fsm);
  await cfg("filter.x.clean", filter);
  await cfg("filter.x.required", "true");
  await cfg("remote.origin.pushurl", evilRemote);
  await mkdir(join(f.repo, ".git", "info"), { recursive: true });
  await writeFile(join(f.repo, ".git", "info", "attributes"), "* filter=x\n");
  return { evilRemote };
}

async function remoteBranches(remote: string): Promise<string[]> {
  const out = await execFileP("git", ["--git-dir", remote, "for-each-ref", "--format=%(refname:short)", "refs/heads/"], {
    env: gitFixtureEnv(remote),
  });
  return out.stdout.split("\n").filter(Boolean);
}

describe("safeCommitAndPr — #7122 P1-B planted workspace state (exactPaths mode)", () => {
  const expected = (): Record<string, string> => ({ [TODAY_DIGEST]: DIGEST_BYTES });

  async function writeDigest(f: Fixture, content = DIGEST_BYTES): Promise<void> {
    await mkdir(join(f.repo, DIGEST_DIR), { recursive: true });
    await writeFile(join(f.repo, TODAY_DIGEST), content);
  }

  it("B-1: a planted hook, clean filter, fsmonitor and pushurl redirect execute NOTHING and the committed bytes are the rendered bytes", async () => {
    const f = await makeFixture();
    const { evilRemote } = await plantHostileGitState(f);
    await writeDigest(f);

    const result = await safeCommitAndPr({ ...exactConfig(f, makeOctokitStub()), expectedContent: expected() });

    expect(result.status).toBe("committed");
    for (const m of ["filter", "fsmonitor", "hook-pre-commit", "hook-commit-msg", "hook-post-commit", "hook-pre-push", "hook-reference-transaction"]) {
      expect(existsSync(marker(f, m)), `planted ${m} executed`).toBe(false);
    }
    // The blob in the pushed branch is byte-identical to the rendered digest (no ATTACKER_CHOSEN_TEXT).
    const branch = result.status === "committed" ? result.branch : "";
    const blob = (await execFileP("git", ["--git-dir", f.remote, "show", `${branch}:${TODAY_DIGEST}`], { env: gitFixtureEnv(f.remote) })).stdout;
    expect(blob).toBe(DIGEST_BYTES);
    // The push went to the REAL origin; the planted pushurl received nothing.
    expect(await remoteBranches(f.remote)).toContain(branch);
    expect(await remoteBranches(evilRemote)).toEqual([]);
  });

  it("B-1b: the harness is live — the same planted state DOES execute under a plain git add/commit (the markers are not unreachable)", async () => {
    const f = await makeFixture();
    await plantHostileGitState(f);
    await writeDigest(f);
    await execFileP("git", ["add", "--", TODAY_DIGEST], { cwd: f.repo, env: { ...gitFixtureEnv(f.repo), ...SEED_ENV } });
    await execFileP("git", ["commit", "-m", "x"], { cwd: f.repo, env: { ...gitFixtureEnv(f.repo), ...SEED_ENV } });
    expect(existsSync(marker(f, "filter"))).toBe(true);
    expect(existsSync(marker(f, "hook-pre-commit"))).toBe(true);
  });

  it("B-2: expectedContent that differs from the staged blob refuses to commit: failed/integrity, nothing pushed, no content in any message", async () => {
    const f = await makeFixture();
    const onDisk = "# 2026-06-10\nSECRET-ON-DISK-8841\n";
    await writeDigest(f, onDisk);
    const wanted = { [TODAY_DIGEST]: "# 2026-06-10\nSECRET-EXPECTED-7720\n" };

    const result = await safeCommitAndPr({ ...exactConfig(f, makeOctokitStub()), expectedContent: wanted });

    expect(result.status).toBe("failed");
    if (result.status === "failed") {
      expect(result.stage).toBe("integrity");
      expect(result.message).toBe("integrity: index-content-mismatch");
    }
    expect(await remoteBranches(f.remote)).toEqual(["main"]);
    const everything = JSON.stringify([result, reportSilentFallbackMock.mock.calls]);
    expect(everything).not.toContain("SECRET-ON-DISK-8841");
    expect(everything).not.toContain("SECRET-EXPECTED-7720");
    const op = reportSilentFallbackMock.mock.calls.find((c) => c[1]?.op === "safe-commit-failed");
    expect(op?.[1].extra).toMatchObject({ stage: "integrity", reason: "index-content-mismatch" });
    // No commit was created locally either.
    expect(await tgit(f.repo, "rev-list", "origin/main..HEAD", "--count")).toBe("0");
  });

  it("B-2b: byte-for-byte, not normalised — a trailing-newline difference is a mismatch", async () => {
    const f = await makeFixture();
    await writeDigest(f, "# 2026-06-10\nline");
    const result = await safeCommitAndPr({ ...exactConfig(f, makeOctokitStub()), expectedContent: { [TODAY_DIGEST]: "# 2026-06-10\nline\n" } });
    expect(result.status === "failed" && result.stage).toBe("integrity");
  });

  it("B-3: a symlink planted at the digest path is refused (it would commit the target's bytes)", async () => {
    const f = await makeFixture();
    await mkdir(join(f.repo, DIGEST_DIR), { recursive: true });
    await writeFile(join(f.root, "target.txt"), DIGEST_BYTES);
    await symlink(join(f.root, "target.txt"), join(f.repo, TODAY_DIGEST));
    const result = await safeCommitAndPr({ ...exactConfig(f, makeOctokitStub()), expectedContent: expected() });
    expect(result.status).toBe("failed");
    expect(result.status === "failed" && result.message).toBe("integrity: path-not-regular-file");
    expect(await remoteBranches(f.remote)).toEqual(["main"]);
  });

  it("B-4: a `.git` that is not a plain directory is refused before any git command runs", async () => {
    const f = await makeFixture();
    await writeDigest(f);
    const moved = join(f.root, "real-git");
    await execFileP("mv", [join(f.repo, ".git"), moved]);
    await symlink(moved, join(f.repo, ".git"));
    const result = await safeCommitAndPr({ ...exactConfig(f, makeOctokitStub()), expectedContent: expected() });
    expect(result.status === "failed" && result.message).toBe("integrity: git-dir-not-directory");
  });

  describe("replay-resume arm (a pre-existing branch ahead of origin/main)", () => {
    const branchFor = () => deriveBranchName("cron-test-fixture", RUN_STARTED_AT);

    // The handler's own identity (what a crashed first attempt would have committed as).
    const BOT_ENV = {
      GIT_AUTHOR_NAME: "github-actions[bot]",
      GIT_AUTHOR_EMAIL: "41898282+github-actions[bot]@users.noreply.github.com",
      GIT_COMMITTER_NAME: "github-actions[bot]",
      GIT_COMMITTER_EMAIL: "41898282+github-actions[bot]@users.noreply.github.com",
    };
    async function precreateBranch(
      f: Fixture,
      files: Record<string, string>,
      as: { env?: Record<string, string>; message?: string } = {},
    ): Promise<void> {
      await tgit(f.repo, "checkout", "-b", branchFor());
      for (const [rel, content] of Object.entries(files)) {
        await mkdir(dirname(join(f.repo, rel)), { recursive: true });
        await writeFile(join(f.repo, rel), content);
      }
      await tgit(f.repo, "add", "--", ...Object.keys(files));
      await execFileP("git", ["commit", "-m", as.message ?? "agent-authored"], {
        cwd: f.repo,
        env: { ...gitFixtureEnv(f.repo), ...SEED_ENV, ...as.env },
      });
    }
    /** A commit exactly as a crashed earlier attempt of this handler would have left it. */
    const precreateGenuine = (f: Fixture, files: Record<string, string>) =>
      precreateBranch(f, files, { env: BOT_ENV, message: "fix(test): fixture commit" });

    it("B-5: a branch carrying an EXTRA file beside the digest is NOT pushed", async () => {
      const f = await makeFixture();
      await precreateBranch(f, { [TODAY_DIGEST]: DIGEST_BYTES, "knowledge-base/planted.md": "ATTACKER_CHOSEN_TEXT\n" });
      const result = await safeCommitAndPr({ ...exactConfig(f, makeOctokitStub()), expectedContent: expected() });
      expect(result.status).toBe("failed");
      expect(result.status === "failed" && result.message).toBe("integrity: resume-unexpected-path");
      expect(await remoteBranches(f.remote)).toEqual(["main"]);
    });

    it("B-5b: a branch whose digest blob differs from the rendered bytes is NOT pushed", async () => {
      const f = await makeFixture();
      await precreateBranch(f, { [TODAY_DIGEST]: "ATTACKER_CHOSEN_TEXT\n" });
      const result = await safeCommitAndPr({ ...exactConfig(f, makeOctokitStub()), expectedContent: expected() });
      expect(result.status === "failed" && result.message).toBe("integrity: resume-content-mismatch");
      expect(await remoteBranches(f.remote)).toEqual(["main"]);
    });

    it("B-5c: more than one commit ahead of origin/main is NOT pushed", async () => {
      const f = await makeFixture();
      await precreateBranch(f, { [TODAY_DIGEST]: DIGEST_BYTES });
      await writeFile(join(f.repo, TODAY_DIGEST), DIGEST_BYTES);
      await tgit(f.repo, "commit", "--allow-empty", "-m", "second");
      const result = await safeCommitAndPr({ ...exactConfig(f, makeOctokitStub()), expectedContent: expected() });
      expect(result.status === "failed" && result.message).toBe("integrity: resume-unexpected-commit-count");
      expect(await remoteBranches(f.remote)).toEqual(["main"]);
    });

    it("B-5d (control): a genuine replay — one commit, only the digest, the rendered bytes, the handler's identity and message — still resumes and pushes", async () => {
      const f = await makeFixture();
      await precreateGenuine(f, { [TODAY_DIGEST]: DIGEST_BYTES });
      const result = await safeCommitAndPr({ ...exactConfig(f, makeOctokitStub()), expectedContent: expected() });
      expect(result.status).toBe("committed");
      expect(result.status === "committed" && result.resumed).toBe(true);
      expect(await remoteBranches(f.remote)).toContain(branchFor());
    });
  });
});

describe("safeCommitAndPr — #7122 P1-B git hardening applies to every caller (not only exactPaths)", () => {
  it("B-6: a planted pre-commit hook and core.fsmonitor do not run in the default allowedPaths mode either", async () => {
    const f = await makeFixture();
    await plantHostileGitState(f);
    await writeFile(join(f.repo, "knowledge-base/marketing/file-2.md"), "edited\n");
    const result = await safeCommitAndPr(baseConfig(f, makeOctokitStub()));
    expect(result.status).toBe("committed");
    expect(existsSync(marker(f, "fsmonitor"))).toBe(false);
    for (const h of ["pre-commit", "commit-msg", "post-commit", "pre-push", "reference-transaction"]) {
      expect(existsSync(marker(f, `hook-${h}`)), h).toBe(false);
    }
  });
});


// ---------------------------------------------------------------------------
// #7122 round-1 — exactPaths trusts NO agent-influenced git state. Every row below
// reproduces a bypass the round-1 security review demonstrated against the previous
// revision (E1b, E2, E8, E10, F1-F4) or a layer a mutation showed to be unpinned
// (test-design P2-4, P3-6). Planted state is created AFTER the seed, effects are proved
// with marker files and by reading the REMOTE, never by reading the helper's own config.
// ---------------------------------------------------------------------------

describe("safeCommitAndPr — #7122 round-1 exactPaths hardening", () => {
  const BOT_ENV = {
    GIT_AUTHOR_NAME: "github-actions[bot]",
    GIT_AUTHOR_EMAIL: "41898282+github-actions[bot]@users.noreply.github.com",
    GIT_COMMITTER_NAME: "github-actions[bot]",
    GIT_COMMITTER_EMAIL: "41898282+github-actions[bot]@users.noreply.github.com",
  };
  const BRANCH = () => deriveBranchName("cron-test-fixture", RUN_STARTED_AT);
  const exactCfg = (f: Fixture, content = DIGEST_BYTES, octokit = makeOctokitStub()) => exactConfig(f, octokit, content);

  async function writeDigest(f: Fixture, content = DIGEST_BYTES): Promise<void> {
    await mkdir(join(f.repo, DIGEST_DIR), { recursive: true });
    await writeFile(join(f.repo, TODAY_DIGEST), content);
  }
  async function remoteGit(f: Fixture, ...args: string[]): Promise<string> {
    return (await execFileP("git", ["--git-dir", f.remote, ...args], { env: gitFixtureEnv(f.remote) })).stdout.trim();
  }
  async function script(f: Fixture, name: string, body = ""): Promise<string> {
    const path = join(f.root, `${name}.sh`);
    await writeFile(path, `#!/bin/sh\ntouch '${marker(f, name)}'\n${body}\nexit 0\n`);
    await chmod(path, 0o755);
    return path;
  }
  async function bareRepo(f: Fixture, name: string): Promise<string> {
    const dir = join(f.root, name);
    await execFileP("git", ["init", "--bare", dir], { env: gitFixtureEnv(dir) });
    return dir;
  }
  const cfgSet = (gitDirOrFile: string, k: string, v: string) =>
    execFileP("git", ["config", "--file", gitDirOrFile, k, v], { env: { ...gitFixtureEnv(gitDirOrFile), ...SEED_ENV } });
  /** A commit exactly as an earlier attempt of the handler would have left it. */
  async function precreate(f: Fixture, files: Record<string, string>, bot = true, message = "fix(test): fixture commit") {
    await tgit(f.repo, "checkout", "-b", BRANCH());
    for (const [rel, content] of Object.entries(files)) {
      await mkdir(dirname(join(f.repo, rel)), { recursive: true });
      await writeFile(join(f.repo, rel), content);
    }
    await tgit(f.repo, "add", "--", ...Object.keys(files));
    await execFileP("git", ["commit", "-m", message], {
      cwd: f.repo,
      env: { ...gitFixtureEnv(f.repo), ...SEED_ENV, ...(bot ? BOT_ENV : {}) },
    });
  }
  const runExact = (f: Fixture, extra: Record<string, unknown> = {}, content = DIGEST_BYTES) =>
    safeCommitAndPr({ ...exactCfg(f, content), ...extra } as never);
  const failedWith = (r: SafeCommitResult) => (r.status === "failed" ? r.message : `<${r.status}>`);

  // ---- (a) the base of the commit is the freshly fetched origin tip --------------------

  describe("agent commits never ride along (E1b / F1)", () => {
    it("R-1: an agent commit of a workflow file on local main is NOT in the pushed branch; its parent is the origin tip", async () => {
      const f = await makeFixture();
      const originTip = await remoteGit(f, "rev-parse", "main");
      await mkdir(join(f.repo, ".github/workflows"), { recursive: true });
      await writeFile(join(f.repo, ".github/workflows/evil.yml"), "on: push\n");
      await tgit(f.repo, "add", "--", ".github/workflows/evil.yml");
      await tgit(f.repo, "commit", "-m", "agent: add workflow");
      await writeDigest(f);

      const result = await runExact(f);

      expect(result.status).toBe("committed");
      const branch = result.status === "committed" ? result.branch : "";
      expect((await remoteGit(f, "diff", "--name-only", "main", branch)).split("\n")).toEqual([TODAY_DIGEST]);
      expect(await remoteGit(f, "rev-parse", `${branch}^`)).toBe(originTip);
      expect(await remoteGit(f, "rev-list", "--count", `main..${branch}`)).toBe("1");
      // The local HEAD is the handler's commit, not the agent's.
      expect(await tgit(f.repo, "rev-parse", "HEAD")).toBe(await remoteGit(f, "rev-parse", branch));
    });

    it("R-1b: the same with `refs/remotes/origin/main` FORGED to the agent commit (the local ref is not the trust anchor)", async () => {
      const f = await makeFixture();
      const originTip = await remoteGit(f, "rev-parse", "main");
      await writeFile(join(f.repo, "agent-evil.txt"), "x\n");
      await tgit(f.repo, "add", "--", "agent-evil.txt");
      await tgit(f.repo, "commit", "-m", "agent");
      await tgit(f.repo, "update-ref", "refs/remotes/origin/main", "HEAD");
      await writeDigest(f);

      const result = await runExact(f);

      expect(result.status).toBe("committed");
      const branch = result.status === "committed" ? result.branch : "";
      expect((await remoteGit(f, "diff", "--name-only", "main", branch)).split("\n")).toEqual([TODAY_DIGEST]);
      expect(await remoteGit(f, "rev-parse", `${branch}^`)).toBe(originTip);
    });

    it("R-1c: the base is the origin tip FETCHED NOW — when main advanced during the run the commit still sits on the new tip and carries nothing else", async () => {
      const f = await makeFixture();
      // Someone else merges to origin/main after this workspace was cloned.
      const other = join(f.root, "other");
      await execFileP("git", ["clone", "-b", "main", f.remote, other], { env: gitFixtureEnv(other) });
      await writeFile(join(other, "later.md"), "merged later\n");
      await tgit(other, "add", "--", "later.md");
      await tgit(other, "commit", "-m", "later");
      await tgit(other, "push", "origin", "main");
      const newTip = await remoteGit(f, "rev-parse", "main");
      await writeDigest(f);

      const result = await runExact(f);

      expect(result.status).toBe("committed");
      const branch = result.status === "committed" ? result.branch : "";
      expect(await remoteGit(f, "rev-parse", `${branch}^`)).toBe(newTip);
      expect((await remoteGit(f, "diff", "--name-only", "main", branch)).split("\n")).toEqual([TODAY_DIGEST]);
    });

    it("R-1d: an origin that cannot be fetched is refused (closed reason), nothing is pushed", async () => {
      const f = await makeFixture();
      await writeDigest(f);
      await tgit(f.repo, "remote", "set-url", "origin", join(f.root, "does-not-exist.git"));
      const result = await runExact(f);
      expect(failedWith(result)).toBe("integrity: origin-fetch-failed");
      expect(await remoteBranches(f.remote)).toEqual(["main"]);
    });
  });

  // ---- (b) replace refs, commondir, alternates: git state the agent could redirect -----

  describe("redirected git state is removed before it is read (E2 / E10 / F2 / F3)", () => {
    it("R-2 (E10): a `refs/replace` swap on the resume arm cannot make an attacker blob read as the rendered bytes", async () => {
      const f = await makeFixture();
      await precreate(f, { [TODAY_DIGEST]: "ATTACKER_CHOSEN_TEXT\n" });
      const badBlob = await tgit(f.repo, "rev-parse", `${BRANCH()}:${TODAY_DIGEST}`);
      await writeFile(join(f.root, "good.txt"), DIGEST_BYTES);
      const goodBlob = await tgit(f.repo, "hash-object", "-w", join(f.root, "good.txt"));
      await tgit(f.repo, "replace", badBlob, goodBlob);
      // Harness is live: through the replace ref a plain read returns the GOOD bytes.
      expect(await tgit(f.repo, "cat-file", "blob", `${BRANCH()}:${TODAY_DIGEST}`)).toBe(DIGEST_BYTES.trim());

      const result = await runExact(f);

      expect(failedWith(result)).toBe("integrity: resume-content-mismatch");
      expect(await remoteBranches(f.remote)).toEqual(["main"]);
    });

    it("R-2b: the hardening reads the REAL object — `--no-replace-objects` AND GIT_NO_REPLACE_OBJECTS are both pinned, and runGit returns the unreplaced blob", async () => {
      expect(GIT_HARDENING_ARGS).toContain("--no-replace-objects");
      expect(GIT_HARDENING_ENV.GIT_NO_REPLACE_OBJECTS).toBe("1");
      const f = await makeFixture();
      await precreate(f, { [TODAY_DIGEST]: "ATTACKER_CHOSEN_TEXT\n" });
      const badBlob = await tgit(f.repo, "rev-parse", `${BRANCH()}:${TODAY_DIGEST}`);
      await writeFile(join(f.root, "good.txt"), DIGEST_BYTES);
      const goodBlob = await tgit(f.repo, "hash-object", "-w", join(f.root, "good.txt"));
      await tgit(f.repo, "replace", badBlob, goodBlob);
      const hardened = await __safeCommitInternals.runGit(f.repo, ["cat-file", "blob", `${BRANCH()}:${TODAY_DIGEST}`]);
      expect(hardened.stdout).toBe("ATTACKER_CHOSEN_TEXT\n");
    });

    it("R-2c: replace refs are DELETED from the workspace by the sanitiser (loose and packed)", async () => {
      const f = await makeFixture();
      await tgit(f.repo, "replace", await tgit(f.repo, "rev-parse", "HEAD:knowledge-base/marketing/file-0.md"), await tgit(f.repo, "rev-parse", "HEAD:knowledge-base/marketing/file-1.md"));
      await tgit(f.repo, "pack-refs", "--all");
      await tgit(f.repo, "replace", await tgit(f.repo, "rev-parse", "HEAD:knowledge-base/marketing/file-2.md"), await tgit(f.repo, "rev-parse", "HEAD:knowledge-base/marketing/file-3.md"));
      expect((await tgit(f.repo, "for-each-ref", "refs/replace/")).split("\n").filter(Boolean)).toHaveLength(2);
      await writeDigest(f);
      expect((await runExact(f)).status).toBe("committed");
      expect(await tgit(f.repo, "for-each-ref", "refs/replace/")).toBe("");
    });

    it("R-3 (E2): a planted `.git/commondir` pointing at an attacker directory neither executes its filter/fsmonitor nor redirects the push", async () => {
      const f = await makeFixture();
      const evilGit = join(f.root, "evilgit");
      await execFileP("cp", ["-r", join(f.repo, ".git"), evilGit]);
      const evilRemote = await bareRepo(f, "evil.git");
      const filter = await script(f, "filter", "cat >/dev/null; echo ATTACKER_CHOSEN_TEXT");
      const fsm = await script(f, "fsmonitor");
      for (const [k, v] of [
        ["filter.x.clean", filter],
        ["filter.x.required", "true"],
        ["core.fsmonitor", fsm],
        ["remote.origin.pushurl", evilRemote],
      ] as const) await cfgSet(join(evilGit, "config"), k, v);
      await mkdir(join(evilGit, "info"), { recursive: true });
      await writeFile(join(evilGit, "info", "attributes"), "* filter=x\n");
      await writeFile(join(f.repo, ".git", "commondir"), `${evilGit}\n`);
      await writeDigest(f);

      const result = await runExact(f);

      expect(result.status).toBe("committed");
      expect(existsSync(marker(f, "filter")), "planted clean filter ran").toBe(false);
      expect(existsSync(marker(f, "fsmonitor")), "planted fsmonitor ran").toBe(false);
      const branch = result.status === "committed" ? result.branch : "";
      expect(await remoteBranches(f.remote)).toContain(branch);
      expect(await remoteBranches(evilRemote)).toEqual([]);
      expect(await remoteGit(f, "show", `${branch}:${TODAY_DIGEST}`)).toBe(DIGEST_BYTES.trim());
      expect(existsSync(join(f.repo, ".git", "commondir"))).toBe(false);
    });

    it("R-3b: `objects/info/alternates`, `info/grafts`, `info/exclude` and `config.worktree` are removed, `shallow` is kept", async () => {
      const f = await makeFixture();
      await mkdir(join(f.repo, ".git", "info"), { recursive: true });
      await mkdir(join(f.repo, ".git", "objects", "info"), { recursive: true });
      await writeFile(join(f.repo, ".git", "objects", "info", "alternates"), `${join(f.root, "elsewhere")}\n`);
      await writeFile(join(f.repo, ".git", "info", "grafts"), "");
      await writeFile(join(f.repo, ".git", "info", "exclude"), "*.md\n");
      await writeFile(join(f.repo, ".git", "config.worktree"), "[core]\n\tfsmonitor = /bin/true\n");
      await writeFile(join(f.repo, ".git", "shallow"), "");
      await writeDigest(f);
      expect((await runExact(f)).status).toBe("committed");
      for (const rel of ["objects/info/alternates", "info/grafts", "info/exclude", "config.worktree"]) {
        expect(existsSync(join(f.repo, ".git", rel)), rel).toBe(false);
      }
      expect(existsSync(join(f.repo, ".git", "shallow"))).toBe(true);
    });

    it("R-3c: a `.git/info/exclude` that hides the digest does not hide it from the scan (the file is removed)", async () => {
      const f = await makeFixture();
      await mkdir(join(f.repo, ".git", "info"), { recursive: true });
      await writeFile(join(f.repo, ".git", "info", "exclude"), "*.md\n");
      await writeDigest(f);
      const result = await runExact(f);
      expect(result.status).toBe("committed");
    });
  });

  // ---- (c) symlinked .git entries ---------------------------------------------------------

  describe("a symlink at a `.git` entry git writes through is refused, never followed (E8 / F4)", () => {
    it.each(["config", "info", "hooks", "objects"])("R-4: `.git/%s` as a symlink is refused and the link target is untouched", async (entry) => {
      const f = await makeFixture();
      await writeDigest(f);
      const target = join(f.root, `victim-${entry}`);
      if (entry === "config") {
        await writeFile(target, "VICTIM-BYTES\n");
        await rm(join(f.repo, ".git", "config"));
      } else {
        await mkdir(join(f.repo, ".git", entry), { recursive: true });
        await rename(join(f.repo, ".git", entry), target);
        await writeFile(join(target, "sentinel"), "VICTIM-BYTES\n");
      }
      await symlink(target, join(f.repo, ".git", entry));

      const result = await runExact(f);

      expect(failedWith(result)).toBe("integrity: git-entry-symlink");
      expect(await readFile(entry === "config" ? target : join(target, "sentinel"), "utf-8")).toBe("VICTIM-BYTES\n");
      expect(await remoteBranches(f.remote)).toEqual(["main"]);
    });

    it("R-4b: the rewritten config is created exclusively and a pre-existing symlinked file is never written through", async () => {
      const f = await makeFixture();
      await writeDigest(f);
      const victim = join(f.root, "victim.txt");
      await writeFile(victim, "VICTIM-BYTES\n");
      // `info/attributes` is removed, not followed: a link there must not delete or write the victim.
      await mkdir(join(f.repo, ".git", "info"), { recursive: true });
      await symlink(victim, join(f.repo, ".git", "info", "attributes"));
      expect((await runExact(f)).status).toBe("committed");
      expect(await readFile(victim, "utf-8")).toBe("VICTIM-BYTES\n");
    });
  });

  // ---- (d) the resume gate -----------------------------------------------------------------

  describe("the pre-push gate on a pre-existing branch", () => {
    it("R-5: a RENAME onto the digest path (same bytes) is refused — rename detection must not pair a delete with the add", async () => {
      const f = await makeFixture();
      const seeded = "seed content 0\n";
      await tgit(f.repo, "checkout", "-b", BRANCH());
      await mkdir(join(f.repo, DIGEST_DIR), { recursive: true });
      await tgit(f.repo, "mv", "knowledge-base/marketing/file-0.md", TODAY_DIGEST);
      await execFileP("git", ["commit", "-m", "fix(test): fixture commit"], {
        cwd: f.repo,
        env: { ...gitFixtureEnv(f.repo), ...SEED_ENV, ...BOT_ENV },
      });
      // Harness is live: plain git sees this commit as a rename (R100), not as an add.
      expect(await tgit(f.repo, "diff", "--name-status", "origin/main", "HEAD")).toMatch(/^R100\t/);

      const result = await runExact(f, {}, seeded);

      expect(failedWith(result)).toBe("integrity: resume-unexpected-path");
      expect(await remoteBranches(f.remote)).toEqual(["main"]);
    });

    it("R-5b: a DELETE beside the digest is refused (status A/M only)", async () => {
      const f = await makeFixture();
      await tgit(f.repo, "checkout", "-b", BRANCH());
      await mkdir(join(f.repo, DIGEST_DIR), { recursive: true });
      await writeFile(join(f.repo, TODAY_DIGEST), DIGEST_BYTES);
      await tgit(f.repo, "rm", "-q", "--", "knowledge-base/marketing/file-0.md");
      await tgit(f.repo, "add", "--", TODAY_DIGEST);
      await execFileP("git", ["commit", "-m", "fix(test): fixture commit"], {
        cwd: f.repo,
        env: { ...gitFixtureEnv(f.repo), ...SEED_ENV, ...BOT_ENV },
      });
      expect(failedWith(await runExact(f))).toBe("integrity: resume-unexpected-path");
      expect(await remoteBranches(f.remote)).toEqual(["main"]);
    });

    it("R-5c: the digest committed as an EXECUTABLE (100755) or as a SYMLINK (120000) is refused", async () => {
      for (const kind of ["exec", "symlink"] as const) {
        const f = await makeFixture();
        await tgit(f.repo, "checkout", "-b", BRANCH());
        await mkdir(join(f.repo, DIGEST_DIR), { recursive: true });
        if (kind === "exec") {
          await writeFile(join(f.repo, TODAY_DIGEST), DIGEST_BYTES);
          await tgit(f.repo, "add", "--", TODAY_DIGEST);
          await tgit(f.repo, "update-index", "--chmod=+x", TODAY_DIGEST);
        } else {
          await symlink(DIGEST_BYTES.trim(), join(f.repo, TODAY_DIGEST)); // blob = the link text
          await tgit(f.repo, "add", "--", TODAY_DIGEST);
        }
        await execFileP("git", ["commit", "-m", "fix(test): fixture commit"], {
          cwd: f.repo,
          env: { ...gitFixtureEnv(f.repo), ...SEED_ENV, ...BOT_ENV },
        });
        // For the symlink the worktree entry is a link too; the content bytes equal the link text + "\n" is not the digest,
        // so restore a regular file on disk (the gate judges the COMMIT, not the worktree).
        const result = await runExact(f, {}, kind === "symlink" ? DIGEST_BYTES.trim() : DIGEST_BYTES);
        expect(failedWith(result), kind).toMatch(/^integrity: resume-(unexpected-mode|content-mismatch)$/);
        expect(await remoteBranches(f.remote), kind).toEqual(["main"]);
        if (kind === "exec") expect(failedWith(result)).toBe("integrity: resume-unexpected-mode");
      }
    });

    it("R-5d: a branch commit by someone else, or with another message, is refused (bot identity and handler message required)", async () => {
      const f = await makeFixture();
      await precreate(f, { [TODAY_DIGEST]: DIGEST_BYTES }, false);
      expect(failedWith(await runExact(f))).toBe("integrity: resume-unexpected-commit-metadata");
      const g = await makeFixture();
      await precreate(g, { [TODAY_DIGEST]: DIGEST_BYTES }, true, "agent says hello");
      expect(failedWith(await runExact(g))).toBe("integrity: resume-unexpected-commit-metadata");
      expect(await remoteBranches(f.remote)).toEqual(["main"]);
      expect(await remoteBranches(g.remote)).toEqual(["main"]);
    });

    it("R-5e: the gate runs before EVERY push in exactPaths mode — it is not conditioned on the resume arm", async () => {
      const src = await readFile(join(__dirname, "../../../server/inngest/functions/_cron-safe-commit.ts"), "utf-8");
      const start = src.indexOf("-- 8.5.");
      const end = src.indexOf('await git(["push"', start);
      expect(start).toBeGreaterThan(-1);
      expect(end).toBeGreaterThan(start);
      const gate = src.slice(start, end);
      expect(gate).toMatch(/if \(exactMode\) \{\s*const unsafe = await pushTipReason\(/);
      expect(gate).not.toMatch(/resuming/);
    });

    it("R-5f (control): a genuine one-commit replay on the fetched tip still resumes and pushes", async () => {
      const f = await makeFixture();
      await precreate(f, { [TODAY_DIGEST]: DIGEST_BYTES });
      const result = await runExact(f);
      expect(result.status).toBe("committed");
      expect(result.status === "committed" && result.resumed).toBe(true);
      expect(await remoteBranches(f.remote)).toContain(BRANCH());
    });
  });

  // ---- (e) expectedContent is required ------------------------------------------------------

  describe("expectedContent is REQUIRED in exactPaths mode", () => {
    it("R-6: absent, empty, or not covering a staged path: refused before any git command; nothing is pushed", async () => {
      for (const expectedContent of [undefined, {}, { "knowledge-base/other.md": "x" }] as const) {
        const f = await makeFixture();
        await writeDigest(f);
        const cfg = { ...exactCfg(f) } as Record<string, unknown>;
        if (expectedContent === undefined) delete cfg.expectedContent;
        else cfg.expectedContent = expectedContent;
        const result = await safeCommitAndPr(cfg as never);
        expect(failedWith(result), JSON.stringify(expectedContent)).toBe("integrity: expected-content-missing");
        expect(await remoteBranches(f.remote)).toEqual(["main"]);
      }
    });
  });

  // ---- (f) planted config keys: the config is rewritten from nothing ------------------------

  describe("planted config keys (test-design P2-4: a denylist implementation must fail here)", () => {
    it("R-7: gpg signing, url.insteadOf, sshCommand, credential helper, include.path, aliases and a filter via include never run or redirect; the config keeps only [core] + remote.origin (+ the branch upstream)", async () => {
      const f = await makeFixture();
      const evilRemote = await bareRepo(f, "evil.git");
      const gpg = await script(f, "gpg");
      const cred = await script(f, "credential");
      const ssh = await script(f, "ssh");
      const aliasCmd = await script(f, "alias");
      const includedFilter = await script(f, "included-filter", "cat >/dev/null; echo ATTACKER_CHOSEN_TEXT");
      const included = join(f.root, "included.cfg");
      await writeFile(included, `[filter "y"]\n\tclean = ${includedFilter}\n\trequired = true\n`);
      const cfg = join(f.repo, ".git", "config");
      for (const [k, v] of [
        ["commit.gpgsign", "true"],
        ["gpg.program", gpg],
        ["credential.helper", `!${cred}`],
        ["core.sshCommand", ssh],
        ["alias.push", `!${aliasCmd}`],
        ["include.path", included],
        ["remote.origin.pushurl", evilRemote],
        ["url." + evilRemote + ".insteadOf", f.remote],
        ["core.editor", ssh],
        ["receive.denyCurrentBranch", "ignore"],
      ] as const) await cfgSet(cfg, k, v);
      await mkdir(join(f.repo, ".git", "info"), { recursive: true });
      await writeFile(join(f.repo, ".git", "info", "attributes"), "* filter=y\n");
      await writeDigest(f);

      const result = await runExact(f);

      expect(result.status).toBe("committed");
      for (const m of ["gpg", "credential", "ssh", "alias", "included-filter"]) {
        expect(existsSync(marker(f, m)), `planted ${m} ran`).toBe(false);
      }
      expect(await remoteBranches(evilRemote)).toEqual([]);
      const branch = result.status === "committed" ? result.branch : "";
      expect(await remoteBranches(f.remote)).toContain(branch);
      expect(await remoteGit(f, "show", `${branch}:${TODAY_DIGEST}`)).toBe(DIGEST_BYTES.trim());
      const after = await readFile(cfg, "utf-8");
      const sections = [...after.matchAll(/^\[([a-z]+)(?: "[^"]*")?\]/gim)].map((m) => m[1].toLowerCase());
      expect([...new Set(sections)].sort()).toEqual(expect.arrayContaining(["core", "remote"]));
      for (const s of new Set(sections)) expect(["core", "remote", "branch"], `unexpected config section [${s}]`).toContain(s);
      expect(after).not.toMatch(/gpg|insteadof|sshcommand|credential|include|alias|filter|pushurl/i);
    });
  });

  // ---- filter-free staging, each layer on its own -------------------------------------------

  describe("each hardening layer on its own (the rewrite masks them through safeCommitAndPr)", () => {
    it("R-8: staging hashes the file's own bytes with NO filter even when a filter is configured and selected by attributes", async () => {
      const f = await makeFixture();
      await writeDigest(f);
      const filter = await script(f, "filter", "cat >/dev/null; echo ATTACKER_CHOSEN_TEXT");
      await cfgSet(join(f.repo, ".git", "config"), "filter.x.clean", filter);
      await mkdir(join(f.repo, ".git", "info"), { recursive: true });
      await writeFile(join(f.repo, ".git", "info", "attributes"), "* filter=x\n");
      const git = (args: string[], env?: Record<string, string>) => __safeCommitInternals.runGit(f.repo, args, env);

      // Layer 1 alone (no sanitising): the blob is the file's own bytes whatever the filter
      // would have produced. (git's racy-clean index check can still EXECUTE a configured
      // clean filter at index-write time and discard its output — that execution is what the
      // sanitiser below removes, so it is asserted with the sanitiser, not without it.)
      const refused = await __safeCommitInternals.stageExactPaths(f.repo, git, [TODAY_DIGEST]);
      expect(refused).toBeNull();
      expect((await git(["cat-file", "blob", `:${TODAY_DIGEST}`])).stdout).toBe(DIGEST_BYTES);

      // Layers 1+2 (the production order): after sanitising, NO filter process runs at all.
      await rm(marker(f, "filter"), { force: true });
      expect(await __safeCommitInternals.sanitizeWorkspaceGit(f.repo, git)).toBeNull();
      expect(await __safeCommitInternals.stageExactPaths(f.repo, git, [TODAY_DIGEST])).toBeNull();
      expect(existsSync(marker(f, "filter")), "the clean filter ran during staging").toBe(false);
      expect((await git(["cat-file", "blob", `:${TODAY_DIGEST}`])).stdout).toBe(DIGEST_BYTES);
    });

    it("R-8b: the staged mode is 100644 even for an executable file on disk", async () => {
      const f = await makeFixture();
      await writeDigest(f);
      await chmod(join(f.repo, TODAY_DIGEST), 0o755);
      const result = await runExact(f);
      expect(result.status).toBe("committed");
      const branch = result.status === "committed" ? result.branch : "";
      expect(await remoteGit(f, "ls-tree", branch, "--", TODAY_DIGEST)).toMatch(/^100644 blob /);
    });

    it("R-8c: `-c core.attributesFile=/dev/null`, `core.fsmonitor=false` and `core.hooksPath=/dev/null` each hold on their own", async () => {
      const f = await makeFixture();
      await writeDigest(f);
      const attrs = join(f.root, "attrs");
      await writeFile(attrs, "* filter=x\n");
      const filter = await script(f, "filter", "cat >/dev/null; echo ATTACKER_CHOSEN_TEXT");
      const fsm = await script(f, "fsmonitor");
      const hooksDir = join(f.root, "hooks");
      await mkdir(hooksDir);
      for (const h of ["pre-commit", "post-commit", "commit-msg"]) {
        await writeFile(join(hooksDir, h), `#!/bin/sh\ntouch '${marker(f, `hook-${h}`)}'\nexit 0\n`);
        await chmod(join(hooksDir, h), 0o755);
      }
      const cfg = join(f.repo, ".git", "config");
      for (const [k, v] of [
        ["core.attributesFile", attrs],
        ["filter.x.clean", filter],
        ["core.fsmonitor", fsm],
        ["core.hooksPath", hooksDir],
      ] as const) await cfgSet(cfg, k, v);

      await __safeCommitInternals.runGit(f.repo, ["hash-object", "-w", "--", TODAY_DIGEST]);
      await __safeCommitInternals.runGit(f.repo, ["status", "--porcelain=v1"]);
      await __safeCommitInternals.runGit(f.repo, ["commit", "--allow-empty", "-m", "x"], BOT_ENV);

      expect(existsSync(marker(f, "filter")), "attributesFile layer").toBe(false);
      expect(existsSync(marker(f, "fsmonitor")), "fsmonitor layer").toBe(false);
      for (const h of ["pre-commit", "post-commit", "commit-msg"]) expect(existsSync(marker(f, `hook-${h}`)), h).toBe(false);
    });

    it("R-8d: a symlinked PARENT directory of the digest is refused (the final component is not the only link that can redirect the read)", async () => {
      const f = await makeFixture();
      const elsewhere = join(f.root, "elsewhere");
      await mkdir(elsewhere);
      await writeFile(join(elsewhere, "2026-06-10-digest.md"), DIGEST_BYTES);
      await mkdir(join(f.repo, "knowledge-base", "support"), { recursive: true });
      await symlink(elsewhere, join(f.repo, "knowledge-base", "support", "community"));
      const result = await runExact(f);
      // The scan sees the file through the link only as an untracked directory entry or not at all:
      // either way nothing is committed and nothing is pushed.
      expect(result.status === "committed").toBe(false);
      expect(await remoteBranches(f.remote)).toEqual(["main"]);
    });
  });

  // ---- multi-key expectedContent -----------------------------------------------------------

  // ---- round-2 verification: single origin URL, required expectedContent, every symlinked entry ----

  describe("round-2 verification gaps", () => {
    it("R-10 (N1): a planted SECOND remote.origin.url is refused — neither the fetch nor the push goes there", async () => {
      const f = await makeFixture();
      await writeDigest(f);
      const evil = await bareRepo(f, "evil-remote.git");
      await tgit(f.repo, "config", "--add", "remote.origin.url", evil);
      const result = await runExact(f);
      expect(failedWith(result)).toBe("integrity: config-rewrite-failed");
      expect(await remoteBranches(f.remote)).toEqual(["main"]);
      expect((await execFileP("git", ["--git-dir", evil, "for-each-ref"], { env: gitFixtureEnv(evil) })).stdout.trim()).toBe("");
    });

    it("R-11: an exactPaths run WITHOUT expectedContent is refused before anything is pushed (it has nothing to prove the commit is ours)", async () => {
      const f = await makeFixture();
      await writeDigest(f);
      const none = await runExact(f, { expectedContent: undefined });
      expect(failedWith(none)).toBe("integrity: expected-content-missing");
      const empty = await runExact(f, { expectedContent: {} });
      expect(failedWith(empty)).toBe("integrity: expected-content-missing");
      expect(await remoteBranches(f.remote)).toEqual(["main"]);
    });

    it("R-12: a resume branch whose commit RENAMES a tracked file onto the digest path is refused (rename pairing is a delete + add)", async () => {
      const f = await makeFixture();
      const seed = Object.keys(SEED_FILES)[0];
      await tgit(f.repo, "checkout", "-b", BRANCH());
      await mkdir(join(f.repo, DIGEST_DIR), { recursive: true });
      await tgit(f.repo, "mv", seed, TODAY_DIGEST);
      await writeFile(join(f.repo, TODAY_DIGEST), DIGEST_BYTES);
      await tgit(f.repo, "add", "--", TODAY_DIGEST);
      await execFileP("git", ["commit", "-m", "fix(test): fixture commit"], {
        cwd: f.repo,
        env: { ...gitFixtureEnv(f.repo), ...SEED_ENV, ...BOT_ENV },
      });
      const result = await runExact(f);
      expect(result.status).toBe("failed");
      expect(await remoteBranches(f.remote)).toEqual(["main"]);
    });

    const SYMLINK_ENTRIES: readonly string[] = [
      "config", "info", "hooks", "objects", "objects/info", "refs", "refs/replace", "HEAD", "index", "packed-refs", "shallow",
    ];
    it.each(SYMLINK_ENTRIES)("R-4b: `.git/%s` as a symlink is refused and the link target is untouched", async (entry) => {
      const f = await makeFixture();
      await writeDigest(f);
      const victim = join(f.root, `victim-${entry.replace(/\//g, "_")}`);
      await writeFile(victim, "VICTIM\n");
      const at = join(f.repo, ".git", entry);
      await mkdir(dirname(at), { recursive: true });
      await rm(at, { recursive: true, force: true });
      await symlink(victim, at);
      const result = await runExact(f);
      expect(failedWith(result)).toBe("integrity: git-entry-symlink");
      expect(await readFile(victim, "utf-8")).toBe("VICTIM\n");
      expect(await remoteBranches(f.remote)).toEqual(["main"]);
    });
  });

  describe("expectedContent is compared for EVERY key", () => {
    const SECOND = `${DIGEST_DIR}2026-06-10-second.md`;
    const twoPaths = (f: Fixture) => ({
      ...exactCfg(f),
      exactPaths: [TODAY_DIGEST, SECOND] as readonly string[],
    });

    it("R-9: two exact paths with both byte-correct commit together; a wrong SECOND key refuses (a first-key-only compare would pass it)", async () => {
      const f = await makeFixture();
      await writeDigest(f);
      await writeFile(join(f.repo, SECOND), "second digest\n");
      const ok = await safeCommitAndPr({ ...twoPaths(f), expectedContent: { [TODAY_DIGEST]: DIGEST_BYTES, [SECOND]: "second digest\n" } } as never);
      expect(ok.status).toBe("committed");
      expect(ok.status === "committed" && ok.fileCount).toBe(2);

      const g = await makeFixture();
      await writeDigest(g);
      await writeFile(join(g.repo, SECOND), "second digest, tampered\n");
      const bad = await safeCommitAndPr({ ...twoPaths(g), expectedContent: { [TODAY_DIGEST]: DIGEST_BYTES, [SECOND]: "second digest\n" } } as never);
      expect(failedWith(bad)).toBe("integrity: index-content-mismatch");
      expect(await remoteBranches(g.remote)).toEqual(["main"]);

      // ...and a wrong FIRST key, symmetrically.
      const h = await makeFixture();
      await writeDigest(h, "tampered first\n");
      await writeFile(join(h.repo, SECOND), "second digest\n");
      const bad1 = await safeCommitAndPr({ ...twoPaths(h), expectedContent: { [TODAY_DIGEST]: DIGEST_BYTES, [SECOND]: "second digest\n" } } as never);
      expect(failedWith(bad1)).toBe("integrity: index-content-mismatch");
    });

    it("R-9b: the same on the resume arm — a branch whose second blob is wrong is not pushed", async () => {
      const f = await makeFixture();
      await precreate(f, { [TODAY_DIGEST]: DIGEST_BYTES, [SECOND]: "second digest, tampered\n" });
      const result = await safeCommitAndPr({ ...twoPaths(f), expectedContent: { [TODAY_DIGEST]: DIGEST_BYTES, [SECOND]: "second digest\n" } } as never);
      expect(failedWith(result)).toBe("integrity: resume-content-mismatch");
      expect(await remoteBranches(f.remote)).toEqual(["main"]);
    });
  });
});
