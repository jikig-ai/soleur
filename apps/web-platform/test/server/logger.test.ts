import { describe, it, expect } from "vitest";
import { Writable } from "node:stream";
import pino from "pino";

import { REDACT_PATHS } from "@/server/logger";

// Build a fresh pino instance pinned to the SUT's redact paths so the test
// asserts the exported allowlist directly — pino-pretty / dev transport is
// bypassed by writing JSON to an in-memory sink.
function loggerWithSink() {
  let captured = "";
  const sink = new Writable({
    write(chunk, _enc, cb) {
      captured += chunk.toString();
      cb();
    },
  });
  const logger = pino({ redact: REDACT_PATHS }, sink);
  return {
    logger,
    read: () => captured,
  };
}

describe("logger REDACT_PATHS", () => {
  it("strips apiKey, Authorization, encryptedKey, iv, auth_tag at top level", () => {
    const { logger, read } = loggerWithSink();
    logger.info(
      {
        apiKey: "PLAINTEXT_APIKEY_TOP",
        Authorization: "PLAINTEXT_AUTH_TOP",
        encryptedKey: "PLAINTEXT_ENC_TOP",
        iv: "PLAINTEXT_IV_TOP",
        auth_tag: "PLAINTEXT_TAG_TOP",
      },
      "secret-bearing log",
    );

    const out = read();
    expect(out).not.toContain("PLAINTEXT_APIKEY_TOP");
    expect(out).not.toContain("PLAINTEXT_AUTH_TOP");
    expect(out).not.toContain("PLAINTEXT_ENC_TOP");
    expect(out).not.toContain("PLAINTEXT_IV_TOP");
    expect(out).not.toContain("PLAINTEXT_TAG_TOP");
  });

  it("strips the same keys nested one level deep", () => {
    const { logger, read } = loggerWithSink();
    logger.info(
      {
        byok: {
          apiKey: "PLAINTEXT_APIKEY_NESTED",
          Authorization: "PLAINTEXT_AUTH_NESTED",
          encryptedKey: "PLAINTEXT_ENC_NESTED",
          iv: "PLAINTEXT_IV_NESTED",
          auth_tag: "PLAINTEXT_TAG_NESTED",
        },
      },
      "nested secret-bearing log",
    );

    const out = read();
    expect(out).not.toContain("PLAINTEXT_APIKEY_NESTED");
    expect(out).not.toContain("PLAINTEXT_AUTH_NESTED");
    expect(out).not.toContain("PLAINTEXT_ENC_NESTED");
    expect(out).not.toContain("PLAINTEXT_IV_NESTED");
    expect(out).not.toContain("PLAINTEXT_TAG_NESTED");
  });

  it("preserves existing req.headers redactions (x-nonce, cookie)", () => {
    const { logger, read } = loggerWithSink();
    logger.info(
      {
        req: {
          headers: {
            "x-nonce": "PLAINTEXT_NONCE",
            cookie: "PLAINTEXT_COOKIE",
          },
        },
      },
      "request log",
    );

    const out = read();
    expect(out).not.toContain("PLAINTEXT_NONCE");
    expect(out).not.toContain("PLAINTEXT_COOKIE");
  });

  it("does not redact unrelated fields (negative-space guard)", () => {
    const { logger, read } = loggerWithSink();
    logger.info({ userId: "user-123", count: 42 }, "non-secret log");

    const out = read();
    expect(out).toContain("user-123");
    expect(out).toContain("42");
  });
});
