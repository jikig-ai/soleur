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
import { join, relative } from "node:path";
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
// #6794: third byte-identical impl of the frontmatter-strip contract (SPEC.md /
// #5999 / ADR-094). Imported here so the always-loaded byte budget is measured
// on the SAME frontmatter-stripped basis the commit gate uses.
import { stripFrontmatter } from "../../../../../scripts/lib/frontmatter-strip/strip";

// =============================================================================
// Constants
// =============================================================================

const SENTRY_MONITOR_SLUG = "scheduled-compound-promote";

export const MAX_RUN_DURATION_MS = 10 * 60 * 1000;
const TOKEN_MIN_LIFETIME_MS = 15 * 60 * 1000;

const WEEK_CAP_DEFAULT = 2;
export const MAX_DIFF_BYTES = 16384;

// Always-loaded (AGENTS.md + AGENTS.core.md) byte budgets.
//
// Source of truth: scripts/lint-agents-rule-budget.py (B_ALWAYS_REJECT /
// B_ALWAYS_WARN). Agreement across every restatement site is enforced by
// scripts/lint-agents-compound-sync.sh — change a value here without changing
// the linter (or vice versa) and that guard fails the build. Do not edit either
// side alone; that de-sync is what issue #6461 was filed for.
//
// UNIT (unit-exact, #6794): both measurement sites below run through
// measureAlwaysLoadedBytes, which measures on the FRONTMATTER-STRIPPED basis —
// the SAME basis the linter's thresholds are defined over
// (scripts/lint-agents-rule-budget.py: b_index raw + b_core stripped). The
// previously-documented raw-vs-stripped skew (~73 B, the frontmatter block on
// AGENTS.core.md) is closed; the comparison is exact, not merely fail-safe. The
// over-strip guard inside the helper keeps the DANGEROUS (falsely-smaller)
// direction fail-safe by falling back to RAW bytes if a malformed strip drops a
// rule line.
//
// Hard ceiling for the POST-APPLY gate: mirrors the commit gate exactly, so an
// applied diff that would be rejected at commit time is reverted here instead.
// Per ADR-092 / AP-017 this byte cap is the only VOLUMETRIC brake on the
// additive envelope of the harness self-edit path, so it must track the real
// ceiling rather than sit at an arbitrary lower value.
const MAX_ALWAYS_LOADED_BYTES = 23000;

// Budget the clustering LLM is told to propose against. Deliberately the WARN
// floor, not the reject ceiling: the promoter's job is not "propose anything the
// gate would not reject" — it is "propose something that leaves headroom" for the
// next promotion and for hand-authored rules. Binding this to the reject ceiling
// would let a cluster land at exactly the cap and pin the registry there.
const PROPOSE_ALWAYS_LOADED_BUDGET = 20000;

// #6794: measure the always-loaded (AGENTS.md + AGENTS.core.md) payload on the
// FRONTMATTER-STRIPPED basis, matching the commit gate's authority
// (scripts/lint-agents-rule-budget.py: b_index raw + b_core stripped). The strip
// is a no-op on AGENTS.md (no leading `---`), so applying it uniformly to both
// files reproduces the authority exactly. Extracted + exported so the
// promoter-vs-B_ALWAYS invariant is unit-testable without invoking the handler.
//
// OVER-STRIP GUARD (the DANGEROUS direction): a malformed/unterminated `---`
// consumes AGENTS.core.md to EMPTY → a falsely-SMALLER byte count that could
// falsely PASS the cap. Mirrors the linter's guard: if the strip drops any
// `- …[id: …]` rule line, fall back to RAW bytes (fail-safe) + emit a distinct
// Sentry signal. The anchored regex matches lint-agents-rule-budget.py's
// `_RULE_LINE_RE = ^- .*\[id: ` line-for-line.
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
 * Always-loaded byte total on the frontmatter-stripped basis (#6794). Pass the
 * raw UTF-8 text of AGENTS.md and AGENTS.core.md; a missing file is passed as
 * "" (→ 0 bytes), preserving the prior existsSync-guarded behavior.
 */
export function measureAlwaysLoadedBytes(
  indexText: string,
  coreText: string,
): number {
  return (
    measureFileStrippedBytes(indexText, "AGENTS.md") +
    measureFileStrippedBytes(coreText, "AGENTS.core.md")
  );
}

export const TARGET_ALLOW_RE =
  /^(AGENTS\.core\.md|plugins\/soleur\/skills\/[A-Za-z0-9_-]+\/SKILL\.md)$/;

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
    await spawnGit(["apply", diffFile], { cwd: repoRoot });
    return true;
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
}: HandlerArgs): Promise<HandlerResult> {
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
      const indexText = existsSync(agentsPath)
        ? await readFile(agentsPath, "utf8")
        : "";
      const coreText = existsSync(agentsCorePath)
        ? await readFile(agentsCorePath, "utf8")
        : "";
      const alwaysLoadedNow = measureAlwaysLoadedBytes(indexText, coreText);

      const prompt = [
        `You are a clustering agent. Cluster the following learnings by problem/root-cause similarity. Return up to ${weekCapResult.remaining} qualifying clusters (each with >=5 source learnings).`,
        `Schema: {clusters:[{cluster_hash:'', tier:'skill'|'agents-core', target_path:string, source_learnings:[paths], proposed_diff_unified:string, rationale:string, byte_impact:{before:int,after:int,delta:int}}]}.`,
        `Apply AGENTS.md cq-agents-md-tier-gate: already-enforced -> skip; domain-scoped -> skill; cross-cutting -> agents-core targeting AGENTS.core.md.`,
        `Current always-loaded payload (AGENTS.md + AGENTS.core.md) is ${alwaysLoadedNow} bytes; propose against a budget of ${PROPOSE_ALWAYS_LOADED_BUDGET} bytes (the warn floor — leave headroom, do not aim for the hard ceiling).`,
        `target_path MUST be one of: AGENTS.core.md, plugins/soleur/skills/<skill-name>/SKILL.md. The workflow refuses any other path. cluster_hash is ignored (the workflow computes it).`,
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
      return { ok: true, status: clusterResult.truncated ? "anthropic-truncated" : "no-qualifying-clusters" };
    }

    // FR9-FR18: apply clusters and open PRs
    let clustersOpened = 0;

    for (const cluster of clusterResult.clusters) {
      const clusterHash = computeClusterHash(cluster.source_learnings);
      // Derived from the MEMOIZED run start, never a fresh Date — the branch
      // name embeds this suffix and the helper's replay-resume is keyed on
      // the branch, so a replay crossing UTC midnight must not re-key it.
      const dateSuffix = runStartedAt.slice(0, 10);

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

        // Post-apply byte budget check (frontmatter-stripped basis, #6794 —
        // mirrors the commit gate exactly).
        const agMd = join(repoRoot, "AGENTS.md");
        const agCore = join(repoRoot, "AGENTS.core.md");
        const postIndexText = existsSync(agMd)
          ? await readFile(agMd, "utf8")
          : "";
        const postCoreText = existsSync(agCore)
          ? await readFile(agCore, "utf8")
          : "";
        const postBytes = measureAlwaysLoadedBytes(postIndexText, postCoreText);
        if (postBytes > MAX_ALWAYS_LOADED_BYTES) {
          logger.warn({ fn: "cron-compound-promote", bytes: postBytes }, "byte-budget-overflow");
          reportSilentFallback(new Error("Post-apply byte budget exceeded"), {
            feature: "cron-compound-promote", op: "byte-budget-overflow",
            extra: { bytes: postBytes, cap: MAX_ALWAYS_LOADED_BYTES },
          });
          await spawnGit(["checkout", "--", "."], { cwd: repoRoot });
          return;
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
        if (result.status === "committed") clustersOpened++;
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
