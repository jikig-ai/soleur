/**
 * Type-level + runtime tests for `AgentInvocationEnd` (PR-B §1.5.5 /
 * type-design F1). Asserts:
 *   1. Exhaustive switch handles all 8 variants.
 *   2. Adding an unhandled variant fails the rail (runtime simulation).
 *   3. Each variant carries the documented payload shape.
 */
import { describe, expect, it } from "vitest";

import {
  AgentInvocationEnd,
  assertExhaustiveAgentInvocationEnd,
} from "@/server/agent-invocation-end";

function describeEnd(end: AgentInvocationEnd): string {
  switch (end.reason) {
    case "idle_window":
      return `idle ${end.idleWindowMs}ms`;
    case "max_turn_duration":
      return `max-turn ${end.maxTurnDurationMs}ms`;
    case "max_turns":
      return `max-turns ${end.maxTurns}`;
    case "cost_kill":
      return `cost ${end.cumulativeCents}/${end.capCents}`;
    case "byok_invalid":
      return "byok-invalid";
    case "tenant_revoked":
      return "tenant-revoked";
    case "user_cancelled":
      return `cancelled-by-${end.by}`;
    case "subprocess_crash":
      return `crash-${end.exitCode}${end.signal ? `-${end.signal}` : ""}`;
    default:
      // Compile-time exhaustiveness rail.
      return assertExhaustiveAgentInvocationEnd(end);
  }
}

describe("AgentInvocationEnd — 8-variant discriminated union", () => {
  it("describes every documented variant without falling through", () => {
    const cases: { input: AgentInvocationEnd; expected: string }[] = [
      { input: { reason: "idle_window", idleWindowMs: 90000 }, expected: "idle 90000ms" },
      {
        input: { reason: "max_turn_duration", maxTurnDurationMs: 600000 },
        expected: "max-turn 600000ms",
      },
      { input: { reason: "max_turns", maxTurns: 30 }, expected: "max-turns 30" },
      {
        input: { reason: "cost_kill", capCents: 2000, cumulativeCents: 2100 },
        expected: "cost 2100/2000",
      },
      { input: { reason: "byok_invalid" }, expected: "byok-invalid" },
      { input: { reason: "tenant_revoked" }, expected: "tenant-revoked" },
      {
        input: { reason: "user_cancelled", by: "founder" },
        expected: "cancelled-by-founder",
      },
      {
        input: { reason: "user_cancelled", by: "operator" },
        expected: "cancelled-by-operator",
      },
      {
        input: { reason: "subprocess_crash", exitCode: 137, signal: "SIGKILL" },
        expected: "crash-137-SIGKILL",
      },
      {
        input: { reason: "subprocess_crash", exitCode: 1 },
        expected: "crash-1",
      },
    ];

    for (const { input, expected } of cases) {
      expect(describeEnd(input)).toBe(expected);
    }
  });

  it("rail throws when an unknown variant slips past the switch (runtime sim)", () => {
    // Cast through `unknown` so we can exercise the rail at runtime; the
    // compile-time guarantee is the load-bearing one (build break on a
    // new variant), but the rail also throws if a runtime-shaped object
    // arrives via wire/IPC.
    const fake = { reason: "schema_drift" } as unknown as AgentInvocationEnd;
    expect(() => describeEnd(fake)).toThrow(/Unhandled AgentInvocationEnd/);
  });
});
