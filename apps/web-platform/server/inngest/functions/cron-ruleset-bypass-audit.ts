// TR9 Phase-2 — Daily audit of the GitHub "CI Required" ruleset's
// bypass_actors against a canonical JSON snapshot. Detects drift
// (someone widened the bypass actors list) and files compliance/critical
// issues. Uses GitHub App auth (driftguard) for elevated ruleset access.
//
// Migrated from .github/workflows/scheduled-ruleset-bypass-audit.yml
// (deleted in the same PR per TR9 I-13 hygiene). Pure TS port — no
// agent spawn, no ephemeral workspace. All IO via Octokit
// (installation-scoped token).
//
// ADR-033 invariants:
//   I1 — All outbound IO is inside step.run for Inngest replay memoization.
//   I2 — Trivially satisfied: no claude / no BYOK lease.
//   I3 — No long-running subprocess; Octokit timeout bounds wallclock.
//   I5 — Deterministic step.run return shapes.
//   I6 — N/A; this function emits no Inngest events.

import type { Octokit } from "@octokit/core";
import { inngest } from "@/server/inngest/client";
import { reportSilentFallback } from "@/server/observability";
import {
  REPO_OWNER,
  REPO_NAME,
  mintInstallationToken,
  postSentryHeartbeat,
  type HandlerArgs,
} from "./_cron-shared";

// =============================================================================
// Constants
// =============================================================================

const SENTRY_MONITOR_SLUG = "scheduled-ruleset-bypass-audit";

// Installation-token lifetime floor: 15-min headroom for a handful of API calls.
const TOKEN_MIN_LIFETIME_MS = 15 * 60 * 1000;

const CANONICAL_BYPASS_ACTORS_PATH =
  "scripts/ci-required-ruleset-canonical-bypass-actors.json";

const RULESET_NAME = "CI Required";

const DRIFT_ISSUE_TITLE =
  "[Ruleset Audit] CI Required bypass_actors drift";

const DRIFT_LABELS = ["ci/auth-broken", "compliance/critical"] as const;

// =============================================================================
// Types
// =============================================================================

export interface BypassActor {
  actor_id: number | null;
  actor_type: string;
  bypass_mode: string;
}

// =============================================================================
// Helpers — comparison logic
// =============================================================================

/**
 * Compare canonical vs actual bypass actors.
 *
 * Returns:
 *   - `drift: true` if actual has actors NOT in canonical (widened).
 *   - `removed` list if canonical has actors NOT in actual (narrowed, warn only).
 *   - `match: true` if sets are identical.
 */
export function compareBypassActors(
  canonical: BypassActor[],
  actual: BypassActor[],
): {
  drift: boolean;
  added: BypassActor[];
  removed: BypassActor[];
  match: boolean;
} {
  const key = (a: BypassActor) =>
    `${a.actor_id ?? "null"}|${a.actor_type}|${a.bypass_mode}`;

  const canonicalKeys = new Set(canonical.map(key));
  const actualKeys = new Set(actual.map(key));

  const added = actual.filter((a) => !canonicalKeys.has(key(a)));
  const removed = canonical.filter((a) => !actualKeys.has(key(a)));

  return {
    drift: added.length > 0,
    added,
    removed,
    match: added.length === 0 && removed.length === 0,
  };
}

// =============================================================================
// Helpers — Octokit operations
// =============================================================================

async function fetchCanonicalBypassActors(
  octokit: Octokit,
): Promise<BypassActor[]> {
  const resp = (await octokit.request(
    "GET /repos/{owner}/{repo}/contents/{path}",
    {
      owner: REPO_OWNER,
      repo: REPO_NAME,
      path: CANONICAL_BYPASS_ACTORS_PATH,
    },
  )) as { data: { content?: string; encoding?: string } };

  if (!resp.data.content || resp.data.encoding !== "base64") {
    throw new Error(
      `Unexpected content encoding for ${CANONICAL_BYPASS_ACTORS_PATH}: ${resp.data.encoding}`,
    );
  }

  const decoded = Buffer.from(resp.data.content, "base64").toString("utf-8");
  return JSON.parse(decoded) as BypassActor[];
}

async function fetchActualBypassActors(
  octokit: Octokit,
): Promise<BypassActor[]> {
  // List all rulesets for the repo, find "CI Required"
  const resp = (await octokit.request("GET /repos/{owner}/{repo}/rulesets", {
    owner: REPO_OWNER,
    repo: REPO_NAME,
    per_page: 100,
  })) as {
    data: Array<{
      id: number;
      name: string;
      bypass_actors?: BypassActor[];
    }>;
  };

  const ruleset = resp.data.find((r) => r.name === RULESET_NAME);
  if (!ruleset) {
    throw new Error(
      `Ruleset "${RULESET_NAME}" not found in ${REPO_OWNER}/${REPO_NAME}`,
    );
  }

  // The list endpoint may not include bypass_actors; fetch the individual ruleset
  const detail = (await octokit.request(
    "GET /repos/{owner}/{repo}/rulesets/{ruleset_id}",
    {
      owner: REPO_OWNER,
      repo: REPO_NAME,
      ruleset_id: ruleset.id,
    },
  )) as {
    data: {
      id: number;
      name: string;
      bypass_actors?: BypassActor[];
    };
  };

  if (!detail.data.bypass_actors) {
    throw new Error(
      `Ruleset "${RULESET_NAME}" response missing bypass_actors — ` +
        "installation token may lack administration:write scope",
    );
  }

  return detail.data.bypass_actors;
}

async function searchExistingDriftIssue(
  octokit: Octokit,
): Promise<number | null> {
  const resp = (await octokit.request("GET /repos/{owner}/{repo}/issues", {
    owner: REPO_OWNER,
    repo: REPO_NAME,
    state: "open",
    labels: DRIFT_LABELS.join(","),
    per_page: 100,
  })) as { data: Array<{ number: number; title: string }> };

  const existing = resp.data.find((i) => i.title === DRIFT_ISSUE_TITLE);
  return existing?.number ?? null;
}

async function fileDriftIssue(
  octokit: Octokit,
  added: BypassActor[],
): Promise<number> {
  const body =
    `## CI Required ruleset bypass_actors drift detected\n\n` +
    `The live \`CI Required\` ruleset has bypass actors NOT present in the ` +
    `canonical snapshot at \`${CANONICAL_BYPASS_ACTORS_PATH}\`.\n\n` +
    `### Added actors (drift)\n\n` +
    "```json\n" +
    JSON.stringify(added, null, 2) +
    "\n```\n\n" +
    `### What to do\n\n` +
    `1. If the addition is intentional, update the canonical snapshot.\n` +
    `2. If the addition is unauthorized, revert via ` +
    `\`scripts/update-ci-required-ruleset.sh\`.\n\n` +
    `See [ruleset-bypass-drift.md runbook](https://github.com/${REPO_OWNER}/${REPO_NAME}/blob/main/knowledge-base/engineering/operations/runbooks/ruleset-bypass-drift.md).\n\n` +
    `_Auto-created by the [scheduled-ruleset-bypass-audit Inngest function](https://github.com/${REPO_OWNER}/${REPO_NAME}/blob/main/apps/web-platform/server/inngest/functions/cron-ruleset-bypass-audit.ts)._`;

  const resp = (await octokit.request("POST /repos/{owner}/{repo}/issues", {
    owner: REPO_OWNER,
    repo: REPO_NAME,
    title: DRIFT_ISSUE_TITLE,
    body,
    labels: [...DRIFT_LABELS, "priority/p1-high"],
  })) as { data: { number: number } };

  return resp.data.number;
}

// =============================================================================
// Handler
// =============================================================================

export async function cronRulesetBypassAuditHandler({
  step,
  logger,
}: HandlerArgs): Promise<{
  ok: boolean;
  drift: boolean;
  addedCount: number;
  removedCount: number;
  issueNumber: number | null;
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

  // --- Step 2: audit bypass actors ---
  const result = await step.run("audit-bypass-actors", async () => {
    const { Octokit: OctokitCtor } = await import("@octokit/core");
    const octokit = new OctokitCtor({
      auth: installationToken,
    }) as unknown as Octokit;

    // Fetch canonical and actual bypass actors in parallel
    const [canonical, actual] = await Promise.all([
      fetchCanonicalBypassActors(octokit),
      fetchActualBypassActors(octokit),
    ]);

    const comparison = compareBypassActors(canonical, actual);

    if (comparison.match) {
      logger.info(
        { fn: "cron-ruleset-bypass-audit" },
        "Bypass actors match canonical — no drift",
      );
      return {
        drift: false,
        addedCount: 0,
        removedCount: 0,
        issueNumber: null as number | null,
      };
    }

    // Log removed actors (warning only)
    if (comparison.removed.length > 0) {
      logger.warn(
        {
          fn: "cron-ruleset-bypass-audit",
          removed: comparison.removed,
        },
        "Bypass actors removed from live ruleset (not in canonical) — warning only",
      );
    }

    // If drift (added actors), file an issue
    let issueNumber: number | null = null;
    if (comparison.drift) {
      logger.warn(
        {
          fn: "cron-ruleset-bypass-audit",
          added: comparison.added,
        },
        "DRIFT: bypass actors added to live ruleset not in canonical",
      );

      // De-dupe: check for existing open issue
      const existingIssueNumber = await searchExistingDriftIssue(octokit);
      if (existingIssueNumber) {
        logger.info(
          {
            fn: "cron-ruleset-bypass-audit",
            issueNumber: existingIssueNumber,
          },
          "Drift issue already open — skipping creation",
        );
        issueNumber = existingIssueNumber;
      } else {
        try {
          issueNumber = await fileDriftIssue(octokit, comparison.added);
          logger.info(
            { fn: "cron-ruleset-bypass-audit", issueNumber },
            "Filed drift issue",
          );
        } catch (err) {
          reportSilentFallback(err, {
            feature: "cron-ruleset-bypass-audit",
            op: "file-drift-issue",
            message: "Failed to file drift issue",
            extra: { fn: "cron-ruleset-bypass-audit" },
          });
        }
      }
    }

    return {
      drift: comparison.drift,
      addedCount: comparison.added.length,
      removedCount: comparison.removed.length,
      issueNumber,
    };
  });

  // --- Step 3: Sentry heartbeat ---
  const ok = !result.drift;
  await step.run("sentry-heartbeat", async () => {
    await postSentryHeartbeat({
      ok,
      sentryMonitorSlug: SENTRY_MONITOR_SLUG,
      cronName: "cron-ruleset-bypass-audit",
      logger,
    });
  });

  return { ok, ...result };
}

// =============================================================================
// Registration
// =============================================================================

export const cronRulesetBypassAudit = inngest.createFunction(
  {
    id: "cron-ruleset-bypass-audit",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "13 6 * * *" },
    { event: "cron/ruleset-bypass-audit.manual-trigger" },
  ],
  cronRulesetBypassAuditHandler as unknown as Parameters<
    typeof inngest.createFunction
  >[2],
);
