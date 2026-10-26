// WikiSkill Phase 2 (#10550) -- the create arm's two step bodies.
//
// The handler (`inngest/functions/cron-compound-promote.ts`) owns the control flow and the marker; THIS module owns
// the work of the two memoized steps, so the edit arm's source (which several census suites read as text) gains no
// new synthetic-check list or step-callback shape. The create arm's own commit call lives HERE, outside `functions/`
// (see the ADR-054 note and `cron-safe-commit-parity.test.ts`, which walks this file too):
//
//   Step A `create-propose`  runCreateProposeStep   week-cap -> clone-present -> create-open -> budget -> prompt ->
//                                                   ONE model call -> checkCreate. MEMOIZED and NEVER THROWS: every
//                                                   failure is a returned refusal with a closed class.
//   Step B `create-persist`  runCreatePersistStep   own-PR lookup -> refresh the clone to main (R5) -> strip the token
//                                                   from `.git/config` (R4) -> re-check -> render -> write -> scan ->
//                                                   README sync -> collect -> bytes check -> restore the token and
//                                                   compare the base blobs -> safeCommitAndPr in exactPaths mode.
//                                                   ONE step, ONE deadline.
//
// Contracts (plan Guards 1 and 3, CTO G2, review rulings R4 and R5):
//   - dark-launched: the handler calls this only for trigger=manual, input=patterns, allow_create===true;
//   - every refusal is mirrored to Sentry with ONE op, `create-refused`, tagged with the closed `class`;
//   - a refused create writes NO ledger row: the promotion-log row exists only inside the committed PR;
//   - the PR is a DRAFT, label self-healing/auto, mergeMode "none"; its body never claims a merge;
//   - the branch suffix derives from the memoized run-start date, never a fresh Date, and Step B first looks up its
//     own open PR by the deterministic head branch (a hit counts as resumed ONLY when its body carries the CREATE
//     line: the EDIT arm uses the same branch shape), so a replay cannot open a second PR;
//   - the installation token is NOT in `.git/config` while any create-arm script runs (R4); it is put back only for
//     the two network calls (the fetch and the commit helper). The edit loop's token handling is untouched: a known
//     limit recorded in the runbook;
//   - the create PR does NOT inherit the edit arm's `skill-security-scan PR gate` / `test` synthetic checks.
//
// No import edge leads from here to the handler (the handler injects what it owns); see
// test/server/compound-promote-screens.test.ts.

import { appendFile, mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { randomBytes } from "node:crypto";
import type { Octokit } from "@octokit/core";
import { reportSilentFallback } from "@/server/observability";
import { REPO_OWNER, REPO_NAME, postAnthropicMessage } from "@/server/inngest/functions/_cron-shared";
import { safeCommitAndPr } from "@/server/inngest/functions/_cron-safe-commit";
import { setOriginToken } from "@/server/inngest/functions/_cron-claude-eval-substrate";
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
  unmeasurableCollisionRefusal,
  type CreateProposal,
  type CreateRefusal,
  type CreateRefusalClass,
  type CreateVerdict,
  type WordCountResult,
} from "@/server/compound-promote-create";
import {
  GIT_TIMEOUT_MS,
  README_SYNC_TIMEOUT_MS,
  SCAN_TIMEOUT_MS,
  collectCreateContent,
  createSyntheticCheckNames,
  runGit,
  runSkillScan,
  snapshotClone,
  syncReadmeCounts,
  type ReadmeSyncResult,
  type ScanResult,
} from "@/server/compound-promote-create-gates";

// =============================================================================
// Constants
// =============================================================================

export const CREATE_ARM_FEATURE = "cron-compound-promote";
/** The ONE Sentry op every create refusal is mirrored under (runbook: `compound-promote-runbook.md`). */
export const CREATE_REFUSED_OP = "create-refused";
/** Bound on the single model call: the same cap the edit-draft call uses (an AbortSignal, so no billed zombie). */
export const CREATE_MODEL_TIMEOUT_MS = 120_000;
/**
 * The prefixes whose open-PR file names feed the slug / nearest-skill collision gates: the skill dirs and the Cursor
 * stub dirs (checkCreate), plus agents and commands (the arm checks those two against the chosen slug itself).
 */
export const CREATE_PR_PATH_PREFIXES = [
  "plugins/soleur/skills/",
  "plugins/soleur/cursor/skills/",
  "plugins/soleur/agents/",
  "plugins/soleur/commands/",
] as const;
/** Open-PR list pages (100 per page) read by the one-open-create check: 300 PRs, a full last page is "incomplete". */
export const CREATE_OPEN_PR_PAGES = 3;
const PR_PAGE_SIZE = 100;
const PR_LIST_TIMEOUT_MS = 20_000;
export const CREATE_LABEL = "self-healing/auto";
/** The head-ref prefix both arms use; with the CREATE body line it is what identifies a create PR (the label is best effort). */
export const CREATE_HEAD_PREFIX = "self-healing/auto-";
/** Mirrors `SENTRY_MONITOR_SLUG` in the handler (the scheduled-output issue label safeCommitAndPr comments on); pinned by a test. */
export const SCHEDULED_ISSUE_LABEL = "scheduled-compound-promote";
/** ONE deadline for the whole of Step B. Every spawn and git call gets `min(its own timeout, what is left)`. */
export const CREATE_PERSIST_DEADLINE_MS = 150_000;
const FETCH_TIMEOUT_MS = 60_000;
/** The tokenless remote the clone is pointed at while any create-arm script runs (R4). */
export const PLAIN_ORIGIN_URL = `https://github.com/${REPO_OWNER}/${REPO_NAME}.git`;
/** The files whose origin/main blob ids are compared before the commit (R5): the two READMEs, the log and the cap file. */
export const BASE_BLOB_PATHS = ["README.md", "plugins/soleur/README.md", PROMOTION_LOG_PATH, COMPONENTS_TEST_PATH] as const;

/** The checks that are real on a create draft (the complement of what the loop posts), in the order the PR body names them. */
export const REAL_CHECK_NAMES = ["test", "skill-security-scan PR gate"] as const;

type ArmOctokit = Pick<Octokit, "request">;
type PersistOctokit = Pick<Octokit, "request" | "graphql">;
type Logger = { info: (...a: unknown[]) => void; warn: (...a: unknown[]) => void; error: (...a: unknown[]) => void };

// =============================================================================
// Refusal plumbing
// =============================================================================

function refusal(cls: CreateRefusalClass, detail: string, numbers?: Record<string, number>): CreateRefusal {
  return numbers && Object.keys(numbers).length > 0 ? { kind: "refused", class: cls, detail, numbers } : { kind: "refused", class: cls, detail };
}

/**
 * Mirror ONE refusal to Sentry (cq-silent-fallback-must-mirror-to-sentry). MESSAGE path (err = null) with TAGS, on
 * purpose: on the Error path the pino mirror captures the same Error first and the tagged capture is dropped
 * (#8629). `class` and `detail` are closed tokens built from constants; `numbers` are bare integers or scores; the
 * optional `extra` carries only closed tokens (a cause token, a signal name, tool names from a closed set).
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

/** Mirror a refusal that was built elsewhere (the pure module, a gate) and return it. */
function mirrored(r: CreateRefusal, extra?: Record<string, unknown>): CreateRefusal {
  mirrorCreateRefusal(r, extra);
  return r;
}

/** Build AND mirror a refusal. */
function fail(cls: CreateRefusalClass, detail: string, o: { numbers?: Record<string, number>; extra?: Record<string, unknown> } = {}): CreateRefusal {
  return mirrored(refusal(cls, detail, o.numbers), o.extra);
}

const CAUSE_CODES: ReadonlySet<string> = new Set([
  "ENOENT", "EACCES", "EPERM", "EISDIR", "ENOTDIR", "ELOOP", "EMFILE", "ENOSPC", "ETIMEDOUT", "ECONNRESET", "ECONNREFUSED", "ENOTFOUND", "EAI_AGAIN",
]);
const CAUSE_NAMES: ReadonlySet<string> = new Set([
  "TimeoutError", "AbortError", "TypeError", "SyntaxError", "RangeError", "HttpError", "RequestError", "AnthropicApiError", "Error",
]);

/**
 * A closed token naming WHY a swallowed call failed: `http-<status>` (an HTTP status the error carries), an errno
 * code or an error class name from a small allowlist, else `unknown`. Never a message, never a free string: it
 * rides the Sentry `extra`, so a 429 reads differently from a timeout without echoing anything the remote said.
 */
export function causeToken(err: unknown): string {
  if (typeof err !== "object" || err === null) return "unknown";
  const e = err as { status?: unknown; code?: unknown; name?: unknown; message?: unknown };
  if (typeof e.status === "number" && Number.isInteger(e.status) && e.status >= 100 && e.status <= 599) return `http-${e.status}`;
  if (typeof e.code === "string" && CAUSE_CODES.has(e.code)) return e.code;
  // postAnthropicMessage rethrows a network error as `Anthropic API request failed (<name>)`.
  const wrapped = typeof e.message === "string" ? /\(([A-Za-z]{1,40})\)$/.exec(e.message)?.[1] : undefined;
  if (wrapped !== undefined && CAUSE_NAMES.has(wrapped)) return wrapped;
  if (typeof e.name === "string" && CAUSE_NAMES.has(e.name)) return e.name;
  return "unknown";
}

// =============================================================================
// One-open-create check (CTO G2)
// =============================================================================

export type OpenCreateProbe =
  | { kind: "none" }
  | { kind: "open"; pr: number }
  | { kind: "unverifiable"; detail: "list-failed" | "list-incomplete"; cause?: string };

interface ListedPr {
  number?: unknown;
  body?: unknown;
  head?: unknown;
}

function headRef(pr: ListedPr): string | null {
  if (typeof pr.head !== "object" || pr.head === null) return null;
  const ref = (pr.head as { ref?: unknown }).ref;
  return typeof ref === "string" ? ref : null;
}

/**
 * Is another create PR already open? `GET /pulls` (state open), never the search API (the search index lags and a
 * stale miss would open a second create). A PR counts when its head ref starts with `self-healing/auto-` AND its body
 * contains the fixed `CREATE (new skill)` line: both are set by this arm at creation, whereas the `self-healing/auto`
 * label is applied best effort afterwards and is NOT required (a label failure must not allow a second open create).
 * A list that cannot be read, or whose last allowed page is full, is `unverifiable` and refuses: absence is never
 * inferred from a read that did not complete.
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
    } catch (err) {
      return { kind: "unverifiable", detail: "list-failed", cause: causeToken(err) };
    }
    if (!Array.isArray(data)) return { kind: "unverifiable", detail: "list-failed", cause: "non-array" };
    for (const pr of data as ListedPr[]) {
      const ref = headRef(pr);
      if (ref !== null && ref.startsWith(CREATE_HEAD_PREFIX) && typeof pr.body === "string" && pr.body.includes(CREATE_PR_BODY_LINE)) {
        return { kind: "open", pr: Number.isInteger(pr.number) ? (pr.number as number) : 0 };
      }
    }
    if (data.length < PR_PAGE_SIZE) return { kind: "none" };
  }
  return { kind: "unverifiable", detail: "list-incomplete" };
}

// =============================================================================
// Measuring the clone (shared by Step A and Step B's re-check)
// =============================================================================

type CountedOk = Extract<WordCountResult, { ok: true }>;

type Measured =
  | { ok: true; counted: CountedOk; cap: number; agentPaths: string[]; cursorDirs: string[]; commandNames: string[] }
  | { ok: false; refusal: CreateRefusal; extra?: Record<string, unknown> };

/**
 * Every population the create gates compare against, read from the clone with the SAME counters as the bun tests and
 * each failing closed. Used before the model call (Step A) and again on the refreshed tree (Step B). Unmirrored:
 * the caller mirrors, so a refusal is mirrored exactly once.
 */
async function measureClone(repoRoot: string): Promise<Measured> {
  const pluginRoot = join(repoRoot, "plugins", "soleur");
  const counted = countDescriptionWords(pluginRoot);
  if (!counted.ok) return { ok: false, refusal: refusal("budget", counted.detail) };
  let cap: number | null;
  let capCause: string | undefined;
  try {
    cap = readBudgetCap(await readFile(join(repoRoot, COMPONENTS_TEST_PATH), "utf8"));
  } catch (err) {
    cap = null;
    capCause = causeToken(err);
  }
  if (cap === null) return { ok: false, refusal: refusal("budget", "cap-unreadable"), extra: capCause ? { cause: capCause } : undefined };
  const agents = readAgentPaths(pluginRoot);
  if (!agents.ok) return { ok: false, refusal: unmeasurableCollisionRefusal(agents.detail) };
  const cursor = readCursorDirs(pluginRoot);
  if (!cursor.ok) return { ok: false, refusal: unmeasurableCollisionRefusal(cursor.detail) };
  return { ok: true, counted, cap, agentPaths: agents.paths, cursorDirs: cursor.dirs, commandNames: readCommandNames(pluginRoot) };
}

// =============================================================================
// Step A -- create-propose
// =============================================================================

export interface CreateProposeArgs {
  repoRoot: string;
  octokit: ArmOctokit;
  patterns: readonly PatternPage[];
  ledgerEntries: readonly LedgerEntry[];
  /** The MEMOIZED run-start ISO timestamp (the ledger's TTL clock). */
  runStartedAt: string;
  /** `weekCap.remaining - editPrsOpenedThisRun`, computed by the handler from memoized values. */
  capLeft: number;
  /**
   * Cluster hashes the EDIT loop recorded this run (opened or attempted). Both arms build the branch
   * `self-healing/auto-<hash>-<date>`, so a create that chose one of these would collide with the edit PR it just
   * opened; each is treated as suppressed.
   */
  sameRunHashes?: readonly string[];
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
    return fail("model-invalid", "internal");
  }
}

/** An open PR that adds an agent or a command named like the slug collides with it just as a skill dir would. */
function openPrAgentOrCommandCollision(slug: string, openPrPaths: readonly string[]): "open-pr-agent" | "open-pr-command" | null {
  for (const path of openPrPaths) {
    if (path.startsWith("plugins/soleur/agents/") && path.endsWith(`/${slug}.md`)) return "open-pr-agent";
    if (path === `plugins/soleur/commands/${slug}.md`) return "open-pr-command";
  }
  return null;
}

async function proposeInner(a: CreateProposeArgs): Promise<CreateVerdict> {
  // week-cap: the edit loop ran first and shares the cap (`remaining - editPrsOpenedThisRun`).
  if (!(a.capLeft > 0)) return fail("week-cap", "no-slot");

  // index-empty before any I/O: a create needs a pattern to be about.
  if (a.patterns.length === 0) return fail("index-empty", "no-open-patterns");

  // The clone is the arm's only data source: a lost clone is its own named refusal, not a budget or slug symptom.
  if (!existsSync(a.repoRoot)) return fail("persist", "clone-missing");

  // create-open: at most one open create at a time. A list that cannot be read refuses.
  const open = await findOpenCreatePr(a.octokit, REPO_OWNER, REPO_NAME);
  if (open.kind === "open") return fail("create-open", "open-create-pr");
  if (open.kind === "unverifiable") return fail("create-open", open.detail, { extra: open.cause ? { cause: open.cause } : undefined });

  // budget inputs and the collision populations, measured from the clone BEFORE the billed call (fail closed).
  const measured = await measureClone(a.repoRoot);
  if (!measured.ok) return mirrored(measured.refusal, measured.extra);

  // open-PR paths feed the slug and nearest-skill collision gates; an incomplete scan is unverifiable, never clear.
  let openPrPaths: string[];
  try {
    const scanned = await a.scanOpenPrPaths(CREATE_PR_PATH_PREFIXES);
    if (scanned.incomplete !== null) return fail("create-open", "paths-incomplete");
    openPrPaths = scanned.paths;
  } catch (err) {
    return fail("create-open", "paths-unverifiable", { extra: { cause: causeToken(err) } });
  }

  const nonce = a.nonce ?? randomBytes(8).toString("hex");
  const prepared = prepareCreate({ patterns: a.patterns, skills: measured.counted.records, nonce });
  if (prepared.kind === "refused") return mirrored(prepared);

  if (!a.apiKey) return fail("model-invalid", "no-api-key");
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
      markerSource: CREATE_ARM_FEATURE,
      markerRunId: a.runId,
    });
    text = res.text;
    stopReason = res.stopReason;
  } catch (err) {
    return fail("model-invalid", "transport", { extra: { cause: causeToken(err) } });
  }
  if (stopReason === "max_tokens") return fail("model-invalid", "max-tokens");
  if (!text) return fail("model-invalid", "empty");
  const raw = parseCreateModelText(text);
  if (raw === undefined) return fail("model-invalid", "not-json");

  const runNow = new Date(a.runStartedAt);
  const sameRun = new Set(a.sameRunHashes ?? []);
  const verdict = checkCreate(raw, {
    patterns: a.patterns,
    skills: measured.counted.records,
    skillDirs: measured.counted.dirs,
    agentPaths: measured.agentPaths,
    cursorDirs: measured.cursorDirs,
    commandNames: measured.commandNames,
    openPrPaths,
    budget: { total: measured.counted.total, cap: measured.cap },
    isHashSuppressed: (hash) => sameRun.has(hash) || decideSuppression({ entries: a.ledgerEntries, hash, now: runNow }),
  });
  if (verdict.kind === "refused") return mirrored(verdict);
  if (verdict.kind === "create") {
    const clash = openPrAgentOrCommandCollision(verdict.proposal.slug, openPrPaths);
    if (clash) return fail("slug", clash);
  }
  return verdict;
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
  /** The chosen pattern page (its evidence count is the promotion-log `n` column; the re-check needs the page). */
  page: PatternPage;
  /** Test seams. */
  safeCommit?: typeof safeCommitAndPr;
  setOrigin?: typeof setOriginToken;
  metaParent?: string;
  now?: () => number;
  deadlineMs?: number;
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
  // The two checks the create PR does NOT get synthesized (a test pins this literal to CREATE_EXCLUDED_SYNTHETIC_CHECKS).
  const real = REAL_CHECK_NAMES.map((n) => `\`${n}\``).join(" and ");
  return [
    CREATE_PR_BODY_LINE,
    "",
    `Proposed by the compound-promotion loop (WikiSkill phase 2). Ref #10550.`,
    `Skill: ${p.slug}. Pattern: ${p.pattern_slug}. Cluster-Hash: ${v.clusterHash}. Nearest existing skill: ${p.nearest_skill}.`,
    `Description words used: ${v.words} of at most ${CREATE_DESCRIPTION_MAX_WORDS}. Budget headroom before this skill: ${v.headroom} words (total ${v.total}, cap ${v.cap}).`,
    `Top-1 overlap with an existing skill: ${v.overlap.top1} (${v.overlap.top1Name}); refused at or above ${OVERLAP_REFUSE_THRESHOLD.toFixed(2)}. Rank of the nearest skill: ${v.overlap.nearestRank}.`,
    `Real CI results on this draft: ${real} only. Every other required check is posted by the loop itself and proves nothing about this skill.`,
    "",
    "Reviewer checklist (fixed text):",
    "- [ ] Read every step as an instruction to an agent that holds shell access and secrets.",
    "- [ ] No step reads, prints or posts credentials or env files.",
    "- [ ] No step is destructive or irreversible.",
    "- [ ] Will this description trigger on unrelated prompts? Narrow it or reject.",
    "- [ ] Scan PURPOSE.md for names, domains or identifiers before merge.",
    "- [ ] Positioning: the skill makes Soleur sharper for the harness itself. No wording that promises an outcome in a user's workspace.",
    "- [ ] The skill does not restate or relax any hard rule.",
    "- [ ] Categorise the skill in plugins/soleur/docs/_data/skills.js (an unmapped skill shows as Uncategorized).",
    "- [ ] After any description edit, or a rebase onto a main that added another skill, rerun `bun plugins/soleur/scripts/sync-cursor-name-map.ts` and `bash scripts/sync-readme-counts.sh`.",
    "",
    "Draft for human review. Close to reject.",
  ].join("\n");
}

/** Hardened, scrubbed git calls for the clone hygiene around Step B. */
async function restoreCleanMain(root: string): Promise<boolean> {
  // Short-circuits on the first failed call: once `reset` failed, `clean` and `checkout` would act on a clone in an unknown state.
  for (const args of [["reset", "--hard", "HEAD"], ["clean", "-fd"], ["checkout", "main"]]) {
    if (!(await runGit(root, args, { timeoutMs: GIT_TIMEOUT_MS })).ok) return false;
  }
  return true;
}

const stripOrigin = (root: string, timeoutMs = GIT_TIMEOUT_MS) => runGit(root, ["remote", "set-url", "origin", PLAIN_ORIGIN_URL], { timeoutMs });

/** Blob ids of the base-sensitive paths at `ref` (`HEAD` or `FETCH_HEAD`); `null` when git cannot name them all. */
async function baseBlobs(root: string, ref: string, timeoutMs: number): Promise<string[] | null> {
  const r = await runGit(root, ["rev-parse", ...BASE_BLOB_PATHS.map((p) => `${ref}:${p}`)], { timeoutMs });
  if (!r.ok) return null;
  const ids = r.stdout.split("\n").filter(Boolean);
  return ids.length === BASE_BLOB_PATHS.length && ids.every((i) => /^[0-9a-f]{40,64}$/.test(i)) ? ids : null;
}

interface PersistCtx {
  slug: string;
  dateSuffix: string;
  branchName: string;
  metaBase: string;
  /** Milliseconds left of the one Step B deadline. */
  left: () => number;
  /** Set once the token has been written to `.git/config`, so the cleanup knows to strip it. */
  originTouched: boolean;
}

/**
 * Step B. ONE step: look up our own open PR, refresh the clone, re-check, render, write, scan, sync, collect, commit.
 * A refused create writes no ledger row (the row is only ever inside the committed PR). The clone is returned to a
 * clean main before and after, and the token is stripped from `.git/config` on the way out.
 */
export async function runCreatePersistStep(a: CreatePersistArgs): Promise<CreatePersistResult> {
  const v = a.verdict;
  const slug = v.proposal.slug;
  const dateSuffix = a.runStartedAt.slice(0, 10);
  const branchName = createBranchName(v.clusterHash, dateSuffix);
  if (!BRANCH_SHAPE_RE.test(branchName)) return fail("persist", "branch-shape");
  if (!existsSync(a.repoRoot)) return fail("persist", "clone-missing");

  // Replay: a previous attempt of THIS step may already have opened our PR. A hit is success, not a second PR, but
  // ONLY when it is a create PR: the edit arm builds the same branch shape, and an edit PR is not our PR.
  try {
    const own = await a.octokit.request("GET /repos/{owner}/{repo}/pulls", {
      owner: REPO_OWNER, repo: REPO_NAME, state: "open", head: `${REPO_OWNER}:${branchName}`, per_page: 1,
      request: { signal: AbortSignal.timeout(PR_LIST_TIMEOUT_MS) },
    });
    if (Array.isArray(own.data) && own.data.length > 0) {
      const hit = own.data[0] as { number?: unknown; body?: unknown };
      const pr = Number.isInteger(hit.number) ? (hit.number as number) : undefined;
      if (typeof hit.body === "string" && hit.body.includes(CREATE_PR_BODY_LINE)) return { kind: "opened", ...(pr === undefined ? {} : { pr }), resumed: true };
      return fail("persist", "branch-taken", { numbers: pr === undefined ? undefined : { pr } });
    }
  } catch (err) {
    // Not provable either way: continue (safeCommitAndPr's own branch-keyed replay-resume is the second layer), loudly.
    reportSilentFallback(err, { feature: CREATE_ARM_FEATURE, op: "create-own-pr-lookup-failed", message: "own open PR lookup failed", extra: { cause: causeToken(err) } });
  }

  const now = a.now ?? Date.now;
  const deadlineAt = now() + (a.deadlineMs ?? CREATE_PERSIST_DEADLINE_MS);
  const metaBase = await mkdtemp(join(a.metaParent ?? tmpdir(), "compound-promote-create-scan-"));
  const ctx: PersistCtx = { slug, dateSuffix, branchName, metaBase, left: () => deadlineAt - now(), originTouched: false };
  let restoredUpfront = false;
  try {
    // A retry of this step must start from a clean main (the previous attempt may have left files behind).
    if (!(await restoreCleanMain(a.repoRoot))) return fail("persist", "clone-not-clean");
    restoredUpfront = true;
    return await persistInner(a, ctx);
  } catch (err) {
    reportSilentFallback(err, { feature: CREATE_ARM_FEATURE, op: "create-persist-internal", message: "create-persist failed unexpectedly" });
    return fail("persist", "internal", { extra: { cause: causeToken(err) } });
  } finally {
    await rm(metaBase, { recursive: true, force: true }).catch(() => {
      // review: swallowed -- best-effort removal of a scratch dir outside the clone; the OS temp reaper bounds a leak.
    });
    // The token never outlives the step on disk, whatever the outcome (best effort; the workspace is torn down next).
    if (ctx.originTouched) await stripOrigin(a.repoRoot);
    // The unconditional reset also discards the residue of a refusal: nothing a refused create wrote survives. Skipped
    // when the very first restore already failed: a second attempt on a clone in an unknown state proves nothing.
    if (restoredUpfront && !(await restoreCleanMain(a.repoRoot))) {
      reportSilentFallback(null, { feature: CREATE_ARM_FEATURE, op: "create-clone-restore-failed", message: "could not return the clone to a clean main" });
    }
  }
}

function scanFailure(scan: Extract<ScanResult, { ok: false }>): CreateRefusal {
  const numbers: Record<string, number> = {
    ...(scan.fileIndex === undefined ? {} : { file_index: scan.fileIndex }),
    ...(scan.exit === undefined ? {} : { exit_code: scan.exit }),
    ...(scan.missing?.length ? { missing_tools: scan.missing.length } : {}),
  };
  return mirrored(refusal("scan", scan.detail, numbers), {
    ...(scan.signal === undefined ? {} : { signal: scan.signal }),
    ...(scan.missing?.length ? { missing_tool_names: scan.missing } : {}),
  });
}

function readmeFailure(sync: Extract<ReadmeSyncResult, { ok: false }>): CreateRefusal {
  const numbers: Record<string, number> = {
    ...(sync.changedCount === undefined ? {} : { changed_count: sync.changedCount }),
    ...(sync.exit === undefined ? {} : { exit_code: sync.exit }),
  };
  return mirrored(refusal("readme-sync", sync.detail, numbers), sync.signal === undefined ? undefined : { signal: sync.signal });
}

async function persistInner(a: CreatePersistArgs, c: PersistCtx): Promise<CreatePersistResult> {
  const v = a.verdict;
  const proposal: CreateProposal = v.proposal;
  const setOrigin = a.setOrigin ?? setOriginToken;
  const budgetMs = (own: number): number => Math.max(1, Math.min(own, c.left()));
  const expired = (): CreateRefusal | null => (c.left() <= 0 ? fail("persist", "deadline") : null);

  // ---- R5: refresh the depth-1 clone to the current main, then R4: take the token OFF disk ----------------------
  let early = expired();
  if (early) return early;
  try {
    c.originTouched = true;
    await setOrigin(a.repoRoot, a.installationToken);
  } catch (err) {
    return fail("persist", "origin-failed", { extra: { cause: causeToken(err) } });
  }
  if (!(await runGit(a.repoRoot, ["fetch", "--depth=1", "origin", "main"], { timeoutMs: budgetMs(FETCH_TIMEOUT_MS) })).ok) {
    return expired() ?? fail("persist", "fetch-failed");
  }
  if (!(await runGit(a.repoRoot, ["reset", "--hard", "FETCH_HEAD"], { timeoutMs: budgetMs(GIT_TIMEOUT_MS) })).ok) return fail("persist", "reset-failed");
  const usedBlobs = await baseBlobs(a.repoRoot, "HEAD", budgetMs(GIT_TIMEOUT_MS));
  if (usedBlobs === null) return fail("persist", "blob-read-failed");
  // From here to the commit no script may see the token (a spawned script could read `.git/config`).
  if (!(await stripOrigin(a.repoRoot, budgetMs(GIT_TIMEOUT_MS))).ok) return fail("persist", "origin-strip-failed");

  // ---- re-run the admission checks against the refreshed tree ---------------------------------------------------
  const measured = await measureClone(a.repoRoot);
  if (!measured.ok) return mirrored(measured.refusal, measured.extra);
  const recheck = checkCreate(proposal, {
    patterns: [a.page],
    skills: measured.counted.records,
    skillDirs: measured.counted.dirs,
    agentPaths: measured.agentPaths,
    cursorDirs: measured.cursorDirs,
    commandNames: measured.commandNames,
    openPrPaths: [],
    budget: { total: measured.counted.total, cap: measured.cap },
    isHashSuppressed: () => false, // the ledger was consulted in Step A, against the same memoized run clock
  });
  if (recheck.kind === "refused") return mirrored(recheck);
  if (recheck.kind !== "create" || recheck.clusterHash !== v.clusterHash) return fail("persist", "recheck-mismatch");

  // ---- render ---------------------------------------------------------------------------------------------------
  let grokBlock: string;
  let purposeTemplate: string;
  try {
    grokBlock = readGrokBlock(await readFile(join(a.repoRoot, GROK_BLOCK_SOURCE_PATH), "utf8"));
    purposeTemplate = await readFile(join(a.repoRoot, PURPOSE_TEMPLATE_PATH), "utf8");
  } catch (err) {
    return fail("shape", "template-unreadable", { extra: { cause: causeToken(err) } });
  }
  const rendered = renderCreateFiles({ proposal, grokBlock, purposeTemplate, date: c.dateSuffix, evidenceCount: a.page.evidence.length });
  if (rendered.kind === "refused") return mirrored(rendered);

  // Files on disk FIRST: the scanner and the exactPaths staging both read the disk.
  early = expired();
  if (early) return early;
  const paths = createPathList(c.slug);
  const [skillRel, purposeRel, stubRel] = paths;
  const logIndex = paths.indexOf(PROMOTION_LOG_PATH);
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
  const logRow = `\n| ${c.dateSuffix} | ${v.clusterHash} | ${skillRel} | ${a.page.evidence.length} | pending | skill | (PR pending) |\n`;
  let logBase: string;
  try {
    logBase = await readFile(join(a.repoRoot, PROMOTION_LOG_PATH), "utf8");
  } catch (err) {
    return fail("persist", "log-unreadable", { extra: { cause: causeToken(err) } });
  }
  await appendFile(join(a.repoRoot, PROMOTION_LOG_PATH), logRow);

  // The baseline is taken BEFORE the scanner runs, so a scan-time write to any non-README path is caught by the sync's guard.
  const since = await snapshotClone(a.repoRoot);
  if (!since) return fail("persist", "git-failed");

  // ---- gates ----------------------------------------------------------------------------------------------------
  early = expired();
  if (early) return early;
  // Two files are scanned one after the other, so each gets at most half of what is left.
  const scan = await runSkillScan({ repoRoot: a.repoRoot, relPaths: [skillRel, purposeRel], metaBase: c.metaBase, timeoutMs: Math.max(1, Math.min(SCAN_TIMEOUT_MS, Math.floor(c.left() / 2))) });
  if (!scan.ok) return scan.detail === "timeout" && c.left() <= 0 ? fail("persist", "deadline") : scanFailure(scan);

  early = expired();
  if (early) return early;
  const sync = await syncReadmeCounts({ repoRoot: a.repoRoot, timeoutMs: budgetMs(README_SYNC_TIMEOUT_MS), since });
  if (!sync.ok) return sync.detail === "timeout" && c.left() <= 0 ? fail("persist", "deadline") : readmeFailure(sync);

  const collected = await collectCreateContent({ repoRoot: a.repoRoot, slug: c.slug });
  if (!collected.ok) {
    return fail("persist", collected.detail, { numbers: collected.index === undefined ? undefined : { path_index: collected.index } });
  }

  // ---- bytes committed == bytes gated ---------------------------------------------------------------------------
  const gated: Array<[number, string]> = [
    [0, rendered.files.skillMd],
    [1, rendered.files.purposeMd],
    [2, rendered.files.stub],
    [logIndex, logBase + logRow],
  ];
  for (const [index, text] of gated) {
    if (collected.expectedContent[paths[index]] !== text) return fail("persist", "bytes-differ", { numbers: { path_index: index } });
  }

  // ---- R4/R5: put the token back for the network calls only, and prove the base did not move -------------------
  early = expired();
  if (early) return early;
  try {
    await setOrigin(a.repoRoot, a.installationToken);
  } catch (err) {
    return fail("persist", "origin-failed", { extra: { cause: causeToken(err) } });
  }
  if (!(await runGit(a.repoRoot, ["fetch", "--depth=1", "origin", "main"], { timeoutMs: budgetMs(FETCH_TIMEOUT_MS) })).ok) {
    return expired() ?? fail("persist", "fetch-failed");
  }
  const nowBlobs = await baseBlobs(a.repoRoot, "FETCH_HEAD", budgetMs(GIT_TIMEOUT_MS));
  if (nowBlobs === null) return fail("persist", "blob-read-failed");
  const moved = nowBlobs.filter((id, i) => id !== usedBlobs[i]).length;
  if (moved > 0) return fail("persist", "base-moved", { numbers: { changed_count: moved } });
  early = expired();
  if (early) return early;

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
    cronName: CREATE_ARM_FEATURE,
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
  a.logger.warn({ fn: CREATE_ARM_FEATURE, hash: v.clusterHash, status: result.status }, "create-not-committed");
  const detail = result.status === "failed" ? `failed-${result.stage}` : `not-committed-${result.status}`;
  return fail("persist", detail);
}
