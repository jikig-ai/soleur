import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { renderHook, act } from "@testing-library/react";

// #7222 — the embedded Concierge (C4 workspace) default is VIEWPORT-DERIVED.
//
// `c4-workspace.test.tsx` covers the TOPOLOGY (split vs overlay) but drives it
// from its own `useState(true)` harness, so it cannot see this default at all.
// The operator's report was "the chat should be closed by default" — that is
// this value, and it lives in `useKbLayoutState`, so it is pinned here.

const { pathnameRef } = vi.hoisted(() => ({
  pathnameRef: { current: "/dashboard/kb/diagrams/c4-model.md" as string },
}));

vi.mock("next/navigation", () => ({
  usePathname: () => pathnameRef.current,
  useRouter: () => ({ push: vi.fn(), replace: vi.fn(), prefetch: vi.fn() }),
  useSearchParams: () => new URLSearchParams(),
}));

vi.mock("react-resizable-panels", () => ({
  usePanelRef: () => ({ current: null }),
}));

// The tree fetch and the thread-info prefetch both go through useSWR; neither
// feeds the value under test, so a single inert stub covers both keys.
vi.mock("swr", () => ({
  default: () => ({ data: undefined, error: undefined, mutate: vi.fn() }),
}));

vi.mock("@/components/feature-flags/provider", () => ({
  useFeatureFlag: () => true,
  useOptionalFeatureFlag: () => true,
}));

vi.mock("@/hooks/use-nav-resume", () => ({
  useNavResume: () => ({
    workspaceId: null,
    readExpanded: () => [],
    writeExpanded: vi.fn(),
    getKbEntryHref: () => "/dashboard/kb",
  }),
}));

import { useKbLayoutState } from "@/hooks/use-kb-layout-state";

function stubViewport(mobile: boolean) {
  vi.stubGlobal("matchMedia", (query: string) => ({
    matches: query.includes("max-width") ? mobile : !mobile,
    media: query,
    addEventListener: () => {},
    removeEventListener: () => {},
  }));
}

beforeEach(() => {
  pathnameRef.current = "/dashboard/kb/diagrams/c4-model.md";
});

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("#7222 — embedded Concierge default follows the breakpoint", () => {
  it("starts CLOSED on mobile so the diagram owns the viewport", () => {
    stubViewport(true);
    const { result } = renderHook(() => useKbLayoutState());

    expect(result.current.chatCtxValue.embeddedConciergeOpen).toBe(false);
  });

  it("starts OPEN on desktop (unchanged behaviour)", () => {
    stubViewport(false);
    const { result } = renderHook(() => useKbLayoutState());

    // The discriminator: without this, the mobile assertion could be satisfied
    // by a blanket `false` that silently regressed the desktop workspace.
    expect(result.current.chatCtxValue.embeddedConciergeOpen).toBe(true);
  });

  it("does not re-open it on mobile when navigating to another document", () => {
    stubViewport(true);
    const { result, rerender } = renderHook(() => useKbLayoutState());

    // Reveal it, then navigate. The close-on-navigate effect restores the
    // DEFAULT — which must stay `false` here, or every phone navigation
    // reinstates the compressed split.
    act(() => result.current.chatCtxValue.revealEmbeddedConcierge?.());
    expect(result.current.chatCtxValue.embeddedConciergeOpen).toBe(true);

    pathnameRef.current = "/dashboard/kb/diagrams/other.md";
    rerender();

    expect(result.current.chatCtxValue.embeddedConciergeOpen).toBe(false);
  });

  it("DOES re-open it on desktop when navigating to another document", () => {
    stubViewport(false);
    const { result, rerender } = renderHook(() => useKbLayoutState());

    act(() => result.current.chatCtxValue.collapseEmbeddedConcierge?.());
    expect(result.current.chatCtxValue.embeddedConciergeOpen).toBe(false);

    pathnameRef.current = "/dashboard/kb/diagrams/other.md";
    rerender();

    expect(result.current.chatCtxValue.embeddedConciergeOpen).toBe(true);
  });
});
