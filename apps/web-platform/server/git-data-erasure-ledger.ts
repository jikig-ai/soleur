// Durable pending-erasure ledger for the git-data bare-repo store (#8211, migration 182).
//
// Account deletion records every non-`erased`/`skipped` removeGitDataRepo outcome here so the
// re-drive cron (server/inngest/functions/cron-git-data-erasure-redrive.ts) can finish the erasure
// instead of leaving it as a Sentry event plus a manual sweep. All access goes through the
// service-role-only SECURITY DEFINER RPCs; the tables have no client-reachable grant.
//
// The only identifier is the workspace id, which equals the id `gitDataRepoId` already carries to
// Sentry (account-delete.ts). This module never logs or tags it anywhere else.

import type { SupabaseClient } from "@supabase/supabase-js";
import { reportSilentFallback } from "@/server/observability";
import { isUuid } from "@/lib/is-uuid";
import type { GitDataErasureOutcome } from "@/server/git-data-replication";

/**
 * The statuses of GitDataErasureOutcome that mean "the repo may still be on the host". DERIVED from
 * the union, not restated: `satisfies Record<..., true>` fails tsc if the union gains or loses a
 * non-terminal status (and test/git-data-erasure-outcome-parity.test.ts compares the same set,
 * read from the union's source text, to the migration CHECK and to this constant at runtime).
 */
type NonTerminalStatus = Exclude<GitDataErasureOutcome, { status: "erased" } | { status: "skipped" }>["status"];
const HOST_OUTCOME_SET = {
  refused: true,
  unreachable: true,
  unauthorized: true,
  unconfigured: true,
  host_key_mismatch: true,
} as const satisfies Record<NonTerminalStatus, true>;

/** Host outcomes the ledger stores under their own status word. */
export const GIT_DATA_ERASURE_HOST_OUTCOMES = Object.keys(HOST_OUTCOME_SET) as NonTerminalStatus[];

/**
 * Two DELIBERATE extras beyond the union, both enforced by the migration CHECK:
 *   - `threw`   account-delete's thrown arm (same spelling as its `erasure_outcome` Sentry tag);
 *   - `seeded`  a row written by the re-drive's manual seed path, which has no host outcome yet.
 *               Nothing else emits it; it is overwritten by the first real attempt.
 */
export const GIT_DATA_ERASURE_LEDGER_EXTRA_OUTCOMES = ["threw", "seeded"] as const;

/** The closed set `git_data_erasure_pending.last_outcome` accepts (CHECK in migration 182). */
export const GIT_DATA_ERASURE_LEDGER_OUTCOMES = [
  ...GIT_DATA_ERASURE_HOST_OUTCOMES,
  ...GIT_DATA_ERASURE_LEDGER_EXTRA_OUTCOMES,
] as const;

export type GitDataErasureLedgerOutcome = (typeof GIT_DATA_ERASURE_LEDGER_OUTCOMES)[number];

export const GIT_DATA_ERASURE_LEDGER_FEATURE = "git-data-erasure-ledger";

/** A hung ledger RPC must not stall the deletion cascade (account-delete awaits the best-effort write). */
export const LEDGER_WRITE_TIMEOUT_MS = 5_000;

/**
 * The minimal client the ledger helpers need. Exported so callers (the re-drive cron) type their
 * service client with it instead of casting through `never`.
 * The id shape guard is `isUuid` (lib/is-uuid.ts): the only id shape the ledger column and the host
 * wrapper accept.
 */
export type Rpc = Pick<SupabaseClient, "rpc">;

/**
 * Upsert a pending row (keeps the earlier requested_at). `requestedAt` is for the seed path only:
 * an id swept from Sentry keeps its ORIGINAL request time so the Art. 12(3) clock is not reset.
 * Throws on any failure.
 */
export async function recordGitDataErasurePending(
  service: Rpc,
  workspaceId: string,
  outcome: GitDataErasureLedgerOutcome,
  requestedAt?: Date,
): Promise<void> {
  const { error } = await service.rpc("record_git_data_erasure_pending", {
    p_workspace_id: workspaceId,
    p_outcome: outcome,
    ...(requestedAt ? { p_requested_at: requestedAt.toISOString() } : {}),
  });
  if (error) throw new Error(`record_git_data_erasure_pending failed: ${error.message}`);
}

/**
 * True only when no account/membership row still keys on the id (see migration 182's header for the
 * exact tables). The ledger is NOT proof that an account is gone: a seeded wrong id, or a deletion
 * that aborts after the ledger write, would otherwise get a live user's repository erased. An RPC
 * error throws; callers must treat a throw as "not gone".
 */
export async function gitDataErasureOwnerGone(service: Rpc, workspaceId: string): Promise<boolean> {
  const { data, error } = await service.rpc("git_data_erasure_owner_gone", { p_workspace_id: workspaceId });
  if (error) throw new Error(`git_data_erasure_owner_gone failed: ${error.message}`);
  return data === true;
}

/**
 * Account-delete variant: NEVER throws and never changes the caller's control flow. A failed,
 * skipped or hung (> LEDGER_WRITE_TIMEOUT_MS) write is mirrored to Sentry under its own feature/op
 * (not the account-delete Art. 17 feature/op, which `art17_erasure_incomplete` filters on). The id
 * rides `gitDataRepoId` only: the ledger write failing means this Sentry event is then the sole
 * record of the owed erasure, and `reportSilentFallback` would hash a `userId` key.
 */
export async function recordGitDataErasurePendingBestEffort(
  service: Rpc,
  workspaceId: string,
  outcome: GitDataErasureLedgerOutcome,
  timeoutMs: number = LEDGER_WRITE_TIMEOUT_MS,
): Promise<void> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    if (!isUuid(workspaceId)) {
      throw new Error("workspace id is not a UUID; the ledger column cannot hold it");
    }
    await Promise.race([
      recordGitDataErasurePending(service, workspaceId, outcome),
      new Promise<never>((_, reject) => {
        timer = setTimeout(
          () => reject(new Error(`ledger write exceeded ${timeoutMs} ms; the deletion cascade continues`)),
          timeoutMs,
        );
      }),
    ]);
  } catch (err) {
    try {
      // `null` + a static message, NOT the Error: reportSilentFallback(Error) is deduplicated against the
      // pino mirror (#8629), which drops these tags and extras. The cause rides `extra`.
      reportSilentFallback(null, {
        feature: GIT_DATA_ERASURE_LEDGER_FEATURE,
        op: "record-pending",
        message:
          "pending git-data erasure could not be recorded in the ledger — only the Art. 17 Sentry event names it; seed it by hand",
        extra: {
          gitDataRepoId: workspaceId,
          outcome,
          cause: err instanceof Error ? err.message : String(err),
        },
      });
    } catch {
      // Reporting must not break the deletion cascade either.
    }
  } finally {
    if (timer) clearTimeout(timer);
  }
}
