// TR9 Phase-2 — Hourly team-membership health probe migrated to Inngest cron.
//
// Migrated from .github/workflows/scheduled-membership-health.yml (deleted
// in the same PR per TR9 I-13 hygiene). Pure TS port — no agent spawn,
// no ephemeral workspace, no claude binary. All IO via fetch + Octokit.
//
// ADR-033 invariants:
//   I1 — All outbound IO is inside step.run for Inngest replay memoization.
//   I2 — Trivially satisfied: no claude / no BYOK lease.
//   I3 — Per-fetch AbortSignal.timeout(10_000) bounds probe wallclock.
//   I5 — Deterministic step.run return shapes.
//   I6 — N/A; this function emits no Inngest events.
//
// NAME NOTE: Sentry monitor slug "scheduled-membership-health" preserves
// historical check-in continuity from the GHA workflow.

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

const SENTRY_MONITOR_SLUG = "scheduled-membership-health";

const FETCH_TIMEOUT_MS = 10_000;

// Installation-token lifetime floor: no agent spawn, so 15-min headroom
// is more than sufficient for a handful of API calls.
const TOKEN_MIN_LIFETIME_MS = 15 * 60 * 1000;

export const FLAGS_URL = "https://soleur.ai/api/flags?role=prd";
export const HEALTH_URL = "https://soleur.ai/api/health/team-membership";
export const FLAG_NAME = "team-workspace-invite";

const ISSUE_TITLE = "[P0] Team membership health degraded";
const ISSUE_LABELS = ["type/incident", "severity/p0", "area/workspace"];

// =============================================================================
// Helpers
// =============================================================================

interface FlagEntry {
  feature: { name: string };
  enabled: boolean;
}

async function checkFlag(): Promise<{ enabled: boolean; error?: string }> {
  try {
    const res = await fetch(FLAGS_URL, {
      signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
      headers: { "User-Agent": "soleur-membership-health-probe/1.0" },
    });
    if (res.status !== 200) {
      return { enabled: false, error: `FLAGS_URL returned HTTP ${res.status}` };
    }
    let json: unknown;
    try {
      json = await res.json();
    } catch {
      return { enabled: false, error: "FLAGS_URL returned non-JSON body" };
    }
    if (!Array.isArray(json)) {
      return { enabled: false, error: "FLAGS_URL returned non-array JSON" };
    }
    const flag = (json as FlagEntry[]).find(
      (f) => f.feature?.name === FLAG_NAME,
    );
    if (!flag) {
      return { enabled: false, error: `Flag "${FLAG_NAME}" not found in response` };
    }
    return { enabled: flag.enabled };
  } catch (err) {
    const e = err as Error;
    return {
      enabled: false,
      error: `FLAGS_URL fetch failed: ${e.name}: ${e.message}`,
    };
  }
}

interface HealthResult {
  degraded: boolean;
  detail: string;
}

async function checkHealth(): Promise<HealthResult> {
  try {
    const res = await fetch(HEALTH_URL, {
      signal: AbortSignal.timeout(FETCH_TIMEOUT_MS),
      headers: { "User-Agent": "soleur-membership-health-probe/1.0" },
    });
    if (res.status !== 200) {
      return {
        degraded: true,
        detail: `HEALTH_URL returned HTTP ${res.status}`,
      };
    }
    let json: unknown;
    try {
      json = await res.json();
    } catch {
      return { degraded: true, detail: "HEALTH_URL returned non-JSON body" };
    }
    const healthStatus = (json as { health_status?: string }).health_status;
    if (healthStatus !== "ok") {
      return {
        degraded: true,
        detail: `health_status=${String(healthStatus ?? "missing")}`,
      };
    }
    return { degraded: false, detail: "ok" };
  } catch (err) {
    const e = err as Error;
    return {
      degraded: true,
      detail: `HEALTH_URL fetch failed: ${e.name}: ${e.message}`,
    };
  }
}

// =============================================================================
// Handler
// =============================================================================

export async function cronMembershipHealthHandler({
  step,
  logger,
}: HandlerArgs): Promise<{
  ok: boolean;
  skipped: boolean;
  degraded: boolean;
  detail: string;
}> {
  // Step 1: check flag + health
  const probeResult = await step.run(
    "membership-health-probe",
    async (): Promise<{
      skipped: boolean;
      degraded: boolean;
      detail: string;
    }> => {
      // Check if flag is enabled
      const flagResult = await checkFlag();
      if (flagResult.error) {
        logger.info(
          { fn: "cron-membership-health", error: flagResult.error },
          "Flag check failed — skipping health probe (fail-closed-to-OFF)",
        );
        return { skipped: true, degraded: false, detail: flagResult.error };
      }
      if (!flagResult.enabled) {
        logger.info(
          { fn: "cron-membership-health" },
          "Flag team-workspace-invite is OFF — skipping health probe",
        );
        return { skipped: true, degraded: false, detail: "flag-off" };
      }

      // Flag is ON — probe health
      const healthResult = await checkHealth();
      return {
        skipped: false,
        degraded: healthResult.degraded,
        detail: healthResult.detail,
      };
    },
  );

  // Step 2: file/dedup incident issue on degraded
  if (probeResult.degraded) {
    await step.run("file-incident-issue", async () => {
      try {
        const token = await mintInstallationToken({
          tokenMinLifetimeMs: TOKEN_MIN_LIFETIME_MS,
        });
        const { Octokit } = await import("@octokit/core");
        const octokit = new Octokit({ auth: token });

        // Dedup: search for existing open issue with same title
        const search = await octokit.request("GET /search/issues", {
          q: `repo:${REPO_OWNER}/${REPO_NAME} is:issue is:open in:title "${ISSUE_TITLE}"`,
          per_page: 1,
        });
        const existing = (search.data.items ?? [])[0];
        if (existing) {
          await octokit.request(
            "POST /repos/{owner}/{repo}/issues/{issue_number}/comments",
            {
              owner: REPO_OWNER,
              repo: REPO_NAME,
              issue_number: existing.number,
              body: `Health probe degraded again at ${new Date().toISOString()} — ${probeResult.detail}`,
            },
          );
          logger.info(
            { fn: "cron-membership-health", issueNumber: existing.number },
            "Commented on existing incident issue",
          );
          return;
        }

        await octokit.request("POST /repos/{owner}/{repo}/issues", {
          owner: REPO_OWNER,
          repo: REPO_NAME,
          title: ISSUE_TITLE,
          labels: ISSUE_LABELS,
          body: [
            "## Team membership health degraded",
            "",
            `- **Detail:** ${probeResult.detail}`,
            `- **Detected at:** ${new Date().toISOString()}`,
            `- **Flag URL:** ${FLAGS_URL}`,
            `- **Health URL:** ${HEALTH_URL}`,
            "",
            "_Auto-created by the [cron-membership-health Inngest function](https://github.com/jikig-ai/soleur/blob/main/apps/web-platform/server/inngest/functions/cron-membership-health.ts)._",
          ].join("\n"),
        });
        logger.info(
          { fn: "cron-membership-health" },
          "Filed new incident issue",
        );
      } catch (err) {
        reportSilentFallback(err, {
          feature: "cron-membership-health",
          op: "file-incident-issue",
          message: "Failed to file/comment incident issue",
          extra: { fn: "cron-membership-health", detail: probeResult.detail },
        });
      }
    });
  }

  // Step 3: Sentry heartbeat
  const ok = !probeResult.degraded;
  await step.run("sentry-heartbeat", async () => {
    await postSentryHeartbeat({
      ok,
      sentryMonitorSlug: SENTRY_MONITOR_SLUG,
      cronName: "cron-membership-health",
      logger,
    });
  });

  return {
    ok,
    skipped: probeResult.skipped,
    degraded: probeResult.degraded,
    detail: probeResult.detail,
  };
}

// =============================================================================
// Registration
// =============================================================================

export const cronMembershipHealth = inngest.createFunction(
  {
    id: "cron-membership-health",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "17 * * * *" },
    { event: "cron/membership-health.manual-trigger" },
  ],
  cronMembershipHealthHandler as unknown as Parameters<
    typeof inngest.createFunction
  >[2],
);
