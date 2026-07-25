// PR-H (#3244) — Founder-facing read-only viewer for
// `audit_github_token_use` rows. RLS policy
// `audit_github_token_use_owner_select` is the primary gate; the
// explicit `.eq("founder_id", user.id)` is belt-and-suspenders against
// any future RLS loosening (precedent: app/(dashboard)/dashboard/audit/page.tsx).
//
// PR-H ships the table + RPC + Art. 17 cascade (mig 051). PR-H+1
// (#4098) wires the per-Octokit-call audit writer at the
// `server/github/app-client.ts` factory — every Octokit response now
// writes one audit_github_token_use row via recordGithubApiCall. The
// ledger populates as Soleur uses the GitHub App installation token on
// behalf of the founder.

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export const dynamic = "force-dynamic";

interface GhAuditRow {
  ts: string;
  installation_id: number;
  repo_full_name: string | null;
  endpoint: string;
  response_status: number | null;
}

export default async function GitHubAuditPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  const { data } = await supabase
    .from("audit_github_token_use")
    .select("ts, installation_id, repo_full_name, endpoint, response_status")
    .eq("founder_id", user.id)
    .order("ts", { ascending: false })
    .limit(50);

  const rows = (data ?? []) as GhAuditRow[];

  return (
    <main className="mx-auto max-w-4xl px-6 py-8">
      <header className="mb-8">
        <h1 className="text-2xl font-medium text-soleur-text-primary">
          GitHub token-use audit
        </h1>
        <p className="mt-2 text-sm text-soleur-text-secondary">
          Every GitHub App installation-token use by Soleur, recorded as
          Art. 5(2) accountability evidence. Read-only; rows are append-only
          (WORM trigger) and anonymise on account deletion.
        </p>
      </header>

      <section
        aria-labelledby="gh-audit-section-header"
        className="rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1"
      >
        <header className="border-b border-soleur-border-default px-5 py-3">
          <h2 id="gh-audit-section-header" className="font-medium text-soleur-text-primary">
            Recent token uses
          </h2>
          <p className="mt-1 text-xs text-soleur-text-muted">
            Latest 50 calls, ordered most-recent first.
          </p>
        </header>
        {rows.length === 0 ? (
          <p
            className="px-5 py-6 text-sm text-soleur-text-secondary"
            data-testid="gh-audit-empty"
          >
            No GitHub token uses yet. The ledger populates as Soleur
            uses your GitHub App installation token on your behalf —
            every API call appends one row here.
          </p>
        ) : (
          <>
            {/* Desktop: table. Mobile (< md): stacked record cards. This page is
                a server component (no hooks), so the responsive split is pure CSS
                dual-render — both trees are server-rendered with identical data;
                `toLocaleString` stays server-side (no hydration drift). Content is
                cheap (<=50 read-only rows), so double-DOM is negligible. */}
            <table className="hidden w-full text-sm md:table">
              <thead className="text-left text-xs uppercase text-soleur-text-muted">
                <tr>
                  <th className="px-5 py-2 font-medium">Timestamp</th>
                  <th className="px-5 py-2 font-medium">Repository</th>
                  <th className="px-5 py-2 font-medium">Endpoint</th>
                  <th className="px-5 py-2 font-medium">Status</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((r, i) => (
                  <tr
                    key={`${r.ts}-${i}`}
                    className="border-t border-soleur-border-default/50"
                  >
                    <td className="px-5 py-2 text-soleur-text-secondary">
                      {new Date(r.ts).toLocaleString()}
                    </td>
                    <td className="px-5 py-2 text-soleur-text-primary">
                      {r.repo_full_name ?? <span className="text-soleur-text-muted">—</span>}
                    </td>
                    <td className="px-5 py-2 font-mono text-xs text-soleur-text-secondary">
                      {r.endpoint}
                    </td>
                    <td className="px-5 py-2 text-soleur-text-secondary">
                      {r.response_status ?? <span className="text-soleur-text-muted">—</span>}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>

            <div className="divide-y divide-soleur-border-default/50 md:hidden">
              {rows.map((r, i) => (
                <div key={`${r.ts}-${i}-card`} className="space-y-1.5 px-5 py-3">
                  <div className="flex items-center justify-between gap-2">
                    <span className="min-w-0 truncate font-medium text-soleur-text-primary">
                      {r.repo_full_name ?? <span className="text-soleur-text-muted">—</span>}
                    </span>
                    <span className="shrink-0 text-xs text-soleur-text-secondary">
                      {r.response_status ?? <span className="text-soleur-text-muted">—</span>}
                    </span>
                  </div>
                  <div className="flex items-start justify-between gap-3 text-xs">
                    <span className="shrink-0 text-soleur-text-muted">Endpoint</span>
                    <span className="min-w-0 break-all text-right font-mono text-soleur-text-secondary">
                      {r.endpoint}
                    </span>
                  </div>
                  <div className="flex items-center justify-between gap-3 text-xs">
                    <span className="text-soleur-text-muted">Time</span>
                    <span className="text-soleur-text-secondary">
                      {new Date(r.ts).toLocaleString()}
                    </span>
                  </div>
                </div>
              ))}
            </div>
          </>
        )}
      </section>

      <p className="mt-6 text-xs text-soleur-text-muted">
        Article 30 PA-16 (GitHub-sourced priority signals) governs this
        ledger. Anonymisation runs automatically when you delete your
        account (Art. 17). See{" "}
        <span className="font-mono">
          knowledge-base/legal/article-30-register.md
        </span>{" "}
        for the full processing record.
      </p>
    </main>
  );
}
