// Workspace sync-health probe — detects workspaces that are connected
// (repo_status='ready') but UNREACHABLE by the webhook-driven reconcile
// because their github_installation_id is NULL.
//
// Why this exists: KB sync is driven entirely by the GitHub push webhook,
// which resolves target workspaces with
//   WHERE github_installation_id = <push.installation.id> AND repo_url = <repo>
// (workspace-reconcile-on-push.ts). A workspace whose github_installation_id
// is NULL — e.g. a legacy connection that predates the GitHub App model, or a
// row left behind by an incomplete re-auth — can NEVER match that filter, so
// it silently never syncs AND writes zero kb_sync_history rows (it never even
// enters the fan-out loop). That exact state froze the founder's own KB for
// ~5 weeks before anyone noticed, because nothing was loud.
//
// This cron makes that class loud: a daily read-only scan that reports each
// `repo_status='ready' AND github_installation_id IS NULL` workspace to Sentry
// via reportSilentFallback. It mutates nothing (a state flip to 'error' would
// 409 the /api/kb/tree read and BLANK the user's tree — strictly worse than a
// stale-but-visible tree), so there is no migration and no UI change.
//
// ADR-033 invariants: I1 (all IO inside step.run), I2 (no claude/BYOK),
// I5 (deterministic step.run return shapes), I6 (emits no Inngest events).

import { inngest } from "@/server/inngest/client";
import { reportSilentFallback } from "@/server/observability";
import { postSentryHeartbeat, type HandlerArgs } from "./_cron-shared";

const SENTRY_MONITOR_SLUG = "cron-workspace-sync-health";
const SENTRY_FEATURE = "workspace-sync-health";

interface ScanResult {
  ok: boolean;
  findings: { workspaceId: string; repoUrl: string | null }[];
  error: string | null;
}

export async function cronWorkspaceSyncHealthHandler({
  step,
  logger,
}: HandlerArgs): Promise<ScanResult> {
  // Step 1: scan workspaces for the ready-but-unreconcilable class.
  const scan = await step.run("scan-ready-null-installation", async (): Promise<ScanResult> => {
    const { createServiceClient } = await import("@/lib/supabase/service");
    const service = createServiceClient();
    const { data, error } = await service
      .from("workspaces")
      .select("id, repo_url")
      .eq("repo_status", "ready")
      .is("github_installation_id", null);
    if (error) {
      reportSilentFallback(error, {
        feature: SENTRY_FEATURE,
        op: "scan",
        message: "Workspace sync-health scan failed",
      });
      return { ok: false, findings: [], error: error.message };
    }
    const rows = (data as { id: string; repo_url: string | null }[] | null) ?? [];
    return {
      ok: true,
      findings: rows.map((r) => ({ workspaceId: r.id, repoUrl: r.repo_url })),
      error: null,
    };
  });

  // Step 2: report each unreachable workspace. Each is a workspace the user
  // believes is connected ('ready') but that the reconcile can never select.
  if (scan.ok && scan.findings.length > 0) {
    await step.run("report-unreachable-workspaces", async () => {
      for (const f of scan.findings) {
        reportSilentFallback(
          new Error("ready workspace has NULL github_installation_id — unreachable by reconcile"),
          {
            feature: SENTRY_FEATURE,
            op: "ready-null-installation",
            extra: { workspaceId: f.workspaceId, repoUrl: f.repoUrl },
            message:
              "Workspace is repo_status=ready but github_installation_id is NULL — KB sync can never run; needs GitHub App re-authorization",
          },
        );
      }
      return { reported: scan.findings.length };
    });
  }

  // Step 3: Sentry heartbeat. ok = the scan itself ran (findings are expected
  // signal, not a probe failure).
  await step.run("sentry-heartbeat", async () => {
    await postSentryHeartbeat({
      ok: scan.ok,
      sentryMonitorSlug: SENTRY_MONITOR_SLUG,
      cronName: "cron-workspace-sync-health",
      logger,
    });
  });

  return scan;
}

export const cronWorkspaceSyncHealth = inngest.createFunction(
  {
    id: "cron-workspace-sync-health",
    concurrency: [
      { scope: "fn", limit: 1 },
      { scope: "account", key: '"cron-platform"', limit: 1 },
    ],
    retries: 1,
  },
  [
    { cron: "23 6 * * *" },
    { event: "cron/workspace-sync-health.manual-trigger" },
  ],
  cronWorkspaceSyncHealthHandler as unknown as Parameters<
    typeof inngest.createFunction
  >[2],
);
