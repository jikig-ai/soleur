// Agent auth-failure diagnostic: the in-place Query tap, against a fixture that models the REAL SDK Query shape
// (measured from sdk.mjs, 0.3.28x): the Query class has its OWN next/return/throw that delegate to an internal Stream,
// and its [Symbol.asyncIterator]() returns that Stream, whose own [Symbol.asyncIterator]() throws "Stream can only be
// iterated once". `for await` therefore never touches Query.next. Plan Phase 1 items 2b and 6 (consumeStream case).
import { describe, expect, it, vi } from "vitest";

import { createSoleurGoRunner, type QueryFactory } from "@/server/soleur-go-runner";
import { tapAgentAuthFailure } from "@/server/agent-auth-failure";
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
    [Symbol.asyncIterator]() {
      return stream;
    }
  }
  return { query: new FakeQuery(), stream };
}

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
