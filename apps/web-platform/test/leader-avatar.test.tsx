import { describe, it, expect } from "vitest";
import { render, screen, fireEvent } from "@testing-library/react";
import { LeaderAvatar } from "@/components/leader-avatar";

describe("LeaderAvatar", () => {
  it("renders with the leader's name in the accessible label", () => {
    render(<LeaderAvatar leaderId="cmo" size="md" />);
    expect(screen.getByLabelText(/CMO avatar/i)).toBeInTheDocument();
  });

  it("exposes 'Soleur avatar' as the label for the system/null fallback", () => {
    render(<LeaderAvatar leaderId="system" size="md" />);
    expect(screen.getByLabelText(/Soleur avatar/i)).toBeInTheDocument();
  });

  it("renders a lucide icon (not the Soleur logo) for a known leader", () => {
    const { container } = render(<LeaderAvatar leaderId="cmo" size="md" />);
    expect(
      container.querySelector('img[src="/icons/soleur-logo-mark.png"]'),
    ).toBeNull();
    expect(container.querySelector("svg")).not.toBeNull();
  });

  it("renders the Soleur logo fallback for the system leader", () => {
    // Use container.querySelector — happy-dom hides decorative alt="" images
    // from role/label queries, so getByRole("img") would not find this node.
    const { container } = render(<LeaderAvatar leaderId="system" size="md" />);
    expect(
      container.querySelector('img[src="/icons/soleur-logo-mark.png"]'),
    ).not.toBeNull();
  });

  it("renders the Soleur logo fallback when leaderId is null", () => {
    const { container } = render(<LeaderAvatar leaderId={null} size="md" />);
    expect(
      container.querySelector('img[src="/icons/soleur-logo-mark.png"]'),
    ).not.toBeNull();
  });

  it("applies the sm/md/lg tailwind size classes to the wrapper", () => {
    // Assert on wrapper class rather than internal svg dimensions — lucide's
    // width attribute is a library detail, the Tailwind class is the contract.
    const { container: sm } = render(<LeaderAvatar leaderId="cto" size="sm" />);
    expect(sm.firstElementChild?.className).toMatch(/\bh-5 w-5\b/);

    const { container: md } = render(<LeaderAvatar leaderId="cto" size="md" />);
    expect(md.firstElementChild?.className).toMatch(/\bh-7 w-7\b/);

    const { container: lg } = render(<LeaderAvatar leaderId="cto" size="lg" />);
    expect(lg.firstElementChild?.className).toMatch(/\bh-8 w-8\b/);
  });

  it("renders a custom icon when customIconPath is provided", () => {
    const { container } = render(
      <LeaderAvatar
        leaderId="cto"
        size="md"
        customIconPath="settings/team-icons/cto.png"
      />,
    );
    const img = container.querySelector('img[alt="CTO custom icon"]');
    expect(img).not.toBeNull();
    expect(img?.getAttribute("src")).toBe(
      "/api/kb/content/settings/team-icons/cto.png",
    );
  });

  it("renders the default icon when customIconPath is null", () => {
    const { container } = render(
      <LeaderAvatar leaderId="cto" size="md" customIconPath={null} />,
    );
    expect(container.querySelector('img[alt="CTO custom icon"]')).toBeNull();
    expect(container.querySelector("svg")).not.toBeNull();
  });

  it("falls back to the lucide icon when the custom icon fails to load", () => {
    const { container } = render(
      <LeaderAvatar
        leaderId="cto"
        size="md"
        customIconPath="broken/path.png"
      />,
    );
    const img = container.querySelector(
      'img[alt="CTO custom icon"]',
    ) as HTMLImageElement | null;
    expect(img).not.toBeNull();
    fireEvent.error(img!);
    // Custom img is removed, lucide svg takes over
    expect(container.querySelector('img[alt="CTO custom icon"]')).toBeNull();
    expect(container.querySelector("svg")).not.toBeNull();
  });

  it("accepts a custom className on the wrapper", () => {
    const { container } = render(
      <LeaderAvatar leaderId="cto" size="md" className="mt-1" />,
    );
    expect(container.firstElementChild?.getAttribute("class")).toContain(
      "mt-1",
    );
  });
});
