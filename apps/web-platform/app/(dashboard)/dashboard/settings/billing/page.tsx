import { redirect } from "next/navigation";
import { createClient, createServiceClient } from "@/lib/supabase/server";
import { BillingSection } from "@/components/settings/billing-section";
import { SettingsShell } from "@/components/settings/settings-shell";

export default async function BillingPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    redirect("/login");
  }

  const service = createServiceClient();

  const [{ data: userData }, { count: conversationCount }, { count: serviceTokenCount }] =
    await Promise.all([
      service
        .from("users")
        .select(
          "subscription_status, current_period_end, cancel_at_period_end, created_at",
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
      <BillingSection
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
