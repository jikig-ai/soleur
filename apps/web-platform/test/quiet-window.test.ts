import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

// #8211 T2 build 1 — quiet-window control (kill-switch for NEW agent sessions)
// and the counts-only live-session read.
//
// The flag read is mocked at the feature-flag boundary: the unit under test is
// the decision wrapper (absent/off allows, on refuses, a throwing read allows
// and is mirrored) and the reporter's output shape (counts only).

const { mockIsPaused, mockWarnSilentFallback, mockInfoSilentFallback, mockLogWarn } = vi.hoisted(() => ({
  mockIsPaused: vi.fn(),
  mockWarnSilentFallback: vi.fn(),
  mockInfoSilentFallback: vi.fn(),
  mockLogWarn: vi.fn(),
}));

vi.mock("@/lib/feature-flags/server", () => ({
  isNewAgentSessionsPaused: mockIsPaused,
}));

vi.mock("@/server/observability", () => ({
  warnSilentFallback: mockWarnSilentFallback,
  infoSilentFallback: mockInfoSilentFallback,
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
  trackSessionStart,
  inFlightStartCount,
  __resetQuietWindowCountersForTests,
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

// #8211 rehearsal: ONE configured synthetic account passes the pause. Everything else stays refused.
describe("newAgentSessionsRefused: the single exempt synthetic account", () => {
  const EXEMPT = "0b8f6f1e-3c1d-4a53-9a55-5b6f7c8d9e01";
  const OTHER = "1c9a7a2f-4d2e-4b64-8b66-6c7a8d9e0f12";
  const original = process.env.QUIET_WINDOW_EXEMPT_USER_ID;

  beforeEach(() => {
    vi.clearAllMocks();
    __resetQuietWindowCountersForTests();
    mockIsPaused.mockResolvedValue(true);
    process.env.QUIET_WINDOW_EXEMPT_USER_ID = EXEMPT;
  });
  afterEach(() => {
    if (original === undefined) delete process.env.QUIET_WINDOW_EXEMPT_USER_ID;
    else process.env.QUIET_WINDOW_EXEMPT_USER_ID = original;
  });

  it("pause on: the exempt id passes, mirrored once with the raw id left to the emit-boundary hash", async () => {
    expect(await newAgentSessionsRefused({ userId: EXEMPT })).toBe(false);
    expect(mockInfoSilentFallback).toHaveBeenCalledTimes(1);
    expect(mockInfoSilentFallback.mock.calls[0][1]).toMatchObject({
      feature: "quiet-window",
      op: "exempt-pass",
      extra: { userId: EXEMPT },
    });
  });

  it("pause on: any other id is refused and counted", async () => {
    expect(await newAgentSessionsRefused({ userId: OTHER })).toBe(true);
    expect(mockInfoSilentFallback).not.toHaveBeenCalled();
  });

  it("pause on: a call with no userId (the reporter read, auto-sync) is never exempt", async () => {
    expect(await newAgentSessionsRefused()).toBe(true);
    expect(await newAgentSessionsRefused({ observe: true })).toBe(true);
    expect(await newAgentSessionsRefused({ userId: undefined })).toBe(true);
  });

  it.each([
    ["uppercase", EXEMPT.toUpperCase()],
    ["prefix", EXEMPT.slice(0, 35)],
    ["suffix", `${EXEMPT}0`],
    ["leading space", ` ${EXEMPT}`],
    ["trailing space", `${EXEMPT} `],
    ["empty", ""],
  ])("pause on: a near-miss id (%s) is refused", async (_n, id) => {
    expect(await newAgentSessionsRefused({ userId: id })).toBe(true);
  });

  it.each([
    ["absent", undefined],
    ["empty", ""],
    ["whitespace around the id", ` ${EXEMPT} `],
    ["uppercase id", EXEMPT.toUpperCase()],
    ["a list of two", `${EXEMPT},${OTHER}`],
    ["not a uuid", "synthetic"],
  ])("malformed or absent config (%s) exempts nobody, not even the id it names", async (_n, cfg) => {
    if (cfg === undefined) delete process.env.QUIET_WINDOW_EXEMPT_USER_ID;
    else process.env.QUIET_WINDOW_EXEMPT_USER_ID = cfg;
    expect(await newAgentSessionsRefused({ userId: EXEMPT })).toBe(true);
    expect(await newAgentSessionsRefused({ userId: OTHER })).toBe(true);
  });

  it("pause off: allowed with no exemption event", async () => {
    mockIsPaused.mockResolvedValue(false);
    expect(await newAgentSessionsRefused({ userId: EXEMPT })).toBe(false);
    expect(mockInfoSilentFallback).not.toHaveBeenCalled();
  });

  it("an observe read by the exempt id passes without emitting an event", async () => {
    expect(await newAgentSessionsRefused({ observe: true, userId: EXEMPT })).toBe(false);
    expect(mockInfoSilentFallback).not.toHaveBeenCalled();
  });

  it("an exempt pass is not a refusal: refused_since_last stays 0 while a real refusal counts", async () => {
    await newAgentSessionsRefused({ userId: EXEMPT });
    vi.useFakeTimers();
    try {
      const timer = startQuietWindowReporter({ readCounts: () => ({ ccQueries: 0, legacySessions: 0 }) });
      await vi.advanceTimersByTimeAsync(0);
      expect(mockLogWarn.mock.calls.at(-1)?.[1]).toMatch(/new_sessions_paused=1 refused_since_last=0$/);
      await newAgentSessionsRefused({ userId: OTHER });
      await vi.advanceTimersByTimeAsync(60_000);
      expect(mockLogWarn.mock.calls.at(-1)?.[1]).toMatch(/new_sessions_paused=1 refused_since_last=1$/);
      clearInterval(timer);
    } finally {
      vi.useRealTimers();
    }
  });

  it("a throwing flag read still fails OPEN for everyone (unchanged) and mirrors once", async () => {
    mockIsPaused.mockRejectedValue(new Error("flagsmith exploded"));
    expect(await newAgentSessionsRefused({ userId: OTHER })).toBe(false);
    expect(mockWarnSilentFallback).toHaveBeenCalledTimes(1);
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
      "agent_sessions_live=3 cc_queries=2 legacy_sessions=1 starting=0 new_sessions_paused=0 refused_since_last=0",
    );
  });

  it("paused=true renders new_sessions_paused=1", () => {
    expect(
      formatLiveSessionsLine({ ccQueries: 0, legacySessions: 0 }, true),
    ).toBe(
      "agent_sessions_live=0 cc_queries=0 legacy_sessions=0 starting=0 new_sessions_paused=1 refused_since_last=0",
    );
  });

  it("coerces a non-finite or negative reading to 0, never prints NaN or a sign", () => {
    const line = formatLiveSessionsLine(
      { ccQueries: Number.NaN, legacySessions: -4 },
      false,
    );
    expect(line).toBe(
      "agent_sessions_live=0 cc_queries=0 legacy_sessions=0 starting=0 new_sessions_paused=0 refused_since_last=0",
    );
  });

  it("matches the closed grammar for any input (no ids, no free text)", () => {
    const line = formatLiveSessionsLine(
      { ccQueries: 12, legacySessions: 7 },
      true,
    );
    expect(line).toMatch(
      /^agent_sessions_live=\d+ cc_queries=\d+ legacy_sessions=\d+ starting=\d+ new_sessions_paused=[01] refused_since_last=\d+$/,
    );
  });
});

describe("startQuietWindowReporter", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    __resetQuietWindowCountersForTests();
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
      "agent_sessions_live=1 cc_queries=1 legacy_sessions=0 starting=0 new_sessions_paused=1 refused_since_last=0",
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
      "refusedSinceLast",
      "startingSessions",
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

describe("in-flight starts and refusal counts (review P2)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    __resetQuietWindowCountersForTests();
    vi.useFakeTimers();
  });
  afterEach(() => {
    vi.useRealTimers();
  });

  it("trackSessionStart counts until released; release is idempotent and never goes negative", () => {
    const base = inFlightStartCount();
    const r1 = trackSessionStart();
    const r2 = trackSessionStart();
    expect(inFlightStartCount()).toBe(base + 2);
    r1();
    r1();
    expect(inFlightStartCount()).toBe(base + 1);
    r2();
    expect(inFlightStartCount()).toBe(base);
  });

  it("a start that passed the gate but has not registered keeps agent_sessions_live above 0 in the emitted line", async () => {
    mockIsPaused.mockResolvedValue(true);
    const release = trackSessionStart();
    const timer = startQuietWindowReporter({
      readCounts: () => ({ ccQueries: 0, legacySessions: 0 }),
      intervalMs: 1000,
    });
    await vi.advanceTimersByTimeAsync(0);
    expect(String(mockLogWarn.mock.calls[0][1])).toMatch(/^agent_sessions_live=[1-9]\d* cc_queries=0 legacy_sessions=0 starting=[1-9]\d* /);
    release();
    clearInterval(timer);
  });

  it("refused_since_last counts real refusals, resets on each emit, and the reporter's own read is not a refusal", async () => {
    mockIsPaused.mockResolvedValue(true);
    await newAgentSessionsRefused();
    await newAgentSessionsRefused();
    const timer = startQuietWindowReporter({
      readCounts: () => ({ ccQueries: 0, legacySessions: 0 }),
      intervalMs: 1000,
    });
    await vi.advanceTimersByTimeAsync(0);
    expect(String(mockLogWarn.mock.calls[0][1])).toMatch(/refused_since_last=2$/);
    await vi.advanceTimersByTimeAsync(1000);
    expect(String(mockLogWarn.mock.calls[1][1])).toMatch(/refused_since_last=0$/);
    clearInterval(timer);
  });
});

describe("payload values and line grammar (review P2)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    __resetQuietWindowCountersForTests();
    vi.useFakeTimers();
  });
  afterEach(() => {
    vi.useRealTimers();
  });

  it("the structured payload carries the SAME values as the message line (sum, paused bit, starting)", async () => {
    mockIsPaused.mockResolvedValue(true);
    const release = trackSessionStart();
    const timer = startQuietWindowReporter({
      readCounts: () => ({ ccQueries: 2, legacySessions: 1 }),
      intervalMs: 1000,
    });
    await vi.advanceTimersByTimeAsync(0);
    expect(mockLogWarn.mock.calls[0][0]).toEqual({
      agentSessionsLive: 4,
      ccQueries: 2,
      legacySessions: 1,
      startingSessions: 1,
      newSessionsPaused: true,
      refusedSinceLast: 0,
    });
    expect(mockLogWarn.mock.calls[0][1]).toBe(
      "agent_sessions_live=4 cc_queries=2 legacy_sessions=1 starting=1 new_sessions_paused=1 refused_since_last=0",
    );
    release();
    clearInterval(timer);
  });

  it("every hostile numeric reading renders as a plain non-negative integer (grammar table)", () => {
    const grammar =
      /^agent_sessions_live=\d+ cc_queries=\d+ legacy_sessions=\d+ starting=\d+ new_sessions_paused=[01] refused_since_last=\d+$/;
    const hostile: unknown[] = [1.5, Number.POSITIVE_INFINITY, Number.NEGATIVE_INFINITY, Number.MAX_SAFE_INTEGER + 2, "7", null, undefined, -0, 1e21];
    for (const v of hostile) {
      const line = formatLiveSessionsLine(
        {
          ccQueries: v as number,
          legacySessions: v as number,
          startingSessions: v as number,
          refusedSinceLast: v as number,
        },
        false,
      );
      expect(line, `input ${String(v)}`).toMatch(grammar);
      expect(line).not.toMatch(/Infinity|NaN|\.|e\+|-/);
    }
  });
});

