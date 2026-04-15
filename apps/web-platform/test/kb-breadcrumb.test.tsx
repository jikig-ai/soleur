import { describe, it, expect } from "vitest";
import { render } from "@testing-library/react";
import { KbBreadcrumb } from "@/components/kb/kb-breadcrumb";

describe("KbBreadcrumb", () => {
  it("decodes URL-encoded segments", () => {
    const { container } = render(
      <KbBreadcrumb path="overview/Au%20Chat%20P%C3%B4tan%20-%20Pitch.pdf" />,
    );
    expect(container.textContent).toContain("Au Chat Pôtan - Pitch.pdf");
    expect(container.textContent).toContain("overview");
    expect(container.textContent).not.toContain("%20");
    expect(container.textContent).not.toContain("%C3%B4");
  });

  it("returns raw segment when decoding throws", () => {
    const { container } = render(<KbBreadcrumb path="folder/bad%E0.txt" />);
    // Malformed percent-escape must not throw; the raw segment is preserved.
    expect(container.textContent).toContain("bad%E0.txt");
  });

  it("highlights the last segment as the current item", () => {
    const { container } = render(<KbBreadcrumb path="a/b/c.md" />);
    const spans = container.querySelectorAll("nav > span > span:last-child");
    const last = spans[spans.length - 1];
    expect(last.textContent).toBe("c.md");
    expect(last.className).toContain("text-neutral-300");
  });
});
