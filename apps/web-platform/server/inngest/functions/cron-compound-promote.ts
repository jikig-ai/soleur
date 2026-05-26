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
import { mkdtemp, readFile, readdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, relative } from "node:path";
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

const SENTRY_MONITOR_SLUG = "scheduled-compound-promote";

export const MAX_RUN_DURATION_MS = 10 * 60 * 1000;
const TOKEN_MIN_LIFETIME_MS = 15 * 60 * 1000;

const WEEK_CAP_DEFAULT = 2;
export const MAX_DIFF_BYTES = 16384;
const MAX_ALWAYS_LOADED_BYTES = 18000;

export const TARGET_ALLOW_RE =
  /^(AGENTS\.core\.md|plugins\/soleur\/skills\/[A-Za-z0-9_-]+\/SKILL\.md)$/;

const BRANCH_SHAPE_RE =
  /^self-healing\/auto-[0-9a-f]{64}-[0-9]{4}-[0-9]{2}-[0-9]{2}$/;

export const ANTHROPIC_MODEL = "claude-sonnet-4-6";
export const ANTHROPIC_MAX_TOKENS = 16384;

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

export const SYNTHETIC_CHECK_NAMES = [
  "test",
  "dependency-review",
  "e2e",
  "skill-security-scan PR gate",
  "enforce",
  "cla-check",
  "cla-evidence",
] as const;

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

async function spawnGitChecked(
  args: string[],
  opts?: { cwd?: string },
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

async function setupEphemeralWorkspace(
  token: string,
): Promise<{ ephemeralRoot: string; repoRoot: string }> {
  const ephemeralRoot = await mkdtemp(
    join(tmpdir(), "soleur-cron-compound-promote-"),
  );
  const repoRoot = join(ephemeralRoot, "repo");
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
  const diffFile = join(tmpdir(), `compound-promote-diff-${Date.now()}.patch`);
  await writeFile(diffFile, diff);
  try {
    const check = await spawnGit(["apply", "--check", diffFile], {
      cwd: repoRoot,
    });
    if (check.exitCode !== 0) return false;
    await spawnGit(["apply", diffFile], { cwd: repoRoot });
    return true;
  } finally {
    await rm(diffFile, { force: true }).catch(() => {});
  }
}

// =============================================================================
// Handler
// =============================================================================

export async function cronCompoundPromoteHandler({
  step,
  logger,
}: HandlerArgs): Promise<HandlerResult> {
  let ephemeralRoot: string | null = null;
  let installationToken = "";

  try {
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

    if (corpus.entries.length === 0) {
      await step.run("sentry-heartbeat-ok-empty", () =>
        postSentryHeartbeat({ ok: true, sentryMonitorSlug: SENTRY_MONITOR_SLUG, cronName: "cron-compound-promote", logger }),
      );
      return { ok: true, status: "empty-corpus" };
    }

    // FR7/FR8: Anthropic cluster call (I3: wall-clock guard)
    const clusterResult = await step.run("anthropic-cluster", () => withTimeout(async () => {
      const apiKey = process.env.ANTHROPIC_API_KEY;
      if (!apiKey) throw new Error("ANTHROPIC_API_KEY not set");

      const agentsPath = join(repoRoot, "AGENTS.md");
      const agentsCorePath = join(repoRoot, "AGENTS.core.md");
      let alwaysLoadedNow = 0;
      if (existsSync(agentsPath)) alwaysLoadedNow += (await readFile(agentsPath)).length;
      if (existsSync(agentsCorePath)) alwaysLoadedNow += (await readFile(agentsCorePath)).length;

      const prompt = [
        `You are a clustering agent. Cluster the following learnings by problem/root-cause similarity. Return up to ${weekCapResult.remaining} qualifying clusters (each with >=5 source learnings) as a JSON array.`,
        `Schema: [{cluster_hash:'', tier:'skill'|'agents-core', target_path:string, source_learnings:[paths], proposed_diff_unified:string, rationale:string, byte_impact:{before:int,after:int,delta:int}}].`,
        `Apply AGENTS.md cq-agents-md-tier-gate: already-enforced -> skip; domain-scoped -> skill; cross-cutting -> agents-core targeting AGENTS.core.md.`,
        `Current always-loaded payload (AGENTS.md + AGENTS.core.md) is ${alwaysLoadedNow} bytes; the warn cap is ${MAX_ALWAYS_LOADED_BYTES} bytes.`,
        `target_path MUST be one of: AGENTS.core.md, plugins/soleur/skills/<skill-name>/SKILL.md. The workflow refuses any other path. cluster_hash is ignored (the workflow computes it).`,
        `Output ONLY the JSON array, nothing else.`,
      ].join("\n");

      const body = {
        model: ANTHROPIC_MODEL,
        max_tokens: ANTHROPIC_MAX_TOKENS,
        messages: [{ role: "user" as const, content: prompt + "\n\nCorpus:\n" + JSON.stringify(corpus.entries) }],
      };

      const resp = await fetch("https://api.anthropic.com/v1/messages", {
        method: "POST",
        headers: {
          "x-api-key": apiKey,
          "anthropic-version": "2023-06-01",
          "content-type": "application/json",
        },
        body: JSON.stringify(body),
      });

      if (!resp.ok) throw new Error(`Anthropic API ${resp.status}: ${resp.statusText}`);

      const data = (await resp.json()) as {
        content: Array<{ text?: string }>;
        stop_reason?: string;
      };

      if (data.stop_reason === "max_tokens") {
        logger.warn({ fn: "cron-compound-promote" }, "anthropic-response-truncated");
        return { clusters: [] as Cluster[], truncated: true };
      }

      const text = data.content?.[0]?.text;
      if (!text) {
        reportSilentFallback(new Error("Empty Anthropic response"), {
          feature: "cron-compound-promote",
          op: "anthropic-cluster",
          message: "Anthropic returned empty content",
        });
        return { clusters: [] as Cluster[], truncated: false };
      }

      let parsed: unknown;
      try {
        parsed = JSON.parse(text);
      } catch {
        reportSilentFallback(new Error("Malformed Anthropic JSON"), {
          feature: "cron-compound-promote",
          op: "anthropic-cluster",
          message: "Anthropic response is not valid JSON",
        });
        return { clusters: [] as Cluster[], truncated: false };
      }

      if (!Array.isArray(parsed)) {
        reportSilentFallback(new Error("Anthropic response is not array"), {
          feature: "cron-compound-promote",
          op: "anthropic-cluster-shape-invalid",
          message: "Anthropic response is not a JSON array",
        });
        return { clusters: [] as Cluster[], truncated: false };
      }

      return { clusters: (parsed as Cluster[]).slice(0, weekCapResult.remaining), truncated: false };
    }, MAX_RUN_DURATION_MS));

    if (clusterResult.clusters.length === 0 || clusterResult.truncated) {
      await step.run("sentry-heartbeat-ok-no-clusters", () =>
        postSentryHeartbeat({ ok: true, sentryMonitorSlug: SENTRY_MONITOR_SLUG, cronName: "cron-compound-promote", logger }),
      );
      return { ok: true, status: clusterResult.truncated ? "anthropic-truncated" : "no-qualifying-clusters" };
    }

    // FR9-FR18: apply clusters and open PRs
    let clustersOpened = 0;

    for (const cluster of clusterResult.clusters) {
      const clusterHash = computeClusterHash(cluster.source_learnings);
      const dateSuffix = new Date().toISOString().slice(0, 10);

      await step.run(`apply-and-pr-${clusterHash.slice(0, 8)}`, async () => {
        const octokit = new Octokit({ auth: installationToken });

        if (!TARGET_ALLOW_RE.test(cluster.target_path)) {
          logger.warn({ fn: "cron-compound-promote", path: cluster.target_path }, "target-path-refused");
          reportSilentFallback(new Error("target_path not in allowlist"), {
            feature: "cron-compound-promote", op: "target-path-refused",
            extra: { path: cluster.target_path },
          });
          return;
        }

        if (cluster.proposed_diff_unified.length > MAX_DIFF_BYTES) {
          logger.warn({ fn: "cron-compound-promote" }, "diff-size-exceeded");
          return;
        }

        const diffPaths = cluster.proposed_diff_unified
          .split("\n")
          .filter((l) => l.startsWith("+++ b/"))
          .map((l) => l.replace("+++ b/", ""));
        const badPath = diffPaths.find((p) => !TARGET_ALLOW_RE.test(p));
        if (badPath) {
          logger.warn({ fn: "cron-compound-promote", path: badPath }, "diff-path-refused");
          return;
        }

        if (cluster.target_path === "AGENTS.core.md" && diffRemovesHardRule(cluster.proposed_diff_unified)) {
          logger.warn({ fn: "cron-compound-promote", hash: clusterHash }, "agents-core-hr-rule-edit-refused");
          reportSilentFallback(new Error("Cluster proposes hr- rule edit"), {
            feature: "cron-compound-promote", op: "agents-core-hr-rule-edit-refused",
            extra: { cluster_hash: clusterHash },
          });
          return;
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
            logger.info({ fn: "cron-compound-promote", pr: firstPR.number }, "skill-conflict-guard-comment-posted");
            return;
          }
        }

        const branchName = `self-healing/auto-${clusterHash}-${dateSuffix}`;
        if (!BRANCH_SHAPE_RE.test(branchName)) {
          logger.warn({ fn: "cron-compound-promote", branch: branchName }, "branch-name-shape-failed");
          return;
        }

        const applied = await applyDiffToWorkspace(cluster.proposed_diff_unified, repoRoot);
        if (!applied) {
          logger.warn({ fn: "cron-compound-promote", hash: clusterHash }, "git-apply-check-failed");
          reportSilentFallback(new Error("git apply --check failed"), {
            feature: "cron-compound-promote", op: "git-apply-check-failed",
          });
          return;
        }

        // Post-apply byte budget check
        const agMd = join(repoRoot, "AGENTS.md");
        const agCore = join(repoRoot, "AGENTS.core.md");
        let postBytes = 0;
        if (existsSync(agMd)) postBytes += (await readFile(agMd)).length;
        if (existsSync(agCore)) postBytes += (await readFile(agCore)).length;
        if (postBytes > MAX_ALWAYS_LOADED_BYTES) {
          logger.warn({ fn: "cron-compound-promote", bytes: postBytes }, "byte-budget-overflow");
          reportSilentFallback(new Error("Post-apply byte budget exceeded"), {
            feature: "cron-compound-promote", op: "byte-budget-overflow",
            extra: { bytes: postBytes, cap: MAX_ALWAYS_LOADED_BYTES },
          });
          await spawnGit(["checkout", "--", "."], { cwd: repoRoot });
          return;
        }

        // Audit log row
        const logPath = join(repoRoot, "knowledge-base", "project", "learnings", "promotion-log.md");
        if (existsSync(logPath)) {
          const existing = await readFile(logPath, "utf-8");
          const row = `\n| ${dateSuffix} | ${clusterHash} | ${cluster.target_path} | ${cluster.source_learnings.length} | pending | ${cluster.tier} | (PR pending) |\n`;
          await writeFile(logPath, existing + row);
        }

        await spawnGitChecked(["add", cluster.target_path, "knowledge-base/project/learnings/promotion-log.md"], { cwd: repoRoot });
        await spawnGitChecked(["config", "user.name", "github-actions[bot]"], { cwd: repoRoot });
        await spawnGitChecked(["config", "user.email", "41898282+github-actions[bot]@users.noreply.github.com"], { cwd: repoRoot });
        await spawnGitChecked(["checkout", "-b", branchName], { cwd: repoRoot });

        const titleLine = `chore(self-healing): promote cluster ${clusterHash} to ${cluster.target_path}`;
        const trailer = [
          `Bot-Author: compound-promotion-loop@${process.env.GITHUB_SHA ?? "local"}`,
          `Source-Learnings: ${cluster.source_learnings.join(",")}`,
          `Threshold-Hit: ${cluster.source_learnings.length}/5`,
          `Cluster-Hash: ${clusterHash}`,
          `Tier: ${cluster.tier}`,
        ].join("\n");
        await spawnGitChecked(["commit", "-m", titleLine, "-m", trailer], { cwd: repoRoot });
        await spawnGitChecked(["push", "-u", "origin", branchName], { cwd: repoRoot });

        const prBody =
          `Promoted by compound-promotion-loop. Source learnings: ${cluster.source_learnings.join(" ")}. ` +
          `Tier: ${cluster.tier}. Cluster-Hash: ${clusterHash}. ` +
          `Reviewer: verify the diff respects cq-agents-md-tier-gate and cq-agents-md-why-single-line; ` +
          `merge to apply, close to reject.\n\nhuman review required`;

        const { data: pr } = await octokit.request("POST /repos/{owner}/{repo}/pulls", {
          owner: REPO_OWNER, repo: REPO_NAME,
          title: `self-healing(auto): promote cluster ${clusterHash} ${dateSuffix}`,
          body: prBody, base: "main", head: branchName, draft: true,
        });

        await octokit.request("POST /repos/{owner}/{repo}/issues/{issue_number}/labels", {
          owner: REPO_OWNER, repo: REPO_NAME, issue_number: pr.number,
          labels: ["self-healing/auto"],
        });

        // FR14: synthetic checks
        const commitSha = await spawnGitCapture(["rev-parse", "HEAD"], { cwd: repoRoot });

        for (const name of SYNTHETIC_CHECK_NAMES) {
          await octokit.request("POST /repos/{owner}/{repo}/check-runs", {
            owner: REPO_OWNER, repo: REPO_NAME, name, head_sha: commitSha,
            status: "completed", conclusion: "success",
            output: { title: "Bot PR", summary: "self-healing/auto promotion — operator review required" },
          });
        }

        await spawnGit(["checkout", "main"], { cwd: repoRoot });
        clustersOpened++;
      });
    }

    await step.run("sentry-heartbeat", () => postSentryHeartbeat({ ok: true, sentryMonitorSlug: SENTRY_MONITOR_SLUG, cronName: "cron-compound-promote", logger }));
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
