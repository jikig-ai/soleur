/**
 * Unit tests — session-proxy.ts proxying-host relay (epic #5274 Phase 3 Sub-PR
 * 3.B, CTO ruling b2). Drives proxyClientToOwner with an injected `dial` +
 * fake sockets: the control handshake (proxy_hello → proxy_ready), bidirectional
 * frame forwarding after ready, close-code forwarding both ways, and the
 * fail-safe teardown when no pinned CA is configured. The live host↔host TLS
 * transport is soak-validated at 3.D (AC7/AC8); this locks the relay LOGIC.
 */

import { EventEmitter } from "node:events";
import { randomBytes, randomUUID } from "node:crypto";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { WS_CLOSE_CODES } from "@/lib/types";

const { mockReport } = vi.hoisted(() => ({ mockReport: vi.fn() }));
vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReport,
  warnSilentFallback: vi.fn(),
  infoSilentFallback: vi.fn(),
}));

import {
  proxyClientToOwner,
  normalizeProxyPeerAddress,
  parseProxyPeerAllowlist,
} from "@/server/session-proxy";
import { verifyProxyHello, createReplayCache } from "@/server/proxy-hello";
import { __resetDenyReporterForTests } from "@/server/proxy-deny-report";

const TEST_CERT = "-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----";
const KEY_HEX = randomBytes(32).toString("hex");
const KEY = Buffer.from(KEY_HEX, "hex");
const U = randomUUID();
const W = randomUUID();

class FakeWs extends EventEmitter {
  readyState = 1; // ws.WebSocket.OPEN
  sent: unknown[] = [];
  closed?: { code: number; reason: string };
  send(data: unknown) {
    this.sent.push(data);
  }
  close(code: number, reason: string) {
    this.closed = { code, reason };
    this.readyState = 3;
  }
}

beforeEach(() => {
  vi.clearAllMocks();
  vi.unstubAllEnvs();
  vi.stubEnv("PROXY_TLS_CERT", TEST_CERT);
  vi.stubEnv("PROXY_HELLO_HMAC_KEY", KEY_HEX);
  __resetDenyReporterForTests();
});
afterEach(() => vi.unstubAllEnvs());

// CTO ruling (3.D security): the owner proxy listener carries a token-less
// pre-authed session, and Hetzner cloud firewalls do NOT filter the private net
// (git-data.tf, resource "hcloud_firewall" "git_data" — no rule blocks), so any 10.0.1.0/24 host — including the LESS-privileged
// git-data host — could open port 8443 and take over any account. The load-bearing
// control is a guest-side peer-origin allowlist (the infra firewall can't do it).
// These lock the pure decision the connection handler uses.
describe("proxy peer-origin allowlist (3.D CTO ruling — account-takeover defense)", () => {
  test("normalizeProxyPeerAddress strips the IPv4-mapped IPv6 prefix so peers compare equal", () => {
    expect(normalizeProxyPeerAddress("::ffff:10.0.1.10")).toBe("10.0.1.10");
    expect(normalizeProxyPeerAddress("10.0.1.10")).toBe("10.0.1.10");
    expect(normalizeProxyPeerAddress(undefined)).toBe("");
    expect(normalizeProxyPeerAddress(null)).toBe("");
  });

  test("parseProxyPeerAllowlist parses trimmed, non-empty CSV entries", () => {
    const set = parseProxyPeerAllowlist(" 10.0.1.10 , 10.0.1.11 ,");
    expect(set.has("10.0.1.10")).toBe(true);
    expect(set.has("10.0.1.11")).toBe(true);
    expect(set.size).toBe(2); // trailing comma / blank dropped
  });

  test("an UNSET/empty allowlist is empty (→ createProxyServer fails closed)", () => {
    expect(parseProxyPeerAllowlist(undefined).size).toBe(0);
    expect(parseProxyPeerAllowlist("").size).toBe(0);
    expect(parseProxyPeerAllowlist("  ,  ").size).toBe(0);
  });

  test("the git-data host (10.0.1.20) is NOT a web-host peer → rejected; web hosts pass", () => {
    const allow = parseProxyPeerAllowlist("10.0.1.10,10.0.1.11");
    // The takeover vector the ruling closes: a connection from the git-data host.
    expect(allow.has(normalizeProxyPeerAddress("::ffff:10.0.1.20"))).toBe(false);
    expect(allow.has(normalizeProxyPeerAddress("10.0.1.20"))).toBe(false);
    // Legit peer web hosts pass.
    expect(allow.has(normalizeProxyPeerAddress("::ffff:10.0.1.10"))).toBe(true);
    expect(allow.has(normalizeProxyPeerAddress("10.0.1.11"))).toBe(true);
  });
});

describe("proxyClientToOwner", () => {
  test("no pinned CA → closes the client non-transiently and never dials (never MITM)", async () => {
    vi.stubEnv("PROXY_TLS_CERT", "");
    const client = new FakeWs();
    const dial = vi.fn();
    await proxyClientToOwner({
      clientWs: client as never,
      ownerAddress: "10.0.1.12",
      userId: U,
      workspaceId: W,
      dial: dial as never,
    });
    expect(dial).not.toHaveBeenCalled();
    expect(client.closed?.code).toBe(WS_CLOSE_CODES.ROUTING_UNAVAILABLE);
  });

  test("dials with the pinned CA + rejectUnauthorized:true and sends proxy_hello on open", async () => {
    const client = new FakeWs();
    const owner = new FakeWs();
    const dial = vi.fn((_url: string, _opts: { ca: string; rejectUnauthorized: true }) => owner);
    await proxyClientToOwner({
      clientWs: client as never,
      ownerAddress: "10.0.1.12",
      userId: U,
      workspaceId: W,
      dial: dial as never,
    });
    expect(dial).toHaveBeenCalledTimes(1);
    const [url, opts] = dial.mock.calls[0]!;
    expect(url).toContain("wss://10.0.1.12");
    expect(opts).toMatchObject({ ca: TEST_CERT, rejectUnauthorized: true });

    owner.emit("open");
    const sent = JSON.parse(owner.sent[0] as string);
    expect(Object.keys(sent).sort()).toEqual(["mac", "nonce", "ts", "type", "userId", "workspaceId"]);
    expect(sent).toMatchObject({ type: "proxy_hello", userId: U, workspaceId: W });
    // The hello verifies under the same key through the REAL verifier (sender and verifier agree).
    expect(verifyProxyHello(Buffer.from(owner.sent[0] as string), false, KEY, createReplayCache())).toEqual({
      ok: true,
      userId: U,
      workspaceId: W,
    });
  });

  test("two sends differ in nonce (fresh randomness per hello)", async () => {
    const nonces: string[] = [];
    for (let i = 0; i < 2; i++) {
      const owner = new FakeWs();
      await proxyClientToOwner({
        clientWs: new FakeWs() as never,
        ownerAddress: "10.0.1.12",
        userId: U,
        workspaceId: W,
        dial: (() => owner) as never,
      });
      owner.emit("open");
      nonces.push(JSON.parse(owner.sent[0] as string).nonce);
    }
    expect(nonces[0]).not.toBe(nonces[1]);
  });

  test.each([
    ["absent", ""],
    ["63 hex", "a".repeat(63)],
    ["uppercase", "A".repeat(64)],
  ])("hello key %s -> client closed ROUTING_UNAVAILABLE, never dials, one bounded no-hello-key event", async (_n, value) => {
    vi.stubEnv("PROXY_HELLO_HMAC_KEY", value);
    const client = new FakeWs();
    const dial = vi.fn();
    await proxyClientToOwner({ clientWs: client as never, ownerAddress: "10.0.1.12", userId: U, workspaceId: W, dial: dial as never });
    expect(dial).not.toHaveBeenCalled();
    expect(client.closed?.code).toBe(WS_CLOSE_CODES.ROUTING_UNAVAILABLE);
    expect(mockReport.mock.calls.map((c) => c[1].op)).toEqual(["proxyClientToOwner.no-hello-key"]);
    expect(JSON.stringify(mockReport.mock.calls)).not.toContain(value || "\u0000never");
  });

  test.each([
    ["non-UUID userId", "user-42", W],
    ["non-UUID workspaceId", U, "ws-9"],
    ["uppercase userId", U.toUpperCase(), W],
  ])("%s -> client closed, never dials, bounded bad-ids event", async (_n, uid, wid) => {
    const client = new FakeWs();
    const dial = vi.fn();
    await proxyClientToOwner({ clientWs: client as never, ownerAddress: "10.0.1.12", userId: uid, workspaceId: wid, dial: dial as never });
    expect(dial).not.toHaveBeenCalled();
    expect(client.closed?.code).toBe(WS_CLOSE_CODES.ROUTING_UNAVAILABLE);
    expect(mockReport.mock.calls.map((c) => c[1].op)).toEqual(["proxyClientToOwner.bad-ids"]);
  });

  test("a burst of 20 refused sends reports at most 5 events", async () => {
    vi.stubEnv("PROXY_HELLO_HMAC_KEY", "");
    for (let i = 0; i < 20; i++) {
      await proxyClientToOwner({ clientWs: new FakeWs() as never, ownerAddress: "10.0.1.12", userId: U, workspaceId: W, dial: vi.fn() as never });
    }
    expect(mockReport.mock.calls.filter((c) => c[1].op === "proxyClientToOwner.no-hello-key")).toHaveLength(5);
  });

  test("after proxy_ready, forwards frames BOTH ways; forwards owner close code to the client", async () => {
    const client = new FakeWs();
    const owner = new FakeWs();
    await proxyClientToOwner({
      clientWs: client as never,
      ownerAddress: "10.0.1.12",
      userId: U,
      workspaceId: W,
      dial: (() => owner) as never,
    });
    owner.emit("open");
    owner.sent.length = 0; // drop the proxy_hello

    // Owner acks → relay becomes ready.
    owner.emit("message", JSON.stringify({ type: "proxy_ready" }));

    // client → owner
    client.emit("message", "client-frame", false);
    expect(owner.sent).toContain("client-frame");
    // owner → client
    owner.emit("message", "owner-frame", false);
    expect(client.sent).toContain("owner-frame");

    // A drain close from the owner must reach the client with the SAME code.
    owner.emit("close", WS_CLOSE_CODES.ROUTING_MIGRATED, Buffer.from("draining"));
    expect(client.closed?.code).toBe(WS_CLOSE_CODES.ROUTING_MIGRATED);
  });

  test("owner sends a non-ready control frame first → tears down both sockets", async () => {
    const client = new FakeWs();
    const owner = new FakeWs();
    await proxyClientToOwner({
      clientWs: client as never,
      ownerAddress: "10.0.1.12",
      userId: U,
      workspaceId: W,
      dial: (() => owner) as never,
    });
    owner.emit("open");
    owner.emit("message", JSON.stringify({ type: "nope" }));
    expect(client.closed?.code).toBe(WS_CLOSE_CODES.ROUTING_UNAVAILABLE);
    expect(owner.closed?.code).toBe(WS_CLOSE_CODES.ROUTING_UNAVAILABLE);
  });

  test("pre-ready client frames are NOT forwarded (owner not yet serving)", async () => {
    const client = new FakeWs();
    const owner = new FakeWs();
    await proxyClientToOwner({
      clientWs: client as never,
      ownerAddress: "10.0.1.12",
      userId: U,
      workspaceId: W,
      dial: (() => owner) as never,
    });
    owner.emit("open");
    owner.sent.length = 0;
    // A client frame arriving before proxy_ready must be dropped, not leaked.
    client.emit("message", "premature", false);
    expect(owner.sent).not.toContain("premature");
  });
});
