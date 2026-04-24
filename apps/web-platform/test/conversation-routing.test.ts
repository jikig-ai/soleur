import { describe, it, expect } from "vitest";
import {
  parseConversationRouting,
  serializeConversationRouting,
  type ConversationRouting,
  type WorkflowName,
} from "@/server/conversation-routing";

// RED test for Stage 2.1 of plan 2026-04-23-feat-cc-route-via-soleur-go-plan.md.
//
// Contract (see plan Stage 2 §"Files to create" and migration 032):
//   - `null`                         ↔ { kind: "legacy" }
//   - `"__unrouted__"` sentinel      ↔ { kind: "soleur_go_pending" }
//   - <WorkflowName>                 ↔ { kind: "soleur_go_active", workflow }
//
// WorkflowName must match migration 032's CHECK enum verbatim (minus the
// '__unrouted__' sentinel which is a separate ADT kind, not a workflow).
//
// Invariant under test: the `__unrouted__` magic string never appears in
// the output of `parseConversationRouting` — it is translated into the
// `soleur_go_pending` variant and never re-exposed as a raw string
// (per plan: "Magic string never leaks past this module").

const WORKFLOW_NAMES: ReadonlyArray<WorkflowName> = [
  "one-shot",
  "brainstorm",
  "plan",
  "work",
  "review",
  "drain-labeled-backlog",
];

describe("conversation-routing ADT", () => {
  describe("parseConversationRouting", () => {
    it("maps null → { kind: 'legacy' }", () => {
      expect(parseConversationRouting({ active_workflow: null })).toEqual({
        kind: "legacy",
      });
    });

    it("maps '__unrouted__' sentinel → { kind: 'soleur_go_pending' }", () => {
      expect(
        parseConversationRouting({ active_workflow: "__unrouted__" }),
      ).toEqual({ kind: "soleur_go_pending" });
    });

    it.each(WORKFLOW_NAMES)(
      "maps workflow name '%s' → { kind: 'soleur_go_active', workflow }",
      (name) => {
        expect(parseConversationRouting({ active_workflow: name })).toEqual({
          kind: "soleur_go_active",
          workflow: name,
        });
      },
    );

    it("never surfaces the '__unrouted__' magic string in output", () => {
      // Sentinel-leak guard. A caller that stringifies the ADT must never
      // see the wire-format sentinel; it must always be translated into a
      // discriminated variant at the storage boundary.
      const inputs: ReadonlyArray<string | null> = [
        null,
        "__unrouted__",
        ...WORKFLOW_NAMES,
      ];
      for (const input of inputs) {
        const result = parseConversationRouting({ active_workflow: input });
        expect(JSON.stringify(result)).not.toContain("__unrouted__");
      }
    });

    it("rejects unknown active_workflow values", () => {
      // Values outside the CHECK-constraint allowlist indicate tamper,
      // migration drift, or a widened TS union that desynced from the DB.
      // Fail loudly rather than silently bucketing into 'legacy' — the
      // caller (ws-handler.ts) decides fallback policy.
      expect(() =>
        parseConversationRouting({ active_workflow: "not-a-workflow" }),
      ).toThrow();
    });

    it("rejects the empty string", () => {
      // Empty string is not a valid sentinel nor a valid workflow name;
      // defend against accidental "" coalescing at the storage boundary.
      expect(() =>
        parseConversationRouting({ active_workflow: "" }),
      ).toThrow();
    });
  });

  describe("serializeConversationRouting", () => {
    it("serializes { kind: 'legacy' } → null", () => {
      expect(serializeConversationRouting({ kind: "legacy" })).toBeNull();
    });

    it("serializes { kind: 'soleur_go_pending' } → '__unrouted__'", () => {
      expect(
        serializeConversationRouting({ kind: "soleur_go_pending" }),
      ).toBe("__unrouted__");
    });

    it.each(WORKFLOW_NAMES)(
      "serializes { kind: 'soleur_go_active', workflow: '%s' } → '%s'",
      (name) => {
        expect(
          serializeConversationRouting({
            kind: "soleur_go_active",
            workflow: name,
          }),
        ).toBe(name);
      },
    );
  });

  describe("round-trip", () => {
    const routings: ReadonlyArray<ConversationRouting> = [
      { kind: "legacy" },
      { kind: "soleur_go_pending" },
      ...WORKFLOW_NAMES.map(
        (workflow): ConversationRouting => ({
          kind: "soleur_go_active",
          workflow,
        }),
      ),
    ];

    it.each(routings)(
      "round-trips $kind via serialize → parse",
      (routing) => {
        const wire = serializeConversationRouting(routing);
        const parsed = parseConversationRouting({ active_workflow: wire });
        expect(parsed).toEqual(routing);
      },
    );
  });

  describe("sentinel encapsulation", () => {
    it("does not export SENTINEL_UNROUTED from the module", async () => {
      // The sentinel is a storage-layer implementation detail. Callers
      // must construct pending-state via { kind: 'soleur_go_pending' },
      // not by importing the raw string. Enforces the plan's
      // "Magic string never leaks past this module" invariant.
      const mod = await import("@/server/conversation-routing");
      expect(Object.keys(mod)).not.toContain("SENTINEL_UNROUTED");
    });
  });
});
