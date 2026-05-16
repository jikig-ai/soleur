import {
  createCipheriv,
  createDecipheriv,
  hkdfSync,
  randomBytes,
} from "crypto";

const ALGORITHM = "aes-256-gcm";
const IV_LENGTH = 12;

function getEncryptionKey(): Buffer {
  const raw = process.env.BYOK_ENCRYPTION_KEY;
  if (raw) {
    const buf = Buffer.from(raw, "hex");
    if (buf.length !== 32) {
      throw new Error(
        "BYOK_ENCRYPTION_KEY must be a 64-character hex string (32 bytes)",
      );
    }
    return buf;
  }

  if (process.env.NODE_ENV === "production") {
    throw new Error("BYOK_ENCRYPTION_KEY is required in production");
  }

  // Deterministic dev-only fallback so encrypted values survive restarts
  return Buffer.from(
    "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
    "hex",
  );
}

function deriveUserKey(masterKey: Buffer, userId: string): Buffer {
  // RFC 5869: salt empty (IKM is high-entropy), userId in info (domain separation)
  return Buffer.from(
    hkdfSync("sha256", masterKey, Buffer.alloc(0), "soleur:byok:" + userId, 32),
  );
}

export function encryptKey(
  plaintext: string,
  userId: string,
): {
  encrypted: Buffer;
  iv: Buffer;
  tag: Buffer;
} {
  const key = deriveUserKey(getEncryptionKey(), userId);
  const iv = randomBytes(IV_LENGTH);
  // CWE-310: pin authTagLength=16 (128-bit tag). Without it, an
  // attacker who can substitute the auth tag could downgrade to a
  // shorter tag (4..15 bytes) and cut forgery cost. Per #3244 review.
  const cipher = createCipheriv(ALGORITHM, key, iv, { authTagLength: 16 });

  const encrypted = Buffer.concat([
    cipher.update(plaintext, "utf8"),
    cipher.final(),
  ]);
  const tag = cipher.getAuthTag();

  return { encrypted, iv, tag };
}

/**
 * Decrypt a BYOK envelope and return the plaintext key as a `Buffer`.
 *
 * Buffer-shaped state is wipeable in place via `zeroize` — this is the
 * load-bearing primitive for the PR-B BYOK lease (#3244 §1.4). The
 * caller MUST eventually call `zeroize(returnedBuffer)` to wipe the
 * plaintext from memory. The boundary where the buffer is converted to
 * a string for the Anthropic SDK reintroduces V8 string-internment;
 * that surface is documented as a residual in the §3.6 ADR and is NOT
 * mitigated here.
 *
 * Plan: 2026-05-05-feat-soleur-server-side-agentic-runtime-plan.md §1.2 / §1.4.
 */
export function decryptKey(
  encrypted: Buffer,
  iv: Buffer,
  tag: Buffer,
  userId: string,
): Buffer {
  const key = deriveUserKey(getEncryptionKey(), userId);
  // CWE-310: pin authTagLength=16 to enforce 128-bit tag at verify time.
  const decipher = createDecipheriv(ALGORITHM, key, iv, { authTagLength: 16 });
  decipher.setAuthTag(tag);

  return Buffer.concat([decipher.update(encrypted), decipher.final()]);
}

/**
 * Legacy (v1, pre-HKDF) decryption path. Returns Buffer for symmetry
 * with `decryptKey` and to keep zeroize-on-finally consistent across
 * both decryption paths.
 */
export function decryptKeyLegacy(
  encrypted: Buffer,
  iv: Buffer,
  tag: Buffer,
): Buffer {
  const key = getEncryptionKey();
  // CWE-310: pin authTagLength=16 to enforce 128-bit tag at verify time.
  const decipher = createDecipheriv(ALGORITHM, key, iv, { authTagLength: 16 });
  decipher.setAuthTag(tag);

  return Buffer.concat([decipher.update(encrypted), decipher.final()]);
}

/**
 * Wipe a Buffer's contents in place. Used by the BYOK lease's `finally`
 * block to bound the in-Soleur-heap exposure window of decrypted keys.
 *
 * `Buffer.fill(0)` mutates the underlying ArrayBuffer bytes — any other
 * view (e.g., a `string` produced via `toString`) is a separate copy
 * and is NOT affected. The lease holds the Buffer as the sole owning
 * reference; downstream consumers receive copies through controlled
 * APIs.
 */
export function zeroize(buf: Buffer): void {
  if (buf.length === 0) return;
  buf.fill(0);
}

