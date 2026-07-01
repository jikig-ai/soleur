// TR3 tool-attempt telemetry collector (#5843, parent #5772 lever 2; ADR-070
// amendment). A fail-open, opt-in, web-only instrument that records WHICH
// available tools the cc-soleur-go agent attempts per workflow phase, aggregated
// ONE ROW PER conversation-session into public.tool_attempts, so the
// never-needed-per-phase subset can be computed empirically:
//
//     never-needed-per-phase = available(cc, per-path config) − attempted(observed)
//
// Design (see plan §Architecture Decision / ADR-070 amendment):
//   - AGGREGATED, not insert-per-call: an in-memory closure accumulates counts;
//     ONE jsonb row flushes at query teardown (closeQuery → handleCcCloseQuery).
//     Insert-per-tool-call would add WAL + index write IO on the hot prod agent
//     path for every user (the Disk-IO class 114/115 / PR #5736 addressed).
//   - CLOSURE-scoped accumulator, NOT a module-level Map<sessionId> (HIGH-5):
//     re-identification, leak, and unbounded growth are all structurally absent.
//     A `crypto.randomUUID()` is minted per query purely as an opaque closure
//     identity (debug/trace correlation); it is DELIBERATELY never persisted —
//     the row carries only { counts } so nothing joins to auth.uid() (CRITICAL-2).
//   - Phase tracked on the PreToolUse(Skill) WAY-IN (off-by-one fix): the routed
//     skill's own subsequent tool calls attribute to the NEW phase. Reading
//     `tool_input.skill` (a known enum key) is the SOLE permitted tool_input read
//     and matches the shipped lever-1 hook; it does NOT violate NO-ECHO, which
//     forbids capturing arbitrary tool_input for NON-Skill tools.
//   - NO tool_input for non-Skill tools ever reaches the row/logs/Sentry.
//   - Fail-open everywhere: the hook and flush never throw into the SDK turn;
//     failures mirror to Sentry via reportSilentFallback (debounced upstream).
import { randomUUID } from "node:crypto";
import type { HookCallback, PreToolUseHookInput } from "@anthropic-ai/claude-agent-sdk";
import { createServiceClient } from "@/lib/supabase/service";
import { sanitizeToolNameForLog } from "@/lib/tool-name-sanitize";
import { createChildLogger } from "@/server/logger";
import { reportSilentFallback } from "@/server/observability";
import { skillToPhase } from "@/server/phase-surface-hook";

const log = createChildLogger("tool-attempt-telemetry");

// Tools attempted before the first Skill routing land here (HIGH-6). The router
// itself (the "Concierge" turn) runs under this bucket until it routes.
const UNROUTED_PHASE = "unrouted";

export interface ToolAttemptCollector {
  /** Single fail-open PreToolUse hook: tracks phase on Skill way-in and counts
   *  every attempted tool name under the active phase. Never throws. */
  preToolUseHook: HookCallback;
  /** Insert ONE aggregated jsonb row for the whole session. Fire-and-forget:
   *  never throws; a DB failure mirrors to Sentry. No-op on an empty session. */
  flush(): Promise<void>;
}

/**
 * Build a per-query collector. Mirrors `createPhaseSurfaceHook()`'s factory
 * shape: side-effect-free at build time so a builder-time call inside the
 * `options.hooks` literal can never throw into `query()` startup. All mutable
 * state lives in the returned closures — no module-level state, one collector
 * per cold Query.
 */
export function createToolAttemptCollector(): ToolAttemptCollector {
  // Closure-private accumulator. `randomId` is an OPAQUE trace handle only —
  // NEVER inserted (the row is anonymous; see CRITICAL-2 in the module header).
  const state: {
    readonly randomId: string;
    phase: string;
    counts: Record<string, Record<string, number>>;
  } = {
    randomId: randomUUID(),
    phase: UNROUTED_PHASE,
    counts: {},
  };

  const preToolUseHook: HookCallback = async (input) => {
    try {
      const i = input as PreToolUseHookInput;
      const rawName = i?.tool_name;
      if (typeof rawName !== "string" || rawName.length === 0) return {};

      // Count the attempted tool NAME under the phase active WHEN it was
      // attempted (Skill included — it is an available router tool, and omitting
      // it would falsely mark it "never needed" for the router phase).
      const tool = sanitizeToolNameForLog(rawName);
      const bucket = (state.counts[state.phase] ??= {});
      bucket[tool] = (bucket[tool] ?? 0) + 1;

      // Phase transition on the Skill WAY-IN, AFTER counting Skill under the
      // prior phase. `tool_input.skill` is a known enum key (own-property-gated
      // in skillToPhase) — the sole permitted tool_input read (NO-ECHO exempt).
      if (rawName === "Skill") {
        const skill = (i.tool_input as { skill?: unknown } | null | undefined)?.skill;
        if (typeof skill === "string") {
          const mapped = skillToPhase(skill);
          if (mapped) state.phase = mapped;
        }
      }
      return {};
    } catch (err) {
      // Fail-open: never throw into the SDK turn. STATIC message — no
      // model-controlled value enters the error path.
      log.warn(
        { err, traceId: state.randomId },
        "tool-attempt telemetry hook failed (fail-open)",
      );
      reportSilentFallback(err, {
        feature: "tool-attempt-telemetry",
        op: "preToolUseHook",
      });
      return {};
    }
  };

  async function flush(): Promise<void> {
    try {
      // Nothing attempted → nothing to learn; skip the write (no noise rows).
      if (Object.keys(state.counts).length === 0) return;
      const supabase = createServiceClient();
      const { error } = await supabase
        .from("tool_attempts")
        .insert({ counts: state.counts });
      if (error) throw error;
    } catch (err) {
      log.warn(
        { err, traceId: state.randomId },
        "tool-attempt telemetry flush failed (fail-open)",
      );
      reportSilentFallback(err, {
        feature: "tool-attempt-telemetry",
        op: "flush",
      });
    }
  }

  return { preToolUseHook, flush };
}
