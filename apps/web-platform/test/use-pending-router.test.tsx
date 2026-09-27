import { describe, it, expect, beforeEach, vi } from "vitest";
import { renderHook } from "@testing-library/react";

const { routerMock } = vi.hoisted(() => ({
  routerMock: {
    push: vi.fn(),
    replace: vi.fn(),
    refresh: vi.fn(),
    back: vi.fn(),
    forward: vi.fn(),
    prefetch: vi.fn(),
    bfcacheId: "bf-test-id",
  },
}));

vi.mock("next/navigation", () => ({
  useRouter: () => routerMock,
}));

vi.mock("@/lib/nav-pending-store", () => ({
  startNavPending: vi.fn(),
  isSameDocTarget: vi.fn(() => false),
}));

import { isSameDocTarget, startNavPending } from "@/lib/nav-pending-store";
import { usePendingRouter } from "@/hooks/use-pending-router";

// feat-ui-action-feedback Layer 2 trigger (b): push/replace fire the bar only
// for cross-doc targets and ALWAYS delegate; refresh/back/forward/prefetch and
// bfcacheId pass through untouched (refresh must never fire — ~22+ callers).

describe("usePendingRouter", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.mocked(isSameDocTarget).mockReturnValue(false);
  });

  it("push to a different doc starts the episode and delegates", () => {
    const { result } = renderHook(() => usePendingRouter());
    result.current.push("/inbox");
    expect(startNavPending).toHaveBeenCalledTimes(1);
    expect(startNavPending).toHaveBeenCalledWith("router");
    expect(routerMock.push).toHaveBeenCalledWith("/inbox");
  });

  it("push to the SAME doc still delegates but never starts (kieran #12)", () => {
    vi.mocked(isSameDocTarget).mockReturnValue(true);
    const { result } = renderHook(() => usePendingRouter());
    result.current.push("/inbox?tab=1");
    expect(startNavPending).not.toHaveBeenCalled();
    expect(routerMock.push).toHaveBeenCalledWith("/inbox?tab=1");
  });

  it("replace mirrors push: cross-doc starts, same-doc delegates silently", () => {
    const { result } = renderHook(() => usePendingRouter());
    result.current.replace("/kb");
    expect(startNavPending).toHaveBeenCalledWith("router");
    expect(routerMock.replace).toHaveBeenCalledWith("/kb");

    vi.clearAllMocks();
    vi.mocked(isSameDocTarget).mockReturnValue(true);
    result.current.replace("/kb");
    expect(startNavPending).not.toHaveBeenCalled();
    expect(routerMock.replace).toHaveBeenCalledWith("/kb");
  });

  it("forwards NavigateOptions through push", () => {
    const { result } = renderHook(() => usePendingRouter());
    result.current.push("/inbox", { scroll: false });
    expect(routerMock.push).toHaveBeenCalledWith("/inbox", { scroll: false });
  });

  it("refresh() passes through and NEVER fires start()", () => {
    const { result } = renderHook(() => usePendingRouter());
    result.current.refresh();
    expect(routerMock.refresh).toHaveBeenCalledTimes(1);
    expect(startNavPending).not.toHaveBeenCalled();
  });

  it("back/forward/prefetch pass through untouched", () => {
    const { result } = renderHook(() => usePendingRouter());
    result.current.back();
    result.current.forward();
    result.current.prefetch("/inbox");
    expect(routerMock.back).toHaveBeenCalledTimes(1);
    expect(routerMock.forward).toHaveBeenCalledTimes(1);
    expect(routerMock.prefetch).toHaveBeenCalledWith("/inbox", undefined);
    expect(startNavPending).not.toHaveBeenCalled();
    expect(isSameDocTarget).not.toHaveBeenCalled();
  });

  it("exposes exactly the six wrapped router methods — nothing else passes through", () => {
    const { result } = renderHook(() => usePendingRouter());
    for (const key of [
      "push",
      "replace",
      "refresh",
      "back",
      "forward",
      "prefetch",
    ] as const) {
      expect(typeof result.current[key]).toBe("function");
    }
    // Members not in the contract are absent, not forwarded: a future
    // nav-shaped member (e.g. bfcacheId, experimental_gesturePush) must be
    // wrapped deliberately.
    expect(Object.keys(result.current).sort()).toEqual([
      "back",
      "forward",
      "prefetch",
      "push",
      "refresh",
      "replace",
    ]);
  });
});
