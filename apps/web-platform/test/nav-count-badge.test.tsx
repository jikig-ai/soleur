import { describe, it, expect, afterEach } from "vitest";
import { render, screen, cleanup } from "@testing-library/react";
import { NavCountBadge } from "@/components/dashboard/nav-count-badge";

afterEach(() => cleanup());

describe("NavCountBadge (shared presentational)", () => {
  it("renders the count as a neutral pill with the given testId + accessible name", () => {
    render(
      <NavCountBadge
        count={3}
        collapsed={false}
        testId="x-badge"
        label="3 items needing attention"
      />,
    );
    const pill = screen.getByTestId("x-badge");
    expect(pill).toHaveTextContent("3");
    expect(pill).toHaveAccessibleName("3 items needing attention");
    expect(pill.className).toContain("bg-soleur-bg-badge");
    expect(pill.className).not.toMatch(/gold/);
  });

  it("caps large counts at 99+", () => {
    render(
      <NavCountBadge count={250} collapsed={false} testId="x-badge" label="l" />,
    );
    expect(screen.getByTestId("x-badge")).toHaveTextContent("99+");
  });

  it("does not render the collapsed corner variant when expanded", () => {
    render(
      <NavCountBadge count={5} collapsed={false} testId="x-badge" label="l" />,
    );
    expect(screen.queryByTestId("x-badge-collapsed")).not.toBeInTheDocument();
  });

  it("renders the collapsed corner dot (aria-hidden, rail-ring) when collapsed", () => {
    render(
      <NavCountBadge count={5} collapsed testId="x-badge" label="l" />,
    );
    const dot = screen.getByTestId("x-badge-collapsed");
    expect(dot).toHaveTextContent("5");
    expect(dot.className).toMatch(/ring-soleur-bg-surface-1/);
    // aria-hidden so it doesn't hijack the collapsed nav link's accessible name.
    expect(dot).toHaveAttribute("aria-hidden", "true");
  });
});
