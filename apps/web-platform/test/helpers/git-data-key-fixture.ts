// Test-time git-data SSH key fixtures (#8211 PR-G). Keys are SYNTHESIZED per call with
// ssh-keygen into a throwaway directory - never a real credential. When ssh-keygen is
// not installed the helper falls back to a PEM-shaped placeholder (not parseable), and
// `HAS_SSH_KEYGEN` lets a parseability assertion skip instead of lie.
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";

// PEM markers are assembled so no source line carries a literal key block (secret scanners flag the shape).
export const PEM_BEGIN = ["-----BEGIN", "OPENSSH PRIVATE KEY-----"].join(" ");
export const PEM_END = ["-----END", "OPENSSH PRIVATE KEY-----"].join(" ");

export const HAS_SSH_KEYGEN = spawnSync("ssh-keygen", ["-?"], { stdio: "ignore" }).error === undefined;

/** A freshly generated, unencrypted OpenSSH ed25519 private key: multi-line, LF-terminated. */
export function makeMultilineKey(): string {
  if (!HAS_SSH_KEYGEN) {
    return [PEM_BEGIN, "c3ludGhlc2l6ZWQtcGxhY2Vob2xkZXIta2V5LW5vdC1wYXJzZWFibGU=", PEM_END, ""].join("\n");
  }
  const dir = mkdtempSync(path.join(tmpdir(), "gdk-fixture-"));
  try {
    const f = path.join(dir, "k");
    const r = spawnSync("ssh-keygen", ["-q", "-t", "ed25519", "-N", "", "-C", "synthesized-test-key", "-f", f]);
    if (r.status !== 0) throw new Error("ssh-keygen failed to synthesize a test key");
    return readFileSync(f, "utf8");
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

/**
 * The form the container receives: what `doppler secrets download --format docker` +
 * `docker --env-file` leaves of a multi-line value - ONE line, literal backslash-n pairs
 * (measured: an 8-line value -> 7 pairs, the trailing newline gone).
 */
export function toDockerForm(multiline: string): string {
  return multiline.trim().split("\n").join("\\n");
}

/** `ssh-keygen -y -f` on the given file content: true when it parses as a private key. */
export function keyParses(content: string): boolean {
  const dir = mkdtempSync(path.join(tmpdir(), "gdk-parse-"));
  try {
    const f = path.join(dir, "k");
    writeFileSync(f, content, { mode: 0o600 });
    return spawnSync("ssh-keygen", ["-y", "-f", f], { stdio: "ignore", input: "" }).status === 0;
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}
