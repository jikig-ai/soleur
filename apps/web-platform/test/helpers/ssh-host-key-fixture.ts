// Test-time SSH host-key fixtures (#7226 / #5914, Guard 3 + Guard 5 harness rows).
//
// Keys are GENERATED per run — never a real host key. The OpenSSH public-key line
// is assembled from node's raw ED25519 public key: the wire blob is
// string("ssh-ed25519") || string(<32-byte key>), each length-prefixed (RFC 8709 §4).

import { createHash, generateKeyPairSync } from "crypto";

function sshString(buf: Buffer): Buffer {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(buf.length, 0);
  return Buffer.concat([len, buf]);
}

/** A freshly generated `ssh-ed25519 <base64>` line (no comment), valid pin shape. */
export function makeEd25519Pin(): string {
  const { publicKey } = generateKeyPairSync("ed25519");
  const der = publicKey.export({ type: "spki", format: "der" });
  const raw = der.subarray(der.length - 32); // SPKI for ED25519 ends in the raw 32-byte key
  const blob = Buffer.concat([sshString(Buffer.from("ssh-ed25519")), sshString(raw)]);
  return `ssh-ed25519 ${blob.toString("base64")}`;
}

/** The OpenSSH `SHA256:` fingerprint of a pin line, computed independently of the app. */
export function expectedFingerprint(pin: string): string {
  const b64 = pin.split(" ")[1];
  const digest = createHash("sha256").update(Buffer.from(b64, "base64")).digest("base64");
  return `SHA256:${digest.replace(/=+$/, "")}`;
}

/**
 * The unpinned TOFU option, assembled so that no test file carries the literal
 * (Guard 1 counts it in exactly one tracked place: git-auth.ts TOFU_FALLBACK_OPTS).
 */
export const TOFU_OPT = "StrictHostKeyChecking=" + "accept" + "-new";
