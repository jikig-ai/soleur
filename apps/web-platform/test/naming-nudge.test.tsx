import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, waitFor } from "@testing-library/react";
import { NamingNudge } from "@/components/chat/naming-nudge";

const mockOnSave = vi.fn().mockResolvedValue(undefined);
const mockOnDismiss = vi.fn();

describe("NamingNudge", () => {
  beforeEach(() => {
    mockOnSave.mockClear();
    mockOnDismiss.mockClear();
  });

  function renderNudge(leaderId = "cto" as const) {
    return render(
      <NamingNudge
        leaderId={leaderId}
        leaderTitle="Chief Technology Officer"
        onSave={mockOnSave}
        onDismiss={mockOnDismiss}
      />,
    );
  }

  it("shows 'You just worked with your CTO.' message", () => {
    renderNudge();
    expect(screen.getByText(/You just worked with your CTO/)).toBeInTheDocument();
  });

  it("shows a text input for the name", () => {
    renderNudge();
    expect(screen.getByPlaceholderText(/name/i)).toBeInTheDocument();
  });

  it("has Save and Dismiss buttons", () => {
    renderNudge();
    expect(screen.getByText("Save")).toBeInTheDocument();
    expect(screen.getByText("Dismiss")).toBeInTheDocument();
  });

  it("calls onSave with leader ID and name when Save is clicked", async () => {
    renderNudge();
    const input = screen.getByPlaceholderText(/name/i);
    fireEvent.change(input, { target: { value: "Alex" } });
    fireEvent.click(screen.getByText("Save"));

    await waitFor(() => {
      expect(mockOnSave).toHaveBeenCalledWith("cto", "Alex");
    });
  });

  it("calls onDismiss when Dismiss is clicked", () => {
    renderNudge();
    fireEvent.click(screen.getByText("Dismiss"));
    expect(mockOnDismiss).toHaveBeenCalledWith("cto");
  });

  it("shows description text about display format", () => {
    renderNudge();
    expect(
      screen.getByText(/display as.*Name \(CTO\).*in conversations/i),
    ).toBeInTheDocument();
  });

  it("does not call onSave when input is empty", async () => {
    renderNudge();
    fireEvent.click(screen.getByText("Save"));
    expect(mockOnSave).not.toHaveBeenCalled();
  });
});
