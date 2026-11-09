import { createHmac, randomBytes, randomUUID } from "node:crypto";
import { beforeEach, describe, expect, it, vi } from "vitest";

// #12289 — the signed relay hello. Pure module tests with an injected clock (no fake timers, no
// sockets). The known-answer vector is assembled BY HAND from the spec string and node:crypto in the
// test, independent of the module's own builder, so a swapped field or a dropped domain prefix cannot
// pass by agreeing with itself.

const { timingSafeEqualSpy } = vi.hoisted(() => ({ timingSafeEqualSpy: vi.fn() }));
vi.mock("node:crypto", async (importOriginal) => {
  const actual = await importOriginal<typeof import("node:crypto")>();
  timingSafeEqualSpy.mockImplementation(actual.timingSafeEqual);
  return { ...actual, timingSafeEqual: timingSafeEqualSpy };
});

import {
  HELLO_MAX_BYTES,
  REPLAY_MAX,
  SKEW_S,
  buildHelloMacInput,
  createReplayCache,
  signProxyHello,
  verifyProxyHello,
} from "@/server/proxy-hello";

const KEY_HEX = randomBytes(32).toString("hex");
const KEY = Buffer.from(KEY_HEX, "hex");
const OTHER_KEY = randomBytes(32);
const U = randomUUID();
const W = randomUUID();
const T0_MS = 1_800_000_000_000; // a fixed instant; seconds = 1_800_000_000
const T0_S = T0_MS / 1000;
let nowMs = T0_MS;
const now = () => nowMs;

function handMac(key: Buffer, userId: string, workspaceId: string, ts: string, nonce: string): string {
  return createHmac("sha256", key)
    .update("soleur-proxy-hello-v1\n" + userId + "\n" + workspaceId + "\n" + ts + "\n" + nonce)
    .digest("hex");
}

const NONCE = "0123456789abcdef0123456789abcdef";

function hello(over: Record<string, unknown> = {}, key: Buffer = KEY): Buffer {
  const base: Record<string, unknown> = { type: "proxy_hello", userId: U, workspaceId: W, ts: String(T0_S), nonce: NONCE };
  const merged = { ...base, ...over };
  if (!("mac" in over)) {
    merged.mac = handMac(key, String(merged.userId), String(merged.workspaceId), String(merged.ts), String(merged.nonce));
  }
  for (const k of Object.keys(merged)) if (merged[k] === undefined) delete merged[k];
  return Buffer.from(JSON.stringify(merged));
}

function verify(buf: Buffer, cache = createReplayCache(), isBinary = false) {
  return verifyProxyHello(buf, isBinary, KEY, cache, now);
}

beforeEach(() => {
  nowMs = T0_MS;
  timingSafeEqualSpy.mockClear();
});

describe("canonical string and MAC (known-answer vector)", () => {
  it("builder output equals the hand-assembled spec string", () => {
    expect(buildHelloMacInput(U, W, String(T0_S), NONCE)).toBe(
      "soleur-proxy-hello-v1\n" + U + "\n" + W + "\n" + String(T0_S) + "\n" + NONCE,
    );
  });

  it("signProxyHello produces a hello whose mac equals the independently computed HMAC", () => {
    const text = signProxyHello(KEY, U, W, { now, nonce: NONCE });
    const parsed = JSON.parse(text);
    expect(Object.keys(parsed).sort()).toEqual(["mac", "nonce", "type", "userId", "workspaceId", "ts"].sort());
    expect(parsed.type).toBe("proxy_hello");
    expect(parsed.ts).toBe(String(T0_S));
    expect(parsed.mac).toBe(handMac(KEY, U, W, String(T0_S), NONCE));
  });

  it("two signs differ in nonce by default", () => {
    const a = JSON.parse(signProxyHello(KEY, U, W, { now }));
    const b = JSON.parse(signProxyHello(KEY, U, W, { now }));
    expect(a.nonce).not.toBe(b.nonce);
    expect(a.nonce).toMatch(/^[0-9a-f]{32}$/);
  });

  it("refuses to sign non-canonical ids", () => {
    expect(() => signProxyHello(KEY, "user-42", W, { now })).toThrow();
    expect(() => signProxyHello(KEY, U.toUpperCase(), W, { now })).toThrow();
  });

  it("round trip: a signed hello verifies and returns the id pair", () => {
    const text = signProxyHello(KEY, U, W, { now });
    expect(verify(Buffer.from(text))).toEqual({ ok: true, userId: U, workspaceId: W });
  });

  it("a second valid UUID pair and a freshly generated second key also verify", () => {
    const u2 = randomUUID();
    const w2 = randomUUID();
    const k2 = randomBytes(32);
    const text = signProxyHello(k2, u2, w2, { now });
    expect(verifyProxyHello(Buffer.from(text), false, k2, createReplayCache(), now)).toEqual({ ok: true, userId: u2, workspaceId: w2 });
  });
});

describe("rejections, in the ruled order", () => {
  it("size: a valid hello padded to 2 KiB is refused with reason size", () => {
    const padded = Buffer.from(hello().toString() + " ".repeat(2048));
    expect(verify(padded)).toEqual({ ok: false, reason: "size" });
    expect(HELLO_MAX_BYTES).toBe(1024);
  });

  it("size is checked on the Buffer byte length before any string conversion (multi-byte payload)", () => {
    const wide = Buffer.from("é".repeat(600)); // 1200 bytes, 600 chars
    expect(wide.length).toBeGreaterThan(HELLO_MAX_BYTES);
    expect(verify(wide)).toEqual({ ok: false, reason: "size" });
  });

  it("a frame of exactly the cap is not refused as size", () => {
    const exact = Buffer.alloc(HELLO_MAX_BYTES, 0x20);
    const r = verify(exact);
    expect(r).toEqual({ ok: false, reason: "shape" });
  });

  it("binary frames are refused with reason shape", () => {
    expect(verify(hello(), createReplayCache(), true)).toEqual({ ok: false, reason: "shape" });
  });

  it.each([
    ["not JSON", Buffer.from("not json")],
    ["JSON array", Buffer.from("[]")],
    ["JSON null", Buffer.from("null")],
    ["JSON string", Buffer.from('"x"')],
    ["old shape (no ts/nonce/mac)", Buffer.from(JSON.stringify({ type: "proxy_hello", userId: U, workspaceId: W }))],
    ["missing mac", hello({ mac: undefined })],
    ["extra key", hello({ extra: "x" })],
    ["wrong type", hello({ type: "other" })],
    ["non-UUID userId", hello({ userId: "user-42" })],
    ["non-UUID workspaceId", hello({ workspaceId: "ws-9" })],
    ["uppercase userId", hello({ userId: U.toUpperCase() })],
    ["uppercase workspaceId", hello({ workspaceId: W.toUpperCase() })],
    ["ts with leading zero", hello({ ts: "0" + String(T0_S).slice(1) })],
    ["ts 9 digits", hello({ ts: "999999999" })],
    ["ts 11 digits", hello({ ts: "18000000000" })],
    ["ts as number", hello({ ts: T0_S })],
    ["nonce uppercase", hello({ nonce: NONCE.toUpperCase() })],
    ["nonce 31 chars", hello({ nonce: NONCE.slice(1) })],
    ["mac 63 chars", hello({ mac: "a".repeat(63) })],
    ["mac uppercase", hello({ mac: "A".repeat(64) })],
  ])("shape: %s -> reason shape", (_name, buf) => {
    expect(verify(buf as Buffer)).toEqual({ ok: false, reason: "shape" });
  });

  it("an array-valued own key set of six keys is not a plain object", () => {
    const arr = Object.assign([], { type: "proxy_hello" });
    expect(verify(Buffer.from(JSON.stringify(arr)))).toEqual({ ok: false, reason: "shape" });
  });

  it.each([
    ["wrong key", hello({}, OTHER_KEY)],
    ["tampered userId", hello({ userId: randomUUID(), mac: handMac(KEY, U, W, String(T0_S), NONCE) })],
    ["tampered workspaceId", hello({ workspaceId: randomUUID(), mac: handMac(KEY, U, W, String(T0_S), NONCE) })],
    ["swapped ids", hello({ userId: W, workspaceId: U, mac: handMac(KEY, U, W, String(T0_S), NONCE) })],
    ["tampered ts", hello({ ts: String(T0_S + 1), mac: handMac(KEY, U, W, String(T0_S), NONCE) })],
    ["tampered nonce", hello({ nonce: "f".repeat(32), mac: handMac(KEY, U, W, String(T0_S), NONCE) })],
    ["zero mac", hello({ mac: "0".repeat(64) })],
  ])("mac: %s -> reason mac", (_name, buf) => {
    expect(verify(buf)).toEqual({ ok: false, reason: "mac" });
  });

  it("mac comparison goes through crypto.timingSafeEqual on two 32-byte buffers, for valid and invalid MACs", () => {
    verify(hello());
    verify(hello({}, OTHER_KEY));
    expect(timingSafeEqualSpy).toHaveBeenCalledTimes(2);
    for (const call of timingSafeEqualSpy.mock.calls) {
      expect(call[0]).toBeInstanceOf(Buffer);
      expect(call[1]).toBeInstanceOf(Buffer);
      expect(call[0]).toHaveLength(32);
      expect(call[1]).toHaveLength(32);
    }
  });

  it("shape-gated hellos never reach the MAC comparison", () => {
    verify(hello({ mac: "a".repeat(63) }));
    expect(timingSafeEqualSpy).not.toHaveBeenCalled();
  });
});

describe("timestamp skew", () => {
  it.each([
    [-31, false],
    [-30, true],
    [-29, true],
    [0, true],
    [29, true],
    [30, true],
    [31, false],
  ])("hello ts offset %i s from the owner clock -> accepted=%s", (offset, accepted) => {
    const ts = String(T0_S + offset);
    const r = verify(hello({ ts }));
    expect(r.ok).toBe(accepted);
    if (!accepted) expect(r).toEqual({ ok: false, reason: "skew" });
    expect(SKEW_S).toBe(30);
  });

  it("ts is compared in seconds: the owner's millisecond clock value is not what ts is checked against", () => {
    // 10 digits, year 2286: shape-valid, MAC-valid, far outside the owner's seconds clock.
    expect(verify(hello({ ts: "9999999999" }))).toEqual({ ok: false, reason: "skew" });
    // A sender that signed milliseconds would emit 13 digits: refused at the shape gate.
    expect(verify(hello({ ts: String(T0_MS) }))).toEqual({ ok: false, reason: "shape" });
  });

  it("the skew check runs after the MAC check: a bad-mac stale hello reads mac, not skew", () => {
    const stale = hello({ ts: String(T0_S - 100), mac: "0".repeat(64) });
    expect(verify(stale)).toEqual({ ok: false, reason: "mac" });
  });
});

describe("replay cache", () => {
  it("the same valid hello twice: second is refused with reason replay", () => {
    const cache = createReplayCache();
    expect(verify(hello(), cache).ok).toBe(true);
    expect(verify(hello(), cache)).toEqual({ ok: false, reason: "replay" });
  });

  it("two valid hellos from one user with different nonces are both accepted", () => {
    const cache = createReplayCache();
    expect(verify(hello({ nonce: "a".repeat(32) }), cache).ok).toBe(true);
    expect(verify(hello({ nonce: "b".repeat(32) }), cache).ok).toBe(true);
  });

  it("forged hellos neither fill the cache nor evict a live entry: 5000 bad-MAC hellos then a valid one", () => {
    const cache = createReplayCache();
    for (let i = 0; i < 5000; i++) {
      const nonce = i.toString(16).padStart(32, "0");
      expect(verify(hello({ nonce, mac: "1".repeat(64) }), cache)).toEqual({ ok: false, reason: "mac" });
    }
    expect(cache.size()).toBe(0);
    expect(verify(hello(), cache).ok).toBe(true);
  });

  it("the 4096th live entry is accepted, the 4097th is refused with reason full and nothing is evicted", () => {
    const cache = createReplayCache();
    for (let i = 0; i < REPLAY_MAX; i++) {
      const nonce = i.toString(16).padStart(32, "0");
      expect(verify(hello({ nonce }), cache).ok).toBe(true);
    }
    expect(cache.size()).toBe(REPLAY_MAX);
    const extra = "f".repeat(32);
    expect(verify(hello({ nonce: extra }), cache)).toEqual({ ok: false, reason: "full" });
    // the first entry is still live: it must read replay, not be evicted
    expect(verify(hello({ nonce: (0).toString(16).padStart(32, "0") }), cache)).toEqual({ ok: false, reason: "replay" });
  });

  it("expiry is derived from ts: a hello with ts = T+30 accepted at T replays at T+35 (refused) and is skew-refused after", () => {
    const cache = createReplayCache();
    const future = hello({ ts: String(T0_S + 30) });
    expect(verify(future, cache).ok).toBe(true);
    nowMs = T0_MS + 35_000;
    expect(verify(future, cache)).toEqual({ ok: false, reason: "replay" });
    nowMs = T0_MS + 60_000; // T+60: ts+30 -> skew 30, still inside the window
    expect(verify(future, cache)).toEqual({ ok: false, reason: "replay" });
    nowMs = T0_MS + 61_000; // skew 31 -> the skew check (not the cache) refuses
    expect(verify(future, cache)).toEqual({ ok: false, reason: "skew" });
  });

  it("boundary: replay at ts+SKEW_S is refused by the cache; at ts+SKEW_S+1 the skew check refuses", () => {
    const cache = createReplayCache();
    const h = hello();
    expect(verify(h, cache).ok).toBe(true);
    nowMs = T0_MS + 30_000;
    expect(verify(h, cache)).toEqual({ ok: false, reason: "replay" });
    nowMs = T0_MS + 31_000;
    expect(verify(h, cache)).toEqual({ ok: false, reason: "skew" });
  });

  it("a nonce reused after the window is a new valid hello (fresh ts) and is accepted again", () => {
    const cache = createReplayCache();
    expect(verify(hello(), cache).ok).toBe(true);
    nowMs = T0_MS + 61_000;
    expect(verify(hello({ ts: String(T0_S + 61) }), cache).ok).toBe(true);
  });

  it("expired entries are purged so a fresh nonce is not refused as full", () => {
    const cache = createReplayCache({ max: 3 });
    for (let i = 0; i < 3; i++) expect(verify(hello({ nonce: String(i).padStart(32, "0") }), cache).ok).toBe(true);
    expect(verify(hello({ nonce: "9".repeat(32) }), cache)).toEqual({ ok: false, reason: "full" });
    nowMs = T0_MS + 40_000;
    expect(verify(hello({ nonce: "9".repeat(32), ts: String(T0_S + 40) }), cache).ok).toBe(true);
  });

  it("a hello rejected for any reason never inserts its nonce", () => {
    const cache = createReplayCache();
    verify(hello({ ts: String(T0_S + 99) }), cache); // skew
    verify(hello({ mac: "0".repeat(64) }), cache); // mac
    expect(cache.size()).toBe(0);
  });
});
