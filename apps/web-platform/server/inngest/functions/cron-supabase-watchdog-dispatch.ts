/**
 * cron-supabase-watchdog-dispatch — Inngest-dispatched trigger for the
 * Supabase Postgres-hang auto-restart watchdog workflow (#9168).
 *
 * DISPATCH HYBRID: this function is the SCHEDULER only. It fires on its cron
 * schedule (every 5 minutes, ≤2-min jitter) and triggers
 * `.github/workflows/scheduled-supabase-watchdog.yml` via a `workflow_dispatch`
 * API call. The GHA workflow remains the EXECUTOR — it runs the 3-read
 * Management-API health probe, the corroborator fetch, the extracted
 * classifier, the sentinel-ledger restart gate and the audit-issue writes in an
 * ephemeral runner, and posts the terminal `scheduled-supabase-watchdog` Sentry
 * heartbeat.
 *
 * WHY NOT `schedule:` — the workflow's own every-5-minutes cron is a FALLBACK,
 * kept byte-identical for the parity gates. GHA `schedule:` delivery was
 * measured drifting 2–7 h (ADR-248); a DB-hang detector that fires hours late
 * is no detector, so the primary trigger is an Inngest cron.
 *
 * WHY INNGEST DISPATCH IS ELIGIBLE HERE (and not, say, the
 * watchdog-dispatch-clock): the dispatch path is DB-INDEPENDENT — verified
 * in-tree: the serve route authenticates by HMAC INNGEST_SIGNING_KEY (env),
 * mintInstallationToken / generateInstallationToken read
 * GITHUB_APP_ID/GITHUB_APP_PRIVATE_KEY from env (Doppler), and Inngest
 * run-state lives on the dedicated host's Redis (ADR-100) — whose backing
 * Postgres is soleur-inngest-prd, a SEPARATE Supabase project from the
 * watched one. The web process stays up through this failure class — during
 * the 09-28 hang it kept serving /health with `supabase:error` — so an
 * Inngest cron survives a project-local hang and needs no
 * WATCHDOG_DISPATCH_TABLE exception. (Residual, accepted: the serve-route
 * middleware's terminal routine_runs row writes to the WATCHED project —
 * during a hang that write fails AFTER the dispatch already fired.)
 *
 * HARD NON-GOAL: this function does NOT probe Supabase and holds NO Supabase
 * credential — the Management-API PAT stays in the ephemeral GHA runner. This
 * function ONLY dispatches; it holds nothing but a short-lived,
 * `actions: write`-scoped GitHub App installation token bounded to this repo.
 *
 * Liveness:
 *  - Scheduler liveness: `cron-inngest-cron-watchdog` + the parity-guarded
 *    `EXPECTED_CRON_FUNCTIONS` manifest keep this cron in the watchdog's
 *    purview.
 *  - End-to-end liveness: if the dispatch never reaches the runner, no GHA
 *    heartbeat arrives and the `scheduled-supabase-watchdog` Sentry monitor
 *    goes red within its 30-min margin.
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

const FUNCTION_NAME = "cron-supabase-watchdog-dispatch";
// The dispatches endpoint accepts the workflow FILE BASENAME as {workflow_id}
// (no numeric-ID lookup needed — see @octokit/openapi-types).
const WORKFLOW_FILE = "scheduled-supabase-watchdog.yml";
// One short-lived API call; a modest floor is plenty.
const TOKEN_MIN_LIFETIME_MS = 5 * 60 * 1000;

export async function cronSupabaseWatchdogDispatchHandler({
  step,
  logger,
}: HandlerArgs): Promise<{ ok: boolean }> {
  const installationToken = await step.run(
    "mint-installation-token",
    async () =>
      mintInstallationToken({
        tokenMinLifetimeMs: TOKEN_MIN_LIFETIME_MS,
        // Least-privilege: the only call is the workflow_dispatch POST, which
        // needs actions:write and nothing else (hr-github-app-auth-not-pat +
        // the #5046 narrowed-token precedent). repositories pins the token to
        // this repo so a leaked token cannot be replayed elsewhere.
        permissions: { actions: "write" },
        repositories: [REPO_NAME],
      }),
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
      "Dispatched supabase-watchdog workflow",
    );
    return { ok: true };
  } catch (err) {
    const e = err as Error;
    // Redact the minted token out of the message before it reaches Sentry,
    // preserving the original Error.name as a field (matches the
    // cron-weekly-analytics precedent).
    const redacted = new Error(redactToken(e.message, installationToken));
    redacted.name = e.name;
    reportSilentFallback(redacted, {
      feature: FUNCTION_NAME,
      op: "dispatch-workflow",
      message: "supabase-watchdog workflow_dispatch failed",
      extra: { fn: FUNCTION_NAME, workflow: WORKFLOW_FILE },
    });
    return { ok: false };
  }
}

export const cronSupabaseWatchdogDispatch = inngest.createFunction(
  {
    id: "cron-supabase-watchdog-dispatch",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "*/5 * * * *" },
    { event: "cron/supabase-watchdog-dispatch.manual-trigger" },
  ],
  cronSupabaseWatchdogDispatchHandler as unknown as Parameters<
    typeof inngest.createFunction
  >[2],
);
