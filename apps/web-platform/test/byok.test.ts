import { describe, test, expect } from "vitest";
import { encryptKey, decryptKey } from "../server/byok";

describe("BYOK encryption round-trip", () => {
  test("encrypts and decrypts a key correctly", () => {
    // Tests crypto primitives in isolation (Buffer-to-Buffer, no serialization)
    const plaintext = "sk-ant-api03-test-key-1234567890";
    const { encrypted, iv, tag } = encryptKey(plaintext);
    const decrypted = decryptKey(encrypted, iv, tag);
    expect(decrypted).toBe(plaintext);
  });

  test("base64 round-trip matches app data flow", () => {
    // Simulates the exact save/read path through Supabase:
    // route.ts writes Buffer.toString("base64") → DB stores text →
    // agent-runner.ts reads Buffer.from(text, "base64")
    const plaintext = "sk-ant-api03-another-key";
    const { encrypted, iv, tag } = encryptKey(plaintext);

    // Save path: Buffer → base64 string (as stored in DB)
    const storedEncrypted = encrypted.toString("base64");
    const storedIv = iv.toString("base64");
    const storedTag = tag.toString("base64");

    // Read path: base64 string → Buffer (as read from DB)
    const decrypted = decryptKey(
      Buffer.from(storedEncrypted, "base64"),
      Buffer.from(storedIv, "base64"),
      Buffer.from(storedTag, "base64"),
    );
    expect(decrypted).toBe(plaintext);
  });
});
