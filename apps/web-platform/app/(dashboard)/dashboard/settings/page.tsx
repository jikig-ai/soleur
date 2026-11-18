import { redirect } from "next/navigation";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { SettingsContent } from "@/components/settings/settings-content";
import type { RepoStatus } from "@/components/settings/project-setup-card";
import { resolveNeedsReconnect } from "@/lib/repo-status";
import { resolveWorkspaceIdentityForSettings } from "@/server/workspace-identity-resolver";
import { resolveActiveWorkspace } from "@/server/workspace-resolver";
import { isCcOauthEnabled } from "@/server/cc-oauth-flag";
import { resolveCcGithubPushRoute } from "@/server/cc-github-push";
import { mirrorWarnWithDebounce, mirrorWithDebounce } from "@/server/observability";
import { isRenderableHeldCount, type HeldRouteState } from "@/lib/kb-sync-held-copy";

export default async function SettingsPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login");
  }

  const service = createServiceClient();

  // ADR-044 Amendment 2026-06-17b: the repo-connection columns are
  // AUTHORITATIVE on the ACTIVE `workspaces` row (PR-2 relocated the writes
  // off `users`; PR-2b DROPs `users.github_installation_id`, so reading it
  // here would throw on every settings render). Resolve the active workspace
  // (claim → solo fallback, never a sibling) and read the repo cols there —
  // mirrors `app/api/repo/status/route.ts`. A transient resolve `db-error`
  // fails closed to "not connected" so the page still renders (do NOT throw).
  const active = await resolveActiveWorkspace(user.id, service);

  // Parallelize all independent queries.
  const [{ data: apiKey }, { data: oauthData, error: oauthError }, wsRes, heldRes] = await Promise.all([
    service
      .from("api_keys")
      .select("provider, is_valid, updated_at")
      .eq("user_id", user.id)
      .eq("provider", "anthropic")
      .eq("is_valid", true)
      .limit(1)
      .single(),
    // #11524: the stored subscription-token row (any validity) so Settings can
    // offer its removal. `hasApiKey` above keeps its meaning (the anthropic row
    // the lease reads); this is a separate, independent credential row.
    service
      .from("api_keys")
      .select("provider, is_valid, updated_at")
      .eq("user_id", user.id)
      .eq("provider", "anthropic_oauth")
      .maybeSingle(),
    active.ok
      ? service
          .from("workspaces")
          .select(
            "repo_url, repo_status, repo_last_synced_at, github_installation_id",
          )
          .eq("id", active.workspaceId)
          .maybeSingle()
      : Promise.resolve({ data: null }),
    // #12714 (D29(3), D33(1)): the held count, in its OWN service-client select keyed on the membership-verified
    // active workspace id (the `authenticated` column grant excludes it, migration 187). Separate so a missing column
    // (an apply that lags, or a rollback) costs only the notice, never the repo card above.
    active.ok
      ? service
          .from("workspaces")
          .select("kb_sync_held_files")
          .eq("id", active.workspaceId)
          .maybeSingle()
      : Promise.resolve({ data: null, error: null }),
  ]);

  if (heldRes.error) {
    // Debounced, constant key (as above): this runs on every Settings render while the read keeps failing.
    // null first, never the error object (#8629: the pino mirror captures a passed Error first and Sentry drops the tagged
    // second capture); the Postgres code is the tag an operator filters on.
    const pgCode = (heldRes.error as { code?: unknown }).code;
    mirrorWithDebounce(
      null,
      {
        feature: "settings",
        op: "read-held-files",
        ...(typeof pgCode === "string" ? { tags: { pg_code: pgCode } } : {}),
        extra: { userId: user.id },
        message: "held-files select failed; no held notice",
      },
      "settings:read-held-files",
      "settings_read_held_files",
    );
  }

  // A failed oauth read must not silently hide the Remove control: report it
  // and render the neutral state (no token UI) rather than guess a row.
  if (oauthError) {
    // Debounced (5 min, in-process): this runs on every Settings render while
    // the read keeps failing. The key is a constant, NOT a user id, so a
    // sustained DB outage yields one event per process per 5 minutes, not one
    // per visit.
    mirrorWithDebounce(
      oauthError,
      {
        feature: "settings",
        op: "read-oauth-credential",
        extra: { userId: user.id },
      },
      "settings:read-oauth-credential",
      "settings_read_oauth_credential",
    );
  }
  const oauthRow = oauthError ? null : oauthData;

  const repoData = wsRes.data;

  const needsReconnect = await resolveNeedsReconnect(
    repoData?.repo_status ?? null,
    repoData?.github_installation_id ?? null,
    user.id,
  );

  // #12714 (D29(3), D29(5)): the held-files notice and the Disconnect warning (V8). The count is display-only; the
  // publish-route predicate is asked for the VIEWER (a member's agent is the one that would push) and only when a notice can
  // render. The predicate never throws (a failed read is "unknown" plus its own debounced warning, tagged with the Settings
  // feature, obs F11); the catch is belt and braces and reads as "unknown" too, never "unavailable" (V6(3)).
  const rawHeldFiles: unknown = heldRes.error ? null : heldRes.data?.kb_sync_held_files;
  const heldFiles = isRenderableHeldCount(rawHeldFiles) ? rawHeldFiles : null;
  const heldRoutePromise: Promise<HeldRouteState> =
    active.ok && repoData?.repo_status === "ready" && heldFiles !== null
      ? resolveCcGithubPushRoute({ userId: user.id, workspaceId: active.workspaceId, feature: "settings" }).catch((err: unknown) => {
          mirrorWarnWithDebounce(
            null,
            {
              feature: "settings",
              op: "cc-push-route-check",
              tags: { failed: "threw" },
              extra: { userId: user.id, errName: err instanceof Error ? err.name : undefined },
              message: "publish-route check could not be completed; the transient copy is shown",
            },
            "settings:held-files-route-predicate",
            "cc-push-route-check",
          );
          return "unknown" as const;
        })
      : Promise.resolve("unknown" as const);

  // #4916: workspace-identity controls (logo + rename), relocated from the
  // flag-gated Team page so they are reachable for every user.
  const [workspaceIdentity, heldRoute] = await Promise.all([
    resolveWorkspaceIdentityForSettings(supabase, service),
    heldRoutePromise,
  ]);

  // feat-operator-cc-oauth — show the subscription-token toggle ONLY for an
  // operator/internal account (ADMIN_USER_IDS) with the kill-switch on.
  // Mirrors the AUTHORITATIVE server-side gate in /api/keys; this just hides
  // the control for everyone else (AC8 "no toggle" when inert).
  const isOperator =
    process.env.ADMIN_USER_IDS?.split(",").includes(user.id) ?? false;
  const ccOauthEnabled = isCcOauthEnabled();

  return (
    <SettingsContent
      userEmail={user.email ?? ""}
      hasApiKey={!!apiKey}
      apiKeyProvider={apiKey?.provider ?? null}
      apiKeyLastValidated={apiKey?.updated_at ?? null}
      repoUrl={repoData?.repo_url ?? null}
      repoStatus={(repoData?.repo_status as RepoStatus) ?? "not_connected"}
      repoLastSyncedAt={repoData?.repo_last_synced_at ?? null}
      needsReconnect={needsReconnect}
      canUseOauthCredential={isOperator && ccOauthEnabled}
      hasOauthToken={!!oauthRow}
      // "In effect" = exactly what the lease applies: kill-switch on AND a
      // valid row. A stored-but-inert token stays removable (copy variant C).
      oauthInEffect={ccOauthEnabled && oauthRow?.is_valid === true}
      oauthTokenSavedAt={oauthRow?.updated_at ?? null}
      workspaceIdentity={workspaceIdentity}
      heldFiles={heldFiles}
      heldRoute={heldRoute}
    />
  );
}
