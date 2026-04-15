import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { renderHook } from "@testing-library/react";
import { useMediaQuery } from "@/hooks/use-media-query";

type MediaQueryListStub = {
  matches: boolean;
  media: string;
  addEventListener: ReturnType<typeof vi.fn>;
  removeEventListener: ReturnType<typeof vi.fn>;
  dispatchChange: (matches: boolean) => void;
};

function installMatchMedia(initialMatches: boolean): MediaQueryListStub {
  const listeners = new Set<(e: { matches: boolean }) => void>();
  const stub: MediaQueryListStub = {
    matches: initialMatches,
    media: "",
    addEventListener: vi.fn((_event: string, cb: (e: { matches: boolean }) => void) => {
      listeners.add(cb);
    }),
    removeEventListener: vi.fn((_event: string, cb: (e: { matches: boolean }) => void) => {
      listeners.delete(cb);
    }),
    dispatchChange(matches: boolean) {
      stub.matches = matches;
      for (const l of listeners) l({ matches });
    },
  };
  vi.stubGlobal("matchMedia", vi.fn((query: string) => {
    stub.media = query;
    return stub;
  }));
  return stub;
}

describe("useMediaQuery", () => {
  beforeEach(() => {
    vi.unstubAllGlobals();
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("returns the initial matchMedia match value", () => {
    installMatchMedia(true);
    const { result } = renderHook(() => useMediaQuery("(min-width: 768px)"));
    expect(result.current).toBe(true);
  });

  it("returns false when initial match is false", () => {
    installMatchMedia(false);
    const { result } = renderHook(() => useMediaQuery("(min-width: 768px)"));
    expect(result.current).toBe(false);
  });

  it("subscribes via addEventListener('change') on mount", () => {
    const stub = installMatchMedia(false);
    renderHook(() => useMediaQuery("(min-width: 768px)"));
    expect(stub.addEventListener).toHaveBeenCalledWith("change", expect.any(Function));
  });

  it("removes listener on unmount", () => {
    const stub = installMatchMedia(false);
    const { unmount } = renderHook(() => useMediaQuery("(min-width: 768px)"));
    unmount();
    expect(stub.removeEventListener).toHaveBeenCalledWith("change", expect.any(Function));
  });

  it("updates the returned value when matchMedia dispatches a change", async () => {
    const stub = installMatchMedia(false);
    const { result, rerender } = renderHook(() => useMediaQuery("(min-width: 768px)"));
    expect(result.current).toBe(false);
    stub.dispatchChange(true);
    rerender();
    expect(result.current).toBe(true);
  });
});
