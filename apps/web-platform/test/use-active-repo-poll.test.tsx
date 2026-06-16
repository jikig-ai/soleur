import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { renderHook, waitFor } from "@testing-library/react";
import {
  useActiveRepo,
  __resetActiveRepoCoalesceForTests,
} from "@/hooks/use-active-repo";

// #5394 AC4 controller — the while-`cloning` 2s poll that auto-transitions the
// chat composer to ready WITHOUT a manual refresh. Fake timers are the faithful
// test (no LLM, no prop-rerender proxy): assert the interval fires while
// cloning, self-stops on ready, clears on unmount, and coalesces via inFlight.

function jsonResponse(body: unknown): Response {
  return {
    ok: true,
    json: async () => body,
    // biome-ignore lint/suspicious/noExplicitAny: minimal Response stub
  } as any;
}

describe("useActiveRepo — while-cloning poll (#5394)", () => {
  let fetchSpy: ReturnType<typeof vi.fn>;

  beforeEach(() => {
    __resetActiveRepoCoalesceForTests();
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

    const { result } = renderHook(() => useActiveRepo());

    // Mount fetch (#1).
    await vi.waitFor(() => expect(result.current.data?.repoStatus).toBe("cloning"));
    expect(fetchSpy).toHaveBeenCalledTimes(1);

    // Tick 2s → poll #2 (still cloning).
    await vi.advanceTimersByTimeAsync(2000);
    expect(fetchSpy).toHaveBeenCalledTimes(2);
    expect(result.current.data?.repoStatus).toBe("cloning");

    // Tick 2s → poll #3 returns ready → composer auto-transitions.
    await vi.advanceTimersByTimeAsync(2000);
    expect(fetchSpy).toHaveBeenCalledTimes(3);
    await vi.waitFor(() => expect(result.current.data?.repoStatus).toBe("ready"));

    // Self-stop: no further polls after ready.
    await vi.advanceTimersByTimeAsync(6000);
    expect(fetchSpy).toHaveBeenCalledTimes(3);
  });

  it("does NOT start a poll when the first read is already ready", async () => {
    fetchSpy.mockResolvedValue(
      jsonResponse({ workspaceId: "w", repoStatus: "ready" }),
    );

    const { result } = renderHook(() => useActiveRepo());
    await vi.waitFor(() => expect(result.current.data?.repoStatus).toBe("ready"));
    expect(fetchSpy).toHaveBeenCalledTimes(1);

    await vi.advanceTimersByTimeAsync(6000);
    expect(fetchSpy).toHaveBeenCalledTimes(1);
  });

  it("clears the interval on unmount (no fetch after teardown)", async () => {
    fetchSpy.mockResolvedValue(
      jsonResponse({ workspaceId: "w", repoStatus: "cloning" }),
    );

    const { result, unmount } = renderHook(() => useActiveRepo());
    await vi.waitFor(() => expect(result.current.data?.repoStatus).toBe("cloning"));
    expect(fetchSpy).toHaveBeenCalledTimes(1);

    unmount();
    await vi.advanceTimersByTimeAsync(6000);
    // No additional fetches once unmounted.
    expect(fetchSpy).toHaveBeenCalledTimes(1);
  });
});
