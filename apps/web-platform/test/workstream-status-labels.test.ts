import { describe, expect, it } from "vitest";
import {
  computeStatusLabels,
  deriveColumn,
  STATUS_LABELS,
  STATUS_WRITE_LABEL,
  type BoardIssueInput,
  type WorkstreamStatus,
} from "@/lib/workstream";

// AC12 — the status-label REMOVAL vocabulary is single-sourced with
// deriveColumn's READ set (no alias drift), and AC13 — the deriveColumn
// round-trip: writing a target column's label yields that column on the next
// read.

function open(labels: string[]): BoardIssueInput {
  return {
    number: 1,
    title: "t",
    body: null,
    assignees: [],
    labels,
    state: "open",
    state_reason: null,
    created_at: "2026-07-10T00:00:00Z",
    updated_at: "2026-07-10T00:00:00Z",
  };
}

describe("status-label vocabulary (AC12: write-set ≡ read-set)", () => {
  // The exact label set deriveColumn's OPEN branch inspects. If deriveColumn
  // gains/loses a status label without updating STATUS_LABELS, this drifts.
  const READ_SET = [
    "blocked",
    "pending",
    "in-progress",
    "review",
    "needs-review",
    "ready",
    "todo",
  ];

  it("STATUS_LABELS equals deriveColumn's read set (order-independent)", () => {
    expect([...STATUS_LABELS].sort()).toEqual([...READ_SET].sort());
  });

  it("every column write-label is a member of the removal set", () => {
    for (const label of Object.values(STATUS_WRITE_LABEL)) {
      expect(STATUS_LABELS).toContain(label);
    }
  });

  it("each read-set label actually moves deriveColumn off backlog (it IS read)", () => {
    for (const label of STATUS_LABELS) {
      expect(deriveColumn(open([label]))).not.toBe("backlog");
    }
  });

  it("a non-status label never moves deriveColumn off backlog (nothing extra is read)", () => {
    expect(deriveColumn(open(["domain/engineering", "priority/p1-high"]))).toBe(
      "backlog",
    );
  });
});

describe("computeStatusLabels + round-trip (AC13)", () => {
  it("round-trips every non-terminal column through its write-label", () => {
    const columns: WorkstreamStatus[] = [
      "ready",
      "in_progress",
      "in_review",
      "blocked",
      "pending",
    ];
    for (const col of columns) {
      const labels = computeStatusLabels([], col);
      expect(deriveColumn(open(labels))).toBe(col);
    }
  });

  it("backlog writes no status label (bare removal)", () => {
    expect(computeStatusLabels(["in-progress"], "backlog")).toEqual([]);
    expect(deriveColumn(open(computeStatusLabels(["in-progress"], "backlog")))).toBe(
      "backlog",
    );
  });

  it("preserves non-status labels and drops ALL prior status labels", () => {
    const next = computeStatusLabels(
      ["domain/engineering", "in-progress", "blocked", "priority/p0-critical"],
      "in_review",
    );
    expect(next).toContain("domain/engineering");
    expect(next).toContain("priority/p0-critical");
    expect(next).toContain("review");
    expect(next).not.toContain("in-progress");
    expect(next).not.toContain("blocked");
    // exactly one status label survives
    expect(next.filter((l) => STATUS_LABELS.includes(l))).toEqual(["review"]);
  });

  it("in_review writes 'review' (which derives back to in_review)", () => {
    expect(STATUS_WRITE_LABEL.in_review).toBe("review");
    expect(deriveColumn(open(["review"]))).toBe("in_review");
  });
});
