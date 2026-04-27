/**
 * Stage 4 (#2886) — RED tests for `<WorkflowLifecycleBar>`.
 *
 * Asserts via `data-lifecycle-state` attribute hook per
 * `cq-jsdom-no-layout-gated-assertions`. Per-state CTAs and labels asserted
 * via visible text + `getByRole("button")`.
 */
import { describe, test, expect, vi } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import { WorkflowLifecycleBar } from "@/components/chat/workflow-lifecycle-bar";

describe("WorkflowLifecycleBar", () => {
  test("idle state renders nothing", () => {
    const { container } = render(
      <WorkflowLifecycleBar lifecycle={{ state: "idle" }} />,
    );
    expect(container.querySelector("[data-lifecycle-state]")).toBeNull();
  });

  // Routing-state tests removed per review F9 (routing variant dropped from
  // the WorkflowLifecycleState union).

  test("active state renders workflow + Switch workflow button", () => {
    const onSwitch = vi.fn();
    const { container } = render(
      <WorkflowLifecycleBar
        lifecycle={{
          state: "active",
          workflow: "plan",
          phase: "Phase 2",
          cumulativeCostUsd: 0.0123,
        }}
        onSwitchWorkflow={onSwitch}
      />,
    );
    const bar = container.querySelector('[data-lifecycle-state="active"]');
    expect(bar).not.toBeNull();
    expect(container.textContent).toContain("plan");
    expect(container.textContent).toContain("Phase 2");
    expect(container.textContent).toContain("0.0123");
    fireEvent.click(screen.getByRole("button", { name: /switch workflow/i }));
    expect(onSwitch).toHaveBeenCalledTimes(1);
  });

  test("ended state renders summary + outcome + Start new conversation", () => {
    const onStart = vi.fn();
    const { container } = render(
      <WorkflowLifecycleBar
        lifecycle={{
          state: "ended",
          workflow: "brainstorm",
          status: "completed",
          summary: "Done",
        }}
        onStartNewConversation={onStart}
      />,
    );
    const bar = container.querySelector('[data-lifecycle-state="ended"]');
    expect(bar).not.toBeNull();
    expect(container.textContent).toContain("brainstorm");
    expect(container.textContent).toContain("completed");
    fireEvent.click(screen.getByRole("button", { name: /start new conversation/i }));
    expect(onStart).toHaveBeenCalledTimes(1);
  });
});
