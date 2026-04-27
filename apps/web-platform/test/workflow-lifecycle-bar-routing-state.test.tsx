/**
 * Stage 4 (#2886) — RED tests for routing-state timing & skill-name extraction.
 *
 * Per plan §4.2: routing state must render within 8s of user-message
 * timestamp. Uses `vi.setSystemTime` for determinism per
 * `cq-raf-batching-sweep-test-helpers`. The bar itself is synchronous —
 * the timing assertion is on the wall-clock budget for the reducer +
 * render path; a unit-level proxy is "render time stays under tolerance"
 * which is brittle in jsdom. Instead we assert the bar shows the routing
 * state when given a routing lifecycle, regardless of intervening time —
 * the 8s budget is enforced server-side / e2e and observed here as
 * "no async work delays the bar's render."
 */
import { afterEach, beforeEach, describe, test, expect, vi } from "vitest";
import { render } from "@testing-library/react";
import { WorkflowLifecycleBar } from "@/components/chat/workflow-lifecycle-bar";

beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(new Date("2026-04-27T12:00:00Z"));
});

afterEach(() => {
  // NOTE: per `cq-vitest-setup-file-hook-scope`, do NOT use
  // `vi.unstubAllGlobals()` or `vi.restoreAllMocks()` here — they break
  // sibling test files that hold module-scope `vi.stubGlobal` calls.
  // We only restore the timer mock, which is local-scoped.
  vi.useRealTimers();
});

describe("WorkflowLifecycleBar routing state", () => {
  test("renders routing state immediately on synchronous render (no rAF batching)", () => {
    const { container } = render(
      <WorkflowLifecycleBar lifecycle={{ state: "routing" }} />,
    );
    // No async wait needed — routing must appear synchronously.
    expect(container.querySelector('[data-lifecycle-state="routing"]')).not.toBeNull();
  });

  test("skillName is extracted into the routing copy", () => {
    const { container } = render(
      <WorkflowLifecycleBar lifecycle={{ state: "routing", skillName: "plan" }} />,
    );
    const bar = container.querySelector('[data-lifecycle-state="routing"]');
    expect(bar?.textContent ?? "").toContain("plan");
  });

  test("routing → active is a clean transition (re-render swaps state attribute)", () => {
    const { container, rerender } = render(
      <WorkflowLifecycleBar lifecycle={{ state: "routing" }} />,
    );
    expect(container.querySelector('[data-lifecycle-state="routing"]')).not.toBeNull();
    rerender(
      <WorkflowLifecycleBar lifecycle={{ state: "active", workflow: "plan" }} />,
    );
    expect(container.querySelector('[data-lifecycle-state="routing"]')).toBeNull();
    expect(container.querySelector('[data-lifecycle-state="active"]')).not.toBeNull();
  });
});
