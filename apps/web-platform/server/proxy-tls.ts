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
import { inspect } from "node:util";
import { createChildLogger } from "./logger";
import { reportSilentFallback, warnSilentFallback } from "./observability";

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

/**
 * The relay hello keys this process loaded. `current` signs and verifies; `acceptAlso` (the accept-only slot
 * PROXY_HELLO_HMAC_KEY_ACCEPT_ALSO, #8211, ADR-323 Decision 9) is VERIFY-ONLY: no code path signs with it. The
 * object is frozen and redacting: `JSON.stringify` and `util.inspect` print a placeholder, and both slots are
 * non-enumerable, so a copy of the set (spread, Object.assign, structuredClone) carries no key. A Buffer read out of
 * it (`keys.current`) is a raw key: never log it.
 */
export interface ProxyHelloKeys {
  readonly current: Buffer | null;
  readonly acceptAlso: Buffer | null;
}

const KEYS_PLACEHOLDER = "[proxy-hello-keys]";

function redactingKeySet(current: Buffer | null, acceptAlso: Buffer | null): ProxyHelloKeys {
  // Every property is non-enumerable: `keys.current` reads work, while a spread, Object.assign, Object.entries,
  // structuredClone or util.inspect({customInspect: false}) copy or print no key.
  const set = Object.defineProperties({} as ProxyHelloKeys, {
    current: { value: current },
    acceptAlso: { value: acceptAlso },
    toJSON: { value: () => KEYS_PLACEHOLDER },
    [inspect.custom]: { value: () => KEYS_PLACEHOLDER },
  });
  return Object.freeze(set);
}

let helloKeys: ProxyHelloKeys | null = null;

/**
 * The relay hello keys, each a 32-byte Buffer or `null` unless its env value is exactly 64 lowercase hex characters
 * (the shape `random_bytes.proxy_hello_hmac` hex-encodes).
 *
 * Both variables are read ONCE, cached in module memory, and BOTH are DELETED from `process.env` on the first call,
 * whatever their values (CTO ruling, 2026-11-09, review of #12462; the precedent is `origin-tls.ts`): every child
 * process the server spawns with the default or a spread environment would otherwise inherit them. Call it at server
 * boot, before any child process can be spawned (index.ts does); a later caller just gets the cached value.
 * `/proc/<pid>/environ` keeps the original block either way (ADR-323 residual). The key is distinct from the TLS key
 * by construction: a leaked TLS key must not forge hellos. Any key change is a restart.
 *
 * The accept-only slot (absent by default, so it ships dark):
 * - unset or empty: `null`, silently;
 * - set but not 64 lowercase hex: `null`, plus one `loadProxyHelloKeys.accept-also-ignored` event, whether or not
 *   `current` is loaded;
 * - byte-equal to `current`: kept (accepting one key twice is harmless), plus one warn-level
 *   `loadProxyHelloKeys.accept-also-equals-current` event; `relay_hello_key_fp` then shows equal values;
 * - well-formed and distinct: kept, plus one warn-level `loadProxyHelloKeys.accept-also-active` event (the slot sits
 *   outside Terraform, so a planted slot must not be silent; the event is expected during a rotation);
 * - well-formed while `current` is null: no extra event (the listener refuses to start and reports no-hello-key).
 * Every event text is a constant: no value, length or prefix. Each fires once per process (cached).
 */
export function loadProxyHelloKeys(): ProxyHelloKeys {
  if (helloKeys === null) {
    const rawCurrent = process.env.PROXY_HELLO_HMAC_KEY;
    const rawAlso = process.env.PROXY_HELLO_HMAC_KEY_ACCEPT_ALSO;
    delete process.env.PROXY_HELLO_HMAC_KEY;
    delete process.env.PROXY_HELLO_HMAC_KEY_ACCEPT_ALSO;
    const current = rawCurrent !== undefined && HELLO_KEY_RE.test(rawCurrent) ? Buffer.from(rawCurrent, "hex") : null;
    let acceptAlso: Buffer | null = null;
    if (rawAlso !== undefined && rawAlso !== "") {
      if (!HELLO_KEY_RE.test(rawAlso)) {
        reportSilentFallback(null, {
          feature: "control_plane_route",
          op: "loadProxyHelloKeys.accept-also-ignored",
          message: "PROXY_HELLO_HMAC_KEY_ACCEPT_ALSO is set but malformed — ignored",
        });
      } else {
        acceptAlso = Buffer.from(rawAlso, "hex");
        if (current !== null && acceptAlso.equals(current)) {
          warnSilentFallback(null, {
            feature: "control_plane_route",
            op: "loadProxyHelloKeys.accept-also-equals-current",
            message: "PROXY_HELLO_HMAC_KEY_ACCEPT_ALSO equals the current hello key — kept, but it adds no second key",
          });
        } else if (current !== null) {
          warnSilentFallback(null, {
            feature: "control_plane_route",
            op: "loadProxyHelloKeys.accept-also-active",
            message: "PROXY_HELLO_HMAC_KEY_ACCEPT_ALSO is set — the relay also accepts a second hello key (expected only during a rotation)",
          });
        }
      }
    }
    helloKeys = redactingKeySet(current, acceptAlso);
  }
  return helloKeys;
}

/** Test seam: the cache is module state. */
export function __resetProxyHelloKeyForTests(): void {
  helloKeys = null;
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
