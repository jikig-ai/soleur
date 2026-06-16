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

  // ---------------------------------------------------------------------------
  // FIX 1b — reconnect re-triggers /api/repo/setup when repo_status != ready
  // ---------------------------------------------------------------------------
  describe("re-setup on repo_status != ready (FIX 1b)", () => {
    const REPO_URL = "https://github.com/owner/repo";

    // Build a fetch mock that routes by URL. `statusSequence` drives the
    // /api/repo/status polls; each call shifts the next value (last value
    // sticks). detect returns `{ installed:true, repos }` by default.
    function makeRouter(opts: {
      detect?: Response | (() => Response);
      setup?: Response | (() => Response);
      statusSequence?: Array<{ status: string }>;
    }) {
      const statusSeq = [...(opts.statusSequence ?? [{ status: "ready" }])];
      return vi.fn((input: string, init?: RequestInit) => {
        if (input === "/api/repo/detect-installation") {
          const r =
            typeof opts.detect === "function"
              ? opts.detect()
              : (opts.detect ??
                new Response(
                  JSON.stringify({
                    installed: true,
                    repos: [{ fullName: "owner/repo" }],
                  }),
                  { status: 200 },
                ));
          return Promise.resolve(r);
        }
        if (input === "/api/repo/setup") {
          const r =
            typeof opts.setup === "function"
              ? opts.setup()
              : (opts.setup ??
                new Response(JSON.stringify({ status: "cloning" }), {
                  status: 200,
                }));
          return Promise.resolve(r);
        }
        if (input === "/api/repo/status") {
          const next = statusSeq.length > 1 ? statusSeq.shift()! : statusSeq[0];
          return Promise.resolve(
            new Response(JSON.stringify(next), { status: 200 }),
          );
        }
        void init;
        return Promise.reject(new Error(`unexpected fetch ${input}`));
      });
    }

    test("installed + repoUrl in list + status!=ready → POST setup then poll status to ready → onReconnected", async () => {
      const fetchMock = makeRouter({
        statusSequence: [{ status: "cloning" }, { status: "ready" }],
      });
      vi.stubGlobal("fetch", fetchMock);

      const onReconnected = vi.fn();
      const { result } = renderHook(() =>
        useReconnect(onReconnected, {
          repoUrl: REPO_URL,
          repoStatus: "error",
          pollIntervalMs: 0,
          maxPollAttempts: 5,
        }),
      );

      await act(async () => {
        await result.current.reconnect();
      });

      const calls = fetchMock.mock.calls.map((c) => c[0]);
      expect(calls).toContain("/api/repo/detect-installation");
      // setup POST issued with { repoUrl }
      const setupCall = fetchMock.mock.calls.find(
        (c) => c[0] === "/api/repo/setup",
      );
      expect(setupCall).toBeDefined();
      expect(setupCall![1]).toMatchObject({ method: "POST" });
      expect(JSON.parse((setupCall![1] as RequestInit).body as string)).toEqual(
        { repoUrl: REPO_URL },
      );
      // status polled to terminal
      expect(calls).toContain("/api/repo/status");
      expect(onReconnected).toHaveBeenCalledTimes(1);
      expect(assignSpy).not.toHaveBeenCalled();
    });

    test("repoStatus === 'ready' → NO setup POST, onReconnected directly", async () => {
      const fetchMock = makeRouter({});
      vi.stubGlobal("fetch", fetchMock);

      const onReconnected = vi.fn();
      const { result } = renderHook(() =>
        useReconnect(onReconnected, {
          repoUrl: REPO_URL,
          repoStatus: "ready",
          pollIntervalMs: 0,
          maxPollAttempts: 5,
        }),
      );

      await act(async () => {
        await result.current.reconnect();
      });

      const calls = fetchMock.mock.calls.map((c) => c[0]);
      expect(calls).not.toContain("/api/repo/setup");
      expect(onReconnected).toHaveBeenCalledTimes(1);
    });

    test("installed:false → /connect-repo redirect, no setup POST", async () => {
      const fetchMock = makeRouter({
        detect: new Response(JSON.stringify({ installed: false }), {
          status: 200,
        }),
      });
      vi.stubGlobal("fetch", fetchMock);

      const onReconnected = vi.fn();
      const { result } = renderHook(() =>
        useReconnect(onReconnected, {
          repoUrl: REPO_URL,
          repoStatus: "error",
          pollIntervalMs: 0,
          maxPollAttempts: 5,
        }),
      );

      await act(async () => {
        await result.current.reconnect();
      });

      const calls = fetchMock.mock.calls.map((c) => c[0]);
      expect(calls).not.toContain("/api/repo/setup");
      expect(onReconnected).not.toHaveBeenCalled();
      expect(assignSpy).toHaveBeenCalledTimes(1);
    });

    test("repoUrl NOT in returned repo list → /connect-repo redirect (reachability guard)", async () => {
      const fetchMock = makeRouter({
        detect: new Response(
          JSON.stringify({
            installed: true,
            repos: [{ fullName: "someone/other" }],
          }),
          { status: 200 },
        ),
      });
      vi.stubGlobal("fetch", fetchMock);

      const onReconnected = vi.fn();
      const { result } = renderHook(() =>
        useReconnect(onReconnected, {
          repoUrl: REPO_URL,
          repoStatus: "error",
          pollIntervalMs: 0,
          maxPollAttempts: 5,
        }),
      );

      await act(async () => {
        await result.current.reconnect();
      });

      const calls = fetchMock.mock.calls.map((c) => c[0]);
      expect(calls).not.toContain("/api/repo/setup");
      expect(onReconnected).not.toHaveBeenCalled();
      expect(assignSpy).toHaveBeenCalledTimes(1);
    });

    test("setup POST non-200 → client Sentry captureException (op reconnect-resetup) + still resolves (no dead button)", async () => {
      const fetchMock = makeRouter({
        setup: new Response("boom", { status: 500 }),
      });
      vi.stubGlobal("fetch", fetchMock);

      const onReconnected = vi.fn();
      const { result } = renderHook(() =>
        useReconnect(onReconnected, {
          repoUrl: REPO_URL,
          repoStatus: "error",
          pollIntervalMs: 0,
          maxPollAttempts: 5,
        }),
      );

      // Must resolve (no throw) — dead-button guard (#4712).
      await act(async () => {
        await result.current.reconnect();
      });

      expect(mockReport).toHaveBeenCalledTimes(1);
      expect(mockReport.mock.calls[0][1]).toMatchObject({
        feature: "kb-reconnect",
        op: "reconnect-resetup",
      });
      expect(onReconnected).not.toHaveBeenCalled();
      // pending cleared — button is usable again
      expect(result.current.isPending).toBe(false);
    });

    test("background clone fails → status polls to error → terminal state, NO onReconnected (no spinner-forever)", async () => {
      const fetchMock = makeRouter({
        statusSequence: [{ status: "cloning" }, { status: "error" }],
      });
      vi.stubGlobal("fetch", fetchMock);

      const onReconnected = vi.fn();
      const { result } = renderHook(() =>
        useReconnect(onReconnected, {
          repoUrl: REPO_URL,
          repoStatus: "error",
          pollIntervalMs: 0,
          maxPollAttempts: 5,
        }),
      );

      await act(async () => {
        await result.current.reconnect();
      });

      const calls = fetchMock.mock.calls.map((c) => c[0]);
      expect(calls).toContain("/api/repo/status");
      // poll reached a terminal `error` — DO NOT refresh as if ready
      expect(onReconnected).not.toHaveBeenCalled();
      expect(result.current.resetupError).toBe(true);
      expect(result.current.isPending).toBe(false);
    });
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
