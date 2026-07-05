// #6031 — cron-ghcr-token-minter tests (ADR-088).
//
// The minter mints a 1h `packages:read` GitHub App installation token and writes
// it to Doppler `prd_ghcr` as GHCR_READ_TOKEN (+ GHCR_READ_USER=x-access-token).
// Security-critical invariants under test:
//   - AC3    scoped mint body + atomic two-key Doppler write in ONE request
//   - AC4    output-aware heartbeat: ok ONLY on 2xx write, error otherwise
//   - AC-Sec1 single step.run (mint+write) returns ONLY non-secret metadata (no token)
//   - AC-Sec2 failure captures the NUMERIC status only — token never in any Sentry field
//   - AC-Sec3 freshness floor: mint with minRemainingMs >= 40 min (fresh, not stale cache)

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// inngest client throws on missing INNGEST_SIGNING_KEY at module load — set the
// build-phase bypass BEFORE the handler import chain runs.
vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

const reportSilentFallbackSpy = vi.fn();
vi.mock("@/server/observability", () => ({
  reportSilentFallback: (...a: unknown[]) => reportSilentFallbackSpy(...a),
  warnSilentFallback: vi.fn(),
}));

const generateInstallationTokenSpy = vi.fn();
const findInstallationByAccountLoginSpy = vi.fn();
vi.mock("@/server/github-app", () => ({
  generateInstallationToken: (...a: unknown[]) => generateInstallationTokenSpy(...a),
  findInstallationByAccountLogin: (...a: unknown[]) =>
    findInstallationByAccountLoginSpy(...a),
}));

const postSentryHeartbeatSpy = vi.fn();
vi.mock("@/server/inngest/functions/_cron-shared", async (importActual) => {
  const actual = (await importActual()) as Record<string, unknown>;
  return {
    ...actual,
    postSentryHeartbeat: (...a: unknown[]) => postSentryHeartbeatSpy(...a),
  };
});

import { cronGhcrTokenMinterHandler } from "@/server/inngest/functions/cron-ghcr-token-minter";

// Distinctive, non-secret-shaped sentinel — searched for in step returns +
// captured Sentry fields to prove it never leaks (not `ghs_...` so it cannot
// trip GitHub Push Protection).
const MINTED_TOKEN = "SYNTHETIC_GHCR_INSTALL_TOKEN_6031_do_not_leak";
const ORG_INSTALL_ID = 424242;
const FRESHNESS_FLOOR_MS = 40 * 60 * 1000; // 2_400_000

const logger = { info: vi.fn(), warn: vi.fn(), error: vi.fn() };

// Records every step.run(name, fn) invocation and its resolved value so tests can
// assert both the step topology (single mint-and-write) and its return payload.
let stepCalls: { name: string; result: unknown }[];
const makeStep = () => ({
  run: vi.fn(async (name: string, fn: () => Promise<unknown>) => {
    const result = await fn();
    stepCalls.push({ name, result });
    return result;
  }),
});

let fetchMock: ReturnType<typeof vi.fn>;

function dopplerResponse(status: number, echoBody: string) {
  return {
    ok: status >= 200 && status < 300,
    status,
    // The real Doppler write echoes the token in its response body — the handler
    // must drain but NEVER read this into a captured field.
    text: async () => echoBody,
  } as unknown as Response;
}

function lastHeartbeatOk(): boolean | undefined {
  const calls = postSentryHeartbeatSpy.mock.calls;
  if (calls.length === 0) return undefined;
  return (calls[calls.length - 1][0] as { ok: boolean }).ok;
}

function dopplerRequestBody(): Record<string, unknown> | undefined {
  const call = fetchMock.mock.calls.find(([url]) =>
    String(url).includes("api.doppler.com"),
  );
  if (!call) return undefined;
  return JSON.parse((call[1] as { body: string }).body);
}

beforeEach(() => {
  stepCalls = [];
  reportSilentFallbackSpy.mockReset();
  postSentryHeartbeatSpy.mockReset().mockResolvedValue(undefined);
  generateInstallationTokenSpy.mockReset().mockResolvedValue(MINTED_TOKEN);
  findInstallationByAccountLoginSpy.mockReset().mockResolvedValue(ORG_INSTALL_ID);
  fetchMock = vi.fn().mockResolvedValue(
    dopplerResponse(200, JSON.stringify({ secrets: { GHCR_READ_TOKEN: MINTED_TOKEN } })),
  );
  global.fetch = fetchMock as unknown as typeof fetch;
  process.env.GHCR_MINTER_DOPPLER_TOKEN = "dp.st.prd_ghcr." + "synthetic-write-token";
});

afterEach(() => {
  delete process.env.GHCR_MINTER_DOPPLER_TOKEN;
});

describe("cron-ghcr-token-minter — mint + Doppler write (AC3, AC-Sec3)", () => {
  it("mints a packages:read token with a >=40-min freshness floor", async () => {
    await cronGhcrTokenMinterHandler({ step: makeStep() as never, logger });
    expect(generateInstallationTokenSpy).toHaveBeenCalledTimes(1);
    const [installId, opts] = generateInstallationTokenSpy.mock.calls[0] as [
      number,
      { permissions?: Record<string, string>; minRemainingMs?: number },
    ];
    expect(installId).toBe(ORG_INSTALL_ID);
    expect(opts.permissions).toEqual({ packages: "read" });
    // AC-Sec3: fresh mint, never a <40-min stale cache hit.
    expect(opts.minRemainingMs).toBeGreaterThanOrEqual(FRESHNESS_FLOOR_MS);
  });

  it("writes BOTH keys atomically in ONE Doppler request to prd_ghcr (AC3)", async () => {
    await cronGhcrTokenMinterHandler({ step: makeStep() as never, logger });
    const dopplerCalls = fetchMock.mock.calls.filter(([url]) =>
      String(url).includes("api.doppler.com"),
    );
    expect(dopplerCalls).toHaveLength(1); // atomic: exactly one write
    const body = dopplerRequestBody()!;
    expect(body.config).toBe("prd_ghcr");
    expect(body.secrets).toEqual({
      GHCR_READ_TOKEN: MINTED_TOKEN,
      GHCR_READ_USER: "x-access-token",
    });
  });

  it("Doppler write is a partial named-secrets upsert, never a full-config replace (R3)", async () => {
    await cronGhcrTokenMinterHandler({ step: makeStep() as never, logger });
    const call = fetchMock.mock.calls.find(([url]) =>
      String(url).includes("api.doppler.com"),
    )!;
    const [url, init] = call as [string, { method: string; body: string }];
    // POST /v3/configs/config/secrets is the merge/upsert endpoint; a full replace
    // would delete the co-resident GHCR_MINTER_DOPPLER_TOKEN.
    expect(url).toContain("/v3/configs/config/secrets");
    expect(init.method).toBe("POST");
    const body = JSON.parse(init.body);
    expect(Object.keys(body.secrets).sort()).toEqual([
      "GHCR_READ_TOKEN",
      "GHCR_READ_USER",
    ]);
  });
});

describe("cron-ghcr-token-minter — single step, no token leak (AC-Sec1)", () => {
  it("mint+write happen in a SINGLE step.run returning only non-secret metadata", async () => {
    await cronGhcrTokenMinterHandler({ step: makeStep() as never, logger });
    const mintSteps = stepCalls.filter((c) => c.name === "mint-and-write");
    expect(mintSteps).toHaveLength(1);
    // The step's return value must NOT contain the token string anywhere.
    expect(JSON.stringify(mintSteps[0].result)).not.toContain(MINTED_TOKEN);
  });
});

describe("cron-ghcr-token-minter — output-aware heartbeat (AC4)", () => {
  it("emits terminal ok ONLY when the Doppler write returns 2xx", async () => {
    const result = await cronGhcrTokenMinterHandler({ step: makeStep() as never, logger });
    expect(result.ok).toBe(true);
    expect(lastHeartbeatOk()).toBe(true);
  });

  it("non-2xx Doppler write → error heartbeat + numeric-only capture (AC4, AC-Sec2)", async () => {
    fetchMock.mockResolvedValue(
      dopplerResponse(403, "forbidden — token was " + MINTED_TOKEN),
    );
    const result = await cronGhcrTokenMinterHandler({ step: makeStep() as never, logger });
    expect(result.ok).toBe(false);
    expect(lastHeartbeatOk()).toBe(false);
    // Fail-loud capture exists, carries the numeric status, and NEVER the token.
    const capture = reportSilentFallbackSpy.mock.calls.find(
      ([, ctx]) => (ctx as { op?: string }).op === "ghcr-token-doppler-write-failed",
    );
    expect(capture).toBeDefined();
    const serialized = JSON.stringify(reportSilentFallbackSpy.mock.calls);
    expect(serialized).toContain("403");
    expect(serialized).not.toContain(MINTED_TOKEN);
  });

  it("mint throw → error heartbeat, no token in any captured field (AC4, AC-Sec2)", async () => {
    generateInstallationTokenSpy.mockRejectedValue(
      new Error("GitHub installation token request failed: 401"),
    );
    const result = await cronGhcrTokenMinterHandler({ step: makeStep() as never, logger });
    expect(result.ok).toBe(false);
    expect(lastHeartbeatOk()).toBe(false);
    // No Doppler write attempted when the mint fails.
    const dopplerCalls = fetchMock.mock.calls.filter(([url]) =>
      String(url).includes("api.doppler.com"),
    );
    expect(dopplerCalls).toHaveLength(0);
    expect(JSON.stringify(reportSilentFallbackSpy.mock.calls)).not.toContain(MINTED_TOKEN);
  });
});

describe("cron-ghcr-token-minter — misconfiguration", () => {
  it("missing GHCR_MINTER_DOPPLER_TOKEN → error heartbeat, no mint attempted", async () => {
    delete process.env.GHCR_MINTER_DOPPLER_TOKEN;
    const result = await cronGhcrTokenMinterHandler({ step: makeStep() as never, logger });
    expect(result.ok).toBe(false);
    expect(lastHeartbeatOk()).toBe(false);
    expect(generateInstallationTokenSpy).not.toHaveBeenCalled();
  });
});
