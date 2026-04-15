import { describe, it, expect } from "vitest";
import { render } from "@testing-library/react";
import { KbBreadcrumb } from "@/components/kb/kb-breadcrumb";

describe("KbBreadcrumb", () => {
  it("decodes URL-encoded segments", () => {
    const { container, getByTestId } = render(
      <KbBreadcrumb path="overview/Au%20Chat%20P%C3%B4tan%20-%20Pitch.pdf" />,
    );
    expect(container.textContent).toContain("overview");
    expect(getByTestId("kb-breadcrumb-current").textContent).toBe(
      "Au Chat Pôtan - Pitch.pdf",
    );
    expect(container.textContent).not.toContain("%20");
    expect(container.textContent).not.toContain("%C3%B4");
  });

  it("returns raw segment when decoding throws", () => {
    const { getByTestId } = render(<KbBreadcrumb path="folder/bad%E0.txt" />);
    // Malformed percent-escape must not throw; the raw segment is preserved.
    expect(getByTestId("kb-breadcrumb-current").textContent).toBe("bad%E0.txt");
  });

  it("marks the last segment as the current item (aria-current)", () => {
    const { getByTestId } = render(<KbBreadcrumb path="a/b/c.md" />);
    const current = getByTestId("kb-breadcrumb-current");
    expect(current.textContent).toBe("c.md");
    expect(current.getAttribute("aria-current")).toBe("page");
  });
});
