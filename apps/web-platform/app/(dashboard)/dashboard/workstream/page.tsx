// Workstream board page. Server component: cookie-session auth gate, then
// renders the client board inside a <Suspense> boundary. The Suspense boundary
// is REQUIRED — WorkstreamBoard calls useSearchParams, and this is a static
// route, so a bare client page would fail `next build` with
// missing-suspense-with-csr-bailout. Mirrors the Inbox/Routines page pattern.

import { Suspense } from "react";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { WorkstreamBoard } from "@/components/workstream/workstream-board";

export const dynamic = "force-dynamic";

export default async function WorkstreamPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  return (
    <main className="px-4 py-8 sm:px-6">
      <Suspense
        fallback={
          <p className="py-8 text-sm text-soleur-text-secondary">Loading…</p>
        }
      >
        <WorkstreamBoard />
      </Suspense>
    </main>
  );
}
