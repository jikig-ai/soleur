import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { ConnectedServicesContent } from "@/components/settings/connected-services-content";

export default async function ConnectedServicesPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login");
  }

  // Fetch connected services (non-sensitive fields only)
  const { data } = await supabase
    .from("api_keys")
    .select("provider, is_valid, validated_at, updated_at")
    .eq("user_id", user.id);

  return <ConnectedServicesContent initialServices={data ?? []} />;
}
