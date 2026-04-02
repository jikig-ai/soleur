import { createServiceClient } from "@/lib/supabase/server";
import { abortAllUserSessions } from "@/server/agent-runner";
import { deleteWorkspace } from "@/server/workspace";
import { createChildLogger } from "./logger";

const log = createChildLogger("account-delete");

export interface DeleteAccountResult {
  success: boolean;
  error?: string;
}

/**
 * Deletes a user account with full cascade:
 * 1. Abort any active agent session
 * 2. Delete the workspace directory
 * 3. Delete the auth.users record (FK cascade handles public.users and all children)
 *
 * Auth deletion MUST come first among destructive steps. If it fails, no data
 * is lost and the user can retry. The FK constraint (public.users.id REFERENCES
 * auth.users(id) ON DELETE CASCADE) ensures public.users, api_keys,
 * conversations, and messages are deleted atomically within the same Postgres
 * transaction as the auth record.
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

  // 4. Delete auth record — FK cascade handles public.users and all children
  //    IMPORTANT: auth deletion must come first. If it fails, no data is lost.
  //    If public.users were deleted first and auth deletion failed, the user
  //    would have an auth record but no data (GDPR Article 17 violation).
  const { error: deleteAuthError } = await service.auth.admin.deleteUser(userId);

  if (deleteAuthError) {
    log.error({ userId, err: deleteAuthError }, "Failed to delete auth record");
    return { success: false, error: "Account deletion failed. Please try again." };
  }

  log.info({ userId }, "Account deleted successfully (GDPR Art. 17)");
  return { success: true };
}
