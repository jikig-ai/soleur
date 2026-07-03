// PR-B (#4379) AC11 — Today card state matrix test.
//
// Exhaustive coverage of the 7-row priority table. Pure derivation
// (no React rendering) so the matrix can be verified directly.

import { describe, expect, it } from "vitest";

import {
  deriveTodayCardState,
  LEADER_MAX_TURNS_FOR_DISPLAY,
  type TodayCardActionSendInput,
} from "@/components/dashboard/today-card-state-matrix";

function row(
  overrides: Partial<TodayCardActionSendInput>,
): TodayCardActionSendInput {
  return {
    failure_reason: null,
    reversal_handles: null,
    undone_at: null,
    acknowledged_at: null,
    artifact_url: null,
    cancellation_requested_at: null,
    current_turn: null,
    ...overrides,
  };
}

describe("deriveTodayCardState (AC11)", () => {
  it("Row 1 (failure + reversal_handles): Failed copy + Partial artifact preserved + Undo + Retry per AC10", () => {
    const state = deriveTodayCardState(
      row({
        failure_reason: "cost_ceiling_exceeded",
        reversal_handles: [{ kind: "pr_comment" }],
      }),
    );
    expect(state.kind).toBe("failure_with_artifact");
    expect(state.copy).toMatch(/^Failed —/);
    expect(state.copy).toMatch(/Partial artifact preserved/);
    expect(state.showUndo).toBe(true);
    expect(state.showStop).toBe(false);
    // cost_ceiling_exceeded is NOT Retry-eligible per AC10.
    expect(state.showRetry).toBe(false);
  });

  it("Row 1 with Retry-eligible reason: Retry button shown", () => {
    const state = deriveTodayCardState(
      row({
        failure_reason: "anthropic_timeout",
        reversal_handles: [{ kind: "pr_comment" }],
      }),
    );
    expect(state.kind).toBe("failure_with_artifact");
    expect(state.showRetry).toBe(true);
  });

  it("Row 2 (failure, no artifact): Failed copy without Partial artifact + no Undo", () => {
    const state = deriveTodayCardState(
      row({ failure_reason: "byok_cap_exceeded" }),
    );
    expect(state.kind).toBe("failure_no_artifact");
    expect(state.copy).toMatch(/^Failed —/);
    expect(state.copy).not.toMatch(/Partial artifact preserved/);
    expect(state.showUndo).toBe(false);
    expect(state.showRetry).toBe(false);
  });

  it("Row 2 unknown reason: generic copy, never leaks raw failure_reason (CPO-2 fallback)", () => {
    const state = deriveTodayCardState(
      row({ failure_reason: "future_unknown_reason" }),
    );
    expect(state.kind).toBe("failure_no_artifact");
    expect(state.copy).not.toContain("future_unknown_reason");
  });

  it("Row 3 (undone): renders 'Undone.' regardless of other state", () => {
    const state = deriveTodayCardState(
      row({
        undone_at: "2026-05-25T13:00:00Z",
        acknowledged_at: "2026-05-25T12:55:00Z",
        artifact_url: "https://github.com/acme/repo/issues/7",
      }),
    );
    expect(state.kind).toBe("undone");
    expect(state.copy).toBe("Undone.");
    expect(state.showUndo).toBe(false);
    expect(state.showStop).toBe(false);
  });

  it("Row 4 (done + reversal_handles): Done copy includes artifact URL + Undo button", () => {
    const state = deriveTodayCardState(
      row({
        acknowledged_at: "2026-05-25T12:55:00Z",
        artifact_url: "https://github.com/acme/repo/issues/7#issuecomment-1",
        reversal_handles: [{ kind: "pr_comment" }],
      }),
    );
    expect(state.kind).toBe("done");
    expect(state.copy).toMatch(/^Done —/);
    expect(state.copy).toContain("https://github.com/acme/repo/issues/7#issuecomment-1");
    expect(state.showUndo).toBe(true);
  });

  it("Row 5 (stopping): Stop button shown but disabled; turn number rendered", () => {
    const state = deriveTodayCardState(
      row({
        cancellation_requested_at: "2026-05-25T12:30:00Z",
        current_turn: 3,
      }),
    );
    expect(state.kind).toBe("stopping");
    expect(state.copy).toBe(
      `Stopping — turn 3 of ${LEADER_MAX_TURNS_FOR_DISPLAY}.`,
    );
    expect(state.showStop).toBe(true);
    expect(state.stopDisabled).toBe(true);
  });

  it("Row 6 (working): Stop button enabled; turn number rendered", () => {
    const state = deriveTodayCardState(
      row({
        current_turn: 2,
      }),
    );
    expect(state.kind).toBe("working");
    expect(state.copy).toBe(
      `Working — turn 2 of ${LEADER_MAX_TURNS_FOR_DISPLAY}.`,
    );
    expect(state.showStop).toBe(true);
    expect(state.stopDisabled).toBe(false);
    expect(state.showUndo).toBe(false);
  });

  it("Row 7 (acknowledged starting): pre-turn-1 fallback", () => {
    const state = deriveTodayCardState(row({}));
    expect(state.kind).toBe("acknowledged_starting");
    expect(state.copy).toBe("Acknowledged — agent starting…");
    expect(state.showStop).toBe(false);
    expect(state.showUndo).toBe(false);
  });

  it("Priority: failure_reason wins over acknowledged_at + current_turn (SpecFlow gap silent-drop)", () => {
    // Without priority, a row that BOTH failed AND has acknowledged_at
    // (from a partial earlier turn) could render as "Done". The matrix
    // forbids this by priority.
    const state = deriveTodayCardState(
      row({
        failure_reason: "leader_max_turns_exceeded",
        acknowledged_at: "2026-05-25T12:55:00Z",
        current_turn: 8,
      }),
    );
    expect(state.kind).toBe("failure_no_artifact");
  });

  it("Priority: undone_at wins over acknowledged_at + reversal_handles", () => {
    const state = deriveTodayCardState(
      row({
        undone_at: "2026-05-25T13:10:00Z",
        acknowledged_at: "2026-05-25T12:55:00Z",
        reversal_handles: [{ kind: "pr_comment" }],
        artifact_url: "https://github.com/acme/repo/issues/7",
      }),
    );
    expect(state.kind).toBe("undone");
  });

  it("Priority: cancellation_requested_at without failure_reason renders Row 5 not Row 6", () => {
    const state = deriveTodayCardState(
      row({
        current_turn: 4,
        cancellation_requested_at: "2026-05-25T12:30:00Z",
      }),
    );
    expect(state.kind).toBe("stopping");
  });

  it("CPO-2: no row leaks raw failure_reason as visible text", () => {
    const reasons = [
      "byok_cap_exceeded",
      "cost_ceiling_exceeded",
      "byok_lease_unavailable",
      "anthropic_timeout",
      "anthropic_rate_limited",
      "leader_max_turns_exceeded",
      "leader_response_truncated",
      "leader_tool_invalid",
      "leader_class_disabled",
      "cancelled_by_operator",
      "github_installation_unauthorized",
      "github_target_not_found",
      "github_api_error",
      "malformed_source_ref",
      "acknowledgment_persist_failed",
    ];
    for (const reason of reasons) {
      const state = deriveTodayCardState(row({ failure_reason: reason }));
      expect(state.copy, `failure_reason=${reason}`).not.toContain(reason);
    }
  });

  // feat-l5-runaway-guard PR-A: Resume affordance for the paused-state
  // failure reasons — the only two that set users.runtime_paused_at.
  it.each(["run_paused", "byok_cap_exceeded"])(
    "shows Resume for paused-state reason %s (route reachable in-product)",
    (reason) => {
      const state = deriveTodayCardState(row({ failure_reason: reason }));
      expect(state.showResume).toBe(true);
    },
  );

  it.each([
    "cost_ceiling_exceeded",
    "cap_check_unavailable",
    "cancelled_by_operator",
    "anthropic_timeout",
  ])("does NOT show Resume for non-pausing reason %s", (reason) => {
    const state = deriveTodayCardState(row({ failure_reason: reason }));
    expect(state.showResume).toBe(false);
  });

  it("non-failure states never show Resume", () => {
    expect(deriveTodayCardState(row({ current_turn: 3 })).showResume).toBe(false);
    expect(deriveTodayCardState(row({})).showResume).toBe(false);
  });
});
