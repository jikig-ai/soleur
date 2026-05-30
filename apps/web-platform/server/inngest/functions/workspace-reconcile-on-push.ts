// #4224 + ADR-044 — periodic workspace reconciliation. Inngest function on
// `platform/workspace.reconcile.requested` (dispatched by the GitHub webhook
// push branch in `app/api/webhooks/github/route.ts`).
//
// ADR-044 re-architecture: repo state moved from `users` to `workspaces`, so
// a push fans out to EVERY workspace connected to (installation_id, repo).
// The target repo is composed from the event's bare `fullName` slug
// (`https://github.com/<fullName>`) then normalized — the TS↔SQL
// normalizeRepoUrl parity (test/repo-url-sql-parity.test.ts) is the sole
// matching contract. Workspace path is derived directly from the workspace
// id (`<WORKSPACES_ROOT>/<workspace_id>`); readiness is a filesystem-
// existence check (no `users.workspace_status` dependency). kb_sync_history
// rows are attributed to each workspace's owner.
//
// Coalescing primitive is Inngest CEL concurrency keyed on installation_id.
// Failure mirroring uses `reportSilentFallback` with explicit `message:`.

import { promises as fs } from "node:fs";
import { inngest } from "@/server/inngest/client";
import {
  reportSilentFallback,
  warnSilentFallback,
} from "@/server/observability";
import { syncWorkspace } from "@/server/kb-route-helpers";
import { normalizeRepoUrl } from "@/lib/repo-url";
import { workspacePathForWorkspaceId } from "@/server/workspace-resolver";
import {
  WORKSPACE_RECONCILE_REQUESTED_EVENT,
  WORKSPACE_RECONCILE_SCHEMA_V,
  WORKSPACE_RECONCILE_SENTRY_FEATURE,
  ERROR_CLASS_NON_FAST_FORWARD,
  ERROR_CLASS_WORKSPACE_NOT_READY,
  ERROR_CLASS_SYNC_FAILED,
  appendKbSyncRow,
} from "@/server/session-sync";
import logger from "@/server/logger";

interface ReconcileEvent {
  name: string;
  v?: string;
  data: {
    // founderId = the installation owner (webhook 404-lookup). Carried for
    // observability; the fan-out targets workspaces by repo, not founder.
    founderId: string;
    installationId: number;
    deliveryId: string;
    defaultBranch: string;
    headSha: string;
    beforeSha: string;
    // ADR-044: bare owner/repo slug from repository.full_name (v=2).
    fullName: string;
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

// Repos the GitHub App is installed on but that are intentionally NOT customer
// workspaces (e.g. Soleur's own dev repo `jikig-ai/soleur`). Every push there
// matches zero workspaces, so without this short-circuit each push emits a
// benign "no-workspace-match" skip — the dominant source of that Sentry issue
// (verified: 100% of recent skip events were `jikig-ai/soleur`). Comma-
// separated `owner/repo` slugs, overridable via env so a future internal repo
// can be added without a code change.
//
// Matched against the EXACT `owner/repo` path segment, not as a raw substring:
// an unanchored `includes("jikig-ai/soleur")` would also swallow a legitimate
// customer repo like `jikig-ai/soleur-fork` and drop it silently (no DB query,
// no log, no Sentry). Exact path-segment equality keeps the default safe and
// makes a misconfigured env override fail loudly (no match → normal path) rather
// than silently dropping a customer's reconcile.
const RECONCILE_IGNORED_REPO_SLUGS = (
  process.env.WORKSPACE_RECONCILE_IGNORE_REPOS ?? "jikig-ai/soleur"
)
  .split(",")
  .map((s) => s.trim())
  // Accept either a bare `owner/repo` slug or a full URL; reduce both to the
  // `owner/repo` path so the comparison is shape-agnostic.
  .map((s) => s.replace(/^https?:\/\/[^/]+\//i, "").replace(/\.git$/i, ""))
  .filter(Boolean);

function repoSlug(repoUrl: string): string {
  return repoUrl.replace(/^https?:\/\/[^/]+\//i, "").replace(/\.git$/i, "");
}

function isIgnoredReconcileRepo(repoUrl: string): boolean {
  const slug = repoSlug(repoUrl);
  return RECONCILE_IGNORED_REPO_SLUGS.some((s) => s === slug);
}

async function workspaceDirExists(path: string): Promise<boolean> {
  try {
    const st = await fs.stat(path);
    return st.isDirectory();
  } catch {
    return false;
  }
}

export async function workspaceReconcileOnPushHandler({
  event,
  step,
  logger: stepLogger,
}: HandlerArgs): Promise<{ ok: true; synced: number } | { ok: false; reason: string }> {
  void stepLogger;
  const { installationId, deliveryId, fullName, headSha, beforeSha, pushReceivedAt } =
    event.data;

  // Schema-gate. Non-throwing — an in-flight v=1 envelope (no fullName)
  // should drain to {ok:false}, not burn a retry. The webhook now emits v=2
  // with fullName; v=1 events persisted up to ~24h replay through here.
  const v = event.v ?? "0";
  const gate = await step.run("schema-gate", async () => {
    if (v !== WORKSPACE_RECONCILE_SCHEMA_V) {
      return { deadletter: true as const, reason: `schema_v=${v}` };
    }
    return { deadletter: false as const, reason: "" };
  });
  if (gate.deadletter) {
    // Expected drain of an in-flight v=1 envelope (the webhook now emits v=2);
    // observable at warning level rather than returning silently.
    warnSilentFallback(new Error("reconcile event drained (schema version)"), {
      feature: WORKSPACE_RECONCILE_SENTRY_FEATURE,
      op: "deadletter-schema-version",
      extra: { installationId, deliveryId, schemaV: v },
      message: "Reconcile drained — unsupported schema version",
    });
    return { ok: false, reason: gate.reason };
  }

  // Compose-before-normalize (ADR-044 P0): repository.full_name is a bare
  // `owner/repo` slug; workspaces.repo_url stores a full URL. Compose the
  // URL FIRST or the match is zero-rows while a URL→URL parity test passes.
  const targetRepoUrl = normalizeRepoUrl(`https://github.com/${fullName}`);

  // Platform-internal repo (the GitHub App is installed on it, but it is not a
  // customer workspace). Short-circuit BEFORE the DB query and BEFORE any
  // log/Sentry emission — these pushes are expected and carry zero signal.
  if (isIgnoredReconcileRepo(targetRepoUrl)) {
    return { ok: false, reason: "ignored-internal-repo" };
  }

  // Resolve EVERY workspace connected to (installation_id, repo). Service
  // client: the webhook is a trusted post-signature-verification context and
  // workspaces may be owned by different users (two-users-same-fork). The
  // (installation_id, repo_url) filter makes the old install-mismatch
  // defense-in-depth check structural — every match has the right install.
  const workspaces = await step.run("resolve-workspaces", async () => {
    const { createServiceClient } = await import("@/lib/supabase/service");
    const service = createServiceClient();
    const { data, error } = await service
      .from("workspaces")
      .select("id")
      .eq("github_installation_id", installationId)
      .eq("repo_url", targetRepoUrl);
    if (error) {
      return { rows: null as { id: string }[] | null, error };
    }
    return { rows: (data as { id: string }[] | null) ?? [], error: null };
  });

  if (workspaces.error) {
    reportSilentFallback(workspaces.error, {
      feature: WORKSPACE_RECONCILE_SENTRY_FEATURE,
      op: "resolve-workspaces",
      extra: { installationId, deliveryId, targetRepoUrl },
      message: "Reconcile aborted — workspace resolution failed",
    });
    return { ok: false, reason: "workspace-resolve-failed" };
  }

  const rows = workspaces.rows ?? [];
  if (rows.length === 0) {
    // Expected, benign outcome -- app uninstalled, repo not yet onboarded, a
    // disconnected fork, or a stale/replayed webhook. NOT actionable. Logged to
    // Better Stack (pino) for the drain but deliberately NOT mirrored to Sentry:
    // it is a by-design skip, and the prior in-process `mirrorWarnWithDebounce`
    // could not bound it across the platform's container churn (each new worker
    // resets the debounce map), so every push still created Sentry issues +
    // alert emails for zero signal. Genuine resolution errors still page via the
    // reportSilentFallback path above; the platform's own dev repo is handled
    // earlier by the ignored-repo short-circuit.
    logger.info(
      {
        feature: WORKSPACE_RECONCILE_SENTRY_FEATURE,
        op: "skip-no-workspace-match",
        installationId,
        deliveryId,
        targetRepoUrl,
      },
      "Reconcile skipped — no workspace connected to this repo",
    );
    return { ok: false, reason: "no-workspace-match" };
  }

  // Fan out: process every matching workspace independently. A push to a
  // shared repo legitimately affects all connected workspaces.
  let synced = 0;
  for (const ws of rows) {
    const outcome = await step.run(`reconcile-${ws.id}`, async () => {
      const { createServiceClient } = await import("@/lib/supabase/service");
      const service = createServiceClient();

      // Owner for kb_sync_history attribution (the workspace's owner row).
      const { data: ownerRow } = await service
        .from("workspace_members")
        .select("user_id")
        .eq("workspace_id", ws.id)
        .eq("role", "owner")
        .maybeSingle();
      const ownerId = (ownerRow as { user_id?: string } | null)?.user_id ?? null;

      const workspacePath = workspacePathForWorkspaceId(ws.id);

      // Readiness = filesystem existence (ADR-044, operator decision). A
      // not-yet-provisioned workspace dir skips without touching git.
      if (!(await workspaceDirExists(workspacePath))) {
        reportSilentFallback(new Error("workspace dir missing"), {
          feature: WORKSPACE_RECONCILE_SENTRY_FEATURE,
          op: "skip-not-ready",
          extra: { workspaceId: ws.id, installationId, deliveryId },
          message: "Workspace dir not provisioned — skipping reconcile",
        });
        if (ownerId) {
          const skipAt = Date.now();
          await appendKbSyncRow(ownerId, {
            at: new Date(skipAt).toISOString(),
            trigger: "webhook_push",
            sha_before: beforeSha,
            sha_after: headSha,
            ok: false,
            error_class: ERROR_CLASS_WORKSPACE_NOT_READY,
            push_received_at: pushReceivedAt,
            sync_completed_at: skipAt,
          });
        }
        return { synced: false };
      }

      const syncResult = await syncWorkspace(installationId, workspacePath, logger, {
        userId: ownerId ?? ws.id,
        op: "push",
      });

      const completedAt = Date.now();
      const at = new Date(completedAt).toISOString();

      if (!syncResult.ok) {
        reportSilentFallback(syncResult.error, {
          feature: WORKSPACE_RECONCILE_SENTRY_FEATURE,
          op: "sync",
          extra: { workspaceId: ws.id, installationId, deliveryId },
          message: "Workspace sync failed",
        });
        if (ownerId) {
          await appendKbSyncRow(ownerId, {
            at,
            trigger: "webhook_push",
            sha_before: beforeSha,
            sha_after: headSha,
            ok: false,
            error_class: ERROR_CLASS_SYNC_FAILED,
            push_received_at: pushReceivedAt,
            sync_completed_at: completedAt,
          });
        }
        return { synced: false };
      }

      if (ownerId) {
        await appendKbSyncRow(ownerId, {
          at,
          trigger: "webhook_push",
          sha_before: beforeSha,
          sha_after: headSha,
          ok: true,
          push_received_at: pushReceivedAt,
          sync_completed_at: completedAt,
        });
      }
      return { synced: true };
    });
    if (outcome.synced) synced += 1;
  }

  if (synced === 0) {
    // Intentionally silent: every path that lands here already emitted its own
    // mirror inside the fan-out loop (reportSilentFallback op="sync" on sync
    // failure, op="skip-not-ready" on a missing workspace dir). An aggregate
    // mirror here would double-report the same incident. (cq-silent-fallback-
    // must-mirror-to-sentry is satisfied by the per-workspace sites.)
    return { ok: false, reason: "no-workspace-synced" };
  }
  return { ok: true, synced };
}

// Re-exported for test convenience.
export {
  ERROR_CLASS_NON_FAST_FORWARD,
  ERROR_CLASS_WORKSPACE_NOT_READY,
  ERROR_CLASS_SYNC_FAILED,
};

export const workspaceReconcileOnPush = inngest.createFunction(
  {
    id: "workspace-reconcile-on-push",
    // CEL key per Inngest concurrency docs. `string(...)` coercion is
    // load-bearing — installationId is a number and CEL `+` does not
    // auto-coerce string + int.
    concurrency: [
      { scope: "fn", key: '"wsr-" + string(event.data.installationId)', limit: 1 },
      { scope: "account", key: '"agent-runtime"', limit: 50 },
    ],
    retries: 1,
  },
  { event: WORKSPACE_RECONCILE_REQUESTED_EVENT },
  workspaceReconcileOnPushHandler as unknown as Parameters<typeof inngest.createFunction>[2],
);
