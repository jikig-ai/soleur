import { describe, it, expect, vi, beforeEach } from "vitest";
import { render, screen, fireEvent, within } from "@testing-library/react";

// DC3 (#7186) — below `md` the secondary doc actions move behind an overflow
// menu. Single-mount by construction: ONE cluster renders, gated in JS.
let mockIsMobile = false;
vi.mock("@/hooks/use-is-mobile", () => ({
  useIsMobile: () => mockIsMobile,
}));

vi.mock("@/components/kb/kb-sync-status", () => ({
  KbSyncStatus: () => <div data-testid="kb-sync-status" />,
}));

vi.mock("@/components/kb/share-popover", () => ({
  SharePopover: ({ documentPath }: { documentPath: string }) => (
    <div data-testid="share-popover" data-path={documentPath} />
  ),
}));

vi.mock("@/components/kb/kb-chat-trigger", () => ({
  KbChatTrigger: ({ fallbackHref }: { fallbackHref: string }) => (
    <div data-testid="chat-trigger" data-href={fallbackHref} />
  ),
}));

vi.mock("@/components/kb/kb-breadcrumb", () => ({
  KbBreadcrumb: ({ path }: { path: string }) => (
    <div data-testid="kb-breadcrumb" data-path={path} />
  ),
}));

import { KbContentHeader } from "@/components/kb/kb-content-header";

beforeEach(() => {
  mockIsMobile = false;
});

describe("KbContentHeader", () => {
  it("renders breadcrumb, share popover, and chat trigger without download", () => {
    const { container, queryByTestId } = render(
      <KbContentHeader
        joinedPath="notes/foo.md"
        chatUrl="/dashboard/chat/new?msg=x"
      />,
    );
    expect(queryByTestId("kb-breadcrumb")?.getAttribute("data-path")).toBe(
      "notes/foo.md",
    );
    expect(queryByTestId("share-popover")?.getAttribute("data-path")).toBe(
      "notes/foo.md",
    );
    expect(queryByTestId("chat-trigger")?.getAttribute("data-href")).toBe(
      "/dashboard/chat/new?msg=x",
    );
    const downloadAnchor = container.querySelector(
      "a[data-testid='kb-content-download']",
    );
    expect(downloadAnchor).toBeNull();
  });

  it("renders the download anchor with href / download / aria-label when download prop is set", () => {
    const { container } = render(
      <KbContentHeader
        joinedPath="notes/foo.pdf"
        chatUrl="/dashboard/chat/new?msg=x"
        download={{ href: "/api/kb/content/notes/foo.pdf", filename: "foo.pdf" }}
      />,
    );
    const anchor = container.querySelector<HTMLAnchorElement>(
      "a[data-testid='kb-content-download']",
    );
    expect(anchor).toBeTruthy();
    expect(anchor?.getAttribute("href")).toBe(
      "/api/kb/content/notes/foo.pdf",
    );
    expect(anchor?.getAttribute("download")).toBe("foo.pdf");
    expect(anchor?.getAttribute("aria-label")).toBe("Download foo.pdf");
  });
});

// DC3 (#7186), operator-approved 2026-08-03. Four trailing actions do not fit
// 375px. Download and Share are NOT dropped — Download is the only way to
// consume a non-markdown attachment on a phone — they move behind a `⋯`.
describe("KbContentHeader — mobile overflow (DC3)", () => {
  const props = {
    joinedPath: "notes/foo.pdf",
    chatUrl: "/dashboard/chat/new?msg=x",
    download: { href: "/api/kb/content/notes/foo.pdf", filename: "foo.pdf" },
    lastSync: null,
  };

  it("desktop keeps the inline cluster and renders no overflow trigger", () => {
    render(<KbContentHeader {...props} />);
    expect(screen.getByTestId("kb-content-download")).toBeInTheDocument();
    expect(screen.getByTestId("share-popover")).toBeInTheDocument();
    expect(screen.getByTestId("kb-sync-status")).toBeInTheDocument();
    expect(screen.queryByTestId("kb-header-overflow-trigger")).toBeNull();
  });

  it("mobile hides the secondary actions behind a ⋯ trigger, keeping Ask visible", () => {
    mockIsMobile = true;
    render(<KbContentHeader {...props} />);

    expect(screen.getByTestId("chat-trigger")).toBeInTheDocument();
    const trigger = screen.getByTestId("kb-header-overflow-trigger");
    expect(trigger).toHaveAttribute("aria-haspopup", "menu");
    expect(trigger).toHaveAttribute("aria-expanded", "false");

    // Closed: the secondary actions are not mounted…
    expect(screen.queryByTestId("kb-content-download")).toBeNull();
    expect(screen.queryByTestId("share-popover")).toBeNull();
    expect(screen.queryByTestId("kb-sync-status")).toBeNull();
  });

  it("mobile: opening the menu exposes Download, sync status and Share exactly once each", () => {
    mockIsMobile = true;
    render(<KbContentHeader {...props} />);

    fireEvent.click(screen.getByTestId("kb-header-overflow-trigger"));
    const menu = screen.getByTestId("kb-header-overflow-menu");
    expect(menu).toHaveAttribute("role", "menu");

    // Single-mount: a `md:hidden` twin would make each of these two.
    expect(screen.getAllByTestId("kb-content-download")).toHaveLength(1);
    expect(screen.getAllByTestId("share-popover")).toHaveLength(1);
    expect(screen.getAllByTestId("kb-sync-status")).toHaveLength(1);
    expect(within(menu).getByTestId("kb-content-download")).toBeInTheDocument();
    expect(within(menu).getByTestId("share-popover")).toBeInTheDocument();
    expect(
      screen.getByTestId("kb-header-overflow-trigger"),
    ).toHaveAttribute("aria-expanded", "true");
  });

  it("mobile: Escape closes the menu and restores focus to the trigger", () => {
    mockIsMobile = true;
    render(<KbContentHeader {...props} />);

    const trigger = screen.getByTestId("kb-header-overflow-trigger");
    fireEvent.click(trigger);
    expect(screen.getByTestId("kb-header-overflow-menu")).toBeInTheDocument();

    fireEvent.keyDown(document, { key: "Escape" });
    expect(screen.queryByTestId("kb-header-overflow-menu")).toBeNull();
    expect(document.activeElement).toBe(trigger);
  });

  it("mobile: an outside pointerdown closes the menu", () => {
    mockIsMobile = true;
    render(<KbContentHeader {...props} />);

    fireEvent.click(screen.getByTestId("kb-header-overflow-trigger"));
    expect(screen.getByTestId("kb-header-overflow-menu")).toBeInTheDocument();

    fireEvent.pointerDown(document.body);
    expect(screen.queryByTestId("kb-header-overflow-menu")).toBeNull();
  });

  it("mobile: a document with no download still gets a usable menu (Share + sync)", () => {
    mockIsMobile = true;
    render(
      <KbContentHeader
        joinedPath="notes/foo.md"
        chatUrl="/dashboard/chat/new?msg=x"
        lastSync={null}
      />,
    );
    fireEvent.click(screen.getByTestId("kb-header-overflow-trigger"));
    const menu = screen.getByTestId("kb-header-overflow-menu");
    expect(within(menu).queryByTestId("kb-content-download")).toBeNull();
    expect(within(menu).getByTestId("share-popover")).toBeInTheDocument();
  });
});
