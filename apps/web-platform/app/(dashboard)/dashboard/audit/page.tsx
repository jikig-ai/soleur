// PR-G (#3947) — Audit viewer page. Server component; cookie-scoped
// Supabase client for BYOK rows (RLS + belt-and-suspenders); Inngest
// section fetches via /api/dashboard/runs proxy on the client (defers
// the network call so the BYOK section renders immediately and partial-
// degrades correctly if Inngest API fails — spec-flow-analyzer finding).

import Link from "next/link";
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

  // .eq("founder_id", user.id) is NOT merely belt-and-suspenders, and the
  // comment here used to say it was. The live SELECT policy on
  // audit_byok_use is audit_byok_use_workspace_member_select — created by
  // 059_workspace_keyed_rls_sweep.sql, which DROPs the founder-scoped
  // audit_byok_use_owner_select from mig 037 in the same file — and it
  // reads USING (public.is_workspace_member(workspace_id, auth.uid())).
  // So RLS admits every co-member's rows in the viewer's workspace(s), and
  // this filter is strictly NARROWER than the policy: it is what makes this
  // page a personal ledger rather than a workspace one. It still defends
  // against future RLS loosening (precedent: today/route.ts), but that is
  // now its second job, not its first.
  //
  // Consequence to know before widening this filter (#7829 / mig 137):
  // a refused delegated turn now persists an audit_byok_use row attributed
  // to the GRANTEE (founder_id = caller) with attribution_shift_reason set,
  // while workspace_id stays the grantor's. Such rows therefore appear on
  // the grantee's page and not the grantor's, and the reason column is not
  // selected below, so a refusal is currently indistinguishable here from
  // an ordinary charge.
  const { data: byokRows } = await supabase
    .from("audit_byok_use")
    // `attribution_shift_reason` is selected because migration 137 makes
    // REFUSED delegated turns persist a row attributed to the grantee. Without
    // it a refusal renders here as an ordinary charge the user incurred.
    .select("ts, agent_role, token_count, unit_cost_cents, attribution_shift_reason")
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

        {/* PR-H+1 (#4098): discoverability link for the GitHub
            installation-token audit sub-route. Without this anchor the
            /dashboard/audit/github page is reachable by URL only — a
            single-user-incident regression vector under Art. 30 PA-16
            (the disclosure asserts founders can inspect the ledger). */}
        <section
          aria-labelledby="audit-related-header"
          className="rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 p-5"
        >
          <h2
            id="audit-related-header"
            className="mb-2 font-medium text-soleur-text-primary"
          >
            Related ledgers
          </h2>
          <ul className="space-y-1 text-sm">
            <li>
              <Link
                href="/dashboard/audit/github"
                className="text-soleur-text-link underline-offset-2 hover:underline"
                data-testid="audit-github-link"
              >
                GitHub token-use audit →
              </Link>
              <span className="ml-2 text-soleur-text-muted">
                Every GitHub App installation-token call Soleur makes on
                your behalf.
              </span>
            </li>
          </ul>
        </section>
      </div>
    </main>
  );
}
