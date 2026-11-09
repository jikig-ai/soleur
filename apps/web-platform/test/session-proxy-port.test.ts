import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { EventEmitter } from "node:events";
import { Server as NetServer } from "node:net";
import type { Server as HttpsServer } from "node:https";
import { randomBytes, randomUUID } from "node:crypto";
import { WS_CLOSE_CODES } from "@/lib/types";
import { makeProxyTestTls, type ProxyTestTls } from "./helpers/proxy-test-tls";

// #12290 — a bad SOLEUR_PROXY_PORT (or port param) must never throw out of createProxyServer or make the
// sender dial wss://host:NaN. The relay is simply not started: reported, proxy_state=error, the app keeps
// serving its other ports. `listen()` is the second fence: any synchronous throw is caught.

const { mockReport } = vi.hoisted(() => ({ mockReport: vi.fn() }));
vi.mock("@/server/logger", () => {
  const child = () => ({ info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() });
  return { default: child(), createChildLogger: child };
});
vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReport,
  warnSilentFallback: vi.fn(),
  infoSilentFallback: vi.fn(),
}));

import { DEFAULT_PROXY_PORT, createProxyServer, proxyClientToOwner, resolveProxyPort } from "@/server/session-proxy";
import { __resetProxyListenerStatusForTests, getProxyStatus } from "@/server/proxy-listener-status";
import { __resetDenyReporterForTests } from "@/server/proxy-deny-report";
import { __resetProxyHelloKeyForTests } from "@/server/proxy-tls";

const KEY_HEX = randomBytes(32).toString("hex");
let tls: ProxyTestTls;
beforeAll(() => {
  tls = makeProxyTestTls();
});
afterAll(() => tls.cleanup());

const opened: HttpsServer[] = [];
const onProxiedSession = vi.fn();
const BASE = { privateBindPrefix: "", bindAddress: "127.0.0.1" } as const;

beforeEach(() => {
  vi.clearAllMocks();
  vi.unstubAllEnvs();
  vi.stubEnv("PROXY_TLS_KEY", tls.KEY);
  vi.stubEnv("PROXY_TLS_CERT", tls.CERT);
  vi.stubEnv("SOLEUR_PROXY_PEER_ALLOWLIST", "127.0.0.1");
  vi.stubEnv("SOLEUR_PROXY_BIND", "");
  vi.stubEnv("PROXY_HELLO_HMAC_KEY", KEY_HEX);
  __resetProxyListenerStatusForTests();
  __resetDenyReporterForTests();
  __resetProxyHelloKeyForTests();
});
afterEach(async () => {
  vi.restoreAllMocks();
  vi.unstubAllEnvs();
  for (const s of opened.splice(0)) await new Promise<void>((r) => s.close(() => r()));
});

describe("resolveProxyPort", () => {
  it.each([
    ["8443", 8443],
    ["1", 1],
    ["65535", 65535],
    ["443", 443],
    ["", DEFAULT_PROXY_PORT],
    [undefined, DEFAULT_PROXY_PORT],
  ])("%j -> %j", (raw, want) => {
    expect(resolveProxyPort(raw as string | undefined)).toBe(want);
  });

  it.each(["abc", "0", "65536", "-1", "8443.5", "0x20fb", "1e3", " 8443", "8443 ", "99999999999", "08443x", "８４４３", "+8443", "NaN", "Infinity"])(
    "%j is rejected (null)",
    (raw) => {
      expect(resolveProxyPort(raw)).toBeNull();
    },
  );

  it("the default is the prod pin, 8443", () => {
    expect(DEFAULT_PROXY_PORT).toBe(8443);
  });
});

describe("createProxyServer never throws on a bad port", () => {
  it.each([[Number.NaN], [-1], [70000], [1.5], [65536]])("params.port %j -> null, proxy_state=error, one bad-port event", (port) => {
    const server = createProxyServer({ onProxiedSession, ...BASE, port });
    expect(server).toBeNull();
    expect(getProxyStatus().state).toBe("error");
    expect(mockReport.mock.calls.map((c) => c[1].op)).toEqual(["createProxyServer.bad-port"]);
    expect(JSON.stringify(mockReport.mock.calls[0][1].extra ?? {})).not.toMatch(/NaN|70000|65536/);
  });

  it.each([["abc"], ["0"], ["65536"], ["0x20fb"], ["1e3"], [" 8443"]])("env SOLEUR_PROXY_PORT=%j -> null, error, one bad-port event", (raw) => {
    vi.stubEnv("SOLEUR_PROXY_PORT", raw);
    expect(createProxyServer({ onProxiedSession, ...BASE })).toBeNull();
    expect(getProxyStatus().state).toBe("error");
    expect(mockReport.mock.calls.map((c) => c[1].op)).toEqual(["createProxyServer.bad-port"]);
  });

  it("params.port 0 (ephemeral, test seam) stays valid and listens", async () => {
    const server = createProxyServer({ onProxiedSession, ...BASE, port: 0 });
    expect(server).not.toBeNull();
    opened.push(server as HttpsServer);
    await new Promise<void>((r) => ((server as HttpsServer).listening ? r() : (server as HttpsServer).once("listening", () => r())));
    expect(getProxyStatus().state).toBe("listening");
    expect(mockReport).not.toHaveBeenCalled();
  });

  it("a bad port does not precede the earlier checks: no key -> still no-hello-key; no allowlist -> still no_allowlist", () => {
    vi.stubEnv("SOLEUR_PROXY_PORT", "abc");
    vi.stubEnv("SOLEUR_PROXY_PEER_ALLOWLIST", "");
    expect(createProxyServer({ onProxiedSession, ...BASE })).toBeNull();
    expect(getProxyStatus().state).toBe("no_allowlist");
  });

  it("a bad port does not precede the key guard: no key + bad port still reads no-hello-key", () => {
    vi.stubEnv("SOLEUR_PROXY_PORT", "abc");
    vi.stubEnv("PROXY_HELLO_HMAC_KEY", "");
    __resetProxyHelloKeyForTests();
    expect(createProxyServer({ onProxiedSession, ...BASE })).toBeNull();
    expect(mockReport.mock.calls.map((c) => c[1].op)).toEqual(["createProxyServer.no-hello-key"]);
  });

  it("a synchronously throwing listen() is caught: server closed once, state error, reported with the code only, null", () => {
    const closeSpy = vi.spyOn(NetServer.prototype, "close");
    vi.spyOn(NetServer.prototype, "listen").mockImplementation(() => {
      throw Object.assign(new Error("secret-ish detail 10.0.1.9"), { code: "ERR_SOCKET_BAD_PORT" });
    });
    const server = createProxyServer({ onProxiedSession, ...BASE, port: 0 });
    expect(server).toBeNull();
    expect(closeSpy).toHaveBeenCalledTimes(1);
    expect(getProxyStatus().state).toBe("error");
    expect(mockReport.mock.calls.map((c) => c[1].op)).toEqual(["createProxyServer.listen-throw"]);
    expect(mockReport.mock.calls[0][1].extra).toEqual({ code: "ERR_SOCKET_BAD_PORT" });
    expect(JSON.stringify(mockReport.mock.calls)).not.toContain("secret-ish");
  });

  it("a throwing listen() with a non-code error still returns null and reports code undefined", () => {
    vi.spyOn(NetServer.prototype, "listen").mockImplementation(() => {
      throw "not an error object";
    });
    expect(createProxyServer({ onProxiedSession, ...BASE, port: 0 })).toBeNull();
    expect(getProxyStatus().state).toBe("error");
  });
});

class FakeWs extends EventEmitter {
  readyState = 1;
  sent: unknown[] = [];
  closed?: { code: number; reason: string };
  send(d: unknown) {
    this.sent.push(d);
  }
  close(code: number, reason: string) {
    this.closed = { code, reason };
    this.readyState = 3;
  }
}

describe("sender with an invalid port", () => {
  const U = randomUUID();
  const W = randomUUID();
  it.each([["abc"], ["0"], ["65536"], ["1e3"]])("env %j -> client closed, no dial, one bounded bad-port event", async (raw) => {
    vi.stubEnv("SOLEUR_PROXY_PORT", raw);
    const client = new FakeWs();
    const dial = vi.fn();
    await proxyClientToOwner({ clientWs: client as never, ownerAddress: "10.0.1.12", userId: U, workspaceId: W, dial: dial as never });
    expect(dial).not.toHaveBeenCalled();
    expect(client.closed?.code).toBe(WS_CLOSE_CODES.ROUTING_UNAVAILABLE);
    expect(mockReport.mock.calls.map((c) => c[1].op)).toEqual(["proxyClientToOwner.bad-port"]);
  });

  it.each([[Number.NaN], [0], [70000], [1.5]])("params.port %j -> no dial", async (port) => {
    const client = new FakeWs();
    const dial = vi.fn();
    await proxyClientToOwner({ clientWs: client as never, ownerAddress: "10.0.1.12", userId: U, workspaceId: W, port, dial: dial as never });
    expect(dial).not.toHaveBeenCalled();
    expect(mockReport.mock.calls.map((c) => c[1].op)).toEqual(["proxyClientToOwner.bad-port"]);
  });

  it("a valid env port is used in the dial URL (positive control)", async () => {
    vi.stubEnv("SOLEUR_PROXY_PORT", "9443");
    const owner = new FakeWs();
    const dial = vi.fn(() => owner);
    await proxyClientToOwner({ clientWs: new FakeWs() as never, ownerAddress: "10.0.1.12", userId: U, workspaceId: W, dial: dial as never });
    expect((dial.mock.calls[0] as unknown as [string])[0]).toBe("wss://10.0.1.12:9443/ws-proxy");
  });
});
