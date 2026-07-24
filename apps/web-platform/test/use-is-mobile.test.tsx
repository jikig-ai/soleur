import { describe, it, expect, vi, afterEach } from "vitest";
import { renderToStaticMarkup } from "react-dom/server";
import { useIsMobile } from "@/hooks/use-is-mobile";

afterEach(() => vi.unstubAllGlobals());

function Probe() {
  return <span>{useIsMobile() ? "mobile" : "desktop"}</span>;
}

describe("useIsMobile hydration-safe seed", () => {
  it("seeds desktop (false) on server render even when the viewport matches mobile", () => {
    // The whole reason this hook exists: if it ever seeds from
    // `matchMedia().matches` (like use-media-query.ts), the server render emits
    // 'mobile' while the first client render emits 'desktop' — the hydration
    // mismatch that broke the mobile kanban board (learning
    // 2026-07-23-mobile-responsive-dual-render-and-tablist-a11y.md). The
    // `matches: true` stub is load-bearing: it proves the seed ignores the live
    // viewport rather than a no-stub render coincidentally reading desktop.
    vi.stubGlobal("matchMedia", () => ({
      matches: true,
      addEventListener() {},
      removeEventListener() {},
    }));
    expect(renderToStaticMarkup(<Probe />)).toContain("desktop");
  });
});
