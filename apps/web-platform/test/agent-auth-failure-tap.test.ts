// Agent auth-failure diagnostic: the in-place Query tap, against fixtures that model the REAL SDK Query shape
// (measured from sdk.mjs, 0.3.284): the Query class has its OWN next/return/throw that delegate to an internal generator,
// and its [Symbol.asyncIterator]() is `return this.sdkMessages` (an AsyncGenerator, so it READS `this`). `for await`
// therefore never touches Query.next. Two fixtures: a hand-written stream with call counters (makeRealShapeQuery), and one
// built from a real `async function*` (makeGeneratorQuery) whose `return()` queues behind a pending `next()`.
// Plan Phase 1 items 2b and 6 (consumeStream case).
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const h = vi.hoisted(() => ({ warn: vi.fn() }));
// Only the diagnostic's own child logger is replaced; the real logger serves everything else (the runner under test).
vi.mock("@/server/logger", async (importOriginal) => {
  const real = await importOriginal<typeof import("@/server/logger")>();
  return {
    ...real,
    createChildLogger: vi.fn((name: string, ...rest: unknown[]) =>
      name === "auth-failure-probe"
        ? { info: vi.fn(), warn: h.warn, error: vi.fn(), debug: vi.fn() }
        : (real.createChildLogger as (...a: unknown[]) => unknown)(name, ...rest),
    ),
  };
});

import { createSoleurGoRunner, type QueryFactory } from "@/server/soleur-go-runner";
import { __resetAgentAuthMatcherWarnForTests, tapAgentAuthFailure } from "@/server/agent-auth-failure";
import { createMockQueryLean, flushMicrotasks, makeResult } from "./helpers/soleur-go-fixtures";

function makeRealShapeQuery(messages: Array<{ n: number }>, opts: { failAt?: number; error?: Error } = {}) {
  let i = 0;
  const stream = {
    started: false,
    [Symbol.asyncIterator]() {
      if (this.started) throw new Error("Stream can only be iterated once");
      this.started = true;
      return this;
    },
    next: vi.fn(async (): Promise<IteratorResult<{ n: number }>> => {
      if (opts.failAt !== undefined && i === opts.failAt) throw opts.error ?? new Error("stream failed");
      if (i < messages.length) return { value: messages[i++], done: false };
      return { value: undefined, done: true };
    }),
    return: vi.fn(async (_value?: unknown): Promise<IteratorResult<{ n: number }>> => ({ value: undefined, done: true })),
    throw: vi.fn(async (e: unknown): Promise<IteratorResult<{ n: number }>> => {
      throw e;
    }),
  };
  class FakeQuery {
    // Own Query methods that delegate to the stream, as in the SDK. `for await` must never reach these.
    next = vi.fn((...a: []) => stream.next(...a));
    close = vi.fn(async () => undefined);
    interrupt = vi.fn(async () => undefined);
    async return(v?: unknown) {
      return stream.return(v);
    }
    async throw(e: unknown) {
      return stream.throw(e);
    }
    // As in the SDK this reads `this`: calling it unbound throws, which is why the tap binds it to the query.
    sdkMessages = stream;
    [Symbol.asyncIterator]() {
      return this.sdkMessages;
    }
  }
  return { query: new FakeQuery(), stream };
}

/** A Query whose iterator is a REAL async generator: `return()` queues behind a pending `next()` and runs `finally`. */
function makeGeneratorQuery(messages: Array<{ n: number }>, gate?: Promise<void>) {
  const state = { cleaned: 0 };
  async function* generate() {
    try {
      if (gate) await gate;
      for (const m of messages) {
        await Promise.resolve();
        yield m;
      }
    } finally {
      state.cleaned += 1;
    }
  }
  class GeneratorQuery {
    sdkMessages = generate();
    [Symbol.asyncIterator]() {
      return this.sdkMessages;
    }
  }
  return { query: new GeneratorQuery(), state };
}

let unhandled: unknown[];
const onUnhandled = (reason: unknown) => {
  unhandled.push(reason);
};
beforeEach(() => {
  unhandled = [];
  h.warn.mockClear();
  __resetAgentAuthMatcherWarnForTests();
  process.on("unhandledRejection", onUnhandled);
});
afterEach(() => {
  process.off("unhandledRejection", onUnhandled);
});
const settle = () => new Promise<void>((r) => setTimeout(r, 20));

const msgs = (k: number) => Array.from({ length: k }, (_, n) => ({ n }));
const collect = async (q: AsyncIterable<unknown>) => {
  const out: unknown[] = [];
  for await (const m of q) out.push(m);
  return out;
};

describe("tapAgentAuthFailure against the measured Query shape", () => {
  it("returns the SAME object (identity), leaves its other members alone, and observes every message in order", async () => {
    const { query, stream } = makeRealShapeQuery(msgs(4));
    const closeBefore = query.close;
    const nextBefore = query.next;
    const probe = { observe: vi.fn() };
    const tapped = tapAgentAuthFailure(query, probe);
    expect(tapped).toBe(query);
    expect(query.close).toBe(closeBefore);
    expect(query.next).toBe(nextBefore);

    expect(await collect(tapped)).toEqual(msgs(4));
    expect(probe.observe.mock.calls.map((c) => c[0])).toEqual(msgs(4));
    // The wrapper never re-entered the Stream's own iterator method, and the Query's own next was never used.
    expect(stream.started).toBe(false);
    expect(query.next).not.toHaveBeenCalled();
  });

  it("`break` runs the underlying return exactly once", async () => {
    const { query, stream } = makeRealShapeQuery(msgs(5));
    const tapped = tapAgentAuthFailure(query, { observe: vi.fn() });
    for await (const m of tapped) {
      if ((m as { n: number }).n === 1) break;
    }
    expect(stream.return).toHaveBeenCalledTimes(1);
  });

  it("an underlying throw propagates unchanged and the messages before it were observed", async () => {
    const boom = new Error("underlying failure");
    const { query } = makeRealShapeQuery(msgs(3), { failAt: 2, error: boom });
    const probe = { observe: vi.fn() };
    const tapped = tapAgentAuthFailure(query, probe);
    const seen: unknown[] = [];
    const failure = await (async () => {
      try {
        for await (const m of tapped) seen.push(m);
      } catch (e) {
        return e;
      }
      return undefined;
    })();
    expect(failure).toBe(boom);
    expect(seen).toEqual(msgs(2));
    expect(probe.observe).toHaveBeenCalledTimes(2);
    await settle();
    expect(unhandled).toEqual([]); // the side branch must not surface the underlying rejection a second time
  });

  it("an observer that throws synchronously, or returns a rejected promise, never alters the stream", async () => {
    for (const observe of [
      vi.fn(() => {
        throw new Error("observer");
      }),
      vi.fn(() => Promise.reject(new Error("observer async"))),
    ]) {
      const { query } = makeRealShapeQuery(msgs(3));
      const tapped = tapAgentAuthFailure(query, { observe });
      expect(await collect(tapped)).toEqual(msgs(3));
      expect(observe).toHaveBeenCalledTimes(3);
    }
    await settle();
    expect(unhandled).toEqual([]);
  });

  it("a result whose done/value getter throws is swallowed: no unhandled rejection, and ONE tap-specific warn", async () => {
    let calls = 0;
    const hostileResult = {
      get done(): boolean {
        calls += 1;
        throw new Error("CANARY-GETTER-9c1e");
      },
      value: { n: 1 },
    };
    const query = {
      [Symbol.asyncIterator]() {
        return { next: async () => hostileResult };
      },
    };
    const probe = { observe: vi.fn() };
    const it = (tapAgentAuthFailure(query, probe) as AsyncIterable<unknown>)[Symbol.asyncIterator]();
    void it.next();
    void it.next();
    await settle();
    expect(calls).toBeGreaterThan(0);
    expect(unhandled).toEqual([]);
    expect(probe.observe).not.toHaveBeenCalled();
    expect(h.warn).toHaveBeenCalledTimes(1);
    expect(h.warn.mock.calls[0]).toHaveLength(1);
    expect(String(h.warn.mock.calls[0][0])).toMatch(/tap/);
    expect(String(h.warn.mock.calls[0][0])).not.toMatch(/CANARY/);
  });

  it("an observer that throws is visible as a tap warn whose text differs from the probe's", async () => {
    const { query } = makeRealShapeQuery(msgs(2));
    const tapped = tapAgentAuthFailure(query, {
      observe: () => {
        throw new Error("observer");
      },
    });
    expect(await collect(tapped)).toEqual(msgs(2));
    expect(h.warn).toHaveBeenCalledTimes(1);
    expect(String(h.warn.mock.calls[0][0])).toMatch(/tap/);
    expect(String(h.warn.mock.calls[0][0])).not.toMatch(/probe/);
  });

  it("`throw` is delegated untouched: the injected error comes back and reaches the underlying stream", async () => {
    const { query, stream } = makeRealShapeQuery(msgs(2));
    const it = (tapAgentAuthFailure(query, { observe: vi.fn() }) as AsyncIterable<unknown>)[Symbol.asyncIterator]();
    const boom = new Error("injected");
    await expect(it.throw!(boom)).rejects.toBe(boom);
    expect(stream.throw).toHaveBeenCalledWith(boom);
  });

  it("a REAL async generator: every message is observed in order, and `break` runs its cleanup exactly once", async () => {
    const full = makeGeneratorQuery(msgs(3));
    const probe = { observe: vi.fn() };
    expect(await collect(tapAgentAuthFailure(full.query, probe))).toEqual(msgs(3));
    expect(probe.observe.mock.calls.map((c) => c[0])).toEqual(msgs(3));
    expect(full.state.cleaned).toBe(1);

    const early = makeGeneratorQuery(msgs(5));
    for await (const m of tapAgentAuthFailure(early.query, { observe: vi.fn() }) as AsyncIterable<{ n: number }>) {
      if (m.n === 1) break;
    }
    expect(early.state.cleaned).toBe(1);
  });

  it("a REAL async generator: `return()` issued while a `next()` is pending queues behind it and still cleans up once", async () => {
    let open: () => void = () => undefined;
    const gate = new Promise<void>((res) => { open = res; });
    const { query, state } = makeGeneratorQuery(msgs(3), gate);
    const probe = { observe: vi.fn() };
    const it = (tapAgentAuthFailure(query, probe) as AsyncIterable<unknown>)[Symbol.asyncIterator]();
    const pendingNext = it.next();
    const returned = it.return!();
    let returnedSettled = false;
    void returned.then(() => { returnedSettled = true; });
    await settle();
    expect(returnedSettled).toBe(false); // queued behind the pending next, as for the untapped generator
    open();
    expect(await pendingNext).toEqual({ value: { n: 0 }, done: false });
    expect((await returned).done).toBe(true);
    expect(state.cleaned).toBe(1);
    expect(probe.observe.mock.calls.map((c) => c[0])).toEqual([{ n: 0 }]);
  });

  it("a frozen, non-extensible, non-writable or non-iterable object is returned untouched and still iterates", async () => {
    const probe = { observe: vi.fn() };

    const frozen = makeRealShapeQuery(msgs(2)).query;
    Object.freeze(frozen);
    expect(tapAgentAuthFailure(frozen, probe)).toBe(frozen);
    expect(await collect(frozen)).toEqual(msgs(2));

    const sealed = makeRealShapeQuery(msgs(2)).query;
    Object.preventExtensions(sealed);
    expect(tapAgentAuthFailure(sealed, probe)).toBe(sealed);
    expect(await collect(sealed)).toEqual(msgs(2));

    const fixed: Record<symbol, unknown> = {};
    const underlying = makeRealShapeQuery(msgs(2)).stream;
    Object.defineProperty(fixed, Symbol.asyncIterator, { value: () => underlying, writable: false, configurable: false });
    expect(tapAgentAuthFailure(fixed, probe)).toBe(fixed);

    for (const plain of [{}, { next: () => undefined }, null, undefined, 42, "x"]) {
      expect(tapAgentAuthFailure(plain, probe)).toBe(plain);
    }
    expect(probe.observe).not.toHaveBeenCalled();
  });

  // Each scenario re-arms the process-wide latch and asserts its own warn: with one shared latch a single warning site
  // would satisfy all three.
  const NOT_INSTALLED = "auth-failure tap: not installed, this Query is not observed";
  const installFailures: Array<[string, () => unknown]> = [
    [
      "a non-configurable iterator",
      () => {
        const fixed: Record<symbol, unknown> = {};
        Object.defineProperty(fixed, Symbol.asyncIterator, { value: () => ({}), writable: false, configurable: false });
        return fixed;
      },
    ],
    ["an iterator that is not a function", () => ({ [Symbol.asyncIterator]: 7 })],
    ["a hostile query", () => new Proxy({}, { get: () => { throw new Error("CANARY-PROXY-3d2a"); } })],
  ];
  it.each(installFailures)("an install that cannot happen is visible: %s -> ONE constant tap warn, query returned untouched", (_name, make) => {
    const query = make();
    expect(() => tapAgentAuthFailure(query, { observe: vi.fn() })).not.toThrow();
    expect(tapAgentAuthFailure(query, { observe: vi.fn() })).toBe(query);
    expect(h.warn.mock.calls).toEqual([[NOT_INSTALLED]]);
  });

  it("values that are not queries (null, a number, a plain object without an iterator) are not an install failure: no warn", () => {
    const probe = { observe: vi.fn() };
    for (const plain of [null, undefined, 42, "x"]) tapAgentAuthFailure(plain, probe);
    expect(h.warn).not.toHaveBeenCalled();
  });

  it("a probe whose observe is missing, or a throwing getter on the query, returns the query untouched instead of throwing", () => {
    const { query } = makeRealShapeQuery(msgs(1));
    expect(() => tapAgentAuthFailure(query, undefined as never)).not.toThrow();
    const hostile = new Proxy({}, { get: () => { throw new Error("boom"); } });
    expect(() => tapAgentAuthFailure(hostile, { observe: vi.fn() })).not.toThrow();
  });

  it("tapping twice never double-wraps: each message is observed once", async () => {
    const { query } = makeRealShapeQuery(msgs(3));
    const probe = { observe: vi.fn() };
    tapAgentAuthFailure(query, probe);
    tapAgentAuthFailure(query, probe);
    await collect(query);
    expect(probe.observe).toHaveBeenCalledTimes(3);
  });

  it("re-entry (a second call of the iterator method) neither recurses nor wraps twice", async () => {
    const { query } = makeRealShapeQuery(msgs(2));
    const probe = { observe: vi.fn() };
    tapAgentAuthFailure(query, probe);
    const first = (query as AsyncIterable<unknown>)[Symbol.asyncIterator]();
    const second = (query as AsyncIterable<unknown>)[Symbol.asyncIterator]();
    expect(typeof first.next).toBe("function");
    expect(typeof second.next).toBe("function");
    await first.next();
    expect(probe.observe).toHaveBeenCalledTimes(1);
  });

  it("adds no microtask to the consumer path: a concurrent microtask ticker interleaves identically with and without the tap", async () => {
    const run = async (wrap: boolean) => {
      const log: string[] = [];
      const { query } = makeRealShapeQuery(msgs(4));
      const target = wrap ? tapAgentAuthFailure(query, { observe: () => Promise.resolve() }) : query;
      const ticker = (async () => {
        for (let i = 0; i < 24; i++) {
          await Promise.resolve();
          log.push(`t${i}`);
        }
      })();
      for await (const m of target) log.push(`m${(m as { n: number }).n}`);
      await ticker;
      return log;
    };
    const untapped = await run(false);
    expect(await run(true)).toEqual(untapped);
    // The ticker really interleaves with the stream (the comparison is not over two serial logs).
    expect(untapped.findIndex((e) => e === "m0")).toBeLessThan(untapped.findIndex((e) => e === "t10"));
  });
});

describe("a tapped Query through the REAL soleur-go-runner consumeStream", () => {
  it("the observer sees the auth-failure message and the result, and the runner still completes the turn", async () => {
    const mock = createMockQueryLean();
    const probe = { observe: vi.fn() };
    const factory = vi.fn<QueryFactory>(() => tapAgentAuthFailure(mock.query, probe));
    const runner = createSoleurGoRunner({ queryFactory: factory, now: () => Date.now() });
    const events = {
      onText: vi.fn(),
      onToolUse: vi.fn(),
      onWorkflowDetected: vi.fn(),
      onWorkflowEnded: vi.fn(),
      onResult: vi.fn(),
    };

    await runner.dispatch({
      persona: "command_center",
      conversationId: "c-tap",
      userId: "u1",
      userMessage: "hello",
      currentRouting: { kind: "soleur_go_pending" },
      events,
      persistActiveWorkflow: vi.fn().mockResolvedValue(undefined),
    });

    const failure = {
      type: "assistant",
      message: { model: "<synthetic>", content: [{ type: "text", text: "Not logged in \u00B7 Please run /login" }] },
      error: "authentication_failed",
      is_api_error_message: true,
    };
    mock.emit(failure as never);
    mock.emit(makeResult(0, "sess-1"));
    await flushMicrotasks(16);

    // consumeStream uses `for await`; if it ever switches to direct .next() consumption the tap goes blind and this reds.
    const seen = probe.observe.mock.calls.map((c) => c[0] as { type: string });
    expect(seen.map((m) => m.type)).toEqual(["assistant", "result"]);
    expect(seen[0]).toBe(failure);
    expect(events.onResult).toHaveBeenCalledTimes(1);

    mock.finish();
    await flushMicrotasks(8);
  });
});
