import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  cleanup,
  fireEvent,
  render,
  screen,
  waitFor,
} from "@testing-library/react";

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
    bump: "minor",
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

  async function renderFeed(releases: ReleaseCard[]) {
    fetchMock.mockResolvedValue({ ok: true, json: async () => ({ releases }) });
    render(<Wrapped />);
    await waitFor(() => expect(screen.getByText(releases[0].tag)).toBeTruthy());
  }

  it("filters cards by the search query (tag/title/body)", async () => {
    await renderFeed([
      card({ tag: "web-v2.0.0", title: "Alpha feature", bodyMarkdown: "x" }),
      card({ tag: "web-v1.0.0", title: "Beta feature", bodyMarkdown: "y" }),
    ]);
    fireEvent.change(screen.getByLabelText("Search releases"), {
      target: { value: "Alpha" },
    });
    expect(screen.getByText("web-v2.0.0")).toBeTruthy();
    expect(screen.queryByText("web-v1.0.0")).toBeNull();
    expect(screen.getByText("1 of 2 releases")).toBeTruthy();
  });

  it("filters by release type (major/minor/patch)", async () => {
    await renderFeed([
      card({ tag: "web-v2.0.0", bump: "major" }),
      card({ tag: "web-v1.1.0", bump: "minor" }),
      card({ tag: "web-v1.0.1", bump: "patch" }),
    ]);
    fireEvent.change(screen.getByLabelText("Filter by release type"), {
      target: { value: "major" },
    });
    expect(screen.getByText("web-v2.0.0")).toBeTruthy();
    expect(screen.queryByText("web-v1.1.0")).toBeNull();
    expect(screen.queryByText("web-v1.0.1")).toBeNull();
  });

  it("sorts oldest-first when selected (Latest badge stays on the newest)", async () => {
    await renderFeed([
      card({ tag: "web-v2.0.0", publishedAt: "2026-07-02T00:00:00Z" }),
      card({ tag: "web-v1.0.0", publishedAt: "2026-07-01T00:00:00Z" }),
    ]);
    fireEvent.change(screen.getByLabelText("Sort releases"), {
      target: { value: "oldest" },
    });
    const tags = screen.getAllByText(/^web-v/).map((el) => el.textContent);
    expect(tags).toEqual(["web-v1.0.0", "web-v2.0.0"]);
    // "Latest" still pinned to the newest (web-v2.0.0), even at the bottom.
    expect(screen.getAllByText("Latest")).toHaveLength(1);
  });

  it("shows a filtered-empty state with a Clear reset", async () => {
    await renderFeed([card({ tag: "web-v2.0.0", title: "Alpha" })]);
    fireEvent.change(screen.getByLabelText("Search releases"), {
      target: { value: "zzz-no-match" },
    });
    expect(screen.getByText(/No releases match/i)).toBeTruthy();
    fireEvent.click(screen.getByText("Clear"));
    expect(screen.getByText("web-v2.0.0")).toBeTruthy();
  });
});
