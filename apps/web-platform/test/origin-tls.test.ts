/**
 * Unit tests for server/origin-tls.ts (#10479): the Cloudflare-to-origin TLS listener.
 *
 * Certificates and keys are SYNTHESIZED per run with the openssl CLI into a temp dir
 * (cq-test-fixtures-synthesized-only): nothing committed, nothing that looks like a real key.
 * A missing openssl fails the suite loudly; it is not skipped.
 */

import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { Agent as HttpsAgent, createServer, request as httpsRequest } from "node:https";
import { createServer as createHttpServer, type Server } from "node:http";
import { connect } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll, afterEach, beforeAll, describe, expect, test, vi } from "vitest";

const reportSilentFallback = vi.fn();
const warnSilentFallback = vi.fn();
vi.mock("@/server/observability", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/observability")>()),
  reportSilentFallback: (...a: unknown[]) => reportSilentFallback(...a),
  warnSilentFallback: (...a: unknown[]) => warnSilentFallback(...a),
}));

// Every log call the module makes, so a test can prove no key material is ever logged.
const logged: unknown[][] = [];
vi.mock("@/server/logger", async (importOriginal) => {
  const m = await importOriginal<typeof import("@/server/logger")>();
  return {
    ...m,
    createChildLogger: (name: string) => {
      const real = m.createChildLogger(name) as unknown as Record<string, unknown>;
      return new Proxy(real, {
        get(target, prop) {
          if (prop === "info" || prop === "warn" || prop === "error") {
            return (...a: unknown[]) => {
              logged.push(a);
              return (target[prop] as (...x: unknown[]) => unknown)(...a);
            };
          }
          return target[prop as string];
        },
      });
    },
  };
});

// Lets one test make the TLS secure-context construction throw (the "never throws" claim).
let throwOnCreate = false;
vi.mock("node:https", async (importOriginal) => {
  const m = await importOriginal<typeof import("node:https")>();
  return {
    ...m,
    createServer: (...a: Parameters<typeof m.createServer>) => {
      if (throwOnCreate) throw new Error("synthetic secure-context failure");
      return m.createServer(...a);
    },
  };
});

import {
  loadOriginTlsMaterial,
  startOriginTlsListener,
  ORIGIN_TLS_CERT_ENV,
  ORIGIN_TLS_DEFAULT_PORT,
  ORIGIN_TLS_HANDSHAKE_TIMEOUT_MS,
  ORIGIN_TLS_KEEPALIVE_TIMEOUT_MS,
  ORIGIN_TLS_KEY_ENV,
  ORIGIN_TLS_REQUIRED_ENV,
  ORIGIN_TRANSPORT_HEADER,
  type OriginTlsEnv,
  type OriginTlsListener,
} from "@/server/origin-tls";

let dir: string;
const b64 = (s: string) => Buffer.from(s).toString("base64");

function mint(name: string, subj: string, san: string, isCa = false, days = 30) {
  const key = join(dir, `${name}.key`);
  const crt = join(dir, `${name}.crt`);
  execFileSync(
    "openssl",
    [
      "req", "-x509", "-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:prime256v1", "-nodes",
      "-keyout", key, "-out", crt, "-days", String(days), "-subj", `/CN=${subj}`,
      "-addext", `subjectAltName=${san}`,
      // openssl's default for `req -x509` is CA:TRUE; leaves must say CA:FALSE explicitly.
      "-addext", `basicConstraints=critical,CA:${isCa ? "TRUE" : "FALSE"}`,
    ],
    { stdio: "pipe" },
  );
  return { key: readFileSync(key, "utf8"), cert: readFileSync(crt, "utf8") };
}

let good: { key: string; cert: string };
let other: { key: string; cert: string };
let wrongHost: { key: string; cert: string };
let evilSuffix: { key: string; cert: string };
let wildcard: { key: string; cert: string };
let caCert: { key: string; cert: string };
let longLived: { key: string; cert: string };

beforeAll(() => {
  dir = mkdtempSync(join(tmpdir(), "origin-tls-test-"));
  good = mint("good", "app.soleur.ai", "DNS:app.soleur.ai");
  other = mint("other", "app.soleur.ai", "DNS:app.soleur.ai");
  wrongHost = mint("wrong", "example.invalid", "DNS:example.invalid");
  evilSuffix = mint("evil", "app.soleur.ai.evil", "DNS:app.soleur.ai.evil");
  // The shape a Cloudflare Origin CA certificate is normally issued with.
  wildcard = mint("wild", "soleur.ai", "DNS:*.soleur.ai, DNS:soleur.ai");
  caCert = mint("ca", "app.soleur.ai", "DNS:app.soleur.ai", true);
  longLived = mint("long", "app.soleur.ai", "DNS:app.soleur.ai", false, 400);
});
afterAll(() => rmSync(dir, { recursive: true, force: true }));
afterEach(() => {
  vi.useRealTimers();
  throwOnCreate = false;
  reportSilentFallback.mockClear();
  warnSilentFallback.mockClear();
  logged.length = 0;
});

const envOf = (m: { key: string; cert: string }) => ({
  [ORIGIN_TLS_KEY_ENV]: b64(m.key),
  [ORIGIN_TLS_CERT_ENV]: b64(m.cert),
});

describe("loadOriginTlsMaterial", () => {
  test("absent when neither variable is set", () => {
    expect(loadOriginTlsMaterial({})).toEqual({ status: "absent" });
  });

  test("absent when both are blank (an unset Doppler secret renders empty)", () => {
    expect(loadOriginTlsMaterial({ [ORIGIN_TLS_KEY_ENV]: " ", [ORIGIN_TLS_CERT_ENV]: "" })).toEqual({
      status: "absent",
    });
  });

  test("half-configured is invalid, in both directions", () => {
    const e = envOf(good);
    expect(loadOriginTlsMaterial({ [ORIGIN_TLS_KEY_ENV]: e[ORIGIN_TLS_KEY_ENV] })).toEqual({
      status: "invalid",
      reason: "half-configured",
    });
    expect(loadOriginTlsMaterial({ [ORIGIN_TLS_CERT_ENV]: e[ORIGIN_TLS_CERT_ENV] })).toEqual({
      status: "invalid",
      reason: "half-configured",
    });
  });

  test("raw PEM (not base64) is rejected", () => {
    expect(
      loadOriginTlsMaterial({ [ORIGIN_TLS_KEY_ENV]: good.key, [ORIGIN_TLS_CERT_ENV]: good.cert }),
    ).toEqual({ status: "invalid", reason: "not-base64-pem" });
  });

  test("a PEM-shaped but unparseable key or certificate is rejected", () => {
    const junk = b64("-----BEGIN PRIVATE KEY-----\nAAAA\n-----END PRIVATE KEY-----");
    const junkCert = b64("-----BEGIN CERTIFICATE-----\nAAAA\n-----END CERTIFICATE-----");
    expect(
      loadOriginTlsMaterial({ [ORIGIN_TLS_KEY_ENV]: junk, [ORIGIN_TLS_CERT_ENV]: b64(good.cert) }),
    ).toEqual({ status: "invalid", reason: "key-unparseable" });
    expect(
      loadOriginTlsMaterial({ [ORIGIN_TLS_KEY_ENV]: b64(good.key), [ORIGIN_TLS_CERT_ENV]: junkCert }),
    ).toEqual({ status: "invalid", reason: "cert-unparseable" });
  });

  test("a key that does not belong to the certificate is rejected", () => {
    expect(
      loadOriginTlsMaterial({ [ORIGIN_TLS_KEY_ENV]: b64(other.key), [ORIGIN_TLS_CERT_ENV]: b64(good.cert) }),
    ).toEqual({ status: "invalid", reason: "key-cert-mismatch" });
  });

  test("a certificate that does not cover app.soleur.ai is rejected, including a suffix look-alike", () => {
    expect(loadOriginTlsMaterial(envOf(wrongHost))).toEqual({ status: "invalid", reason: "hostname-mismatch" });
    expect(loadOriginTlsMaterial(envOf(evilSuffix))).toEqual({ status: "invalid", reason: "hostname-mismatch" });
  });

  test("a wildcard + apex certificate (the Origin CA default shape) covers app.soleur.ai", () => {
    expect(loadOriginTlsMaterial(envOf(wildcard)).status).toBe("ready");
  });

  test("a CA certificate is rejected (the origin presents a leaf)", () => {
    expect(loadOriginTlsMaterial(envOf(caCert))).toEqual({ status: "invalid", reason: "ca-certificate" });
  });

  test("the validity window is exact at both edges", () => {
    const ready = loadOriginTlsMaterial(envOf(good));
    if (ready.status !== "ready") throw new Error("fixture must be valid");
    const notBefore = Date.parse(ready.info.notBefore);
    const notAfter = Date.parse(ready.info.notAfter);
    const reason = (now: number) => {
      const r = loadOriginTlsMaterial(envOf(good), now);
      return r.status === "invalid" ? r.reason : r.status;
    };
    expect(reason(notAfter)).toBe("expired");
    expect(reason(notAfter - 1000)).toBe("ready");
    expect(reason(notBefore - 1000)).toBe("not-yet-valid");
    expect(reason(notBefore)).toBe("ready");
  });

  test("every block of a chain must parse, not just the leaf", () => {
    const leafPlusIntermediate = good.cert + other.cert;
    expect(
      loadOriginTlsMaterial({
        [ORIGIN_TLS_KEY_ENV]: b64(good.key),
        [ORIGIN_TLS_CERT_ENV]: b64(leafPlusIntermediate),
      }).status,
    ).toBe("ready");
    const truncated = `${good.cert}\n-----BEGIN CERTIFICATE-----\nAAAA\n-----END CERTIFICATE-----\n`;
    expect(
      loadOriginTlsMaterial({ [ORIGIN_TLS_KEY_ENV]: b64(good.key), [ORIGIN_TLS_CERT_ENV]: b64(truncated) }),
    ).toEqual({ status: "invalid", reason: "cert-unparseable" });
  });

  test("valid material is ready and reports the certificate facts, never the key", () => {
    const r = loadOriginTlsMaterial(envOf(good));
    expect(r.status).toBe("ready");
    if (r.status !== "ready") return;
    expect(r.info.subjectAltName).toContain("app.soleur.ai");
    expect(r.info.daysLeft).toBeGreaterThanOrEqual(28);
    expect(r.info.daysLeft).toBeLessThanOrEqual(30);
    expect(r.info.fingerprint256).toMatch(/^[0-9A-F:]{95}$/);
    expect(JSON.stringify(r.info)).not.toContain("PRIVATE KEY");
  });
});

describe("startOriginTlsListener", () => {
  let http: Server | undefined;
  let tls: OriginTlsListener | null = null;

  afterEach(async () => {
    tls?.closeAllConnections();
    tls?.close();
    tls = null;
    http?.close();
    http = undefined;
  });

  const boot = (env: OriginTlsEnv, handler?: Parameters<typeof createHttpServer>[1]) =>
    new Promise<number | null>((resolve) => {
      http = createHttpServer((req, res) => {
        res.writeHead(200, { "content-type": "text/plain" });
        res.end(`plain-handler ${req.url}`);
      });
      if (handler) http.on("upgrade", handler as never);
      tls = startOriginTlsListener({ httpServer: http, env, port: 0, onListening: resolve });
      if (!tls) resolve(null);
    });

  /** Bind the plain-HTTP server that `boot` created, as index.ts does, and return its port. */
  const listenPlain = async (): Promise<number> => {
    await new Promise<void>((r) => http!.listen(0, "127.0.0.1", r));
    return (http!.address() as { port: number }).port;
  };

  const get = (port: number, path: string, headers: Record<string, string> = {}) =>
    new Promise<{ status: number; body: string; headers: Record<string, unknown> }>((resolve, reject) => {
      const req = httpsRequest(
        { host: "127.0.0.1", port, path, servername: "app.soleur.ai", ca: good.cert, headers },
        (res) => {
          let body = "";
          res.on("data", (c) => (body += c));
          res.on("end", () => resolve({ status: res.statusCode ?? 0, body, headers: res.headers }));
        },
      );
      req.on("error", reject);
      req.end();
    });

  test("no material: nothing starts and nothing is reported", async () => {
    expect(await boot({})).toBeNull();
    expect(tls).toBeNull();
    expect(reportSilentFallback).not.toHaveBeenCalled();
  });

  test("invalid material: nothing starts, the reason reaches Sentry as tags, and the HTTP server still serves", async () => {
    expect(await boot(envOf(wrongHost))).toBeNull();
    expect(tls).toBeNull();
    expect(reportSilentFallback).toHaveBeenCalledTimes(1);
    const [err, opts] = reportSilentFallback.mock.calls[0] as [
      unknown,
      { feature: string; op: string; message: string; tags: Record<string, string> },
    ];
    // null error: an Error would be mirrored by the pino logger first and lose these tags.
    expect(err).toBeNull();
    expect(opts.feature).toBe("origin_tls");
    expect(opts.op).toBe("load");
    expect(opts.tags.reason).toBe("hostname-mismatch");
    expect(opts.message).toContain("hostname-mismatch");
    expect(JSON.stringify([err, opts])).not.toContain("PRIVATE KEY");

    const res = await fetch(`http://127.0.0.1:${await listenPlain()}/health`);
    expect(res.status).toBe(200);
  });

  test("a TLS secure-context failure never escapes: reported, listener disabled, HTTP unaffected", async () => {
    throwOnCreate = true;
    expect(await boot(envOf(good))).toBeNull();
    expect(tls).toBeNull();
    expect(reportSilentFallback).toHaveBeenCalledWith(
      null,
      expect.objectContaining({
        feature: "origin_tls",
        op: "create",
        tags: { reason: "tls-context-rejected" },
      }),
    );
    expect((await fetch(`http://127.0.0.1:${await listenPlain()}/health`)).status).toBe(200);
  });

  test("valid material: serves the plain handler over TLS, and /health carries the transport header", async () => {
    const port = await boot(envOf(good));
    expect(port).toBeGreaterThan(0);

    const home = await get(port!, "/anything?x=1");
    expect(home.status).toBe(200);
    expect(home.body).toBe("plain-handler /anything?x=1");
    expect(home.headers[ORIGIN_TRANSPORT_HEADER]).toBeUndefined();

    for (const path of ["/health", "/health?probe=1"]) {
      const h = await get(port!, path);
      expect(h.status).toBe(200);
      expect(h.headers[ORIGIN_TRANSPORT_HEADER]).toMatch(/^TLSv1\.[23]$/);
    }
    // The stamp is scoped to /health exactly: a longer path that merely starts with it is not one.
    expect((await get(port!, "/healthz")).headers[ORIGIN_TRANSPORT_HEADER]).toBeUndefined();
  });

  test("the REAL plain-HTTP server never sets the transport header (so the header proves the TLS hop)", async () => {
    const port = await boot(envOf(good));
    expect(port).toBeGreaterThan(0);
    // The same http server the TLS listener is wired to, reached over plain HTTP.
    const res = await fetch(`http://127.0.0.1:${await listenPlain()}/health`);
    expect(res.status).toBe(200);
    expect(res.headers.get(ORIGIN_TRANSPORT_HEADER)).toBeNull();
  });

  test("valid material never puts key bytes in a log line or a Sentry call", async () => {
    await boot(envOf(good));
    const bodyOfKey = good.key.split("\n").filter((l) => l && !l.startsWith("-----"))[0];
    const everything = JSON.stringify([logged, reportSilentFallback.mock.calls]);
    expect(everything).not.toContain("PRIVATE KEY");
    expect(everything).not.toContain(bodyOfKey);
    expect(everything).not.toContain(b64(good.key));
  });

  test("an upgrade event on the TLS listener is re-emitted to the HTTP server's upgrade listener", async () => {
    // This pins the FORWARDING only. The real ws handshake over a TLS socket is the same `ws`
    // code path as over a plain socket (server/ws-handler.ts) and is not re-driven here.
    const seen = vi.fn();
    const port = await boot(envOf(good), (req: unknown, socket: { end(s: string): void }) => {
      seen((req as { url: string }).url);
      socket.end("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n\r\n");
    });
    const status = await new Promise<number>((resolve, reject) => {
      const req = httpsRequest({
        host: "127.0.0.1",
        port: port!,
        path: "/ws",
        servername: "app.soleur.ai",
        ca: good.cert,
        headers: { Connection: "Upgrade", Upgrade: "websocket" },
      });
      req.on("upgrade", (res) => resolve(res.statusCode ?? 0));
      req.on("error", reject);
      req.end();
    });
    expect(status).toBe(101);
    expect(seen).toHaveBeenCalledWith("/ws");
  });

  test("a client that does not trust the certificate cannot connect (no plaintext downgrade)", async () => {
    const port = await boot(envOf(good));
    await expect(
      new Promise((resolve, reject) => {
        const req = httpsRequest({ host: "127.0.0.1", port: port!, path: "/health", servername: "app.soleur.ai" }, resolve);
        req.on("error", reject);
        req.end();
      }),
    ).rejects.toThrow();
  });

  test("a failed handshake is logged with its code, once (rate-limited)", async () => {
    const port = await boot(envOf(good));
    for (let i = 0; i < 2; i++) {
      const s = connect(port!, "127.0.0.1");
      s.on("error", () => undefined);
      s.write("GET / HTTP/1.1\r\n\r\n");
    }
    // Count only this test's failure shape: a late handshake error from an earlier test's listener
    // (the untrusted-certificate client) has a different code and must not be counted.
    const mine = () =>
      logged.filter(
        (a) =>
          String(a[1]).includes("failed the TLS handshake") &&
          (a[0] as { code: unknown }).code === "ERR_SSL_HTTP_REQUEST",
      );
    await vi.waitFor(() => expect(mine().length).toBeGreaterThanOrEqual(1));
    // Both bad clients arrived inside one rate-limit window: still exactly one line.
    expect(mine()).toHaveLength(1);
  });

  test("close() stops accepting and closeAllConnections() drops a held connection", async () => {
    const port = await boot(envOf(good));
    // A completed TLS handshake + keep-alive request: only then is the socket one the HTTP server tracks.
    const agent = new HttpsAgent({ keepAlive: true });
    let closed = false;
    await new Promise<void>((resolve, reject) => {
      const req = httpsRequest(
        { host: "127.0.0.1", port: port!, path: "/anything", servername: "app.soleur.ai", ca: good.cert, agent },
        (res) => {
          res.socket.once("close", () => (closed = true));
          res.resume();
          res.on("end", () => resolve());
        },
      );
      req.on("error", reject);
      req.end();
    });
    expect(closed).toBe(false);
    tls!.closeAllConnections();
    await vi.waitFor(() => expect(closed).toBe(true));
    agent.destroy();

    tls!.close();
    await expect(get(port!, "/health")).rejects.toThrow();
  });

  test("a 30-day certificate triggers the expiry warning, a long-lived one does not", async () => {
    await boot(envOf(good));
    expect(warnSilentFallback).toHaveBeenCalledWith(
      expect.any(Error),
      expect.objectContaining({ feature: "origin_tls", op: "cert_expiry" }),
    );
    tls?.closeAllConnections();
    tls?.close();
    http?.close();
    warnSilentFallback.mockClear();

    await boot(envOf(longLived));
    expect(warnSilentFallback).not.toHaveBeenCalled();
  });

  test("the HTTPS server keeps idle connections longer than Cloudflare reuses them", async () => {
    await boot(envOf(good));
    expect(tls!.server.keepAliveTimeout).toBe(ORIGIN_TLS_KEEPALIVE_TIMEOUT_MS);
    expect(tls!.server.keepAliveTimeout).toBeGreaterThan(900_000);
  });

  // headersTimeout is deliberately NOT set on the :443 server (ADR-321, ruling R-A of 2026-11-08): the plain server's assignment is
  // bounded by Node's requestTimeout (300 s), so mirroring it would loosen the :443 slow-header cutoff from Node's 60 s default to
  // 300 s for no demonstrated need (an idle keep-alive socket stays open at 75 s with the default, measured on Node 22.23.4 and 26).
  test("the HTTPS server keeps Node's 60 s headersTimeout (the slow-header cutoff is not loosened)", async () => {
    await boot(envOf(good));
    expect(tls!.server.headersTimeout).toBeLessThanOrEqual(60_000);
  });
  test("origin-tls.ts never assigns headersTimeout (a loosening needs a demonstrated need and an explicit requestTimeout)", () => {
    const src = readFileSync(join(__dirname, "..", "server/origin-tls.ts"), "utf8").replace(/\/\*[\s\S]*?\*\//g, "").replace(/^\s*\/\/.*$/gm, "");
    expect(src).not.toMatch(/headersTimeout\s*=/);
    expect(src).not.toMatch(/requestTimeout\s*=/);
  });

  // The once-per-start line is the per-host proof; `required` makes "REQUIRED is live on this host" a direct read.
  const listeningLine = () => logged.find((a) => String(a[1]).startsWith("origin-tls: listening"));
  test("the startup line states the REQUIRED mode as a boolean: true under REQUIRED=1", async () => {
    http = createHttpServer();
    await new Promise<number>((resolve) => {
      tls = startOriginTlsListener({ httpServer: http!, env: { [ORIGIN_TLS_REQUIRED_ENV]: "1", ...envOf(good) }, port: 0, onListening: resolve, exit: vi.fn() });
    });
    expect((listeningLine()![0] as { required: unknown }).required).toBe(true);
  });
  test("the startup line states the REQUIRED mode as a boolean: false without it", async () => {
    await boot(envOf(good));
    expect((listeningLine()![0] as { required: unknown }).required).toBe(false);
  });
  test("required is written AFTER the certificate facts in the startup line (the later key wins in an object spread)", () => {
    const src = readFileSync(join(__dirname, "..", "server/origin-tls.ts"), "utf8").replace(/\/\*[\s\S]*?\*\//g, "").replace(/^\s*\/\/.*$/gm, "");
    expect(src).toMatch(/\{\s*port:\s*boundPort,\s*\.\.\.loaded\.info,\s*required\s*\}/);
  });
  test("the startup line adds only that boolean: no key, certificate or PEM text reaches it", async () => {
    await boot(envOf(good));
    const fields = listeningLine()![0] as Record<string, unknown>;
    expect(typeof fields.required).toBe("boolean");
    const text = JSON.stringify(fields);
    expect(text).not.toContain("PRIVATE KEY");
    expect(text).not.toContain("BEGIN CERTIFICATE");
    expect(text).not.toContain(b64(good.key));
    expect(text).not.toContain(b64(good.cert));
  });

  test("a real process.env is scrubbed of the key and cert after boot; a plain env object is not", async () => {
    const plain = envOf(good) as Record<string, string | undefined>;
    await boot(plain);
    expect(plain[ORIGIN_TLS_KEY_ENV]).toBeDefined();

    tls?.closeAllConnections();
    tls?.close();
    http?.close();

    const saved = { k: process.env[ORIGIN_TLS_KEY_ENV], c: process.env[ORIGIN_TLS_CERT_ENV] };
    try {
      Object.assign(process.env, envOf(good));
      http = createHttpServer();
      tls = startOriginTlsListener({ httpServer: http, env: process.env, port: 0 });
      expect(tls).not.toBeNull();
      expect(process.env[ORIGIN_TLS_KEY_ENV]).toBeUndefined();
      expect(process.env[ORIGIN_TLS_CERT_ENV]).toBeUndefined();
    } finally {
      if (saved.k === undefined) delete process.env[ORIGIN_TLS_KEY_ENV];
      else process.env[ORIGIN_TLS_KEY_ENV] = saved.k;
      if (saved.c === undefined) delete process.env[ORIGIN_TLS_CERT_ENV];
      else process.env[ORIGIN_TLS_CERT_ENV] = saved.c;
    }
  });

  describe("ORIGIN_TLS_REQUIRED=1 (fail closed)", () => {
    const required = { [ORIGIN_TLS_REQUIRED_ENV]: "1" };

    const startWith = (env: OriginTlsEnv) => {
      const exit = vi.fn();
      http = createHttpServer();
      tls = startOriginTlsListener({ httpServer: http, env, port: 0, exit });
      return exit;
    };

    test("absent material is reported and fatal", () => {
      const exit = startWith({ ...required });
      expect(tls).toBeNull();
      expect(exit).toHaveBeenCalledWith(1);
      expect(reportSilentFallback).toHaveBeenCalledWith(
        null,
        expect.objectContaining({ op: "load", tags: { reason: "absent-but-required" } }),
      );
    });

    test("invalid material is reported and fatal", () => {
      const exit = startWith({ ...required, ...envOf(wrongHost) });
      expect(exit).toHaveBeenCalledWith(1);
      expect(reportSilentFallback).toHaveBeenCalledWith(
        null,
        expect.objectContaining({ op: "load", tags: { reason: "hostname-mismatch" } }),
      );
    });

    test("a TLS context that cannot be built is fatal", () => {
      throwOnCreate = true;
      const exit = startWith({ ...required, ...envOf(good) });
      expect(exit).toHaveBeenCalledWith(1);
    });

    test("a listener error is fatal", async () => {
      const blocker = createServer();
      await new Promise<void>((r) => blocker.listen(0, r));
      const taken = (blocker.address() as { port: number }).port;
      try {
        const exit = vi.fn();
        http = createHttpServer();
        tls = startOriginTlsListener({ httpServer: http, env: { ...required, ...envOf(good) }, port: taken, exit });
        await vi.waitFor(() => expect(exit).toHaveBeenCalledWith(1));
      } finally {
        blocker.close();
      }
    });

    const takenPort = async () => {
      const blocker = createServer();
      await new Promise<void>((r) => blocker.listen(0, r));
      return { blocker, taken: (blocker.address() as { port: number }).port };
    };

    test("a startup bind failure under REQUIRED is reported with phase startup and is fatal", async () => {
      const { blocker, taken } = await takenPort();
      try {
        const exit = vi.fn();
        http = createHttpServer();
        tls = startOriginTlsListener({ httpServer: http, env: { ...required, ...envOf(good) }, port: taken, exit });
        await vi.waitFor(() => expect(exit).toHaveBeenCalledWith(1));
        expect(reportSilentFallback).toHaveBeenCalledWith(
          null,
          expect.objectContaining({ op: "listen", tags: { reason: "EADDRINUSE", phase: "startup" } }),
        );
      } finally {
        blocker.close();
      }
    });

    // The fixture direction the other way round, with an INJECTED exit (vitest traps process.exit, so an un-injected check
    // would pass for the wrong reason): without REQUIRED a startup bind failure is reported and the process keeps going.
    test("a startup bind failure WITHOUT REQUIRED is reported and never calls exit", async () => {
      const { blocker, taken } = await takenPort();
      try {
        const exit = vi.fn();
        http = createHttpServer();
        tls = startOriginTlsListener({ httpServer: http, env: envOf(good), port: taken, exit });
        await vi.waitFor(() =>
          expect(reportSilentFallback).toHaveBeenCalledWith(
            null,
            expect.objectContaining({ tags: { reason: "EADDRINUSE", phase: "startup" } }),
          ),
        );
        expect(exit).not.toHaveBeenCalled();
      } finally {
        blocker.close();
      }
    });

    // After the bind a server 'error' (an accept failure) leaves the listener open in Node, and exit(1) would kill the whole
    // process, including every WebSocket on the plain listener, over a transient condition: report (throttled) and continue.
    const bootListening = async (env: OriginTlsEnv) => {
      const exit = vi.fn();
      http = createHttpServer((_req, res) => res.end("plain-handler"));
      const port = await new Promise<number>((resolve) => {
        tls = startOriginTlsListener({ httpServer: http!, env, port: 0, onListening: resolve, exit });
      });
      return { exit, port };
    };
    // A fixture code only: whether libuv surfaces EMFILE through the server's 'error' event is unverified.
    const runtimeError = () => Object.assign(new Error("accept failed"), { code: "EMFILE" });
    const runtimeReports = () =>
      reportSilentFallback.mock.calls.filter((c) => (c[1] as { tags?: { phase?: string } }).tags?.phase === "runtime");

    test("a runtime error AFTER the bind under REQUIRED is reported with phase runtime and is NOT fatal", async () => {
      const { exit, port } = await bootListening({ ...required, ...envOf(good) });
      tls!.server.emit("error", runtimeError());
      expect(exit).not.toHaveBeenCalled();
      expect(reportSilentFallback).toHaveBeenCalledWith(
        null,
        expect.objectContaining({ feature: "origin_tls", op: "listen", tags: { reason: "EMFILE", phase: "runtime" } }),
      );
      expect((await get(port, "/anything")).status).toBe(200); // the listener still serves
    });

    test("a runtime error after the bind without REQUIRED is reported with phase runtime and never exits", async () => {
      const { exit } = await bootListening(envOf(good));
      tls!.server.emit("error", runtimeError());
      expect(exit).not.toHaveBeenCalled();
      expect(reportSilentFallback).toHaveBeenCalledWith(
        null,
        expect.objectContaining({ tags: { reason: "EMFILE", phase: "runtime" } }),
      );
    });

    test("a burst of runtime errors is reported once a minute, with the suppressed count on the next report", async () => {
      const { exit } = await bootListening({ ...required, ...envOf(good) });
      let now = 1_000_000;
      const spy = vi.spyOn(performance, "now").mockImplementation(() => now);
      try {
        for (let i = 0; i < 5; i++) tls!.server.emit("error", runtimeError());
        expect(runtimeReports()).toHaveLength(1);
        now += 59_000;
        tls!.server.emit("error", runtimeError());
        expect(runtimeReports()).toHaveLength(1); // still inside the window
        now += 2_000;
        tls!.server.emit("error", runtimeError());
        expect(runtimeReports()).toHaveLength(2);
        expect((runtimeReports()[1][1] as { extra: { suppressed: number } }).extra.suppressed).toBe(5);
        expect(exit).not.toHaveBeenCalled();
      } finally {
        spy.mockRestore();
      }
    });

    // The one in-process sign of a dead listener: the https server closing when nobody asked it to.
    test("an UNEXPECTED close of the listener under REQUIRED is reported and fatal (the container restarts)", async () => {
      const { exit } = await bootListening({ ...required, ...envOf(good) });
      tls!.server.close(); // not through the returned close(): nobody "asked" for this
      await vi.waitFor(() => expect(exit).toHaveBeenCalledWith(1));
      expect(reportSilentFallback).toHaveBeenCalledWith(
        null,
        expect.objectContaining({ tags: { reason: "unexpected-close", phase: "runtime" } }),
      );
    });

    test("an unexpected close without REQUIRED is reported and never exits", async () => {
      const { exit } = await bootListening(envOf(good));
      tls!.server.close();
      await vi.waitFor(() =>
        expect(reportSilentFallback).toHaveBeenCalledWith(
          null,
          expect.objectContaining({ tags: { reason: "unexpected-close", phase: "runtime" } }),
        ),
      );
      expect(exit).not.toHaveBeenCalled();
    });

    test("an INTENTIONAL close() (shutdown) is neither reported nor fatal, even under REQUIRED", async () => {
      const { exit } = await bootListening({ ...required, ...envOf(good) });
      tls!.close();
      await new Promise((r) => setTimeout(r, 100));
      expect(exit).not.toHaveBeenCalled();
      expect(runtimeReports()).toHaveLength(0);
    });

    test("valid material under REQUIRED starts normally and never exits", async () => {
      const exit = vi.fn();
      http = createHttpServer();
      const port = await new Promise<number>((resolve) => {
        tls = startOriginTlsListener({
          httpServer: http!,
          env: { ...required, ...envOf(good) },
          port: 0,
          onListening: resolve,
          exit,
        });
      });
      expect(port).toBeGreaterThan(0);
      expect(exit).not.toHaveBeenCalled();
    });

    test("without REQUIRED the same failures stay inert (never exit)", () => {
      const exit = startWith({});
      expect(exit).not.toHaveBeenCalled();
      expect(tls).toBeNull();
    });
  });

  test("a port that is already taken is reported and does not throw", async () => {
    const blocker = createServer();
    await new Promise<void>((r) => blocker.listen(0, r));
    const taken = (blocker.address() as { port: number }).port;
    try {
      http = createHttpServer();
      tls = startOriginTlsListener({ httpServer: http, env: envOf(good), port: taken });
      await vi.waitFor(() =>
        expect(reportSilentFallback).toHaveBeenCalledWith(
          null,
          expect.objectContaining({
            feature: "origin_tls",
            op: "listen",
            tags: { reason: "EADDRINUSE", phase: "startup" },
          }),
        ),
      );
    } finally {
      blocker.close();
    }
  });
});

describe("wiring and contract pins", () => {
  const read = (rel: string) => readFileSync(join(__dirname, "..", rel), "utf8");
  const stripComments = (s: string) => s.replace(/\/\*[\s\S]*?\*\//g, "").replace(/^\s*\/\/.*$/gm, "");

  test("server/index.ts starts the listener inside server.listen and wires both shutdown paths", () => {
    const src = stripComments(read("server/index.ts"));
    const listenAt = src.indexOf("server.listen(port, () => {");
    const startAt = src.indexOf("originTls = startOriginTlsListener({ httpServer: server })");
    expect(listenAt).toBeGreaterThan(-1);
    expect(startAt).toBeGreaterThan(listenAt);
    expect(src.match(/startOriginTlsListener\(/g)).toHaveLength(1);
    expect(src).toContain("originTls?.close()");
    expect(src).toContain("originTls?.closeAllConnections()");
  });

  test("the plain :80 server uses the same keep-alive constant, with headersTimeout above it (unchanged from main)", () => {
    const src = stripComments(read("server/index.ts"));
    expect(src).toMatch(/^\s*server\.keepAliveTimeout = ORIGIN_TLS_KEEPALIVE_TIMEOUT_MS;$/m);
    expect(src).toMatch(/^\s*server\.headersTimeout = ORIGIN_TLS_KEEPALIVE_TIMEOUT_MS \+ 5_000;$/m);
  });

  test("the default container port equals the port the run sites publish as host :443", () => {
    for (const rel of ["infra/ci-deploy.sh", "infra/cloud-init.yml"]) {
      const m = read(rel).match(/-p 0\.0\.0\.0:443:(\d+)/);
      expect(m, `${rel} must publish 443`).not.toBeNull();
      expect(Number(m![1])).toBe(ORIGIN_TLS_DEFAULT_PORT);
    }
  });

  test("only server/origin-tls.ts sets the transport header (so it cannot appear on the plain listener)", () => {
    const { readdirSync } = require("node:fs") as typeof import("node:fs");
    const offenders = readdirSync(join(__dirname, "..", "server"))
      .filter((f) => f.endsWith(".ts") && f !== "origin-tls.ts")
      .filter((f) => /x-origin-transport/i.test(stripComments(read(`server/${f}`))));
    expect(offenders).toEqual([]);
  });

  test("the handshake timeout is bounded well below Node's 120 s default", () => {
    expect(ORIGIN_TLS_HANDSHAKE_TIMEOUT_MS).toBeLessThanOrEqual(30_000);
  });
});
