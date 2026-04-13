import { describe, it, expect } from "vitest";
import { render, screen } from "@testing-library/react";
import { LeaderAvatar } from "@/components/leader-avatar";

describe("LeaderAvatar", () => {
  it("renders a domain-specific icon for a known leader", () => {
    const { container } = render(<LeaderAvatar leaderId="cmo" size="md" />);
    // Should render a circular badge with the leader's color, not the Soleur logo
    const badge = container.querySelector("[aria-label]");
    expect(badge).toBeTruthy();
    expect(badge!.getAttribute("aria-label")).toContain("CMO");
    // Should NOT render the soleur-logo-mark.png
    const img = container.querySelector('img[src="/icons/soleur-logo-mark.png"]');
    expect(img).toBeNull();
  });

  it("renders Soleur logo for system leader", () => {
    const { container } = render(<LeaderAvatar leaderId="system" size="md" />);
    const img = container.querySelector('img[src="/icons/soleur-logo-mark.png"]');
    expect(img).toBeTruthy();
  });

  it("renders Soleur logo when leaderId is null", () => {
    const { container } = render(<LeaderAvatar leaderId={null} size="md" />);
    const img = container.querySelector('img[src="/icons/soleur-logo-mark.png"]');
    expect(img).toBeTruthy();
  });

  it("applies correct size classes for sm", () => {
    const { container } = render(<LeaderAvatar leaderId="cto" size="sm" />);
    const badge = container.firstElementChild;
    expect(badge?.className).toContain("h-5");
    expect(badge?.className).toContain("w-5");
  });

  it("applies correct size classes for md", () => {
    const { container } = render(<LeaderAvatar leaderId="cto" size="md" />);
    const badge = container.firstElementChild;
    expect(badge?.className).toContain("h-7");
    expect(badge?.className).toContain("w-7");
  });

  it("applies correct size classes for lg", () => {
    const { container } = render(<LeaderAvatar leaderId="cto" size="lg" />);
    const badge = container.firstElementChild;
    expect(badge?.className).toContain("h-8");
    expect(badge?.className).toContain("w-8");
  });

  it("applies the leader background color", () => {
    const { container } = render(<LeaderAvatar leaderId="cmo" size="md" />);
    const badge = container.firstElementChild;
    expect(badge?.className).toContain("bg-pink-500");
  });

  it("includes aria-label with leader name", () => {
    render(<LeaderAvatar leaderId="cfo" size="md" />);
    const el = screen.getByLabelText(/CFO avatar/i);
    expect(el).toBeTruthy();
  });

  it("accepts optional className", () => {
    const { container } = render(
      <LeaderAvatar leaderId="cto" size="md" className="mt-1" />,
    );
    const badge = container.firstElementChild;
    expect(badge?.className).toContain("mt-1");
  });

  it("renders custom icon when customIconPath is provided", () => {
    const { container } = render(
      <LeaderAvatar leaderId="cto" size="md" customIconPath="settings/team-icons/cto.png" />,
    );
    const img = container.querySelector("img");
    expect(img).toBeTruthy();
    expect(img!.getAttribute("src")).toBe("/api/kb/content/settings/team-icons/cto.png");
    expect(img!.getAttribute("alt")).toBe("CTO custom icon");
  });

  it("renders default icon when customIconPath is null", () => {
    const { container } = render(
      <LeaderAvatar leaderId="cto" size="md" customIconPath={null} />,
    );
    // Should NOT render a custom img
    const img = container.querySelector('img[alt="CTO custom icon"]');
    expect(img).toBeNull();
  });
});
