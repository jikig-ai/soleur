// WikiSkill Phase 2 (#10550) -- the DRY RENDER: every CI-red surface a new skill touches, run against a
// synthetic copy of the real tree with a created skill injected.
//
// PROPERTY: the create arm's output is mergeable as drafted. Rendering the six-path set with the REAL gates (the real
// scanner, the real README sync, the real content collector) and then running the repository's own checks over the
// result leaves every one of them green, and the checks are not vacuous (the injected skill is visible to them).
//
// ASSEMBLY: a copy of the tracked tree in a temp directory (tar of `git ls-files`, then its own `git init`), the
// REAL `runCreateProposeStep` (model call stubbed) and `runCreatePersistStep` (commit helper stubbed, everything
// else real) driven against it. The six committed paths are then materialized from the very `expectedContent` that
// `safeCommitAndPr` would stage, and the surfaces CI runs on a skill-adding PR are executed there:
//   plugins/soleur/test/components.test.ts        description budget, frontmatter, reference-path lint over skills/**/*.md
//   plugins/soleur/test/cursor-name-map.test.ts   + `sync-cursor-name-map.ts --check`   the Cursor stub, byte for byte
//   plugins/soleur/test/grok-harness-invoke.test.ts   the canonical Grok block in every skill
//   plugins/soleur/test/invocation-axis.test.ts       skills/**/*.md invocation-axis census
//   plugins/soleur/test/harness-parity-tree.test.ts   ADR-226 component-reference census
//   scripts/sync-readme-counts.sh --check         lint-bot-statuses
//   plugins/soleur/docs/_data/skills.js           the docs loader (an unmapped skill must load as Uncategorized)
//   skill-security-scan                           offline, both files, via the gate (the verdict is read, not assumed)
//   markdownlint                                  the repo's pinned binary and config, when present
// ANCHOR: these are the repository's own checks, run unmodified; this suite adds none of its own verdicts.
import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";
import { spawnSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";

vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});
const remote = vi.hoisted(() => ({ url: "" }));
vi.mock("@/server/observability", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/observability")>()),
  reportSilentFallback: vi.fn(),
}));
// Step B refreshes the clone from `origin` (R5): the copy gets a local bare remote instead of the real GitHub URL.
vi.mock("@/server/inngest/functions/_cron-shared", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/inngest/functions/_cron-shared")>()),
  buildAuthenticatedCloneUrl: () => remote.url,
}));

import { PLAIN_ORIGIN_URL, runCreatePersistStep, runCreateProposeStep, type CreateVerdictCreate } from "@/server/compound-promote-create-arm";
import {
  PROMOTION_LOG_PATH,
  countDescriptionWords,
  createPathList,
  proposalOverlapText,
  rankOverlap,
} from "@/server/compound-promote-create";
import type { PatternPage } from "@/server/compound-promote-patterns";
import { gitFixture } from "../../../../plugins/soleur/test/lib/git-fixture-env";

const APP_ROOT = join(__dirname, "..", "..");
const REPO_ROOT = join(APP_ROOT, "..", "..");
const FIX = join(__dirname, "..", "fixtures", "compound-promote-create");
const PROPOSAL = JSON.parse(readFileSync(join(FIX, "proposal.json"), "utf8")) as Record<string, unknown>;
const SLUG = String(PROPOSAL.slug);
const PATTERN: PatternPage = {
  slug: String(PROPOSAL.pattern_slug), title: "Synthetic retry pattern", summary: "Synthetic summary.", status: "open", openedOn: "2026-10-01", tags: ["retry"],
  evidence: [1, 2, 3, 4, 5].map((n) => `knowledge-base/project/learnings/2026-10-0${n}-synthetic-${n}.md`), requiredReading: false,
};
const BUN_SUITES = [
  "plugins/soleur/test/components.test.ts",
  "plugins/soleur/test/cursor-name-map.test.ts",
  "plugins/soleur/test/grok-harness-invoke.test.ts",
  "plugins/soleur/test/invocation-axis.test.ts",
  "plugins/soleur/test/harness-parity-tree.test.ts",
];

let tree = "";
const remotes: string[] = [];
let committed: { exactPaths: readonly string[]; expectedContent: Record<string, string> } | null = null;
let baselinePass = 0;
let injectedPass = 0;
let injectedFail = 0;
let injectedStatus = -1;
let verdict: CreateVerdictCreate | null = null;
let persistResult: unknown = null;

const cleanEnv = (): NodeJS.ProcessEnv => {
  const env: Record<string, string> = {};
  for (const [k, v] of Object.entries(process.env)) if (!k.startsWith("GIT_") && v !== undefined) env[k] = v;
  return env as NodeJS.ProcessEnv;
};

function sh(cmd: string, args: string[], cwd: string, timeout = 120_000) {
  return spawnSync(cmd, args, { cwd, env: cleanEnv(), encoding: "utf8", timeout, maxBuffer: 64 * 1024 * 1024 });
}

function bunTest(): { status: number; pass: number; fail: number; out: string } {
  const r = sh("bun", ["test", ...BUN_SUITES], tree, 150_000);
  const out = `${r.stdout ?? ""}\n${r.stderr ?? ""}`;
  const pass = Number(/\n\s*(\d+) pass\b/.exec(out)?.[1] ?? -1);
  const fail = Number(/\n\s*(\d+) fail\b/.exec(out)?.[1] ?? -1);
  return { status: r.status ?? -1, pass, fail, out };
}

beforeAll(async () => {
  // A missing capability is a FAILURE, never a silent skip: the suite proves a property of the whole tree.
  expect(sh("bun", ["--version"], REPO_ROOT).status, "bun must be on PATH (ci.yml test-webplat sets it up)").toBe(0);
  tree = mkdtempSync(join(tmpdir(), "create-dry-render-"));
  const copy = sh(
    "bash",
    ["-c", 'git -C "$1" ls-files -z | tar --null --ignore-failed-read -C "$1" -T - -cf - 2>/dev/null | tar -x -C "$2"', "_", REPO_ROOT, tree],
    REPO_ROOT,
  );
  expect(copy.status, copy.stderr).toBe(0);
  // The bun suites import `yaml` and friends; the app's node_modules carries them (the repo root's may be absent in CI).
  symlinkSync(join(APP_ROOT, "node_modules"), join(tree, "node_modules"));
  const git = gitFixture(tree);
  git(["init", "-q", "-b", "main", "."]);
  git(["add", "-A"]);
  git(["commit", "-qm", "baseline"]);
  const bare = mkdtempSync(join(tmpdir(), "create-dry-render-remote-"));
  remotes.push(bare);
  expect(sh("git", ["clone", "-q", "--bare", tree, bare], REPO_ROOT).status).toBe(0);
  remote.url = `file://${bare}`;
  git(["remote", "add", "origin", remote.url]);

  // Baseline: the repository's own checks pass on the unmodified copy (otherwise the injected run proves nothing).
  const base = bunTest();
  expect(base.fail, base.out.slice(-2000)).toBe(0);
  expect(base.status).toBe(0);
  baselinePass = base.pass;

  // Step A on the REAL tree: real skill list, real budget counter, real cap; only the model is stubbed.
  const counted = countDescriptionWords(join(tree, "plugins", "soleur"));
  if (!counted.ok) throw new Error(`counter: ${counted.detail}`);
  const nearest = rankOverlap(
    proposalOverlapText({ slug: SLUG, description: String(PROPOSAL.description), when_to_use: PROPOSAL.when_to_use as string[] }),
    counted.records,
  )[0].name;
  const proposal = { ...PROPOSAL, nearest_skill: nearest };
  const proposed = await runCreateProposeStep({
    repoRoot: tree,
    octokit: { request: async () => ({ data: [] }) } as never,
    patterns: [PATTERN],
    ledgerEntries: [],
    runStartedAt: "2026-10-26T10:00:00.000Z",
    capLeft: 1,
    apiKey: "k",
    runId: "DRY",
    scanOpenPrPaths: async () => ({ paths: [], incomplete: null }),
    post: (async () => ({ text: JSON.stringify(proposal), stopReason: "end_turn" })) as never,
  });
  if (proposed.kind !== "create") throw new Error(`step A did not create: ${JSON.stringify(proposed)}`);
  verdict = proposed;

  // Step B: real render, real scan, real README sync, real collector; only the commit helper is a double.
  persistResult = await runCreatePersistStep({
    repoRoot: tree,
    installationToken: "t",
    runStartedAt: "2026-10-26T10:00:00.000Z",
    octokit: { request: async () => ({ data: [] }), graphql: async () => ({}) } as never,
    logger: { info: () => {}, warn: () => {}, error: () => {} },
    verdict: proposed,
    patterns: [PATTERN],
    safeCommit: (async (cfg: { exactPaths: readonly string[]; expectedContent: Record<string, string> }) => {
      committed = { exactPaths: cfg.exactPaths, expectedContent: cfg.expectedContent };
      return { status: "committed", prNumber: 1, branch: "b", fileCount: 6, deletionCount: 0 };
    }) as never,
  });
  if (committed === null) throw new Error(`step B did not reach the commit: ${JSON.stringify(persistResult)}`);

  // Materialize exactly the bytes the commit helper would stage, then stage them (the suites read `git ls-files`).
  const c = committed as { exactPaths: readonly string[]; expectedContent: Record<string, string> };
  for (const p of c.exactPaths) {
    mkdirSync(dirname(join(tree, p)), { recursive: true });
    writeFileSync(join(tree, p), c.expectedContent[p]);
  }
  git(["add", "-A"]);

  const inj = bunTest();
  injectedPass = inj.pass;
  injectedFail = inj.fail;
  injectedStatus = inj.status;
  if (inj.fail !== 0) console.error(inj.out.slice(-3000));
}, 240_000);

afterAll(() => {
  if (tree) rmSync(tree, { recursive: true, force: true });
  for (const r of remotes) rmSync(r, { recursive: true, force: true });
});

describe("the real gates passed on the real tree", () => {
  it("step B reached the commit with the closed six-path set and the rendered bytes", () => {
    expect(persistResult).toEqual({ kind: "opened", pr: 1 });
    const c = committed as unknown as { exactPaths: readonly string[]; expectedContent: Record<string, string> };
    expect(c.exactPaths).toEqual(createPathList(SLUG));
    expect(Object.keys(c.expectedContent).sort()).toEqual([...createPathList(SLUG)].sort());
    expect(c.expectedContent[`plugins/soleur/skills/${SLUG}/SKILL.md`]).toMatch(/^---\nname: http-retry-backoff\n/);
  });

  it("R4: the clone's origin is the tokenless URL after the step (the token never outlives it on disk)", () => {
    expect(sh("git", ["config", "remote.origin.url"], tree).stdout.trim()).toBe(PLAIN_ORIGIN_URL);
  });

  it("the budget numbers come from the real tree and leave a non-negative headroom after the new skill", () => {
    const v = verdict as CreateVerdictCreate;
    expect(v.total).toBeGreaterThan(1000);
    expect(v.cap - v.total).toBeGreaterThanOrEqual(v.words);
    expect(v.words).toBeGreaterThanOrEqual(12);
    expect(v.words).toBeLessThanOrEqual(30);
  });

  it("git sees EXACTLY the six paths changed in the materialized tree, and no other", () => {
    const st = sh("git", ["status", "--porcelain", "-uall", "--no-renames"], tree).stdout.split("\n").filter(Boolean).map((l) => l.slice(3));
    expect(st.sort()).toEqual([...createPathList(SLUG)].sort());
  });

  it("the promotion-log row rides the commit: hash, new SKILL.md path, evidence count, pending, skill", () => {
    const c = committed as unknown as { expectedContent: Record<string, string> };
    const log = c.expectedContent[PROMOTION_LOG_PATH];
    expect(log.split("\n").some((l) => l.includes(`plugins/soleur/skills/${SLUG}/SKILL.md | 5 | pending | skill |`))).toBe(true);
  });
});

describe("the repository's own CI checks, run unmodified over the tree with the new skill", () => {
  it("components, cursor-name-map, grok-harness-invoke, invocation-axis and harness-parity-tree are green (0 fail)", () => {
    expect(injectedStatus).toBe(0);
    expect(injectedFail).toBe(0);
  });

  it("non-vacuity: the checks SAW the new skill (strictly more tests ran than on the baseline copy)", () => {
    expect(baselinePass).toBeGreaterThan(1000);
    expect(injectedPass).toBeGreaterThan(baselinePass);
  });

  it("the real Cursor generator agrees with the pure stub renderer byte for byte (`--check`)", () => {
    const r = sh("bun", ["plugins/soleur/scripts/sync-cursor-name-map.ts", "--check"], tree);
    expect(r.status, `${r.stdout}${r.stderr}`).toBe(0);
    const stub = readFileSync(join(tree, `plugins/soleur/cursor/skills/soleur-${SLUG}/SKILL.md`), "utf8");
    expect(stub).toContain(`name: soleur-${SLUG}`);
  });

  it("`sync-readme-counts.sh --check` (lint-bot-statuses) is green: both README counts moved with the skill", () => {
    const r = sh("bash", ["scripts/sync-readme-counts.sh", "--check"], tree);
    expect(r.status, `${r.stdout}${r.stderr}`).toBe(0);
    expect(r.stdout).toContain("All component counts are in sync.");
  });

  it("the docs loader (`_data/skills.js`) loads the skill and files it under Uncategorized (the PR body tells the reviewer to categorise)", () => {
    const r = sh(
      "node",
      [
        "--input-type=module",
        "-e",
        "import('./plugins/soleur/docs/_data/skills.js').then((m) => { const d = m.default(); console.log(JSON.stringify(d.categories.map((c) => ({ n: c.name, s: c.skills.map((x) => x.name) })))); })",
      ],
      tree,
    );
    expect(r.status, r.stderr).toBe(0);
    const cats = JSON.parse(r.stdout.trim().split("\n").pop() as string) as Array<{ n: string; s: string[] }>;
    const where = cats.filter((c) => c.s.includes(SLUG)).map((c) => c.n);
    expect(where).toEqual(["Uncategorized"]);
  });

  it("the security scan verdict was LOW-RISK for BOTH files, read from the real scanner (the gate returned ok)", () => {
    // The gate returns `ok` only on exit 0 AND the exact LOW-RISK first line for each file; step B reached the commit.
    expect(persistResult).toMatchObject({ kind: "opened" });
    const skill = readFileSync(join(tree, `plugins/soleur/skills/${SLUG}/SKILL.md`), "utf8");
    const purpose = readFileSync(join(tree, `plugins/soleur/skills/${SLUG}/PURPOSE.md`), "utf8");
    // and the pr-quality-guards.yml invocation (offline, SKILL.md only) agrees when re-run here
    const scan = spawnSync("bash", [join(tree, "plugins/soleur/skills/skill-security-scan/scripts/run-scan.sh")], {
      cwd: tree, input: skill, encoding: "utf8", env: { ...cleanEnv(), SKILL_SECURITY_SCAN_OFFLINE: "1", SKILL_SCAN_META_BASE: mkdtempSync(join(tmpdir(), "dry-scan-meta-")) },
    });
    expect(scan.stdout.split("\n")[0]).toBe("# skill-security-scan verdict: LOW-RISK");
    expect(purpose.length).toBeGreaterThan(200);
  });

  const mdl = join(REPO_ROOT, "node_modules", ".bin", "markdownlint");
  it("markdownlint (the repo's pinned binary and config) is clean on the generated markdown", (ctx) => {
    if (!existsSync(mdl)) {
      // An absent binary is a visible SKIP. The CI legs that run this suite (test-webplat, tenant-integration) install only
      // apps/web-platform deps, so the root-pinned binary is not there; asserting its presence failed both (PR run
      // 40416582288). The created skill's own draft PR runs markdownlint over its tracked files in pr-quality-guards.yml.
      ctx.skip();
    }
    const r = sh(mdl, ["--config", join(REPO_ROOT, ".markdownlint.json"), `plugins/soleur/skills/${SLUG}/SKILL.md`, `plugins/soleur/skills/${SLUG}/PURPOSE.md`], tree);
    expect(r.status, `${r.stdout}${r.stderr}`).toBe(0);
  });
});
