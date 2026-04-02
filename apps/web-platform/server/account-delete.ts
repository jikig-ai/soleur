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
 * 3. Delete the public.users row (cascades to api_keys, conversations, messages)
 * 4. Delete the auth.users record
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

  // 4. Delete public.users row (FK cascade deletes api_keys, conversations, messages)
  const { error: deletePublicError } = await service
    .from("users")
    .delete()
    .eq("id", userId);

  if (deletePublicError) {
    log.error({ userId, err: deletePublicError }, "Failed to delete public.users");
    return { success: false, error: "Account deletion failed. Please try again." };
  }

  // 5. Delete auth record
  const { error: deleteAuthError } = await service.auth.admin.deleteUser(userId);

  if (deleteAuthError) {
    log.error({ userId, err: deleteAuthError }, "Failed to delete auth record");
    return { success: false, error: "Account deletion failed. Auth record could not be removed." };
  }

  log.info({ userId }, "Account deleted successfully (GDPR Art. 17)");
  return { success: true };
}
