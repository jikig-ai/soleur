import { createHmac, randomBytes, randomUUID } from "node:crypto";
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import type { Server as HttpsServer } from "node:https";
import { WebSocket } from "ws";
import { WS_CLOSE_CODES } from "@/lib/types";
import { makeProxyTestTls, type ProxyTestTls } from "./helpers/proxy-test-tls";

// #12289 — the owner verifies a signed hello BEFORE the AP-2 membership lookup. Real sockets, a real
// https/ws server, the real verifier; only the Supabase-backed membership call and the Sentry mirror are
// replaced by spies so the ORDER (membership never reached by an earlier reject) can be asserted.

const { mockMembership, mockReport, mockWarn, cacheArgs } = vi.hoisted(() => ({
  mockMembership: vi.fn(),
  mockReport: vi.fn(),
  mockWarn: vi.fn(),
  cacheArgs: [] as unknown[],
}));

vi.mock("@/server/logger", () => {
  const child = () => ({ info: vi.fn(), warn: mockWarn, error: vi.fn(), debug: vi.fn() });
  return { default: child(), createChildLogger: child };
});
vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReport,
  warnSilentFallback: vi.fn(),
  infoSilentFallback: vi.fn(),
}));
vi.mock("@/server/session-router", () => ({ verifyProxiedSessionMembership: mockMembership }));
vi.mock("@/lib/supabase/service", () => ({ createServiceClient: () => ({}) }));
// A real 4096-entry fill over TLS sockets is too heavy for a unit run; the cache is shrunk to 2 here and
// its 4096 bound is pinned in proxy-hello.test.ts.
vi.mock("@/server/proxy-hello", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/server/proxy-hello")>();
  return {
    ...actual,
    createReplayCache: (o?: { max?: number }) => {
      cacheArgs.push(o);
      return actual.createReplayCache({ ...o, max: 2 });
    },
  };
});

import { createProxyServer } from "@/server/session-proxy";
import { signProxyHello } from "@/server/proxy-hello";
import * as denyReporterModule from "@/server/proxy-deny-report";
import { __resetDenyReporterForTests } from "@/server/proxy-deny-report";
import { __resetProxyHelloKeyForTests } from "@/server/proxy-tls";
import { __resetProxyListenerStatusForTests, getProxyStatus } from "@/server/proxy-listener-status";

const TEST_BIND = { privateBindPrefix: "", bindAddress: "127.0.0.1", port: 0 } as const;
const KEY_HEX = randomBytes(32).toString("hex");
const KEY = Buffer.from(KEY_HEX, "hex");
const U = randomUUID();
const W = randomUUID();

let tls: ProxyTestTls;
beforeAll(() => {
  tls = makeProxyTestTls();
});
afterAll(() => tls.cleanup());

const opened: HttpsServer[] = [];
const clients: WebSocket[] = [];
const onProxiedSession = vi.fn();

async function start(extra: { helloDeadlineMs?: number } = {}): Promise<{ server: HttpsServer; port: number }> {
  vi.stubEnv("SOLEUR_PROXY_PEER_ALLOWLIST", "127.0.0.1");
  const server = createProxyServer({ onProxiedSession, ...TEST_BIND, ...extra });
  if (!server) throw new Error("createProxyServer returned null");
  opened.push(server);
  if (!server.listening) await new Promise<void>((r) => server.once("listening", () => r()));
  const a = server.address();
  if (!a || typeof a === "string") throw new Error("no address");
  return { server, port: a.port };
}

interface Outcome {
  ready: boolean;
  closeCode?: number;
  closeReason?: string;
}

/** Open a client, send each frame in order, resolve on proxy_ready or close. */
function run(port: number, frames: Array<Buffer | string>, binary = false): Promise<Outcome> {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(`wss://127.0.0.1:${port}/ws-proxy`, { ca: tls.CERT, rejectUnauthorized: true });
    clients.push(ws);
    const out: Outcome = { ready: false };
    let opened = false;
    // A server-side terminate can surface as a client socket error after the upgrade: that is an outcome
    // (the close event follows), not a failure of the harness.
    ws.on("error", (e) => {
      if (!opened) reject(e);
    });
    ws.on("message", (d) => {
      if (JSON.parse(String(d)).type === "proxy_ready") {
        out.ready = true;
        resolve(out);
      }
    });
    ws.once("close", (code, reason) => {
      out.closeCode = code;
      out.closeReason = reason.toString();
      resolve(out);
    });
    ws.once("open", () => {
      opened = true;
      for (const f of frames) ws.send(f, { binary });
    });
  });
}

function mac(key: Buffer, userId: string, workspaceId: string, ts: string, nonce: string): string {
  return createHmac("sha256", key)
    .update("soleur-proxy-hello-v1\n" + userId + "\n" + workspaceId + "\n" + ts + "\n" + nonce)
    .digest("hex");
}

function raw(over: Record<string, unknown> = {}, key: Buffer = KEY): string {
  const ts = String(Math.floor(Date.now() / 1000));
  const nonce = randomBytes(16).toString("hex");
  const base: Record<string, unknown> = { type: "proxy_hello", userId: U, workspaceId: W, ts, nonce };
  const m = { ...base, ...over };
  if (!("mac" in over)) m.mac = mac(key, String(m.userId), String(m.workspaceId), String(m.ts), String(m.nonce));
  for (const k of Object.keys(m)) if (m[k] === undefined) delete m[k];
  return JSON.stringify(m);
}

const denyReporterAccepted = () => denyReporterModule.denyReporter.acceptedCount();
const reports = () => mockReport.mock.calls.map((c) => ({ op: c[1]?.op as string, extra: c[1]?.extra as Record<string, unknown> | undefined }));

beforeEach(() => {
  vi.clearAllMocks();
  vi.unstubAllEnvs();
  vi.stubEnv("PROXY_TLS_KEY", tls.KEY);
  vi.stubEnv("PROXY_TLS_CERT", tls.CERT);
  vi.stubEnv("SOLEUR_PROXY_BIND", "");
  vi.stubEnv("PROXY_HELLO_HMAC_KEY", KEY_HEX);
  mockMembership.mockResolvedValue(true);
  __resetProxyListenerStatusForTests();
  __resetDenyReporterForTests();
  __resetProxyHelloKeyForTests();
});

afterEach(async () => {
  vi.unstubAllEnvs();
  for (const c of clients.splice(0)) c.terminate();
  for (const s of opened.splice(0)) await new Promise<void>((r) => s.close(() => r()));
});

describe("a valid signed hello", () => {
  it("is acked with proxy_ready and handed to onProxiedSession with the authenticated pair", async () => {
    const s = await start();
    const out = await run(s.port, [signProxyHello(KEY, U, W)]);
    expect(out.ready).toBe(true);
    expect(mockMembership).toHaveBeenCalledTimes(1);
    expect(mockMembership.mock.calls[0].slice(0, 2)).toEqual([U, W]);
    expect(onProxiedSession).toHaveBeenCalledTimes(1);
    expect(onProxiedSession.mock.calls[0][1]).toEqual({ userId: U, workspaceId: W });
  });
});

describe("every rejection class refuses with one uniform reason and never reaches the membership lookup", () => {
  const ts = () => String(Math.floor(Date.now() / 1000));
  const cases: Array<[string, string, () => Array<Buffer | string>, boolean?]> = [
    ["missing mac", "shape", () => [raw({ mac: undefined })]],
    ["bad mac", "mac", () => [raw({ mac: "0".repeat(64) })]],
    ["wrong key", "mac", () => [raw({}, randomBytes(32))]],
    ["tampered userId", "mac", () => [raw({ userId: randomUUID(), mac: mac(KEY, U, W, ts(), "a".repeat(32)), nonce: "a".repeat(32) })]],
    ["tampered workspaceId", "mac", () => [raw({ workspaceId: randomUUID(), mac: mac(KEY, U, W, ts(), "b".repeat(32)), nonce: "b".repeat(32) })]],
    ["swapped ids", "mac", () => [raw({ userId: W, workspaceId: U, mac: mac(KEY, U, W, ts(), "c".repeat(32)), nonce: "c".repeat(32) })]],
    ["old-shape hello (no ts/nonce/mac)", "shape", () => [JSON.stringify({ type: "proxy_hello", userId: U, workspaceId: W })]],
    ["extra key", "shape", () => [raw({ extra: "x" })]],
    ["oversized frame (valid hello padded to 2 KiB)", "size", () => [raw() + " ".repeat(2048)]],
    ["non-UUID ids", "shape", () => [raw({ userId: "user-42", workspaceId: "ws-9" })]],
    ["skew +31 s", "skew", () => [raw({ ts: String(Math.floor(Date.now() / 1000) + 31) })]],
    ["skew -31 s", "skew", () => [raw({ ts: String(Math.floor(Date.now() / 1000) - 31) })]],
    ["binary frame", "shape", () => [Buffer.from(raw())], true],
    ["not JSON", "shape", () => ["hello"]],
  ];

  it.each(cases)("%s -> reason %s", async (_name, reason, frames, binary) => {
    const s = await start();
    const out = await run(s.port, frames(), binary === true);
    expect(out.ready).toBe(false);
    expect(out.closeCode).toBe(WS_CLOSE_CODES.ROUTING_UNAVAILABLE);
    expect(out.closeReason).toBe("relay refused");
    expect(mockMembership).not.toHaveBeenCalled();
    expect(onProxiedSession).not.toHaveBeenCalled();
    expect(reports().map((r) => r.extra?.reason)).toEqual([reason]);
    // An unauthenticated class carries exactly {reason, peer}: no byte of the hello, no id.
    expect(reports().map((r) => r.extra)).toEqual([{ reason, peer: "127.0.0.1" }]);
  });

  it("a replayed hello is refused with reason replay", async () => {
    const s = await start();
    const text = signProxyHello(KEY, U, W);
    expect((await run(s.port, [text])).ready).toBe(true);
    const second = await run(s.port, [text]);
    expect(second.ready).toBe(false);
    expect(second.closeReason).toBe("relay refused");
    expect(mockMembership).toHaveBeenCalledTimes(1);
    expect(reports().map((r) => r.extra?.reason)).toEqual(["replay"]);
  });

  it("a full replay cache refuses with its own reason full (never mistaken for a replay)", async () => {
    const s = await start();
    expect((await run(s.port, [signProxyHello(KEY, U, W)])).ready).toBe(true);
    expect((await run(s.port, [signProxyHello(KEY, U, W)])).ready).toBe(true);
    const third = await run(s.port, [signProxyHello(KEY, U, W)]);
    expect(third.ready).toBe(false);
    expect(reports().map((r) => r.extra?.reason)).toEqual(["full"]);
    expect(mockMembership).toHaveBeenCalledTimes(2);
  });

  it("AP-2 deny after a valid MAC still refuses, through the bounded reporter, with the authenticated pair", async () => {
    mockMembership.mockResolvedValue(false);
    const s = await start();
    const out = await run(s.port, [signProxyHello(KEY, U, W)]);
    expect(out.ready).toBe(false);
    expect(out.closeReason).toBe("relay refused");
    expect(onProxiedSession).not.toHaveBeenCalled();
    expect(reports()).toEqual([
      { op: "createProxyServer.ap2-deny", extra: { reason: "membership", peer: "127.0.0.1", userId: U, workspaceId: W } },
    ]);
  });

  it("two hellos with the same nonce in the same tick yield exactly one proxy_ready (check-and-insert precedes the await)", async () => {
    let release: (v: boolean) => void = () => undefined;
    mockMembership.mockImplementation(() => new Promise<boolean>((r) => (release = r)));
    const s = await start();
    const text = signProxyHello(KEY, U, W);
    const a = run(s.port, [text]);
    const b = run(s.port, [text]);
    await vi.waitFor(() => expect(mockMembership.mock.calls.length + reports().length).toBeGreaterThanOrEqual(2));
    release(true);
    const outs = await Promise.all([a, b]);
    expect(outs.filter((o) => o.ready)).toHaveLength(1);
    expect(mockMembership).toHaveBeenCalledTimes(1);
    expect(reports().map((r) => r.extra?.reason)).toEqual(["replay"]);
  });

  it("a flood of forged hellos reports at most 5 events and leaves the cache usable for a valid one", async () => {
    const s = await start();
    for (let i = 0; i < 12; i++) await run(s.port, [raw({ mac: "1".repeat(64) })]);
    expect(reports().filter((r) => r.extra?.reason === "mac")).toHaveLength(5);
    expect((await run(s.port, [signProxyHello(KEY, U, W)])).ready).toBe(true);
  });

  it("no report carries a hello-derived byte for an unauthenticated class", async () => {
    const s = await start();
    const secretish = randomUUID();
    await run(s.port, [raw({ userId: secretish, mac: "0".repeat(64) })]);
    const blob = JSON.stringify(mockReport.mock.calls);
    expect(blob).not.toContain(secretish);
    expect(blob).not.toContain(KEY_HEX);
  });
});

describe("pre-authentication hardening (review of #12462)", () => {
  it("a malformed frame (invalid UTF-8) from an allowlisted peer with no key does not crash the process: closed, counted as shape", async () => {
    const s = await start();
    // Without a socket 'error' listener this is an uncaught exception (the vitest run itself would fail).
    const out = await run(s.port, [Buffer.from([0xff, 0xfe, 0xfd])], false);
    expect(out.ready).toBe(false);
    expect(mockMembership).not.toHaveBeenCalled();
    await vi.waitFor(() => expect(reports().map((r) => r.extra)).toEqual([{ reason: "shape", peer: "127.0.0.1" }]));
  });

  it("a 2 MiB first frame is cut off before it is buffered: closed, reason size, membership never reached", async () => {
    const s = await start();
    const out = await run(s.port, [Buffer.alloc(2 * 1024 * 1024, 0x20)], false);
    expect(out.ready).toBe(false);
    // Terminated by the byte guard (abnormal close), not refused by the verifier after buffering the whole
    // frame (which would close 4014 "relay refused").
    expect(out.closeReason).not.toBe("relay refused");
    expect(mockMembership).not.toHaveBeenCalled();
    await vi.waitFor(() => expect(reports().map((r) => r.extra?.reason)).toEqual(["size"]));
  });

  it("an admitted peer that never sends a message is closed at the deadline (hello_timeout)", async () => {
    const s = await start({ helloDeadlineMs: 400 });
    const closed = await new Promise<{ code: number; at: number }>((resolve, reject) => {
      const t0 = Date.now();
      const ws = new WebSocket(`wss://127.0.0.1:${s.port}/ws-proxy`, { ca: tls.CERT, rejectUnauthorized: true });
      clients.push(ws);
      ws.on("error", () => undefined);
      ws.once("close", (code) => resolve({ code, at: Date.now() - t0 }));
      setTimeout(() => reject(new Error("not closed within 3 s")), 3000);
    });
    expect(closed.at).toBeGreaterThanOrEqual(300);
    expect(reports().map((r) => r.extra)).toEqual([{ reason: "hello_timeout", peer: "127.0.0.1" }]);
    expect(mockMembership).not.toHaveBeenCalled();
  });

  it("a valid hello clears the deadline: the session is still open well past it", async () => {
    const s = await start({ helloDeadlineMs: 400 });
    const ws = new WebSocket(`wss://127.0.0.1:${s.port}/ws-proxy`, { ca: tls.CERT, rejectUnauthorized: true });
    clients.push(ws);
    await new Promise<void>((resolve, reject) => {
      ws.on("error", reject);
      ws.on("message", (d) => JSON.parse(String(d)).type === "proxy_ready" && resolve());
      ws.once("open", () => ws.send(signProxyHello(KEY, U, W)));
    });
    await new Promise((r) => setTimeout(r, 900));
    expect(ws.readyState).toBe(WebSocket.OPEN);
    expect(reports()).toEqual([]);
  });

  it("frames after proxy_ready are NOT run through the hello verifier (the pipe stays open, nothing is reported)", async () => {
    const s = await start();
    const ws = new WebSocket(`wss://127.0.0.1:${s.port}/ws-proxy`, { ca: tls.CERT, rejectUnauthorized: true });
    clients.push(ws);
    await new Promise<void>((resolve, reject) => {
      ws.on("error", reject);
      ws.on("message", (d) => JSON.parse(String(d)).type === "proxy_ready" && resolve());
      ws.once("open", () => ws.send(signProxyHello(KEY, U, W)));
    });
    ws.send("a relayed client frame, not a hello");
    await new Promise((r) => setTimeout(r, 300));
    expect(ws.readyState).toBe(WebSocket.OPEN);
    expect(reports()).toEqual([]);
  });

  it("a client that drops during the membership lookup is not attached (no supersede of the live session)", async () => {
    let release: (v: boolean) => void = () => undefined;
    mockMembership.mockImplementation(() => new Promise<boolean>((r) => (release = r)));
    const s = await start();
    const ws = new WebSocket(`wss://127.0.0.1:${s.port}/ws-proxy`, { ca: tls.CERT, rejectUnauthorized: true });
    clients.push(ws);
    ws.on("error", () => undefined);
    await new Promise<void>((resolve) => ws.once("open", () => (ws.send(signProxyHello(KEY, U, W)), resolve())));
    await vi.waitFor(() => expect(mockMembership).toHaveBeenCalledTimes(1));
    ws.terminate();
    await new Promise((r) => setTimeout(r, 150));
    release(true);
    await new Promise((r) => setTimeout(r, 150));
    expect(onProxiedSession).not.toHaveBeenCalled();
    expect(denyReporterAccepted()).toBe(0);
  });

  it("a throwing membership lookup fails closed (relay refused, reason internal) instead of an unhandled rejection", async () => {
    mockMembership.mockRejectedValue(new Error("db down"));
    const s = await start();
    const out = await run(s.port, [signProxyHello(KEY, U, W)]);
    expect(out.ready).toBe(false);
    expect(out.closeReason).toBe("relay refused");
    expect(onProxiedSession).not.toHaveBeenCalled();
    expect(reports().map((r) => r.extra?.reason)).toEqual(["internal"]);
  });

  it("the replay cache is built with the production bound (no max override reaches createReplayCache)", async () => {
    await start();
    expect(cacheArgs.length).toBeGreaterThan(0);
    expect(cacheArgs.every((a) => a === undefined || (a as { max?: number }).max === undefined)).toBe(true);
  });
});

describe("accepted hellos are counted (the positive off-host signal)", () => {
  it("an accepted hello increments the accepted counter; a refused one does not", async () => {
    const { denyReporter } = await import("@/server/proxy-deny-report");
    const s = await start();
    await run(s.port, [raw({ mac: "0".repeat(64) })]);
    expect(denyReporter.acceptedCount()).toBe(0);
    await run(s.port, [signProxyHello(KEY, U, W)]);
    expect(denyReporter.acceptedCount()).toBe(1);
  });
});

describe("startup guard: hello key", () => {
  const BASE = { privateBindPrefix: "", port: 0 } as const;

  it.each([
    ["absent", ""],
    ["63 hex", "a".repeat(63)],
    ["uppercase", "A".repeat(64)],
    ["padded", " " + "a".repeat(64)],
  ])("key %s with TLS + bind + allowlist set -> null, proxy_state=error, one no-hello-key event", (_n, value) => {
    vi.stubEnv("PROXY_HELLO_HMAC_KEY", value);
    vi.stubEnv("SOLEUR_PROXY_PEER_ALLOWLIST", "127.0.0.1");
    const server = createProxyServer({ onProxiedSession, ...BASE, bindAddress: "127.0.0.1" });
    expect(server).toBeNull();
    expect(getProxyStatus().state).toBe("error");
    const ops = reports().map((r) => r.op);
    expect(ops).toEqual(["createProxyServer.no-hello-key"]);
    const blob = JSON.stringify(mockReport.mock.calls);
    if (value) expect(blob).not.toContain(value);
  });

  it("the no-hello-key error text is a constant: no value, length or state", () => {
    vi.stubEnv("PROXY_HELLO_HMAC_KEY", "a".repeat(63));
    vi.stubEnv("SOLEUR_PROXY_PEER_ALLOWLIST", "127.0.0.1");
    createProxyServer({ onProxiedSession, ...BASE, bindAddress: "127.0.0.1" });
    // Null error + explicit message: the event keeps its feature/op tags in Sentry (see proxy-deny-report.ts).
    expect(mockReport.mock.calls[0][0]).toBeNull();
    const message = String(mockReport.mock.calls[0][1].message);
    expect(message).toMatch(/^PROXY_HELLO_HMAC_KEY missing or malformed/);
    expect(message).not.toMatch(/63|invalid|absent/);
  });

  it("a valid key listens (positive control)", async () => {
    vi.stubEnv("SOLEUR_PROXY_PEER_ALLOWLIST", "127.0.0.1");
    const server = createProxyServer({ onProxiedSession, ...BASE, bindAddress: "127.0.0.1" });
    expect(server).not.toBeNull();
    opened.push(server as HttpsServer);
    if (!server?.listening) await new Promise<void>((r) => server?.once("listening", () => r()));
    expect(getProxyStatus().state).toBe("listening");
  });

  it("TLS absent (dev/CI) -> disabled and NO Sentry event, even with no key", () => {
    vi.stubEnv("PROXY_TLS_KEY", "");
    vi.stubEnv("PROXY_TLS_CERT", "");
    vi.stubEnv("PROXY_HELLO_HMAC_KEY", "");
    expect(createProxyServer({ onProxiedSession, ...BASE, bindAddress: "127.0.0.1" })).toBeNull();
    expect(getProxyStatus().state).toBe("disabled");
    expect(mockReport).not.toHaveBeenCalled();
  });

  it("empty SOLEUR_PROXY_BIND (canary) still reads no_bind, not error, with no key", () => {
    vi.stubEnv("PROXY_HELLO_HMAC_KEY", "");
    vi.stubEnv("SOLEUR_PROXY_PEER_ALLOWLIST", "127.0.0.1");
    expect(createProxyServer({ onProxiedSession, ...BASE, bindAddress: "" })).toBeNull();
    expect(getProxyStatus().state).toBe("no_bind");
    expect(reports().map((r) => r.op)).toEqual(["createProxyServer.no-bind"]);
  });

  it("unset allowlist still reads no_allowlist, not error, with no key", () => {
    vi.stubEnv("PROXY_HELLO_HMAC_KEY", "");
    vi.stubEnv("SOLEUR_PROXY_PEER_ALLOWLIST", "");
    expect(createProxyServer({ onProxiedSession, ...BASE, bindAddress: "127.0.0.1" })).toBeNull();
    expect(getProxyStatus().state).toBe("no_allowlist");
  });
});
