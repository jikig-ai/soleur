import { isUuid } from "@/lib/is-uuid";
import { isApprovalQueueEnabled } from "@/server/approval/flag";
import { reportLegalOp } from "@/server/approval/ops";

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

let configReported = false;
/** Test seam: re-arms the once-per-process config report. */
export function resetSurfaceConfigReport(): void {
  configReported = false;
}

/**
 * True only when the flag is on AND this user is the configured founder.
 *
 * Order matters (CTO ruling T4, 2026-11-08): the founder is compared FIRST, so a non-founder returns false without a flag read. With
 * no usable founder id the surface is closed for everyone, and that is the one state that would otherwise be invisible: the flag
 * is ON (the operator turned it on), the founder gets a plain 404, and nothing says why. So that state, and only that state, is
 * reported once per process as `store_failed` / stage `config` (the same event the check endpoint raises for a malformed value).
 * The report never carries the user id or the variable's value.
 */
export async function isLegalSurfaceEnabled(userId: string): Promise<boolean> {
  const founder = legalFounderId();
  if (founder !== null) {
    if (userId.toLowerCase() !== founder) return false;
    return isApprovalQueueEnabled({ userId, workspaceId: null });
  }
  const flagOn = await isApprovalQueueEnabled({ userId, workspaceId: null });
  if (flagOn && !configReported) {
    configReported = true;
    reportLegalOp("storeFailed", null, {
      tags: { stage: "config" },
      extra: { step: "config", variables: ["LEGAL_ACCEPTANCE_FOUNDER_ID"] },
    });
  }
  return false;
}
