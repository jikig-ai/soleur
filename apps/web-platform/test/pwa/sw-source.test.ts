import { readFileSync } from "fs";
import { resolve } from "path";
import { describe, test, expect } from "vitest";

// Source-level invariants on public/sw.js. The service worker runs in the
// browser SW scope (no importable module), so these guard the load-bearing
// text: cache version, offline precache, no silent skipWaiting, the SKIP_WAITING
// message listener, the navigate fallback, and the #3002 cache.put guard.
const SW = readFileSync(resolve(__dirname, "../../public/sw.js"), "utf8");

describe("public/sw.js invariants", () => {
  test("CACHE_NAME bumped to v10 (purges old-version caches on activate)", () => {
    expect(SW).toContain('const CACHE_NAME = "soleur-app-shell-v10"');
  });

  test("/offline.html is precached in SHELL_ASSETS", () => {
    const shell = SW.match(/const SHELL_ASSETS = \[([\s\S]*?)\]/);
    expect(shell).not.toBeNull();
    expect(shell![1]).toContain('"/offline.html"');
  });

  test("install handler does NOT call skipWaiting (new workers wait)", () => {
    const install = SW.match(/addEventListener\("install"[\s\S]*?\}\);/);
    expect(install).not.toBeNull();
    expect(install![0]).not.toContain("skipWaiting");
  });

  test("a message listener activates the waiting worker on SKIP_WAITING", () => {
    expect(SW).toContain('addEventListener("message"');
    expect(SW).toContain('event.data.type === "SKIP_WAITING"');
    expect(SW).toContain("self.skipWaiting()");
  });

  test("activate still claims clients", () => {
    expect(SW).toContain("self.clients.claim()");
  });

  test("navigate requests fall back to the offline shell (catch-only, never on response.ok)", () => {
    expect(SW).toContain('event.request.mode === "navigate"');
    expect(SW).toContain('fetch(event.request).catch(() => caches.match("/offline.html"))');
  });

  test("#3002: cache.put is guarded against quota failures", () => {
    // The cache-first asset branch must swallow a failed cache.put.
    expect(SW).toMatch(/cache\.put\(event\.request, clone\)\)\s*\.catch\(\(\) => \{\}\)/);
  });

  test("#3002: global error + unhandledrejection handlers are present", () => {
    expect(SW).toContain('addEventListener("error"');
    expect(SW).toContain('addEventListener("unhandledrejection"');
  });

  test("push + notificationclick handlers are preserved", () => {
    expect(SW).toContain('addEventListener("push"');
    expect(SW).toContain('addEventListener("notificationclick"');
  });
});
