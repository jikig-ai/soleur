/**
 * Stage 4 (#2886) — RED-first tests for `<SubagentGroup>`.
 *
 * Asserts via `data-*` attribute hooks per `cq-jsdom-no-layout-gated-assertions`.
 * No assertions on `clientWidth`, `scrollHeight`, etc.
 */
import { describe, test, expect } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import { SubagentGroup } from "@/components/chat/subagent-group";
import type { DomainLeaderId } from "@/server/domain-leaders";

function child(spawnId: string, leaderId: DomainLeaderId, status?: "success" | "error" | "timeout") {
  return { spawnId, leaderId, task: `task-${spawnId}`, status };
}

describe("SubagentGroup", () => {
  test("≤2 children renders expanded with no expand toggle", () => {
    const { container } = render(
      <SubagentGroup
        parentSpawnId="p-1"
        parentLeaderId={"cto" as DomainLeaderId}
        subagents={[child("s-1", "cmo" as DomainLeaderId), child("s-2", "cfo" as DomainLeaderId)]}
      />,
    );
    const group = container.querySelector('[data-parent-spawn-id="p-1"]');
    expect(group).not.toBeNull();
    expect(group?.getAttribute("data-expanded")).toBe("true");
    // Both children rendered.
    expect(container.querySelectorAll("[data-child-spawn-id]")).toHaveLength(2);
    // No toggle button when ≤2.
    expect(container.querySelector('[data-testid="subagent-group-toggle"]')).toBeNull();
  });

  test("≥3 children renders collapsed with an expand toggle", () => {
    const { container } = render(
      <SubagentGroup
        parentSpawnId="p-2"
        parentLeaderId={"cto" as DomainLeaderId}
        subagents={[
          child("s-1", "cmo" as DomainLeaderId),
          child("s-2", "cfo" as DomainLeaderId),
          child("s-3", "cpo" as DomainLeaderId),
        ]}
      />,
    );
    const group = container.querySelector('[data-parent-spawn-id="p-2"]');
    expect(group?.getAttribute("data-expanded")).toBe("false");
    expect(container.querySelector('[data-testid="subagent-group-toggle"]')).not.toBeNull();
  });

  test("per-child status badges render via data-child-status (collapsed → toggle to expand)", () => {
    const { container } = render(
      <SubagentGroup
        parentSpawnId="p-3"
        parentLeaderId={"cto" as DomainLeaderId}
        subagents={[
          child("s-1", "cmo" as DomainLeaderId, "success"),
          child("s-2", "cfo" as DomainLeaderId, "error"),
          child("s-3", "cpo" as DomainLeaderId, "timeout"),
          child("s-4", "cco" as DomainLeaderId), // in-flight
        ]}
      />,
    );
    // Default collapsed (≥3 children) — children not rendered yet.
    expect(container.querySelectorAll("[data-child-spawn-id]").length).toBe(0);
    // Expand.
    fireEvent.click(container.querySelector('[data-testid="subagent-group-toggle"]')!);
    expect(container.querySelector('[data-child-spawn-id="s-1"]')?.getAttribute("data-child-status")).toBe("success");
    expect(container.querySelector('[data-child-spawn-id="s-2"]')?.getAttribute("data-child-status")).toBe("error");
    expect(container.querySelector('[data-child-spawn-id="s-3"]')?.getAttribute("data-child-status")).toBe("timeout");
    expect(container.querySelector('[data-child-spawn-id="s-4"]')?.getAttribute("data-child-status")).toBe("in_flight");
  });

  test("count chip shows N subagents spawned", () => {
    render(
      <SubagentGroup
        parentSpawnId="p-4"
        parentLeaderId={"cto" as DomainLeaderId}
        subagents={[child("s-1", "cmo" as DomainLeaderId), child("s-2", "cfo" as DomainLeaderId)]}
      />,
    );
    expect(screen.getByText(/2 subagents spawned/i)).toBeTruthy();
  });

  test("partial-failure rendering shows mixed statuses without throwing (after expand)", () => {
    const { container } = render(
      <SubagentGroup
        parentSpawnId="p-5"
        parentLeaderId={"cto" as DomainLeaderId}
        subagents={[
          child("s-1", "cmo" as DomainLeaderId, "success"),
          child("s-2", "cfo" as DomainLeaderId, "timeout"),
          child("s-3", "cpo" as DomainLeaderId, "success"),
        ]}
      />,
    );
    fireEvent.click(container.querySelector('[data-testid="subagent-group-toggle"]')!);
    const statuses = Array.from(container.querySelectorAll("[data-child-status]")).map(
      (el) => el.getAttribute("data-child-status"),
    );
    expect(statuses).toEqual(["success", "timeout", "success"]);
  });

  // #3949 — regression: when `subagents` grows past
  // SUBAGENT_GROUP_AUTO_EXPAND_MAX across separate renders (the realistic
  // WS-incremental scenario), the group must re-collapse to honor the
  // policy default. The pre-fix `useState(initialExpanded)` snapshot would
  // keep `expanded=true` from the first render at length=1.
  test("re-collapses when children grow past the boundary across renders (no user toggle)", () => {
    const { container, rerender } = render(
      <SubagentGroup
        parentSpawnId="p-grow"
        parentLeaderId={"cto" as DomainLeaderId}
        subagents={[child("s-1", "cmo" as DomainLeaderId)]}
      />,
    );
    const group = container.querySelector('[data-parent-spawn-id="p-grow"]');
    expect(group?.getAttribute("data-expanded")).toBe("true"); // N=1, policy says expand
    rerender(
      <SubagentGroup
        parentSpawnId="p-grow"
        parentLeaderId={"cto" as DomainLeaderId}
        subagents={[
          child("s-1", "cmo" as DomainLeaderId),
          child("s-2", "cfo" as DomainLeaderId),
          child("s-3", "cpo" as DomainLeaderId),
        ]}
      />,
    );
    expect(group?.getAttribute("data-expanded")).toBe("false"); // N=3, policy says collapse
  });

  // #3949 — user-toggle wins over the policy default after subagents grow.
  test("user-toggle expansion persists when children grow further", () => {
    const { container, rerender } = render(
      <SubagentGroup
        parentSpawnId="p-toggle"
        parentLeaderId={"cto" as DomainLeaderId}
        subagents={[
          child("s-1", "cmo" as DomainLeaderId),
          child("s-2", "cfo" as DomainLeaderId),
          child("s-3", "cpo" as DomainLeaderId),
        ]}
      />,
    );
    const group = container.querySelector('[data-parent-spawn-id="p-toggle"]');
    expect(group?.getAttribute("data-expanded")).toBe("false");
    fireEvent.click(container.querySelector('[data-testid="subagent-group-toggle"]')!);
    expect(group?.getAttribute("data-expanded")).toBe("true");
    rerender(
      <SubagentGroup
        parentSpawnId="p-toggle"
        parentLeaderId={"cto" as DomainLeaderId}
        subagents={[
          child("s-1", "cmo" as DomainLeaderId),
          child("s-2", "cfo" as DomainLeaderId),
          child("s-3", "cpo" as DomainLeaderId),
          child("s-4", "cco" as DomainLeaderId),
        ]}
      />,
    );
    expect(group?.getAttribute("data-expanded")).toBe("true"); // user override holds
  });
});
