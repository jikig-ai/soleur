import { describe, it, expect } from "vitest";

import {
  resolveInitialRouting,
  type ConversationRouting,
  parseConversationRouting,
} from "@/server/conversation-routing";

// RED test for Stage 2.3 of plan 2026-04-23-feat-cc-route-via-soleur-go-plan.md.
//
// `FLAG_CC_SOLEUR_GO` is read exactly once, at conversation creation
// (`start_session`). From that point on, the conversation's routing is
// determined by the persisted `active_workflow` column — NEVER re-read
// from the flag module. Consequences:
//
//   (a) A conversation born while the flag was true stays on the new
//       runner even if the flag flips to false mid-session.
//   (b) A conversation born while the flag was false stays on the legacy
//       router even if the flag flips to true mid-session.
//   (c) Dual-path coexistence: both code paths can run in the same
//       container without a global kill switch breaking in-flight
//       conversations.
//
// Enforcement surface:
//   - `resolveInitialRouting(flag)` is the ONLY function that takes the
//     flag as input. `start_session` calls it once; its output is written
//     to `conversations.active_workflow` via `serializeConversationRouting`.
//   - `parseConversationRouting(row)` takes NO flag argument, by type.
//     The compiler forbids re-reading the flag during `sendUserMessage`.

describe("router-flag-stickiness (Stage 2.3)", () => {
  it("resolveInitialRouting(true) → { kind: 'soleur_go_pending' }", () => {
    expect(resolveInitialRouting(true)).toEqual({ kind: "soleur_go_pending" });
  });

  it("resolveInitialRouting(false) → { kind: 'legacy' }", () => {
    expect(resolveInitialRouting(false)).toEqual({ kind: "legacy" });
  });

  it("parseConversationRouting has no flag parameter — enforced structurally", () => {
    // If a future change adds a second argument, this cast-arity test
    // will fail at compile time. The runtime assertion is a smoke for
    // the structural one.
    expect(parseConversationRouting.length).toBe(1);
  });

  it("a conversation that started on legacy stays on legacy regardless of flag state", () => {
    // Simulate the sendUserMessage read path after a row was persisted
    // when the flag was false.
    const persisted = { active_workflow: null };
    const routing = parseConversationRouting(persisted);
    expect(routing).toEqual({ kind: "legacy" });
    // Flag value is not an input to this decision.
  });

  it("a conversation that started on /soleur:go stays on the new runner regardless of flag state", () => {
    const persisted = { active_workflow: "__unrouted__" };
    const routing: ConversationRouting = parseConversationRouting(persisted);
    expect(routing).toEqual({ kind: "soleur_go_pending" });
  });

  it("a conversation with a detected workflow name stays on that workflow regardless of flag state", () => {
    const persisted = { active_workflow: "brainstorm" };
    const routing = parseConversationRouting(persisted);
    expect(routing).toEqual({ kind: "soleur_go_active", workflow: "brainstorm" });
  });
});
