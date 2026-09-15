// #8180/#8182/#8183 — handler-driven coverage for the re-vendor write, dedup
// completeness, and issue-body metadata enrichment.
//
// SEPARATE test file (NOT folded into cron-content-vendor-drift.test.ts): that
// suite imports the REAL module for source-shape/import-time smoke tests, and
// vitest hoists vi.mock to the top of a file — adding these mocks there would
// clobber every existing assertion. Convention per
// cron-community-monitor-heartbeat.test.ts.
//
// The substrate is exercised for real wherever it is safe: `git clone` runs
// against a `file://` fixture repo built per test, the NOTICE parser and the
// drift classifier are the REAL bash scripts copied into the fixture, `git
// merge-file`/`hash-object` are real, and safeCommitAndPr runs the REAL helper
// — real `git status`, real `git add`/`commit`, real `git push` back into the
// disposable fixture remote. Only the GitHub API is mocked (route-table
// octokit), plus the non-git substrate seams (token mint, clone URL, workspace
// root, heartbeat, Sentry mirror, liveness marker).

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { execSync } from "node:child_process";
import {
  cpSync,
  mkdirSync,
  mkdtempSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { createHash } from "node:crypto";
import { gitFixtureEnv } from "../../../../../plugins/soleur/test/lib/git-fixture-env";

vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

// ---------------------------------------------------------------------------
// Hoisted spies + per-test state
// ---------------------------------------------------------------------------

const state = vi.hoisted(() => ({
  cloneUrl: "",
  workspaceRoot: "",
  // Octokit route-table inputs, reset per test.
  repoMeta: null as null | {
    full_name: string;
    archived: boolean;
    default_branch: string;
  },
  repoMetaThrows: false,
  newPinnedCommit: "",
  contents: {} as Record<string, { sha: string; content: string }>,
  blobs: {} as Record<string, string>,
  // Paginated enumeration fixtures, keyed by 1-based page number. The dedup
  // sites page via fetchAllPages — a page <100 items ends the walk.
  searchIssuePages: {} as Record<number, { title: string }[]>,
  pullPages: {} as Record<number, { head: { ref: string } }[]>,
  // Recorded API traffic.
  issues: [] as Record<string, unknown>[],
  pulls: [] as Record<string, unknown>[],
  labelPosts: [] as Record<string, unknown>[],
  merges: [] as Record<string, unknown>[],
  realSafeCommit: null as null | ((cfg: unknown) => Promise<unknown>),
  forceNoChanges: false,
}));

const {
  reportSilentFallbackSpy,
  octokitRequestSpy,
  octokitGraphqlSpy,
  postHeartbeatSpy,
  safeCommitAndPrSpy,
} = vi.hoisted(() => ({
  reportSilentFallbackSpy: vi.fn(),
  octokitRequestSpy: vi.fn(),
  octokitGraphqlSpy: vi.fn(),
  postHeartbeatSpy: vi.fn(async (_args?: unknown) => {}),
  safeCommitAndPrSpy: vi.fn(),
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: (...a: unknown[]) => reportSilentFallbackSpy(...a),
  warnSilentFallback: vi.fn(),
  mirrorWarnWithDebounce: vi.fn(),
}));

vi.mock("@/server/inngest/client", () => ({
  inngest: { createFunction: vi.fn(), send: vi.fn() },
}));

vi.mock("@/server/cron-liveness-marker", () => ({
  emitCronDigestLiveness: vi.fn(),
  emitCommunityDigestFile: vi.fn(),
  emitCronPersistResult: vi.fn(),
  emitCronPersistSkipped: vi.fn(),
  emitCronTier2Deferred: vi.fn(),
  emitCronDedupSkip: vi.fn(),
}));

vi.mock("@octokit/core", () => ({
  Octokit: vi.fn().mockImplementation(function (
    this: Record<string, unknown>,
  ) {
    this.request = octokitRequestSpy;
    this.graphql = octokitGraphqlSpy;
  }),
}));

// safeCommitAndPr is the REAL helper by default — it runs the genuine git
// status/add/commit/push pipeline against the file:// fixture remote, so a
// clean tree really returns `no-changes`. `state.forceNoChanges` overrides
// that for the observability test.
vi.mock("@/server/inngest/functions/_cron-safe-commit", async (importOriginal) => {
  const actual =
    await importOriginal<
      typeof import("@/server/inngest/functions/_cron-safe-commit")
    >();
  state.realSafeCommit = actual.safeCommitAndPr as (
    cfg: unknown,
  ) => Promise<unknown>;
  return {
    ...actual,
    safeCommitAndPr: (cfg: unknown) =>
      state.forceNoChanges
        ? { status: "no-changes" }
        : safeCommitAndPrSpy(cfg),
  };
});

vi.mock("@/server/inngest/functions/_cron-shared", async (importOriginal) => {
  const actual =
    await importOriginal<
      typeof import("@/server/inngest/functions/_cron-shared")
    >();
  return {
    ...actual,
    mintInstallationToken: vi.fn(async () => "ghs_test_token"),
    buildAuthenticatedCloneUrl: vi.fn(() => state.cloneUrl),
    resolveCronWorkspaceRoot: vi.fn(() => state.workspaceRoot),
    warnIfCronWorkspaceLowOnDisk: vi.fn(async () => {}),
    postSentryHeartbeat: (args: unknown) => postHeartbeatSpy(args),
  };
});

import { cronContentVendorDriftHandler } from "@/server/inngest/functions/cron-content-vendor-drift";

// ---------------------------------------------------------------------------
// Fixture construction
// ---------------------------------------------------------------------------

const REPO_ROOT = resolve(__dirname, "../../../../..");
const SCRIPTS_DIR = join(
  REPO_ROOT,
  "plugins/soleur/skills/gdpr-gate/scripts",
);
const SKILL_DIR = "plugins/soleur/skills/gdpr-gate";

/** `git hash-object --no-filters` without a repo: sha1("blob <len>\0" + bytes). */
function blobSha(content: string): string {
  const buf = Buffer.from(content, "utf8");
  return createHash("sha1")
    .update(`blob ${buf.length}\0`)
    .update(buf)
    .digest("hex");
}

function git(dir: string, args: string): string {
  return execSync(`git ${args}`, {
    cwd: dir,
    encoding: "utf8",
    env: gitFixtureEnv(dir),
  }).trim();
}

interface FixtureFile {
  /** NOTICE-relative path, e.g. references/alpha.md */
  lifted: string;
  /** Upstream repo path, e.g. rules/alpha.md — must NOT sit under `layers/`
   *  (the classifier's security regex matches `+++ b/.../layers/` and would
   *  route the fixture to the issue arm, not the PR arm under test). */
  upstream: string;
  /** Content pinned at `pinned-commit` (the merge base). */
  oldContent: string;
  /** Content currently committed in the fixture repo (local side of merge). */
  localContent: string;
  /** Content the upstream default branch serves now (other side of merge). */
  newContent: string;
}

const PINNED_COMMIT = "a".repeat(40);
const NEW_PINNED_COMMIT = "b".repeat(40);

/**
 * Build a disposable git remote the handler clones. The fixture carries the
 * REAL parser + classifier scripts so detection exercises the production
 * NOTICE contract end to end.
 */
function buildFixtureRepo(
  files: FixtureFile[],
  opts?: {
    lastVerified?: string;
    /** A second enrolled bundle (slug + files). Files are written
     * unchanged (upstream sha == pinned sha) so the sibling measures clean
     * unless its upstream contents are registered as drifted. */
    sibling?: { slug: string; files: FixtureFile[] };
  },
): string {
  const dir = mkdtempSync(join(tmpdir(), "vdrift-fixture-"));
  git(dir, "init -b main");
  for (const s of ["notice-frontmatter.sh", "vendor-drift-classify.sh"]) {
    const dest = join(dir, SKILL_DIR, "scripts", s);
    mkdirSync(dirname(dest), { recursive: true });
    cpSync(join(SCRIPTS_DIR, s), dest);
  }

  const writeBundle = (skillDir: string, bundleFiles: FixtureFile[]) => {
    const records = bundleFiles
      .map((f) => {
        const abs = join(dir, skillDir, f.lifted);
        mkdirSync(dirname(abs), { recursive: true });
        writeFileSync(abs, f.localContent, "utf8");
        return [
          `  - path: ${f.lifted}`,
          `    upstream-path: ${f.upstream}`,
          `    upstream-blob-sha: ${blobSha(f.oldContent)}`,
          `    local-blob-sha: ${blobSha(f.localContent)}`,
          "    status: active-verbatim",
        ].join("\n");
      })
      .join("\n");

    const notice = [
      "---",
      "upstream: github.com/acme/widgets",
      `pinned-commit: ${PINNED_COMMIT}`,
      `last-verified: ${opts?.lastVerified ?? "2026-01-01"}`,
      "registry: knowledge-base/engineering/policies/content-vendoring.md",
      "lifted-files:",
      records,
      "---",
      "",
      "# NOTICE",
      "",
    ].join("\n");
    mkdirSync(join(dir, skillDir), { recursive: true });
    writeFileSync(join(dir, skillDir, "NOTICE"), notice, "utf8");
  };

  writeBundle(SKILL_DIR, files);
  if (opts?.sibling) {
    writeBundle(
      `plugins/soleur/skills/${opts.sibling.slug}`,
      opts.sibling.files,
    );
  }

  git(dir, "add -A");
  git(dir, "commit -m fixture");
  return dir;
}

/** Register the upstream side of the octokit route table for a fixture file. */
function registerUpstream(f: FixtureFile) {
  const newSha = blobSha(f.newContent);
  state.contents[f.upstream] = {
    sha: newSha,
    content: Buffer.from(f.newContent, "utf8").toString("base64"),
  };
  state.blobs[blobSha(f.oldContent)] = f.oldContent;
  state.blobs[newSha] = f.newContent;
}

const ALPHA: FixtureFile = {
  lifted: "references/alpha.md",
  upstream: "rules/alpha.md",
  oldContent: "alpha rule one\nalpha rule two\n",
  localContent:
    "<!-- lifted from acme/widgets (MIT) -->\n\nalpha rule one\nalpha rule two\n",
  newContent: "alpha rule one\nalpha rule two\nalpha rule three added\n",
};

const BETA_CLEAN: FixtureFile = {
  lifted: "references/beta.md",
  upstream: "rules/beta.md",
  oldContent: "beta intro\nbeta outro\n",
  localContent: "<!-- lifted -->\nbeta intro\nbeta outro\n",
  newContent: "beta intro\nbeta outro\nbeta appended upstream\n",
};

const BETA_CONFLICT: FixtureFile = {
  ...BETA_CLEAN,
  oldContent: "beta intro\nbeta shared line\nbeta outro\n",
  localContent: "beta intro\nbeta LOCAL edit\nbeta outro\n",
  newContent: "beta intro\nbeta UPSTREAM edit\nbeta outro\n",
};

// ---------------------------------------------------------------------------
// Octokit route table
// ---------------------------------------------------------------------------

function installOctokitRoutes() {
  octokitRequestSpy.mockImplementation(
    async (route: string, params?: Record<string, unknown>) => {
      switch (route) {
        case "GET /repos/{owner}/{repo}": {
          if (state.repoMetaThrows) {
            const e = new Error("503 upstream unreachable") as Error & {
              status?: number;
            };
            e.status = 503;
            throw e;
          }
          return { data: state.repoMeta };
        }
        case "GET /repos/{owner}/{repo}/commits/{ref}":
          return { data: { sha: state.newPinnedCommit } };
        case "GET /repos/{owner}/{repo}/contents/{path}": {
          const c = state.contents[params?.path as string];
          if (!c) {
            const e = new Error("Not Found") as Error & { status?: number };
            e.status = 404;
            throw e;
          }
          return { data: { ...c, encoding: "base64" } };
        }
        case "GET /repos/{owner}/{repo}/git/blobs/{file_sha}": {
          const b = state.blobs[params?.file_sha as string];
          if (b === undefined) {
            const e = new Error("Not Found") as Error & { status?: number };
            e.status = 404;
            throw e;
          }
          return {
            data: {
              content: Buffer.from(b, "utf8").toString("base64"),
              encoding: "base64",
            },
          };
        }
        case "GET /search/issues": {
          const page = (params?.page as number) ?? 1;
          const items = state.searchIssuePages[page] ?? [];
          return { data: { total_count: items.length, items } };
        }
        case "GET /repos/{owner}/{repo}/pulls": {
          const page = (params?.page as number) ?? 1;
          return { data: state.pullPages[page] ?? [] };
        }
        case "POST /repos/{owner}/{repo}/labels":
          return { data: {} };
        case "POST /repos/{owner}/{repo}/issues":
          state.issues.push(params ?? {});
          return { data: { number: 9001 } };
        case "POST /repos/{owner}/{repo}/pulls":
          state.pulls.push(params ?? {});
          return { data: { number: 4242, node_id: "PR_node_1" } };
        case "POST /repos/{owner}/{repo}/issues/{issue_number}/labels":
          state.labelPosts.push(params ?? {});
          return { data: {} };
        case "POST /repos/{owner}/{repo}/check-runs":
          return { data: {} };
        case "PUT /repos/{owner}/{repo}/pulls/{pull_number}/merge":
          state.merges.push(params ?? {});
          return { data: { merged: true } };
        default:
          throw new Error(
            `unmocked octokit route: ${route} ${JSON.stringify(params)}`,
          );
      }
    },
  );
}

// ---------------------------------------------------------------------------
// Step + logger harness
// ---------------------------------------------------------------------------

function makeStep(memo?: Map<string, unknown>) {
  const executed: string[] = [];
  return {
    executed,
    run: vi.fn(async (name: string, cb: () => Promise<unknown>) => {
      if (memo?.has(name)) return memo.get(name);
      const result = await cb();
      memo?.set(name, result);
      executed.push(name);
      return result;
    }),
  };
}

const logger = { info: vi.fn(), warn: vi.fn(), error: vi.fn() };

type HandlerArg = Parameters<typeof cronContentVendorDriftHandler>[0];
const invoke = (step: ReturnType<typeof makeStep>) =>
  cronContentVendorDriftHandler({
    step: step as unknown as HandlerArg["step"],
    logger: logger as unknown as HandlerArg["logger"],
  } as HandlerArg);

const fallbackOps = () =>
  reportSilentFallbackSpy.mock.calls.map(
    (c) => (c[1] as { op?: string })?.op,
  );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

let fixtureDir = "";

beforeEach(() => {
  vi.clearAllMocks();
  state.repoMeta = {
    full_name: "acme/widgets",
    archived: false,
    default_branch: "main",
  };
  state.repoMetaThrows = false;
  state.newPinnedCommit = NEW_PINNED_COMMIT;
  state.contents = {};
  state.blobs = {};
  state.searchIssuePages = {};
  state.pullPages = {};
  state.issues = [];
  state.pulls = [];
  state.labelPosts = [];
  state.merges = [];
  state.forceNoChanges = false;
  state.workspaceRoot = mkdtempSync(join(tmpdir(), "vdrift-ws-"));
  installOctokitRoutes();
  safeCommitAndPrSpy.mockImplementation((cfg: unknown) =>
    state.realSafeCommit!(cfg),
  );
});

afterEach(() => {
  if (fixtureDir) rmSync(fixtureDir, { recursive: true, force: true });
  fixtureDir = "";
  if (state.workspaceRoot)
    rmSync(state.workspaceRoot, { recursive: true, force: true });
});

describe("cron-content-vendor-drift — re-vendor write (#8180)", () => {
  it("two drifted files, clean merges → real PR carrying merged bytes + bumped NOTICE", async () => {
    const files = [ALPHA, BETA_CLEAN];
    fixtureDir = buildFixtureRepo(files, {
      lastVerified: new Date().toISOString().slice(0, 10),
    });
    state.cloneUrl = `file://${fixtureDir}`;
    files.forEach(registerUpstream);

    const step = makeStep();
    const res = await invoke(step);

    // Route + steps.
    expect(step.executed).toContain("detect-drift-gdpr-gate");
    expect(step.executed).toContain("safe-commit-pr-gdpr-gate");
    expect(res.bundles?.[0]?.route).toBe("pr");

    // safeCommitAndPr really committed + pushed + opened + merged a PR.
    expect(state.pulls.length).toBe(1);
    expect(state.merges.length).toBe(1);
    expect(state.pulls[0].head).toMatch(/^ci\/content-vendor-drift-/);
    expect(String(state.pulls[0].body)).toContain("Per-file merge status");
    expect(String(state.pulls[0].body)).toContain(
      "`references/alpha.md` — merged",
    );
    expect(String(state.pulls[0].body)).toContain(
      "`references/beta.md` — merged",
    );
    expect(state.labelPosts[0].labels).toContain("vendor/pin-drift");
    expect(state.labelPosts[0].labels).not.toContain("needs-human-review");

    // The pushed branch in the fixture remote carries the merged bytes.
    const branch = String(state.pulls[0].head);
    const mergedAlpha = git(
      fixtureDir,
      `show ${branch}:${SKILL_DIR}/references/alpha.md`,
    );
    expect(mergedAlpha).toContain("alpha rule three added");
    expect(mergedAlpha).toContain("lifted from acme/widgets");
    const mergedBeta = git(
      fixtureDir,
      `show ${branch}:${SKILL_DIR}/references/beta.md`,
    );
    expect(mergedBeta).toContain("beta appended upstream");

    // NOTICE on the branch: every drifted record rewritten + pin/date bumped.
    const notice = git(fixtureDir, `show ${branch}:${SKILL_DIR}/NOTICE`);
    expect(notice).toContain(`pinned-commit: ${NEW_PINNED_COMMIT}`);
    expect(notice).toMatch(/last-verified: \d{4}-\d{2}-\d{2}/);
    expect(notice).not.toContain(`last-verified: 2026-01-01`);
    for (const f of files) {
      expect(notice).toContain(`upstream-blob-sha: ${blobSha(f.newContent)}`);
      expect(notice).not.toContain(`upstream-blob-sha: ${blobSha(f.oldContent)}`);
    }

    // no-changes is genuinely unreachable here.
    expect(fallbackOps()).not.toContain("safe-commit-no-changes");
  });

  it("conflicted merge → create-only PR + needs-human-review + markers in the pushed file", async () => {
    const files = [ALPHA, BETA_CONFLICT];
    fixtureDir = buildFixtureRepo(files, {
      lastVerified: new Date().toISOString().slice(0, 10),
    });
    state.cloneUrl = `file://${fixtureDir}`;
    files.forEach(registerUpstream);

    const res = await invoke(makeStep());
    expect(res.bundles?.[0]?.route).toBe("pr");

    expect(state.pulls.length).toBe(1);
    // mergeMode "none" — no direct merge, no auto-merge arm attempted.
    expect(state.merges.length).toBe(0);
    expect(octokitGraphqlSpy).not.toHaveBeenCalled();
    expect(state.labelPosts[0].labels).toContain("needs-human-review");
    expect(String(state.pulls[0].body)).toContain(
      "`references/beta.md` — conflicted",
    );
    expect(String(state.pulls[0].body)).toContain("runbook");

    const branch = String(state.pulls[0].head);
    const mergedBeta = git(
      fixtureDir,
      `show ${branch}:${SKILL_DIR}/references/beta.md`,
    );
    expect(mergedBeta).toContain("<<<<<<<");
    expect(mergedBeta).toContain(">>>>>>>");
    expect(mergedBeta).toContain("beta LOCAL edit");
    expect(mergedBeta).toContain("beta UPSTREAM edit");
  });

  it("safeCommitAndPr returning no-changes is reported, never read as success", async () => {
    state.forceNoChanges = true;
    const files = [ALPHA];
    fixtureDir = buildFixtureRepo(files, {
      lastVerified: new Date().toISOString().slice(0, 10),
    });
    state.cloneUrl = `file://${fixtureDir}`;
    files.forEach(registerUpstream);

    await invoke(makeStep());
    expect(state.pulls.length).toBe(0);
    expect(fallbackOps()).toContain("safe-commit-no-changes");
  });

  it("replay shape: memoized detect + fresh clean worktree still produces the write", async () => {
    // AC-2. Simulates an Inngest retry where detect-drift is memoized (its
    // side-effect-free result returned without re-executing) while
    // setup-workspace and safe-commit-pr re-execute on a CLEAN clone. If the
    // write ever moved back into detect, this run sees a clean tree and
    // returns no-changes — the #8180 failure, re-armed.
    const files = [ALPHA];
    fixtureDir = buildFixtureRepo(files, {
      lastVerified: new Date().toISOString().slice(0, 10),
    });
    state.cloneUrl = `file://${fixtureDir}`;
    files.forEach(registerUpstream);

    const memo = new Map<string, unknown>();
    await invoke(makeStep(memo));
    expect(state.pulls.length).toBe(1);

    memo.delete("setup-workspace");
    memo.delete("safe-commit-pr-gdpr-gate");
    const step2 = makeStep(memo);
    await invoke(step2);
    expect(step2.executed).not.toContain("detect-drift-gdpr-gate");
    expect(step2.executed).toContain("safe-commit-pr-gdpr-gate");
    expect(state.pulls.length).toBe(2);
    expect(fallbackOps()).not.toContain("safe-commit-no-changes");
  });
});

describe("cron-content-vendor-drift — dedup completeness (#8182)", () => {
  it("an open drift PR on page 2 of the pulls enumeration suppresses the route", async () => {
    const files = [ALPHA];
    fixtureDir = buildFixtureRepo(files);
    state.cloneUrl = `file://${fixtureDir}`;
    files.forEach(registerUpstream);
    // The regression shape: a bounded page-1 scan reads this as "no match".
    // Page 1 is full (100 refs) so a page-1-only reader never sees the match.
    state.pullPages = {
      1: Array.from({ length: 100 }, (_, i) => ({
        head: { ref: `ci/unrelated-${i}` },
      })),
      2: [
        {
          head: {
            ref: "ci/content-vendor-drift-gdpr-gate-2026-09-08T11-17-00",
          },
        },
      ],
    };

    const step = makeStep();
    const res = await invoke(step);

    expect(res.bundles?.[0]?.status).toBe("skipped-open-pr");
    expect(step.executed).not.toContain("safe-commit-pr-gdpr-gate");
    expect(state.pulls.length).toBe(0);
  });

  it("an existing security-drift issue on page 2 of the search enumeration suppresses filing", async () => {
    const files = [ALPHA];
    fixtureDir = buildFixtureRepo(files);
    state.cloneUrl = `file://${fixtureDir}`;
    // Archived upstream routes to issue; per-file SHAs all compare same.
    state.repoMeta = {
      full_name: "acme/widgets",
      archived: true,
      default_branch: "main",
    };
    for (const f of files) {
      state.contents[f.upstream] = {
        sha: blobSha(f.oldContent),
        content: Buffer.from(f.oldContent, "utf8").toString("base64"),
      };
    }
    state.searchIssuePages = {
      1: Array.from({ length: 100 }, (_, i) => ({
        title: `unrelated issue ${i}`,
      })),
      2: [
        {
          title:
            "[vendor-drift][gdpr-gate] security-relevant drift on 2026-09-08 (classifier rc=12)",
        },
      ],
    };

    const res = await invoke(makeStep());
    expect(res.bundles?.[0]?.route).toBe("issue");
    expect(state.issues.length).toBe(0);
  });

  it("a sibling bundle's open PR does NOT suppress this bundle's route", async () => {
    // Two enrolled bundles — classifyBranchOwner can only attribute the
    // sibling's ref when the sibling slug is actually enrolled.
    const siblingFile: FixtureFile = {
      lifted: "references/gamma.md",
      upstream: "rules/gamma.md",
      oldContent: "gamma unchanged\n",
      localContent: "gamma unchanged\n",
      newContent: "gamma unchanged\n",
    };
    const files = [ALPHA];
    fixtureDir = buildFixtureRepo(files, {
      lastVerified: new Date().toISOString().slice(0, 10),
      sibling: { slug: "legal-generate", files: [siblingFile] },
    });
    state.cloneUrl = `file://${fixtureDir}`;
    files.forEach(registerUpstream);
    // The sibling measures clean: contents serves its pinned sha.
    state.contents[siblingFile.upstream] = {
      sha: blobSha(siblingFile.oldContent),
      content: Buffer.from(siblingFile.oldContent, "utf8").toString("base64"),
    };
    // The open PR belongs to the sibling's branch namespace — the
    // client-side classifyBranchOwner must not let it mask gdpr-gate.
    state.pullPages = {
      1: [
        {
          head: {
            ref: "ci/content-vendor-drift-legal-generate-2026-09-08T11-17-00",
          },
        },
      ],
    };

    const res = await invoke(makeStep());
    const gdpr = res.bundles?.find((b) => b.slug === "gdpr-gate");
    expect(gdpr?.route).toBe("pr");
    expect(
      state.pulls.some((p) =>
        String(p.head).startsWith("ci/content-vendor-drift-gdpr-gate-"),
      ),
    ).toBe(true);
  });
});

describe("cron-content-vendor-drift — issue-body repo metadata (#8183)", () => {
  function archivedRoute() {
    const files = [ALPHA];
    fixtureDir = buildFixtureRepo(files);
    state.cloneUrl = `file://${fixtureDir}`;
    state.contents[ALPHA.upstream] = {
      sha: blobSha(ALPHA.oldContent),
      content: Buffer.from(ALPHA.oldContent, "utf8").toString("base64"),
    };
  }

  it("archived exit-12 issue renders full_name/archived/default_branch + repo state", async () => {
    archivedRoute();
    state.repoMeta = {
      full_name: "acme/widgets",
      archived: true,
      default_branch: "main",
    };

    const res = await invoke(makeStep());
    expect(res.bundles?.[0]?.route).toBe("issue");
    expect(state.issues.length).toBe(1);
    const body = String(state.issues[0].body);
    expect(body).toContain("## Upstream repository metadata");
    expect(body).toContain("**full_name:** `acme/widgets`");
    expect(body).toContain("**archived:** `true`");
    expect(body).toContain("**default_branch:** `main`");
    expect(body).toContain("**upstream_repo_state:** `archived`");
  });

  it("unreachable probe renders `?` fields — never affirmative facts", async () => {
    archivedRoute();
    state.repoMetaThrows = true;

    const res = await invoke(makeStep());
    expect(res.bundles?.[0]?.route).toBe("issue");
    expect(state.issues.length).toBe(1);
    const body = String(state.issues[0].body);
    expect(body).toContain("**full_name:** `?`");
    expect(body).toContain("**archived:** `?`");
    expect(body).toContain("**default_branch:** `?`");
    expect(body).toContain("**upstream_repo_state:** `unreachable`");
    expect(body).toContain("probe failed");
    // The bundle-identity line legitimately names the configured upstream;
    // what must NOT render is affirmative probed metadata.
    expect(body).not.toContain("**full_name:** `acme/widgets`");
    expect(body).not.toContain("**archived:** `true`");
  });
});
