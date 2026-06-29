import { NextResponse } from "next/server";
import * as Sentry from "@sentry/nextjs";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { provisionWorkspaceWithRepo } from "@/server/workspace";
import { scanProjectHealth } from "@/server/project-scanner";
import { normalizeRepoUrl } from "@/lib/repo-url";
import { writeRepoColsToWorkspace } from "@/server/workspace-repo-mirror";
import { resolveActiveWorkspace } from "@/server/workspace-resolver";
import {
  resolveReachableInstallationIds,
  resolveOwningInstallationForRepo,
} from "@/server/reachable-installations";
import { resolveGithubLogin } from "@/server/github-login";
import { GitOperationError, sanitizeGitStderr } from "@/server/git-auth";
import logger from "@/server/logger";
import { reportSilentFallback } from "@/server/observability";
import { hashUserIdValue } from "@/server/userid-pseudonymize";
import { triggerHeadlessSync } from "@/server/auto-sync-trigger";
import { evaluateRepoConnect } from "@/server/repo-connect-guard";

/**
 * POST /api/repo/setup
 *
 * Starts cloning a repository into the user's workspace.
 * The clone runs in the background — poll GET /api/repo/status for progress.
 *
 * Body: { repoUrl: string }
 */
export async function POST(request: Request) {
  const { valid, origin } = validateOrigin(request);
  if (!valid) return rejectCsrf("api/repo/setup", origin);

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  // ADR-044 PR-2 team write-cutover (#5462): resolve the target workspace id
  // server-side via the MEMBERSHIP-VERIFIED resolver. `resolveActiveWorkspace`
  // returns the active workspace id ONLY for a membership-verified team or the
  // caller's own solo id (IDOR-safe — derived from session claim, never request
  // input). At a WRITE/provisioning boundary a db-error must FAIL-CLOSED (503),
  // never silently fall back to the caller's solo workspace and provision there
  // under a team claim (the `resolveCurrentWorkspaceId` fail-to-solo posture is
  // unsafe here). A removed/non-member of a stale team claim is reset to their
  // OWN solo id (`resetFromClaim`) and the whole request proceeds against it.
  const activeResolution = await resolveActiveWorkspace(user.id, supabase);
  if (!activeResolution.ok) {
    return NextResponse.json(
      { error: "Could not resolve your active workspace. Please retry." },
      { status: 503 },
    );
  }
  const activeWorkspaceId = activeResolution.workspaceId;
  if (activeResolution.resetFromClaim) {
    logger.info(
      { userId: user.id, staleClaim: activeResolution.resetFromClaim },
      "repo setup: stale team claim reset to caller's solo workspace",
    );
  }

  // ADR-044 owner-gate (confused-deputy): only the OWNER of the workspace this
  // handler mutates may connect a repo to it. `p_workspace_id` MUST equal the id
  // the handler actually mutates — now the RESOLVED active id (team or solo), so
  // the gate is load-bearing for team workspaces (a non-owner member connecting
  // to a team workspace gets 403) and remains a no-op for solo (a solo user owns
  // workspace_id=user.id). `is_workspace_owner` is SECURITY DEFINER (mig 098),
  // GRANT authenticated.
  const ownerRes = await supabase.rpc("is_workspace_owner", {
    p_workspace_id: activeWorkspaceId,
    p_user_id: user.id,
  });
  if (ownerRes.error) {
    logger.error(
      { err: ownerRes.error, userId: user.id },
      "is_workspace_owner check failed during repo setup",
    );
    return NextResponse.json(
      { error: "Failed to connect repository" },
      { status: 500 },
    );
  }
  if (ownerRes.data !== true) {
    return NextResponse.json(
      { error: "Only the workspace owner can connect a repository." },
      { status: 403 },
    );
  }

  const body = await request.json().catch(() => null);
  if (!body?.repoUrl || typeof body.repoUrl !== "string") {
    return NextResponse.json(
      { error: "Missing or invalid repoUrl" },
      { status: 400 },
    );
  }

  // Validate URL format (must be HTTPS GitHub URL with valid owner/repo).
  // `normalizeRepoUrl` runs BEFORE the format regex so the validator sees
  // the canonical form — any subsequent DB write scopes match the same
  // form every read-site normalization produces.
  const repoUrl = normalizeRepoUrl(body.repoUrl);
  if (!/^https:\/\/github\.com\/[a-zA-Z0-9._-]+\/[a-zA-Z0-9._-]+$/.test(repoUrl)) {
    return NextResponse.json(
      { error: "Invalid GitHub repository URL" },
      { status: 400 },
    );
  }

  const serviceClient = createServiceClient();

  // Email + GitHub login stay on `users` (not relocated by ADR-044). The stored
  // install id is read from the active `workspaces` row in the degraded-fallback
  // below (ADR-044 PR-2 — it moved off `users`).
  const { data: userData } = await serviceClient
    .from("users")
    .select("email, github_username")
    .eq("id", user.id)
    .single();

  // Resolve the installation that should be used for THIS repo. Priority:
  //   1. Owning install from the reachable set (most correct): the install
  //      that actually has the repo, regardless of whether
  //      users.github_installation_id is set. This is the path that lets an
  //      org member clone an org-owned repo via a workspace-membership install
  //      (ADR-044) without a stored personal install.
  //   2. Stored users.github_installation_id (preserves the personal happy
  //      path even when the owning-install probe is degraded/inconclusive).
  //   3. Otherwise -> keep the 400 "not installed" contract.
  //
  // We do NOT write the resolved install back onto users.github_installation_id
  // (unique constraint — ADR-044 resolves the shared case per-request).
  //
  // Parse owner/repo from the already-normalized repoUrl (canonical
  // <owner>/<repo> guaranteed by the format regex above).
  const ownerRepoMatch = repoUrl.match(
    /^https:\/\/github\.com\/([^/]+)\/([^/]+)$/,
  );
  let installationId: number | null = null;
  if (ownerRepoMatch) {
    const [, owner, repo] = ownerRepoMatch;
    const githubLogin = await resolveGithubLogin(
      serviceClient,
      user.id,
      userData?.github_username,
    );
    const reachable = await resolveReachableInstallationIds(
      serviceClient,
      user.id,
      githubLogin,
    );
    installationId = await resolveOwningInstallationForRepo(
      reachable,
      owner,
      repo,
    );
  }

  // Degraded-probe fallback: owning resolution was inconclusive, but a stored
  // install exists on the active workspace — use it. ADR-044 PR-2: read it from
  // `workspaces.<activeWorkspaceId>` (was `users.github_installation_id`). The
  // column is REVOKE'd from `authenticated`, but `service_role` reads it directly.
  if (installationId == null) {
    const { data: wsRow } = await serviceClient
      .from("workspaces")
      .select("github_installation_id")
      .eq("id", activeWorkspaceId)
      .maybeSingle();
    if (wsRow?.github_installation_id != null) {
      installationId = wsRow.github_installation_id as number;
    }
  }

  if (installationId == null) {
    return NextResponse.json(
      { error: "GitHub App not installed. Please install the app first." },
      { status: 400 },
    );
  }

  // ADR-044 amendment — application-enforced scoped solo-uniqueness. BEFORE the
  // cloning flip, decide whether this connect proceeds, is redirected to a
  // SWITCH (the owning solo is the caller's OWN + ready), or is DECLINED (a
  // different user's solo already owns this (install, repo) — the condition that
  // makes the non-push webhook founder resolver fail-closed: WEB-PLATFORM-3M).
  // Running before the `:202` lock means a declined/switched connect leaves zero
  // partial provisioning to roll back. `installationId` is server-derived and
  // non-null here; `repoUrl` is normalized at :106; `serviceClient` is held above.
  const connectOutcome = await evaluateRepoConnect({
    installationId,
    repoUrl,
    userId: user.id,
    activeWorkspaceId,
    serviceClient,
  });
  if (connectOutcome.outcome === "switch") {
    // The caller already has their OWN (ready) workspace for this repo. Surface
    // the caller's-own id so the UI can offer "switch to that workspace". 409 is
    // overloaded with "Setup already in progress" below — callers branch on
    // `outcome`/`code`, never the bare status.
    return NextResponse.json(
      {
        outcome: "switch",
        code: connectOutcome.code,
        existingWorkspaceId: connectOutcome.existingWorkspaceId,
        canRequestJoin: connectOutcome.canRequestJoin,
        error: "You already have a workspace connected to this repository.",
      },
      { status: 409 },
    );
  }
  if (connectOutcome.outcome === "decline") {
    // Fixed, non-disclosing baseline — byte-identical across every decline
    // sub-case (different-user owner / ambiguous / db-error). NEVER carries a
    // workspace/user reference (no information disclosure / IDOR).
    return NextResponse.json(
      {
        outcome: "decline",
        code: connectOutcome.code,
        canRequestJoin: connectOutcome.canRequestJoin,
        error: "This repository can't be connected.",
      },
      { status: 409 },
    );
  }
  // outcome === "ok" → fall through to the existing cloning flip.

  // Optimistic lock: only transition to "cloning" if not already cloning.
  // Prevents race condition from double-click or concurrent requests.
  // Stamp `repo_last_synced_at = now()` on the cloning flip so the dispatch
  // self-heal lock's staleness window (claim_repo_clone_lock, migration 108)
  // measures THIS clone's age — without it a reconnect over a >5-min-old prior
  // sync would read as instantly-stale and a cold dispatch could start a second
  // concurrent clone, and a process-killed clone would leave a NULL clock that
  // the staleness escape can never recover (permanent `cloning` strand).
  // ADR-044 PR-2: the optimistic "cloning" lock + repo write are AUTHORITATIVE on
  // `workspaces` keyed on the resolved active id (was `users` keyed on user.id).
  // The contended row is the SHARED workspace, so two concurrent connects on the
  // same team workspace serialize correctly (on per-caller `users` rows they would
  // both win the lock). `workspaces.repo_status` has the same CHECK enum (mig 079)
  // and `service_role` keeps its default grant, so the service-client lock write
  // is unaffected by the column-level REVOKE. The installation grant is written
  // here too so the workspaces-only credential read (resolve_workspace_installation_id)
  // sees the in-progress connection.
  const cloningAt = new Date().toISOString();
  const { data: lockResult, error: updateError } = await serviceClient
    .from("workspaces")
    .update({
      repo_url: repoUrl,
      github_installation_id: installationId,
      repo_status: "cloning",
      repo_error: null,
      repo_last_synced_at: cloningAt,
    })
    .eq("id", activeWorkspaceId)
    .neq("repo_status", "cloning")
    .select("id")
    .maybeSingle();

  if (updateError) {
    logger.error(
      { err: updateError, userId: user.id, workspaceId: activeWorkspaceId },
      "Failed to update repo status to cloning",
    );
    return NextResponse.json(
      { error: "Failed to start setup" },
      { status: 500 },
    );
  }

  if (!lockResult) {
    return NextResponse.json(
      { error: "Setup already in progress" },
      { status: 409 },
    );
  }

  // Kick off clone in the background (don't await)
  const userName = user.user_metadata?.full_name ?? user.email?.split("@")[0] ?? "Soleur User";
  const userEmail = userData?.email ?? user.email ?? "";

  const isStartFresh = body.source === "start_fresh";

  // ADR-044 PR-2: provision the RESOLVED active workspace on disk
  // (`/workspaces/<activeWorkspaceId>` — team or solo). The id is captured in the
  // background-callback closure below and NEVER re-resolved: the session claim can
  // drift between request return and clone completion, so re-resolving could write
  // `repo_status:ready` to a different workspace than the one provisioned
  // (identity-pinned write). For a solo connect this equals `user.id` (N2).
  const isSoloWorkspace = activeWorkspaceId === user.id;
  provisionWorkspaceWithRepo(
    activeWorkspaceId,
    repoUrl,
    installationId,
    userName,
    userEmail,
    { suppressWelcomeHook: isStartFresh },
  )
    .then(async (workspacePath) => {
      // Fast scan — failure must not block provisioning.
      // Skip for Start Fresh projects: the repo is empty by design and the
      // health snapshot would only show misleading "Gaps Found" signals.
      // When null, ReadyState renders "Your AI Team Is Ready." instead.
      let healthSnapshot = null;
      if (!isStartFresh) {
        try {
          healthSnapshot = scanProjectHealth(workspacePath);
        } catch (scanErr) {
          logger.error(
            { err: scanErr, userId: user.id },
            "Project health scan failed — continuing without snapshot",
          );
          Sentry.captureException(scanErr);
        }
      }

      // ADR-044 PR-2 — AUTHORITATIVE repo-connection write to the active
      // workspace (was the `users` row). The helper `.select("id")`s so a 0-row
      // no-op (workspace deleted mid-clone; current_workspace_id ON DELETE SET
      // NULL) is Sentry-mirrored instead of silently lost.
      await writeRepoColsToWorkspace(serviceClient, activeWorkspaceId, {
        repo_status: "ready",
        repo_last_synced_at: new Date().toISOString(),
      });

      // The provisioning/readiness columns (`workspace_status`, `health_snapshot`)
      // are NOT relocated by ADR-044 — they stay on the OWNER's `users` row. Only
      // write them for a SOLO connect: for a team workspace the caller's `users`
      // row is their PERSONAL solo readiness, and the team's readiness is governed
      // by the org owner's existing `users.workspace_status` (already "ready" from
      // onboarding). `workspace_path` is intentionally NOT written — it is derived
      // from the workspace id (`workspacePathForWorkspaceId`) and set immutably at
      // onboarding, so re-writing it here is redundant and trips the PR-2b
      // zero-`users.*`-write exit criterion.
      if (isSoloWorkspace) {
        const { error } = await serviceClient
          .from("users")
          .update({
            workspace_status: "ready",
            health_snapshot: healthSnapshot,
          })
          .eq("id", user.id);

        if (error) {
          logger.error(
            { err: error, userId: user.id },
            "Failed to update user readiness after successful clone",
          );
        }
      }

      logger.info(
        { userId: user.id, workspaceId: activeWorkspaceId, repoUrl, category: healthSnapshot?.category },
        "Repo setup completed",
      );

      // Auto-trigger headless sync — fire-and-forget. Resilience (BYOK-lease /
      // tenant-JWT-mint race → bounded retry; keyless skip; single conversation
      // INSERT outside the retry boundary) lives in triggerHeadlessSync so it is
      // unit-testable without the agent SDK. The helper never rethrows and never
      // mutates repo_status (the clone already succeeded).
      //
      // Dynamic import: agent-runner.ts pulls in @anthropic-ai/claude-agent-sdk
      // which breaks Next.js build-time route validation when statically imported,
      // so startAgentSession is injected at the call site. The import is wrapped
      // in a thunk so agent-runner loads ONLY when startAgentSession actually
      // fires — i.e. AFTER triggerHeadlessSync's keyless presence-gate passes.
      // Keyless users never pull the SDK graph (restores the pre-extraction
      // ordering the setup-route tests assert).
      await triggerHeadlessSync(user.id, repoUrl, {
        startAgentSession: async (...args) => {
          const { startAgentSession } = await import("@/server/agent-runner");
          return startAgentSession(...args);
        },
        serviceClient,
        // P0-4: pin the headless sync to the CAPTURED active id, not a re-resolve.
        // If the user switched workspaces mid-clone, a re-resolve would target the
        // now-active workspace instead of the one we just cloned.
        resolveWorkspaceId: async () => activeWorkspaceId,
      });
    })
    .catch(async (err) => {
      Sentry.withIsolationScope(() => {
        Sentry.getCurrentScope().setUser({ id: hashUserIdValue(user.id) });
        reportSilentFallback(err, {
          feature: "repo-setup",
          op: "clone",
          message: "Repo clone failed",
          extra: { userId: user.id, repoUrl },
        });
      });

      const rawMessage = err instanceof Error ? err.message : String(err);
      const code =
        err instanceof GitOperationError ? err.errorCode : "CLONE_UNKNOWN";
      // Sanitize unconditionally — GitOperationError messages are already
      // sanitized, but other error paths (token-generation failure,
      // UUID-validation, preflight) write raw `err.message` which can
      // contain absolute paths from the Node error stack.
      const payload = JSON.stringify({
        code,
        message: sanitizeGitStderr(rawMessage).slice(0, 2000),
        timestamp: new Date().toISOString(),
      });
      // ADR-044 PR-2 — write the error status + sanitized reason to the active
      // workspace (was `users`). `repo_error` is now a `workspaces` column (mig
      // 110, in the non-credential `authenticated` GRANT). The helper Sentry-mirrors
      // a db error or 0-row no-op.
      await writeRepoColsToWorkspace(serviceClient, activeWorkspaceId, {
        repo_status: "error",
        repo_error: payload,
      });
    });

  return NextResponse.json({ status: "cloning" });
}
