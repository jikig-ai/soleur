/**
 * `AgentInvocationEnd` — 8-variant discriminated union surfacing the
 * end-of-invocation reason for `startAgentSession` (PR-B §1.5.5 / §1.7).
 *
 * Distinct from `WorkflowEnd` in `soleur-go-runner.ts` (which keys on
 * `status` and is scoped to the cc-soleur-go workflow). This union is
 * per-invocation for the agent-runner: it carries the reason a session
 * stopped ticking — whether due to a guard, a lifecycle gate, an
 * external cancellation, or a subprocess crash.
 *
 * Per type-design F1: the earlier 3-reason enum was provably incomplete
 * (no `cost_kill`, no `byok_invalid`, no `tenant_revoked`) and led to
 * silent fall-through in the runner end-state branch. Each variant
 * carries the minimum payload the consumer needs to render an accurate
 * UI / Sentry event.
 *
 * Per `cq-union-widening-grep-three-patterns`: every consumer must
 * have an `_exhaustive: never` rail. Adding a new variant here without
 * a matching `case` in the rail is a TS build break.
 */

export type AgentInvocationEnd =
  /** Per-block idle window elapsed without an assistant block. Default 90s, resets per block. */
  | { reason: "idle_window"; idleWindowMs: number }
  /** Absolute turn-duration guard fired. Anchored on `firstToolUseAt`, NOT reset by activity. */
  | { reason: "max_turn_duration"; maxTurnDurationMs: number }
  /** SDK `maxTurns` ceiling reached without a terminal assistant block. */
  | { reason: "max_turns"; maxTurns: number }
  /** Per-tenant cost cap tripped via `record_byok_use_and_check_cap` RPC. (§3.5 cost kill-switch.) */
  | {
      reason: "cost_kill";
      capCents: number;
      cumulativeCents: number;
    }
  /** BYOK lease error (fetch / decrypt / scope-escape) at session-start prefetch. */
  | { reason: "byok_invalid" }
  /** Tenant JWT mint refused (rate-limit, denied-jti, secret missing). */
  | { reason: "tenant_revoked" }
  /** External cancellation — operator-initiated abort or founder-initiated abort. */
  | {
      reason: "user_cancelled";
      by: "founder" | "operator";
    }
  /** Anthropic SDK subprocess exited unexpectedly. */
  | {
      reason: "subprocess_crash";
      exitCode: number;
      signal?: string;
    };

/**
 * Exhaustiveness rail (per `cq-union-widening-grep-three-patterns`).
 *
 * Use as `default: assertExhaustiveAgentInvocationEnd(end)` in every
 * `switch (end.reason)` consumer. A new variant added to the union
 * without a `case` here makes TS infer a non-`never` argument — build
 * break, not silent drop.
 */
export function assertExhaustiveAgentInvocationEnd(end: never): never {
  throw new Error(
    `Unhandled AgentInvocationEnd variant: ${JSON.stringify(end)}`,
  );
}
