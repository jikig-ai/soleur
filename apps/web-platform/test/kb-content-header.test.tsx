import { describe, it, expect, vi } from "vitest";
import { render } from "@testing-library/react";

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
