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
  const cipher = createCipheriv(ALGORITHM, key, iv);

  const encrypted = Buffer.concat([
    cipher.update(plaintext, "utf8"),
    cipher.final(),
  ]);
  const tag = cipher.getAuthTag();

  return { encrypted, iv, tag };
}

export function decryptKey(
  encrypted: Buffer,
  iv: Buffer,
  tag: Buffer,
  userId: string,
): string {
  const key = deriveUserKey(getEncryptionKey(), userId);
  const decipher = createDecipheriv(ALGORITHM, key, iv);
  decipher.setAuthTag(tag);

  return decipher.update(encrypted) + decipher.final("utf8");
}

export function decryptKeyLegacy(
  encrypted: Buffer,
  iv: Buffer,
  tag: Buffer,
): string {
  const key = getEncryptionKey();
  const decipher = createDecipheriv(ALGORITHM, key, iv);
  decipher.setAuthTag(tag);

  return decipher.update(encrypted) + decipher.final("utf8");
}

