import { randomBytes, createHash } from "node:crypto";
import { createServiceClient } from "@/lib/supabase/service";
import { createChildLogger } from "@/server/logger";
import { reportSilentFallback } from "@/server/observability";

const log = createChildLogger("workspace-invitations");

const INVITE_EXPIRY_DAYS = 7;

export function generateInviteToken(): string {
  return randomBytes(32).toString("base64url");
}

export function hashToken(token: string): string {
  return createHash("sha256").update(token).digest("hex");
}

export interface InvitationDetails {
  ok: true;
  invitation_id: string;
  workspace_id: string;
  workspace_name: string;
  inviter_name: string;
  invitee_email: string;
  role: string;
  expires_at: string;
}

export type LookupResult =
  | InvitationDetails
  | { ok: false; reason: string };

export async function lookupInvitationByToken(
  tokenHash: string,
): Promise<LookupResult> {
  const service = createServiceClient();
  const { data, error } = await service.rpc("lookup_invitation_by_token", {
    p_token_hash: tokenHash,
  });

  if (error) {
    log.error({ err: error.message }, "lookup_invitation_by_token RPC failed");
    return { ok: false, reason: "rpc_failed" };
  }

  return data as LookupResult;
}

export interface PendingInvite {
  id: string;
  workspace_id: string;
  workspace_name: string;
  inviter_name: string;
  role: string;
  expires_at: string;
  created_at: string;
}

export async function getPendingInvitesForUser(
  userId: string,
  email: string,
): Promise<PendingInvite[]> {
  const service = createServiceClient();
  const now = new Date().toISOString();
  const selectFields = `
    id,
    workspace_id,
    role,
    expires_at,
    created_at,
    workspaces!inner(name),
    inviter:users!workspace_invitations_inviter_user_id_fkey(
      email,
      raw_user_meta_data
    )
  `;

  const [byUserId, byEmail] = await Promise.all([
    service
      .from("workspace_invitations")
      .select(selectFields)
      .eq("invitee_user_id", userId)
      .is("accepted_at", null)
      .is("declined_at", null)
      .is("revoked_at", null)
      .gt("expires_at", now),
    service
      .from("workspace_invitations")
      .select(selectFields)
      .eq("invitee_email", email.toLowerCase())
      .is("accepted_at", null)
      .is("declined_at", null)
      .is("revoked_at", null)
      .gt("expires_at", now),
  ]);

  if (byUserId.error) {
    log.error({ err: byUserId.error.message }, "Failed to query pending invites by userId");
    reportSilentFallback(null, {
      feature: "workspace-invitations",
      op: "get-pending-by-userid",
      message: `Failed to query pending invites: ${byUserId.error.message}`,
    });
  }
  if (byEmail.error) {
    log.error({ err: byEmail.error.message }, "Failed to query pending invites by email");
    reportSilentFallback(null, {
      feature: "workspace-invitations",
      op: "get-pending-by-email",
      message: `Failed to query pending invites: ${byEmail.error.message}`,
    });
  }

  const allRows = [...(byUserId.data ?? []), ...(byEmail.data ?? [])];
  const seen = new Set<string>();

  return allRows
    .filter((row: Record<string, unknown>) => {
      const id = row.id as string;
      if (seen.has(id)) return false;
      seen.add(id);
      return true;
    })
    .map((row: Record<string, unknown>) => {
      const workspace = row.workspaces as { name: string } | null;
      const inviter = row.inviter as {
        email: string | null;
        raw_user_meta_data: { full_name?: string } | null;
      } | null;

      return {
        id: row.id as string,
        workspace_id: row.workspace_id as string,
        workspace_name: workspace?.name ?? "Workspace",
        inviter_name:
          inviter?.raw_user_meta_data?.full_name ?? inviter?.email ?? "A team member",
        role: row.role as string,
        expires_at: row.expires_at as string,
        created_at: row.created_at as string,
      };
    });
}

export interface CreateInvitationArgs {
  callerUserId: string;
  workspaceId: string;
  inviteeEmail: string;
  role: "owner" | "member";
  attestationText: string;
}

export type CreateInvitationResult =
  | { ok: true; invitationId: string; attestationId: string; token: string }
  | { ok: false; reason: string };

export async function createWorkspaceInvitation(
  args: CreateInvitationArgs,
): Promise<CreateInvitationResult> {
  const token = generateInviteToken();
  const tokenHash = hashToken(token);

  const service = createServiceClient();
  const { data, error } = await service.rpc("create_workspace_invitation", {
    p_workspace_id: args.workspaceId,
    p_invitee_email: args.inviteeEmail,
    p_role: args.role,
    p_token_hash: tokenHash,
    p_attestation_text: args.attestationText,
    p_caller_user_id: args.callerUserId,
  });

  if (error) {
    const msg = error.message ?? "";
    if (msg.includes("caller_not_owner")) {
      return { ok: false, reason: "caller_not_owner" };
    }
    if (msg.includes("invitee_already_member")) {
      return { ok: false, reason: "invitee_already_member" };
    }
    if (msg.includes("duplicate_pending_invite")) {
      return { ok: false, reason: "duplicate_pending_invite" };
    }
    log.error({ err: msg }, "create_workspace_invitation RPC failed");
    return { ok: false, reason: "rpc_failed" };
  }

  const result = data as { ok: boolean; invitation_id: string; attestation_id: string };

  return {
    ok: true,
    invitationId: result.invitation_id,
    attestationId: result.attestation_id,
    token,
  };
}

export type AcceptInvitationResult =
  | { ok: true; workspaceId: string; attestationId: string }
  | { ok: false; reason: string };

export async function acceptWorkspaceInvitation(
  invitationId: string,
  accepterUserId: string,
): Promise<AcceptInvitationResult> {
  const service = createServiceClient();
  const { data, error } = await service.rpc("accept_workspace_invitation", {
    p_invitation_id: invitationId,
    p_accepter_user_id: accepterUserId,
  });

  if (error) {
    log.error({ err: error.message }, "accept_workspace_invitation RPC failed");
    return { ok: false, reason: "rpc_failed" };
  }

  const result = data as { ok: boolean; reason?: string; workspace_id?: string; attestation_id?: string };
  if (!result.ok) {
    return { ok: false, reason: result.reason ?? "unknown" };
  }

  return {
    ok: true,
    workspaceId: result.workspace_id!,
    attestationId: result.attestation_id!,
  };
}

export type DeclineInvitationResult =
  | { ok: true }
  | { ok: false; reason: string };

export async function declineWorkspaceInvitation(
  invitationId: string,
  declinerUserId: string,
): Promise<DeclineInvitationResult> {
  const service = createServiceClient();
  const { data, error } = await service.rpc("decline_workspace_invitation", {
    p_invitation_id: invitationId,
    p_decliner_user_id: declinerUserId,
  });

  if (error) {
    log.error({ err: error.message }, "decline_workspace_invitation RPC failed");
    return { ok: false, reason: "rpc_failed" };
  }

  const result = data as { ok: boolean; reason?: string };
  if (!result.ok) {
    return { ok: false, reason: result.reason ?? "unknown" };
  }

  return { ok: true };
}

export type RevokeInvitationResult =
  | { ok: true }
  | { ok: false; reason: string };

/**
 * Owner-side cancellation of a pending invite (feat-cancel-pending-invite,
 * #4634). Soft revoke via the revoke_workspace_invitation RPC; the RPC
 * re-checks the caller is a workspace owner (defense-in-depth alongside the
 * route owner-check). Mirrors declineWorkspaceInvitation.
 */
export async function revokeWorkspaceInvitation(
  invitationId: string,
  callerUserId: string,
): Promise<RevokeInvitationResult> {
  const service = createServiceClient();
  const { data, error } = await service.rpc("revoke_workspace_invitation", {
    p_invitation_id: invitationId,
    p_caller_user_id: callerUserId,
  });

  if (error) {
    log.error({ err: error.message }, "revoke_workspace_invitation RPC failed");
    reportSilentFallback(null, {
      feature: "workspace-invitations",
      op: "revoke",
      message: `revoke_workspace_invitation RPC failed: ${error.message}`,
    });
    return { ok: false, reason: "rpc_failed" };
  }

  const result = data as { ok: boolean; reason?: string };
  if (!result.ok) {
    return { ok: false, reason: result.reason ?? "unknown" };
  }

  return { ok: true };
}
