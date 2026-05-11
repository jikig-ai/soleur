import { describe, it, expect } from "vitest";

import {
  type ConversationRouting,
  parseConversationRouting,
} from "@/server/conversation-routing";

// Stickiness invariant for the Command Center `/soleur:go` router.
//
// `parseConversationRouting(row)` is the ONLY routing decision on turn 2+.
// Its sole input is the persisted `conversations.active_workflow` column
// — by type it takes no flag, no env, no config. Consequences:
//
//   (a) A row with `active_workflow IS NULL` is invariably routed to
//       `{ kind: "legacy" }`. No future flag, config, or rollout knob
//       can re-route it. The DB column is the source of truth.
//   (b) A row with `active_workflow = '__unrouted__'` is invariably
//       routed to `{ kind: "soleur_go_pending" }`.
//   (c) A row with a workflow name is invariably routed to
//       `{ kind: "soleur_go_active", workflow }`.
//
// This invariant is what makes turn-2+ routing deterministic and
// idempotent. It used to be paired with `resolveInitialRouting(flag)` —
// the start_session-time flag-to-routing adapter — but the adapter was
// removed in #3270 once FLAG_CC_SOLEUR_GO was retired (cc-soleur-go is
// now the unconditional production binding). The stickiness invariant
// itself is unchanged: the DB column dictates routing on every read.

describe("router stickiness invariant (active_workflow → ConversationRouting)", () => {
  it("parseConversationRouting has no flag parameter — enforced structurally", () => {
    // If a future change adds a second argument, this cast-arity test
    // will fail at compile time. The runtime assertion is a smoke for
    // the structural one.
    expect(parseConversationRouting.length).toBe(1);
  });

  it("a row with active_workflow=NULL is invariably { kind: 'legacy' }", () => {
    const persisted = { active_workflow: null };
    const routing = parseConversationRouting(persisted);
    expect(routing).toEqual({ kind: "legacy" });
  });

  it("a row with active_workflow='__unrouted__' is invariably { kind: 'soleur_go_pending' }", () => {
    const persisted = { active_workflow: "__unrouted__" };
    const routing: ConversationRouting = parseConversationRouting(persisted);
    expect(routing).toEqual({ kind: "soleur_go_pending" });
  });

  it("a row with a workflow name is invariably { kind: 'soleur_go_active', workflow }", () => {
    const persisted = { active_workflow: "brainstorm" };
    const routing = parseConversationRouting(persisted);
    expect(routing).toEqual({ kind: "soleur_go_active", workflow: "brainstorm" });
  });
});
