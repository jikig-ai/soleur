/**
 * #12011 PR-C: `postJson` maps a network answer to one of four kinds. Only statuses OUR routes emit for a refusal read as
 * `rejected` ("nothing was recorded"); every other status may sit in front of a committed row and reads as `unknown`.
 */
import { afterEach, describe, expect, it, vi } from "vitest";
import { postJson } from "@/lib/legal-acceptance-client";
import { PENDING_WATCHDOG_MS } from "@/lib/pending-timing";

const reply = (status: number, body: unknown) =>
  vi.fn(async () => ({ ok: status >= 200 && status < 300, status, json: async () => body }));

afterEach(() => {
  vi.unstubAllGlobals();
  vi.useRealTimers();
});

describe("postJson status mapping", () => {
  it.each([400, 401, 404, 413, 415])("HTTP %i is rejected (our routes emit it for a refusal)", async (status) => {
    vi.stubGlobal("fetch", reply(status, { error: "x" }));
    expect(await postJson("/x", {})).toEqual({ kind: "rejected" });
  });

  it("a 403 whose body is {error:'reverify'} is reverify", async () => {
    vi.stubGlobal("fetch", reply(403, { error: "reverify" }));
    expect(await postJson("/x", {})).toEqual({ kind: "reverify" });
  });

  it("a CSRF or non-web 403 {error:'Forbidden'} is rejected, NOT reverify (isReverifyBody must look at the body)", async () => {
    vi.stubGlobal("fetch", reply(403, { error: "Forbidden" }));
    expect(await postJson("/x", {})).toEqual({ kind: "rejected" });
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: false, status: 403, json: async () => Promise.reject(new Error("not json")) })));
    expect(await postJson("/x", {})).toEqual({ kind: "rejected" });
  });

  it.each([408, 409, 429, 499, 500, 502, 503, 504])("HTTP %i is unknown (a row can be committed behind it)", async (status) => {
    vi.stubGlobal("fetch", reply(status, { error: "x" }));
    expect(await postJson("/x", {})).toEqual({ kind: "unknown" });
  });

  it("a network error and an unreadable 200 are unknown; a readable 200 is ok", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => Promise.reject(new TypeError("network"))));
    expect(await postJson("/x", {})).toEqual({ kind: "unknown" });
    vi.stubGlobal("fetch", vi.fn(async () => ({ ok: true, status: 200, json: async () => Promise.reject(new Error("bad json")) })));
    expect(await postJson("/x", {})).toEqual({ kind: "unknown" });
    vi.stubGlobal("fetch", reply(200, { a: 1 }));
    expect(await postJson("/x", {})).toEqual({ kind: "ok", value: { a: 1 } });
  });
});

describe("postJson deadline", () => {
  it("passes an AbortSignal.timeout signal when the runtime has one", async () => {
    const f = reply(200, {});
    vi.stubGlobal("fetch", f);
    await postJson("/x", {});
    expect((f.mock.calls[0] as unknown[])[1]).toMatchObject({ signal: expect.any(AbortSignal) });
  });

  it("falls back to an AbortController and a timer when AbortSignal.timeout is missing: a hung request ends as unknown", async () => {
    vi.useFakeTimers();
    const original = AbortSignal.timeout;
    Object.defineProperty(AbortSignal, "timeout", { configurable: true, value: undefined });
    try {
      vi.stubGlobal(
        "fetch",
        vi.fn(
          (_u: string, init: RequestInit) =>
            new Promise((_res, rej) => {
              init.signal?.addEventListener("abort", () => rej(new DOMException("aborted", "AbortError")));
            }),
        ),
      );
      const p = postJson("/x", {});
      await vi.advanceTimersByTimeAsync(PENDING_WATCHDOG_MS + 1);
      expect(await p).toEqual({ kind: "unknown" });
    } finally {
      Object.defineProperty(AbortSignal, "timeout", { configurable: true, value: original });
    }
  });

  it("the fallback timer is cleared once the answer arrives (no stray abort later)", async () => {
    vi.useFakeTimers();
    const original = AbortSignal.timeout;
    Object.defineProperty(AbortSignal, "timeout", { configurable: true, value: undefined });
    try {
      vi.stubGlobal("fetch", reply(200, { a: 1 }));
      expect(await postJson("/x", {})).toEqual({ kind: "ok", value: { a: 1 } });
      expect(vi.getTimerCount()).toBe(0);
    } finally {
      Object.defineProperty(AbortSignal, "timeout", { configurable: true, value: original });
    }
  });
});
