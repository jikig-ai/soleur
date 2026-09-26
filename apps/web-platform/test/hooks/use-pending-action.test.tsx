import { describe, it, expect, vi, afterEach } from "vitest";
import { render, screen, act, renderHook, fireEvent } from "@testing-library/react";
import {
  usePendingAction,
  PENDING_WATCHDOG_MS,
} from "@/hooks/use-pending-action";
import { Button } from "@/components/ui/button";
import { reportSilentFallback } from "@/lib/client-observability";

vi.mock("@/lib/client-observability", () => ({
  reportSilentFallback: vi.fn(),
  warnSilentFallback: vi.fn(),
}));

afterEach(() => {
  vi.useRealTimers();
  vi.mocked(reportSilentFallback).mockClear();
});

function deferred() {
  let resolve!: () => void;
  let reject!: (err: unknown) => void;
  const promise = new Promise<void>((res, rej) => {
    resolve = res;
    reject = rej;
  });
  return { promise, resolve, reject };
}

describe("usePendingAction", () => {
  it("pending is true while the action is in flight, false after resolve", async () => {
    const d = deferred();
    const fn = vi.fn(() => d.promise);
    const { result } = renderHook(() => usePendingAction(fn));
    act(() => result.current.run());
    expect(result.current.pending).toBe(true);
    expect(result.current.error).toBeNull();
    await act(async () => d.resolve());
    expect(result.current.pending).toBe(false);
    expect(fn).toHaveBeenCalledTimes(1);
  });

  it("pendingRef covers the click-to-first-render sync gap — a second run() is a no-op", () => {
    const d = deferred();
    const fn = vi.fn(() => d.promise);
    const { result } = renderHook(() => usePendingAction(fn));
    act(() => {
      result.current.run();
      result.current.run();
    });
    expect(fn).toHaveBeenCalledTimes(1);
    expect(result.current.pendingRef.current).toBe(true);
  });

  it("rejection surfaces an Error on the error channel and releases pending", async () => {
    const d = deferred();
    const { result } = renderHook(() => usePendingAction(() => d.promise));
    act(() => result.current.run());
    await act(async () => d.reject(new Error("send failed")));
    expect(result.current.pending).toBe(false);
    expect(result.current.error?.message).toBe("send failed");
  });

  it("non-Error rejections are wrapped into Error", async () => {
    const d = deferred();
    const { result } = renderHook(() => usePendingAction(() => d.promise));
    act(() => result.current.run());
    await act(async () => d.reject("plain string"));
    expect(result.current.error).toBeInstanceOf(Error);
    expect(result.current.error?.message).toBe("plain string");
  });

  it("latchOnRedirect never resets pending once the action resolves", async () => {
    const d = deferred();
    const { result } = renderHook(() =>
      usePendingAction(() => d.promise, { latchOnRedirect: true }),
    );
    act(() => result.current.run());
    await act(async () => d.resolve());
    expect(result.current.pending).toBe(true);
    expect(result.current.pendingRef.current).toBe(true);
    // The latch also blocks re-runs — the redirect owns the teardown.
    act(() => result.current.run());
    expect(result.current.pending).toBe(true);
  });

  it("latchOnRedirect still releases pending on failure", async () => {
    const d = deferred();
    const { result } = renderHook(() =>
      usePendingAction(() => d.promise, { latchOnRedirect: true }),
    );
    act(() => result.current.run());
    await act(async () => d.reject(new Error("boom")));
    expect(result.current.pending).toBe(false);
    expect(result.current.error?.message).toBe("boom");
  });

  it("watchdog mirrors a hung action to Sentry and releases pending at ~30s", () => {
    vi.useFakeTimers();
    const never = new Promise<void>(() => {});
    const { result } = renderHook(() => usePendingAction(() => never));
    act(() => result.current.run());
    expect(result.current.pending).toBe(true);
    act(() => vi.advanceTimersByTime(PENDING_WATCHDOG_MS));
    expect(reportSilentFallback).toHaveBeenCalledTimes(1);
    expect(result.current.pending).toBe(false);
  });

  it("restores focus to the invoking control on resolve when it collapsed to body", async () => {
    const d = deferred();
    function Harness() {
      const { run, pending } = usePendingAction(() => d.promise);
      return (
        <Button loading={pending} onClick={() => run()}>
          Send
        </Button>
      );
    }
    render(<Harness />);
    const btn = screen.getByRole("button", { name: "Send" });
    btn.focus();
    expect(document.activeElement).toBe(btn);
    act(() => fireEvent.click(btn));
    expect(btn).toBeDisabled();
    // Simulate the disabled-flip blur: focus collapsed to <body>. (happy-dom
    // no-ops blur() on a disabled element; body.focus() moves activeElement.)
    document.body.focus();
    expect(document.activeElement).toBe(document.body);
    await act(async () => d.resolve());
    expect(document.activeElement).toBe(btn);
  });
});
