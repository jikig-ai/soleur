// PR-G (#3947) — Audit viewer page. Server component; cookie-scoped
// Supabase client for BYOK rows (RLS + belt-and-suspenders); Inngest
// section fetches via /api/dashboard/runs proxy on the client (defers
// the network call so the BYOK section renders immediately and partial-
// degrades correctly if Inngest API fails — spec-flow-analyzer finding).

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import {
  AuditSections,
  type ByokRow,
} from "@/components/audit/audit-sections";

export const dynamic = "force-dynamic";

export default async function AuditPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  // Belt-and-suspenders: .eq("founder_id", user.id) defends against any
  // future RLS loosening on audit_byok_use (precedent: today/route.ts).
  // The RLS policy audit_byok_use_owner_select is the primary gate; this
  // is defense in depth at single-user-incident threshold.
  const { data: byokRows } = await supabase
    .from("audit_byok_use")
    .select("ts, agent_role, token_count, unit_cost_cents")
    .eq("founder_id", user.id)
    .order("ts", { ascending: false })
    .limit(50);

  const rows = (byokRows ?? []) as ByokRow[];

  return (
    <main className="mx-auto max-w-4xl px-6 py-8">
      <header className="mb-8">
        <h1 className="text-2xl font-medium text-soleur-text-primary">
          Audit log
        </h1>
        <p className="mt-2 text-sm text-soleur-text-secondary">
          Every Soleur run, every BYOK call. You decide. Agents execute. The
          ledger is the record.
        </p>
      </header>

      <div className="space-y-6">
        <AuditSections source="byok" rows={rows} />
        <AuditSections source="inngest" />
      </div>
    </main>
  );
}
