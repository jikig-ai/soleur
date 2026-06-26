import { afterEach, describe, expect, it } from "vitest";
import { cleanup, render, screen } from "@testing-library/react";
import { IssueConciergePanel } from "@/components/workstream/issue-concierge-panel";

afterEach(() => cleanup());

describe("IssueConciergePanel", () => {
  it("shows the Decision Making header + one seeded Concierge intro message", () => {
    render(<IssueConciergePanel />);
    expect(screen.getByText("Decision Making")).toBeTruthy();
    expect(screen.getByText("Concierge")).toBeTruthy();
    expect(screen.getByText(/talk through decisions/i)).toBeTruthy();
  });

  it("shows the offline notice and a disabled (wired) composer — no silent drop", () => {
    render(<IssueConciergePanel />);
    expect(screen.getByText(/offline — opening soon/i)).toBeTruthy();
    const composer = screen.getByLabelText("Message Concierge") as HTMLInputElement;
    expect(composer.disabled).toBe(true);
    const send = screen.getByRole("button", { name: "Send" }) as HTMLButtonElement;
    expect(send.disabled).toBe(true);
  });

  it("links Discuss in Chat to the live chat surface", () => {
    render(<IssueConciergePanel />);
    const link = screen.getByRole("link", { name: /discuss in chat/i });
    expect(link.getAttribute("href")).toBe("/dashboard/chat");
  });
});
