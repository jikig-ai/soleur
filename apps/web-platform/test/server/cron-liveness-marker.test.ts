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
      digest_path: "knowledge-base/support/community/2026-07-19-digest.md",
      present: 1 as const,
    },
    msg: "community digest file",
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
      deduped: 1 as const,
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

  it.each(MARKERS)("$name emits via warn, never info/debug", ({ emit, payload }) => {
    // The level is the whole reason these are reachable. Vector's
    // app_container_warn_filter ships only pino level >= 40 to Better Stack, so
    // an info-level marker never leaves the host and the signal is invisible in
    // exactly the incident it exists for. The mocked logger exposes ONLY `warn`,
    // so any other level would throw here rather than silently downgrade.
    expect(() => (emit as (m: unknown) => void)(payload)).not.toThrow();
    expect(warnMock).toHaveBeenCalledTimes(1);
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
