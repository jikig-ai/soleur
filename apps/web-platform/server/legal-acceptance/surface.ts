import { isUuid } from "@/lib/is-uuid";
import { isApprovalQueueEnabled } from "@/server/approval/flag";

/**
 * Who may see and answer the founder legal-acceptance card (#12197, CTO ruling B of 2026-11-07).
 *
 * The `approval-queue` flag is read with `workspaceId: null` and its identifier is `role:prd`, so it cannot target one user:
 * with the flag ON, every signed-in user would be offered the card. The card is the founder's own record, so the surface is
 * the flag AND the founder: the id in `LEGAL_ACCEPTANCE_FOUNDER_ID` (the same variable the check endpoint uses). For anyone
 * else this behaves exactly like the flag being off. Fails closed: an unset or malformed variable disables the surface for
 * everyone, including the founder.
 *
 * This module never creates or flips the flag; that stays the operator's act.
 */

/** The configured founder id, lower-cased, or null when the variable is unset or not a UUID. */
export function legalFounderId(): string | null {
  const raw = process.env.LEGAL_ACCEPTANCE_FOUNDER_ID;
  return isUuid(raw) ? raw.toLowerCase() : null;
}

/** True only when the flag is on AND this user is the configured founder. */
export async function isLegalSurfaceEnabled(userId: string): Promise<boolean> {
  const flagOn = await isApprovalQueueEnabled({ userId, workspaceId: null });
  const founder = legalFounderId();
  return flagOn && founder !== null && userId.toLowerCase() === founder;
}
