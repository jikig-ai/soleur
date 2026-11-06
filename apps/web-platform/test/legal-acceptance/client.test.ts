/**
 * #12011 PR-C: `postJson` maps a network answer to one of four kinds. Only statuses OUR routes emit for a refusal read as
 * `rejected` ("nothing was recorded"); every other status may sit in front of a committed row and reads as `unknown`.
 */
import { afterEach, describe, expect, it, vi } from "vitest";
import { postJson, postLegalDecide, interpretDecide } from "@/lib/legal-acceptance-client";
import { LEGAL_COPY } from "@/lib/legal-acceptance-copy";
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

describe("a 2xx whose body is not JSON is unknown, never rejected", () => {
  // Real Response objects: the parse failure is the platform's own SyntaxError, not a stub.
  const html = (status: number) => vi.fn(async () => new Response("<html><body>Bad gateway page</body></html>", { status, headers: { "content-type": "text/html" } }));

  it.each([200, 201])("postJson: HTTP %i with an HTML body is unknown", async (status) => {
    vi.stubGlobal("fetch", html(status));
    expect(await postJson("/x", {})).toEqual({ kind: "unknown" });
  });

  it("postJson: HTTP 200 with an empty body is unknown", async () => {
    vi.stubGlobal("fetch", vi.fn(async () => new Response("", { status: 200 })));
    expect(await postJson("/x", {})).toEqual({ kind: "unknown" });
  });

  it("postLegalDecide: a 200 non-JSON answer is unknown, and interpretDecide words it as 'reload to check' (never 'nothing was recorded')", async () => {
    vi.stubGlobal("fetch", html(200));
    const post = await postLegalDecide("customer-terms", { choice: "decline", textHash: "a".repeat(64) });
    expect(post).toEqual({ kind: "unknown" });
    const out = interpretDecide(post, { choice: "decline", version: "3" }, false);
    expect(out).toEqual({ kind: "error", message: LEGAL_COPY.errors.unknownResult, reload: true });
    expect(out).not.toMatchObject({ message: LEGAL_COPY.errors.nothingRecorded });
  });

  it("a non-JSON 502 stays unknown and a non-JSON 403 stays rejected (the body only matters for the reverify check)", async () => {
    vi.stubGlobal("fetch", html(502));
    expect(await postJson("/x", {})).toEqual({ kind: "unknown" });
    vi.stubGlobal("fetch", html(403));
    expect(await postJson("/x", {})).toEqual({ kind: "rejected" });
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

describe("postJson deadline without AbortSignal.timeout (property deleted)", () => {
  const original = Object.getOwnPropertyDescriptor(AbortSignal, "timeout");
  const without = () => {
    delete (AbortSignal as unknown as Record<string, unknown>).timeout;
    expect("timeout" in AbortSignal).toBe(false);
  };
  const restore = () => {
    if (original) Object.defineProperty(AbortSignal, "timeout", original);
  };
  afterEach(restore);

  /** A fetch that never answers; it ends only when its signal aborts. */
  const hung = () => {
    const seen: { signal?: AbortSignal } = {};
    const fn = vi.fn(
      (_u: string, init: RequestInit) =>
        new Promise((_res, rej) => {
          seen.signal = init.signal ?? undefined;
          init.signal?.addEventListener("abort", () => rej(new DOMException("aborted", "AbortError")));
        }),
    );
    return { fn, seen };
  };

  it("aborts at the fallback deadline, not before, and returns unknown", async () => {
    vi.useFakeTimers();
    without();
    const { fn, seen } = hung();
    vi.stubGlobal("fetch", fn);
    let settled = false;
    const p = postJson("/x", {}).then((r) => ((settled = true), r));
    await vi.advanceTimersByTimeAsync(PENDING_WATCHDOG_MS - 1);
    expect(seen.signal).toBeInstanceOf(AbortSignal);
    expect(seen.signal?.aborted).toBe(false);
    expect(settled).toBe(false);
    await vi.advanceTimersByTimeAsync(2);
    expect(seen.signal?.aborted).toBe(true);
    expect(await p).toEqual({ kind: "unknown" });
    expect(vi.getTimerCount()).toBe(0);
  });

  it("a deadline that fires while the body is still being read is unknown too", async () => {
    vi.useFakeTimers();
    without();
    vi.stubGlobal(
      "fetch",
      vi.fn(async (_u: string, init: RequestInit) => ({
        ok: true,
        status: 200,
        json: () =>
          new Promise((_res, rej) => {
            init.signal?.addEventListener("abort", () => rej(new DOMException("aborted", "AbortError")));
          }),
      })),
    );
    const p = postJson("/x", {});
    await vi.advanceTimersByTimeAsync(PENDING_WATCHDOG_MS + 1);
    expect(await p).toEqual({ kind: "unknown" });
  });

  it.each([
    ["a 200", () => reply(200, { a: 1 })],
    ["a rejected 400", () => reply(400, { error: "x" })],
    ["a 403 reverify", () => reply(403, { error: "reverify" })],
    ["an unknown 503", () => reply(503, {})],
    ["a network error", () => vi.fn(async () => Promise.reject(new TypeError("network")))],
    ["an unreadable 200", () => vi.fn(async () => ({ ok: true, status: 200, json: async () => Promise.reject(new Error("bad json")) }))],
  ])("the fallback timer is cleared after %s (nothing is left to abort later)", async (_n, make) => {
    vi.useFakeTimers();
    without();
    const clear = vi.spyOn(globalThis, "clearTimeout");
    vi.stubGlobal("fetch", make());
    await postJson("/x", {});
    expect(clear).toHaveBeenCalledTimes(1);
    expect(vi.getTimerCount()).toBe(0);
    clear.mockRestore();
  });

  it("with AbortSignal.timeout present no fallback timer is ever armed", async () => {
    vi.useFakeTimers();
    vi.stubGlobal("fetch", reply(200, { a: 1 }));
    expect(typeof AbortSignal.timeout).toBe("function");
    await postJson("/x", {});
    expect(vi.getTimerCount()).toBe(0);
  });
});
