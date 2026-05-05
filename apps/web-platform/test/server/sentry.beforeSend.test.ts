import { describe, it, expect } from "vitest";

import {
  scrubSentryEvent,
  scrubSentryBreadcrumb,
  SENTRY_SENSITIVE_KEYS,
} from "@/lib/sentry-scrub";

describe("scrubSentryEvent (beforeSend hook)", () => {
  it("strips x-nonce and cookie from request.headers", () => {
    const event = {
      request: {
        headers: {
          "x-nonce": "PLAINTEXT_NONCE",
          cookie: "PLAINTEXT_COOKIE",
          "user-agent": "test",
        },
      },
    };
    const out = scrubSentryEvent(event);
    expect(JSON.stringify(out)).not.toContain("PLAINTEXT_NONCE");
    expect(JSON.stringify(out)).not.toContain("PLAINTEXT_COOKIE");
    expect(JSON.stringify(out)).toContain("test");
  });

  it("strips apiKey, Authorization, encryptedKey, iv, auth_tag from request headers", () => {
    const event = {
      request: {
        headers: {
          apiKey: "PLAINTEXT_APIKEY",
          Authorization: "PLAINTEXT_AUTH",
          encryptedKey: "PLAINTEXT_ENC",
          iv: "PLAINTEXT_IV",
          auth_tag: "PLAINTEXT_TAG",
        },
      },
    };
    const out = scrubSentryEvent(event);
    const json = JSON.stringify(out);
    expect(json).not.toContain("PLAINTEXT_APIKEY");
    expect(json).not.toContain("PLAINTEXT_AUTH");
    expect(json).not.toContain("PLAINTEXT_ENC");
    expect(json).not.toContain("PLAINTEXT_IV");
    expect(json).not.toContain("PLAINTEXT_TAG");
  });

  it("strips sensitive keys at arbitrary nesting under contexts/extra/tags", () => {
    const event = {
      contexts: {
        byok: {
          apiKey: "PLAINTEXT_DEEP_APIKEY",
          encryptedKey: "PLAINTEXT_DEEP_ENC",
          iv: "PLAINTEXT_DEEP_IV",
          auth_tag: "PLAINTEXT_DEEP_TAG",
        },
        nested: {
          deeper: {
            Authorization: "PLAINTEXT_DEEP_AUTH",
          },
        },
      },
      extra: {
        request_payload: {
          api_key_field: "PLAINTEXT_EXTRA_VARIANT",
          apiKey: "PLAINTEXT_EXTRA_APIKEY",
        },
      },
      tags: {
        Authorization: "PLAINTEXT_TAGS_AUTH",
      },
    };
    const out = scrubSentryEvent(event);
    const json = JSON.stringify(out);
    expect(json).not.toContain("PLAINTEXT_DEEP_APIKEY");
    expect(json).not.toContain("PLAINTEXT_DEEP_ENC");
    expect(json).not.toContain("PLAINTEXT_DEEP_IV");
    expect(json).not.toContain("PLAINTEXT_DEEP_TAG");
    expect(json).not.toContain("PLAINTEXT_DEEP_AUTH");
    expect(json).not.toContain("PLAINTEXT_EXTRA_APIKEY");
    expect(json).not.toContain("PLAINTEXT_TAGS_AUTH");
  });

  it("preserves non-sensitive fields (negative-space guard)", () => {
    const event = {
      contexts: { app: { app_name: "soleur", app_version: "1.0" } },
      extra: { userId: "user-123", count: 42 },
    };
    const out = scrubSentryEvent(event);
    const json = JSON.stringify(out);
    expect(json).toContain("user-123");
    expect(json).toContain("soleur");
    expect(json).toContain("42");
  });

  it("returns the event so it can be passed through Sentry's hook contract", () => {
    const event = { message: "hello" };
    const out = scrubSentryEvent(event);
    expect(out).not.toBeNull();
    expect(out).toBeDefined();
  });
});

describe("scrubSentryBreadcrumb (beforeBreadcrumb hook)", () => {
  it("strips sensitive keys from breadcrumb.data", () => {
    const breadcrumb = {
      category: "http",
      data: {
        url: "https://api.example.com",
        Authorization: "PLAINTEXT_BC_AUTH",
        apiKey: "PLAINTEXT_BC_APIKEY",
        encryptedKey: "PLAINTEXT_BC_ENC",
        iv: "PLAINTEXT_BC_IV",
        auth_tag: "PLAINTEXT_BC_TAG",
      },
    };
    const out = scrubSentryBreadcrumb(breadcrumb);
    const json = JSON.stringify(out);
    expect(json).not.toContain("PLAINTEXT_BC_AUTH");
    expect(json).not.toContain("PLAINTEXT_BC_APIKEY");
    expect(json).not.toContain("PLAINTEXT_BC_ENC");
    expect(json).not.toContain("PLAINTEXT_BC_IV");
    expect(json).not.toContain("PLAINTEXT_BC_TAG");
    expect(json).toContain("https://api.example.com");
  });

  it("returns the breadcrumb so it can be passed through Sentry's hook contract", () => {
    const breadcrumb = { category: "ui.click", data: { target: "button" } };
    const out = scrubSentryBreadcrumb(breadcrumb);
    expect(out).not.toBeNull();
    expect(out).toBeDefined();
  });
});

describe("SENTRY_SENSITIVE_KEYS export", () => {
  it("includes the canonical sensitive key set", () => {
    const lower = SENTRY_SENSITIVE_KEYS.map((k) => k.toLowerCase());
    expect(lower).toContain("apikey");
    expect(lower).toContain("authorization");
    expect(lower).toContain("encryptedkey");
    expect(lower).toContain("iv");
    expect(lower).toContain("auth_tag");
  });
});
