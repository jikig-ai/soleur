// In-app Releases page (#5958). Server component: cookie-session auth gate,
// then renders the client surface which fetches /api/dashboard/releases (the
// app's web-v* GitHub Releases, cleaned server-side, newest first).

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { ReleasesSurface } from "@/components/releases/releases-surface";

export const dynamic = "force-dynamic";

export default async function ReleasesPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  return (
    <main className="mx-auto max-w-5xl px-6 py-8">
      <header className="mb-6">
        <h1 className="text-2xl font-medium text-soleur-text-primary">Releases</h1>
        <p className="mt-2 text-sm text-soleur-text-secondary">
          Everything we&apos;ve shipped to Soleur, newest first.
        </p>
      </header>
      <ReleasesSurface />
    </main>
  );
}
