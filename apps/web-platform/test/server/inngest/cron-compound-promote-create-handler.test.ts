// WikiSkill Phase 2 (#10550) -- handler-level behaviour of the gated create arm.
//
// PROPERTIES
//   Guard 3  A scheduled run, a manual `corpus` run and a manual `patterns` run whose `allow_create` is anything but
//            the boolean `true` execute EXACTLY as before: same steps, same model calls, same commits, same marker.
//   Guard 1  No byte reaches `safeCommitAndPr` in the create arm unless every gate passed; the create commit is the
//            closed six-path set in `exactPaths` mode with the rendered bytes in `expectedContent`; it never posts
//            the edit arm's `skill-security-scan PR gate` / `test` synthetic checks; the PR is a draft with the fixed
//            `CREATE (new skill)` line and never claims a merge.
//   CTO G2   The edit loop runs first; the arm shares the week cap (`remaining - editPrsOpenedThisRun`); one open
//            create at a time (list failure refuses); two steps (memoized `create-propose`, single `create-persist`);
//            deterministic branch from the memoized run date; replay finds its own open PR.
//
// ASSEMBLY: drives the real `cronCompoundPromoteHandler` over a real cloned git repo; only the network edges
// (Anthropic, the GitHub REST/search routes, the clone URL, the commit/PR helper) and the three SPAWN gates
// (scanner, README sync, content collector -- exercised for real in compound-promote-create-gates.test.ts and the
// dry-render suite) are stubbed. Own file, like its siblings, because it replaces `_cron-shared` and
// `@octokit/core` wholesale and vitest hoists every vi.mock to file scope.
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { runLikeInngest } from "../../helpers/inngest-step-harness";
import { buildSyntheticPluginTree } from "../../helpers/compound-promote-tree";

vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

const h = vi.hoisted(() => ({
  post: vi.fn(),
  safeCommit: vi.fn(),
  marker: vi.fn(),
  scan: vi.fn(),
  sync: vi.fn(),
  collect: vi.fn(),
  cloneUrl: "",
  workRoot: "",
  ledger: { items: [] as unknown[] },
  /** Open `self-healing/auto` PR count returned for the week-cap query. */
  openPrs: 0,
  /** `GET /pulls` (no head filter): the open-PR list the create-open check and the path scan read. */
  pulls: { list: [] as unknown[], error: null as unknown, files: {} as Record<number, unknown[]> },
  /** `GET /pulls?head=...`: our own open PR for the deterministic branch. */
  ownPrs: [] as unknown[],
  heads: [] as string[],
  calls: [] as string[],
}));

vi.mock("@/server/observability", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/observability")>()),
  reportSilentFallback: vi.fn(),
}));
vi.mock("@octokit/core", () => ({
  Octokit: class {
    request = async (route: string, params: Record<string, unknown>) => {
      h.calls.push(route);
      if (route === "GET /repos/{owner}/{repo}/pulls") {
        if (typeof params.head === "string") {
          h.heads.push(params.head);
          return { data: h.ownPrs };
        }
        if (h.pulls.error) throw h.pulls.error;
        const start = ((params.page as number) - 1) * 100;
        return { data: h.pulls.list.slice(start, start + 100) };
      }
      if (route === "GET /repos/{owner}/{repo}/pulls/{pull_number}/files") {
        const all = h.pulls.files[params.pull_number as number] ?? [];
        const start = ((params.page as number) - 1) * 100;
        return { data: all.slice(start, start + 100) };
      }
      const q = String(params.q ?? "");
      if (q.includes("head:self-healing/auto-")) {
        return { data: { total_count: h.ledger.items.length, incomplete_results: false, items: h.ledger.items } };
      }
      if (q.includes("[Scheduled] Compound Promotion")) return { data: { total_count: 0, items: [] } };
      if (q.includes("is:pr is:open label:self-healing/auto")) return { data: { total_count: h.openPrs, items: [] } };
      return { data: { total_count: 0, items: [] } };
    };
  },
}));
vi.mock("@/server/inngest/functions/_cron-shared", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/inngest/functions/_cron-shared")>()),
  mintInstallationToken: async () => "ghs_" + "x".repeat(30),
  buildAuthenticatedCloneUrl: () => h.cloneUrl,
  resolveCronWorkspaceRoot: () => h.workRoot,
  warnIfCronWorkspaceLowOnDisk: async () => {},
  postAnthropicMessage: (...a: unknown[]) => h.post(...a),
  postSentryHeartbeat: async () => {},
}));
vi.mock("@/server/inngest/functions/_cron-safe-commit", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/inngest/functions/_cron-safe-commit")>()),
  safeCommitAndPr: (...a: unknown[]) => h.safeCommit(...a),
}));
vi.mock("@/server/compound-promote-marker", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/compound-promote-marker")>()),
  emitOutcomeMarker: (o: unknown) => h.marker(o),
}));
vi.mock("@/server/compound-promote-create-gates", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/compound-promote-create-gates")>()),
  runSkillScan: (...a: unknown[]) => h.scan(...a),
  syncReadmeCounts: (...a: unknown[]) => h.sync(...a),
  collectCreateContent: (...a: unknown[]) => h.collect(...a),
}));

import { reportSilentFallback } from "@/server/observability";
import { cronCompoundPromoteHandler } from "@/server/inngest/functions/cron-compound-promote";
import { PROMOTE_BRANCH_PREFIX, promotePrTitle } from "@/server/compound-promote-ledger";
import {
  CREATE_MAX_TOKENS,
  CREATE_PR_BODY_LINE,
  createClusterHash,
  createPathList,
  proposalOverlapText,
  rankOverlap,
  PROMOTION_LOG_PATH,
  type SkillRecord,
} from "@/server/compound-promote-create";
import { createSyntheticCheckNames } from "@/server/compound-promote-create-gates";
import { gitFixture } from "../../../../../plugins/soleur/test/lib/git-fixture-env";

const FIX = join(__dirname, "..", "..", "fixtures", "compound-promote-create");
const Q = 5;
const L = (n: number) => `knowledge-base/project/learnings/l${n}.md`;
const Ls = (start: number, count: number) => Array.from({ length: count }, (_, i) => L(start + i));
const MANUAL = (data: Record<string, unknown> = {}) => ({ name: "cron/compound-promote.manual-trigger", data });
const CRON = (data: Record<string, unknown> = {}) => ({ name: "inngest/scheduled.timer", data });
const PATTERNS_CREATE = () => MANUAL({ input: "patterns", allow_create: true });

const AGENTS_RULES = ["---", "last_reviewed: 2026-10-01", "---", "", "## Code Quality", "",
  "- Write tests first [id: cq-tests-first]. Because.", "- Keep it small [id: cq-keep-small]. Because.", ""].join("\n");
const GOOD_AGENTS_EDIT = { insert_after_line: "- Keep it small [id: cq-keep-small]. Because.", new_lines: ["- Prefer small diffs [id: cq-small-diffs]. Reviewers read less."] };

function page(slug: string, evidence: string[]): string {
  return [
    "---",
    `title: ${JSON.stringify(`Pattern ${slug}`)}`,
    `summary: "Summary for ${slug}: a recurring failure, its root cause and the fix."`,
    "status: open",
    'opened_on: "2026-10-24"',
    "tags: [guards]",
    "evidence:",
    ...evidence.map((p) => `  - ${p}`),
    "required_reading: false",
    "---",
    "## Root cause",
    `BODY-ROOT-${slug}`,
    "",
    "## Fix",
    `BODY-FIX-${slug}`,
    "",
  ].join("\n");
}

const fixtureJson = <T,>(name: string): T => JSON.parse(readFileSync(join(FIX, name), "utf8")) as T;
const PROPOSAL = fixtureJson<Record<string, unknown>>("proposal.json");
const CREATE_PATTERN_SLUG = String(PROPOSAL.pattern_slug);
const CREATE_EVIDENCE = Ls(1, Q);
const EDIT_EVIDENCE = Ls(Q + 1, Q);
const EDIT_CLUSTER = { tier: "agents-core", target_path: "AGENTS.rules.md", source_learnings: EDIT_EVIDENCE, rationale: "RATIONALE-AGENTS" };

let remoteDir: string;
let workRoot: string;
let allSkills: SkillRecord[] = [];
let wordTotal = 0;
const savedGitEnv: Record<string, string | undefined> = {};

beforeAll(() => {
  for (const k of Object.keys(process.env)) {
    if (k.startsWith("GIT_")) {
      savedGitEnv[k] = process.env[k];
      delete process.env[k];
    }
  }
  process.env.ANTHROPIC_API_KEY = "test-key";
  // The literal `x-access-token` in the path makes the clone's `.git/config` carry the marker the real token URL would (R4).
  remoteDir = mkdtempSync(join(tmpdir(), "create-handler-remote-x-access-token-"));
  workRoot = mkdtempSync(join(tmpdir(), "create-handler-work-"));
  const git = gitFixture(remoteDir);
  git(["init", "-q", "-b", "main", "."]);
  const put = (p: string, t: string) => {
    mkdirSync(dirname(join(remoteDir, p)), { recursive: true });
    writeFileSync(join(remoteDir, p), t);
  };
  put("AGENTS.md", "# AGENTS index\n\n- [id: cq-tests-first] -> rules\n");
  put("AGENTS.rules.md", AGENTS_RULES);
  put("knowledge-base/project/promotion-config.yml", "enabled: true\n");
  put("knowledge-base/project/learnings/promotion-log.md", "| date | hash | target | n | status | tier | pr |\n");
  for (let n = 1; n <= 12; n++) put(L(n), `# Learning ${n}\n\nA recurring failure number ${n} about retries.\n`);
  put(`knowledge-base/project/patterns/${CREATE_PATTERN_SLUG}.md`, page(CREATE_PATTERN_SLUG, CREATE_EVIDENCE));
  put("knowledge-base/project/patterns/page-two.md", page("page-two", EDIT_EVIDENCE));

  // The shared synthetic plugin tree (fixture skills + the REAL plan skill and PURPOSE template + fillers + populations + cap).
  const tree = buildSyntheticPluginTree(put);
  allSkills = tree.records;
  wordTotal = tree.total;
  put("README.md", "Soleur: 99 skills\n");
  put("plugins/soleur/README.md", "| Skills | 99 |\n");
  git(["add", "-A"]);
  git(["commit", "-qm", "init"]);
  h.cloneUrl = `file://${remoteDir}`;
  h.workRoot = workRoot;
});

afterAll(() => {
  rmSync(remoteDir, { recursive: true, force: true });
  rmSync(workRoot, { recursive: true, force: true });
  for (const [k, v] of Object.entries(savedGitEnv)) if (v !== undefined) process.env[k] = v;
});

/** The valid create proposal; its nearest skill follows the server's own ranking over the fixture tree. */
function goodProposal(over: Record<string, unknown> = {}): Record<string, unknown> {
  const merged: Record<string, unknown> = { ...structuredClone(PROPOSAL), ...over };
  if (!("nearest_skill" in over)) {
    merged.nearest_skill = rankOverlap(
      proposalOverlapText({ slug: String(merged.slug), description: String(merged.description), when_to_use: merged.when_to_use as string[] }),
      allSkills,
    )[0].name;
  }
  return merged;
}

type CreateReply = { text: string; stopReason?: string } | Error;
let createReply: CreateReply;
let editClusters: unknown[];

function stubModel() {
  h.post.mockImplementation(async (a: { messages: Array<{ content: string }> }) => {
    const prompt = a.messages[0].content;
    if (prompt.includes("clustering agent")) return { text: JSON.stringify({ clusters: editClusters }), stopReason: "end_turn" };
    if (prompt.includes("brand-new skill")) {
      if (createReply instanceof Error) throw createReply;
      return createReply;
    }
    if (prompt.includes("RATIONALE-AGENTS")) return { text: JSON.stringify(GOOD_AGENTS_EDIT), stopReason: "end_turn" };
    throw new Error("unstubbed prompt");
  });
}

const createPrompts = () => h.post.mock.calls.filter((c) => (c[0] as { messages: Array<{ content: string }> }).messages[0].content.includes("brand-new skill"));
const createCommits = () => h.safeCommit.mock.calls.filter((c) => Array.isArray((c[0] as { exactPaths?: unknown }).exactPaths));
const editCommits = () => h.safeCommit.mock.calls.filter((c) => !Array.isArray((c[0] as { exactPaths?: unknown }).exactPaths));

beforeEach(() => {
  expect.hasAssertions();
  for (const m of [h.post, h.safeCommit, h.marker, h.scan, h.sync, h.collect]) m.mockReset();
  h.ledger.items = [];
  h.openPrs = 0;
  h.pulls.list = [];
  h.pulls.error = null;
  h.pulls.files = {};
  h.ownPrs = [];
  h.heads.length = 0;
  h.calls.length = 0;
  vi.mocked(reportSilentFallback).mockClear();
  createReply = { text: JSON.stringify(goodProposal()), stopReason: "end_turn" };
  editClusters = [EDIT_CLUSTER];
  h.safeCommit.mockResolvedValue({ status: "committed", prNumber: 101, branch: "b", fileCount: 1, deletionCount: 0 });
  // Default gates: pass. `collect` reads what is on disk, exactly the contract of the real collector.
  h.scan.mockResolvedValue({ ok: true });
  h.sync.mockResolvedValue({ ok: true });
  h.collect.mockImplementation(async (o: { repoRoot: string; slug: string }) => {
    const paths = createPathList(o.slug);
    const expectedContent: Record<string, string> = {};
    for (const p of paths) expectedContent[p] = readFileSync(join(o.repoRoot, p), "utf8");
    return { ok: true, exactPaths: paths, expectedContent };
  });
  stubModel();
});
afterEach(() => vi.useRealTimers());

interface RunResult {
  result: { ok: boolean; status: string };
  names: string[];
  markers: Array<Record<string, unknown>>;
  last: Record<string, unknown>;
  /** `git status --porcelain` of the clone right after each create-persist callback returned. */
  statusAfterPersist: string[];
}

async function run(event: { name: string; data?: Record<string, unknown> }): Promise<RunResult> {
  const names: string[] = [];
  const statusAfterPersist: string[] = [];
  const memo = new Map<string, unknown>();
  const step = {
    run: async <T,>(name: string, cb: () => Promise<T>): Promise<T> => {
      names.push(name);
      if (memo.has(name)) return memo.get(name) as T;
      const v = await cb();
      memo.set(name, v);
      const repo = (memo.get("read-config") as { repoRoot: string } | undefined)?.repoRoot;
      if (name === "create-persist" && repo && existsSync(repo)) {
        statusAfterPersist.push(execFileSync("git", ["-C", repo, "status", "--porcelain", "-uall"], { encoding: "utf8" }));
      }
      return v;
    },
  };
  const logger = { info: vi.fn(), warn: vi.fn(), error: vi.fn() };
  const result = await cronCompoundPromoteHandler({ step, logger, event, runId: "RUN-C" });
  const markers = h.marker.mock.calls.map((c) => c[0] as Record<string, unknown>);
  return { result, names, markers, last: markers[markers.length - 1], statusAfterPersist };
}

const CREATE_ONLY_KEYS = [
  "kind", "create_arm", "create_outcome", "create_no_action_reason", "create_refusal_class", "create_detail",
  "create_words", "create_cap", "create_total", "create_top1", "create_nearest_rank", "create_pr",
];
const createKeys = (m: Record<string, unknown>) => Object.keys(m).filter((k) => k.startsWith("create_") || k === "kind");
const ENTRY_HASH = createClusterHash(CREATE_EVIDENCE);

// ---------------------------------------------------------------------------------------------------------
describe("Guard 3 -- the arm is reachable ONLY for trigger=manual, input=patterns, allow_create===true", () => {
  /** What a run did, comparable across `allow_create` variants: steps, model prompts, commit configs, marker. */
  const fingerprint = async (event: { name: string; data?: Record<string, unknown> }) => {
    h.post.mockClear();
    h.safeCommit.mockClear();
    h.marker.mockClear();
    const r = await run(event);
    return {
      names: r.names,
      prompts: h.post.mock.calls.map((c) => (c[0] as { messages: Array<{ content: string }> }).messages[0].content.replace(/<<<(BEGIN|END)-[0-9a-f]{16}/g, "<<<$1-N")),
      commits: h.safeCommit.mock.calls.map((c) => {
        const cfg = c[0] as Record<string, unknown>;
        return { ...cfg, installationToken: "T", octokit: "O", logger: "L", runStartedAt: "R", spawnCwd: "W" };
      }),
      marker: { ...r.last, run_id: "R" },
    };
  };

  it("a CRON event carrying input=patterns and allow_create=true is byte-identical to one without", async () => {
    const without = await fingerprint(CRON({ input: "patterns" }));
    const withFlag = await fingerprint(CRON({ input: "patterns", allow_create: true }));
    expect(withFlag).toEqual(without);
    expect(withFlag.names.some((n) => n.startsWith("create-"))).toBe(false);
    expect(createKeys(withFlag.marker)).toEqual([]);
    expect(createPrompts()).toHaveLength(0);
  });

  it("a manual CORPUS run with allow_create=true is byte-identical to one without", async () => {
    const without = await fingerprint(MANUAL({ input: "corpus" }));
    const withFlag = await fingerprint(MANUAL({ input: "corpus", allow_create: true }));
    expect(withFlag).toEqual(without);
    expect(withFlag.names.some((n) => n.startsWith("create-"))).toBe(false);
    expect(createKeys(withFlag.marker)).toEqual([]);
  });

  it("a manual run with NO input (defaults to corpus) and allow_create=true is byte-identical to one without", async () => {
    const without = await fingerprint(MANUAL());
    const withFlag = await fingerprint(MANUAL({ allow_create: true }));
    expect(withFlag).toEqual(without);
    expect(createKeys(withFlag.marker)).toEqual([]);
  });

  it.each([["true"], [1], ["yes"], [{}], [[true]], [null], [0], [false], [undefined]])(
    "a manual PATTERNS run with allow_create=%j is not a create: no create step, no model create call, create_requested=false",
    async (flag) => {
      const r = await run(MANUAL({ input: "patterns", allow_create: flag }));
      expect(r.names.some((n) => n.startsWith("create-"))).toBe(false);
      expect(createPrompts()).toHaveLength(0);
      expect(createCommits()).toHaveLength(0);
      // Only the request marker is present, and it says false.
      expect(createKeys(r.last)).toEqual(["create_requested"]);
      expect(r.last.create_requested).toBe(false);
      expect(r.last).not.toHaveProperty("create_arm");
      expect(r.last).not.toHaveProperty("kind");
    },
  );

  it("must-PASS: a manual PATTERNS run with allow_create=true DOES run the arm, once", async () => {
    const r = await run(PATTERNS_CREATE());
    expect(r.names.filter((n) => n === "create-propose")).toHaveLength(1);
    expect(createPrompts()).toHaveLength(1);
    expect(r.last).toMatchObject({ create_requested: true, create_arm: "ran", kind: "create" });
  });

  it("G5e: the marker key sets are pinned -- scheduled and manual-corpus rows carry NO create key; a manual-patterns row gains EXACTLY `create_requested`", async () => {
    const keysOf = async (ev: { name: string; data?: Record<string, unknown> }) => Object.keys((await run(ev)).last).sort();
    const cron = await keysOf(CRON());
    const corpus = await keysOf(MANUAL({ input: "corpus" }));
    const patterns = await keysOf(MANUAL({ input: "patterns" }));
    const patternsOn = await keysOf(MANUAL({ input: "patterns", allow_create: false }));
    expect(cron.filter((k) => k.startsWith("create_") || k === "kind")).toEqual([]);
    expect(corpus.filter((k) => k.startsWith("create_") || k === "kind")).toEqual([]);
    expect(corpus).toEqual(cron); // a manual corpus row is the scheduled row
    expect(patterns).toEqual(patternsOn);
    expect(patterns.filter((k) => k.startsWith("create_") || k === "kind")).toEqual(["create_requested"]);
    // the patterns row is the patterns-arm fields plus that ONE key
    expect(patterns.filter((k) => k !== "create_requested")).toEqual(patterns.filter((k) => !k.startsWith("create_")));
    expect(patterns).toEqual(expect.arrayContaining(["input_source", "ledger_read", "ledger_suppressed", "patterns_open", "trigger"]));
  });

  it("the scheduled path and the manual corpus path never gain a create field, even when the arm is refused elsewhere", async () => {
    for (const ev of [CRON(), MANUAL(), MANUAL({ input: "corpus" })]) {
      const r = await run(ev);
      expect(createKeys(r.last), JSON.stringify(ev)).toEqual([]);
      expect(Object.keys(r.last).filter((k) => CREATE_ONLY_KEYS.includes(k))).toEqual([]);
    }
  });

  it("the single parse site: readRunOptions parses allow_create only after the manual/patterns checks", () => {
    const src = readFileSync(join(__dirname, "..", "..", "..", "server", "inngest", "functions", "cron-compound-promote.ts"), "utf8");
    const body = src.slice(src.indexOf("function readRunOptions("), src.indexOf("/** Learning paths named by"));
    const manualIdx = body.indexOf('trigger !== "manual"');
    const inputIdx = body.indexOf("event?.data?.input");
    const flagIdx = body.indexOf("allow_create");
    expect(manualIdx).toBeGreaterThan(-1);
    expect(inputIdx).toBeGreaterThan(manualIdx);
    expect(flagIdx).toBeGreaterThan(inputIdx);
    expect(body).toContain('=== "patterns"');
    expect(body).toMatch(/allow_create === true/);
    // and nowhere else in the handler module reads the raw event flag
    expect(src.match(/event\??\.data\??\.allow_create/g) ?? []).toHaveLength(1);
  });
});

// ---------------------------------------------------------------------------------------------------------
describe("the week cap (CTO G2): the edit loop runs first and shares the cap", () => {
  it("with the REAL saturated cap (two open self-healing/auto PRs: #11230 and #11231 today) the run ends week-cap-reached BEFORE the arm", async () => {
    h.openPrs = 2;
    const r = await run(PATTERNS_CREATE());
    expect(r.result.status).toBe("week-cap-reached");
    expect(r.names).not.toContain("create-propose");
    expect(createPrompts()).toHaveLength(0);
    // The request is visible on the early terminal row; the arm did not run.
    expect(r.last).toMatchObject({ status: "week-cap-reached", input_source: "patterns", create_requested: true });
    expect(r.last).not.toHaveProperty("create_arm");
  });

  it("with ONE slot left and the edit loop spending it, the arm is refused class=week-cap: no model create call, no commit, mirrored to Sentry", async () => {
    h.openPrs = 1;
    const r = await run(PATTERNS_CREATE());
    expect(r.last).toMatchObject({ status: "completed", clusters_opened: 1, create_arm: "ran", create_outcome: "refused", create_refusal_class: "week-cap" });
    expect(r.last.refusals).toContain("create-refused");
    expect(createPrompts()).toHaveLength(0);
    expect(createCommits()).toHaveLength(0);
    expect(editCommits()).toHaveLength(1);
    expect(r.names).toContain("create-propose");
    expect(r.names).not.toContain("create-persist");
    expect(reportSilentFallback).toHaveBeenCalledWith(null, expect.objectContaining({ feature: "cron-compound-promote", op: "create-refused", tags: { class: "week-cap" } }));
  });

  it("the edit loop runs first: apply-and-pr precedes create-propose, and the edit PR is committed before any create step", async () => {
    const r = await run(PATTERNS_CREATE());
    const editIdx = r.names.findIndex((n) => n.startsWith("apply-and-pr-"));
    const createIdx = r.names.indexOf("create-propose");
    expect(editIdx).toBeGreaterThan(-1);
    expect(createIdx).toBeGreaterThan(editIdx);
    expect(editCommits()).toHaveLength(1);
  });

  it("with the edit arm finding nothing (no qualifying clusters) the arm still runs, with the whole cap left", async () => {
    editClusters = [];
    const r = await run(PATTERNS_CREATE());
    expect(r.result.status).toBe("no-qualifying-clusters");
    expect(r.names).toContain("create-propose");
    expect(r.last).toMatchObject({ status: "no-qualifying-clusters", create_arm: "ran", create_outcome: "opened" });
  });
});

// ---------------------------------------------------------------------------------------------------------
describe("one open create at a time (CTO G2)", () => {
  const BOT_HEAD = { ref: `${PROMOTE_BRANCH_PREFIX}${"c".repeat(64)}-2026-10-20`, repo: { full_name: "jikig-ai/soleur" } };
  const OPEN_CREATE = { number: 777, body: `${CREATE_PR_BODY_LINE}\n\nProposed by the loop.`, labels: [{ name: "self-healing/auto" }], head: BOT_HEAD };

  it("another open self-healing/auto PR carrying the fixed CREATE line refuses create-open before any model call", async () => {
    h.pulls.list = [OPEN_CREATE];
    const r = await run(PATTERNS_CREATE());
    expect(r.last).toMatchObject({ create_outcome: "refused", create_refusal_class: "create-open", create_detail: "open-create-pr" });
    expect(createPrompts()).toHaveLength(0);
    expect(createCommits()).toHaveLength(0);
    expect(reportSilentFallback).toHaveBeenCalledWith(null, expect.objectContaining({ op: "create-refused", tags: { class: "create-open" } }));
  });

  it("a list that cannot be read REFUSES create-open (absence is never inferred from a failed read)", async () => {
    h.pulls.error = Object.assign(new Error("boom with a body"), { status: 502 });
    const r = await run(PATTERNS_CREATE());
    expect(r.last).toMatchObject({ create_outcome: "refused", create_refusal_class: "create-open", create_detail: "list-failed" });
    expect(createPrompts()).toHaveLength(0);
    expect(JSON.stringify(r.last)).not.toContain("boom with a body");
  });

  it("the open-PR list is a literal-route GET /pulls, never the search API", async () => {
    await run(PATTERNS_CREATE());
    expect(h.calls).toContain("GET /repos/{owner}/{repo}/pulls");
  });
});

// ---------------------------------------------------------------------------------------------------------
describe("Step A: create-propose is ONE bounded model call, memoized, and never throws", () => {
  it("binds the call to the same helper and attribution as the patterns call, with its own output cap and a timeout", async () => {
    await run(PATTERNS_CREATE());
    expect(createPrompts()).toHaveLength(1);
    const args = createPrompts()[0][0] as Record<string, unknown>;
    expect(args).toMatchObject({ maxTokens: CREATE_MAX_TOKENS, markerSource: "cron-compound-promote", markerRunId: "RUN-C" });
    expect(typeof args.timeoutMs).toBe("number");
    expect(args.maxTokens).toBe(3000);
    expect(args.outputConfig).toMatchObject({ format: { type: "json_schema" } });
  });

  it.each([
    ["transport failure", new Error("Anthropic API request failed (TimeoutError)"), "transport"],
    ["truncated", { text: "{", stopReason: "max_tokens" }, "max-tokens"],
    ["empty", { text: "", stopReason: "end_turn" }, "empty"],
    ["not JSON", { text: "sorry, here is a skill", stopReason: "end_turn" }, "not-json"],
    ["wrong schema", { text: JSON.stringify({ decision: "create", slug: "x" }), stopReason: "end_turn" }, "schema"],
  ] as const)("%s -> refused model-invalid(%s), ONE call (no retry), a returned class not a throw", async (_n, reply, detail) => {
    createReply = reply as CreateReply;
    const r = await run(PATTERNS_CREATE());
    expect(r.result.status).toBe("completed");
    expect(r.last).toMatchObject({ create_outcome: "refused", create_refusal_class: "model-invalid", create_detail: detail });
    expect(createPrompts()).toHaveLength(1);
    expect(createCommits()).toHaveLength(0);
    expect(r.names).not.toContain("create-persist");
  });

  it("no_action is a clean outcome: create_arm ran, no refusal, no persist step", async () => {
    createReply = { text: JSON.stringify({ decision: "no_action", reason_class: "all-owned" }), stopReason: "end_turn" };
    const r = await run(PATTERNS_CREATE());
    expect(r.last).toMatchObject({ create_arm: "ran", kind: "create", create_outcome: "no_action", create_no_action_reason: "all-owned" });
    expect(r.last).not.toHaveProperty("create_refusal_class");
    expect(r.last.refusals).not.toContain("create-refused");
    expect(r.names).not.toContain("create-persist");
    expect(reportSilentFallback).not.toHaveBeenCalledWith(null, expect.objectContaining({ op: "create-refused" }));
  });

  it("each checkCreate refusal surfaces its class and closed detail in the marker, with numbers only", async () => {
    createReply = { text: JSON.stringify(goodProposal({ steps: ["Run `rm -rf` now"] })), stopReason: "end_turn" };
    const shape = await run(PATTERNS_CREATE());
    expect(shape.last).toMatchObject({ create_refusal_class: "shape", create_detail: "steps[0]:backtick" });

    const words = Array.from({ length: 31 }, (_, i) => `w${i}`).join(" ");
    createReply = { text: JSON.stringify(goodProposal({ description: `This skill should be used ${words}` })), stopReason: "end_turn" };
    h.marker.mockClear();
    const budget = await run(PATTERNS_CREATE());
    expect(budget.last).toMatchObject({ create_refusal_class: "budget", create_detail: "words-out-of-range" });
  });

  it("budget: a description of exactly `cap - total` words is accepted and one more is refused (fixture tree)", async () => {
    // cap - total = 40 in the fixture tree, but the description maximum is 30: exercise the headroom edge by
    // lowering the cap in a throwaway commit so headroom is exactly the description's word count.
    const git = gitFixture(remoteDir);
    const words = String(goodProposal().description).split(/\s+/).filter(Boolean).length;
    const write = (cap: number) => {
      writeFileSync(join(remoteDir, "plugins/soleur/test/components.test.ts"), `const SKILL_DESCRIPTION_WORD_BUDGET = ${cap};\n`);
      git(["commit", "-qam", `cap ${cap}`]);
    };
    write(wordTotal + words);
    try {
      const ok = await run(PATTERNS_CREATE());
      expect(ok.last).toMatchObject({ create_outcome: "opened" });
    } finally {
      git(["reset", "-q", "--hard", "HEAD~1"]);
    }
    write(wordTotal + words - 1);
    try {
      h.marker.mockClear();
      const over = await run(PATTERNS_CREATE());
      expect(over.last).toMatchObject({ create_outcome: "refused", create_refusal_class: "budget", create_detail: "over-headroom", create_words: words, create_cap: wordTotal + words - 1, create_total: wordTotal });
    } finally {
      git(["reset", "-q", "--hard", "HEAD~1"]);
    }
  });

  it("an unreadable cap (no constant in components.test.ts) refuses budget, never creates", async () => {
    const git = gitFixture(remoteDir);
    writeFileSync(join(remoteDir, "plugins/soleur/test/components.test.ts"), "// no cap here\n");
    git(["commit", "-qam", "no cap"]);
    try {
      const r = await run(PATTERNS_CREATE());
      expect(r.last).toMatchObject({ create_outcome: "refused", create_refusal_class: "budget", create_detail: "cap-unreadable" });
      expect(createPrompts()).toHaveLength(0);
    } finally {
      git(["reset", "-q", "--hard", "HEAD~1"]);
    }
  });

  it("the evidence fixtures (#11230 / #11231 shapes) are refused prefer-patch with rank and top-1 as numbers", async () => {
    // A cluster whose nearest skill is git-worktree: the description restates it.
    const cal = fixtureJson<{ evidence: Array<{ slug: string; description: string; when_to_use: string[]; target: string }> }>("calibration.json");
    const ev = cal.evidence[0];
    createReply = { text: JSON.stringify(goodProposal({ slug: ev.slug, description: ev.description, when_to_use: ev.when_to_use, nearest_skill: ev.target })), stopReason: "end_turn" };
    const r = await run(PATTERNS_CREATE());
    expect(r.last).toMatchObject({ create_outcome: "refused", create_refusal_class: "prefer-patch" });
    expect(typeof r.last.create_top1).toBe("number");
    expect(typeof r.last.create_nearest_rank).toBe("number");
  });

  it("a pattern already proposed (ledger: an open PR carries its cluster hash) is SUPPRESSED, not refused: existing ledger-suppressed reason", async () => {
    h.ledger.items = [{
      title: promotePrTitle(ENTRY_HASH, "2026-10-04"), state: "open", closed_at: null,
      user: { login: "soleur-ai[bot]" }, pull_request: { merged_at: null },
    }];
    const r = await run(PATTERNS_CREATE());
    expect(r.last.refusals).toContain("ledger-suppressed");
    expect(r.last).toMatchObject({ create_arm: "ran", create_outcome: "no_action", create_no_action_reason: "other", ledger_suppressed: 1 });
    expect(r.last).not.toHaveProperty("create_refusal_class");
    expect(createCommits()).toHaveLength(0);
    expect(r.names).not.toContain("create-persist");
  });
});

// ---------------------------------------------------------------------------------------------------------
describe("Step B: create-persist -- the closed six-path commit in exactPaths mode", () => {
  it("opens a DRAFT PR: exactPaths x6, expectedContent = the rendered bytes, no allowedPaths, deterministic branch, fixed body", async () => {
    const r = await run(PATTERNS_CREATE());
    expect(r.last).toMatchObject({ status: "completed", create_arm: "ran", create_outcome: "opened", create_pr: 101, kind: "create", create_requested: true });
    expect(createCommits()).toHaveLength(1);
    const cfg = createCommits()[0][0] as Record<string, any>;
    const slug = String(PROPOSAL.slug);
    expect(cfg.exactPaths).toEqual(createPathList(slug));
    expect(cfg.exactPaths).toHaveLength(6);
    expect(cfg.allowedPaths).toEqual([]);
    expect(Object.keys(cfg.expectedContent).sort()).toEqual([...createPathList(slug)].sort());
    expect(cfg.expectedContent[`plugins/soleur/skills/${slug}/SKILL.md`]).toMatch(/^---\nname: http-retry-backoff\n/);
    expect(cfg.expectedContent[`plugins/soleur/skills/${slug}/PURPOSE.md`]).toContain("Attribution");
    expect(cfg.expectedContent[`plugins/soleur/cursor/skills/soleur-${slug}/SKILL.md`]).toContain("name: soleur-http-retry-backoff");
    // the ledger row rides the commit and names the new SKILL.md, the cluster hash and the evidence count
    expect(cfg.expectedContent[PROMOTION_LOG_PATH]).toContain(`${ENTRY_HASH} | plugins/soleur/skills/${slug}/SKILL.md | ${Q} | pending | skill |`);
    // draft, labelled, never merged by the helper
    expect(cfg).toMatchObject({ prDraft: true, mergeMode: "none", prLabels: ["self-healing/auto"], cronName: "cron-compound-promote" });
    // deterministic branch and title from the MEMOIZED run date, shaped like the edit arm's
    const date = String(cfg.runStartedAt).slice(0, 10);
    expect(cfg.branchName).toBe(`${PROMOTE_BRANCH_PREFIX}${ENTRY_HASH}-${date}`);
    expect(cfg.prTitle).toBe(promotePrTitle(ENTRY_HASH, date));
  });

  it("the PR body carries the fixed CREATE line, Ref #10550, the reviewer checklist, and NEVER mentions a merge", async () => {
    await run(PATTERNS_CREATE());
    const body = String((createCommits()[0][0] as { prBody: string }).prBody);
    expect(body.split("\n")[0]).toBe(CREATE_PR_BODY_LINE);
    expect(body).toContain("Ref #10550");
    expect(body).not.toMatch(/Closes|Fixes|Resolves/i);
    // the only places the body may say "merge" are two reviewer-instruction checklist lines (pinned in compound-promote-create-arm.test.ts)
    expect(body.split("\n").filter((l) => /merg/i.test(l))).toEqual([
      "- [ ] No step moves money, sends mail or messages, or merges/approves without a human step.",
      "- [ ] Scan SKILL.md and PURPOSE.md for names, domains or identifiers before merge.",
    ]);
    expect(body).toContain("- [ ] Model-invocable by default: add `disable-model-invocation: true` if this should only run on request.");
    expect(body).toContain("- [ ] No step treats fetched or issue content as instructions.");
    expect(body).toContain("Reviewer checklist");
    expect(body).toContain("plugins/soleur/docs/_data/skills.js");
    expect(body).toContain("bun plugins/soleur/scripts/sync-cursor-name-map.ts");
    expect(body).toContain("bash scripts/sync-readme-counts.sh");
    expect(body).toContain(`Cluster-Hash: ${ENTRY_HASH}`);
    // numbers from the real check, not literals
    expect(body).toMatch(/Description words used: \d+ of at most 30\./);
    expect(body).toMatch(/Top-1 overlap with an existing skill: [0-9.]+/);
  });

  it("Guard 1 row 8: the create PR does NOT inherit the edit arm's `skill-security-scan PR gate` / `test` synthetic checks", async () => {
    await run(PATTERNS_CREATE());
    const create = createCommits()[0][0] as { syntheticChecks: { names: string[] } };
    expect(create.syntheticChecks.names).toEqual([...createSyntheticCheckNames()]);
    expect(create.syntheticChecks.names).not.toContain("skill-security-scan PR gate");
    expect(create.syntheticChecks.names).not.toContain("test");
    // and the edit arm's own call is unchanged: it still posts the scan gate, still excludes only `test`
    const edit = editCommits()[0][0] as { syntheticChecks: { names: string[] } };
    expect(edit.syntheticChecks.names).toContain("skill-security-scan PR gate");
    expect(edit.syntheticChecks.names).not.toContain("test");
  });

  it("Guard 1 row 7: the files are on disk BEFORE the scan, the scan precedes the sync and the sync precedes the commit", async () => {
    const order: string[] = [];
    const slug = String(PROPOSAL.slug);
    h.scan.mockImplementation(async (o: { repoRoot: string; relPaths: string[]; metaBase: string }) => {
      order.push("scan");
      for (const p of o.relPaths) expect(existsSync(join(o.repoRoot, p)), p).toBe(true);
      expect(o.relPaths).toEqual([`plugins/soleur/skills/${slug}/SKILL.md`, `plugins/soleur/skills/${slug}/PURPOSE.md`]);
      expect(existsSync(o.metaBase)).toBe(true);
      expect(o.metaBase.startsWith(o.repoRoot)).toBe(false);
      return { ok: true };
    });
    h.sync.mockImplementation(async () => {
      order.push("sync");
      return { ok: true };
    });
    h.collect.mockImplementation(async (o: { repoRoot: string; slug: string }) => {
      order.push("collect");
      const paths = createPathList(o.slug);
      return { ok: true, exactPaths: paths, expectedContent: Object.fromEntries(paths.map((p) => [p, readFileSync(join(o.repoRoot, p), "utf8")])) };
    });
    h.safeCommit.mockImplementation(async (cfg: { exactPaths?: unknown }) => {
      if (cfg.exactPaths) order.push("commit");
      return { status: "committed", prNumber: 101, branch: "b", fileCount: 1, deletionCount: 0 };
    });
    await run(PATTERNS_CREATE());
    expect(order).toEqual(["scan", "sync", "collect", "commit"]);
  });

  it.each([
    ["scan", () => h.scan.mockResolvedValue({ ok: false, detail: "high-risk" }), "scan", "high-risk"],
    ["readme-sync", () => h.sync.mockResolvedValue({ ok: false, detail: "non-digit-change" }), "readme-sync", "non-digit-change"],
    ["collector", () => h.collect.mockResolvedValue({ ok: false, detail: "changed-set-mismatch" }), "persist", "changed-set-mismatch"],
    ["helper non-commit", () => h.safeCommit.mockResolvedValue({ status: "failed", stage: "integrity", message: "m" }), "persist", "failed-integrity"],
    ["helper no-changes", () => h.safeCommit.mockResolvedValue({ status: "no-changes" }), "persist", "not-committed-no-changes"],
  ] as const)("a %s refusal ends the create refused (class %s), mirrors to Sentry, and leaves the clone CLEAN: a refused create writes no ledger row", async (_n, arrange, cls, detail) => {
    // the helper stays the default committed double except for the case that overrides it
    arrange();
    const r = await run(PATTERNS_CREATE());
    expect(r.last).toMatchObject({ create_outcome: "refused", create_refusal_class: cls, create_detail: detail });
    expect(r.last.refusals).toContain("create-refused");
    expect(r.statusAfterPersist).toEqual([""]);
    expect(reportSilentFallback).toHaveBeenCalledWith(null, expect.objectContaining({ op: "create-refused", tags: { class: cls } }));
    if (cls !== "persist" || detail.startsWith("changed")) expect(createCommits()).toHaveLength(0);
  });

  it("a scan refusal never reaches the commit helper even when later gates would pass (Guard 1 row 1)", async () => {
    h.scan.mockResolvedValue({ ok: false, detail: "review" });
    await run(PATTERNS_CREATE());
    expect(h.sync).not.toHaveBeenCalled();
    expect(h.collect).not.toHaveBeenCalled();
    expect(createCommits()).toHaveLength(0);
  });

  it("a rendered-output refusal (template unreadable) happens before any file is written or scan run", async () => {
    const git = gitFixture(remoteDir);
    execFileSync("git", ["-C", remoteDir, "rm", "-q", "plugins/soleur/skills/skill-creator/templates/purpose.md"]);
    git(["commit", "-qm", "drop template"]);
    try {
      const r = await run(PATTERNS_CREATE());
      expect(r.last).toMatchObject({ create_outcome: "refused", create_refusal_class: "shape", create_detail: "template-unreadable" });
      expect(h.scan).not.toHaveBeenCalled();
      expect(r.statusAfterPersist).toEqual([""]);
    } finally {
      git(["reset", "-q", "--hard", "HEAD~1"]);
    }
  });
});

// ---------------------------------------------------------------------------------------------------------
describe("replay (CTO G2): a second pass finds its own open PR and never opens a second", () => {
  it("Step B looks up its own open PR by the deterministic head branch; a hit is success and nothing is committed", async () => {
    h.ownPrs = [{ number: 4242, body: `${CREATE_PR_BODY_LINE}\n\nProposed by the loop.` }];
    const r = await run(PATTERNS_CREATE());
    expect(r.last).toMatchObject({ create_outcome: "opened", create_pr: 4242 });
    expect(createCommits()).toHaveLength(0);
    expect(h.scan).not.toHaveBeenCalled();
    expect(h.heads).toHaveLength(1);
    expect(h.heads[0]).toMatch(new RegExp(`^jikig-ai:${PROMOTE_BRANCH_PREFIX}${ENTRY_HASH}-\\d{4}-\\d{2}-\\d{2}$`));
  });

  it("through the real step boundary (every step memoized, the handler re-entered from the top) the arm makes exactly one model call and one create commit", async () => {
    const logger = { info: vi.fn(), warn: vi.fn(), error: vi.fn() };
    const out = await runLikeInngest(
      ({ step }) => cronCompoundPromoteHandler({ step, logger, event: PATTERNS_CREATE(), runId: "RUN-C" } as never),
      { maxAttempts: 2, maxInvocations: 60 },
    );
    expect(out.outcome).toBe("returned");
    expect(createPrompts()).toHaveLength(1);
    expect(createCommits()).toHaveLength(1);
    expect(editCommits()).toHaveLength(1);
    const rows = h.marker.mock.calls.map((c) => c[0] as Record<string, unknown>);
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({ status: "completed", create_arm: "ran", create_outcome: "opened", create_pr: 101 });
  });

  it("through the real step boundary a refused create is stable across re-entries: one model call, one mirrored refusal, one marker", async () => {
    createReply = { text: "not json", stopReason: "end_turn" };
    const logger = { info: vi.fn(), warn: vi.fn(), error: vi.fn() };
    const out = await runLikeInngest(
      ({ step }) => cronCompoundPromoteHandler({ step, logger, event: PATTERNS_CREATE(), runId: "RUN-C" } as never),
      { maxAttempts: 2, maxInvocations: 60 },
    );
    expect(out.outcome).toBe("returned");
    expect(createPrompts()).toHaveLength(1);
    const mirrors = vi.mocked(reportSilentFallback).mock.calls.filter((c) => (c[1] as { op?: string }).op === "create-refused");
    expect(mirrors).toHaveLength(1);
    const rows = h.marker.mock.calls.map((c) => c[0] as Record<string, unknown>);
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({ create_outcome: "refused", create_refusal_class: "model-invalid", create_detail: "not-json" });
    expect((rows[0].refusals as string[]).filter((x) => x === "create-refused")).toHaveLength(1);
  });
});

// ---------------------------------------------------------------------------------------------------------
describe("the open-PR path scan feeds the collision gates", () => {
  it("an open PR already touching the new slug's path refuses slug (open-pr-slug)", async () => {
    h.pulls.list = [{ number: 5, body: "x", labels: [] }];
    h.pulls.files[5] = [{ filename: `plugins/soleur/skills/${String(PROPOSAL.slug)}/SKILL.md` }];
    const r = await run(PATTERNS_CREATE());
    expect(r.last).toMatchObject({ create_outcome: "refused", create_refusal_class: "slug", create_detail: "open-pr-slug" });
    expect(createCommits()).toHaveLength(0);
  });

  it("an open PR touching the nearest skill refuses prefer-patch (open-pr-nearest)", async () => {
    const nearest = String(goodProposal().nearest_skill);
    h.pulls.list = [{ number: 6, body: "x", labels: [] }];
    h.pulls.files[6] = [{ filename: `plugins/soleur/skills/${nearest}/SKILL.md` }];
    const r = await run(PATTERNS_CREATE());
    expect(r.last).toMatchObject({ create_outcome: "refused", create_refusal_class: "prefer-patch", create_detail: "open-pr-nearest" });
  });
});

// ---------------------------------------------------------------------------------------------------------
describe("the marker for a create run", () => {
  it("an opened create carries exactly the closed create fields (no text), alongside the unchanged edit-arm fields", async () => {
    const r = await run(PATTERNS_CREATE());
    expect(createKeys(r.last).sort()).toEqual(["create_arm", "create_outcome", "create_pr", "create_requested", "kind"]);
    expect(r.last).toMatchObject({ clusters_proposed: 1, clusters_opened: 1, input_source: "patterns", ledger_read: "ok" });
    expect(JSON.stringify(r.last)).not.toContain(String(PROPOSAL.description));
  });

  it("a refused create does NOT count as an opened cluster, and mirrors exactly one Sentry event", async () => {
    createReply = { text: "x", stopReason: "end_turn" };
    const r = await run(PATTERNS_CREATE());
    expect(r.last).toMatchObject({ clusters_opened: 1 });
    expect(vi.mocked(reportSilentFallback).mock.calls.filter((c) => (c[1] as { op?: string }).op === "create-refused")).toHaveLength(1);
  });

  it("the scheduled-path equivalence holds: no create step name exists anywhere in a cron run", async () => {
    const r = await run(CRON());
    expect(r.names.filter((n) => n.startsWith("create-"))).toEqual([]);
  });
});

// ---------------------------------------------------------------------------------------------------------
describe("review round -- the same-run collision, the token, the lost clone, the bounds", () => {
  it("G4: a pattern whose hash the EDIT loop just opened is NOT offered; with another pattern present the model is called, and one that names the owned pattern anyway is the backstop: no_action(other), not a second suppression", async () => {
    // The edit loop opens a PR on exactly the create pattern's evidence set -> its branch is `self-healing/auto-<ENTRY_HASH>-<date>`.
    editClusters = [{ ...EDIT_CLUSTER, source_learnings: CREATE_EVIDENCE }];
    const r = await run(PATTERNS_CREATE());
    expect(editCommits()).toHaveLength(1);
    expect((editCommits()[0][0] as { branchName: string }).branchName).toContain(ENTRY_HASH);
    expect(createPrompts()).toHaveLength(1); // page-two is still offered
    expect(String((createPrompts()[0][0] as { messages: Array<{ content: string }> }).messages[0].content)).not.toContain(CREATE_PATTERN_SLUG);
    expect(createCommits()).toHaveLength(0); // the model named the owned pattern anyway: suppressed, never created
    expect(r.names).not.toContain("create-persist");
    expect(r.last).toMatchObject({ clusters_opened: 1, create_arm: "ran", create_outcome: "no_action", create_no_action_reason: "other", ledger_suppressed: 0 });
    expect(r.last.refusals).not.toContain("ledger-suppressed"); // the edit loop OPENED that hash; nothing was refused
    expect(r.last).not.toHaveProperty("create_pr");
  });

  it("G4: when the only pattern is owned by the edit loop this run there is NO create model call at all", async () => {
    const git = gitFixture(remoteDir);
    execFileSync("git", ["-C", remoteDir, "rm", "-q", "knowledge-base/project/patterns/page-two.md"]);
    git(["commit", "-qm", "drop page two"]);
    try {
      editClusters = [{ ...EDIT_CLUSTER, source_learnings: CREATE_EVIDENCE }];
      const r = await run(PATTERNS_CREATE());
      expect(createPrompts()).toHaveLength(0);
      expect(r.names).toContain("create-propose");
      expect(r.names).not.toContain("create-persist");
      expect(r.last).toMatchObject({ create_arm: "ran", create_outcome: "no_action", create_no_action_reason: "other", ledger_suppressed: 0 });
      expect(r.last).not.toHaveProperty("create_refusal_class");
    } finally {
      git(["reset", "-q", "--hard", "HEAD~1"]);
    }
  });

  it("G4: a hash the edit loop REFUSED (one refusal_detail entry) is not recorded a second time by the backstop; the counter stays 0", async () => {
    // an off-allowlist target is refused by the edit loop (`target-path-refused`) but its hash is still the run's
    editClusters = [{ ...EDIT_CLUSTER, target_path: "not/allowed.md", source_learnings: CREATE_EVIDENCE }];
    const r = await run(PATTERNS_CREATE());
    const entries = (r.last.refusal_detail as Array<{ cluster_hash: string; reason: string }>).filter((e) => e.cluster_hash === ENTRY_HASH);
    expect(entries).toHaveLength(1);
    expect(entries[0].reason).not.toBe("ledger-suppressed");
    expect(r.last).toMatchObject({ create_outcome: "no_action", create_no_action_reason: "other", ledger_suppressed: 0 });
  });

  it("G4: a hash the LEDGER suppresses (a prior PR) is still recorded once and counted once", async () => {
    h.ledger.items = [{
      title: promotePrTitle(ENTRY_HASH, "2026-10-04"), state: "open", closed_at: null,
      user: { login: "soleur-ai[bot]" }, pull_request: { merged_at: null },
    }];
    const r = await run(PATTERNS_CREATE());
    const entries = (r.last.refusal_detail as Array<{ cluster_hash: string; reason: string }>).filter((e) => e.cluster_hash === ENTRY_HASH);
    expect(entries).toHaveLength(1);
    expect(r.last).toMatchObject({ ledger_suppressed: 1 });
  });

  it("A: the create-propose step receives exactly the hashes the edit loop recorded (opened or attempted)", async () => {
    const r = await run(PATTERNS_CREATE());
    expect(editCommits()).toHaveLength(1);
    // a different evidence set: the edit hash is not the create hash, so the create proceeds and opens its own PR
    expect(r.last).toMatchObject({ create_outcome: "opened", clusters_opened: 1 });
    expect((createCommits()[0][0] as { branchName: string }).branchName).toContain(ENTRY_HASH);
    expect((editCommits()[0][0] as { branchName: string }).branchName).not.toContain(ENTRY_HASH);
  });

  it("L: a truncated clustering answer with allow_create never spends create-propose (no create step, no create call)", async () => {
    h.post.mockImplementation(async (a: { messages: Array<{ content: string }> }) => {
      if (a.messages[0].content.includes("clustering agent")) return { text: "{", stopReason: "max_tokens" };
      throw new Error("unstubbed prompt");
    });
    const r = await run(PATTERNS_CREATE());
    expect(r.result.status).toBe("anthropic-truncated");
    expect(r.names.some((n) => n.startsWith("create-"))).toBe(false);
    expect(createPrompts()).toHaveLength(0);
    expect(r.last).toMatchObject({ status: "anthropic-truncated", create_requested: true });
    expect(r.last).not.toHaveProperty("create_arm");
  });

  it("L: the open-PR path scan hitting a bound propagates through the handler adapter -> create-open/paths-incomplete, no model call", async () => {
    // 200 open PRs, each costing one file request: the scan's 150-request budget runs out; the one-open-create list (2 pages) is complete.
    h.pulls.list = Array.from({ length: 200 }, (_, i) => ({ number: 1000 + i, body: "an edit PR", labels: [], head: { ref: `feature/x${i}` } }));
    const r = await run(PATTERNS_CREATE());
    expect(r.last).toMatchObject({ create_outcome: "refused", create_refusal_class: "create-open", create_detail: "paths-incomplete" });
    expect(createPrompts()).toHaveLength(0);
  });

  it("L: an error AFTER the arm ran still carries the create fields on the error marker", async () => {
    h.marker.mockImplementationOnce(() => {
      throw new Error("marker sink exploded");
    });
    const r = await run(PATTERNS_CREATE());
    expect(r.markers.length).toBeGreaterThanOrEqual(2);
    expect(r.last).toMatchObject({ status: "error", create_requested: true, create_arm: "ran", kind: "create", create_outcome: "opened", create_pr: 101 });
  });

  it("F: refusal evidence numbers reach the marker through the typed allowlist (exit code, file index, path index, changed count, missing tools)", async () => {
    h.scan.mockResolvedValue({ ok: false, detail: "non-zero", fileIndex: 1, exit: 3, signal: "SIGKILL" });
    const scan = await run(PATTERNS_CREATE());
    expect(scan.last).toMatchObject({ create_refusal_class: "scan", create_detail: "non-zero", create_file_index: 1, create_exit: 3 });
    expect(JSON.stringify(scan.last)).not.toContain("SIGKILL"); // the signal name is Sentry-only

    h.scan.mockResolvedValue({ ok: false, detail: "missing-tool", missing: ["jq", "cut", "date"] });
    h.marker.mockClear();
    const tools = await run(PATTERNS_CREATE());
    expect(tools.last).toMatchObject({ create_detail: "missing-tool", create_missing_tools: 3 });
    expect(JSON.stringify(tools.last)).not.toContain('"jq"');

    h.scan.mockResolvedValue({ ok: true });
    h.sync.mockResolvedValue({ ok: false, detail: "unexpected-change", changedCount: 2 });
    h.marker.mockClear();
    const sync = await run(PATTERNS_CREATE());
    expect(sync.last).toMatchObject({ create_refusal_class: "readme-sync", create_changed_count: 2 });

    h.sync.mockResolvedValue({ ok: true });
    h.collect.mockResolvedValue({ ok: false, detail: "path-nul", index: 4 });
    h.marker.mockClear();
    const collect = await run(PATTERNS_CREATE());
    expect(collect.last).toMatchObject({ create_refusal_class: "persist", create_detail: "path-nul", create_path_index: 4 });
  });
});
