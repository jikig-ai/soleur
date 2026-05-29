/**
 * Tests for normalizeAppPrivateKey() — canonicalizes a GitHub App private key
 * PEM to a clean LF-only PKCS#8 PEM before it reaches @octokit/app.
 *
 * Root cause (Sentry 4e6a3003…): universal-github-app-jwt@2.2.2's getDERfromPEM
 * does `pem.trim().split("\n").slice(1,-1).join("")` + Web-Crypto
 * importKey("pkcs8", …) — it rejects PKCS#1 and corrupts DER from CRLF-laden
 * PEMs, surfacing as GitHub's opaque "A JSON web token could not be decoded".
 *
 * These are PURE string→string tests: no network, no @octokit/app mock.
 * Keys are synthesized per-run via crypto.generateKeyPairSync
 * (cq-test-fixtures-synthesized-only — never a real or real-shaped App key).
 */
import { describe, test, expect } from "vitest";
import { createPrivateKey, generateKeyPairSync } from "crypto";
import { normalizeAppPrivateKey } from "@/server/github/probe-octokit";

// One synthesized RSA keypair for the whole file, exported in both formats.
const { pkcs1Pem, pkcs8Pem } = (() => {
  const pkcs1 = generateKeyPairSync("rsa", {
    modulusLength: 2048,
    publicKeyEncoding: { type: "spki", format: "pem" },
    privateKeyEncoding: { type: "pkcs1", format: "pem" },
  }).privateKey;
  const pkcs8 = generateKeyPairSync("rsa", {
    modulusLength: 2048,
    publicKeyEncoding: { type: "spki", format: "pem" },
    privateKeyEncoding: { type: "pkcs8", format: "pem" },
  }).privateKey;
  return { pkcs1Pem: pkcs1 as string, pkcs8Pem: pkcs8 as string };
})();

// Mirror universal-github-app-jwt@2.2.2's fragile body extraction so the test
// proves the canonicalized output survives the exact slice the library does.
function getDERBodyFromPEM(pem: string): string {
  return pem.trim().split("\n").slice(1, -1).join("");
}

describe("normalizeAppPrivateKey", () => {
  test("AC1: PKCS#1 PEM is converted to PKCS#8", () => {
    const out = normalizeAppPrivateKey(pkcs1Pem);
    expect(out.startsWith("-----BEGIN PRIVATE KEY-----")).toBe(true);
    expect(out).not.toContain("BEGIN RSA PRIVATE KEY");
    // Round-trips back to a valid key.
    expect(() => createPrivateKey(out)).not.toThrow();
  });

  test("AC2: CRLF line endings are normalized to LF and body base64-decodes", () => {
    const crlf = pkcs8Pem.replace(/\n/g, "\r\n");
    const out = normalizeAppPrivateKey(crlf);
    expect(out).not.toContain("\r");
    const body = getDERBodyFromPEM(out);
    // No stray \r in the extracted body; decodes to non-empty DER.
    expect(body).not.toContain("\r");
    const der = Buffer.from(body, "base64");
    expect(der.length).toBeGreaterThan(0);
  });

  test("AC3: escaped \\n is expanded to real newlines and parses", () => {
    // Env/Doppler-shaped single-line value with literal backslash-n separators.
    const escaped = pkcs8Pem.replace(/\n/g, "\\n");
    expect(escaped).toContain("\\n");
    const out = normalizeAppPrivateKey(escaped);
    expect(out).toContain("\n");
    expect(out).not.toContain("\\n");
    expect(out.startsWith("-----BEGIN PRIVATE KEY-----")).toBe(true);
    expect(() => createPrivateKey(out)).not.toThrow();
  });

  test("AC4: a clean PKCS#8 LF PEM is idempotent (modulo trailing newline)", () => {
    const out = normalizeAppPrivateKey(pkcs8Pem);
    expect(out.trim()).toBe(pkcs8Pem.trim());
  });

  test("AC: empty value throws (does not swallow a missing/blank secret)", () => {
    expect(() => normalizeAppPrivateKey("")).toThrow();
  });

  test("AC: whitespace-only value throws", () => {
    expect(() => normalizeAppPrivateKey("   \n  ")).toThrow();
  });
});
