// Integration test for the SLA worker wiring (#6836 L4). The pure decisions are covered
// exhaustively in action-required-sla-policy.test.ts; here we prove the ORCHESTRATION:
// TOCTOU abort, escalate posts a sentinel-guarded comment + label, sentinel dedup skips the
// 2nd comment, expire closes not_planned, and an OPS issue is NEVER closed.
import { describe, expect, it, beforeEach, vi } from "vitest";

const state = vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
  return {
    fixture: null as unknown as Record<string, unknown>,
    calls: [] as Array<{ route: string; params: Record<string, unknown> }>,
    timelineCalls: 0,
  };
});

vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
  mirrorWarnWithDebounce: vi.fn(),
}));
vi.mock("@/server/inngest/functions/_cron-shared", async (orig) => ({
  ...(await orig<typeof import("@/server/inngest/functions/_cron-shared")>()),
  mintInstallationToken: vi.fn(async () => "test-token"),
  postSentryHeartbeat: vi.fn(async () => {}),
}));
vi.mock("@octokit/core", () => ({
  Octokit: class {
    async request(route: string, params: Record<string, unknown>) {
      state.calls.push({ route, params });
      const f = state.fixture as Record<string, unknown>;
      if (route === "GET /repos/{owner}/{repo}/issues/{issue_number}") return { data: f.issue };
      if (route.includes("/timeline")) {
        state.timelineCalls += 1;
        // `lateTimeline` models a human engaging BETWEEN the assess fetch and the expire-step
        // re-fetch (the 2nd timeline GET) — exercising the independent veto re-check tripwire.
        if (f.lateTimeline && state.timelineCalls >= 2) return { data: f.lateTimeline };
        return { data: f.timeline ?? [] };
      }
      if (route === "GET /repos/{owner}/{repo}/issues/{issue_number}/comments") return { data: f.comments ?? [] };
      return { data: {} }; // POST comment / POST labels / PATCH close
    }
  },
}));

import { slaIssueProcessHandler } from "@/server/inngest/functions/sla-issue-process";

const DAY = 86_400_000;
const NOW = "2026-07-22T00:00:00Z";
const nowMs = Date.parse(NOW);
const daysAgo = (n: number) => new Date(nowMs - n * DAY).toISOString();

const fakeStep = { run: async <T>(_name: string, cb: () => Promise<T>): Promise<T> => cb() };
const fakeLogger = { info: vi.fn(), warn: vi.fn(), error: vi.fn() };

async function run(issueNumber: number, listedUpdatedAt: string) {
  return slaIssueProcessHandler({
    event: { data: { issueNumber, listedUpdatedAt, runStartedAt: NOW } },
    step: fakeStep as never,
    logger: fakeLogger as never,
  } as never);
}

const mutations = () => state.calls.filter((c) => c.route.startsWith("POST") || c.route.startsWith("PATCH"));
const closes = () => state.calls.filter((c) => c.route.startsWith("PATCH") && (c.params as { state?: string }).state === "closed");
const comments = () => state.calls.filter((c) => c.route === "POST /repos/{owner}/{repo}/issues/{issue_number}/comments");

beforeEach(() => {
  state.calls.length = 0;
  state.fixture = {};
  state.timelineCalls = 0;
});

describe("SLA worker orchestration", () => {
  it("TOCTOU: aborts with no mutation when updatedAt drifted since the list snapshot (D2)", async () => {
    state.fixture = {
      issue: { state: "open", updated_at: daysAgo(0), created_at: daysAgo(90), labels: ["action-required", "content-publisher"], assignees: [] },
      timeline: [],
    };
    const res = (await run(1, daysAgo(5))) as { action: string }; // listed at 5d ago, fresh is now → drift
    expect(res.action).toBe("skip");
    expect(mutations()).toHaveLength(0);
  });

  it("escalates an aged OPS issue: sentinel comment + priority label, never a close", async () => {
    state.fixture = {
      issue: { state: "open", updated_at: daysAgo(2), created_at: daysAgo(60), labels: ["action-required"], assignees: [] },
      timeline: [{ actor: { login: "github-actions[bot]", type: "Bot" }, created_at: daysAgo(2) }],
      comments: [],
    };
    const res = (await run(2, daysAgo(2))) as { action: string };
    expect(res.action).toBe("escalate");
    expect(comments()).toHaveLength(1);
    expect((comments()[0].params as { body: string }).body).toContain("sla:escalate:priority/p0-critical");
    expect(state.calls.some((c) => c.route.endsWith("/labels") && ((c.params as { labels: string[] }).labels ?? []).includes("priority/p0-critical"))).toBe(true);
    expect(closes()).toHaveLength(0); // OPS is NEVER closed
  });

  it("sentinel dedup: does NOT post a 2nd escalation comment when the marker is present (D2)", async () => {
    state.fixture = {
      issue: { state: "open", updated_at: daysAgo(2), created_at: daysAgo(60), labels: ["action-required"], assignees: [] },
      timeline: [],
      comments: [{ body: "prior run\n<!-- sla:escalate:priority/p0-critical -->" }],
    };
    const res = (await run(3, daysAgo(2))) as { action: string };
    expect(res.action).toBe("escalate");
    expect(comments()).toHaveLength(0); // sentinel present → no duplicate comment
  });

  it("expires a stale dead-content issue: closes not_planned + wontfix-stale label", async () => {
    state.fixture = {
      issue: { state: "open", updated_at: daysAgo(30), created_at: daysAgo(60), labels: ["action-required", "content-publisher"], assignees: [] },
      timeline: [{ actor: { login: "deruelle", type: "User" }, created_at: daysAgo(40) }], // last human touch 40d ago
      comments: [],
    };
    const res = (await run(4, daysAgo(30))) as { action: string };
    expect(res.action).toBe("expire");
    expect(closes()).toHaveLength(1);
    expect((closes()[0].params as { state_reason: string }).state_reason).toBe("not_planned");
    expect(state.calls.some((c) => c.route.endsWith("/labels") && ((c.params as { labels: string[] }).labels ?? []).includes("wontfix-stale"))).toBe(true);
  });

  it("recent human activity keeps an issue non-stale (skip, not closed)", async () => {
    state.fixture = {
      issue: { state: "open", updated_at: daysAgo(1), created_at: daysAgo(60), labels: ["action-required", "content-publisher"], assignees: [] },
      timeline: [{ actor: { login: "deruelle", type: "User" }, created_at: daysAgo(1) }],
      comments: [],
    };
    const res = (await run(5, daysAgo(1))) as { action: string };
    expect(res.action).toBe("skip");
    expect(closes()).toHaveLength(0);
  });

  // The following are the ADVERSARIAL fixtures (test-design review): each is constructed so that
  // removing the specific guard under test flips the outcome — i.e. the assertion is load-bearing.

  it("assignee veto: a 60d-inactive dead-content issue with a non-bot assignee is SKIPPED at assess (kills a delete-veto mutation)", async () => {
    // No timeline activity → 60d inactive; without the veto this WOULD expire. The assignee is the
    // only non-redundant veto path. Asserting res.action==="skip" pins the decideAction veto itself
    // (a delete-veto mutation makes assess return "expire", which the expire-step tripwire still
    // blocks — closes()===0 — but res.action would then be "expire", failing this assertion).
    state.fixture = {
      issue: { state: "open", updated_at: daysAgo(40), created_at: daysAgo(60), labels: ["action-required", "content-publisher"], assignees: [{ login: "deruelle", type: "User" }] },
      timeline: [],
      comments: [],
    };
    const res = (await run(6, daysAgo(40))) as { action: string };
    expect(res.action).toBe("skip");
    expect(closes()).toHaveLength(0);
  });

  it("non-bot clock (D3): a bot-commented-yesterday but human-inactive-60d dead-content issue STILL expires (kills a raw-updatedAt mutation)", async () => {
    // updated_at is 1d (bot noise), but the last NON-BOT activity is 60d. A raw-updatedAt clock
    // would read 1d → skip; the non-bot clock reads 60d → expire. This fixture separates them.
    state.fixture = {
      issue: { state: "open", updated_at: daysAgo(1), created_at: daysAgo(70), labels: ["action-required", "content-publisher"], assignees: [] },
      timeline: [
        { actor: { login: "deruelle", type: "User" }, created_at: daysAgo(60) },
        { actor: { login: "github-actions[bot]", type: "Bot" }, created_at: daysAgo(1) },
      ],
      comments: [],
    };
    const res = (await run(7, daysAgo(1))) as { action: string };
    expect(res.action).toBe("expire");
    expect(closes()).toHaveLength(1);
  });

  it("D1 through the worker: an ops emergency carrying the broad `content` label is NEVER closed (kills a classify-on-content mutation)", async () => {
    state.fixture = {
      issue: { state: "open", updated_at: daysAgo(70), created_at: daysAgo(70), labels: ["action-required", "content", "priority/p0-critical"], assignees: [] },
      timeline: [],
      comments: [],
    };
    await run(8, daysAgo(70));
    expect(closes()).toHaveLength(0); // classifies OPS (not content-publisher) → escalate-only, never expire
  });

  it("late-engagement tripwire: a human engaging between assess and the close is caught by the expire-step re-check (no close)", async () => {
    // assess sees an empty timeline → decides expire; the expire-step re-fetch sees a fresh human
    // comment (lateTimeline on the 2nd timeline GET) → independent veto blocks the destructive close
    // and emits the feared case (human_engaged=true) for the Sentry alert. updated_at is held static
    // so this isolates the veto re-check (not the TOCTOU-drift path).
    state.fixture = {
      issue: { state: "open", updated_at: daysAgo(40), created_at: daysAgo(70), labels: ["action-required", "content-publisher"], assignees: [] },
      timeline: [],
      lateTimeline: [{ actor: { login: "deruelle", type: "User" }, created_at: daysAgo(0) }],
      comments: [],
    };
    await run(9, daysAgo(40));
    expect(closes()).toHaveLength(0);
  });
});
