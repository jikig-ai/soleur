// #9545 — the one place that evaluates the `egress-audit-collection` runtime flag for an organisation.
//
// Three readers share it so their identities cannot drift: the ingest route (decides whether to
// store a batch), the egress audit view (decides which empty state is true) and the Scope Grants
// page (decides whether the enable dialog may say hosts are recorded). The identity shape matters:
// the flag is evaluated PER ORGANISATION (a per-org Flagsmith override is how a Jikigai-owned canary
// organisation is enabled), with role "prd" and no user, so the root provider's oldest-membership org
// and the `orgId: null` reads elsewhere on the settings pages can never be used in its place.
//
// getRuntimeFlag never throws on a Flagsmith outage: it falls back to the GLOBAL, role-blind env
// mirror, which must stay off in production (ADR-288). An outage therefore reads "off" for ingest and
// for every reader alike, so "nothing is being recorded" and "Recording isn't on" stay true together.
// A caller that wants to distinguish a thrown evaluation from "off" catches the throw itself.

import { getRuntimeFlag } from "@/lib/feature-flags/server";

export const EGRESS_AUDIT_COLLECTION_FLAG = "egress-audit-collection" as const;

export async function isEgressAuditCollectionOn(orgId: string): Promise<boolean> {
  return getRuntimeFlag(EGRESS_AUDIT_COLLECTION_FLAG, {
    userId: null,
    role: "prd",
    orgId,
    email: null,
    subscriptionStatus: null,
  });
}
