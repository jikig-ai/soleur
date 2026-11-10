/**
 * Unit tests — proxy-tls.ts loader (epic #5274 Phase 3 Sub-PR 3.B).
 *
 * Loads the one-way-TLS material (PROXY_TLS_KEY / PROXY_TLS_CERT, minted in 3.A)
 * for the host↔host session-router proxy; returns null when unconfigured
 * (single-host/dev). The cert below is a SYNTHESIZED throwaway self-signed ECDSA
 * cert (cq-test-fixtures-synthesized-only) — public material, no private key.
 */

import { execFileSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { createServer } from "node:https";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { inspect } from "node:util";
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, test, vi } from "vitest";

import { REDACT_PATHS, SENSITIVE_LOWER } from "@/server/sensitive-keys";

// Named Sentry-mirror spies (#8211 accept-only slot): the loader's degraded states are asserted by op.
const { mockReportSilentFallback, mockWarnSilentFallback } = vi.hoisted(() => ({
  mockReportSilentFallback: vi.fn(),
  mockWarnSilentFallback: vi.fn(),
}));
vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
  warnSilentFallback: mockWarnSilentFallback,
  infoSilentFallback: vi.fn(),
}));

import {
  loadProxyTlsServerOptions,
  loadProxyTlsClientCa,
  getProxyCertNotAfter,
  __resetProxyHelloKeyForTests,
  loadProxyHelloKeys,
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

describe("loadProxyHelloKeys().current (#12289): a 32-byte Buffer only for exactly 64 lowercase hex, read once, then deleted from the env", () => {
  const VALID = "0123456789abcdef".repeat(4);
  beforeEach(() => __resetProxyHelloKeyForTests());

  test("valid key: a 32-byte Buffer holding the decoded bytes", () => {
    vi.stubEnv("PROXY_HELLO_HMAC_KEY", VALID);
    const key = loadProxyHelloKeys().current;
    expect(key).toBeInstanceOf(Buffer);
    expect(key).toHaveLength(32);
    expect(key?.toString("hex")).toBe(VALID);
  });

  test("a different random valid key per run is accepted", () => {
    const k = Array.from({ length: 64 }, () => "0123456789abcdef"[Math.floor(Math.random() * 16)]).join("");
    vi.stubEnv("PROXY_HELLO_HMAC_KEY", k);
    expect(loadProxyHelloKeys().current?.toString("hex")).toBe(k);
  });

  test("unset and empty read as null", () => {
    vi.stubEnv("PROXY_HELLO_HMAC_KEY", "");
    expect(loadProxyHelloKeys().current).toBeNull();
  });

  test.each([
    ["63 chars", VALID.slice(1)],
    ["65 chars", VALID + "a"],
    ["uppercase", VALID.toUpperCase()],
    ["leading space", " " + VALID],
    ["trailing newline", VALID + "\n"],
    ["non-hex char", VALID.slice(0, 63) + "g"],
    ["0x prefix", "0x" + VALID.slice(2)],
  ])("%s reads as null", (_n, v) => {
    vi.stubEnv("PROXY_HELLO_HMAC_KEY", v);
    expect(loadProxyHelloKeys().current).toBeNull();
  });

  test("the first read DELETES the variable from process.env (children spawned later cannot inherit it)", () => {
    vi.stubEnv("PROXY_HELLO_HMAC_KEY", VALID);
    expect(process.env.PROXY_HELLO_HMAC_KEY).toBe(VALID);
    loadProxyHelloKeys();
    expect("PROXY_HELLO_HMAC_KEY" in process.env).toBe(false);
  });

  test("an invalid value is deleted too, and the verdict is cached", () => {
    vi.stubEnv("PROXY_HELLO_HMAC_KEY", "not-a-key");
    expect(loadProxyHelloKeys().current).toBeNull();
    expect("PROXY_HELLO_HMAC_KEY" in process.env).toBe(false);
  });

  test("cached: a later env change is not re-read; the reset seam reloads", () => {
    vi.stubEnv("PROXY_HELLO_HMAC_KEY", VALID);
    const first = loadProxyHelloKeys().current;
    vi.stubEnv("PROXY_HELLO_HMAC_KEY", "f".repeat(64));
    expect(loadProxyHelloKeys().current?.toString("hex")).toBe(first?.toString("hex"));
    __resetProxyHelloKeyForTests();
    vi.stubEnv("PROXY_HELLO_HMAC_KEY", "f".repeat(64));
    expect(loadProxyHelloKeys().current?.toString("hex")).toBe("f".repeat(64));
  });
});

// #8211 (ADR-323 Decision 9, B3) — the accept-only slot PROXY_HELLO_HMAC_KEY_ACCEPT_ALSO. Verify-only, never signed
// with, absent by default. Each loader state is asserted with its exact Sentry events (named spies), and every event
// payload is scanned for the fixture keys' hex and base64 forms. Keys are synthesized per run.
describe("loadProxyHelloKeys: the accept-only slot (#8211)", () => {
  const CURRENT_HEX = randomBytes(32).toString("hex");
  const ALSO_HEX = randomBytes(32).toString("hex");
  const SLOT = "PROXY_HELLO_HMAC_KEY_ACCEPT_ALSO";
  const MALFORMED_MESSAGE = "PROXY_HELLO_HMAC_KEY_ACCEPT_ALSO is set but malformed — ignored";
  const ops = () => [
    ...mockReportSilentFallback.mock.calls.map((c) => ({ level: "error", err: c[0], op: c[1]?.op as string, opts: c[1] })),
    ...mockWarnSilentFallback.mock.calls.map((c) => ({ level: "warn", err: c[0], op: c[1]?.op as string, opts: c[1] })),
  ];
  const assertNoKeyMaterial = () => {
    const blob = JSON.stringify([mockReportSilentFallback.mock.calls, mockWarnSilentFallback.mock.calls]);
    for (const hex of [CURRENT_HEX, ALSO_HEX]) {
      expect(blob).not.toContain(hex);
      expect(blob).not.toContain(hex.slice(0, 8));
      expect(blob).not.toContain(Buffer.from(hex, "hex").toString("base64"));
    }
  };

  beforeEach(() => {
    __resetProxyHelloKeyForTests();
    mockReportSilentFallback.mockClear();
    mockWarnSilentFallback.mockClear();
  });

  test("fixture distinctness: the current and accept-also fixture keys differ (else every two-key row is vacuous)", () => {
    expect(CURRENT_HEX).not.toBe(ALSO_HEX);
  });

  test("slot unset (the default): acceptAlso is null and 0 events", () => {
    vi.stubEnv("PROXY_HELLO_HMAC_KEY", CURRENT_HEX);
    const keys = loadProxyHelloKeys();
    expect(keys.current?.toString("hex")).toBe(CURRENT_HEX);
    expect(keys.acceptAlso).toBeNull();
    expect(ops()).toEqual([]);
  });

  test("slot empty: acceptAlso is null and 0 events", () => {
    vi.stubEnv("PROXY_HELLO_HMAC_KEY", CURRENT_HEX);
    vi.stubEnv(SLOT, "");
    expect(loadProxyHelloKeys().acceptAlso).toBeNull();
    expect(ops()).toEqual([]);
  });

  test.each([
    ["63 chars", () => ALSO_HEX.slice(1)],
    ["65 chars", () => ALSO_HEX + "a"],
    ["uppercase", () => ALSO_HEX.toUpperCase()],
    ["trailing newline", () => ALSO_HEX + "\n"],
    ["non-hex char", () => ALSO_HEX.slice(0, 63) + "g"],
  ])("slot malformed (%s): acceptAlso is null, exactly 1 accept-also-ignored error event with exactly the constant payload", (_n, value) => {
    vi.stubEnv("PROXY_HELLO_HMAC_KEY", CURRENT_HEX);
    vi.stubEnv(SLOT, value());
    const keys = loadProxyHelloKeys();
    expect(keys.current?.toString("hex")).toBe(CURRENT_HEX);
    expect(keys.acceptAlso).toBeNull();
    expect(ops().map((o) => [o.level, o.op])).toEqual([["error", "loadProxyHelloKeys.accept-also-ignored"]]);
    const [only] = ops();
    expect(only.err).toBeNull();
    // Exact: any extra key (a length, a prefix, an `extra` object) fails.
    expect(only.opts).toEqual({ feature: "control_plane_route", op: "loadProxyHelloKeys.accept-also-ignored", message: MALFORMED_MESSAGE });
    assertNoKeyMaterial();
  });

  test("the malformed-slot message is CONSTANT: two malformed inputs of different lengths, with and without a current key, give one identical message", () => {
    const messages: string[] = [];
    for (const [current, slot] of [
      [CURRENT_HEX, "zz"],
      [CURRENT_HEX, ALSO_HEX.slice(1)],
      ["", "zz"],
      ["", ALSO_HEX + "a"],
    ] as const) {
      __resetProxyHelloKeyForTests();
      mockReportSilentFallback.mockClear();
      mockWarnSilentFallback.mockClear();
      vi.stubEnv("PROXY_HELLO_HMAC_KEY", current);
      vi.stubEnv(SLOT, slot);
      loadProxyHelloKeys();
      expect(ops().map((o) => o.op)).toEqual(["loadProxyHelloKeys.accept-also-ignored"]);
      messages.push(String(ops()[0].opts?.message));
    }
    expect(new Set(messages)).toEqual(new Set([MALFORMED_MESSAGE]));
    expect(MALFORMED_MESSAGE).not.toMatch(/\d/);
    // True with no current key too: it claims nothing about which key the relay accepts.
    expect(MALFORMED_MESSAGE).not.toMatch(/current/i);
  });

  test("slot equal to current: KEPT, exactly 1 warn-level accept-also-equals-current event", () => {
    vi.stubEnv("PROXY_HELLO_HMAC_KEY", CURRENT_HEX);
    vi.stubEnv(SLOT, CURRENT_HEX);
    const keys = loadProxyHelloKeys();
    expect(keys.acceptAlso?.toString("hex")).toBe(CURRENT_HEX);
    expect(ops().map((o) => [o.level, o.op])).toEqual([["warn", "loadProxyHelloKeys.accept-also-equals-current"]]);
    expect(ops()[0].err).toBeNull();
    expect(ops()[0].opts).toMatchObject({ feature: "control_plane_route" });
    assertNoKeyMaterial();
  });

  test("slot well-formed and distinct: kept, exactly 1 warn-level accept-also-active event with no value or fingerprint", () => {
    vi.stubEnv("PROXY_HELLO_HMAC_KEY", CURRENT_HEX);
    vi.stubEnv(SLOT, ALSO_HEX);
    const keys = loadProxyHelloKeys();
    expect(keys.current?.toString("hex")).toBe(CURRENT_HEX);
    expect(keys.acceptAlso?.toString("hex")).toBe(ALSO_HEX);
    expect(ops().map((o) => [o.level, o.op])).toEqual([["warn", "loadProxyHelloKeys.accept-also-active"]]);
    expect(ops()[0].err).toBeNull();
    expect(ops()[0].opts?.extra).toBeUndefined();
    assertNoKeyMaterial();
  });

  test("slot well-formed, current absent: the loader emits nothing (the listener's no-hello-key event is the signal)", () => {
    vi.stubEnv("PROXY_HELLO_HMAC_KEY", "");
    vi.stubEnv(SLOT, ALSO_HEX);
    const keys = loadProxyHelloKeys();
    expect(keys.current).toBeNull();
    expect(ops()).toEqual([]);
  });

  test("slot malformed, current absent: exactly 1 accept-also-ignored event from the loader", () => {
    vi.stubEnv("PROXY_HELLO_HMAC_KEY", "");
    vi.stubEnv(SLOT, "not-a-key");
    const keys = loadProxyHelloKeys();
    expect(keys.current).toBeNull();
    expect(keys.acceptAlso).toBeNull();
    expect(ops().map((o) => o.op)).toEqual(["loadProxyHelloKeys.accept-also-ignored"]);
  });

  test("each op has its own constant message text (Sentry groups by message), naming no value", () => {
    const messages: string[] = [];
    for (const v of ["bad", CURRENT_HEX, ALSO_HEX]) {
      __resetProxyHelloKeyForTests();
      mockReportSilentFallback.mockClear();
      mockWarnSilentFallback.mockClear();
      vi.stubEnv("PROXY_HELLO_HMAC_KEY", CURRENT_HEX);
      vi.stubEnv(SLOT, v);
      loadProxyHelloKeys();
      messages.push(String(ops()[0].opts?.message));
    }
    expect(new Set(messages).size).toBe(3);
    for (const m of messages) {
      expect(m.length).toBeGreaterThan(0);
      expect(m).not.toMatch(/[0-9a-f]{8}/);
    }
  });

  test.each([
    ["malformed", () => "not-a-key", "loadProxyHelloKeys.accept-also-ignored"],
    ["equal to current", () => CURRENT_HEX, "loadProxyHelloKeys.accept-also-equals-current"],
    ["distinct", () => ALSO_HEX, "loadProxyHelloKeys.accept-also-active"],
  ])("call twice (%s): the event fires exactly once (cached loader), and the slot is not re-read", (_n, value, op) => {
    vi.stubEnv("PROXY_HELLO_HMAC_KEY", CURRENT_HEX);
    vi.stubEnv(SLOT, value());
    const first = loadProxyHelloKeys();
    vi.stubEnv(SLOT, randomBytes(32).toString("hex"));
    const second = loadProxyHelloKeys();
    expect(second).toBe(first);
    expect(ops().map((o) => o.op)).toEqual([op]);
  });

  test.each([
    ["well-formed", () => ALSO_HEX],
    ["malformed", () => "not-a-key"],
    ["empty", () => ""],
  ])("the first read DELETES both names from process.env, whatever the slot holds (%s)", (_n, value) => {
    vi.stubEnv("PROXY_HELLO_HMAC_KEY", CURRENT_HEX);
    vi.stubEnv(SLOT, value());
    expect(SLOT in process.env).toBe(true);
    loadProxyHelloKeys();
    expect("PROXY_HELLO_HMAC_KEY" in process.env).toBe(false);
    expect(SLOT in process.env).toBe(false);
  });

  test("the key set is frozen and redacting: JSON.stringify, util.inspect (customInspect on or off), spread, Object.assign, Object.entries and structuredClone never carry a key byte, while property reads still work", () => {
    vi.stubEnv("PROXY_HELLO_HMAC_KEY", CURRENT_HEX);
    vi.stubEnv(SLOT, ALSO_HEX);
    const keys = loadProxyHelloKeys();
    expect(Object.isFrozen(keys)).toBe(true);
    // The two slots are own, non-enumerable properties: reads work, copies carry nothing.
    expect(Object.keys(keys)).toEqual([]);
    expect(Object.getOwnPropertyNames(keys).sort()).toEqual(["acceptAlso", "current", "toJSON"]);
    expect(keys.current?.toString("hex")).toBe(CURRENT_HEX);
    expect(keys.acceptAlso?.toString("hex")).toBe(ALSO_HEX);
    const { current, acceptAlso } = keys; // destructuring reads still work
    expect(current?.toString("hex")).toBe(CURRENT_HEX);
    expect(acceptAlso?.toString("hex")).toBe(ALSO_HEX);
    const outputs = [
      JSON.stringify(keys),
      JSON.stringify({ nested: keys }),
      inspect(keys),
      inspect({ nested: keys }, { depth: 5 }),
      inspect(keys, { customInspect: false }),
      inspect({ nested: keys }, { customInspect: false, depth: 5 }),
      JSON.stringify({ ...keys }),
      inspect({ ...keys }),
      JSON.stringify(Object.assign({}, keys)),
      inspect(Object.assign({}, keys)),
      JSON.stringify(Object.entries(keys)),
      inspect(Object.entries(keys)),
      JSON.stringify(Object.values(keys)),
      inspect(structuredClone(keys)),
      JSON.stringify(structuredClone(keys)),
      `${String(keys)} ${JSON.stringify([keys])}`,
    ];
    for (const hex of [CURRENT_HEX, ALSO_HEX]) {
      const bytes = Buffer.from(hex, "hex");
      const spaced = hex.match(/../g)!.join(" ");
      for (const out of outputs) {
        expect(out).not.toContain(hex);
        expect(out).not.toContain(spaced.slice(0, 23)); // util.inspect's `<Buffer 01 23 ...>` form
        expect(out).not.toContain(Array.from(bytes).slice(0, 8).join(",")); // JSON's `{"data":[1,35,...]}` form
        expect(out).not.toContain(bytes.toString("base64"));
      }
    }
    expect(JSON.stringify(keys)).toBe('"[proxy-hello-keys]"');
    expect(JSON.stringify({ ...keys })).toBe("{}");
    expect(Object.entries(keys)).toEqual([]);
    expect(Object.keys(structuredClone(keys))).toEqual([]);
  });
});
