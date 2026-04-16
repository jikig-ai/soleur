import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import {
  FoundationCards,
  type FoundationCard,
} from "@/components/dashboard/foundation-cards";
import type { DomainLeaderId } from "@/server/domain-leaders";

const mixedCards: FoundationCard[] = [
  {
    id: "vision",
    title: "Vision",
    leaderId: "cpo",
    kbPath: "overview/vision.md",
    promptText: "",
    done: true,
  },
  {
    id: "brand",
    title: "Brand Identity",
    leaderId: "cmo",
    kbPath: "marketing/brand-guide.md",
    promptText: "Define the brand identity for my company.",
    done: false,
  },
  {
    id: "validation",
    title: "Business Validation",
    leaderId: "cpo",
    kbPath: "product/business-validation.md",
    promptText: "Run a business validation.",
    done: false,
  },
  {
    id: "legal",
    title: "Legal Foundations",
    leaderId: "clo",
    kbPath: "legal/privacy-policy.md",
    promptText: "Set up legal foundations.",
    done: true,
  },
];

describe("FoundationCards", () => {
  const mockOnIncompleteClick = vi.fn();
  const mockGetIconPath = vi.fn((_id: DomainLeaderId): string | null => null);

  beforeEach(() => {
    mockOnIncompleteClick.mockClear();
    mockGetIconPath.mockClear();
  });

  function renderCards(cards: FoundationCard[] = mixedCards) {
    return render(
      <FoundationCards
        cards={cards}
        getIconPath={mockGetIconPath}
        onIncompleteClick={mockOnIncompleteClick}
      />,
    );
  }

  it("renders completed cards as anchor links to the KB path", () => {
    renderCards();
    const visionLink = screen.getByRole("link", { name: /Vision/ });
    expect(visionLink).toHaveAttribute("href", "/dashboard/kb/overview/vision.md");

    const legalLink = screen.getByRole("link", { name: /Legal Foundations/ });
    expect(legalLink).toHaveAttribute(
      "href",
      "/dashboard/kb/legal/privacy-policy.md",
    );
  });

  it("renders incomplete cards as buttons", () => {
    renderCards();
    const brandBtn = screen.getByRole("button", { name: /Brand Identity/ });
    expect(brandBtn).toBeInTheDocument();
    expect(brandBtn.tagName).toBe("BUTTON");

    const validationBtn = screen.getByRole("button", {
      name: /Business Validation/,
    });
    expect(validationBtn.tagName).toBe("BUTTON");
  });

  it("fires onIncompleteClick with the prompt text when an incomplete card is clicked", () => {
    renderCards();
    fireEvent.click(screen.getByRole("button", { name: /Brand Identity/ }));
    expect(mockOnIncompleteClick).toHaveBeenCalledTimes(1);
    expect(mockOnIncompleteClick).toHaveBeenCalledWith(
      "Define the brand identity for my company.",
    );

    fireEvent.click(
      screen.getByRole("button", { name: /Business Validation/ }),
    );
    expect(mockOnIncompleteClick).toHaveBeenCalledTimes(2);
    expect(mockOnIncompleteClick).toHaveBeenLastCalledWith(
      "Run a business validation.",
    );
  });

  it("does not fire onIncompleteClick when a completed (link) card is activated", () => {
    renderCards();
    // Clicking anchors does not invoke onIncompleteClick
    fireEvent.click(screen.getByRole("link", { name: /Vision/ }));
    expect(mockOnIncompleteClick).not.toHaveBeenCalled();
  });

  it("renders one element per card", () => {
    renderCards();
    expect(screen.getAllByRole("link")).toHaveLength(2);
    expect(screen.getAllByRole("button")).toHaveLength(2);
  });

  it("calls getIconPath for each incomplete card's leaderId", () => {
    renderCards();
    // Incomplete: Brand (cmo), Validation (cpo)
    const calls = mockGetIconPath.mock.calls.map((c) => c[0]);
    expect(calls).toContain("cmo");
    expect(calls).toContain("cpo");
  });

  describe("chip rendering for completed cards", () => {
    it("renders completed cards as compact chips separate from the active grid", () => {
      const { container } = renderCards();
      // Completed cards should be in a chips row (flex container), not the grid
      const chipsRow = container.querySelector("[data-testid='completed-chips']");
      expect(chipsRow).toBeInTheDocument();

      // Chips should contain links for completed cards
      const chipLinks = chipsRow!.querySelectorAll("a");
      expect(chipLinks).toHaveLength(2); // Vision + Legal
    });

    it("renders incomplete cards in the active grid only", () => {
      const { container } = renderCards();
      const activeGrid = container.querySelector("[data-testid='active-grid']");
      expect(activeGrid).toBeInTheDocument();

      const gridButtons = activeGrid!.querySelectorAll("button");
      expect(gridButtons).toHaveLength(2); // Brand + Validation
    });

    it("renders nothing when all cards are complete", () => {
      const allDone = mixedCards.map((c) => ({ ...c, done: true }));
      const { container } = renderCards(allDone);
      // Only chips, no active grid
      const activeGrid = container.querySelector("[data-testid='active-grid']");
      expect(activeGrid).not.toBeInTheDocument();

      const chipsRow = container.querySelector("[data-testid='completed-chips']");
      expect(chipsRow).toBeInTheDocument();
      expect(chipsRow!.querySelectorAll("a")).toHaveLength(4);
    });

    it("renders no chips row when no cards are complete", () => {
      const noneDone = mixedCards.map((c) => ({ ...c, done: false }));
      const { container } = renderCards(noneDone);
      const chipsRow = container.querySelector("[data-testid='completed-chips']");
      expect(chipsRow).not.toBeInTheDocument();
    });

    it("chip links navigate to the KB path", () => {
      renderCards();
      const visionChip = screen.getByRole("link", { name: /Vision/ });
      expect(visionChip).toHaveAttribute("href", "/dashboard/kb/overview/vision.md");
    });
  });
});
