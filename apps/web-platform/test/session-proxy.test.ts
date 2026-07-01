/**
 * Unit tests — session-proxy.ts proxying-host relay (epic #5274 Phase 3 Sub-PR
 * 3.B, CTO ruling b2). Drives proxyClientToOwner with an injected `dial` +
 * fake sockets: the control handshake (proxy_hello → proxy_ready), bidirectional
 * frame forwarding after ready, close-code forwarding both ways, and the
 * fail-safe teardown when no pinned CA is configured. The live host↔host TLS
 * transport is soak-validated at 3.D (AC7/AC8); this locks the relay LOGIC.
 */

import { EventEmitter } from "node:events";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { WS_CLOSE_CODES } from "@/lib/types";
import { proxyClientToOwner } from "@/server/session-proxy";

const TEST_CERT = "-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----";

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
  vi.unstubAllEnvs();
  vi.stubEnv("PROXY_TLS_CERT", TEST_CERT);
});
afterEach(() => vi.unstubAllEnvs());

describe("proxyClientToOwner", () => {
  test("no pinned CA → closes the client non-transiently and never dials (never MITM)", async () => {
    vi.stubEnv("PROXY_TLS_CERT", "");
    const client = new FakeWs();
    const dial = vi.fn();
    await proxyClientToOwner({
      clientWs: client as never,
      ownerAddress: "10.0.1.12",
      userId: "u",
      workspaceId: "w",
      dial: dial as never,
    });
    expect(dial).not.toHaveBeenCalled();
    expect(client.closed?.code).toBe(WS_CLOSE_CODES.ROUTING_UNAVAILABLE);
  });

  test("dials with the pinned CA + rejectUnauthorized:true and sends proxy_hello on open", async () => {
    const client = new FakeWs();
    const owner = new FakeWs();
    const dial = vi.fn(() => owner);
    await proxyClientToOwner({
      clientWs: client as never,
      ownerAddress: "10.0.1.12",
      userId: "user-42",
      workspaceId: "ws-9",
      dial: dial as never,
    });
    expect(dial).toHaveBeenCalledTimes(1);
    const [url, opts] = dial.mock.calls[0];
    expect(url).toContain("wss://10.0.1.12");
    expect(opts).toMatchObject({ ca: TEST_CERT, rejectUnauthorized: true });

    owner.emit("open");
    expect(JSON.parse(owner.sent[0] as string)).toEqual({
      type: "proxy_hello",
      userId: "user-42",
      workspaceId: "ws-9",
    });
  });

  test("after proxy_ready, forwards frames BOTH ways; forwards owner close code to the client", async () => {
    const client = new FakeWs();
    const owner = new FakeWs();
    await proxyClientToOwner({
      clientWs: client as never,
      ownerAddress: "10.0.1.12",
      userId: "u",
      workspaceId: "w",
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
      userId: "u",
      workspaceId: "w",
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
      userId: "u",
      workspaceId: "w",
      dial: (() => owner) as never,
    });
    owner.emit("open");
    owner.sent.length = 0;
    // A client frame arriving before proxy_ready must be dropped, not leaked.
    client.emit("message", "premature", false);
    expect(owner.sent).not.toContain("premature");
  });
});
