import { redirect } from "next/navigation";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { SettingsContent } from "@/components/settings/settings-content";
import type { RepoStatus } from "@/components/settings/project-setup-card";
import { resolveNeedsReconnect } from "@/lib/repo-status";
import { resolveWorkspaceIdentityForSettings } from "@/server/workspace-identity-resolver";
import { resolveActiveWorkspace } from "@/server/workspace-resolver";

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
  const [{ data: apiKey }, wsRes] = await Promise.all([
    service
      .from("api_keys")
      .select("provider, is_valid, updated_at")
      .eq("user_id", user.id)
      .eq("provider", "anthropic")
      .eq("is_valid", true)
      .limit(1)
      .single(),
    active.ok
      ? service
          .from("workspaces")
          .select(
            "repo_url, repo_status, repo_last_synced_at, github_installation_id",
          )
          .eq("id", active.workspaceId)
          .maybeSingle()
      : Promise.resolve({ data: null }),
  ]);

  const repoData = wsRes.data;

  const needsReconnect = await resolveNeedsReconnect(
    repoData?.repo_status ?? null,
    repoData?.github_installation_id ?? null,
    user.id,
  );

  // #4916: workspace-identity controls (logo + rename), relocated from the
  // flag-gated Team page so they are reachable for every user.
  const workspaceIdentity = await resolveWorkspaceIdentityForSettings(
    supabase,
    service,
  );

  // feat-operator-cc-oauth — show the subscription-token toggle ONLY for an
  // operator/internal account (ADMIN_USER_IDS) with the kill-switch on.
  // Mirrors the AUTHORITATIVE server-side gate in /api/keys; this just hides
  // the control for everyone else (AC8 "no toggle" when inert).
  const isOperator =
    process.env.ADMIN_USER_IDS?.split(",").includes(user.id) ?? false;
  const ccOauthEnabled =
    process.env.CC_OAUTH_ENABLED === "1" ||
    process.env.CC_OAUTH_ENABLED === "true";

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
      workspaceIdentity={workspaceIdentity}
    />
  );
}
