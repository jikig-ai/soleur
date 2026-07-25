// Routines management page (#5345 PR-1). Server component: cookie-session auth
// gate, then renders the client surface which fetches /api/dashboard/routines*.

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { RoutinesSurface } from "@/components/routines/routines-surface";

export const dynamic = "force-dynamic";

export default async function RoutinesPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  return (
    <main className="mx-auto max-w-5xl px-4 py-8 sm:px-6">
      <header className="mb-6">
        <h1 className="text-2xl font-medium text-soleur-text-primary">
          Routines
        </h1>
        <p className="mt-2 text-sm text-soleur-text-secondary">
          Recurring work definitions that materialize into auditable execution
          issues.
        </p>
      </header>
      <RoutinesSurface />
    </main>
  );
}
