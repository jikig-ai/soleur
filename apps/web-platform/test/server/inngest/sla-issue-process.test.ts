// Integration test for the SLA worker wiring (#6836 L4). The pure decisions are covered
// exhaustively in action-required-sla-policy.test.ts; here we prove the ORCHESTRATION:
// TOCTOU abort, escalate posts a sentinel-guarded comment + label, sentinel dedup skips the
// 2nd comment, expire closes not_planned, and an OPS issue is NEVER closed.
import { describe, expect, it, beforeEach, vi } from "vitest";

const state = vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
  return { fixture: null as unknown as Record<string, unknown>, calls: [] as Array<{ route: string; params: Record<string, unknown> }> };
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
      if (route.includes("/timeline")) return { data: f.timeline ?? [] };
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

  it("human-engagement veto: a recently-commented stale dead-content issue is NOT closed", async () => {
    state.fixture = {
      issue: { state: "open", updated_at: daysAgo(1), created_at: daysAgo(60), labels: ["action-required", "content-publisher"], assignees: [] },
      timeline: [{ actor: { login: "deruelle", type: "User" }, created_at: daysAgo(1) }], // human comment yesterday
      comments: [],
    };
    const res = (await run(5, daysAgo(1))) as { action: string };
    expect(res.action).toBe("skip");
    expect(closes()).toHaveLength(0);
  });
});
