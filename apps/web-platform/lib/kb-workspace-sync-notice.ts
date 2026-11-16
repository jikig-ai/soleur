// #12600 (CTO ruling D16): the interim answer of a KB write (upload, delete, rename) that landed on GitHub while the
// workspace clone was deliberately NOT updated, because it holds local changes that are not on the repository's default
// branch yet (a designed hold of the self-heal: held commits, a dirty tracked file, or an untracked file in the reset's
// way). "Not on GitHub" would be false after a protected KB-only turn: the held commit is then the side commit, which IS
// on GitHub in the open `soleur/kb-sync` PR (#12600 D23). The route answers
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
  detail: "Your workspace has local changes that aren't on your repository's main branch yet, so it was not updated. You don't need to try again.",
} as const;

/** The full notice for `op`. */
export function kbWorkspaceSyncPendingNotice(op: KbWriteOp): string {
  return `${KB_WORKSPACE_SYNC_PENDING_NOTICE.lead[op]} ${KB_WORKSPACE_SYNC_PENDING_NOTICE.detail}`;
}

/** The `workspace_sync_held` value the c4 route forwards when only the post-render resync was held (D22(c)). */
export const WORKSPACE_SYNC_HELD_RESYNC_ONLY = "rerender" as const;

/**
 * D22(c): the c4 save's first sync updated the workspace and only the post-render resync was held, so the saved source
 * IS in the workspace and only the re-rendered diagram may be missing.
 */
export function kbWorkspaceSyncResyncPendingNotice(): string {
  return "Saved to GitHub. Your workspace may not show the updated diagram yet, because it has local changes that aren't on your repository's main branch yet. You don't need to try again.";
}

/** True when a c4 save's JSON body says only the post-render resync was held. */
export function isWorkspaceSyncResyncOnly(body: unknown): boolean {
  return typeof body === "object" && body !== null && (body as { workspace_sync_held?: unknown }).workspace_sync_held === WORKSPACE_SYNC_HELD_RESYNC_ONLY;
}

/** True when a KB write route's JSON body says the workspace was held (`workspace_sync: "pending"`). */
export function isWorkspaceSyncPending(body: unknown): boolean {
  return typeof body === "object" && body !== null && (body as { workspace_sync?: unknown }).workspace_sync === WORKSPACE_SYNC_PENDING;
}
