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
// mirror, which must stay off in production (ADR-288). Two readers, two contracts:
//   * `isEgressAuditCollectionOn` (ingest) returns that plain boolean, so an outage reads "off" and
//     nothing is stored: unchanged behaviour, and the safe direction for a write path.
//   * `readEgressAuditCollectionState` (the view and the card) reports `"unknown"` when the value came
//     from the fallback, so an outage renders the unavailable state instead of asserting "Recording
//     isn't on" (which would be a guess about a flag that did not answer).
// A caller that wants to distinguish a thrown evaluation from either catches the throw itself.

import { getRuntimeFlag, readRuntimeFlagDetailed } from "@/lib/feature-flags/server";

export const EGRESS_AUDIT_COLLECTION_FLAG = "egress-audit-collection" as const;

// One identity for every reader: they must not drift apart.
const identityFor = (orgId: string) => ({
  userId: null,
  role: "prd" as const,
  orgId,
  email: null,
  subscriptionStatus: null,
});

export async function isEgressAuditCollectionOn(orgId: string): Promise<boolean> {
  return getRuntimeFlag(EGRESS_AUDIT_COLLECTION_FLAG, identityFor(orgId));
}

/** `true` / `false` as Flagsmith answered, `"unknown"` when the value is the env mirror because Flagsmith did not answer. */
export async function readEgressAuditCollectionState(orgId: string): Promise<true | false | "unknown"> {
  const { value, fellBack } = await readRuntimeFlagDetailed(EGRESS_AUDIT_COLLECTION_FLAG, identityFor(orgId));
  return fellBack ? "unknown" : value;
}
