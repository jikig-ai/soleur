/**
 * Unit tests — proxy-tls.ts loader (epic #5274 Phase 3 Sub-PR 3.B).
 *
 * Loads the one-way-TLS material (PROXY_TLS_KEY / PROXY_TLS_CERT, minted in 3.A)
 * for the host↔host session-router proxy; returns null when unconfigured
 * (single-host/dev). The cert below is a SYNTHESIZED throwaway self-signed ECDSA
 * cert (cq-test-fixtures-synthesized-only) — public material, no private key.
 */

import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";

import {
  loadProxyTlsServerOptions,
  loadProxyTlsClientCa,
  getProxyCertNotAfter,
} from "@/server/proxy-tls";

// Synthesized self-signed P-256 cert, CN=soleur-web-proxy, notAfter Jun 2036.
const TEST_CERT = `-----BEGIN CERTIFICATE-----
MIIBrDCCAVOgAwIBAgIUTruQnb9gm6qqXndCo2rSOq3ScmQwCgYIKoZIzj0EAwIw
LDEZMBcGA1UEAwwQc29sZXVyLXdlYi1wcm94eTEPMA0GA1UECgwGU29sZXVyMB4X
DTI2MDcwMTE5MjMzOVoXDTM2MDYyODE5MjMzOVowLDEZMBcGA1UEAwwQc29sZXVy
LXdlYi1wcm94eTEPMA0GA1UECgwGU29sZXVyMFkwEwYHKoZIzj0CAQYIKoZIzj0D
AQcDQgAE47aUnEcuKhaKqyFlFgdetHJ1U8AT1JYXsYcCtotkLZodL05Sml/Ewv2i
RSIZ84QHnoIYXFY0vXJLXQ8tLbksVKNTMFEwHQYDVR0OBBYEFI5IeDP7zeD/dYyI
N6ikEpf23D9bMB8GA1UdIwQYMBaAFI5IeDP7zeD/dYyIN6ikEpf23D9bMA8GA1Ud
EwEB/wQFMAMBAf8wCgYIKoZIzj0EAwIDRwAwRAIgUw+ggkQXv+x1f0/iUu5x/t2W
SW3Wihcy13CkMVOOTUMCIHdOOGDrqabG+BUHWDgONBxcha9uDsstU1h3X/Mg8wv1
-----END CERTIFICATE-----`;

beforeEach(() => {
  vi.unstubAllEnvs();
  vi.stubEnv("PROXY_TLS_KEY", "");
  vi.stubEnv("PROXY_TLS_CERT", "");
});
afterEach(() => vi.unstubAllEnvs());

describe("loadProxyTlsServerOptions", () => {
  test("returns {key,cert} when both env vars are present", () => {
    vi.stubEnv("PROXY_TLS_KEY", "KEYPEM");
    vi.stubEnv("PROXY_TLS_CERT", TEST_CERT);
    expect(loadProxyTlsServerOptions()).toEqual({ key: "KEYPEM", cert: TEST_CERT });
  });

  test("returns null when the key is absent (single-host/dev — no TLS listener)", () => {
    vi.stubEnv("PROXY_TLS_CERT", TEST_CERT);
    expect(loadProxyTlsServerOptions()).toBeNull();
  });

  test("returns null when the cert is absent", () => {
    vi.stubEnv("PROXY_TLS_KEY", "KEYPEM");
    expect(loadProxyTlsServerOptions()).toBeNull();
  });
});

describe("loadProxyTlsClientCa (pinned trust anchor, never rejectUnauthorized:false)", () => {
  test("returns the cert when present", () => {
    vi.stubEnv("PROXY_TLS_CERT", TEST_CERT);
    expect(loadProxyTlsClientCa()).toBe(TEST_CERT);
  });

  test("returns null when absent (caller must treat remote owner as unreachable)", () => {
    expect(loadProxyTlsClientCa()).toBeNull();
  });
});

describe("getProxyCertNotAfter", () => {
  test("parses the notAfter of a valid cert", () => {
    const notAfter = getProxyCertNotAfter(TEST_CERT);
    expect(notAfter).toBeInstanceOf(Date);
    expect(notAfter!.getUTCFullYear()).toBe(2036);
    expect(notAfter!.getTime()).toBeGreaterThan(Date.now()); // long-lived, not expired
  });

  test("returns null on unparseable PEM", () => {
    expect(getProxyCertNotAfter("not-a-cert")).toBeNull();
    expect(getProxyCertNotAfter("")).toBeNull();
  });
});
