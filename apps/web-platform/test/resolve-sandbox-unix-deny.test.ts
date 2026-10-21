// #10455 (a) / A4, A6(c) — resolveSandboxUnixDeny is awaited before every query, so it must fail closed to OFF AND stay off
// the hot path: memoised for the flag-cache horizon (a failed read is negative-cached), concurrent callers share one
// read, and the per-read bound is 300 ms (the SDK's first attempt aborts at 200 ms; waiting longer only waits for its
// 1 s retry delay).
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

const flag = vi.hoisted(() => ({ isAgentSandboxUnixDenyEnabled: vi.fn() }));
const obs = vi.hoisted(() => ({ mirrorWarnWithDebounce: vi.fn() }));

vi.mock("@/lib/feature-flags/server", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/lib/feature-flags/server")>()),
  isAgentSandboxUnixDenyEnabled: flag.isAgentSandboxUnixDenyEnabled,
}));
vi.mock("@/server/observability", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/observability")>()),
  mirrorWarnWithDebounce: obs.mirrorWarnWithDebounce,
}));

import {
  MEMO_TTL_MS,
  RESOLVE_TIMEOUT_MS,
  __resetResolveMemoForTests,
  resolveSandboxUnixDeny,
} from "@/server/resolve-sandbox-unix-deny";

const HANG = () => new Promise<boolean>(() => {});

describe("resolveSandboxUnixDeny", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(1_000_000);
    __resetResolveMemoForTests();
    flag.isAgentSandboxUnixDenyEnabled.mockReset();
    obs.mirrorWarnWithDebounce.mockReset();
  });
  afterEach(() => {
    vi.useRealTimers();
  });

  it("the constants: a 300 ms read bound and a 30 s memo, both pinned by value", () => {
    expect(RESOLVE_TIMEOUT_MS).toBe(300);
    expect(MEMO_TTL_MS).toBe(30_000);
  });

  it("true only when the flag service answers exactly true", async () => {
    for (const [answer, want] of [
      [true, true],
      [false, false],
      [undefined, false],
      ["true", false],
      [1, false],
    ] as const) {
      __resetResolveMemoForTests();
      flag.isAgentSandboxUnixDenyEnabled.mockResolvedValueOnce(answer);
      expect(await resolveSandboxUnixDeny(), String(answer)).toBe(want);
    }
  });

  it("a thrown error resolves OFF and is mirrored once with the pinned warn shape", async () => {
    const boom = new Error("flagsmith down");
    flag.isAgentSandboxUnixDenyEnabled.mockRejectedValueOnce(boom);
    expect(await resolveSandboxUnixDeny()).toBe(false);
    expect(obs.mirrorWarnWithDebounce).toHaveBeenCalledTimes(1);
    expect(obs.mirrorWarnWithDebounce).toHaveBeenCalledWith(
      boom,
      {
        feature: "agent-sandbox",
        op: "unix-deny-flag-unresolved",
        message: "agent-sandbox-unix-deny flag unresolved; using the base seccomp artifact for this query",
      },
      "global",
      "agent-sandbox-unix-deny-unresolved",
    );
  });

  it("the DEFAULT bound is RESOLVE_TIMEOUT_MS: a hang resolves OFF at 300 ms, not before and not at 2 s", async () => {
    flag.isAgentSandboxUnixDenyEnabled.mockImplementation(HANG);
    let settled: boolean | undefined;
    const p = resolveSandboxUnixDeny().then((v) => (settled = v));
    await vi.advanceTimersByTimeAsync(299);
    expect(settled).toBeUndefined();
    await vi.advanceTimersByTimeAsync(1);
    await p;
    expect(settled).toBe(false);
    expect(obs.mirrorWarnWithDebounce).toHaveBeenCalledTimes(1);
    expect(String((obs.mirrorWarnWithDebounce.mock.calls[0][0] as Error).message)).toMatch(/timed out/);
  });

  it("an explicit timeout argument still wins over the default", async () => {
    flag.isAgentSandboxUnixDenyEnabled.mockImplementation(HANG);
    const p = resolveSandboxUnixDeny(25);
    await vi.advanceTimersByTimeAsync(25);
    expect(await p).toBe(false);
  });

  it("healthy path: after the first read the memo answers without touching the flag service or any timer", async () => {
    flag.isAgentSandboxUnixDenyEnabled.mockResolvedValue(true);
    // Baseline BEFORE the first call: the race timer must be cleared once the read settles (removing clearTimeout reds).
    const timersBaseline = vi.getTimerCount();
    expect(await resolveSandboxUnixDeny()).toBe(true);
    expect(vi.getTimerCount()).toBe(timersBaseline);
    for (let i = 0; i < 50; i++) expect(await resolveSandboxUnixDeny()).toBe(true);
    expect(flag.isAgentSandboxUnixDenyEnabled).toHaveBeenCalledTimes(1);
    expect(vi.getTimerCount()).toBe(timersBaseline);
  });

  it("a backward wall-clock step does not hold an ON memo past its TTL window (age >= 0 guard)", async () => {
    flag.isAgentSandboxUnixDenyEnabled.mockResolvedValueOnce(true).mockResolvedValueOnce(false);
    expect(await resolveSandboxUnixDeny()).toBe(true);
    // Clock steps back 1 h: age is negative; the memo must be treated as expired and the flag re-read.
    vi.setSystemTime(1_000_000 - 3_600_000);
    expect(await resolveSandboxUnixDeny()).toBe(false);
    expect(flag.isAgentSandboxUnixDenyEnabled).toHaveBeenCalledTimes(2);
  });

  it("the memo expires after MEMO_TTL_MS and the next call re-reads (a flip reaches new queries)", async () => {
    flag.isAgentSandboxUnixDenyEnabled.mockResolvedValueOnce(true).mockResolvedValueOnce(false);
    expect(await resolveSandboxUnixDeny()).toBe(true);
    vi.setSystemTime(1_000_000 + MEMO_TTL_MS - 1);
    expect(await resolveSandboxUnixDeny()).toBe(true);
    expect(flag.isAgentSandboxUnixDenyEnabled).toHaveBeenCalledTimes(1);
    vi.setSystemTime(1_000_000 + MEMO_TTL_MS);
    expect(await resolveSandboxUnixDeny()).toBe(false);
    expect(flag.isAgentSandboxUnixDenyEnabled).toHaveBeenCalledTimes(2);
  });

  it("degraded flag service: the 300 ms bound is paid once per TTL window, not per turn (negative cache)", async () => {
    flag.isAgentSandboxUnixDenyEnabled.mockImplementation(HANG);
    const first = resolveSandboxUnixDeny();
    await vi.advanceTimersByTimeAsync(RESOLVE_TIMEOUT_MS);
    expect(await first).toBe(false);
    // 20 further turns inside the window: instant, no new read, no new timer, no new warning.
    const timersBefore = vi.getTimerCount();
    for (let i = 0; i < 20; i++) expect(await resolveSandboxUnixDeny()).toBe(false);
    expect(flag.isAgentSandboxUnixDenyEnabled).toHaveBeenCalledTimes(1);
    expect(vi.getTimerCount()).toBe(timersBefore);
    expect(obs.mirrorWarnWithDebounce).toHaveBeenCalledTimes(1);
    // The next window pays the bound once more.
    vi.setSystemTime(1_000_000 + MEMO_TTL_MS + RESOLVE_TIMEOUT_MS);
    const second = resolveSandboxUnixDeny();
    await vi.advanceTimersByTimeAsync(RESOLVE_TIMEOUT_MS);
    expect(await second).toBe(false);
    expect(flag.isAgentSandboxUnixDenyEnabled).toHaveBeenCalledTimes(2);
  });

  it("concurrent callers share ONE read (single-flight), including the degraded case", async () => {
    let release!: (v: boolean) => void;
    flag.isAgentSandboxUnixDenyEnabled.mockImplementation(() => new Promise<boolean>((r) => (release = r)));
    const calls = Array.from({ length: 8 }, () => resolveSandboxUnixDeny());
    await vi.advanceTimersByTimeAsync(0);
    release(true);
    expect(await Promise.all(calls)).toEqual(Array(8).fill(true));
    expect(flag.isAgentSandboxUnixDenyEnabled).toHaveBeenCalledTimes(1);

    __resetResolveMemoForTests();
    flag.isAgentSandboxUnixDenyEnabled.mockReset();
    flag.isAgentSandboxUnixDenyEnabled.mockImplementation(HANG);
    const degraded = Array.from({ length: 8 }, () => resolveSandboxUnixDeny());
    await vi.advanceTimersByTimeAsync(RESOLVE_TIMEOUT_MS);
    expect(await Promise.all(degraded)).toEqual(Array(8).fill(false));
    expect(flag.isAgentSandboxUnixDenyEnabled).toHaveBeenCalledTimes(1);
  });

  it("the in-flight slot is released: a read that settles does not wedge later windows", async () => {
    flag.isAgentSandboxUnixDenyEnabled.mockResolvedValueOnce(false).mockResolvedValueOnce(true);
    expect(await resolveSandboxUnixDeny()).toBe(false);
    vi.setSystemTime(1_000_000 + MEMO_TTL_MS + 1);
    expect(await resolveSandboxUnixDeny()).toBe(true);
  });
});
