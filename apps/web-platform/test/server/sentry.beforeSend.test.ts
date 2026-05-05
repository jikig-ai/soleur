import { describe, it, expect } from "vitest";

import {
  scrubSentryEvent,
  scrubSentryBreadcrumb,
  SENTRY_SENSITIVE_KEYS,
} from "@/server/sentry-scrub";

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

  it("strips the BYOK envelope shape returned by byok.encryptKey ({encrypted, iv, tag})", () => {
    // byok.ts returns { encrypted, iv, tag } — the prior scrubber list
    // covered `encryptedKey` / `auth_tag` (alt spellings) but missed the
    // real shape. Both spellings must be redacted.
    const event = {
      contexts: {
        byok_envelope: {
          encrypted: "PLAINTEXT_BYOK_ENCRYPTED",
          iv: "PLAINTEXT_BYOK_IV",
          tag: "PLAINTEXT_BYOK_TAG",
        },
        byok_legacy: {
          encryptedKey: "PLAINTEXT_BYOK_ENCKEY",
          auth_tag: "PLAINTEXT_BYOK_AUTHTAG",
        },
      },
    };
    const json = JSON.stringify(scrubSentryEvent(event));
    expect(json).not.toContain("PLAINTEXT_BYOK_ENCRYPTED");
    expect(json).not.toContain("PLAINTEXT_BYOK_IV");
    expect(json).not.toContain("PLAINTEXT_BYOK_TAG");
    expect(json).not.toContain("PLAINTEXT_BYOK_ENCKEY");
    expect(json).not.toContain("PLAINTEXT_BYOK_AUTHTAG");
  });

  it("strips provider-style API keys (api_key, x-api-key, apiKey)", () => {
    const event = {
      request: {
        headers: {
          apiKey: "PLAINTEXT_APIKEY_CAMEL",
          api_key: "PLAINTEXT_APIKEY_SNAKE",
          "x-api-key": "PLAINTEXT_APIKEY_HEADER",
        },
      },
    };
    const json = JSON.stringify(scrubSentryEvent(event));
    expect(json).not.toContain("PLAINTEXT_APIKEY_CAMEL");
    expect(json).not.toContain("PLAINTEXT_APIKEY_SNAKE");
    expect(json).not.toContain("PLAINTEXT_APIKEY_HEADER");
  });

  it("strips OAuth and password keys (token, access_token, refresh_token, password, client_secret, private_key, secret, bearer)", () => {
    const event = {
      contexts: {
        oauth: {
          token: "PLAINTEXT_TOKEN",
          access_token: "PLAINTEXT_ACCESS",
          refresh_token: "PLAINTEXT_REFRESH",
          bearer: "PLAINTEXT_BEARER",
          client_secret: "PLAINTEXT_CLIENT_SECRET",
        },
        creds: {
          password: "PLAINTEXT_PASSWORD",
          private_key: "PLAINTEXT_PRIVATE",
          secret: "PLAINTEXT_SECRET",
        },
      },
    };
    const json = JSON.stringify(scrubSentryEvent(event));
    expect(json).not.toContain("PLAINTEXT_TOKEN");
    expect(json).not.toContain("PLAINTEXT_ACCESS");
    expect(json).not.toContain("PLAINTEXT_REFRESH");
    expect(json).not.toContain("PLAINTEXT_BEARER");
    expect(json).not.toContain("PLAINTEXT_CLIENT_SECRET");
    expect(json).not.toContain("PLAINTEXT_PASSWORD");
    expect(json).not.toContain("PLAINTEXT_PRIVATE");
    expect(json).not.toContain("PLAINTEXT_SECRET");
  });

  it("strips Authorization (case variants) at arbitrary nesting", () => {
    const event = {
      contexts: {
        nested: {
          deeper: {
            Authorization: "PLAINTEXT_AUTH_PROPER",
            authorization: "PLAINTEXT_AUTH_LOWER",
          },
        },
      },
      tags: {
        Authorization: "PLAINTEXT_TAGS_AUTH",
      },
    };
    const json = JSON.stringify(scrubSentryEvent(event));
    expect(json).not.toContain("PLAINTEXT_AUTH_PROPER");
    expect(json).not.toContain("PLAINTEXT_AUTH_LOWER");
    expect(json).not.toContain("PLAINTEXT_TAGS_AUTH");
  });

  it("scrubs both branches of a shared sub-object (DAG correctness)", () => {
    // Regression: the prior WeakSet implementation returned the original
    // (un-scrubbed) value on the second visit of a shared object. A single
    // `error.cause` chain referenced from multiple breadcrumbs would
    // bypass redaction on every reference after the first.
    const sharedSecret = { apiKey: "PLAINTEXT_SHARED_APIKEY" };
    const event = {
      contexts: { branch_a: sharedSecret, branch_b: sharedSecret },
      extra: { branch_c: sharedSecret },
    };
    const out = scrubSentryEvent(event) as {
      contexts: {
        branch_a: { apiKey: string };
        branch_b: { apiKey: string };
      };
      extra: { branch_c: { apiKey: string } };
    };
    expect(out.contexts.branch_a.apiKey).toBe("[Redacted]");
    expect(out.contexts.branch_b.apiKey).toBe("[Redacted]");
    expect(out.extra.branch_c.apiKey).toBe("[Redacted]");
    expect(JSON.stringify(out)).not.toContain("PLAINTEXT_SHARED_APIKEY");
  });

  it("does not infinite-loop on cyclic event structures", () => {
    type Cyclic = { name: string; self?: Cyclic; apiKey: string };
    const cyclic: Cyclic = { name: "loop", apiKey: "PLAINTEXT_CYCLIC_APIKEY" };
    cyclic.self = cyclic;
    const out = scrubSentryEvent(cyclic) as { apiKey: string };
    expect(out.apiKey).toBe("[Redacted]");
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
        encrypted: "PLAINTEXT_BC_ENC",
        iv: "PLAINTEXT_BC_IV",
        tag: "PLAINTEXT_BC_TAG",
        token: "PLAINTEXT_BC_TOKEN",
        password: "PLAINTEXT_BC_PASSWORD",
      },
    };
    const json = JSON.stringify(scrubSentryBreadcrumb(breadcrumb));
    expect(json).not.toContain("PLAINTEXT_BC_AUTH");
    expect(json).not.toContain("PLAINTEXT_BC_APIKEY");
    expect(json).not.toContain("PLAINTEXT_BC_ENC");
    expect(json).not.toContain("PLAINTEXT_BC_IV");
    expect(json).not.toContain("PLAINTEXT_BC_TAG");
    expect(json).not.toContain("PLAINTEXT_BC_TOKEN");
    expect(json).not.toContain("PLAINTEXT_BC_PASSWORD");
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
  it("includes BYOK envelope (real + alt spellings)", () => {
    const lower = SENTRY_SENSITIVE_KEYS.map((k) => k.toLowerCase());
    expect(lower).toContain("encrypted");
    expect(lower).toContain("iv");
    expect(lower).toContain("tag");
    expect(lower).toContain("encryptedkey");
    expect(lower).toContain("auth_tag");
  });

  it("includes provider/OAuth/password keys", () => {
    const lower = SENTRY_SENSITIVE_KEYS.map((k) => k.toLowerCase());
    for (const k of [
      "apikey",
      "api_key",
      "x-api-key",
      "authorization",
      "bearer",
      "token",
      "access_token",
      "refresh_token",
      "password",
      "client_secret",
      "private_key",
      "secret",
      "cookie",
      "x-nonce",
    ]) {
      expect(lower).toContain(k);
    }
  });
});
