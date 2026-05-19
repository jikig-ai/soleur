// PR-G (#3947) — Webhook predicate's grant probe. Reads scope_grants via
// service-role client because the webhook handler is service-role-context
// (no founder JWT). The .eq("founder_id", founderId) is load-bearing
// here (NOT belt-and-suspenders) — service-role bypasses RLS, so the
// founder filter IS the tenant gate. A typo or stale founderId would
// leak across tenants. AC3 includes the founderId-typo regression test.

import type { SupabaseClient } from "@supabase/supabase-js";
import * as Sentry from "@sentry/nextjs";
import type { ActionClassTier } from "./action-class-map";

// Code-constant denylist. Inlined per Code Simplicity review — PR-G ships
// with empty denylist; when the first entry lands, extract to a sibling
// file alongside an unmocked rejection test.
const ACTION_CLASS_DENYLIST: ReadonlySet<string> = new Set<string>();

export function isDenied(actionClass: string): boolean {
  return ACTION_CLASS_DENYLIST.has(actionClass);
}

export interface ActiveGrant {
  tier: ActionClassTier;
}

export async function isGranted(
  serviceClient: SupabaseClient,
  founderId: string,
  actionClass: string,
): Promise<ActiveGrant | null> {
  if (isDenied(actionClass)) return null;

  const { data, error } = await serviceClient
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
