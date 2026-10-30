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
//   1. THROWN-ONLY FINAL-ATTEMPT GATE (#5674). onRunError fires on EVERY
//      attempt's thrown result. A cron fails two ways: it THREW (Inngest retries)
//      or it RETURNED { ok:false } (terminal — NO retry under retries:1). Only
//      the THROWN path may be gated on the final attempt (a thrown non-final
//      attempt will retry → suppress the interim write to avoid a double-row). A
//      returned ok:false lands at attempt 0 (non-final) and is NEVER retried, so
//      it MUST be written on the spot — gating it on isFinalAttempt would drop
//      the exact failure we exist to record. So: write on success (terminal), on
//      a returned ok:false (terminal), OR on a FINAL thrown attempt.
//      inngest@4 hands `isFinalAttempt` natively on onRunError — the v3 manual
//      `attempt >= maxAttempts - 1` approximation (and the transformInput ctx
//      capture that fed it) is retired. See
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

import { Middleware } from "inngest";
import * as Sentry from "@sentry/nextjs";
import { getServiceClient } from "@/lib/supabase/service";
import { ROUTINE_METADATA } from "@/server/inngest/routine-metadata";
import { redactCommandForDisplay } from "@/lib/safety/redaction-allowlist";
import { finishRoutineRunProgress } from "@/server/inngest/routine-run-progress";

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

// #5674: error_summary for a handler that RETURNED { ok:false } (without
// throwing). Same firstLine → redact → truncate discipline as errorSummary()
// above, with a non-null fallback so a returned failure with no reason is still
// recorded as failed (never a null error_summary on a failed row).
function formatErrorSummary(summary?: string): string {
  const firstLine = (summary ?? "").split("\n")[0] ?? "";
  const scrubbed = redactCommandForDisplay(firstLine).slice(0, ERROR_SUMMARY_MAX);
  return scrubbed || "cron returned ok:false (see Sentry)";
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

// v4 port (#8628): registered on the client as a CLASS — the SDK instantiates
// one per request, so the per-request captures that lived in the v3
// onFunctionRun closure move to instance fields. The terminal write itself is
// split across the two v4 run-final hooks: onRunComplete (handler returned —
// success OR returned `{ ok:false }`) and onRunError (handler threw — gated on
// the native `isFinalAttempt` flag, which retires v3's manual
// `attempt >= maxAttempts - 1` approximation).
export class RunLogMiddleware extends Middleware.BaseMiddleware {
  readonly id = "routine-run-log";

  // Per-request captures. A fresh instance per request means a retried run's
  // second attempt gets its own startedAtMs — same semantics as the v3
  // transformInput capture (one startedAtMs per request, not per run).
  private fnId: string | null = null;
  private routineRun = false;
  private runId: string | undefined;
  private eventName = "";
  private eventData: Record<string, unknown> = {};
  private startedAtMs = Date.now();

  transformFunctionInput(
    arg: Middleware.TransformFunctionInputArgs,
  ): Middleware.TransformFunctionInputArgs {
    // transformFunctionInput is the first v4 hook handed the full run ctx
    // (event, runId). Membership is resolved here so BOTH run-final hooks can
    // no-op cheaply on non-routine functions without re-reading ctx.
    const fnId = arg.fn.id();
    this.routineRun = fnId in ROUTINE_METADATA;
    if (!this.routineRun) return arg;
    this.fnId = fnId;
    this.runId = arg.ctx.runId;
    this.eventName = arg.ctx.event?.name ?? "";
    this.eventData = (arg.ctx.event?.data ?? {}) as Record<string, unknown>;
    this.startedAtMs = Date.now();
    return arg;
  }

  async onRunComplete(
    arg: Middleware.OnRunCompleteArgs,
  ): Promise<void> {
    if (!this.routineRun || !this.fnId) return;
    // #5674: a RETURNED { ok:false } is terminal — a returned value never
    // retries regardless of `retries:` — so it is written on the spot, never
    // gated on a final-attempt signal (that was the P0 regression the first
    // plan draft codified).
    const output = arg.output as
      | { ok?: boolean; errorSummary?: string }
      | undefined;
    const failed = output?.ok === false;
    await this.writeTerminalRow({
      failed,
      errorSummary: failed ? formatErrorSummary(output?.errorSummary) : null,
    });
  }

  async onRunError(arg: Middleware.OnRunErrorArgs): Promise<void> {
    if (!this.routineRun || !this.fnId) return;
    // Gate ONLY the thrown path: a thrown error on a non-final attempt will
    // retry, so suppress the interim write (avoids a double-row on a
    // fail-then-succeed run). v4 hands the flag natively.
    if (!arg.isFinalAttempt) return;
    await this.writeTerminalRow({
      failed: true,
      errorSummary: errorSummary(arg.error),
    });
  }

  private async writeTerminalRow(args: {
    failed: boolean;
    errorSummary: string | null;
  }): Promise<void> {
    const fnId = this.fnId;
    const runId = this.runId;
    if (!fnId || !runId) return;
    const endedAtMs = Date.now();
    const attribution = deriveAttribution(this.eventName, this.eventData);
    try {
      await getServiceClient().rpc("write_routine_run", {
        p_routine_id: fnId,
        p_run_id: runId,
        p_status: args.failed ? "failed" : "completed",
        p_trigger_source: attribution.triggerSource,
        p_actor_class: attribution.actorClass,
        p_actor_id: attribution.actorId,
        p_delegating_principal: attribution.delegatingPrincipal,
        p_started_at: new Date(this.startedAtMs).toISOString(),
        p_ended_at: new Date(endedAtMs).toISOString(),
        p_duration_ms: Math.max(0, endedAtMs - this.startedAtMs),
        p_error_summary: args.errorSummary,
      });
      // #5766: the terminal row landed — delete the live-state row (a run
      // that reaches here is no longer in-flight). Placed AFTER the write
      // resolves and INSIDE the try (arch-A-2 / DI-P1-C): if write_routine_run
      // threw, we skip this and the live row survives so the reader shows
      // "stuck" instead of vanishing the run. finishRoutineRunProgress is
      // itself fail-soft (own Sentry mirror), so it never poisons the write
      // path. A no-op (0 rows) for light crons that never wrote a live row.
      await finishRoutineRunProgress(runId);
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
  }
}
