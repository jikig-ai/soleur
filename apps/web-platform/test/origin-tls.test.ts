/**
 * Unit tests for server/origin-tls.ts (#10479): the Cloudflare-to-origin TLS listener.
 *
 * Certificates and keys are SYNTHESIZED per run with the openssl CLI into a temp dir
 * (cq-test-fixtures-synthesized-only): nothing committed, nothing that looks like a real key.
 * A missing openssl fails the suite loudly; it is not skipped.
 */

import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { createServer, request as httpsRequest } from "node:https";
import { createServer as createHttpServer, type Server } from "node:http";
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

import {
  loadOriginTlsMaterial,
  startOriginTlsListener,
  ORIGIN_TLS_CERT_ENV,
  ORIGIN_TLS_KEY_ENV,
  ORIGIN_TRANSPORT_HEADER,
  type OriginTlsEnv,
  type OriginTlsListener,
} from "@/server/origin-tls";

let dir: string;
const b64 = (s: string) => Buffer.from(s).toString("base64");

function mint(name: string, subj: string, san: string, isCa = false) {
  const key = join(dir, `${name}.key`);
  const crt = join(dir, `${name}.crt`);
  execFileSync(
    "openssl",
    [
      "req", "-x509", "-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:prime256v1", "-nodes",
      "-keyout", key, "-out", crt, "-days", "30", "-subj", `/CN=${subj}`,
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
let caCert: { key: string; cert: string };

beforeAll(() => {
  dir = mkdtempSync(join(tmpdir(), "origin-tls-test-"));
  good = mint("good", "app.soleur.ai", "DNS:app.soleur.ai");
  other = mint("other", "app.soleur.ai", "DNS:app.soleur.ai");
  wrongHost = mint("wrong", "example.invalid", "DNS:example.invalid");
  caCert = mint("ca", "app.soleur.ai", "DNS:app.soleur.ai", true);
});
afterAll(() => rmSync(dir, { recursive: true, force: true }));
afterEach(() => {
  vi.useRealTimers();
  reportSilentFallback.mockClear();
  warnSilentFallback.mockClear();
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

  test("a certificate that does not cover app.soleur.ai is rejected", () => {
    expect(loadOriginTlsMaterial(envOf(wrongHost))).toEqual({ status: "invalid", reason: "hostname-mismatch" });
  });

  test("a CA certificate is rejected (the origin presents a leaf)", () => {
    expect(loadOriginTlsMaterial(envOf(caCert))).toEqual({ status: "invalid", reason: "ca-certificate" });
  });

  test("expired and not-yet-valid are distinguished by the clock", () => {
    const day = 86_400_000;
    expect(loadOriginTlsMaterial(envOf(good), Date.now() + 60 * day)).toEqual({
      status: "invalid",
      reason: "expired",
    });
    expect(loadOriginTlsMaterial(envOf(good), Date.now() - 2 * day)).toEqual({
      status: "invalid",
      reason: "not-yet-valid",
    });
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

  test("invalid material: nothing starts, the reason (and no key bytes) reaches Sentry", async () => {
    expect(await boot(envOf(wrongHost))).toBeNull();
    expect(tls).toBeNull();
    expect(reportSilentFallback).toHaveBeenCalledTimes(1);
    const [err, opts] = reportSilentFallback.mock.calls[0] as [Error, { feature: string; tags: Record<string, string> }];
    expect(opts.feature).toBe("origin_tls");
    expect(opts.tags.reason).toBe("hostname-mismatch");
    expect(JSON.stringify([err.message, opts])).not.toContain("PRIVATE KEY");
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
  });

  test("the plain-HTTP server never sets the transport header (so the header proves the TLS hop)", async () => {
    const plain = createHttpServer((req, res) => res.end("x"));
    await new Promise<void>((r) => plain.listen(0, r));
    const port = (plain.address() as { port: number }).port;
    const res = await fetch(`http://127.0.0.1:${port}/health`);
    expect(res.headers.get(ORIGIN_TRANSPORT_HEADER)).toBeNull();
    plain.close();
  });

  test("a WebSocket upgrade over TLS reaches the upgrade listener registered on the HTTP server", async () => {
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

  test("a port that is already taken is reported and does not throw", async () => {
    const blocker = createServer();
    await new Promise<void>((r) => blocker.listen(0, r));
    const taken = (blocker.address() as { port: number }).port;
    http = createHttpServer();
    tls = startOriginTlsListener({ httpServer: http, env: envOf(good), port: taken });
    await new Promise((r) => setTimeout(r, 100));
    expect(reportSilentFallback).toHaveBeenCalledWith(
      expect.objectContaining({ code: "EADDRINUSE" }),
      expect.objectContaining({ feature: "origin_tls", op: "listen" }),
    );
    blocker.close();
  });
});
