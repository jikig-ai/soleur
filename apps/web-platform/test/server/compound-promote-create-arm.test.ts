// WikiSkill Phase 2 (#10550) -- the create arm's two step bodies, unit level.
//
// The handler-level behaviour (invariance, week cap, ordering, replay through the real step boundary) is in
// test/server/inngest/cron-compound-promote-create-handler.test.ts. This file owns what only a unit can reach:
// the one-open-create probe's pagination and failure modes, Step A's "never throws" contract and every refusal
// that does not need the whole handler, and the PR body's fixed text.
import { afterAll, beforeEach, describe, expect, it, vi } from "vitest";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";

vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});
vi.mock("@/server/observability", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/observability")>()),
  reportSilentFallback: vi.fn(),
}));
import { reportSilentFallback } from "@/server/observability";
import {
  BASE_BLOB_PATHS,
  CREATE_ARM_FEATURE,
  CREATE_HEAD_PREFIX,
  REAL_CHECK_NAMES,
  SCHEDULED_ISSUE_LABEL,
  causeToken,
  CREATE_MODEL_TIMEOUT_MS,
  CREATE_OPEN_PR_PAGES,
  CREATE_PR_PATH_PREFIXES,
  CREATE_REFUSED_OP,
  buildCreatePrBody,
  createBranchName,
  findOpenCreatePr,
  mirrorCreateRefusal,
  runCreatePersistStep,
  runCreateProposeStep,
  type CreateProposeArgs,
  type CreateVerdictCreate,
} from "@/server/compound-promote-create-arm";
import {
  COMPONENTS_TEST_PATH,
  CREATE_MAX_TOKENS,
  CREATE_PR_BODY_LINE,
  PROMOTION_LOG_PATH,
  OVERLAP_REFUSE_THRESHOLD,
  countDescriptionWords,
  createClusterHash,
  proposalOverlapText,
  rankOverlap,
  type SkillRecord,
} from "@/server/compound-promote-create";
import type { PatternPage } from "@/server/compound-promote-patterns";
import { PROMOTE_BRANCH_PREFIX } from "@/server/compound-promote-ledger";
import { CREATE_EXCLUDED_SYNTHETIC_CHECKS, CREATE_FEATURE_NAME, GIT_MAX_TIMEOUT_MS, GIT_TIMEOUT_MS, README_PATHS } from "@/server/compound-promote-create-gates";

const FIX = join(__dirname, "..", "fixtures", "compound-promote-create");
const SKILLS = JSON.parse(readFileSync(join(FIX, "skills.json"), "utf8")) as SkillRecord[];
const PROPOSAL = JSON.parse(readFileSync(join(FIX, "proposal.json"), "utf8")) as Record<string, unknown>;
const PATTERN: PatternPage = {
  slug: String(PROPOSAL.pattern_slug), title: "Synthetic", summary: "Synthetic summary.", status: "open", openedOn: "2026-10-01", tags: ["retry"],
  evidence: [1, 2, 3, 4, 5].map((n) => `knowledge-base/project/learnings/2026-10-0${n}-synthetic-${n}.md`), requiredReading: false,
};

const roots: string[] = [];
afterAll(() => {
  for (const r of roots) rmSync(r, { recursive: true, force: true });
});

beforeEach(() => {
  expect.hasAssertions();
  vi.mocked(reportSilentFallback).mockClear();
});

// ---------------------------------------------------------------------------------------------------------
describe("findOpenCreatePr -- one open create at a time", () => {
  const HEAD = `${CREATE_HEAD_PREFIX}${"a".repeat(64)}-2026-10-26`;
  const pr = (n: number, body: string, ref: string | null = HEAD, fullName: string | null = "o/r") =>
    ({ number: n, body, head: ref === null ? null : { ref, ...(fullName === null ? {} : { repo: { full_name: fullName } }) } });
  const octokitOf = (pages: unknown[][] | Error) => {
    const calls: Array<Record<string, unknown>> = [];
    return {
      calls,
      octokit: {
        request: async (route: string, params: Record<string, unknown>) => {
          calls.push({ route, ...params });
          if (pages instanceof Error) throw pages;
          return { data: pages[(params.page as number) - 1] ?? [] };
        },
      } as never,
    };
  };

  it("finds a PR by head-ref prefix plus the fixed body line, by literal-route GET /pulls with state=open", async () => {
    const { octokit, calls } = octokitOf([[pr(1, "edit"), pr(2, `${CREATE_PR_BODY_LINE}\nrest`)]]);
    expect(await findOpenCreatePr(octokit, "o", "r")).toEqual({ kind: "open", pr: 2 });
    expect(calls[0]).toMatchObject({ route: "GET /repos/{owner}/{repo}/pulls", state: "open", per_page: 100, page: 1 });
  });

  it("does NOT depend on the best-effort label: a labelless create PR still counts (a label failure must not allow a second open create)", async () => {
    const labelless = { number: 7, body: CREATE_PR_BODY_LINE, head: { ref: HEAD, repo: { full_name: "o/r" } }, labels: [] };
    expect(await findOpenCreatePr(octokitOf([[labelless]]).octokit, "o", "r")).toEqual({ kind: "open", pr: 7 });
  });

  it("ignores the line on a PR whose head is not a bot branch, a bot branch without the line, and null shapes", async () => {
    const { octokit } = octokitOf([[pr(1, CREATE_PR_BODY_LINE, "feature/x"), pr(2, "edit"), pr(3, CREATE_PR_BODY_LINE, null), { number: 4, body: null, head: { ref: HEAD, repo: { full_name: "o/r" } } }, { number: 5, body: CREATE_PR_BODY_LINE }]]);
    expect(await findOpenCreatePr(octokit, "o", "r")).toEqual({ kind: "none" });
  });

  it("G2: a FORK PR (head repo is not this repo, or unknown/deleted) with the bot branch name and the body line does NOT block the arm", async () => {
    const { octokit } = octokitOf([[
      pr(1, CREATE_PR_BODY_LINE, HEAD, "attacker/r"),
      pr(2, CREATE_PR_BODY_LINE, HEAD, "o/r-fork"),
      pr(3, CREATE_PR_BODY_LINE, HEAD, null), // head.repo missing (a deleted fork): not ours
      { number: 4, body: CREATE_PR_BODY_LINE, head: { ref: HEAD, repo: null } },
      pr(5, CREATE_PR_BODY_LINE, HEAD, "O/R"), // case differs: GitHub reports the canonical name, so a mismatch is not ours either
    ]]);
    expect(await findOpenCreatePr(octokit, "o", "r")).toEqual({ kind: "none" });
    // and the same PR from THIS repo is found (the assertion can fail)
    const { octokit: own } = octokitOf([[pr(1, CREATE_PR_BODY_LINE, HEAD, "attacker/r"), pr(9, CREATE_PR_BODY_LINE, HEAD, "o/r")]]);
    expect(await findOpenCreatePr(own, "o", "r")).toEqual({ kind: "open", pr: 9 });
  });

  it("walks pages until a short one; a FULL last allowed page is unverifiable (never inferred clear)", async () => {
    const full = Array.from({ length: 100 }, (_, i) => pr(i + 1, "edit"));
    const { octokit: ok, calls } = octokitOf([full, [pr(500, `${CREATE_PR_BODY_LINE}`)]]);
    expect(await findOpenCreatePr(ok, "o", "r")).toEqual({ kind: "open", pr: 500 });
    expect(calls.map((c) => c.page)).toEqual([1, 2]);
    const { octokit: capped } = octokitOf(Array.from({ length: CREATE_OPEN_PR_PAGES }, () => full));
    expect(await findOpenCreatePr(capped, "o", "r")).toEqual({ kind: "unverifiable", detail: "list-incomplete" });
  });

  it("a request error and a non-array payload are unverifiable list-failed, with a closed cause token", async () => {
    expect(await findOpenCreatePr(octokitOf(Object.assign(new Error("rate limited, body: secret-ish"), { status: 429 })).octokit, "o", "r")).toEqual({ kind: "unverifiable", detail: "list-failed", cause: "http-429" });
    const weird = { request: async () => ({ data: { not: "an array" } }) } as never;
    expect(await findOpenCreatePr(weird, "o", "r")).toEqual({ kind: "unverifiable", detail: "list-failed", cause: "non-array" });
  });
});

describe("derived constants (no duplicated literal arrays)", () => {
  it("the base blob set, the head prefix and the real-check names are DERIVED from their owners", () => {
    expect([...BASE_BLOB_PATHS]).toEqual([...README_PATHS, PROMOTION_LOG_PATH, COMPONENTS_TEST_PATH]);
    expect(CREATE_HEAD_PREFIX).toBe(PROMOTE_BRANCH_PREFIX);
    expect(REAL_CHECK_NAMES).toBe(CREATE_EXCLUDED_SYNTHETIC_CHECKS);
    expect(CREATE_ARM_FEATURE).toBe(CREATE_FEATURE_NAME);
    expect(GIT_MAX_TIMEOUT_MS).toBe(GIT_TIMEOUT_MS * 2);
  });
});

describe("causeToken -- a closed token, never a message", () => {
  it("maps an HTTP status, an allowlisted errno code or class name; everything else is `unknown`", () => {
    expect(causeToken(Object.assign(new Error("x"), { status: 429 }))).toBe("http-429");
    expect(causeToken(Object.assign(new Error("x"), { status: 99 }))).toBe("Error");
    expect(causeToken(Object.assign(new Error("x"), { code: "ENOENT" }))).toBe("ENOENT");
    expect(causeToken(Object.assign(new Error("x"), { code: "EWEIRD" }))).toBe("Error");
    expect(causeToken(Object.assign(new Error("x"), { name: "TimeoutError" }))).toBe("TimeoutError");
    expect(causeToken(new Error("Anthropic API request failed (TimeoutError)"))).toBe("TimeoutError");
    expect(causeToken(new Error("some free text with a token ghs_secret"))).toBe("Error");
    expect(causeToken(Object.assign(new Error("x"), { name: "EvilName; drop table" }))).toBe("unknown");
    for (const odd of [null, undefined, "str", 42]) expect(causeToken(odd)).toBe("unknown");
  });
});

// ---------------------------------------------------------------------------------------------------------
function pluginTree(opts: { skills?: number; cap?: number | null } = {}): string {
  const root = mkdtempSync(join(tmpdir(), "create-arm-"));
  roots.push(root);
  const put = (p: string, t: string) => {
    mkdirSync(dirname(join(root, p)), { recursive: true });
    writeFileSync(join(root, p), t);
  };
  const records = [...SKILLS];
  for (let i = 0; i < (opts.skills ?? 40); i++) records.push({ name: `filler-${i}`, description: `This skill should be used for filler topic ${i}.`, disableModelInvocation: false });
  for (const s of records) put(`plugins/soleur/skills/${s.name}/SKILL.md`, `---\nname: ${s.name}\ndescription: ${JSON.stringify(s.description)}\n---\n# ${s.name}\n`);
  // The collision populations the create arm fails closed on (agents >= 30, Cursor stubs >= 50).
  for (let i = 0; i < 30; i++) put(`plugins/soleur/agents/engineering/synthetic-agent-${i}.md`, "---\nname: x\n---\n");
  for (let i = 0; i < 50; i++) put(`plugins/soleur/cursor/skills/soleur-stub-${i}/SKILL.md`, "stub\n");
  const total = records.filter((r) => !r.disableModelInvocation).reduce((n, r) => n + r.description.split(/\s+/).filter(Boolean).length, 0);
  if (opts.cap !== null) put("plugins/soleur/test/components.test.ts", `const SKILL_DESCRIPTION_WORD_BUDGET = ${opts.cap ?? total + 40};\n`);
  return root;
}

function args(over: Partial<CreateProposeArgs> = {}): CreateProposeArgs {
  return {
    repoRoot: pluginTree(),
    octokit: { request: async () => ({ data: [] }) } as never,
    patterns: [PATTERN],
    ledgerEntries: [],
    runStartedAt: "2026-10-26T10:00:00.000Z",
    capLeft: 1,
    apiKey: "k",
    runId: "RUN",
    scanOpenPrPaths: async () => ({ paths: [], incomplete: null }),
    post: vi.fn(async () => ({ text: JSON.stringify({ decision: "no_action", reason_class: "other" }), stopReason: "end_turn" })) as never,
    ...over,
  };
}

describe("Step A runCreateProposeStep -- never throws, every refusal is a returned, mirrored class", () => {
  it("week-cap: no slot left refuses BEFORE any read or model call", async () => {
    const post = vi.fn();
    const v = await runCreateProposeStep(args({ capLeft: 0, post: post as never, repoRoot: "/nonexistent" }));
    expect(v).toMatchObject({ kind: "refused", class: "week-cap", detail: "no-slot" });
    expect(post).not.toHaveBeenCalled();
    expect(await runCreateProposeStep(args({ capLeft: -3, post: post as never }))).toMatchObject({ class: "week-cap" });
    expect(await runCreateProposeStep(args({ capLeft: Number.NaN, post: post as never }))).toMatchObject({ class: "week-cap" });
  });

  it("G: a missing clone is persist/clone-missing, after the cap and index checks and before any request", async () => {
    const request = vi.fn();
    const post = vi.fn();
    const v = await runCreateProposeStep(args({ repoRoot: join(tmpdir(), "create-arm-gone-" + Date.now()), octokit: { request } as never, post: post as never }));
    expect(v).toEqual({ kind: "refused", class: "persist", detail: "clone-missing" });
    expect(request).not.toHaveBeenCalled();
    expect(post).not.toHaveBeenCalled();
  });

  it("index-empty: no open pattern refuses before the listing", async () => {
    const request = vi.fn();
    const v = await runCreateProposeStep(args({ patterns: [], octokit: { request } as never }));
    expect(v).toMatchObject({ kind: "refused", class: "index-empty" });
    expect(request).not.toHaveBeenCalled();
  });

  it("input-size: an index plus skill list over the ceiling is refused, never truncated, with the bound in numbers", async () => {
    const root = pluginTree({ skills: 0 });
    for (let i = 0; i < 400; i++) {
      const d = `big-${i}`;
      mkdirSync(join(root, "plugins/soleur/skills", d), { recursive: true });
      writeFileSync(join(root, "plugins/soleur/skills", d, "SKILL.md"), `---\nname: ${d}\ndescription: ${JSON.stringify("This skill should be used ".repeat(40))}\n---\n`);
    }
    writeFileSync(join(root, "plugins/soleur/test/components.test.ts"), "const SKILL_DESCRIPTION_WORD_BUDGET = 999999;\n");
    const post = vi.fn();
    const v = await runCreateProposeStep(args({ repoRoot: root, post: post as never }));
    expect(v).toMatchObject({ kind: "refused", class: "input-size", detail: "over-ceiling" });
    expect((v as { numbers?: Record<string, number> }).numbers?.tokens).toBeGreaterThan(12000);
    expect(post).not.toHaveBeenCalled();
  });

  it("budget: a tree the counter cannot read, and a missing cap, are refused (fail closed)", async () => {
    const bare = mkdtempSync(join(tmpdir(), "create-arm-bare-"));
    roots.push(bare);
    expect(await runCreateProposeStep(args({ repoRoot: bare }))).toMatchObject({ class: "budget", detail: "skills-dir-unreadable" });
    expect(await runCreateProposeStep(args({ repoRoot: pluginTree({ skills: 3 }) }))).toMatchObject({ class: "budget", detail: "population-below-floor" });
    expect(await runCreateProposeStep(args({ repoRoot: pluginTree({ cap: null }) }))).toMatchObject({ class: "budget", detail: "cap-unreadable" });
  });

  it("an open-PR path scan that throws, or hits a bound, is unverifiable create-open, never clear", async () => {
    const post = vi.fn();
    const thrown = await runCreateProposeStep(args({ scanOpenPrPaths: async () => { throw new Error("502 with a body"); }, post: post as never }));
    expect(thrown).toMatchObject({ class: "create-open", detail: "paths-unverifiable" });
    expect(JSON.stringify(thrown)).not.toContain("502");
    const bounded = await runCreateProposeStep(args({ scanOpenPrPaths: async () => ({ paths: [], incomplete: "prs" }), post: post as never }));
    expect(bounded).toMatchObject({ class: "create-open", detail: "paths-incomplete" });
    expect(post).not.toHaveBeenCalled();
  });

  it("the scan is asked for the skill, Cursor stub, agent and command prefixes", async () => {
    const scan = vi.fn(async () => ({ paths: [], incomplete: null }));
    await runCreateProposeStep(args({ scanOpenPrPaths: scan }));
    expect(scan).toHaveBeenCalledWith(CREATE_PR_PATH_PREFIXES);
    expect([...CREATE_PR_PATH_PREFIXES]).toEqual(["plugins/soleur/skills/", "plugins/soleur/cursor/skills/", "plugins/soleur/agents/", "plugins/soleur/commands/"]);
  });

  it("no API key is a returned model-invalid refusal and no call is made", async () => {
    const post = vi.fn();
    const v = await runCreateProposeStep(args({ apiKey: undefined, post: post as never }));
    expect(v).toMatchObject({ class: "model-invalid", detail: "no-api-key" });
    expect(post).not.toHaveBeenCalled();
  });

  it("ONE call with the create output cap, the attribution, the timeout and a closed json schema; no retry on failure", async () => {
    const post = vi.fn(async (_a: unknown) => { throw new Error("Anthropic API request failed (TimeoutError)"); });
    const v = await runCreateProposeStep(args({ post: post as never }));
    expect(v).toMatchObject({ class: "model-invalid", detail: "transport" });
    expect(post).toHaveBeenCalledTimes(1);
    expect(post.mock.calls[0][0]).toMatchObject({
      apiKey: "k", maxTokens: CREATE_MAX_TOKENS, markerSource: "cron-compound-promote", markerRunId: "RUN", timeoutMs: CREATE_MODEL_TIMEOUT_MS,
      outputConfig: { format: { type: "json_schema" } },
    });
  });

  it("a thrown defect inside the step becomes a returned, Error-mirrored refusal (the step cannot throw)", async () => {
    const boom = { capLeft: 1, get patterns(): never { throw new Error("defect"); } } as unknown as CreateProposeArgs;
    const v = await runCreateProposeStep(boom);
    expect(v).toMatchObject({ kind: "refused", class: "model-invalid", detail: "internal" });
    expect(reportSilentFallback).toHaveBeenCalledWith(expect.any(Error), expect.objectContaining({ op: "create-propose-internal" }));
    expect(reportSilentFallback).toHaveBeenCalledWith(null, expect.objectContaining({ op: CREATE_REFUSED_OP, tags: { class: "model-invalid" } }));
  });

  it("a passing no_action returns the clean verdict and mirrors nothing", async () => {
    const v = await runCreateProposeStep(args());
    expect(v).toEqual({ kind: "no_action", reason: "other" });
    expect(reportSilentFallback).not.toHaveBeenCalled();
  });

  it("the verdict is JSON-plain (it is a memoized step return)", async () => {
    const v = await runCreateProposeStep(args({ capLeft: 0 }));
    expect(JSON.parse(JSON.stringify(v))).toEqual(v);
  });
});

// ---------------------------------------------------------------------------------------------------------
describe("Step A with a valid create proposal", () => {
  function createArgs(over: Partial<CreateProposeArgs> = {}, proposalOver: Record<string, unknown> = {}): CreateProposeArgs {
    const base = args();
    const counted = countDescriptionWords(join(base.repoRoot, "plugins", "soleur"));
    if (!counted.ok) throw new Error(counted.detail);
    const merged: Record<string, unknown> = { ...structuredClone(PROPOSAL), ...proposalOver };
    merged.nearest_skill = rankOverlap(
      proposalOverlapText({ slug: String(merged.slug), description: String(merged.description), when_to_use: merged.when_to_use as string[] }),
      counted.records,
    )[0].name;
    return { ...base, post: vi.fn(async () => ({ text: JSON.stringify(merged), stopReason: "end_turn" })) as never, ...over };
  }
  const HASH = createClusterHash(PATTERN.evidence);

  it("a valid proposal passes every gate and returns a create verdict (the harness for the rows below)", async () => {
    const v = await runCreateProposeStep(createArgs());
    expect(v).toMatchObject({ kind: "create", clusterHash: HASH });
  });

  it("G4: when EVERY pattern is owned by the edit loop this run, the arm ends no_action(other) BEFORE any read, request or model call", async () => {
    const post = vi.fn();
    const request = vi.fn();
    const a = createArgs({ sameRunHashes: [HASH], post: post as never, octokit: { request } as never });
    expect(await runCreateProposeStep(a)).toEqual({ kind: "no_action", reason: "other" });
    expect(post).not.toHaveBeenCalled();
    expect(request).not.toHaveBeenCalled();
    expect(reportSilentFallback).not.toHaveBeenCalled(); // a clean outcome, nothing mirrored
  });

  it("G4: an owned pattern is NOT offered to the model (the prompt lists only the others); the week cap still comes first", async () => {
    const other: PatternPage = { ...PATTERN, slug: "other-pattern", evidence: [6, 7, 8, 9, 10].map((n) => `knowledge-base/project/learnings/2026-10-${n < 10 ? "0" : ""}${n}-synthetic-${n}.md`) };
    const post = vi.fn(async (_a: unknown) => ({ text: JSON.stringify({ decision: "no_action", reason_class: "other" }), stopReason: "end_turn" }));
    await runCreateProposeStep(createArgs({ patterns: [PATTERN, other], sameRunHashes: [HASH], post: post as never }));
    const prompt = String((post.mock.calls[0][0] as { messages: Array<{ content: string }> }).messages[0].content);
    expect(prompt).toContain("other-pattern");
    expect(prompt).not.toContain(PATTERN.slug);
    expect(await runCreateProposeStep(createArgs({ sameRunHashes: [HASH], capLeft: 0 }))).toMatchObject({ class: "week-cap" });
  });

  it("G4 backstop: a model that names an owned pattern anyway (not offered, but present in the list) is still SUPPRESSED, never created", async () => {
    const other: PatternPage = { ...PATTERN, slug: "other-pattern", evidence: [6, 7, 8, 9, 10].map((n) => `knowledge-base/project/learnings/2026-10-${n < 10 ? "0" : ""}${n}-synthetic-${n}.md`) };
    expect(await runCreateProposeStep(createArgs({ patterns: [PATTERN, other], sameRunHashes: [HASH] }))).toEqual({ kind: "suppressed", clusterHash: HASH });
  });

  it("A: an unrelated same-run hash does not suppress", async () => {
    expect(await runCreateProposeStep(createArgs({ sameRunHashes: ["f".repeat(64)] }))).toMatchObject({ kind: "create" });
  });

  it("E: an open PR that adds an agent or a command named like the slug refuses slug/open-pr-agent | open-pr-command", async () => {
    const slug = String(PROPOSAL.slug);
    expect(await runCreateProposeStep(createArgs({ scanOpenPrPaths: async () => ({ paths: [`plugins/soleur/agents/engineering/${slug}.md`], incomplete: null }) })))
      .toMatchObject({ class: "slug", detail: "open-pr-agent" });
    expect(await runCreateProposeStep(createArgs({ scanOpenPrPaths: async () => ({ paths: [`plugins/soleur/commands/${slug}.md`], incomplete: null }) })))
      .toMatchObject({ class: "slug", detail: "open-pr-command" });
    // a longer name that merely ends with the slug is not a collision
    expect(await runCreateProposeStep(createArgs({ scanOpenPrPaths: async () => ({ paths: [`plugins/soleur/agents/engineering/not-${slug}.md`], incomplete: null }) })))
      .toMatchObject({ kind: "create" });
  });

  it("F: the swallowed failures carry a closed cause token in the Sentry extra (detail stays the census token)", async () => {
    const transport = await runCreateProposeStep(createArgs({ post: (async () => { throw Object.assign(new Error("429 body text"), { status: 429 }); }) as never }));
    expect(transport).toMatchObject({ class: "model-invalid", detail: "transport" });
    expect(vi.mocked(reportSilentFallback)).toHaveBeenCalledWith(null, expect.objectContaining({ op: CREATE_REFUSED_OP, extra: expect.objectContaining({ detail: "transport", cause: "http-429" }) }));
    expect(JSON.stringify(vi.mocked(reportSilentFallback).mock.calls)).not.toContain("429 body text");

    vi.mocked(reportSilentFallback).mockClear();
    await runCreateProposeStep(createArgs({ scanOpenPrPaths: async () => { throw Object.assign(new Error("x"), { code: "ECONNRESET" }); } }));
    expect(vi.mocked(reportSilentFallback)).toHaveBeenCalledWith(null, expect.objectContaining({ extra: expect.objectContaining({ detail: "paths-unverifiable", cause: "ECONNRESET" }) }));

    vi.mocked(reportSilentFallback).mockClear();
    await runCreateProposeStep(createArgs({ octokit: { request: async () => { throw Object.assign(new Error("x"), { status: 503 }); } } as never }));
    expect(vi.mocked(reportSilentFallback)).toHaveBeenCalledWith(null, expect.objectContaining({ extra: expect.objectContaining({ detail: "list-failed", cause: "http-503" }) }));

    vi.mocked(reportSilentFallback).mockClear();
    const noCap = createArgs();
    rmSync(join(noCap.repoRoot, "plugins/soleur/test/components.test.ts"));
    await runCreateProposeStep(noCap);
    expect(vi.mocked(reportSilentFallback)).toHaveBeenCalledWith(null, expect.objectContaining({ extra: expect.objectContaining({ detail: "cap-unreadable", cause: "ENOENT" }) }));
  });
});

// ---------------------------------------------------------------------------------------------------------
describe("mirrorCreateRefusal -- ONE op, a class tag, closed extras", () => {
  it("is a message-path capture (err = null) tagged with the class, carrying detail and numbers", () => {
    mirrorCreateRefusal({ kind: "refused", class: "budget", detail: "over-headroom", numbers: { words: 31, cap: 2436, total: 2402 } });
    expect(reportSilentFallback).toHaveBeenCalledWith(null, {
      feature: "cron-compound-promote",
      op: "create-refused",
      message: "create refused: budget (over-headroom)",
      tags: { class: "budget" },
      extra: { class: "budget", detail: "over-headroom", words: 31, cap: 2436, total: 2402 },
    });
  });
});

// ---------------------------------------------------------------------------------------------------------
describe("the PR body and the branch", () => {
  const verdict = {
    kind: "create",
    proposal: PROPOSAL,
    clusterHash: "a".repeat(64),
    gates: [],
    overlap: { top1Name: "ship", top1: 0.05, nearestRank: 2, top3: ["plan", "ship", "x"] },
    words: 22,
    cap: 2436,
    total: 2402,
    headroom: 34,
  } as unknown as CreateVerdictCreate;

  it("the first line is the fixed CREATE line, the text is fixed, and it never speaks of merging", () => {
    const body = buildCreatePrBody(verdict);
    expect(body.split("\n")[0]).toBe(CREATE_PR_BODY_LINE);
    expect(body).toContain("Ref #10550");
    // the one fixed checklist item the CTO ruling mandates says "before merge" (a reviewer instruction, not a claim)
    expect(body.replace("Scan PURPOSE.md for names, domains or identifiers before merge.", "")).not.toMatch(/merg|auto-?merge|will land|shipped|guarantee/i);
    expect(body).toContain(`refused at or above ${OVERLAP_REFUSE_THRESHOLD.toFixed(2)}`);
    expect(body).toContain("Description words used: 22 of at most 30.");
    expect(body).toContain("Budget headroom before this skill: 34 words (total 2402, cap 2436).");
    expect(body).toContain(`Cluster-Hash: ${"a".repeat(64)}`);
    expect(body.endsWith("Draft for human review. Close to reject.")).toBe(true);
  });

  it("I: the reviewer checklist is the fixed R1/R2/R3 set, and the body says only `test` and `skill-security-scan PR gate` are real checks", () => {
    const body = buildCreatePrBody(verdict);
    for (const item of [
      "- [ ] Read every step as an instruction to an agent that holds shell access and secrets.",
      "- [ ] No step reads, prints or posts credentials or env files.",
      "- [ ] No step is destructive or irreversible.",
      "- [ ] Will this description trigger on unrelated prompts? Narrow it or reject.",
      "- [ ] Scan PURPOSE.md for names, domains or identifiers before merge.",
      "- [ ] Categorise the skill in plugins/soleur/docs/_data/skills.js",
    ]) {
      expect(body, item).toContain(item);
    }
    expect(body).toContain("Real CI results on this draft: `test` and `skill-security-scan PR gate` only.");
    expect([...REAL_CHECK_NAMES].sort()).toEqual([...CREATE_EXCLUDED_SYNTHETIC_CHECKS].sort());
    expect(body).toContain("Ref #10550");
    expect(body).not.toMatch(/Closes|Fixes|Resolves/i);
  });

  it("the body carries no model prose: the description and rationale fields never appear", () => {
    const body = buildCreatePrBody(verdict);
    for (const text of [String(PROPOSAL.description), String(PROPOSAL.patch_rejection_reason), ...(PROPOSAL.steps as string[])]) {
      expect(body).not.toContain(text);
    }
  });

  it("SCHEDULED_ISSUE_LABEL equals the handler's SENTRY_MONITOR_SLUG (the label safeCommitAndPr comments on)", () => {
    const handler = readFileSync(join(__dirname, "..", "..", "server", "inngest", "functions", "cron-compound-promote.ts"), "utf8");
    expect(/const SENTRY_MONITOR_SLUG = "([^"]+)";/.exec(handler)?.[1]).toBe(SCHEDULED_ISSUE_LABEL);
  });

  it("the branch is the edit arm's shape: prefix + 64-hex hash + date", () => {
    expect(createBranchName("b".repeat(64), "2026-10-26")).toBe(`self-healing/auto-${"b".repeat(64)}-2026-10-26`);
  });
});

// ---------------------------------------------------------------------------------------------------------
describe("Step B runCreatePersistStep -- guards before any write", () => {
  const persistArgs = (over: Record<string, unknown> = {}) => ({
    repoRoot: mkdtempSync(join(tmpdir(), "create-arm-persist-")),
    installationToken: "t",
    runStartedAt: "2026-10-26T10:00:00.000Z",
    octokit: { request: async () => ({ data: [] }), graphql: async () => ({}) } as never,
    logger: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
    patterns: [PATTERN],
    verdict: {
      kind: "create", proposal: PROPOSAL, clusterHash: "c".repeat(64), gates: [],
      overlap: { top1Name: "ship", top1: 0.05, nearestRank: 1, top3: ["ship"] }, words: 22, cap: 2436, total: 2402, headroom: 34,
    } as unknown as CreateVerdictCreate,
    safeCommit: vi.fn(),
    ...over,
  });

  it("a hit on our own open PR (deterministic head) is success with NO commit", async () => {
    const a = persistArgs({ octokit: { request: async () => ({ data: [{ number: 9, body: `${CREATE_PR_BODY_LINE}\nrest` }] }), graphql: async () => ({}) } });
    roots.push(a.repoRoot);
    expect(await runCreatePersistStep(a as never)).toEqual({ kind: "opened", pr: 9, resumed: true });
    expect(a.safeCommit).not.toHaveBeenCalled();
  });

  it("A: a hit that is an EDIT PR (same branch shape, no CREATE line in the body) is NOT resumed: persist/branch-taken, no commit", async () => {
    const a = persistArgs({ octokit: { request: async () => ({ data: [{ number: 9, body: "Tier: agents-core. Cluster-Hash: x" }] }), graphql: async () => ({}) } });
    roots.push(a.repoRoot);
    const v = await runCreatePersistStep(a as never);
    expect(v).toEqual({ kind: "refused", class: "persist", detail: "branch-taken", numbers: { pr: 9 } });
    expect(a.safeCommit).not.toHaveBeenCalled();
    expect(reportSilentFallback).toHaveBeenCalledWith(null, expect.objectContaining({ op: CREATE_REFUSED_OP, tags: { class: "persist" } }));
    // a body that is not a string at all is not a create PR either
    const b = persistArgs({ octokit: { request: async () => ({ data: [{ number: 10, body: null }] }), graphql: async () => ({}) } });
    roots.push(b.repoRoot);
    expect(await runCreatePersistStep(b as never)).toMatchObject({ class: "persist", detail: "branch-taken" });
  });

  it("G: a missing clone directory is its own named refusal before ANY request or write", async () => {
    const request = vi.fn(async () => ({ data: [] }));
    const a = persistArgs({ repoRoot: join(tmpdir(), "create-arm-gone-" + Date.now()), octokit: { request, graphql: async () => ({}) } });
    expect(await runCreatePersistStep(a as never)).toEqual({ kind: "refused", class: "persist", detail: "clone-missing" });
    expect(request).not.toHaveBeenCalled();
    expect(a.safeCommit).not.toHaveBeenCalled();
  });

  it("a failed own-PR lookup is mirrored and does NOT end the step (the branch-exists probe before the commit is what stops a second push)", async () => {
    const a = persistArgs({ octokit: { request: async () => { throw Object.assign(new Error("502"), { status: 502 }); }, graphql: async () => ({}) } });
    roots.push(a.repoRoot);
    // The directory is not a git clone, so the step then refuses at the clean-main guard, before any write.
    const v = await runCreatePersistStep(a as never);
    expect(v).toMatchObject({ kind: "refused", class: "persist", detail: "clone-not-clean" });
    expect(reportSilentFallback).toHaveBeenCalledWith(expect.any(Error), expect.objectContaining({ op: "create-own-pr-lookup-failed", extra: { cause: "http-502" } }));
    expect(a.safeCommit).not.toHaveBeenCalled();
  });

  it("a directory that is not a clean clone refuses persist without writing a single file", async () => {
    const a = persistArgs();
    roots.push(a.repoRoot);
    const v = await runCreatePersistStep(a as never);
    expect(v).toMatchObject({ kind: "refused", class: "persist", detail: "clone-not-clean" });
    expect(a.safeCommit).not.toHaveBeenCalled();
  });

  it("a verdict whose cluster hash is not 64 lowercase hex cannot form a branch (branch-shape)", async () => {
    const a = persistArgs();
    roots.push(a.repoRoot);
    (a.verdict as { clusterHash: string }).clusterHash = "NOT-A-HASH";
    expect(await runCreatePersistStep(a as never)).toMatchObject({ class: "persist", detail: "branch-shape" });
  });
});
