// #9545 PR2 — egress audit destination page (wireframes 07-04..07-25). A child route of Scope Grants, so
// the settings shell keeps the Scope Grants tab highlighted. Server-rendered: the loader calls the
// member-gated RPC through the caller's cookie client; the filter is the `?decision=` search param
// (chips are links), so there is no client fetch, abort guard or rate-limited route. Expected failures
// render in place (the settings tabs stay); only an uncaught bug reaches the dashboard error boundary.
// Caching: `force-dynamic` below keeps the page out of the static cache, and the middleware sends
// `Cache-Control: no-store` on authenticated document navigations (test/middleware.no-store.test.ts), so a
// member's audit log is not restored by Back after sign-out (document navigations only; this does not govern
// client-side route transitions or fetches).

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { EgressAuditView } from "@/components/settings/egress-audit-view";
import { parseDecisionFilter } from "@/lib/egress-audit/summary";
import { loadEgressAudit } from "@/server/egress-audit-read";

export const dynamic = "force-dynamic";

export default async function EgressAuditPage({
  searchParams,
}: {
  searchParams: Promise<{ decision?: string | string[] }>;
}) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  // Next 16: searchParams is a Promise. An unknown or repeated value falls back to "all" (never a 400).
  const filter = parseDecisionFilter((await searchParams).decision);
  const result = await loadEgressAudit(supabase, user.id, filter);

  return <EgressAuditView result={result} filter={filter} />;
}
