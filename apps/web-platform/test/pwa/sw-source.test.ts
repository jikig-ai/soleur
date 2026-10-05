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

  // --- CodeQL alert 203 (js/missing-origin-check) compensating control -----------------
  //
  // Alert 203 is dismissed as a false positive, NOT fixed. The reasoning:
  // `ServiceWorker.postMessage()` accepts no `targetOrigin`, so there is nothing to tighten
  // at the send site; only same-origin, in-scope clients can obtain a handle to this
  // registration; and the handler's entire effect is `self.skipWaiting()` — precisely what
  // the user's own Reload button does. No read, no write, no privilege change.
  //
  // Against that, adding an origin check is actively harmful: `event.origin` on
  // `ExtendableMessageEvent` is not uniformly populated across browsers, so a naive
  // predicate silently locks every user out of app updates with no feedback — a
  // feedback-free update lockout is strictly worse than the non-threat it would prevent.
  //
  // The dismissal is only defensible while the handler stays this small, so THIS is the
  // control that keeps it honest: if the handler ever gains a real capability, this fails
  // and forces the origin-check conversation onto the diff where it can be reasoned about.
  test("alert 203: the message handler's only effect is skipWaiting", () => {
    const start = SW.indexOf('self.addEventListener("message"');
    expect(start, "message handler not found — this control cannot run").toBeGreaterThan(-1);

    // Bounded slice. An unbounded one would swallow the following handlers and this
    // assertion would then be about the whole file, passing for the wrong reason.
    const rest = SW.slice(start);
    const end = rest.indexOf("\n});");
    expect(end, "could not find the handler's closing brace").toBeGreaterThan(-1);
    const handler = rest.slice(0, end);

    // Sanity-check the slice really is the handler, so the negative-space assertions below
    // cannot pass against an empty or mis-cut region.
    expect(handler).toContain('event.data.type === "SKIP_WAITING"');
    expect(handler).toContain("self.skipWaiting()");
    expect(handler.length).toBeLessThan(400);

    // Negative space: any of these would give the handler a capability worth an origin
    // check, at which point the dismissal must be revisited rather than inherited.
    for (const forbidden of [
      "fetch(",
      "caches.",
      "postMessage(",
      "indexedDB",
      "importScripts",
      "clients.openWindow",
      "registration.showNotification",
      "localStorage",
      "eval(",
    ]) {
      expect(
        handler.includes(forbidden),
        `sw.js message handler now calls \`${forbidden}\`. CodeQL alert 203 ` +
          "(js/missing-origin-check) was dismissed on the argument that this handler's only " +
          "effect is skipWaiting. That argument no longer holds — re-open the alert and " +
          "decide the origin check on this diff. See ADR-191.",
      ).toBe(false);
    }
  });
});
