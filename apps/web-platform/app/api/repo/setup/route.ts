import { NextResponse } from "next/server";
import * as Sentry from "@sentry/nextjs";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { provisionWorkspaceWithRepo } from "@/server/workspace";
import { scanProjectHealth } from "@/server/project-scanner";
import { normalizeRepoUrl } from "@/lib/repo-url";
import { mirrorRepoColsToSoloWorkspace } from "@/server/workspace-repo-mirror";
import { resolveCurrentWorkspaceId } from "@/server/workspace-resolver";
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

  // Get user's installation ID
  const { data: userData } = await serviceClient
    .from("users")
    .select("github_installation_id, email, github_username")
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
  // install exists — use it.
  if (installationId == null && userData?.github_installation_id) {
    installationId = userData.github_installation_id;
  }

  if (installationId == null) {
    return NextResponse.json(
      { error: "GitHub App not installed. Please install the app first." },
      { status: 400 },
    );
  }

  // Optimistic lock: only transition to "cloning" if not already cloning.
  // Prevents race condition from double-click or concurrent requests.
  const { data: lockResult, error: updateError } = await serviceClient
    .from("users")
    .update({ repo_url: repoUrl, repo_status: "cloning", repo_error: null })
    .eq("id", user.id)
    .neq("repo_status", "cloning")
    .select("id")
    .maybeSingle();

  if (updateError) {
    logger.error(
      { err: updateError, userId: user.id },
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

  // ADR-044: mirror the connecting repo + installation to the solo workspace
  // so the workspaces-only read path sees the in-progress connection.
  await mirrorRepoColsToSoloWorkspace(serviceClient, user.id, {
    repo_url: repoUrl,
    github_installation_id: installationId,
    repo_status: "cloning",
  });

  // Kick off clone in the background (don't await)
  const userName = user.user_metadata?.full_name ?? user.email?.split("@")[0] ?? "Soleur User";
  const userEmail = userData?.email ?? user.email ?? "";

  const isStartFresh = body.source === "start_fresh";

  // Solo provisioning: `user.id` is the workspace_id (N2 invariant —
  // migration 053 §1.1.7). Team-invite repo-setup flows (Phase 5) will
  // resolve the target workspace_id first.
  provisionWorkspaceWithRepo(
    user.id,
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

      const { error } = await serviceClient
        .from("users")
        .update({
          workspace_path: workspacePath,
          workspace_status: "ready",
          repo_status: "ready",
          repo_last_synced_at: new Date().toISOString(),
          health_snapshot: healthSnapshot,
        })
        .eq("id", user.id);

      if (error) {
        logger.error(
          { err: error, userId: user.id },
          "Failed to update user after successful clone",
        );
        return;
      }

      // ADR-044: mirror the ready repo state to the solo workspace.
      await mirrorRepoColsToSoloWorkspace(serviceClient, user.id, {
        repo_status: "ready",
        repo_last_synced_at: new Date().toISOString(),
      });

      logger.info(
        { userId: user.id, repoUrl, category: healthSnapshot?.category },
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
        resolveWorkspaceId: resolveCurrentWorkspaceId,
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
      await serviceClient
        .from("users")
        .update({ repo_status: "error", repo_error: payload })
        .eq("id", user.id)
        .then(({ error }) => {
          if (error) {
            logger.error(
              { err: error, userId: user.id },
              "Failed to update repo status to error",
            );
          }
        });
      // ADR-044: mirror the error status to the solo workspace.
      await mirrorRepoColsToSoloWorkspace(serviceClient, user.id, {
        repo_status: "error",
      });
    });

  return NextResponse.json({ status: "cloning" });
}
