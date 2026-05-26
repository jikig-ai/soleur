// Storage-boundary ADT for the Command Center `/soleur:go` runner.
//
// Plan: knowledge-base/project/plans/2026-04-23-feat-cc-route-via-soleur-go-plan.md
// (Stage 2). Migration 032 adds `active_workflow text NULL` with a CHECK
// constraint enumerating the valid wire-format set:
//
//   NULL                  → legacy router (agent-runner.ts code path)
//   '__unrouted__'        → /soleur:go runner started, no workflow selected
//   <WorkflowName>        → /soleur:go runner dispatched into a workflow
//
// This module is the ONLY translator between the wire format
// (`conversations.active_workflow`) and the richer discriminated-union ADT
// consumed by ws-handler.ts and soleur-go-runner.ts. The `__unrouted__`
// sentinel is a storage-layer detail; it must never leak past this module.
// Callers construct pending state via `{ kind: "soleur_go_pending" }`.
//
// COUPLING INVARIANT: `WorkflowName` below must match migration 032's
// `conversations_active_workflow_chk` CHECK enum verbatim (minus the
// sentinel, which is a separate ADT kind). Drift between this union and
// the CHECK clause produces asymmetric rejection: inserts fail at the DB
// boundary, but `parseConversationRouting` widening would silently surface
// invalid routing state. The file-parse test at
// test/supabase-migrations/032-workflow-state.test.ts pins the DB side;
// the round-trip tests at test/conversation-routing.test.ts pin this side.

export type WorkflowName =
  | "one-shot"
  | "brainstorm"
  | "plan"
  | "work"
  | "review"
  | "drain-labeled-backlog";

export type ConversationRouting =
  | { kind: "legacy" }
  | { kind: "soleur_go_pending" }
  | { kind: "soleur_go_active"; workflow: WorkflowName };

// Private to this module — not exported. See file header for rationale.
const SENTINEL_UNROUTED = "__unrouted__";

const WORKFLOW_NAMES: ReadonlySet<WorkflowName> = new Set<WorkflowName>([
  "one-shot",
  "brainstorm",
  "plan",
  "work",
  "review",
  "drain-labeled-backlog",
]);

function isWorkflowName(value: string): value is WorkflowName {
  return (WORKFLOW_NAMES as ReadonlySet<string>).has(value);
}

export function parseConversationRouting(row: {
  active_workflow: string | null;
}): ConversationRouting {
  const raw = row.active_workflow;
  if (raw === null) return { kind: "legacy" };
  if (raw === SENTINEL_UNROUTED) return { kind: "soleur_go_pending" };
  if (isWorkflowName(raw)) return { kind: "soleur_go_active", workflow: raw };
  throw new Error(
    `parseConversationRouting: unknown active_workflow value (possible CHECK-constraint drift or tampered row)`,
  );
}

export function serializeConversationRouting(
  routing: ConversationRouting,
): string | null {
  switch (routing.kind) {
    case "legacy":
      return null;
    case "soleur_go_pending":
      return SENTINEL_UNROUTED;
    case "soleur_go_active":
      return routing.workflow;
    default: {
      const _exhaustive: never = routing;
      void _exhaustive;
      throw new Error("serializeConversationRouting: non-exhaustive match");
    }
  }
}
