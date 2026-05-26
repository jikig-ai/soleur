// TR9 Phase-2 — Monthly aggregator for skill invocation metrics.
// Reads `.claude/.skill-invocations.jsonl` (gitignored — may not exist
// on Hetzner worker), produces
// `knowledge-base/engineering/operations/skill-freshness.json`, and files
// up to CAP_PER_RUN issues per run for idle (>=180 days) or
// archival_candidate (>=365 days) skills.
//
// Migrated from .github/workflows/scheduled-skill-freshness.yml (deleted
// in the same PR per TR9 I-13 hygiene). Requires filesystem access to
// the repo (JSONL + SKILL.md glob), so uses setupEphemeralWorkspace from
// _cron-claude-eval-substrate.ts for the clone.
//
// ADR-033 invariants:
//   I1 — All outbound IO is inside step.run for Inngest replay memoization.
//        One `git clone` spawn lives in setupEphemeralWorkspace; that is
//        the ONLY child_process.spawn call in this file.
//   I2 — Trivially satisfied: no claude / no BYOK lease.
//   I3 — Outer wall-clock safety enforced by Inngest step timeout.
//   I4 — N/A (no claude binary resolution; pure Node.js + Octokit).
//   I5 — Deterministic step.run return shapes.
//   I6 — N/A; this function emits no Inngest events.

import { existsSync } from "node:fs";
import { readFile, readdir, writeFile, mkdir } from "node:fs/promises";
import { join, dirname } from "node:path";
import type { Octokit } from "@octokit/core";
import { inngest } from "@/server/inngest/client";
import { reportSilentFallback } from "@/server/observability";
import {
  REPO_OWNER,
  REPO_NAME,
  redactToken,
  mintInstallationToken,
  postSentryHeartbeat,
  type HandlerArgs,
} from "./_cron-shared";
import {
  setupEphemeralWorkspace,
  teardownEphemeralWorkspace,
} from "./_cron-claude-eval-substrate";

// =============================================================================
// Constants
// =============================================================================

const SENTRY_MONITOR_SLUG = "scheduled-skill-freshness";

const TOKEN_MIN_LIFETIME_MS = 15 * 60 * 1000;

/** Maximum issues filed per run to avoid flooding. */
export const CAP_PER_RUN = 3;

/** Skill-name validation regex (kebab-case, optional :plugin prefix). */
export const SKILL_NAME_RE = /^[a-z][a-z0-9-]*(:[a-z0-9-]+)?$/;

const INVOCATIONS_REL_PATH = ".claude/.skill-invocations.jsonl";
const SKILLS_DIR_REL = "plugins/soleur/skills";
const REPORT_REL_PATH =
  "knowledge-base/engineering/operations/skill-freshness.json";

const IDLE_THRESHOLD_DAYS = 180;
const ARCHIVAL_THRESHOLD_DAYS = 365;

const FRESHNESS_LABEL = "scheduled-skill-freshness";

// =============================================================================
// Types
// =============================================================================

interface InvocationRecord {
  schema: number;
  skill: string;
  ts: string;
  error?: string;
}

interface SkillFreshnessEntry {
  name: string;
  last_invoked: string | null;
  invocation_count: number;
  days_since_last: number | null;
  status: "fresh" | "idle" | "archival_candidate" | "never_invoked";
}

interface FreshnessReport {
  schema: 1;
  generated_at: string;
  skills: SkillFreshnessEntry[];
  summary: {
    total_skills: number;
    idle_180d: number;
    idle_365d: number;
    never_invoked: number;
  };
}

// =============================================================================
// Helpers — inventory + aggregation
// =============================================================================

async function enumerateSkills(repoRoot: string): Promise<string[]> {
  const skillsDir = join(repoRoot, SKILLS_DIR_REL);
  if (!existsSync(skillsDir)) return [];

  const entries = await readdir(skillsDir, { withFileTypes: true });
  const skills: string[] = [];
  for (const entry of entries) {
    if (!entry.isDirectory()) continue;
    const skillMd = join(skillsDir, entry.name, "SKILL.md");
    if (existsSync(skillMd)) {
      skills.push(entry.name);
    }
  }
  return skills.sort();
}

function parseInvocations(
  raw: string,
): Map<string, { lastInvoked: string; count: number }> {
  const bySkill = new Map<string, { lastInvoked: string; count: number }>();

  for (const line of raw.split("\n")) {
    if (!line.trim()) continue;
    let record: InvocationRecord;
    try {
      record = JSON.parse(line) as InvocationRecord;
    } catch {
      continue; // malformed line
    }
    if (record.schema !== 1 || !record.skill || !record.ts) continue;
    if (record.error) continue; // drop sentinels

    // Normalize namespaced skill names ("soleur:plan") to bare ("plan")
    const bare = record.skill.includes(":")
      ? record.skill.split(":").pop()!
      : record.skill;

    const existing = bySkill.get(bare);
    if (!existing) {
      bySkill.set(bare, { lastInvoked: record.ts, count: 1 });
    } else {
      existing.count++;
      if (record.ts > existing.lastInvoked) {
        existing.lastInvoked = record.ts;
      }
    }
  }

  return bySkill;
}

function buildReport(
  skills: string[],
  invocations: Map<string, { lastInvoked: string; count: number }>,
  nowIso: string,
): FreshnessReport {
  const nowEpoch = Date.parse(nowIso);

  const entries: SkillFreshnessEntry[] = skills.map((name) => {
    const inv = invocations.get(name);
    if (!inv) {
      return {
        name,
        last_invoked: null,
        invocation_count: 0,
        days_since_last: null,
        status: "never_invoked" as const,
      };
    }

    const lastEpoch = Date.parse(inv.lastInvoked);
    const ageSecs = (nowEpoch - lastEpoch) / 1000;
    const daysSince = Math.floor(ageSecs / 86400);

    let status: SkillFreshnessEntry["status"];
    if (ageSecs >= ARCHIVAL_THRESHOLD_DAYS * 86400) {
      status = "archival_candidate";
    } else if (ageSecs >= IDLE_THRESHOLD_DAYS * 86400) {
      status = "idle";
    } else {
      status = "fresh";
    }

    return {
      name,
      last_invoked: inv.lastInvoked,
      invocation_count: inv.count,
      days_since_last: daysSince,
      status,
    };
  });

  return {
    schema: 1,
    generated_at: nowIso,
    skills: entries,
    summary: {
      total_skills: entries.length,
      idle_180d: entries.filter((e) => e.status === "idle").length,
      idle_365d: entries.filter((e) => e.status === "archival_candidate")
        .length,
      never_invoked: entries.filter((e) => e.status === "never_invoked")
        .length,
    },
  };
}

// =============================================================================
// Helpers — issue filing
// =============================================================================

async function ensureFreshnessLabel(octokit: Octokit): Promise<void> {
  try {
    await octokit.request("POST /repos/{owner}/{repo}/labels", {
      owner: REPO_OWNER,
      repo: REPO_NAME,
      name: FRESHNESS_LABEL,
      description: "Monthly skill freshness report finding",
      color: "0E8A16",
    });
  } catch (err) {
    const status = (err as { status?: number }).status;
    if (status !== 422) {
      reportSilentFallback(err, {
        feature: "cron-skill-freshness",
        op: "ensure-label",
        message: "Failed to create scheduled-skill-freshness label",
        extra: { fn: "cron-skill-freshness", status },
      });
    }
  }
}

async function searchExistingFreshnessIssue(
  octokit: Octokit,
  skillName: string,
): Promise<boolean> {
  const resp = (await octokit.request("GET /repos/{owner}/{repo}/issues", {
    owner: REPO_OWNER,
    repo: REPO_NAME,
    state: "all",
    labels: FRESHNESS_LABEL,
    per_page: 10,
  })) as { data: Array<{ title: string }> };

  return resp.data.some((i) =>
    i.title.startsWith(`[Scheduled] Skill freshness: ${skillName} idle`),
  );
}

async function fileSkillIssue(
  octokit: Octokit,
  entry: SkillFreshnessEntry,
): Promise<void> {
  const title = `[Scheduled] Skill freshness: ${entry.name} idle ${entry.days_since_last} days (${entry.status})`;
  const body =
    `Skill \`${entry.name}\` has not been invoked in ${entry.days_since_last} days (status: \`${entry.status}\`).\n\n` +
    `Filed by \`cron-skill-freshness\` Inngest function. ` +
    `Source: \`${REPORT_REL_PATH}\`.\n\n` +
    `Review action:\n` +
    `- Is this skill still useful? If yes, close this issue.\n` +
    `- Is this skill superseded? Mark for archival via \`/soleur:archive-kb\`.\n` +
    `- Is the discovery surface broken (skill exists but operators forget it)? ` +
    `Update \`/soleur:help\` taxonomy.\n\n` +
    `Do not autoclose this issue (do-not-autoclose label).`;

  await octokit.request("POST /repos/{owner}/{repo}/issues", {
    owner: REPO_OWNER,
    repo: REPO_NAME,
    title,
    body,
    labels: [FRESHNESS_LABEL, "do-not-autoclose"],
  });
}

// =============================================================================
// Handler
// =============================================================================

export async function cronSkillFreshnessHandler({
  step,
  logger,
}: HandlerArgs): Promise<{
  ok: boolean;
  totalSkills: number;
  idle: number;
  archival: number;
  neverInvoked: number;
  issuesFiled: number;
}> {
  // --- Step 1: mint installation token ---
  const installationToken = await step.run(
    "mint-installation-token",
    async () => {
      return mintInstallationToken({
        tokenMinLifetimeMs: TOKEN_MIN_LIFETIME_MS,
      });
    },
  );

  // --- Step 2: setup ephemeral workspace ---
  let ephemeralRoot: string | null = null;
  let spawnCwd: string | null = null;
  try {
    const ws = await step.run("setup-workspace", async () => {
      return setupEphemeralWorkspace({
        installationToken,
        cronName: "cron-skill-freshness",
      });
    });
    ephemeralRoot = ws.ephemeralRoot;
    spawnCwd = ws.spawnCwd;
  } catch (err) {
    const e = err as Error;
    const redactedMsg = redactToken(e.message ?? "", installationToken);
    const redacted = new Error(redactedMsg);
    redacted.name = e.name;
    reportSilentFallback(redacted, {
      feature: "cron-skill-freshness",
      op: "setup-ephemeral-workspace",
      message: "Failed to scaffold ephemeral cron workspace",
      extra: { fn: "cron-skill-freshness" },
    });
    await step.run("sentry-heartbeat", async () => {
      await postSentryHeartbeat({
        ok: false,
        sentryMonitorSlug: SENTRY_MONITOR_SLUG,
        cronName: "cron-skill-freshness",
        logger,
      });
    });
    return {
      ok: false,
      totalSkills: 0,
      idle: 0,
      archival: 0,
      neverInvoked: 0,
      issuesFiled: 0,
    };
  }

  try {
    // --- Step 3: aggregate skill freshness ---
    const result = await step.run("aggregate-skill-freshness", async () => {
      const repoRoot = spawnCwd!;

      // 1. Enumerate skills
      const skills = await enumerateSkills(repoRoot);
      if (skills.length === 0) {
        throw new Error(
          `No skills found under ${SKILLS_DIR_REL} — directory may have been reorganized`,
        );
      }

      // 2. Parse invocations
      const invocationsPath = join(repoRoot, INVOCATIONS_REL_PATH);
      let invocationsRaw = "";
      if (existsSync(invocationsPath)) {
        invocationsRaw = await readFile(invocationsPath, "utf-8");
      }
      const invocations = parseInvocations(invocationsRaw);

      // 3. Build report
      const nowIso = new Date().toISOString();
      const report = buildReport(skills, invocations, nowIso);

      // 4. Write report
      const reportPath = join(repoRoot, REPORT_REL_PATH);
      await mkdir(dirname(reportPath), { recursive: true });
      await writeFile(reportPath, JSON.stringify(report, null, 2) + "\n", "utf-8");

      logger.info(
        {
          fn: "cron-skill-freshness",
          totalSkills: report.summary.total_skills,
          idle180d: report.summary.idle_180d,
          idle365d: report.summary.idle_365d,
          neverInvoked: report.summary.never_invoked,
        },
        "Skill freshness report generated",
      );

      return report;
    });

    // --- Step 4: file issues for stale skills ---
    const issuesFiled = await step.run("file-stale-skill-issues", async () => {
      const { Octokit: OctokitCtor } = await import("@octokit/core");
      const octokit = new OctokitCtor({
        auth: installationToken,
      }) as unknown as Octokit;

      await ensureFreshnessLabel(octokit);

      // Collect stale skills (worst offenders first)
      const staleSkills = result.skills
        .filter(
          (s) => s.status === "idle" || s.status === "archival_candidate",
        )
        .sort((a, b) => (b.days_since_last ?? 0) - (a.days_since_last ?? 0));

      let filed = 0;
      for (const entry of staleSkills) {
        if (filed >= CAP_PER_RUN) break;

        // Validate skill name
        if (!SKILL_NAME_RE.test(entry.name)) {
          logger.warn(
            { fn: "cron-skill-freshness", skillName: entry.name },
            "Refusing malformed skill name",
          );
          continue;
        }

        // De-dupe
        const exists = await searchExistingFreshnessIssue(
          octokit,
          entry.name,
        );
        if (exists) {
          logger.info(
            { fn: "cron-skill-freshness", skillName: entry.name },
            "Skipping — existing issue found",
          );
          continue;
        }

        try {
          await fileSkillIssue(octokit, entry);
          logger.info(
            { fn: "cron-skill-freshness", skillName: entry.name },
            "Filed stale-skill issue",
          );
          filed++;
        } catch (err) {
          reportSilentFallback(err, {
            feature: "cron-skill-freshness",
            op: "file-skill-issue",
            message: `Failed to file issue for ${entry.name}`,
            extra: { fn: "cron-skill-freshness", skillName: entry.name },
          });
        }
      }

      return filed;
    });

    // --- Step 5: Sentry heartbeat ---
    await step.run("sentry-heartbeat", async () => {
      await postSentryHeartbeat({
        ok: true,
        sentryMonitorSlug: SENTRY_MONITOR_SLUG,
        cronName: "cron-skill-freshness",
        logger,
      });
    });

    return {
      ok: true,
      totalSkills: result.summary.total_skills,
      idle: result.summary.idle_180d,
      archival: result.summary.idle_365d,
      neverInvoked: result.summary.never_invoked,
      issuesFiled,
    };
  } finally {
    await teardownEphemeralWorkspace(ephemeralRoot, "cron-skill-freshness").catch(
      (err) => {
        reportSilentFallback(err, {
          feature: "cron-skill-freshness",
          op: "teardown-ephemeral-workspace-finally",
          message: "teardownEphemeralWorkspace threw in finally block",
          extra: { fn: "cron-skill-freshness", ephemeralRoot },
        });
      },
    );
  }
}

// =============================================================================
// Registration
// =============================================================================

export const cronSkillFreshness = inngest.createFunction(
  {
    id: "cron-skill-freshness",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "0 2 1 * *" },
    { event: "cron/skill-freshness.manual-trigger" },
  ],
  cronSkillFreshnessHandler as unknown as Parameters<
    typeof inngest.createFunction
  >[2],
);
