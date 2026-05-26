import {
  describe,
  it,
  expect,
  vi,
  afterEach,
  beforeEach,
  type MockInstance,
} from "vitest";

vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
  warnSilentFallback: vi.fn(),
}));

describe("assertSingleReplicaInvariant", () => {
  let exitSpy: MockInstance<(code?: string | number | null) => never>;

  beforeEach(() => {
    exitSpy = vi
      .spyOn(process, "exit")
      .mockImplementation(((code?: number) => {
        throw new Error(`process.exit(${code ?? 0})`);
      }) as never);
  });

  afterEach(() => {
    vi.resetModules();
    vi.unstubAllEnvs();
    vi.clearAllMocks();
    exitSpy.mockRestore();
  });

  async function loadModule() {
    return import("@/server/single-replica-assertion");
  }

  it("no-ops when WEB_PLATFORM_REPLICAS is unset", async () => {
    // vi.unstubAllEnvs() in afterEach guarantees no carry-over; we explicitly
    // delete the host-shell value so a developer with the var exported in
    // their shell doesn't get a silently-different test result.
    vi.stubEnv("WEB_PLATFORM_REPLICAS", undefined as never);
    const { assertSingleReplicaInvariant } = await loadModule();
    const observability = await import("@/server/observability");

    expect(() => assertSingleReplicaInvariant()).not.toThrow();
    expect(exitSpy).not.toHaveBeenCalled();
    // Proves early-return: no observability call when env is unset.
    expect(observability.reportSilentFallback).not.toHaveBeenCalled();
    expect(observability.warnSilentFallback).not.toHaveBeenCalled();
  });

  it("no-ops when WEB_PLATFORM_REPLICAS=1", async () => {
    vi.stubEnv("WEB_PLATFORM_REPLICAS", "1");
    const { assertSingleReplicaInvariant } = await loadModule();
    const observability = await import("@/server/observability");

    expect(() => assertSingleReplicaInvariant()).not.toThrow();
    expect(exitSpy).not.toHaveBeenCalled();
    expect(observability.reportSilentFallback).not.toHaveBeenCalled();
    expect(observability.warnSilentFallback).not.toHaveBeenCalled();
  });

  it("aborts boot (process.exit(1)) when WEB_PLATFORM_REPLICAS=3 without override", async () => {
    vi.stubEnv("WEB_PLATFORM_REPLICAS", "3");
    const { assertSingleReplicaInvariant } = await loadModule();
    const observability = await import("@/server/observability");

    expect(() => assertSingleReplicaInvariant()).toThrowError(/process\.exit\(1\)/);
    expect(exitSpy).toHaveBeenCalledWith(1);

    expect(observability.reportSilentFallback).toHaveBeenCalledTimes(1);
    const call = vi.mocked(observability.reportSilentFallback).mock.calls[0];
    expect(call[1].feature).toBe("single-replica-assertion");
    expect(call[1].message).toMatch(/ADR-027/);
    expect(call[1].extra).toMatchObject({ WEB_PLATFORM_REPLICAS: 3 });

    // Ordering invariant: Sentry mirror must fire BEFORE process.exit so the
    // breadcrumb has a chance to flush. Without invocationCallOrder, a
    // refactor that moves the mirror after process.exit would pass — exit
    // throws (per the spy) and the call-counts stay 1/1.
    const mirrorOrder = vi.mocked(observability.reportSilentFallback).mock
      .invocationCallOrder[0];
    const exitOrder = exitSpy.mock.invocationCallOrder[0];
    expect(mirrorOrder).toBeLessThan(exitOrder);
  });

  it("warn-not-abort when WEB_PLATFORM_REPLICAS=3 with ALLOW_MULTI_REPLICA=1", async () => {
    vi.stubEnv("WEB_PLATFORM_REPLICAS", "3");
    vi.stubEnv("ALLOW_MULTI_REPLICA", "1");
    const { assertSingleReplicaInvariant } = await loadModule();
    const observability = await import("@/server/observability");

    expect(() => assertSingleReplicaInvariant()).not.toThrow();
    expect(exitSpy).not.toHaveBeenCalled();

    expect(observability.warnSilentFallback).toHaveBeenCalledTimes(1);
    const call = vi.mocked(observability.warnSilentFallback).mock.calls[0];
    expect(call[1].feature).toBe("single-replica-assertion");
    expect(call[1].op).toBe("override");
    expect(call[1].message).toMatch(/ADR-027/);
  });

  it("warn-not-abort when WEB_PLATFORM_REPLICAS=not-a-number (operator typo)", async () => {
    vi.stubEnv("WEB_PLATFORM_REPLICAS", "not-a-number");
    const { assertSingleReplicaInvariant } = await loadModule();
    const observability = await import("@/server/observability");

    expect(() => assertSingleReplicaInvariant()).not.toThrow();
    expect(exitSpy).not.toHaveBeenCalled();

    expect(observability.warnSilentFallback).toHaveBeenCalledTimes(1);
    const call = vi.mocked(observability.warnSilentFallback).mock.calls[0];
    expect(call[1].feature).toBe("single-replica-assertion");
    expect(call[1].op).toBe("parse");
    expect(call[1].extra).toMatchObject({ WEB_PLATFORM_REPLICAS: "not-a-number" });
  });
});
