import { describe, it, expect, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import { FoundationSection } from "@/components/dashboard/foundation-section";
import type { FoundationCard } from "@/components/dashboard/foundation-cards";

function makeCards(): FoundationCard[] {
  return [
    {
      id: "vision",
      title: "Vision",
      leaderId: "cpo",
      kbPath: "knowledge-base/overview/vision.md",
      promptText: "Draft a vision document",
      done: false,
    },
  ];
}

describe("FoundationSection", () => {
  it("renders FOUNDATIONS header and descriptive copy", () => {
    render(
      <FoundationSection
        cards={makeCards()}
        getIconPath={() => null}
        onIncompleteClick={vi.fn()}
      />,
    );

    expect(screen.getByText("FOUNDATIONS")).toBeInTheDocument();
    expect(
      screen.getByText(/Complete these to brief your department leaders\./i),
    ).toBeInTheDocument();
  });

  it("applies the className prop to the outer wrapper", () => {
    const { container } = render(
      <FoundationSection
        cards={makeCards()}
        getIconPath={() => null}
        onIncompleteClick={vi.fn()}
        className="mb-10 w-full"
      />,
    );

    expect(container.firstElementChild?.className).toContain("mb-10 w-full");
  });
});
