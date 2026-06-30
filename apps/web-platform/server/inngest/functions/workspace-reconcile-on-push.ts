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
// id (`<WORKSPACES_ROOT>/<workspace_id>`); readiness gates on git work-tree
// VALIDITY (`isValidGitWorkTree`, ADR-044 amendment 2026-06-29) — an INVALID or
// ABSENT `.git` is re-cloned via `ensureWorkspaceRepoCloned`, not skipped (no
// `users.workspace_status` dependency). kb_sync_history rows are attributed to
// each workspace's owner.
//
// Coalescing primitive is Inngest CEL concurrency keyed on installation_id.
// Failure mirroring uses `reportSilentFallback` with explicit `message:`.

import * as Sentry from "@sentry/nextjs";
import { inngest } from "@/server/inngest/client";
import {
  reportSilentFallback,
  warnSilentFallback,
  mirrorWarnWithDebounce,
} from "@/server/observability";
import { syncWorkspace } from "@/server/kb-route-helpers";
import {
  isReadyGitWorkTree,
  evaluateAgentReadiness,
  probeGitWorktreeShape,
} from "@/server/git-worktree-validity";
import { reportAgentReadinessSelfStop } from "@/server/repo-resolver-divergence";
import { ensureWorkspaceRepoCloned } from "@/server/ensure-workspace-repo";
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
  appendKbSyncRowForWorkspace,
} from "@/server/session-sync";
import logger from "@/server/logger";

interface ReconcileEvent {
  name: string;
  v?: string;
  data: {
    // `founderId` removed in ADR-044 Amendment 2026-06-17b (v=3): it was
    // vestigial — the fan-out targets workspaces by (installation_id,
    // repo_url), never founder, and the field was never destructured here.
    installationId: number;
    deliveryId: string;
    defaultBranch: string;
    headSha: string;
    beforeSha: string;
    // ADR-044: bare owner/repo slug from repository.full_name (v=3).
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

export async function workspaceReconcileOnPushHandler({
  event,
  step,
  logger: stepLogger,
}: HandlerArgs): Promise<{ ok: true; synced: number } | { ok: false; reason: string }> {
  void stepLogger;
  const { installationId, deliveryId, fullName, headSha, beforeSha, pushReceivedAt } =
    event.data;

  // Schema-gate. Non-throwing — an in-flight v=2 envelope (the prior schema,
  // before this PR dropped the vestigial `founderId`) should drain to
  // {ok:false}, not burn a retry. The webhook now emits v=3 (SCHEMA_V); stale
  // in-flight v=2 (and older v=1) events persist in the self-hosted store (no
  // automatic deletion; ~24h is only the event-id dedup window) and deadletter
  // through here when they replay.
  const v = event.v ?? "0";
  const gate = await step.run("schema-gate", async () => {
    if (v !== WORKSPACE_RECONCILE_SCHEMA_V) {
      return { deadletter: true as const, reason: `schema_v=${v}` };
    }
    return { deadletter: false as const, reason: "" };
  });
  if (gate.deadletter) {
    // Expected deadletter of an in-flight v=2 (or older) envelope (the webhook
    // now emits v=3); observable at warning level rather than returning
    // silently.
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

  // NOTE: the ignored-internal-repo short-circuit is evaluated AFTER this
  // resolution, gated on zero matches (see below). It previously ran BEFORE
  // the query and silently starved a real connected workspace on an ignored
  // repo — e.g. the founder dogfooding their KB from the platform's own repo,
  // which was added to the ignore-list for Sentry-noise suppression (#4666).
  // Resolving first costs one indexed `select id`; the silent skip still fires
  // for the common zero-workspace case, preserving #4666's intent.
  //
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
    // Ignored-internal-repo short-circuit, NOW gated on zero matches (#4666
    // intent preserved). A push to an ignored repo (e.g. the platform's own
    // dev repo) with NO connected workspace is fully silent — no log, no
    // Sentry — exactly as #4666 intended. Evaluated here (after resolution)
    // rather than before it, so an ignored repo that DOES have a connected
    // workspace is no longer starved (the bug that froze a dogfooding KB for
    // ~5 weeks: the ignore check ran first and dropped the push before the
    // matching workspace was ever queried).
    if (isIgnoredReconcileRepo(targetRepoUrl)) {
      return { ok: false, reason: "ignored-internal-repo" };
    }
    // Expected, benign outcome -- app uninstalled, repo not yet onboarded, a
    // disconnected fork, or a stale/replayed webhook. NOT actionable. Logged to
    // Better Stack (pino) for the drain but deliberately NOT mirrored to Sentry:
    // it is a by-design skip, and the prior in-process `mirrorWarnWithDebounce`
    // could not bound it across the platform's container churn (each new worker
    // resets the debounce map), so every push still created Sentry issues +
    // alert emails for zero signal. Genuine resolution errors still page via the
    // reportSilentFallback path above.
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

  // Shadowed-workspace guard (the gap that hid the ~5-week freeze). An ignored
  // repo that nonetheless HAS connected workspaces is the EXPECTED steady state
  // when the founder dogfoods their KB out of an ignored repo (the default
  // ignore entry `jikig-ai/soleur` is the platform's own dev repo). It is NOT a
  // misconfiguration: we reconcile the workspaces below exactly as for any other
  // repo. #4706 emitted a Sentry warning here to make the prior silent-starve
  // loud, but the condition is permanently true for the default config, so the
  // breadcrumb became a per-push alert flood with zero signal. Record it at pino
  // `info` (Better Stack audit trail) so an operator can still pull "which
  // ignored repos still have live workspaces" on demand — but do NOT mirror to
  // Sentry. Genuine reconcile failures (sync / resolve, plus the inner
  // ensure-workspace-repo mirrors on a reclone honest-block) still page via the
  // reportSilentFallback sites. Mirrors the benign-skip info-log above
  // (skip-no-workspace-match).
  if (isIgnoredReconcileRepo(targetRepoUrl)) {
    logger.info(
      {
        feature: WORKSPACE_RECONCILE_SENTRY_FEATURE,
        op: "ignored-repo-has-workspaces",
        installationId,
        deliveryId,
        targetRepoUrl,
        workspaceCount: rows.length,
      },
      "Reconcile ignore-list shadows a connected workspace — reconciling anyway (info; review WORKSPACE_RECONCILE_IGNORE_REPOS if unexpected)",
    );
  }

  // Fan out: process every matching workspace independently. A push to a
  // shared repo legitimately affects all connected workspaces.
  let synced = 0;
  for (const ws of rows) {
    const outcome = await step.run(`reconcile-${ws.id}`, async () => {
      const { createServiceClient } = await import("@/lib/supabase/service");
      const service = createServiceClient();

      // Owner for kb_sync_history attribution. #5733 — workspaces support N
      // co-owners by design (supersedes #4520 single-owner-strict;
      // `transfer_workspace_ownership` also opens a transient 2-owner window).
      // The former `.maybeSingle()` ERRORED on ≥2 owner rows → ownerId=null → a
      // FALSE "owner-less workspace reconciled" warn EVERY push (the operator's
      // soleur workspace: 2 legitimate owners). Select ALL owner rows and pick
      // the attribution owner deterministically: the solo self-row
      // (user_id == ws.id) when present, else the earliest-created owner.
      // `ownerId` is used ONLY for kb_sync attribution + the breadcrumb here, so
      // any stable pick is sound. "owner-less" now means GENUINELY zero rows.
      const { data: ownerRows, error: ownerErr } = await service
        .from("workspace_members")
        .select("user_id, created_at")
        .eq("workspace_id", ws.id)
        .eq("role", "owner")
        // `user_id` is the deterministic tie-break: two co-owners inserted in the
        // same transaction share `created_at = now()`, so without it `owners[0]`
        // is order-undefined (the team-workspace-without-self-row branch).
        .order("created_at", { ascending: true })
        .order("user_id", { ascending: true });
      if (ownerErr) {
        // A real probe error is NOT "owner-less" — never emit the drift warn on
        // a transient read failure (cq-silent-fallback-must-mirror-to-sentry).
        // Fall back to the workspace-keyed audit (ownerId stays null) and
        // surface the error under its own op so it is queryable.
        reportSilentFallback(ownerErr, {
          feature: WORKSPACE_RECONCILE_SENTRY_FEATURE,
          op: "owner-attribution-probe",
          extra: { workspaceId: ws.id, installationId, deliveryId },
          message:
            "Owner-attribution read failed — reconciling via workspace-keyed audit",
        });
      }
      const owners = (ownerRows as { user_id: string }[] | null) ?? [];
      const ownerId =
        owners.find((o) => o.user_id === ws.id)?.user_id ??
        owners[0]?.user_id ??
        null;

      // #4906 — an owner-less workspace is an invariant drift (every solo
      // workspace should carry a workspace_members(role='owner') canary row,
      // ADR-038 N2). It still self-heals + syncs (#4901), but the audit row
      // was previously skipped behind `if (ownerId)`, leaving the recovery
      // invisible in the admin analytics forensic trail. We now (a) write the
      // audit row via the workspace-keyed service-role path, and (b) surface the
      // drift at warn level (non-paging) so the operator can repair the canary.
      // appendKbSyncRowForWorkspace takes the service-role `service` client as a
      // param — session-sync.ts must not import createServiceClient itself (it
      // is tenant-only per .service-role-allowlist; the privilege-acquisition
      // site stays here, in the allowlisted handler).
      const writeAuditRow = (row: Parameters<typeof appendKbSyncRow>[1]) =>
        ownerId
          ? appendKbSyncRow(ownerId, row)
          : appendKbSyncRowForWorkspace(service, ws.id, row);

      if (owners.length > 1) {
        // ≥2 legitimate co-owners (multi-owner is BY DESIGN, #5733). Record the
        // state with a distinct, non-paging info breadcrumb — NEVER the false
        // "owner-less" warn the pre-fix `.maybeSingle()` error produced. This is
        // the honest signal that distinguishes by-design multi-owner from drift.
        Sentry.addBreadcrumb({
          category: "workspace-reconcile-push",
          message: "multiple-owners-reconcile",
          level: "info",
          data: {
            op: "multiple-owners-reconcile",
            workspaceId: ws.id,
            ownerCount: owners.length,
          },
        });
      }
      if (!ownerId && !ownerErr) {
        // GENUINELY zero owner rows (not a transient probe error). Per-workspace
        // 5-min TTL on the Sentry mirror (mirrorWarnWithDebounce,
        // keyed on ws.id). A SYSTEMIC owner-canary regression (a provisioning
        // bug dropping owner rows for a whole cohort) would otherwise emit one
        // warn per owner-less workspace PER PUSH — the same per-push alert-flood
        // class this handler already de-noised for the ignored-repo breadcrumb
        // (#4706). Debouncing collapses it to one event per workspace per
        // window while still surfacing each distinct drifted workspace.
        mirrorWarnWithDebounce(
          new Error("owner-less workspace reconciled"),
          {
            feature: WORKSPACE_RECONCILE_SENTRY_FEATURE,
            op: "ownerless-reconcile",
            extra: { workspaceId: ws.id, installationId, deliveryId },
            message:
              "Owner-canary row missing — reconciled via workspace-keyed audit",
          },
          ws.id,
          "ownerless-reconcile",
        );
      }

      const workspacePath = workspacePathForWorkspaceId(ws.id);
      // userId is for logging/breadcrumb ONLY — pseudonymized downstream. Owner-less
      // workspaces (#5591) carry no canary row, so fall back to the workspace id.
      const breadcrumbUserId = ownerId ?? ws.id;

      // Readiness = git work-tree VALIDITY, not mere dir existence (ADR-044 amendment
      // 2026-06-29). A VALID .git takes the existing pull/reset sync path. An INVALID
      // or ABSENT .git is re-cloned via the validity+corrupt-aware ensure path — the
      // permanent-trap that a dir-existence-only readiness check could never recover.
      // #5733 deliverable A — compute the shared host `rev-parse` confirm ONCE per
      // event (AC8: one rev-parse spawn per reconcile invocation, single
      // workspace). `evaluateAgentReadiness` runs the host confirm ONLY for a
      // `dir-valid` shape and emits the self-stop internally on a confirmed
      // `"not-a-worktree"` — the SAME shared helper the cold + warm gates use, so
      // the emit + heal-route is structural (the cold-only-emit drift was the
      // 26×-dark incident on THIS reconcile surface). A `dir-valid` `.git` the host
      // rev-parse rejects is lstat-READY, so it would otherwise skip the heal
      // branch entirely and take the sync path into a strand.
      const agentReady = await evaluateAgentReadiness(workspacePath, {
        userId: breadcrumbUserId,
        activeWorkspaceId: ws.id,
        connected: Boolean(targetRepoUrl),
        dbReady: true,
      });
      if (!isReadyGitWorkTree(workspacePath) || agentReady === "block") {
        const outcome = await ensureWorkspaceRepoCloned({
          userId: breadcrumbUserId,
          workspacePath,
          installationId, // number, from the push event
          repoUrl: targetRepoUrl, // composed + normalized in scope above
        });

        // Assert the INVARIANT, not the "ok" proxy: ensureWorkspaceRepoCloned returns
        // "ok" for a benign skip (e.g. a repo_url that fails its github-https allowlist)
        // WITHOUT having healed anything. Recovered requires BOTH lstat readiness AND
        // the host rev-parse confirm (#5733): a populated-corrupt `dir-valid` that
        // ensureWorkspaceRepoCloned no-op'd reads `isReadyGitWorkTree=true` but
        // `agentReady` stays `"block"`, so it is correctly NOT recovered (the
        // self-stop already fired inside evaluateAgentReadiness above).
        const recovered =
          outcome === "ok" &&
          isReadyGitWorkTree(workspacePath) &&
          agentReady === "ready";

        // Best-effort transaction-trace context (task-mandated). NOTE: a breadcrumb is
        // only transmitted when a captureException/Message fires on the same Sentry scope;
        // this handler returns cleanly on both paths, so the DURABLE signals are the
        // kb_sync_history row (below) + the inner ensure-workspace-repo Sentry mirrors —
        // not this breadcrumb (observability-review P1). Do NOT add a captureException
        // here (would double-page; ensureWorkspaceRepoCloned already mirrors failures).
        Sentry.addBreadcrumb({
          category: "workspace-reconcile-push",
          message: "corrupt-worktree-reclone",
          level: recovered ? "info" : "warning",
          data: { op: "corrupt-worktree-reclone", recovered, workspaceId: ws.id },
        });

        const at = Date.now();
        if (!recovered) {
          // #5733 — un-blind the RECONCILE benign-skip (the 26×-dark surface): a
          // clone that returned "ok" WITHOUT healing (repo_url failed the
          // github-https allowlist, EACCES, gitdir-FILE) leaves the workspace
          // not-ready but previously wrote ONLY a kb_sync_history row — no Sentry
          // event, so the strand was unqueryable on the path that actually fired.
          // Emit the agent-readiness self-stop from THIS gate too. Deduped by
          // (userId, workspace, gitKind, source): a `dir-valid` corruption already
          // emitted inside evaluateAgentReadiness above (same gitKind+source) →
          // collapsed; a non-dir-valid benign-skip (absent / escaping pointer) has
          // a distinct gitKind → emits here. `gitRevParseValid` omitted (no host
          // confirm ran for these shapes). NEVER the subprocess stderr/raw path.
          const unrecoveredShape = probeGitWorktreeShape(workspacePath);
          reportAgentReadinessSelfStop({
            userId: breadcrumbUserId,
            activeWorkspaceId: ws.id,
            gitValid:
              unrecoveredShape.kind === "dir-valid" ||
              unrecoveredShape.kind === "file-pointer",
            gitKind: unrecoveredShape.kind,
            gitdirEscapesWorkspace: unrecoveredShape.gitdirEscapesWorkspace,
            source: "host-pre-heal",
          });
          // Honest-block (populated-broken / EACCES / gitdir-FILE), clone failure, or a
          // benign skip that did not heal. ensureWorkspaceRepoCloned already mirrored the
          // genuine failures to Sentry via reportSilentFallback (op: corrupt-worktree-block
          // / corrupt-worktree-rm / clone) — do NOT double-page here. Record the audit row
          // so the workspace stays observably not-ready.
          await writeAuditRow({
            at: new Date(at).toISOString(),
            trigger: "webhook_push",
            sha_before: beforeSha,
            sha_after: headSha,
            ok: false,
            error_class: ERROR_CLASS_WORKSPACE_NOT_READY,
            push_received_at: pushReceivedAt,
            sync_completed_at: at,
            workspace_id: ws.id,
          });
          return { synced: false };
        }

        // Re-cloned successfully: the shallow clone is already at origin HEAD, so a
        // subsequent pull would be redundant. Record an OK audit row marked recovered.
        await writeAuditRow({
          at: new Date(at).toISOString(),
          trigger: "webhook_push",
          sha_before: beforeSha,
          sha_after: headSha,
          ok: true,
          recovered: true,
          push_received_at: pushReceivedAt,
          sync_completed_at: at,
          workspace_id: ws.id,
        });
        return { synced: true };
      }

      // VALID .git — preserve the existing pull/reset sync path unchanged.
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
        await writeAuditRow({
          at,
          trigger: "webhook_push",
          sha_before: beforeSha,
          sha_after: headSha,
          ok: false,
          // Real class from the git stderr/exit signature — `syncWorkspace`
          // classifies non_fast_forward vs sync_failed (and self-heals a
          // diverged clone first). No longer hard-coded.
          error_class: syncResult.errorClass,
          push_received_at: pushReceivedAt,
          sync_completed_at: completedAt,
          workspace_id: ws.id, // #4728 — discriminator (id in scope from fan-out loop)
        });
        return { synced: false };
      }

      await writeAuditRow({
        at,
        trigger: "webhook_push",
        sha_before: beforeSha,
        sha_after: headSha,
        ok: true,
        // true when a diverged clone was self-healed via reset (vs clean pull)
        recovered: syncResult.recovered,
        push_received_at: pushReceivedAt,
        sync_completed_at: completedAt,
        workspace_id: ws.id, // #4728 — discriminator (id in scope from fan-out loop)
      });
      return { synced: true };
    });
    if (outcome.synced) synced += 1;
  }

  if (synced === 0) {
    // Intentionally silent: every path that lands here already emitted its own
    // mirror inside the fan-out loop (reportSilentFallback op="sync" on sync
    // failure; the inner ensure-workspace-repo mirrors — corrupt-worktree-block
    // / clone — on a reclone honest-block / clone-fail). The not-recovered
    // reclone path adds only a breadcrumb (no double-page). An aggregate mirror
    // here would double-report the same incident. (cq-silent-fallback-must-
    // mirror-to-sentry is satisfied by the per-workspace sites.)
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
