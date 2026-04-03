// @ts-nocheck — bun-only preload script; tsc does not resolve bun:test types
import { GlobalRegistrator } from "@happy-dom/global-registrator";

GlobalRegistrator.register();

// Must be after register() — but ES imports are hoisted, so we use
// dynamic imports via top-level await to guarantee execution order.
const { expect, afterEach } = await import("bun:test");
const matchers = await import("@testing-library/jest-dom/matchers");
const { cleanup } = await import("@testing-library/react");

expect.extend(matchers);

afterEach(() => {
  cleanup();
});
