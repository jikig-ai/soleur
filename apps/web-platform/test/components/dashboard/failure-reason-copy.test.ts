// PR-B (#4379) AC10 — exhaustive coverage of `FAILURE_REASON_COPY` and
// Retry-eligibility per reason.

import { describe, expect, it } from "vitest";

import {
  FAILURE_REASON_COPY,
  type FailureReason,
} from "@/components/dashboard/failure-reason-copy";

// Source-of-truth list mirrors the FailureReason union. Adding a new
// reason: extend the union, add the row, extend this list. The Record<>
// type forces a copy entry; this list forces a TEST entry.
const ALL_REASONS: FailureReason[] = [
  "github_installation_unauthorized",
  "github_target_not_found",
  "github_api_error",
  "malformed_source_ref",
  "acknowledgment_persist_failed",
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
  // feat-l5-runaway-guard PR-A.
  "run_paused",
  "cap_check_unavailable",
];

describe("FAILURE_REASON_COPY", () => {
  it("covers every reason in the FailureReason union", () => {
    const keys = Object.keys(FAILURE_REASON_COPY).sort();
    expect(keys).toEqual([...ALL_REASONS].sort());
  });

  it.each(ALL_REASONS)(
    "%s: copy is non-empty and does not echo the raw reason key (CPO-2)",
    (reason) => {
      const row = FAILURE_REASON_COPY[reason];
      expect(row.copy.length).toBeGreaterThan(0);
      // No raw `failure_reason` strings should leak into operator copy
      // (e.g., "byok_cap_exceeded" rendered as-is). Per AC22 CPO-2.
      expect(row.copy).not.toContain(reason);
    },
  );

  it.each(ALL_REASONS)(
    "%s: retryEligible is boolean (not undefined)",
    (reason) => {
      const row = FAILURE_REASON_COPY[reason];
      expect(typeof row.retryEligible).toBe("boolean");
    },
  );

  it("Retry eligibility is consistent with AC10 spec table", () => {
    // The plan's AC10 table fixes Retry-eligibility per reason. Pin
    // exact values so a casual edit can't silently flip the button on
    // a reason where retrying is harmful (e.g., anthropic_rate_limited).
    expect(FAILURE_REASON_COPY.byok_cap_exceeded.retryEligible).toBe(false);
    expect(FAILURE_REASON_COPY.cost_ceiling_exceeded.retryEligible).toBe(false);
    expect(FAILURE_REASON_COPY.byok_lease_unavailable.retryEligible).toBe(true);
    expect(FAILURE_REASON_COPY.anthropic_timeout.retryEligible).toBe(true);
    expect(FAILURE_REASON_COPY.anthropic_rate_limited.retryEligible).toBe(
      false,
    );
    expect(FAILURE_REASON_COPY.leader_max_turns_exceeded.retryEligible).toBe(
      false,
    );
    expect(FAILURE_REASON_COPY.leader_response_truncated.retryEligible).toBe(
      true,
    );
    expect(FAILURE_REASON_COPY.leader_tool_invalid.retryEligible).toBe(false);
    expect(FAILURE_REASON_COPY.cancelled_by_operator.retryEligible).toBe(false);
    // PR-A inherited:
    expect(
      FAILURE_REASON_COPY.github_installation_unauthorized.retryEligible,
    ).toBe(false);
    expect(FAILURE_REASON_COPY.github_target_not_found.retryEligible).toBe(
      false,
    );
    expect(FAILURE_REASON_COPY.github_api_error.retryEligible).toBe(true);
    expect(FAILURE_REASON_COPY.malformed_source_ref.retryEligible).toBe(false);
    expect(
      FAILURE_REASON_COPY.acknowledgment_persist_failed.retryEligible,
    ).toBe(false);
    expect(FAILURE_REASON_COPY.leader_class_disabled.retryEligible).toBe(false);
    // feat-l5-runaway-guard: a paused account must be cleared out-of-band
    // (operator resume), and a failed cap-check needs a wait — neither shows
    // an inline Retry.
    expect(FAILURE_REASON_COPY.run_paused.retryEligible).toBe(false);
    expect(FAILURE_REASON_COPY.cap_check_unavailable.retryEligible).toBe(false);
  });

  it("run_paused copy points the operator to resume, not retry", () => {
    expect(FAILURE_REASON_COPY.run_paused.copy).toMatch(/paused|resume/i);
  });

  it("cap_check_unavailable copy reads as transient, not a budget breach", () => {
    expect(FAILURE_REASON_COPY.cap_check_unavailable.copy).not.toMatch(
      /exceeded|over your (cap|budget|limit)/i,
    );
    expect(FAILURE_REASON_COPY.cap_check_unavailable.copy).toMatch(
      /again|moment|temporar/i,
    );
  });

  it("byok_cap_exceeded copy directs operator to raise cap (m4 fix)", () => {
    expect(FAILURE_REASON_COPY.byok_cap_exceeded.copy).toMatch(/raise/i);
  });

  it("cost_ceiling_exceeded copy mentions Undo (partial artifact preserved)", () => {
    expect(FAILURE_REASON_COPY.cost_ceiling_exceeded.copy).toMatch(/undo/i);
  });
});
