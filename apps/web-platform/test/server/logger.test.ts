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
  const logger = pino({ redact: [...REDACT_PATHS] }, sink);
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

  it("strips the BYOK envelope shape returned by byok.encryptKey ({encrypted, iv, tag})", () => {
    const { logger, read } = loggerWithSink();
    logger.info(
      {
        encrypted: "PLAINTEXT_BYOK_ENCRYPTED",
        iv: "PLAINTEXT_BYOK_IV",
        tag: "PLAINTEXT_BYOK_TAG",
      },
      "byok envelope log",
    );
    const out = read();
    expect(out).not.toContain("PLAINTEXT_BYOK_ENCRYPTED");
    expect(out).not.toContain("PLAINTEXT_BYOK_IV");
    expect(out).not.toContain("PLAINTEXT_BYOK_TAG");
  });

  it("strips provider keys (api_key, x-api-key) and OAuth keys (token, access_token, refresh_token, bearer, client_secret) and password/secret/private_key", () => {
    const { logger, read } = loggerWithSink();
    logger.info(
      {
        api_key: "PLAINTEXT_PROVIDER_APIKEY",
        token: "PLAINTEXT_OAUTH_TOKEN",
        access_token: "PLAINTEXT_OAUTH_ACCESS",
        refresh_token: "PLAINTEXT_OAUTH_REFRESH",
        bearer: "PLAINTEXT_BEARER",
        client_secret: "PLAINTEXT_CLIENT_SECRET",
        password: "PLAINTEXT_PASSWORD",
        private_key: "PLAINTEXT_PRIVATE",
        secret: "PLAINTEXT_SECRET",
      },
      "provider keys log",
    );
    const out = read();
    for (const v of [
      "PLAINTEXT_PROVIDER_APIKEY",
      "PLAINTEXT_OAUTH_TOKEN",
      "PLAINTEXT_OAUTH_ACCESS",
      "PLAINTEXT_OAUTH_REFRESH",
      "PLAINTEXT_BEARER",
      "PLAINTEXT_CLIENT_SECRET",
      "PLAINTEXT_PASSWORD",
      "PLAINTEXT_PRIVATE",
      "PLAINTEXT_SECRET",
    ]) {
      expect(out).not.toContain(v);
    }
  });

  it("strips x-api-key and authorization at req.headers (canonical pino path)", () => {
    const { logger, read } = loggerWithSink();
    logger.info(
      {
        req: {
          headers: {
            "x-api-key": "PLAINTEXT_HEADER_APIKEY",
            authorization: "PLAINTEXT_HEADER_AUTH",
          },
        },
      },
      "request log",
    );
    const out = read();
    expect(out).not.toContain("PLAINTEXT_HEADER_APIKEY");
    expect(out).not.toContain("PLAINTEXT_HEADER_AUTH");
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
