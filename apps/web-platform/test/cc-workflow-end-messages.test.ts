import { describe, it, expect } from "vitest";

import {
  WORKFLOW_END_USER_MESSAGES,
  WORKSPACE_RECLAIMED_MESSAGE,
  resolveWorktreeEnterFailedMessage,
} from "@/server/cc-workflow-end-messages";

// Relocated from `test/cc-dispatcher.test.ts:723-769` as part of the
// `cc-workflow-end-messages.ts` extraction (#3243, ADR-031).
//
// WORKFLOW_END_USER_MESSAGES — typed exhaustive map replaces the prior
// `Workflow ended (${status}) — retry to continue.` template that
// leaked the internal status enum to users. Compile-time enforcement is
// via `Record<WorkflowEndStatus, string>`; this test pins a runtime
// snapshot + verifies every variant has an entry.

describe("WORKFLOW_END_USER_MESSAGES", () => {
  it("has an entry for every WorkflowEndStatus variant", () => {
    // Variants from the runner's WorkflowEnd union.
    const expectedKeys: ReadonlyArray<string> = [
      "completed",
      "cost_ceiling",
      "runner_runaway",
      "user_aborted",
      "idle_timeout",
      "plugin_load_failure",
      "internal_error",
      // #4440 follow-up to #4418 — cross-process JWT-deny propagation.
      // Routes to the terminal session_ended family via
      // TERMINAL_WORKFLOW_END_STATUSES in cc-dispatcher.ts.
      "session_revoked",
      // #5313 (deferred #5240 FR-half) — worktree-rebind loop guardrail.
      "worktree_enter_failed",
    ];
    const actualKeys = Object.keys(WORKFLOW_END_USER_MESSAGES).sort();
    expect(actualKeys).toEqual([...expectedKeys].sort());

    // `completed` is intentionally empty — that path is handled via the
    // terminal `session_ended` WS event and never produces a user-facing
    // error message.
    expect(WORKFLOW_END_USER_MESSAGES.completed).toBe("");

    // Recoverable branches must surface user-friendly copy without
    // leaking the internal enum.
    expect(WORKFLOW_END_USER_MESSAGES.runner_runaway).toContain(
      "agent went idle",
    );
    expect(WORKFLOW_END_USER_MESSAGES.cost_ceiling).toContain(
      "per-workflow cost cap",
    );
    expect(WORKFLOW_END_USER_MESSAGES.internal_error).toContain(
      "Something went wrong",
    );
    expect(WORKFLOW_END_USER_MESSAGES.session_revoked).toContain(
      "revoked",
    );

    // #5313 AC7 — the worktree-enter failure surfaces an honest, actionable
    // status and NEVER the misleading "Agent stopped responding" banner.
    expect(WORKFLOW_END_USER_MESSAGES.worktree_enter_failed).toContain(
      "workspace",
    );
    expect(WORKFLOW_END_USER_MESSAGES.worktree_enter_failed).not.toContain(
      "Agent stopped responding",
    );

    // Defense-in-depth: NO entry should leak the status token verbatim
    // in a `Workflow ended (...)` template.
    for (const [key, msg] of Object.entries(WORKFLOW_END_USER_MESSAGES)) {
      expect(msg, `key=${key}`).not.toContain("Workflow ended (");
    }
  });
});

// #5340 / #5240 design item #2 — the post-recovery-failure honest message.
// `resolveWorktreeEnterFailedMessage` is the pure routing decision the cc
// `onWorkflowEnded` else-branch consumes: `worktree_enter_failed` routes there
// (it is NOT terminal — see TERMINAL_WORKFLOW_END_STATUSES) and emits a
// `{ type: "error", message }` frame. Which message depends on whether the
// re-provision recovery genuinely failed.
describe("resolveWorktreeEnterFailedMessage — honest reclaimed message gating", () => {
  it("recovery FAILED → the honest 'workspace reclaimed' message", () => {
    expect(resolveWorktreeEnterFailedMessage("failed")).toBe(
      WORKSPACE_RECLAIMED_MESSAGE,
    );
  });

  // PLACEMENT INVARIANT (load-bearing — 2026-06-14-short-circuit-guard-must-sit-
  // after-the-recovery-it-gates.md): the honest "it's gone" message is a
  // POST-recovery-failure concept. A successful/benign recovery ("ok") — or an
  // unresolved outcome (undefined) — must NEVER yield the reclaimed message;
  // it falls through to the generic, retryable copy. This is what proves the
  // branch sits AFTER the recovery, not before it.
  it("recovery 'ok' → the generic retryable worktree-enter copy (NOT the reclaimed message)", () => {
    expect(resolveWorktreeEnterFailedMessage("ok")).toBe(
      WORKFLOW_END_USER_MESSAGES.worktree_enter_failed,
    );
    expect(resolveWorktreeEnterFailedMessage("ok")).not.toBe(
      WORKSPACE_RECLAIMED_MESSAGE,
    );
  });

  it("recovery outcome unresolved (undefined) → generic copy (fail-closed, never a false reclaim)", () => {
    expect(resolveWorktreeEnterFailedMessage(undefined)).toBe(
      WORKFLOW_END_USER_MESSAGES.worktree_enter_failed,
    );
  });

  it("the reclaimed copy is honest + actionable (no internal enum leak, no 'Agent stopped responding')", () => {
    expect(WORKSPACE_RECLAIMED_MESSAGE).toContain("workspace");
    expect(WORKSPACE_RECLAIMED_MESSAGE).not.toContain("Agent stopped responding");
    expect(WORKSPACE_RECLAIMED_MESSAGE).not.toContain("Workflow ended (");
    expect(WORKSPACE_RECLAIMED_MESSAGE).not.toContain("worktree_enter_failed");
  });
});
