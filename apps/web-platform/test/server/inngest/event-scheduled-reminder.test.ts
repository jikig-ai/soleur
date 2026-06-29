import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// --- Module mocks (hoisted by vitest), mirroring oneshot-4650 -------------

const {
  reportSilentFallbackSpy,
  warnSilentFallbackSpy,
  mintInstallationTokenSpy,
  octokitRequestSpy,
} = vi.hoisted(() => ({
  reportSilentFallbackSpy: vi.fn(),
  warnSilentFallbackSpy: vi.fn(),
  mintInstallationTokenSpy: vi.fn(async () => "ghs_test_token_abc"),
  octokitRequestSpy: vi.fn(),
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: reportSilentFallbackSpy,
  warnSilentFallback: warnSilentFallbackSpy,
}));

vi.mock("@/server/inngest/client", () => ({
  inngest: { createFunction: vi.fn(), send: vi.fn() },
}));

vi.mock("@/server/inngest/functions/_cron-shared", async () => {
  const actual = await vi.importActual<
    typeof import("@/server/inngest/functions/_cron-shared")
  >("@/server/inngest/functions/_cron-shared");
  return { ...actual, mintInstallationToken: mintInstallationTokenSpy };
});

vi.mock("@octokit/core", () => ({
  Octokit: vi.fn().mockImplementation(function (this: Record<string, unknown>) {
    this.request = octokitRequestSpy;
  }),
}));

// Neutralize the retry backoff so the suite runs instantly while keeping the
// real `isRetryable` classifier (the retry decision is under test; the sleep is
// not). Partial-mock avoids fake-timer interaction with `AbortSignal.timeout`.
vi.mock("@/server/github-retry", async (orig) => ({
  ...(await orig<typeof import("@/server/github-retry")>()),
  delay: vi.fn(() => Promise.resolve()),
}));

import {
  eventScheduledReminderHandler,
  CHECK_REGISTRY,
} from "@/server/inngest/functions/event-scheduled-reminder";
// `delay` is the partial-mocked no-op (see vi.mock above) — imported so the
// bounded-retry test can assert the exact backoff SCHEDULE, not just the count.
import { delay } from "@/server/github-retry";

// --- Helpers ----------------------------------------------------------------

function makeStep() {
  const calls: { name: string }[] = [];
  return {
    calls,
    async run<T>(name: string, cb: () => Promise<T>): Promise<T> {
      calls.push({ name });
      return cb();
    },
  };
}

function run(data: Record<string, unknown>) {
  const step = makeStep();
  return {
    step,
    result: eventScheduledReminderHandler({
      event: { data },
      step,
    } as never),
  };
}

const FIRE_AT = "2026-06-04T09:45:00Z";

beforeEach(() => {
  reportSilentFallbackSpy.mockReset();
  warnSilentFallbackSpy.mockReset();
  octokitRequestSpy.mockReset();
  mintInstallationTokenSpy.mockClear();
  octokitRequestSpy.mockResolvedValue({ data: [] });
});

describe("eventScheduledReminderHandler — guards", () => {
  it("invalid fire_at → reportSilentFallback(invalid-fire-at), no IO", async () => {
    const { result, step } = run({
      reminder_id: "r1",
      fire_at: "not-a-date",
      actor: "platform",
      action: { type: "issue-comment", issue: 2714, body: "hi" },
    });
    expect(await result).toEqual({ ok: false, reason: "invalid-fire-at" });
    expect(reportSilentFallbackSpy.mock.calls[0][1].op).toBe("invalid-fire-at");
    expect(step.calls).toHaveLength(0);
    expect(octokitRequestSpy).not.toHaveBeenCalled();
  });

  it("non-allowlisted action.type → reject, no IO", async () => {
    const { result, step } = run({
      reminder_id: "r1",
      fire_at: FIRE_AT,
      actor: "platform",
      action: { type: "label", issue: 1, name: "bug" },
    });
    expect(await result).toEqual({ ok: false, reason: "action-not-allowlisted" });
    expect(reportSilentFallbackSpy.mock.calls[0][1].op).toBe("action-not-allowlisted");
    expect(step.calls).toHaveLength(0);
  });

  it("issue-comment body over cap → reject before any IO", async () => {
    const { result } = run({
      reminder_id: "r1",
      fire_at: FIRE_AT,
      actor: "platform",
      action: { type: "issue-comment", issue: 1, body: "x".repeat(65001) },
    });
    expect(await result).toEqual({ ok: false, reason: "invalid-issue-comment" });
    expect(octokitRequestSpy).not.toHaveBeenCalled();
  });
});

describe("eventScheduledReminderHandler — issue-comment", () => {
  it("posts a comment via the installation token", async () => {
    const { result, step } = run({
      reminder_id: "r1",
      fire_at: FIRE_AT,
      actor: "platform",
      action: { type: "issue-comment", issue: 2714, body: "scheduled note" },
    });
    expect(await result).toEqual({ ok: true, reason: "issue-comment-posted" });
    expect(step.calls).toEqual([{ name: "post-comment" }]);
    expect(mintInstallationTokenSpy).toHaveBeenCalledTimes(1);
    const post = octokitRequestSpy.mock.calls.find(
      (c) => c[0] === "POST /repos/{owner}/{repo}/issues/{issue_number}/comments",
    );
    expect(post![1]).toMatchObject({ issue_number: 2714, body: "scheduled note" });
    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();
  });
});

describe("eventScheduledReminderHandler — named-check", () => {
  it("unregistered check → reportSilentFallback(unregistered-check), no comment", async () => {
    const { result } = run({
      reminder_id: "r1",
      fire_at: FIRE_AT,
      actor: "platform",
      action: { type: "named-check", check: "does-not-exist", report_to_issue: 2714 },
    });
    expect(await result).toEqual({ ok: false, reason: "unregistered-check" });
    expect(reportSilentFallbackSpy.mock.calls[0][1].op).toBe("unregistered-check");
    const posts = octokitRequestSpy.mock.calls.filter((c) =>
      String(c[0]).includes("/comments"),
    );
    expect(posts).toHaveLength(0);
  });

  it("registered demonstrator → runs check, posts body to report_to_issue", async () => {
    // The seeded check reads cloud-task-silence issues, then posts.
    octokitRequestSpy.mockImplementation(async (route: string) => {
      if (route === "GET /repos/{owner}/{repo}/issues") {
        return { data: [{ id: 1 }, { id: 2 }] };
      }
      return { data: {} };
    });
    const { result } = run({
      reminder_id: "r1",
      fire_at: FIRE_AT,
      actor: "platform",
      action: {
        type: "named-check",
        check: "open-silence-issue-count",
        report_to_issue: 2714,
      },
    });
    expect(await result).toEqual({ ok: true, reason: "named-check-info" });
    const post = octokitRequestSpy.mock.calls.find(
      (c) => c[0] === "POST /repos/{owner}/{repo}/issues/{issue_number}/comments",
    );
    expect(post![1]).toMatchObject({ issue_number: 2714 });
    expect((post![1] as { body: string }).body).toContain("2 open");
    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();
  });

  it("verdict fail → reportSilentFallback(named-check-failed) but still posts", async () => {
    // Inject a temporary failing check into the registry (restore after).
    CHECK_REGISTRY["__test-fail"] = async () => ({ verdict: "fail", body: "boom" });
    try {
      const { result } = run({
        reminder_id: "r1",
        fire_at: FIRE_AT,
        actor: "platform",
        action: { type: "named-check", check: "__test-fail", report_to_issue: 2714 },
      });
      expect(await result).toEqual({ ok: true, reason: "named-check-fail" });
      expect(reportSilentFallbackSpy.mock.calls[0][1].op).toBe("named-check-failed");
      const post = octokitRequestSpy.mock.calls.find(
        (c) => c[0] === "POST /repos/{owner}/{repo}/issues/{issue_number}/comments",
      );
      expect((post![1] as { body: string }).body).toBe("boom");
    } finally {
      delete CHECK_REGISTRY["__test-fail"];
    }
  });

  it("registers exactly the reviewed checks (registry membership is code-reviewed)", () => {
    // Adding/removing a CHECK_REGISTRY key is a deliberate, code-reviewed change —
    // this exact-set assertion forces that review (a stray/typo'd key fails CI).
    expect(new Set(Object.keys(CHECK_REGISTRY))).toEqual(
      new Set(["open-silence-issue-count", "sentry-issue-rate"]),
    );
  });
});

// --- sentry-issue-rate named-check (#5417 follow-on) ------------------------

describe("eventScheduledReminderHandler — sentry-issue-rate", () => {
  const ENV = {
    SENTRY_API_HOST: "jikigai-eu.sentry.io",
    SENTRY_ORG: "jikigai-eu",
    SENTRY_PROJECT: "web-platform",
    SENTRY_ISSUE_RW_TOKEN: "sntrytok_secret_value_xyz",
  };
  let fetchMock: ReturnType<typeof vi.fn>;
  const dailyStats = (counts: number[]) =>
    counts.map((c, i) => [1_700_000_000 + i * 86_400, c]);

  function stubFetch(opts: {
    issues?: unknown;
    issuesStatus?: number;
    stats?: unknown; // the daily `.stats["30d"]` series (wrapped into the detail body)
    detail?: unknown; // override the whole issue-detail body (for shape tests)
    statsStatus?: number;
  }) {
    fetchMock = vi.fn(async (url: string) => {
      // issue-DETAIL GET: `…/issues/<id>/` with no `?query=` (vs the search list).
      if (/\/issues\/[^/?]+\/(\?|$)/.test(url)) {
        const status = opts.statsStatus ?? 200;
        const body =
          "detail" in opts ? opts.detail : { stats: { "30d": opts.stats } };
        return { ok: status < 400, status, json: async () => body, text: async () => "" };
      }
      const status = opts.issuesStatus ?? 200;
      return { ok: status < 400, status, json: async () => opts.issues, text: async () => "" };
    });
    vi.stubGlobal("fetch", fetchMock);
  }

  // Per-URL-class response SEQUENCING (vs stubFetch's single fixed response):
  // each call to the search URL or the detail URL consumes the NEXT entry from
  // its queue, so attempt 1 and attempt 2 of the SAME url can differ. A queue
  // entry is either a thrown error (network/timeout) or a `{ status, body }`.
  // The last entry is reused once a queue is drained (mirrors mockImplementation
  // fall-through), so a single trailing success serves any remaining attempts.
  type SeqEntry = Error | { status?: number; body?: unknown };
  function stubFetchSequence(opts: { search: SeqEntry[]; detail?: SeqEntry[] }) {
    const search = [...opts.search];
    const detail = [...(opts.detail ?? [])];
    const take = (q: SeqEntry[]): SeqEntry => (q.length > 1 ? q.shift()! : q[0]);
    fetchMock = vi.fn(async (url: string) => {
      const isDetail = /\/issues\/[^/?]+\/(\?|$)/.test(url);
      const entry = isDetail ? take(detail) : take(search);
      if (entry instanceof Error) throw entry;
      const status = entry.status ?? 200;
      // `text` mirrors a real fetch Response — the retry loop drains the body of
      // a transient 5xx/429 before backing off (socket keep-alive hygiene).
      return {
        ok: status < 400,
        status,
        json: async () => entry.body,
        text: async () => "",
      };
    });
    vi.stubGlobal("fetch", fetchMock);
  }
  // Count fetch invocations whose URL is the search list (no detail-path shape).
  const searchCalls = () =>
    fetchMock.mock.calls.filter(
      (c) => !/\/issues\/[^/?]+\/(\?|$)/.test(String(c[0])),
    ).length;
  // Count fetch invocations to the issue-DETAIL URL (the search-call inverse).
  const detailCalls = () =>
    fetchMock.mock.calls.filter((c) =>
      /\/issues\/[^/?]+\/(\?|$)/.test(String(c[0])),
    ).length;
  const timeoutError = () =>
    new DOMException("The operation timed out", "TimeoutError");
  // The exact undici network-error shape `isRetryable` classifies transient.
  const networkError = () => new TypeError("fetch failed");
  const passSeries = dailyStats([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0]);

  function arm(params: Record<string, unknown>, reportTo = 5417) {
    return run({
      reminder_id: "r1",
      fire_at: FIRE_AT,
      actor: "platform",
      action: { type: "named-check", check: "sentry-issue-rate", report_to_issue: reportTo, params },
    });
  }

  const okParams = { tag: "event_type:server-startup", max_per_day: 1, window_hours: 72 };

  beforeEach(() => {
    for (const [k, v] of Object.entries(ENV)) vi.stubEnv(k, v);
    octokitRequestSpy.mockResolvedValue({});
    vi.mocked(delay).mockClear(); // per-test backoff-call ledger
  });
  afterEach(() => {
    vi.unstubAllEnvs();
    vi.unstubAllGlobals();
  });

  function lastComment() {
    const post = octokitRequestSpy.mock.calls.find(
      (c) => c[0] === "POST /repos/{owner}/{repo}/issues/{issue_number}/comments",
    );
    return post?.[1] as { issue_number: number; body: string } | undefined;
  }
  function closeCall() {
    return octokitRequestSpy.mock.calls.find(
      (c) => c[0] === "PATCH /repos/{owner}/{repo}/issues/{issue_number}",
    );
  }

  it("pass + close_on_pass → posts report comment AND closes report_to_issue", async () => {
    stubFetch({ issues: [{ id: "120495109" }], stats: dailyStats([9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 0, 1, 0]) });
    const { result } = arm({ ...okParams, close_on_pass: true }, 5417);
    expect(await result).toEqual({ ok: true, reason: "named-check-pass" });
    expect(lastComment()!.body).toContain("**pass**");
    const close = closeCall();
    expect(close).toBeDefined();
    expect(close![1]).toMatchObject({ issue_number: 5417, state: "closed", state_reason: "completed" });
  });

  it("pass WITHOUT close_on_pass → comment, NO close", async () => {
    stubFetch({ issues: [{ id: "1" }], stats: dailyStats([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0]) });
    const { result } = arm({ ...okParams });
    expect(await result).toEqual({ ok: true, reason: "named-check-pass" });
    expect(lastComment()!.body).toContain("**pass**");
    expect(closeCall()).toBeUndefined();
  });

  it("fail (rate above threshold) → comment, NO close, reportSilentFallback(named-check-failed)", async () => {
    stubFetch({ issues: [{ id: "1" }], stats: dailyStats([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 40, 60, 12]) });
    const { result } = arm({ ...okParams, close_on_pass: true });
    expect(await result).toEqual({ ok: true, reason: "named-check-fail" });
    expect(lastComment()!.body).toContain("**fail**");
    expect(closeCall()).toBeUndefined();
    expect(reportSilentFallbackSpy.mock.calls.some((c) => c[1].op === "named-check-failed")).toBe(true);
  });

  it("ambiguous (>1 matching issues) → fail-closed info, NO close, no fetch to stats", async () => {
    stubFetch({ issues: [{ id: "1" }, { id: "2" }] });
    const { result } = arm({ ...okParams, close_on_pass: true });
    expect(await result).toEqual({ ok: true, reason: "named-check-info" });
    expect(lastComment()!.body).toContain("fail-closed");
    expect(closeCall()).toBeUndefined();
  });

  it("missing Sentry env → fail-closed info, NO fetch", async () => {
    vi.stubEnv("SENTRY_ISSUE_RW_TOKEN", "");
    stubFetch({ issues: [{ id: "1" }] });
    const { result } = arm({ ...okParams, close_on_pass: true });
    expect(await result).toEqual({ ok: true, reason: "named-check-info" });
    expect(lastComment()!.body).toContain("Sentry env not configured");
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("injection / invalid tag → fail-closed before any fetch", async () => {
    stubFetch({ issues: [{ id: "1" }] });
    const { result } = arm({ ...okParams, tag: "event_type:foo&admin=1", close_on_pass: true });
    expect(await result).toEqual({ ok: true, reason: "named-check-info" });
    expect(lastComment()!.body).toContain("invalid-tag");
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("token-non-leak: Sentry HTTP error → fail-closed body has no token/Bearer", async () => {
    stubFetch({ issuesStatus: 500 });
    const { result } = arm({ ...okParams, close_on_pass: true });
    expect(await result).toEqual({ ok: true, reason: "named-check-info" });
    const body = lastComment()!.body;
    expect(body).toContain("fail-closed");
    expect(body).not.toContain("Bearer");
    expect(body).not.toContain(ENV.SENTRY_ISSUE_RW_TOKEN);
    // also no token in any Sentry-side reported error
    for (const call of reportSilentFallbackSpy.mock.calls) {
      expect(JSON.stringify(call)).not.toContain(ENV.SENTRY_ISSUE_RW_TOKEN);
    }
  });

  it("uses the EU host from SENTRY_API_HOST (jikigai-eu.sentry.io, not eu.sentry.io)", async () => {
    stubFetch({ issues: [{ id: "1" }], stats: dailyStats([0, 1, 0]) });
    await arm({ ...okParams }).result;
    const urls = fetchMock.mock.calls.map((c) => String(c[0]));
    expect(urls.length).toBeGreaterThan(0);
    expect(urls.every((u) => u.startsWith("https://jikigai-eu.sentry.io/api/0/"))).toBe(true);
    expect(urls.some((u) => u.includes("query=event_type%3Aserver-startup"))).toBe(true);
  });

  it("reads daily buckets from the issue-DETAIL endpoint, not /stats/", async () => {
    stubFetch({ issues: [{ id: "120495109" }], stats: dailyStats([0, 1, 0]) });
    await arm({ ...okParams }).result;
    const statsUrls = fetchMock.mock.calls
      .map((c) => String(c[0]))
      .filter((u) => !u.includes("query="));
    // exactly one detail GET, ending `/issues/<id>/`, with no `/stats/` sub-path
    expect(statsUrls).toHaveLength(1);
    expect(statsUrls[0]).toMatch(/\/issues\/120495109\/$/);
    expect(statsUrls[0]).not.toContain("/stats/");
  });

  it("parses a REAL captured `.stats[30d]` daily series (still-churning → fail, NO close)", async () => {
    // Real last-7 daily buckets captured from jikigai-eu.sentry.io WEB-PLATFORM-1
    // (event_type:server-startup) on 2026-06-16 — the issue is still active.
    const realDaily = [
      [1781049600, 16], [1781136000, 40], [1781222400, 42], [1781308800, 0],
      [1781395200, 28], [1781481600, 60], [1781568000, 32],
    ];
    stubFetch({ issues: [{ id: "120495109" }], stats: realDaily });
    const { result } = arm({ ...okParams, close_on_pass: true }); // window 72h → last 3 days = 28+60+32 = 120/3 = 40/day
    expect(await result).toEqual({ ok: true, reason: "named-check-fail" });
    expect(lastComment()!.body).toContain("**fail**");
    expect(closeCall()).toBeUndefined();
  });

  it("dilution guard: a high recent burst stays FAIL even at the widest in-bounds window", async () => {
    // 7 days of heavy churn; window_hours=168 (max) must NOT dilute it to a pass.
    stubFetch({ issues: [{ id: "1" }], stats: dailyStats([50, 50, 50, 50, 50, 50, 50]) });
    const { result } = arm({ ...okParams, window_hours: 168, close_on_pass: true });
    expect(await result).toEqual({ ok: true, reason: "named-check-fail" });
    expect(closeCall()).toBeUndefined();
  });

  it("fail-closed when the matched issue has no id (no stats fetch, NO close)", async () => {
    stubFetch({ issues: [{ title: "no id here" }] });
    const { result } = arm({ ...okParams, close_on_pass: true });
    expect(await result).toEqual({ ok: true, reason: "named-check-info" });
    expect(lastComment()!.body).toContain("matched issue has no id");
    expect(closeCall()).toBeUndefined();
  });

  it("fail-closed on an unexpected detail/stats shape (no daily array, NO close)", async () => {
    stubFetch({ issues: [{ id: "1" }], detail: { stats: { "24h": [[1, 2]] } } });
    const { result } = arm({ ...okParams, close_on_pass: true });
    expect(await result).toEqual({ ok: true, reason: "named-check-info" });
    expect(lastComment()!.body).toContain("unexpected stats shape");
    expect(closeCall()).toBeUndefined();
  });

  it("pass+close where the close PATCH fails → pass-close-failed, reportSilentFallback", async () => {
    stubFetch({ issues: [{ id: "1" }], stats: dailyStats([0, 0, 1]) });
    octokitRequestSpy.mockImplementation(async (route: string) => {
      if (route === "PATCH /repos/{owner}/{repo}/issues/{issue_number}") {
        throw new Error("close failed");
      }
      return {};
    });
    const { result } = arm({ ...okParams, close_on_pass: true });
    expect(await result).toEqual({ ok: true, reason: "named-check-pass-close-failed" });
    expect(
      reportSilentFallbackSpy.mock.calls.some((c) => c[1].op === "named-check-close"),
    ).toBe(true);
  });

  // --- transient-retry hardening (#5417 AC12 follow-on) ---------------------

  it("transient HTTP 5xx on the search, then success → REAL verdict (not fail-closed)", async () => {
    stubFetchSequence({
      search: [{ status: 503 }, { body: [{ id: "120495109" }] }],
      detail: [{ body: { stats: { "30d": passSeries } } }],
    });
    const { result } = arm({ ...okParams });
    expect(await result).toEqual({ ok: true, reason: "named-check-pass" });
    expect(lastComment()!.body).toContain("**pass**");
    expect(lastComment()!.body).not.toContain("fail-closed");
    expect(searchCalls()).toBe(2);
  });

  it("transient AbortSignal.timeout on the search, then success → REAL verdict", async () => {
    // TimeoutError is what AbortSignal.timeout throws and what isRetryable
    // classifies transient — an AbortError (old AbortController) would NOT retry.
    stubFetchSequence({
      search: [timeoutError(), { body: [{ id: "1" }] }],
      detail: [{ body: { stats: { "30d": passSeries } } }],
    });
    const { result } = arm({ ...okParams });
    expect(await result).toEqual({ ok: true, reason: "named-check-pass" });
    expect(lastComment()!.body).toContain("**pass**");
    expect(searchCalls()).toBe(2);
  });

  it("transient network error (undici 'fetch failed') on the search, then success → REAL verdict", async () => {
    // Exercises the isRetryable network arm (distinct from the TimeoutError arm).
    stubFetchSequence({
      search: [networkError(), { body: [{ id: "1" }] }],
      detail: [{ body: { stats: { "30d": passSeries } } }],
    });
    const { result } = arm({ ...okParams });
    expect(await result).toEqual({ ok: true, reason: "named-check-pass" });
    expect(searchCalls()).toBe(2);
  });

  it("transient HTTP 429 (rate-limit) on the search, then success → REAL verdict", async () => {
    stubFetchSequence({
      search: [{ status: 429 }, { body: [{ id: "1" }] }],
      detail: [{ body: { stats: { "30d": passSeries } } }],
    });
    const { result } = arm({ ...okParams });
    expect(await result).toEqual({ ok: true, reason: "named-check-pass" });
    expect(searchCalls()).toBe(2);
  });

  it("HTTP 4xx does NOT retry → single fetch, fail-closed, Sentry-visible warn", async () => {
    stubFetchSequence({ search: [{ status: 403 }, { body: [{ id: "1" }] }] });
    const { result } = arm({ ...okParams, close_on_pass: true });
    expect(await result).toEqual({ ok: true, reason: "named-check-info" });
    expect(lastComment()!.body).toContain("fail-closed");
    expect(searchCalls()).toBe(1); // no retry on a deterministic 4xx
    const warn = warnSilentFallbackSpy.mock.calls.find(
      (c) => c[1].op === "sentry-issue-rate-fail-closed",
    );
    expect(warn).toBeDefined();
    expect(String(warn![1].extra.reason)).toContain("HTTP 403");
  });

  it("retries are bounded to SENTRY_FETCH_MAX_RETRIES+1 (3) on persistent 5xx", async () => {
    stubFetchSequence({ search: [{ status: 503 }] }); // single entry reused every attempt
    const { result } = arm({ ...okParams, close_on_pass: true });
    expect(await result).toEqual({ ok: true, reason: "named-check-info" });
    expect(lastComment()!.body).toContain("fail-closed");
    expect(searchCalls()).toBe(3);
    // Pin the exact backoff SCHEDULE (not just the count) — the impl deliberately
    // uses 500/1500, NOT the siblings' geometric 500/1000; a silent drift to
    // `2 ** attempt` would pass a count-only assertion.
    expect(vi.mocked(delay).mock.calls).toEqual([[500], [1500]]);
    expect(
      warnSilentFallbackSpy.mock.calls.some(
        (c) => c[1].op === "sentry-issue-rate-fail-closed",
      ),
    ).toBe(true);
  });

  it("retries the SECOND (detail) call too: 500 then success → REAL verdict", async () => {
    stubFetchSequence({
      search: [{ body: [{ id: "1" }] }],
      detail: [{ status: 500 }, { body: { stats: { "30d": passSeries } } }],
    });
    const { result } = arm({ ...okParams });
    expect(await result).toEqual({ ok: true, reason: "named-check-pass" });
    expect(lastComment()!.body).toContain("**pass**");
    expect(searchCalls()).toBe(1); // search succeeded first try
    expect(detailCalls()).toBe(2); // detail retried once — localizes a search-vs-detail regression
  });

  it("env-unset fail-close is Sentry-visible (warn op), no fetch", async () => {
    vi.stubEnv("SENTRY_ISSUE_RW_TOKEN", "");
    stubFetchSequence({ search: [{ body: [{ id: "1" }] }] });
    const { result } = arm({ ...okParams, close_on_pass: true });
    expect(await result).toEqual({ ok: true, reason: "named-check-info" });
    expect(fetchMock).not.toHaveBeenCalled();
    const warn = warnSilentFallbackSpy.mock.calls.find(
      (c) => c[1].op === "sentry-issue-rate-fail-closed",
    );
    expect(warn).toBeDefined();
    expect(warn![1].extra.reason).toBe("Sentry env not configured");
  });

  it("token never leaks across the retry + warn paths (5xx exhaustion)", async () => {
    stubFetchSequence({ search: [{ status: 503 }] });
    const { result } = arm({ ...okParams, close_on_pass: true });
    await result;
    expect(lastComment()!.body).not.toContain("Bearer");
    expect(lastComment()!.body).not.toContain(ENV.SENTRY_ISSUE_RW_TOKEN);
    for (const call of [
      ...reportSilentFallbackSpy.mock.calls,
      ...warnSilentFallbackSpy.mock.calls,
    ]) {
      const s = JSON.stringify(call);
      expect(s).not.toContain(ENV.SENTRY_ISSUE_RW_TOKEN);
      expect(s).not.toContain("Bearer");
    }
  });
});
