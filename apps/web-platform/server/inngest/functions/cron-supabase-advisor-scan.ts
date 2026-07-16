/**
 * cron-supabase-advisor-scan — Inngest-dispatched trigger for the nightly
 * "no public table without RLS" gate (#3366).
 *
 * DISPATCH HYBRID: this function is the SCHEDULER only. It fires nightly and
 * triggers `.github/workflows/scheduled-supabase-advisor-scan.yml` via
 * `workflow_dispatch`. The GHA workflow remains the EXECUTOR.
 *
 * Why the scan does NOT run in-process here: it needs a Supabase Management API
 * personal access token — a cloud-admin credential. Parking that on the
 * long-lived app host is exactly what ADR-033's scope note calls actively
 * harmful, and the split is already load-bearing elsewhere in this codebase:
 * cron-supabase-disk-io.ts notes that "the runtime container has the
 * service-role key but NOT a Management API PAT". This function therefore holds
 * nothing but a short-lived, `actions: write`-scoped GitHub App installation
 * token. Same shape as cron-terraform-drift.ts, and for the same reason.
 *
 * WHY `source: "inngest"` IS PASSED, AND WHY IT MATTERS
 * ====================================================
 * The workflow is `workflow_dispatch`-only and is advertised as manually
 * smoke-testable. Its Sentry check-in is gated on this input. Without the gate,
 * any human running `gh workflow run ...` would post an `ok` check-in and
 * satisfy the monitor's window — forging the liveness signal while THIS
 * dispatcher was dead for weeks. The check-in must mean "the scheduler fired
 * and the scan ran end-to-end", not merely "someone ran the workflow".
 *
 * 03:37 UTC is deliberate: 20 minutes after the `17 * * * *` hourly Inngest-RLS
 * self-heal, which minimizes the window in which the Supabase advisor is
 * legitimately stale and the gate has to fall back to its object-scoped
 * disagreement carve-out.
 *
 * Liveness (no own Sentry monitor, mirroring cron-terraform-drift):
 *  - Scheduler liveness: cron-inngest-cron-watchdog + the parity-guarded
 *    EXPECTED_CRON_FUNCTIONS manifest keep this cron in the watchdog's purview.
 *  - End-to-end liveness: if the dispatch never reaches the runner, no GHA
 *    heartbeat arrives and the `scheduled-supabase-advisor-scan` monitor goes
 *    red on a missed check-in.
 *  - Dispatch error path: a token-mint / Octokit failure is reported to the
 *    Sentry issues stream via reportSilentFallback (token redacted).
 */
import { inngest } from "@/server/inngest/client";
import {
  type HandlerArgs,
  mintInstallationToken,
  redactToken,
  REPO_NAME,
  REPO_OWNER,
} from "./_cron-shared";
import { reportSilentFallback } from "@/server/observability";

const FUNCTION_NAME = "cron-supabase-advisor-scan";
// The dispatches endpoint accepts the workflow FILE BASENAME as {workflow_id}.
const WORKFLOW_FILE = "scheduled-supabase-advisor-scan.yml";
// One short-lived API call; a modest floor is plenty.
const TOKEN_MIN_LIFETIME_MS = 5 * 60 * 1000;

export async function cronSupabaseAdvisorScanHandler({
  step,
  logger,
}: HandlerArgs): Promise<{ ok: boolean }> {
  const installationToken = await step.run(
    "mint-installation-token",
    async () =>
      mintInstallationToken({ tokenMinLifetimeMs: TOKEN_MIN_LIFETIME_MS }),
  );

  try {
    await step.run("dispatch-workflow", async () => {
      const { Octokit } = await import("@octokit/core");
      const octokit = new Octokit({ auth: installationToken });
      await octokit.request(
        "POST /repos/{owner}/{repo}/actions/workflows/{workflow_id}/dispatches",
        {
          owner: REPO_OWNER,
          repo: REPO_NAME,
          workflow_id: WORKFLOW_FILE,
          ref: "main",
          // Load-bearing: the workflow's Sentry check-in is gated on this.
          inputs: { source: "inngest" },
        },
      );
    });

    logger.info(
      { fn: FUNCTION_NAME, workflow: WORKFLOW_FILE },
      "Dispatched supabase-advisor-scan workflow",
    );
    return { ok: true };
  } catch (err) {
    const e = err as Error;
    // Redact the minted token out of the message before it reaches Sentry,
    // preserving the original Error.name as a field.
    const redacted = new Error(redactToken(e.message, installationToken));
    redacted.name = e.name;
    reportSilentFallback(redacted, {
      feature: FUNCTION_NAME,
      op: "dispatch-workflow",
      message: "supabase-advisor-scan workflow_dispatch failed",
      extra: { fn: FUNCTION_NAME, workflow: WORKFLOW_FILE },
    });
    return { ok: false };
  }
}

export const cronSupabaseAdvisorScan = inngest.createFunction(
  {
    id: "cron-supabase-advisor-scan",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "37 3 * * *" },
    { event: "cron/supabase-advisor-scan.manual-trigger" },
  ],
  cronSupabaseAdvisorScanHandler as unknown as Parameters<
    typeof inngest.createFunction
  >[2],
);
