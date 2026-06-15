import type { SupabaseClient } from "@supabase/supabase-js";
import { createServiceClient } from "@/lib/supabase/service";
import { abortAllUserSessions } from "@/server/agent-runner";
import { deleteWorkspace, purgeWorkspaceLogoObjects } from "@/server/workspace";
import { createChildLogger } from "./logger";
import { hashUserId, reportSilentFallback, warnSilentFallback } from "@/server/observability";

const log = createChildLogger("account-delete");

const PAGE_SIZE = 1_000;
const MAX_PAGES = 100; // Safety bound: 100k objects per folder

/**
 * List all object names in a Storage folder, paginating through all pages.
 * Supabase Storage uses offset-based pagination.
 */
async function listAllStorageObjects(
  storage: SupabaseClient["storage"],
  bucket: string,
  folder: string,
): Promise<string[]> {
  const names: string[] = [];
  let offset = 0;

  for (let page = 0; page < MAX_PAGES; page++) {
    const { data } = await storage
      .from(bucket)
      .list(folder, { limit: PAGE_SIZE, offset });

    if (!data || data.length === 0) break;

    names.push(...data.map((obj) => obj.name));

    if (data.length < PAGE_SIZE) break;
    offset += PAGE_SIZE;
  }

  return names;
}

export interface DeleteAccountResult {
  success: boolean;
  error?: string;
}

/**
 * Deletes a user account with full cascade per plan rev-2 AC25.
 *
 * Cascade order is load-bearing:
 *   1. abort-dsar-jobs  — UPDATE in-flight DSAR exports to status='failed'.
 *                         MUST come first: an in-flight worker reading
 *                         against a tombstoned user_id would fire
 *                         assertReadScope cross-tenant P0 against itself.
 *   2. abort            — abort any active agent session.
 *   3. workspace        — delete workspace directory.
 *   4. storage-purge    — purge chat-attachments/<userId>/ AND
 *                         dsar-exports/<userId>/ Storage blobs.
 *   5. anonymise-dsar-audit — anonymise_dsar_export_audit_pii RPC.
 *                             MUST come before auth-delete so the
 *                             WORM-trigger GUC is available before
 *                             the auth row vanishes.
 *   5.5 anonymise-tc-acceptances — anonymise_tc_acceptances RPC (migration 044).
 *                             MUST come before auth-delete: tc_acceptances.user_id
 *                             has ON DELETE RESTRICT, so the auth cascade to
 *                             public.users would abort without prior anonymisation.
 *   5.6 anonymise-workspace-attestations — anonymise_workspace_member_attestations
 *                             RPC (migration 058). FK-reverse: attestations
 *                             reference users via inviter_user_id +
 *                             invitee_user_id (RESTRICT).
 *   5.7 anonymise-workspace-members — anonymise_workspace_members RPC
 *                             (migration 058). DELETEs membership rows
 *                             (workspace_id RESTRICT to workspaces).
 *   5.8 anonymise-organization-membership — anonymise_organization_membership
 *                             RPC (migration 058). Orphan-cleanup or reassign-
 *                             owner; breaks the RESTRICT FK to public.users.
 *   5.9 anonymise-workspace-member-actions — anonymise_workspace_member_actions
 *                             RPC (migration 063, #4231). NULL-sets actor_user_id
 *                             + target_user_id on the audit log; lineage
 *                             (workspace_id, action_type, role, created_at,
 *                             attestation_id) preserved. Cascade DELETEs from
 *                             3.91 do NOT create new audit rows because
 *                             anonymise_workspace_members SET LOCAL
 *                             session_replication_role='replica' suppresses
 *                             the AFTER trigger — this step only anonymises
 *                             rows from prior legitimate invite/remove RPC calls.
 *   5.10 anonymise-byok-delegations — anonymise_byok_delegations RPC
 *                             (migration 064, BYOK Delegations PR-A #4232).
 *                             Active rows take WORM Shape 1 (revoke flip with
 *                             reason='art_17_anonymise'), then WORM Shape 2
 *                             nulls identity + workspace + actor cols in a
 *                             single txn. Required: byok_delegations.{grantor,
 *                             grantee,created_by,revoked_by,cap_updated_by}
 *                             all REFERENCES users(id) ON DELETE RESTRICT —
 *                             without this step the auth-delete cascade
 *                             would abort.
 *   5.11 anonymise-byok-delegation-acceptances —
 *                             anonymise_byok_delegation_acceptances RPC
 *                             (migration 074, BYOK Delegations PR-B #4232).
 *                             Nulls user_id + ip_hash + user_agent on the
 *                             consent ledger. Required: acceptances.user_id
 *                             REFERENCES users(id) ON DELETE RESTRICT.
 *   5.12 anonymise-byok-delegation-withdrawals —
 *                             anonymise_byok_delegation_withdrawals RPC
 *                             (migration 084, #4625). Nulls user_id +
 *                             ip_hash + user_agent on the consent-withdrawal
 *                             ledger. Required: withdrawals.user_id
 *                             REFERENCES users(id) ON DELETE RESTRICT.
 *   5.13 anonymise-email-triage-items —
 *                             anonymise_email_triage_items RPC (migration
 *                             102, #5103). Nulls user_id + sender under the
 *                             GUC-gated WORM bypass; statutory rows retained
 *                             anonymised per Art. 17(3)(b). Required:
 *                             email_triage_items.user_id REFERENCES
 *                             users(id) ON DELETE RESTRICT.
 *   5.14 anonymise-routine-runs —
 *                             anonymise_routine_runs RPC (migration 107,
 *                             #5345 / #5372). Nulls actor_id +
 *                             delegating_principal under the GUC-gated WORM
 *                             bypass (app.worm_bypass); the append-only run-log
 *                             row is retained anonymised. Required:
 *                             routine_runs.actor_id / .delegating_principal
 *                             REFERENCE users(id) ON DELETE RESTRICT.
 *   6. auth             — auth.admin.deleteUser(); FK cascade handles
 *                         public.users and all children atomically.
 *
 * Recoverability invariant: anonymise-dsar-audit and anonymise-tc-acceptances
 * are both idempotent. If a later step fails, re-running this cascade is safe.
 *
 * GDPR Article 17 — Right to Erasure
 */
export async function deleteAccount(
  userId: string,
  confirmEmail: string,
): Promise<DeleteAccountResult> {
  const service = createServiceClient();

  // 1. Verify user exists and email matches
  const { data, error: getUserError } = await service.auth.admin.getUserById(userId);

  if (getUserError || !data?.user) {
    log.warn({ userId, err: getUserError }, "User not found during deletion");
    return { success: false, error: "User not found" };
  }

  if (data.user.email !== confirmEmail) {
    return { success: false, error: "Email does not match. Please type your exact email to confirm." };
  }

  // 1.5 Abort in-flight DSAR export jobs FIRST per plan rev-2 AC25.
  // An in-flight worker reading against a soon-to-be-tombstoned user_id
  // would fire assertReadScope cross-tenant P0 against itself; flip
  // status before the auth row vanishes so the next poller tick sees
  // a terminal-state job and skips.
  try {
    const { error: abortDsarErr } = await service
      .from("dsar_export_jobs")
      .update({
        status: "failed",
        failure_reason: "account_deleted_during_export",
        completed_at: new Date().toISOString(),
      })
      .eq("user_id", userId)
      .in("status", ["pending", "running"]);
    if (abortDsarErr) {
      log.warn(
        { userId, err: abortDsarErr },
        "Failed to abort in-flight DSAR jobs (non-fatal)",
      );
    }
  } catch (err) {
    log.warn(
      { userId, err },
      "abort-dsar-jobs threw during deletion (non-fatal)",
    );
  }

  // 2. Abort active session (best-effort — session may not exist)
  try {
    abortAllUserSessions(userId);
  } catch (err) {
    log.warn({ userId, err }, "Failed to abort session during deletion (non-fatal)");
  }

  // 3. Delete workspace directory.
  //
  // The deleted user is, by the GDPR Art. 17 contract, the sole member of
  // their own workspace at this point (Phase 7 anonymise_workspace_members
  // strips any team memberships earlier in the cascade). `userId` ===
  // `workspaces.id` per migration 053 §1.1.7 N2 invariant.
  try {
    await deleteWorkspace(userId);
  } catch (err) {
    log.warn({ userId, err }, "Failed to delete workspace during deletion (non-fatal)");
  }

  // 3.6 Purge the workspace logo Storage object (#4916). Sole-owned teardown
  // only — `userId === workspaces.id` per the N2 invariant (mig 053), so the
  // deterministic key is `<userId>/logo.webp`. Shared-workspace member removal
  // does NOT purge (it's a shared asset). Best-effort; reports, never throws.
  try {
    await purgeWorkspaceLogoObjects(userId, service);
  } catch (err) {
    log.warn({ userId, err }, "Failed to purge workspace logo during deletion (non-fatal)");
  }

  // 3.5 Purge Storage blobs for all user attachments AND DSAR export
  // bundles (DB rows are FK-cascaded, but Storage objects are not).
  // Plan rev-2 AC25 extends the storage-purge step to cover
  // dsar-exports/<userId>/ so a half-completed export bundle does not
  // outlive the user account.
  //
  // NOTE (mig 068 #4318): a more surgical owned-conv-only purge using
  // message_attachments ⨝ conversations.user_id was considered (would
  // preserve the user's uploads in shared-workspace conversations under
  // an Art. 17 controller's-legitimate-interest carve-out, with uploader
  // identity already nulled by step 3.901). Deferred to a follow-up
  // because the wide-purge regression tests at test/account-delete.test.ts
  // would need a substantial rewrite. Today: bytes AND identity both
  // wiped on full account-delete; co-members see broken thumbnails for
  // departed-user files in shared convs. Acceptable Art. 17 compliance;
  // the carve-out is a UX optimization to revisit when the flag flips.
  try {
    const folders = await listAllStorageObjects(service.storage, "chat-attachments", userId);

    if (folders.length > 0) {
      const allPaths: string[] = [];
      for (const folderName of folders) {
        const files = await listAllStorageObjects(
          service.storage,
          "chat-attachments",
          `${userId}/${folderName}`,
        );
        allPaths.push(...files.map((f) => `${userId}/${folderName}/${f}`));
      }
      if (allPaths.length > 0) {
        await service.storage.from("chat-attachments").remove(allPaths);
      }
    }
  } catch (err) {
    log.warn({ userId, err }, "Failed to purge attachment blobs during deletion (non-fatal)");
  }

  try {
    const dsarFiles = await listAllStorageObjects(
      service.storage,
      "dsar-exports",
      userId,
    );
    if (dsarFiles.length > 0) {
      const paths = dsarFiles.map((f) => `${userId}/${f}`);
      await service.storage.from("dsar-exports").remove(paths);
    }
  } catch (err) {
    log.warn(
      { userId, err },
      "Failed to purge dsar-exports blobs during deletion (non-fatal)",
    );
  }

  // 3.75 Anonymise dsar_export_audit_pii rows for this user BEFORE
  // auth-delete per plan rev-2 AC25. The RPC is SECURITY DEFINER + the
  // ONLY SET-site for app.dsar_audit_anonymise_in_progress (WORM
  // bypass gate per AC29); the auth row must still exist when the
  // function fires so the FK relationship is in place. Idempotent —
  // re-running on already-anonymised rows is a no-op.
  try {
    const { error: anonErr } = await service.rpc(
      "anonymise_dsar_export_audit_pii",
      { p_user_id: userId },
    );
    if (anonErr) {
      log.warn(
        { userId, err: anonErr },
        "anonymise_dsar_export_audit_pii failed (non-fatal but flagged)",
      );
    }
  } catch (err) {
    log.warn(
      { userId, err },
      "anonymise-dsar-audit threw during deletion (non-fatal)",
    );
  }

  // 3.82 Anonymise action_sends rows for this user BEFORE anonymise_scope_grants
  //      (migration 052, PR-H #4077). FK action_sends.user_id → users.id is ON
  //      DELETE RESTRICT, AND action_sends.grant_id → scope_grants.id is also
  //      RESTRICT — so anonymise_action_sends MUST land BEFORE anonymise_scope_grants
  //      (which we keep below) and BEFORE auth.admin.deleteUser. The RPC bypasses
  //      the action_sends WORM trigger via SET LOCAL session_replication_role.
  //      Failure here is FATAL on the same reasoning as 3.85: skipping it
  //      guarantees auth-delete fails, leaving a half-deleted user (GDPR Art. 17
  //      violation). Idempotent.
  try {
    const { error: anonAsErr } = await service.rpc(
      "anonymise_action_sends",
      { p_user_id: userId },
    );
    if (anonAsErr) {
      reportSilentFallback(anonAsErr, {
        feature: "account-delete",
        op: "anonymise-action-sends",
        extra: { userId },
        message: "anonymise_action_sends failed — aborting deletion to avoid FK-block",
      });
      return { success: false, error: "Account deletion failed at anonymise-action-sends. Please try again." };
    }
  } catch (err) {
    reportSilentFallback(err, {
      feature: "account-delete",
      op: "anonymise-action-sends",
      extra: { userId },
      message: "anonymise_action_sends threw — aborting deletion to avoid FK-block",
    });
    return { success: false, error: "Account deletion failed at anonymise-action-sends. Please try again." };
  }

  // 3.83 Anonymise template_authorizations rows for this user BETWEEN
  //      anonymise_action_sends and anonymise_scope_grants (migration 053,
  //      PR-I #4078). SEMANTIC ordering, NOT FK-driven: anonymise_* is
  //      UPDATE, so scope_grants FK ON DELETE RESTRICT does not fire. The
  //      required invariant is that `dsr_erasure` reason MUST be set on
  //      child rows BEFORE the parent scope_grant's user_id is nulled —
  //      otherwise Art. 5(2) audit-trail attribution breaks. SECURITY
  //      DEFINER RPC, idempotent (UPDATE … WHERE founder_id = p_user_id
  //      is a no-op on already-anonymised rows; COALESCE preserves any
  //      prior revocation_reason). Failure here is FATAL on the same
  //      reasoning as 3.85.
  try {
    const { error: anonTaErr } = await service.rpc(
      "anonymise_template_authorizations",
      { p_user_id: userId },
    );
    if (anonTaErr) {
      reportSilentFallback(anonTaErr, {
        feature: "account-delete",
        op: "anonymise-template-authorizations",
        extra: { userId },
        message: "anonymise_template_authorizations failed — aborting deletion to avoid Art. 5(2) attribution break",
      });
      return {
        success: false,
        error: "Account deletion failed at anonymise-template-authorizations. Please try again.",
      };
    }
  } catch (err) {
    reportSilentFallback(err, {
      feature: "account-delete",
      op: "anonymise-template-authorizations",
      extra: { userId },
      message: "anonymise_template_authorizations threw — aborting deletion to avoid Art. 5(2) attribution break",
    });
    return {
      success: false,
      error: "Account deletion failed at anonymise-template-authorizations. Please try again.",
    };
  }

  // 3.84 Anonymise scope_grants rows for this user BEFORE the tc_acceptances
  //      cascade (migration 048, PR-G #3947). FK is ON DELETE RESTRICT — the
  //      auth.admin.deleteUser call would abort without this. Runs BEFORE
  //      anonymise_tc_acceptances so the cascade sequence matches FK order;
  //      both target public.users(id). Failure here is FATAL on the same
  //      reasoning as 3.85. SECURITY DEFINER RPC, idempotent (UPDATE …
  //      WHERE founder_id = p_user_id is a no-op on already-anonymised rows).
  try {
    const { error: anonSgErr } = await service.rpc(
      "anonymise_scope_grants",
      { p_user_id: userId },
    );
    if (anonSgErr) {
      reportSilentFallback(anonSgErr, {
        feature: "account-delete",
        op: "anonymise-scope-grants",
        extra: { userId },
        message: "anonymise_scope_grants failed — aborting deletion to avoid FK-block",
      });
      return { success: false, error: "Account deletion failed at anonymise-scope-grants. Please try again." };
    }
  } catch (err) {
    reportSilentFallback(err, {
      feature: "account-delete",
      op: "anonymise-scope-grants",
      extra: { userId },
      message: "anonymise_scope_grants threw — aborting deletion to avoid FK-block",
    });
    return { success: false, error: "Account deletion failed at anonymise-scope-grants. Please try again." };
  }

  // 3.85 Anonymise tc_acceptances rows for this user BEFORE auth-delete
  //      (migration 044). FK is ON DELETE RESTRICT — the cascade from
  //      auth.users → public.users would abort without this. Failure here
  //      is FATAL: skipping it guarantees the auth-delete fails too, leaving
  //      a half-deleted user (GDPR Art. 17 violation). SECURITY DEFINER RPC,
  //      idempotent (UPDATE … WHERE user_id IS NOT NULL).
  try {
    const { error: anonTcErr } = await service.rpc(
      "anonymise_tc_acceptances",
      { p_user_id: userId },
    );
    if (anonTcErr) {
      reportSilentFallback(anonTcErr, {
        feature: "account-delete",
        op: "anonymise-tc-acceptances",
        extra: { userId },
        message: "anonymise_tc_acceptances failed — aborting deletion to avoid FK-block",
      });
      return { success: false, error: "Account deletion failed at anonymise-tc-acceptances. Please try again." };
    }
  } catch (err) {
    reportSilentFallback(err, {
      feature: "account-delete",
      op: "anonymise-tc-acceptances",
      extra: { userId },
      message: "anonymise_tc_acceptances threw — aborting deletion to avoid FK-block",
    });
    return { success: false, error: "Account deletion failed at anonymise-tc-acceptances. Please try again." };
  }

  // 3.86 Anonymise audit_github_token_use rows for this user BEFORE
  //      auth-delete (migration 052, PR-H #3244). The FK is ON DELETE
  //      SET NULL so the auth-delete cascade scrubs founder_id natively
  //      — this explicit call is defense-in-depth + symmetry with the
  //      043/044/048 anonymise RPCs above. Failure here is NON-FATAL
  //      (the SET-NULL cascade will run anyway during auth-delete).
  //      SECURITY DEFINER RPC, idempotent.
  try {
    const { error: anonGhErr } = await service.rpc(
      "anonymise_audit_github_token_use",
      { p_founder_id: userId },
    );
    if (anonGhErr) {
      warnSilentFallback(anonGhErr, {
        feature: "account-delete",
        op: "anonymise-audit-github-token-use",
        extra: { userId },
        message: "anonymise_audit_github_token_use failed — relying on ON DELETE SET NULL cascade (non-fatal)",
      });
    }
  } catch (err) {
    warnSilentFallback(err, {
      feature: "account-delete",
      op: "anonymise-audit-github-token-use",
      extra: { userId },
      message: "anonymise_audit_github_token_use threw — relying on ON DELETE SET NULL cascade (non-fatal)",
    });
  }

  // 3.90 Anonymise workspace_member_attestations BEFORE workspace_members
  //      (migration 058, feat-team-workspace-multi-user). FK-reverse
  //      order per Phase 7.4 AC-GDPR-17-CALLER:
  //        attestations → workspace_members → organizations → auth.users
  //      attestations.invitee_user_id + .inviter_user_id are both ON
  //      DELETE RESTRICT, so they MUST be NULLed before the auth-delete
  //      cascade reaches them. SECURITY DEFINER + idempotent.
  //      FATAL: skipping guarantees auth-delete fails on the RESTRICT FK,
  //      leaving a half-deleted user (GDPR Art. 17 violation).
  try {
    const { error: anonAttErr } = await service.rpc(
      "anonymise_workspace_member_attestations",
      { p_user_id: userId },
    );
    if (anonAttErr) {
      reportSilentFallback(anonAttErr, {
        feature: "account-delete",
        op: "anonymise-workspace-member-attestations",
        extra: { userId },
        message: "anonymise_workspace_member_attestations failed — aborting deletion",
      });
      return { success: false, error: "Account deletion failed at anonymise-workspace-member-attestations. Please try again." };
    }
  } catch (err) {
    reportSilentFallback(err, {
      feature: "account-delete",
      op: "anonymise-workspace-member-attestations",
      extra: { userId },
      message: "anonymise_workspace_member_attestations threw — aborting deletion",
    });
    return { success: false, error: "Account deletion failed at anonymise-workspace-member-attestations. Please try again." };
  }

  // 3.802 anonymise-workspace-invitations — anonymise_workspace_invitations
  //       RPC NULLs PII columns (inviter_user_id, invitee_email,
  //       invitee_user_id) for invitations where the departing user was
  //       either the inviter or the invitee. Migration 075.
  //       Graceful degradation: if the RPC doesn't exist yet (migration
  //       not applied), skip silently — the table has no rows to anonymise.
  try {
    const { error: anonInvErr } = await service.rpc(
      "anonymise_workspace_invitations",
      { p_user_id: userId },
    );
    if (anonInvErr) {
      const msg = anonInvErr.message ?? "";
      if (msg.includes("function") && msg.includes("does not exist")) {
        // Migration 075 not yet applied — table has no rows; skip.
      } else {
        reportSilentFallback(anonInvErr, {
          feature: "account-delete",
          op: "anonymise-workspace-invitations",
          message: "anonymise_workspace_invitations failed — aborting deletion",
        });
        return { success: false, error: "Account deletion failed at anonymise-workspace-invitations. Please try again." };
      }
    }
  } catch (err) {
    reportSilentFallback(err, {
      feature: "account-delete",
      op: "anonymise-workspace-invitations",
      message: "anonymise_workspace_invitations threw — aborting deletion",
    });
    return { success: false, error: "Account deletion failed at anonymise-workspace-invitations. Please try again." };
  }

  // 3.901 Cascade-pseudonymise messages.user_id on shared-workspace
  //       conversations the departing user authored attachments in
  //       (migration 068, #4318). Sets messages.user_id = NULL on
  //       authored-with-attachments rows in conversations the
  //       departing user does NOT own — preserves the message body
  //       for surviving co-members while severing PII linkage. Runs
  //       BEFORE 3.905 (workspace_member_removals anonymise) so the
  //       cascade RPC iterates workspaces while membership rows are
  //       still resolvable. Runs BEFORE 3.91 (workspace_members
  //       DELETE) so is_workspace_member predicates inside the RPC
  //       still return true. Phase 0 emergent finding E-1: pseudonym
  //       is NULL (not 'member_<hex>') because messages.user_id has
  //       an FK to auth.users(id) ON DELETE CASCADE.
  //
  //       Runtime ordering guard (architecture P1-3): if no
  //       workspace_members row exists for this user at invocation
  //       time, a sibling step already ran out-of-order and the
  //       cascade would silently skip. Sentry-warn but do not abort.
  try {
    const { count: memberCount, error: memberCountErr } = await service
      .from("workspace_members")
      .select("workspace_id", { count: "exact", head: true })
      .eq("user_id", userId);
    if (memberCountErr) {
      reportSilentFallback(memberCountErr, {
        feature: "account-delete",
        op: "anonymise-authored-messages-shared-workspaces",
        extra: { userId },
        message: "ordering-guard probe failed — proceeding to RPC",
      });
    } else if ((memberCount ?? 0) === 0) {
      // Cascade-order regression detector: a sibling step already
      // emptied workspace_members. The RPC will return 0 affected
      // rows; Sentry-warn at structured P1.
      reportSilentFallback(null, {
        feature: "account-delete",
        op: "anonymise-authored-messages-shared-workspaces",
        extra: { userId },
        message:
          "ordering-guard tripped: workspace_members empty before cascade — sibling step ran out of order",
      });
    }
    const { data: anonCount, error: anonErr } = await service.rpc(
      "anonymise_departed_user_across_workspaces",
      { p_departing_user: userId },
    );
    if (anonErr) {
      reportSilentFallback(anonErr, {
        feature: "account-delete",
        op: "anonymise-authored-messages-shared-workspaces",
        extra: { userId },
        message:
          "anonymise_departed_user_across_workspaces failed — aborting deletion",
      });
      return { success: false, error: "Account deletion failed at anonymise-authored-messages-shared-workspaces. Please try again." };
    }
    log.info(
      { userId, anonymisedMessageCount: anonCount ?? 0 },
      "anonymise_departed_user_across_workspaces completed",
    );
  } catch (err) {
    reportSilentFallback(err, {
      feature: "account-delete",
      op: "anonymise-authored-messages-shared-workspaces",
      extra: { userId },
      message:
        "anonymise_departed_user_across_workspaces threw — aborting deletion",
    });
    return { success: false, error: "Account deletion failed at anonymise-authored-messages-shared-workspaces. Please try again." };
  }

  // 3.9015 Purge Storage objects for co-member uploads in conversations
  //        owned by the departing user (#4444). The wide purge at step 3.5
  //        covers {departingUserId}/... but NOT {coMemberUserId}/{convId}/...
  //        paths. Non-fatal: identity linkage is already severed at 3.901;
  //        orphaned bytes are a resource leak, not a compliance violation.
  try {
    // visibility-sweep-audit: owner-scoped — deletion cascade is per-user
    const { data: ownedConvs } = await service
      .from("conversations")
      .select("id")
      .eq("user_id", userId);
    const ownedConvIds = (ownedConvs ?? []).map((r) => r.id).filter(Boolean);
    if (ownedConvIds.length > 0) {
      let coMemberMsgIds: string[] = [];
      for (let i = 0; i < ownedConvIds.length; i += 500) {
        const convBatch = ownedConvIds.slice(i, i + 500);
        const { data: coMemberMsgs } = await service
          .from("messages")
          .select("id")
          .in("conversation_id", convBatch)
          .neq("user_id", userId)
          .not("user_id", "is", null);
        coMemberMsgIds = coMemberMsgIds.concat(
          (coMemberMsgs ?? []).map((r) => r.id).filter(Boolean),
        );
      }
      if (coMemberMsgIds.length > 0) {
        let storagePaths: string[] = [];
        for (let i = 0; i < coMemberMsgIds.length; i += 500) {
          const msgBatch = coMemberMsgIds.slice(i, i + 500);
          const { data: attachRows } = await service
            .from("message_attachments")
            .select("storage_path")
            .in("message_id", msgBatch);
          storagePaths = storagePaths.concat(
            (attachRows ?? []).map((r) => r.storage_path).filter(Boolean),
          );
        }
        for (let i = 0; i < storagePaths.length; i += 1000) {
          const batch = storagePaths.slice(i, i + 1000);
          await service.storage.from("chat-attachments").remove(batch);
        }
      }
    }
  } catch (err) {
    reportSilentFallback(err, {
      feature: "account-delete",
      op: "purge-shared-conv-attachments",
      extra: { userId },
      message:
        "step 3.9015 co-member Storage purge failed (non-fatal — identity already severed at 3.901)",
    });
  }

  // 3.905 Anonymise workspace_member_removals (migration 063, #4230).
  //      NULLs removed_user_id + removed_by_user_id for every removal
  //      row where the deleted user appears on either side. Mirrors
  //      3.90's pattern: lineage (id, workspace_id, removed_at) is
  //      preserved (WORM); PII columns transition NOT NULL → NULL via
  //      the SECURITY DEFINER RPC. Both FK columns are ON DELETE
  //      RESTRICT — skipping this step would leave the auth-delete
  //      cascade unable to clear users(id), same failure mode as 3.90.
  //      Runs AFTER attestations to preserve the 058-cascade convention
  //      (each ledger anonymise step covers its own table's user-FK).
  try {
    const { error: anonRemErr } = await service.rpc(
      "anonymise_workspace_member_removals",
      { p_user_id: userId },
    );
    if (anonRemErr) {
      reportSilentFallback(anonRemErr, {
        feature: "account-delete",
        op: "anonymise-workspace-member-removals",
        extra: { userId },
        message: "anonymise_workspace_member_removals failed — aborting deletion",
      });
      return { success: false, error: "Account deletion failed at anonymise-workspace-member-removals. Please try again." };
    }
  } catch (err) {
    reportSilentFallback(err, {
      feature: "account-delete",
      op: "anonymise-workspace-member-removals",
      extra: { userId },
      message: "anonymise_workspace_member_removals threw — aborting deletion",
    });
    return { success: false, error: "Account deletion failed at anonymise-workspace-member-removals. Please try again." };
  }

  // 3.91 Anonymise workspace_members rows (migration 058). DELETEs every
  //      membership row keyed on user_id, including the user's solo
  //      backfill owner row. FK workspace_members.workspace_id +
  //      .attestation_id are RESTRICT — attestations were already
  //      NULLed in 3.90, and workspaces stay live (they're cleaned up by
  //      anonymise_organization_membership in 3.92 if they orphan).
  try {
    const { error: anonMemErr } = await service.rpc(
      "anonymise_workspace_members",
      { p_user_id: userId },
    );
    if (anonMemErr) {
      reportSilentFallback(anonMemErr, {
        feature: "account-delete",
        op: "anonymise-workspace-members",
        extra: { userId },
        message: "anonymise_workspace_members failed — aborting deletion",
      });
      return { success: false, error: "Account deletion failed at anonymise-workspace-members. Please try again." };
    }
  } catch (err) {
    reportSilentFallback(err, {
      feature: "account-delete",
      op: "anonymise-workspace-members",
      extra: { userId },
      message: "anonymise_workspace_members threw — aborting deletion",
    });
    return { success: false, error: "Account deletion failed at anonymise-workspace-members. Please try again." };
  }

  // 3.92 Anonymise organization membership (migration 058, simplified by
  //      migration 065 Part 3). For every organization where the deleted
  //      user was owner with other members remaining, the RPC reassigns
  //      owner_user_id to the oldest remaining member. Orphan orgs (no
  //      other members) are NOT hard-deleted here; mig 065 Part 1 changed
  //      organizations.owner_user_id from RESTRICT to SET NULL, so the
  //      cascade-induced auth.users delete naturally NULLs the owner. The
  //      orphan org survives as a record-of-existence with NULL owner,
  //      reachable by no live user via RLS, eventually purged by a janitor.
  try {
    const { data: orgsReassigned, error: anonOrgErr } = await service.rpc(
      "anonymise_organization_membership",
      { p_user_id: userId },
    );
    if (anonOrgErr) {
      reportSilentFallback(anonOrgErr, {
        feature: "account-delete",
        op: "anonymise-organization-membership",
        extra: { userId },
        message: "anonymise_organization_membership failed — aborting deletion",
      });
      const detail = typeof anonOrgErr === "object" && anonOrgErr !== null && "message" in anonOrgErr ? (anonOrgErr as { message: string }).message : String(anonOrgErr);
      return { success: false, error: `Account deletion failed at anonymise-organization-membership: ${detail}` };
    }
    // Surface the reassign count + count of soon-to-be-orphan orgs so a
    // janitor / dashboard can detect runaway null-owner growth.
    // `anonymise_organization_membership` returns the reassign count; an
    // orphan org count is the live count of orgs owned by this user before
    // the SET NULL cascade fires at auth-delete.
    try {
      const { data: orphanRows } = await service
        .from("organizations")
        .select("id", { count: "exact", head: true })
        .eq("owner_user_id", userId);
      // Use userIdHash directly per the userid-bypass-lint convention
      // (#3698) — the pino formatter rename hook covers grandfathered
      // sites but new emits must compute the hash at the call site.
      log.info(
        {
          userIdHash: hashUserId(userId),
          orgsReassigned: orgsReassigned ?? 0,
          orphanOrgsPendingSetNull: orphanRows ?? 0,
        },
        "Art-17 cascade: organization-membership state",
      );
    } catch (probeErr) {
      // Observability-only; do not fail the cascade.
      log.warn(
        { userIdHash: hashUserId(userId), err: probeErr },
        "orphan-org probe failed (non-fatal)",
      );
    }
  } catch (err) {
    reportSilentFallback(err, {
      feature: "account-delete",
      op: "anonymise-organization-membership",
      extra: { userId },
      message: "anonymise_organization_membership threw — aborting deletion",
    });
    return { success: false, error: "Account deletion failed at anonymise-organization-membership. Please try again." };
  }

  // 3.93 Anonymise workspace_member_actions audit rows (migration 063, #4231).
  //      NULL-sets actor_user_id + target_user_id for every row referencing
  //      the departing user. Lineage columns (workspace_id, action_type,
  //      old_role, new_role, created_at, attestation_id) preserved. Idempotent
  //      (re-run's WHERE matches zero already-NULLed rows). MUST run BEFORE
  //      auth.admin.deleteUser — public.users FK is RESTRICT, so the auth
  //      cascade aborts without prior anonymisation. Cascade DELETEs at
  //      step 3.91 do NOT create new audit rows because anonymise_workspace_
  //      members SET LOCAL session_replication_role='replica' suppresses the
  //      AFTER trigger; step 3.93 only anonymises rows from prior legitimate
  //      invite/remove RPC calls.
  try {
    const { error: anonAuditErr } = await service.rpc(
      "anonymise_workspace_member_actions",
      { p_user_id: userId },
    );
    if (anonAuditErr) {
      reportSilentFallback(anonAuditErr, {
        feature: "account-delete",
        op: "anonymise-workspace-member-actions",
        extra: { userId },
        message: "anonymise_workspace_member_actions failed — aborting deletion",
      });
      return { success: false, error: "Account deletion failed at anonymise-workspace-member-actions. Please try again." };
    }
  } catch (err) {
    reportSilentFallback(err, {
      feature: "account-delete",
      op: "anonymise-workspace-member-actions",
      extra: { userId },
      message: "anonymise_workspace_member_actions threw — aborting deletion",
    });
    return { success: false, error: "Account deletion failed at anonymise-workspace-member-actions. Please try again." };
  }

  // 3.935 Anonymise workspace_activity rows (migration 076, #4521 PR-B).
  //       NULL-sets actor_user_id + empties metadata for every row
  //       referencing the departing user. Best-effort — activity feed
  //       events are ephemeral (90-day pg_cron purge) and the SET NULL FK
  //       handles the auth cascade; this step is defense-in-depth for
  //       metadata scrubbing.
  try {
    const { error: anonActivityErr } = await service.rpc(
      "anonymise_workspace_activity",
      { p_user_id: userId },
    );
    if (anonActivityErr) {
      reportSilentFallback(anonActivityErr, {
        feature: "account-delete",
        op: "anonymise-workspace-activity",
        extra: { userId },
      });
    }
  } catch (err) {
    reportSilentFallback(err, {
      feature: "account-delete",
      op: "anonymise-workspace-activity",
      extra: { userId },
    });
  }

  // 3.94 Anonymise byok_delegations (migration 064, #4232 PR-A).
  //      byok_delegations.{grantor,grantee,created_by,revoked_by,
  //      cap_updated_by}_user_id all reference users(id) ON DELETE
  //      RESTRICT — without this step the auth-delete cascade would
  //      abort with FK 23503. The RPC writes WORM Shape 1 (revoke
  //      flip with revocation_reason='art_17_anonymise') for any
  //      currently-active rows, then WORM Shape 2 nulls identity +
  //      workspace + actor cols in a single txn. Idempotent: re-runs
  //      no-op once every row referencing this user has been
  //      anonymised. Sibling-error shape with anonymise_workspace_
  //      member_actions above.
  try {
    const { error: anonByokErr } = await service.rpc(
      "anonymise_byok_delegations",
      { p_user_id: userId },
    );
    if (anonByokErr) {
      log.error(
        { userId, err: anonByokErr },
        "anonymise_byok_delegations failed — aborting deletion to avoid FK-block",
      );
      return { success: false, error: "Account deletion failed at unknown. Please try again." };
    }
  } catch (err) {
    log.error(
      { userId, err },
      "anonymise_byok_delegations threw — aborting deletion to avoid FK-block",
    );
    return { success: false, error: "Account deletion failed at unknown. Please try again." };
  }

  // 3.95 Anonymise byok_delegation_acceptances (migration 074, #4232 PR-B).
  //      byok_delegation_acceptances.user_id references users(id) ON DELETE
  //      RESTRICT — without this step the auth-delete cascade would abort
  //      with FK 23503. The RPC nulls user_id + ip_hash + user_agent via
  //      session_replication_role='replica' WORM bypass. Idempotent.
  try {
    const { error: anonAcceptErr } = await service.rpc(
      "anonymise_byok_delegation_acceptances",
      { p_user_id: userId },
    );
    if (anonAcceptErr) {
      log.error(
        { userId, err: anonAcceptErr },
        "anonymise_byok_delegation_acceptances failed — aborting deletion to avoid FK-block",
      );
      return { success: false, error: "Account deletion failed at unknown. Please try again." };
    }
  } catch (err) {
    log.error(
      { userId, err },
      "anonymise_byok_delegation_acceptances threw — aborting deletion to avoid FK-block",
    );
    return { success: false, error: "Account deletion failed at unknown. Please try again." };
  }

  // 3.96 Anonymise byok_delegation_withdrawals (migration 084, #4625).
  //      byok_delegation_withdrawals.user_id references users(id) ON DELETE
  //      RESTRICT — without this step the auth-delete cascade would abort
  //      with FK 23503. The RPC nulls user_id + ip_hash + user_agent via
  //      session_replication_role='replica' WORM bypass. The table has NO
  //      UNIQUE(user_id, delegation_id), so anonymising ≥2 withdrawal rows
  //      for the same delegation cannot collide on (NULL, delegation_id)
  //      (AC14). Idempotent.
  try {
    const { error: anonWithdrawErr } = await service.rpc(
      "anonymise_byok_delegation_withdrawals",
      { p_user_id: userId },
    );
    if (anonWithdrawErr) {
      log.error(
        { userId, err: anonWithdrawErr },
        "anonymise_byok_delegation_withdrawals failed — aborting deletion to avoid FK-block",
      );
      return { success: false, error: "Account deletion failed at unknown. Please try again." };
    }
  } catch (err) {
    log.error(
      { userId, err },
      "anonymise_byok_delegation_withdrawals threw — aborting deletion to avoid FK-block",
    );
    return { success: false, error: "Account deletion failed at unknown. Please try again." };
  }

  // 3.97 Anonymise email_triage_items (migration 102, #5103).
  //      email_triage_items.user_id references users(id) ON DELETE RESTRICT —
  //      without this step the auth-delete cascade would abort with FK 23503
  //      (and a no-delete WORM trigger would block a CASCADE anyway). The RPC
  //      NULLs user_id + sender under the GUC-gated WORM bypass
  //      (app.email_triage_anonymise_in_progress); statutory rows are retained
  //      anonymised per Art. 17(3)(b) — see the PA-27 LIA. Idempotent: re-runs
  //      no-op once every row referencing this user is anonymised.
  try {
    const { error: anonTriageErr } = await service.rpc(
      "anonymise_email_triage_items",
      { p_user_id: userId },
    );
    if (anonTriageErr) {
      log.error(
        { userId, err: anonTriageErr },
        "anonymise_email_triage_items failed — aborting deletion to avoid FK-block",
      );
      return { success: false, error: "Account deletion failed at anonymise-email-triage-items. Please try again." };
    }
  } catch (err) {
    log.error(
      { userId, err },
      "anonymise_email_triage_items threw — aborting deletion to avoid FK-block",
    );
    return { success: false, error: "Account deletion failed at anonymise-email-triage-items. Please try again." };
  }

  // 3.98 Anonymise routine_runs (migration 107, #5345 / #5372).
  //      routine_runs.actor_id / .delegating_principal reference users(id)
  //      ON DELETE RESTRICT — without this step the auth-delete cascade aborts
  //      with FK 23503 (and the WORM no-mutate trigger would block a SET NULL/
  //      CASCADE anyway). The RPC NULLs both columns under the GUC-gated WORM
  //      bypass (app.worm_bypass), preserving the append-only run-log row
  //      (Art. 17 = scrub the subject's PII, keep the operational-audit row).
  //      MUST run BEFORE auth.admin.deleteUser. Idempotent: re-runs no-op once
  //      every row referencing this user is anonymised.
  try {
    const { error: anonRoutineErr } = await service.rpc(
      "anonymise_routine_runs",
      { p_user_id: userId },
    );
    if (anonRoutineErr) {
      reportSilentFallback(anonRoutineErr, {
        feature: "account-delete",
        op: "anonymise-routine-runs",
        extra: { userId },
        message: "anonymise_routine_runs failed — aborting deletion to avoid FK-block",
      });
      return { success: false, error: "Account deletion failed at anonymise-routine-runs. Please try again." };
    }
  } catch (err) {
    reportSilentFallback(err, {
      feature: "account-delete",
      op: "anonymise-routine-runs",
      extra: { userId },
      message: "anonymise_routine_runs threw — aborting deletion to avoid FK-block",
    });
    return { success: false, error: "Account deletion failed at anonymise-routine-runs. Please try again." };
  }

  // 4. Delete auth record — FK cascade handles public.users and all children
  //    IMPORTANT: auth deletion runs LAST among destructive steps. If it
  //    fails, the preceding steps are idempotent (anonymise re-runs as a
  //    no-op; abort-dsar-jobs re-runs against already-failed rows; storage
  //    purges have no orphan harm) so the user can retry the cascade
  //    safely. If auth-delete ran FIRST and a later step failed, the user
  //    would have an auth record but no data (GDPR Article 17 violation).
  const { error: deleteAuthError } = await service.auth.admin.deleteUser(userId);

  if (deleteAuthError) {
    reportSilentFallback(deleteAuthError, {
      feature: "account-delete",
      op: "auth-delete",
      extra: { userId },
      message: "Failed to delete auth record",
    });
    return { success: false, error: "Account deletion failed at auth-delete. Please try again." };
  }

  log.info({ userId }, "Account deleted successfully (GDPR Art. 17)");
  return { success: true };
}
