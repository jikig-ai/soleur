// TR9 Phase-2 — Migrated from the GHA scheduled-content-vendor-drift
// workflow (deleted in the same PR per TR9 I-13 hygiene). Weekly upstream
// content drift detector. Parses schema-conforming NOTICE files under
// plugins/soleur/skills/<slug>/NOTICE (multi-bundle discovery, ADR-219),
// fetches upstream blobs, detects SHA drift. Routes security-relevant drift
// to an issue; the low-risk auto-PR route (classifier rc 13) re-vendors via
// an in-step `git merge-file --diff3` write + NOTICE pin advance, committed
// through safeCommitAndPr (#8180).
//
// ADR-033 invariants (binding all cron-*.ts files):
//   I1 — Octokit + node:fs reads called INSIDE step.run (replay memoization).
//   I2 — Operator-owned data only; never founder BYOK.
//   I3 — NOT SATISFIED in this file. There is no `Promise.race`, and
//        `MAX_RUN_DURATION_MS` is exported but never applied to anything, so
//        this function has no outer wall-clock bound; it relies on Inngest's
//        own step timeouts. This line claimed the guard was in force until
//        #7710 review measured it. Corrected rather than removed so the gap
//        is visible.
//   I4 — N/A (no claude binary; Octokit + git spawn only).
//   I5 — Deterministic step.run return shape per step (see handler).
//   I6 — Any event payload this function emits carries `actor: "platform"`.
//        (This line read "No event payloads emitted" until #7710 review. That
//        is not what I6 says: it constrains the TAG on emitted events and
//        forbids no emission. This function happens to emit none, which is a
//        fact about this function, not a rule it obeys.)
//
// PURE-TS + GIT SPAWN PATTERN — the vendor-drift detection logic is
// complex (3-way merges, NOTICE parsing, classifier routing). The GHA
// workflow relied on gh CLI + bash scripts for NOTICE parsing and drift
// classification. The Inngest port uses Octokit for GitHub API calls and
// spawns git/bash for merge operations, keeping the existing classifier
// script as the routing brain.

import { spawn } from "node:child_process";
import { existsSync, lstatSync } from "node:fs";
import { mkdtemp, readdir, readFile, rm, writeFile } from "node:fs/promises";
import { join, resolve, sep } from "node:path";
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
  postSentryHeartbeat,
  type HandlerArgs,
} from "./_cron-shared";
import {
  SYNTHETIC_CHECK_NAMES,
  safeCommitAndPr,
  type SafeCommitResult,
} from "./_cron-safe-commit";

// =============================================================================
// Constants
// =============================================================================

const SENTRY_MONITOR_SLUG = "scheduled-content-vendor-drift";

export const MAX_RUN_DURATION_MS = 15 * 60 * 1000;

/**
 * Days below which a verified-clean run skips the write entirely.
 *
 * The banner fires at STALENESS_WARN_DAYS (30), so re-attesting a field only
 * days old costs a bot PR on a compliance-critical file for no signal. At 21
 * a weekly cron writes at most once per three weeks and the observed age
 * never exceeds 21 on the healthy path, leaving 9 days of margin before the
 * banner — enough to absorb one missed run (28) but not two (35), which is
 * the intended alarm.
 */
export const WRITE_SUPPRESSION_DAYS = 21;
const TOKEN_MIN_LIFETIME_MS = 20 * 60 * 1000;

/**
 * Bundle discovery root. Every `plugins/soleur/skills/<slug>/NOTICE` whose
 * frontmatter parses AND declares non-empty `upstream` + `pinned-commit` is
 * a vendored bundle (schema-keyed enrollment, ADR-219). Prose attribution
 * NOTICEs without the schema — `incident/NOTICE` exists on the tree today —
 * match the bare glob but are skip-with-warn, never enrolled.
 */
export const SKILLS_DIR_REL = "plugins/soleur/skills";
export const NOTICE_FILENAME = "NOTICE";

// Shared scripts, not bundle constants — the parser and classifier are the
// gdpr-gate skill's, reused for every bundle via the NOTICE_FILE env override
// (ADR-095 shared-engine).
export const PARSER_REL =
  "plugins/soleur/skills/gdpr-gate/scripts/notice-frontmatter.sh";
export const CLASSIFIER_REL =
  "plugins/soleur/skills/gdpr-gate/scripts/vendor-drift-classify.sh";

/**
 * Re-vendor branch prefix. `safeCommitAndPr`'s `deriveBranchName` produces
 * `ci/<cronName minus cron->-<ts>`; the per-bundle cronName
 * `cron-content-vendor-drift-<slug>` therefore lands each bundle's re-vendor
 * PR on `ci/content-vendor-drift-<slug>-<ts>`. The dedup query keys on this
 * prefix and classifies ownership per slug — see classifyBranchOwner.
 */
export const DRIFT_BRANCH_PREFIX = "ci/content-vendor-drift";

/**
 * The bundle that owns UNSUFFIXED legacy artifacts. Pre-multi-bundle branches
 * (`ci/content-vendor-drift-<ts>`, `ci/vendor-attest-<ts>`) and issues whose
 * titles carry no `[<slug>]` token predate slugging and are all gdpr-gate's —
 * they were created when gdpr-gate was the only bundle. Classifying them as
 * gdpr-gate's keeps the dedup suppressing duplicate PRs/issues for that
 * bundle without letting them mask a sibling.
 */
export const LEGACY_BUNDLE_SLUG = "gdpr-gate";

/**
 * Branch prefix for the freshness-attestation PR.
 *
 * DELIBERATELY OUTSIDE the `ci/content-vendor-drift-` namespace that
 * `deriveBranchName(cronName, …)` would produce. The detect step dedups the
 * re-vendor route with `head:ci/content-vendor-drift-`, a guard written when
 * only that route created such branches. An attestation PR sitting on the
 * same prefix — which is the ORDINARY state, since the direct merge normally
 * falls back to armed auto-merge — would make the next run that finds genuine
 * drift return `skipped-open-pr` and open no re-vendor PR at all, while the
 * heartbeat reported healthy. Two independent reviewers converged on this
 * (#7710 review).
 */
export const ATTEST_BRANCH_PREFIX = "ci/vendor-attest";

/**
 * Cap on the lines emitted per drifted file into the classifier's stdin.
 * The corpus is a handful of small markdown rule files; the cap exists so a
 * pathological upstream cannot hand this cron an unbounded stdin, not because
 * any real file approaches it.
 */
export const MAX_DIFF_LINES_PER_FILE = 4000;

/**
 * Decode the body of a GitHub `contents` response, or null when it does not
 * carry one (a directory, a symlink, a submodule, or a file above the API's
 * inline-content ceiling). Callers must treat null as "I could not read it",
 * never as "it is empty" — an empty diff routes to the least-guarded path.
 */
export function decodeContentsBody(contents: unknown): string | null {
  const c = contents as { content?: string; encoding?: string } | null;
  if (!c || typeof c.content !== "string" || c.encoding !== "base64") {
    return null;
  }
  try {
    return Buffer.from(c.content, "base64").toString("utf8");
  } catch {
    return null;
  }
}

/** Drift labels mapped from classifier categories. */
const CATEGORY_LABELS: Record<string, string[]> = {
  security: ["vendor/pin-drift", "compliance/critical"],
  license: ["vendor/license-changed", "compliance/critical"],
  archived: ["vendor/upstream-archived", "compliance/critical"],
  renamed: ["vendor/upstream-archived", "needs-human-review"],
  rollback: ["vendor/upstream-rollback", "needs-human-review"],
  batched: ["vendor/pin-drift"],
};

/** Exit codes that route to issue (security-relevant). */
export const ISSUE_EXIT_CODES = new Set([10, 11, 12, 15, 16]);

/** Repository-level state of the upstream, observed once per run. */
export type UpstreamRepoState = "ok" | "archived" | "renamed" | "unreachable";

/**
 * One drifted lifted file, carried from detection to the re-vendor write.
 *
 * `liftedPath` is the NOTICE-relative path (`references/...`); `upstreamPath`
 * the upstream repo path; `oldSha` the NOTICE-pinned upstream blob and
 * `newSha` the blob currently at `upstreamPath` on the upstream default
 * branch. Only records the detect loop scored `drift` land here — an
 * error-record file is excluded so the write never touches unmeasured bytes.
 */
export interface DriftedFile {
  liftedPath: string;
  upstreamPath: string;
  oldSha: string;
  newSha: string;
  /** The NOTICE `local-blob-sha` for this record — carried so the rewrite
   * can bind the substitution to the record that actually drifted rather
   * than any hex value in a positionally-paired block (#8185 review). */
  oldLocalSha: string;
}

/**
 * Upstream repository metadata, captured when the detect-step probe answered.
 * Absent (null) when the probe failed — `unreachable` must never render as
 * affirmative repository facts in the issue body (#8183).
 */
export interface RepoMetaSummary {
  fullName: string;
  archived: boolean;
  defaultBranch: string;
}

/**
 * Totals produced by one comparison pass over the NOTICE registry.
 *
 * `filesExamined` counts registry lines that yielded a usable
 * `<upstream-path>:<sha>` pair. A malformed line increments `filesError`
 * WITHOUT incrementing `filesExamined`, so it fails the completeness conjunct
 * from both directions.
 */
export interface ComparisonTotals {
  registryCount: number;
  filesExamined: number;
  filesSame: number;
  filesDrifted: number;
  filesError: number;
  /**
   * Repository-level drift. `unreachable` is its own state rather than being
   * folded into `archived`: the repo-meta probe's bare catch fires on a 403
   * rate-limit or a 5xx just as it does on a genuine archive, and "I could
   * not measure" must never read as evidence of anything.
   */
  upstreamRepoState: UpstreamRepoState;
}

/**
 * The three states a single per-file comparison can land in (#7710).
 *
 * `"error"` is the state that did not exist before: a response that ARRIVED
 * but could not be parsed — a degraded 200, a body with no `sha` field — was
 * previously indistinguishable from "unchanged", so an upstream serving
 * garbage read as a clean corpus.
 *
 * Exported and pure so the distinction is provable by a test that changes the
 * INPUT, rather than by grepping the loop for a token. A grep for a counter
 * increment cannot tell which branch it came from — the loop has three of
 * them — so the guard has to sit here.
 */
export type FileComparison = "same" | "drifted" | "error";

export function classifyFileComparison(
  pinnedSha: string | undefined,
  upstreamSha: string | undefined,
): FileComparison {
  // A registry line we could not read is not a file we verified.
  if (!pinnedSha) return "error";
  // A response that did not carry a sha is NOT evidence of sameness. This is
  // the arm whose absence made an outage look like a clean bill of health.
  if (!upstreamSha) return "error";
  return upstreamSha === pinnedSha ? "same" : "drifted";
}

/**
 * Whether a run may advance NOTICE `last-verified` (#7710).
 *
 * This is the ONLY predicate permitted to gate the freshness attestation, and
 * it deliberately takes TOTALS rather than the detect step's `drift` verdict.
 * Two of that step's returns yield `drift: "none"`, and only one of them means
 * "I compared everything and it matched"; the other is reached AFTER drift was
 * detected, when the classifier declines to categorise it. A writer keyed on
 * the verdict would advance a compliance attestation over a corpus the same
 * run had just found drift in.
 *
 * Exported and pure so the property can be asserted behaviourally over every
 * exit — clean, drifted, drift-detected-but-classifier-zero, comparison
 * failed, partial — rather than grep-asserted against the handler's source.
 *
 * Every conjunct is load-bearing:
 * - `registryCount > 0` — `0 of 0` is not evidence of currency. A writer that
 *   treats an empty registry as a clean comparison is vacuous by construction.
 * - `filesExamined === registryCount` — a PARTIAL comparison is not evidence.
 *   `registryCount` is the count of records DECLARED in the NOTICE, NOT the
 *   count the parser emitted, and that distinction is the whole value of this
 *   conjunct: `_emit_files` drops a record missing its upstream SHA, so
 *   deriving the denominator from the emitted view compares the parser's
 *   output against itself — the denominator shrinks with the numerator and a
 *   partial comparison reads as complete. Measured on a 3-record fixture with
 *   one incomplete record: emitted 2, declared 3 (#7710 review).
 * - `filesDrifted === 0` — the obvious one.
 * - `filesError === 0` — a file that could not be fetched is not a file that
 *   was verified. Without this conjunct an upstream outage reads as a clean
 *   bill of health, which is the failure direction that stays invisible.
 * - `upstreamRepoState === "ok"` — REPOSITORY-level drift, which the per-file
 *   totals structurally cannot express. Every file compares SAME against an
 *   archived or renamed upstream because the blobs at the pinned SHAs still
 *   resolve; without this conjunct the run escalates a `compliance/critical`
 *   "upstream archived" issue and advances the attestation in the same pass
 *   (#7710 review, P1-A).
 */
export function mayAttestFreshness(totals: ComparisonTotals): boolean {
  return (
    totals.registryCount > 0 &&
    totals.filesExamined === totals.registryCount &&
    totals.filesDrifted === 0 &&
    totals.filesError === 0 &&
    totals.upstreamRepoState === "ok"
  );
}

/**
 * The 30-day threshold at which `gdpr-gate.sh` starts printing its staleness
 * banner. The heartbeat is keyed on the same number so the monitor and the
 * customer-visible banner cannot disagree about what "current" means.
 */
export const STALENESS_WARN_DAYS = 30;

/**
 * Whether the run failed to MEASURE, as distinct from measuring drift.
 *
 * These states have no route: they produce no issue, no PR and no artifact,
 * so without this predicate they end in a GREEN check-in with nothing behind
 * it — which is the #7710 shape exactly, re-armed one layer up. Drift is
 * different: it is routed to an issue or a re-vendor PR, so a run that found
 * drift is doing its job and reports healthy.
 */
export function couldNotMeasure(totals: ComparisonTotals): boolean {
  return (
    totals.registryCount === 0 ||
    totals.filesExamined !== totals.registryCount ||
    totals.filesError > 0 ||
    totals.upstreamRepoState === "unreachable"
  );
}

/**
 * Whether the Sentry check-in may report healthy.
 *
 * The monitor tracks the ARTIFACT — is `last-verified` inside the window the
 * gate warns at — NOT whether this particular run performed a merge.
 *
 * That distinction is the whole finding. An earlier revision keyed this on
 * `res.merged`, i.e. the direct `PUT .../merge` succeeding inside the run.
 * Measured against the sibling `mergeMode: "direct"` cron, that is the
 * UNCOMMON path: PRs #4083, #3766 and #3468 each show `autoMergeEnabledAt` at
 * created + 6s (the direct merge failed) and `mergedAt` at +54s to +69s. The
 * artifact lands reliably, just after the run has ended. Keying on the merge
 * would therefore have posted non-OK and raised a Sentry issue on essentially
 * EVERY healthy attestation — and a monitor that pages on the healthy path is
 * muted within two cycles, which is the condition that let #7710 run for 117
 * days undetected.
 *
 * Reading the age from the freshly-cloned default branch at the START of the
 * run makes the signal self-correcting without needing to observe the merge:
 * a healthy weekly cron with the 21-day write suppression sees ages of 7, 14,
 * 21 (writes, resets to 0), so it never approaches 30. If a write fails to
 * land, the next run sees the age keep climbing, and at 30 the monitor pages —
 * one cadence after the banner would have fired for a human anyway.
 *
 * @param observedAgeDays age of `last-verified` on the default branch as read
 *   BEFORE this run's write, or `null` when it could not be read at all.
 */
export function heartbeatOk(
  measurementFailed: boolean,
  attestationEligible: boolean,
  observedAgeDays: number | null,
  route: "pr" | "issue" | "none",
): boolean {
  // "I could not measure" is never healthy — it has no other route.
  if (measurementFailed) return false;

  // THE AGE GATE IS UNCONDITIONAL, AND THAT ORDERING IS THE FIX.
  //
  // Two revisions of this function short-circuited `return true` on the
  // ineligible (drift-found) arm BEFORE reaching the age, on the reasoning
  // that drift is "routed to an issue — working as intended". Both were
  // wrong, and wrong in #7710's own shape:
  //
  //   Week 1: one file drifts, an issue is opened, `last-verified` freezes.
  //   Weeks 2..N: the issue-open step dedups on an open issue with the same
  //   title, so nothing new is filed and the totals are identical every run.
  //   The field ages past 30 (customer banner) and then past 90
  //   (`POSTURE_FAIL`) while this monitor reports OK every single week.
  //
  // A corpus stale for 90 days because its drift is unresolved is not a
  // healthy control, whatever the run did. The artifact is the subject, so
  // the artifact's age binds on every path — the caller now reads it
  // unconditionally rather than only when it is about to refresh it.
  if (observedAgeDays === null) return false;
  if (observedAgeDays >= STALENESS_WARN_DAYS) return false;

  // Age is fine. On the drift arm, additionally require that the run actually
  // produced an artifact. `route`, not `attestationEligible`: on the
  // `classifyRc === 0` path — drift detected, classifier declines to
  // categorise — this handler returns `route: "none"`, so there is real
  // drift, no issue, no PR, and a measurement that SUCCEEDED. Keyed on
  // eligibility alone that run reads healthy.
  return attestationEligible || route !== "none";
}

// =============================================================================
// Types
// =============================================================================

/**
 * One enrolled vendored bundle. Discovered from `plugins/soleur/skills/<slug>/NOTICE`
 * inside a step.run against the clone (ADR-033 I1 — never module-level).
 *
 * `upstream` is the NOTICE's raw `upstream:` field (e.g.
 * `github.com/General-Legal/legal-templates`); `upstreamName` is the
 * `owner/repo` form used in commit/PR text.
 */
export interface BundleDescriptor {
  slug: string;
  noticeFileRel: string;
  skillPrefix: string;
  upstream: string;
  upstreamName: string;
  pinnedCommit: string;
}

/** The detect step's per-bundle result: verdict, route, and the totals the
 * attestation predicate reads. Every return site spreads `ComparisonTotals`
 * so no exit can silently omit a conjunct (#7710 review). */
interface DetectResult extends ComparisonTotals {
  drift: "none" | "detected" | "skipped-open-pr";
  route: "pr" | "issue" | "none";
  labels: string[];
  classifyRc: number;
  /** The upstream default branch the comparison fetched against
   * (`repoMeta.default_branch`, "main" when the probe could not answer). */
  upstreamRef: string;
  /** The upstream head commit at detect time — the pin the re-vendor write
   * advances `pinned-commit` to (#8180). Null when it could not be fetched. */
  newPinnedCommit: string | null;
  /** Per-file (liftedPath, upstreamPath, oldSha, newSha) pairs for the
   * re-vendor write (#8180). Empty on non-drift exits. */
  driftedFiles: DriftedFile[];
  /** Upstream repo metadata for the issue body (#8183). Null on a failed
   * probe — unreachable renders `?`, never affirmative facts. */
  repoMetaSummary: RepoMetaSummary | null;
  /** The resolved upstream head sits behind/diverged from the pinned
   * commit — a rollback or rewritten history. Forces the issue route
   * regardless of the content classification (#8185 review). */
  rollbackSuspected: boolean;
  /** Open drift-PR head refs that suppressed this run (populated only on
   * the skipped-open-pr arm) — carried so the health message can name the
   * suppressing PR instead of `pr=none` (#8185 review). */
  openPrRefs: string[];
}

/**
 * Per-bundle arm outcome. `healthy` is this bundle's own heartbeatOk verdict
 * (or false when the arm failed before totals existed); the run-level
 * heartbeat is the AND over all bundles — a red bundle is never masked by a
 * green sibling.
 */
interface BundleOutcome {
  slug: string;
  status: "failed" | "no-drift" | "detected" | "skipped-open-pr";
  route: "pr" | "issue" | "none" | null;
  healthy: boolean;
  attestationOutcome: string;
  attestationPrNumber: string | null;
  observedAgeDays: number | null;
  error?: string;
}

interface HandlerResult {
  ok: boolean;
  status: string;
  bundles?: BundleOutcome[];
}

// =============================================================================
// Helpers
// =============================================================================

/** Host git-config isolation, matching runGit's scrub in
 * `_cron-safe-commit.ts` — merge-file/hash-object are effectively
 * config-insensitive, but the two spawners must not disagree inside one
 * pipeline (#8185 review). */
const GIT_ISOLATED_ENV: NodeJS.ProcessEnv = {
  ...process.env,
  GIT_CONFIG_GLOBAL: "/dev/null",
  GIT_CONFIG_SYSTEM: "/dev/null",
  GIT_CONFIG_NOSYSTEM: "1",
};

function spawnGit(
  args: string[],
  opts?: { cwd?: string; env?: NodeJS.ProcessEnv },
): Promise<{
  exitCode: number | null;
  signal: NodeJS.Signals | null;
  stderr: string;
}> {
  return new Promise((resolve) => {
    const child = spawn("git", args, {
      ...opts,
      env: { ...GIT_ISOLATED_ENV, ...opts?.env },
      stdio: ["ignore", "ignore", "pipe"],
    });
    let stderr = "";
    child.stderr?.on("data", (d: Buffer) => {
      stderr += d.toString();
    });
    child.on("exit", (exitCode, signal) =>
      resolve({ exitCode, signal, stderr }),
    );
    child.on("error", (err) =>
      resolve({ exitCode: -1, signal: null, stderr: err.message }),
    );
  });
}

/** Spawn git and capture stdout (rejects on non-zero exit or spawn error). */
async function spawnGitStdout(
  args: string[],
  opts?: { cwd?: string; env?: NodeJS.ProcessEnv },
): Promise<string> {
  return new Promise((resolve, reject) => {
    const child = spawn("git", args, {
      stdio: ["ignore", "pipe", "pipe"],
      ...opts,
      env: { ...GIT_ISOLATED_ENV, ...opts?.env },
    });
    let stdout = "";
    let stderr = "";
    child.stdout?.on("data", (d: Buffer) => {
      stdout += d.toString();
    });
    child.stderr?.on("data", (d: Buffer) => {
      stderr += d.toString();
    });
    child.on("exit", (exitCode) => {
      if (exitCode === 0) {
        resolve(stdout.trim());
      } else {
        reject(
          new Error(
            `git ${args.join(" ")} exited ${exitCode}: ${stderr.slice(0, 500)}`,
          ),
        );
      }
    });
    child.on("error", (err) => reject(err));
  });
}

/**
 * Walk all pages of a paginated octokit list call (`per_page: 100`) up to a
 * defensive cap of 20 pages — the `fetchAllPages` pattern established in
 * `get-workstream-issue-options.ts` (the octokit client here is bare
 * `@octokit/core`; no `paginate` plugin is installed).
 *
 * Any dedup path that ENUMERATES items to decide "does a matching open item
 * exist" must page to completion: a bounded first page makes an existing open
 * item beyond it invisible and the cron files a duplicate — a failure that
 * grows exactly when the repo is busiest (#8182). The enumeration call sites
 * are `listOpenPrHeads` (open-PR dedup for both the drift and attestation
 * arms) and the per-bundle issue scan in `open-drift-issue-<slug>`.
 */
export async function fetchAllPages<T>(
  fetchPage: (page: number) => Promise<{ data: T[] }>,
  opts?: { perPage?: number; maxPages?: number },
): Promise<T[]> {
  const perPage = opts?.perPage ?? 100;
  const maxPages = opts?.maxPages ?? 20;
  const out: T[] = [];
  let lastSize = 0;
  for (let page = 1; page <= maxPages; page++) {
    const { data } = await fetchPage(page);
    out.push(...data);
    lastSize = data.length;
    if (data.length < perPage) break;
  }
  // The cap is a bound on runaway walks, not a silent truncation point: a
  // full final page means the enumeration is INCOMPLETE and a dedup decided
  // on it can miss an existing open item — the exact defect #8182 exists to
  // close. Fail loud rather than dedup on a partial view.
  if (lastSize === perPage) {
    throw new Error(
      `fetchAllPages hit the ${maxPages}-page cap with a full final page — enumeration is incomplete; dedup must not decide on a partial view`,
    );
  }
  return out;
}

/**
 * Rewrite ONE lifted-files record in a NOTICE frontmatter body, porting the
 * deleted workflow's Python heredoc verbatim in spirit
 * (`git show 804114883:.github/workflows/scheduled-content-vendor-drift.yml`).
 *
 * The block anchor is `- path: <rel>` followed by its 4-space-indented
 * sub-keys; the greedy `(?:    [^\n]+\n)+` span is load-bearing — a
 * non-greedy span would capture only the first sub-key line and the sha
 * substitutions below would silently no-op on a block lacking their targets.
 * FAILS CLOSED: anything but exactly 1 block match, 1 local-blob-sha
 * substitution and 1 upstream-blob-sha substitution throws — a NOTICE that
 * cannot be rewritten atomically must not be written at all.
 */
export function rewriteNoticeRecord(
  src: string,
  relPath: string,
  newLocalSha: string,
  newUpstreamSha: string,
  expected: { upstreamPath: string; oldUpstreamSha: string; oldLocalSha: string },
): string {
  const esc = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const escaped = esc(relPath);
  const blockRe = new RegExp(`- path: ${escaped}\\n(?:    [^\\n]+\\n)+`, "g");
  const nBlocks = (src.match(blockRe) ?? []).length;
  if (nBlocks !== 1) {
    throw new Error(
      `NOTICE rewrite failed for ${relPath}: ${nBlocks} matching record blocks (expected exactly 1)`,
    );
  }
  let nLocal = 0;
  let nUpstream = 0;
  const next = src.replace(new RegExp(blockRe.source, "m"), (block) => {
    // Bind the substitution to the RECORD that drifted, not to position:
    // `lifted-files`/`upstream-files` are filtered over different key pairs,
    // so equal-length views can still pair record i's local path with
    // record j's upstream sha (#8185 review — positional zip is only a
    // cardinality check). Requiring the block to name the expected
    // upstream-path and carry the expected OLD shas turns a crossed pair
    // into a loud throw instead of a wrong-file merge.
    const pathRe = new RegExp(
      `^    upstream-path:[ \\t]*${esc(expected.upstreamPath)}[ \\t]*$`,
      "m",
    );
    if (!pathRe.test(block)) {
      throw new Error(
        `NOTICE rewrite failed for ${relPath}: record block does not name upstream-path ${expected.upstreamPath} — registry views misaligned`,
      );
    }
    const withLocal = block.replace(
      new RegExp(`(local-blob-sha:[ \\t]*)${esc(expected.oldLocalSha)}`, "g"),
      (_m, prefix: string) => {
        nLocal += 1;
        return prefix + newLocalSha;
      },
    );
    return withLocal.replace(
      new RegExp(
        `(upstream-blob-sha:[ \\t]*)${esc(expected.oldUpstreamSha)}`,
        "g",
      ),
      (_m, prefix: string) => {
        nUpstream += 1;
        return prefix + newUpstreamSha;
      },
    );
  });
  if (nLocal !== 1 || nUpstream !== 1) {
    throw new Error(
      `NOTICE rewrite failed for ${relPath}: local-subs=${nLocal} upstream-subs=${nUpstream} (expected exactly 1 each)`,
    );
  }
  return next;
}

/**
 * Advance ONE top-level NOTICE scalar field, line-anchored. Exactly one
 * replacement or throw — the same fail-closed contract as the record rewrite
 * above: a NOTICE whose `pinned-commit`/`last-verified` cannot be advanced
 * unambiguously must abort the write rather than attest a value it did not
 * set.
 */
export function bumpNoticeField(
  src: string,
  field: "pinned-commit" | "last-verified",
  value: string,
): string {
  const all = new RegExp(`^${field}:[ \\t]*\\S+[ \\t]*$`, "gm");
  const n = (src.match(all) ?? []).length;
  if (n !== 1) {
    throw new Error(
      `NOTICE ${field} bump failed: ${n} matching lines (expected exactly 1)`,
    );
  }
  return src.replace(
    new RegExp(`^${field}:[ \\t]*\\S+[ \\t]*$`, "m"),
    `${field}: ${value}`,
  );
}

/**
 * Fetch one upstream blob by its immutable SHA. A 404 or an undecodable body
 * here is a genuine anomaly — the SHA came from the contents endpoint minutes
 * ago — so this THROWS rather than skipping (the deleted workflow's
 * `base64 -d` had the same hard-fail shape).
 */
async function fetchUpstreamBlob(
  octokit: Octokit,
  ownerRepo: string,
  sha: string,
): Promise<Buffer> {
  const { data } = await octokit.request(
    "GET /repos/{owner}/{repo}/git/blobs/{file_sha}",
    {
      owner: ownerRepo.split("/")[0],
      repo: ownerRepo.split("/")[1],
      file_sha: sha,
    },
  );
  const d = data as { content?: string; encoding?: string };
  if (typeof d.content !== "string" || d.encoding !== "base64") {
    throw new Error(
      `Upstream blob ${sha} returned no decodable base64 content`,
    );
  }
  return Buffer.from(d.content, "base64");
}

/** Spawn a bash script and capture stdout + stderr + exit code. */
async function spawnScriptCapture(
  script: string,
  args: string[],
  opts: { cwd: string; env: NodeJS.ProcessEnv; stdin?: string },
): Promise<{ exitCode: number | null; stdout: string; stderr: string }> {
  return new Promise((resolve) => {
    const child = spawn("bash", [script, ...args], {
      stdio: [opts.stdin !== undefined ? "pipe" : "ignore", "pipe", "pipe"],
      cwd: opts.cwd,
      env: opts.env,
    });
    let stdout = "";
    let stderr = "";
    child.stdout?.on("data", (d: Buffer) => {
      stdout += d.toString();
    });
    child.stderr?.on("data", (d: Buffer) => {
      stderr += d.toString();
    });
    if (opts.stdin !== undefined && child.stdin) {
      child.stdin.write(opts.stdin);
      child.stdin.end();
    }
    child.on("exit", (exitCode) => resolve({ exitCode, stdout, stderr }));
    child.on("error", () => resolve({ exitCode: -1, stdout, stderr }));
  });
}

async function setupEphemeralWorkspace(
  token: string,
): Promise<{ ephemeralRoot: string; repoRoot: string }> {
  const ephemeralRoot = await mkdtemp(
    join(resolveCronWorkspaceRoot(), "soleur-cron-content-vendor-drift-"),
  );
  const repoRoot = join(ephemeralRoot, "repo");
  await warnIfCronWorkspaceLowOnDisk(ephemeralRoot, "cron-content-vendor-drift");
  const cloneUrl = buildAuthenticatedCloneUrl(token);
  const result = await spawnGit([
    "clone",
    "--depth=1",
    cloneUrl,
    repoRoot,
  ]);
  if (result.exitCode !== 0) {
    throw new Error(
      `git clone failed (exit ${result.exitCode}, signal ${result.signal}) for ${REPO_OWNER}/${REPO_NAME}`,
    );
  }
  if (!existsSync(join(repoRoot, SKILLS_DIR_REL))) {
    throw new Error(`Sentinel: ${SKILLS_DIR_REL} absent after clone`);
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
      feature: "cron-content-vendor-drift",
      op: "teardown-ephemeral-workspace",
      message: "Failed to remove ephemeral workspace",
      extra: { fn: "cron-content-vendor-drift", ephemeralRoot },
    });
  }
}

/** Ensure labels exist (idempotent — 422 on existing is swallowed). */
async function ensureLabels(octokit: Octokit): Promise<void> {
  const labels = [
    {
      name: "compliance/critical",
      description:
        "Compliance Critical (Art. 9, missing lawful basis, etc.)",
      color: "B60205",
    },
    {
      name: "vendor/pin-drift",
      description: "Upstream content drift detected on pinned bundle",
      color: "FBCA04",
    },
    {
      name: "vendor/license-changed",
      description: "Upstream license file modified — escalate",
      color: "B60205",
    },
    {
      name: "vendor/upstream-archived",
      description:
        "Upstream repo archived — fork-or-drop ADR required",
      color: "B60205",
    },
    {
      name: "vendor/upstream-rollback",
      description:
        "Upstream HEAD is an ancestor of pinned SHA — needs human review",
      color: "FBCA04",
    },
    {
      name: "vendor/cron-failure",
      description:
        "Vendor-drift workflow failed (gh api 5xx, rate-limit, etc.)",
      color: "B60205",
    },
    {
      // Advisory label the conflicted re-vendor arm applies (#8180): a PR
      // carrying --diff3 markers is create-only and waits on a human.
      name: "needs-human-review",
      description:
        "Automated change needs human review before merge",
      color: "D93F0B",
    },
  ];
  for (const label of labels) {
    try {
      await octokit.request("POST /repos/{owner}/{repo}/labels", {
        owner: REPO_OWNER,
        repo: REPO_NAME,
        ...label,
      });
    } catch (err) {
      const status = (err as { status?: number }).status;
      if (status !== 422) {
        reportSilentFallback(err, {
          feature: "cron-content-vendor-drift",
          op: "ensure-label",
          message: `Failed to create label ${label.name}`,
          extra: { fn: "cron-content-vendor-drift", status },
        });
      }
    }
  }
}

/** Parse classifier stdout into a set of labels. */
function parseClassifierLabels(
  stdout: string,
  classifyRc: number,
): string[] {
  const labelSet = new Set<string>();
  for (const line of stdout.split("\n")) {
    const catMatch = line.match(/^category=(.+)$/);
    if (!catMatch) continue;
    const cat = catMatch[1].trim();
    const mapped = CATEGORY_LABELS[cat];
    if (mapped) {
      for (const label of mapped) labelSet.add(label);
    }
  }
  // Fallback for unknown exit codes when classifier emits nothing.
  if (labelSet.size === 0 && classifyRc !== 0) {
    labelSet.add("vendor/pin-drift");
  }
  return [...labelSet];
}

// =============================================================================
// Bundle discovery + per-bundle identity
// =============================================================================

/**
 * The schema predicate shared by cron discovery, Guard 2, and the
 * vendor-pin-verify workflow: a NOTICE enrolls its skill as a vendored bundle
 * iff it declares non-empty `upstream` AND `pinned-commit` through the parser.
 * `incident/NOTICE` — prose attribution, no schema — must NOT enroll.
 *
 * Exported and pure so the predicate is assertable without a filesystem
 * (#7710-class guard: enrollment is a schema property, not a glob property).
 */
export function isSchemaConformingNotice(
  upstream: string,
  pinnedCommit: string,
): boolean {
  return upstream.trim() !== "" && pinnedCommit.trim() !== "";
}

/**
 * Which bundle owns an open `ci/` branch. Slugged refs
 * (`<prefix>-<slug>-<ts>`) belong to that slug; refs with no slug segment are
 * LEGACY_BUNDLE_SLUG's (pre-multi-bundle artifacts — see its docblock).
 * Returns null for refs outside the prefix entirely.
 *
 * Exported and pure because the masking property — "an open bundle-A PR must
 * not suppress a bundle-B dedup" — is assertable only over ref strings, not
 * by grepping the query.
 */
export function classifyBranchOwner(
  ref: string,
  prefix: string,
  slugs: readonly string[],
): string | null {
  if (!ref.startsWith(`${prefix}-`)) return null;
  const rest = ref.slice(prefix.length + 1);
  // Longest-match-first: when one slug is a hyphenated prefix of another
  // (`legal` vs `legal-generate`), iterating the sorted slug list would hand
  // `ci/content-vendor-drift-legal-generate-<ts>` to `legal` — suppressing the
  // longer slug's dedup and misattributing its artifacts.
  for (const slug of [...slugs].sort((a, b) => b.length - a.length)) {
    if (rest.startsWith(`${slug}-`)) return slug;
  }
  return LEGACY_BUNDLE_SLUG;
}

/**
 * Which bundle owns an open drift issue. New titles carry `[<slug>]`
 * (`[vendor-drift][<slug>] security-relevant drift …`); titles with no slug
 * token are LEGACY_BUNDLE_SLUG's.
 */
export function classifyIssueOwner(
  title: string,
  slugs: readonly string[],
): string {
  for (const slug of slugs) {
    if (title.includes(`[${slug}]`)) return slug;
  }
  return LEGACY_BUNDLE_SLUG;
}

/**
 * Enumerate `plugins/soleur/skills/<slug>/NOTICE` in the clone and keep the
 * schema-conforming ones. Called INSIDE a step.run — filesystem work is
 * Inngest-memoized (ADR-033 I1) and a module-level glob would freeze the
 * bundle set at import time.
 */
async function discoverBundles(
  repoRoot: string,
  env: NodeJS.ProcessEnv,
  logger: HandlerArgs["logger"],
): Promise<BundleDescriptor[]> {
  const parserPath = join(repoRoot, PARSER_REL);
  if (!existsSync(parserPath)) {
    throw new Error(`Parser script not found: ${PARSER_REL}`);
  }
  const skillsDir = join(repoRoot, SKILLS_DIR_REL);
  const entries = await readdir(skillsDir, { withFileTypes: true });
  const bundles: BundleDescriptor[] = [];
  for (const entry of [...entries].sort((a, b) => a.name.localeCompare(b.name))) {
    if (!entry.isDirectory()) continue;
    const noticeFileRel = `${SKILLS_DIR_REL}/${entry.name}/${NOTICE_FILENAME}`;
    const noticeAbs = join(repoRoot, noticeFileRel);
    if (!existsSync(noticeAbs)) continue;

    const bundleEnv: NodeJS.ProcessEnv = { ...env, NOTICE_FILE: noticeAbs };
    const upstream = (
      await spawnScriptCapture(parserPath, ["field", "upstream"], {
        cwd: repoRoot,
        env: bundleEnv,
      })
    ).stdout.trim();
    const pinnedCommit = (
      await spawnScriptCapture(parserPath, ["field", "pinned-commit"], {
        cwd: repoRoot,
        env: bundleEnv,
      })
    ).stdout.trim();

    if (!isSchemaConformingNotice(upstream, pinnedCommit)) {
      // Skip-with-warn, not enroll-and-fail: a prose NOTICE (incident/NOTICE
      // is on the tree today) is attribution, not a vendoring registry, and
      // treating it as one would red the cron on every run.
      logger.warn(
        { fn: "cron-content-vendor-drift", noticeFileRel },
        "NOTICE lacks vendoring schema (upstream/pinned-commit) — skipped",
      );
      continue;
    }

    bundles.push({
      slug: entry.name,
      noticeFileRel,
      skillPrefix: `${SKILLS_DIR_REL}/${entry.name}`,
      upstream,
      upstreamName: upstream.replace(/^github\.com\//, ""),
      pinnedCommit,
    });
  }
  return bundles;
}

/** Open PR head refs — ALL pages of the `pulls` list, classified per-slug
 * by classifyBranchOwner. The search API's `head:` filter cannot express
 * "prefix X but not slug Y", so ownership is resolved client-side — which
 * makes this an ENUMERATION dedup: it must page to completion via
 * fetchAllPages, or a matching open PR beyond page 1 is invisible and the
 * run files a duplicate (#8182). */
async function listOpenPrHeads(octokit: Octokit): Promise<string[]> {
  const prs = await fetchAllPages((page) =>
    octokit.request("GET /repos/{owner}/{repo}/pulls", {
      owner: REPO_OWNER,
      repo: REPO_NAME,
      state: "open",
      per_page: 100,
      page,
    }),
  );
  // Same-repo heads only: a FORK PR's branch can carry any name, so an
  // external actor could open `ci/content-vendor-drift-<slug>-x` from a fork
  // and suppress this bundle's re-vendor PRs indefinitely (#8185 review).
  return prs
    .filter(
      (pr) => pr.head.repo?.full_name === `${REPO_OWNER}/${REPO_NAME}`,
    )
    .map((pr) => pr.head.ref);
}

// =============================================================================
// Handler
// =============================================================================

export async function cronContentVendorDriftHandler({
  step,
  logger,
}: HandlerArgs): Promise<HandlerResult> {
  let ephemeralRoot: string | null = null;
  let installationToken = "";

  try {
    // Memoized run-start timestamp — safeCommitAndPr derives the ci/ branch
    // name and pins commit dates from it (replay-stable, #5111).
    const runStartedAt = await step.run(
      "run-started-at",
      async () => new Date().toISOString(),
    );

    installationToken = await step.run(
      "mint-installation-token",
      async () =>
        mintInstallationToken({
          tokenMinLifetimeMs: TOKEN_MIN_LIFETIME_MS,
        }),
    );

    const workspace = await step.run("setup-workspace", async () => {
      const ws = await setupEphemeralWorkspace(installationToken);
      ephemeralRoot = ws.ephemeralRoot;
      return {
        ephemeralRoot: ws.ephemeralRoot,
        repoRoot: ws.repoRoot,
      };
    });

    const repoRoot = workspace.repoRoot;
    ephemeralRoot = workspace.ephemeralRoot;

    const octokit = new Octokit({ auth: installationToken });
    await step.run("ensure-labels", async () => {
      await ensureLabels(octokit);
    });

    // Bundle discovery runs INSIDE a step against the clone (ADR-033 I1):
    // the enrolled set is whatever `plugins/soleur/skills/*/NOTICE` says at
    // run time, never a module-level constant.
    const bundles = await step.run("discover-bundles", async () => {
      const env: NodeJS.ProcessEnv = {
        PATH: process.env.PATH,
        NODE_ENV: process.env.NODE_ENV,
        HOME: process.env.HOME,
        GH_TOKEN: installationToken,
      };
      return discoverBundles(repoRoot, env, logger);
    });
    const slugs = bundles.map((b) => b.slug);

    // An empty registry is not a clean registry. Zero conforming NOTICEs is
    // a measurement failure — the glob shrank, the parser broke, or the clone
    // is wrong — and must never post a green heartbeat.
    if (bundles.length === 0) {
      reportSilentFallback(
        new Error("No schema-conforming vendored bundles discovered"),
        {
          feature: "cron-content-vendor-drift",
          op: "discovery-empty",
          message: `${SKILLS_DIR_REL}/*/NOTICE matched no bundle with upstream + pinned-commit`,
        },
      );
      await step.run("sentry-heartbeat", () =>
        postSentryHeartbeat({
          ok: false,
          sentryMonitorSlug: SENTRY_MONITOR_SLUG,
          cronName: "cron-content-vendor-drift",
          logger,
        }),
      );
      return { ok: false, status: "no-bundles", bundles: [] };
    }

    // Per-bundle arms run SEQUENTIALLY in a stable order (discovery sorts by
    // slug). A throwing arm is a typed per-bundle failure — caught here so a
    // sibling still runs — never an abort that leaves the sibling unmeasured.
    const outcomes: BundleOutcome[] = [];
    for (const bundle of bundles) {
      try {
        outcomes.push(
          await runBundleArm({
            step,
            logger,
            bundle,
            slugs,
            octokit,
            repoRoot,
            installationToken,
            runStartedAt,
          }),
        );
      } catch (armErr) {
        const e = armErr as Error;
        if (installationToken) {
          e.message = redactToken(e.message, installationToken);
        }
        reportSilentFallback(e, {
          feature: "cron-content-vendor-drift",
          op: "bundle-arm",
          message: `bundle=${bundle.slug} ${e.message}`,
          extra: { fn: "cron-content-vendor-drift", bundle: bundle.slug },
        });
        outcomes.push({
          slug: bundle.slug,
          status: "failed",
          route: null,
          healthy: false,
          attestationOutcome: "arm-threw",
          attestationPrNumber: null,
          observedAgeDays: null,
          error: e.message,
        });
      }
    }

    // The run-level heartbeat is the AND over bundles. A red bundle is never
    // masked by a green sibling; the per-bundle breakdown travels in the
    // result so the accountability record names the failing bundle.
    const isHealthy = outcomes.every((o) => o.healthy);

    await step.run("sentry-heartbeat", () =>
      postSentryHeartbeat({
        ok: isHealthy,
        sentryMonitorSlug: SENTRY_MONITOR_SLUG,
        cronName: "cron-content-vendor-drift",
        logger,
      }),
    );

    return {
      ok: isHealthy,
      status: outcomes.every((o) => o.status === "no-drift")
        ? "no-drift"
        : "drift-or-failure",
      bundles: outcomes,
    };
  } catch (err) {
    const e = err as Error;
    if (installationToken) {
      e.message = redactToken(e.message, installationToken);
    }
    reportSilentFallback(e, {
      feature: "cron-content-vendor-drift",
      op: "handler-top-level",
      message: e.message,
    });
    // The attestation summary is the ADR-203 accountability record, and the
    // step that emits it is never reached on a throw — so without this the
    // runs with NO record are exactly the runs that failed. Emitted outside a
    // step deliberately: the handler is already unwinding.
    logger.warn(
      {
        fn: "cron-content-vendor-drift",
        op: "attestation-summary",
        attestationOutcome: "handler-threw",
        isHealthy: false,
      },
      "Vendor-drift attestation summary (run aborted before the summary step)",
    );
    try {
      await postSentryHeartbeat({
        ok: false,
        sentryMonitorSlug: SENTRY_MONITOR_SLUG,
        cronName: "cron-content-vendor-drift",
        logger,
      });
    } catch {
      // best-effort
    }
    return { ok: false, status: "error" };
  } finally {
    await teardownEphemeralWorkspace(ephemeralRoot);
  }
}

// =============================================================================
// Per-bundle arm
// =============================================================================

/**
 * One bundle's full pass: worktree reset → detect → route (PR/issue) → age
 * read → attestation → summary. Every step.run ID carries the slug because
 * Inngest memoizes BY STEP ID — an unsuffixed ID would replay bundle A's
 * memoized result for bundle B.
 *
 * The arm is sequential within itself but isolated across bundles: a throw
 * anywhere here is caught by the caller as THIS bundle's typed failure and
 * does not abort siblings.
 */
async function runBundleArm(deps: {
  step: HandlerArgs["step"];
  logger: HandlerArgs["logger"];
  bundle: BundleDescriptor;
  slugs: readonly string[];
  octokit: Octokit;
  repoRoot: string;
  installationToken: string;
  runStartedAt: string;
}): Promise<BundleOutcome> {
  const {
    step,
    logger,
    bundle,
    slugs,
    octokit,
    repoRoot,
    installationToken,
    runStartedAt,
  } = deps;
  // Per-bundle cronName feeds safeCommitAndPr's deriveBranchName, landing
  // this bundle's re-vendor PRs on `ci/content-vendor-drift-<slug>-<ts>` —
  // the namespace the dedup classifier reads.
  const cronName = `cron-content-vendor-drift-${bundle.slug}`;
  const noticeAbs = join(repoRoot, bundle.noticeFileRel);

  // Per-arm worktree reset to origin/main. safeCommitAndPr's `checkout -B`
  // branches from HEAD (_cron-safe-commit.ts:622), so without this bundle B's
  // attestation PR could carry bundle A's unmerged re-vendor commit.
  await step.run(`reset-worktree-${bundle.slug}`, async () => {
    const reset = await spawnGit(
      ["checkout", "-f", "-B", "main", "origin/main"],
      { cwd: repoRoot },
    );
    if (reset.exitCode !== 0) {
      throw new Error(
        `worktree reset to origin/main failed (exit ${reset.exitCode}) for ${bundle.slug}`,
      );
    }
    return { reset: true };
  });

  // Detect drift by parsing NOTICE and fetching upstream blobs.
  // NOTICE_FILE is the per-bundle ABSOLUTE path — without it the shared
  // parser falls back to gdpr-gate's NOTICE and bundle B attests onto
  // bundle A's registry.
  // Typed so every return site is compile-checked against DetectResult —
  // the interface was previously inferred-only dead surface (#8185 review).
  const detectResult: DetectResult = await step.run(
    `detect-drift-${bundle.slug}`,
    async () => {
    const parserPath = join(repoRoot, PARSER_REL);
    const classifierPath = join(repoRoot, CLASSIFIER_REL);

    if (!existsSync(parserPath)) {
      throw new Error(`Parser script not found: ${PARSER_REL}`);
    }
    if (!existsSync(classifierPath)) {
      throw new Error(`Classifier script not found: ${CLASSIFIER_REL}`);
    }

    const env: NodeJS.ProcessEnv = {
      PATH: process.env.PATH,
      NODE_ENV: process.env.NODE_ENV,
      HOME: process.env.HOME,
      GH_TOKEN: installationToken,
      NOTICE_FILE: noticeAbs,
    };

    const upstream = bundle.upstream;
    const pinnedSha = bundle.pinnedCommit;
    const ownerRepo = bundle.upstreamName;
    logger.info(
      {
        fn: "cron-content-vendor-drift",
        bundle: bundle.slug,
        upstream,
        pinnedSha,
      },
      "Parsed NOTICE",
    );

    // Probe upstream repo for archived/renamed status.
    //
    // `driftFlags` drives the CLASSIFIER (its vocabulary is that script's
    // contract and is left untouched); `upstreamRepoState` is the same
    // observation in a form the attestation predicate can read. They are
    // deliberately separate: the catch reports `--archived` to the
    // classifier because that is the conservative ROUTING, but "I could not
    // reach the repo" is not evidence the repo IS archived, and the
    // attestation must distinguish them (#7710 review, P1-A).
    let driftFlags = "";
    let upstreamRepoState: UpstreamRepoState = "ok";
    // Captured for the issue-body enrichment (#8183) and the pin advance
    // (#8180). `repoMetaSummary` stays null when the probe throws —
    // `unreachable` must never render as affirmative repository facts.
    let repoMetaSummary: RepoMetaSummary | null = null;
    // The upstream default branch, derived from the repo probe rather than
    // assumed — a bundle whose upstream renamed `main` must not fetch a
    // stale or nonexistent ref and read the failure as drift.
    let upstreamRef = "main";
    try {
      const { data: repoMeta } = await octokit.request(
        "GET /repos/{owner}/{repo}",
        {
          owner: ownerRepo.split("/")[0],
          repo: ownerRepo.split("/")[1],
        },
      );
      repoMetaSummary = {
        // A degraded 200 can carry no full_name — fall back to the
        // NOTICE-declared owner/repo rather than rendering `undefined`
        // inside a code span in the issue body.
        fullName:
          typeof repoMeta.full_name === "string" && repoMeta.full_name
            ? repoMeta.full_name
            : ownerRepo,
        archived: repoMeta.archived === true,
        defaultBranch: repoMeta.default_branch || "main",
      };
      upstreamRef = repoMetaSummary.defaultBranch;
      if (repoMeta.archived) {
        driftFlags = "--archived";
        upstreamRepoState = "archived";
      } else if (
        repoMeta.full_name &&
        repoMeta.full_name !== ownerRepo
      ) {
        driftFlags = "--renamed";
        upstreamRepoState = "renamed";
      }
    } catch {
      driftFlags = "--archived";
      upstreamRepoState = "unreachable";
      repoMetaSummary = null;
    }

    // The commit the new pin will name on the re-vendor arm (#8180).
    // Detection, this pin, and the blobs merged all describe the same
    // upstream head (`upstreamRef`). A failed fetch leaves null rather than
    // degrading the probe's repo-level verdict — the write step throws on
    // a missing pin, so the failure is loud, not silently absent.
    let newPinnedCommit: string | null = null;
    if (upstreamRepoState === "ok" || upstreamRepoState === "renamed") {
      try {
        const { data: headCommit } = await octokit.request(
          "GET /repos/{owner}/{repo}/commits/{ref}",
          {
            owner: ownerRepo.split("/")[0],
            repo: ownerRepo.split("/")[1],
            ref: upstreamRef,
          },
        );
        if (typeof headCommit.sha === "string" && headCommit.sha) {
          newPinnedCommit = headCommit.sha;
        }
      } catch (pinErr) {
        logger.warn(
          {
            fn: "cron-content-vendor-drift",
            bundle: bundle.slug,
            err: (pinErr as Error).message,
          },
          "Upstream head-commit fetch failed — a PR-route run will fail loudly on the missing pin",
        );
      }
    }

    // Get upstream files list
    const upstreamFilesResult = await spawnScriptCapture(
      parserPath,
      ["upstream-files"],
      { cwd: repoRoot, env },
    );
    const upstreamFiles = upstreamFilesResult.stdout
      .trim()
      .split("\n")
      .filter(Boolean);

    // The positional twin of `upstream-files`: `lifted-files` emits
    // `<local-rel>:<local-sha>` in the same record order, and the re-vendor
    // write pairs them by index to know WHICH local path a drifted
    // upstream path maps to (#8180). If the two views differ in length the
    // zip would merge the wrong upstream bytes into the wrong file —
    // throw; that NOTICE is malformed and the mismatch is a measurement
    // failure, not a per-file error.
    const liftedFilesResult = await spawnScriptCapture(
      parserPath,
      ["lifted-files"],
      { cwd: repoRoot, env },
    );
    const liftedFiles = liftedFilesResult.stdout
      .trim()
      .split("\n")
      .filter(Boolean);
    if (liftedFiles.length !== upstreamFiles.length) {
      throw new Error(
        `NOTICE registry views disagree on cardinality: lifted-files=${liftedFiles.length} upstream-files=${upstreamFiles.length} — cannot zip-pair records for the re-vendor write`,
      );
    }

    let driftDetected = false;
    const aggDiffParts: string[] = [];
    const driftedFiles: DriftedFile[] = [];

    // THREE states, not two (#7710). The previous form collapsed a missing
    // sha and an equal sha into ONE `continue`, which scores a response that
    // ARRIVED BUT COULD NOT BE PARSED — a degraded 200, a body with no
    // `sha` field — identically to "this file is unchanged".
    //
    // (That superseded expression is deliberately not quoted verbatim here:
    // the regression guard in the test suite greps this file for it, and a
    // body-grep cannot tell code from a comment.)
    // That is a false-clean: the run cannot distinguish "I compared it and
    // it matched" from "I could not compare it", and both fed a `drift:
    // none` return that reads as evidence of currency.
    //
    // A fetch that did not answer is ERROR, never SAME.
    let filesExamined = 0;
    const examinedPaths = new Set<string>();
    let filesSame = 0;
    let filesDrifted = 0;
    let filesError = 0;

    for (let i = 0; i < upstreamFiles.length; i++) {
      const line = upstreamFiles[i];
      const [upstreamPath, oldSha] = line.split(":");
      if (!upstreamPath || !oldSha) {
        // A malformed registry line is not a file we compared. Counting it
        // as examined-and-same would let a corrupt NOTICE manufacture a
        // clean total.
        filesError += 1;
        continue;
      }

      // DISTINCT paths, not records. A duplicated `upstream-path` (the
      // ordinary copy-paste slip in a re-vendor PR) would otherwise let
      // eight records compare seven files twice-over and satisfy
      // `filesExamined === registryCount` with one rule file never fetched
      // — the same 5-of-8 shape the completeness conjunct exists to catch,
      // one level down. The Set lives on the object the predicate reads, so
      // it cannot drift away from the conjunct that consumes it.
      if (examinedPaths.has(upstreamPath)) {
        filesError += 1;
        logger.warn(
          {
            fn: "cron-content-vendor-drift",
            bundle: bundle.slug,
            path: upstreamPath,
          },
          "Duplicate upstream-path in the NOTICE registry — scored ERROR; the registry does not describe the corpus it claims to",
        );
        continue;
      }
      examinedPaths.add(upstreamPath);
      filesExamined += 1;

      try {
        const { data: contents } = await octokit.request(
          "GET /repos/{owner}/{repo}/contents/{path}",
          {
            owner: ownerRepo.split("/")[0],
            repo: ownerRepo.split("/")[1],
            path: upstreamPath,
            // Read at the RESOLVED head commit when we have it, not the
            // mutable branch name: a push landing between the pin fetch
            // above and this read would otherwise write a NOTICE asserting
            // `upstream-blob-sha` at commit C2 while `pinned-commit` names
            // C1 — an internally inconsistent binding the #8181 check then
            // correctly fails on main after auto-merge (#8185 review). The
            // branch name remains the fallback for detection when the pin
            // fetch failed (the pr route throws on the null pin anyway).
            ref: newPinnedCommit ?? upstreamRef,
          },
        );
        const currentSha = (contents as { sha?: string }).sha;
        const verdict = classifyFileComparison(oldSha, currentSha);

        if (verdict === "error") {
          filesError += 1;
          logger.warn(
            {
              fn: "cron-content-vendor-drift",
              bundle: bundle.slug,
              path: upstreamPath,
              oldSha,
            },
            "Upstream contents response carried no sha — scored ERROR, not SAME",
          );
          continue;
        }

        if (verdict === "same") {
          filesSame += 1;
          continue;
        }

        filesDrifted += 1;
        driftDetected = true;

        // Record the pair the re-vendor write will merge (#8180). The
        // lifted path AND the local sha come from the positionally-paired
        // `lifted-files` view (cardinality asserted above); `newSha` is the
        // blob now at `upstreamPath` on `upstreamRef`, fetched seconds ago.
        // `oldLocalSha` lets the NOTICE rewrite bind the substitution to
        // this record's block — positional pairing alone cannot tell a
        // crossed view pair from an aligned one (#8185 review).
        const [liftedPath, oldLocalSha] = liftedFiles[i].split(":");
        if (!liftedPath || !/^[0-9a-f]{40}$/.test(oldLocalSha ?? "")) {
          // A lifted-files line without a usable sha is a malformed record,
          // not a file to merge — count it and let the write step's
          // completeness gate refuse the pr route.
          filesError += 1;
          continue;
        }
        driftedFiles.push({
          liftedPath,
          upstreamPath,
          oldSha,
          // verdict === "drift" is unreachable with an empty currentSha —
          // classifyFileComparison scores that ERROR above.
          newSha: currentSha as string,
          oldLocalSha,
        });

        // Populate the classifier's stdin. This array was declared and
        // joined into `stdin` but NEVER written to (#7710), so the
        // classifier received an empty diff on every run, returned 0, and
        // the handler took the `classifyRc === 0` early return — which is
        // the SECOND `drift: "none"` site, reached AFTER drift was
        // detected. Categorising drift is the classifier's whole job and it
        // was being asked to categorise nothing.
        //
        // IT MUST BE A UNIFIED DIFF. `vendor-drift-classify.sh` says so in
        // its header, and every category check is anchored accordingly:
        // license on `^(\+\+\+|---) [ab]/…LICENSE`, security on `^\+`. A
        // first revision of this fix pushed `path\told\tnew`, which begins
        // with a path and therefore matches NEITHER — so exits 10 (security)
        // and 11 (license) became unreachable and every drift fell through
        // to check 5's bare non-empty test, i.e. exit 13 → the auto-PR route
        // with `mergeMode: "direct"`. That route is restricted to exit 13
        // precisely to keep attacker-controlled upstream bytes from landing
        // via the weekly bot, so the shape of the string is load-bearing
        // security, not formatting.
        //
        // Every line of the drifted upstream file is emitted as ADDED. That
        // is deliberate and conservative: a minimal diff can only shrink the
        // text the security regex sees, and the failure direction we cannot
        // afford is under-triggering. Over-triggering costs a human reading
        // an issue instead of a bot opening a PR.
        const upstreamBody = decodeContentsBody(contents);
        const bodyLines = upstreamBody?.split("\n");
        if (
          upstreamBody === null ||
          (bodyLines?.length ?? 0) > MAX_DIFF_LINES_PER_FILE
        ) {
          // We know it drifted but cannot show the classifier what changed
          // (undecodable body), or cannot show it ALL (the truncation cap):
          // a diff past line MAX_DIFF_LINES_PER_FILE would feed the security
          // regex a PREFIX while the merge commits the whole blob — content
          // past the cap would auto-merge unscreened (#8185 review). Force
          // the guarded route with an explicit marker the security regex
          // matches.
          aggDiffParts.push(
            `--- a/${upstreamPath}\n+++ b/${upstreamPath}\n+[CRITICAL] drifted content ${upstreamBody === null ? "unreadable" : `exceeds the ${MAX_DIFF_LINES_PER_FILE}-line classifier window`} — classify conservatively`,
          );
        } else {
          const body = (bodyLines ?? [])
            .map((l) => `+${l}`)
            .join("\n");
          aggDiffParts.push(
            `--- a/${upstreamPath}\n+++ b/${upstreamPath}\n${body}`,
          );
        }

        logger.info(
          {
            fn: "cron-content-vendor-drift",
            bundle: bundle.slug,
            path: upstreamPath,
            oldSha,
            currentSha,
          },
          "Drift detected",
        );
      } catch (fetchErr) {
        // A per-FILE fetch failure is not evidence about the REPOSITORY.
        // This arm used to raise the repo-level rename flag, telling the
        // classifier the whole upstream had moved — and routing to
        // `vendor/upstream-archived` + `needs-human-review` — on a single
        // 404 or 5xx. That is "I could not measure" read as evidence, which
        // is the defect this PR exists to close (#7710 review). The
        // superseded assignment is described rather than quoted: the
        // regression guard greps this region for it, and a body-grep cannot
        // tell code from a comment.
        //
        // The error is counted, which is enough: `filesError > 0` both
        // refuses the attestation and marks the run as unable to measure,
        // so it reaches the heartbeat without inventing a repo-level claim.
        driftDetected = true;
        filesError += 1;
        logger.warn(
          {
            fn: "cron-content-vendor-drift",
            bundle: bundle.slug,
            path: upstreamPath,
            err: (fetchErr as Error).message,
          },
          "Upstream contents fetch failed for one file — scored ERROR",
        );
      }
    }

    // The count of records DECLARED in the NOTICE — NOT `upstreamFiles.length`.
    //
    // `upstream-files` is a FILTERED view: `_emit_files` flushes a record
    // only when both its path key and its sha key are non-empty, so a record
    // that loses `upstream-blob-sha` vanishes from it. Deriving the
    // denominator from that view made the completeness conjunct a tautology
    // — the denominator shrank with the numerator, `filesExamined ===
    // registryCount` held, and the cron attested over a corpus it had only
    // partially compared. That is the 5-of-8 failure #7710 exists to
    // prevent, so its guard must not be measured through the same lens that
    // loses the records (#7710 review).
    const declaredResult = await spawnScriptCapture(
      parserPath,
      ["record-count", "lifted-files"],
      { cwd: repoRoot, env },
    );
    const declaredRaw = declaredResult.stdout.trim();

    // A SECOND, differently-derived view of the registry's size.
    //
    // `record-count` shares its record-opener predicate with `_emit_files`,
    // so deleting an OPENER line shrinks both together: measured, declared 7
    // and emitted 7 with one record silently absorbed into its predecessor,
    // and the completeness conjunct held. Counting a key the opener
    // predicate does not consume breaks that coupling — on the same fixture
    // it reads 8 against an emitted 7.
    const statusResult = await spawnScriptCapture(
      parserPath,
      ["key-count", "lifted-files", "status"],
      { cwd: repoRoot, env },
    );
    const statusRaw = statusResult.stdout.trim();
    // Fail closed: a non-numeric answer means the registry could not be
    // read, and 0 makes `registryCount > 0` refuse.
    const declaredOpeners = /^\d+$/.test(declaredRaw) ? Number(declaredRaw) : 0;
    const declaredStatus = /^\d+$/.test(statusRaw) ? Number(statusRaw) : 0;

    // The LARGER of the two declared views. Any record loss inflates the
    // denominator relative to what was examined, so the completeness
    // conjunct refuses; a missing `status:` key alone does not (it costs no
    // comparability, and all records were still compared).
    const registryCount = Math.max(declaredOpeners, declaredStatus);
    if (
      declaredOpeners !== declaredStatus ||
      registryCount !== upstreamFiles.length
    ) {
      logger.warn(
        {
          fn: "cron-content-vendor-drift",
          bundle: bundle.slug,
          declaredOpeners,
          declaredStatus,
          emitted: upstreamFiles.length,
        },
        "NOTICE registry views disagree — a record is malformed or being dropped; the attestation will refuse",
      );
    }

    // Built once and spread at every exit. Hand-copying six fields across
    // six returns is how a seventh return site silently omits one, and an
    // omitted field on THIS object is a conjunct the write predicate then
    // cannot evaluate (#7710 review).
    const totals: ComparisonTotals = {
      registryCount,
      filesExamined,
      filesSame,
      filesDrifted,
      filesError,
      upstreamRepoState,
    };

    // Rollback / rewritten-history detection (#8183, #8185 review). The
    // classifier's exit-15 arm needs `git merge-base` against objects this
    // clone does not hold, so ordering is decided via the compare API
    // instead: the resolved upstream head BEHIND or DIVERGED from the
    // pinned commit is a rollback/force-push — a supply-chain signal that
    // must reach a human regardless of what the content diff classifies as.
    let rollbackSuspected = false;
    if (
      driftDetected &&
      newPinnedCommit &&
      /^[0-9a-f]{40}$/.test(pinnedSha) &&
      newPinnedCommit !== pinnedSha
    ) {
      try {
        const { data: cmp } = await octokit.request(
          "GET /repos/{owner}/{repo}/compare/{basehead}",
          {
            owner: ownerRepo.split("/")[0],
            repo: ownerRepo.split("/")[1],
            basehead: `${pinnedSha}...${newPinnedCommit}`,
          },
        );
        if (cmp.status === "behind" || cmp.status === "diverged") {
          rollbackSuspected = true;
          logger.warn(
            {
              fn: "cron-content-vendor-drift",
              bundle: bundle.slug,
              pinnedCommit: pinnedSha,
              newPinnedCommit,
              compareStatus: cmp.status,
            },
            "Upstream head is behind/diverged from the pinned commit — rollback or rewritten history; routing to human review",
          );
        }
      } catch (cmpErr) {
        // An inconclusive compare is not evidence of ordering — leave the
        // flag false and let content classification route; the failure is
        // logged, not asserted.
        logger.warn(
          {
            fn: "cron-content-vendor-drift",
            bundle: bundle.slug,
            err: (cmpErr as Error).message,
          },
          "Upstream compare probe failed — rollback detection inconclusive",
        );
      }
    }

    // Carried on every arm for a uniform memoized shape (ADR-033 I5):
    // `driftedFiles`/`newPinnedCommit` feed the re-vendor write,
    // `repoMetaSummary` feeds the issue-body metadata section, and
    // `openPrRefs` lets the skip arm report WHICH PRs suppressed this run.
    const detection = {
      driftedFiles,
      newPinnedCommit,
      repoMetaSummary,
      rollbackSuspected,
      openPrRefs: [] as string[],
    };

    if (!driftDetected && !driftFlags) {
      return {
        drift: "none" as const,
        route: "none" as const,
        labels: [] as string[],
        classifyRc: 0,
        upstreamRef,
        ...detection,
        ...totals,
      };
    }

    // Run classifier
    const classifierArgs = driftFlags ? [driftFlags] : [];
    const classifyResult = await spawnScriptCapture(
      classifierPath,
      classifierArgs,
      {
        cwd: repoRoot,
        env,
        stdin: aggDiffParts.join("\n"),
      },
    );

    const classifyRc = classifyResult.exitCode ?? 0;
    const labels = parseClassifierLabels(
      classifyResult.stdout,
      classifyRc,
    );
    // A suspected rollback/rewrite must reach a human no matter what the
    // content diff classified as — the classifier's own exit-15 arm is
    // unreachable here (it needs upstream git objects this clone lacks), so
    // the compare-API verdict above takes over its routing and labels.
    if (rollbackSuspected) {
      for (const l of CATEGORY_LABELS.rollback) {
        if (!labels.includes(l)) labels.push(l);
      }
    }

    logger.info(
      {
        fn: "cron-content-vendor-drift",
        bundle: bundle.slug,
        classifyRc,
        labels,
      },
      "Classifier result",
    );

    if (classifyRc === 0) {
      // NOT an attestation-worthy exit. This return is reached AFTER drift
      // was detected, whenever the classifier declines to categorise it.
      // Keying the freshness write on `drift === "none"` would therefore
      // advance a compliance attestation over a corpus this very run found
      // drift in — which is the exact falsification #7710 exists to
      // prevent. The write predicate keys on the TOTALS instead.
      return {
        drift: "none" as const,
        route: "none" as const,
        labels: [] as string[],
        classifyRc: 0,
        upstreamRef,
        ...detection,
        ...totals,
      };
    }

    // Trust-model routing: security/license/rollback/renamed/archived
    // drift opens an ISSUE (no auto-PR). Auto-PR is reserved for
    // low-risk batched drift (exit 13). A suspected upstream rollback joins
    // the issue route unconditionally — its content can be classifier-clean
    // while still being a supply-chain event.
    if (ISSUE_EXIT_CODES.has(classifyRc) || rollbackSuspected) {
      return {
        drift: "detected" as const,
        route: "issue" as const,
        labels,
        classifyRc,
        upstreamRef,
        ...detection,
        ...totals,
      };
    }

    if (classifyRc === 13) {
      // Idempotency, scoped PER BUNDLE: an open bundle-A re-vendor PR must
      // not suppress bundle-B's. The pulls list is classified by
      // classifyBranchOwner — slugged refs belong to their slug, legacy
      // unsuffixed refs to LEGACY_BUNDLE_SLUG (#5111 kept the prefix-based
      // dedup; multi-bundle adds the ownership classification).
      const openHeads = await listOpenPrHeads(octokit);
      const openDriftPrs = openHeads.filter(
        (ref) =>
          classifyBranchOwner(ref, DRIFT_BRANCH_PREFIX, slugs) ===
          bundle.slug,
      );
      if (openDriftPrs.length > 0) {
        // WARN, not info: <40 pino lines reach no observability layer (the
        // comment at the attestation summary carries the measurement), and
        // "why did the cron not file this week" is a question an operator
        // should be able to answer from shipped telemetry.
        logger.warn(
          {
            fn: "cron-content-vendor-drift",
            bundle: bundle.slug,
            openDriftPrs,
          },
          "Skipping: open drift PR(s) already exist for this bundle",
        );
        return {
          drift: "skipped-open-pr" as const,
          route: "none" as const,
          labels,
          classifyRc,
          upstreamRef,
          ...detection,
          openPrRefs: openDriftPrs,
          ...totals,
        };
      }

      return {
        drift: "detected" as const,
        route: "pr" as const,
        labels,
        classifyRc,
        upstreamRef,
        ...detection,
        ...totals,
      };
    }

    // Unknown exit code — route to issue for human triage
    return {
      drift: "detected" as const,
      route: "issue" as const,
      labels,
      classifyRc,
      upstreamRef,
      ...detection,
      ...totals,
    };
  });

  // Route: open PR for low-risk drift. Persistence via safeCommitAndPr
  // (#5111) — gains the deletion guard (a large upstream restructure
  // deleting >10 files under references/ aborts loudly BY DESIGN; see the
  // runbook's DEFAULT_MAX_DELETIONS raise path), dirty-index precondition,
  // dropped-path warn, and replay idempotency. mergeMode "direct" +
  // synthetic checks preserves the production-proven merge mechanics.
  // Branch becomes ci/content-vendor-drift-<slug>-<ts> via the per-bundle
  // cronName (helper derivation, #5111) — the detect step's open-PR dedup
  // classifies this namespace by slug and was updated in lockstep.
  // `pr` route honesty: the result is CAPTURED, not discarded. A pr-route
  // arm with no committed artifact is NOT healthy — the heartbeat must not
  // read `route !== "none"` as "artifact produced" (prArtifactMissing below).
  let prStepResult: SafeCommitResult | null = null;
  if (detectResult.route === "pr") {
    prStepResult = await step.run(`safe-commit-pr-${bundle.slug}`, async () => {
      // THE RE-VENDOR WRITE LIVES IN THIS STEP, before safeCommitAndPr —
      // not in a prior step. A filesystem write that is the only carrier of
      // new content must execute in the same memoized step as the commit
      // consuming it: split out, an Inngest replay returns the memoized
      // detect result while the worktree is clean and the commit is a
      // silent `no-changes` no-op — the exact dead-route failure #8180
      // exists to remove (learning
      // 2026-06-14-inngest-regenerate-cron-consolidate-write-and-commit-in-one-step).
      //
      // The merge/NOTICE-rewrite/conflict-gate shape is ported from the
      // deleted workflow (`git show
      // 804114883:.github/workflows/scheduled-content-vendor-drift.yml`,
      // ~:270-360): blob fetches keyed by immutable SHA, `git merge-file
      // --diff3` into the lifted path, `git hash-object --no-filters` for
      // the new local pin, block-anchored NOTICE rewrite with an
      // assert-exactly-1 contract, then the conflict-marker gate. All paths
      // and identity strings are per-bundle — `bundle.skillPrefix`,
      // `bundle.noticeFileRel`, `bundle.upstreamName` — never the old
      // single-bundle constants.
      if (detectResult.driftedFiles.length === 0) {
        throw new Error(
          `route=pr with zero drifted files for bundle ${bundle.slug} — the classifier routed drift this run did not measure`,
        );
      }
      if (!detectResult.newPinnedCommit) {
        throw new Error(
          `route=pr without a resolved upstream head commit for bundle ${bundle.slug} — cannot write a pin that was not measured`,
        );
      }
      if (!/^[0-9a-f]{40}$/.test(detectResult.newPinnedCommit)) {
        throw new Error(
          `route=pr with a non-SHA pin for bundle ${bundle.slug}: ${detectResult.newPinnedCommit}`,
        );
      }
      // A partially-measured registry must not advance `pinned-commit`:
      // `bumpNoticeField` moves the pin for the WHOLE registry while only
      // `driftedFiles` records get rewritten — an errored/unmeasured record
      // would keep its old blob-sha beside the new commit, an internally
      // inconsistent binding the #8181 verify gate then fails on the merged
      // PR itself (#8185 review). Fail loud; the issue route is where
      // unmeasurable drift belongs.
      if (
        detectResult.filesError > 0 ||
        detectResult.filesExamined !== detectResult.registryCount
      ) {
        throw new Error(
          `route=pr on a partially-measured registry for bundle ${bundle.slug} (examined=${detectResult.filesExamined}/${detectResult.registryCount} errors=${detectResult.filesError}) — refusing to advance pinned-commit over unmeasured records`,
        );
      }

      // `liftedPath` is NOTICE-supplied data used as a write target —
      // confine it to `references/` (the only prefix safeCommitAndPr's
      // allowlist commits content under) before ANY disk touch, including
      // the restore below. A record declaring `../x` or `docs/x` would
      // otherwise be merged on disk and then DROPPED by the allowlist —
      // while its NOTICE record was already rewritten, leaving a merged PR
      // attesting bytes it never carried (#8185 review). Validated for the
      // whole set up front so a bad LATER record cannot leave earlier
      // merges half-applied before the throw.
      const referencesRoot = join(
        repoRoot,
        bundle.skillPrefix,
        "references",
      );
      for (const f of detectResult.driftedFiles) {
        const liftedAbs = join(repoRoot, bundle.skillPrefix, f.liftedPath);
        if (
          f.liftedPath.includes("..") ||
          f.liftedPath.startsWith("/") ||
          !resolve(liftedAbs).startsWith(referencesRoot + sep)
        ) {
          throw new Error(
            `Refusing to merge into a lifted path outside references/: ${bundle.skillPrefix}/${f.liftedPath}`,
          );
        }
      }

      // Replay idempotency: a mid-loop throw retries this WHOLE step with
      // detect memoized and the worktree holding the first attempt's
      // merges. `git merge-file` is not idempotent — a second pass over
      // already-merged content produces nested markers or a clean-but-wrong
      // merge (#8185 review). Restore every touched path to origin/main —
      // NOT HEAD, which by then is the ci/ branch tip carrying the first
      // attempt's merges — so the retry merges the same inputs as the
      // initial attempt.
      {
        const restore = await spawnGit(
          [
            "restore",
            "--source=origin/main",
            "--worktree",
            "--",
            bundle.noticeFileRel,
            ...detectResult.driftedFiles.map(
              (f) => `${bundle.skillPrefix}/${f.liftedPath}`,
            ),
          ],
          { cwd: repoRoot },
        );
        if (restore.exitCode !== 0) {
          throw new Error(
            `git restore of re-vendor targets failed for bundle ${bundle.slug} (exit ${restore.exitCode}): ${restore.stderr.slice(0, 500)}`,
          );
        }
      }

      // Merge inputs live OUTSIDE the clone — inside `repoRoot` they would
      // read as untracked paths to safeCommitAndPr's allow-list guard.
      const mergeDir = await mkdtemp(join(repoRoot, "..", "merge-inputs-"));
      let noticeSrc = await readFile(noticeAbs, "utf8");
      const mergeStatus: {
        path: string;
        outcome: "merged" | "conflicted";
      }[] = [];

      for (const f of detectResult.driftedFiles) {
        // A symlink at the merge target is as out-of-bounds as a `..` path:
        // merge-file follows it and writes outside the repo.
        const liftedAbs = join(repoRoot, bundle.skillPrefix, f.liftedPath);
        if (
          !existsSync(liftedAbs) ||
          !lstatSync(liftedAbs).isFile() ||
          lstatSync(liftedAbs).isSymbolicLink()
        ) {
          throw new Error(
            `Drifted lifted file absent from worktree (or not a regular file): ${bundle.skillPrefix}/${f.liftedPath}`,
          );
        }
        const idx = mergeStatus.length;
        const oldTmp = join(mergeDir, `old-${idx}`);
        const newTmp = join(mergeDir, `new-${idx}`);
        // Both keyed by immutable blob SHA — a resumed step re-derives
        // identical bytes.
        await writeFile(
          oldTmp,
          await fetchUpstreamBlob(octokit, bundle.upstreamName, f.oldSha),
        );
        await writeFile(
          newTmp,
          await fetchUpstreamBlob(octokit, bundle.upstreamName, f.newSha),
        );

        // git merge-file: 0 = clean merge (lifted path rewritten in place);
        // 1..127 = conflict count and the file now carries --diff3 markers;
        // >=128 or a spawn error is a hard failure — throw, never skip.
        const merge = await spawnGit(
          [
            "merge-file",
            "--diff3",
            "-L",
            f.liftedPath,
            "-L",
            "upstream-pinned",
            "-L",
            "upstream-new",
            liftedAbs,
            oldTmp,
            newTmp,
          ],
          { cwd: repoRoot },
        );
        if (
          merge.exitCode === null ||
          merge.exitCode < 0 ||
          merge.exitCode >= 128 ||
          merge.signal
        ) {
          throw new Error(
            `git merge-file failed for ${f.liftedPath} (exit ${merge.exitCode}, signal ${merge.signal}): ${merge.stderr.slice(0, 500)}`,
          );
        }
        const conflicted = merge.exitCode > 0;
        mergeStatus.push({
          path: f.liftedPath,
          outcome: conflicted ? "conflicted" : "merged",
        });

        const newLocalSha = await spawnGitStdout(
          ["hash-object", "--no-filters", liftedAbs],
          { cwd: repoRoot },
        );
        if (!/^[0-9a-f]{40}$/.test(newLocalSha)) {
          throw new Error(
            `git hash-object returned a non-SHA for ${f.liftedPath}: ${newLocalSha}`,
          );
        }
        noticeSrc = rewriteNoticeRecord(
          noticeSrc,
          f.liftedPath,
          newLocalSha,
          f.newSha,
          {
            upstreamPath: f.upstreamPath,
            oldUpstreamSha: f.oldSha,
            oldLocalSha: f.oldLocalSha,
          },
        );
        await rm(oldTmp, { force: true });
        await rm(newTmp, { force: true });
      }

      // The records now attest the newly-pinned content — this write IS the
      // verified-clean endpoint for the new pin, so pinned-commit and
      // last-verified advance inside the PR's own NOTICE diff. Line-anchored,
      // exactly-one each (bumpNoticeField throws otherwise). The separate
      // attest-freshness step's clean-run writer is untouched.
      const today = runStartedAt.slice(0, 10);
      noticeSrc = bumpNoticeField(
        noticeSrc,
        "pinned-commit",
        detectResult.newPinnedCommit,
      );
      noticeSrc = bumpNoticeField(noticeSrc, "last-verified", today);
      await writeFile(noticeAbs, noticeSrc, "utf8");

      // Conflict-marker gate (runbook §2): a merged file still carrying
      // `<<<<<<<` markers must NOT auto-merge upstream bytes into
      // compliance content — the PR is created create-only and labeled for
      // human resolution. The merge-file exit verdict is a belt over the
      // marker scan: a >0 exit with no visible markers still means the
      // merge was not clean (#8185 review).
      let needsHumanReview = mergeStatus.some(
        (m) => m.outcome === "conflicted",
      );
      for (const f of detectResult.driftedFiles) {
        const merged = await readFile(
          join(repoRoot, bundle.skillPrefix, f.liftedPath),
          "utf8",
        );
        if (/^<<<<<<</m.test(merged)) {
          needsHumanReview = true;
        }
      }

      const res = await safeCommitAndPr({
        spawnCwd: repoRoot,
        installationToken,
        cronName,
        commitMessage: `chore(vendor-drift): re-vendor ${bundle.upstreamName}`,
        allowedPaths: [
          `${bundle.skillPrefix}/NOTICE`,
          `${bundle.skillPrefix}/references/`,
        ],
        runStartedAt,
        scheduledIssueLabel: SENTRY_MONITOR_SLUG,
        // An earlier revision of this body asserted a last-verified bump
        // nothing performed (#7710 — the sentence is described, not quoted,
        // because the regression guard greps for it). The claim is true NOW:
        // the write loop above advances both fields in this PR's NOTICE
        // diff, so the body reports what it did rather than what it did not.
        prBody: [
          `Automated re-vendor on upstream drift for bundle \`${bundle.slug}\`. Resolution path: knowledge-base/engineering/operations/runbooks/vendor-pin-drift-resolution.md.`,
          "",
          "## Per-file merge status",
          "",
          ...mergeStatus.map((m) => `- \`${m.path}\` — ${m.outcome}`),
          "",
          `NOTICE \`pinned-commit\` advanced to \`${detectResult.newPinnedCommit}\` and \`last-verified\` to \`${today}\` — the merged records attest the newly pinned content.`,
          ...(needsHumanReview
            ? [
                "",
                "⚠️ Merge conflicts present — files above marked `conflicted` carry `--diff3` markers. This PR is create-only; resolve per runbook §2.",
              ]
            : []),
        ].join("\n"),
        prLabels: detectResult.labels.concat(
          needsHumanReview ? ["needs-human-review"] : [],
        ),
        syntheticChecks: {
          names: SYNTHETIC_CHECK_NAMES,
          summary: "Re-vendor on upstream drift detection — see runbook",
        },
        // "none" is the create-only human-review arm: a conflicted
        // re-vendor must not auto-merge conflict markers into compliance
        // content (also removes the CODEOWNERS-bypass residual ADR-203
        // carries on the direct-merge arm).
        mergeMode: needsHumanReview ? "none" : "direct",
        octokit,
        logger,
      });

      // The return must never be discarded — a clean worktree means a
      // silent no-PR run reading green. On this arm `no-changes` means the
      // write loop regressed; report it so the miss is observable (the
      // prArtifactMissing conjunct below additionally keeps the bundle
      // heartbeat red).
      if (res.status === "no-changes") {
        reportSilentFallback(
          new Error(
            "Re-vendor write produced no worktree changes — safeCommitAndPr returned no-changes on the PR route",
          ),
          {
            feature: "cron-content-vendor-drift",
            op: "safe-commit-no-changes",
            message: `bundle=${bundle.slug} drifted=${detectResult.driftedFiles.length} conflicted=${needsHumanReview} — expected a dirty tree, got none`,
            extra: {
              fn: "cron-content-vendor-drift",
              bundle: bundle.slug,
              driftedFiles: detectResult.driftedFiles.length,
              conflicted: needsHumanReview,
            },
          },
        );
      }
      // The committed set must CONTAIN every file this step claims to have
      // re-vendored — `paths` is undefined only on the replay-resume arm,
      // where the commit was already produced under this same check.
      // Without this, an allowlist-dropped file leaves the NOTICE attesting
      // content that never landed (#8185 review).
      if (res.status === "committed" && res.paths) {
        const committed = new Set(res.paths);
        const missing = detectResult.driftedFiles
          .map((f) => `${bundle.skillPrefix}/${f.liftedPath}`)
          .filter((p) => !committed.has(p));
        if (missing.length > 0) {
          reportSilentFallback(
            new Error(
              `Re-vendor PR for bundle ${bundle.slug} committed without ${missing.length} drifted path(s): ${missing.join(", ")} — the NOTICE attests content the PR does not carry`,
            ),
            {
              feature: "cron-content-vendor-drift",
              op: "revendor-paths-missing",
              extra: { fn: "cron-content-vendor-drift", bundle: bundle.slug, missing },
            },
          );
        }
      }
      return res;
    });
  }

  // Route: open issue for security-relevant drift
  if (detectResult.route === "issue") {
    await step.run(`open-drift-issue-${bundle.slug}`, async () => {
      const todayISO = new Date().toISOString().slice(0, 10);
      const title = `[vendor-drift][${bundle.slug}] security-relevant drift on ${todayISO} (classifier rc=${detectResult.classifyRc})`;

      // Idempotency, scoped PER BUNDLE: titles carry `[<slug>]`, and legacy
      // titles with no slug token classify as LEGACY_BUNDLE_SLUG's — an open
      // bundle-A issue must not suppress bundle-B's filing.
      // Dedup on the TITLE PHRASE alone — the label conjunct would miss the
      // four non-security drift classes (license/archived/renamed/rollback
      // carry vendor/license-changed, vendor/upstream-archived and
      // vendor/upstream-rollback, NOT vendor/pin-drift), so an unresolved
      // issue in any of those classes was invisible to this query and the
      // run re-filed a duplicate every week. Bundle ownership is still
      // partitioned client-side by classifyIssueOwner on the [<slug>] token.
      //
      // Dedup completeness (#8182): this is an ENUMERATION — the match is
      // found by scanning `items`, so the scan must page to completion via
      // fetchAllPages. A bounded first page makes an existing open issue
      // beyond it invisible and the run re-files a duplicate every week.
      const existingItems = await fetchAllPages(async (page) => {
        const { data } = await octokit.request("GET /search/issues", {
          q: `is:issue is:open repo:${REPO_OWNER}/${REPO_NAME} "security-relevant drift" in:title`,
          per_page: 100,
          page,
        });
        // A server-side-truncated search page is not a complete enumeration
        // — deciding dedup on it re-files a duplicate (#8185 review).
        if (data.incomplete_results === true) {
          throw new Error(
            "Issue-search enumeration returned incomplete_results — dedup cannot decide on a partial page",
          );
        }
        return { data: data.items };
      });
      const existingForBundle = existingItems.filter(
        (item) => classifyIssueOwner(item.title, slugs) === bundle.slug,
      );
      if (existingForBundle.length > 0) {
        logger.warn(
          {
            fn: "cron-content-vendor-drift",
            bundle: bundle.slug,
            titles: existingForBundle.map((i) => i.title),
          },
          "Existing open security-drift issue found; skipping",
        );
        return;
      }

      // The detect step already fetched this — render it rather than
      // making the operator re-fetch it during triage (#8183). A failed
      // probe leaves `repoMetaSummary` null and renders `?`: "I could not
      // reach the repo" is uncertainty, never an affirmative "repo is
      // healthy" fact.
      const meta = detectResult.repoMetaSummary;
      // Upstream-controlled strings (full_name, default_branch — a refname
      // can legally contain backticks) are scrubbed before interpolating
      // into markdown code spans (mirrors safeMd in _cron-safe-commit).
      const mdSafe = (s: string) => s.replace(/[`\r\n|]/g, "ʼ");
      const body = [
        "Automated drift detection routed to issue-only (no auto-PR).",
        "",
        `**Bundle:** \`${bundle.slug}\` (\`${bundle.noticeFileRel}\`)`,
        `**Upstream:** \`${bundle.upstream}\` pinned at \`${bundle.pinnedCommit}\``,
        `**Classifier exit code:** \`${detectResult.classifyRc}\``,
        `**Labels:** \`${detectResult.labels.join(", ")}\``,
        ...(detectResult.rollbackSuspected
          ? [
              "",
              "**⚠️ Upstream head is behind/diverged from the pinned commit — possible rollback or rewritten history. Treat as a supply-chain event.**",
            ]
          : []),
        "",
        "## Upstream repository metadata",
        "",
        `- **full_name:** \`${meta ? mdSafe(meta.fullName) : "?"}\``,
        `- **archived:** \`${meta ? meta.archived : "?"}\``,
        `- **default_branch:** \`${meta ? mdSafe(meta.defaultBranch) : "?"}\``,
        `- **upstream_repo_state:** \`${detectResult.upstreamRepoState}\``,
        ...(meta
          ? []
          : [
              "",
              "_(repository probe failed — fields are unknown, not healthy)_",
            ]),
        "",
        "## Why issue, not PR?",
        "",
        "Security-/license-/rollback-/archived-/renamed-class drift requires human re-vendor (per review #3521 user-impact-reviewer).",
        "The auto-PR path is restricted to exit 13 (batched non-security drift) to prevent attacker-controlled upstream bytes from landing via the weekly bot.",
        "",
        "## Resolution path",
        "",
        "Follow `knowledge-base/engineering/operations/runbooks/vendor-pin-drift-resolution.md` §2-§5 (classifier-rc-specific branches).",
        "",
        "Ref #3517",
      ].join("\n");

      await octokit.request("POST /repos/{owner}/{repo}/issues", {
        owner: REPO_OWNER,
        repo: REPO_NAME,
        title,
        body,
        labels: detectResult.labels,
      });
    });
  }

  // -- Freshness attestation (#7710), per bundle --------------------------
  //
  // `last-verified` in each NOTICE is what that bundle's gate hook reads to
  // decide whether its corpus is current. Nothing had EVER advanced it:
  // `git log -S` over that field returns exactly one commit, the one that
  // introduced it, and that commit typed the value by hand — a date one day
  // older than the commit itself. The workflow deleted in #4483 carried a
  // `sed` for the field but behind an `exit 0` on the no-drift path, so it
  // never fired on the arm that mattered. The field therefore aged from
  // 2026-05-10 to 117 days stale while this cron compared the corpus every
  // week and found it clean the whole time. This step is a NEW writer, not a
  // restored one.
  //
  // THE PREDICATE IS THE TOTALS, NEVER `detectResult.drift`. Two of the
  // returns above yield `drift: "none"` and only one of them means "I
  // compared everything and it matched" — the other is reached after drift
  // was detected and the classifier declined to categorise it. Keying on
  // the return value would advance a compliance attestation over a corpus
  // the same run had just found drift in.
  //
  // Every conjunct is load-bearing:
  //   registryCount > 0        — `0 of 0` is not evidence of currency, and
  //                              a writer treating it as such is vacuous.
  //   filesExamined === count  — a PARTIAL comparison is not evidence.
  //   filesDrifted === 0       — the obvious one.
  //   filesError === 0         — a file we could not fetch is not a file we
  //                              verified; without this, an outage reads as
  //                              a clean bill of health.
  const attestationEligible = mayAttestFreshness(detectResult);
  const measurementFailed = couldNotMeasure(detectResult);

  let wroteAttestation = false;
  let artifactCurrent = false;
  let observedAgeDays: number | null = null;
  let attestationOutcome = "not-eligible";
  // A PR number, not a commit SHA. `safeCommitAndPr`'s committed arm
  // reports `prNumber`; calling it `commitSha` on the only forensic surface
  // this run has would be the same conflation #7710 is about.
  let attestationPrNumber: string | null = null;

  // READ THE ARTIFACT'S AGE UNCONDITIONALLY.
  //
  // This used to happen only inside the `if (attestationEligible)` block,
  // so on every drift run `observedAgeDays` stayed null and was never read.
  // That is what let a drift run report healthy indefinitely: the drift is
  // filed once, the issue-open step dedups on it thereafter, and the field
  // ages past 30 and then 90 days behind a green monitor. The age is a
  // local read of the already-cloned NOTICE — it costs nothing and it is
  // the number the whole control is about, so it is measured on every path.
  observedAgeDays = await step.run(
    `read-attestation-age-${bundle.slug}`,
    async () => {
      try {
        // Read the field on the DEFAULT BRANCH, not the worktree: on the
        // pr-route arm the write step has already bumped `last-verified` in
        // `noticeAbs` (and committed onto a ci/ branch), so a worktree read
        // would report age 0 while main's artifact keeps aging — a parked
        // conflicted PR would check in healthy at exactly the moment it
        // needs watching (#8185 review).
        const notice = await spawnGitStdout(
          ["show", `origin/main:${bundle.noticeFileRel}`],
          { cwd: repoRoot },
        );
        const m = notice.match(/^last-verified:[ \t]*(\S+)[ \t]*$/m);
        if (!m) return null;
        const age = Math.floor(
          (Date.parse(`${runStartedAt.slice(0, 10)}T00:00:00Z`) -
            Date.parse(`${m[1]}T00:00:00Z`)) /
            86_400_000,
        );
        return Number.isFinite(age) && age >= 0 ? age : null;
      } catch {
        return null;
      }
    },
  );

  if (attestationEligible) {
    const attestation = await step.run(
      `attest-freshness-${bundle.slug}`,
      async () => {
        // Read from origin/main, not the worktree: a step retry after a
        // partial attempt would otherwise see its own bumped `last-verified`
        // and short-circuit `still-fresh`, silently dropping the attestation
        // (#8185 review).
        const before = await spawnGitStdout(
          ["show", `origin/main:${bundle.noticeFileRel}`],
          { cwd: repoRoot },
        );
        // `runStartedAt`, not a fresh clock read: this value is the
        // idempotency key for the "already advanced today" short-circuit
        // below, and `_cron-safe-commit` already derives the branch name and
        // PR title from the same memoized timestamp. A fresh `new Date()`
        // makes the guard disagree with the branch across a UTC midnight on
        // the `retries: 1` retry (#7710 review).
        const today = runStartedAt.slice(0, 10);

        // The pinned commit the comparison was made against, read from the
        // same file we are about to advance. Recorded in the PR body so the
        // attestation says WHAT was compared, not merely that something was.
        const pinnedMatch = before.match(/^pinned-commit:[ \t]*(\S+)[ \t]*$/m);
        const pinnedForBody = pinnedMatch ? pinnedMatch[1] : "unknown";

        const match = before.match(/^last-verified:[ \t]*(\S+)[ \t]*$/m);
        if (!match) {
          return {
            outcome: "notice-unparseable" as const,
            wrote: false,
            current: false,
            ageDays: null as number | null,
            pr: null as string | null,
          };
        }

        // Age of the field on the freshly-cloned default branch, measured
        // BEFORE this run writes. This is what the heartbeat reads: it says
        // whether the ARTIFACT is current, which is observable, rather than
        // whether this run's merge succeeded, which is usually false even on
        // the healthy path (see heartbeatOk).
        const observedAge = Math.floor(
          (Date.parse(`${today}T00:00:00Z`) -
            Date.parse(`${match[1]}T00:00:00Z`)) /
            86_400_000,
        );
        const ageDays =
          Number.isFinite(observedAge) && observedAge >= 0 ? observedAge : null;
        // Suppress a write that buys no signal. The banner fires at 30 days,
        // so re-attesting a field that is only days old costs a bot PR on a
        // compliance-critical file for nothing. 21 days keeps a full cron
        // cadence of slack ahead of the 30-day threshold while cutting the
        // write rate ~3x — which also shrinks the CODEOWNERS-bypass residual
        // ADR-203 has to argue away (#7710 review).
        if (ageDays !== null && ageDays < WRITE_SUPPRESSION_DAYS) {
          // Nothing is written on this arm, so `wrote` is FALSE. The artifact
          // is nonetheless current, which is what the heartbeat cares about —
          // conflating the two would make the accountability log report a
          // write that did not happen.
          return {
            outcome: "still-fresh" as const,
            wrote: false,
            current: true,
            ageDays,
            pr: null as string | null,
          };
        }
        // Idempotency, scoped PER BUNDLE: do not stack attestation PRs. The
        // 21-day suppression reads `last-verified` from the freshly-cloned
        // default branch, so an unmerged PR is invisible to it — without this
        // guard a stuck PR means a NEW one every cadence, each self-merging,
        // each editing the same line and so mutually conflicting, on a
        // CODEOWNERS-protected compliance file (#7710 review).
        // The dedup runs BEFORE the write: on this arm a step retry would
        // otherwise re-read an already-bumped `last-verified` (ageDays 0 →
        // `still-fresh`) and silently drop the attestation (#8185 review).
        const openHeads = await listOpenPrHeads(octokit);
        const openAttestPRs = openHeads.filter(
          (ref) =>
            classifyBranchOwner(ref, ATTEST_BRANCH_PREFIX, slugs) ===
            bundle.slug,
        );
        if (openAttestPRs.length > 0) {
          return {
            outcome: "attest-pr-already-open" as const,
            wrote: false,
            // The artifact is NOT current — a PR is open precisely because it
            // is stale — so this must not green the heartbeat. `ageDays`
            // carries the truth and the heartbeat reads that.
            current: false,
            ageDays,
            pr: null as string | null,
          };
        }

        // `bumpNoticeField`, not an inline replace: the exactly-one contract
        // throws on a duplicated `last-verified` line where `replace` would
        // bump the first and leave the second stale (#8185 review).
        await writeFile(
          noticeAbs,
          bumpNoticeField(before, "last-verified", today),
          "utf8",
        );

        const res = await safeCommitAndPr({
          spawnCwd: repoRoot,
          installationToken,
          cronName,
          // The squash commit that lands on `main` carries COMMIT_MESSAGES,
          // not the PR body (verified against the repo's
          // `squash_merge_commit_message` setting), so the evidence has to be
          // IN the commit message or it does not survive the merge — and
          // ADR-203's Art. 5(2) argument rests on the commit being the record.
          commitMessage: [
            `chore(vendor-drift): attest ${bundle.upstreamName} unchanged (${today})`,
            "",
            `Compared ${detectResult.filesExamined} of ${detectResult.registryCount} registered files, pinned at ${pinnedForBody}, against upstream ${detectResult.upstreamRef}:`,
            `${detectResult.filesSame} SAME, ${detectResult.filesDrifted} drifted, ${detectResult.filesError} errors, repo-state ${detectResult.upstreamRepoState}.`,
            "",
            "Advances last-verified only; no vendored content is changed.",
          ].join("\n"),
          branchName: `${ATTEST_BRANCH_PREFIX}-${bundle.slug}-${runStartedAt.replace(/[:.]/g, "-")}`,
          allowedPaths: [`${bundle.skillPrefix}/NOTICE`],
          runStartedAt,
          scheduledIssueLabel: SENTRY_MONITOR_SLUG,
          prBody: [
            `Automated freshness attestation for bundle \`${bundle.slug}\`.`,
            "",
            `Compared ${detectResult.filesExamined} of ${detectResult.registryCount} registered files, pinned at \`${pinnedForBody}\`, against upstream \`${detectResult.upstreamRef}\`: ${detectResult.filesSame} SAME, ${detectResult.filesDrifted} drifted, ${detectResult.filesError} errors.`,
            "",
            "This PR advances `last-verified` only. It does not change any vendored content.",
          ].join("\n"),
          prLabels: [],
          syntheticChecks: {
            names: SYNTHETIC_CHECK_NAMES,
            summary: "Freshness attestation — no content change",
          },
          mergeMode: "direct",
          octokit,
          logger,
        });

        // `wrote` keys on the MERGE, not on the PR existing. A failed direct
        // merge falls back to arming auto-merge and still reports
        // `status: "committed"`, so keying on the status would flip the
        // heartbeat green the moment the PR opened — before anything reached
        // the default branch, and permanently if armed auto-merge later
        // disarms on conflict. That is the #7710 shape one layer up: a green
        // signal with no artifact behind it (#7710 review).
        return {
          outcome:
            res.status === "committed" && res.merged !== true
              ? "pr-open-not-merged"
              : res.status,
          // `wrote` means this run merged the advance. It is FALSE on the
          // ordinary `pr-open-not-merged` path, which is fine — the heartbeat
          // reads `ageDays`, not this. It is reported so the accountability
          // log can separate "merged in-run" from "PR opened, lands shortly".
          wrote: res.status === "committed" && res.merged === true,
          current: false,
          ageDays,
          pr:
            res.status === "committed" && typeof res.prNumber === "number"
              ? String(res.prNumber)
              : null,
        };
      },
    );

    wroteAttestation = attestation.wrote;
    artifactCurrent = attestation.current;
    observedAgeDays = attestation.ageDays;
    attestationOutcome = attestation.outcome;
    attestationPrNumber = attestation.pr;
  }

  // ONE line carrying every field together. Four hypotheses share the
  // symptom "the attestation did not advance" — clean-and-written,
  // clean-and-the-merge-was-refused, drifted-and-correctly-withheld, and
  // never-compared — and a single boolean cannot separate them.
  //
  // A structured log rather than an Inngest event because this run has no
  // consumer for an event. (An earlier revision of this comment cited
  // "ADR-033 I6 forbids event payloads from this function"; ADR-033 I6
  // requires `actor: "platform"` ON emitted events and forbids nothing —
  // #7710 review. The pre-existing gloss in this file's header carries the
  // same error and is corrected there too.)
  // Inside a step: Inngest re-executes the handler BODY at every step
  // boundary, so a bare logger.info here re-fires on each replay and this
  // line is the accountability artifact ADR-203 relies on — duplicating it
  // corrupts the evidence it exists to be. Same for the Sentry mirror
  // below (#7710 review).
  // A `pr` route that produced no committed artifact reads as "none" for
  // health purposes — the dedup-and-skip path aside, `route !== "none"` is the
  // heartbeat's "the run produced an artifact" signal, and a discarded
  // `no-changes` result must not satisfy it. This is also what makes a
  // regressed re-vendor write VISIBLE the day an upstream drifts into the
  // auto-PR class: red check-in + Sentry event instead of a silent green.
  const prArtifactMissing =
    detectResult.route === "pr" && prStepResult?.status !== "committed";
  if (prArtifactMissing) {
    attestationOutcome = `pr-route-no-artifact(${prStepResult?.status ?? "no-step"})`;
  }
  const bundleHealthy =
    heartbeatOk(
      measurementFailed,
      attestationEligible,
      observedAgeDays,
      detectResult.route,
    ) && !prArtifactMissing;
  await step.run(`attestation-summary-${bundle.slug}`, async () => {
    // WARN, not info. Measured: `logger.info` reaches no observability
    // layer — the Sentry breadcrumb mirror keeps >= warn
    // (SENTRY_BREADCRUMB_MIN_LEVEL) and the Vector pipeline drops pino
    // level < 40 — so an `info` line carrying the ADR-203 accountability
    // fields would exist only in a stream nothing ingests. This IS the
    // compliance record; it has to be queryable.
    logger.warn(
      {
        fn: "cron-content-vendor-drift",
        bundle: bundle.slug,
        op: "attestation-summary",
        filesExamined: detectResult.filesExamined,
        filesSame: detectResult.filesSame,
        filesDrifted: detectResult.filesDrifted,
        filesError: detectResult.filesError,
        registryCount: detectResult.registryCount,
        attestationEligible,
        wroteAttestation,
        attestationOutcome,
        attestationPrNumber,
        artifactCurrent,
        observedAgeDays,
        measurementFailed,
        isHealthy: bundleHealthy,
      },
      "Vendor-drift attestation summary",
    );

    if (!bundleHealthy) {
      reportSilentFallback(
        new Error(
          `Vendor-drift run is not healthy for bundle ${bundle.slug} (outcome=${attestationOutcome}, age=${observedAgeDays ?? "unreadable"})`,
        ),
        {
          feature: "cron-content-vendor-drift",
          op: measurementFailed
            ? "comparison-could-not-measure"
            : "attestation-stale",
          // `pr` is load-bearing: on the ordinary `pr-open-not-merged` path
          // this is the ONLY Sentry event, and without it the operator
          // cannot tell "a PR is open and auto-merging" from "nothing was
          // created". `bundle` names which registry the event is about.
          message: `bundle=${bundle.slug} examined=${detectResult.filesExamined}/${detectResult.registryCount} drifted=${detectResult.filesDrifted} errors=${detectResult.filesError} repo=${detectResult.upstreamRepoState} outcome=${attestationOutcome} pr=${attestationPrNumber ?? "none"} openPrs=${detectResult.openPrRefs.join(",") || "none"} age=${observedAgeDays ?? "unreadable"}`,
        },
      );
    }
    return { logged: true };
  });

  // The heartbeat must reflect the ARTIFACT, not the run. Previously this
  // posted ok:true unconditionally, so the cron could compare clean, fail
  // to commit, and still report healthy — the failure path inside
  // safeCommitAndPr terminates in reportSilentFallback under a green
  // check-in, which is how a broken writer stays invisible for 117 days.
  return {
    slug: bundle.slug,
    status: detectResult.drift === "none" ? "no-drift" : detectResult.drift,
    route: detectResult.route,
    healthy: bundleHealthy,
    attestationOutcome,
    attestationPrNumber,
    observedAgeDays,
  };
}

// =============================================================================
// Registration
// =============================================================================

export const cronContentVendorDrift = inngest.createFunction(
  {
    id: "cron-content-vendor-drift",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "17 11 * * 1" },
    { event: "cron/content-vendor-drift.manual-trigger" },
  ],
  cronContentVendorDriftHandler as unknown as Parameters<
    typeof inngest.createFunction
  >[2],
);
