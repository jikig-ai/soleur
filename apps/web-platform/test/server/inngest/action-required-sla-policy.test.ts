// Pure-policy tests for the action-required staleness contract (#6836, plan Phase 3 + Deepening).
// The fail-safe close authority + the two correctness-FATAL deepen-plan findings (non-bot
// activity clock D3; classify on the AGENT-owned label not the human-attachable `content` D1)
// live in this pure module, so they are exhaustively covered here without mocking Inngest.
import { describe, it, expect } from "vitest";
import {
  classifyIssue,
  isBot,
  priorityRank,
  decideAction,
  lastNonBotActivityMs,
  isHumanEngaged,
  buildSentinelMarker,
  hasSentinel,
  EXPIRE_INACTIVE_DAYS,
  WONTFIX_STALE_LABEL,
  type ActivityEvent,
} from "@/server/inngest/functions/action-required-sla-policy";

const DAY = 86_400_000;
const NOW = Date.parse("2026-07-22T00:00:00Z");
const daysAgo = (n: number) => new Date(NOW - n * DAY).toISOString();

describe("classifyIssue — fail-safe AGENT-owned allowlist (D1)", () => {
  it("defaults to ops (never closeable) for an unlabeled issue", () => {
    expect(classifyIssue([])).toBe("ops");
    expect(classifyIssue(["priority/p1-high", "domain/engineering"])).toBe("ops");
  });
  it("an ops emergency carrying the broad `content` label is OPS, NOT dead-content (D1 fatal)", () => {
    // `content` is human-attachable; keying expiry on it would close a real emergency.
    expect(classifyIssue(["content", "priority/p0-critical"])).toBe("ops");
  });
  it("keys dead-content on the AGENT-owned `content-publisher` label", () => {
    expect(classifyIssue(["action-required", "content-publisher"])).toBe("dead-content");
  });
  it("content-starvation stays OPS (genuine standing signal, never expired)", () => {
    expect(classifyIssue(["content-starvation", "content-publisher"])).toBe("ops");
  });
  it("classifies decision-challenge", () => {
    expect(classifyIssue(["decision-challenge"])).toBe("decision-challenge");
  });
});

describe("isBot", () => {
  it("detects the App/bot identity by type and [bot] suffix", () => {
    expect(isBot("github-actions[bot]", "Bot")).toBe(true);
    expect(isBot("claude[bot]", "User")).toBe(true);
    expect(isBot("some-app[bot]", undefined)).toBe(true);
  });
  it("treats a human login as non-bot", () => {
    expect(isBot("deruelle", "User")).toBe(false);
  });
});

describe("lastNonBotActivityMs — the D3 fatal fix", () => {
  const events: ActivityEvent[] = [
    { actor: "deruelle", actorType: "User", at: daysAgo(90) }, // last HUMAN touch: 90d ago
    { actor: "github-actions[bot]", actorType: "Bot", at: daysAgo(3) }, // bot noise every few days
    { actor: "claude[bot]", actorType: "User", at: daysAgo(1) },
  ];
  it("ignores bot events — inactivity measured from the last non-bot event", () => {
    // Raw updatedAt would read 1d; the non-bot clock reads 90d.
    expect(lastNonBotActivityMs(events)).toBe(Date.parse(daysAgo(90)));
  });
  it("returns null when there is NO non-bot activity (fall back to createdAt at the call site)", () => {
    expect(
      lastNonBotActivityMs([{ actor: "github-actions[bot]", actorType: "Bot", at: daysAgo(2) }]),
    ).toBeNull();
  });
});

describe("isHumanEngaged — veto (D1)", () => {
  it("vetoes on a non-bot assignee", () => {
    expect(isHumanEngaged({ assignees: [{ login: "deruelle", type: "User" }], events: [] })).toBe(true);
  });
  it("vetoes on a human comment", () => {
    expect(
      isHumanEngaged({ assignees: [], events: [{ actor: "deruelle", actorType: "User", at: daysAgo(1) }] }),
    ).toBe(true);
  });
  it("does NOT veto on bot-only assignee/comments (the cron's own writes)", () => {
    expect(
      isHumanEngaged({
        assignees: [{ login: "github-actions[bot]", type: "Bot" }],
        events: [{ actor: "claude[bot]", actorType: "User", at: daysAgo(1) }],
      }),
    ).toBe(false);
  });
});

describe("decideAction — OPS escalate-only, never close", () => {
  const opsSnap = (ageDays: number, currentPriority: string | null) => ({
    cls: "ops" as const,
    ageDays,
    inactiveDays: ageDays,
    humanEngaged: false,
    currentPriority,
    labels: [] as string[],
    closed: false,
  });
  it("never expires an OPS issue even at 999 days", () => {
    expect(decideAction(opsSnap(999, "priority/p0-critical")).action).not.toBe("expire");
  });
  it("escalates ≥14d to p2", () => {
    const d = decideAction(opsSnap(14, null));
    expect(d.action).toBe("escalate");
    expect(d.targetPriority).toBe("priority/p2-medium");
  });
  it("escalates ≥30d to p1, ≥60d to p0", () => {
    expect(decideAction(opsSnap(30, "priority/p2-medium")).targetPriority).toBe("priority/p1-high");
    expect(decideAction(opsSnap(60, "priority/p1-high")).targetPriority).toBe("priority/p0-critical");
  });
  it("is idempotent — no escalate when already at/above the tier (bumps upward only)", () => {
    expect(decideAction(opsSnap(30, "priority/p0-critical")).action).toBe("skip");
    expect(decideAction(opsSnap(14, "priority/p2-medium")).action).toBe("skip");
  });
});

describe("decideAction — dead classes expire on the NON-BOT clock, veto blocks", () => {
  const deadSnap = (inactiveDays: number, over: Partial<{ humanEngaged: boolean; closed: boolean; labels: string[] }> = {}) => ({
    cls: "dead-content" as const,
    ageDays: Math.max(inactiveDays, 40),
    inactiveDays,
    humanEngaged: over.humanEngaged ?? false,
    currentPriority: null,
    labels: over.labels ?? [],
    closed: over.closed ?? false,
  });
  it("expires at exactly EXPIRE_INACTIVE_DAYS, not one day before", () => {
    expect(decideAction(deadSnap(EXPIRE_INACTIVE_DAYS)).action).toBe("expire");
    expect(decideAction(deadSnap(EXPIRE_INACTIVE_DAYS - 1)).action).toBe("skip");
  });
  it("a 40d-old but recently non-bot-active issue does NOT expire (D3)", () => {
    // ageDays 40 but inactiveDays 2 → not stale.
    expect(decideAction(deadSnap(2)).action).toBe("skip");
  });
  it("human-engagement veto blocks the close even past threshold", () => {
    expect(decideAction(deadSnap(90, { humanEngaged: true })).action).toBe("skip");
  });
  it("does not re-expire an already wontfix-stale / closed issue", () => {
    expect(decideAction(deadSnap(90, { labels: [WONTFIX_STALE_LABEL] })).action).toBe("skip");
    expect(decideAction(deadSnap(90, { closed: true })).action).toBe("skip");
  });
  it("decision-challenge also expires on the non-bot clock at threshold", () => {
    const dc = { cls: "decision-challenge" as const, ageDays: 40, inactiveDays: 30, humanEngaged: false, currentPriority: null, labels: [], closed: false };
    expect(decideAction(dc).action).toBe("expire");
  });
});

describe("sentinel marker (D2 cross-run dedup)", () => {
  it("round-trips a per-action/threshold marker embedded in a comment body", () => {
    const m = buildSentinelMarker("escalate", "priority/p1-high");
    expect(hasSentinel(`some comment\n${m}\nmore`, "escalate", "priority/p1-high")).toBe(true);
    expect(hasSentinel("no marker here", "escalate", "priority/p1-high")).toBe(false);
    // A different threshold's marker does not satisfy this threshold's guard.
    expect(hasSentinel(buildSentinelMarker("escalate", "priority/p2-medium"), "escalate", "priority/p1-high")).toBe(false);
  });
});

describe("priorityRank", () => {
  it("orders p0 > p1 > p2 > p3 > none", () => {
    expect(priorityRank(["priority/p0-critical"])).toBeGreaterThan(priorityRank(["priority/p1-high"]));
    expect(priorityRank(["priority/p3-low"])).toBeGreaterThan(priorityRank([]));
  });
});
