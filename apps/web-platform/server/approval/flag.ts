/**
 * The `approval-queue` flag seam (#4672).
 *
 * Everything that would create, show or emit an approval request reads the flag through THIS function and nothing
 * else. It is deliberately constant-false until task 4.3 wires the Flagsmith read (RUNTIME_FLAGS entry, env mirror,
 * flip map): the code path is dormant by construction, and no flag exists, is created or is flipped by this module.
 *
 * Contract for the wired version: evaluated once per gate (never per poll), per workspace identity, and any error,
 * timeout or absent feature means OFF (fail closed: an unreadable flag must never turn the approval path ON).
 */

export interface ApprovalFlagIdentity {
  userId: string;
  /** Null when the caller has not resolved the workspace (the wired flag read resolves the identity itself). */
  workspaceId: string | null;
}

export async function isApprovalQueueEnabled(_identity: ApprovalFlagIdentity): Promise<boolean> {
  // SOLEUR-DEBT: constant-false until task 4.3 (flag plumbing) swaps this body for the Flagsmith read; upgrade trigger: 4.3 lands.
  return false;
}
