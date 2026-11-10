// proxy-tls.ts — loader for the one-way-TLS material of the host↔host
// session-router proxy (epic #5274 Phase 3 Sub-PR 3.B, ADR-068 amendment
// 2026-07-01). The material itself (a single long-lived self-signed ECDSA server
// cert + key, SANs over every web host's private IP) is minted in
// infra/proxy-tls.tf (Sub-PR 3.A) and delivered to the container env via Doppler
// `prd` as PROXY_TLS_KEY / PROXY_TLS_CERT.
//
// One-way TLS (ADR-068 amendment, DHH/simplicity): the OWNING host runs an
// https/wss server presenting this cert; the PROXYING host (the non-owner an
// inbound session first lands on) dials it as a client pinning the SAME cert as
// its trust anchor (`ca: [cert], rejectUnauthorized: true` — NEVER false, which
// would be MITM-able). No client cert. A single 10-year cert ⇒ no rotation cron;
// this module logs `notAfter` at startup and a Better Stack monitor watches
// expiry (Observability §).

import { X509Certificate } from "node:crypto";
import { createChildLogger } from "./logger";
import { reportSilentFallback } from "./observability";

const log = createChildLogger("proxy-tls");

/** TLS server options for the owning host's proxy listener. */
export interface ProxyTlsServerOptions {
  key: string;
  cert: string;
}

// Exactly space, tab, CR, LF (the same four characters normalizeGitDataKey trims).
const PEM_END_WS = /^[ \t\r\n]+|[ \t\r\n]+$/g;

/**
 * Repair a PEM as the container receives it. ci-deploy.sh loads Doppler prd with
 * `doppler secrets download --format docker` + `docker --env-file`, which collapses a
 * multi-line PEM into ONE line holding literal backslash-n pairs; node's
 * `https.createServer` then throws ERR_OSSL_PEM_NO_START_LINE. A value with NO real
 * newline that contains a literal `\n` (or `\r\n`) pair gets each pair expanded to a real
 * newline; a real multi-line value (LF or CRLF) is returned trimmed and otherwise
 * untouched. Same rule as `normalizeGitDataKey`. "" when unset or blank.
 */
function normalizeProxyPem(raw: string | undefined | null): string {
  const trimmed = (raw ?? "").replace(PEM_END_WS, "");
  if (!trimmed.includes("\n") && trimmed.includes("\\n")) {
    return trimmed.replace(/(?:\\r)?\\n/g, "\n").replace(PEM_END_WS, "");
  }
  return trimmed;
}

/**
 * Load the proxy TLS server key + cert from the container env, or `null` when
 * either is absent (dev / single-host before the 3.A material is delivered) — in
 * which case the router serves only local sessions and no https listener starts.
 * Both must be present to stand up the TLS proxy server.
 */
export function loadProxyTlsServerOptions(): ProxyTlsServerOptions | null {
  const key = normalizeProxyPem(process.env.PROXY_TLS_KEY);
  const cert = normalizeProxyPem(process.env.PROXY_TLS_CERT);
  if (!key || !cert) return null;
  return { key, cert };
}

/**
 * Load the pinned trust anchor for the PROXYING client (the same self-signed
 * cert the server presents). `null` when unset — the caller must then treat a
 * remote owner as unreachable rather than dialling with verification disabled
 * (never `rejectUnauthorized: false`).
 */
export function loadProxyTlsClientCa(): string | null {
  return normalizeProxyPem(process.env.PROXY_TLS_CERT) || null;
}

const HELLO_KEY_RE = /^[0-9a-f]{64}$/;

let helloKey: { loaded: boolean; key: Buffer | null } = { loaded: false, key: null };

/**
 * The relay hello-signing key as a 32-byte Buffer, or `null` unless the env value is exactly 64
 * lowercase hex characters (the shape `random_bytes.proxy_hello_hmac` hex-encodes).
 *
 * Read ONCE, cached in module memory, and DELETED from `process.env` (CTO ruling, 2026-11-09, review
 * of #12462; the precedent is `origin-tls.ts`): every child process the server spawns with the
 * default or a spread environment would otherwise inherit the key. Call it at server boot, before
 * any child process can be spawned (index.ts does); a later caller just gets the cached value.
 * `/proc/<pid>/environ` keeps the original block either way (ADR-323 residual). The key is distinct
 * from the TLS key by construction: a leaked TLS key must not forge hellos. Rotation is a restart.
 */
export function loadProxyHelloKey(): Buffer | null {
  if (!helloKey.loaded) {
    const raw = process.env.PROXY_HELLO_HMAC_KEY;
    helloKey = { loaded: true, key: raw !== undefined && HELLO_KEY_RE.test(raw) ? Buffer.from(raw, "hex") : null };
    delete process.env.PROXY_HELLO_HMAC_KEY;
  }
  return helloKey.key;
}

/** Test seam: the cache is module state. */
export function __resetProxyHelloKeyForTests(): void {
  helloKey = { loaded: false, key: null };
}

/**
 * Parse a PEM cert's `notAfter` expiry, or `null` when the PEM is
 * absent/unparseable. Pure — used both by the startup expiry log and by tests.
 */
export function getProxyCertNotAfter(certPem: string): Date | null {
  try {
    const parsed = new Date(new X509Certificate(certPem).validTo);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  } catch {
    return null;
  }
}

/**
 * Startup observability for the long-lived proxy cert (no rotation cron — the
 * only expiry signal besides the Better Stack monitor). Logs `notAfter` +
 * days-left, and mirrors an ALREADY-EXPIRED cert to Sentry (fail-loud — an
 * expired cert silently breaks every cross-host proxy). No-op when TLS is not
 * configured (single-host/dev).
 */
export function logProxyCertExpiryAtStartup(): void {
  const cert = loadProxyTlsClientCa();
  if (!cert) {
    log.info(
      "proxy-tls: no PROXY_TLS_CERT configured — host↔host proxy TLS disabled (single-host/dev)",
    );
    return;
  }
  const notAfter = getProxyCertNotAfter(cert);
  if (!notAfter) {
    reportSilentFallback(
      new Error("PROXY_TLS_CERT present but unparseable — cannot determine expiry"),
      { feature: "control_plane_route", op: "proxy_cert_expiry" },
    );
    return;
  }
  if (notAfter.getTime() <= Date.now()) {
    reportSilentFallback(new Error("proxy-tls server cert is EXPIRED"), {
      feature: "control_plane_route",
      op: "proxy_cert_expiry",
      extra: { notAfter: notAfter.toISOString() },
    });
    return;
  }
  const daysLeft = Math.floor((notAfter.getTime() - Date.now()) / 86_400_000);
  log.info({ notAfter: notAfter.toISOString(), daysLeft }, "proxy-tls: server cert loaded");
}
