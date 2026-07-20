import { afterEach, describe, expect, it, vi } from "vitest";

// Same seam as claude-cost-marker.test.ts: the module builds a dedicated pino
// instance at load, so mocking pino is what lets us (a) capture the emitted
// payload, (b) capture the CONSTRUCTOR config, and (c) make warn throw to prove
// the fail-open contract. Hoisted so the factory can close over them.
const { warnMock, pinoFactory } = vi.hoisted(() => {
  const warnMock = vi.fn();
  // Rest param, not `() => …`: a zero-parameter vi.fn implementation types
  // `mock.calls` as a zero-length tuple, so reading `calls[0][0]` below fails
  // tsc (TS2493) while the vitest run stays green — vitest type-checks test
  // files lazily, so only the standalone tsc pass catches it.
  return {
    warnMock,
    pinoFactory: vi.fn((..._args: unknown[]) => ({ warn: warnMock })),
  };
});

vi.mock("pino", () => ({ default: pinoFactory }));

import {
  emitCommunityDigestFile,
  emitCronDedupSkip,
  emitCronDigestLiveness,
  emitCronPersistResult,
  emitCronPersistSkipped,
  emitCronTier2Deferred,
} from "@/server/cron-liveness-marker";

afterEach(() => {
  warnMock.mockReset();
  warnMock.mockImplementation(() => undefined);
});

// Every marker, its emitter, a representative payload, and the msg string. Driven
// as a table so a NEW marker added without a test is visible as a missing row
// rather than silently uncovered.
const MARKERS = [
  {
    name: "SOLEUR_CRON_PERSIST_RESULT",
    emit: emitCronPersistResult,
    payload: {
      cron: "cron-community-monitor",
      status: "committed" as const,
      files: 3,
      pr: 4242,
      stage: null,
    },
    msg: "cron persist result",
  },
  {
    name: "SOLEUR_CRON_PERSIST_SKIPPED",
    emit: emitCronPersistSkipped,
    payload: { cron: "cron-community-monitor", reason: "timeout" as const },
    msg: "cron persist skipped",
  },
  {
    name: "SOLEUR_COMMUNITY_DIGEST_FILE",
    emit: emitCommunityDigestFile,
    payload: {
      cron: "cron-community-monitor",
      attempt: 0,
      digest_path: "knowledge-base/support/community/2026-07-19-digest.md",
      present: 1 as const,
    },
    msg: "community digest file",
  },
  {
    name: "SOLEUR_CRON_DIGEST_LIVENESS",
    emit: emitCronDigestLiveness,
    payload: {
      cron: "cron-community-monitor",
      run_id: "01JRUN",
      attempt: 0,
      ok: 0 as const,
      reason: "digest-absent-from-commit" as const,
    },
    msg: "cron digest liveness",
  },
  {
    name: "SOLEUR_CRON_TIER2_DEFERRED",
    emit: emitCronTier2Deferred,
    payload: { cron: "cron-community-monitor" },
    msg: "cron tier2 deferred",
  },
  {
    name: "SOLEUR_CRON_DEDUP_SKIP",
    emit: emitCronDedupSkip,
    payload: {
      cron: "cron-community-monitor",
      date: "2026-07-19",
      digest_committed: 1 as const,
    },
    msg: "cron dedup skip",
  },
] as const;

describe("cron-liveness-marker — per-marker contract (#6714 AC25/AC26)", () => {
  it.each(MARKERS)(
    "$name emits ONE warn line carrying its discriminator and exact field set",
    ({ name, emit, payload, msg }) => {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      (emit as (m: unknown) => void)(payload);

      expect(warnMock).toHaveBeenCalledTimes(1);
      const [obj, message] = warnMock.mock.calls[0];
      // toEqual, not toMatchObject: the field set is the contract. A silently
      // added field (especially a regulated one — this pino instance has no
      // ADR-029 pseudonymizer and no redact paths) must fail here.
      expect(obj).toEqual({ [name]: true, ...payload });
      expect(message).toBe(msg);
    },
  );

  it.each(MARKERS)(
    "$name is fail-open: a throwing log.warn never propagates",
    ({ emit, payload }) => {
      warnMock.mockImplementation(() => {
        throw new Error("pino boom");
      });
      expect(() => (emit as (m: unknown) => void)(payload)).not.toThrow();
    },
  );

  // A third `it.each` asserting "emits via warn, never info/debug" was removed as
  // strictly subsumed: the field-set block above already asserts
  // toHaveBeenCalledTimes(1), so a downgrade to log.info fails THERE on a 0 count
  // before a dedicated level test could run. (My mutation run showed "2 failed"
  // for an info downgrade; I read that as two tests earning their keep when it
  // actually meant one was redundant.) The level contract is now stated
  // explicitly by the mock shape assertion below instead of resting on the
  // accident that the mocked logger happens to expose only `warn`.
  it("the module calls ONLY log.warn — never info/debug/error", () => {
    // Stated as a contract rather than inferred from a deliberately-thin mock, so
    // a future faithful-mock refactor cannot silently void it. Levels below 40
    // are dropped by Vector's app_container_warn_filter and never reach Better
    // Stack — the marker would be invisible in exactly the incident it exists for.
    const levels = { warn: warnMock, info: vi.fn(), debug: vi.fn(), error: vi.fn() };
    pinoFactory.mockReturnValueOnce(levels as never);
    for (const { emit, payload } of MARKERS) {
      (emit as (m: unknown) => void)(payload);
    }
    expect(warnMock).toHaveBeenCalledTimes(MARKERS.length);
    expect(levels.info).not.toHaveBeenCalled();
    expect(levels.debug).not.toHaveBeenCalled();
    expect(levels.error).not.toHaveBeenCalled();
  });

  it("the MARKERS table covers EVERY emitter the module exports", async () => {
    // V4 — the table's comment claimed a new marker without a row would be
    // "visible as a missing row". It was not: nothing quantified over the
    // module's exports, and review proved it by appending a sixth emitter that
    // logged at info, had no fail-open wrapper, and carried a user_email on a
    // pino instance with no ADR-029 pseudonymizer — 16/16 still passed.
    const mod = await import("@/server/cron-liveness-marker");
    const exportedEmitters = Object.keys(mod).filter((k) => k.startsWith("emit"));
    expect(exportedEmitters).toHaveLength(MARKERS.length);
  });
});

describe("cron-liveness-marker — logger construction (#6714)", () => {
  it("builds a DEDICATED instance with no logMethod hook and no level override", () => {
    expect(pinoFactory).toHaveBeenCalledTimes(1);
    const config = pinoFactory.mock.calls[0]?.[0] as
      | { hooks?: unknown; level?: unknown; base?: unknown }
      | undefined;

    // No hooks.logMethod: logger.ts mirrors every WARN+ line into a Sentry
    // breadcrumb, and a steady daily marker stream would evict genuine
    // diagnostics from the shared-scope ring buffer.
    expect(config?.hooks).toBeUndefined();
    // No level override — pino defaults to `info`, so `warn` always emits. A
    // level of "error"/"silent" here would suppress every marker while every
    // other assertion in this file still passed.
    expect(config?.level).toBeUndefined();
    expect(config?.base).toMatchObject({ component: "cron-liveness" });
  });
});
