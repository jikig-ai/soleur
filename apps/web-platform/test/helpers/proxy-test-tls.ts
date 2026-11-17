import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

// cq-test-fixtures-synthesized-only: a throwaway self-signed cert for the relay tests, minted ONCE
// per test file (the openssl spawn dominates a real-socket file's runtime when done per case).
// SAN covers 127.0.0.1 so a client pinning the cert as its CA verifies a loopback listener.

export interface ProxyTestTls {
  KEY: string;
  CERT: string;
  cleanup: () => void;
}

export function makeProxyTestTls(): ProxyTestTls {
  const dir = mkdtempSync(join(tmpdir(), "relay-test-tls-"));
  execFileSync(
    "openssl",
    [
      "req", "-x509", "-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:prime256v1", "-nodes",
      "-keyout", join(dir, "k.pem"), "-out", join(dir, "c.pem"), "-days", "1",
      "-subj", "/CN=relay-test", "-addext", "subjectAltName=IP:127.0.0.1",
    ],
    { stdio: "ignore" },
  );
  const KEY = readFileSync(join(dir, "k.pem"), "utf8");
  const CERT = readFileSync(join(dir, "c.pem"), "utf8");
  return { KEY, CERT, cleanup: () => rmSync(dir, { recursive: true, force: true }) };
}
