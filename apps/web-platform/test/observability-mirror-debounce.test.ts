/**
 * mirrorWithDebounce — per-(userId, errorClass) 5-minute Sentry mirror coalescer.
 *
 * Extracted from `cc-dispatcher.ts` to `observability.ts` so other modules
 * (kb-document-resolver, soleur-go-runner.notifyAwaitingUser) can use the
 * same debounce without circular import (#3369 / #3040 Finding 2).
 *
 * Pins:
 *  - (a) first call mirrors;
 *  - (b) repeat call within 5min for same `(userId, errorClass)` is a no-op;
 *  - (c) call after 5min for the same key mirrors again;
 *  - (d) different `errorClass` for the same `userId` mirrors independently;
 *  - (e) different `userId` for the same `errorClass` mirrors independently.
 */
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";

const { mockCaptureException } = vi.hoisted(() => ({
  mockCaptureException: vi.fn(),
}));

vi.mock("@sentry/nextjs", () => ({
  captureException: mockCaptureException,
  captureMessage: vi.fn(),
  addBreadcrumb: vi.fn(),
}));

// Suppress pino stdout noise from reportSilentFallback's logger mirror.
vi.mock("@/server/logger", () => ({
  default: {
    error: vi.fn(),
    warn: vi.fn(),
    info: vi.fn(),
    debug: vi.fn(),
  },
}));

import {
  MIRROR_DEBOUNCE_MS,
  __resetMirrorDebounceForTests,
  mirrorWithDebounce,
} from "../server/observability";

beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(0);
  mockCaptureException.mockClear();
  __resetMirrorDebounceForTests();
});

afterEach(() => {
  vi.useRealTimers();
});

describe("mirrorWithDebounce — 5-minute per-(userId, errorClass) TTL", () => {
  test("(a) first call mirrors", () => {
    mirrorWithDebounce(new Error("kaboom"), { feature: "t" }, "user-A", "klass-X");
    expect(mockCaptureException).toHaveBeenCalledTimes(1);
  });

  test("(b) repeat call within 5 min for same key is a no-op", () => {
    mirrorWithDebounce(new Error("kaboom"), { feature: "t" }, "user-A", "klass-X");
    expect(mockCaptureException).toHaveBeenCalledTimes(1);

    vi.advanceTimersByTime(MIRROR_DEBOUNCE_MS - 1);
    mirrorWithDebounce(new Error("kaboom"), { feature: "t" }, "user-A", "klass-X");
    expect(mockCaptureException).toHaveBeenCalledTimes(1);
  });

  test("(c) call after 5 min for the same key mirrors again", () => {
    mirrorWithDebounce(new Error("kaboom"), { feature: "t" }, "user-A", "klass-X");
    vi.advanceTimersByTime(MIRROR_DEBOUNCE_MS);
    mirrorWithDebounce(new Error("kaboom"), { feature: "t" }, "user-A", "klass-X");
    expect(mockCaptureException).toHaveBeenCalledTimes(2);
  });

  test("(d) different errorClass for the same userId mirrors independently", () => {
    mirrorWithDebounce(new Error("a"), { feature: "t" }, "user-A", "klass-X");
    mirrorWithDebounce(new Error("b"), { feature: "t" }, "user-A", "klass-Y");
    expect(mockCaptureException).toHaveBeenCalledTimes(2);
  });

  test("(e) different userId for the same errorClass mirrors independently", () => {
    mirrorWithDebounce(new Error("a"), { feature: "t" }, "user-A", "klass-X");
    mirrorWithDebounce(new Error("b"), { feature: "t" }, "user-B", "klass-X");
    expect(mockCaptureException).toHaveBeenCalledTimes(2);
  });
});
