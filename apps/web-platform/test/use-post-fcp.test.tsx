import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen, renderHook, waitFor } from "@testing-library/react";
import useSWR, { SWRConfig } from "swr";
import type { ReactNode } from "react";
import { usePostFcp } from "@/hooks/use-post-fcp";
import { swrKeys } from "@/lib/swr-config";

// #9178 FR4 — the post-FCP deferral primitive: a null-gated SWR key must not
// fire until after first paint (the requestIdleCallback/setTimeout arm), then
// fire exactly once. Also the Safari edge: requestIdleCallback absent → the
// setTimeout fallback still defers past paint.

function freshCache({ children }: { children: ReactNode }) {
  return (
    <SWRConfig
      value={{
        provider: () => new Map(),
        dedupingInterval: 0,
        focusThrottleInterval: 0,
      }}
    >
      {children}
    </SWRConfig>
  );
}

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

describe("usePostFcp (#9178 — deferred below-fold keys)", () => {
  let fetchSpy: ReturnType<typeof vi.fn>;
  let savedRic: typeof window.requestIdleCallback;

  beforeEach(() => {
    fetchSpy = vi.fn().mockResolvedValue(
      jsonResponse({ names: {}, nudgesDismissed: [], namingPromptedAt: null }),
    );
    vi.stubGlobal("fetch", fetchSpy);
    savedRic = window.requestIdleCallback;
  });

  afterEach(() => {
    window.requestIdleCallback = savedRic;
    vi.unstubAllGlobals();
  });

  it("no fetch before the idle arm; exactly one fetch after it", async () => {
    render(<DeferredProbe />, { wrapper: freshCache });
    // Pre-paint: the key is null, the deferred fetch must not fire.
    expect(screen.getByTestId("probe").textContent).toBe("pre-fcp:none");
    expect(fetchSpy).not.toHaveBeenCalled();

    // The idle callback arms post-paint → the key engages → exactly one GET.
    await screen.findByText(/post-fcp:loaded/);
    await waitFor(() => expect(fetchSpy).toHaveBeenCalledTimes(1));
    expect(fetchSpy.mock.calls[0][0]).toBe("/api/team-names");
  });

  it("Safari fallback — requestIdleCallback absent still arms via setTimeout", async () => {
    // jsdom type allows it; delete simulates the missing API.
    // @ts-expect-error — simulating Safari's missing rIC
    window.requestIdleCallback = undefined;
    render(<DeferredProbe />, { wrapper: freshCache });
    expect(fetchSpy).not.toHaveBeenCalled();
    await screen.findByText(/post-fcp:loaded/);
    await waitFor(() => expect(fetchSpy).toHaveBeenCalledTimes(1));
  });

  it("unmount before the idle arm cancels the flip (no setState-after-unmount)", async () => {
    const { result, unmount } = renderHook(() => usePostFcp(), {
      wrapper: freshCache,
    });
    expect(result.current).toBe(false);
    unmount();
    // Advancing real timers should not warn/set state post-unmount.
    await new Promise((r) => setTimeout(r, 20));
    expect(result.current).toBe(false);
  });
});
