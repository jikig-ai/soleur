import { isUuid } from "@/lib/is-uuid";
import { reportLegalOp } from "@/server/approval/ops";

/**
 * Who may see and answer the founder legal-acceptance card (#12197).
 *
 * The surface (the card pages, the Inbox row and the decide and reauth routes) is open only to the configured founder: the id in
 * `LEGAL_ACCEPTANCE_FOUNDER_ID` (the same variable the check endpoint uses). For anyone else it behaves as if it did not exist.
 * Fails closed: an unset or malformed variable disables the surface for everyone, including the founder. The kill switch is
 * unsetting the variable.
 *
 * The `approval-queue` flag is not read. It is read elsewhere with `workspaceId: null` (identifier `role:prd`), so no per-workspace
 * segment can match it, and narrowing or turning off the approval queue would otherwise hide the founder's own screen. CTO ruling
 * 2026-11-10 supersedes ruling B's (2026-11-07) gate on both the flag and the founder, and T4's "flag ON" condition. This module
 * never reads, creates or flips the flag.
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
 * True only when this user is the configured founder (case-insensitive id compare).
 *
 * An unset id is the dark state (the kill switch, or a value removed by accident): it is silent here and in the check endpoint, it
 * can take effect only at a process start, and it is found by the unauthenticated probe of the check endpoint answering 503
 * instead of 401. A set-but-malformed id is reported once per process as `store_failed` / stage `config`. CTO ruling 2026-11-10
 * supersedes T4's flag-ON condition.
 *
 * The report never carries the user id or the variable's value. Kept `async` so no caller changes.
 */
export async function isLegalSurfaceEnabled(userId: string): Promise<boolean> {
  const founder = legalFounderId();
  if (founder === null) {
    if (process.env.LEGAL_ACCEPTANCE_FOUNDER_ID && !configReported) {
      configReported = true;
      reportLegalOp("storeFailed", null, {
        tags: { stage: "config" },
        extra: { step: "config", variables: ["LEGAL_ACCEPTANCE_FOUNDER_ID"] },
      });
    }
    return false;
  }
  return userId.toLowerCase() === founder;
}
