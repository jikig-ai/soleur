import { beforeEach, describe, expect, it, vi } from "vitest";

// --- Module mocks (hoisted by vitest) --------------------------------------

const {
  reportSilentFallbackSpy,
  warnSilentFallbackSpy,
  mintInstallationTokenSpy,
  fetchRegistrySpy,
  octokitRequestSpy,
} = vi.hoisted(() => ({
  reportSilentFallbackSpy: vi.fn(),
  warnSilentFallbackSpy: vi.fn(),
  mintInstallationTokenSpy: vi.fn(async () => "ghs_test_token_abc"),
  fetchRegistrySpy: vi.fn(),
  octokitRequestSpy: vi.fn(),
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: reportSilentFallbackSpy,
  warnSilentFallback: warnSilentFallbackSpy,
}));

vi.mock("@/server/inngest/client", () => ({
  inngest: { createFunction: vi.fn(), send: vi.fn() },
}));

// Partial-mock the watchdog: override fetchRegistry only; keep classifyRegistry
// + resolveInngestHost real (they are pure — we want to exercise real
// classification logic).
vi.mock("@/server/inngest/functions/cron-inngest-cron-watchdog", async () => {
  const actual = await vi.importActual<
    typeof import("@/server/inngest/functions/cron-inngest-cron-watchdog")
  >("@/server/inngest/functions/cron-inngest-cron-watchdog");
  return { ...actual, fetchRegistry: fetchRegistrySpy };
});

// Partial-mock _cron-shared: override mintInstallationToken; keep REPO_OWNER/NAME.
vi.mock("@/server/inngest/functions/_cron-shared", async () => {
  const actual = await vi.importActual<
    typeof import("@/server/inngest/functions/_cron-shared")
  >("@/server/inngest/functions/_cron-shared");
  return { ...actual, mintInstallationToken: mintInstallationTokenSpy };
});

vi.mock("@octokit/core", () => ({
  // vitest 4: mocks invoked with `new` now construct an instance, so a
  // constructor mock must use the `function` keyword and assign to `this`
  // (an arrow returning an object throws "is not a constructor").
  Octokit: vi.fn().mockImplementation(function (this: Record<string, unknown>) {
    this.request = octokitRequestSpy;
  }),
}));

// --- SUT import (module does not exist yet — RED) ----------------------------

import {
  oneshot4650MonitorCloseHandler,
  TARGET_FN_IDS,
} from "@/server/inngest/functions/oneshot-4650-monitor-close";
import { EXPECTED_CRON_FUNCTIONS } from "@/server/inngest/functions/cron-inngest-cron-watchdog";

// --- Helpers ----------------------------------------------------------------

function makeStep() {
  const calls: { name: string }[] = [];
  return {
    calls,
    async run<T>(name: string, cb: () => Promise<T>): Promise<T> {
      const result = await cb();
      calls.push({ name });
      return result;
    },
  };
}

const logger = { info: vi.fn(), warn: vi.fn(), error: vi.fn() };

// Registry entry helpers — a planned cron has a cron trigger; an UNPLANNED one
// has the slug but no cron trigger; a MISSING one is absent from the array.
const TARGET_SLUGS = [
  "cron-gh-pages-cert-state",
  "cron-community-monitor",
  "cron-inngest-cron-watchdog",
];
function planned(slug: string) {
  return { slug: `soleur-runtime-${slug}`, triggers: [{ cron: "0 3 * * *" }] };
}
function unplanned(slug: string) {
  return { slug: `soleur-runtime-${slug}`, triggers: [{ event: "x" }] };
}
function allHealthyRegistry() {
  return TARGET_SLUGS.map(planned);
}

function event(over?: Partial<{ issue: number; expected_date: string; date_override: string }>) {
  return {
    data: {
      issue: 4650,
      expected_date: "2026-05-31",
      actor: "platform" as const,
      ...over,
    },
  };
}

function setIssueState(state: "open" | "closed") {
  octokitRequestSpy.mockImplementation(async (route: string) => {
    if (route.startsWith("GET ")) return { data: { state } };
    return { data: {} }; // comment POST / issue PATCH (close)
  });
}

function postedComment(): boolean {
  return octokitRequestSpy.mock.calls.some(
    (c) => typeof c[0] === "string" && c[0].includes("/comments"),
  );
}
function patched(): boolean {
  return octokitRequestSpy.mock.calls.some(
    (c) => typeof c[0] === "string" && c[0].startsWith("PATCH "),
  );
}

beforeEach(() => {
  vi.clearAllMocks();
  mintInstallationTokenSpy.mockResolvedValue("ghs_test_token_abc");
});

describe("oneshot-4650-monitor-close", () => {
  it("date-guard: before expected_date → warn-level reject, no close", async () => {
    fetchRegistrySpy.mockResolvedValue(allHealthyRegistry());
    setIssueState("open");
    const res = await oneshot4650MonitorCloseHandler({
      event: event({ date_override: "2026-05-30" }),
      step: makeStep(),
      logger,
    });
    expect(res).toEqual({ ok: false, reason: "date-guard" });
    expect(warnSilentFallbackSpy).toHaveBeenCalledTimes(1);
    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();
    // must NOT have attempted a close (PATCH)
    expect(patched()).toBe(false);
  });

  it("date-guard: invalid calendar date in date_override → invalid-date-override", async () => {
    const res = await oneshot4650MonitorCloseHandler({
      event: event({ date_override: "2026-13-45" }),
      step: makeStep(),
      logger,
    });
    expect(res).toEqual({ ok: false, reason: "invalid-date-override" });
    expect(reportSilentFallbackSpy).toHaveBeenCalledTimes(1);
  });

  it("all 3 OK + issue open → closes #4650", async () => {
    fetchRegistrySpy.mockResolvedValue(allHealthyRegistry());
    setIssueState("open");
    const res = await oneshot4650MonitorCloseHandler({
      event: event({ date_override: "2026-05-31" }),
      step: makeStep(),
      logger,
    });
    expect(res).toEqual({ ok: true, reason: "closed" });
    expect(postedComment()).toBe(true); // comment precedes close
    expect(patched()).toBe(true);
  });

  it("partial registry (1 MISSING) + open → leave open, reportSilentFallback, NO close", async () => {
    fetchRegistrySpy.mockResolvedValue([
      planned("cron-gh-pages-cert-state"),
      planned("cron-community-monitor"),
      // cron-inngest-cron-watchdog MISSING
    ]);
    setIssueState("open");
    const res = await oneshot4650MonitorCloseHandler({
      event: event({ date_override: "2026-05-31" }),
      step: makeStep(),
      logger,
    });
    expect(res).toEqual({ ok: false, reason: "not-all-healthy" });
    expect(reportSilentFallbackSpy).toHaveBeenCalledTimes(1);
    expect(patched()).toBe(false);
  });

  it("registry fetch throws + open → fail-safe, no close (distinct from partial)", async () => {
    fetchRegistrySpy.mockRejectedValue(new Error("inngest /v1/functions returned 503"));
    setIssueState("open");
    const res = await oneshot4650MonitorCloseHandler({
      event: event({ date_override: "2026-05-31" }),
      step: makeStep(),
      logger,
    });
    expect(res).toEqual({ ok: false, reason: "registry-fetch-failed" });
    expect(reportSilentFallbackSpy).toHaveBeenCalledTimes(1);
    expect(patched()).toBe(false);
  });

  it("already-closed + all OK → no-op success, no already-closed-unhealthy alert", async () => {
    fetchRegistrySpy.mockResolvedValue(allHealthyRegistry());
    setIssueState("closed");
    const res = await oneshot4650MonitorCloseHandler({
      event: event({ date_override: "2026-05-31" }),
      step: makeStep(),
      logger,
    });
    expect(res).toEqual({ ok: true, reason: "already-closed" });
    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();
  });

  it("already-closed but a cron UNPLANNED → reportSilentFallback(already-closed-unhealthy)", async () => {
    fetchRegistrySpy.mockResolvedValue([
      planned("cron-gh-pages-cert-state"),
      planned("cron-community-monitor"),
      unplanned("cron-inngest-cron-watchdog"),
    ]);
    setIssueState("closed");
    const res = await oneshot4650MonitorCloseHandler({
      event: event({ date_override: "2026-05-31" }),
      step: makeStep(),
      logger,
    });
    expect(res).toEqual({ ok: true, reason: "already-closed" });
    expect(reportSilentFallbackSpy).toHaveBeenCalledTimes(1);
    expect(reportSilentFallbackSpy.mock.calls[0][1]).toMatchObject({
      op: "already-closed-unhealthy",
    });
  });

  it("open + all OK but the close PATCH fails → close-failed + reportSilentFallback", async () => {
    fetchRegistrySpy.mockResolvedValue(allHealthyRegistry());
    octokitRequestSpy.mockImplementation(async (route: string) => {
      if (route.startsWith("GET ")) return { data: { state: "open" } };
      if (route.startsWith("PATCH ")) throw new Error("422 cannot close");
      return { data: {} }; // comment POST
    });
    const res = await oneshot4650MonitorCloseHandler({
      event: event({ date_override: "2026-05-31" }),
      step: makeStep(),
      logger,
    });
    expect(res).toEqual({ ok: false, reason: "close-failed" });
    expect(reportSilentFallbackSpy.mock.calls.some((c) => c[1]?.op === "close-issue")).toBe(true);
  });

  it("default real-clock path (no date_override) after expected_date → closes", async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-06-01T09:00:00Z"));
    try {
      fetchRegistrySpy.mockResolvedValue(allHealthyRegistry());
      setIssueState("open");
      const res = await oneshot4650MonitorCloseHandler({
        event: event(), // no date_override → exercises new Date()
        step: makeStep(),
        logger,
      });
      expect(res).toEqual({ ok: true, reason: "closed" });
    } finally {
      vi.useRealTimers();
    }
  });

  it("non-target issue → wrong-issue, never touches GitHub", async () => {
    const res = await oneshot4650MonitorCloseHandler({
      event: event({ issue: 9999, date_override: "2026-05-31" }),
      step: makeStep(),
      logger,
    });
    expect(res).toEqual({ ok: false, reason: "wrong-issue" });
    expect(octokitRequestSpy).not.toHaveBeenCalled();
  });

  it("TARGET_FN_IDS is a subset of the watchdog EXPECTED_CRON_FUNCTIONS manifest", () => {
    for (const fnId of TARGET_FN_IDS) {
      expect(EXPECTED_CRON_FUNCTIONS).toContain(fnId);
    }
  });
});
