// Read-only beta-CRM board page (feat-beta-crm-ui #6172). Server component:
// cookie-session auth gate, then the client surface inside a <Suspense>
// boundary. The boundary is REQUIRED — CrmSurface calls useSearchParams for the
// ?contact=<id> deep-link, and a bare client page would fail `next build` with
// missing-suspense-with-csr-bailout. Mirrors the Workstream/Inbox page pattern.

import { Suspense } from "react";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { CrmSurface } from "@/components/crm/crm-surface";

export const dynamic = "force-dynamic";

export default async function CrmPage() {
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
        <CrmSurface />
      </Suspense>
    </main>
  );
}
