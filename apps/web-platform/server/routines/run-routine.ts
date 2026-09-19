// Routine dispatch chokepoint (#5345 PR-1).
//
// THE dispatch site for every USER/AGENT-initiated manual routine run — the
// session route (human), the agent MCP tool (agent), AND the legacy secret
// route (/api/internal/trigger-cron, actorClass="system") all dispatch through
// here. Centralizing means the manualTrigger policy + attribution are enforced
// once and a forged actor cannot bypass them (route-controlled keys spread
// LAST). NB: one trusted in-cron system-cascade (cron-weekly-analytics KPI-miss
// fan-out) still emits *.manual-trigger via a raw inngest.send and does not
// route through here — it is trusted system code and is logged as a manual run
// with a null actor_id.
//
// Scope: fnId MUST be in EXPECTED_CRON_FUNCTIONS — event-driven functions
// (cfo-on-payment-failed et al.) require an event.data payload and are rejected.

import {
  EXPECTED_CRON_FUNCTIONS,
  manualTriggerEventFor,
} from "@/server/inngest/cron-manifest";
import { randomUUID } from "node:crypto";
import { ROUTINE_METADATA } from "@/server/inngest/routine-metadata";
import { sendInngestWithRetry } from "@/server/inngest/send-with-retry";

export type RunRoutineActorClass = "system" | "human" | "agent";

export interface RunRoutineInput {
  fnId: string;
  actorClass: RunRoutineActorClass;
  actorId?: string | null;
  delegatingPrincipal?: string | null;
  /** Bypasses the `confirm` policy when true (UI modal acknowledged / agent review-gate approved / secret tier). */
  confirmed?: boolean;
  /** Per-cron event payload forwarded to the handler (validated by each cron). Spread BEFORE route keys. */
  data?: Record<string, unknown>;
  /** Observability feature tag for sendInngestWithRetry. */
  feature?: string;
  /** Trusted workspace context used by the engine binding repository. */
  workspaceId?: string;
  routineRunId?: string;
  bindRun?: (input: {
    workspaceId: string;
    executionKind: "routine";
    routineId: string;
    routineRunId: string;
    createdBy: string;
  }) => Promise<unknown>;
}

export type RunRoutineResult =
  | { ok: true; event: string }
  | {
      ok: false;
      code: "unknown_routine" | "confirmation_required" | "engine_binding_failed";
      status: 400 | 409 | 503;
    };

const EXPECTED = new Set(EXPECTED_CRON_FUNCTIONS);

export async function runRoutine(
  input: RunRoutineInput,
): Promise<RunRoutineResult> {
  const {
    fnId,
    actorClass,
    actorId = null,
    delegatingPrincipal = null,
    confirmed = false,
    data = {},
    feature = "run-routine",
    workspaceId,
    routineRunId,
    bindRun,
  } = input;
  let eventData = data;

  // Membership check excludes event-driven / one-shot functions.
  if (!EXPECTED.has(fnId)) {
    return { ok: false, code: "unknown_routine", status: 400 };
  }

  // Deny-by-default for protected (financial/egress/deletion) routines.
  const meta = ROUTINE_METADATA[fnId];
  if (meta?.manualTrigger === "confirm" && !confirmed) {
    return { ok: false, code: "confirmation_required", status: 409 };
  }

  const event = manualTriggerEventFor(fnId);
  const trigger =
    actorClass === "agent"
      ? "agent"
      : actorClass === "system"
        ? "manual-api"
        : "manual";

  if (bindRun) {
    if (!workspaceId) {
      return { ok: false, code: "engine_binding_failed", status: 503 };
    }
    const boundRoutineRunId = routineRunId ??
      (typeof data.run_id === "string" ? data.run_id : randomUUID());
    try {
      await bindRun({
        workspaceId,
        executionKind: "routine",
        routineId: fnId,
        routineRunId: boundRoutineRunId,
        createdBy: actorId ?? delegatingPrincipal ?? "system",
      });
    } catch {
      return { ok: false, code: "engine_binding_failed", status: 503 };
    }
    eventData = { ...data, engine_run_id: boundRoutineRunId };
  }

  // The Inngest client is imported dynamically to defer its load-time
  // fail-closed throw (missing INNGEST_SIGNING_KEY) to call time.
  const { inngest } = await import("@/server/inngest/client");
  await sendInngestWithRetry(
    () =>
      inngest.send({
        name: event,
        // Route-controlled attribution keys spread LAST (audit-poison guard):
        // a caller's `data` cannot override actor_class / actor_id / trigger.
        data: {
          ...eventData,
          trigger,
          at: new Date().toISOString(),
          actor_class: actorClass,
          actor_id: actorId,
          delegating_principal: delegatingPrincipal,
        },
      }),
    { feature },
  );

  return { ok: true, event };
}
