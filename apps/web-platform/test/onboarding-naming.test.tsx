import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { NamingOnboardingModal } from "@/components/onboarding/naming-modal";

const mockUpdateName = vi.fn().mockResolvedValue(undefined);
const mockOnSkip = vi.fn();
const mockOnComplete = vi.fn();

describe("NamingOnboardingModal", () => {
  beforeEach(() => {
    mockUpdateName.mockClear();
    mockOnSkip.mockClear();
    mockOnComplete.mockClear();
  });

  function renderModal() {
    return render(
      <NamingOnboardingModal
        onSave={mockUpdateName}
        onSkip={mockOnSkip}
        onComplete={mockOnComplete}
      />,
    );
  }

  it("renders heading 'Want to Name Your Leaders?'", () => {
    renderModal();
    expect(screen.getByText(/Name Your Leaders/)).toBeInTheDocument();
  });

  it("shows all 8 domain leaders", () => {
    renderModal();
    expect(screen.getByText("Chief Marketing Officer")).toBeInTheDocument();
    expect(screen.getByText("Chief Technology Officer")).toBeInTheDocument();
    expect(screen.getByText("Chief Financial Officer")).toBeInTheDocument();
    expect(screen.getByText("Chief Product Officer")).toBeInTheDocument();
    expect(screen.getByText("Chief Revenue Officer")).toBeInTheDocument();
    expect(screen.getByText("Chief Operations Officer")).toBeInTheDocument();
    expect(screen.getByText("Chief Legal Officer")).toBeInTheDocument();
    expect(screen.getByText("Chief Communications Officer")).toBeInTheDocument();
  });

  it("has 8 input fields with placeholder text", () => {
    renderModal();
    const inputs = screen.getAllByPlaceholderText("Enter a name...");
    expect(inputs).toHaveLength(8);
  });

  it("calls onSkip when 'Skip for now' is clicked", () => {
    renderModal();
    fireEvent.click(screen.getByText("Skip for now"));
    expect(mockOnSkip).toHaveBeenCalled();
  });

  it("calls onSave for each named leader when 'Save Names' is clicked", async () => {
    renderModal();
    const inputs = screen.getAllByPlaceholderText("Enter a name...");

    // Name the first two leaders
    fireEvent.change(inputs[0], { target: { value: "Sarah" } });
    fireEvent.change(inputs[1], { target: { value: "Alex" } });

    fireEvent.click(screen.getByText("Save Names"));

    await waitFor(() => {
      // Should save both names
      expect(mockUpdateName).toHaveBeenCalledWith("cmo", "Sarah");
      expect(mockUpdateName).toHaveBeenCalledWith("cto", "Alex");
    });
  });

  it("does not save empty fields", async () => {
    renderModal();
    const inputs = screen.getAllByPlaceholderText("Enter a name...");

    // Only name one leader
    fireEvent.change(inputs[0], { target: { value: "Sarah" } });

    fireEvent.click(screen.getByText("Save Names"));

    await waitFor(() => {
      expect(mockUpdateName).toHaveBeenCalledTimes(1);
      expect(mockUpdateName).toHaveBeenCalledWith("cmo", "Sarah");
    });
  });

  it("calls onComplete after saving", async () => {
    renderModal();
    fireEvent.click(screen.getByText("Save Names"));

    await waitFor(() => {
      expect(mockOnComplete).toHaveBeenCalled();
    });
  });

  it("shows colored badges for each leader", () => {
    renderModal();
    // Check that badge elements exist (CMO, CTO etc.)
    expect(screen.getByText("CMO")).toBeInTheDocument();
    expect(screen.getByText("CTO")).toBeInTheDocument();
  });
});
