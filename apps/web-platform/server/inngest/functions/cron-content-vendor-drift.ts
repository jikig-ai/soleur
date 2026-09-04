// TR9 Phase-2 — Migrated from the GHA scheduled-content-vendor-drift
// workflow (deleted in the same PR per TR9 I-13 hygiene). Weekly upstream
// content drift detector. Parses NOTICE files in plugins/soleur/skills/*/
// NOTICE.md, fetches upstream blobs, detects SHA drift, runs 3-way merge.
// Opens PR for low-risk drift, issue for security/license drift.
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
import { existsSync } from "node:fs";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
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
import { SYNTHETIC_CHECK_NAMES, safeCommitAndPr } from "./_cron-safe-commit";

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

export const NOTICE_FILE_REL = "plugins/soleur/skills/gdpr-gate/NOTICE";
export const PARSER_REL =
  "plugins/soleur/skills/gdpr-gate/scripts/notice-frontmatter.sh";
export const CLASSIFIER_REL =
  "plugins/soleur/skills/gdpr-gate/scripts/vendor-drift-classify.sh";
export const SKILL_PREFIX = "plugins/soleur/skills/gdpr-gate";

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

/**
/** Repository-level state of the upstream, observed once per run. */
export type UpstreamRepoState = "ok" | "archived" | "renamed" | "unreachable";

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
): boolean {
  // "I could not measure" is never healthy — it has no other route.
  if (measurementFailed) return false;
  // Drift found: routed to an issue or a re-vendor PR. Working as intended.
  if (!attestationEligible) return true;
  // Eligible to attest but the field we attest could not be read.
  if (observedAgeDays === null) return false;
  return observedAgeDays < STALENESS_WARN_DAYS;
}

// =============================================================================
// Types
// =============================================================================

interface HandlerResult {
  ok: boolean;
  status: string;
  route?: "pr" | "issue" | "none";
  labels?: string[];
}

// =============================================================================
// Helpers
// =============================================================================

function spawnGit(
  args: string[],
  opts?: { cwd?: string; env?: NodeJS.ProcessEnv },
): Promise<{ exitCode: number | null; signal: NodeJS.Signals | null }> {
  return new Promise((resolve) => {
    const child = spawn("git", args, { stdio: "ignore", ...opts });
    child.on("exit", (exitCode, signal) => resolve({ exitCode, signal }));
    child.on("error", () => resolve({ exitCode: -1, signal: null }));
  });
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
  if (!existsSync(join(repoRoot, NOTICE_FILE_REL))) {
    throw new Error(
      `Sentinel: ${NOTICE_FILE_REL} absent after clone`,
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

    // Detect drift by parsing NOTICE and fetching upstream blobs
    const detectResult = await step.run("detect-drift", async () => {
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
      };

      // Get upstream repo info
      const upstreamResult = await spawnScriptCapture(
        parserPath,
        ["field", "upstream"],
        { cwd: repoRoot, env },
      );
      const upstream = upstreamResult.stdout.trim();

      const pinnedResult = await spawnScriptCapture(
        parserPath,
        ["field", "pinned-commit"],
        { cwd: repoRoot, env },
      );
      const pinnedSha = pinnedResult.stdout.trim();

      if (!upstream || !pinnedSha) {
        throw new Error(
          `Failed to parse NOTICE: upstream=${upstream}, pinned-commit=${pinnedSha}`,
        );
      }

      const ownerRepo = upstream.replace(/^github\.com\//, "");
      logger.info(
        { fn: "cron-content-vendor-drift", upstream, pinnedSha },
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
      try {
        const { data: repoMeta } = await octokit.request(
          "GET /repos/{owner}/{repo}",
          {
            owner: ownerRepo.split("/")[0],
            repo: ownerRepo.split("/")[1],
          },
        );
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

      let driftDetected = false;
      const aggDiffParts: string[] = [];

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
      let filesSame = 0;
      let filesDrifted = 0;
      let filesError = 0;

      for (const line of upstreamFiles) {
        const [upstreamPath, oldSha] = line.split(":");
        if (!upstreamPath || !oldSha) {
          // A malformed registry line is not a file we compared. Counting it
          // as examined-and-same would let a corrupt NOTICE manufacture a
          // clean total.
          filesError += 1;
          continue;
        }

        filesExamined += 1;

        try {
          const { data: contents } = await octokit.request(
            "GET /repos/{owner}/{repo}/contents/{path}",
            {
              owner: ownerRepo.split("/")[0],
              repo: ownerRepo.split("/")[1],
              path: upstreamPath,
              ref: "main",
            },
          );
          const currentSha = (contents as { sha?: string }).sha;
          const verdict = classifyFileComparison(oldSha, currentSha);

          if (verdict === "error") {
            filesError += 1;
            logger.warn(
              {
                fn: "cron-content-vendor-drift",
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

          // Populate the classifier's stdin. This array was declared and
          // joined into `stdin` but NEVER written to (#7710), so the
          // classifier received an empty diff on every run, returned 0, and
          // the handler took the `classifyRc === 0` early return — which is
          // the SECOND `drift: "none"` site, reached AFTER drift was
          // detected. Categorising drift is the classifier's whole job and it
          // was being asked to categorise nothing.
          aggDiffParts.push(`${upstreamPath}\t${oldSha}\t${currentSha}`);

          logger.info(
            {
              fn: "cron-content-vendor-drift",
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

      if (!driftDetected && !driftFlags) {
        return {
          drift: "none" as const,
          route: "none" as const,
          labels: [] as string[],
          classifyRc: 0,
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

      logger.info(
        {
          fn: "cron-content-vendor-drift",
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
          ...totals,
        };
      }

      // Trust-model routing: security/license/rollback/renamed/archived
      // drift opens an ISSUE (no auto-PR). Auto-PR is reserved for
      // low-risk batched drift (exit 13).
      if (ISSUE_EXIT_CODES.has(classifyRc)) {
        return {
          drift: "detected" as const,
          route: "issue" as const,
          labels,
          classifyRc,
          ...totals,
        };
      }

      if (classifyRc === 13) {
        // Check for open drift PRs (idempotency). The prefix MUST track the
        // safeCommitAndPr-derived branch (`ci/content-vendor-drift-<ts>`,
        // #5111) — this guard is what suppresses duplicate drift PRs when a
        // direct merge failed and last week's PR is still open. (No old
        // `ci/vendor-drift-` transition match needed: the pre-#5111 PR route
        // never produced content, so no old-prefix PR can be open.)
        const { data: openPRs } = await octokit.request(
          "GET /search/issues",
          {
            q: `is:pr is:open repo:${REPO_OWNER}/${REPO_NAME} head:ci/content-vendor-drift-`,
            per_page: 5,
          },
        );
        if (openPRs.total_count > 0) {
          logger.info(
            { fn: "cron-content-vendor-drift" },
            "Skipping: open drift PR(s) already exist",
          );
          return {
            drift: "skipped-open-pr" as const,
            route: "none" as const,
            labels,
            classifyRc,
          ...totals,
          };
        }

        return {
          drift: "detected" as const,
          route: "pr" as const,
          labels,
          classifyRc,
          ...totals,
        };
      }

      // Unknown exit code — route to issue for human triage
      return {
        drift: "detected" as const,
        route: "issue" as const,
        labels,
        classifyRc,
          ...totals,
      };
    });

    // Route: open PR for low-risk drift. Persistence via safeCommitAndPr
    // (#5111) — gains the deletion guard (a large upstream restructure
    // deleting >10 files under references/ aborts loudly BY DESIGN; see the
    // runbook's DEFAULT_MAX_DELETIONS raise path), dirty-index precondition,
    // dropped-path warn, and replay idempotency. mergeMode "direct" +
    // synthetic checks preserves the production-proven merge mechanics.
    // Branch becomes ci/content-vendor-drift-<ts> (helper derivation,
    // renamed from ci/vendor-drift-<date> — NOT cosmetic: the detect step's
    // open-PR dedup query keys on this prefix and was updated in lockstep).
    if (detectResult.route === "pr") {
      await step.run("safe-commit-pr", async () =>
        safeCommitAndPr({
          spawnCwd: repoRoot,
          installationToken,
          cronName: "cron-content-vendor-drift",
          commitMessage:
            "chore(vendor-drift): re-vendor gosprinto/compliance-skills",
          allowedPaths: [`${SKILL_PREFIX}/NOTICE`, `${SKILL_PREFIX}/references/`],
          runStartedAt,
          scheduledIssueLabel: SENTRY_MONITOR_SLUG,
          // The sentence claiming the NOTICE freshness field was advanced at
          // PR-creation time was removed here (#7710). Nothing had done that
          // since the GHA workflow carrying the `sed` was deleted in #4483, so
          // this body asserted a bump on every drift PR it opened while the
          // field sat unchanged. The retired sentence is described rather than
          // quoted: the regression guard greps this file for it. `last-verified` is now advanced by the
          // attest-freshness step below, and ONLY on a verified-clean run —
          // which is deliberately not this path, since this path exists
          // because drift WAS found.
          prBody:
            "Automated re-vendor on upstream drift. Resolution path: knowledge-base/engineering/operations/runbooks/vendor-pin-drift-resolution.md. NOTICE last-verified is NOT advanced here — this PR exists because drift was detected; the field advances only on a verified-clean comparison. Classifier exit and labels set in commit metadata.",
          prLabels: detectResult.labels,
          syntheticChecks: {
            names: SYNTHETIC_CHECK_NAMES,
            summary: "Re-vendor on upstream drift detection — see runbook",
          },
          mergeMode: "direct",
          octokit,
          logger,
        }),
      );
    }

    // Route: open issue for security-relevant drift
    if (detectResult.route === "issue") {
      await step.run("open-drift-issue", async () => {
        const todayISO = new Date().toISOString().slice(0, 10);
        const title = `[vendor-drift] security-relevant drift on ${todayISO} (classifier rc=${detectResult.classifyRc})`;

        // Idempotency: check for existing open issue
        const { data: existing } = await octokit.request(
          "GET /search/issues",
          {
            q: `is:issue is:open repo:${REPO_OWNER}/${REPO_NAME} label:vendor/pin-drift "vendor-drift] security-relevant drift" in:title`,
            per_page: 5,
          },
        );
        if (existing.total_count > 0) {
          logger.info(
            { fn: "cron-content-vendor-drift" },
            "Existing open security-drift issue found; skipping",
          );
          return;
        }

        const body = [
          "Automated drift detection routed to issue-only (no auto-PR).",
          "",
          `**Classifier exit code:** \`${detectResult.classifyRc}\``,
          `**Labels:** \`${detectResult.labels.join(", ")}\``,
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

    // -- Freshness attestation (#7710) ------------------------------------
    //
    // `last-verified` in NOTICE is what the gdpr-gate hook reads to decide
    // whether its detection corpus is current. Nothing had advanced it since
    // the workflow carrying the `sed` was deleted in #4483: `git log -S` over
    // that field returns exactly one commit, the one that introduced it. The
    // field therefore aged from 2026-05-10 to 117 days stale while this cron
    // compared the corpus every week and found it clean the whole time.
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

    if (attestationEligible) {
      const attestation = await step.run("attest-freshness", async () => {
        const noticePath = join(repoRoot, NOTICE_FILE_REL);
        const before = await readFile(noticePath, "utf8");
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
        await writeFile(
          noticePath,
          before.replace(
            /^last-verified:[ \t]*\S+[ \t]*$/m,
            `last-verified: ${today}`,
          ),
          "utf8",
        );

        // Routed through safeCommitAndPr rather than a raw push: the helper
        // has no direct-to-branch mode (every path opens a PR against main),
        // and a raw push is independently blocked by the branch rulesets
        // whose relevant bypass actors are all `bypass_mode: "pull_request"`.
        // `mergeMode: "direct"` opens the PR and squash-merges it, which is
        // what the drift route already does, and inherits the allow-list, the
        // deletion guard and the replay idempotency a hand-rolled path would
        // discard.
        // Idempotency: do not stack attestation PRs. The 21-day suppression
        // reads `last-verified` from the freshly-cloned default branch, so an
        // unmerged PR is invisible to it — without this guard a stuck PR means
        // a NEW one every cadence, each self-merging, each editing the same
        // line and so mutually conflicting, on a CODEOWNERS-protected
        // compliance file (#7710 review).
        const { data: openAttestPRs } = await octokit.request(
          "GET /search/issues",
          {
            q: `is:pr is:open repo:${REPO_OWNER}/${REPO_NAME} head:${ATTEST_BRANCH_PREFIX}-`,
            per_page: 5,
          },
        );
        if (openAttestPRs.total_count > 0) {
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

        const res = await safeCommitAndPr({
          spawnCwd: repoRoot,
          installationToken,
          cronName: "cron-content-vendor-drift",
          // The squash commit that lands on `main` carries COMMIT_MESSAGES,
          // not the PR body (verified against the repo's
          // `squash_merge_commit_message` setting), so the evidence has to be
          // IN the commit message or it does not survive the merge — and
          // ADR-203's Art. 5(2) argument rests on the commit being the record.
          commitMessage: [
            `chore(vendor-drift): attest gosprinto/compliance-skills unchanged (${today})`,
            "",
            `Compared ${detectResult.filesExamined} of ${detectResult.registryCount} registered files, pinned at ${pinnedForBody}, against upstream main:`,
            `${detectResult.filesSame} SAME, ${detectResult.filesDrifted} drifted, ${detectResult.filesError} errors, repo-state ${detectResult.upstreamRepoState}.`,
            "",
            "Advances last-verified only; no vendored content is changed.",
          ].join("\n"),
          branchName: `${ATTEST_BRANCH_PREFIX}-${runStartedAt.replace(/[:.]/g, "-")}`,
          allowedPaths: [`${SKILL_PREFIX}/NOTICE`],
          runStartedAt,
          scheduledIssueLabel: SENTRY_MONITOR_SLUG,
          prBody: [
            "Automated freshness attestation.",
            "",
            `Compared ${detectResult.filesExamined} of ${detectResult.registryCount} registered files, pinned at \`${pinnedForBody}\`, against upstream \`main\`: ${detectResult.filesSame} SAME, ${detectResult.filesDrifted} drifted, ${detectResult.filesError} errors.`,
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
      });

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
    await step.run("attestation-summary", async () => {
      // WARN, not info. Measured: `logger.info` reaches no observability
      // layer — the Sentry breadcrumb mirror keeps >= warn
      // (SENTRY_BREADCRUMB_MIN_LEVEL) and the Vector pipeline drops pino
      // level < 40 — so an `info` line carrying the ADR-203 accountability
      // fields would exist only in a stream nothing ingests. This IS the
      // compliance record; it has to be queryable.
      logger.warn(
      {
        fn: "cron-content-vendor-drift",
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
        isHealthy: heartbeatOk(
          measurementFailed,
          attestationEligible,
          observedAgeDays,
        ),
      },
      "Vendor-drift attestation summary",
      );

      if (!heartbeatOk(measurementFailed, attestationEligible, observedAgeDays)) {
        reportSilentFallback(
          new Error(
            `Vendor-drift run is not healthy (outcome=${attestationOutcome}, age=${observedAgeDays ?? "unreadable"})`,
          ),
          {
            feature: "cron-content-vendor-drift",
            op: measurementFailed
              ? "comparison-could-not-measure"
              : "attestation-stale",
            // `pr` is load-bearing: on the ordinary `pr-open-not-merged` path
            // this is the ONLY Sentry event, and without it the operator
            // cannot tell "a PR is open and auto-merging" from "nothing was
            // created".
            message: `examined=${detectResult.filesExamined}/${detectResult.registryCount} drifted=${detectResult.filesDrifted} errors=${detectResult.filesError} repo=${detectResult.upstreamRepoState} outcome=${attestationOutcome} pr=${attestationPrNumber ?? "none"} age=${observedAgeDays ?? "unreadable"}`,
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
    const isHealthy = heartbeatOk(
      measurementFailed,
      attestationEligible,
      observedAgeDays,
    );

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
      status: detectResult.drift === "none" ? "no-drift" : detectResult.drift,
      route: detectResult.route,
      labels: detectResult.labels,
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
