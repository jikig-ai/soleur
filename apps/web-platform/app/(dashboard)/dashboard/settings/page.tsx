import { redirect } from "next/navigation";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { SettingsContent } from "@/components/settings/settings-content";
import { SettingsShell } from "@/components/settings/settings-shell";
import type { RepoStatus } from "@/components/settings/project-setup-card";

export default async function SettingsPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login");
  }

  // Fetch API key status and repo status
  const service = createServiceClient();
  const { data: apiKey } = await service
    .from("api_keys")
    .select("provider, is_valid, updated_at")
    .eq("user_id", user.id)
    .eq("is_valid", true)
    .limit(1)
    .single();

  const { data: repoData } = await service
    .from("users")
    .select("repo_url, repo_status, repo_last_synced_at")
    .eq("id", user.id)
    .single();

  return (
    <SettingsShell>
      <SettingsContent
        userEmail={user.email ?? ""}
        hasApiKey={!!apiKey}
        apiKeyProvider={apiKey?.provider ?? null}
        apiKeyLastValidated={apiKey?.updated_at ?? null}
        repoUrl={repoData?.repo_url ?? null}
        repoStatus={(repoData?.repo_status as RepoStatus) ?? "not_connected"}
        repoLastSyncedAt={repoData?.repo_last_synced_at ?? null}
      />
    </SettingsShell>
  );
}
