import { redirect } from "next/navigation";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { SettingsContent } from "@/components/settings/settings-content";

export default async function SettingsPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login");
  }

  // Fetch API key status
  const service = createServiceClient();
  const { data: apiKey } = await service
    .from("api_keys")
    .select("provider, is_valid, updated_at")
    .eq("user_id", user.id)
    .eq("is_valid", true)
    .limit(1)
    .single();

  return (
    <SettingsContent
      userEmail={user.email ?? ""}
      hasApiKey={!!apiKey}
      apiKeyProvider={apiKey?.provider ?? null}
      apiKeyLastValidated={apiKey?.updated_at ?? null}
    />
  );
}
