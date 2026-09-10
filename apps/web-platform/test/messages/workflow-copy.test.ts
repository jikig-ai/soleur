/**
 * Phase 2.2 (#1055) — Content-shape gates for `WORKFLOW_COPY`.
 *
 * Mirrors `test/messages/action-class-copy.test.ts`. Per-entry assertions via
 * `test.each` so a failure names the offending bucket, not just a matcher diff:
 *   1. non-empty `label`
 *   2. `label` ≤ 28 chars (copy spec §12 budget)
 *   3. no raw-slug leakage — no `.`, `_`, or `-` (the wire values
 *      `drain-labeled-backlog` / `__unrouted__` are all-hyphen/underscore)
 *   4. the label is never the wire value itself
 *   5. labels are unique — two buckets sharing a label makes the breakdown
 *      unreadable and silently merges two spend categories in the reader's head
 *
 * COMPLETENESS IS NOT TESTED HERE. `as const satisfies Record<WorkflowBucket,
 * WorkflowCopy>` in `lib/messages/workflow-copy.ts` makes a missing or extra key
 * a *compile* error, which is strictly stronger than a runtime loop
 * (`action-class-copy.ts` sets the same convention). Plan §Test Scenarios H2:
 * this suite must pass on a REORDERED map with the same key set, so nothing
 * below may depend on key order.
 */

import { describe, expect, test } from "vitest";

import {
  WORKFLOW_COPY,
  WORKFLOW_LABEL_MAX,
  workflowLabel,
  type WorkflowBucket,
} from "@/lib/messages/workflow-copy";

const BUCKETS = Object.keys(WORKFLOW_COPY) as WorkflowBucket[];

describe("WORKFLOW_COPY content shape", () => {
  // TWO floors, because they cover DIFFERENT axes and the plan's G2/H1 rows
  // assumed one covered both.
  //
  //   G2 — the enumeration returns zero members. Caught here: every `test.each`
  //        would silently register zero cases.
  //   H1 — the enumeration is fine but an assertion BODY is emptied. NOT caught
  //        here, and measured: deleting the body of the non-empty-label test
  //        left the suite at 53 passed / exit 0. A member-count floor cannot
  //        see an empty body; only an assertion-count floor can.
  //
  // So each looped case declares `expect.assertions(n)` below. Vitest then
  // fails a case that runs no assertion, which is the mutation H1 describes.
  test("the map is non-empty (dispatch floor — a zero-member loop must never pass silently)", () => {
    expect(BUCKETS.length).toBeGreaterThanOrEqual(8);
  });

  test.each(BUCKETS)("%s has a non-empty label", (b) => {
    expect.assertions(1);
    expect(WORKFLOW_COPY[b].label.trim().length).toBeGreaterThan(0);
  });

  test.each(BUCKETS)(`%s label ≤ ${WORKFLOW_LABEL_MAX} chars`, (b) => {
    expect.assertions(1);
    expect(WORKFLOW_COPY[b].label.length).toBeLessThanOrEqual(
      WORKFLOW_LABEL_MAX,
    );
  });

  test.each(BUCKETS)("%s label leaks no raw-slug characters", (b) => {
    expect.assertions(1);
    expect(WORKFLOW_COPY[b].label).not.toMatch(/[._-]/);
  });

  test.each(BUCKETS)("%s label is not the wire value restated", (b) => {
    expect.assertions(1);
    expect(WORKFLOW_COPY[b].label).not.toBe(b);
  });

  test.each(BUCKETS)("%s label carries no sentinel underscores", (b) => {
    expect.assertions(1);
    expect(WORKFLOW_COPY[b].label).not.toContain("__");
  });

  test("labels are unique across buckets", () => {
    const labels = BUCKETS.map((b) => WORKFLOW_COPY[b].label);
    expect(new Set(labels).size).toBe(labels.length);
  });

  // Intentional duplication of copy spec §12
  // (`knowledge-base/project/specs/feat-restore-byok-usage-dashboard/copy.md`).
  // These strings are an editorial decision with a documented rationale; drift
  // must be an explicit test edit, never an incidental one. `toEqual` on an
  // object is order-independent, so H2 (reordered map) still passes.
  test("every label matches copy spec §12 verbatim", () => {
    expect(
      Object.fromEntries(BUCKETS.map((b) => [b, WORKFLOW_COPY[b].label])),
    ).toEqual({
      "one-shot": "Idea to shipped",
      brainstorm: "Exploring an idea",
      plan: "Planning the work",
      work: "Doing the work",
      review: "Reviewing the code",
      "drain-labeled-backlog": "Clearing the backlog",
      unrouted: "No workflow started",
      legacy: "Before workflow tracking",
    });
  });

  // The migration emits NEUTRAL keys (`legacy`, `unrouted`) precisely so the
  // `__unrouted__` storage sentinel never crosses into TS
  // (136_workflow_cost_rollup.sql, "SENTINEL NORMALISATION").
  test("no map key is a storage sentinel", () => {
    for (const b of BUCKETS) expect(b).not.toContain("__");
  });
});

describe("workflowLabel", () => {
  test.each(BUCKETS)("%s resolves to its editorial label", (b) => {
    expect(workflowLabel(b)).toBe(WORKFLOW_COPY[b].label);
  });

  test("an unmapped bucket falls back to the raw value", () => {
    // Partial deploy: migration 032's CHECK enum widened ahead of the web
    // bundle. Showing the raw key is better than dropping the money; the
    // loader mirrors the event to Sentry (see server/api-usage.ts).
    expect(workflowLabel("drain-prs")).toBe("drain-prs");
  });
});
