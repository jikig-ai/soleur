import type { SupabaseClient } from "@supabase/supabase-js";
import { createServiceClient } from "@/lib/supabase/server";
import { abortAllUserSessions } from "@/server/agent-runner";
import { deleteWorkspace } from "@/server/workspace";
import { createChildLogger } from "./logger";

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

  // 3. Delete workspace directory
  try {
    await deleteWorkspace(userId);
  } catch (err) {
    log.warn({ userId, err }, "Failed to delete workspace during deletion (non-fatal)");
  }

  // 3.5 Purge Storage blobs for all user attachments AND DSAR export
  // bundles (DB rows are FK-cascaded, but Storage objects are not).
  // Plan rev-2 AC25 extends the storage-purge step to cover
  // dsar-exports/<userId>/ so a half-completed export bundle does not
  // outlive the user account.
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
      log.error(
        { userId, err: anonSgErr },
        "anonymise_scope_grants failed — aborting deletion to avoid FK-block",
      );
      return { success: false, error: "Account deletion failed. Please try again." };
    }
  } catch (err) {
    log.error(
      { userId, err },
      "anonymise_scope_grants threw — aborting deletion to avoid FK-block",
    );
    return { success: false, error: "Account deletion failed. Please try again." };
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
      log.error(
        { userId, err: anonTcErr },
        "anonymise_tc_acceptances failed — aborting deletion to avoid FK-block",
      );
      return { success: false, error: "Account deletion failed. Please try again." };
    }
  } catch (err) {
    log.error(
      { userId, err },
      "anonymise_tc_acceptances threw — aborting deletion to avoid FK-block",
    );
    return { success: false, error: "Account deletion failed. Please try again." };
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
    log.error({ userId, err: deleteAuthError }, "Failed to delete auth record");
    return { success: false, error: "Account deletion failed. Please try again." };
  }

  log.info({ userId }, "Account deleted successfully (GDPR Art. 17)");
  return { success: true };
}
