// Phase 1 — pure promotion library (no I/O). These tests pin the slot math,
// readiness gate, deterministic assignment, and the *targeted line-replacement*
// mutation contract (NOT a gray-matter round-trip — learning
// 2026-05-25-tr9-pr6-gray-matter-yaml11-date-coercion-trap). Written RED-first
// per cq-write-failing-tests-before.
//
// All fixtures are synthesized inline (cq-test-fixtures-synthesized-only).

import { describe, expect, it } from "vitest";
import {
  HORIZON_DAYS,
  PROMOTION_WEEKDAYS,
  applyPromotion,
  isReadyDraft,
  nextTueThuSlots,
  parseContentFrontmatter,
  planPromotions,
} from "@/server/inngest/functions/content-promotion";

// --- Fixture builders --------------------------------------------------------

/** A ready draft: status:draft, real channels, non-empty mapped X section. */
function readyDraft(opts?: { channels?: string; publishDate?: string }): string {
  const channels = opts?.channels ?? "x, bluesky";
  const publishDate = opts?.publishDate ?? "";
  return `---
title: "A headline: with an embedded colon, and, commas"
type: feature-launch
publish_date: "${publishDate}"
channels: ${channels}
status: draft
---

## X/Twitter Thread

This is a real, non-empty X thread body that should post.

## Bluesky

A real Bluesky body.
`;
}

// --- parseContentFrontmatter -------------------------------------------------

describe("parseContentFrontmatter", () => {
  it("reads status, publish_date, channels — robust to a title containing ':'", () => {
    const parsed = parseContentFrontmatter(readyDraft());
    expect(parsed.status).toBe("draft");
    expect(parsed.publishDate).toBe(""); // quotes stripped, empty
    expect(parsed.channels).toEqual(["x", "bluesky"]);
  });

  it("strips quotes and splits channels on comma with trimming", () => {
    const parsed = parseContentFrontmatter(
      readyDraft({ channels: "discord, x, bluesky, linkedin-company", publishDate: "2026-05-14" }),
    );
    expect(parsed.publishDate).toBe("2026-05-14");
    expect(parsed.channels).toEqual(["discord", "x", "bluesky", "linkedin-company"]);
  });

  it("returns empty channels when frontmatter is absent", () => {
    const parsed = parseContentFrontmatter("no frontmatter here");
    expect(parsed.channels).toEqual([]);
    expect(parsed.status).toBeUndefined();
  });
});

// --- isReadyDraft ------------------------------------------------------------

function bodyOf(raw: string): string {
  const m = raw.split(/^---$/m);
  return m.length >= 3 ? m.slice(2).join("---") : raw;
}

describe("isReadyDraft", () => {
  it("accepts a draft with channels, liquid-clean body, and ≥1 non-empty mapped section", () => {
    const raw = readyDraft();
    expect(isReadyDraft(parseContentFrontmatter(raw), bodyOf(raw))).toBe(true);
  });

  it("rejects a parked file", () => {
    const raw = readyDraft().replace("status: draft", "status: parked");
    expect(isReadyDraft(parseContentFrontmatter(raw), bodyOf(raw))).toBe(false);
  });

  it("rejects a stale file", () => {
    const raw = readyDraft().replace("status: draft", "status: stale");
    expect(isReadyDraft(parseContentFrontmatter(raw), bodyOf(raw))).toBe(false);
  });

  it("rejects a published file", () => {
    const raw = readyDraft().replace("status: draft", "status: published");
    expect(isReadyDraft(parseContentFrontmatter(raw), bodyOf(raw))).toBe(false);
  });

  it("rejects a draft with no channels", () => {
    const raw = readyDraft({ channels: "" });
    expect(isReadyDraft(parseContentFrontmatter(raw), bodyOf(raw))).toBe(false);
  });

  it("rejects a draft whose body carries a Liquid marker", () => {
    const raw = readyDraft().replace("should post.", "has {{ leak }} marker.");
    expect(isReadyDraft(parseContentFrontmatter(raw), bodyOf(raw))).toBe(false);
  });

  it("rejects a draft whose declared channels all map to EMPTY sections", () => {
    // channels declare x + bluesky but both sections are empty/placeholder.
    const raw = `---
title: "Empty sections"
publish_date: ""
channels: x, bluesky
status: draft
---

## X/Twitter Thread

Not scheduled for this platform.

## Bluesky

`;
    expect(isReadyDraft(parseContentFrontmatter(raw), bodyOf(raw))).toBe(false);
  });

  it("accepts when ≥1 declared channel has content even if another section is a stub", () => {
    const raw = `---
title: "One ready one stub"
publish_date: ""
channels: x, bluesky
status: draft
---

## X/Twitter Thread

Real content here.

## Bluesky

Not scheduled for this platform.
`;
    expect(isReadyDraft(parseContentFrontmatter(raw), bodyOf(raw))).toBe(true);
  });
});

// --- nextTueThuSlots ---------------------------------------------------------

describe("nextTueThuSlots", () => {
  it("returns only Tue/Thu UTC dates within the horizon (from 2026-07-05, 28 days)", () => {
    const slots = nextTueThuSlots(new Date("2026-07-05T00:00:00Z"), new Set(), 28);
    expect(slots).toEqual([
      "2026-07-07",
      "2026-07-09",
      "2026-07-14",
      "2026-07-16",
      "2026-07-21",
      "2026-07-23",
      "2026-07-28",
      "2026-07-30",
    ]);
  });

  it("every returned date is a Tue or Thu by getUTCDay", () => {
    const slots = nextTueThuSlots(new Date("2026-07-05T00:00:00Z"), new Set(), 28);
    for (const s of slots) {
      const day = new Date(`${s}T00:00:00Z`).getUTCDay();
      expect([2, 4]).toContain(day);
    }
  });

  it("includes `from` itself when it is a Tue/Thu (inclusive lower bound)", () => {
    // 2026-07-07 is a Tuesday.
    const slots = nextTueThuSlots(new Date("2026-07-07T00:00:00Z"), new Set(), 7);
    expect(slots[0]).toBe("2026-07-07");
  });

  it("skips occupied dates", () => {
    const slots = nextTueThuSlots(
      new Date("2026-07-05T00:00:00Z"),
      new Set(["2026-07-07", "2026-07-14"]),
      28,
    );
    expect(slots).not.toContain("2026-07-07");
    expect(slots).not.toContain("2026-07-14");
    expect(slots).toContain("2026-07-09");
  });

  it("is UTC-based regardless of the from-Date's intraday time", () => {
    const slots = nextTueThuSlots(new Date("2026-07-05T23:59:59Z"), new Set(), 3);
    // 07-07 (Tue) is within 3 days of 07-05.
    expect(slots).toEqual(["2026-07-07"]);
  });
});

// --- planPromotions ----------------------------------------------------------

describe("planPromotions", () => {
  it("assigns ready drafts deterministically (filename asc) to successive free slots", () => {
    const files = [
      { path: "b.md", raw: readyDraft() },
      { path: "a.md", raw: readyDraft() },
    ];
    const plan = planPromotions({
      files,
      today: new Date("2026-07-05T00:00:00Z"),
      occupied: new Set(),
      horizonDays: 28,
    });
    expect(plan).toEqual([
      { path: "a.md", publishDate: "2026-07-07" },
      { path: "b.md", publishDate: "2026-07-09" },
    ]);
  });

  it("never double-books an occupied date (parked/published/etc.)", () => {
    const files = [{ path: "a.md", raw: readyDraft() }];
    const plan = planPromotions({
      files,
      today: new Date("2026-07-05T00:00:00Z"),
      occupied: new Set(["2026-07-07"]),
      horizonDays: 28,
    });
    expect(plan[0].publishDate).toBe("2026-07-09");
  });

  it("excludes non-ready files (parked/stale/no-channels)", () => {
    const files = [
      { path: "ready.md", raw: readyDraft() },
      { path: "parked.md", raw: readyDraft().replace("status: draft", "status: parked") },
      { path: "nochan.md", raw: readyDraft({ channels: "" }) },
    ];
    const plan = planPromotions({
      files,
      today: new Date("2026-07-05T00:00:00Z"),
      occupied: new Set(),
      horizonDays: 28,
    });
    expect(plan).toEqual([{ path: "ready.md", publishDate: "2026-07-07" }]);
  });

  it("cold-start backlog: 18 ready drafts fill only the ~8 horizon slots on run-1", () => {
    const files = Array.from({ length: 18 }, (_, i) => ({
      path: `draft-${String(i).padStart(2, "0")}.md`,
      raw: readyDraft(),
    }));
    const plan = planPromotions({
      files,
      today: new Date("2026-07-05T00:00:00Z"),
      occupied: new Set(),
      horizonDays: 28,
    });
    expect(plan.length).toBe(8);
    // deterministic prefix of the sorted list
    expect(plan.map((p) => p.path)).toEqual([
      "draft-00.md",
      "draft-01.md",
      "draft-02.md",
      "draft-03.md",
      "draft-04.md",
      "draft-05.md",
      "draft-06.md",
      "draft-07.md",
    ]);
    // no date reused
    const dates = plan.map((p) => p.publishDate);
    expect(new Set(dates).size).toBe(dates.length);
  });

  it("rolling window: a later run promotes the remainder as earlier slots burn", () => {
    const files = Array.from({ length: 18 }, (_, i) => ({
      path: `draft-${String(i).padStart(2, "0")}.md`,
      raw: readyDraft(),
    }));
    // Run-1 assigns the first 8. Simulate those becoming occupied+published,
    // and advance the window two weeks: new horizon slots open, remainder drains.
    const run1 = planPromotions({
      files,
      today: new Date("2026-07-05T00:00:00Z"),
      occupied: new Set(),
      horizonDays: 28,
    });
    const remaining = files.filter((f) => !run1.some((r) => r.path === f.path));
    const run2 = planPromotions({
      files: remaining,
      today: new Date("2026-07-19T00:00:00Z"),
      occupied: new Set(run1.map((r) => r.publishDate)),
      horizonDays: 28,
    });
    expect(run2.length).toBeGreaterThan(0);
    // no permanent skip: run1 ∪ run2 covers strictly more than run1
    expect(run1.length + run2.length).toBeGreaterThan(run1.length);
    // no date collision across runs
    const all = [...run1, ...run2].map((r) => r.publishDate);
    expect(new Set(all).size).toBe(all.length);
  });
});

// --- applyPromotion ----------------------------------------------------------

describe("applyPromotion", () => {
  it("flips status:draft→scheduled and writes an UNQUOTED publish_date", () => {
    const out = applyPromotion(readyDraft(), "2026-07-07");
    expect(out).toContain("status: scheduled");
    expect(out).not.toContain("status: draft");
    expect(out).toContain("publish_date: 2026-07-07");
    // unquoted — no wrapping quotes
    expect(out).not.toContain('publish_date: "2026-07-07"');
  });

  it("preserves every other line byte-for-byte", () => {
    const raw = readyDraft();
    const out = applyPromotion(raw, "2026-07-07");
    // Only the two frontmatter lines change; title/channels/body untouched.
    expect(out).toContain('title: "A headline: with an embedded colon, and, commas"');
    expect(out).toContain("channels: x, bluesky");
    expect(out).toContain("This is a real, non-empty X thread body that should post.");
    // Line count identical (targeted replacement, no reflow).
    expect(out.split("\n").length).toBe(raw.split("\n").length);
  });

  it("is idempotent: a no-op on an already-scheduled file", () => {
    const scheduled = applyPromotion(readyDraft({ publishDate: "" }), "2026-07-07");
    const again = applyPromotion(scheduled, "2026-07-09");
    expect(again).toBe(scheduled); // byte-identical, no re-date
  });

  it("does not touch a body line that happens to look like frontmatter", () => {
    const raw = `---
title: "T"
publish_date: ""
channels: x
status: draft
---

## X/Twitter Thread

status: draft (this is prose, not frontmatter)
`;
    const out = applyPromotion(raw, "2026-07-07");
    // The prose line is preserved; only the frontmatter status flips.
    expect(out).toContain("status: draft (this is prose, not frontmatter)");
    expect(out.match(/^status: scheduled$/m)).not.toBeNull();
  });
});

// --- constants ---------------------------------------------------------------

describe("constants", () => {
  it("HORIZON_DAYS is 28", () => {
    expect(HORIZON_DAYS).toBe(28);
  });
  it("PROMOTION_WEEKDAYS is [2, 4] (Tue, Thu)", () => {
    expect(PROMOTION_WEEKDAYS).toEqual([2, 4]);
  });
});
