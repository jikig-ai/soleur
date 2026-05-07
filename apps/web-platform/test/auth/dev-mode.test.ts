import { describe, it, expect, beforeEach, afterEach } from "vitest";

import { isDevSignInEnabled } from "@/lib/auth/dev-mode";

const ORIGINAL_ENV = process.env;

beforeEach(() => {
  process.env = { ...ORIGINAL_ENV };
});

afterEach(() => {
  process.env = ORIGINAL_ENV;
});

describe("isDevSignInEnabled (R3 dev sign-in gate)", () => {
  it("returns false in production regardless of FLAG_DEV_SIGNIN", () => {
    process.env.NODE_ENV = "production";
    process.env.FLAG_DEV_SIGNIN = "1";
    expect(isDevSignInEnabled()).toBe(false);
  });

  it("returns false under NODE_ENV=test even with FLAG_DEV_SIGNIN=1 (strict === \"development\")", () => {
    // The strict literal guards against the !== "production" footgun documented
    // in 2026-04-13-supabase-env-var-dev-mode-graceful-degradation: under
    // NODE_ENV=test (vitest default), a `!= "production"` check fires and the
    // panel/route would render in SDK-mocked suites.
    process.env.NODE_ENV = "test";
    process.env.FLAG_DEV_SIGNIN = "1";
    expect(isDevSignInEnabled()).toBe(false);
  });

  it("returns false in development when FLAG_DEV_SIGNIN is unset", () => {
    process.env.NODE_ENV = "development";
    delete process.env.FLAG_DEV_SIGNIN;
    expect(isDevSignInEnabled()).toBe(false);
  });

  it("returns false in development when FLAG_DEV_SIGNIN is any non-\"1\" value", () => {
    process.env.NODE_ENV = "development";
    process.env.FLAG_DEV_SIGNIN = "true";
    expect(isDevSignInEnabled()).toBe(false);
    process.env.FLAG_DEV_SIGNIN = "0";
    expect(isDevSignInEnabled()).toBe(false);
  });

  it("returns true only under NODE_ENV=development AND FLAG_DEV_SIGNIN=1", () => {
    process.env.NODE_ENV = "development";
    process.env.FLAG_DEV_SIGNIN = "1";
    expect(isDevSignInEnabled()).toBe(true);
  });
});
