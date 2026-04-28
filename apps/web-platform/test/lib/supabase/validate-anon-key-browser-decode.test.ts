// Reproduces the production browser-bundle environment by patching
// `Buffer.from(s, "base64url")` to throw `TypeError: Unknown encoding:
// base64url` — matching the older `buffer` npm polyfill webpack ships in
// client bundles. `atob` is native in Node 16+ and in browsers, so the
// validator's atob branch is exercised directly here.
//
// PR #3007 introduced `Buffer.from(middle, "base64url")` in
// `validate-anon-key.ts`. Vitest's default Node env hid the regression — Node
// 16+ has native base64url. Production browsers throw at module load, so every
// authenticated visitor saw the dashboard error.tsx until this test was added.
//
// The test is the GREEN gate for the browser-safe decoder. Removing the test
// would re-open the regression class.

import { describe, it, expect, beforeAll, afterAll, beforeEach, afterEach, vi } from "vitest";

const realBufferFrom = Buffer.from.bind(Buffer);
let originalBufferFrom: typeof Buffer.from;

beforeAll(() => {
  originalBufferFrom = Buffer.from;
  // Replace Buffer.from so calls with "base64url" throw, but other encodings still work.
  // Mirrors the `buffer@5.x` polyfill behavior that webpack ships for client bundles.
  Buffer.from = ((value: unknown, encoding?: BufferEncoding) => {
    if (encoding === ("base64url" as BufferEncoding)) {
      throw new TypeError("Unknown encoding: base64url");
    }
    return realBufferFrom(value as string, encoding);
  }) as typeof Buffer.from;
});

afterAll(() => {
  Buffer.from = originalBufferFrom;
});

const CANONICAL_URL = "https://ifsccnjhymdmidffkzhl.supabase.co";
const CANONICAL_REF = "ifsccnjhymdmidffkzhl";

// Hand-construct a JWT WITHOUT calling Buffer.from(_, "base64url") — that
// helper is what we just patched to throw.
function browserSafeBase64UrlEncode(str: string): string {
  return Buffer.from(str, "utf8")
    .toString("base64")
    .replace(/=/g, "")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");
}

function fakeJwt(payload: Record<string, unknown>): string {
  const header = browserSafeBase64UrlEncode('{"alg":"HS256","typ":"JWT"}');
  const body = browserSafeBase64UrlEncode(JSON.stringify(payload));
  return `${header}.${body}.fake-signature`;
}

describe("validate-anon-key under browser-polyfill Buffer", () => {
  beforeEach(() => {
    vi.stubEnv("NODE_ENV", "production");
  });

  afterEach(() => {
    vi.unstubAllEnvs();
  });

  it("decodes a canonical anon JWT without calling Buffer.from(_, 'base64url')", async () => {
    const { assertProdSupabaseAnonKey } = await import(
      "@/lib/supabase/validate-anon-key"
    );
    const jwt = fakeJwt({
      iss: "supabase",
      role: "anon",
      ref: CANONICAL_REF,
      iat: 1700000000,
      exp: 2000000000,
    });
    expect(() => assertProdSupabaseAnonKey(jwt, CANONICAL_URL)).not.toThrow();
  });

  it("rejects a service_role JWT (claim-check still runs after browser-safe decode)", async () => {
    const { assertProdSupabaseAnonKey } = await import(
      "@/lib/supabase/validate-anon-key"
    );
    const jwt = fakeJwt({
      iss: "supabase",
      role: "service_role",
      ref: CANONICAL_REF,
      iat: 1700000000,
      exp: 2000000000,
    });
    expect(() =>
      assertProdSupabaseAnonKey(jwt, CANONICAL_URL),
    ).toThrow(/role="service_role"/);
  });

  it("Buffer.from(_, 'base64url') is genuinely patched (sentinel — guards against accidental mock removal)", () => {
    expect(() => Buffer.from("dGVzdA", "base64url" as BufferEncoding)).toThrow(
      /Unknown encoding: base64url/,
    );
    // Other encodings still work.
    expect(Buffer.from("dGVzdA==", "base64").toString("utf8")).toBe("test");
  });
});
