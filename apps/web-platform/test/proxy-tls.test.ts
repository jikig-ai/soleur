/**
 * Unit tests — proxy-tls.ts loader (epic #5274 Phase 3 Sub-PR 3.B).
 *
 * Loads the one-way-TLS material (PROXY_TLS_KEY / PROXY_TLS_CERT, minted in 3.A)
 * for the host↔host session-router proxy; returns null when unconfigured
 * (single-host/dev). The cert below is a SYNTHESIZED throwaway self-signed ECDSA
 * cert (cq-test-fixtures-synthesized-only) — public material, no private key.
 */

import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { createServer } from "node:https";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, test, vi } from "vitest";

import { REDACT_PATHS, SENSITIVE_LOWER } from "@/server/sensitive-keys";

import {
  loadProxyTlsServerOptions,
  loadProxyTlsClientCa,
  getProxyCertNotAfter,
  getProxyHelloKeyState,
  loadProxyHelloKey,
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

// ci-deploy.sh loads Doppler prd with `doppler secrets download --format docker` + `docker
// --env-file`: a multi-line PEM arrives as ONE line of literal backslash-n pairs, and
// https.createServer throws ERR_OSSL_PEM_NO_START_LINE on it. The loaders repair it.
describe("collapsed (docker env-file) PEM is normalised on load", () => {
  let dir: string;
  let KEY: string;
  let CERT: string;
  const collapse = (pem: string) => pem.trim().replace(/\r?\n/g, "\\n");

  beforeAll(() => {
    dir = mkdtempSync(join(tmpdir(), "proxy-tls-pem-"));
    execFileSync(
      "openssl",
      ["req", "-x509", "-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:prime256v1", "-nodes",
       "-keyout", join(dir, "k.pem"), "-out", join(dir, "c.pem"), "-days", "1", "-subj", "/CN=pem-load-test"],
      { stdio: "ignore" },
    );
    KEY = readFileSync(join(dir, "k.pem"), "utf8").trim();
    CERT = readFileSync(join(dir, "c.pem"), "utf8").trim();
  });
  afterAll(() => rmSync(dir, { recursive: true, force: true }));

  test("the collapsed form really is what node cannot load (the measured failure)", () => {
    expect(collapse(KEY)).not.toContain("\n");
    expect(() => createServer({ key: collapse(KEY), cert: collapse(CERT) })).toThrow();
  });

  test("collapsed key + cert load as real multi-line PEM and a real https server accepts them", () => {
    vi.stubEnv("PROXY_TLS_KEY", collapse(KEY));
    vi.stubEnv("PROXY_TLS_CERT", collapse(CERT));
    const opts = loadProxyTlsServerOptions();
    expect(opts).toEqual({ key: KEY, cert: CERT });
    expect(() => createServer(opts!)).not.toThrow();
  });

  test("collapsed client CA loads normalised, and getProxyCertNotAfter sees the normalised form", () => {
    vi.stubEnv("PROXY_TLS_CERT", collapse(CERT));
    const ca = loadProxyTlsClientCa();
    expect(ca).toBe(CERT);
    expect(getProxyCertNotAfter(ca!)).toBeInstanceOf(Date);
  });

  test("a trailing literal backslash-n (docker format artefact) is trimmed away", () => {
    vi.stubEnv("PROXY_TLS_CERT", `${collapse(CERT)}\\n`);
    expect(loadProxyTlsClientCa()).toBe(CERT);
  });

  test("literal CRLF pairs collapse to the same PEM as LF pairs", () => {
    vi.stubEnv("PROXY_TLS_CERT", CERT.replace(/\n/g, "\\r\\n"));
    expect(loadProxyTlsClientCa()).toBe(CERT);
  });

  test("a real multi-line PEM is untouched (inner text never rewritten)", () => {
    vi.stubEnv("PROXY_TLS_KEY", KEY);
    vi.stubEnv("PROXY_TLS_CERT", `${CERT}\n`);
    expect(loadProxyTlsServerOptions()).toEqual({ key: KEY, cert: CERT });
    const withBackslashN = `${CERT.split("\n")[0]}\nliteral\\ntext\n${CERT.split("\n").slice(1).join("\n")}`;
    vi.stubEnv("PROXY_TLS_CERT", withBackslashN);
    expect(loadProxyTlsClientCa()).toBe(withBackslashN);
  });

  test("a real multi-line CRLF PEM is accepted by node and left as-is", () => {
    const crlfKey = KEY.replace(/\n/g, "\r\n");
    const crlfCert = CERT.replace(/\n/g, "\r\n");
    vi.stubEnv("PROXY_TLS_KEY", crlfKey);
    vi.stubEnv("PROXY_TLS_CERT", crlfCert);
    const opts = loadProxyTlsServerOptions();
    expect(opts).toEqual({ key: crlfKey, cert: crlfCert });
    expect(() => createServer(opts!)).not.toThrow();
  });
});

describe("PROXY_TLS_KEY is a sensitive key; the public cert is not", () => {
  test("listed for pino/Sentry redaction", () => {
    expect(SENSITIVE_LOWER.has("proxy_tls_key")).toBe(true);
    expect(SENSITIVE_LOWER.has("proxy_tls_cert")).toBe(false);
    expect(REDACT_PATHS).toContain("PROXY_TLS_KEY");
  });
});

describe("loadProxyHelloKey (#12289): a 32-byte Buffer only for exactly 64 lowercase hex", () => {
  const VALID = "0123456789abcdef".repeat(4);

  test("valid key: state ok and a 32-byte Buffer holding the decoded bytes", () => {
    vi.stubEnv("PROXY_HELLO_HMAC_KEY", VALID);
    expect(getProxyHelloKeyState()).toBe("ok");
    const key = loadProxyHelloKey();
    expect(key).toBeInstanceOf(Buffer);
    expect(key).toHaveLength(32);
    expect(key?.toString("hex")).toBe(VALID);
  });

  test("a different random valid key per run is accepted", () => {
    const k = Array.from({ length: 64 }, () => "0123456789abcdef"[Math.floor(Math.random() * 16)]).join("");
    vi.stubEnv("PROXY_HELLO_HMAC_KEY", k);
    expect(loadProxyHelloKey()?.toString("hex")).toBe(k);
  });

  test("unset and empty read as absent", () => {
    vi.stubEnv("PROXY_HELLO_HMAC_KEY", "");
    expect(getProxyHelloKeyState()).toBe("absent");
    expect(loadProxyHelloKey()).toBeNull();
  });

  test.each([
    ["63 chars", VALID.slice(1)],
    ["65 chars", VALID + "a"],
    ["uppercase", VALID.toUpperCase().replace(/0123456789ABCDEF/g, "0123456789ABCDEF")],
    ["leading space", " " + VALID],
    ["trailing newline", VALID + "\n"],
    ["non-hex char", VALID.slice(0, 63) + "g"],
    ["0x prefix", "0x" + VALID.slice(2)],
  ])("%s reads as invalid and returns null", (_n, v) => {
    vi.stubEnv("PROXY_HELLO_HMAC_KEY", v);
    expect(getProxyHelloKeyState()).toBe("invalid");
    expect(loadProxyHelloKey()).toBeNull();
  });

  test("the key is read per call from process.env, not cached", () => {
    vi.stubEnv("PROXY_HELLO_HMAC_KEY", VALID);
    expect(loadProxyHelloKey()).not.toBeNull();
    vi.stubEnv("PROXY_HELLO_HMAC_KEY", "");
    expect(loadProxyHelloKey()).toBeNull();
  });
});
