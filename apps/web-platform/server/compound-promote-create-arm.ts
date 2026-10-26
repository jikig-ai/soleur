// WikiSkill Phase 2 (#10550), commit 5 -- the create arm's two step bodies.
//
// The handler (`inngest/functions/cron-compound-promote.ts`) owns the control flow and the marker; THIS module owns
// the work of the two memoized steps, so the edit arm's source (which several census suites read as text) gains no
// new commit call, synthetic-check list or step-callback shape:
//
//   Step A `create-propose`  runCreateProposeStep   week-cap -> create-open -> budget -> prompt -> ONE model call ->
//                                                   checkCreate. MEMOIZED and NEVER THROWS: every failure is a
//                                                   returned refusal with a closed class.
//   Step B `create-persist`  runCreatePersistStep   own-PR lookup -> render -> write -> scan -> README sync ->
//                                                   collect -> safeCommitAndPr in exactPaths mode. ONE step.
//
// Contracts (plan Guards 1 and 3, CTO G2):
//   - dark-launched: the handler calls this only for trigger=manual, input=patterns, allow_create===true;
//   - every refusal is mirrored to Sentry with ONE op, `create-refused`, tagged with the closed `class`;
//   - a refused create writes NO ledger row: the promotion-log row exists only inside the committed PR;
//   - the PR is a DRAFT, label self-healing/auto, mergeMode "none"; its body never claims a merge;
//   - the branch suffix derives from the memoized run-start date, never a fresh Date, and Step B first looks up its
//     own open PR by the deterministic head branch (a hit is success), so a replay cannot open a second PR;
//   - the create PR does NOT inherit the edit arm's `skill-security-scan PR gate` / `test` synthetic checks.
//
// No import edge leads from here to the handler (the handler injects what it owns); see
// test/server/compound-promote-screens.test.ts.

import { execFile } from "node:child_process";
import { appendFile, mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import type { Octokit } from "@octokit/core";
import { reportSilentFallback } from "@/server/observability";
import { REPO_OWNER, REPO_NAME, postAnthropicMessage } from "@/server/inngest/functions/_cron-shared";
import { safeCommitAndPr } from "@/server/inngest/functions/_cron-safe-commit";
import { GIT_HARDENING_ARGS, GIT_HARDENING_ENV } from "@/server/inngest/functions/_git-hardening";
import { EXECUTION_MODEL } from "@/server/inngest/model-tiers";
import { PROMOTE_BRANCH_PREFIX, decideSuppression, promotePrTitle, type LedgerEntry } from "@/server/compound-promote-ledger";
import type { PatternPage } from "@/server/compound-promote-patterns";
import {
  COMPONENTS_TEST_PATH,
  CREATE_DESCRIPTION_MAX_WORDS,
  CREATE_OUTPUT_SCHEMA,
  CREATE_PR_BODY_LINE,
  GROK_BLOCK_SOURCE_PATH,
  OVERLAP_REFUSE_THRESHOLD,
  PROMOTION_LOG_PATH,
  PURPOSE_TEMPLATE_PATH,
  checkCreate,
  countDescriptionWords,
  createPathList,
  parseCreateModelText,
  prepareCreate,
  readAgentPaths,
  readBudgetCap,
  readCommandNames,
  readCursorDirs,
  readGrokBlock,
  renderCreateFiles,
  type CreateProposal,
  type CreateRefusal,
  type CreateRefusalClass,
  type CreateVerdict,
  unmeasurableCollisionRefusal,
} from "@/server/compound-promote-create";
import {
  buildScrubbedEnv,
  collectCreateContent,
  createSyntheticCheckNames,
  runSkillScan,
  syncReadmeCounts,
} from "@/server/compound-promote-create-gates";
import { randomBytes } from "node:crypto";

// =============================================================================
// Constants
// =============================================================================

export const CREATE_ARM_FEATURE = "cron-compound-promote";
/** The ONE Sentry op every create refusal is mirrored under (runbook: `compound-promote-runbook.md`). */
export const CREATE_REFUSED_OP = "create-refused";
/** Bound on the single model call: the same cap the edit-draft call uses (an AbortSignal, so no billed zombie). */
export const CREATE_MODEL_TIMEOUT_MS = 120_000;
/** The prefixes whose open-PR file names feed the slug / nearest-skill collision gates. */
export const CREATE_PR_PATH_PREFIXES = ["plugins/soleur/skills/", "plugins/soleur/cursor/skills/"] as const;
/** Open-PR list pages (100 per page) read by the one-open-create check: 300 PRs, a full last page is "incomplete". */
export const CREATE_OPEN_PR_PAGES = 3;
const PR_PAGE_SIZE = 100;
const PR_LIST_TIMEOUT_MS = 20_000;
export const CREATE_LABEL = "self-healing/auto";
/** Mirrors `SENTRY_MONITOR_SLUG` in the handler (the scheduled-output issue label safeCommitAndPr comments on). */
const SCHEDULED_ISSUE_LABEL = "scheduled-compound-promote";

type ArmOctokit = Pick<Octokit, "request">;
type PersistOctokit = Pick<Octokit, "request" | "graphql">;
type Logger = { info: (...a: unknown[]) => void; warn: (...a: unknown[]) => void; error: (...a: unknown[]) => void };

// =============================================================================
// Refusal plumbing
// =============================================================================

function refusal(cls: CreateRefusalClass, detail: string, numbers?: Record<string, number>): CreateRefusal {
  return numbers ? { kind: "refused", class: cls, detail, numbers } : { kind: "refused", class: cls, detail };
}

/**
 * Mirror ONE refusal to Sentry (cq-silent-fallback-must-mirror-to-sentry). MESSAGE path (err = null) with TAGS, on
 * purpose: on the Error path the pino mirror captures the same Error first and the tagged capture is dropped
 * (#8629). `class` and `detail` are closed tokens built from constants; `numbers` are bare integers or scores.
 */
export function mirrorCreateRefusal(r: CreateRefusal, extra?: Record<string, unknown>): void {
  reportSilentFallback(null, {
    feature: CREATE_ARM_FEATURE,
    op: CREATE_REFUSED_OP,
    message: `create refused: ${r.class} (${r.detail})`,
    tags: { class: r.class },
    extra: { class: r.class, detail: r.detail, ...(r.numbers ?? {}), ...(extra ?? {}) },
  });
}

function refuseAndMirror(cls: CreateRefusalClass, detail: string, numbers?: Record<string, number>): CreateRefusal {
  const r = refusal(cls, detail, numbers);
  mirrorCreateRefusal(r);
  return r;
}

// =============================================================================
// One-open-create check (CTO G2)
// =============================================================================

export type OpenCreateProbe =
  | { kind: "none" }
  | { kind: "open"; pr: number }
  | { kind: "unverifiable"; detail: "list-failed" | "list-incomplete" };

interface ListedPr {
  number?: unknown;
  body?: unknown;
  labels?: unknown;
}

function hasLabel(pr: ListedPr, label: string): boolean {
  return Array.isArray(pr.labels) && pr.labels.some((l) => typeof l === "object" && l !== null && (l as { name?: unknown }).name === label);
}

/**
 * Is another create PR already open? `GET /pulls` (state open), never the search API (the search index lags and a
 * stale miss would open a second create). A PR counts when it carries the `self-healing/auto` label AND its body
 * contains the fixed `CREATE (new skill)` line. A list that cannot be read, or whose last allowed page is full, is
 * `unverifiable` and refuses: absence is never inferred from a read that did not complete.
 */
export async function findOpenCreatePr(octokit: ArmOctokit, owner: string, repo: string): Promise<OpenCreateProbe> {
  for (let page = 1; page <= CREATE_OPEN_PR_PAGES; page++) {
    let data: unknown;
    try {
      const res = await octokit.request("GET /repos/{owner}/{repo}/pulls", {
        owner, repo, state: "open", per_page: PR_PAGE_SIZE, page,
        request: { signal: AbortSignal.timeout(PR_LIST_TIMEOUT_MS) },
      });
      data = res.data;
    } catch {
      return { kind: "unverifiable", detail: "list-failed" };
    }
    if (!Array.isArray(data)) return { kind: "unverifiable", detail: "list-failed" };
    for (const pr of data as ListedPr[]) {
      if (typeof pr.body === "string" && pr.body.includes(CREATE_PR_BODY_LINE) && hasLabel(pr, CREATE_LABEL)) {
        return { kind: "open", pr: Number.isInteger(pr.number) ? (pr.number as number) : 0 };
      }
    }
    if (data.length < PR_PAGE_SIZE) return { kind: "none" };
  }
  return { kind: "unverifiable", detail: "list-incomplete" };
}

// =============================================================================
// Step A -- create-propose
// =============================================================================

export interface CreateProposeArgs {
  repoRoot: string;
  octokit: ArmOctokit;
  owner?: string;
  repo?: string;
  patterns: readonly PatternPage[];
  ledgerEntries: readonly LedgerEntry[];
  /** The MEMOIZED run-start ISO timestamp (the ledger's TTL clock). */
  runStartedAt: string;
  /** `weekCap.remaining - editPrsOpenedThisRun`, computed by the handler from memoized values. */
  capLeft: number;
  apiKey: string | undefined;
  runId?: string;
  /** Open-PR file names under the given prefixes (the handler wraps `scanOpenPrSkillPaths`); `incomplete` = a bound was hit. */
  scanOpenPrPaths: (prefixes: readonly string[]) => Promise<{ paths: string[]; incomplete: string | null }>;
  /** Test seams. */
  nonce?: string;
  post?: typeof postAnthropicMessage;
}

/**
 * Step A. NEVER THROWS: any failure is converted to a returned, mirrored refusal with a closed class, so the
 * memoized step output is always a verdict and a replay re-enters nothing.
 */
export async function runCreateProposeStep(a: CreateProposeArgs): Promise<CreateVerdict> {
  try {
    return await proposeInner(a);
  } catch (err) {
    // A defect, not a gate outcome: mirror the Error itself so the stack reaches Sentry, then return a closed refusal.
    reportSilentFallback(err, { feature: CREATE_ARM_FEATURE, op: "create-propose-internal", message: "create-propose failed unexpectedly" });
    return refuseAndMirror("model-invalid", "internal");
  }
}

async function proposeInner(a: CreateProposeArgs): Promise<CreateVerdict> {
  const owner = a.owner ?? REPO_OWNER;
  const repo = a.repo ?? REPO_NAME;

  // week-cap: the edit loop ran first and shares the cap (`remaining - editPrsOpenedThisRun`).
  if (!(a.capLeft > 0)) return refuseAndMirror("week-cap", "no-slot", { cap_left: Math.max(0, Number.isFinite(a.capLeft) ? a.capLeft : 0) });

  // index-empty before any I/O: a create needs a pattern to be about.
  if (a.patterns.length === 0) return refuseAndMirror("index-empty", "no-open-patterns");

  // create-open: at most one open create at a time. A list that cannot be read refuses.
  const open = await findOpenCreatePr(a.octokit, owner, repo);
  if (open.kind === "open") return refuseAndMirror("create-open", "open-create-pr");
  if (open.kind === "unverifiable") return refuseAndMirror("create-open", open.detail);

  // budget inputs, measured from the clone with the SAME counter as the bun test; unreadable refuses (fail closed).
  const pluginRoot = join(a.repoRoot, "plugins", "soleur");
  const counted = countDescriptionWords(pluginRoot);
  if (!counted.ok) return refuseAndMirror("budget", counted.detail);
  let cap: number | null;
  try {
    cap = readBudgetCap(await readFile(join(a.repoRoot, COMPONENTS_TEST_PATH), "utf8"));
  } catch {
    cap = null;
  }
  if (cap === null) return refuseAndMirror("budget", "cap-unreadable");

  // open-PR paths feed the slug and nearest-skill collision gates; an incomplete scan is unverifiable, never clear.
  let openPrPaths: string[];
  try {
    const scanned = await a.scanOpenPrPaths(CREATE_PR_PATH_PREFIXES);
    if (scanned.incomplete !== null) return refuseAndMirror("create-open", "paths-incomplete");
    openPrPaths = scanned.paths;
  } catch {
    return refuseAndMirror("create-open", "paths-unverifiable");
  }

  // The collision populations are measured BEFORE the model call (fail closed, never after a billed call).
  const agents = readAgentPaths(pluginRoot);
  if (!agents.ok) return mirrorAndReturn(unmeasurableCollisionRefusal(agents.detail));
  const cursor = readCursorDirs(pluginRoot);
  if (!cursor.ok) return mirrorAndReturn(unmeasurableCollisionRefusal(cursor.detail));
  const commandNames = readCommandNames(pluginRoot);

  const nonce = a.nonce ?? randomBytes(8).toString("hex");
  const prepared = prepareCreate({ patterns: a.patterns, skills: counted.records, nonce });
  if (prepared.kind === "refused") return mirrorAndReturn(prepared);

  if (!a.apiKey) return refuseAndMirror("model-invalid", "no-api-key");
  const post = a.post ?? postAnthropicMessage;
  let text: string;
  let stopReason: string | undefined;
  try {
    // ONE call, no retry. Bounded exactly like the existing `input: patterns` call (same helper, same
    // `markerSource`), with its own output cap and an AbortSignal timeout.
    const res = await post({
      apiKey: a.apiKey,
      model: EXECUTION_MODEL,
      maxTokens: prepared.maxTokens,
      timeoutMs: CREATE_MODEL_TIMEOUT_MS,
      messages: [{ role: "user", content: prepared.prompt }],
      outputConfig: { format: { type: "json_schema", schema: CREATE_OUTPUT_SCHEMA } },
      markerSource: "cron-compound-promote",
      markerRunId: a.runId,
    });
    text = res.text;
    stopReason = res.stopReason;
  } catch {
    return refuseAndMirror("model-invalid", "transport");
  }
  if (stopReason === "max_tokens") return refuseAndMirror("model-invalid", "max-tokens");
  if (!text) return refuseAndMirror("model-invalid", "empty");
  const raw = parseCreateModelText(text);
  if (raw === undefined) return refuseAndMirror("model-invalid", "not-json");

  const runNow = new Date(a.runStartedAt);
  const verdict = checkCreate(raw, {
    patterns: a.patterns,
    skills: counted.records,
    skillDirs: counted.dirs,
    agentPaths: agents.paths,
    cursorDirs: cursor.dirs,
    commandNames,
    openPrPaths,
    budget: { total: counted.total, cap },
    isHashSuppressed: (hash) => decideSuppression({ entries: a.ledgerEntries, hash, now: runNow }),
  });
  if (verdict.kind === "refused") return mirrorAndReturn(verdict);
  return verdict;
}

function mirrorAndReturn(r: CreateRefusal): CreateRefusal {
  mirrorCreateRefusal(r);
  return r;
}

// =============================================================================
// Step B -- create-persist
// =============================================================================

export type CreatePersistResult = { kind: "opened"; pr?: number; resumed?: true } | CreateRefusal;

export type CreateVerdictCreate = Extract<CreateVerdict, { kind: "create" }>;

export interface CreatePersistArgs {
  repoRoot: string;
  installationToken: string;
  /** The MEMOIZED run-start ISO timestamp: the branch suffix, PR title date and commit date all derive from it. */
  runStartedAt: string;
  octokit: PersistOctokit;
  logger: Logger;
  verdict: CreateVerdictCreate;
  /** Evidence entries of the chosen pattern (the promotion-log `n` column). */
  evidenceCount: number;
  /** Test seams. */
  safeCommit?: typeof safeCommitAndPr;
  metaParent?: string;
}

const BRANCH_SHAPE_RE = new RegExp(
  `^${PROMOTE_BRANCH_PREFIX.replace(/[.*+?^${}()|[\]\\/]/g, "\\$&")}[0-9a-f]{64}-[0-9]{4}-[0-9]{2}-[0-9]{2}$`,
);

/** The deterministic head branch of a create PR: the same shape the edit arm and the ledger use. */
export function createBranchName(clusterHash: string, dateSuffix: string): string {
  return `${PROMOTE_BRANCH_PREFIX}${clusterHash}-${dateSuffix}`;
}

/**
 * The fixed PR body. Server text plus closed tokens and numbers only (the slug, pattern slug and nearest skill passed
 * the identifier allowlist; the description and prose are in the diff, not here). It never claims a merge or an
 * auto-merge: the PR is a draft for a human to review, and no word of it speaks of merging.
 */
export function buildCreatePrBody(v: CreateVerdictCreate): string {
  const p = v.proposal;
  return [
    CREATE_PR_BODY_LINE,
    "",
    `Proposed by the compound-promotion loop (WikiSkill phase 2). Ref #10550.`,
    `Skill: ${p.slug}. Pattern: ${p.pattern_slug}. Cluster-Hash: ${v.clusterHash}. Nearest existing skill: ${p.nearest_skill}.`,
    `Description words used: ${v.words} of at most ${CREATE_DESCRIPTION_MAX_WORDS}. Budget headroom before this skill: ${v.headroom} words (total ${v.total}, cap ${v.cap}).`,
    `Top-1 overlap with an existing skill: ${v.overlap.top1} (${v.overlap.top1Name}); refused at or above ${OVERLAP_REFUSE_THRESHOLD.toFixed(2)}. Rank of the nearest skill: ${v.overlap.nearestRank}.`,
    "",
    "Reviewer checklist (fixed text):",
    '- [ ] Positioning: the skill makes Soleur sharper for the harness itself. No wording that promises an outcome in a user\'s workspace.',
    "- [ ] No personal data, handles, customer names or secrets in SKILL.md or PURPOSE.md.",
    "- [ ] The skill does not restate or relax any hard rule.",
    "- [ ] Categorise the skill in plugins/soleur/docs/_data/skills.js (an unmapped skill shows as Uncategorized).",
    "- [ ] After any description edit, or a rebase onto a main that added another skill, rerun `bun plugins/soleur/scripts/sync-cursor-name-map.ts` and `bash scripts/sync-readme-counts.sh`.",
    "",
    "Draft for human review. Close to reject.",
  ].join("\n");
}

/** Hardened, scrubbed git for the clone hygiene around Step B. Best effort; a failure is mirrored, never thrown. */
function gitClean(root: string, args: readonly string[]): Promise<boolean> {
  const env = { ...buildScrubbedEnv({}, process.env), ...GIT_HARDENING_ENV } as NodeJS.ProcessEnv;
  return new Promise((resolve) => {
    execFile("git", [...GIT_HARDENING_ARGS, "-C", root, ...args], { env, timeout: 30_000, encoding: "utf8" }, (err) => {
      resolve(!err);
    });
  });
}

async function restoreCleanMain(root: string): Promise<boolean> {
  const a = await gitClean(root, ["reset", "--hard", "HEAD"]);
  const b = await gitClean(root, ["clean", "-fd"]);
  const c = await gitClean(root, ["checkout", "main"]);
  return a && b && c;
}

/**
 * Step B. ONE step: look up our own open PR, render, write, scan, sync, collect, commit. A refused create writes no
 * ledger row (the row is only ever inside the committed PR). The clone is returned to a clean main before and after.
 */
export async function runCreatePersistStep(a: CreatePersistArgs): Promise<CreatePersistResult> {
  const v = a.verdict;
  const slug = v.proposal.slug;
  const dateSuffix = a.runStartedAt.slice(0, 10);
  const branchName = createBranchName(v.clusterHash, dateSuffix);
  if (!BRANCH_SHAPE_RE.test(branchName)) return refuseAndMirror("persist", "branch-shape");

  // Replay: a previous attempt of THIS step may already have opened our PR. A hit is success, not a second PR.
  try {
    const own = await a.octokit.request("GET /repos/{owner}/{repo}/pulls", {
      owner: REPO_OWNER, repo: REPO_NAME, state: "open", head: `${REPO_OWNER}:${branchName}`, per_page: 1,
      request: { signal: AbortSignal.timeout(PR_LIST_TIMEOUT_MS) },
    });
    if (Array.isArray(own.data) && own.data.length > 0) {
      const n = (own.data[0] as { number?: unknown }).number;
      return { kind: "opened", ...(Number.isInteger(n) ? { pr: n as number } : {}), resumed: true };
    }
  } catch (err) {
    // Not provable either way: continue (safeCommitAndPr's own branch-keyed replay-resume is the second layer), loudly.
    reportSilentFallback(err, { feature: CREATE_ARM_FEATURE, op: "create-own-pr-lookup-failed", message: "own open PR lookup failed" });
  }

  const metaBase = await mkdtemp(join(a.metaParent ?? tmpdir(), "compound-promote-create-scan-"));
  try {
    // A retry of this step must start from a clean main (the previous attempt may have left files behind).
    if (!(await restoreCleanMain(a.repoRoot))) return refuseAndMirror("persist", "clone-not-clean");
    return await persistInner(a, { slug, dateSuffix, branchName, metaBase });
  } catch (err) {
    reportSilentFallback(err, { feature: CREATE_ARM_FEATURE, op: "create-persist-internal", message: "create-persist failed unexpectedly" });
    return refuseAndMirror("persist", "internal");
  } finally {
    await rm(metaBase, { recursive: true, force: true }).catch(() => {});
    // The unconditional reset also discards the residue of a refusal: nothing a refused create wrote survives.
    if (!(await restoreCleanMain(a.repoRoot))) {
      reportSilentFallback(null, { feature: CREATE_ARM_FEATURE, op: "create-clone-restore-failed", message: "could not return the clone to a clean main" });
    }
  }
}

async function persistInner(
  a: CreatePersistArgs,
  c: { slug: string; dateSuffix: string; branchName: string; metaBase: string },
): Promise<CreatePersistResult> {
  const v = a.verdict;
  const proposal: CreateProposal = v.proposal;

  let grokBlock: string;
  let purposeTemplate: string;
  try {
    grokBlock = readGrokBlock(await readFile(join(a.repoRoot, GROK_BLOCK_SOURCE_PATH), "utf8"));
    purposeTemplate = await readFile(join(a.repoRoot, PURPOSE_TEMPLATE_PATH), "utf8");
  } catch {
    return refuseAndMirror("shape", "template-unreadable");
  }
  const rendered = renderCreateFiles({ proposal, grokBlock, purposeTemplate, date: c.dateSuffix, evidenceCount: a.evidenceCount });
  if (rendered.kind === "refused") return mirrorAndReturn(rendered);

  // Files on disk FIRST: the scanner and the exactPaths staging both read the disk.
  const [skillRel, purposeRel, stubRel] = createPathList(c.slug);
  const targets: Array<[string, string]> = [
    [skillRel, rendered.files.skillMd],
    [purposeRel, rendered.files.purposeMd],
    [stubRel, rendered.files.stub],
  ];
  for (const [rel, text] of targets) {
    const abs = join(a.repoRoot, rel);
    await mkdir(dirname(abs), { recursive: true });
    await writeFile(abs, text, "utf8");
  }
  // The ledger row rides the commit (same shape as the edit arm's row); it is never written before the gates pass
  // because nothing above reaches this point on a refusal, and the finally-reset discards it on any later one.
  const logRow = `\n| ${c.dateSuffix} | ${v.clusterHash} | ${skillRel} | ${a.evidenceCount} | pending | skill | (PR pending) |\n`;
  await appendFile(join(a.repoRoot, PROMOTION_LOG_PATH), logRow);

  const scan = await runSkillScan({ repoRoot: a.repoRoot, relPaths: [skillRel, purposeRel], metaBase: c.metaBase });
  if (!scan.ok) {
    const missing = scan.missing?.length ? { missing_tools: scan.missing.length } : undefined;
    return mirrorAndReturn(refusal("scan", scan.detail, missing));
  }

  const sync = await syncReadmeCounts({ repoRoot: a.repoRoot });
  if (!sync.ok) return mirrorAndReturn(refusal("readme-sync", sync.detail));

  const collected = await collectCreateContent({ repoRoot: a.repoRoot, slug: c.slug });
  if (!collected.ok) return mirrorAndReturn(refusal("persist", collected.detail, collected.index === undefined ? undefined : { path_index: collected.index }));

  const titleLine = `chore(self-healing): create skill ${c.slug} from cluster ${v.clusterHash}`;
  const trailer = [
    `Bot-Author: compound-promotion-loop@${process.env.GITHUB_SHA ?? "local"}`,
    `Cluster-Hash: ${v.clusterHash}`,
    `Tier: skill`,
    `Create-Skill: ${c.slug}`,
  ].join("\n");
  const commit = a.safeCommit ?? safeCommitAndPr;
  const result = await commit({
    spawnCwd: a.repoRoot,
    installationToken: a.installationToken,
    cronName: "cron-compound-promote",
    commitMessage: titleLine,
    commitBody: trailer,
    // exactPaths mode: string-equality staging of exactly the six paths, byte-checked against `expectedContent`.
    allowedPaths: [],
    exactPaths: collected.exactPaths,
    expectedContent: collected.expectedContent,
    runStartedAt: a.runStartedAt,
    scheduledIssueLabel: SCHEDULED_ISSUE_LABEL,
    branchName: c.branchName,
    prTitle: promotePrTitle(v.clusterHash, c.dateSuffix),
    prBody: buildCreatePrBody(v),
    prDraft: true,
    prLabels: [CREATE_LABEL],
    syntheticChecks: {
      // NOT the edit arm's list: a synthesized green `skill-security-scan PR gate` is the #8203 class, and a faked
      // `test` would hide a real components.test failure. Both are earned by the real CI run on the draft.
      names: createSyntheticCheckNames(),
      summary: "self-healing/auto new-skill draft - operator review required",
    },
    mergeMode: "none",
    octokit: a.octokit,
    logger: a.logger,
  });
  if (result.status === "committed") return { kind: "opened", pr: result.prNumber };
  a.logger.warn({ fn: "cron-compound-promote", hash: v.clusterHash, status: result.status }, "create-not-committed");
  const detail = result.status === "failed" ? `failed-${result.stage}` : `not-committed-${result.status}`;
  return mirrorAndReturn(refusal("persist", detail));
}
