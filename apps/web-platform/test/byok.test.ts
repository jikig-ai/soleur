import { describe, test, expect } from "vitest";
import { createCipheriv, randomBytes } from "crypto";
import { encryptKey, decryptKey, decryptKeyLegacy } from "../server/byok";

const TEST_USER_A = "550e8400-e29b-41d4-a716-446655440000";
const TEST_USER_B = "660e8400-e29b-41d4-a716-446655440001";

describe("BYOK encryption round-trip", () => {
  test("encrypts and decrypts a key correctly with HKDF", () => {
    const plaintext = "sk-ant-api03-test-key-1234567890";
    const { encrypted, iv, tag } = encryptKey(plaintext, TEST_USER_A);
    const decrypted = decryptKey(encrypted, iv, tag, TEST_USER_A);
    expect(decrypted).toBe(plaintext);
  });

  test("base64 round-trip matches app data flow", () => {
    const plaintext = "sk-ant-api03-another-key";
    const { encrypted, iv, tag } = encryptKey(plaintext, TEST_USER_A);

    // Save path: Buffer -> base64 string (as stored in DB)
    const storedEncrypted = encrypted.toString("base64");
    const storedIv = iv.toString("base64");
    const storedTag = tag.toString("base64");

    // Read path: base64 string -> Buffer (as read from DB)
    const decrypted = decryptKey(
      Buffer.from(storedEncrypted, "base64"),
      Buffer.from(storedIv, "base64"),
      Buffer.from(storedTag, "base64"),
      TEST_USER_A,
    );
    expect(decrypted).toBe(plaintext);
  });
});

describe("HKDF per-user isolation", () => {
  test("different users produce different ciphertext for same plaintext", () => {
    const plaintext = "sk-ant-api03-shared-key";
    const resultA = encryptKey(plaintext, TEST_USER_A);
    const resultB = encryptKey(plaintext, TEST_USER_B);

    // Derived keys differ, so even if IVs happened to match, ciphertext would differ
    // But IVs are random too, so both encrypted outputs and IVs should differ
    expect(resultA.encrypted.equals(resultB.encrypted)).toBe(false);
  });

  test("decrypting with wrong user ID fails", () => {
    const plaintext = "sk-ant-api03-user-a-key";
    const { encrypted, iv, tag } = encryptKey(plaintext, TEST_USER_A);

    expect(() => decryptKey(encrypted, iv, tag, TEST_USER_B)).toThrow();
  });

  test("HKDF derivation is deterministic", () => {
    const plaintext = "sk-ant-api03-determinism-test";
    // Encrypt twice with same user — derived key is the same,
    // but ciphertext differs (random IV). Both decrypt correctly.
    const result1 = encryptKey(plaintext, TEST_USER_A);
    const result2 = encryptKey(plaintext, TEST_USER_A);

    expect(decryptKey(result1.encrypted, result1.iv, result1.tag, TEST_USER_A)).toBe(plaintext);
    expect(decryptKey(result2.encrypted, result2.iv, result2.tag, TEST_USER_A)).toBe(plaintext);
  });
});

describe("legacy decryption (v1 migration path)", () => {
  test("decryptKeyLegacy decrypts without HKDF (raw master key)", () => {
    // Simulate a v1 row: encrypted with raw master key (no userId)
    const masterKey = Buffer.from(
      "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
      "hex",
    );
    const plaintext = "sk-ant-api03-legacy-key";
    const iv = randomBytes(12);
    const cipher = createCipheriv("aes-256-gcm", masterKey, iv);
    const encrypted = Buffer.concat([
      cipher.update(plaintext, "utf8"),
      cipher.final(),
    ]);
    const tag = cipher.getAuthTag();

    const decrypted = decryptKeyLegacy(encrypted, iv, tag);
    expect(decrypted).toBe(plaintext);
  });

  test("v1 legacy key cannot be decrypted with HKDF-derived key", () => {
    const masterKey = Buffer.from(
      "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
      "hex",
    );
    const plaintext = "sk-ant-api03-legacy-key";
    const iv = randomBytes(12);
    const cipher = createCipheriv("aes-256-gcm", masterKey, iv);
    const encrypted = Buffer.concat([
      cipher.update(plaintext, "utf8"),
      cipher.final(),
    ]);
    const tag = cipher.getAuthTag();

    // HKDF-derived key should NOT decrypt a v1 row
    expect(() => decryptKey(encrypted, iv, tag, TEST_USER_A)).toThrow();
  });
});
