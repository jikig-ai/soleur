import { createClient } from "@/lib/supabase/server";
import { resolveIdentity } from "@/lib/feature-flags/identity";
import { DashboardShell } from "./dashboard-shell";

// Phase 6 (#5532): async SERVER component. The identity chain is the same
// `resolveIdentity(await createClient())` the root layout runs — both calls
// are cache()-deduped (Phase 3), so this resolves against the already-warm
// memo and adds zero extra RTTs. The three chrome inputs below previously
// arrived via mount effects (fetch /api/admin/check + getSession → users
// select) and popped in post-hydration; they are now in the initial HTML.
export default async function DashboardLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const supabase = await createClient();
  const identity = await resolveIdentity(supabase);
  // Identical derivation to /api/admin/check (which stays — e2e still
  // exercises it). Guarded on non-null userId so an empty/blank
  // ADMIN_USER_IDS entry can never match the anonymous identity.
  const isAdmin =
    identity.userId !== null &&
    (process.env.ADMIN_USER_IDS?.split(",").includes(identity.userId) ??
      false);

  return (
    <DashboardShell
      isAdmin={isAdmin}
      userEmail={identity.email}
      subscriptionStatus={identity.subscriptionStatus}
    >
      {children}
    </DashboardShell>
  );
}
