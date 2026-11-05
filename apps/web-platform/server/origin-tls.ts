// origin-tls.ts — the Cloudflare-to-origin TLS listener (#10479, epic #10205).
//
// WHY. Cloudflare reaches the web hosts over plain HTTP because the zone carries an enabled
// `flexible` rule for app.soleur.ai (apps/web-platform/infra/seo-config-rules.tf). The Cloudflare
// `strict` mode needs the origin to answer TLS on :443 with a certificate Cloudflare verifies
// (a Cloudflare Origin CA certificate). This module is that listener: a SECOND server inside the
// same Node process, on container port 3443 (published as host :443 by ci-deploy.sh /
// cloud-init.yml), that hands every request and every WebSocket upgrade to the SAME handlers as
// the plain-HTTP server. It is a transport, not a second app: no route, auth or session logic
// lives here, so the two listeners cannot drift apart.
//
// INERT BY DEFAULT. With no ORIGIN_TLS_* material in the environment nothing starts (dev, CI, e2e
// and every host before the certificate is minted). With material that does not validate, nothing
// starts either, the reason is mirrored to Sentry, and the plain-HTTP listener keeps serving: a
// bad certificate must never take the :80 path down while the zone is still `flexible`.
//
// MATERIAL. ORIGIN_TLS_KEY_B64 and ORIGIN_TLS_CERT_B64 are base64 of the PEM files, delivered
// through Doppler `prd` into the container's env-file. Base64 because the docker env-file format
// is line-oriented (precedent: INNGEST_TLS_CA in infra/inngest-tls.tf). The key is minted
// OUTSIDE Terraform (ADR-320: a key in Tier-A-readable state is not allowed) by the mint script
// named in the plan; this module only reads it. The key and the PEM bodies are never logged and
// never put in an error message or a Sentry extra.
//
// PROOF OF TRANSPORT. Every /health response served through this listener carries
// `x-origin-transport: <negotiated TLS version>`. The plain-HTTP listener never sets it, so a
// probe through Cloudflare that sees the header has proven the Cloudflare-to-origin hop used TLS
// and that Cloudflare accepted the certificate (a rejected certificate under `strict` is a 526,
// not a 200). That is the "handshake probe" the done-condition of #10479 asks for.
//
// SCOPE. No client-certificate check (Authenticated Origin Pulls) here: ruled out for this
// change in the plan (knowledge-base/project/plans/2026-11-05-feat-origin-tls-listener-plan.md).

import { X509Certificate, createPrivateKey } from "node:crypto";
import { createServer as createHttpsServer, type Server as HttpsServer } from "node:https";
import type { Server as HttpServer, IncomingMessage } from "node:http";
import type { TLSSocket } from "node:tls";
import { createChildLogger } from "./logger";
import { reportSilentFallback, warnSilentFallback } from "./observability";

const log = createChildLogger("origin-tls");

/** The only hostname Cloudflare asks the origin for. The certificate must cover it. */
export const ORIGIN_TLS_HOSTNAME = "app.soleur.ai";
/** Container-side port. ci-deploy.sh and cloud-init.yml publish it as host :443. */
export const ORIGIN_TLS_DEFAULT_PORT = 3443;
export const ORIGIN_TLS_KEY_ENV = "ORIGIN_TLS_KEY_B64";
export const ORIGIN_TLS_CERT_ENV = "ORIGIN_TLS_CERT_B64";
export const ORIGIN_TLS_PORT_ENV = "ORIGIN_TLS_PORT";
export const ORIGIN_TRANSPORT_HEADER = "x-origin-transport";
/** Below this many days to notAfter the startup line is also a Sentry warning. */
export const ORIGIN_TLS_EXPIRY_WARN_DAYS = 90;

/** process.env, or a plain object in tests (NodeJS.ProcessEnv demands NODE_ENV). */
export type OriginTlsEnv = Readonly<Record<string, string | undefined>>;

export type OriginTlsInvalidReason =
  | "half-configured"
  | "not-base64-pem"
  | "key-unparseable"
  | "cert-unparseable"
  | "key-cert-mismatch"
  | "ca-certificate"
  | "not-yet-valid"
  | "expired"
  | "hostname-mismatch";

export interface OriginCertInfo {
  subject: string;
  issuer: string;
  subjectAltName: string;
  notBefore: string;
  notAfter: string;
  daysLeft: number;
  fingerprint256: string;
}

export type OriginTlsLoad =
  | { status: "absent" }
  | { status: "invalid"; reason: OriginTlsInvalidReason }
  | { status: "ready"; key: string; cert: string; info: OriginCertInfo };

function decodePem(raw: string): string | null {
  const text = Buffer.from(raw.trim(), "base64").toString("utf8").trim();
  return text.startsWith("-----BEGIN ") ? text : null;
}

const oneLine = (s: string): string => s.replace(/\s*\n\s*/g, ", ");

/**
 * Read and validate the origin TLS material. Pure apart from the clock: no I/O, no logging, so the
 * tests can drive every branch. A `ready` result means the key parses, the certificate parses, the
 * pair matches, the certificate is a leaf, inside its validity window and covers
 * {@link ORIGIN_TLS_HOSTNAME}.
 */
export function loadOriginTlsMaterial(
  env: OriginTlsEnv = process.env,
  now: number = Date.now(),
): OriginTlsLoad {
  const rawKey = env[ORIGIN_TLS_KEY_ENV]?.trim();
  const rawCert = env[ORIGIN_TLS_CERT_ENV]?.trim();
  if (!rawKey && !rawCert) return { status: "absent" };
  if (!rawKey || !rawCert) return { status: "invalid", reason: "half-configured" };

  const key = decodePem(rawKey);
  const cert = decodePem(rawCert);
  if (!key || !cert) return { status: "invalid", reason: "not-base64-pem" };

  let privateKey;
  try {
    privateKey = createPrivateKey(key);
  } catch {
    return { status: "invalid", reason: "key-unparseable" };
  }
  let x509: X509Certificate;
  try {
    x509 = new X509Certificate(cert);
  } catch {
    return { status: "invalid", reason: "cert-unparseable" };
  }

  if (!x509.checkPrivateKey(privateKey)) return { status: "invalid", reason: "key-cert-mismatch" };
  if (x509.ca) return { status: "invalid", reason: "ca-certificate" };
  const notBefore = new Date(x509.validFrom).getTime();
  const notAfter = new Date(x509.validTo).getTime();
  if (Number.isNaN(notBefore) || Number.isNaN(notAfter)) {
    return { status: "invalid", reason: "cert-unparseable" };
  }
  if (now < notBefore) return { status: "invalid", reason: "not-yet-valid" };
  if (now >= notAfter) return { status: "invalid", reason: "expired" };
  if (!x509.checkHost(ORIGIN_TLS_HOSTNAME)) return { status: "invalid", reason: "hostname-mismatch" };

  return {
    status: "ready",
    key,
    cert,
    info: {
      subject: oneLine(x509.subject),
      issuer: oneLine(x509.issuer),
      subjectAltName: x509.subjectAltName ?? "",
      notBefore: new Date(notBefore).toISOString(),
      notAfter: new Date(notAfter).toISOString(),
      daysLeft: Math.floor((notAfter - now) / 86_400_000),
      fingerprint256: x509.fingerprint256,
    },
  };
}

export interface OriginTlsListener {
  server: HttpsServer;
  /** Stops accepting connections and drops idle ones (called from the SIGTERM path). */
  close(): void;
  /** Drops every connection, including active ones (the forced-exit path). */
  closeAllConnections(): void;
}

const isHealthPath = (url: string | undefined): boolean =>
  url === "/health" || (url?.startsWith("/health?") ?? false);

/** One line per minute at most: a scanner hitting :443 must not become a log flood. */
const TLS_CLIENT_ERROR_LOG_INTERVAL_MS = 60_000;

/**
 * Start the origin TLS listener next to `httpServer`, or return null when it must not run (no
 * material, invalid material, or the port could not be bound). Never throws: the plain-HTTP
 * server is the one that must keep serving.
 */
export function startOriginTlsListener(params: {
  httpServer: HttpServer;
  env?: OriginTlsEnv;
  /** 0 asks the OS for a free port (tests). */
  port?: number;
  onListening?: (port: number) => void;
}): OriginTlsListener | null {
  const env = params.env ?? process.env;
  const loaded = loadOriginTlsMaterial(env);

  if (loaded.status === "absent") {
    log.info("origin-tls: no ORIGIN_TLS material configured, origin TLS listener disabled");
    return null;
  }
  if (loaded.status === "invalid") {
    reportSilentFallback(new Error(`origin-tls: material rejected (${loaded.reason})`), {
      feature: "origin_tls",
      op: "load",
      tags: { reason: loaded.reason },
    });
    return null;
  }

  const port = params.port ?? parsePort(env[ORIGIN_TLS_PORT_ENV]) ?? ORIGIN_TLS_DEFAULT_PORT;
  const httpsServer = createHttpsServer({
    key: loaded.key,
    cert: loaded.cert,
    minVersion: "TLSv1.2",
  });

  // The same handlers as the plain-HTTP server, by re-emitting its events: the request handler and
  // the WebSocket upgrade listener (ws-handler.ts) are registered on `httpServer`, and ws accepts
  // any duplex socket, so a TLS socket upgrades like a plain one.
  httpsServer.on("request", (req, res) => {
    if (isHealthPath(req.url)) {
      res.setHeader(ORIGIN_TRANSPORT_HEADER, negotiatedProtocol(req));
    }
    params.httpServer.emit("request", req, res);
  });
  httpsServer.on("upgrade", (req, socket, head) => {
    params.httpServer.emit("upgrade", req, socket, head);
  });

  let lastClientErrorLog = 0;
  httpsServer.on("tlsClientError", (err) => {
    const t = Date.now();
    if (t - lastClientErrorLog < TLS_CLIENT_ERROR_LOG_INTERVAL_MS) return;
    lastClientErrorLog = t;
    log.warn(
      { code: (err as NodeJS.ErrnoException).code ?? "unknown" },
      "origin-tls: a client failed the TLS handshake (rate-limited to one line per minute)",
    );
  });

  httpsServer.on("error", (err) => {
    reportSilentFallback(err, { feature: "origin_tls", op: "listen" });
  });

  httpsServer.listen(port, () => {
    const address = httpsServer.address();
    const boundPort = typeof address === "object" && address ? address.port : port;
    log.info(
      { port: boundPort, ...loaded.info },
      "origin-tls: listening (Cloudflare strict-mode origin), certificate loaded",
    );
    if (loaded.info.daysLeft < ORIGIN_TLS_EXPIRY_WARN_DAYS) {
      warnSilentFallback(new Error("origin-tls: certificate expires soon"), {
        feature: "origin_tls",
        op: "cert_expiry",
        extra: { notAfter: loaded.info.notAfter, daysLeft: loaded.info.daysLeft },
      });
    }
    params.onListening?.(boundPort);
  });

  return {
    server: httpsServer,
    close() {
      httpsServer.close();
      httpsServer.closeIdleConnections();
    },
    closeAllConnections() {
      httpsServer.closeAllConnections();
    },
  };
}

function negotiatedProtocol(req: IncomingMessage): string {
  return (req.socket as TLSSocket).getProtocol?.() ?? "unknown";
}

function parsePort(raw: string | undefined): number | null {
  if (!raw) return null;
  const n = Number.parseInt(raw, 10);
  return Number.isInteger(n) && n > 0 && n < 65536 ? n : null;
}
