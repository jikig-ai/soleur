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
}));

vi.mock("@/server/observability", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/observability")>()),
  reportSilentFallback: vi.fn(),
}));
vi.mock("@octokit/core", () => ({
  Octokit: class {
    request = async () => ({ data: { total_count: 0, items: [] } });
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
import { cronCompoundPromoteHandler } from "@/server/inngest/functions/cron-compound-promote";
import { gitFixture } from "../../../../../plugins/soleur/test/lib/git-fixture-env";

const L = (n: number) => `knowledge-base/project/learnings/l${n}.md`;
const SKILL = "plugins/soleur/skills/alpha/SKILL.md";

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
  put("knowledge-base/project/promotion-config.yml", "enabled: true\n");
  put("knowledge-base/project/learnings/promotion-log.md", "| date | hash | target | n | status | tier | pr |\n");
  for (let n = 1; n <= 6; n++) put(L(n), `# Learning ${n}\n\nA recurring failure number ${n} about test ordering.\n`);
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
  h.safeCommit.mockResolvedValue({ status: "committed" });
});

type Cl = { tier: "skill" | "agents-core"; target_path: string; source_learnings: string[]; rationale: string };
const AGENTS_CLUSTER: Cl = {
  tier: "agents-core",
  target_path: "AGENTS.rules.md",
  source_learnings: [L(1), L(2)],
  rationale: "RATIONALE-AGENTS",
};
const SKILL_CLUSTER: Cl = {
  tier: "skill",
  target_path: SKILL,
  source_learnings: [L(3), L(4)],
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

async function run() {
  const names: string[] = [];
  const step = {
    run: async <T,>(name: string, cb: () => Promise<T>): Promise<T> => {
      names.push(name);
      return cb();
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
  return { result, names, markers, last: markers[markers.length - 1] };
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
  });
});

describe("a refused draft is a counted, named refusal that skips the apply step", () => {
  it("a model anchor that is not in the file -> edit-anchor-not-found, no commit, no apply step, mirrored to Sentry", async () => {
    stubModel([AGENTS_CLUSTER], { "RATIONALE-AGENTS": { insert_after_line: "- Not in the file", new_lines: ["- Rule [id: cq-r]. x"] } });
    const { last, names } = await run();
    expect(last).toMatchObject({ status: "completed", clusters_proposed: 1, clusters_opened: 0, refusals: ["edit-anchor-not-found"] });
    expect(h.safeCommit).not.toHaveBeenCalled();
    expect(names.some((n) => n.startsWith("apply-and-pr-"))).toBe(false);
    const detail = last.refusal_detail as Array<{ cluster_hash: string; reason: string }>;
    expect(detail).toHaveLength(1);
    expect(detail[0].reason).toBe("edit-anchor-not-found");
    expect(detail[0].cluster_hash).toMatch(/^[0-9a-f]{64}$/);
    expect(reportSilentFallback).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ op: "draft-edit-refused" }),
    );
  });

  it("T19: a second cluster on an already-drafted target is edit-target-duplicate and the model is NOT called for it", async () => {
    const second: Cl = { ...AGENTS_CLUSTER, source_learnings: [L(5), L(6)], rationale: "RATIONALE-AGENTS-2" };
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
