// Phase 2 — content-starvation detection wired into cron-content-publisher.
//
// Pins the load-bearing fixes:
//   - analyzeCorpus: single-scan post-promotion scalars (promotions, gate-failed
//     drafts, latest-published baseline, scheduled-within-horizon, backlog).
//   - isStarved (silent-failure F1): fires on an ABSENT/NaN published baseline —
//     the exact cold/all-draft drought a naive `daysSincePublish >= N` silently
//     skips (`NaN >= N` is false).
//   - runStarvationCheck (architecture A-P1b / F3): failure-isolated — an Octokit
//     throw is caught + reported, never re-thrown (so the heartbeat cannot flip
//     to ok:false); dedup issue create + auto-close on recovery.
//
// Fixtures synthesized inline (cq-test-fixtures-synthesized-only).

import { describe, expect, it, vi } from "vitest";

const reportSilentFallbackSpy = vi.fn();
const warnSilentFallbackSpy = vi.fn();
const mirrorWarnWithDebounceSpy = vi.fn();
vi.mock("@/server/observability", async (importActual) => {
  const actual = await importActual<typeof import("@/server/observability")>();
  return {
    ...actual,
    reportSilentFallback: (...a: unknown[]) => reportSilentFallbackSpy(...a),
    warnSilentFallback: (...a: unknown[]) => warnSilentFallbackSpy(...a),
    mirrorWarnWithDebounce: (...a: unknown[]) => mirrorWarnWithDebounceSpy(...a),
  };
});

vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

import {
  STARVATION_DAYS,
  STARVATION_ISSUE_TITLE,
  analyzeCorpus,
  isStarved,
  runStarvationCheck,
} from "@/server/inngest/functions/cron-content-publisher";
import type { PromotionInput } from "@/server/inngest/functions/content-promotion";

const TODAY = new Date("2026-07-05T00:00:00Z");
const HORIZON = 28;

// --- fixture builders --------------------------------------------------------

function draft(opts?: { channels?: string; ready?: boolean }): string {
  const channels = opts?.channels ?? "x, bluesky";
  const body =
    opts?.ready === false
      ? "## X/Twitter Thread\n\nNot scheduled for this platform.\n\n## Bluesky\n\n"
      : "## X/Twitter Thread\n\nReal thread content.\n\n## Bluesky\n\nReal bluesky content.\n";
  return `---
title: "Draft"
publish_date: ""
channels: ${channels}
status: draft
---

${body}`;
}

function published(date: string): string {
  return `---
title: "Published"
publish_date: ${date}
channels: x
status: published
---

## X/Twitter Thread

Posted content.
`;
}

function scheduled(date: string): string {
  return `---
title: "Scheduled"
publish_date: ${date}
channels: x
status: scheduled
---

## X/Twitter Thread

Queued content.
`;
}

function parked(date: string): string {
  return `---
title: "Parked"
publish_date: ${date}
channels: x
status: parked
---

## X/Twitter Thread

Held content.
`;
}

// =============================================================================
// analyzeCorpus — single-scan post-promotion scalars
// =============================================================================

describe("analyzeCorpus", () => {
  it("cold-start backlog: 18 drafts, 0 scheduled, 0 published → ~8 promotions, undefined baseline", () => {
    const files: PromotionInput[] = Array.from({ length: 18 }, (_, i) => ({
      path: `d-${String(i).padStart(2, "0")}.md`,
      raw: draft(),
    }));
    const a = analyzeCorpus({ files, today: TODAY, horizonDays: HORIZON });
    expect(a.promotions.length).toBe(8);
    expect(a.scheduledWithinHorizon).toBe(8); // all newly promoted
    expect(a.draftBacklog).toBe(18);
    expect(a.latestPublishedDate).toBeUndefined();
    expect(a.gateFailedDrafts).toEqual([]);
  });

  it("collects gate-failing drafts independently of scheduledWithinHorizon", () => {
    const files: PromotionInput[] = [
      { path: "ready.md", raw: draft() },
      { path: "broken.md", raw: draft({ ready: false }) },
    ];
    const a = analyzeCorpus({ files, today: TODAY, horizonDays: HORIZON });
    expect(a.promotions.map((p) => p.path)).toEqual(["ready.md"]);
    expect(a.gateFailedDrafts).toEqual(["broken.md"]); // surfaced even though ready.md schedulable
    expect(a.scheduledWithinHorizon).toBe(1);
  });

  it("occupied includes a parked file's future date (no double-book onto it)", () => {
    // 2026-07-07 is the first Tue slot; a parked file holds it.
    const files: PromotionInput[] = [
      { path: "a.md", raw: draft() },
      { path: "parked.md", raw: parked("2026-07-07") },
    ];
    const a = analyzeCorpus({ files, today: TODAY, horizonDays: HORIZON });
    expect(a.promotions[0].publishDate).not.toBe("2026-07-07");
    expect(a.promotions[0].publishDate).toBe("2026-07-09");
  });

  it("computes latestPublishedDate + daysSincePublish from published files", () => {
    const files: PromotionInput[] = [
      { path: "p1.md", raw: published("2026-06-20") },
      { path: "p2.md", raw: published("2026-06-25") }, // latest
    ];
    const a = analyzeCorpus({ files, today: TODAY, horizonDays: HORIZON });
    expect(a.latestPublishedDate).toBe("2026-06-25");
    expect(a.daysSincePublish).toBe(10); // 2026-07-05 - 2026-06-25
  });

  it("counts existing scheduled-within-horizon plus new promotions", () => {
    const files: PromotionInput[] = [
      { path: "s.md", raw: scheduled("2026-07-14") },
      { path: "d.md", raw: draft() },
    ];
    const a = analyzeCorpus({ files, today: TODAY, horizonDays: HORIZON });
    expect(a.scheduledWithinHorizon).toBe(2); // 1 existing + 1 promoted
  });

  it("surfaces an unparseable publish_date on a published file", () => {
    const files: PromotionInput[] = [
      { path: "bad.md", raw: published("not-a-date") },
    ];
    const a = analyzeCorpus({ files, today: TODAY, horizonDays: HORIZON });
    expect(a.unparseablePublishedDates).toContain("bad.md");
    expect(a.latestPublishedDate).toBeUndefined();
  });
});

// =============================================================================
// isStarved — the F1 predicate
// =============================================================================

describe("isStarved (F1: fires on empty/NaN baseline)", () => {
  it("0 scheduled + undefined latestPublishedDate → STARVED (cold all-draft drought)", () => {
    expect(
      isStarved({
        scheduledWithinHorizon: 0,
        latestPublishedDate: undefined,
        daysSincePublish: undefined,
        starvationDays: STARVATION_DAYS,
      }),
    ).toBe(true);
  });

  it("0 scheduled + NaN daysSincePublish (unparseable) → STARVED", () => {
    expect(
      isStarved({
        scheduledWithinHorizon: 0,
        latestPublishedDate: "garbage",
        daysSincePublish: NaN,
        starvationDays: STARVATION_DAYS,
      }),
    ).toBe(true);
  });

  it("0 scheduled + daysSincePublish >= STARVATION_DAYS → STARVED", () => {
    expect(
      isStarved({
        scheduledWithinHorizon: 0,
        latestPublishedDate: "2026-06-20",
        daysSincePublish: 15,
        starvationDays: STARVATION_DAYS,
      }),
    ).toBe(true);
  });

  it("0 scheduled + recent post (daysSincePublish < STARVATION_DAYS) → NOT starved", () => {
    expect(
      isStarved({
        scheduledWithinHorizon: 0,
        latestPublishedDate: "2026-07-02",
        daysSincePublish: 3,
        starvationDays: STARVATION_DAYS,
      }),
    ).toBe(false);
  });

  it("scheduledWithinHorizon > 0 → NOT starved regardless of baseline", () => {
    expect(
      isStarved({
        scheduledWithinHorizon: 3,
        latestPublishedDate: undefined,
        daysSincePublish: undefined,
        starvationDays: STARVATION_DAYS,
      }),
    ).toBe(false);
  });
});

// =============================================================================
// runStarvationCheck — issue orchestration + failure isolation
// =============================================================================

function mockOctokit(handlers: {
  getIssues?: Array<{ title: string; number: number }>;
  onThrow?: boolean;
}) {
  const request = vi.fn(async (route: string, _params?: Record<string, unknown>) => {
    void _params;
    if (handlers.onThrow) throw new Error("octokit boom");
    if (route === "GET /repos/{owner}/{repo}/issues") {
      return { data: handlers.getIssues ?? [] };
    }
    if (route === "POST /repos/{owner}/{repo}/issues") {
      return { data: { number: 5555 } };
    }
    return { data: {} };
  });
  return { request };
}

describe("runStarvationCheck", () => {
  const base = {
    scheduledWithinHorizon: 0,
    latestPublishedDate: undefined as string | undefined,
    daysSincePublish: undefined as number | undefined,
    draftBacklog: 18,
    starvationDays: STARVATION_DAYS,
  };

  it("starved → reportSilentFallback op=content-starvation + creates ONE dedup issue", async () => {
    reportSilentFallbackSpy.mockClear();
    const client = mockOctokit({ getIssues: [] });
    const res = await runStarvationCheck({
      client: client as never,
      ...base,
    });
    expect(res.starved).toBe(true);
    const starvationReport = reportSilentFallbackSpy.mock.calls.find(
      (c) => (c[1] as { op?: string }).op === "content-starvation",
    );
    expect(starvationReport).toBeDefined();
    expect((starvationReport![1] as { tags: { starvation: string } }).tags.starvation).toBe("true");
    // exactly one POST create
    const posts = client.request.mock.calls.filter(
      (c) => c[0] === "POST /repos/{owner}/{repo}/issues",
    );
    expect(posts.length).toBe(1);
    const postArgs = posts[0]![1] as { title: string; labels: string[] };
    expect(postArgs.title).toBe(STARVATION_ISSUE_TITLE);
    expect(postArgs.labels).toContain("action-required");
  });

  it("starved + issue already open → does NOT duplicate", async () => {
    const client = mockOctokit({
      getIssues: [{ title: STARVATION_ISSUE_TITLE, number: 42 }],
    });
    const res = await runStarvationCheck({ client: client as never, ...base });
    expect(res.starved).toBe(true);
    const posts = client.request.mock.calls.filter(
      (c) => c[0] === "POST /repos/{owner}/{repo}/issues",
    );
    expect(posts.length).toBe(0);
  });

  it("recovery: scheduledWithinHorizon > 0 → closes an open starvation issue with a comment", async () => {
    const client = mockOctokit({
      getIssues: [{ title: STARVATION_ISSUE_TITLE, number: 77 }],
    });
    const res = await runStarvationCheck({
      client: client as never,
      ...base,
      scheduledWithinHorizon: 4,
    });
    expect(res.starved).toBe(false);
    const patches = client.request.mock.calls.filter(
      (c) => c[0] === "PATCH /repos/{owner}/{repo}/issues/{issue_number}",
    );
    expect(patches.length).toBe(1);
    const patchArgs = patches[0]![1] as { issue_number: number; state: string };
    expect(patchArgs.issue_number).toBe(77);
    expect(patchArgs.state).toBe("closed");
    const comments = client.request.mock.calls.filter(
      (c) => c[0] === "POST /repos/{owner}/{repo}/issues/{issue_number}/comments",
    );
    expect(comments.length).toBe(1);
  });

  it("failure-isolated: an Octokit throw is caught → op=starvation-check-failed, does NOT rethrow", async () => {
    reportSilentFallbackSpy.mockClear();
    const client = mockOctokit({ onThrow: true });
    // Must resolve (not reject) — a throw here must never propagate to the
    // handler top-level catch (which would post ok:false, a false cron-DOWN).
    const res = await runStarvationCheck({ client: client as never, ...base });
    expect(res.starved).toBe(false);
    const failed = reportSilentFallbackSpy.mock.calls.find(
      (c) => (c[1] as { op?: string }).op === "starvation-check-failed",
    );
    expect(failed).toBeDefined();
  });
});

// =============================================================================
// Handler source-shape — heartbeat stays ok:true, step order, isolation
// =============================================================================

import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const SRC = readFileSync(
  resolve(__dirname, "../../../server/inngest/functions/cron-content-publisher.ts"),
  "utf-8",
);

describe("handler wiring (source-shape)", () => {
  it("promote-drafts step runs before pre-check-stale-content", () => {
    expect(SRC.indexOf('"promote-drafts"')).toBeGreaterThan(-1);
    expect(SRC.indexOf('"promote-drafts"')).toBeLessThan(
      SRC.indexOf('"pre-check-stale-content"'),
    );
  });

  it("starvation-check step runs after safe-commit-pr and before sentry-heartbeat", () => {
    expect(SRC.indexOf('"safe-commit-pr"')).toBeLessThan(
      SRC.indexOf('"starvation-check"'),
    );
    expect(SRC.indexOf('"starvation-check"')).toBeLessThan(
      SRC.indexOf('"sentry-heartbeat"'),
    );
  });

  it("sentry-heartbeat posts ok:true — starvation is a content signal, not a liveness signal", () => {
    const hb = SRC.slice(SRC.indexOf('"sentry-heartbeat"'));
    expect(hb).toMatch(/ok:\s*true/);
  });

  it("commit message names both mutations (promotion + status update)", () => {
    expect(SRC).toContain("promote review-ready drafts");
  });
});
