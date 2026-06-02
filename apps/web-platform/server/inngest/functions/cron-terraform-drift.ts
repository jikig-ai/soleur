/**
 * cron-terraform-drift — Inngest-dispatched trigger for the terraform-drift
 * GitHub Actions workflow.
 *
 * DISPATCH HYBRID: this function is the SCHEDULER only. It fires on
 * `{ cron: "0 6,18 * * *" }` (≤2-min jitter) and triggers the EXISTING
 * `.github/workflows/scheduled-terraform-drift.yml` workflow via a
 * `workflow_dispatch` API call. The GHA workflow remains the EXECUTOR — it still
 * runs `terraform plan -detailed-exitcode` in an ephemeral runner with the
 * Doppler `prd_terraform` / R2 / AWS cloud-admin credentials, and its end-of-job
 * `sentry-heartbeat` step still checks into the `scheduled-terraform-drift`
 * Sentry monitor.
 *
 * Why dispatch-hybrid here, when ADR-033 REJECTED it (Option C) for the TR9
 * agent-loop crons: those crons run `claude-code`, and TR9 deliberately moved
 * their EXECUTION onto the Hetzner Node worker to gain replay-safety /
 * idempotency / observability — so a dispatch-only hybrid (scheduling moves,
 * execution stays on GHA) defeated their purpose. terraform-drift is the inverse
 * workload: its execution needs the terraform binary + R2/AWS/Doppler
 * `prd_terraform` cloud-admin credentials, which must NOT be parked on the app
 * server. Here the goal is ONLY to replace GHA's jittery `schedule:` trigger
 * (ADR-033's accepted rationale: GHA scheduling jitter is the problem), while
 * keeping execution exactly where it safely belongs. Dispatch-hybrid is the
 * correct shape for this credential-heavy infra cron, not a regression of TR9.
 *
 * Migrated off the GHA `schedule:` trigger because GitHub's scheduled-workflow
 * delivery jitter (observed up to 339 min late over a 58-day survey) forced the
 * Sentry monitor margin to 480 min just to suppress false "missed check-in"
 * alarms (superseded PR #4772). With Inngest as the single scheduling substrate
 * the jitter is gone and the margin tightens back to 60 min.
 *
 * HARD NON-GOAL: this function does NOT run terraform in-process and does NOT
 * clone the repo. terraform needs the binary + cloud-admin credentials; running
 * it inside the Node app server would park those credentials on the prod host —
 * a security/complexity regression. terraform stays in the ephemeral GHA runner.
 * This function ONLY dispatches; it holds nothing but a short-lived,
 * `actions: write`-scoped GitHub App installation token.
 *
 * Liveness (Design A — no own Sentry monitor):
 *  - Scheduler liveness: `cron-inngest-cron-watchdog` + the parity-guarded
 *    `EXPECTED_CRON_FUNCTIONS` manifest keep this cron in the watchdog's purview.
 *  - End-to-end liveness: if the dispatch never reaches the runner, no GHA
 *    heartbeat arrives and the existing `scheduled-terraform-drift` monitor goes
 *    red within its 60-min margin.
 *  - Dispatch error path: a token-mint / Octokit failure is reported loudly to
 *    the Sentry issues stream via `reportSilentFallback` (token redacted).
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

const FUNCTION_NAME = "cron-terraform-drift";
// The dispatches endpoint accepts the workflow FILE BASENAME as {workflow_id}
// (no numeric-ID lookup needed — see @octokit/openapi-types).
const WORKFLOW_FILE = "scheduled-terraform-drift.yml";
// One short-lived API call; a modest floor is plenty.
const TOKEN_MIN_LIFETIME_MS = 5 * 60 * 1000;

export async function cronTerraformDriftHandler({
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
        },
      );
    });

    logger.info(
      { fn: FUNCTION_NAME, workflow: WORKFLOW_FILE },
      "Dispatched terraform-drift workflow",
    );
    return { ok: true };
  } catch (err) {
    const e = err as Error;
    const redacted = new Error(
      redactToken(`${e.name}: ${e.message}`, installationToken),
    );
    reportSilentFallback(redacted, {
      feature: FUNCTION_NAME,
      op: "dispatch-workflow",
      message: "terraform-drift workflow_dispatch failed",
      extra: { fn: FUNCTION_NAME, workflow: WORKFLOW_FILE },
    });
    return { ok: false };
  }
}

export const cronTerraformDrift = inngest.createFunction(
  {
    id: "cron-terraform-drift",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "0 6,18 * * *" },
    { event: "cron/terraform-drift.manual-trigger" },
  ],
  cronTerraformDriftHandler as unknown as Parameters<
    typeof inngest.createFunction
  >[2],
);
