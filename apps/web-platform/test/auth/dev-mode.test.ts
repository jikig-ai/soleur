import { describe, it, expect, afterEach, vi } from "vitest";

import { isDevSignInEnabled } from "@/lib/auth/dev-mode";

afterEach(() => {
  vi.unstubAllEnvs();
});

describe("isDevSignInEnabled (R3 dev sign-in gate)", () => {
  it("returns false in production regardless of FLAG_DEV_SIGNIN", () => {
    vi.stubEnv("NODE_ENV", "production");
    vi.stubEnv("FLAG_DEV_SIGNIN", "1");
    expect(isDevSignInEnabled()).toBe(false);
  });

  it("returns false under NODE_ENV=test even with FLAG_DEV_SIGNIN=1 (strict === \"development\")", () => {
    // The strict literal guards against the !== "production" footgun documented
    // in 2026-04-13-supabase-env-var-dev-mode-graceful-degradation: under
    // NODE_ENV=test (vitest default), a `!= "production"` check fires and the
    // panel/route would render in SDK-mocked suites.
    vi.stubEnv("NODE_ENV", "test");
    vi.stubEnv("FLAG_DEV_SIGNIN", "1");
    expect(isDevSignInEnabled()).toBe(false);
  });

  it("returns false in development when FLAG_DEV_SIGNIN is unset", () => {
    vi.stubEnv("NODE_ENV", "development");
    vi.stubEnv("FLAG_DEV_SIGNIN", undefined);
    expect(isDevSignInEnabled()).toBe(false);
  });

  it("returns false in development when FLAG_DEV_SIGNIN is any non-\"1\" value", () => {
    vi.stubEnv("NODE_ENV", "development");
    vi.stubEnv("FLAG_DEV_SIGNIN", "true");
    expect(isDevSignInEnabled()).toBe(false);
    vi.stubEnv("FLAG_DEV_SIGNIN", "0");
    expect(isDevSignInEnabled()).toBe(false);
  });

  it("returns true only under NODE_ENV=development AND FLAG_DEV_SIGNIN=1", () => {
    vi.stubEnv("NODE_ENV", "development");
    vi.stubEnv("FLAG_DEV_SIGNIN", "1");
    expect(isDevSignInEnabled()).toBe(true);
  });
});
