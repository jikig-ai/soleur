import { describe, it, expect, vi, afterEach } from "vitest";
import { render, screen, cleanup, within } from "@testing-library/react";
import { KbChatFullScreen } from "@/components/chat/kb-chat-fullscreen";
import { KbBreadcrumb } from "@/components/kb/kb-breadcrumb";

// #7326 — the mobile takeover's chrome.
//
// The #7222 takeover stacked THREE headers on a 390px phone (takeover header,
// C4 tab strip, KbChatContent's own filename + ✕ bar), showed the filename
// twice, offered two competing dismiss controls, and exited via an unlabelled
// 44×44 chevron.

afterEach(() => cleanup());

describe("KbChatFullScreen — the exit says where it goes", () => {
  it("exits via a button whose VISIBLE text is 'Return to file preview'", () => {
    render(
      <KbChatFullScreen
        open
        onClose={vi.fn()}
        contextPath="engineering/architecture/diagrams/c4-model.md"
      >
        <div />
      </KbChatFullScreen>,
    );
    const back = screen.getByTestId("kb-chat-fullscreen-back");
    // Not just an accessible name — the label has to be READABLE. #7222 shipped
    // a bare chevron whose only wording was an aria-label.
    expect(back.textContent).toContain("Return to file preview");
    expect(back.querySelector("svg")).toBeTruthy();
  });

  it("keeps the exit at a 44px touch target", () => {
    render(
      <KbChatFullScreen open onClose={vi.fn()} contextPath="a/b/adr-158.md">
        <div />
      </KbChatFullScreen>,
    );
    expect(screen.getByTestId("kb-chat-fullscreen-back").className).toContain(
      "min-h-11",
    );
  });

  it("names the document ONCE, on a single line", () => {
    render(
      <KbChatFullScreen open onClose={vi.fn()} contextPath="a/b/adr-158.md">
        <div />
      </KbChatFullScreen>,
    );
    const header = screen.getByTestId("kb-chat-fullscreen-header");
    expect(within(header).getAllByText("adr-158.md")).toHaveLength(1);
    expect(within(header).getByText("Asking about")).toBeTruthy();
  });
});

describe("KbBreadcrumb — the filename survives a narrow header", () => {
  it("truncates ANCESTOR segments and never the current one", () => {
    render(<KbBreadcrumb path="engineering/architecture/diagrams/c4-model.md" />);

    const current = screen.getByTestId("kb-breadcrumb-current");
    // The current segment is the filename. A blanket `truncate` on the trail
    // would cut exactly this, which is the one part the user needs.
    expect(current.className).not.toContain("truncate");
    expect(current.parentElement?.className).toContain("shrink-0");

    const ancestor = screen.getByText("engineering");
    expect(ancestor.className).toContain("truncate");
    expect(ancestor.parentElement?.className).toContain("min-w-0");
  });

  it("lets the whole trail shrink so it cannot shove the header actions", () => {
    const { container } = render(<KbBreadcrumb path="a/b/c.md" />);
    const nav = container.querySelector("nav") as HTMLElement;
    // Without min-w-0 a flex child takes its max-content width — that is what
    // pushed the gold trigger off a 390px screen.
    expect(nav.className).toContain("min-w-0");
    expect(nav.className).toContain("overflow-hidden");
  });

  it("still exposes every segment to assistive tech and DOM-driving agents", () => {
    render(<KbBreadcrumb path="engineering/architecture/diagrams/c4-model.md" />);
    for (const seg of ["engineering", "architecture", "diagrams", "c4-model.md"]) {
      expect(screen.getByText(seg)).toBeTruthy();
    }
  });
});
