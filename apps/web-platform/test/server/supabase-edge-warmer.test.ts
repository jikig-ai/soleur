// supabase-edge-warmer.test.ts — #8978 upstream warm-up: the AC-critical
// property is "a tick failure cannot crash the server" plus the warm request
// targeting the real edge path (GET /rest/v1/, anon apikey, bounded signal).
import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";
import {
  startSupabaseEdgeWarmer,
  supabaseEdgeWarmerTick,
} from "@/server/supabase-edge-warmer";

beforeEach(() => {
  vi.unstubAllEnvs();
});

afterEach(() => {
  vi.unstubAllEnvs();
});

describe("supabaseEdgeWarmerTick", () => {
  test("a fetch that throws resolves to null — the tick never rejects", async () => {
    const fetchImpl = vi.fn().mockRejectedValue(new Error("edge unreachable"));
    await expect(
      supabaseEdgeWarmerTick("https://sup.example.co", "anon", 50, fetchImpl),
    ).resolves.toBeNull();
  });

  test("a fetch that hangs resolves to null via the tick's own AbortSignal timeout", async () => {
    const fetchImpl = vi.fn((_url: string, init?: RequestInit) => {
      const signal = init?.signal;
      return new Promise((_res, rej) => {
        signal?.addEventListener("abort", () =>
          rej(new DOMException("The operation timed out.", "TimeoutError")),
        );
      });
    }) as unknown as typeof fetch;
    await expect(
      supabaseEdgeWarmerTick("https://sup.example.co", "anon", 30, fetchImpl),
    ).resolves.toBeNull();
    expect(fetchImpl).toHaveBeenCalledTimes(1);
  });

  test("a healthy tick returns a duration and hits GET <url>/rest/v1/ with the anon apikey + a signal", async () => {
    const fetchImpl = vi
      .fn()
      .mockResolvedValue(new Response("{}", { status: 200 }));
    const dur = await supabaseEdgeWarmerTick(
      "https://sup.example.co",
      "anon-key-1",
      50,
      fetchImpl,
    );
    expect(dur).not.toBeNull();
    expect(typeof dur).toBe("number");
    const [url, init] = fetchImpl.mock.calls[0] as [string, RequestInit];
    expect(url).toBe("https://sup.example.co/rest/v1/");
    expect((init.headers as Record<string, string>).apikey).toBe("anon-key-1");
    expect(init.signal).toBeInstanceOf(AbortSignal);
  });
});

describe("startSupabaseEdgeWarmer", () => {
  test("no-ops when NEXT_PUBLIC_SUPABASE_* are unset", () => {
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "");
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY", "");
    expect(startSupabaseEdgeWarmer()).toBeUndefined();
  });

  test("arms an unref'd interval; each tick issues the bounded edge request", async () => {
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "https://sup.example.co");
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY", "anon-key-2");
    const fetchImpl = vi
      .fn()
      .mockResolvedValue(new Response("{}", { status: 200 }));
    const callbacks: (() => void)[] = [];
    const unref = vi.fn();
    const setIntervalImpl = vi.fn((cb: () => void) => {
      callbacks.push(cb);
      return { unref } as unknown as ReturnType<typeof setInterval>;
    }) as unknown as typeof setInterval;

    const timer = startSupabaseEdgeWarmer({
      fetchImpl,
      setIntervalImpl,
      intervalMs: 1000,
      tickTimeoutMs: 50,
    });

    expect(setIntervalImpl).toHaveBeenCalledTimes(1);
    expect(unref).toHaveBeenCalledTimes(1);
    expect(timer).toBeDefined();

    callbacks[0]();
    callbacks[0]();
    await vi.waitFor(() => {
      expect(fetchImpl).toHaveBeenCalledTimes(2);
    });
  });

  test("a throwing tick inside the interval cannot crash the caller (fire-and-forget)", async () => {
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "https://sup.example.co");
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_ANON_KEY", "anon-key-3");
    const fetchImpl = vi.fn().mockRejectedValue(new Error("boom"));
    const callbacks: (() => void)[] = [];
    const setIntervalImpl = vi.fn((cb: () => void) => {
      callbacks.push(cb);
      return { unref: vi.fn() } as unknown as ReturnType<typeof setInterval>;
    }) as unknown as typeof setInterval;

    startSupabaseEdgeWarmer({ fetchImpl, setIntervalImpl });
    // The interval body is synchronous void-dispatch; a failing tick resolves
    // to null internally — invoking the callback must not throw or reject.
    expect(() => callbacks[0]()).not.toThrow();
    await vi.waitFor(() => {
      expect(fetchImpl).toHaveBeenCalledTimes(1);
    });
  });
});
