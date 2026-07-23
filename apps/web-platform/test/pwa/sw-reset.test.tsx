// happy-dom (via .test.tsx include) — sw-reset.ts touches window/navigator/caches.
import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";
import {
  SW_RESET_PARAM,
  hasSwResetFlag,
  unregisterAllAndClearCaches,
  cleanResetUrl,
} from "@/lib/pwa/sw-reset";

describe("hasSwResetFlag", () => {
  test("true when ?sw-reset is present", () => {
    expect(hasSwResetFlag("?sw-reset")).toBe(true);
    expect(hasSwResetFlag("?foo=1&sw-reset=1")).toBe(true);
  });
  test("false when absent", () => {
    expect(hasSwResetFlag("")).toBe(false);
    expect(hasSwResetFlag("?foo=1")).toBe(false);
  });
});

describe("cleanResetUrl", () => {
  test("strips the sw-reset param, preserving path + other query + hash", () => {
    expect(cleanResetUrl("https://app.soleur.ai/dashboard?sw-reset=1")).toBe("/dashboard");
    expect(cleanResetUrl("https://app.soleur.ai/login?next=/x&sw-reset=1#top")).toBe(
      "/login?next=%2Fx#top",
    );
  });
  test("no-op when the param is absent", () => {
    expect(cleanResetUrl("https://app.soleur.ai/dashboard?a=b")).toBe("/dashboard?a=b");
  });
});

describe("unregisterAllAndClearCaches", () => {
  const originalNavigator = globalThis.navigator;

  afterEach(() => {
    Object.defineProperty(globalThis, "navigator", {
      value: originalNavigator,
      configurable: true,
      writable: true,
    });
    vi.restoreAllMocks();
    // @ts-expect-error test cleanup
    delete globalThis.caches;
  });

  test("unregisters every worker and deletes every cache", async () => {
    const unregister = vi.fn().mockResolvedValue(true);
    Object.defineProperty(globalThis, "navigator", {
      value: {
        serviceWorker: {
          getRegistrations: vi.fn().mockResolvedValue([{ unregister }, { unregister }]),
        },
      },
      configurable: true,
      writable: true,
    });
    const cacheDelete = vi.fn().mockResolvedValue(true);
    // @ts-expect-error minimal CacheStorage stub
    globalThis.caches = {
      keys: vi.fn().mockResolvedValue(["soleur-app-shell-v10", "old"]),
      delete: cacheDelete,
    };

    await unregisterAllAndClearCaches();

    expect(unregister).toHaveBeenCalledTimes(2);
    expect(cacheDelete).toHaveBeenCalledWith("soleur-app-shell-v10");
    expect(cacheDelete).toHaveBeenCalledWith("old");
  });
});

describe("SW_RESET_PARAM", () => {
  test("is the stable sw-reset key", () => {
    expect(SW_RESET_PARAM).toBe("sw-reset");
  });
});
