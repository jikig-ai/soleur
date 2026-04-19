import { createServiceClient } from "@/lib/supabase/service";
import { createChildLogger } from "./logger";
import { reportSilentFallback } from "./observability";
import * as Sentry from "@sentry/nextjs";
import type { PlanTier } from "@/lib/types";

const log = createChildLogger("concurrency");

/** Five fields per plan FR9 (original spec). The 6 CFO-memo additions are
 *  deferred to #2626 and intentionally omitted. */
export interface ConcurrencyCapHitEvent {
  tier: PlanTier;
  active_conversation_count: number;
  effective_cap: number;
  /** Where the deny was triggered. */
  path: "start_session" | "downgrade_sweep" | "hard_cap_24h";
  /** What the user did after the deny. Default "abandoned" if no follow-up
   *  within 30s (client is expected to update via explicit event when the
   *  modal CTA fires — not implemented in v1, so always "abandoned" for now). */
  action: "abandoned" | "upgraded" | "waited";
}

/**
 * Emit a `concurrency_cap_hit` telemetry event. In v1 we log + add a Sentry
 * breadcrumb so the 5-field shape is observable in both log aggregators and
 * Sentry. Forwarding to Plausible via the server-side channel is wired in a
 * follow-up (#2626 telemetry expansion).
 */
export function emitConcurrencyCapHit(event: ConcurrencyCapHitEvent): void {
  log.info({ event: "concurrency_cap_hit", ...event }, "concurrency_cap_hit");
  Sentry.addBreadcrumb({
    category: "concurrency",
    level: "info",
    message: "concurrency_cap_hit",
    data: { ...event },
  });
}

export interface AcquireSlotResult {
  status: "ok" | "cap_hit" | "error";
  activeCount: number;
  effectiveCap: number;
}

const supabase = createServiceClient();

/** Transient Postgres error SQLSTATEs that warrant a single retry:
 *  40P01 deadlock_detected, 55P03 lock_not_available. */
const TRANSIENT_SQLSTATES = new Set(["40P01", "55P03"]);

function isTransient(err: unknown): boolean {
  const code = (err as { code?: string } | null)?.code;
  return typeof code === "string" && TRANSIENT_SQLSTATES.has(code);
}

async function delay(ms: number): Promise<void> {
  await new Promise<void>((r) => setTimeout(r, ms));
}

/**
 * Call the acquire_conversation_slot RPC with bounded jittered retry for
 * deadlock / lock-timeout. Never throws — callers treat `status: "error"`
 * as fail-closed per plan §Risks.
 */
export async function acquireSlot(
  userId: string,
  conversationId: string,
  effectiveCap: number,
): Promise<AcquireSlotResult> {
  for (let attempt = 0; attempt < 3; attempt++) {
    const { data, error } = await supabase.rpc("acquire_conversation_slot", {
      p_user_id: userId,
      p_conversation_id: conversationId,
      p_effective_cap: effectiveCap,
    });
    if (!error && data) {
      const row = Array.isArray(data) ? data[0] : data;
      if (row && typeof row === "object") {
        return {
          status: (row as { status?: string }).status === "cap_hit" ? "cap_hit" : "ok",
          activeCount: (row as { active_count?: number }).active_count ?? 0,
          effectiveCap: (row as { effective_cap?: number }).effective_cap ?? effectiveCap,
        };
      }
    }
    if (error && isTransient(error) && attempt < 2) {
      await delay(80 + Math.random() * 40); // 80–120 ms jitter
      continue;
    }
    if (error) {
      reportSilentFallback(error, {
        feature: "concurrency",
        op: "acquireSlot",
        extra: { userId, conversationId, effectiveCap, attempt },
      });
      return { status: "error", activeCount: 0, effectiveCap };
    }
  }
  return { status: "error", activeCount: 0, effectiveCap };
}

/**
 * Call the release_conversation_slot RPC. Best-effort: errors are logged
 * + mirrored to Sentry but not re-thrown, because the pg_cron sweep is the
 * correctness guarantee and the caller is usually a teardown path.
 */
export async function releaseSlot(
  userId: string,
  conversationId: string,
): Promise<void> {
  try {
    const { error } = await supabase.rpc("release_conversation_slot", {
      p_user_id: userId,
      p_conversation_id: conversationId,
    });
    if (error) {
      reportSilentFallback(error, {
        feature: "concurrency",
        op: "releaseSlot",
        extra: { userId, conversationId },
      });
    }
  } catch (err) {
    reportSilentFallback(err, {
      feature: "concurrency",
      op: "releaseSlot",
      extra: { userId, conversationId },
    });
  }
}
