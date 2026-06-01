import { describe, test, expect, vi, beforeEach } from "vitest";
import { renderHook, act, waitFor } from "@testing-library/react";

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

const { mockReport, mockWarn } = vi.hoisted(() => ({
  mockReport: vi.fn(),
  mockWarn: vi.fn(),
}));

vi.mock("@/lib/client-observability", () => ({
  reportSilentFallback: mockReport,
  warnSilentFallback: mockWarn,
}));

import { useReconnect } from "@/components/repo/use-reconnect";

// happy-dom's window.location is not trivially reassignable; replace the
// individual props we read/write under test via defineProperty.
let assignSpy: ReturnType<typeof vi.fn>;

function installLocation(pathname = "/dashboard/kb/some/file") {
  assignSpy = vi.fn();
  Object.defineProperty(window.location, "pathname", {
    configurable: true,
    value: pathname,
  });
  Object.defineProperty(window.location, "assign", {
    configurable: true,
    value: assignSpy,
  });
}

describe("useReconnect", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    installLocation();
    sessionStorage.clear();
  });

  test("calls onReconnected on { installed: true } and never redirects", async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValue(
        new Response(JSON.stringify({ installed: true }), { status: 200 }),
      );
    vi.stubGlobal("fetch", fetchMock);

    const onReconnected = vi.fn();
    const { result } = renderHook(() => useReconnect(onReconnected));

    await act(async () => {
      await result.current.reconnect();
    });

    expect(fetchMock).toHaveBeenCalledWith(
      "/api/repo/detect-installation",
      expect.objectContaining({ method: "POST" }),
    );
    expect(onReconnected).toHaveBeenCalledTimes(1);
    expect(assignSpy).not.toHaveBeenCalled();
    expect(mockReport).not.toHaveBeenCalled();
    expect(mockWarn).not.toHaveBeenCalled();
  });

  test("{ installed: false } warns, persists return_to, and redirects", async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValue(
        new Response(JSON.stringify({ installed: false }), { status: 200 }),
      );
    vi.stubGlobal("fetch", fetchMock);

    const onReconnected = vi.fn();
    const { result } = renderHook(() => useReconnect(onReconnected));

    await act(async () => {
      await result.current.reconnect();
    });

    expect(onReconnected).not.toHaveBeenCalled();
    expect(mockWarn).toHaveBeenCalledTimes(1);
    expect(mockWarn.mock.calls[0][1]).toMatchObject({
      feature: "kb-reconnect",
      op: "detect-installation-fallback",
    });
    expect(sessionStorage.getItem("soleur_return_to")).toBe(
      "/dashboard/kb/some/file",
    );
    expect(assignSpy).toHaveBeenCalledWith(
      "/connect-repo?return_to=" +
        encodeURIComponent("/dashboard/kb/some/file"),
    );
    // warn fired BEFORE redirect
    expect(mockWarn.mock.invocationCallOrder[0]).toBeLessThan(
      assignSpy.mock.invocationCallOrder[0],
    );
  });

  test("network error reports (error level) then redirects", async () => {
    const fetchMock = vi.fn().mockRejectedValue(new Error("boom"));
    vi.stubGlobal("fetch", fetchMock);

    const onReconnected = vi.fn();
    const { result } = renderHook(() => useReconnect(onReconnected));

    await act(async () => {
      await result.current.reconnect();
    });

    expect(onReconnected).not.toHaveBeenCalled();
    expect(mockReport).toHaveBeenCalledTimes(1);
    expect(mockReport.mock.calls[0][1]).toMatchObject({
      feature: "kb-reconnect",
      op: "detect-installation-fallback",
    });
    expect(assignSpy).toHaveBeenCalledTimes(1);
    expect(mockReport.mock.invocationCallOrder[0]).toBeLessThan(
      assignSpy.mock.invocationCallOrder[0],
    );
  });

  test("non-200 response warns and redirects", async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValue(new Response("nope", { status: 500 }));
    vi.stubGlobal("fetch", fetchMock);

    const { result } = renderHook(() => useReconnect(vi.fn()));
    await act(async () => {
      await result.current.reconnect();
    });

    expect(assignSpy).toHaveBeenCalledTimes(1);
  });

  test("still redirects when sessionStorage.setItem throws (Safari private mode)", async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValue(
        new Response(JSON.stringify({ installed: false }), { status: 200 }),
      );
    vi.stubGlobal("fetch", fetchMock);

    const setItemSpy = vi
      .spyOn(Storage.prototype, "setItem")
      .mockImplementation(() => {
        throw new DOMException("QuotaExceededError", "QuotaExceededError");
      });

    try {
      const { result } = renderHook(() => useReconnect(vi.fn()));
      await act(async () => {
        await result.current.reconnect();
      });

      // The storage write threw, but the essential redirect MUST still run.
      expect(assignSpy).toHaveBeenCalledWith(
        "/connect-repo?return_to=" +
          encodeURIComponent("/dashboard/kb/some/file"),
      );
    } finally {
      setItemSpy.mockRestore();
    }
  });

  test("isPending toggles true during the request and clears after", async () => {
    let resolveFetch!: (r: Response) => void;
    const fetchMock = vi.fn(
      () =>
        new Promise<Response>((resolve) => {
          resolveFetch = resolve;
        }),
    );
    vi.stubGlobal("fetch", fetchMock);

    const { result } = renderHook(() => useReconnect(vi.fn()));
    expect(result.current.isPending).toBe(false);

    let pending!: Promise<void>;
    act(() => {
      pending = result.current.reconnect();
    });
    await waitFor(() => expect(result.current.isPending).toBe(true));

    await act(async () => {
      resolveFetch(
        new Response(JSON.stringify({ installed: true }), { status: 200 }),
      );
      await pending;
    });
    expect(result.current.isPending).toBe(false);
  });
});
