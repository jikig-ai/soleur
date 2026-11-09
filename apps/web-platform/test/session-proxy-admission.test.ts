import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { Socket, connect as netConnect } from "node:net";
import { connect as tlsConnect } from "node:tls";
import type { Server as HttpsServer } from "node:https";
import { WebSocket } from "ws";
import { makeProxyTestTls, type ProxyTestTls } from "./helpers/proxy-test-tls";

// #12288 — the owner admits a peer on the raw TCP `remoteAddress` BEFORE the TLS handshake
// starts. Real sockets: a mocked server cannot show that no handshake happened.

const { mockWarn, mockReportSilentFallback } = vi.hoisted(() => ({
  mockWarn: vi.fn(),
  mockReportSilentFallback: vi.fn(),
}));

vi.mock("@/server/logger", () => {
  const child = () => ({ info: vi.fn(), warn: mockWarn, error: vi.fn(), debug: vi.fn() });
  return { default: child(), createChildLogger: child };
});
vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
  warnSilentFallback: vi.fn(),
  infoSilentFallback: vi.fn(),
}));

import { createProxyServer, isAllowedProxyPeer, parseProxyPeerAllowlist } from "@/server/session-proxy";
import { __resetDenyReporterForTests, denyReporter } from "@/server/proxy-deny-report";
import { __resetProxyListenerStatusForTests, getProxyStatus } from "@/server/proxy-listener-status";

const TEST_BIND = { privateBindPrefix: "", bindAddress: "127.0.0.1", port: 0 } as const;
const GRAMMAR =
  /^relay_probe proxy_state=(listening|disabled|no_bind|no_allowlist|error) addr=([0-9a-fA-F:.]+|none) port=\d{1,5} workspaces_populated=[01]$/;

let tls: ProxyTestTls;
beforeAll(() => {
  tls = makeProxyTestTls();
});
afterAll(() => tls.cleanup());

const opened: HttpsServer[] = [];
const sockets: Socket[] = [];
const onProxiedSession = vi.fn();

async function start(allowlist: string): Promise<{ server: HttpsServer; port: number; secure: () => number; conns: () => number }> {
  vi.stubEnv("SOLEUR_PROXY_PEER_ALLOWLIST", allowlist);
  const server = createProxyServer({ onProxiedSession, ...TEST_BIND });
  if (!server) throw new Error("createProxyServer returned null");
  opened.push(server);
  let secure = 0;
  let conns = 0;
  server.on("secureConnection", () => secure++);
  server.on("connection", () => conns++);
  if (!server.listening) await new Promise<void>((r) => server.once("listening", () => r()));
  const a = server.address();
  if (!a || typeof a === "string") throw new Error("no address");
  return { server, port: a.port, secure: () => secure, conns: () => conns };
}

beforeEach(() => {
  vi.clearAllMocks();
  vi.unstubAllEnvs();
  vi.stubEnv("PROXY_TLS_KEY", tls.KEY);
  vi.stubEnv("PROXY_TLS_CERT", tls.CERT);
  vi.stubEnv("SOLEUR_PROXY_BIND", "");
  vi.stubEnv("PROXY_HELLO_HMAC_KEY", "a".repeat(64));
  __resetProxyListenerStatusForTests();
  __resetDenyReporterForTests();
});

afterEach(async () => {
  vi.unstubAllEnvs();
  for (const s of sockets.splice(0)) s.destroy();
  for (const s of opened.splice(0)) await new Promise<void>((r) => s.close(() => r()));
});

const peerReports = () => mockReportSilentFallback.mock.calls.filter((c) => c[1]?.op === "createProxyServer.peer-deny");

function tlsOutcome(port: number): Promise<"secure" | "reset" | "closed"> {
  return new Promise((resolve) => {
    // Kept open (afterEach destroys it) so the server side can finish counting the handshake.
    const sock = tlsConnect({ host: "127.0.0.1", port, ca: tls.CERT, rejectUnauthorized: true }, () => {
      resolve("secure");
    });
    sockets.push(sock);
    sock.once("error", (e: NodeJS.ErrnoException) => resolve(e.code === "ECONNRESET" ? "reset" : "closed"));
    sock.once("close", () => resolve("closed"));
  });
}

describe("pre-TLS admission", () => {
  it("(a) an allowlisted peer completes the TLS handshake", async () => {
    const s = await start("127.0.0.1");
    expect(await tlsOutcome(s.port)).toBe("secure");
    await vi.waitFor(() => expect(s.secure()).toBe(1));
    expect(peerReports()).toHaveLength(0);
  });

  it("(b) a non-allowlisted peer is reset before any handshake: secureConnection stays 0", async () => {
    const s = await start("10.0.1.9");
    expect(await tlsOutcome(s.port)).not.toBe("secure");
    await vi.waitFor(() => expect(s.conns()).toBe(1));
    expect(s.secure()).toBe(0);
    expect(peerReports()).toHaveLength(1);
    expect(peerReports()[0][1].extra).toEqual({ reason: "peer", peer: "127.0.0.1" });
  });

  it("(b2) the admission listener is the FIRST connection listener and is named", async () => {
    const s = await start("127.0.0.1");
    const first = s.server.listeners("connection")[0] as { name: string };
    expect(first.name).toBe("admitProxyPeer");
  });

  it("(c) a connection with no remoteAddress is destroyed (deny, never allow)", async () => {
    const s = await start("127.0.0.1");
    const fake = new Socket();
    Object.defineProperty(fake, "remoteAddress", { value: undefined });
    s.server.emit("connection", fake);
    expect(fake.destroyed).toBe(true);
    expect(peerReports()).toHaveLength(1);
    expect(peerReports()[0][1].extra).toEqual({ reason: "peer", peer: "unknown" });
  });

  it("(d) the IPv4-mapped spelling matches a plain-IPv4 allowlist; a trailing-space CSV entry matches too", () => {
    const allow = parseProxyPeerAllowlist("10.0.1.8, 10.0.1.9 ");
    expect(isAllowedProxyPeer("::ffff:10.0.1.9", allow)).toBe(true);
    expect(isAllowedProxyPeer("10.0.1.8", allow)).toBe(true);
    expect(isAllowedProxyPeer("::ffff:10.0.1.7", allow)).toBe(false);
    expect(isAllowedProxyPeer(undefined, allow)).toBe(false);
    expect(isAllowedProxyPeer("", allow)).toBe(false);
    expect(isAllowedProxyPeer(null, allow)).toBe(false);
  });

  it("(d2) a fake socket spelled ::ffff:<allowlisted> is NOT destroyed by admission", async () => {
    const s = await start("10.0.1.9");
    const fake = new Socket();
    Object.defineProperty(fake, "remoteAddress", { value: "::ffff:10.0.1.9" });
    fake.on("error", () => undefined);
    s.server.emit("connection", fake);
    expect(peerReports()).toHaveLength(0);
    sockets.push(fake);
  });

  it("(e) a flood of 200 denied connects yields exactly 5 reports and an exact counter of 200", async () => {
    const s = await start("10.0.1.9");
    await Promise.all(
      Array.from({ length: 200 }, () =>
        new Promise<void>((resolve) => {
          const c = netConnect({ host: "127.0.0.1", port: s.port });
          sockets.push(c);
          c.once("error", () => resolve());
          c.once("close", () => resolve());
        }),
      ),
    );
    await vi.waitFor(() => expect(s.conns()).toBe(200));
    expect(peerReports()).toHaveLength(5);
    expect(denyReporter.counters("peer")).toEqual({ denied: 200, reported: 5, suppressed: 195 });
    expect(s.secure()).toBe(0);
  });

  it("(f) an allowlisted peer that sends no hello is NOT closed within 1.2 s (pins the 700 ms ok-probe contract)", async () => {
    const s = await start("127.0.0.1");
    const ws = new WebSocket(`wss://127.0.0.1:${s.port}/ws-proxy`, { ca: tls.CERT, rejectUnauthorized: true });
    await new Promise<void>((resolve, reject) => {
      ws.once("open", () => resolve());
      ws.once("error", reject);
    });
    await new Promise((r) => setTimeout(r, 1200));
    expect(ws.readyState).toBe(WebSocket.OPEN);
    ws.close();
  });

  it("(g) relay_probe still reads listening and the emitted line matches the closed grammar", async () => {
    await start("127.0.0.1");
    expect(getProxyStatus().state).toBe("listening");
    const { emitProxyListenerStatusOnce } = await import("@/server/proxy-listener-status");
    emitProxyListenerStatusOnce({ readWorkspacesPopulated: () => true });
    const lines = mockWarn.mock.calls.map((c) => String(c[1])).filter((l) => l.startsWith("relay_probe"));
    expect(lines).toHaveLength(1);
    expect(lines[0]).toMatch(GRAMMAR);
  });
});
