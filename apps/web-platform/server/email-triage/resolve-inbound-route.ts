// ADR-269 — resolve an inbound email's recipient addresses to a validated
// (workspace, owner) pair through `email_inbox_routes`, with the env-pinned
// EMAIL_TRIAGE_OWNER_USER_ID as the no-match fallback.
//
// Contract (each line is pinned by test/server/email-triage-resolve-route.test.ts):
//   - empty recipients          → env owner, NO routes query (prd path is
//                                 byte-identical while the table is empty);
//   - routes query ERROR        → throws (retriable). NEVER falls back: a
//                                 fallback on error would hand a routed
//                                 tenant's mail to the operator;
//   - two or more routes match  → throws (ambiguous). Silent first-wins would
//                                 let a sender steer which tenant a mail
//                                 lands in; fan-out is a #9459 design;
//   - one route matches         → that route, owner validated as a PAIR;
//   - no match                  → env owner (fallback).
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
}

interface RouteRow {
  address: string;
  workspace_id: string;
  owner_user_id: string;
}

/** Owner-validation memo TTL — re-validating with 2 queries per email is pure
 * overhead; 1h bounds staleness if an owner row is deleted/demoted. */
const OWNER_VALIDATION_TTL_MS = 60 * 60 * 1000;

// Keyed on the (workspace, owner) PAIR: a route change or env rotation
// invalidates immediately.
const ownerValidationMemo = new Map<string, number>();

/** Test-only: clear the owner-validation memo between cases. */
export function resetOwnerValidationMemo(): void {
  ownerValidationMemo.clear();
}

/**
 * The strongest available founder/owner predicate: a users row exists AND a
 * workspace_members row (workspace_id, user_id, role='owner') exists. For the
 * env path the pair is (owner, owner) — the ADR-038 N2 solo-workspace shape.
 * Failure is a retriable throw, never a skip.
 */
async function assertWorkspaceOwner(
  sb: ServiceClient,
  workspaceId: string,
  ownerId: string,
  source: ResolvedRoute["source"],
): Promise<void> {
  const key = `${workspaceId}:${ownerId}`;
  const validatedAt = ownerValidationMemo.get(key);
  if (validatedAt !== undefined && Date.now() - validatedAt < OWNER_VALIDATION_TTL_MS) {
    return;
  }
  const label = source === "env-fallback" ? "EMAIL_TRIAGE_OWNER_USER_ID" : "route owner";

  const { data: userRow, error: userErr } = await sb
    .from("users")
    .select("id")
    .eq("id", ownerId)
    .maybeSingle();
  if (userErr) {
    throw new Error(`owner lookup failed: ${userErr.code ?? "unknown"}`);
  }
  if (!userRow) {
    throw new Error(`${label} does not match a users row`);
  }
  const { data: memberRow, error: memberErr } = await sb
    .from("workspace_members")
    .select("user_id")
    .eq("workspace_id", workspaceId)
    .eq("user_id", ownerId)
    .eq("role", "owner")
    .maybeSingle();
  if (memberErr) {
    throw new Error(`owner role lookup failed: ${memberErr.code ?? "unknown"}`);
  }
  if (!memberRow) {
    throw new Error(
      `${label} is not the workspace owner (workspace_members role='owner')`,
    );
  }
  ownerValidationMemo.set(key, Date.now());
}

export async function resolveInboundRoute(
  sb: ServiceClient,
  recipients: string[],
  envOwnerId: string | undefined,
): Promise<ResolvedRoute> {
  if (recipients.length > 0) {
    const { data, error } = await sb
      .from("email_inbox_routes")
      .select("address, workspace_id, owner_user_id")
      .in("address", recipients);
    if (error) {
      // Code only — never row values (TR3).
      throw new Error(`route lookup failed: ${error.code ?? "unknown"}`);
    }
    const rows = (data as RouteRow[] | null) ?? [];
    if (rows.length > 1) {
      throw new Error(`ambiguous inbound route: ${rows.length} routes match`);
    }
    if (rows.length === 1) {
      const row = rows[0];
      await assertWorkspaceOwner(sb, row.workspace_id, row.owner_user_id, "table");
      return {
        workspaceId: row.workspace_id,
        ownerId: row.owner_user_id,
        source: "table",
      };
    }
  }

  if (!envOwnerId) {
    // Retriable by design — NEVER skip, NEVER NonRetriableError: a missing
    // owner env is ops misconfiguration; Inngest redelivery means no email
    // is dropped while it is fixed, and Layer 1 captures on exhaustion.
    throw new Error(
      "EMAIL_TRIAGE_OWNER_USER_ID is unset — cannot claim inbound email",
    );
  }
  await assertWorkspaceOwner(sb, envOwnerId, envOwnerId, "env-fallback");
  return { workspaceId: envOwnerId, ownerId: envOwnerId, source: "env-fallback" };
}
