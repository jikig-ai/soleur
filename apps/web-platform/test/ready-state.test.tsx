import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen } from "@testing-library/react";

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

vi.mock("next/font/google", () => ({
  Cormorant_Garamond: () => ({
    className: "mock-serif",
    variable: "--font-serif",
  }),
  Inter: () => ({ className: "mock-sans", variable: "--font-sans" }),
}));

// ---------------------------------------------------------------------------
// Types — the interface the revamped component will accept
// ---------------------------------------------------------------------------

interface ProjectHealthSnapshot {
  scannedAt: string;
  category: "strong" | "developing" | "gaps-found";
  signals: {
    detected: { id: string; label: string }[];
    missing: { id: string; label: string }[];
  };
  recommendations: string[];
  kbExists: boolean;
}

// ---------------------------------------------------------------------------
// Mock data
// ---------------------------------------------------------------------------

const mockSnapshot: ProjectHealthSnapshot = {
  scannedAt: new Date().toISOString(),
  category: "developing",
  signals: {
    detected: [
      { id: "package-manager", label: "Package manager" },
      { id: "tests", label: "Test suite" },
      { id: "readme", label: "README" },
    ],
    missing: [
      { id: "ci", label: "CI/CD" },
      { id: "linting", label: "Linting" },
      { id: "claude-md", label: "CLAUDE.md" },
      { id: "docs", label: "Documentation" },
      { id: "kb", label: "Knowledge Base" },
    ],
  },
  recommendations: [
    "Set up CI/CD to automate testing.",
    "Add a linter for consistent code style.",
    "Add a CLAUDE.md for AI assistant context.",
  ],
  kbExists: false,
};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Import the component fresh each test (mocks stay in place). */
async function importReadyState() {
  const mod = await import("@/components/connect-repo/ready-state");
  return mod.ReadyState;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("ReadyState — health snapshot", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  // -------------------------------------------------------------------------
  // 1. Health category badge
  // -------------------------------------------------------------------------

  it("renders health category badge when healthSnapshot is provided", async () => {
    const ReadyState = await importReadyState();
    render(
      <ReadyState
        repoName="user/test-repo"
        onContinue={vi.fn()}
        onViewKb={vi.fn()}
        healthSnapshot={mockSnapshot}
      />,
    );

    // "developing" category should display as a badge
    expect(screen.getByText(/developing/i)).toBeInTheDocument();
  });

  it('renders "Strong" badge for strong category', async () => {
    const ReadyState = await importReadyState();
    const strongSnapshot: ProjectHealthSnapshot = {
      ...mockSnapshot,
      category: "strong",
    };
    render(
      <ReadyState
        repoName="user/test-repo"
        onContinue={vi.fn()}
        onViewKb={vi.fn()}
        healthSnapshot={strongSnapshot}
      />,
    );

    expect(screen.getByText(/strong/i)).toBeInTheDocument();
  });

  it('renders "Gaps Found" badge for gaps-found category', async () => {
    const ReadyState = await importReadyState();
    const gapsSnapshot: ProjectHealthSnapshot = {
      ...mockSnapshot,
      category: "gaps-found",
    };
    render(
      <ReadyState
        repoName="user/test-repo"
        onContinue={vi.fn()}
        onViewKb={vi.fn()}
        healthSnapshot={gapsSnapshot}
      />,
    );

    expect(screen.getByText(/gaps found/i)).toBeInTheDocument();
  });

  // -------------------------------------------------------------------------
  // 2. Detected signals with green checkmarks
  // -------------------------------------------------------------------------

  it("renders detected signals with green checkmarks", async () => {
    const ReadyState = await importReadyState();
    render(
      <ReadyState
        repoName="user/test-repo"
        onContinue={vi.fn()}
        onViewKb={vi.fn()}
        healthSnapshot={mockSnapshot}
      />,
    );

    // Each detected signal label should be visible
    for (const signal of mockSnapshot.signals.detected) {
      expect(screen.getByText(signal.label)).toBeInTheDocument();
    }

    // Detected signals should have green checkmark indicators
    const detectedSection = screen.getByTestId("detected-signals");
    expect(detectedSection).toBeInTheDocument();
    // Each detected signal should have a green check icon
    const checkIcons = detectedSection.querySelectorAll("[data-testid='signal-check']");
    expect(checkIcons).toHaveLength(mockSnapshot.signals.detected.length);
  });

  // -------------------------------------------------------------------------
  // 3. Missing signals with amber indicators
  // -------------------------------------------------------------------------

  it("renders missing signals with amber indicators", async () => {
    const ReadyState = await importReadyState();
    render(
      <ReadyState
        repoName="user/test-repo"
        onContinue={vi.fn()}
        onViewKb={vi.fn()}
        healthSnapshot={mockSnapshot}
      />,
    );

    // Each missing signal label should be visible
    for (const signal of mockSnapshot.signals.missing) {
      expect(screen.getByText(signal.label)).toBeInTheDocument();
    }

    // Missing signals should have amber indicators
    const missingSection = screen.getByTestId("missing-signals");
    expect(missingSection).toBeInTheDocument();
    const amberIcons = missingSection.querySelectorAll("[data-testid='signal-missing']");
    expect(amberIcons).toHaveLength(mockSnapshot.signals.missing.length);
  });

  // -------------------------------------------------------------------------
  // 4. Renders exactly 3 recommendations
  // -------------------------------------------------------------------------

  it("renders exactly 3 recommendations", async () => {
    const ReadyState = await importReadyState();
    render(
      <ReadyState
        repoName="user/test-repo"
        onContinue={vi.fn()}
        onViewKb={vi.fn()}
        healthSnapshot={mockSnapshot}
      />,
    );

    for (const rec of mockSnapshot.recommendations) {
      expect(screen.getByText(rec)).toBeInTheDocument();
    }

    const recommendationItems = screen.getAllByTestId("recommendation-item");
    expect(recommendationItems).toHaveLength(3);
  });

  // -------------------------------------------------------------------------
  // 5. Shows "Deep analysis in progress" only when syncConversationId exists
  // -------------------------------------------------------------------------

  it('shows "Deep analysis in progress" when syncConversationId is provided', async () => {
    const ReadyState = await importReadyState();
    render(
      <ReadyState
        repoName="user/test-repo"
        onContinue={vi.fn()}
        onViewKb={vi.fn()}
        healthSnapshot={mockSnapshot}
        syncConversationId="conv-123"
      />,
    );

    expect(
      screen.getByText(/deep analysis in progress/i),
    ).toBeInTheDocument();

    // Should have a link/reference to Dashboard
    const ccLink = screen.getByRole("link", { name: /dashboard/i });
    expect(ccLink).toBeInTheDocument();
    expect(ccLink).toHaveAttribute("href", expect.stringContaining("/dashboard"));
  });

  it('shows fallback message when syncConversationId is null (#1816)', async () => {
    const ReadyState = await importReadyState();
    render(
      <ReadyState
        repoName="user/test-repo"
        onContinue={vi.fn()}
        onViewKb={vi.fn()}
        healthSnapshot={mockSnapshot}
        syncConversationId={null}
      />,
    );

    // Should NOT show deep analysis message
    expect(
      screen.queryByText(/deep analysis in progress/i),
    ).not.toBeInTheDocument();

    // Should show fallback message
    expect(
      screen.getByText(/your project is ready/i),
    ).toBeInTheDocument();
  });

  // -------------------------------------------------------------------------
  // 6. Graceful degradation — current design when healthSnapshot is null
  // -------------------------------------------------------------------------

  it("renders current design when healthSnapshot is null (graceful degradation)", async () => {
    const ReadyState = await importReadyState();
    render(
      <ReadyState
        repoName="user/test-repo"
        onContinue={vi.fn()}
        onViewKb={vi.fn()}
        healthSnapshot={null}
      />,
    );

    // Current component renders these elements regardless
    expect(
      screen.getByText("Your AI Team Is Ready."),
    ).toBeInTheDocument();
    expect(screen.getByText("user/test-repo")).toBeInTheDocument();
    expect(screen.getByText("Open Dashboard")).toBeInTheDocument();
    expect(screen.getByText("Review Knowledge Base")).toBeInTheDocument();

    // Health-specific sections should NOT be present
    expect(screen.queryByTestId("detected-signals")).not.toBeInTheDocument();
    expect(screen.queryByTestId("missing-signals")).not.toBeInTheDocument();
    expect(
      screen.queryByText(/deep analysis in progress/i),
    ).not.toBeInTheDocument();
  });

  // -------------------------------------------------------------------------
  // 7. Renders "Open Dashboard" and "Review Knowledge Base" CTAs
  // -------------------------------------------------------------------------

  it('renders "Open Dashboard" CTA when healthSnapshot is provided', async () => {
    const ReadyState = await importReadyState();
    render(
      <ReadyState
        repoName="user/test-repo"
        onContinue={vi.fn()}
        onViewKb={vi.fn()}
        healthSnapshot={mockSnapshot}
      />,
    );

    const ccButton = screen.getByRole("button", {
      name: /open dashboard/i,
    });
    expect(ccButton).toBeInTheDocument();
  });

  it('renders "Review Knowledge Base" CTA when healthSnapshot is provided and kbExists is false', async () => {
    const ReadyState = await importReadyState();
    render(
      <ReadyState
        repoName="user/test-repo"
        onContinue={vi.fn()}
        onViewKb={vi.fn()}
        healthSnapshot={mockSnapshot}
      />,
    );

    // kbExists is false, so the CTA should navigate to KB
    const kbButton = screen.getByRole("button", {
      name: /review knowledge base/i,
    });
    expect(kbButton).toBeInTheDocument();
  });

  it('renders "Open Dashboard" and "Review Knowledge Base" CTAs together', async () => {
    const ReadyState = await importReadyState();
    render(
      <ReadyState
        repoName="user/test-repo"
        onContinue={vi.fn()}
        onViewKb={vi.fn()}
        healthSnapshot={mockSnapshot}
      />,
    );

    expect(
      screen.getByRole("button", { name: /open dashboard/i }),
    ).toBeInTheDocument();
    expect(
      screen.getByRole("button", { name: /review knowledge base/i }),
    ).toBeInTheDocument();
  });
});
