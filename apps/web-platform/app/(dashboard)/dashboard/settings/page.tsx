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

  const service = createServiceClient();

  // Parallelize all independent queries
  const [
    { data: apiKey },
    { data: userData },
    { count: conversationCount },
    { count: serviceTokenCount },
  ] = await Promise.all([
    service
      .from("api_keys")
      .select("provider, is_valid, updated_at")
      .eq("user_id", user.id)
      .eq("is_valid", true)
      .limit(1)
      .single(),
    service
      .from("users")
      .select(
        "repo_url, repo_status, repo_last_synced_at, subscription_status, current_period_end, cancel_at_period_end, created_at",
      )
      .eq("id", user.id)
      .single(),
    service
      .from("conversations")
      .select("*", { count: "exact", head: true })
      .eq("user_id", user.id),
    service
      .from("service_tokens")
      .select("*", { count: "exact", head: true })
      .eq("user_id", user.id),
  ]);

  return (
    <SettingsShell>
      <SettingsContent
        userEmail={user.email ?? ""}
        hasApiKey={!!apiKey}
        apiKeyProvider={apiKey?.provider ?? null}
        apiKeyLastValidated={apiKey?.updated_at ?? null}
        repoUrl={userData?.repo_url ?? null}
        repoStatus={(userData?.repo_status as RepoStatus) ?? "not_connected"}
        repoLastSyncedAt={userData?.repo_last_synced_at ?? null}
        subscriptionStatus={userData?.subscription_status ?? null}
        currentPeriodEnd={userData?.current_period_end ?? null}
        cancelAtPeriodEnd={userData?.cancel_at_period_end ?? false}
        conversationCount={conversationCount ?? 0}
        serviceTokenCount={serviceTokenCount ?? 0}
        createdAt={userData?.created_at ?? new Date().toISOString()}
      />
    </SettingsShell>
  );
}
