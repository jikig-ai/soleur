import { describe, it, expect } from "vitest";
import { render, screen } from "@testing-library/react";
import { WelcomeCard } from "@/components/chat/welcome-card";

describe("WelcomeCard", () => {
  it("renders headline and body copy", () => {
    render(<WelcomeCard />);
    expect(screen.getByText("Your Organization Is Ready")).toBeInTheDocument();
    expect(
      screen.getByText(
        "Eight department leaders are standing by. Type @ to put one to work.",
      ),
    ).toBeInTheDocument();
  });

  it("has an amber accent icon", () => {
    render(<WelcomeCard />);
    const icon = screen.getByTestId("welcome-icon");
    expect(icon).toBeInTheDocument();
    expect(icon.className).toMatch(/amber/);
  });
});
