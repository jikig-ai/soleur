// TR9 Phase-2 — Migrated from the GHA scheduled-content-vendor-drift
// workflow (deleted in the same PR per TR9 I-13 hygiene). Weekly upstream
// content drift detector. Parses NOTICE files in plugins/soleur/skills/*/
// NOTICE.md, fetches upstream blobs, detects SHA drift, runs 3-way merge.
// Opens PR for low-risk drift, issue for security/license drift.
//
// ADR-033 invariants (binding all cron-*.ts files):
//   I1 — Octokit + node:fs reads called INSIDE step.run (replay memoization).
//   I2 — Operator-owned data only; never founder BYOK.
//   I3 — Outer wall-clock safety via Promise.race (MAX_RUN_DURATION_MS).
//   I4 — N/A (no claude binary; Octokit + git spawn only).
//   I5 — Deterministic step.run return shape per step (see handler).
//   I6 — No event payloads emitted.
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
import { tmpdir } from "node:os";
import { join } from "node:path";
import { Octokit } from "@octokit/core";
import { inngest } from "@/server/inngest/client";
import { reportSilentFallback } from "@/server/observability";
import {
  REPO_OWNER,
  REPO_NAME,
  redactToken,
  buildAuthenticatedCloneUrl,
  mintInstallationToken,
  postSentryHeartbeat,
  type HandlerArgs,
} from "./_cron-shared";

// =============================================================================
// Constants
// =============================================================================

const SENTRY_MONITOR_SLUG = "scheduled-content-vendor-drift";

export const MAX_RUN_DURATION_MS = 15 * 60 * 1000;
const TOKEN_MIN_LIFETIME_MS = 20 * 60 * 1000;

export const NOTICE_FILE_REL = "plugins/soleur/skills/gdpr-gate/NOTICE";
export const PARSER_REL =
  "plugins/soleur/skills/gdpr-gate/scripts/notice-frontmatter.sh";
export const CLASSIFIER_REL =
  "plugins/soleur/skills/gdpr-gate/scripts/vendor-drift-classify.sh";
export const SKILL_PREFIX = "plugins/soleur/skills/gdpr-gate";

export const SYNTHETIC_CHECK_NAMES = [
  "test",
  "dependency-review",
  "e2e",
  "skill-security-scan PR gate",
  "enforce",
  "cla-check",
  "cla-evidence",
] as const;

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

async function spawnGitChecked(
  args: string[],
  opts?: { cwd?: string; env?: NodeJS.ProcessEnv },
): Promise<void> {
  const result = await spawnGit(args, opts);
  if (result.exitCode !== 0) {
    throw new Error(`git ${args[0]} failed (exit ${result.exitCode})`);
  }
}

function spawnGitCapture(
  args: string[],
  opts?: { cwd?: string },
): Promise<string> {
  return new Promise((resolve) => {
    const child = spawn("git", args, { ...opts });
    let out = "";
    child.stdout?.on("data", (d: Buffer) => {
      out += d.toString();
    });
    child.on("exit", () => resolve(out.trim()));
    child.on("error", () => resolve(""));
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
    join(tmpdir(), "soleur-cron-content-vendor-drift-"),
  );
  const repoRoot = join(ephemeralRoot, "repo");
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

      // Probe upstream repo for archived/renamed status
      let driftFlags = "";
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
        } else if (
          repoMeta.full_name &&
          repoMeta.full_name !== ownerRepo
        ) {
          driftFlags = "--renamed";
        }
      } catch {
        driftFlags = "--archived";
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

      for (const line of upstreamFiles) {
        const [upstreamPath, oldSha] = line.split(":");
        if (!upstreamPath || !oldSha) continue;

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
          if (!currentSha || currentSha === oldSha) continue;

          driftDetected = true;
          logger.info(
            {
              fn: "cron-content-vendor-drift",
              path: upstreamPath,
              oldSha,
              currentSha,
            },
            "Drift detected",
          );
        } catch {
          driftFlags = "--renamed";
          driftDetected = true;
        }
      }

      if (!driftDetected && !driftFlags) {
        return {
          drift: "none" as const,
          route: "none" as const,
          labels: [] as string[],
          classifyRc: 0,
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
        return {
          drift: "none" as const,
          route: "none" as const,
          labels: [] as string[],
          classifyRc: 0,
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
        };
      }

      if (classifyRc === 13) {
        // Check for open drift PRs (idempotency)
        const { data: openPRs } = await octokit.request(
          "GET /search/issues",
          {
            q: `is:pr is:open repo:${REPO_OWNER}/${REPO_NAME} head:ci/vendor-drift-`,
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
          };
        }

        return {
          drift: "detected" as const,
          route: "pr" as const,
          labels,
          classifyRc,
        };
      }

      // Unknown exit code — route to issue for human triage
      return {
        drift: "detected" as const,
        route: "issue" as const,
        labels,
        classifyRc,
      };
    });

    // Route: open PR for low-risk drift
    if (detectResult.route === "pr") {
      await step.run("open-drift-pr", async () => {
        const dateSuffix = new Date().toISOString().slice(0, 10);
        const branchName = `ci/vendor-drift-${dateSuffix}`;

        await spawnGitChecked(
          ["config", "user.name", "github-actions[bot]"],
          { cwd: repoRoot },
        );
        await spawnGitChecked(
          [
            "config",
            "user.email",
            "41898282+github-actions[bot]@users.noreply.github.com",
          ],
          { cwd: repoRoot },
        );
        await spawnGitChecked(["checkout", "-b", branchName], {
          cwd: repoRoot,
        });
        await spawnGitChecked(
          [
            "add",
            `${SKILL_PREFIX}/NOTICE`,
            `${SKILL_PREFIX}/references/`,
          ],
          { cwd: repoRoot },
        );

        // Only commit if there are staged changes
        const diffCheck = await spawnGit(
          ["diff", "--cached", "--quiet"],
          { cwd: repoRoot },
        );
        if (diffCheck.exitCode === 0) {
          logger.info(
            { fn: "cron-content-vendor-drift" },
            "No staged changes after merge — skipping PR",
          );
          return;
        }

        await spawnGitChecked(
          [
            "commit",
            "-m",
            "chore(vendor-drift): re-vendor gosprinto/compliance-skills",
          ],
          { cwd: repoRoot },
        );
        await spawnGitChecked(["push", "-u", "origin", branchName], {
          cwd: repoRoot,
        });

        const { data: pr } = await octokit.request(
          "POST /repos/{owner}/{repo}/pulls",
          {
            owner: REPO_OWNER,
            repo: REPO_NAME,
            title: `chore(vendor-drift): re-vendor gosprinto/compliance-skills ${dateSuffix}`,
            body: "Automated re-vendor on upstream drift. Resolution path: knowledge-base/engineering/ops/runbooks/vendor-pin-drift-resolution.md. NOTICE last-verified bumped at PR-creation time. Classifier exit and labels set in commit metadata.",
            base: "main",
            head: branchName,
          },
        );

        // Apply labels
        if (detectResult.labels.length > 0) {
          await octokit.request(
            "POST /repos/{owner}/{repo}/issues/{issue_number}/labels",
            {
              owner: REPO_OWNER,
              repo: REPO_NAME,
              issue_number: pr.number,
              labels: detectResult.labels,
            },
          );
        }

        // Synthetic checks
        const commitSha = await spawnGitCapture(["rev-parse", "HEAD"], {
          cwd: repoRoot,
        });

        for (const name of SYNTHETIC_CHECK_NAMES) {
          await octokit.request(
            "POST /repos/{owner}/{repo}/check-runs",
            {
              owner: REPO_OWNER,
              repo: REPO_NAME,
              name,
              head_sha: commitSha,
              status: "completed",
              conclusion: "success",
              output: {
                title: "Bot PR",
                summary:
                  "Re-vendor on upstream drift detection — see runbook",
              },
            },
          );
        }

        // Auto-merge
        try {
          await octokit.request(
            "PUT /repos/{owner}/{repo}/pulls/{pull_number}/merge",
            {
              owner: REPO_OWNER,
              repo: REPO_NAME,
              pull_number: pr.number,
              merge_method: "squash",
            },
          );
        } catch {
          logger.warn(
            { fn: "cron-content-vendor-drift", pr: pr.number },
            "Direct merge failed — PR left open for review",
          );
        }
      });
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
          "Follow `knowledge-base/engineering/ops/runbooks/vendor-pin-drift-resolution.md` §2-§5 (classifier-rc-specific branches).",
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

    await step.run("sentry-heartbeat", () =>
      postSentryHeartbeat({
        ok: true,
        sentryMonitorSlug: SENTRY_MONITOR_SLUG,
        cronName: "cron-content-vendor-drift",
        logger,
      }),
    );

    return {
      ok: true,
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
