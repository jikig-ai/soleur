// TR9 PR-6 (closes #4416) — Migrated from the GHA scheduled-strategy-review
// workflow (deleted in the same PR per TR9 I-13 hygiene). Pure TS port —
// scripts/strategy-review-check.sh remains on disk for operator-local
// hand-testing but is NOT the runtime contract (gh CLI absent from
// Hetzner Dockerfile per deepen-pass verification).
//
// ADR-033 invariants (binding all cron-*.ts files):
//   I1 — Octokit + node:fs reads called INSIDE step.run (Inngest replay
//        memoization). No claude-eval spawn (PR-6 is the first TR9 child
//        with no agent spawn — pure TS port). One `git clone` spawn lives
//        in setupEphemeralWorkspace; that is the ONLY child_process.spawn
//        call in this file.
//   I2 — Operator-owned data only; never founder BYOK. Structurally
//        satisfied — no SDK call. Auto-asserted by
//        test/server/cron-no-byok-lease-sweep.test.ts via cron-*.ts glob.
//   I3 — Outer step.run carries no AbortSignal for an agent spawn (none
//        exists). Outer wall-clock safety enforced via Promise.race
//        against MAX_RUN_DURATION_MS in the strategy-review-check step.
//   I4 — N/A (no claude binary resolution; pure Node.js + Octokit).
//   I5 — Deterministic step.run return shape per step (see handler).
//   I6 — Event payloads emitted by this handler MUST carry actor: "platform".
//        (This handler emits none.)
//
// NAME NOTE: Sentry monitor slug "scheduled-strategy-review" is NEW — the
// GHA predecessor had NO Sentry check-in. The resource was added to
// cron-monitors.tf in the same commit. It also needed a matching
// apply-sentry-infra.yml `-target=` line at the time; that requirement is gone
// since #6589 made the apply full-root, so declaring a monitor now applies it.
//
// PURE-TS PATTERN — PR-6 is the first TR9 child with ZERO agent spawn
// (no claude-eval, no bash script invocation). All GH ops via Octokit;
// file reads via node:fs/promises against the cloned workspace. See
// learning 2026-05-25-tr9-pr6-strategy-review-no-bash-spawn-octokit-port-pattern.md.
//
// CONTRACT DIVERGENCE: this file replaces the bash script's exit-code
// contract. The contract is now `result.errors === 0 ⇒ ok: true`. The
// `parseISODate` regex is STRICTER than bash `date -d` (only YYYY-MM-DD);
// docs with non-strict `last_reviewed` shapes are treated as malformed
// (errors++). The bash script accepted more forms via `date -d` coercion.

import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { lstat, mkdtemp, readFile, readdir, rm } from "node:fs/promises";
import { join } from "node:path";
import type { Octokit } from "@octokit/core";
import matter from "gray-matter";
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

// =============================================================================
// Constants
// =============================================================================

const SENTRY_MONITOR_SLUG = "scheduled-strategy-review";

// 10 min outer wall-clock budget. GHA's timeout-minutes was 5; 10 doubles
// it for safety against transient GitHub API retries. Past runs complete
// in <30s (≤20 strategy docs scanned, ≤5 issues created). Enforced via
// Promise.race wrapping the strategy-review step.run callback.
export const MAX_RUN_DURATION_MS = 10 * 60 * 1000;

// Installation-token lifetime floor: 10-min outer budget + 5-min headroom.
// Smaller than PR-5's 60-min floor because there is no claude-eval spawn.
const TOKEN_MIN_LIFETIME_MS = 15 * 60 * 1000;

// Strategy-review-check.sh contract constants (1:1 port).
const REVIEW_LABEL = "scheduled-strategy-review";
const ISSUE_MILESTONE_TITLE = "Post-MVP / Later";
const STRATEGY_DIRS = [
  "knowledge-base/product",
  "knowledge-base/marketing",
  "knowledge-base/sales/battlecards",
] as const;
const CADENCE_DAYS: Record<string, number> = {
  weekly: 7,
  monthly: 30,
  quarterly: 90,
  biannual: 180,
  annual: 365,
};

// =============================================================================
// Types
// =============================================================================

interface ReviewResult {
  created: number;
  skipped: number;
  upToDate: number;
  errors: number;
}

// =============================================================================
// Helpers — workspace lifecycle
// =============================================================================

// Scaffold the ephemeral workspace: `git clone --depth=1` into a tmp dir
// and sentinel-check at least one of the strategy-doc directories exists.
// No plugin symlink (PR-6 spawns no claude). No `.claude/settings.json`
// overlay. The ONLY child_process.spawn in this file is the `git clone`
// call below — verified by AC3b grep.
async function setupEphemeralWorkspace(token: string): Promise<{
  ephemeralRoot: string;
  repoRoot: string;
}> {
  const ephemeralRoot = await mkdtemp(
    join(resolveCronWorkspaceRoot(), "soleur-cron-strategy-review-"),
  );
  const repoRoot = join(ephemeralRoot, "repo");
  await warnIfCronWorkspaceLowOnDisk(ephemeralRoot, "cron-strategy-review");
  const cloneUrl = buildAuthenticatedCloneUrl(token);
  const cloneResult = await new Promise<{
    exitCode: number | null;
    signal: NodeJS.Signals | null;
  }>((resolve) => {
    const child = spawn("git", ["clone", "--depth=1", cloneUrl, repoRoot], {
      stdio: "ignore",
    });
    child.on(
      "exit",
      (exitCode: number | null, signal: NodeJS.Signals | null) => {
        resolve({ exitCode, signal });
      },
    );
    child.on("error", () => {
      resolve({ exitCode: -1, signal: null });
    });
  });
  if (cloneResult.exitCode !== 0) {
    // DO NOT include cloneUrl — contains the token.
    throw new Error(
      `git clone failed (exit ${cloneResult.exitCode}, signal ${cloneResult.signal}) for ${REPO_OWNER}/${REPO_NAME}`,
    );
  }
  // Sentinel: at least one of the three strategy-doc directories must
  // exist post-clone. If all three are missing, knowledge-base/ was
  // reorganized and this cron's source-of-truth has drifted.
  const dirHits = await Promise.all(
    STRATEGY_DIRS.map(async (rel) => existsSync(join(repoRoot, rel))),
  );
  if (!dirHits.some(Boolean)) {
    throw new Error(
      `Sentinel: none of [${STRATEGY_DIRS.join(", ")}] exist after clone — knowledge-base/ may have been reorganized`,
    );
  }
  return { ephemeralRoot, repoRoot };
}

// Best-effort teardown of the ephemeral workspace. Failures are mirrored
// to Sentry but never propagated — a stranded /tmp dir is acceptable
// degraded state, throwing here would mask the upstream result.
async function teardownEphemeralWorkspace(
  ephemeralRoot: string | null,
): Promise<void> {
  if (!ephemeralRoot) return;
  try {
    await rm(ephemeralRoot, { recursive: true, force: true });
  } catch (err) {
    reportSilentFallback(err, {
      feature: "cron-strategy-review",
      op: "teardown-ephemeral-workspace",
      message: "Failed to remove ephemeral workspace",
      extra: { fn: "cron-strategy-review", ephemeralRoot },
    });
  }
}

// =============================================================================
// TS port of scripts/strategy-review-check.sh
//
// Faithful port preserves the script's contract:
//   - Scan knowledge-base/{product,marketing,sales/battlecards}/*.md (maxdepth 1).
//   - Parse YAML frontmatter for `review_cadence` (weekly|monthly|quarterly
//     |biannual|annual) + `last_reviewed` (YYYY-MM-DD or missing → immediately
//     stale).
//   - Skip docs not due within 7 days.
//   - Dedup via GET /repos/{owner}/{repo}/issues?labels=scheduled-strategy-review
//     against title "Strategy Review: {scope}/{slug}".
//   - Create issue with milestone "Post-MVP / Later" (resolve title→number
//     via GET /repos/{owner}/{repo}/milestones?state=open first).
//   - Return counts: created / skipped / up_to_date / errors. errors>0 → ok=false.
// =============================================================================

async function ensureReviewLabel(octokit: Octokit): Promise<void> {
  try {
    await octokit.request("POST /repos/{owner}/{repo}/labels", {
      owner: REPO_OWNER,
      repo: REPO_NAME,
      name: REVIEW_LABEL,
      description: "Strategy document review is overdue",
      color: "0E8A16",
    });
  } catch (err) {
    // 422 already-exists is the idempotent path; swallow (matches script's
    // `gh label create … 2>/dev/null || true` semantic).
    const status = (err as { status?: number }).status;
    if (status !== 422) {
      reportSilentFallback(err, {
        feature: "cron-strategy-review",
        op: "ensure-label",
        message: "Failed to create scheduled-strategy-review label",
        extra: { fn: "cron-strategy-review", status },
      });
    }
  }
}

// Script uses `--milestone "Post-MVP / Later"` (title); Octokit REST
// requires the integer number. Resolve title→number; on miss, log to
// Sentry and return undefined so issue creation proceeds without
// milestone (matches script's `|| true` fallback).
async function resolveMilestoneNumber(
  octokit: Octokit,
): Promise<number | undefined> {
  try {
    const resp = (await octokit.request(
      "GET /repos/{owner}/{repo}/milestones",
      {
        owner: REPO_OWNER,
        repo: REPO_NAME,
        state: "open",
        per_page: 100,
      },
    )) as { data: Array<{ number: number; title: string }> };
    return resp.data.find((m) => m.title === ISSUE_MILESTONE_TITLE)?.number;
  } catch (err) {
    reportSilentFallback(err, {
      feature: "cron-strategy-review",
      op: "resolve-milestone",
      message: `Failed to resolve milestone "${ISSUE_MILESTONE_TITLE}"`,
      extra: { fn: "cron-strategy-review" },
    });
    return undefined;
  }
}

// Script: gh issue list --label LABEL --state open --json title.
// Pagination: per_page=100; corpus is small (<20 open per fire), but guard
// against future growth by paginating until an empty page or a short page.
async function listExistingReviewIssueTitles(
  octokit: Octokit,
): Promise<Set<string>> {
  const titles = new Set<string>();
  let page = 1;
  // Cap pagination at 10 pages (1000 issues) as a defensive runaway-guard.
  for (let i = 0; i < 10; i++) {
    const resp = (await octokit.request("GET /repos/{owner}/{repo}/issues", {
      owner: REPO_OWNER,
      repo: REPO_NAME,
      state: "open",
      labels: REVIEW_LABEL,
      per_page: 100,
      page,
    })) as { data: Array<{ title: string }> };
    if (resp.data.length === 0) break;
    for (const issue of resp.data) titles.add(issue.title);
    if (resp.data.length < 100) break;
    page++;
  }
  return titles;
}

// Script: find <dir> -maxdepth 1 -name '*.md' -type f
export async function collectStrategyFiles(
  repoRoot: string,
): Promise<string[]> {
  const files: string[] = [];
  for (const rel of STRATEGY_DIRS) {
    const abs = join(repoRoot, rel);
    let entries: string[] = [];
    try {
      entries = await readdir(abs);
    } catch {
      continue;
    }
    for (const name of entries) {
      if (!name.endsWith(".md")) continue;
      const fullPath = join(abs, name);
      try {
        // lstat (not stat) so symlinks are visible as symlinks; skip them
        // to prevent a malicious commit on main planting a symlink to
        // /etc/passwd or similar and triggering readFile follow-through.
        const s = await lstat(fullPath);
        if (s.isSymbolicLink()) continue;
        if (s.isFile()) files.push(fullPath);
      } catch {
        // skip — file disappeared between readdir and lstat
      }
    }
  }
  return files;
}

// Script: date -d "$last_reviewed" +%s — accepts YYYY-MM-DD plus other
// forms. Restrict TS port to strict YYYY-MM-DD; if a doc uses non-strict
// date, treat as malformed (script's "invalid last_reviewed" branch).
// Use Date.parse for the strict shape since YYYY-MM-DD parses
// unambiguously as UTC midnight.
export function parseISODate(s: string): number | null {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(s)) return null;
  const t = Date.parse(`${s}T00:00:00Z`);
  return Number.isNaN(t) ? null : t;
}

// gray-matter parses YAML 1.1, which coerces unquoted ISO dates
// (`last_reviewed: 2026-05-25`) into JavaScript `Date` objects, NOT strings.
// Every strategy doc in knowledge-base/ uses the unquoted form, so the raw
// frontmatter value is virtually always a `Date`. Coerce both shapes to a
// strict `YYYY-MM-DD` string so parseISODate accepts them. Returns undefined
// for missing/null and the literal raw string for unrecognized shapes (which
// will then fail parseISODate and route into the "invalid last_reviewed"
// errors++ branch — matching bash's `date -d` failure path).
export function coerceFrontmatterDate(raw: unknown): string | undefined {
  if (raw === undefined || raw === null) return undefined;
  if (raw instanceof Date) {
    if (Number.isNaN(raw.getTime())) return undefined;
    return raw.toISOString().slice(0, 10);
  }
  return String(raw);
}

async function runStrategyReview(args: {
  octokit: Octokit;
  repoRoot: string;
  todayISO: string;
  logger: HandlerArgs["logger"];
}): Promise<ReviewResult> {
  const { octokit, repoRoot, todayISO, logger } = args;
  const result: ReviewResult = {
    created: 0,
    skipped: 0,
    upToDate: 0,
    errors: 0,
  };

  const todayEpochMs = parseISODate(todayISO);
  if (todayEpochMs === null) {
    throw new Error(`Invalid today date: ${todayISO}`);
  }

  await ensureReviewLabel(octokit);
  const milestoneNumber = await resolveMilestoneNumber(octokit);
  const existingTitles = await listExistingReviewIssueTitles(octokit);
  const files = await collectStrategyFiles(repoRoot);
  if (files.length === 0) {
    logger.info({ fn: "cron-strategy-review" }, "No strategy documents found");
    return result;
  }

  logger.info(
    { fn: "cron-strategy-review", count: files.length },
    "Scanning strategy documents",
  );

  for (const filePath of files) {
    let raw: string;
    try {
      raw = await readFile(filePath, "utf-8");
    } catch (err) {
      reportSilentFallback(err, {
        feature: "cron-strategy-review",
        op: "read-file",
        message: `Failed to read ${filePath}`,
        extra: { fn: "cron-strategy-review", filePath },
      });
      result.errors++;
      continue;
    }

    let parsed: ReturnType<typeof matter>;
    try {
      parsed = matter(raw);
    } catch (err) {
      logger.warn(
        { fn: "cron-strategy-review", filePath, err: (err as Error).message },
        "Skipping: failed to parse frontmatter",
      );
      result.errors++;
      continue;
    }

    const cadence = parsed.data.review_cadence as string | undefined;
    if (!cadence) continue; // no cadence → not a tracked strategy doc

    const cadenceDays = CADENCE_DAYS[cadence];
    if (!cadenceDays) {
      logger.warn(
        { fn: "cron-strategy-review", filePath, cadence },
        "Skipping: unknown review_cadence",
      );
      result.errors++;
      continue;
    }

    const lastReviewed = coerceFrontmatterDate(parsed.data.last_reviewed);
    let daysUntil: number;
    let lastEpochMs: number | null = null;
    if (!lastReviewed) {
      daysUntil = -1;
    } else {
      lastEpochMs = parseISODate(lastReviewed);
      if (lastEpochMs === null) {
        logger.warn(
          { fn: "cron-strategy-review", filePath, lastReviewed },
          "Skipping: invalid last_reviewed",
        );
        result.errors++;
        continue;
      }
      const nextDueEpochMs = lastEpochMs + cadenceDays * 86400 * 1000;
      daysUntil = Math.floor((nextDueEpochMs - todayEpochMs) / (86400 * 1000));
    }

    if (daysUntil > 7) {
      result.upToDate++;
      continue;
    }

    // Script: slug=${file#knowledge-base/}; slug=${slug%.md}
    const kbIdx = filePath.indexOf("knowledge-base/");
    const relFromKb =
      kbIdx >= 0
        ? filePath.substring(kbIdx + "knowledge-base/".length)
        : filePath;
    const slug = relFromKb.replace(/\.md$/, "");
    const expectedTitle = `Strategy Review: ${slug}`;

    if (existingTitles.has(expectedTitle)) {
      logger.info(
        { fn: "cron-strategy-review", slug },
        "Skipping: open issue already exists",
      );
      result.skipped++;
      continue;
    }

    const ownerRaw = parsed.data.owner;
    const owner =
      ownerRaw === undefined || ownerRaw === null
        ? undefined
        : String(ownerRaw);

    const reviewDue =
      lastEpochMs !== null
        ? new Date(lastEpochMs + cadenceDays * 86400 * 1000)
            .toISOString()
            .slice(0, 10)
        : "immediately (no last_reviewed set)";

    const repoUrl = `https://github.com/${REPO_OWNER}/${REPO_NAME}`;
    const fileRel = kbIdx >= 0 ? filePath.substring(kbIdx) : filePath;
    const fileLink = `${repoUrl}/blob/main/${fileRel}`;
    const body =
      `## Strategy Review Due: ${slug}\n\n` +
      `**Review due:** ${reviewDue}\n` +
      `**Last reviewed:** ${lastReviewed ?? "never"}\n` +
      `**Cadence:** ${cadence}\n` +
      `**Owner:** ${owner ?? "unassigned"}\n` +
      `**Source:** [${fileRel}](${fileLink})\n\n` +
      `When complete:\n` +
      `- [ ] Review the document for accuracy and relevance\n` +
      `- [ ] Update \`last_reviewed\` to today's date in the YAML frontmatter\n` +
      `- [ ] Update \`last_updated\` if content was changed\n` +
      `- [ ] Check \`depends_on\` documents for upstream changes since last review\n` +
      `- [ ] Close this issue\n\n` +
      `_Auto-created by the [scheduled-strategy-review Inngest function](${repoUrl}/blob/main/apps/web-platform/server/inngest/functions/cron-strategy-review.ts)._`;

    try {
      await octokit.request("POST /repos/{owner}/{repo}/issues", {
        owner: REPO_OWNER,
        repo: REPO_NAME,
        title: expectedTitle,
        body,
        labels: [REVIEW_LABEL],
        ...(milestoneNumber !== undefined
          ? { milestone: milestoneNumber }
          : {}),
      });
      logger.info(
        { fn: "cron-strategy-review", title: expectedTitle },
        "Created issue",
      );
      result.created++;
    } catch (err) {
      reportSilentFallback(err, {
        feature: "cron-strategy-review",
        op: "create-issue",
        message: `Failed to create issue for ${slug}`,
        extra: { fn: "cron-strategy-review", slug, title: expectedTitle },
      });
      result.errors++;
    }
  }

  return result;
}

// =============================================================================
// Handler — 4 step.run blocks: mint-installation-token → setup-workspace
// → strategy-review-check → sentry-heartbeat (+ finally:teardown)
// =============================================================================

export async function cronStrategyReviewHandler({
  event,
  step,
  logger,
}: HandlerArgs): Promise<{
  ok: boolean;
  created: number;
  skipped: number;
  upToDate: number;
  errors: number;
}> {
  // --- Parse manual-trigger date_override; validate YYYY-MM-DD shape ---
  let dateOverride: string | undefined;
  const rawOverride = event?.data?.date_override;
  if (rawOverride !== undefined && rawOverride !== null) {
    if (
      typeof rawOverride !== "string" ||
      !/^\d{4}-\d{2}-\d{2}$/.test(rawOverride)
    ) {
      reportSilentFallback(
        new Error(
          `Invalid event.data.date_override: ${JSON.stringify(rawOverride)}`,
        ),
        {
          feature: "cron-strategy-review",
          op: "parse-event-data",
          message: "date_override must be YYYY-MM-DD",
          extra: {
            fn: "cron-strategy-review",
            rawOverride: String(rawOverride),
          },
        },
      );
      await step.run("sentry-heartbeat", async () => {
        await postSentryHeartbeat({ ok: false, sentryMonitorSlug: SENTRY_MONITOR_SLUG, cronName: "cron-strategy-review", logger });
      });
      return { ok: false, created: 0, skipped: 0, upToDate: 0, errors: 1 };
    }
    dateOverride = rawOverride;
  }
  const todayISO = dateOverride ?? new Date().toISOString().slice(0, 10);

  // --- Step 1: mint installation token (memoized across replays) ---
  const installationToken = await step.run(
    "mint-installation-token",
    async () => {
      return mintInstallationToken({ tokenMinLifetimeMs: TOKEN_MIN_LIFETIME_MS });
    },
  );

  // --- Step 2: setup ephemeral workspace (clone --depth=1 + sentinel) ---
  let ephemeralRoot: string | null = null;
  let repoRoot: string | null = null;
  try {
    const ws = await step.run("setup-workspace", async () => {
      return setupEphemeralWorkspace(installationToken);
    });
    ephemeralRoot = ws.ephemeralRoot;
    repoRoot = ws.repoRoot;
  } catch (err) {
    // Redact token if it sneaks into the error message (defense-in-depth).
    const e = err as Error;
    const redactedMsg = redactToken(e.message ?? "", installationToken);
    const redacted = new Error(redactedMsg);
    redacted.name = e.name;
    reportSilentFallback(redacted, {
      feature: "cron-strategy-review",
      op: "setup-ephemeral-workspace",
      message: "Failed to scaffold ephemeral cron workspace",
      extra: { fn: "cron-strategy-review" },
    });
    await step.run("sentry-heartbeat", async () => {
      await postSentryHeartbeat({ ok: false, sentryMonitorSlug: SENTRY_MONITOR_SLUG, cronName: "cron-strategy-review", logger });
    });
    return { ok: false, created: 0, skipped: 0, upToDate: 0, errors: 1 };
  }

  // --- Step 3 + 4: strategy-review-check + sentry-heartbeat; teardown
  //     in finally guarantees cleanup even if the inner step.run throws ---
  try {
    const result = await step.run(
      "strategy-review-check",
      async (): Promise<ReviewResult & { ok: boolean }> => {
        // Construct a per-step Octokit instance authenticated with the
        // freshly-minted installation token. NOT createProbeOctokit (which
        // uses JWT) — we need installation-scoped requests for issues:write.
        const { Octokit: OctokitCtor } = await import("@octokit/core");
        const octokit = new OctokitCtor({
          auth: installationToken,
        }) as unknown as Octokit;

        // Outer wall-clock guard via Promise.race against MAX_RUN_DURATION_MS.
        const timeoutMs = MAX_RUN_DURATION_MS;
        let timeoutHandle: ReturnType<typeof setTimeout> | null = null;
        const reviewPromise = runStrategyReview({
          octokit,
          repoRoot: repoRoot!,
          todayISO,
          logger,
        });
        const timeoutPromise = new Promise<never>((_resolve, reject) => {
          timeoutHandle = setTimeout(
            () =>
              reject(new Error(`strategy-review timed out after ${timeoutMs}ms`)),
            timeoutMs,
          );
        });
        try {
          const review = await Promise.race([reviewPromise, timeoutPromise]);
          logger.info(
            { fn: "cron-strategy-review", ...review },
            "strategy-review complete",
          );
          return { ...review, ok: review.errors === 0 };
        } finally {
          if (timeoutHandle) clearTimeout(timeoutHandle);
        }
      },
    );

    await step.run("sentry-heartbeat", async () => {
      await postSentryHeartbeat({ ok: result.ok, sentryMonitorSlug: SENTRY_MONITOR_SLUG, cronName: "cron-strategy-review", logger });
    });
    return result;
  } finally {
    // Best-effort teardown (idempotent rm -rf with force:true). Mirrors
    // PR-5's finally-block discipline — a teardown throw must never escape
    // and mask a real upstream error.
    await teardownEphemeralWorkspace(ephemeralRoot).catch((err) => {
      reportSilentFallback(err, {
        feature: "cron-strategy-review",
        op: "teardown-ephemeral-workspace-finally",
        message: "teardownEphemeralWorkspace threw in finally block",
        extra: { fn: "cron-strategy-review", ephemeralRoot },
      });
    });
  }
}

// =============================================================================
// Registration
// =============================================================================
//
// Triggers: scheduled cron (0 8 * * 1 UTC, weekly Monday 08:00) + manual
// operator event `cron/strategy-review.manual-trigger`. account-scope
// concurrency "cron-platform" limits to 1 simultaneous cron-* invocation
// across the Hetzner node (PR-1..PR-5 precedent).

export const cronStrategyReview = inngest.createFunction(
  {
    id: "cron-strategy-review",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "0 8 * * 1" },
    { event: "cron/strategy-review.manual-trigger" },
  ],
  cronStrategyReviewHandler as unknown as Parameters<
    typeof inngest.createFunction
  >[2],
);
