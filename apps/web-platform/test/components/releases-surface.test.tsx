import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { cleanup, render, screen, waitFor } from "@testing-library/react";

// MarkdownRenderer is heavy (react-markdown + lazy c4 diagram); stub it to a
// plain content passthrough so the surface test stays in jsdom.
vi.mock("@/components/ui/markdown-renderer", () => ({
  MarkdownRenderer: ({ content }: { content: string }) => <div>{content}</div>,
}));

import { ReleasesSurface } from "@/components/releases/releases-surface";
import type { ReleaseCard } from "@/server/release-notes";
import { SwrTestProvider } from "../helpers/swr-wrapper";

function card(over: Partial<ReleaseCard> = {}): ReleaseCard {
  return {
    tag: "web-v1.0.0",
    title: "Faster dashboard",
    bodyMarkdown: "Tab switching is instant now.",
    publishedAt: "2026-07-02T00:00:00Z",
    htmlUrl: "https://github.com/jikig-ai/soleur/releases/tag/web-v1.0.0",
    securitySensitive: false,
    ...over,
  };
}

let fetchMock: ReturnType<typeof vi.fn>;
beforeEach(() => {
  fetchMock = vi.fn();
  vi.stubGlobal("fetch", fetchMock);
});
afterEach(() => {
  cleanup();
  vi.unstubAllGlobals();
});

function Wrapped() {
  return (
    <SwrTestProvider>
      <ReleasesSurface />
    </SwrTestProvider>
  );
}

describe("ReleasesSurface", () => {
  it("shows the skeleton while data is undefined", () => {
    fetchMock.mockReturnValue(new Promise(() => {})); // never resolves
    render(<Wrapped />);
    expect(screen.getByTestId("releases-skeleton")).toBeTruthy();
  });

  it("renders reverse-chron cards with Latest badge and View on GitHub link", async () => {
    fetchMock.mockResolvedValue({
      ok: true,
      json: async () => ({
        releases: [
          card({ tag: "web-v2.0.0", title: "Newest" }),
          card({ tag: "web-v1.0.0", title: "Older" }),
        ],
      }),
    });
    render(<Wrapped />);
    await waitFor(() => expect(screen.getByText("web-v2.0.0")).toBeTruthy());
    expect(screen.getByText("web-v1.0.0")).toBeTruthy();
    // "Latest" appears exactly once (first card only).
    expect(screen.getAllByText("Latest")).toHaveLength(1);
    const links = screen.getAllByText("View on GitHub");
    expect(links).toHaveLength(2);
    // Stale bar must NOT be present on a successful feed.
    expect(screen.queryByTestId("stale-refresh-bar")).toBeNull();
  });

  it("renders the empty state when there are no releases", async () => {
    fetchMock.mockResolvedValue({ ok: true, json: async () => ({ releases: [] }) });
    render(<Wrapped />);
    await waitFor(() =>
      expect(screen.getByText(/No releases yet/i)).toBeTruthy(),
    );
  });

  it("renders the cold error surface with a Try again action", async () => {
    fetchMock.mockResolvedValue({ ok: false, status: 502 });
    render(<Wrapped />);
    await waitFor(() =>
      expect(screen.getByText(/Couldn't load releases/i)).toBeTruthy(),
    );
    expect(screen.getByText("Try again")).toBeTruthy();
  });
});
