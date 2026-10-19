import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

// #8211 T2 build 1 — quiet-window control (kill-switch for NEW agent sessions)
// and the counts-only live-session read.
//
// The flag read is mocked at the feature-flag boundary: the unit under test is
// the decision wrapper (absent/off allows, on refuses, a throwing read allows
// and is mirrored) and the reporter's output shape (counts only).

const { mockIsPaused, mockWarnSilentFallback, mockLogWarn } = vi.hoisted(() => ({
  mockIsPaused: vi.fn(),
  mockWarnSilentFallback: vi.fn(),
  mockLogWarn: vi.fn(),
}));

vi.mock("@/lib/feature-flags/server", () => ({
  isNewAgentSessionsPaused: mockIsPaused,
}));

vi.mock("@/server/observability", () => ({
  warnSilentFallback: mockWarnSilentFallback,
  reportSilentFallback: vi.fn(),
}));

vi.mock("@/server/logger", () => ({
  default: { info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() },
  createChildLogger: () => ({
    info: vi.fn(),
    warn: mockLogWarn,
    error: vi.fn(),
    debug: vi.fn(),
  }),
}));

import {
  QUIET_WINDOW_MESSAGE,
  newAgentSessionsRefused,
  formatLiveSessionsLine,
  startQuietWindowReporter,
} from "@/server/quiet-window";

describe("newAgentSessionsRefused", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("flag off/absent (read returns false) -> sessions allowed", async () => {
    mockIsPaused.mockResolvedValue(false);
    expect(await newAgentSessionsRefused()).toBe(false);
  });

  it("flag on -> refused", async () => {
    mockIsPaused.mockResolvedValue(true);
    expect(await newAgentSessionsRefused()).toBe(true);
  });

  it("a throwing flag read fails OPEN (sessions allowed) and is mirrored to Sentry", async () => {
    mockIsPaused.mockRejectedValue(new Error("flagsmith exploded"));
    expect(await newAgentSessionsRefused()).toBe(false);
    expect(mockWarnSilentFallback).toHaveBeenCalledTimes(1);
    expect(mockWarnSilentFallback.mock.calls[0][1]).toMatchObject({
      feature: "quiet-window",
    });
  });

  it("only a strict boolean true refuses (truthy non-boolean does not)", async () => {
    mockIsPaused.mockResolvedValue("1" as unknown as boolean);
    expect(await newAgentSessionsRefused()).toBe(false);
  });
});

describe("QUIET_WINDOW_MESSAGE", () => {
  it("is a maintenance message that tells the user existing work is safe and to retry", () => {
    expect(QUIET_WINDOW_MESSAGE).toMatch(/maintenance/i);
    expect(QUIET_WINDOW_MESSAGE).toMatch(/try again/i);
  });
});

describe("formatLiveSessionsLine (counts only)", () => {
  it("renders fixed key=value integers and the paused bit, nothing else", () => {
    const line = formatLiveSessionsLine(
      { ccQueries: 2, legacySessions: 1 },
      false,
    );
    expect(line).toBe(
      "agent_sessions_live=3 cc_queries=2 legacy_sessions=1 new_sessions_paused=0",
    );
  });

  it("paused=true renders new_sessions_paused=1", () => {
    expect(
      formatLiveSessionsLine({ ccQueries: 0, legacySessions: 0 }, true),
    ).toBe(
      "agent_sessions_live=0 cc_queries=0 legacy_sessions=0 new_sessions_paused=1",
    );
  });

  it("coerces a non-finite or negative reading to 0, never prints NaN or a sign", () => {
    const line = formatLiveSessionsLine(
      { ccQueries: Number.NaN, legacySessions: -4 },
      false,
    );
    expect(line).toBe(
      "agent_sessions_live=0 cc_queries=0 legacy_sessions=0 new_sessions_paused=0",
    );
  });

  it("matches the closed grammar for any input (no ids, no free text)", () => {
    const line = formatLiveSessionsLine(
      { ccQueries: 12, legacySessions: 7 },
      true,
    );
    expect(line).toMatch(
      /^agent_sessions_live=\d+ cc_queries=\d+ legacy_sessions=\d+ new_sessions_paused=[01]$/,
    );
  });
});

describe("startQuietWindowReporter", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.useFakeTimers();
  });
  afterEach(() => {
    vi.useRealTimers();
  });

  it("emits once at start and then on every interval, with the paused bit from the same resolution path as the gate", async () => {
    mockIsPaused.mockResolvedValue(true);
    const readCounts = vi.fn(() => ({ ccQueries: 1, legacySessions: 0 }));
    const timer = startQuietWindowReporter({ readCounts, intervalMs: 1000 });

    await vi.advanceTimersByTimeAsync(0);
    expect(mockLogWarn).toHaveBeenCalledTimes(1);
    expect(mockLogWarn.mock.calls[0][1]).toBe(
      "agent_sessions_live=1 cc_queries=1 legacy_sessions=0 new_sessions_paused=1",
    );

    await vi.advanceTimersByTimeAsync(2000);
    expect(mockLogWarn).toHaveBeenCalledTimes(3);
    clearInterval(timer);
  });

  it("the structured payload carries counts only (no user id, conversation id or content keys)", async () => {
    mockIsPaused.mockResolvedValue(false);
    const timer = startQuietWindowReporter({
      readCounts: () => ({ ccQueries: 4, legacySessions: 5 }),
      intervalMs: 1000,
    });
    await vi.advanceTimersByTimeAsync(0);
    const payload = mockLogWarn.mock.calls[0][0] as Record<string, unknown>;
    expect(Object.keys(payload).sort()).toEqual([
      "agentSessionsLive",
      "ccQueries",
      "legacySessions",
      "newSessionsPaused",
    ]);
    for (const v of Object.values(payload)) {
      expect(["number", "boolean"]).toContain(typeof v);
    }
    clearInterval(timer);
  });

  it("a throwing counts source never takes the process down and is mirrored", async () => {
    mockIsPaused.mockResolvedValue(false);
    const timer = startQuietWindowReporter({
      readCounts: () => {
        throw new Error("registry boom");
      },
      intervalMs: 1000,
    });
    await expect(vi.advanceTimersByTimeAsync(1000)).resolves.not.toThrow();
    expect(mockWarnSilentFallback).toHaveBeenCalled();
    expect(mockLogWarn).not.toHaveBeenCalled();
    clearInterval(timer);
  });

  it("a throwing flag read in the reporter still emits the counts with paused=0", async () => {
    mockIsPaused.mockRejectedValue(new Error("flagsmith down"));
    const timer = startQuietWindowReporter({
      readCounts: () => ({ ccQueries: 0, legacySessions: 0 }),
      intervalMs: 1000,
    });
    await vi.advanceTimersByTimeAsync(0);
    expect(mockLogWarn).toHaveBeenCalledTimes(1);
    expect(mockLogWarn.mock.calls[0][1]).toContain("new_sessions_paused=0");
    clearInterval(timer);
  });

  it("the interval is unref'd so it cannot block shutdown", () => {
    mockIsPaused.mockResolvedValue(false);
    const timer = startQuietWindowReporter({
      readCounts: () => ({ ccQueries: 0, legacySessions: 0 }),
      intervalMs: 1000,
    });
    // fake timers return a Timeout-like object; hasRef() false after unref().
    expect((timer as unknown as { hasRef: () => boolean }).hasRef()).toBe(false);
    clearInterval(timer);
  });
});
