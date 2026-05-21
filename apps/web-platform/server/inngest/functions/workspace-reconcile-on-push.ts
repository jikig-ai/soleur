// #4224 — periodic workspace reconciliation. Inngest function on
// `platform/workspace.reconcile.requested` (dispatched by the GitHub
// webhook push branch in `app/api/webhooks/github/route.ts`).
//
// Coalescing primitive is Inngest CEL concurrency keyed on installation_id
// — `--ff-only` makes redundant pulls idempotent, so we do NOT need an
// in-process Map (DHH + Simplicity convergence in plan-review). No throttle
// either: CEL already serializes per-installation, and rapid pushes that
// CEL skips re-converge at the operator's next session-boundary sync.
//
// Failure mirroring uses the canonical `reportSilentFallback` helper with
// explicit `message:` arg (PR #3731 sharp-edge — dashboard keying breaks
// without it). Per-failure-class `op:` tags surface in Sentry so the
// 30-day drift analysis (TR4 / DS1 gating) can slice by class.

import { inngest } from "@/server/inngest/client";
import { getFreshTenantClient } from "@/lib/supabase/tenant";
import { reportSilentFallback } from "@/server/observability";
import { syncWorkspace } from "@/server/kb-route-helpers";
import { appendKbSyncRow } from "@/server/session-sync";
import logger from "@/server/logger";

interface UserRow {
  workspace_path: string | null;
  workspace_status: string | null;
  github_installation_id: number | null;
  kb_sync_history: unknown[] | null;
}

interface ReconcileEvent {
  name: string;
  v?: string;
  data: {
    founderId: string;
    installationId: number;
    deliveryId: string;
    defaultBranch: string;
    headSha: string;
    beforeSha: string;
    pushReceivedAt?: number;
  };
}

interface HandlerArgs {
  event: ReconcileEvent;
  step: {
    run<T>(name: string, cb: () => Promise<T>): Promise<T>;
  };
  logger: {
    warn: (...args: unknown[]) => void;
    info: (...args: unknown[]) => void;
    error: (...args: unknown[]) => void;
  };
}

export async function workspaceReconcileOnPushHandler({
  event,
  step,
  logger: stepLogger,
}: HandlerArgs): Promise<
  | { ok: true }
  | { ok: false; reason: string }
> {
  // syncWorkspace expects a pino Logger; the Inngest `step.logger` only
  // exposes warn/info/error. Use the module-scoped pino logger for the
  // sync call (load-bearing for cq-silent-fallback-must-mirror-to-sentry
  // attribution — kb-route-helpers tags its `feature` on this site).
  void stepLogger;
  const { founderId, installationId, deliveryId, headSha, beforeSha, pushReceivedAt } = event.data;

  // Step 1: fetch user row. Defense-in-depth — the dispatcher already
  // resolved founderId via the partial-UNIQUE github_installation_id
  // index, but installs can be uninstalled between dispatch and Inngest
  // pickup. Skip + Sentry-mirror without touching the filesystem.
  const userRow = await step.run("fetch-user-row", async () => {
    const tenant = await getFreshTenantClient(founderId);
    const { data, error } = await tenant
      .from("users")
      .select("workspace_path, workspace_status, github_installation_id, kb_sync_history")
      .eq("id", founderId)
      .single();
    if (error || !data) return null;
    return data as UserRow;
  });

  if (!userRow) {
    reportSilentFallback(new Error("user row missing or unmapped"), {
      feature: "workspace-reconcile-push",
      op: "skip-unmapped",
      extra: { userId: founderId, installationId, deliveryId },
      message: "Reconcile skipped — founder no longer mapped to installation",
    });
    return { ok: false, reason: "unmapped-founder" };
  }

  const workspacePath = userRow.workspace_path;
  if (!workspacePath) {
    reportSilentFallback(new Error("workspace_path missing"), {
      feature: "workspace-reconcile-push",
      op: "skip-no-workspace",
      extra: { userId: founderId, installationId, deliveryId },
      message: "Reconcile skipped — workspace_path missing",
    });
    return { ok: false, reason: "no-workspace-path" };
  }

  // Step 2: workspace_status guard. Cloning / failed / never-cloned all
  // skip with a kb_sync_history row recording the class.
  if (userRow.workspace_status !== "ready") {
    reportSilentFallback(new Error("workspace not ready"), {
      feature: "workspace-reconcile-push",
      op: "skip-not-ready",
      extra: {
        userId: founderId,
        installationId,
        deliveryId,
        workspaceStatus: userRow.workspace_status,
      },
      message: "Workspace not ready — skipping reconcile",
    });
    await appendKbSyncRow(founderId, {
      at: new Date().toISOString(),
      trigger: "webhook_push",
      sha_before: beforeSha,
      sha_after: headSha,
      ok: false,
      error_class: "workspace_not_ready",
      push_received_at: pushReceivedAt,
      sync_completed_at: Date.now(),
    });
    return { ok: false, reason: "workspace-not-ready" };
  }

  // Step 3: pull. syncWorkspace is `--ff-only`, so a non-fast-forward
  // returns ok:false, error_class="non_fast_forward". We mirror to
  // Sentry and let the UI's KbSyncStatus flip to desync.
  const syncResult = await syncWorkspace(installationId, workspacePath, logger, {
    userId: founderId,
    op: "push",
  });

  const completedAt = Date.now();
  if (!syncResult.ok) {
    reportSilentFallback(syncResult.error, {
      feature: "workspace-reconcile-push",
      op: "sync",
      extra: { userId: founderId, installationId, deliveryId, workspacePath },
      message: "Workspace sync failed",
    });
    await appendKbSyncRow(founderId, {
      at: new Date().toISOString(),
      trigger: "webhook_push",
      sha_before: beforeSha,
      sha_after: headSha,
      ok: false,
      error_class: "non_fast_forward",
      push_received_at: pushReceivedAt,
      sync_completed_at: completedAt,
    });
    return { ok: false, reason: "sync-failed" };
  }

  await appendKbSyncRow(founderId, {
    at: new Date().toISOString(),
    trigger: "webhook_push",
    sha_before: beforeSha,
    sha_after: headSha,
    ok: true,
    push_received_at: pushReceivedAt,
    sync_completed_at: completedAt,
  });

  return { ok: true };
}

export const workspaceReconcileOnPush = inngest.createFunction(
  {
    id: "workspace-reconcile-on-push",
    // CEL key per Inngest concurrency docs. Per-installation_id
    // serialization is sufficient — rapid pushes on the same installation
    // converge on the same `--ff-only` HEAD; cross-installation events
    // run in parallel.
    concurrency: [
      { scope: "fn", key: '"wsr-" + event.data.installationId', limit: 1 },
      { scope: "account", key: '"agent-runtime"', limit: 50 },
    ],
    retries: 1,
  },
  { event: "platform/workspace.reconcile.requested" },
  workspaceReconcileOnPushHandler as unknown as Parameters<typeof inngest.createFunction>[2],
);
