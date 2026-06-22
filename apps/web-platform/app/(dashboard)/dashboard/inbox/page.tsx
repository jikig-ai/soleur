// Inbox list page (#5512). Server component: cookie-session auth gate, then
// renders the client surface inside a <Suspense> boundary. The Suspense
// boundary is REQUIRED — InboxSurface calls useSearchParams, and this is a
// static route, so a bare client page would fail `next build` with
// missing-suspense-with-csr-bailout. Mirrors the Routines page pattern.

import { Suspense } from "react";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { InboxSurface } from "@/components/inbox/inbox-surface";

export const dynamic = "force-dynamic";

export default async function InboxPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  return (
    <main className="mx-auto max-w-5xl px-6 py-8">
      <header className="mb-6">
        <h1 className="text-2xl font-medium text-soleur-text-primary">Inbox</h1>
        <p className="mt-2 text-sm text-soleur-text-secondary">
          Operator email triage — statutory and operational mail routed to your
          workspace. Reads are shared across workspace Owners.
        </p>
      </header>
      <Suspense
        fallback={
          <p className="py-8 text-sm text-soleur-text-secondary">Loading…</p>
        }
      >
        <InboxSurface />
      </Suspense>
    </main>
  );
}
