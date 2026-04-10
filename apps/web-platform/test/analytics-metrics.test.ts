import { describe, test, expect } from "vitest";
import { computeMetrics } from "@/lib/analytics";
import type { UserRow, ConversationRow, UserMetrics } from "@/lib/analytics";

const USERS: UserRow[] = [
  {
    id: "user-1",
    email: "alice@example.com",
    created_at: "2026-03-20T00:00:00Z",
    kb_sync_history: [
      { date: "2026-04-01", count: 5 },
      { date: "2026-04-02", count: 8 },
      { date: "2026-04-03", count: 12 },
    ],
  },
  {
    id: "user-2",
    email: "bob@example.com",
    created_at: "2026-04-05T00:00:00Z",
    kb_sync_history: [],
  },
  {
    id: "user-3",
    email: "carol@example.com",
    created_at: "2026-04-01T00:00:00Z",
    kb_sync_history: [{ date: "2026-04-08", count: 3 }],
  },
];

const CONVERSATIONS: ConversationRow[] = [
  // Alice: 3 sessions across 2 domains (cto, cmo), 1 failed
  { user_id: "user-1", domain_leader: "cto", status: "completed", created_at: "2026-04-01T10:00:00Z" },
  { user_id: "user-1", domain_leader: "cmo", status: "completed", created_at: "2026-04-02T10:00:00Z" },
  { user_id: "user-1", domain_leader: "cto", status: "failed", created_at: "2026-04-03T10:00:00Z" },
  // Bob: 1 session, 1 domain
  { user_id: "user-2", domain_leader: "cpo", status: "completed", created_at: "2026-04-06T10:00:00Z" },
  // Carol: no sessions (empty)
];

describe("computeMetrics", () => {
  const now = new Date("2026-04-10T12:00:00Z");

  test("computes domain engagement per user", () => {
    const metrics = computeMetrics(USERS, CONVERSATIONS, now);
    const alice = metrics.find((m) => m.userId === "user-1")!;
    expect(alice.domainCounts).toEqual({ cto: 2, cmo: 1 });
  });

  test("computes total session count per user", () => {
    const metrics = computeMetrics(USERS, CONVERSATIONS, now);
    const alice = metrics.find((m) => m.userId === "user-1")!;
    const bob = metrics.find((m) => m.userId === "user-2")!;
    expect(alice.totalSessions).toBe(3);
    expect(bob.totalSessions).toBe(1);
  });

  test("computes multi-domain count per user", () => {
    const metrics = computeMetrics(USERS, CONVERSATIONS, now);
    const alice = metrics.find((m) => m.userId === "user-1")!;
    const bob = metrics.find((m) => m.userId === "user-2")!;
    expect(alice.domainCount).toBe(2);
    expect(bob.domainCount).toBe(1);
  });

  test("computes error rate per user", () => {
    const metrics = computeMetrics(USERS, CONVERSATIONS, now);
    const alice = metrics.find((m) => m.userId === "user-1")!;
    const bob = metrics.find((m) => m.userId === "user-2")!;
    // Alice: 1 failed out of 3
    expect(alice.errorRate).toBeCloseTo(1 / 3, 2);
    // Bob: 0 failed out of 1
    expect(bob.errorRate).toBe(0);
  });

  test("computes time-to-first-value in days", () => {
    const metrics = computeMetrics(USERS, CONVERSATIONS, now);
    const alice = metrics.find((m) => m.userId === "user-1")!;
    // Alice signed up 2026-03-20, first session 2026-04-01 = 12 days
    expect(alice.ttfvDays).toBe(12);
  });

  test("returns null ttfv for users with no sessions", () => {
    const metrics = computeMetrics(USERS, CONVERSATIONS, now);
    const carol = metrics.find((m) => m.userId === "user-3")!;
    expect(carol.ttfvDays).toBeNull();
  });

  test("computes churn signal based on 7-day threshold", () => {
    const metrics = computeMetrics(USERS, CONVERSATIONS, now);
    const alice = metrics.find((m) => m.userId === "user-1")!;
    const bob = metrics.find((m) => m.userId === "user-2")!;
    const carol = metrics.find((m) => m.userId === "user-3")!;
    // Alice last session: 2026-04-03, now: 2026-04-10 = 7 days → churning
    expect(alice.churning).toBe(true);
    // Bob last session: 2026-04-06, now: 2026-04-10 = 4 days → active
    expect(bob.churning).toBe(false);
    // Carol: no sessions → churning
    expect(carol.churning).toBe(true);
  });

  test("includes KB sync history from user data", () => {
    const metrics = computeMetrics(USERS, CONVERSATIONS, now);
    const alice = metrics.find((m) => m.userId === "user-1")!;
    expect(alice.kbHistory).toEqual([
      { date: "2026-04-01", count: 5 },
      { date: "2026-04-02", count: 8 },
      { date: "2026-04-03", count: 12 },
    ]);
  });

  test("computes session frequency as daily counts", () => {
    const metrics = computeMetrics(USERS, CONVERSATIONS, now);
    const alice = metrics.find((m) => m.userId === "user-1")!;
    // Alice had sessions on 3 different days, 1 each
    expect(alice.sessionsByDay).toEqual({
      "2026-04-01": 1,
      "2026-04-02": 1,
      "2026-04-03": 1,
    });
  });

  test("returns all users even those with zero sessions", () => {
    const metrics = computeMetrics(USERS, CONVERSATIONS, now);
    expect(metrics).toHaveLength(3);
    const carol = metrics.find((m) => m.userId === "user-3")!;
    expect(carol.totalSessions).toBe(0);
    expect(carol.domainCount).toBe(0);
    expect(carol.errorRate).toBe(0);
    expect(carol.domainCounts).toEqual({});
    expect(carol.sessionsByDay).toEqual({});
  });
});
