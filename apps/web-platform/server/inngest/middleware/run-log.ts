// Inngest → routine_runs run-log middleware (#5345 PR-1).
//
// Applied once at server/inngest/client.ts (after sentry-correlation); runs on
// every function invocation. For EXPECTED_CRON_FUNCTIONS crons ONLY (membership
// via ROUTINE_METADATA — event-driven fns like cfo-on-payment-failed are
// skipped), it writes ONE terminal row per run to public.routine_runs via the
// service-role write_routine_run RPC.
//
// Two load-bearing invariants (5-agent plan-review):
//
//   1. FINAL-ATTEMPT GATE. transformOutput fires on EVERY attempt's final
//      result, not just the last. Writing unconditionally would append a
//      `failed` row on attempt 0 AND a `completed` row on attempt 1 for a
//      fail-then-succeed run. So: write on success (always terminal) OR on a
//      FINAL failed attempt (attempt >= maxAttempts-1). Fail-SAFE to write when
//      attempt data is absent (attempt=0/maxAttempts=1 → final). Mirrors the
//      Sentry-heartbeat gate in _cron-shared.ts. See
//      knowledge-base/.../2026-06-12-inngest-cron-heartbeat-gate-on-final-attempt-and-step-memoization.md
//
//   2. ATTRIBUTION FROM event.name, NOT caller data. trigger_source is derived
//      from the event NAME (`*.manual-trigger` ⇒ manual/agent; otherwise
//      scheduled/system) so a forged data.actor_class cannot make a manual run
//      look scheduled. The actor_class/id come from runRoutine's route-controlled
//      keys. runRoutine is the producer for all USER/AGENT-initiated manual
//      triggers; one trusted system-cascade (cron-weekly-analytics KPI-miss
//      fan-out) still emits *.manual-trigger via a raw inngest.send and is
//      logged actor_class:"human"/actor_id:null — acceptable (trusted system
//      code), noted so the "only producer" claim isn't read as absolute.
//
// Fail-soft: a write failure mirrors to Sentry (cq-silent-fallback-must-mirror-
// to-sentry) and NEVER throws into the handler (no retry-poisoning).

import { InngestMiddleware } from "inngest";
import * as Sentry from "@sentry/nextjs";
import { getServiceClient } from "@/lib/supabase/service";
import { ROUTINE_METADATA } from "@/server/inngest/routine-metadata";
import { redactCommandForDisplay } from "@/lib/safety/redaction-allowlist";

const ERROR_SUMMARY_MAX = 500;

function errorSummary(err: unknown): string {
  const msg = err instanceof Error ? err.message : String(err);
  // First line only (avoid stack/payload) + SECRET/PII redaction (the row is
  // WORM — a leaked credential in an error message would be permanent and is
  // NOT touched by anonymise_routine_runs). Redact BEFORE truncating so a
  // credential straddling the 500-char boundary is still caught. The four
  // legal-doc disclosures describe error_summary as "scrubbed + truncated";
  // this is the scrub. Reuses the same allowlist as the command-stream emit
  // boundary (tokens, JWTs, conn-string passwords, emails, UUIDs, IPs).
  const firstLine = msg.split("\n")[0] ?? "";
  return redactCommandForDisplay(firstLine).slice(0, ERROR_SUMMARY_MAX);
}

interface Attribution {
  triggerSource: "scheduled" | "manual" | "agent";
  actorClass: "system" | "human" | "agent";
  actorId: string | null;
  delegatingPrincipal: string | null;
}

function deriveAttribution(
  eventName: string,
  data: Record<string, unknown>,
): Attribution {
  // Derive from the event NAME, never trust data for trigger_source.
  if (!eventName.endsWith(".manual-trigger")) {
    return {
      triggerSource: "scheduled",
      actorClass: "system",
      actorId: null,
      delegatingPrincipal: null,
    };
  }
  // actor_class is authoritative — runRoutine is the only producer of
  // manual-trigger events and spreads it route-LAST (a caller cannot forge it).
  // Validate against the known set; fall back to "human".
  const ac = data.actor_class;
  const actorClass: Attribution["actorClass"] =
    ac === "agent" || ac === "system" ? ac : "human";
  const actorId = typeof data.actor_id === "string" ? data.actor_id : null;
  const delegatingPrincipal =
    typeof data.delegating_principal === "string"
      ? data.delegating_principal
      : null;
  return {
    // A manual-trigger event is never "scheduled". Agent runs read as "agent";
    // human + system (secret-CLI) runs both read as "manual".
    triggerSource: actorClass === "agent" ? "agent" : "manual",
    actorClass,
    actorId,
    delegatingPrincipal,
  };
}

export const runLogMiddleware = new InngestMiddleware({
  name: "routine-run-log",
  init() {
    return {
      onFunctionRun({ ctx, fn }) {
        const fnId = fn.id();
        // Only EXPECTED_CRON_FUNCTIONS crons are logged.
        if (!(fnId in ROUTINE_METADATA)) return {};

        const runId = ctx.runId;
        const eventName = ctx.event.name;
        const eventData = (ctx.event.data ?? {}) as Record<string, unknown>;
        // attempt / maxAttempts are NOT on onFunctionRun's ctx — that ctx is
        // Inngest's InitialRunInfo ({ event, runId } only; "does not necessarily
        // contain all the data"). The retry-attempt fields live on BaseContext,
        // which is only handed to transformInput. Reading them off the
        // onFunctionRun ctx silently yields undefined → the final-attempt gate
        // degrades to always-write (double-rows on retried runs). Capture them
        // in transformInput, which receives the full run ctx.
        let attempt = 0;
        let maxAttempts = 1;
        let startedAtMs = Date.now();

        return {
          transformInput({
            ctx: runCtx,
          }: {
            ctx: { attempt?: number; maxAttempts?: number };
          }) {
            startedAtMs = Date.now();
            attempt = runCtx.attempt ?? 0;
            maxAttempts = runCtx.maxAttempts ?? 1;
          },
          async transformOutput({
            result,
            step,
          }: {
            result: { error?: unknown; data?: unknown };
            step?: unknown;
          }) {
            if (step) return; // step-level event — only the function-final result lands a row
            const failed = result.error != null;
            const isFinalAttempt = attempt >= maxAttempts - 1;
            // FINAL-ATTEMPT GATE: success is always terminal; a failed
            // non-final attempt will retry → do not write (avoids double-row).
            if (failed && !isFinalAttempt) return;

            const endedAtMs = Date.now();
            const attribution = deriveAttribution(eventName, eventData);
            try {
              await getServiceClient().rpc("write_routine_run", {
                p_routine_id: fnId,
                p_run_id: runId,
                p_status: failed ? "failed" : "completed",
                p_trigger_source: attribution.triggerSource,
                p_actor_class: attribution.actorClass,
                p_actor_id: attribution.actorId,
                p_delegating_principal: attribution.delegatingPrincipal,
                p_started_at: new Date(startedAtMs).toISOString(),
                p_ended_at: new Date(endedAtMs).toISOString(),
                p_duration_ms: Math.max(0, endedAtMs - startedAtMs),
                p_error_summary: failed ? errorSummary(result.error) : null,
              });
            } catch (e) {
              // Fail-soft: mirror to Sentry, never propagate (no retry-poisoning).
              try {
                Sentry.captureException(
                  e instanceof Error ? e : new Error(String(e)),
                  { tags: { surface: "routine-run-log", "inngest.fn_id": fnId } },
                );
              } catch {
                // captureException failure must not propagate either.
              }
            }
          },
        };
      },
    };
  },
});
