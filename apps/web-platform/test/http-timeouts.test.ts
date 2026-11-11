// Ruled by CTO agent, 2026-11-08 (ADR-321 item 12): the plain :80 server sets an explicit 60 s header phase inside a 300 s
// whole-request window. The :443 listener keeps Node's defaults (origin-tls.test.ts pins that it assigns neither property).
import { beforeEach, describe, expect, test } from "vitest";
import { createServer, type Server } from "node:http";
import { connect } from "node:net";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

import { stripComments as stripCommentsAst } from "./helpers/strip-comments";

import {
  PLAIN_HTTP_HEADERS_TIMEOUT_MS,
  PLAIN_HTTP_REQUEST_TIMEOUT_MS,
  applyPlainHttpTimeouts,
} from "../server/http-timeouts";

const ROOT = join(__dirname, "..");
const read = (rel: string): string => readFileSync(join(ROOT, rel), "utf8");
const stripComments = (s: string): string => stripCommentsAst(s);

beforeEach(() => {
  expect.hasAssertions();
});

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
    applyPlainHttpTimeouts(server, { headersMs: 500, requestMs: 30_000 });
    // The fixture must not be able to pass by timing out slowly: the sweep interval is the thing that makes 0.5 s observable.
    expect((server as unknown as { connectionsCheckingInterval?: number }).connectionsCheckingInterval).toBe(100);

    await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
    const address = server.address();
    if (address === null || typeof address === "string") throw new Error("no address");

    const started = Date.now();
    const client = connect(address.port, "127.0.0.1");
    let received = "";
    const closedAt = await new Promise<number>((resolve, reject) => {
      const guard = setTimeout(() => reject(new Error("client was not cut within 8 s")), 8_000);
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
    expect(closedAt).toBeLessThan(5_000);
    // Node answers 408 itself when it can; an abrupt close (no bytes) is also an accepted outcome.
    if (received.length > 0) expect(received).toMatch(/^HTTP\/1\.1 408 /);
  });

  test("index.ts wires the helper and no longer assigns headersTimeout itself", () => {
    const src = stripComments(read("server/index.ts"));
    expect(src).toContain("applyPlainHttpTimeouts(server);");
    // Any spelling of a direct timeout write on the server (dot, bracket, Object.assign) other than the helper call is a bypass.
    expect(src).not.toMatch(/server\s*(?:\.|\[\s*["'])\s*(?:headers|request)Timeout/);
    expect(src).not.toMatch(/Object\.assign\(\s*server\b/);
    // Whole-file rule: the property names appear nowhere in index.ts (an alias, a template-literal key, Reflect.set or
    // Object.defineProperty cannot write them without spelling the name).
    expect(src).not.toMatch(/headersTimeout|requestTimeout/);
    // The call is a top-level statement of the same block that sets the keep-alive, not nested in a conditional.
    expect(src).toMatch(/^ {2}server\.keepAliveTimeout = ORIGIN_TLS_KEEPALIVE_TIMEOUT_MS;\n {2}applyPlainHttpTimeouts\(server\);$/m);
    // The keep-alive assignment is left exactly as it was.
    expect(src).toMatch(/^\s*server\.keepAliveTimeout = ORIGIN_TLS_KEEPALIVE_TIMEOUT_MS;$/m);
  });

  test("every HTTP(S) listener in server/ is known: a new server creator must be reviewed for its timeouts", () => {
    const walk = (dir: string): string[] =>
      readdirSync(join(ROOT, dir), { withFileTypes: true }).flatMap((e) =>
        e.isDirectory() ? walk(`${dir}/${e.name}`) : /\.[cm]?[jt]sx?$/.test(e.name) ? [`${dir}/${e.name}`] : [],
      );
    // Comments are removed by the TypeScript parser (test/helpers/strip-comments.ts), so a string such as "a//b" or "src/*.ts"
    // cannot hide code. Any mention counts, so an aliased import (`createServer as mk`) and a bracket access
    // (`http["createServer"]`) are seen as well as a call.
    const uncommented = (f: string): string => stripCommentsAst(read(f), f);
    const creatorMention = /\bcreate(?:Secure|Https?)?Server\b|\bnew\s+(?:\w+\.)?Server\s*\(/;
    const valueImportStmt = /^\s*import\s+(?!type\b)(?:\w+|\*\s+as\s+\w+)\s*(?:,[^;]*)?from\s+["'](?:node:)?(?:https?|http2)["']/m;
    const valueRequireCall = /require\(\s*["'](?:node:)?(?:https?|http2)["']\s*\)/;
    const valueHttpImport = { test: (src: string): boolean => valueImportStmt.test(src) || valueRequireCall.test(src) };
    // `import { Server as S } from "node:http"; new S()`: the constructor under any alias (a type-only use is not a listener).
    const aliasedConstructor = (src: string): boolean =>
      [...src.matchAll(/\bimport\s*\{([^}]*)\}\s*from\s*["'](?:node:)?(?:https?|http2)["']/g)].some((m) => {
        const spec = m[1].match(/(?:^|,)\s*(?:Server|Http2Server|Http2SecureServer)(?:\s+as\s+(\w+))?\s*(?:,|$)/);
        return spec !== null && new RegExp(`\\bnew\\s+${spec[1] ?? "(?:Server|Http2Server|Http2SecureServer)"}\\s*\\(`).test(src);
      });
    const creators = walk("server")
      .filter((f) => {
        const src = uncommented(f);
        return creatorMention.test(src) || valueHttpImport.test(src) || aliasedConstructor(src);
      })
      .sort();
    // index.ts: the :80 server (timeouts via http-timeouts.ts). origin-tls.ts: the :443 listener (Node defaults, pinned in
    // origin-tls.test.ts). session-proxy.ts: the private-net proxy, out of scope by design (ADR-321 item 12).
    // inngest-exec-receiver.ts (#9137): the private-TLS step-call receiver — Node defaults are CORRECT there:
    // requestTimeout (300 s) bounds only inbound request receipt (a small POST body), never the streamed
    // step response, which must stream unbounded (ADR-243); a total deadline is exactly the 524 class.
    expect(creators).toEqual([
      "server/index.ts",
      "server/inngest-exec-receiver.ts",
      "server/origin-tls.ts",
      "server/session-proxy.ts",
    ]);
    // A second creator inside a known file is not a new file name: count them where the :80 timeouts are applied.
    expect(stripComments(read("server/index.ts")).match(/\bcreateServer\s*\(/g)).toHaveLength(1);
  });

  test("http-timeouts.ts imports nothing from the server (it must stay import-safe for tests)", () => {
    const src = stripComments(read("server/http-timeouts.ts"));
    expect(src).not.toMatch(/^\s*import\s[^;]*from\s+["'](?:\.{1,2}\/|@\/)/m);
  });
});
