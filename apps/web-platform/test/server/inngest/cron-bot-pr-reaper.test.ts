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
  readMergeQueueRule,
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

// Synthesized rule lists (cq-test-fixtures-synthesized-only): the reaper reads
// rules by `.type`, never by position, so the queue rule sits second.
const RULES_ROUTE = "GET /repos/{owner}/{repo}/rules/branches/{branch}";
const NO_QUEUE_RULES = [
  { type: "required_status_checks" },
  { type: "deletion" },
  { type: "non_fast_forward" },
];
const QUEUE_RULES = [
  { type: "required_status_checks" },
  { type: "merge_queue" },
  { type: "deletion" },
];
const NOW = Date.parse("2026-10-22T12:00:00Z");
const HOUR = 60 * 60 * 1000;
const hoursAgo = (hrs: number) => new Date(NOW - hrs * HOUR).toISOString();
// Existing direct reapBotPr cases mean "no queue": the verdict is a required
// arg, and an old createdAt proves the none path ignores age.
const NONE_ARGS = { queueRule: "none" as const, createdAt: "2026-01-01T00:00:00Z" };

// Minimal route-dispatching octokit stub. `pulls` is the list response; each
// `details[n]` is the GET /pulls/{n} body; `checkRuns[sha]` the check-runs
// response; `issues` the open-issues list used by ensureDedupIssue and the
// self-close scan.
function octokitStub(opts: {
  pulls: Array<Record<string, unknown>>;
  details: Record<number, Record<string, unknown>>;
  checkRuns?: Record<string, Array<{ status: string }>>;
  issues?: Array<{ title: string; number: number }>;
  rules?: unknown;
  rulesThrow?: unknown;
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
    if (route === RULES_ROUTE) {
      if (opts.rulesThrow !== undefined) throw opts.rulesThrow;
      return { data: "rules" in opts ? opts.rules : NO_QUEUE_RULES };
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
    ['"merge_queue"', "rule selected by type"],
    ["rules/branches", "rules read endpoint"],
    ["read-merge-queue-rule", "memoized once-per-sweep verdict step"],
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
      ...NONE_ARGS,
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
      ...NONE_ARGS,
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
      ...NONE_ARGS,
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
      ...NONE_ARGS,
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
        ...NONE_ARGS,
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
      ...NONE_ARGS,
      logger,
    });
    expect(r.action).toMatch(/^skipped-/);
    expect(stub.calls.some((c) => c.route.includes("update-branch"))).toBe(false);
  });

  describe("queue-owned behind PRs (verdict passed by value)", () => {
    const run = (
      stub: ReturnType<typeof mk>,
      over: Partial<Parameters<typeof reapBotPr>[0]> & {
        queueRule: "queue" | "none" | "unreadable";
        createdAt: string;
      },
    ) =>
      reapBotPr({
        octokit: { request: stub.request } as never,
        prNumber: 1,
        updatesUsed: 0,
        updatesCap: 5,
        unknownRereadDelayMs: 0,
        nowMs: NOW,
        logger,
        ...over,
      });
    const updated = (stub: ReturnType<typeof mk>) =>
      stub.calls.some((c) => c.route.includes("update-branch"));
    const checked = (stub: ReturnType<typeof mk>) =>
      stub.calls.some((c) => c.route.includes("check-runs"));

    it("queue + terminal checks inside the grace → skipped-queue-owned, no update, no check-runs read", async () => {
      const stub = mk("behind", [{ status: "completed" }]);
      const r = await run(stub, { queueRule: "queue", createdAt: hoursAgo(1) });
      expect(r.action).toBe("skipped-queue-owned");
      expect(updated(stub)).toBe(false);
      expect(checked(stub)).toBe(false);
    });

    it("queue + update cap reached → still skipped-queue-owned (the verdict precedes the cap)", async () => {
      const stub = mk("behind", [{ status: "completed" }]);
      const r = await run(stub, {
        queueRule: "queue",
        createdAt: hoursAgo(1),
        updatesUsed: 5,
      });
      expect(r.action).toBe("skipped-queue-owned");
      expect(updated(stub)).toBe(false);
    });

    it("unreadable inside the grace → skipped-queue-unknown, no update (fail closed)", async () => {
      const stub = mk("behind", [{ status: "completed" }]);
      const r = await run(stub, { queueRule: "unreadable", createdAt: hoursAgo(1) });
      expect(r.action).toBe("skipped-queue-unknown");
      expect(updated(stub)).toBe(false);
      expect(checked(stub)).toBe(false);
    });

    it("none keeps today's path whatever the PR age → updated with expected_head_sha", async () => {
      const stub = mk("behind", [{ status: "completed" }]);
      const r = await run(stub, { queueRule: "none", createdAt: hoursAgo(500) });
      expect(r.action).toBe("updated");
      expect(
        stub.calls.find((c) => c.route.includes("update-branch"))?.params
          .expected_head_sha,
      ).toBe("abc123");
    });

    it("the 6 h bound is inclusive: exactly 6 h is still owned, 6 h + 1 ms alerts", async () => {
      const at = mk("behind", [{ status: "completed" }]);
      const rAt = await run(at, {
        queueRule: "queue",
        createdAt: new Date(NOW - 6 * HOUR).toISOString(),
      });
      expect(rAt.action).toBe("skipped-queue-owned");
      const past = mk("behind", [{ status: "completed" }]);
      const rPast = await run(past, {
        queueRule: "queue",
        createdAt: new Date(NOW - 6 * HOUR - 1).toISOString(),
      });
      expect(rPast.action).toBe("stuck-alerted");
      expect(updated(past)).toBe(false);
    });

    it("queue past 6 h with terminal checks → stuck-alerted (queue-stalled), never updated", async () => {
      const stub = mk("behind", [{ status: "completed" }]);
      const r = await run(stub, { queueRule: "queue", createdAt: hoursAgo(7) });
      expect(r.action).toBe("stuck-alerted");
      expect(r.reason).toBe("queue-stalled");
      expect(updated(stub)).toBe(false);
    });

    it("unreadable past 6 h with terminal checks → stuck-alerted (queue-rule-unreadable)", async () => {
      const stub = mk("behind", [{ status: "completed" }]);
      const r = await run(stub, { queueRule: "unreadable", createdAt: hoursAgo(7) });
      expect(r.action).toBe("stuck-alerted");
      expect(r.reason).toBe("queue-rule-unreadable");
      expect(updated(stub)).toBe(false);
    });

    it("past 6 h with checks in flight → skipped-checks-in-flight until 24 h", async () => {
      const stub = mk("behind", [{ status: "in_progress" }]);
      const r = await run(stub, { queueRule: "queue", createdAt: hoursAgo(7) });
      expect(r.action).toBe("skipped-checks-in-flight");
      expect(updated(stub)).toBe(false);
    });

    it("past 24 h a hung check no longer hides the PR → stuck-alerted (queue-stalled-checks-running)", async () => {
      const stub = mk("behind", [{ status: "queued" }]);
      const r = await run(stub, { queueRule: "queue", createdAt: hoursAgo(25) });
      expect(r.action).toBe("stuck-alerted");
      expect(r.reason).toBe("queue-stalled-checks-running");
      const u = mk("behind", [{ status: "queued" }]);
      const ru = await run(u, { queueRule: "unreadable", createdAt: hoursAgo(25) });
      expect(ru.action).toBe("stuck-alerted");
      expect(ru.reason).toBe("queue-rule-unreadable");
    });

    it("an unparseable createdAt counts as past both bounds (alerts, never hides)", async () => {
      const terminal = mk("behind", [{ status: "completed" }]);
      const r1 = await run(terminal, { queueRule: "queue", createdAt: "not-a-date" });
      expect(r1.action).toBe("stuck-alerted");
      const hung = mk("behind", [{ status: "in_progress" }]);
      const r2 = await run(hung, { queueRule: "queue", createdAt: "" });
      expect(r2.action).toBe("stuck-alerted");
      expect(updated(terminal) || updated(hung)).toBe(false);
    });

    it.each(["dirty", "blocked", "unstable"])(
      "%s → stuck-alerted, no update, under every verdict",
      async (state) => {
        for (const queueRule of ["queue", "none", "unreadable"] as const) {
          const stub = mk(state);
          const r = await run(stub, { queueRule, createdAt: hoursAgo(1) });
          expect(r.action).toBe("stuck-alerted");
          expect(r.reason).toBeUndefined();
          expect(updated(stub)).toBe(false);
        }
      },
    );
  });

  it("unknown → one re-read, still unknown → skipped-unknown", async () => {
    const stub = mk("unknown");
    const r = await reapBotPr({
      octokit: { request: stub.request } as never,
      prNumber: 1,
      updatesUsed: 0,
      updatesCap: 5,
      unknownRereadDelayMs: 0,
      ...NONE_ARGS,
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
      ...NONE_ARGS,
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
      ...NONE_ARGS,
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
      if (route === RULES_ROUTE) return { data: NO_QUEUE_RULES };
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

  // ensureDedupIssue pays its production 5s miss-retry inside the step here.
  it("stuck PRs (dirty/blocked/unstable) → dedup issue + aggregated reportSilentFallback", { timeout: 15_000 }, async () => {
    const pulls = [BOT_PR(20, "2026-09-30T08:00:00Z")];
    h.requestSpy.mockImplementation(async (route: string, _params: Record<string, unknown>) => {
      if (route === RULES_ROUTE) return { data: NO_QUEUE_RULES };
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
      "ci/bot-pr-reaper",
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
      if (route === RULES_ROUTE) return { data: NO_QUEUE_RULES };
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
      if (route === RULES_ROUTE) return { data: NO_QUEUE_RULES };
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
      if (route === RULES_ROUTE) return { data: NO_QUEUE_RULES };
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

describe("readMergeQueueRule — fail-closed verdict", () => {
  const read = (opts: Parameters<typeof octokitStub>[0]) => {
    const stub = octokitStub(opts);
    return { stub, p: readMergeQueueRule({ request: stub.request } as never) };
  };
  const base = { pulls: [], details: {} };
  const filler = (n: number) =>
    Array.from({ length: n }, (_, i) => ({ type: `unrelated_${i}` }));

  it("merge_queue as the second of five rules → queue (selected by type, not position)", async () => {
    const { p } = read({ ...base, rules: [...QUEUE_RULES, { type: "a" }, { type: "b" }] });
    await expect(p).resolves.toMatchObject({ verdict: "queue" });
  });

  it("five unrelated rules → none (a guard that rejects everything cannot pass this)", async () => {
    const { p } = read({ ...base, rules: filler(5) });
    await expect(p).resolves.toEqual({ verdict: "none" });
  });

  it("merge_queue at index 99 of 100 → queue", async () => {
    const rules = [...filler(99), { type: "merge_queue" }];
    expect(rules).toHaveLength(100);
    const { p } = read({ ...base, rules });
    await expect(p).resolves.toMatchObject({ verdict: "queue" });
  });

  it("100 rules without merge_queue → unreadable (the rule may sit on a later page)", async () => {
    const { p } = read({ ...base, rules: filler(100) });
    const r = await p;
    expect(r.verdict).toBe("unreadable");
    expect(typeof r.cause).toBe("string");
  });

  it.each([
    ["403", Object.assign(new Error("Forbidden"), { status: 403 })],
    ["500", Object.assign(new Error("Server Error"), { status: 500 })],
  ])("a %s rejection → unreadable with a cause string, never throws", async (_n, err) => {
    const { p } = read({ ...base, rulesThrow: err });
    const r = await p;
    expect(r.verdict).toBe("unreadable");
    expect(typeof r.cause).toBe("string");
    expect(r.cause).toContain((err as Error).message);
  });

  it.each([
    ["an object", { message: "degraded" }],
    ["null", null],
    ["a string", "[]"],
  ])("a non-list body (%s) → unreadable, not empty", async (_n, rules) => {
    const { p } = read({ ...base, rules });
    expect((await p).verdict).toBe("unreadable");
  });

  it("requests the main branch rules with per_page 100", async () => {
    const { stub, p } = read({ ...base, rules: QUEUE_RULES });
    await p;
    const call = stub.calls.find((c) => c.route === RULES_ROUTE);
    expect(call?.params).toMatchObject({ branch: "main", per_page: 100 });
  });
});

describe("cronBotPrReaperHandler — merge-queue deferral", () => {
  beforeEach(() => {
    h.requestSpy.mockReset();
    h.reportSilentFallbackSpy.mockClear();
    h.mintSpy.mockClear();
    h.heartbeatSpy.mockClear();
  });

  const recently = (hrs: number) => new Date(Date.now() - hrs * HOUR).toISOString();
  const behindDetails = (ns: number[]) =>
    Object.fromEntries(
      ns.map((n) => [
        n,
        { number: n, mergeable_state: "behind", head: { sha: `sha${n}` } },
      ]),
    );
  const updatesOf = (stub: ReturnType<typeof octokitStub>) =>
    stub.calls.filter((c) => c.route.includes("update-branch"));
  const rulesCallsOf = (stub: ReturnType<typeof octokitStub>) =>
    stub.calls.filter((c) => c.route === RULES_ROUTE);

  it("queue sweep: three behind PRs → zero update-branch, exactly one rules read, no check-runs", async () => {
    const pulls = [10, 11, 12].map((n) => BOT_PR(n, recently(1 + n / 100)));
    const stub = octokitStub({
      pulls,
      details: behindDetails([10, 11, 12]),
      rules: QUEUE_RULES,
    });
    h.requestSpy.mockImplementation(stub.request);
    const result = await cronBotPrReaperHandler({ step: makeStep(), logger });
    expect(result.ok).toBe(true);
    expect(updatesOf(stub)).toHaveLength(0);
    expect(rulesCallsOf(stub)).toHaveLength(1);
    expect(stub.calls.some((c) => c.route.includes("check-runs"))).toBe(false);
  });

  it("no-queue sweep: updates oldest-first within the cap, still exactly one rules read", async () => {
    const ns = [40, 41, 42, 43, 44, 45, 46];
    const pulls = ns.map((n, i) =>
      BOT_PR(n, `2026-09-${String(20 + i).padStart(2, "0")}T08:00:00Z`),
    );
    const checkRuns = Object.fromEntries(
      ns.map((n) => [`sha${n}`, [{ status: "completed" }]]),
    );
    const stub = octokitStub({
      pulls: [...pulls].reverse(),
      details: behindDetails(ns),
      checkRuns,
      rules: NO_QUEUE_RULES,
    });
    h.requestSpy.mockImplementation(stub.request);
    await cronBotPrReaperHandler({ step: makeStep(), logger });
    expect(updatesOf(stub).map((c) => c.params.pull_number)).toEqual([40, 41, 42, 43, 44]);
    expect(rulesCallsOf(stub)).toHaveLength(1);
  });

  it("unreadable sweep: zero updates, one redacted merge-queue-rule-unreadable report, heartbeat still posted", async () => {
    const stub = octokitStub({
      pulls: [BOT_PR(50, recently(1))],
      details: behindDetails([50]),
      rulesThrow: Object.assign(
        new Error("Forbidden for fake-installation-token"),
        { status: 403 },
      ),
    });
    h.requestSpy.mockImplementation(stub.request);
    const result = await cronBotPrReaperHandler({ step: makeStep(), logger });
    expect(result.ok).toBe(true);
    expect(updatesOf(stub)).toHaveLength(0);
    expect(h.reportSilentFallbackSpy).toHaveBeenCalledTimes(1);
    expect(h.reportSilentFallbackSpy.mock.calls[0][1]).toMatchObject({
      op: "merge-queue-rule-unreadable",
      feature: "cron-bot-pr-reaper",
    });
    const errArg = h.reportSilentFallbackSpy.mock.calls[0][0];
    const errMsg = errArg instanceof Error ? errArg.message : String(errArg);
    expect(errMsg).not.toContain("fake-installation-token");
    expect(h.heartbeatSpy).toHaveBeenCalledTimes(1);
    expect(h.heartbeatSpy.mock.calls[0][0]).toMatchObject({ ok: true });
  });

  it("no bot PRs → the rules route is never called", async () => {
    const stub = octokitStub({ pulls: [], details: {}, rules: QUEUE_RULES });
    h.requestSpy.mockImplementation(stub.request);
    await cronBotPrReaperHandler({ step: makeStep(), logger });
    expect(rulesCallsOf(stub)).toHaveLength(0);
  });

  // ensureDedupIssue pays its production 5s miss-retry inside the step here.
  it("a stalled queue PR → dedup issue with the neutral reason line, reason in the Sentry extra", { timeout: 15_000 }, async () => {
    const stub = octokitStub({
      pulls: [BOT_PR(60, recently(7))],
      details: behindDetails([60]),
      checkRuns: { sha60: [{ status: "completed" }] },
      rules: QUEUE_RULES,
    });
    h.requestSpy.mockImplementation(stub.request);
    await cronBotPrReaperHandler({ step: makeStep(), logger });
    expect(updatesOf(stub)).toHaveLength(0);
    const create = stub.calls.find((c) => c.route === "POST /repos/{owner}/{repo}/issues");
    expect(create).toBeDefined();
    const body = String(create!.params.body);
    expect(body).toContain("#60");
    expect(body).toContain("not enqueued after 6h");
    expect(body).not.toMatch(/\bgreen\b/);
    expect(h.reportSilentFallbackSpy).toHaveBeenCalledTimes(1);
    const report = h.reportSilentFallbackSpy.mock.calls[0][1] as {
      op: string;
      extra: { prs: Array<{ number: number; reason?: string }>; issueNumber?: number };
    };
    expect(report.op).toBe("bot-pr-unmergeable");
    expect(report.extra.prs).toEqual([
      expect.objectContaining({ number: 60, reason: "queue-stalled" }),
    ]);
    expect(report.extra.issueNumber).toBe(9900);
  });

  it("a dirty PR under a queue verdict still files the stuck issue", { timeout: 15_000 }, async () => {
    const stub = octokitStub({
      pulls: [BOT_PR(70, recently(1))],
      details: { 70: { number: 70, mergeable_state: "dirty", head: { sha: "x" } } },
      rules: QUEUE_RULES,
    });
    h.requestSpy.mockImplementation(stub.request);
    await cronBotPrReaperHandler({ step: makeStep(), logger });
    expect(
      stub.calls.some((c) => c.route === "POST /repos/{owner}/{repo}/issues"),
    ).toBe(true);
    expect(h.reportSilentFallbackSpy.mock.calls[0][1]).toMatchObject({
      op: "bot-pr-unmergeable",
    });
  });

  it("replay: a memoizing step.run fake invoked twice reads the rules exactly once", async () => {
    const memo = new Map<string, unknown>();
    // Inngest persists step results as JSON: round-trip so a non-serializable
    // verdict (or an in-memory cache standing in for the step) cannot pass.
    const replayStep = {
      run: async <T>(name: string, cb: () => Promise<T>): Promise<T> => {
        if (memo.has(name)) return memo.get(name) as T;
        const v = await cb();
        memo.set(name, v === undefined ? v : JSON.parse(JSON.stringify(v)));
        return memo.get(name) as T;
      },
    };
    const stub = octokitStub({
      pulls: [BOT_PR(80, recently(1))],
      details: behindDetails([80]),
      rules: QUEUE_RULES,
    });
    h.requestSpy.mockImplementation(stub.request);
    await cronBotPrReaperHandler({ step: replayStep, logger });
    await cronBotPrReaperHandler({ step: replayStep, logger });
    expect(rulesCallsOf(stub)).toHaveLength(1);
    expect(updatesOf(stub)).toHaveLength(0);
  });
});
