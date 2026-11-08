// Ruled by CTO agent, 2026-11-08 (ADR-321 item 12): the plain :80 server sets an explicit 60 s header phase inside a 300 s
// whole-request window. The :443 listener keeps Node's defaults (origin-tls.test.ts pins that it assigns neither property).
import { describe, expect, test } from "vitest";
import { createServer, type Server } from "node:http";
import { connect } from "node:net";
import { readFileSync } from "node:fs";
import { join } from "node:path";

import {
  PLAIN_HTTP_HEADERS_TIMEOUT_MS,
  PLAIN_HTTP_REQUEST_TIMEOUT_MS,
  applyPlainHttpTimeouts,
} from "../server/http-timeouts";

const ROOT = join(__dirname, "..");
const read = (rel: string): string => readFileSync(join(ROOT, rel), "utf8");
const stripComments = (s: string): string =>
  s.replace(/\/\*[\s\S]*?\*\//g, "").replace(/(^|[^:])\/\/.*$/gm, "$1");

describe("plain :80 server timeouts (http-timeouts.ts)", () => {
  test("the defaults are 60 s for the header phase and 300 s for the whole request (hardcoded here on purpose)", () => {
    // Literals, not imported values: weakening the module's constants must also need an edit to this test.
    expect(PLAIN_HTTP_HEADERS_TIMEOUT_MS).toBe(60_000);
    expect(PLAIN_HTTP_REQUEST_TIMEOUT_MS).toBe(300_000);
  });

  test("applyPlainHttpTimeouts assigns both properties on the server it is given", () => {
    const server = createServer();
    try {
      applyPlainHttpTimeouts(server);
      expect(server.headersTimeout).toBe(60_000);
      expect(server.requestTimeout).toBe(300_000);
      applyPlainHttpTimeouts(server, { headersMs: 700, requestMs: 700 });
      // Equal values are permitted (the boundary of the rule below).
      expect(server.headersTimeout).toBe(700);
      expect(server.requestTimeout).toBe(700);
    } finally {
      server.close();
    }
  });

  test("it throws when the header bound exceeds the request bound, and assigns nothing", () => {
    const server = createServer();
    try {
      const before = { h: server.headersTimeout, r: server.requestTimeout };
      expect(() => applyPlainHttpTimeouts(server, { headersMs: 2_000, requestMs: 1_000 })).toThrow(/headers/i);
      expect({ h: server.headersTimeout, r: server.requestTimeout }).toEqual(before);
    } finally {
      server.close();
    }
  });

  // Behavioural: a client that never finishes its headers is cut at the HEADER bound, not at the (much longer) request bound.
  // connectionsCheckingInterval is lowered so Node's periodic sweep is fast enough for a sub-second assertion; real Node
  // enforces the timeout plus up to 30 s (its default sweep interval), which is why the numbers below are a window and not
  // an equality. The 0.5 s wait is intentional: it is the shortest header bound the sweep can resolve reliably.
  test("a client stalling mid-header is cut near the header bound, far before the request bound", async () => {
    const server: Server = createServer({ connectionsCheckingInterval: 100 });
    applyPlainHttpTimeouts(server, { headersMs: 500, requestMs: 2_500 });
    // The fixture must not be able to pass by timing out slowly: the sweep interval is the thing that makes 0.5 s observable.
    expect((server as unknown as { connectionsCheckingInterval?: number }).connectionsCheckingInterval).toBe(100);

    await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
    const address = server.address();
    if (address === null || typeof address === "string") throw new Error("no address");

    const started = Date.now();
    const client = connect(address.port, "127.0.0.1");
    let received = "";
    const closedAt = await new Promise<number>((resolve, reject) => {
      const guard = setTimeout(() => reject(new Error("client was not cut within 4 s")), 4_000);
      client.on("data", (d) => {
        received += d.toString();
      });
      client.on("close", () => {
        clearTimeout(guard);
        resolve(Date.now() - started);
      });
      client.on("error", () => {
        /* a reset after the 408 is acceptable; the close handler resolves */
      });
      // An incomplete request line + headers: the header phase never completes.
      client.write("GET / HTTP/1.1\r\nHost: x\r\nX-Slow: ");
    }).finally(() => {
      client.destroy();
      server.close();
    });

    expect(closedAt).toBeGreaterThanOrEqual(400);
    expect(closedAt).toBeLessThan(1_500);
    // Node answers 408 itself when it can; an abrupt close (no bytes) is also an accepted outcome.
    if (received.length > 0) expect(received).toMatch(/^HTTP\/1\.1 408 /);
  });

  test("index.ts wires the helper and no longer assigns headersTimeout itself", () => {
    const src = stripComments(read("server/index.ts"));
    expect(src).toContain("applyPlainHttpTimeouts(server);");
    expect(src).not.toMatch(/server\.headersTimeout\s*=/);
    // The keep-alive assignment is left exactly as it was.
    expect(src).toMatch(/^\s*server\.keepAliveTimeout = ORIGIN_TLS_KEEPALIVE_TIMEOUT_MS;$/m);
  });

  test("http-timeouts.ts imports nothing from the server (it must stay import-safe for tests)", () => {
    const src = stripComments(read("server/http-timeouts.ts"));
    expect(src).not.toMatch(/^\s*import\s[^;]*from\s+["'](?:\.{1,2}\/|@\/)/m);
  });
});
