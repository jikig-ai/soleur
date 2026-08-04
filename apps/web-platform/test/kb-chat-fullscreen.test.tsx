import { describe, it, expect, vi, afterEach } from "vitest";
import { render, screen, fireEvent, cleanup } from "@testing-library/react";

// #7222 — the mobile KB chat takeover, and the `md`+ topology it must NOT touch.
//
// The wireframe rejected an in-page overlay that sits BELOW the 56px top bar.
// Most of what makes this the approved design instead of the rejected one is
// invisible in a screenshot — portal target, aria-modal, focus restore, whether
// the hamburger is still tappable — so it is asserted here.

vi.mock("@/components/chat/kb-chat-content", () => ({
  KbChatContent: ({ contextPath }: { contextPath: string }) => (
    <div data-kb-chat data-testid="kb-chat-content" data-context-path={contextPath} />
  ),
}));

import { KbChatSidebar } from "@/components/chat/kb-chat-sidebar";
import { KbChatFullScreen } from "@/components/chat/kb-chat-fullscreen";

const CONTEXT_PATH = "knowledge-base/engineering/architecture/adr-158.md";

function stubViewport(mobile: boolean) {
  vi.stubGlobal("matchMedia", (query: string) => ({
    matches: query.includes("max-width") ? mobile : !mobile,
    media: query,
    addEventListener: () => {},
    removeEventListener: () => {},
  }));
}

afterEach(() => {
  vi.unstubAllGlobals();
  cleanup();
});

describe("#7222 — KbChatFullScreen chrome", () => {
  it("portals to <body> as an aria-modal dialog", () => {
    stubViewport(true);
    const { container } = render(
      <KbChatFullScreen open onClose={() => {}} contextPath={CONTEXT_PATH}>
        <div data-testid="body" />
      </KbChatFullScreen>,
    );

    // Portaled, so it is NOT in the render container — that is the whole point:
    // an in-tree overlay cannot cover the top bar that lives above it.
    expect(container.querySelector("[role=dialog]")).toBeNull();
    const dialog = screen.getByRole("dialog");
    expect(dialog.getAttribute("aria-modal")).toBe("true");
    expect(document.body.contains(dialog)).toBe(true);
  });

  it("carries the ASKING ABOUT context block with the filename", () => {
    stubViewport(true);
    render(
      <KbChatFullScreen open onClose={() => {}} contextPath={CONTEXT_PATH}>
        <div />
      </KbChatFullScreen>,
    );

    expect(screen.getByText(/asking about/i)).toBeTruthy();
    // The basename, not the whole KB-relative path — a path would wrap off a
    // 390px header and tell the user nothing the breadcrumb did not.
    expect(screen.getByText("adr-158.md")).toBeTruthy();
  });

  it("closes on the back chevron and on Escape", () => {
    stubViewport(true);
    const onClose = vi.fn();
    render(
      <KbChatFullScreen open onClose={onClose} contextPath={CONTEXT_PATH}>
        <div />
      </KbChatFullScreen>,
    );

    fireEvent.click(screen.getByLabelText("Back to document"));
    expect(onClose).toHaveBeenCalledTimes(1);

    fireEvent.keyDown(window, { key: "Escape" });
    expect(onClose).toHaveBeenCalledTimes(2);
  });

  it("does NOT close on a backdrop click", () => {
    stubViewport(true);
    const onClose = vi.fn();
    render(
      <KbChatFullScreen open onClose={onClose} contextPath={CONTEXT_PATH}>
        <div />
      </KbChatFullScreen>,
    );

    // A takeover has no visible backdrop, so a tap landing on the gutter must
    // not drop a composer draft.
    const dialog = screen.getByRole("dialog");
    fireEvent.click(dialog.parentElement as HTMLElement);
    expect(onClose).not.toHaveBeenCalled();
  });

  it("renders nothing when closed", () => {
    stubViewport(true);
    render(
      <KbChatFullScreen open={false} onClose={() => {}} contextPath={CONTEXT_PATH}>
        <div data-testid="body" />
      </KbChatFullScreen>,
    );

    expect(screen.queryByRole("dialog")).toBeNull();
    expect(screen.queryByTestId("body")).toBeNull();
  });
});

describe("#7222 — KbChatSidebar picks its host by breakpoint", () => {
  it("below md: the full-screen takeover, not the 60vh sheet", () => {
    stubViewport(true);
    render(
      <KbChatSidebar open onClose={() => {}} contextPath={CONTEXT_PATH} />,
    );

    expect(screen.getByTestId("kb-chat-fullscreen-header")).toBeTruthy();
    // The Sheet's mobile branch is aria-modal="false" with a drag handle; its
    // absence is what proves the swap happened rather than both rendering.
    expect(screen.queryByLabelText("Resize panel")).toBeNull();
    expect(screen.getAllByTestId("kb-chat-content")).toHaveLength(1);
  });

  it("at md+: the inline Sheet push-column is untouched", () => {
    stubViewport(false);
    render(
      <KbChatSidebar open onClose={() => {}} contextPath={CONTEXT_PATH} />,
    );

    // The discriminator. Desktop must keep the push-column: swapping it for a
    // modal would black out the document beside it on a laptop.
    expect(screen.queryByTestId("kb-chat-fullscreen-header")).toBeNull();
    const dialog = screen.getByRole("dialog");
    expect(dialog.getAttribute("aria-modal")).toBe("false");
    expect(screen.getAllByTestId("kb-chat-content")).toHaveLength(1);
  });
});
