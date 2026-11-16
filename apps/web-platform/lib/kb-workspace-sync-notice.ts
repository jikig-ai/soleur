// #12600 (CTO ruling D16): the interim answer of a KB write (upload, delete, rename) that landed on GitHub while the
// workspace clone was deliberately NOT updated, because it holds local changes that are not on GitHub yet (a designed
// hold of the self-heal: held commits, a dirty tracked file, or an untracked file in the reset's way). The route answers
// its normal success body plus `workspace_sync: "pending"` and the KB UI shows this notice as a non-error status.
//
// ONE shared constant (client-safe: no server import) for the wire value and the user-facing copy. No timing promise:
// no code path guarantees when the workspace updates. Interim copy; the #12714 wireframe may refine it.

/** The `workspace_sync` value a KB write route adds to its success body when the workspace was held. */
export const WORKSPACE_SYNC_PENDING = "pending" as const;

export type KbWriteOp = "upload" | "delete" | "rename" | "save";

export const KB_WORKSPACE_SYNC_PENDING_NOTICE = {
  /** First clause, per op. */
  lead: {
    upload: "Saved to GitHub.",
    delete: "Deleted on GitHub.",
    rename: "Renamed on GitHub.",
    save: "Saved to GitHub.",
  } satisfies Record<KbWriteOp, string>,
  /** The shared second clause. */
  detail: "Your workspace has local changes that are not on GitHub yet, so it was not updated. You don't need to try again.",
} as const;

/** The full notice for `op`. */
export function kbWorkspaceSyncPendingNotice(op: KbWriteOp): string {
  return `${KB_WORKSPACE_SYNC_PENDING_NOTICE.lead[op]} ${KB_WORKSPACE_SYNC_PENDING_NOTICE.detail}`;
}

/** True when a KB write route's JSON body says the workspace was held (`workspace_sync: "pending"`). */
export function isWorkspaceSyncPending(body: unknown): boolean {
  return typeof body === "object" && body !== null && (body as { workspace_sync?: unknown }).workspace_sync === WORKSPACE_SYNC_PENDING;
}
