import { readFileSync } from "node:fs";
import { resolve } from "node:path";

import { beforeEach, describe, expect, it, vi } from "vitest";

// vi.hoisted runs BEFORE ES-module imports — set NEXT_PHASE so importing the
// inngest client (transitively pulled by the SUT) does not throw on the missing
// INNGEST_SIGNING_KEY in the test env. Mirrors cron-supabase-watchdog-dispatch.test.ts.
const h = vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
  return {
    // Untyped: mockImplementation swaps in route-dispatching stubs whose
    // arg/return shapes vary per test; a declared signature would reject them.
    requestSpy: vi.fn(),
    reportSilentFallbackSpy: vi.fn((..._args: unknown[]) => {}),
    warnSilentFallbackSpy: vi.fn((..._args: unknown[]) => {}),
    mintSpy: vi.fn(async (_opts: unknown) => "fake-installation-token"),
    heartbeatSpy: vi.fn(async (_opts: unknown) => {}),
  };
});

vi.mock("@octokit/core", () => ({
  Octokit: class {
    request = h.requestSpy;
  },
}));

vi.mock("@/server/inngest/functions/_cron-shared", async () => {
  const actual = await vi.importActual<
    typeof import("@/server/inngest/functions/_cron-shared")
  >("@/server/inngest/functions/_cron-shared");
  return {
    ...actual,
    mintInstallationToken: h.mintSpy,
    postSentryHeartbeat: h.heartbeatSpy,
  };
});

vi.mock("@/server/observability", async () => {
  const actual =
    await vi.importActual<typeof import("@/server/observability")>(
      "@/server/observability",
    );
  return { ...actual, reportSilentFallback: h.reportSilentFallbackSpy };
});

import {
  cronBotPrReaper,
  cronBotPrReaperHandler,
  reapBotPr,
} from "@/server/inngest/functions/cron-bot-pr-reaper";

const SUT_SOURCE = readFileSync(
  resolve(
    __dirname,
    "../../../server/inngest/functions/cron-bot-pr-reaper.ts",
  ),
  "utf-8",
);

function makeStep() {
  return {
    run: async <T>(_name: string, cb: () => Promise<T>): Promise<T> => cb(),
  };
}
const logger = { info: vi.fn(), warn: vi.fn(), error: vi.fn() };

// Minimal route-dispatching octokit stub. `pulls` is the list response; each
// `details[n]` is the GET /pulls/{n} body; `checkRuns[sha]` the check-runs
// response; `issues` the open-issues list used by ensureDedupIssue and the
// self-close scan.
function octokitStub(opts: {
  pulls: Array<Record<string, unknown>>;
  details: Record<number, Record<string, unknown>>;
  checkRuns?: Record<string, Array<{ status: string }>>;
  issues?: Array<{ title: string; number: number }>;
}) {
  const calls: Array<{ route: string; params: Record<string, unknown> }> = [];
  const request = vi.fn(async (route: string, params: Record<string, unknown>) => {
    calls.push({ route, params });
    if (route === "GET /repos/{owner}/{repo}/pulls") {
      return { data: opts.pulls };
    }
    if (route === "GET /repos/{owner}/{repo}/pulls/{pull_number}") {
      const d = opts.details[params.pull_number as number];
      if (!d) throw Object.assign(new Error("404"), { status: 404 });
      return { data: d };
    }
    if (route === "GET /repos/{owner}/{repo}/commits/{ref}/check-runs") {
      return {
        data: {
          check_runs: opts.checkRuns?.[params.ref as string] ?? [],
        },
      };
    }
    if (route === "PUT /repos/{owner}/{repo}/pulls/{pull_number}/update-branch") {
      return { status: 202, data: {} };
    }
    if (route === "GET /repos/{owner}/{repo}/issues") {
      return { data: opts.issues ?? [] };
    }
    if (route === "POST /repos/{owner}/{repo}/issues") {
      return { data: { number: 9900 } };
    }
    if (
      route === "POST /repos/{owner}/{repo}/issues/{issue_number}/comments" ||
      route === "PATCH /repos/{owner}/{repo}/issues/{issue_number}"
    ) {
      return { status: 201, data: {} };
    }
    throw new Error(`unexpected route ${route}`);
  });
  return { request, calls };
}

const BOT_PR = (n: number, created: string) => ({
  number: n,
  created_at: created,
  draft: false,
  user: { login: "soleur-ai[bot]" },
  auto_merge: { merge_method: "squash" },
});

describe("cronBotPrReaper — registration shape (import-time smoke)", () => {
  it("loads without throwing", () => {
    expect(cronBotPrReaper).toBeDefined();
    expect(typeof cronBotPrReaper).toBe("object");
  });
});

describe("registration source-shape anchors", () => {
  it.each([
    ['id: "cron-bot-pr-reaper"', "canonical function id"],
    ['cron: "17 */2 * * *"', "every-2-hours sweep cadence"],
    ['event: "cron/bot-pr-reaper.manual-trigger"', "operator manual trigger"],
    ['scope: "fn"', "fn-scoped serialization"],
    ["retries: 1", "single retry on failure"],
    ['"scheduled-bot-pr-reaper"', "Sentry monitor slug (kebab-case, SLUG_RE)"],
    ['"soleur-ai[bot]"', "REST user.login bot predicate (NOT GraphQL app/soleur-ai)"],
    ["expected_head_sha", "update-branch CAS binding"],
    ["checks: \"read\"", "settle-guard check-runs grant"],
  ])("source contains %s (%s)", (anchor) => {
    expect(SUT_SOURCE).toContain(anchor);
  });
});

describe("reapBotPr — decision table", () => {
  const detail = (state: string, sha = "abc123") => ({
    number: 1,
    mergeable_state: state,
    head: { sha },
  });
  const mk = (state: string, checkRuns: Array<{ status: string }> = []) =>
    octokitStub({
      pulls: [],
      details: { 1: detail(state) },
      checkRuns: { abc123: checkRuns },
    });

  it("behind + terminal checks → update-branch WITH expected_head_sha", async () => {
    const stub = mk("behind", [{ status: "completed" }]);
    const r = await reapBotPr({
      octokit: { request: stub.request } as never,
      prNumber: 1,
      updatesUsed: 0,
      updatesCap: 5,
      unknownRereadDelayMs: 0,
      logger,
    });
    expect(r.action).toBe("updated");
    const upd = stub.calls.find((c) => c.route.includes("update-branch"));
    expect(upd?.params.expected_head_sha).toBe("abc123");
  });

  it("behind + in-flight checks → skipped, never updates", async () => {
    const stub = mk("behind", [{ status: "in_progress" }]);
    const r = await reapBotPr({
      octokit: { request: stub.request } as never,
      prNumber: 1,
      updatesUsed: 0,
      updatesCap: 5,
      unknownRereadDelayMs: 0,
      logger,
    });
    expect(r.action).toBe("skipped-checks-in-flight");
    expect(stub.calls.some((c) => c.route.includes("update-branch"))).toBe(false);
  });

  it("behind + update cap reached → skipped-update-cap, no update call", async () => {
    const stub = mk("behind", [{ status: "completed" }]);
    const r = await reapBotPr({
      octokit: { request: stub.request } as never,
      prNumber: 1,
      updatesUsed: 5,
      updatesCap: 5,
      unknownRereadDelayMs: 0,
      logger,
    });
    expect(r.action).toBe("skipped-update-cap");
    expect(stub.calls.some((c) => c.route.includes("update-branch"))).toBe(false);
  });

  it("behind + 422 head-sha mismatch → quiet skip", async () => {
    const stub = mk("behind", [{ status: "completed" }]);
    stub.request.mockImplementation(async (route: string, _params: Record<string, unknown>) => {
      if (route.includes("update-branch")) {
        throw Object.assign(new Error("expected_head_sha does not match"), { status: 422 });
      }
      if (route === "GET /repos/{owner}/{repo}/pulls/{pull_number}") {
        return { data: detail("behind") };
      }
      if (route.includes("check-runs")) {
        return { data: { check_runs: [{ status: "completed" }] } };
      }
      throw new Error(`unexpected ${route}`);
    });
    const r = await reapBotPr({
      octokit: { request: stub.request } as never,
      prNumber: 1,
      updatesUsed: 0,
      updatesCap: 5,
      unknownRereadDelayMs: 0,
      logger,
    });
    expect(r.action).toBe("skipped-head-moved");
  });

  it.each(["dirty", "blocked", "unstable"])(
    "%s → stuck-alerted, no update call",
    async (state) => {
      const stub = mk(state);
      const r = await reapBotPr({
        octokit: { request: stub.request } as never,
        prNumber: 1,
        updatesUsed: 0,
        updatesCap: 5,
        unknownRereadDelayMs: 0,
        logger,
      });
      expect(r.action).toBe("stuck-alerted");
      expect(stub.calls.some((c) => c.route.includes("update-branch"))).toBe(false);
    },
  );

  it.each(["clean", "draft", "has_hooks"])("%s → skipped", async (state) => {
    const stub = mk(state);
    const r = await reapBotPr({
      octokit: { request: stub.request } as never,
      prNumber: 1,
      updatesUsed: 0,
      updatesCap: 5,
      unknownRereadDelayMs: 0,
      logger,
    });
    expect(r.action).toMatch(/^skipped-/);
    expect(stub.calls.some((c) => c.route.includes("update-branch"))).toBe(false);
  });

  it("unknown → one re-read, still unknown → skipped-unknown", async () => {
    const stub = mk("unknown");
    const r = await reapBotPr({
      octokit: { request: stub.request } as never,
      prNumber: 1,
      updatesUsed: 0,
      updatesCap: 5,
      unknownRereadDelayMs: 0,
      logger,
    });
    expect(r.action).toBe("skipped-unknown");
    expect(
      stub.calls.filter((c) => c.route === "GET /repos/{owner}/{repo}/pulls/{pull_number}"),
    ).toHaveLength(2);
  });

  it("unknown → re-read resolves to clean → skipped-clean", async () => {
    const stub = mk("unknown");
    let reads = 0;
    stub.request.mockImplementation(async (route: string) => {
      if (route === "GET /repos/{owner}/{repo}/pulls/{pull_number}") {
        reads++;
        return { data: detail(reads === 1 ? "unknown" : "clean") };
      }
      throw new Error(`unexpected ${route}`);
    });
    const r = await reapBotPr({
      octokit: { request: stub.request } as never,
      prNumber: 1,
      updatesUsed: 0,
      updatesCap: 5,
      unknownRereadDelayMs: 0,
      logger,
    });
    expect(r.action).toBe("skipped-clean");
    expect(reads).toBe(2);
  });

  it("unrecognized state → skipped + warn (forward-compat fallthrough)", async () => {
    const stub = mk("future_state_9");
    logger.warn.mockClear();
    const r = await reapBotPr({
      octokit: { request: stub.request } as never,
      prNumber: 1,
      updatesUsed: 0,
      updatesCap: 5,
      unknownRereadDelayMs: 0,
      logger,
    });
    expect(r.action).toBe("skipped-state");
    expect(logger.warn).toHaveBeenCalled();
  });
});

describe("cronBotPrReaperHandler — sweep", () => {
  beforeEach(() => {
    h.requestSpy.mockReset();
    h.reportSilentFallbackSpy.mockClear();
    h.mintSpy.mockClear();
    h.heartbeatSpy.mockClear();
  });

  it("mints the exact narrowed grant (contents/pull_requests/issues write + checks read)", async () => {
    h.requestSpy.mockResolvedValue({ data: [] });
    await cronBotPrReaperHandler({ step: makeStep(), logger });
    expect(h.mintSpy).toHaveBeenCalledTimes(1);
    expect(h.mintSpy.mock.calls[0][0]).toEqual({
      tokenMinLifetimeMs: 10 * 60 * 1000,
      permissions: {
        contents: "write",
        pull_requests: "write",
        issues: "write",
        checks: "read",
      },
      repositories: ["soleur"],
    });
  });

  it("filters to soleur-ai[bot] + armed auto_merge + non-draft; updates behind PRs oldest-first within the cap", async () => {
    const pulls = [
      // newest first in the list; oldest-first ordering must reorder
      BOT_PR(12, "2026-09-30T08:00:00Z"),
      BOT_PR(10, "2026-09-28T08:00:00Z"),
      BOT_PR(11, "2026-09-29T08:00:00Z"),
      { ...BOT_PR(13, "2026-09-27T08:00:00Z"), user: { login: "jean" } }, // not the bot
      { ...BOT_PR(14, "2026-09-26T08:00:00Z"), auto_merge: null }, // not armed
      { ...BOT_PR(15, "2026-09-25T08:00:00Z"), draft: true }, // draft excluded
    ];
    const details: Record<number, Record<string, unknown>> = {};
    for (const n of [10, 11, 12]) {
      details[n] = { number: n, mergeable_state: "behind", head: { sha: `sha${n}` } };
    }
    const checkRuns: Record<string, Array<{ status: string }>> = {};
    for (const n of [10, 11, 12]) checkRuns[`sha${n}`] = [{ status: "completed" }];

    h.requestSpy.mockImplementation(async (route: string, params: Record<string, unknown>) => {
      if (route === "GET /repos/{owner}/{repo}/pulls") return { data: pulls };
      if (route === "GET /repos/{owner}/{repo}/pulls/{pull_number}") {
        return { data: details[params.pull_number as number] };
      }
      if (route.includes("check-runs")) {
        return { data: { check_runs: checkRuns[params.ref as string] ?? [] } };
      }
      if (route.includes("update-branch")) return { status: 202, data: {} };
      if (route === "GET /repos/{owner}/{repo}/issues") return { data: [] };
      throw new Error(`unexpected ${route}`);
    });

    const result = await cronBotPrReaperHandler({ step: makeStep(), logger });
    expect(result.ok).toBe(true);
    const updates = h.requestSpy.mock.calls.filter(([r]) =>
      String(r).includes("update-branch"),
    );
    expect(updates.map(([, p]) => (p as Record<string, unknown>).pull_number)).toEqual([
      10, 11, 12, // oldest-first
    ]);
    expect(h.heartbeatSpy).toHaveBeenCalledTimes(1);
    expect(h.heartbeatSpy.mock.calls[0][0]).toMatchObject({
      ok: true,
      sentryMonitorSlug: "scheduled-bot-pr-reaper",
    });
  });

  it("stuck PRs (dirty/blocked/unstable) → dedup issue + aggregated reportSilentFallback", async () => {
    const pulls = [BOT_PR(20, "2026-09-30T08:00:00Z")];
    h.requestSpy.mockImplementation(async (route: string, _params: Record<string, unknown>) => {
      if (route === "GET /repos/{owner}/{repo}/pulls") return { data: pulls };
      if (route === "GET /repos/{owner}/{repo}/pulls/{pull_number}") {
        return { data: { number: 20, mergeable_state: "dirty", head: { sha: "x" } } };
      }
      if (route === "GET /repos/{owner}/{repo}/issues") return { data: [] };
      if (route === "POST /repos/{owner}/{repo}/issues") return { data: { number: 9901 } };
      throw new Error(`unexpected ${route}`);
    });

    const result = await cronBotPrReaperHandler({ step: makeStep(), logger });
    expect(result.ok).toBe(true);
    const create = h.requestSpy.mock.calls.find(
      ([r]) => r === "POST /repos/{owner}/{repo}/issues",
    );
    expect(create).toBeDefined();
    expect((create![1] as Record<string, unknown>).title).toBe(
      "[ci/bot-pr-reaper] bot PRs unmergeable without intervention",
    );
    expect((create![1] as Record<string, unknown>).labels).toEqual([
      "action-required",
      "domain/engineering",
    ]);
    expect(h.reportSilentFallbackSpy).toHaveBeenCalledTimes(1);
    expect(h.reportSilentFallbackSpy.mock.calls[0][1]).toMatchObject({
      op: "bot-pr-unmergeable",
      feature: "cron-bot-pr-reaper",
    });
  });

  it("drained stuck set → self-closes the open tracking issue", async () => {
    h.requestSpy.mockImplementation(async (route: string, _params: Record<string, unknown>) => {
      if (route === "GET /repos/{owner}/{repo}/pulls") return { data: [] };
      if (route === "GET /repos/{owner}/{repo}/issues") {
        return {
          data: [
            {
              title: "[ci/bot-pr-reaper] bot PRs unmergeable without intervention",
              number: 8811,
            },
          ],
        };
      }
      if (route === "POST /repos/{owner}/{repo}/issues/{issue_number}/comments") {
        return { status: 201, data: {} };
      }
      if (route === "PATCH /repos/{owner}/{repo}/issues/{issue_number}") {
        return { status: 200, data: {} };
      }
      throw new Error(`unexpected ${route}`);
    });

    await cronBotPrReaperHandler({ step: makeStep(), logger });
    const close = h.requestSpy.mock.calls.find(
      ([r, p]) =>
        r === "PATCH /repos/{owner}/{repo}/issues/{issue_number}" &&
        (p as Record<string, unknown>).issue_number === 8811 &&
        (p as Record<string, unknown>).state === "closed",
    );
    expect(close).toBeDefined();
  });

  it("a per-PR API failure is reported and recorded but does not fail the sweep; heartbeat still lands", async () => {
    const pulls = [BOT_PR(30, "2026-09-30T08:00:00Z"), BOT_PR(31, "2026-09-29T08:00:00Z")];
    h.requestSpy.mockImplementation(async (route: string, params: Record<string, unknown>) => {
      if (route === "GET /repos/{owner}/{repo}/pulls") return { data: pulls };
      if (route === "GET /repos/{owner}/{repo}/pulls/{pull_number}") {
        if (params.pull_number === 31) throw new Error("fake-installation-token boom 500");
        return { data: { number: 30, mergeable_state: "clean", head: { sha: "s30" } } };
      }
      if (route === "GET /repos/{owner}/{repo}/issues") return { data: [] };
      throw new Error(`unexpected ${route}`);
    });

    const result = await cronBotPrReaperHandler({ step: makeStep(), logger });
    expect(result.ok).toBe(false); // error surfaced, not hidden
    expect(h.reportSilentFallbackSpy).toHaveBeenCalledTimes(1);
    expect(h.reportSilentFallbackSpy.mock.calls[0][1]).toMatchObject({
      op: "bot-pr-update-failed",
    });
    const errArg = h.reportSilentFallbackSpy.mock.calls[0][0];
    const errMsg = errArg instanceof Error ? errArg.message : String(errArg);
    expect(errMsg).not.toContain("fake-installation-token");
    expect(h.heartbeatSpy).toHaveBeenCalledTimes(1);
    expect(h.heartbeatSpy.mock.calls[0][0]).toMatchObject({ ok: false });
  });

  it("update-branch cap: >5 eligible PRs → exactly 5 updates fire", async () => {
    const pulls = Array.from({ length: 7 }, (_, i) =>
      BOT_PR(40 + i, `2026-09-${String(20 + i).padStart(2, "0")}T08:00:00Z`),
    );
    h.requestSpy.mockImplementation(async (route: string, params: Record<string, unknown>) => {
      if (route === "GET /repos/{owner}/{repo}/pulls") return { data: pulls };
      if (route === "GET /repos/{owner}/{repo}/pulls/{pull_number}") {
        const n = params.pull_number as number;
        return { data: { number: n, mergeable_state: "behind", head: { sha: `s${n}` } } };
      }
      if (route.includes("check-runs")) return { data: { check_runs: [{ status: "completed" }] } };
      if (route.includes("update-branch")) return { status: 202, data: {} };
      if (route === "GET /repos/{owner}/{repo}/issues") return { data: [] };
      throw new Error(`unexpected ${route}`);
    });

    await cronBotPrReaperHandler({ step: makeStep(), logger });
    const updates = h.requestSpy.mock.calls.filter(([r]) =>
      String(r).includes("update-branch"),
    );
    expect(updates).toHaveLength(5);
    // oldest-first: PRs 40..44 (created 2026-09-20..24)
    expect(updates.map(([, p]) => (p as Record<string, unknown>).pull_number)).toEqual(
      [40, 41, 42, 43, 44],
    );
  });
});
