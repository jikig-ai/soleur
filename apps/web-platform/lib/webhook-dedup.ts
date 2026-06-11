// #5103 Phase 3 — webhook delivery-id dedup claim/release helper.
//
// Rule-of-three extraction: the resend-inbound route would otherwise be the
// THIRD verbatim copy of the claim/release idiom after
// `app/api/webhooks/stripe/route.ts:118-160` and
// `app/api/webhooks/github/route.ts:147-190`. Used by the NEW route only —
// migrating the two existing brand-critical routes is a separate scope-out
// issue (distinct from #3739, which extracts reportSilentFallbackWithUser).
//
// Claim is a plain .insert() — NO ON CONFLICT. supabase-js .insert()
// returns data:null (not [], not an affected-row count) on
// ON CONFLICT DO NOTHING, making the empty-result gate unreliable
// (migration 052_multi_source_dedup.sql index comment). We catch
// PG_UNIQUE_VIOLATION (23505) instead — the house idiom.

import logger from "@/server/logger";
import * as Sentry from "@sentry/nextjs";
import { PG_UNIQUE_VIOLATION } from "@/lib/postgres-errors";

interface DedupDbError {
  code?: string;
  message?: string;
}

// Structural subset of SupabaseClient — the real service client satisfies
// it, and tests can pass a minimal mock without the full builder surface.
export interface DedupClient {
  from(table: string): {
    insert(
      row: Record<string, string>,
    ): PromiseLike<{ error: DedupDbError | null }>;
    delete(): {
      eq(
        column: string,
        value: string,
      ): PromiseLike<{ error: DedupDbError | null }>;
    };
  };
}

export interface ClaimResult {
  /** true: this delivery is ours to process. false without `error`: a
   * duplicate (23505) — respond 200 and stop. */
  claimed: boolean;
  /** Set on a non-23505 insert failure — respond 5xx so the sender retries. */
  error?: DedupDbError;
}

export async function claimDelivery(
  client: DedupClient,
  table: string,
  column: string,
  key: string,
): Promise<ClaimResult> {
  const { error } = await client.from(table).insert({ [column]: key });
  if (!error) return { claimed: true };
  if (error.code === PG_UNIQUE_VIOLATION) return { claimed: false };
  return { claimed: false, error };
}

// Mirror of the GitHub route's releaseDedupRow (github/route.ts:175-190):
// on any 5xx after a successful claim, the row MUST be released before
// returning so the sender's redelivery is processed instead of being
// 200-short-circuited as a duplicate. Silently tolerates a DELETE failure
// (logged + Sentry) — the redelivery is the correction mechanism.
export async function releaseDelivery(
  client: DedupClient,
  table: string,
  column: string,
  key: string,
): Promise<void> {
  const { error } = await client.from(table).delete().eq(column, key);
  if (error) {
    logger.error(
      { err: error, table, deliveryKey: key },
      "webhook-dedup: failed to release dedup row on handler error — redelivery will be short-circuited",
    );
    Sentry.captureException(error, {
      tags: { feature: "webhook-dedup", op: "dedup-release" },
      extra: { table, column, key },
    });
  }
}
