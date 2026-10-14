// #8611 / ADR-243 — the Inngest SDK 3.54.2 streaming heartbeat must never see a consumer cancel.
//
// createStream (node_modules/inngest/helpers/stream.js) clears its 3 s heartbeat only in finalize()
// and has no cancel() handler, so a dropped step stream makes every tick throw "Invalid state:
// Controller is already closed" from a timer — an uncaughtException, which server/crash-handlers.ts
// turns into process.exit(1). detachFromConsumerCancel re-streams the body and, on cancel, drains
// the SDK stream instead of cancelling it. These tests drive the REAL createStream.
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const { fallbackMock } = vi.hoisted(() => ({ fallbackMock: vi.fn() }));
// Drop reports are warning-level (an expected, degraded path); the mock captures them.
vi.mock("@/server/observability", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/observability")>()),
  warnSilentFallback: fallbackMock,
}));

import { detachFromConsumerCancel, streamRequestInfo } from "@/server/inngest/stream-detach";

const SDK_STREAM_JS = join(__dirname, "../../../node_modules/inngest/helpers/stream.js");
// The wrapper exists for THIS file's defect. Any SDK change must re-open the question (inngest@4
// fixes it upstream, and the wrapper should then be deleted — see ADR-243).
const SDK_STREAM_SHA256 = "eff696a989fe85881065d72da7ef7ea86801181ebfb1345a002671e3c4d84b94";

type SdkStream = { stream: ReadableStream<Uint8Array>; finalize: (data: unknown) => void };
async function sdkStream(): Promise<SdkStream> {
  const mod = (await import(/* @vite-ignore */ SDK_STREAM_JS)) as {
    createStream: () => Promise<SdkStream>;
  };
  return mod.createStream();
}

const dec = new TextDecoder();
async function readAll(body: ReadableStream<Uint8Array>): Promise<string> {
  const reader = body.getReader();
  let out = "";
  for (;;) {
    const { done, value } = await reader.read();
    if (done) return out;
    out += dec.decode(value);
  }
}

beforeEach(() => {
  fallbackMock.mockReset();
  vi.useFakeTimers();
});
afterEach(() => vi.useRealTimers());

describe("detachFromConsumerCancel — #8611", () => {
  it("pins the SDK stream helper it works around", () => {
    const sha = createHash("sha256").update(readFileSync(SDK_STREAM_JS)).digest("hex");
    expect(sha).toBe(SDK_STREAM_SHA256);
  });

  it("control: WITHOUT the wrapper, a consumer cancel makes the next heartbeat tick throw", async () => {
    const { stream } = await sdkStream();
    const reader = new Response(stream).body!.getReader();
    await reader.cancel();
    expect(() => vi.advanceTimersByTime(3_000)).toThrow(/Controller is already closed|Invalid state/);
  });

  it("after a consumer cancel, 60 s of heartbeats and a late finalize throw nothing and the SDK stream is drained", async () => {
    const { stream, finalize } = await sdkStream();
    const res = detachFromConsumerCancel(new Response(stream, { status: 201 }));
    const reader = res.body!.getReader();
    await reader.cancel();

    const rejections: unknown[] = [];
    const onRejection = (r: unknown) => rejections.push(r);
    process.on("unhandledRejection", onRejection);
    try {
      expect(() => vi.advanceTimersByTime(60_000)).not.toThrow();
      finalize({ status: 200, body: "done" });
      await vi.runAllTimersAsync();
      // Drained to the end: the source is closed, so no heartbeat is left running.
      expect(vi.getTimerCount()).toBe(0);
      // An unhandled rejection surfaces on a real macrotask turn, which fake timers would swallow.
      vi.useRealTimers();
      await new Promise((r) => setImmediate(r));
    } finally {
      process.off("unhandledRejection", onRejection);
    }
    expect(rejections).toEqual([]);
    expect(fallbackMock.mock.calls.some((c) => c[1]?.op === "inngest-stream-consumer-cancel")).toBe(true);
  });

  it("without a cancel, passes status, headers and every byte through, final envelope included", async () => {
    const { stream, finalize } = await sdkStream();
    const res = detachFromConsumerCancel(
      new Response(stream, { status: 201, headers: { "x-inngest-sdk": "js:v3.54.2" } }),
    );
    expect(res.status).toBe(201);
    expect(res.headers.get("x-inngest-sdk")).toBe("js:v3.54.2");
    const body = readAll(res.body!);
    vi.advanceTimersByTime(6_000); // two heartbeats
    finalize({ status: 200, body: "ok" });
    await vi.runAllTimersAsync();
    const text = await body;
    expect(text.startsWith("  ")).toBe(true);
    expect(JSON.parse(text.trim())).toEqual({ status: 200, body: "ok" });
    expect(fallbackMock).not.toHaveBeenCalled();
  });

  it("a cancel drains the source to its end (not just stops the heartbeat) and tags the report", async () => {
    vi.useRealTimers();
    let sawDone = false;
    let pushed = 0;
    // A source that only completes once it has been read to the end: `done` is observable.
    const source = new ReadableStream<Uint8Array>({
      pull(controller) {
        if (pushed < 3) {
          pushed += 1;
          controller.enqueue(new TextEncoder().encode("x"));
        } else {
          sawDone = true;
          controller.close();
        }
      },
    });
    const res = detachFromConsumerCancel(new Response(source), { fnId: "fn-a", stepId: "st-1", signed: true });
    await res.body!.getReader().cancel();
    await new Promise((r) => setTimeout(r, 20));
    expect(sawDone).toBe(true);
    const call = fallbackMock.mock.calls.find((c) => c[1]?.op === "inngest-stream-consumer-cancel");
    expect(call?.[1]).toMatchObject({ tags: { signed: "true", fn: "fn-a" }, extra: { stepId: "st-1" } });
  });

  it("with the consumer still attached, a source error propagates to it (no hang)", async () => {
    vi.useRealTimers();
    const source = new ReadableStream<Uint8Array>({
      pull() {
        throw new Error("sdk stream broke");
      },
    });
    const reader = detachFromConsumerCancel(new Response(source)).body!.getReader();
    await expect(reader.read()).rejects.toThrow(/sdk stream broke/);
  });

  it("streamRequestInfo reads fnId/stepId from the query and whether the request was signed", () => {
    const signed = new Request("http://x/api/inngest?fnId=cron-a&stepId=step", {
      method: "POST",
      headers: { "x-inngest-signature": "t=1&s=00" },
    });
    expect(streamRequestInfo(signed)).toEqual({ fnId: "cron-a", stepId: "step", signed: true });
    expect(streamRequestInfo(new Request("http://x/api/inngest", { method: "POST" }))).toEqual({
      fnId: null,
      stepId: null,
      signed: false,
    });
  });

  it("returns a body-less response unchanged", () => {
    const res = new Response(null, { status: 204 });
    expect(detachFromConsumerCancel(res)).toBe(res);
  });
});
