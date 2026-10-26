// #10552 -- handler-level behaviour of the two-step draft.
//
// This is the REGRESSION for the reported bug: with phase 1 stubbed to return clusters
// and phase 2 stubbed to return valid edits, every cluster must reach the apply step
// and none may end `diff-underivable-*`. It drives the real `cronCompoundPromoteHandler`
// against a real cloned git repo; only the network edges (Anthropic, GitHub search, the
// clone URL, the commit/PR helper) are stubbed. It lives in its own file because it
// replaces `_cron-shared` and `@octokit/core` wholesale, which would clobber the real
// imports the pure-function suites rely on (vitest hoists every vi.mock to file scope).
import { afterAll, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

const h = vi.hoisted(() => ({
  post: vi.fn(),
  safeCommit: vi.fn(),
  marker: vi.fn(),
  cloneUrl: "",
  workRoot: "",
  /** Every GitHub request the handler made: `{ route, params }`. */
  requests: [] as Array<{ route: string; params: Record<string, unknown> }>,
  /** Open PRs the pulls routes serve; `files` is served in pages of 100. Per-case. */
  openPrs: [] as Array<{ number: number; user?: { login: string } | null; files?: Array<{ filename: string }> }>,
  /** When set, the pulls list route throws it. */
  pullsError: null as unknown,
}));

vi.mock("@/server/observability", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/observability")>()),
  reportSilentFallback: vi.fn(),
}));
vi.mock("@octokit/core", () => ({
  Octokit: class {
    // Route-aware (#10552): the skill-conflict guard lists open PRs and their changed files.
    request = async (route: string, params: Record<string, unknown> = {}) => {
      h.requests.push({ route, params });
      if (route === "GET /repos/{owner}/{repo}/pulls" || route === "GET /repos/{owner}/{repo}/pulls/{pull_number}/files") {
        // The guard must ask for open PRs, 100 per page, of a real repo (a swapped or empty owner/repo
        // would silently scan nothing in production).
        if (typeof params.owner !== "string" || !params.owner || typeof params.repo !== "string" || !params.repo || params.owner === params.repo) {
          throw new Error(`bad owner/repo: ${String(params.owner)}/${String(params.repo)}`);
        }
        if (params.per_page !== 100 || (route.endsWith("/pulls") && params.state !== "open")) {
          throw new Error(`bad list params: ${JSON.stringify(params)}`);
        }
      }
      if (route === "GET /repos/{owner}/{repo}/pulls") {
        if (h.pullsError) throw h.pullsError;
        const page = Number(params.page ?? 1);
        return { data: h.openPrs.slice((page - 1) * 100, page * 100).map((p) => ({ number: p.number, user: p.user === undefined ? { login: "someone" } : p.user })) };
      }
      if (route === "GET /repos/{owner}/{repo}/pulls/{pull_number}/files") {
        const pr = h.openPrs.find((p) => p.number === params.pull_number);
        const page = Number(params.page ?? 1);
        return { data: (pr?.files ?? []).slice((page - 1) * 100, page * 100) };
      }
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

import { reportSilentFallback } from "@/server/observability";
import { PROMOTION_QUORUM, cronCompoundPromoteHandler } from "@/server/inngest/functions/cron-compound-promote";
import { gitFixture, gitFixtureEnv } from "../../../../../plugins/soleur/test/lib/git-fixture-env";

const L = (n: number) => `knowledge-base/project/learnings/l${n}.md`;
// Every fixture size derives from the constant, never a literal 5: a fixture that hard-codes
// the quorum keeps passing when the constant is lowered. `Ls(start, count)` is `count`
// consecutive corpus paths from `L(start)`.
const Q = PROMOTION_QUORUM;
const Ls = (start: number, count: number) => Array.from({ length: count }, (_, i) => L(start + i));
const SKILL = "plugins/soleur/skills/alpha/SKILL.md";
const SKILL_B = "plugins/soleur/skills/beta/SKILL.md";

const AGENTS_RULES = [
  "---",
  "last_reviewed: 2026-10-01",
  "---",
  "",
  "## Code Quality",
  "",
  "- Write tests first [id: cq-tests-first]. Because.",
  "- Keep it small [id: cq-keep-small]. Because.",
  "",
].join("\n");

const SKILL_TEXT = ["# Alpha", "", "## Steps", "", "- one", "- two", ""].join("\n");

let remoteDir: string;
let workRoot: string;
const savedGitEnv: Record<string, string | undefined> = {};

beforeAll(() => {
  // A hook-launched test run inherits GIT_DIR / GIT_INDEX_FILE, which would redirect
  // the handler's own un-scrubbed `git clone` at the surrounding repository.
  for (const k of Object.keys(process.env)) {
    if (k.startsWith("GIT_")) {
      savedGitEnv[k] = process.env[k];
      delete process.env[k];
    }
  }
  process.env.ANTHROPIC_API_KEY = "test-key";
  remoteDir = mkdtempSync(join(tmpdir(), "compound-handler-remote-"));
  workRoot = mkdtempSync(join(tmpdir(), "compound-handler-work-"));
  const git = gitFixture(remoteDir);
  git(["init", "-q", "-b", "main", "."]);
  const put = (p: string, t: string) => {
    mkdirSync(join(remoteDir, p, ".."), { recursive: true });
    writeFileSync(join(remoteDir, p), t);
  };
  put("AGENTS.md", "# AGENTS index\n\n- [id: cq-tests-first] -> rules\n");
  put("AGENTS.rules.md", AGENTS_RULES);
  put(SKILL, SKILL_TEXT);
  put(SKILL_B, SKILL_TEXT);
  put("knowledge-base/project/promotion-config.yml", "enabled: true\n");
  put("knowledge-base/project/learnings/promotion-log.md", "| date | hash | target | n | status | tier | pr |\n");
  for (let n = 1; n <= 2 * Q + 2; n++) put(L(n), `# Learning ${n}\n\nA recurring failure number ${n} about test ordering.\n`);
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

beforeEach(() => {
  expect.hasAssertions();
  h.post.mockReset();
  h.safeCommit.mockReset();
  h.marker.mockReset();
  vi.mocked(reportSilentFallback).mockClear();
  h.requests.length = 0;
  h.openPrs = [];
  h.pullsError = null;
  h.safeCommit.mockResolvedValue({ status: "committed" });
});

type Cl = {
  tier: "skill" | "agents-core";
  target_path: string;
  source_learnings: string[];
  rationale: string;
  /** A model-supplied field the schema no longer offers; the server must ignore it. */
  proposed_diff_unified?: string;
};
const AGENTS_CLUSTER: Cl = {
  tier: "agents-core",
  target_path: "AGENTS.rules.md",
  source_learnings: Ls(1, Q),
  rationale: "RATIONALE-AGENTS",
};
const SKILL_CLUSTER: Cl = {
  tier: "skill",
  target_path: SKILL,
  source_learnings: Ls(Q + 1, Q),
  rationale: "RATIONALE-SKILL",
};

const GOOD_AGENTS_EDIT = {
  insert_after_line: "- Keep it small [id: cq-keep-small]. Because.",
  new_lines: ["- Prefer small diffs [id: cq-small-diffs]. Reviewers read less."],
};
const GOOD_SKILL_EDIT = { insert_after_line: "## Steps", new_lines: ["- a new step"] };

/** Phase 1 answers with `clusters`; phase 2 answers per rationale via `edits`. */
function stubModel(clusters: Cl[], edits: Record<string, unknown>) {
  h.post.mockImplementation(async (a: { messages: Array<{ content: string }> }) => {
    const prompt = a.messages[0].content;
    if (prompt.includes("clustering agent")) {
      return { text: JSON.stringify({ clusters }), stopReason: "end_turn" };
    }
    for (const [needle, edit] of Object.entries(edits)) {
      if (prompt.includes(needle)) return { text: JSON.stringify(edit), stopReason: "end_turn" };
    }
    throw new Error("phase-2 prompt matched no stubbed edit");
  });
}

async function run(memo?: Map<string, unknown>) {
  const names: string[] = [];
  const step = {
    run: async <T,>(name: string, cb: () => Promise<T>): Promise<T> => {
      names.push(name);
      // Inngest serves a completed step from memo WITHOUT re-entering its callback.
      if (memo?.has(name)) return memo.get(name) as T;
      const v = await cb();
      memo?.set(name, v);
      return v;
    },
  };
  const logger = { info: vi.fn(), warn: vi.fn(), error: vi.fn() };
  const result = await cronCompoundPromoteHandler({
    step,
    logger,
    event: { name: "inngest/scheduled.timer" },
    runId: "RUN-H",
  });
  const markers = h.marker.mock.calls.map((c) => c[0] as Record<string, unknown>);
  return { result, names, markers, last: markers[markers.length - 1], logger };
}

const phase2Calls = () =>
  h.post.mock.calls.filter((c) => !(c[0] as { messages: Array<{ content: string }> }).messages[0].content.includes("clustering agent"));

describe("T15 (#10552): the reported bug -- a proposal now reaches the apply step", () => {
  it("TWO clusters (AGENTS.rules.md and a SKILL.md) each draft a derived diff and open; neither ends diff-underivable-*", async () => {
    stubModel([AGENTS_CLUSTER, SKILL_CLUSTER], {
      "RATIONALE-AGENTS": GOOD_AGENTS_EDIT,
      "RATIONALE-SKILL": GOOD_SKILL_EDIT,
    });
    const { last, names } = await run();
    expect(last).toMatchObject({ status: "completed", clusters_proposed: 2, clusters_opened: 2, refusals: [] });
    // M-7: BOTH drafts observed -- one model call each, one commit each. An absence of
    // refusals alone would also hold if the second draft were silently skipped.
    expect(phase2Calls()).toHaveLength(2);
    expect(h.safeCommit).toHaveBeenCalledTimes(2);
    const refusals = (last.refusals as string[]).join(",");
    expect(refusals).not.toContain("diff-underivable");
    // Ordering: each draft precedes its own apply.
    for (const hashStep of names.filter((n) => n.startsWith("draft-edit-"))) {
      const hash8 = hashStep.slice("draft-edit-".length);
      expect(names.indexOf(`apply-and-pr-${hash8}`)).toBeGreaterThan(names.indexOf(hashStep));
    }
    expect(names.filter((n) => n.startsWith("draft-edit-"))).toHaveLength(2);
    // CTO ruling (Fork 1): an AGENTS.rules.md draft is single-file, so the corpus lint
    // (lint-rule-ids: every body needs an AGENTS.md pointer) is red until a reviewer adds it.
    // The PR body is where the reviewer acts, so it names the exact slug to add. A skill draft
    // carries no such line.
    const bodies = h.safeCommit.mock.calls.map((c) => (c[0] as { prBody: string }).prBody);
    const agentsBody = bodies.find((b) => b.includes("cq-small-diffs"));
    const skillBody = bodies.find((b) => !b.includes("cq-small-diffs"));
    expect(agentsBody).toContain("lint-rule-ids");
    expect(agentsBody).toContain("`- [id: cq-small-diffs]`");
    expect(skillBody).toBeDefined();
    expect(skillBody).not.toContain("lint-rule-ids");
  });
});

describe("a refused draft is a counted, named refusal that skips the apply step", () => {
  it("a model anchor that is not in the file -> edit-anchor-not-found, no commit, no apply step, mirrored to Sentry", async () => {
    stubModel([AGENTS_CLUSTER], { "RATIONALE-AGENTS": { insert_after_line: "- Not in the file", new_lines: ["- Rule [id: cq-rule-x]. x"] } });
    const { last, names } = await run();
    expect(last).toMatchObject({ status: "completed", clusters_proposed: 1, clusters_opened: 0, refusals: ["edit-anchor-not-found"] });
    expect(h.safeCommit).not.toHaveBeenCalled();
    expect(names.some((n) => n.startsWith("apply-and-pr-"))).toBe(false);
    const detail = last.refusal_detail as Array<{ cluster_hash: string; reason: string }>;
    expect(detail).toHaveLength(1);
    expect(detail[0].reason).toBe("edit-anchor-not-found");
    expect(detail[0].cluster_hash).toMatch(/^[0-9a-f]{64}$/);
    // MESSAGE path with TAGS: on the Error path the pino mirror captures the same Error first
    // and Sentry drops the tagged capture, so `op`/`cause` never arrive (see anthropic-credit.ts).
    expect(reportSilentFallback).toHaveBeenCalledWith(
      null,
      expect.objectContaining({
        op: "draft-edit-refused",
        tags: { reason: "edit-anchor-not-found", cause: "absent" },
      }),
    );
  });

  it("refused-then-good: a REFUSED first draft does not block a later valid cluster on the same target", async () => {
    const second: Cl = { ...AGENTS_CLUSTER, source_learnings: Ls(Q + 1, Q), rationale: "RATIONALE-AGENTS-2" };
    stubModel([AGENTS_CLUSTER, second], {
      "RATIONALE-AGENTS-2": GOOD_AGENTS_EDIT,
      "RATIONALE-AGENTS": { insert_after_line: "- Not in the file", new_lines: ["- Rule [id: cq-rule-x]. x"] },
    });
    const { last } = await run();
    expect(last).toMatchObject({ clusters_proposed: 2, clusters_opened: 1, refusals: ["edit-anchor-not-found"] });
    expect(h.safeCommit).toHaveBeenCalledTimes(1);
  });

  it("T19: a second cluster on an already-drafted target is edit-target-duplicate and the model is NOT called for it", async () => {
    const second: Cl = { ...AGENTS_CLUSTER, source_learnings: Ls(Q + 1, Q), rationale: "RATIONALE-AGENTS-2" };
    stubModel([AGENTS_CLUSTER, second], { "RATIONALE-AGENTS": GOOD_AGENTS_EDIT });
    const { last } = await run();
    expect(last).toMatchObject({ clusters_proposed: 2, clusters_opened: 1, refusals: ["edit-target-duplicate"] });
    expect(phase2Calls()).toHaveLength(1);
    expect(h.safeCommit).toHaveBeenCalledTimes(1);
  });

  it("a disallowed target_path is target-path-refused by the draft step, and the model is not called for it", async () => {
    const bad: Cl = { ...AGENTS_CLUSTER, target_path: "apps/web-platform/server/x.ts" };
    stubModel([bad], {});
    const { last } = await run();
    expect(last).toMatchObject({ clusters_opened: 0, refusals: ["target-path-refused"] });
    expect(phase2Calls()).toHaveLength(0);
  });
});

describe("T16 (#10552): a phase-2 API error is a loud run error, not a refusal", () => {
  it("the run ends status=error and nothing is committed", async () => {
    h.post.mockImplementation(async (a: { messages: Array<{ content: string }> }) => {
      if (a.messages[0].content.includes("clustering agent")) {
        return { text: JSON.stringify({ clusters: [AGENTS_CLUSTER] }), stopReason: "end_turn" };
      }
      throw new Error("Anthropic API 500");
    });
    const { last } = await run();
    expect(last).toMatchObject({ status: "error" });
    expect(h.safeCommit).not.toHaveBeenCalled();
  });
});

describe("the derived diff is the ONLY diff (a model-supplied proposed_diff_unified is ignored)", () => {
  it("a hostile diff in the phase-1 answer neither applies nor changes the outcome", async () => {
    // Valid against the fixture and DESTRUCTIVE: it deletes a rule line. If it won, the shrink
    // floor would refuse (`corpus-shrink-refused`); the derived additive diff opens cleanly.
    const remoteGit = gitFixture(remoteDir);
    writeFileSync(join(remoteDir, "AGENTS.rules.md"), AGENTS_RULES.replace("- Keep it small [id: cq-keep-small]. Because.\n", ""));
    const hostile = remoteGit(["diff"]);
    remoteGit(["checkout", "--", "."]);
    expect(hostile).toContain("-- Keep it small");
    execFileSync("git", ["apply", "--check"], { cwd: remoteDir, input: hostile, env: gitFixtureEnv(remoteDir) });
    stubModel([{ ...AGENTS_CLUSTER, proposed_diff_unified: hostile }], { "RATIONALE-AGENTS": GOOD_AGENTS_EDIT });
    const { last } = await run();
    expect(last).toMatchObject({ clusters_opened: 1, refusals: [] });
  });
});

describe("model-supplied source_learnings never reach the commit trailers or PR body unless they are corpus paths", () => {
  it("a newline-bearing / unknown path is dropped before the cluster hash, the trailer and the PR body", async () => {
    const evil = "knowledge-base/project/learnings/x.md\nCo-Authored-By: Mallory <m@example.test>";
    stubModel([{ ...AGENTS_CLUSTER, source_learnings: [L(1), evil, "../../etc/passwd", ...Ls(2, Q - 1)] }], {
      "RATIONALE-AGENTS": GOOD_AGENTS_EDIT,
    });
    const { last } = await run();
    expect(last).toMatchObject({ clusters_opened: 1, refusals: [] });
    const cfg = h.safeCommit.mock.calls[0][0] as { commitBody: string; prBody: string };
    expect(cfg.commitBody).toContain(`Source-Learnings: ${Ls(1, Q).join(",")}\n`);
    expect(cfg.commitBody).not.toContain("Mallory");
    expect(cfg.prBody).not.toContain("Mallory");
    expect(cfg.prBody).not.toContain("etc/passwd");
  });

  it("a cluster whose every source learning is unknown is refused quorum-not-met (zero is below the quorum) and never calls the model", async () => {
    stubModel([{ ...AGENTS_CLUSTER, source_learnings: ["../../a", "../../b"] }], { "RATIONALE-AGENTS": GOOD_AGENTS_EDIT });
    const { last } = await run();
    expect(last).toMatchObject({ clusters_opened: 0, refusals: ["quorum-not-met"] });
    expect(phase2Calls()).toHaveLength(0);
    expect(reportSilentFallback).toHaveBeenCalledWith(
      null,
      expect.objectContaining({
        op: "draft-edit-refused",
        extra: { cluster_hash: expect.any(String), source_count: 0, proposed_count: 2 },
      }),
    );
  });
});

describe("replay: a resumed run reproduces the same marker from memoized steps", () => {
  it("the duplicate-target refusal survives a full replay and the model is not called again", async () => {
    const second: Cl = { ...AGENTS_CLUSTER, source_learnings: Ls(Q + 1, Q), rationale: "RATIONALE-AGENTS-2" };
    stubModel([AGENTS_CLUSTER, second], { "RATIONALE-AGENTS-2": GOOD_AGENTS_EDIT, "RATIONALE-AGENTS": GOOD_AGENTS_EDIT });
    const memo = new Map<string, unknown>();
    const first = await run(memo);
    const callsAfterFirst = h.post.mock.calls.length;
    const again = await run(memo);
    expect(first.last).toMatchObject({ clusters_opened: 1, refusals: ["edit-target-duplicate"] });
    // Same accumulators from memoized returns only: draftedTargets was rebuilt in the handler body.
    expect(again.last).toMatchObject({ clusters_opened: 1, refusals: ["edit-target-duplicate"] });
    expect(h.post.mock.calls.length).toBe(callsAfterFirst);
    expect(h.safeCommit).toHaveBeenCalledTimes(1);
  });
});

describe("headroom is divided across the clusters still to draft", () => {
  const headroomOf = (call: unknown[]): number =>
    Number(/headroom for this edit: (\d+) bytes/.exec((call[0] as { messages: Array<{ content: string }> }).messages[0].content)?.[1]);

  it("the first of two AGENTS-targeted drafts is offered about half of what a lone draft is", async () => {
    stubModel([AGENTS_CLUSTER], { "RATIONALE-AGENTS": GOOD_AGENTS_EDIT });
    await run();
    const lone = headroomOf(phase2Calls()[0]);
    h.post.mockReset();
    h.safeCommit.mockClear();
    const second: Cl = { ...AGENTS_CLUSTER, source_learnings: Ls(Q + 1, Q), rationale: "RATIONALE-AGENTS-2" };
    stubModel([AGENTS_CLUSTER, second], { "RATIONALE-AGENTS-2": GOOD_AGENTS_EDIT, "RATIONALE-AGENTS": GOOD_AGENTS_EDIT });
    await run();
    const first = headroomOf(phase2Calls()[0]);
    expect(lone).toBeGreaterThan(1000);
    expect(first).toBeLessThanOrEqual(Math.ceil(lone / 2));
    expect(first).toBeGreaterThan(lone / 2 - 2);
  });
});

describe("round 2: the parse boundary and the headroom order", () => {
  it("a hostile tier / non-string target_path / missing source_learnings cannot forge trailers or crash the run", async () => {
    h.post.mockImplementation(async (a: { messages: Array<{ content: string }> }) => {
      const prompt = a.messages[0].content;
      if (prompt.includes("clustering agent")) {
        return {
          text: JSON.stringify({
            clusters: [
              { ...AGENTS_CLUSTER, tier: "skill\nCo-Authored-By: Mallory <m@example.test>" },
              { ...SKILL_CLUSTER, target_path: 5, source_learnings: undefined },
            ],
          }),
          stopReason: "end_turn",
        };
      }
      return { text: JSON.stringify(GOOD_AGENTS_EDIT), stopReason: "end_turn" };
    });
    const { last } = await run();
    // The hostile-tier cluster opens with a COERCED tier; the malformed one is refused, never thrown.
    expect(last).toMatchObject({ status: "completed", clusters_opened: 1 });
    const cfg = h.safeCommit.mock.calls[0][0] as { commitBody: string; prBody: string };
    expect(cfg.commitBody).toContain("Tier: agents-core");
    expect(cfg.commitBody).not.toContain("Mallory");
    expect((last.refusals as string[]).length).toBe(1);
  });

  it("a null element in the clusters array is dropped, not a TypeError", async () => {
    h.post.mockImplementation(async (a: { messages: Array<{ content: string }> }) => {
      const prompt = a.messages[0].content;
      if (prompt.includes("clustering agent")) {
        return { text: JSON.stringify({ clusters: [null, AGENTS_CLUSTER] }), stopReason: "end_turn" };
      }
      return { text: JSON.stringify(GOOD_AGENTS_EDIT), stopReason: "end_turn" };
    });
    const { last } = await run();
    expect(last).toMatchObject({ status: "completed", clusters_opened: 1, refusals: [] });
  });

  it("duplicate source learnings are collapsed before the trailer and the threshold line", async () => {
    stubModel([{ ...AGENTS_CLUSTER, source_learnings: [L(1), L(1), L(1), ...Ls(1, Q)] }], { "RATIONALE-AGENTS": GOOD_AGENTS_EDIT });
    await run();
    const cfg = h.safeCommit.mock.calls[0][0] as { commitBody: string };
    expect(cfg.commitBody).toContain(`Source-Learnings: ${Ls(1, Q).join(",")}\n`);
    expect(cfg.commitBody).toContain(`Threshold-Hit: ${Q}/${Q}`);
  });

  it("an AGENTS draft that comes SECOND is offered the full headroom, not half", async () => {
    const headroomOf = (call: unknown[]): number =>
      Number(/headroom for this edit: (\d+) bytes/.exec((call[0] as { messages: Array<{ content: string }> }).messages[0].content)?.[1]);
    stubModel([AGENTS_CLUSTER], { "RATIONALE-AGENTS": GOOD_AGENTS_EDIT });
    await run();
    const lone = headroomOf(phase2Calls()[0]);
    h.post.mockReset();
    h.safeCommit.mockClear();
    stubModel([SKILL_CLUSTER, AGENTS_CLUSTER], { "RATIONALE-SKILL": GOOD_SKILL_EDIT, "RATIONALE-AGENTS": GOOD_AGENTS_EDIT });
    await run();
    const agentsCall = phase2Calls().find((c) => (c[0] as { messages: Array<{ content: string }> }).messages[0].content.includes("headroom for this edit"));
    expect(headroomOf(agentsCall as unknown[])).toBe(lone);
  });
});

// =============================================================================
// The server-enforced quorum: a cluster with fewer than PROMOTION_QUORUM distinct,
// corpus-resolved sources is refused `quorum-not-met` before the target file is read and
// before the phase-2 model call, through the same refusals[] / Sentry path as every other
// refusal. (The draft step's API-key check and always-loaded read still precede the drafter.)
// =============================================================================
describe("PROMOTION_QUORUM: a sub-quorum cluster is refused and never reaches phase 2", () => {
  const quorumEvents = () =>
    vi.mocked(reportSilentFallback).mock.calls.filter((c) => (c[1] as { op?: string }).op === "draft-edit-refused");
  const SUB = (start: number) => Ls(start, Q - 1);

  it("H1: Q-1 valid sources plus unknown paths -> quorum-not-met, no model call, no commit, exact Sentry shape, marker row carries no count", async () => {
    // Raw length Q+1 (above the quorum), resolved distinct Q-1 (below it): the resolved set decides.
    stubModel([{ ...AGENTS_CLUSTER, source_learnings: [...SUB(1), "../../a", "knowledge-base/project/learnings/nope.md"] }], {
      "RATIONALE-AGENTS": GOOD_AGENTS_EDIT,
    });
    const { last, names } = await run();
    expect(last).toMatchObject({ status: "completed", clusters_proposed: 1, clusters_opened: 0, refusals: ["quorum-not-met"] });
    expect(phase2Calls()).toHaveLength(0);
    expect(h.safeCommit).not.toHaveBeenCalled();
    expect(names.some((n) => n.startsWith("apply-and-pr-"))).toBe(false);
    const detail = last.refusal_detail as Array<Record<string, unknown>>;
    expect(detail).toHaveLength(1);
    // The marker field set is unchanged: the count rides Sentry only.
    expect(Object.keys(detail[0]).sort()).toEqual(["cluster_hash", "reason"]);
    expect(detail[0].reason).toBe("quorum-not-met");
    expect(reportSilentFallback).toHaveBeenCalledWith(
      null,
      expect.objectContaining({
        feature: "cron-compound-promote",
        op: "draft-edit-refused",
        message: "draft edit refused: quorum-not-met (below-quorum)",
        tags: { reason: "quorum-not-met", cause: "below-quorum" },
        // Exact: bare integers only, nothing else rides the event.
        extra: {
          cluster_hash: expect.stringMatching(/^[0-9a-f]{64}$/),
          source_count: Q - 1,
          proposed_count: Q + 1,
        },
      }),
    );
  });

  it("H1b: a non-array source_learnings is a quorum refusal with proposed_count 0; other refusals carry no counts", async () => {
    stubModel(
      [{ ...AGENTS_CLUSTER, source_learnings: "not-an-array" as unknown as string[] }],
      { "RATIONALE-AGENTS": GOOD_AGENTS_EDIT },
    );
    const nonArray = await run();
    expect(nonArray.last).toMatchObject({ clusters_opened: 0, refusals: ["quorum-not-met"] });
    expect(reportSilentFallback).toHaveBeenCalledWith(
      null,
      expect.objectContaining({
        op: "draft-edit-refused",
        extra: { cluster_hash: expect.any(String), source_count: 0, proposed_count: 0 },
      }),
    );

    vi.mocked(reportSilentFallback).mockClear();
    h.post.mockReset();
    // A different refusal on a full-quorum cluster must not grow count fields.
    stubModel([AGENTS_CLUSTER], {
      "RATIONALE-AGENTS": { insert_after_line: "- Not in the file", new_lines: ["- Rule [id: cq-rule-x]. x"] },
    });
    const other = await run();
    expect(other.last).toMatchObject({ refusals: ["edit-anchor-not-found"] });
    expect(reportSilentFallback).toHaveBeenCalledWith(
      null,
      expect.objectContaining({
        op: "draft-edit-refused",
        extra: { cluster_hash: expect.any(String) },
      }),
    );
  });

  it("H2: a sub-quorum cluster beside a valid one (either order, different targets): one opens, one is refused, the run is a green completed one", async () => {
    for (const order of ["valid-first", "sub-first"] as const) {
      h.post.mockReset();
      h.safeCommit.mockClear();
      vi.mocked(reportSilentFallback).mockClear();
      const valid = AGENTS_CLUSTER;
      const sub: Cl = { ...SKILL_CLUSTER, source_learnings: SUB(Q + 1) };
      stubModel(order === "valid-first" ? [valid, sub] : [sub, valid], {
        "RATIONALE-AGENTS": GOOD_AGENTS_EDIT,
        "RATIONALE-SKILL": GOOD_SKILL_EDIT,
      });
      const { last, names } = await run();
      expect(last, order).toMatchObject({ status: "completed", clusters_proposed: 2, clusters_opened: 1, refusals: ["quorum-not-met"] });
      // The refused cluster is OBSERVED refused (one phase-2 call total, for the valid one),
      // not merely absent.
      expect(phase2Calls(), order).toHaveLength(1);
      expect(h.safeCommit, order).toHaveBeenCalledTimes(1);
      expect(quorumEvents(), order).toHaveLength(1);
      expect(names, order).toContain("sentry-heartbeat");
    }
  });

  it("H3: a quorum-refused target is not consumed -- a later valid cluster on the same target drafts and opens", async () => {
    const sub: Cl = { ...AGENTS_CLUSTER, source_learnings: SUB(Q + 1), rationale: "RATIONALE-AGENTS-SUB" };
    stubModel([sub, AGENTS_CLUSTER], { "RATIONALE-AGENTS": GOOD_AGENTS_EDIT });
    const { last } = await run();
    expect(last).toMatchObject({ clusters_proposed: 2, clusters_opened: 1, refusals: ["quorum-not-met"] });
    expect(last.refusals).not.toContain("edit-target-duplicate");
    expect(phase2Calls()).toHaveLength(1);
  });

  it("H4: a valid cluster drafts first, then a sub-quorum cluster on the SAME target is edit-target-duplicate (duplicate outranks quorum)", async () => {
    const sub: Cl = { ...AGENTS_CLUSTER, source_learnings: SUB(Q + 1), rationale: "RATIONALE-AGENTS-SUB" };
    stubModel([AGENTS_CLUSTER, sub], { "RATIONALE-AGENTS": GOOD_AGENTS_EDIT });
    const { last } = await run();
    expect(last).toMatchObject({ clusters_opened: 1, refusals: ["edit-target-duplicate"] });
  });

  it("H5: an off-allowlist target_path with a sub-quorum list is target-path-refused (the security signal wins)", async () => {
    stubModel([{ ...AGENTS_CLUSTER, target_path: "apps/web-platform/server/x.ts", source_learnings: SUB(1) }], {});
    const { last } = await run();
    expect(last).toMatchObject({ clusters_opened: 0, refusals: ["target-path-refused"] });
    expect(last.refusals).not.toContain("quorum-not-met");
  });

  it("H6: exactly Q and Q+2 sources both open, and the trailer is built from the constant", async () => {
    for (const n of [Q, Q + 2]) {
      h.post.mockReset();
      h.safeCommit.mockClear();
      stubModel([{ ...AGENTS_CLUSTER, source_learnings: Ls(1, n) }], { "RATIONALE-AGENTS": GOOD_AGENTS_EDIT });
      const { last } = await run();
      expect(last, `n=${n}`).toMatchObject({ clusters_opened: 1, refusals: [] });
      const cfg = h.safeCommit.mock.calls[0][0] as { commitBody: string };
      expect(cfg.commitBody, `n=${n}`).toContain(`Threshold-Hit: ${n}/${Q}`);
      expect(cfg.commitBody, `n=${n}`).toContain(`Source-Learnings: ${Ls(1, n).join(",")}\n`);
    }
  });

  it("H7: a full replay reproduces the refusal from the memo and the Sentry event fires exactly once per step", async () => {
    stubModel([{ ...AGENTS_CLUSTER, source_learnings: SUB(1) }], { "RATIONALE-AGENTS": GOOD_AGENTS_EDIT });
    const memo = new Map<string, unknown>();
    const first = await run(memo);
    expect(quorumEvents()).toHaveLength(1);
    const callsAfterFirst = h.post.mock.calls.length;
    const again = await run(memo);
    expect(first.last).toMatchObject({ clusters_opened: 0, refusals: ["quorum-not-met"] });
    expect(again.last).toMatchObject({ clusters_opened: 0, refusals: ["quorum-not-met"] });
    // Asserting only "unchanged" would pass vacuously if the event never fired; the mock is
    // cleared only in beforeEach, so the count after pass 2 is still 1.
    expect(quorumEvents()).toHaveLength(1);
    expect(h.post.mock.calls.length).toBe(callsAfterFirst);
  });

  it("H8: two sub-quorum clusters with identical or empty lists are each counted and each reported", async () => {
    // The cluster hash is over the sorted sources only, so identical lists share the step
    // name `draft-edit-<hash8>`. With no memo map the harness does not alias them.
    const a: Cl = { ...AGENTS_CLUSTER, source_learnings: SUB(1) };
    const b: Cl = { ...SKILL_CLUSTER, source_learnings: SUB(1) };
    stubModel([a, b], {});
    const same = await run();
    expect(same.last).toMatchObject({ clusters_opened: 0, refusals: ["quorum-not-met", "quorum-not-met"] });
    expect(quorumEvents()).toHaveLength(2);

    vi.mocked(reportSilentFallback).mockClear();
    h.post.mockReset();
    stubModel([{ ...AGENTS_CLUSTER, source_learnings: [] }, { ...SKILL_CLUSTER, source_learnings: [] }], {});
    const empty = await run();
    expect(empty.last).toMatchObject({ clusters_opened: 0, refusals: ["quorum-not-met", "quorum-not-met"] });
    expect(quorumEvents()).toHaveLength(2);
    expect(phase2Calls()).toHaveLength(0);
  });
});

describe("#10552: the skill-conflict guard decides on the same file and never posts a comment", () => {
  const SKILL_B_CLUSTER: Cl = { tier: "skill", target_path: SKILL_B, source_learnings: Ls(2 * Q + 1, 1).concat(Ls(1, Q - 1)), rationale: "RATIONALE-SKILL-B" };
  const EDITS = { "RATIONALE-AGENTS": GOOD_AGENTS_EDIT, "RATIONALE-SKILL-B": GOOD_SKILL_EDIT, "RATIONALE-SKILL": GOOD_SKILL_EDIT };
  const pulls = () => h.requests.filter((r) => r.route === "GET /repos/{owner}/{repo}/pulls");
  const fileLists = () => h.requests.filter((r) => r.route === "GET /repos/{owner}/{repo}/pulls/{pull_number}/files");
  const sentryOps = () => vi.mocked(reportSilentFallback).mock.calls.map((c) => (c[1] as { op: string }).op);
  const warnLines = (logger: { warn: ReturnType<typeof vi.fn> }) => logger.warn.mock.calls.map((c) => String(c[1]));
  // The removed guard was a title/body SEARCH; nothing in the handler may ask for it again.
  const searchedByFiles = () => h.requests.filter((r) => /in:files|plugins\/soleur\/skills/.test(String(r.params.q ?? "")));

  it("different-file: an open PR that touches OTHER files (the live #10812 shape) does not block the skill cluster", async () => {
    h.openPrs = [{ number: 10812, files: [{ filename: "plugins/soleur/skills/gemini-imagegen/requirements.txt" }] }];
    stubModel([AGENTS_CLUSTER, SKILL_CLUSTER], EDITS);
    const { last } = await run();
    expect(last).toMatchObject({ clusters_proposed: 2, clusters_opened: 2, refusals: [] });
    expect(fileLists()).toHaveLength(1);
    expect(searchedByFiles()).toHaveLength(0);
  });

  it("same-file: an open PR that changes the target refuses it as skill-conflict-guard, with no POST and no comment", async () => {
    h.openPrs = [{ number: 4242, files: [{ filename: SKILL }] }];
    stubModel([AGENTS_CLUSTER, SKILL_CLUSTER], EDITS);
    const { last, logger } = await run();
    expect(last).toMatchObject({ clusters_proposed: 2, clusters_opened: 1, refusals: ["skill-conflict-guard"] });
    expect(h.safeCommit).toHaveBeenCalledTimes(1);
    expect(h.requests.some((r) => r.route.startsWith("POST") || r.route.includes("comments"))).toBe(false);
    // The conflicting PR number rides the warn line (Better Stack), not a comment and not Sentry.
    expect(warnLines(logger)).toContain("skill-conflict-guard-refused");
    const line = logger.warn.mock.calls.find((c) => c[1] === "skill-conflict-guard-refused")![0] as Record<string, unknown>;
    expect(line).toMatchObject({ pr: 4242, target: SKILL });
    expect(sentryOps().some((o) => o.startsWith("skill-conflict-guard"))).toBe(false);
    expect(searchedByFiles()).toHaveLength(0);
  });

  it("unverifiable: a scan that hits its bound refuses the skill cluster by name, mirrors it to Sentry, and the AGENTS cluster still opens", async () => {
    h.openPrs = Array.from({ length: 300 }, (_, i) => ({ number: i + 1, user: { login: "dependabot[bot]" } }));
    stubModel([AGENTS_CLUSTER, SKILL_CLUSTER], EDITS);
    const { last, logger } = await run();
    expect(last).toMatchObject({ clusters_opened: 1, refusals: ["skill-conflict-guard-unverifiable"] });
    expect(pulls()).toHaveLength(3);
    expect(reportSilentFallback).toHaveBeenCalledWith(
      null,
      expect.objectContaining({ op: "skill-conflict-guard-unverifiable", tags: { bound: "prs" } }),
    );
    expect(warnLines(logger)).toContain("skill-conflict-guard-unverifiable");
    const warn = logger.warn.mock.calls.find((c) => c[1] === "skill-conflict-guard-unverifiable")![0] as Record<string, unknown>;
    expect(warn).toMatchObject({ fn: "cron-compound-promote", bound: "prs" });
    expect(warn.hash).toMatch(/^[0-9a-f]{64}$/);
    expect(reportSilentFallback).toHaveBeenCalledWith(
      null,
      expect.objectContaining({
        message: "skill conflict scan incomplete: prs",
        extra: { cluster_hash: warn.hash },
      }),
    );
  });

  it("unverifiable via the FILES bound (one PR whose list fills every page) carries that bound end to end", async () => {
    h.openPrs = [{ number: 77, files: Array.from({ length: 1000 }, (_, i) => ({ filename: `docs/f-${i}.md` })) }];
    stubModel([AGENTS_CLUSTER, SKILL_CLUSTER], EDITS);
    const { last, logger } = await run();
    expect(last).toMatchObject({ clusters_opened: 1, refusals: ["skill-conflict-guard-unverifiable"] });
    expect(reportSilentFallback).toHaveBeenCalledWith(null, expect.objectContaining({ tags: { bound: "files" } }));
    const warn = logger.warn.mock.calls.find((c) => c[1] === "skill-conflict-guard-unverifiable")![0] as Record<string, unknown>;
    expect(warn.bound).toBe("files");
  });

  it("verdict order is per cluster: a CONFLICTING cluster first does not taint a clean one after it", async () => {
    h.openPrs = [{ number: 9, files: [{ filename: SKILL }] }];
    stubModel([SKILL_CLUSTER, SKILL_B_CLUSTER], EDITS);
    const { last, logger } = await run();
    expect(last).toMatchObject({ clusters_proposed: 2, clusters_opened: 1, refusals: ["skill-conflict-guard"] });
    const refused = logger.warn.mock.calls.filter((c) => c[1] === "skill-conflict-guard-refused").map((c) => (c[0] as { target: string }).target);
    expect(refused).toEqual([SKILL]);
    // The opened PR is the clean one (SKILL_B), not the conflicting one.
    const opened = h.safeCommit.mock.calls.map((c) => JSON.stringify(c[0]));
    expect(opened).toHaveLength(1);
    expect(opened[0]).toContain("beta");
    expect(opened[0]).not.toContain("alpha");
  });

  it("one scan is shared by two skill clusters, and the second still gets its own verdict", async () => {
    h.openPrs = [{ number: 9, files: [{ filename: SKILL_B }] }];
    stubModel([SKILL_CLUSTER, SKILL_B_CLUSTER], EDITS);
    const { last, names } = await run();
    expect(names.filter((n) => n === "skill-conflict-scan")).toHaveLength(1);
    expect(pulls()).toHaveLength(1);
    expect(last).toMatchObject({ clusters_proposed: 2, clusters_opened: 1, refusals: ["skill-conflict-guard"] });
  });

  it("an AGENTS.rules.md-only run makes no pulls request at all", async () => {
    stubModel([AGENTS_CLUSTER], EDITS);
    const { last, names } = await run();
    expect(last).toMatchObject({ clusters_opened: 1, refusals: [] });
    expect(pulls()).toHaveLength(0);
    expect(names).not.toContain("skill-conflict-scan");
  });

  it("a skill cluster refused before it drafts (sub-quorum) makes no pulls request", async () => {
    stubModel([{ ...SKILL_CLUSTER, source_learnings: ["../../a", "../../b"] }], EDITS);
    const { last, names } = await run();
    expect(last).toMatchObject({ clusters_opened: 0, refusals: ["quorum-not-met"] });
    expect(pulls()).toHaveLength(0);
    expect(names).not.toContain("skill-conflict-scan");
  });

  it("fail closed: a GitHub error during the scan ends the run in error and commits nothing", async () => {
    h.pullsError = new Error("HTTP 502");
    stubModel([SKILL_CLUSTER], EDITS);
    const { last } = await run();
    expect(last).toMatchObject({ status: "error" });
    expect(h.safeCommit).not.toHaveBeenCalled();
  });

  it("replay: a resumed run reuses the memoized scan and makes no new pulls request", async () => {
    h.openPrs = [{ number: 4242, files: [{ filename: SKILL }] }];
    stubModel([SKILL_CLUSTER], EDITS);
    const memo = new Map<string, unknown>();
    await run(memo);
    const before = pulls().length;
    h.safeCommit.mockClear();
    h.marker.mockClear();
    const second = await run(memo);
    expect(pulls()).toHaveLength(before);
    expect(second.last).toMatchObject({ refusals: ["skill-conflict-guard"] });
  });
});
