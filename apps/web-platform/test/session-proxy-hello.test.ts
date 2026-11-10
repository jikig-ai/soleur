import { createHmac, randomBytes, randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { connect as netConnect } from "node:net";
import { connect as tlsConnect } from "node:tls";
import path from "node:path";
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

import { createProxyServer, HELLO_DEADLINE_MS, PRE_HELLO_MAX_BYTES, REFUSE_LINGER_MS, isSendableCloseCode } from "@/server/session-proxy";
import { proxyClientToOwner } from "@/server/session-proxy";
import { createReplayCache, helloKeyFingerprint, verifyProxyHello } from "@/server/proxy-hello";
import { reportSilentFallback, warnSilentFallback } from "@/server/observability";
import { EventEmitter } from "node:events";
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
    // +33, not +31: the verifier floors `now` to whole seconds, so a second tick between building and verifying the
    // hello turns a +31 s stamp into a 30 s skew (accepted). The exact boundary is pinned with an injected clock in proxy-hello.test.ts.
    ["skew +33 s", "skew", () => [raw({ ts: String(Math.floor(Date.now() / 1000) + 33) })]],
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
    await vi.waitFor(() => expect(reports().map((r) => r.extra)).toEqual([{ reason: "size", peer: "127.0.0.1" }]));
  });

  it("a verifier refusal ends in terminate(): a peer that ignores the close frame cannot keep streaming into a closing socket", async () => {
    const terminate = vi.spyOn(WebSocket.prototype, "terminate");
    const s = await start();
    const out = await run(s.port, ["not json at all"]);
    expect(out.closeCode).toBe(WS_CLOSE_CODES.ROUTING_UNAVAILABLE);
    await vi.waitFor(() => expect(terminate.mock.contexts.some((c) => (c as unknown as { _isServer?: boolean })._isServer === true)).toBe(true), { timeout: 2000 });
    terminate.mockRestore();
  });

  it("every owner-side refusal goes through refuse() (comment-stripped source: no bare uniform-reason close outside it)", () => {
    // A behavioural check cannot tell refuse() from a graceful close here: the polite test client closes (and the
    // server's own socket-error handler terminates) either way. The wire is pinned by call form instead.
    const src = readFileSync(path.join(__dirname, "../server/session-proxy.ts"), "utf8")
      .replace(/\/\*[\s\S]*?\*\//g, "")
      .replace(/^\s*\/\/.*$/gm, "");
    expect(src.match(/safeClose\(ws, WS_CLOSE_CODES\.ROUTING_UNAVAILABLE, RELAY_REFUSED\)/g)).toHaveLength(1);
    expect(src.match(/\brefuse\(ws\);/g)).toHaveLength(4); // defence-in-depth peer, verifier, membership, internal
    expect(src.match(/\bws\.close\(/g)).toHaveLength(1); // the one inside safeClose: no other direct close on the owner-side ws
  });

  it("the refusal linger is long enough for the 4014 frame to reach a legitimate sender and short enough to bound a streaming peer", () => {
    expect(REFUSE_LINGER_MS).toBeGreaterThanOrEqual(100);
    expect(REFUSE_LINGER_MS).toBeLessThanOrEqual(1000);
  });

  it.each([
    [999, false], [1000, true], [1003, true], [1004, false], [1005, false], [1006, false], [1014, true], [1015, false],
    [2999, false], [3000, true], [4014, true], [4999, true], [5000, false],
  ])("isSendableCloseCode(%i) is %s (the exact set `ws` can put on the wire)", (code, want) => {
    expect(isSendableCloseCode(code)).toBe(want);
  });

  it("a refused peer's later protocol error is not counted as a second refusal", async () => {
    const s = await start();
    const ws = new WebSocket(`wss://127.0.0.1:${s.port}/ws-proxy`, { ca: tls.CERT, rejectUnauthorized: true });
    clients.push(ws);
    ws.on("error", () => undefined);
    await new Promise<void>((r) => ws.once("open", () => r()));
    const sock = (ws as unknown as { _socket: import("node:net").Socket })._socket;
    // One write, two masked text frames: "x" (refused as shape by the verifier), then invalid UTF-8 (a ws protocol error
    // that arrives while the refusal is lingering).
    sock.write(Buffer.concat([Buffer.from([0x81, 0x81, 0, 0, 0, 0, 0x78]), Buffer.from([0x81, 0x83, 0, 0, 0, 0, 0xff, 0xfe, 0xfd])]));
    await vi.waitFor(() => expect(denyReporterModule.denyReporter.counters("shape").denied).toBe(1), { timeout: 2000 });
    await new Promise((r) => setTimeout(r, 400));
    expect(denyReporterModule.denyReporter.counters("shape").denied).toBe(1);
  });

  it("a protocol error while the AP-2 lookup is pending is still counted as a hello refusal (accepted is set only after proxy_ready)", async () => {
    let release: (v: boolean) => void = () => undefined;
    mockMembership.mockImplementation(() => new Promise<boolean>((r) => (release = r)));
    const s = await start();
    const ws = new WebSocket(`wss://127.0.0.1:${s.port}/ws-proxy`, { ca: tls.CERT, rejectUnauthorized: true });
    clients.push(ws);
    ws.on("error", () => undefined);
    await new Promise<void>((r) => ws.once("open", () => r()));
    ws.send(signProxyHello(KEY, U, W));
    await vi.waitFor(() => expect(mockMembership).toHaveBeenCalledTimes(1));
    const sock = (ws as unknown as { _socket: import("node:net").Socket })._socket;
    sock.write(Buffer.from([0x81, 0x83, 0, 0, 0, 0, 0xff, 0xfe, 0xfd])); // invalid UTF-8 text frame
    await vi.waitFor(() => expect(denyReporterModule.denyReporter.counters("shape").denied).toBe(1), { timeout: 2000 });
    release(true);
  });

  it("the byte guard terminates the socket (not a graceful close)", async () => {
    const terminate = vi.spyOn(WebSocket.prototype, "terminate");
    const s = await start();
    await run(s.port, [Buffer.alloc(64 * 1024, 0x20)], false);
    await vi.waitFor(() => expect(terminate.mock.contexts.some((c) => (c as unknown as { _isServer?: boolean })._isServer === true)).toBe(true), { timeout: 2000 });
    terminate.mockRestore();
  });

  it("the byte count is cumulative: 40 small pings (each under the bound) are cut off as size", async () => {
    const s = await start();
    const ws = new WebSocket(`wss://127.0.0.1:${s.port}/ws-proxy`, { ca: tls.CERT, rejectUnauthorized: true });
    clients.push(ws);
    ws.on("error", () => undefined);
    await new Promise<void>((r) => ws.once("open", () => r()));
    for (let i = 0; i < 40 && ws.readyState === WebSocket.OPEN; i++) {
      ws.ping(Buffer.alloc(125));
      await new Promise((r) => setTimeout(r, 15));
    }
    await vi.waitFor(() => expect(reports().map((r) => r.extra?.reason)).toEqual(["size"]), { timeout: 3000 });
    expect(reports()[0].extra).toEqual({ reason: "size", peer: "127.0.0.1" });
  });

  it("the production limits are pinned, and the deadline stays far above the serve-gate probe's hold", () => {
    expect(HELLO_DEADLINE_MS).toBe(10_000);
    expect(PRE_HELLO_MAX_BYTES).toBe(2048);
    const probe = readFileSync(path.join(__dirname, "../infra/ci-deploy.sh"), "utf8");
    const hold = [...probe.matchAll(/setTimeout\(verdict,(\d+)\)/g)].map((m) => Number(m[1]));
    expect(hold).toHaveLength(1);
    expect(HELLO_DEADLINE_MS).toBeGreaterThanOrEqual(10 * hold[0]);
  });

  it("the deadline is keyed per connection: a second silent peer from the same address neither orphans nor clears the first's timer", async () => {
    const s = await start({ helloDeadlineMs: 400 });
    const ws = new WebSocket(`wss://127.0.0.1:${s.port}/ws-proxy`, { ca: tls.CERT, rejectUnauthorized: true });
    clients.push(ws);
    ws.on("error", () => undefined);
    await new Promise<void>((r) => ws.once("open", () => r()));
    // The second peer is admitted while the first is still waiting to send its hello.
    const second = tlsConnect({ host: "127.0.0.1", port: s.port, ca: tls.CERT });
    second.on("error", () => undefined);
    const secondClosed = new Promise<void>((r) => second.once("close", () => r()));
    await new Promise<void>((r) => second.once("secureConnect", () => r()));
    const ready = new Promise<void>((resolve) => ws.on("message", (d) => JSON.parse(String(d)).type === "proxy_ready" && resolve()));
    ws.send(signProxyHello(KEY, U, W));
    await ready;
    await new Promise((r) => setTimeout(r, 900));
    expect(ws.readyState).toBe(WebSocket.OPEN); // the accepted session survives the second peer's deadline
    await secondClosed; // and the second, silent peer was dropped at its own deadline
  });

  it("the deadline destroys the socket: a half-open client that never sends FIN does not keep it alive", async () => {
    const s = await start({ helloDeadlineMs: 250 });
    const serverSide: import("node:stream").Duplex[] = [];
    s.server.on("connection", (sock) => serverSide.push(sock));
    const c = netConnect({ host: "127.0.0.1", port: s.port, allowHalfOpen: true });
    c.on("error", () => undefined);
    await vi.waitFor(() => expect(serverSide.length).toBe(1));
    await vi.waitFor(() => expect(serverSide[0].destroyed).toBe(true), { timeout: 2000 });
    c.destroy();
  });

  it("the injected deadline is honoured only under vitest (comment-stripped source, anchored on the expression)", () => {
    // Behavioural form is not possible: the other test seams (port 0, bind prefix) also need VITEST, so the
    // listener cannot start with it cleared.
    const src = readFileSync(path.join(__dirname, "../server/session-proxy.ts"), "utf8")
      .replace(/\/\*[\s\S]*?\*\//g, "")
      .replace(/^\s*\/\/.*$/gm, "");
    const decls = [...src.matchAll(/const deadlineMs = ([^;]+);/g)].map((m) => m[1].replace(/\s+/g, " "));
    expect(decls).toEqual(["process.env.VITEST ? (params.helloDeadlineMs ?? HELLO_DEADLINE_MS) : HELLO_DEADLINE_MS"]);
  });

  it("the ws options the byte guard relies on are pinned in source (comment-stripped, scoped to the constructor)", () => {
    const src = readFileSync(path.join(__dirname, "../server/session-proxy.ts"), "utf8")
      .replace(/\/\*[\s\S]*?\*\//g, "")
      .replace(/^\s*\/\/.*$/gm, "");
    const calls = [...src.matchAll(/new WebSocketServer\(\{([^}]*)\}\)/g)].map((m) => m[1]);
    expect(calls).toHaveLength(1);
    expect(calls[0]).toMatch(/perMessageDeflate:\s*false/);
    expect(calls[0]).toMatch(/allowSynchronousEvents:\s*true/);
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
    // Exact extras: the peer rides along, and only the error CLASS (never the message "db down").
    expect(reports().map((r) => r.extra)).toEqual([{ reason: "internal", peer: "127.0.0.1", errName: "Error" }]);
    expect(JSON.stringify(reports())).not.toContain("db down");
  });

  it("a protocol error AFTER proxy_ready is not counted as a hello refusal", async () => {
    const s = await start();
    const ws = new WebSocket(`wss://127.0.0.1:${s.port}/ws-proxy`, { ca: tls.CERT, rejectUnauthorized: true });
    clients.push(ws);
    ws.on("error", () => undefined);
    await new Promise<void>((resolve, reject) => {
      ws.on("message", (d) => JSON.parse(String(d)).type === "proxy_ready" && resolve());
      ws.once("open", () => ws.send(signProxyHello(KEY, U, W)));
      setTimeout(() => reject(new Error("no proxy_ready")), 3000);
    });
    // A frame with invalid UTF-8 in a text message makes the server-side receiver emit 'error'.
    const sock = (ws as unknown as { _socket: import("node:net").Socket })._socket;
    sock.write(Buffer.from([0x81, 0x83, 0, 0, 0, 0, 0xff, 0xfe, 0xfd]));
    await new Promise((r) => setTimeout(r, 400));
    expect(reports()).toEqual([]);
    expect(denyReporterModule.denyReporter.counters("shape")).toEqual({ denied: 0, reported: 0, suppressed: 0 });
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

// #8211 (ADR-323 Decision 9, B3) — the accept-only slot PROXY_HELLO_HMAC_KEY_ACCEPT_ALSO at the call sites: the
// sender signs with CURRENT only, the listener starts only with a CURRENT key, the verifier receives the key set, and
// every loader state has its exact Sentry events (named spies) plus the relay_hello_key_fp boot line.
describe("accept-only slot (#8211): call sites, degraded states and the fingerprint line", () => {
  const SLOT = "PROXY_HELLO_HMAC_KEY_ACCEPT_ALSO";
  const ACCEPT_HEX = randomBytes(32).toString("hex");
  const ACCEPT_KEY = Buffer.from(ACCEPT_HEX, "hex");
  const BASE = { privateBindPrefix: "", port: 0 } as const;
  const namedReport = vi.mocked(reportSilentFallback);
  const namedWarn = vi.mocked(warnSilentFallback);
  const warnOps = () => namedWarn.mock.calls.map((c) => c[1]?.op as string);
  const fpLines = () =>
    mockWarn.mock.calls.filter((c) => typeof c[1] === "string" && String(c[1]).startsWith("relay_hello_key_fp")) as Array<
      [Record<string, unknown>, string]
    >;
  const assertNoKeyMaterial = () => {
    const blob = JSON.stringify([mockReport.mock.calls, namedWarn.mock.calls, mockWarn.mock.calls]);
    for (const hex of [KEY_HEX, ACCEPT_HEX]) {
      expect(blob).not.toContain(hex);
      expect(blob).not.toContain(Buffer.from(hex, "hex").toString("base64"));
    }
  };
  const listen = async (server: HttpsServer | null) => {
    expect(server).not.toBeNull();
    opened.push(server as HttpsServer);
    if (!server?.listening) await new Promise<void>((r) => server?.once("listening", () => r()));
    const a = (server as HttpsServer).address();
    if (!a || typeof a === "string") throw new Error("no address");
    return a.port;
  };
  const startWith = (current: string, slot: string | undefined) => {
    vi.stubEnv("PROXY_HELLO_HMAC_KEY", current);
    if (slot !== undefined) vi.stubEnv(SLOT, slot);
    vi.stubEnv("SOLEUR_PROXY_PEER_ALLOWLIST", "127.0.0.1");
    return createProxyServer({ onProxiedSession, ...BASE, bindAddress: "127.0.0.1" });
  };

  it("the reporter spies are the named module exports (not anonymous vi.fn())", () => {
    expect(namedReport).toBe(mockReport);
    expect(vi.isMockFunction(namedWarn)).toBe(true);
    expect(KEY_HEX).not.toBe(ACCEPT_HEX); // fixture distinctness
  });

  it("slot unset (default): listens, 0 events, one fingerprint line with accept_also=none", async () => {
    const port = await listen(startWith(KEY_HEX, undefined));
    expect(reports()).toEqual([]);
    expect(warnOps()).toEqual([]);
    const lines = fpLines();
    expect(lines).toHaveLength(1);
    expect(lines[0][1]).toBe(`relay_hello_key_fp current=${helloKeyFingerprint(KEY)} accept_also=none`);
    expect(lines[0][0]).toEqual({ current_fp: helloKeyFingerprint(KEY), accept_also_fp: "none" });
    expect((await run(port, [signProxyHello(KEY, U, W)])).ready).toBe(true);
  });

  it("slot malformed: listens, exactly 1 accept-also-ignored event (no extra), the slot is absent", async () => {
    const port = await listen(startWith(KEY_HEX, ACCEPT_HEX.toUpperCase()));
    expect(reports()).toEqual([{ op: "loadProxyHelloKeys.accept-also-ignored", extra: undefined }]);
    expect(warnOps()).toEqual([]);
    expect(fpLines().map((l) => l[1])).toEqual([`relay_hello_key_fp current=${helloKeyFingerprint(KEY)} accept_also=none`]);
    expect((await run(port, [signProxyHello(ACCEPT_KEY, U, W)])).ready).toBe(false);
    assertNoKeyMaterial();
  });

  it("slot equal to current: listens, exactly 1 warn-level accept-also-equals-current event, the line shows equal values", async () => {
    await listen(startWith(KEY_HEX, KEY_HEX));
    expect(reports()).toEqual([]);
    expect(warnOps()).toEqual(["loadProxyHelloKeys.accept-also-equals-current"]);
    const fp = helloKeyFingerprint(KEY);
    expect(fpLines().map((l) => l[1])).toEqual([`relay_hello_key_fp current=${fp} accept_also=${fp}`]);
    assertNoKeyMaterial();
  });

  it("slot well-formed and distinct: exactly 1 warn-level accept-also-active event (no value, no fingerprint), and an accept-also hello is admitted", async () => {
    const port = await listen(startWith(KEY_HEX, ACCEPT_HEX));
    expect(reports()).toEqual([]);
    expect(warnOps()).toEqual(["loadProxyHelloKeys.accept-also-active"]);
    const payload = JSON.stringify(namedWarn.mock.calls);
    expect(payload).not.toContain(helloKeyFingerprint(KEY));
    expect(payload).not.toContain(helloKeyFingerprint(ACCEPT_KEY));
    expect(namedWarn.mock.calls[0][1]?.extra).toBeUndefined();
    const lines = fpLines();
    expect(lines.map((l) => l[1])).toEqual([
      `relay_hello_key_fp current=${helloKeyFingerprint(KEY)} accept_also=${helloKeyFingerprint(ACCEPT_KEY)}`,
    ]);
    expect(lines[0][0]).toEqual({ current_fp: helloKeyFingerprint(KEY), accept_also_fp: helloKeyFingerprint(ACCEPT_KEY) });
    expect(helloKeyFingerprint(KEY)).not.toBe(helloKeyFingerprint(ACCEPT_KEY));
    const out = await run(port, [signProxyHello(ACCEPT_KEY, U, W)]);
    expect(out.ready).toBe(true);
    expect(onProxiedSession.mock.calls[0][1]).toEqual({ userId: U, workspaceId: W });
    expect((await run(port, [signProxyHello(KEY, U, W)])).ready).toBe(true);
    expect((await run(port, [raw({}, randomBytes(32))])).ready).toBe(false);
    expect(reports().map((r) => r.extra?.reason)).toEqual(["mac"]);
    assertNoKeyMaterial();
  });

  it("slot well-formed, current absent: no listener, exactly 1 no-hello-key event, 0 accept-also events, no fingerprint line", () => {
    expect(startWith("", ACCEPT_HEX)).toBeNull();
    expect(getProxyStatus().state).toBe("error");
    expect(reports().map((r) => r.op)).toEqual(["createProxyServer.no-hello-key"]);
    expect(warnOps()).toEqual([]);
    expect(fpLines()).toEqual([]);
    assertNoKeyMaterial();
  });

  it("slot malformed, current absent: no listener, 1 accept-also-ignored then 1 no-hello-key event", () => {
    expect(startWith("", "zz")).toBeNull();
    expect(reports().map((r) => r.op)).toEqual(["loadProxyHelloKeys.accept-also-ignored", "createProxyServer.no-hello-key"]);
    expect(warnOps()).toEqual([]);
    expect(fpLines()).toEqual([]);
  });

  it("both unset: no listener, exactly 1 no-hello-key event", () => {
    expect(startWith("", undefined)).toBeNull();
    expect(reports().map((r) => r.op)).toEqual(["createProxyServer.no-hello-key"]);
    expect(warnOps()).toEqual([]);
  });

  it("call twice: the loader's event fires once per process, while each listener start prints its own fingerprint line", async () => {
    await listen(startWith(KEY_HEX, ACCEPT_HEX));
    await listen(createProxyServer({ onProxiedSession, ...BASE, bindAddress: "127.0.0.1" }));
    expect(warnOps()).toEqual(["loadProxyHelloKeys.accept-also-active"]);
    expect(fpLines()).toHaveLength(2);
  });

  it("the canary (empty bind) stops before the key check: no fingerprint line, no slot event", () => {
    vi.stubEnv(SLOT, ACCEPT_HEX);
    vi.stubEnv("SOLEUR_PROXY_PEER_ALLOWLIST", "127.0.0.1");
    expect(createProxyServer({ onProxiedSession, ...BASE, bindAddress: "" })).toBeNull();
    expect(fpLines()).toEqual([]);
    expect(warnOps()).toEqual([]);
  });

  it("a hello admitted through accept-also still gets the AP-2 membership deny when membership is false", async () => {
    mockMembership.mockResolvedValue(false);
    const port = await listen(startWith(KEY_HEX, ACCEPT_HEX));
    const out = await run(port, [signProxyHello(ACCEPT_KEY, U, W)]);
    expect(out.ready).toBe(false);
    expect(out.closeReason).toBe("relay refused");
    expect(onProxiedSession).not.toHaveBeenCalled();
    expect(reports()).toEqual([
      { op: "createProxyServer.ap2-deny", extra: { reason: "membership", peer: "127.0.0.1", userId: U, workspaceId: W } },
    ]);
  });

  it("a replayed accept-also hello is refused with replay over the real listener", async () => {
    const port = await listen(startWith(KEY_HEX, ACCEPT_HEX));
    const text = signProxyHello(ACCEPT_KEY, U, W);
    expect((await run(port, [text])).ready).toBe(true);
    expect((await run(port, [text])).ready).toBe(false);
    expect(reports().map((r) => r.extra?.reason)).toEqual(["replay"]);
  });

  it("the sender signs with CURRENT only: with both keys set, its hello verifies under CURRENT and fails on a verifier holding only the accept-also key", async () => {
    vi.stubEnv("PROXY_HELLO_HMAC_KEY", KEY_HEX);
    vi.stubEnv(SLOT, ACCEPT_HEX);
    class FakeWs extends EventEmitter {
      readyState = 1;
      sent: unknown[] = [];
      send(d: unknown) {
        this.sent.push(d);
      }
      close() {
        this.readyState = 3;
      }
    }
    const client = new FakeWs();
    const owner = new FakeWs();
    await proxyClientToOwner({ clientWs: client as never, ownerAddress: "10.0.1.12", userId: U, workspaceId: W, dial: (() => owner) as never });
    owner.emit("open");
    expect(owner.sent).toHaveLength(1);
    const frame = Buffer.from(owner.sent[0] as string);
    expect(verifyProxyHello(frame, false, { current: KEY, acceptAlso: null }, createReplayCache())).toEqual({ ok: true, userId: U, workspaceId: W });
    expect(verifyProxyHello(frame, false, { current: ACCEPT_KEY, acceptAlso: null }, createReplayCache())).toEqual({ ok: false, reason: "mac" });
  });

  it("the sender with only the accept-also key (current absent) never dials: no_key", async () => {
    vi.stubEnv("PROXY_HELLO_HMAC_KEY", "");
    vi.stubEnv(SLOT, ACCEPT_HEX);
    const dial = vi.fn();
    const client = new EventEmitter() as EventEmitter & { readyState: number; close: () => void };
    client.readyState = 1;
    client.close = () => undefined;
    await proxyClientToOwner({ clientWs: client as never, ownerAddress: "10.0.1.12", userId: U, workspaceId: W, dial: dial as never });
    expect(dial).not.toHaveBeenCalled();
  });
});
