import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// Separate file (per work-skill guidance): the handler test needs vi.mock for
// fs / fetch / Sentry / _cron-shared, which would clobber the real-import pure
// helper tests in cron-inngest-cron-watchdog.test.ts. NEXT_PHASE hoisted so the
// inngest client load-time key check short-circuits.
vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

const writeFileMock = vi.fn(async (..._args: unknown[]): Promise<void> => {});
const readFileMock = vi.fn(async (..._args: unknown[]): Promise<string> => {
  throw new Error("ENOENT"); // no prior state by default
});

vi.mock("node:fs/promises", () => ({
  readFile: (...a: unknown[]) => readFileMock(...a),
  writeFile: (...a: unknown[]) => writeFileMock(...a),
  mkdir: vi.fn(async () => {}),
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
}));

// Preserve the real pure helpers + constants; stub only the IO-heavy exports
// the handler calls (postSentryHeartbeat does its own fs/fetch; mintInstallationToken
// hits GitHub).
vi.mock("@/server/inngest/functions/_cron-shared", async () => {
  const actual = await vi.importActual<
    typeof import("@/server/inngest/functions/_cron-shared")
  >("@/server/inngest/functions/_cron-shared");
  return {
    ...actual,
    postSentryHeartbeat: vi.fn(async () => {}),
    mintInstallationToken: vi.fn(async () => "ghs_faketoken"),
  };
});

import { cronInngestCronWatchdogHandler, EXPECTED_CRON_FUNCTIONS } from "@/server/inngest/functions/cron-inngest-cron-watchdog";
import { postSentryHeartbeat } from "@/server/inngest/functions/_cron-shared";

// Fake Inngest step: runs each step body inline (no replay machinery).
const fakeStep = { run: <T>(_name: string, fn: () => Promise<T>) => fn() };
const fakeLogger = { info: vi.fn(), warn: vi.fn(), error: vi.fn() };

// Build a /v1/functions registry where exactly `omit` is MISSING (H9a); all
// others present + cron-planned.
function registryMissing(omit: string): unknown[] {
  return EXPECTED_CRON_FUNCTIONS.filter((f) => f !== omit).map((fnId) => ({
    slug: `soleur-runtime-${fnId}`,
    triggers: [{ cron: "0 8 * * *" }],
  }));
}

function mockFetch(registry: unknown[], webhookStatus: number) {
  return vi.fn(async (url: string | URL) => {
    const u = String(url);
    if (u.includes("/v1/functions")) {
      return { ok: true, json: async () => registry } as unknown as Response;
    }
    if (u.includes("deploy.soleur.ai")) {
      return { status: webhookStatus } as unknown as Response;
    }
    throw new Error(`unexpected fetch ${u}`);
  });
}

describe("cronInngestCronWatchdogHandler — backstop restart orchestration (#4652 / AC4–AC7)", () => {
  const ORIG = { ...process.env };

  beforeEach(() => {
    writeFileMock.mockClear();
    readFileMock.mockClear();
    process.env.INNGEST_BASE_URL = "http://host.docker.internal:8288";
    process.env.WEBHOOK_DEPLOY_SECRET = "secret";
    process.env.CF_ACCESS_CLIENT_ID = "cf-id";
    process.env.CF_ACCESS_CLIENT_SECRET = "cf-secret";
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    process.env = { ...ORIG };
  });

  it("AC4: H9a single tick → NO restart, ok=false, NO deploy-webhook fetch (polling gets its grace window)", async () => {
    // Default readFileMock throws ENOENT → no prior state → streak starts at 1
    // < POLL_RECOVERY_GRACE_TICKS, so the demoted watchdog must NOT restart on
    // the first defective tick (pre-#4652 this restarted immediately).
    const fetchMock = mockFetch(registryMissing("cron-community-monitor"), 202);
    vi.stubGlobal("fetch", fetchMock);

    const out = await cronInngestCronWatchdogHandler({
      step: fakeStep,
      logger: fakeLogger,
    } as never);

    expect(out.ok).toBe(false); // defect present → ok=false heartbeat still pages (AC7 safety net intact)
    expect(out.healed.restartRequested).toBe(false); // AC4: no restart on tick 1
    // The load-bearing assertion: the deploy webhook was NOT POSTed this tick.
    expect(
      fetchMock.mock.calls.some((c) => String(c[0]).includes("deploy.soleur.ai")),
    ).toBe(false);
    // Streak persisted at 1; no last_restart_at written.
    const lastWrite = writeFileMock.mock.calls.at(-1);
    expect(lastWrite).toBeDefined();
    const persisted = JSON.parse(String(lastWrite![1]));
    expect(persisted.defect_streaks).toEqual({ "cron-community-monitor": 1 });
    expect(persisted.last_restart_at).toBeUndefined();
  });

  it("AC5: H9a sustained to the grace threshold → restartRequested, webhook 202, streaks cleared", async () => {
    // Seed a prior defect streak of (grace-1) so THIS defective tick crosses
    // POLL_RECOVERY_GRACE_TICKS and escalates to the backstop restart.
    readFileMock.mockResolvedValueOnce(
      JSON.stringify({ defect_streaks: { "cron-community-monitor": 1 } }),
    );
    const fetchMock = mockFetch(registryMissing("cron-community-monitor"), 202);
    vi.stubGlobal("fetch", fetchMock);

    const out = await cronInngestCronWatchdogHandler({
      step: fakeStep,
      logger: fakeLogger,
    } as never);

    expect(out.ok).toBe(false);
    expect(out.healed.restartRequested).toBe(true);
    expect(
      fetchMock.mock.calls.some((c) => String(c[0]).includes("deploy.soleur.ai")),
    ).toBe(true);
    // last_restart_at set, streaks cleared (a restart re-syncs + re-plans all).
    const restartWrite = writeFileMock.mock.calls.find((c) =>
      String(c[1]).includes("last_restart_at"),
    );
    expect(restartWrite).toBeDefined();
    const persisted = JSON.parse(String(restartWrite![1]));
    expect(typeof persisted.last_restart_at).toBe("string");
    expect(persisted.defect_streaks).toEqual({});
  });

  it("AC5: sustained H9a + webhook non-202 → falls back to D1-B, handler does not reject", async () => {
    // Sustained defect (seeded streak crosses the threshold this tick) so the
    // restart path is reached; webhook returns 500 → D1-A fails → D1-B.
    readFileMock.mockResolvedValueOnce(
      JSON.stringify({ defect_streaks: { "cron-community-monitor": 1 } }),
    );
    const fetchMock = mockFetch(registryMissing("cron-community-monitor"), 500);
    vi.stubGlobal("fetch", fetchMock);

    const out = await cronInngestCronWatchdogHandler({
      step: fakeStep,
      logger: fakeLogger,
    } as never).catch((e) => e);

    // Either D1-B completed (restartRequested true) or Octokit threw (caught →
    // reportSilentFallback → returns false). Both are non-throwing; assert the
    // handler did not reject AND the webhook was attempted before D1-B.
    expect(out).not.toBeInstanceOf(Error);
    expect(
      fetchMock.mock.calls.some((c) => String(c[0]).includes("deploy.soleur.ai")),
    ).toBe(true);
  });

  it("AC7: clean registry → no restart, ok=true, persists empty streaks (cooldown timestamp preserved)", async () => {
    readFileMock.mockResolvedValueOnce(
      JSON.stringify({ last_restart_at: "2026-05-29T00:00:00Z", defect_streaks: {} }),
    );
    const fullRegistry = EXPECTED_CRON_FUNCTIONS.map((fnId) => ({
      slug: `soleur-runtime-${fnId}`,
      triggers: [{ cron: "0 8 * * *" }],
    }));
    vi.stubGlobal("fetch", mockFetch(fullRegistry, 202));

    const out = await cronInngestCronWatchdogHandler({
      step: fakeStep,
      logger: fakeLogger,
    } as never);

    expect(out.ok).toBe(true);
    expect(out.healed.restartRequested).toBe(false);
    // State still written to persist (empty) streaks while preserving timestamp.
    const lastWrite = writeFileMock.mock.calls.at(-1);
    expect(lastWrite).toBeDefined();
    const persisted = JSON.parse(String(lastWrite![1]));
    expect(persisted.last_restart_at).toBe("2026-05-29T00:00:00Z");
    expect(persisted.defect_streaks).toEqual({});
  });
});

describe("cronInngestCronWatchdogHandler — registry-fetch is non-fatal (#4682)", () => {
  const ORIG = { ...process.env };

  beforeEach(() => {
    writeFileMock.mockClear();
    readFileMock.mockClear();
    vi.mocked(postSentryHeartbeat).mockClear();
    process.env.INNGEST_BASE_URL = "http://host.docker.internal:8288";
    process.env.WEBHOOK_DEPLOY_SECRET = "secret";
    process.env.CF_ACCESS_CLIENT_ID = "cf-id";
    process.env.CF_ACCESS_CLIENT_SECRET = "cf-secret";
  });

  afterEach(() => {
    vi.unstubAllGlobals();
    process.env = { ...ORIG };
  });

  it("404 from /v1/functions → handler does NOT crash, posts ok=false heartbeat, no restart (#4682)", async () => {
    // The exact prod failure: /v1/functions returns 404 → fetchRegistry throws.
    // Pre-#4682 this aborted the handler before the heartbeat → 0 check-ins
    // (silent watchdog). Now it must catch, page ok=false, and skip heal.
    const fetchMock = vi.fn(async (url: string | URL) => {
      const u = String(url);
      if (u.includes("/v1/functions")) {
        return { ok: false, status: 404, json: async () => ({}) } as unknown as Response;
      }
      if (u.includes("deploy.soleur.ai")) {
        return { status: 202 } as unknown as Response;
      }
      throw new Error(`unexpected fetch ${u}`);
    });
    vi.stubGlobal("fetch", fetchMock);

    const out = await cronInngestCronWatchdogHandler({
      step: fakeStep,
      logger: fakeLogger,
    } as never).catch((e) => e);

    // Did NOT reject (the silent-death failure mode is gone).
    expect(out).not.toBeInstanceOf(Error);
    expect(out.ok).toBe(false);
    expect(out.results).toEqual([]);
    expect(out.healed.restartRequested).toBe(false);
    // The load-bearing fix: a heartbeat (ok=false) IS posted so the monitor pages
    // instead of going silent.
    const hb = vi.mocked(postSentryHeartbeat).mock.calls.at(-1);
    expect(hb).toBeDefined();
    expect(hb![0]).toMatchObject({ ok: false, sentryMonitorSlug: "scheduled-inngest-cron-watchdog" });
    // No restart webhook on the degraded path (no registry data to act on).
    expect(
      fetchMock.mock.calls.some((c) => String(c[0]).includes("deploy.soleur.ai")),
    ).toBe(false);
  });

  it("does NOT send an Authorization header to /v1/functions (#4682 — unauth loopback endpoint)", async () => {
    // INNGEST_SIGNING_KEY is present in prod; the header it would carry caused
    // the 404. Assert the registry fetch is unauthenticated regardless.
    process.env.INNGEST_SIGNING_KEY = "signkey-prod-deadbeef";
    const calls: Array<{ url: string; init: RequestInit | undefined }> = [];
    const fetchMock = vi.fn(async (url: string | URL, init?: RequestInit) => {
      calls.push({ url: String(url), init });
      return {
        ok: true,
        json: async () =>
          EXPECTED_CRON_FUNCTIONS.map((fnId) => ({
            slug: `soleur-runtime-${fnId}`,
            triggers: [{ cron: "0 8 * * *" }],
          })),
      } as unknown as Response;
    });
    vi.stubGlobal("fetch", fetchMock);

    await cronInngestCronWatchdogHandler({ step: fakeStep, logger: fakeLogger } as never);

    const regCall = calls.find((c) => c.url.includes("/v1/functions"));
    expect(regCall).toBeDefined();
    const headers = (regCall!.init?.headers ?? {}) as Record<string, string>;
    const headerKeys = Object.keys(headers).map((k) => k.toLowerCase());
    expect(headerKeys).not.toContain("authorization");
  });
});
