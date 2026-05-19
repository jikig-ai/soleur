// PR-G (#3947) — Scope-grant settings page. Founder-facing UI to grant
// or revoke per-action-class authorization. Server component; fetches
// active grants via cookie-scoped RLS Supabase client.
//
// Per code-simplicity review: list iteration + empty state inlined here
// (one action class in PR-G; no separate list-wrapper module).

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import {
  ACTION_CLASSES,
  type ActionClass,
  type ActionClassTier,
} from "@/server/scope-grants/action-class-map";
import { ScopeGrantRow } from "@/components/scope-grants/scope-grant-row";

export const dynamic = "force-dynamic";

interface ActiveGrant {
  action_class: ActionClass;
  tier: ActionClassTier;
  granted_at: string;
}

export default async function ScopeGrantsPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/login");

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

      <ul className="space-y-4">
        {ACTION_CLASSES.map((ac) => {
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
      {activeByClass.size === 0 ? (
        <p className="mt-6 rounded-lg border border-soleur-border-default bg-soleur-bg-surface-2 p-4 text-sm text-soleur-text-secondary">
          No grants yet — Soleur will not act on your behalf for any action
          class until you authorize one above.
        </p>
      ) : null}
    </div>
  );
}
