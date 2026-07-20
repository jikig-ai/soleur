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

/**
 * Load the proxy TLS server key + cert from the container env, or `null` when
 * either is absent (dev / single-host before the 3.A material is delivered) — in
 * which case the router serves only local sessions and no https listener starts.
 * Both must be present to stand up the TLS proxy server.
 */
export function loadProxyTlsServerOptions(): ProxyTlsServerOptions | null {
  const key = process.env.PROXY_TLS_KEY?.trim();
  const cert = process.env.PROXY_TLS_CERT?.trim();
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
  const cert = process.env.PROXY_TLS_CERT?.trim();
  return cert || null;
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
