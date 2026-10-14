import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { renderHook, waitFor } from "@testing-library/react";
import useSWR from "swr";
import type { ReactNode } from "react";
import { useActiveRepo } from "@/hooks/use-active-repo";
import { jsonFetcher, swrKeys } from "@/lib/swr-config";
import { SwrTestProvider } from "./helpers/swr-wrapper";

// #5394 AC4 controller — the while-`cloning` 2s poll that auto-transitions the
// chat composer to ready WITHOUT a manual refresh. Fake timers are the faithful
// test (no LLM, no prop-rerender proxy): assert the interval fires while
// cloning, self-stops on ready, clears on unmount.
//
// #9178 port: the hook now rides the shared SWR key (swrKeys.workspaceActiveRepo)
// instead of a module-level inFlight latch. The per-render SWRConfig provider
// gives each test a FRESH cache (the global one is shared across a file's
// tests), and dedupingInterval: 0 makes focus/interval revalidation assertable.
// The coalescing property the latch enforced is now SWR's own per-key in-flight
// join — asserted by the two-consumers test below.

function jsonResponse(body: unknown): Response {
  return {
    ok: true,
    json: async () => body,
    // biome-ignore lint/suspicious/noExplicitAny: minimal Response stub
  } as any;
}

const freshCache = ({ children }: { children: ReactNode }) => (
  <SwrTestProvider value={{ focusThrottleInterval: 0 }}>{children}</SwrTestProvider>
);

describe("useActiveRepo — while-cloning poll (#5394)", () => {
  let fetchSpy: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    vi.useFakeTimers();
    fetchSpy = vi.fn();
    vi.stubGlobal("fetch", fetchSpy);
  });

  afterEach(() => {
    vi.useRealTimers();
    vi.unstubAllGlobals();
  });

  it("polls every 2s while cloning, then self-stops once status reaches ready", async () => {
    // cloning → cloning → ready, then would-be-extra calls return ready.
    fetchSpy
      .mockResolvedValueOnce(jsonResponse({ workspaceId: "w", repoStatus: "cloning" }))
      .mockResolvedValueOnce(jsonResponse({ workspaceId: "w", repoStatus: "cloning" }))
      .mockResolvedValue(jsonResponse({ workspaceId: "w", repoStatus: "ready" }));

    const { result } = renderHook(() => useActiveRepo(), {
      wrapper: freshCache,
    });

    // Mount fetch (#1).
    await vi.waitFor(() => expect(result.current.data?.repoStatus).toBe("cloning"));
    expect(fetchSpy).toHaveBeenCalledTimes(1);

    // Floor pin: the interval must sit OUTSIDE the 2s dedup window — at
    // 2000ms there must be no tick yet (#9180 review: a 2000ms interval
    // inside the window could stretch the effective cadence toward ~4s).
    await vi.advanceTimersByTimeAsync(2000);
    expect(fetchSpy).toHaveBeenCalledTimes(1);

    // Tick 2.1s → poll #2 (still cloning).
    await vi.advanceTimersByTimeAsync(150);
    expect(fetchSpy).toHaveBeenCalledTimes(2);
    expect(result.current.data?.repoStatus).toBe("cloning");

    // Tick → poll #3 returns ready → composer auto-transitions.
    await vi.advanceTimersByTimeAsync(2100);
    expect(fetchSpy).toHaveBeenCalledTimes(3);
    await vi.waitFor(() => expect(result.current.data?.repoStatus).toBe("ready"));

    // Self-stop: no further polls after ready.
    await vi.advanceTimersByTimeAsync(6000);
    expect(fetchSpy).toHaveBeenCalledTimes(3);
  });

  it("self-stops on the error branch too (cloning → error clears the interval)", async () => {
    fetchSpy
      .mockResolvedValueOnce(jsonResponse({ workspaceId: "w", repoStatus: "cloning" }))
      .mockResolvedValue(jsonResponse({ workspaceId: "w", repoStatus: "error" }));

    const { result } = renderHook(() => useActiveRepo(), {
      wrapper: freshCache,
    });
    await vi.waitFor(() => expect(result.current.data?.repoStatus).toBe("cloning"));
    expect(fetchSpy).toHaveBeenCalledTimes(1);

    // Tick 2s → poll #2 returns error → refreshInterval re-evaluates to 0.
    await vi.advanceTimersByTimeAsync(2100);
    expect(fetchSpy).toHaveBeenCalledTimes(2);
    await vi.waitFor(() => expect(result.current.data?.repoStatus).toBe("error"));

    await vi.advanceTimersByTimeAsync(6000);
    expect(fetchSpy).toHaveBeenCalledTimes(2);
  });

  it("does NOT start a poll when the first read is already ready", async () => {
    fetchSpy.mockResolvedValue(
      jsonResponse({ workspaceId: "w", repoStatus: "ready" }),
    );

    const { result } = renderHook(() => useActiveRepo(), {
      wrapper: freshCache,
    });
    await vi.waitFor(() => expect(result.current.data?.repoStatus).toBe("ready"));
    expect(fetchSpy).toHaveBeenCalledTimes(1);

    await vi.advanceTimersByTimeAsync(6000);
    expect(fetchSpy).toHaveBeenCalledTimes(1);
  });

  it("clears the interval on unmount (no fetch after teardown)", async () => {
    fetchSpy.mockResolvedValue(
      jsonResponse({ workspaceId: "w", repoStatus: "cloning" }),
    );

    const { result, unmount } = renderHook(() => useActiveRepo(), {
      wrapper: freshCache,
    });
    await vi.waitFor(() => expect(result.current.data?.repoStatus).toBe("cloning"));
    expect(fetchSpy).toHaveBeenCalledTimes(1);

    unmount();
    await vi.advanceTimersByTimeAsync(6000);
    // No additional fetches once unmounted.
    expect(fetchSpy).toHaveBeenCalledTimes(1);
  });
});

describe("useActiveRepo — shared-key dedup (#9178 FR2)", () => {
  let fetchSpy: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    fetchSpy = vi.fn();
    vi.stubGlobal("fetch", fetchSpy);
  });

  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("two useActiveRepo consumers + one direct SWR reader issue ONE mount GET", async () => {
    fetchSpy.mockResolvedValue(
      jsonResponse({
        workspaceId: "w",
        repoUrl: "https://github.com/a/b",
        repoStatus: "ready",
        fellBackToSolo: false,
      }),
    );

    const { result } = renderHook(
      () => ({
        a: useActiveRepo(),
        b: useActiveRepo(),
        // The OTHER channel: dashboard/page.tsx + useConversations read the
        // same key through useSWR directly — pre-#9178 this and the hook's
        // raw-fetch latch were two parallel fetch channels.
        c: useSWR<{ repoStatus?: string }>(
          swrKeys.workspaceActiveRepo(),
          jsonFetcher,
        ),
      }),
      { wrapper: freshCache },
    );

    await waitFor(() => expect(result.current.a.data?.repoStatus).toBe("ready"));
    await waitFor(() => expect(result.current.b.data?.repoStatus).toBe("ready"));
    await waitFor(() => expect(result.current.c.data?.repoStatus).toBe("ready"));

    const activeRepoCalls = fetchSpy.mock.calls.filter((c) =>
      String(c[0]).includes("/api/workspace/active-repo"),
    );
    expect(activeRepoCalls).toHaveLength(1);
  });
});
