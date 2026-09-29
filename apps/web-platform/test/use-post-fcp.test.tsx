import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, renderHook, waitFor } from "@testing-library/react";
import useSWR from "swr";
import type { ReactNode } from "react";
import { usePostFcp } from "@/hooks/use-post-fcp";
import { swrKeys } from "@/lib/swr-config";
import { SwrTestProvider } from "./helpers/swr-wrapper";

// #9178 FR4 — the post-FCP deferral primitive: a null-gated SWR key must not
// fire until after first paint (the requestIdleCallback arm — bounded by
// {timeout} so a saturated main thread cannot starve it), then fire exactly
// once. Also the Safari edges: rIC absent → requestAnimationFrame → setTimeout
// (post-first-paint), and neither API → bare setTimeout.

function jsonResponse(body: unknown): Response {
  return {
    ok: true,
    json: async () => body,
    // biome-ignore lint/suspicious/noExplicitAny: minimal Response stub
  } as any;
}

function DeferredProbe() {
  const postFcp = usePostFcp();
  const { data } = useSWR(
    postFcp ? swrKeys.teamNames() : null,
    async () => {
      const res = await fetch("/api/team-names");
      return res.json();
    },
  );
  return (
    <span data-testid="probe">
      {postFcp ? "post-fcp" : "pre-fcp"}:{data ? "loaded" : "none"}
    </span>
  );
}

const freshCache = ({ children }: { children: ReactNode }) => (
  <SwrTestProvider value={{ focusThrottleInterval: 0 }}>{children}</SwrTestProvider>
);

describe("usePostFcp (#9178 — deferred below-fold keys)", () => {
  let fetchSpy: ReturnType<typeof vi.fn>;
  let savedRic: typeof window.requestIdleCallback;
  let savedRaf: typeof window.requestAnimationFrame;
  let savedCancelRic: unknown;
  let savedCancelRaf: unknown;

  beforeEach(() => {
    fetchSpy = vi.fn().mockResolvedValue(
      jsonResponse({ names: {}, nudgesDismissed: [], namingPromptedAt: null }),
    );
    vi.stubGlobal("fetch", fetchSpy);
    savedRic = window.requestIdleCallback;
    savedRaf = window.requestAnimationFrame;
    savedCancelRic = (window as { cancelIdleCallback?: unknown }).cancelIdleCallback;
    savedCancelRaf = (window as { cancelAnimationFrame?: unknown }).cancelAnimationFrame;
  });

  afterEach(() => {
    window.requestIdleCallback = savedRic;
    window.requestAnimationFrame = savedRaf;
    (window as { cancelIdleCallback?: unknown }).cancelIdleCallback = savedCancelRic;
    (window as { cancelAnimationFrame?: unknown }).cancelAnimationFrame = savedCancelRaf;
    vi.unstubAllGlobals();
  });

  it("no fetch before the arm flips; exactly one fetch after it", async () => {
    // happy-dom ships no native requestIdleCallback — this exercises the
    // rAF→setTimeout arm (the rIC arm is pinned by the spy test below).
    render(<DeferredProbe />, { wrapper: freshCache });
    // Pre-paint: the key is null, the deferred fetch must not fire.
    expect(screen.getByTestId("probe").textContent).toBe("pre-fcp:none");
    expect(fetchSpy).not.toHaveBeenCalled();

    // The idle callback arms post-paint → the key engages → exactly one GET.
    await screen.findByText(/post-fcp:loaded/);
    await waitFor(() => expect(fetchSpy).toHaveBeenCalledTimes(1));
    expect(fetchSpy.mock.calls[0][0]).toBe("/api/team-names");
  });

  it("rIC arm carries a bounded {timeout} (starvation cannot gate indefinitely)", async () => {
    const ricSpy = vi.fn(
      (cb: IdleRequestCallback, _opts?: { timeout?: number }) => {
        // Schedule the callback like a real rIC so the probe can flip.
        setTimeout(cb, 0);
        return 1;
      },
    );
    window.requestIdleCallback = ricSpy as unknown as typeof window.requestIdleCallback;
    render(<DeferredProbe />, { wrapper: freshCache });
    await screen.findByText(/post-fcp:loaded/);
    expect(ricSpy).toHaveBeenCalledTimes(1);
    const opts = ricSpy.mock.calls[0][1] as { timeout?: number };
    expect(opts?.timeout).toBeGreaterThan(0);
    expect(opts?.timeout).toBeLessThanOrEqual(5_000);
  });

  it("Safari fallback — rIC absent arms via requestAnimationFrame", async () => {
    // @ts-expect-error — simulating Safari's missing rIC
    window.requestIdleCallback = undefined;
    const rafSpy = vi.fn((cb: FrameRequestCallback) => {
      setTimeout(() => cb(0), 0);
      return 1;
    });
    window.requestAnimationFrame = rafSpy;
    render(<DeferredProbe />, { wrapper: freshCache });
    expect(fetchSpy).not.toHaveBeenCalled();
    await screen.findByText(/post-fcp:loaded/);
    expect(rafSpy).toHaveBeenCalledTimes(1);
    await waitFor(() => expect(fetchSpy).toHaveBeenCalledTimes(1));
  });

  it("last resort — neither rIC nor rAF falls back to bare setTimeout", async () => {
    // @ts-expect-error — simulating engines without either API
    window.requestIdleCallback = undefined;
    // @ts-expect-error — same for rAF
    window.requestAnimationFrame = undefined;
    render(<DeferredProbe />, { wrapper: freshCache });
    expect(fetchSpy).not.toHaveBeenCalled();
    await screen.findByText(/post-fcp:loaded/);
    await waitFor(() => expect(fetchSpy).toHaveBeenCalledTimes(1));
  });

  it("unmount before the arm cancels it (rIC arm — cancel spy)", async () => {
    const cancelSpy = vi.fn();
    // Stub rIC/cancel pair for the unmount-cleanup pin.
    window.requestIdleCallback = vi.fn(() => 42) as unknown as typeof window.requestIdleCallback;
    window.cancelIdleCallback = cancelSpy as unknown as typeof window.cancelIdleCallback;
    const { result, unmount } = renderHook(() => usePostFcp(), {
      wrapper: freshCache,
    });
    expect(result.current).toBe(false);
    unmount();
    expect(cancelSpy).toHaveBeenCalledWith(42);
  });

  it("unmount before the arm cancels it (rAF arm — cancel spy)", async () => {
    // @ts-expect-error — rIC absent → rAF arm
    window.requestIdleCallback = undefined;
    const cancelSpy = vi.fn();
    window.requestAnimationFrame = vi.fn(() => 7);
    window.cancelAnimationFrame = cancelSpy;
    const { result, unmount } = renderHook(() => usePostFcp(), {
      wrapper: freshCache,
    });
    expect(result.current).toBe(false);
    unmount();
    expect(cancelSpy).toHaveBeenCalledWith(7);
  });
});
