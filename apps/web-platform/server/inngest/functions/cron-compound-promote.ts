// TR9 PR-11 (Refs #3948) — Migrated from the GHA scheduled-compound-promote
// workflow (deleted in the same PR per TR9 I-13 hygiene). Pure TS port —
// scripts/compound-promote.sh remains on disk for operator-local
// hand-testing but is NOT the runtime contract (gh CLI absent from
// Hetzner Dockerfile per TR9 PR-6 deepen-pass verification).
//
// ADR-033 invariants (binding all cron-*.ts files):
//   I1 — Octokit + node:fs reads called INSIDE step.run (replay memoization).
//   I2 — Operator-owned data only; never founder BYOK. Auto-asserted by
//        test/server/cron-no-byok-lease-sweep.test.ts via cron-*.ts glob.
//   I3 — Outer wall-clock safety via Promise.race (MAX_RUN_DURATION_MS).
//   I4 — N/A (no claude binary; pure TS + Anthropic fetch).
//   I5 — Deterministic step.run return shape per step (see handler).
//   I6 — No event payloads emitted.
//
// PURE-TS PATTERN — PR-6 shape (cron-strategy-review.ts), NOT PR-7 claude-
// eval-spawn shape. See ADR-027 (stateless self-modifying cron).

import { createHash } from "node:crypto";
import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import {
  appendFile,
  mkdtemp,
  readFile,
  readdir,
  rm,
  writeFile,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, relative } from "node:path";
import { Octokit } from "@octokit/core";
import { inngest } from "@/server/inngest/client";
import { reportSilentFallback } from "@/server/observability";
import {
  REPO_OWNER,
  REPO_NAME,
  redactToken,
  buildAuthenticatedCloneUrl,
  resolveCronWorkspaceRoot,
  warnIfCronWorkspaceLowOnDisk,
  mintInstallationToken,
  postAnthropicMessage,
  postSentryHeartbeat,
  type HandlerArgs,
} from "./_cron-shared";
import { SYNTHETIC_CHECK_NAMES, safeCommitAndPr } from "./_cron-safe-commit";
import { EXECUTION_MODEL } from "@/server/inngest/model-tiers";

// =============================================================================
// Constants
// =============================================================================

const SENTRY_MONITOR_SLUG = "scheduled-compound-promote";

export const MAX_RUN_DURATION_MS = 10 * 60 * 1000;
const TOKEN_MIN_LIFETIME_MS = 15 * 60 * 1000;

const WEEK_CAP_DEFAULT = 2;
export const MAX_DIFF_BYTES = 16384;

// Always-loaded (AGENTS.md + AGENTS.rules.md) byte budgets.
//
// Source of truth: scripts/lint-agents-rule-budget.py (B_ALWAYS_REJECT /
// B_ALWAYS_WARN). Agreement across every restatement site is enforced by
// scripts/lint-agents-compound-sync.sh — change a value here without changing
// the linter (or vice versa) and that guard fails the build. Do not edit either
// side alone; that de-sync is what issue #6461 was filed for.
//
// UNIT (unit-exact, #6794): both measurement sites below run through
// measureAlwaysLoadedBytes, which measures on the SAME basis the linter's
// thresholds are defined over (scripts/lint-agents-rule-budget.py: b_index RAW +
// b_corpus FRONTMATTER-STRIPPED). The previously-documented raw-vs-stripped skew
// (~73 B, the frontmatter block on the rule corpus — the only always-loaded file
// with frontmatter) is closed; the comparison is exact, not merely fail-safe.
// The over-strip guard inside the helper keeps the DANGEROUS (falsely-smaller)
// direction fail-safe by falling back to RAW bytes if a malformed strip drops a
// rule line.
//
// Hard ceiling for the POST-APPLY gate: mirrors the commit gate exactly, so an
// applied diff that would be rejected at commit time is reverted here instead.
// Per ADR-092 / AP-017 this byte cap is the only VOLUMETRIC brake on the
// additive envelope of the harness self-edit path, so it must track the real
// ceiling rather than sit at an arbitrary lower value.
const MAX_ALWAYS_LOADED_BYTES = 46000;

// Budget the clustering LLM is told to propose against. Deliberately the WARN
// floor, not the reject ceiling: the promoter's job is not "propose anything the
// gate would not reject" — it is "propose something that leaves headroom" for the
// next promotion and for hand-authored rules. Binding this to the reject ceiling
// would let a cluster land at exactly the cap and pin the registry there.
const PROPOSE_ALWAYS_LOADED_BUDGET = 44000;

// #6794 (inlined per #6860): the frontmatter-strip contract
// (scripts/lib/frontmatter-strip/SPEC.md; parity-pinned across strip.sh/py/ts by
// scripts/lib/frontmatter-strip.test.sh). Inlined here rather than imported from
// repo-root scripts/ because the Next.js Docker build context copies only
// apps/web-platform/ (+ the vendored plugin), NOT repo-root scripts/ — a
// cross-root import compiles under a local `next build` (full repo present) but
// fails the containerized build with "Module not found: ../../../../../scripts/…".
// This body is byte-identical in behavior to strip.py/strip.ts; keep it in
// lockstep with SPEC.md (a ~6-line startsWith/split, near-zero drift surface).
function stripFrontmatter(text: string): string {
  if (!text.startsWith("---\n")) {
    return text;
  }
  const lines = text.split("\n");
  for (let i = 1; i < lines.length; i++) {
    if (lines[i] === "---") {
      return lines.slice(i + 1).join("\n");
    }
  }
  // Opening delimiter with no close — malformed; consume everything (over-strip).
  return "";
}

// #6794: measure the always-loaded (AGENTS.md + AGENTS.rules.md) payload on the
// SAME basis as the commit gate's authority (scripts/lint-agents-rule-budget.py):
// b_index RAW (`file_bytes`, no strip) + b_core FRONTMATTER-STRIPPED.
// measureAlwaysLoadedBytes mirrors that split exactly — stripping only the corpus,
// which is the only always-loaded file that carries frontmatter. Extracted +
// exported so the promoter-vs-B_ALWAYS invariant is unit-testable without
// invoking the handler.
//
// OVER-STRIP GUARD (the DANGEROUS direction): a malformed/unterminated `---`
// consumes the corpus to EMPTY → a falsely-SMALLER byte count that could
// falsely PASS the cap. Mirrors the linter's guard: if the strip drops any
// `- …[id: …]` rule line, fall back to RAW bytes (fail-safe) + emit a distinct
// Sentry signal. The anchored regex matches lint-agents-rule-budget.py's
// `_RULE_LINE_RE = ^- .*\[id: ` line-for-line (pinned by
// scripts/lib/rule-line-regex-parity.test.sh).
const RULE_LINE_RE = /^- .*\[id: /;

function ruleLineCount(text: string): number {
  let n = 0;
  for (const line of text.split("\n")) {
    if (RULE_LINE_RE.test(line)) n++;
  }
  return n;
}

function measureFileStrippedBytes(text: string, file: string): number {
  const stripped = stripFrontmatter(text);
  if (ruleLineCount(stripped) < ruleLineCount(text)) {
    // Over-strip: malformed frontmatter consumed rule bodies. Never trust the
    // (smaller) stripped count — it could pass an oversized payload. Fall back
    // to raw and page.
    reportSilentFallback(
      new Error("frontmatter over-strip dropped rule lines"),
      {
        feature: "cron-compound-promote",
        op: "frontmatter-overstrip-fallback",
        extra: { file },
      },
    );
    return Buffer.byteLength(text, "utf8");
  }
  return Buffer.byteLength(stripped, "utf8");
}

/**
 * Always-loaded byte total, byte-exact with the commit-gate authority (#6794).
 * The index (AGENTS.md) is measured RAW and only the corpus (AGENTS.rules.md)
 * is frontmatter-stripped — exactly `lint-agents-rule-budget.py`'s
 * `b_index = file_bytes(index)` + `b_corpus = len(strip(corpus))`. This is
 * faithful in ALL cases, not just while AGENTS.md happens to carry no
 * frontmatter: were a `---` block ever added to the index, uniformly stripping
 * it would UNDER-count vs the authority (the dangerous direction) and the
 * over-strip guard could not catch it (an index over-strip drops no `[id:]`
 * pointer line).
 *
 * Callers MUST pass real file contents. Passing "" for a missing file (the old
 * existsSync-guarded behavior) silently under-reports the payload and invents
 * phantom headroom — the exact fail-open ADR-151 removed. `readAlwaysLoaded`
 * below throws instead.
 */
export function measureAlwaysLoadedBytes(
  indexText: string,
  corpusText: string,
): number {
  return (
    Buffer.byteLength(indexText, "utf8") +
    measureFileStrippedBytes(corpusText, "AGENTS.rules.md")
  );
}

/**
 * Read the always-loaded pair, failing LOUD if either file is absent.
 *
 * Before ADR-151 both reads were `existsSync(p) ? await readFile(p) : ""`. When
 * the corpus filename changed, a deployed build running against a newer checkout
 * read the absent old file as 0 bytes, collapsing the measured payload from
 * ~40 kB to ~5 kB. That invented ~35 kB of headroom for the proposer AND
 * disabled the post-apply overflow guard, which compares against the same
 * falsely-low number. A governance instrument that under-reports its own input
 * is the #7008 defect class; refuse instead.
 */
async function readAlwaysLoaded(
  repoRoot: string,
): Promise<{ indexText: string; corpusText: string }> {
  const indexPath = join(repoRoot, "AGENTS.md");
  const corpusPath = join(repoRoot, "AGENTS.rules.md");
  for (const p of [indexPath, corpusPath]) {
    if (!existsSync(p)) {
      throw new Error(
        `compound-promote: ${p} missing — refusing to compute the always-loaded ` +
          `byte budget from a partial corpus (would invent phantom headroom).`,
      );
    }
  }
  return {
    indexText: await readFile(indexPath, "utf8"),
    corpusText: await readFile(corpusPath, "utf8"),
  };
}

export const TARGET_ALLOW_RE =
  /^(AGENTS\.rules\.md|plugins\/soleur\/skills\/[A-Za-z0-9_-]+\/SKILL\.md)$/;

// =============================================================================
// Outcome marker (#8281)
// =============================================================================

/**
 * Every terminal path of this handler returns a `status`. Until #8281 that
 * string was returned into the void: the only signal a run emitted was
 * `postSentryHeartbeat({ ok: true })`, which proves LIVENESS and says nothing
 * about WORK. Ten weeks of zero output were therefore undiagnosable — the
 * handler was not failing, it was succeeding at nothing and saying ok.
 *
 * WARN is load-bearing, not stylistic: only pino WARN+ transits Vector to the
 * Better Stack source, so an `info` marker would be unqueryable and would
 * recreate the exact blind spot this exists to remove. Precedent:
 * `claude-cost-marker.ts` ("Emit one SOLEUR_CLAUDE_COST WARN marker").
 *
 * Never throws — observability must not break a run.
 */
export interface CompoundPromoteOutcome {
  status: string;
  corpus_count?: number;
  clusters_proposed?: number;
  clusters_opened?: number;
  /** One entry per refusal site that fired, in order. */
  refusals?: string[];
  /**
   * Bounded per-cluster refusal detail. Carries a cluster hash and a fixed
   * reason enum ONLY — never learning text or paths — so a recurring refusal of
   * the SAME cluster is distinguishable from a genuinely quiet corpus.
   */
  refusal_detail?: { cluster_hash: string; reason: string }[];
  /** Bytes of the corpus payload serialized into the Anthropic message. */
  corpus_input_bytes?: number;
  /**
   * Which trigger produced this run. BOTH triggers dispatch this same handler
   * (`{ cron: "0 0 * * 0" }` and `{ event: "...manual-trigger" }` are registered
   * on one function), so nothing downstream can tell them apart without this
   * field — and the #8281 soak probe's whole claim is about the SCHEDULED path.
   * Without it a manual fire during the soak window closes the tracker while
   * the weekly path stays dark.
   */
  trigger?: "cron" | "manual";
  /** Inngest run id — the join key to a Sentry event for the same run. */
  run_id?: string;
}

/**
 * What one cluster's `apply-and-pr` step DID, carried in the step's RETURN
 * VALUE rather than pushed into a handler-scope array.
 *
 * Inngest memoizes a completed `step.run`'s return value and re-executes the
 * surrounding handler body on every resume WITHOUT re-entering the callback.
 * The accumulators used to be plain arrays in the body, mutated from inside
 * these callbacks -- so on the pass that finally reaches the `completed`
 * marker every cluster step is memoized, no push has happened, and the marker
 * emitted `refusals: []` / `clusters_opened: 0` for a run that refused every
 * cluster. That is byte-identical to a genuinely quiet corpus, which is the
 * exact distinction #8281 exists to make. A returned value replays; a closure
 * mutation does not.
 */
type ClusterOutcome =
  | { kind: "opened" }
  | { kind: "refused"; reason: string };

/** Cap on `refusal_detail` entries so one pathological run cannot flood the sink. */
export const REFUSAL_DETAIL_CAP = 20;

export function emitOutcomeMarker(
  logger: { warn: (obj: object, msg: string) => void },
  outcome: CompoundPromoteOutcome,
): void {
  try {
    logger.warn(
      {
        SOLEUR_COMPOUND_PROMOTE_OUTCOME: true,
        fn: "cron-compound-promote",
        ...outcome,
        refusal_detail: outcome.refusal_detail?.slice(0, REFUSAL_DETAIL_CAP),
      },
      "compound promote outcome",
    );
  } catch {
    // fail-open: a marker-emit failure must never propagate into the caller.
  }
}

// =============================================================================
// Diff path derivation (#8274)
// =============================================================================

export type DiffPathVerdict =
  | { ok: true; paths: string[] }
  | { ok: false; reason: "structural-op" | "underivable" | "path-refused"; detail: string };

/**
 * Decide whether a proposal diff may be applied, deriving the affected paths
 * from git ITSELF rather than from a hand-written header parser.
 *
 * Two measured facts drive the shape:
 *
 *  1. `git apply` with no `-p` strips ONE leading path component, whatever it
 *     is. The shipped filter matched `+++ b/` literally, so `+++ x/…` and
 *     `+++ w/…` wrote files it never saw and the allowlist passed vacuously.
 *
 *  2. `--numstat` reports only a rename's DESTINATION. A diff renaming
 *     `AGENTS.rules.md` to an allowlisted `SKILL.md` path therefore yields a
 *     fully-allowlisted path set while the apply DELETES the rule corpus — so a
 *     numstat-only derivation would have shipped a second bypass of the guard
 *     it was fixing.
 *
 * An earlier revision of this guard answered (2) with `git apply --summary`,
 * on the stated invariant that a non-empty summary means create/delete/rename/
 * copy/mode-change and an EMPTY one means a pure content edit. **That invariant
 * is false, and review measured it false.** `--summary` reports a rename only
 * when the patch carries explicit `rename from` / `rename to` headers. For an
 * IMPLICIT rename — a `diff --git a/X b/Y` whose `---` and `+++` name different
 * files with no rename headers — `--summary` is EMPTY, `--numstat` reports only
 * Y, and `git apply` still DELETES X. Measured (git 2.55.0):
 *
 *     --- a/plugins/soleur/skills/alpha/SKILL.md
 *     +++ b/AGENTS.rules.md
 *   → summary "", numstat "1\t0\tAGENTS.rules.md", apply rc 0,
 *     status "AD plugins/soleur/skills/alpha/SKILL.md" — the source is GONE.
 *
 * That is the corpus-deleting shape the guard exists to refuse, and it passed.
 * The previous test row only caught the rename because `git mv` emits the
 * explicit headers; a model authoring a diff by hand is under no such
 * obligation. So the derivation no longer asks git what a patch SAYS it will
 * do — it applies the patch to a throwaway index and asks what it DID, which
 * names both sides of every operation by construction.
 *
 * Creation is deliberately refused too: new skills are Phase 2 (#8293).
 */
export async function checkDiffPaths(
  diff: string,
  repoRoot: string,
): Promise<DiffPathVerdict> {
  // A binary hunk is invisible to BOTH this guard's path derivation (it shows
  // as an ordinary modify) and to `diffRemovesHardRule` (base85 payload lines
  // never start with `-`), and the post-apply byte budget only catches GROWTH.
  // Measured: a `GIT binary patch` replaced AGENTS.rules.md wholesale at rc 0
  // with every gate green. These targets are Markdown; a binary patch to one
  // is never an edit.
  if (/^(GIT binary patch|literal \d+|delta \d+)$/m.test(diff)) {
    return { ok: false, reason: "structural-op", detail: "binary patch" };
  }

  const indexFile = join(await mkdtemp(join(tmpdir(), "compound-idx-")), "index");
  try {
    const env = { GIT_INDEX_FILE: indexFile };
    const read = await spawnGitCapture(["read-tree", "HEAD"], repoRoot, "", env);
    if (read.exitCode !== 0) {
      return { ok: false, reason: "underivable", detail: safeDetail(read.stderr) };
    }
    // `--cached` applies to the throwaway index only: a dry run that leaves the
    // worktree untouched while producing git's own account of every path.
    const applied = await spawnGitCapture(["apply", "--cached"], repoRoot, diff, env);
    if (applied.exitCode !== 0) {
      return { ok: false, reason: "underivable", detail: safeDetail(applied.stderr) };
    }
    const named = await spawnGitCapture(
      ["diff-index", "--cached", "-z", "HEAD"],
      repoRoot,
      "",
      env,
    );
    if (named.exitCode !== 0) {
      return { ok: false, reason: "underivable", detail: safeDetail(named.stderr) };
    }

    // RAW format, not `--name-status`: records alternate
    //   `:<srcmode> <dstmode> <srcsha> <dstsha> <status>` \0 `<path>` \0
    // `--name-status` was the first attempt and it reports a mode-only change
    // as plain `M`, so an all-`M` rule ACCEPTED chmod 644→755 — caught by the
    // existing mode-change row. The raw form carries both modes, so the mode
    // is checked rather than inferred from a status letter that cannot express
    // it. A rename/copy emits `R100`/`C100` with TWO paths; a non-`M` status is
    // refused before its arity matters, and any record we cannot parse is
    // refused too, never dropped.
    const fields = named.stdout.split("\0").filter((f) => f.length > 0);
    if (fields.length === 0) {
      // An empty derived set must REFUSE. Reading it as "no forbidden paths"
      // is the vacuous pass a header-less diff exploited.
      return { ok: false, reason: "underivable", detail: "diff changed nothing" };
    }
    const paths: string[] = [];
    for (let i = 0; i < fields.length; i += 2) {
      const meta = fields[i];
      const path = fields[i + 1];
      if (meta === undefined || path === undefined || !meta.startsWith(":")) {
        return { ok: false, reason: "underivable", detail: "unparsable diff-index record" };
      }
      const parts = meta.slice(1).split(" ");
      const [srcMode, dstMode, , , status] = parts;
      if (parts.length !== 5 || srcMode === undefined || dstMode === undefined || !status) {
        return { ok: false, reason: "underivable", detail: "unparsable diff-index record" };
      }
      if (status !== "M") {
        // Create (A), delete (D), rename (R), copy (C) and type-change (T) all
        // land here, named by the status git itself assigned. The implicit
        // rename that defeated the `--summary` derivation surfaces here as a
        // `D` record for the source alongside the `M` for the destination.
        //
        // EQUIVALENT-MUTANT NOTE, with the enumeration that makes it a claim
        // rather than an excuse: disabling this branch does NOT redden the
        // suite, because the mode comparison below already refuses every
        // status this branch can currently see. Enumerated over what
        // `diff-index` emits WITHOUT `-M`/`-C` (which we deliberately do not
        // pass): A is `000000 => <mode>`, D is `<mode> => 000000`, T is
        // e.g. `100644 => 120000` — all three have differing modes; R and C
        // are unreachable without the rename/copy detection flags. So this is
        // defence in depth against a future caller adding `-M`, not dead code,
        // and it is deliberately kept unreachable-alone rather than removed.
        // If `-M` is ever added here, this branch becomes load-bearing and
        // needs its own must-REFUSE row.
        return { ok: false, reason: "structural-op", detail: safeDetail(`${status} ${path}`) };
      }
      if (srcMode !== dstMode) {
        return {
          ok: false,
          reason: "structural-op",
          detail: safeDetail(`mode ${srcMode} => ${dstMode} ${path}`),
        };
      }
      paths.push(path);
    }

    // No `.trim()`: a trailing-space filename is a DIFFERENT file, and trimming
    // made the string we checked differ from the path git wrote. No digit
    // filter either: it silently DROPPED an all-digit path so it was never
    // allowlist-checked at all. Both were measured live.
    const bad = paths.find((p) => !TARGET_ALLOW_RE.test(p));
    if (bad !== undefined) {
      return { ok: false, reason: "path-refused", detail: safeDetail(bad) };
    }
    return { ok: true, paths };
  } finally {
    await rm(dirname(indexFile), { recursive: true, force: true }).catch(() => {});
  }
}

const BRANCH_SHAPE_RE =
  /^self-healing\/auto-[0-9a-f]{64}-[0-9]{4}-[0-9]{2}-[0-9]{2}$/;

export const ANTHROPIC_MODEL = EXECUTION_MODEL;
export const ANTHROPIC_MAX_TOKENS = 16384;
// Structured-output schema (#5186): the model returns clusters wrapped in an
// object (structured-output roots are objects, not top-level arrays). Every
// object needs `additionalProperties: false`; numeric/array constraints are
// NOT supported by the API — the slice(0, remaining) cap stays a post-parse TS
// slice. The prompt and the parse-site read are kept in lockstep with this wrapper.
const CLUSTER_OUTPUT_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["clusters"],
  properties: {
    clusters: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: [
          "cluster_hash",
          "tier",
          "target_path",
          "source_learnings",
          "proposed_diff_unified",
          "rationale",
          "byte_impact",
        ],
        properties: {
          cluster_hash: { type: "string" },
          tier: { type: "string", enum: ["skill", "agents-core"] },
          target_path: { type: "string" },
          source_learnings: { type: "array", items: { type: "string" } },
          proposed_diff_unified: { type: "string" },
          rationale: { type: "string" },
          byte_impact: {
            type: "object",
            additionalProperties: false,
            required: ["before", "after", "delta"],
            properties: {
              before: { type: "integer" },
              after: { type: "integer" },
              delta: { type: "integer" },
            },
          },
        },
      },
    },
  },
} as const;

// Byte-for-byte port of scripts/compound-promote.sh:75 PII_REGEX.
// Unit-tested for parity (AC8).
export const PII_REGEX = new RegExp(
  "([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,})" +
    "|([0-9]{1,3}(\\.[0-9]{1,3}){3})" +
    "|([A-Z]{2}[0-9]{2}[A-Z0-9]{4}[0-9]{7}([A-Z0-9]?){0,16})" +
    "|(eyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+)" +
    "|(sk-ant-[A-Za-z0-9_-]{20,})" +
    "|(gh[psr]_[A-Za-z0-9]{20,})" +
    "|(AKIA[0-9A-Z]{16})" +
    "|((sk|pk)_(live|test)_[A-Za-z0-9]{20,})" +
    "|(xox[baprs]-[A-Za-z0-9-]{10,})",
);

// =============================================================================
// Types
// =============================================================================

interface Cluster {
  cluster_hash: string;
  tier: "skill" | "agents-core";
  target_path: string;
  source_learnings: string[];
  proposed_diff_unified: string;
  rationale: string;
  byte_impact: { before: number; after: number; delta: number };
}

interface HandlerResult {
  ok: boolean;
  status: string;
  clustersOpened?: number;
}

// =============================================================================
// Helpers
// =============================================================================

function spawnGit(
  args: string[],
  opts?: { cwd?: string },
): Promise<{ exitCode: number | null; signal: NodeJS.Signals | null }> {
  return new Promise((resolve) => {
    const child = spawn("git", args, { stdio: "ignore", ...opts });
    child.on("exit", (exitCode, signal) => resolve({ exitCode, signal }));
    child.on("error", () => resolve({ exitCode: -1, signal: null }));
  });
}

/**
 * Run git with the diff on stdin and capture stdout. `spawnGit` uses
 * `stdio: "ignore"`, so it cannot answer a question ABOUT a diff — only whether
 * a command succeeded. The allowlist derivation needs git's own report of what
 * a patch would write, which is stdout.
 */
function spawnGitCapture(
  args: string[],
  cwd: string,
  stdin: string,
  extraEnv?: Record<string, string>,
): Promise<{ exitCode: number | null; stdout: string; stderr: string }> {
  return new Promise((resolve) => {
    // Strip every GIT_* key by PREFIX rather than by a hand-listed set. A
    // `git` child honours an inherited GIT_DIR / GIT_INDEX_FILE over both its
    // cwd and `-C`, so an unconstructed environment makes the derivation
    // answer about a DIFFERENT repository than the one we are guarding
    // (#7833). A name list is a claim about which variables git honours, and
    // it is wrong the moment git adds one.
    const env: Record<string, string> = { ...extraEnv };
    for (const [k, v] of Object.entries(process.env)) {
      if (!k.startsWith("GIT_") && v !== undefined) env[k] = v;
    }
    Object.assign(env, extraEnv ?? {});
    env.GIT_CONFIG_NOSYSTEM = "1";
    env.GIT_CONFIG_GLOBAL = "/dev/null";
    const child = spawn("git", args, {
      cwd,
      stdio: ["pipe", "pipe", "pipe"] as const,
      env: env as NodeJS.ProcessEnv,
    });
    let stdout = "";
    let stderr = "";
    child.stdout?.setEncoding("utf8");
    child.stdout?.on("data", (chunk: string) => {
      stdout += chunk;
    });
    child.stderr?.setEncoding("utf8");
    child.stderr?.on("data", (chunk: string) => {
      // Bounded: git's diagnostic is the diagnosis a refusal carries, but it
      // is rendered from MODEL-SUPPLIED paths, so it is untrusted and capped.
      if (stderr.length < 4096) stderr += chunk;
    });
    child.on("exit", (exitCode) => resolve({ exitCode, stdout, stderr }));
    child.on("error", (err) => resolve({ exitCode: -1, stdout: "", stderr: String(err) }));
    child.stdin?.on("error", () => {
      // A diff large enough to trip EPIPE must not crash the handler; the
      // non-zero exit below is the refusal.
    });
    child.stdin?.end(stdin);
  });
}

/**
 * Strip control characters and the Unicode line separators that survive
 * `JSON.stringify`, then bound the length. Every `detail` we emit is rendered
 * by git from a MODEL-SUPPLIED path, so it is attacker-influenced text on its
 * way to a third-party log store.
 */
function safeDetail(s: string): string {
  // eslint-disable-next-line no-control-regex
  return s.replace(/[\u0000-\u001f\u007f\u2028\u2029]/g, " ").slice(0, 200);
}

async function setupEphemeralWorkspace(
  token: string,
): Promise<{ ephemeralRoot: string; repoRoot: string }> {
  const ephemeralRoot = await mkdtemp(
    join(resolveCronWorkspaceRoot(), "soleur-cron-compound-promote-"),
  );
  const repoRoot = join(ephemeralRoot, "repo");
  await warnIfCronWorkspaceLowOnDisk(ephemeralRoot, "cron-compound-promote");
  const cloneUrl = buildAuthenticatedCloneUrl(token);
  const result = await spawnGit(["clone", "--depth=1", cloneUrl, repoRoot]);
  if (result.exitCode !== 0) {
    throw new Error(
      `git clone failed (exit ${result.exitCode}, signal ${result.signal}) for ${REPO_OWNER}/${REPO_NAME}`,
    );
  }
  if (!existsSync(join(repoRoot, "knowledge-base", "project", "learnings"))) {
    throw new Error(
      "Sentinel: knowledge-base/project/learnings/ absent after clone",
    );
  }
  return { ephemeralRoot, repoRoot };
}

async function teardownEphemeralWorkspace(
  ephemeralRoot: string | null,
): Promise<void> {
  if (!ephemeralRoot) return;
  try {
    await rm(ephemeralRoot, { recursive: true, force: true });
  } catch (err) {
    reportSilentFallback(err, {
      feature: "cron-compound-promote",
      op: "teardown-ephemeral-workspace",
      message: "Failed to remove ephemeral workspace",
      extra: { fn: "cron-compound-promote", ephemeralRoot },
    });
  }
}

// FR2: extract enabled flag with YAML 1.1 coercion tolerance.
export function extractEnabledFlag(raw: string): boolean {
  const match = raw.match(
    /^[ \t]*enabled[ \t]*:[ \t]*["']?([^#\n"']+?)["']?[ \t]*(?:#.*)?$/m,
  );
  if (!match) return false;
  const val = match[1].trim().toLowerCase();
  return val === "true" || val === "yes" || val === "1";
}

// FR10: refuse any cluster whose diff removes a line containing `[id: hr-`
export function diffRemovesHardRule(diff: string): boolean {
  return diff.split("\n").some((line) => {
    return line.startsWith("-") && /\[id:\s*hr-/.test(line);
  });
}

// I3: wall-clock guard via Promise.race. Wraps heavy step callbacks
// so a hung fetch/spawn terminates before Inngest's global timeout.
function withTimeout<T>(fn: () => Promise<T>, ms: number): Promise<T> {
  return Promise.race([
    fn(),
    new Promise<never>((_, reject) => {
      const id = setTimeout(
        () => reject(new Error(`wall-clock exceeded (${ms}ms)`)),
        ms,
      );
      if (typeof id === "object" && "unref" in id) id.unref();
    }),
  ]);
}

function computeClusterHash(sourceLearnings: string[]): string {
  const sorted = [...sourceLearnings].sort();
  return createHash("sha256").update(sorted.join("\n") + "\n").digest("hex");
}

async function applyDiffToWorkspace(
  diff: string,
  repoRoot: string,
): Promise<boolean> {
  // Write the patch inside a per-invocation private temp directory (mode 0700
  // via mkdtemp) rather than a predictable `tmpdir()/...-${Date.now()}.patch`
  // name in the world-readable OS temp dir. A guessable name in a shared dir is
  // pre-creatable/symlinkable by another local user (js/insecure-temporary-file).
  const tmpDir = await mkdtemp(join(tmpdir(), "compound-promote-"));
  const diffFile = join(tmpDir, "diff.patch");
  await writeFile(diffFile, diff);
  try {
    const check = await spawnGit(["apply", "--check", diffFile], {
      cwd: repoRoot,
    });
    if (check.exitCode !== 0) return false;
    // Read the REAL apply's exit code. It used to be discarded and `true`
    // returned unconditionally, so an apply that failed after a passing
    // `--check` (ENOSPC, EACCES, a signal) left `applied` true: the run went
    // on to append a promotion-log row asserting a promotion whose diff never
    // landed, committed that row alone, and counted the cluster as opened.
    // A success path that reports ok while doing nothing is the defect class
    // this whole branch exists to close.
    const applied = await spawnGit(["apply", diffFile], { cwd: repoRoot });
    return applied.exitCode === 0;
  } finally {
    await rm(tmpDir, { recursive: true, force: true }).catch(() => {});
  }
}

// =============================================================================
// Handler
// =============================================================================

export async function cronCompoundPromoteHandler({
  step,
  logger,
  event,
  runId,
}: HandlerArgs): Promise<HandlerResult> {
  // The manual-trigger route stamps `trigger` into the event data
  // (server/routines/run-routine.ts); a scheduled cron fire carries none.
  const trigger: "cron" | "manual" = event?.data?.trigger === undefined ? "cron" : "manual";
  let ephemeralRoot: string | null = null;
  let installationToken = "";

  try {
    // Memoized run-start timestamp — safeCommitAndPr pins commit dates from
    // it (replay-stable, #5111); branch names use the per-cluster override.
    const runStartedAt = await step.run(
      "run-started-at",
      async () => new Date().toISOString(),
    );

    installationToken = await step.run(
      "mint-installation-token",
      async () => mintInstallationToken({ tokenMinLifetimeMs: TOKEN_MIN_LIFETIME_MS }),
    );

    const config = await step.run("read-config", async () => {
      const ws = await setupEphemeralWorkspace(installationToken);
      ephemeralRoot = ws.ephemeralRoot;

      const configPath = join(
        ws.repoRoot,
        "knowledge-base",
        "project",
        "promotion-config.yml",
      );
      if (!existsSync(configPath)) {
        return { enabled: false, repoRoot: ws.repoRoot, ephemeralRoot: ws.ephemeralRoot };
      }
      const raw = await readFile(configPath, "utf-8");
      return {
        enabled: extractEnabledFlag(raw),
        repoRoot: ws.repoRoot,
        ephemeralRoot: ws.ephemeralRoot,
      };
    });

    if (!config.enabled) {
      await step.run("sentry-heartbeat-ok-disabled", () =>
        postSentryHeartbeat({ ok: true, sentryMonitorSlug: SENTRY_MONITOR_SLUG, cronName: "cron-compound-promote", logger }),
      );
      emitOutcomeMarker(logger, { trigger, run_id: runId, status: "disabled" });
      return { ok: true, status: "disabled" };
    }

    const repoRoot = config.repoRoot;
    ephemeralRoot = config.ephemeralRoot;

    // FR3: dedup check via Octokit
    const dedupResult = await step.run("dedup-check", async () => {
      const octokit = new Octokit({ auth: installationToken });
      const { data } = await octokit.request("GET /search/issues", {
        q: `is:issue is:open label:self-healing/auto repo:${REPO_OWNER}/${REPO_NAME} "[Scheduled] Compound Promotion" in:title`,
        per_page: 5,
      });
      if (data.total_count > 0) {
        const sixDaysAgo = Date.now() - 6 * 24 * 60 * 60 * 1000;
        const recent = data.items.some(
          (item) => new Date(item.created_at).getTime() > sixDaysAgo,
        );
        return { deduped: recent };
      }
      return { deduped: false };
    });

    if (dedupResult.deduped) {
      await step.run("sentry-heartbeat-ok-dedup", () =>
        postSentryHeartbeat({ ok: true, sentryMonitorSlug: SENTRY_MONITOR_SLUG, cronName: "cron-compound-promote", logger }),
      );
      emitOutcomeMarker(logger, { trigger, run_id: runId, status: "deduped" });
      return { ok: true, status: "deduped" };
    }

    // FR4: week cap via Octokit
    const weekCapResult = await step.run("week-cap", async () => {
      const octokit = new Octokit({ auth: installationToken });
      const { data } = await octokit.request("GET /search/issues", {
        q: `is:pr is:open label:self-healing/auto repo:${REPO_OWNER}/${REPO_NAME}`,
        per_page: 1,
      });
      const remaining = WEEK_CAP_DEFAULT - data.total_count;
      return { remaining: Math.max(remaining, 0) };
    });

    if (weekCapResult.remaining <= 0) {
      await step.run("sentry-heartbeat-ok-week-cap", () =>
        postSentryHeartbeat({ ok: true, sentryMonitorSlug: SENTRY_MONITOR_SLUG, cronName: "cron-compound-promote", logger }),
      );
      emitOutcomeMarker(logger, { trigger, run_id: runId, status: "week-cap-reached" });
      return { ok: true, status: "week-cap-reached" };
    }

    // FR5/FR6: collect corpus with PII + retired-rule pre-pass
    const corpus = await step.run("collect-corpus", async () => {
      const learningsDir = join(repoRoot, "knowledge-base", "project", "learnings");
      if (!existsSync(learningsDir)) {
        return { entries: [] as { path: string; summary: string }[] };
      }

      const retiredPaths = new Set<string>();
      const retiredFile = join(repoRoot, "scripts", "retired-rule-ids.txt");
      if (existsSync(retiredFile)) {
        const content = await readFile(retiredFile, "utf-8");
        const pathRe = /knowledge-base\/[^ |]+\.md/g;
        for (const line of content.split("\n")) {
          let m: RegExpExecArray | null;
          while ((m = pathRe.exec(line)) !== null) {
            retiredPaths.add(m[0]);
          }
        }
      }

      const entries: { path: string; summary: string }[] = [];
      const walkDir = async (dir: string): Promise<void> => {
        const items = await readdir(dir, { withFileTypes: true });
        for (const item of items) {
          if (item.name === "archive") continue;
          const full = join(dir, item.name);
          if (item.isDirectory()) {
            await walkDir(full);
          } else if (item.name.endsWith(".md")) {
            const relPath = relative(repoRoot, full);
            if (retiredPaths.has(relPath)) {
              logger.info({ fn: "cron-compound-promote", path: relPath }, "retired-excluded");
              continue;
            }
            const content = await readFile(full, "utf-8");
            if (PII_REGEX.test(content)) {
              logger.info({ fn: "cron-compound-promote", path: relPath }, "pii-excluded");
              continue;
            }
            const lines = content.split("\n").slice(0, 10).join("\n");
            entries.push({ path: relPath, summary: lines });
          }
        }
      };
      await walkDir(learningsDir);
      return { entries };
    });

    // #8281: the measured cost driver. The 2026-09-13 run sent 516,512 input
    // tokens and opened nothing; this is the term that made it so.
    const corpusInputBytes = Buffer.byteLength(JSON.stringify(corpus.entries), "utf8");

    if (corpus.entries.length === 0) {
      await step.run("sentry-heartbeat-ok-empty", () =>
        postSentryHeartbeat({ ok: true, sentryMonitorSlug: SENTRY_MONITOR_SLUG, cronName: "cron-compound-promote", logger }),
      );
      emitOutcomeMarker(logger, { trigger, run_id: runId, status: "empty-corpus", corpus_count: 0 });
      return { ok: true, status: "empty-corpus" };
    }

    // FR7/FR8: Anthropic cluster call (I3: wall-clock guard)
    const clusterResult = await step.run("anthropic-cluster", () => withTimeout(async () => {
      const apiKey = process.env.ANTHROPIC_API_KEY;
      if (!apiKey) throw new Error("ANTHROPIC_API_KEY not set");

      const { indexText, corpusText } = await readAlwaysLoaded(repoRoot);
      const alwaysLoadedNow = measureAlwaysLoadedBytes(indexText, corpusText);

      const prompt = [
        `You are a clustering agent. Cluster the following learnings by problem/root-cause similarity. Return up to ${weekCapResult.remaining} qualifying clusters (each with >=5 source learnings).`,
        `Schema: {clusters:[{cluster_hash:'', tier:'skill'|'agents-core', target_path:string, source_learnings:[paths], proposed_diff_unified:string, rationale:string, byte_impact:{before:int,after:int,delta:int}}]}.`,
        `Apply AGENTS.md cq-agents-md-tier-gate: already-enforced -> skip; domain-scoped -> skill; cross-cutting -> agents-core targeting AGENTS.rules.md.`,
        `Current always-loaded payload (AGENTS.md + AGENTS.rules.md) is ${alwaysLoadedNow} bytes; propose against a budget of ${PROPOSE_ALWAYS_LOADED_BUDGET} bytes (the warn floor — leave headroom, do not aim for the hard ceiling).`,
        `target_path MUST be one of: AGENTS.rules.md, plugins/soleur/skills/<skill-name>/SKILL.md. The workflow refuses any other path. cluster_hash is ignored (the workflow computes it).`,
        `Output ONLY a JSON object with a "clusters" key, nothing else.`,
      ].join("\n");

      const { text, stopReason } = await postAnthropicMessage({
        apiKey,
        model: ANTHROPIC_MODEL,
        maxTokens: ANTHROPIC_MAX_TOKENS,
        messages: [{ role: "user", content: prompt + "\n\nCorpus:\n" + JSON.stringify(corpus.entries) }],
        outputConfig: { format: { type: "json_schema", schema: CLUSTER_OUTPUT_SCHEMA } },
        // #cost-attribution (plan Phase 2, choke point #3): real per-cron spend.
        markerSource: "cron-compound-promote",
      });

      if (stopReason === "max_tokens") {
        logger.warn({ fn: "cron-compound-promote" }, "anthropic-response-truncated");
        return { clusters: [] as Cluster[], truncated: true };
      }

      if (!text) {
        reportSilentFallback(new Error("Empty Anthropic response"), {
          feature: "cron-compound-promote",
          op: "anthropic-cluster",
          message: "Anthropic returned empty content",
        });
        return { clusters: [] as Cluster[], truncated: false };
      }

      // Structured output guarantees schema-valid JSON — parse directly, no fence strip.
      let parsed: { clusters?: unknown };
      try {
        parsed = JSON.parse(text) as { clusters?: unknown };
      } catch {
        reportSilentFallback(new Error("Malformed Anthropic JSON"), {
          feature: "cron-compound-promote",
          op: "anthropic-cluster",
          message: "Anthropic response is not valid JSON",
        });
        return { clusters: [] as Cluster[], truncated: false };
      }

      if (!Array.isArray(parsed.clusters)) {
        reportSilentFallback(new Error("Anthropic response is not array"), {
          feature: "cron-compound-promote",
          op: "anthropic-cluster-shape-invalid",
          message: "Anthropic response has no clusters array",
        });
        return { clusters: [] as Cluster[], truncated: false };
      }

      return { clusters: (parsed.clusters as Cluster[]).slice(0, weekCapResult.remaining), truncated: false };
    }, MAX_RUN_DURATION_MS));

    if (clusterResult.clusters.length === 0 || clusterResult.truncated) {
      await step.run("sentry-heartbeat-ok-no-clusters", () =>
        postSentryHeartbeat({ ok: true, sentryMonitorSlug: SENTRY_MONITOR_SLUG, cronName: "cron-compound-promote", logger }),
      );
      emitOutcomeMarker(logger, { trigger, run_id: runId,
        status: clusterResult.truncated ? "anthropic-truncated" : "no-qualifying-clusters",
        corpus_count: corpus.entries.length,
        clusters_proposed: clusterResult.clusters.length,
        clusters_opened: 0,
        corpus_input_bytes: corpusInputBytes,
      });
      return { ok: true, status: clusterResult.truncated ? "anthropic-truncated" : "no-qualifying-clusters" };
    }

    // FR9-FR18: apply clusters and open PRs
    let clustersOpened = 0;
    // #8281: why a run produced nothing is the datum that was missing. One
    // entry per refusal that fired, plus a bounded per-cluster detail so a
    // cluster refused EVERY week is distinguishable from a quiet corpus.
    const refusals: string[] = [];
    const refusalDetail: { cluster_hash: string; reason: string }[] = [];

    for (const cluster of clusterResult.clusters) {
      const clusterHash = computeClusterHash(cluster.source_learnings);
      // Derived from the MEMOIZED run start, never a fresh Date — the branch
      // name embeds this suffix and the helper's replay-resume is keyed on
      // the branch, so a replay crossing UTC midnight must not re-key it.
      const dateSuffix = runStartedAt.slice(0, 10);

      const outcome: ClusterOutcome = await step.run(
        `apply-and-pr-${clusterHash.slice(0, 8)}`,
        async (): Promise<ClusterOutcome> => {
        const octokit = new Octokit({ auth: installationToken });

        if (!TARGET_ALLOW_RE.test(cluster.target_path)) {
          logger.warn({ fn: "cron-compound-promote", path: cluster.target_path }, "target-path-refused");
          reportSilentFallback(new Error("target_path not in allowlist"), {
            feature: "cron-compound-promote", op: "target-path-refused",
            extra: { path: cluster.target_path },
          });
          return { kind: "refused", reason: "target-path-refused" };
        }

        if (cluster.proposed_diff_unified.length > MAX_DIFF_BYTES) {
          logger.warn({ fn: "cron-compound-promote" }, "diff-size-exceeded");
          return { kind: "refused", reason: "diff-size-exceeded" };
        }

        // #8274: derive the affected paths from git itself. The previous
        // `+++ b/` filter was vacuous — `git apply` strips ONE leading
        // component whatever it is, so `+++ x/…` wrote files it never saw.
        const pathVerdict = await checkDiffPaths(cluster.proposed_diff_unified, repoRoot);
        if (!pathVerdict.ok) {
          const reason = `diff-${pathVerdict.reason}`;
          logger.warn(
            { fn: "cron-compound-promote", hash: clusterHash, reason, detail: pathVerdict.detail },
            "diff-path-refused",
          );
          reportSilentFallback(new Error(`diff refused: ${pathVerdict.reason}`), {
            feature: "cron-compound-promote",
            op: "diff-path-refused",
            extra: { cluster_hash: clusterHash, reason, detail: pathVerdict.detail },
          });
          return { kind: "refused", reason: reason };
        }

        if (cluster.target_path === "AGENTS.rules.md" && diffRemovesHardRule(cluster.proposed_diff_unified)) {
          logger.warn({ fn: "cron-compound-promote", hash: clusterHash }, "agents-core-hr-rule-edit-refused");
          reportSilentFallback(new Error("Cluster proposes hr- rule edit"), {
            feature: "cron-compound-promote", op: "agents-core-hr-rule-edit-refused",
            extra: { cluster_hash: clusterHash },
          });
          return { kind: "refused", reason: "agents-core-hr-rule-edit-refused" };
        }

        if (cluster.target_path.startsWith("plugins/soleur/skills/")) {
          const { data: openPRs } = await octokit.request("GET /search/issues", {
            q: `is:pr is:open repo:${REPO_OWNER}/${REPO_NAME} "plugins/soleur/skills" in:files`,
            per_page: 5,
          });
          if (openPRs.total_count > 0) {
            const firstPR = openPRs.items[0];
            const diffBody = PII_REGEX.test(cluster.proposed_diff_unified)
              ? "[diff redacted — PII pattern detected in LLM output]"
              : `\`\`\`diff\n${cluster.proposed_diff_unified}\n\`\`\``;
            await octokit.request("POST /repos/{owner}/{repo}/issues/{issue_number}/comments", {
              owner: REPO_OWNER, repo: REPO_NAME, issue_number: firstPR.number,
              body: `Compound-promote cluster \`${clusterHash}\` proposes edits to \`${cluster.target_path}\` but this PR already touches skill files. Posting diff here instead of opening a conflicting branch.\n\n${diffBody}`,
            });
            // WARN, not info: `app_container_warn_filter` keeps level >= 40,
            // so an info line never reaches Better Stack and this exit was
            // invisible -- the very blindness #8281 exists to remove.
            logger.warn({ fn: "cron-compound-promote", pr: firstPR.number }, "skill-conflict-guard-comment-posted");
            return { kind: "refused", reason: "skill-conflict-guard" };
          }
        }

        const branchName = `self-healing/auto-${clusterHash}-${dateSuffix}`;
        if (!BRANCH_SHAPE_RE.test(branchName)) {
          logger.warn({ fn: "cron-compound-promote", branch: branchName }, "branch-name-shape-failed");
          return { kind: "refused", reason: "branch-name-shape-failed" };
        }

        const applied = await applyDiffToWorkspace(cluster.proposed_diff_unified, repoRoot);
        if (!applied) {
          logger.warn({ fn: "cron-compound-promote", hash: clusterHash }, "git-apply-check-failed");
          reportSilentFallback(new Error("git apply --check failed"), {
            feature: "cron-compound-promote", op: "git-apply-check-failed",
          });
          return { kind: "refused", reason: "git-apply-check-failed" };
        }

        // Post-apply byte budget check (frontmatter-stripped basis, #6794 —
        // mirrors the commit gate exactly).
        const post = await readAlwaysLoaded(repoRoot);
        const postBytes = measureAlwaysLoadedBytes(
          post.indexText,
          post.corpusText,
        );
        if (postBytes > MAX_ALWAYS_LOADED_BYTES) {
          logger.warn({ fn: "cron-compound-promote", bytes: postBytes }, "byte-budget-overflow");
          reportSilentFallback(new Error("Post-apply byte budget exceeded"), {
            feature: "cron-compound-promote", op: "byte-budget-overflow",
            extra: { bytes: postBytes, cap: MAX_ALWAYS_LOADED_BYTES },
          });
          await spawnGit(["checkout", "--", "."], { cwd: repoRoot });
          return { kind: "refused", reason: "byte-budget-overflow" };
        }

        // Audit log row — atomic O_APPEND write instead of existsSync→read→
        // concat→writeFile, which CodeQL flags as a TOCTOU race
        // (js/file-system-race: the file can change between the existence check
        // and the rewrite, clobbering a concurrent append). promotion-log.md is
        // repo-committed so it always exists at runtime; appendFile also creates
        // it if absent, so the prior existsSync guard was redundant.
        const logPath = join(repoRoot, "knowledge-base", "project", "learnings", "promotion-log.md");
        const row = `\n| ${dateSuffix} | ${clusterHash} | ${cluster.target_path} | ${cluster.source_learnings.length} | pending | ${cluster.tier} | (PR pending) |\n`;
        await appendFile(logPath, row);

        // Persist via safeCommitAndPr (#5111) — per-cluster branch override,
        // commit trailers via commitBody, draft PR with mergeMode "none"
        // (human review required; the helper never touches merge endpoints).
        // Gains the deletion guard, dirty-index precondition, and dropped-
        // path warn. Replay caveat: a crash-replay of this step re-runs
        // applyDiffToWorkspace BEFORE the helper, so a crash AFTER commit
        // fails the re-apply `--check` and early-returns above — the
        // helper's branch-keyed replay-resume covers only crashes inside
        // its own push/PR tail. The whole cluster step is memoized, so a
        // COMPLETED cluster never re-executes.
        const titleLine = `chore(self-healing): promote cluster ${clusterHash} to ${cluster.target_path}`;
        const trailer = [
          `Bot-Author: compound-promotion-loop@${process.env.GITHUB_SHA ?? "local"}`,
          `Source-Learnings: ${cluster.source_learnings.join(",")}`,
          `Threshold-Hit: ${cluster.source_learnings.length}/5`,
          `Cluster-Hash: ${clusterHash}`,
          `Tier: ${cluster.tier}`,
        ].join("\n");
        const prBody =
          `Promoted by compound-promotion-loop. Source learnings: ${cluster.source_learnings.join(" ")}. ` +
          `Tier: ${cluster.tier}. Cluster-Hash: ${clusterHash}. ` +
          `Reviewer: verify the diff respects cq-agents-md-tier-gate and cq-agents-md-why-single-line; ` +
          `merge to apply, close to reject.\n\nhuman review required`;

        const result = await safeCommitAndPr({
          spawnCwd: repoRoot,
          installationToken,
          cronName: "cron-compound-promote",
          commitMessage: titleLine,
          commitBody: trailer,
          allowedPaths: [
            cluster.target_path,
            "knowledge-base/project/learnings/promotion-log.md",
          ],
          runStartedAt,
          scheduledIssueLabel: SENTRY_MONITOR_SLUG,
          branchName,
          prTitle: `self-healing(auto): promote cluster ${clusterHash} ${dateSuffix}`,
          prBody,
          prDraft: true,
          prLabels: ["self-healing/auto"],
          syntheticChecks: {
            names: SYNTHETIC_CHECK_NAMES,
            summary: "self-healing/auto promotion — operator review required",
          },
          mergeMode: "none",
          octokit,
          logger,
        });

        // Non-committed exits (deletion-guard, dirty-index, no-changes after
        // an allowlist drop, …) leave this cluster's applied diff and its
        // promotion-log row UNSTAGED in the worktree. The pre-#5111 throwing
        // git pipeline halted the loop here; the non-throwing helper
        // continues — so reset the worktree or cluster A's residue rides
        // into cluster B's commit (promotion-log.md is in EVERY allowlist).
        if (result.status !== "committed") {
          // reset --hard covers staged AND unstaged residue (a dirty-index
          // failure means something was staged); clean -fd removes new files
          // the diff created. The clone is ephemeral — nothing else lives here.
          await spawnGit(["reset", "--hard", "HEAD"], { cwd: repoRoot });
          await spawnGit(["clean", "-fd"], { cwd: repoRoot });
        }
        await spawnGit(["checkout", "main"], { cwd: repoRoot });
          if (result.status === "committed") {
            return { kind: "opened" };
          }
          // Previously unlogged and uncounted: a non-committed exit
          // (deletion-guard, dirty index, no changes after an allowlist drop)
          // left the run reporting zero opened and zero refusals.
          logger.warn(
            { fn: "cron-compound-promote", hash: clusterHash, status: result.status },
            "cluster-not-committed",
          );
          return { kind: "refused", reason: `not-committed-${result.status}` };
        },
      );

      // Accumulate from the MEMOIZED return value, in the handler body. This
      // is the whole point: on a replay the callback above does not re-run,
      // but `outcome` is replayed from step state, so these arrays are correct
      // on every pass rather than only on the first.
      if (outcome.kind === "opened") {
        clustersOpened++;
      } else {
        refusals.push(outcome.reason);
        refusalDetail.push({ cluster_hash: clusterHash, reason: outcome.reason });
      }
    }

    await step.run("sentry-heartbeat", () => postSentryHeartbeat({ ok: true, sentryMonitorSlug: SENTRY_MONITOR_SLUG, cronName: "cron-compound-promote", logger }));
    emitOutcomeMarker(logger, { trigger, run_id: runId,
      status: "completed",
      corpus_count: corpus.entries.length,
      clusters_proposed: clusterResult.clusters.length,
      clusters_opened: clustersOpened,
      refusals,
      refusal_detail: refusalDetail,
      corpus_input_bytes: corpusInputBytes,
    });
    return { ok: true, status: "completed", clustersOpened };
  } catch (err) {
    const e = err as Error;
    if (installationToken) {
      e.message = redactToken(e.message, installationToken);
    }
    reportSilentFallback(e, {
      feature: "cron-compound-promote",
      op: "handler-top-level",
      message: e.message,
    });
    try {
      await postSentryHeartbeat({ ok: false, sentryMonitorSlug: SENTRY_MONITOR_SLUG, cronName: "cron-compound-promote", logger });
    } catch {
      // best-effort
    }
    emitOutcomeMarker(logger, { trigger, run_id: runId, status: "error" });
    return { ok: false, status: "error" };
  } finally {
    await teardownEphemeralWorkspace(ephemeralRoot);
  }
}

// =============================================================================
// Registration
// =============================================================================

export const cronCompoundPromote = inngest.createFunction(
  {
    id: "cron-compound-promote",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "0 0 * * 0" },
    { event: "cron/compound-promote.manual-trigger" },
  ],
  cronCompoundPromoteHandler as unknown as Parameters<
    typeof inngest.createFunction
  >[2],
);
