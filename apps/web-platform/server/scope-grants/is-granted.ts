// PR-G (#3947) — Webhook predicate's grant probe. Reads scope_grants via
// service-role client because the webhook handler is service-role-context
// (no founder JWT). The .eq("founder_id", founderId) is load-bearing
// here (NOT belt-and-suspenders) — service-role bypasses RLS, so the
// founder filter IS the tenant gate. A typo or stale founderId would
// leak across tenants. AC3 includes the founderId-typo regression test.

import type { SupabaseClient } from "@supabase/supabase-js";
import * as Sentry from "@sentry/nextjs";
import type { ActionClass, ActionClassTier } from "./action-class-map";

// Code-constant denylist. PR-H tightened the element type to ActionClass
// so the literal-union narrows compile-time. Empty by default; adding an
// entry requires a sibling rejection test (cq-write-failing-tests-before).
const ACTION_CLASS_DENYLIST: ReadonlySet<ActionClass> = new Set<ActionClass>();

export function isDenied(actionClass: ActionClass): boolean {
  return ACTION_CLASS_DENYLIST.has(actionClass);
}

export interface ActiveGrant {
  tier: ActionClassTier;
}

// PR-H (#4077): cookie-scoped callers (`isGranted(supabase, ...)` from
// dashboard routes) coexist with service-role callers (webhook). The
// 1st argument is the client to query through — RLS lets cookie-scoped
// founders self-read; service-role-scoped webhook calls bypass RLS and
// rely on `.eq("founder_id", founderId)` as the tenant gate.
export async function isGranted(
  client: SupabaseClient,
  founderId: string,
  actionClass: ActionClass,
): Promise<ActiveGrant | null> {
  if (isDenied(actionClass)) return null;

  const { data, error } = await client
    .from("scope_grants")
    .select("tier")
    .eq("founder_id", founderId)
    .eq("action_class", actionClass)
    .is("revoked_at", null)
    .order("granted_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  // Distinguish no-grant (silent null) from DB error (Sentry + null).
  // Fail-closed in both cases per single-user-incident threshold:
  // if we can't confirm a grant exists, we don't fire inngest.send.
  // DB errors are a regression signal — surface to Sentry (TR9).
  if (error) {
    Sentry.captureException(error, {
      tags: { surface: "is-granted", action_class: actionClass },
    });
    return null;
  }
  if (!data) return null;
  return { tier: data.tier as ActionClassTier };
}
