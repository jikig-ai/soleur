/**
 * Stage 4 (#2886) — RED tests for `<ToolUseChip>`.
 *
 * Per AC6: chip renders for `cc_router` / `system` leader; label arrives
 * pre-built. NO `@/server/tool-labels` import in the component (sentinel
 * grep enforces this in Phase 6).
 */
import { describe, test, expect } from "vitest";
import { render } from "@testing-library/react";
import { ToolUseChip } from "@/components/chat/tool-use-chip";

describe("ToolUseChip", () => {
  test("renders the provided toolLabel verbatim", () => {
    const { container } = render(
      <ToolUseChip toolName="Skill" toolLabel="Routing via /soleur:go" leaderId="cc_router" />,
    );
    expect(container.querySelector("[data-tool-chip-id]")).not.toBeNull();
    expect(container.textContent).toContain("Routing via /soleur:go");
  });

  test("cc_router leader gets the cc_router border class", () => {
    const { container } = render(
      <ToolUseChip toolName="Skill" toolLabel="Routing" leaderId="cc_router" />,
    );
    const chip = container.querySelector("[data-tool-chip-id]");
    expect(chip?.className ?? "").toMatch(/border-yellow/);
  });

  test("system leader gets the system border class", () => {
    const { container } = render(
      <ToolUseChip toolName="Bash" toolLabel="Bootstrap" leaderId="system" />,
    );
    const chip = container.querySelector("[data-tool-chip-id]");
    expect(chip?.className ?? "").toMatch(/border-neutral/);
  });

  test("multiple chips coexist when rendered together", () => {
    const { container } = render(
      <div>
        <ToolUseChip toolName="A" toolLabel="A label" leaderId="cc_router" />
        <ToolUseChip toolName="B" toolLabel="B label" leaderId="system" />
      </div>,
    );
    expect(container.querySelectorAll("[data-tool-chip-id]")).toHaveLength(2);
  });

  test("renders attacker-influenced toolLabel as text (no executed tag)", () => {
    const { container } = render(
      <ToolUseChip toolName="X" toolLabel="<script>alert(1)</script>" leaderId="cc_router" />,
    );
    expect(container.querySelector("script")).toBeNull();
    expect(container.textContent).toContain("<script>alert(1)</script>");
  });
});
