// TR9 Phase-2 — Migrated from the GHA scheduled-content-publisher
// workflow (deleted in the same PR per TR9 I-13 hygiene). Spawns the
// existing scripts/content-publisher.sh and creates a bot-PR with
// synthetic checks for any status updates committed by the script.
//
// ADR-033 invariants (binding all cron-*.ts files):
//   I1 — Octokit + node:fs reads called INSIDE step.run (replay memoization).
//   I2 — Operator-owned data only; never founder BYOK.
//   I3 — Outer wall-clock safety via Promise.race (MAX_RUN_DURATION_MS).
//   I4 — N/A (no claude binary; bash script spawn only).
//   I5 — Deterministic step.run return shape per step (see handler).
//   I6 — No event payloads emitted.
//
// SPAWN PATTERN — the content-publisher.sh script has complex platform-
// specific API logic (OAuth, multipart uploads, etc.). Cleanest port is
// to keep the existing bash script and spawn it from Inngest, capturing
// its exit code. Same pattern as cron-compound-promote.ts which spawns
// git commands.

import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { mkdtemp, readdir, readFile, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import matter from "gray-matter";
import type { Octokit } from "@octokit/core";
import { inngest } from "@/server/inngest/client";
import {
  reportSilentFallback,
  mirrorWarnWithDebounce,
} from "@/server/observability";
import {
  REPO_OWNER,
  REPO_NAME,
  redactToken,
  buildAuthenticatedCloneUrl,
  resolveCronWorkspaceRoot,
  warnIfCronWorkspaceLowOnDisk,
  mintInstallationToken,
  postSentryHeartbeat,
  ensureDedupIssue,
  type HandlerArgs,
} from "./_cron-shared";
import { SYNTHETIC_CHECK_NAMES, safeCommitAndPr } from "./_cron-safe-commit";
import {
  HORIZON_DAYS,
  applyPromotion,
  isReadyDraft,
  parseContentFrontmatter,
  planPromotions,
  splitFrontmatter,
  type PlannedPromotion,
  type PromotionInput,
} from "./content-promotion";

// =============================================================================
// Constants
// =============================================================================

const SENTRY_MONITOR_SLUG = "scheduled-content-publisher";

export const MAX_RUN_DURATION_MS = 10 * 60 * 1000;
const TOKEN_MIN_LIFETIME_MS = 15 * 60 * 1000;

const CONTENT_DIR_REL = "knowledge-base/marketing/distribution-content";

/** Environment variable names forwarded to the content-publisher.sh spawn. */
export const PUBLISHER_ENV_KEYS = [
  "DISCORD_BLOG_WEBHOOK_URL",
  "DISCORD_WEBHOOK_URL",
  "X_API_KEY",
  "X_API_SECRET",
  "X_ACCESS_TOKEN",
  "X_ACCESS_TOKEN_SECRET",
  "LINKEDIN_ACCESS_TOKEN",
  "LINKEDIN_PERSON_URN",
  "LINKEDIN_ORG_ID",
  "LINKEDIN_ORG_ACCESS_TOKEN",
  "BSKY_HANDLE",
  "BSKY_APP_PASSWORD",
] as const;

// =============================================================================
// Types
// =============================================================================

interface HandlerResult {
  ok: boolean;
  status: string;
  published?: number;
  staleDetected?: number;
  promoted?: number;
  starved?: boolean;
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

async function setupEphemeralWorkspace(
  token: string,
): Promise<{ ephemeralRoot: string; repoRoot: string }> {
  const ephemeralRoot = await mkdtemp(
    join(resolveCronWorkspaceRoot(), "soleur-cron-content-publisher-"),
  );
  const repoRoot = join(ephemeralRoot, "repo");
  await warnIfCronWorkspaceLowOnDisk(ephemeralRoot, "cron-content-publisher");
  const cloneUrl = buildAuthenticatedCloneUrl(token);
  const result = await spawnGit(["clone", "--depth=1", cloneUrl, repoRoot]);
  if (result.exitCode !== 0) {
    throw new Error(
      `git clone failed (exit ${result.exitCode}, signal ${result.signal}) for ${REPO_OWNER}/${REPO_NAME}`,
    );
  }
  if (!existsSync(join(repoRoot, CONTENT_DIR_REL))) {
    throw new Error(
      `Sentinel: ${CONTENT_DIR_REL}/ absent after clone`,
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
      feature: "cron-content-publisher",
      op: "teardown-ephemeral-workspace",
      message: "Failed to remove ephemeral workspace",
      extra: { fn: "cron-content-publisher", ephemeralRoot },
    });
  }
}

/**
 * Build the env map for the content-publisher.sh spawn. Explicit allowlist
 * of the 12 social API secrets + PATH/HOME/GH_TOKEN. No `...process.env`
 * spread — that would leak Doppler secrets into the child.
 */
export function buildPublisherEnv(ghToken: string): NodeJS.ProcessEnv {
  const env: NodeJS.ProcessEnv = {
    PATH: process.env.PATH,
    HOME: process.env.HOME,
    NODE_ENV: process.env.NODE_ENV,
    GH_TOKEN: ghToken,
    X_ALLOW_POST: "true",
    LINKEDIN_ALLOW_POST: "true",
    BSKY_ALLOW_POST: "true",
  };
  for (const key of PUBLISHER_ENV_KEYS) {
    env[key] = process.env[key];
  }
  return env;
}

/** Spawn a bash script and capture stdout + stderr + exit code. */
async function spawnScriptCapture(
  script: string,
  args: string[],
  opts: { cwd: string; env: NodeJS.ProcessEnv },
): Promise<{ exitCode: number | null; stdout: string; stderr: string }> {
  return new Promise((resolve) => {
    const child = spawn("bash", [script, ...args], {
      stdio: ["ignore", "pipe", "pipe"],
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
    child.on("exit", (exitCode) => resolve({ exitCode, stdout, stderr }));
    child.on("error", () => resolve({ exitCode: -1, stdout, stderr }));
  });
}

// gray-matter parses YAML 1.1, which coerces unquoted ISO dates into
// JavaScript Date objects. Coerce both shapes to YYYY-MM-DD.
function coerceFrontmatterDate(raw: unknown): string | undefined {
  if (raw === undefined || raw === null) return undefined;
  if (raw instanceof Date) {
    if (Number.isNaN(raw.getTime())) return undefined;
    return raw.toISOString().slice(0, 10);
  }
  return String(raw);
}

// =============================================================================
// Promotion + starvation (Phase 2)
// =============================================================================

/** Days with no post AND nothing scheduled that trips the starvation alert. */
export const STARVATION_DAYS = 10;

/**
 * Stable, date-free title for the standing starvation alert. A persisting
 * drought files ONE issue (not one per daily run); it auto-closes on recovery.
 */
export const STARVATION_ISSUE_TITLE =
  "Content starvation: distribution schedule is empty (auto-promotion found nothing to schedule)";

/**
 * Dedicated label carried by the starvation issue IN ADDITION to
 * `action-required`. The dedup + auto-close reads filter on BOTH labels
 * (GitHub AND-semantics), so the candidate set stays ~1 regardless of how many
 * other `action-required` issues are open. Without this, the `per_page: 10,
 * sort: created desc` read would page the standing (long-lived, stable-title)
 * starvation issue off page 1 once ≥10 newer `action-required` issues exist —
 * exactly the neglected-backlog state a multi-week drought represents — causing
 * daily duplicates AND a missed auto-close on recovery. (`ensureScheduledAuditIssue`
 * is safe with `action-required` alone only because its title is date-suffixed
 * and it dedups same-day; a standing alert needs the narrower filter.)
 */
export const STARVATION_ISSUE_LABEL = "content-starvation";

const DAY_MS = 24 * 60 * 60 * 1000;

/** Strict `YYYY-MM-DD` → epoch ms (UTC), or NaN if not that shape. */
function parseISODateUTC(d: string): number {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(d)) return NaN;
  return Date.parse(`${d}T00:00:00Z`);
}

export interface CorpusAnalysis {
  /** Drafts assigned a Tue/Thu slot this run (path + new publish_date). */
  promotions: PlannedPromotion[];
  /** status:draft + channels but failing the readiness gate (per-draft signal). */
  gateFailedDrafts: string[];
  /** Most-recent parseable publish_date among status:published files. */
  latestPublishedDate?: string;
  /** Whole days since latestPublishedDate; undefined when no baseline. */
  daysSincePublish?: number;
  /** Post-promotion count of scheduled items landing within the horizon. */
  scheduledWithinHorizon: number;
  /** Count of status:draft files (ready or not). */
  draftBacklog: number;
  /** status:published files whose publish_date could not be parsed. */
  unparseablePublishedDates: string[];
}

/**
 * ONE pass over the content corpus (simplicity S3) producing every scalar the
 * promote-drafts and starvation-check steps need. Pure — the caller supplies the
 * file list read off the ephemeral clone.
 *
 * `occupied` (double-book guard) = the publish_date of EVERY file carrying one,
 * regardless of status (a parked/stale/published date must never be re-assigned
 * to a promoted draft). Only status:draft files are promotable.
 */
export function analyzeCorpus(args: {
  files: PromotionInput[];
  today: Date;
  horizonDays: number;
}): CorpusAnalysis {
  const { files, today, horizonDays } = args;
  const todayMs = Date.UTC(
    today.getUTCFullYear(),
    today.getUTCMonth(),
    today.getUTCDate(),
  );
  const horizonEndMs = todayMs + horizonDays * DAY_MS;

  const occupied = new Set<string>();
  const gateFailedDrafts: string[] = [];
  const unparseablePublishedDates: string[] = [];
  let latestPublishedMs = -Infinity;
  let latestPublishedDate: string | undefined;
  let draftBacklog = 0;
  let existingScheduledInHorizon = 0;

  for (const f of files) {
    const parsed = parseContentFrontmatter(f.raw);
    const pd = parsed.publishDate;
    if (pd && pd.length > 0) occupied.add(pd);

    if (parsed.status === "draft") {
      draftBacklog++;
      const { body } = splitFrontmatter(f.raw);
      // Gate-failed is scoped to drafts that DECLARE channels — an empty-channels
      // draft is simply not-ready, not "broken". Independent of scheduling so a
      // malformed draft is never masked by another schedulable one (spec-flow P0).
      if (parsed.channels.length > 0 && !isReadyDraft(parsed, body)) {
        gateFailedDrafts.push(f.path);
      }
    } else if (parsed.status === "published") {
      if (pd && pd.length > 0) {
        const ms = parseISODateUTC(pd);
        if (Number.isFinite(ms)) {
          if (ms > latestPublishedMs) {
            latestPublishedMs = ms;
            latestPublishedDate = pd;
          }
        } else {
          unparseablePublishedDates.push(f.path);
        }
      }
    } else if (parsed.status === "scheduled") {
      if (pd) {
        const ms = parseISODateUTC(pd);
        if (Number.isFinite(ms) && ms >= todayMs && ms <= horizonEndMs) {
          existingScheduledInHorizon++;
        }
      }
    }
  }

  const promotions = planPromotions({ files, today, occupied, horizonDays });
  const scheduledWithinHorizon = existingScheduledInHorizon + promotions.length;

  const daysSincePublish =
    latestPublishedDate !== undefined
      ? Math.floor((todayMs - latestPublishedMs) / DAY_MS)
      : undefined;

  return {
    promotions,
    gateFailedDrafts,
    latestPublishedDate,
    daysSincePublish,
    scheduledWithinHorizon,
    draftBacklog,
    unparseablePublishedDates,
  };
}

/**
 * Starvation predicate (silent-failure F1 — the load-bearing fix). A naive
 * `daysSincePublish >= N` SILENTLY skips the worst drought: with zero published
 * files `daysSincePublish` is undefined and `NaN >= N` is false. Treat an
 * absent/non-finite baseline (with nothing scheduled) as starved.
 */
export function isStarved(args: {
  scheduledWithinHorizon: number;
  latestPublishedDate?: string;
  daysSincePublish?: number;
  starvationDays: number;
}): boolean {
  const { scheduledWithinHorizon, latestPublishedDate, daysSincePublish, starvationDays } =
    args;
  return (
    scheduledWithinHorizon === 0 &&
    (latestPublishedDate === undefined ||
      !Number.isFinite(daysSincePublish) ||
      (daysSincePublish as number) >= starvationDays)
  );
}

function buildStarvationIssueBody(args: {
  daysSincePublish?: number;
  draftBacklog: number;
  latestPublishedDate?: string;
  gateFailedDrafts?: string[];
}): string {
  const { daysSincePublish, draftBacklog, latestPublishedDate, gateFailedDrafts } = args;
  const daysLabel = Number.isFinite(daysSincePublish)
    ? `${daysSincePublish}`
    : "unknown (no published baseline)";
  const gateSection =
    gateFailedDrafts && gateFailedDrafts.length > 0
      ? `\n\n**Drafts failing the readiness gate** (Liquid marker or all mapped sections empty):\n${gateFailedDrafts
          .map((f) => `- \`${f}\``)
          .join("\n")}`
      : "";
  return (
    `## Content distribution has starved\n\n` +
    `The daily \`cron-content-publisher\` ran, attempted auto-promotion, and still ` +
    `has **0 items scheduled within the horizon** — so nothing will post.\n\n` +
    `| Signal | Value |\n| --- | --- |\n` +
    `| days since last post | ${daysLabel} |\n` +
    `| last published date | ${latestPublishedDate ?? "none (no published files)"} |\n` +
    `| draft backlog | ${draftBacklog} |\n` +
    `| starvation threshold (days) | ${STARVATION_DAYS} |\n` +
    gateSection +
    `\n\nThe schedule self-heals once a review-ready draft (\`status: draft\` with ` +
    `declared channels, Liquid-clean, ≥1 non-empty mapped section) exists — the ` +
    `next daily run will promote it. Use \`status: parked\` to hold a specific draft. ` +
    `This issue auto-closes when the schedule refills.`
  );
}

async function closeStarvationIssueOnRecovery(
  client: Octokit,
  scheduledWithinHorizon: number,
): Promise<void> {
  const existing = (await client.request("GET /repos/{owner}/{repo}/issues", {
    owner: REPO_OWNER,
    repo: REPO_NAME,
    state: "open",
    // Filter on BOTH labels (AND) so the standing starvation issue can never
    // scroll off page 1 behind a backlog of other action-required issues.
    labels: `action-required,${STARVATION_ISSUE_LABEL}`,
    sort: "created",
    direction: "desc",
    per_page: 10,
    headers: { "X-GitHub-Api-Version": "2022-11-28" },
  })) as { data: Array<{ title: string; number: number }> };
  const open = existing.data.find((i) => i.title === STARVATION_ISSUE_TITLE);
  if (!open) return;

  await client.request("POST /repos/{owner}/{repo}/issues/{issue_number}/comments", {
    owner: REPO_OWNER,
    repo: REPO_NAME,
    issue_number: open.number,
    body:
      `Recovery: ${scheduledWithinHorizon} item(s) are now scheduled within the ` +
      `horizon — the distribution schedule has refilled. Auto-closing this ` +
      `starvation alert.`,
    headers: { "X-GitHub-Api-Version": "2022-11-28" },
  });
  await client.request("PATCH /repos/{owner}/{repo}/issues/{issue_number}", {
    owner: REPO_OWNER,
    repo: REPO_NAME,
    issue_number: open.number,
    state: "closed",
    headers: { "X-GitHub-Api-Version": "2022-11-28" },
  });
}

/**
 * Starvation-check orchestration — FAILURE-ISOLATED (architecture A-P1b /
 * silent-failure F3). Every Octokit path is wrapped: on any throw we report
 * `starvation-check-failed` and return normally, so an issue-API hiccup can
 * NEVER propagate to the handler top-level catch (which posts `ok:false` — a
 * false cron-DOWN). Starvation is a CONTENT signal; it must not flip liveness.
 */
export async function runStarvationCheck(args: {
  client: Octokit;
  scheduledWithinHorizon: number;
  latestPublishedDate?: string;
  daysSincePublish?: number;
  draftBacklog: number;
  gateFailedDrafts?: string[];
  starvationDays: number;
}): Promise<{ starved: boolean }> {
  const {
    client,
    scheduledWithinHorizon,
    latestPublishedDate,
    daysSincePublish,
    draftBacklog,
    gateFailedDrafts,
    starvationDays,
  } = args;

  const starved = isStarved({
    scheduledWithinHorizon,
    latestPublishedDate,
    daysSincePublish,
    starvationDays,
  });

  try {
    if (starved) {
      const daysLabel = Number.isFinite(daysSincePublish)
        ? `${daysSincePublish}`
        : "unknown (no published baseline)";
      reportSilentFallback(
        new Error(
          `content starvation: 0 scheduled, ${daysLabel} days since last post`,
        ),
        {
          feature: "cron-content-publisher",
          op: "content-starvation",
          message:
            "Distribution schedule empty after promotion — no content will post",
          tags: { starvation: "true" },
          extra: { daysSincePublish, draftBacklog, latestPublishedDate, gateFailedDrafts },
        },
      );
      await ensureDedupIssue(client, {
        title: STARVATION_ISSUE_TITLE,
        body: buildStarvationIssueBody({
          daysSincePublish,
          draftBacklog,
          latestPublishedDate,
          gateFailedDrafts,
        }),
        labels: ["action-required", STARVATION_ISSUE_LABEL],
      });
    } else if (scheduledWithinHorizon > 0) {
      await closeStarvationIssueOnRecovery(client, scheduledWithinHorizon);
    }
    return { starved };
  } catch (err) {
    reportSilentFallback(err, {
      feature: "cron-content-publisher",
      op: "starvation-check-failed",
      message:
        "Starvation check failed (Octokit/issue op) — isolated from heartbeat",
    });
    // Degrade to not-starved: we could not complete the check, and the heartbeat
    // must stay green regardless.
    return { starved: false };
  }
}

// =============================================================================
// Handler
// =============================================================================

export async function cronContentPublisherHandler({
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
      async () => mintInstallationToken({ tokenMinLifetimeMs: TOKEN_MIN_LIFETIME_MS }),
    );

    const workspace = await step.run("setup-workspace", async () => {
      const ws = await setupEphemeralWorkspace(installationToken);
      ephemeralRoot = ws.ephemeralRoot;
      return { ephemeralRoot: ws.ephemeralRoot, repoRoot: ws.repoRoot };
    });

    const repoRoot = workspace.repoRoot;
    ephemeralRoot = workspace.ephemeralRoot;

    // Auto-promote review-ready drafts onto upcoming Tue/Thu slots BEFORE the
    // stale-content pre-check (A-P2): pre-check derives `published =
    // scheduledToday`, so it must see post-promotion disk state or a draft
    // promoted onto today would undercount. Promotion only ever assigns
    // future/today dates, so it can never manufacture a stale entry. A throw
    // here (planPromotions / writeFile) is a PERSISTENCE failure and correctly
    // propagates to the top-level catch → ok:false (F5) — do NOT swallow.
    const promotion = await step.run("promote-drafts", async () => {
      const contentDir = join(repoRoot, CONTENT_DIR_REL);
      const today = new Date();
      const names = await readdir(contentDir);
      const files: PromotionInput[] = [];
      for (const name of names) {
        if (!name.endsWith(".md")) continue;
        const raw = await readFile(join(contentDir, name), "utf-8");
        files.push({ path: name, raw });
      }

      const analysis = analyzeCorpus({ files, today, horizonDays: HORIZON_DAYS });

      // Persist each promotion via TARGETED line replacement (never a
      // gray-matter round-trip — YAML-1.1 date coercion trap).
      for (const p of analysis.promotions) {
        const original = files.find((f) => f.path === p.path);
        if (!original) continue;
        await writeFile(
          join(contentDir, p.path),
          applyPromotion(original.raw, p.publishDate),
          "utf-8",
        );
      }

      // An unparseable publish_date on a PUBLISHED file understates the
      // starvation baseline — surface it loudly rather than let it collapse to a
      // false-negative (F1).
      for (const badFile of analysis.unparseablePublishedDates) {
        reportSilentFallback(
          new Error(`Unparseable publish_date on published file: ${badFile}`),
          {
            feature: "cron-content-publisher",
            op: "published-date-unparseable",
            message:
              "A status:published file has an unparseable publish_date — starvation baseline may be understated",
            extra: { fn: "cron-content-publisher", file: badFile },
          },
        );
      }

      // Per-draft gate-failed signal (spec-flow P0) — debounced, and emitted
      // INDEPENDENTLY of whether anything else was schedulable.
      if (analysis.gateFailedDrafts.length > 0) {
        mirrorWarnWithDebounce(
          new Error(
            `draft(s) failed the readiness gate: ${analysis.gateFailedDrafts.join(", ")}`,
          ),
          {
            feature: "cron-content-publisher",
            op: "draft-gate-failed",
            message:
              "Draft(s) declare channels but fail the readiness gate (Liquid marker or all mapped sections empty)",
            extra: { fn: "cron-content-publisher", files: analysis.gateFailedDrafts },
          },
          "cron-content-publisher",
          "draft-gate-failed",
        );
      }

      return {
        promoted: analysis.promotions,
        latestPublishedDate: analysis.latestPublishedDate,
        daysSincePublish: analysis.daysSincePublish,
        scheduledWithinHorizon: analysis.scheduledWithinHorizon,
        draftBacklog: analysis.draftBacklog,
        gateFailedDrafts: analysis.gateFailedDrafts,
      };
    });

    // Detect stale content before running publisher (status: scheduled +
    // publish_date in the past). Report via reportSilentFallback.
    const preCheck = await step.run("pre-check-stale-content", async () => {
      const contentDir = join(repoRoot, CONTENT_DIR_REL);
      let staleCount = 0;
      let scheduledToday = 0;
      const todayISO = new Date().toISOString().slice(0, 10);

      try {
        const files = await readdir(contentDir);
        for (const name of files) {
          if (!name.endsWith(".md")) continue;
          const filePath = join(contentDir, name);
          const raw = await readFile(filePath, "utf-8");
          let parsed: ReturnType<typeof matter>;
          try {
            parsed = matter(raw);
          } catch {
            continue;
          }
          const status = parsed.data.status as string | undefined;
          if (status !== "scheduled") continue;

          const publishDate = coerceFrontmatterDate(parsed.data.publish_date);
          if (!publishDate) continue;

          if (publishDate === todayISO) {
            scheduledToday++;
          } else if (publishDate < todayISO) {
            staleCount++;
            reportSilentFallback(
              new Error(`Stale scheduled content: ${name}`),
              {
                feature: "cron-content-publisher",
                op: "stale-content-detection",
                message: `File ${name} has status:scheduled but publish_date ${publishDate} is in the past`,
                extra: { fn: "cron-content-publisher", file: name, publishDate },
              },
            );
          }
        }
      } catch (err) {
        reportSilentFallback(err, {
          feature: "cron-content-publisher",
          op: "pre-check-stale-content",
          message: "Failed to scan content directory",
          extra: { fn: "cron-content-publisher" },
        });
      }
      return { staleCount, scheduledToday };
    });

    // Run the content-publisher script
    const publishResult = await step.run("run-publisher-script", async () => {
      const staleEventsFile = join(ephemeralRoot!, "stale-events.txt");
      const env = buildPublisherEnv(installationToken);
      env.STALE_EVENTS_FILE = staleEventsFile;

      const scriptPath = join(repoRoot, "scripts", "content-publisher.sh");
      if (!existsSync(scriptPath)) {
        throw new Error("scripts/content-publisher.sh not found in clone");
      }

      const result = await spawnScriptCapture(scriptPath, [], {
        cwd: repoRoot,
        env,
      });

      if (result.exitCode === 2) {
        logger.warn(
          { fn: "cron-content-publisher", exitCode: result.exitCode },
          "Partial failure — some platforms failed but fallback issues were created",
        );
      } else if (result.exitCode !== 0 && result.exitCode !== null) {
        throw new Error(
          `content-publisher.sh failed (exit ${result.exitCode})`,
        );
      }

      return { exitCode: result.exitCode };
    });

    // Persist status updates via safeCommitAndPr (#5111) — gains the
    // deletion guard, dirty-index precondition, dropped-path warn, and
    // replay idempotency. mergeMode "direct" + synthetic checks preserves
    // this pipeline's production-proven merge mechanics; the helper's
    // direct→arm-auto-merge→loud-failure ladder strictly improves on the
    // old log-only catch.
    const prResult = await step.run("safe-commit-pr", async () => {
      const result = await safeCommitAndPr({
        spawnCwd: repoRoot,
        installationToken,
        cronName: "cron-content-publisher",
        commitMessage:
          "ci: promote review-ready drafts + update content distribution status",
        // Trailing slash added vs CONTENT_DIR_REL: the helper's allowlist
        // matching is bare startsWith and directory entries must end "/".
        allowedPaths: [`${CONTENT_DIR_REL}/`],
        runStartedAt,
        scheduledIssueLabel: SENTRY_MONITOR_SLUG,
        prBody: "Automated status update from content publisher workflow.",
        syntheticChecks: {
          names: SYNTHETIC_CHECK_NAMES,
          summary: "Status metadata only, no code changes",
        },
        mergeMode: "direct",
        logger,
      });
      // Distinguish failed from no-changes: a "failed" result at stage
      // auto-merge means a PR EXISTS but needs a manual merge — folding it
      // into prCreated:false would report "no-changes" for a run that
      // actually produced an open PR.
      return result.status === "committed"
        ? { prCreated: true, prNumber: result.prNumber, persistFailed: false }
        : { prCreated: false, persistFailed: result.status === "failed" };
    });

    // Content-starvation check on POST-publish disk state (latestPublishedDate
    // reflects any same-run publish). Fully failure-isolated: runStarvationCheck
    // swallows every Octokit throw internally, and this step wraps it once more
    // so a client-construction throw likewise never reaches the top-level catch
    // (which posts ok:false). Starvation is a CONTENT signal, not liveness.
    const starvation = await step.run("starvation-check", async () => {
      try {
        const { Octokit } = await import("@octokit/core");
        const client = new Octokit({ auth: installationToken }) as unknown as Octokit;
        return await runStarvationCheck({
          client,
          scheduledWithinHorizon: promotion.scheduledWithinHorizon,
          latestPublishedDate: promotion.latestPublishedDate,
          daysSincePublish: promotion.daysSincePublish,
          draftBacklog: promotion.draftBacklog,
          gateFailedDrafts: promotion.gateFailedDrafts,
          starvationDays: STARVATION_DAYS,
        });
      } catch (err) {
        reportSilentFallback(err, {
          feature: "cron-content-publisher",
          op: "starvation-check-failed",
          message:
            "Starvation check setup failed — isolated from heartbeat",
        });
        return { starved: false };
      }
    });

    await step.run("sentry-heartbeat", () =>
      postSentryHeartbeat({
        ok: true,
        sentryMonitorSlug: SENTRY_MONITOR_SLUG,
        cronName: "cron-content-publisher",
        logger,
      }),
    );

    return {
      ok: true,
      status:
        publishResult.exitCode === 2
          ? "partial-failure"
          : prResult.prCreated
            ? "published"
            : prResult.persistFailed
              ? "persist-failed"
              : "no-changes",
      published: preCheck.scheduledToday,
      staleDetected: preCheck.staleCount,
      promoted: promotion.promoted.length,
      starved: starvation.starved,
    };
  } catch (err) {
    const e = err as Error;
    if (installationToken) {
      e.message = redactToken(e.message, installationToken);
    }
    reportSilentFallback(e, {
      feature: "cron-content-publisher",
      op: "handler-top-level",
      message: e.message,
    });
    try {
      await postSentryHeartbeat({
        ok: false,
        sentryMonitorSlug: SENTRY_MONITOR_SLUG,
        cronName: "cron-content-publisher",
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

export const cronContentPublisher = inngest.createFunction(
  {
    id: "cron-content-publisher",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "0 14 * * *" },
    { event: "cron/content-publisher.manual-trigger" },
  ],
  cronContentPublisherHandler as unknown as Parameters<
    typeof inngest.createFunction
  >[2],
);
