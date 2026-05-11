import { describe, it, expect, vi, afterEach, beforeEach } from "vitest";

vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
  warnSilentFallback: vi.fn(),
}));

vi.mock("@/server/logger", () => ({
  default: { error: vi.fn(), warn: vi.fn(), info: vi.fn() },
  createChildLogger: () => ({ error: vi.fn(), warn: vi.fn(), info: vi.fn() }),
}));

describe("assertSingleReplicaInvariant", () => {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let exitSpy: any;

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
    vi.stubEnv("WEB_PLATFORM_REPLICAS", "");
    // Use undefined by deleting the stub
    vi.unstubAllEnvs();
    const { assertSingleReplicaInvariant } = await loadModule();
    expect(() => assertSingleReplicaInvariant()).not.toThrow();
    expect(exitSpy).not.toHaveBeenCalled();
  });

  it("no-ops when WEB_PLATFORM_REPLICAS=1", async () => {
    vi.stubEnv("WEB_PLATFORM_REPLICAS", "1");
    const { assertSingleReplicaInvariant } = await loadModule();
    expect(() => assertSingleReplicaInvariant()).not.toThrow();
    expect(exitSpy).not.toHaveBeenCalled();
  });

  it("aborts boot (process.exit(1)) when WEB_PLATFORM_REPLICAS=3 without override", async () => {
    vi.stubEnv("WEB_PLATFORM_REPLICAS", "3");
    const { assertSingleReplicaInvariant } = await loadModule();
    const observability = await import("@/server/observability");

    expect(() => assertSingleReplicaInvariant()).toThrowError(/process\.exit\(1\)/);
    expect(exitSpy).toHaveBeenCalledWith(1);

    // Sentry mirror fires with feature tag.
    expect(observability.reportSilentFallback).toHaveBeenCalledTimes(1);
    const call = vi.mocked(observability.reportSilentFallback).mock.calls[0];
    expect(call[1].feature).toBe("single-replica-assertion");
    expect(call[1].message).toMatch(/ADR-027/);
    expect(call[1].extra).toMatchObject({ WEB_PLATFORM_REPLICAS: 3 });
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
