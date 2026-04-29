import { afterEach, beforeEach, describe, expect, test } from "vitest";
import WS from "ws";
import { ensureNodeWebSocketPolyfill } from "./node-websocket-polyfill";

type MaybeWS = { WebSocket?: unknown };

describe("ensureNodeWebSocketPolyfill", () => {
  let originalWebSocket: unknown;
  let hadOriginal: boolean;

  beforeEach(() => {
    hadOriginal = "WebSocket" in globalThis;
    originalWebSocket = (globalThis as MaybeWS).WebSocket;
    delete (globalThis as MaybeWS).WebSocket;
  });

  afterEach(() => {
    if (hadOriginal) (globalThis as MaybeWS).WebSocket = originalWebSocket;
    else delete (globalThis as MaybeWS).WebSocket;
  });

  test("assigns ws when globalThis.WebSocket is undefined", () => {
    expect((globalThis as MaybeWS).WebSocket).toBeUndefined();
    ensureNodeWebSocketPolyfill();
    expect((globalThis as MaybeWS).WebSocket).toBe(WS);
  });

  test("no-op when globalThis.WebSocket is already defined", () => {
    const sentinel = function FakeWebSocket() {} as unknown;
    (globalThis as MaybeWS).WebSocket = sentinel;
    ensureNodeWebSocketPolyfill();
    expect((globalThis as MaybeWS).WebSocket).toBe(sentinel);
  });

  test("idempotent across multiple calls", () => {
    ensureNodeWebSocketPolyfill();
    const first = (globalThis as MaybeWS).WebSocket;
    ensureNodeWebSocketPolyfill();
    ensureNodeWebSocketPolyfill();
    expect((globalThis as MaybeWS).WebSocket).toBe(first);
    expect((globalThis as MaybeWS).WebSocket).toBe(WS);
  });
});
