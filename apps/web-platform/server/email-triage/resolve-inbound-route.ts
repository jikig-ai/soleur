// ADR-269 — resolve an inbound email's recipient addresses through
// `email_inbox_routes`, with the env-pinned EMAIL_TRIAGE_OWNER_USER_ID as the
// fallback.
//
// INVARIANT (enforced here, not just documented): until the ADR-269 hard
// preconditions land (#9459), every route MUST resolve to the operator pair
// (workspace = owner = EMAIL_TRIAGE_OWNER_USER_ID). A route to anyone else is
// refused: the mail is claimed under the operator and the anomaly is reported,
// never delivered to the other workspace. That makes two things safe at once:
// the table cannot misroute a tenant's mail, and ANY routing anomaly (a lookup
// error, a refused route) can degrade to the operator instead of losing mail.
//
// Because real prd mail always carries recipients (Sieve-forwarded `ops@` mail
// arrives as `to: triage@inbound.soleur.ai`), this resolver runs one indexed
// query per mail. Contract (each line pinned by
// test/server/email-triage-resolve-route.test.ts):
//   - empty recipients          → env owner, NO routes query;
//   - routes query ERROR        → env owner, `degraded: route-lookup-failed`
//                                 (statutory mail must keep flowing through a
//                                 schema-cache miss, a blip or a rollback);
//   - no matching route         → env owner;
//   - route(s) all operator     → the operator pair, `source: "table"` (two
//                                 aliases of the operator are not ambiguous);
//   - any non-operator route    → env owner, `degraded: non-operator-route`;
//   - env owner unset           → throws (retriable): nothing can be validated.
//
// The Supabase client is injected (no createServiceClient import here), so the
// caller's step owns the service-role boundary.

import type { createServiceClient } from "@/lib/supabase/service";

type ServiceClient = ReturnType<typeof createServiceClient>;

export interface ResolvedRoute {
  workspaceId: string;
  /** user_id of the row and the notification recipient. */
  ownerId: string;
  source: "table" | "env-fallback";
  /** Set when routing could not be honoured and the env owner was used instead.
   * The caller reports it (Sentry); the resolver stays free of observability. */
  degraded?: "route-lookup-failed" | "non-operator-route";
  /** pg error code when `degraded === "route-lookup-failed"` (code only, TR3). */
  detail?: string;
}

interface RouteRow {
  address: string;
  workspace_id: string;
  owner_user_id: string;
}

/** Owner-validation memo TTL — re-validating with 2 queries per email is pure
 * overhead; 1h bounds staleness if the owner row is deleted/demoted. */
const OWNER_VALIDATION_TTL_MS = 60 * 60 * 1000;

// Keyed on ownerId so an env rotation invalidates immediately.
let ownerValidationMemo: { ownerId: string; validatedAt: number } | null = null;

/** Test-only: clear the owner-validation memo between cases. */
export function resetOwnerValidationMemo(): void {
  ownerValidationMemo = null;
}

/**
 * The strongest available founder/owner predicate: the ADR-038 N2 solo-workspace
 * shape — a users row exists AND a workspace_members row with
 * workspace_id = user_id = owner AND role = 'owner' exists (users.role is
 * 'prd'/'dev' flag-targeting, not ownership). Failure is a retriable throw,
 * never a skip.
 */
async function assertOperatorIsWorkspaceOwner(
  sb: ServiceClient,
  ownerId: string,
): Promise<void> {
  const fresh =
    ownerValidationMemo !== null &&
    ownerValidationMemo.ownerId === ownerId &&
    Date.now() - ownerValidationMemo.validatedAt < OWNER_VALIDATION_TTL_MS;
  if (fresh) return;

  const { data: userRow, error: userErr } = await sb
    .from("users")
    .select("id")
    .eq("id", ownerId)
    .maybeSingle();
  if (userErr) {
    throw new Error(`owner lookup failed: ${userErr.code ?? "unknown"}`);
  }
  if (!userRow) {
    throw new Error("EMAIL_TRIAGE_OWNER_USER_ID does not match a users row");
  }
  const { data: memberRow, error: memberErr } = await sb
    .from("workspace_members")
    .select("user_id")
    .eq("workspace_id", ownerId)
    .eq("user_id", ownerId)
    .eq("role", "owner")
    .maybeSingle();
  if (memberErr) {
    throw new Error(`owner role lookup failed: ${memberErr.code ?? "unknown"}`);
  }
  if (!memberRow) {
    throw new Error(
      "EMAIL_TRIAGE_OWNER_USER_ID is not the workspace owner (workspace_members role='owner')",
    );
  }
  ownerValidationMemo = { ownerId, validatedAt: Date.now() };
}

export const OWNER_UNSET_MESSAGE =
  "EMAIL_TRIAGE_OWNER_USER_ID is unset — cannot claim inbound email";

export async function resolveInboundRoute(
  sb: ServiceClient,
  recipients: string[],
  envOwnerId: string | undefined,
): Promise<ResolvedRoute> {
  if (!envOwnerId) {
    // Retriable by design — NEVER skip, NEVER NonRetriableError: a missing
    // owner env is ops misconfiguration; Inngest redelivery means no email is
    // dropped while it is fixed, and Layer 1 captures on exhaustion. It also
    // blocks routing: without the operator pair nothing can be validated.
    throw new Error(OWNER_UNSET_MESSAGE);
  }

  const toEnvOwner = async (
    extra?: Pick<ResolvedRoute, "degraded" | "detail">,
  ): Promise<ResolvedRoute> => {
    await assertOperatorIsWorkspaceOwner(sb, envOwnerId);
    return {
      workspaceId: envOwnerId,
      ownerId: envOwnerId,
      source: "env-fallback",
      ...extra,
    };
  };

  if (recipients.length === 0) return toEnvOwner();

  const { data, error } = await sb
    .from("email_inbox_routes")
    .select("address, workspace_id, owner_user_id")
    .in("address", recipients);
  if (error) {
    return toEnvOwner({
      degraded: "route-lookup-failed",
      detail: error.code ?? "unknown",
    });
  }
  const rows = (data as RouteRow[] | null) ?? [];
  if (rows.length === 0) return toEnvOwner();

  const operatorOnly = rows.every(
    (r) => r.workspace_id === envOwnerId && r.owner_user_id === envOwnerId,
  );
  if (!operatorOnly) return toEnvOwner({ degraded: "non-operator-route" });

  await assertOperatorIsWorkspaceOwner(sb, envOwnerId);
  return { workspaceId: envOwnerId, ownerId: envOwnerId, source: "table" };
}
