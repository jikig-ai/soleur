import { createServiceClient } from "@/lib/supabase/service";
import {
  abortAllWorkspaceMemberSessions,
} from "@/server/agent-session-registry";
import { sessions } from "@/server/session-registry";
import { closeWithPreamble } from "@/lib/ws-close-helper";
import { WS_CLOSE_CODES } from "@/lib/types";
import { reportSilentFallback } from "@/server/observability";

// PERMANENT service-role surface (.service-role-allowlist line 133):
// invite_workspace_member + remove_workspace_member RPCs require service-role
// to write WORM `workspace_member_attestations` rows. The RPCs themselves
// enforce caller-is-owner via `auth.uid()` checks inside the SECURITY DEFINER
// body, so the service-role lift is purely to bypass the WORM table's
// "no INSERT for authenticated" policy. The pattern mirrors `scope_grants`
// (migration 048).

export interface InviteWorkspaceMemberArgs {
  callerUserId: string;
  workspaceId: string;
  invitee: { userId?: string; email?: string };
  role: "owner" | "member";
  attestationText: string;
  /** Forwarded into workspace_member_attestations.ip_hash; opaque to this layer. */
  ipHash?: string;
  /** Forwarded into workspace_member_attestations.user_agent. */
  userAgent?: string;
}

export type InviteResult =
  | { ok: true; attestationId: string }
  | { ok: false; reason: InviteFailureReason; detail?: string };

export type InviteFailureReason =
  | "invitee_not_found"
  | "invitee_already_member"
  | "caller_not_owner"
  | "rpc_failed";

interface UserLookupRow {
  id: string;
  email: string | null;
}

/**
 * Resolve an invitee identifier (email or user_id) to a Soleur auth.users.id.
 * Email lookup goes through the `users` mirror table (RLS bypassed by service
 * role) — auth.users is not directly queryable via PostgREST.
 *
 * Returns null when no match exists. The plan's UX surface for "user must
 * already exist" lives at this gate (wireframe 03 caption).
 */
async function resolveInviteeUserId(identifier: {
  userId?: string;
  email?: string;
}): Promise<string | null> {
  const service = createServiceClient();
  if (identifier.userId) {
    const result = (await service
      .from("users")
      .select("id, email")
      .eq("id", identifier.userId)
      .limit(1)) as { data: UserLookupRow[] | null; error: unknown };
    if (result.error) return null;
    return result.data?.[0]?.id ?? null;
  }
  if (identifier.email) {
    const result = (await service
      .from("users")
      .select("id, email")
      .eq("email", identifier.email.toLowerCase())
      .limit(1)) as { data: UserLookupRow[] | null; error: unknown };
    if (result.error) return null;
    return result.data?.[0]?.id ?? null;
  }
  return null;
}

export async function inviteWorkspaceMember(
  args: InviteWorkspaceMemberArgs,
): Promise<InviteResult> {
  const inviteeUserId = await resolveInviteeUserId(args.invitee);
  if (!inviteeUserId) {
    return { ok: false, reason: "invitee_not_found" };
  }

  const service = createServiceClient();
  // Note: invite_workspace_member RPC enforces caller-is-owner via auth.uid().
  // Service-role calls do NOT set auth.uid(), so we pass the caller explicitly
  // and the RPC checks `caller_id IS NULL OR caller_id = ...`. Migration 054
  // §1.2.6 defines the RPC's signature; the SECURITY DEFINER body re-reads
  // the caller's owner row in workspace_members before the WORM write.
  const { data, error } = await service.rpc("invite_workspace_member", {
    p_workspace_id: args.workspaceId,
    p_invitee_user_id: inviteeUserId,
    p_attestation_text: args.attestationText,
  });

  if (error) {
    const msg = error.message ?? "";
    if (msg.includes("already a member")) {
      return { ok: false, reason: "invitee_already_member" };
    }
    if (msg.includes("not workspace owner") || msg.includes("not owner")) {
      return { ok: false, reason: "caller_not_owner" };
    }
    return { ok: false, reason: "rpc_failed", detail: msg };
  }

  return { ok: true, attestationId: String(data) };
}

export interface RemoveWorkspaceMemberArgs {
  callerUserId: string;
  workspaceId: string;
  inviteeUserId: string;
  /** For the WS close preamble + terminal screen UX. */
  organizationName?: string | null;
}

export type RemoveResult =
  | { ok: true }
  | { ok: false; reason: RemoveFailureReason; detail?: string };

export type RemoveFailureReason =
  | "owner_cannot_remove_self"
  | "not_a_member"
  | "caller_not_owner"
  | "rpc_failed";

export interface UpdateWorkspaceMemberRoleArgs {
  callerUserId: string;
  workspaceId: string;
  targetUserId: string;
  newRole: "owner" | "member";
}

export type UpdateRoleResult =
  | { ok: true }
  | { ok: false; reason: UpdateRoleFailureReason; detail?: string };

export type UpdateRoleFailureReason =
  | "invalid_role"
  | "caller_not_owner"
  | "not_a_member"
  | "rpc_failed";

/**
 * Change a workspace member's role (owner ↔ member) + cascade the
 * revocation surface (#4307 plan §3.1).
 *
 * Mirrors `removeWorkspaceMember` shape:
 *   1. SQL RPC `update_workspace_member_role` (mig 064) — atomic role
 *      change + revocation INSERT + user_session_state clear + actor GUC.
 *   2. `abortAllWorkspaceMemberSessions` — local-process SIGTERM for
 *      any in-flight agent session the user has bound to this workspace.
 *   3. WS close with `MEMBERSHIP_REVOKED` (4012) preamble. Cut C6: the
 *      preamble's `reason` field is NOT added in PR-1; the in-flight
 *      terminal screen renders identical copy for "removed" and
 *      "role-changed" (acceptable per plan §"Risks" #7). Tracked at
 *      AC20-2 follow-up.
 */
export async function updateWorkspaceMemberRole(
  args: UpdateWorkspaceMemberRoleArgs,
): Promise<UpdateRoleResult> {
  if (args.newRole !== "owner" && args.newRole !== "member") {
    return { ok: false, reason: "invalid_role" };
  }

  const service = createServiceClient();
  const { error } = await service.rpc("update_workspace_member_role", {
    p_workspace_id: args.workspaceId,
    p_user_id: args.targetUserId,
    p_new_role: args.newRole,
  });
  if (error) {
    const msg = error.message ?? "";
    if (msg.includes("caller is not an owner")) {
      return { ok: false, reason: "caller_not_owner" };
    }
    if (msg.includes("no workspace_members row")) {
      return { ok: false, reason: "not_a_member" };
    }
    if (msg.includes("invalid role")) {
      return { ok: false, reason: "invalid_role" };
    }
    return { ok: false, reason: "rpc_failed", detail: msg };
  }

  try {
    abortAllWorkspaceMemberSessions(args.workspaceId, args.targetUserId);
  } catch (abortErr) {
    reportSilentFallback(abortErr, {
      feature: "workspace-membership",
      op: "abort-role-changed-member-sessions",
      extra: { workspaceId: args.workspaceId, targetUserId: args.targetUserId },
    });
  }

  // WS close fan-out — mirrors removeWorkspaceMember at lines 187-192.
  // No `reason` field on the preamble (cut C6 — deferred to AC20-2).
  try {
    const session = sessions.get(args.targetUserId);
    if (session) {
      closeWithPreamble(session.ws, WS_CLOSE_CODES.MEMBERSHIP_REVOKED, {
        type: "membership_revoked",
        organizationName: null,
        workspaceId: args.workspaceId,
      });
    }
  } catch (closeErr) {
    reportSilentFallback(closeErr, {
      feature: "workspace-membership",
      op: "close-role-changed-member-socket",
      extra: { workspaceId: args.workspaceId, targetUserId: args.targetUserId },
    });
  }

  return { ok: true };
}

/**
 * Remove a member from a workspace + cascade the SIGTERM hook (AC-FLOW2).
 *
 * Order:
 *  1. SQL RPC `remove_workspace_member` — atomic delete of workspace_members
 *     row + RAISE on AC-FLOW4 (owner cannot remove self).
 *  2. `abortAllWorkspaceMemberSessions` — local-process agent SIGTERM.
 *  3. WS close with `MEMBERSHIP_REVOKED` preamble — drives the terminal
 *     screen on the removed user's client.
 *
 * If step 1 fails, steps 2 and 3 do not run. Steps 2 and 3 are best-effort
 * (the user may not be connected to this process — the SQL RPC + RLS reload
 * are the source-of-truth; sibling process WS connections will pick up the
 * revocation on their next is_workspace_member check, which fires every
 * RLS-bound query).
 */
export async function removeWorkspaceMember(
  args: RemoveWorkspaceMemberArgs,
): Promise<RemoveResult> {
  // AC-FLOW4 short-circuit before hitting the DB.
  if (args.callerUserId === args.inviteeUserId) {
    return { ok: false, reason: "owner_cannot_remove_self" };
  }

  const service = createServiceClient();
  const { error } = await service.rpc("remove_workspace_member", {
    p_workspace_id: args.workspaceId,
    p_user_id: args.inviteeUserId,
  });
  if (error) {
    const msg = error.message ?? "";
    if (msg.includes("owner cannot remove self")) {
      return { ok: false, reason: "owner_cannot_remove_self" };
    }
    if (msg.includes("not workspace owner") || msg.includes("caller is not")) {
      return { ok: false, reason: "caller_not_owner" };
    }
    if (msg.includes("not a member")) {
      return { ok: false, reason: "not_a_member" };
    }
    return { ok: false, reason: "rpc_failed", detail: msg };
  }

  // SIGTERM in-flight sessions for the removed user IF their currently-bound
  // workspace matches. Kieran C5: this is safe because the registry only
  // fires when userWorkspaces.get(removedUserId) === workspaceId.
  try {
    abortAllWorkspaceMemberSessions(args.workspaceId, args.inviteeUserId);
  } catch (abortErr) {
    reportSilentFallback(abortErr, {
      feature: "workspace-membership",
      op: "abort-removed-member-sessions",
      extra: { workspaceId: args.workspaceId, inviteeUserId: args.inviteeUserId },
    });
  }

  // Close the user's WS with MEMBERSHIP_REVOKED preamble. Best-effort — no
  // close happens if the user isn't connected to this process.
  try {
    const session = sessions.get(args.inviteeUserId);
    if (session) {
      closeWithPreamble(session.ws, WS_CLOSE_CODES.MEMBERSHIP_REVOKED, {
        type: "membership_revoked",
        organizationName: args.organizationName ?? null,
        workspaceId: args.workspaceId,
      });
    }
  } catch (closeErr) {
    reportSilentFallback(closeErr, {
      feature: "workspace-membership",
      op: "close-removed-member-socket",
      extra: { workspaceId: args.workspaceId, inviteeUserId: args.inviteeUserId },
    });
  }

  return { ok: true };
}
