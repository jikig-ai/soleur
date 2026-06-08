// PR-G (#3947) — Scope-grant settings page. Founder-facing UI to grant
// or revoke per-action-class authorization. Server component; fetches
// active grants via cookie-scoped RLS Supabase client.
//
// Per code-simplicity review: list iteration + empty state inlined here
// (one action class in PR-G; no separate list-wrapper module).

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import {
  type ActionClass,
  type ActionClassTier,
} from "@/server/scope-grants/action-class-map";
import { ACTION_CLASSES_BY_CATEGORY } from "@/lib/messages/action-class-copy";
import { ScopeGrantRow } from "@/components/scope-grants/scope-grant-row";
import { TemplateAuthorizationRow } from "@/components/scope-grants/template-authorization-row";
import { BashAutonomousToggle } from "@/components/settings/bash-autonomous-toggle";
import { DebugModeToggle } from "@/components/settings/debug-mode-toggle";
import { resolveBashAutonomous } from "@/server/resolve-bash-autonomous";
import { resolveDebugMode } from "@/server/resolve-debug-mode";
import { isDebugModeAvailable, type Role } from "@/lib/feature-flags/server";
import { resolveCurrentWorkspaceId } from "@/server/workspace-resolver";

export const dynamic = "force-dynamic";

interface ActiveGrant {
  action_class: ActionClass;
  tier: ActionClassTier;
  granted_at: string;
}

interface ActiveTemplateAuth {
  id: string;
  template_hash: string;
  action_class: string;
  authorized_at: string;
  expires_at: string;
  soft_reconfirm_at: string;
  max_sends: number;
  // sends_used is computed via a parallel COUNT against action_sends —
  // see scope-grants/page.tsx below. NOT a column on the row.
}

export default async function ScopeGrantsPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  // feat-bash-autonomous-default-on — Concierge command-execution toggle
  // (relocated here from Settings → Privacy). Owner-only: read the current
  // value (member-checked, fail-closed false) and resolve owner status of the
  // active workspace so non-owners don't see a control they can't use. The
  // scope-grants page does NOT otherwise resolve workspace ownership, so add
  // the same membership query the Privacy page used (cookie/RLS-scoped client,
  // workspace_members members_select_peers policy — caller reads its own row).
  const autonomous = await resolveBashAutonomous(user.id);
  const activeWorkspaceId = await resolveCurrentWorkspaceId(user.id, supabase);
  const { data: membership } = await supabase
    .from("workspace_members")
    .select("role")
    .eq("workspace_id", activeWorkspaceId)
    .eq("user_id", user.id)
    .maybeSingle();
  const isWorkspaceOwner = membership?.role === "owner";

  // feat-debug-mode-stream — internal harness-stream toggle. Visible ONLY to
  // the `dev` cohort (server-resolved availability, fail-closed; a Flagsmith
  // outage keeps it hidden for prd). Owner-WRITE: a non-owner dev sees the
  // current state read-only. Read the dev role from the cookie/RLS-scoped
  // client (caller reads its own users row), then the member-checked toggle.
  const { data: debugRoleRow } = await supabase
    .from("users")
    .select("role")
    .eq("id", user.id)
    .single<{ role: unknown }>();
  const debugRole: Role = debugRoleRow?.role === "dev" ? "dev" : "prd";
  const debugAvailable = await isDebugModeAvailable({
    userId: user.id,
    role: debugRole,
    orgId: null,
  });
  const debugMode = debugAvailable ? await resolveDebugMode(user.id) : false;

  // Belt-and-suspenders .eq("founder_id", user.id) defends against any
  // future RLS loosening on scope_grants. Comment per today/route.ts
  // precedent (the RLS policy is the primary gate; this is defense in
  // depth at single-user-incident threshold).
  const { data: rows } = await supabase
    .from("scope_grants")
    .select("action_class, tier, granted_at")
    .eq("founder_id", user.id)
    .is("revoked_at", null)
    .order("granted_at", { ascending: false });

  // Build a "currently active grant per action class" map. The WORM RPC
  // pattern (re-grant revokes previous) means at most one active row per
  // (founder_id, action_class), but defend against the invariant being
  // violated by future migrations: take the most recent if multiple.
  const activeByClass = new Map<ActionClass, ActiveGrant>();
  for (const r of (rows ?? []) as ActiveGrant[]) {
    if (!activeByClass.has(r.action_class)) {
      activeByClass.set(r.action_class, r);
    }
  }

  // PR-I (#4078) — Active template authorizations. Plan §Phase 7 query:
  // JOIN scope_grants and filter sg.revoked_at IS NULL so template_auths
  // under revoked grants do not appear (architecture-strategist P1).
  // supabase-js !inner join produces an INNER JOIN; the .is filter on
  // the joined relation enforces the scope_grants.revoked_at IS NULL leg.
  const { data: templateAuthRows } = await supabase
    .from("template_authorizations")
    .select(
      "id, template_hash, action_class, authorized_at, expires_at, soft_reconfirm_at, max_sends, grant_id, scope_grants!inner(revoked_at, founder_id)",
    )
    .eq("founder_id", user.id)
    // Belt-and-suspenders on the joined scope_grants row: independent of
    // scope_grants RLS, the JOIN's `founder_id` MUST match the calling
    // founder. If a future migration loosens scope_grants RLS, this
    // filter still prevents cross-tenant leakage of the joined
    // revoked_at flag. Surfaced by PR-I multi-agent review
    // (architecture-strategist P2-2).
    .eq("scope_grants.founder_id", user.id)
    .is("revoked_at", null)
    .is("scope_grants.revoked_at", null)
    .order("authorized_at", { ascending: false });

  const templateAuths = (templateAuthRows ?? []) as Array<
    ActiveTemplateAuth & { grant_id: string }
  >;

  // Per-row sends_used count. Parallel COUNT against action_sends with
  // matching (user_id, template_hash). Sequenced after the rows fetch so
  // we know which template_hashes to count for.
  const sendsByHash = new Map<string, number>();
  if (templateAuths.length > 0) {
    const uniqueHashes = Array.from(
      new Set(templateAuths.map((r) => r.template_hash)),
    );
    const counts = await Promise.all(
      uniqueHashes.map(async (h) => {
        const { count } = await supabase
          .from("action_sends")
          .select("id", { count: "exact", head: true })
          .eq("user_id", user.id)
          .eq("template_hash", h);
        return [h, count ?? 0] as const;
      }),
    );
    for (const [h, c] of counts) sendsByHash.set(h, c);
  }

  return (
    <div className="mx-auto max-w-3xl px-6 py-8">
      <header className="mb-6">
        <h1 className="text-2xl font-medium text-soleur-text-primary">
          Scope Grants
        </h1>
        <p className="mt-2 text-sm text-soleur-text-secondary">
          Authorize Soleur to act on your behalf for specific action classes.
          You decide. Agents execute. Revoke at any time. Revoking won&apos;t
          stop runs already in progress.
        </p>
      </header>

      {isWorkspaceOwner && (
        <section
          id="concierge-command-execution"
          aria-labelledby="concierge-command-execution-heading"
          className="mb-8 rounded-none border border-soleur-border-default bg-soleur-bg-surface-1 p-4"
        >
          <h2
            id="concierge-command-execution-heading"
            className="mb-2 text-sm font-medium uppercase tracking-wide text-soleur-text-muted"
          >
            Concierge command execution
          </h2>
          <p className="mb-4 text-sm text-soleur-text-secondary">
            The Concierge runs commands to get work done. With autonomous mode
            on it runs non-blocked commands without asking you to approve each
            one; with it off, it asks before every command. The blocklist
            (curl, wget, sudo, …) and secret redaction always apply.
          </p>
          <BashAutonomousToggle
            initialAutonomous={autonomous}
            isOwner={isWorkspaceOwner}
          />
        </section>
      )}

      {debugAvailable && (
        <section
          id="debug-mode"
          aria-labelledby="debug-mode-heading"
          className="mb-8 rounded-none border border-dashed border-soleur-border-default bg-soleur-bg-surface-1 p-4"
        >
          <h2
            id="debug-mode-heading"
            className="mb-2 text-sm font-medium uppercase tracking-wide text-soleur-text-muted"
          >
            Debug mode (internal)
          </h2>
          <DebugModeToggle initialDebugMode={debugMode} isOwner={isWorkspaceOwner} />
        </section>
      )}

      {Array.from(ACTION_CLASSES_BY_CATEGORY.entries()).map(
        ([category, classes]) => {
          if (classes.length === 0) return null;
          const headingId = `scope-grants-category-${category
            .toLowerCase()
            .replace(/\s+/g, "-")}`;
          return (
            <section
              key={category}
              aria-labelledby={headingId}
              className="mb-8 last:mb-0"
            >
              <h2
                id={headingId}
                className="mb-3 text-sm font-medium uppercase tracking-wide text-soleur-text-muted"
              >
                {category}
              </h2>
              <ul className="space-y-4">
                {classes.map((ac) => {
                  const active = activeByClass.get(ac);
                  return (
                    <li key={ac}>
                      <ScopeGrantRow
                        actionClass={ac}
                        currentTier={active?.tier ?? null}
                        grantedAt={active?.granted_at ?? null}
                      />
                    </li>
                  );
                })}
              </ul>
            </section>
          );
        },
      )}
      {activeByClass.size === 0 ? (
        <p className="mt-6 rounded-lg border border-soleur-border-default bg-soleur-bg-surface-2 p-4 text-sm text-soleur-text-secondary">
          No grants yet — Soleur will not act on your behalf for any action
          class until you authorize one above.
        </p>
      ) : null}

      {/* PR-I (#4078) — Template authorizations section. */}
      <section
        aria-labelledby="template-authorizations-heading"
        className="mt-10"
      >
        <h2
          id="template-authorizations-heading"
          className="mb-3 text-sm font-medium uppercase tracking-wide text-soleur-text-muted"
        >
          Template authorizations
        </h2>
        {templateAuths.length > 0 ? (
          <ul className="space-y-4">
            {templateAuths.map((row) => (
              <li key={row.id}>
                <TemplateAuthorizationRow
                  id={row.id}
                  templateHash={row.template_hash}
                  actionClass={row.action_class}
                  authorizedAt={row.authorized_at}
                  expiresAt={row.expires_at}
                  softReconfirmAt={row.soft_reconfirm_at}
                  maxSends={row.max_sends}
                  sendsUsed={sendsByHash.get(row.template_hash) ?? 0}
                />
              </li>
            ))}
          </ul>
        ) : (
          <p className="rounded-lg border border-soleur-border-default bg-soleur-bg-surface-2 p-4 text-sm text-soleur-text-secondary">
            No template authorizations yet. When you 1-click send a draft,
            the template will be authorized for up to 100 sends over 90 days.
          </p>
        )}
      </section>
    </div>
  );
}
