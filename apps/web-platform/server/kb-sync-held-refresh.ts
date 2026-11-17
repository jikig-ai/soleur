// ---------------------------------------------------------------------------
// KB sync held count: the one compute-and-write path of `workspaces.kb_sync_held_files` (#12714, ruling D39(a)).
//
// `heldCountOn` / `writeHeldCount` moved here verbatim from server/session-sync.ts (review Phase 0), which still calls them
// from `syncPull` and `syncPush`. `writeHeldFromIsolated` and `refreshHeldCount` are the frozen signatures WP3 fills in
// (D39(a)/(b)/(f)); in Phase 0 nothing calls them, and both never throw.
// ---------------------------------------------------------------------------

import type { SupabaseClient } from "@supabase/supabase-js";
import type { IsolatedPushDirHandle } from "./git-isolated-push-dir";
import { computeHeldFiles, readRecoveredKbSyncTips, type HeldFiles } from "./kb-sync-held";
import { createChildLogger } from "./logger";
import { writeKbSyncHeldCols, type KbSyncPullBlocked } from "./workspace-repo-mirror";

// The moved lines keep the log context they had in session-sync.ts (no behaviour change in the move).
const log = createChildLogger("session-sync");

/** A computed held-files count and when it was computed. */
export interface HeldCount extends HeldFiles {
  readonly checkedAt: string;
}

/**
 * #12714 (W1, W2, W4, D29(1)): the held-files count on an isolated dir this sync holds, over `base...head` (`base` = the
 * remote tip this run's hardened `ls-remote` returned, `head` = a HEX40 HEAD sha) plus the recovered kb-sync tips. Null
 * (write nothing, show nothing) when the recovered refs cannot be read safely or the count cannot be computed; never
 * throws (the count is display-only and must not change the sync's result).
 */
export async function heldCountOn(
  isolated: IsolatedPushDirHandle,
  base: string,
  head: string,
  workspacePath: string,
  workspaceId: string,
): Promise<HeldCount | null> {
  try {
    const recovered = readRecoveredKbSyncTips(workspacePath);
    if (recovered === null) return null;
    const held = await computeHeldFiles({ isolated, base, head, recovered, workspaceId });
    return held === null ? null : { total: held.total, onRecovered: held.onRecovered, checkedAt: new Date().toISOString() };
  } catch (err) {
    log.warn({ workspaceId, errName: err instanceof Error ? err.name : typeof err }, "Held-files count failed; nothing written");
    return null;
  }
}

/**
 * The separate held-files UPDATE (D29(1)): never folded into `updateLastSynced`, so a missing column fails only this write.
 * `writeKbSyncHeldCols` never throws by contract; the catch keeps a broken client from changing the sync's result.
 */
export async function writeHeldCount(service: SupabaseClient, workspaceId: string, held: HeldCount): Promise<void> {
  try {
    await writeKbSyncHeldCols(service, workspaceId, { heldFiles: held.total, checkedAt: new Date(held.checkedAt) });
  } catch (err) {
    log.warn({ workspaceId, errName: err instanceof Error ? err.name : typeof err }, "Held-files write threw");
  }
}

/**
 * D39(a): the held count on an isolated dir a sync or the self-heal already holds, over its own `T`, written with
 * `checkedAt` (the instant this run read `T`, `RemoteState.readAt`). Returns the stored total, or null when none was
 * computed. Never throws.
 *
 * Phase 0 stub (frozen signature): computes only and writes nothing (the service-client write, `pullBlocked` and the
 * budget land with WP3). No caller yet.
 */
export async function writeHeldFromIsolated(a: {
  readonly isolated: IsolatedPushDirHandle;
  readonly workspacePath: string;
  readonly workspaceId: string;
  readonly T: string;
  readonly headSha: string;
  readonly checkedAt: Date;
  readonly pullBlocked?: KbSyncPullBlocked | null;
  readonly budgetMs?: number;
}): Promise<number | null> {
  try {
    const held = await heldCountOn(a.isolated, a.T, a.headSha, a.workspacePath, a.workspaceId);
    return held === null ? null : held.total;
  } catch {
    return null;
  }
}

/**
 * D39(a): the standalone refresh (repo URL, installation, isolated dir, hardened `readRemoteState`, compute, write,
 * dispose), called by the cc runner after a turn. Never throws.
 *
 * Phase 0 stub (frozen signature): a no-op. No caller yet.
 */
export async function refreshHeldCount(_a: {
  readonly workspaceId: string;
  readonly workspacePath: string;
  readonly installationId: number;
  readonly userId?: string;
}): Promise<void> {
  return;
}
