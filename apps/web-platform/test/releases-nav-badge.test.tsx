import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, cleanup, waitFor } from "@testing-library/react";
import type { ReleaseCard } from "@/server/release-notes";

// The badge derives "new version" from the SAME shared SWR key the Releases
// surface uses (swrKeys.releasesList()), so we drive it by controlling useSWR's
// return, plus a device-local last-seen tag in localStorage. Contract: seed
// silently on first load (no dot), gold dot only when the latest tag differs
// from the last-seen one, and NEVER a false signal on a cold/errored fetch.
const useSWRMock = vi.fn();
vi.mock("swr", async (importOriginal) => {
  const actual = await importOriginal<typeof import("swr")>();
  return { ...actual, default: (...args: unknown[]) => useSWRMock(...args) };
});

const STORAGE_KEY = "soleur:releases:last-seen-tag";

function card(tag: string): ReleaseCard {
  return {
    tag,
    title: tag,
    bodyMarkdown: "notes",
    publishedAt: "2026-07-01T00:00:00.000Z",
    htmlUrl: `https://example.test/${tag}`,
    securitySensitive: false,
    bump: "minor",
  };
}

// Newest-first, matching the server contract (index 0 = latest).
function feed(...tags: string[]): ReleaseCard[] {
  return tags.map(card);
}

beforeEach(() => {
  useSWRMock.mockReset();
  window.localStorage.clear();
});
afterEach(() => cleanup());

async function renderBadge(collapsed = false) {
  const { ReleasesNavBadge } = await import(
    "@/components/dashboard/releases-nav-badge"
  );
  return render(<ReleasesNavBadge collapsed={collapsed} />);
}

describe("ReleasesNavBadge (new version published)", () => {
  it("keys the SAME shared SWR tuple the Releases surface uses (dedup)", async () => {
    useSWRMock.mockReturnValue({ data: feed("web-v1.0.0"), error: undefined });
    await renderBadge();
    const { swrKeys } = await import("@/lib/swr-config");
    expect(useSWRMock.mock.calls[0]![0]).toEqual(swrKeys.releasesList());
  });

  it("seeds silently on first load (no record) — no dot, latest recorded", async () => {
    useSWRMock.mockReturnValue({ data: feed("web-v1.2.0"), error: undefined });
    await renderBadge();
    // No dot for an existing user's first-ever load...
    expect(
      screen.queryByTestId("releases-nav-badge-dot"),
    ).not.toBeInTheDocument();
    // ...but the current latest is now seeded as seen.
    await waitFor(() =>
      expect(window.localStorage.getItem(STORAGE_KEY)).toBe("web-v1.2.0"),
    );
  });

  it("shows a gold dot when a newer tag than last-seen has shipped", async () => {
    window.localStorage.setItem(STORAGE_KEY, "web-v1.2.0");
    useSWRMock.mockReturnValue({
      data: feed("web-v1.3.0", "web-v1.2.0"),
      error: undefined,
    });
    await renderBadge();
    const dot = screen.getByTestId("releases-nav-badge-dot");
    expect(dot).toHaveAccessibleName("New version published");
    expect(dot.className).toContain("bg-soleur-accent-gold-fill");
  });

  it("omits on a rollback — a regressed latest tag is not 'newer' than last-seen", async () => {
    // Device already saw web-v1.3.0; a yank makes the feed's newest web-v1.2.0.
    window.localStorage.setItem(STORAGE_KEY, "web-v1.3.0");
    useSWRMock.mockReturnValue({
      data: feed("web-v1.2.0", "web-v1.1.0"),
      error: undefined,
    });
    await renderBadge();
    expect(
      screen.queryByTestId("releases-nav-badge-dot"),
    ).not.toBeInTheDocument();
  });

  it("omits when the latest tag equals the last-seen tag", async () => {
    window.localStorage.setItem(STORAGE_KEY, "web-v1.3.0");
    useSWRMock.mockReturnValue({
      data: feed("web-v1.3.0", "web-v1.2.0"),
      error: undefined,
    });
    await renderBadge();
    expect(
      screen.queryByTestId("releases-nav-badge-dot"),
    ).not.toBeInTheDocument();
  });

  it("omits on a COLD fetch (data undefined) — never a false dot", async () => {
    window.localStorage.setItem(STORAGE_KEY, "web-v1.2.0");
    useSWRMock.mockReturnValue({ data: undefined, error: new Error("502") });
    await renderBadge();
    expect(
      screen.queryByTestId("releases-nav-badge-dot"),
    ).not.toBeInTheDocument();
  });

  it("renders the collapsed corner dot variant with a rail-matching ring", async () => {
    window.localStorage.setItem(STORAGE_KEY, "web-v1.2.0");
    useSWRMock.mockReturnValue({
      data: feed("web-v1.3.0"),
      error: undefined,
    });
    await renderBadge(true);
    const dot = screen.getByTestId("releases-nav-badge-dot-collapsed");
    expect(dot.className).toMatch(/ring-soleur-bg-surface-1/);
    expect(dot).toHaveAttribute("aria-hidden", "true");
  });
});
