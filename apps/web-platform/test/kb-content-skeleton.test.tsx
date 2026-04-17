import { describe, it, expect } from "vitest";
import { render } from "@testing-library/react";

import { KbContentSkeleton } from "@/components/kb/kb-content-skeleton";

describe("KbContentSkeleton", () => {
  it("renders default 5 width rows when no widths prop provided", () => {
    const { container } = render(<KbContentSkeleton />);
    const rows = container.querySelectorAll<HTMLDivElement>(
      "[data-testid='kb-content-skeleton-row']",
    );
    expect(rows.length).toBe(5);
    const widths = Array.from(rows).map((row) => row.style.width);
    expect(widths).toEqual(["85%", "70%", "90%", "65%", "80%"]);
  });

  it("renders N rows with provided widths", () => {
    const { container } = render(
      <KbContentSkeleton widths={["100%", "50%"]} />,
    );
    const rows = container.querySelectorAll<HTMLDivElement>(
      "[data-testid='kb-content-skeleton-row']",
    );
    expect(rows.length).toBe(2);
    const widths = Array.from(rows).map((row) => row.style.width);
    expect(widths).toEqual(["100%", "50%"]);
  });

  it("renders the dashboard 6-row variant when passed 6 widths", () => {
    const { container } = render(
      <KbContentSkeleton
        widths={["85%", "70%", "90%", "65%", "80%", "75%"]}
      />,
    );
    const rows = container.querySelectorAll<HTMLDivElement>(
      "[data-testid='kb-content-skeleton-row']",
    );
    expect(rows.length).toBe(6);
  });
});
