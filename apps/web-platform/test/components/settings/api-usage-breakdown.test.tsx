// #1055 Phase 3.2 — the per-workflow cost breakdown block inside
// `components/settings/api-usage-section.tsx`.
//
// Every assertion here is on RENDERED OUTPUT, never on source text. That is
// deliberate: the plan's task 3.3.5 records that a source grep for
// `may under-reflect` is VACUOUS, because the JSX wraps that phrase across two
// lines. Only `container.textContent` sees the string a founder actually reads.
//
// Copy authority: knowledge-base/project/specs/feat-restore-byok-usage-dashboard/copy.md
// §§11-17. Layout authority: knowledge-base/product/design/byok-cost-tracking/
// workflow-cost-breakdown.pen (frames 06-12).
import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";
import { render, screen } from "@testing-library/react";

const { mockLoad } = vi.hoisted(() => ({ mockLoad: vi.fn() }));

vi.mock("@/server/api-usage", async () => {
  const actual =
    await vi.importActual<typeof import("@/server/api-usage")>(
      "@/server/api-usage",
    );
  return {
    ...actual,
    loadApiUsageForUser: mockLoad,
  };
});

vi.mock("next/navigation", () => ({
  useRouter: () => ({ refresh: vi.fn(), push: vi.fn() }),
}));

import { ApiUsageSection } from "@/components/settings/api-usage-section";
import type { ApiUsageRow, WorkflowCostRow } from "@/server/api-usage";

const VALID_UUID = "11111111-1111-1111-1111-111111111111";

// Copy spec §12 labels. Duplicated as literals rather than imported from
// `lib/messages/workflow-copy.ts` on purpose: importing the map would make the
// test agree with the component by construction even if both drifted off spec.
const LABEL = {
  oneShot: "Idea to shipped",
  brainstorm: "Exploring an idea",
  plan: "Planning the work",
  work: "Doing the work",
  review: "Reviewing the code",
  backlog: "Clearing the backlog",
  unrouted: "No workflow started",
  legacy: "Before workflow tracking",
} as const;

function bucket(
  key: string,
  label: string,
  totalUsd: number,
  count: number,
): WorkflowCostRow {
  return {
    bucket: key,
    label,
    totalUsd,
    count,
    avgUsd: count > 0 ? totalUsd / count : 0,
  };
}

function conversation(id: string, costUsd: number): ApiUsageRow {
  return {
    id,
    domainLabel: "Engineering",
    createdAt: new Date("2026-04-17T10:00:00Z"),
    inputTokens: 100,
    outputTokens: 200,
    cacheReadTokens: 0,
    cacheCreationTokens: 0,
    costUsd,
  };
}

interface UsageFixture {
  mtdTotalUsd: number;
  mtdCount: number;
  rows?: ApiUsageRow[];
  byWorkflow: WorkflowCostRow[] | null;
}

// window-assembly: renderSection — the closure assertions below
// (`expect(amounts).toEqual([...])`) read bucket totals through the DOM query
// `[data-testid="workflow-bucket-total"]`. That selector is the window, and it
// is asserted complete against ONE thing: the count of buckets passed into this
// helper's `byWorkflow` fixture. `bucketAmounts()` enforces that equality
// before returning, so a bucket that rendered its total WITHOUT the testid, or
// outside the queried container, fails loudly instead of shrinking the list
// the assertion then matches exactly.
//
// What this does NOT establish: that the rendered figure came from the
// allocator rather than a raw passthrough. `formatBucketUsd` is exercised for
// that separately. The window is complete against bucket COUNT, not provenance.
async function renderSection(usage: UsageFixture) {
  mockLoad.mockResolvedValueOnce({
    rows: [conversation("c1", usage.mtdTotalUsd)],
    ...usage,
  });
  const element = await ApiUsageSection({ userId: VALID_UUID });
  const { container } = render(element);
  return container;
}

/**
 * Bucket totals as displayed, refusing to return a window narrower than the
 * fixture it stands for. Without the count check a `toEqual([...])` over this
 * list pins only what the selector happened to span -- the exact shape
 * `scripts/lint-window-closure-assertion.py` exists to catch.
 */
function bucketAmounts(container: HTMLElement, expectedBuckets: number): string[] {
  const nodes = Array.from(
    container.querySelectorAll<HTMLElement>('[data-testid="workflow-bucket-total"]'),
  );
  expect(nodes).toHaveLength(expectedBuckets);
  return nodes.map((el) => el.textContent ?? "");
}

function sectionText(container: HTMLElement): string {
  const section = container.querySelector("section");
  expect(section).not.toBeNull();
  return section!.textContent ?? "";
}

function barWidths(container: HTMLElement): number[] {
  return Array.from(
    container.querySelectorAll<HTMLElement>('[data-testid="workflow-bar-fill"]'),
  ).map((el) => Number.parseFloat(el.style.width));
}

// Copy spec §11 header — the single string whose presence/absence IS the
// suppression verdict. Nothing else in the section carries it.
const BLOCK_HEADER = "Where it went";

describe("ApiUsageSection — per-workflow cost breakdown (#1055)", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-04-17T12:00:00Z"));
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  describe("suppression matrix (3.3.2) — four states, four distinct renders", () => {
    test("state 1: >= 2 non-zero buckets renders the breakdown, ordered by spend descending", async () => {
      const container = await renderSection({
        mtdTotalUsd: 13.96,
        mtdCount: 30,
        byWorkflow: [
          bucket("work", LABEL.work, 8.12, 14),
          bucket("brainstorm", LABEL.brainstorm, 3.4, 6),
          bucket("plan", LABEL.plan, 1.55, 4),
          bucket("review", LABEL.review, 0.61, 3),
          bucket("drain-labeled-backlog", LABEL.backlog, 0.28, 2),
          bucket("unrouted", LABEL.unrouted, 0.0004, 1),
        ],
      });

      const text = sectionText(container);
      expect(text).toContain(BLOCK_HEADER);
      // §11b subhead — states the attribution rule before any number is read.
      expect(text).toContain(
        "Your spend this month, split by the workflow each conversation started in. Nothing is left out.",
      );

      // Labels present, in spend-descending DOM order.
      const order = [
        LABEL.work,
        LABEL.brainstorm,
        LABEL.plan,
        LABEL.review,
        LABEL.backlog,
        LABEL.unrouted,
      ].map((l) => text.indexOf(l));
      expect(order.every((i) => i >= 0)).toBe(true);
      expect([...order].sort((a, b) => a - b)).toEqual(order);

      // §13 secondary line: `{n} conversations · {avg} each`.
      expect(text).toContain("14 conversations · $0.58 each");
      // §13: n === 1 suppresses the average entirely.
      expect(text).toContain("1 conversation");
      expect(text).not.toContain("1 conversations");
    });

    test("state 2: legacy-only renders its OWN line — a different message from the single-workflow silence", async () => {
      const container = await renderSection({
        mtdTotalUsd: 2.18,
        mtdCount: 7,
        byWorkflow: [bucket("legacy", LABEL.legacy, 2.18, 7)],
      });

      const text = sectionText(container);
      // §16b — forward-looking, not apologetic, and NOT the §16c failure line.
      expect(text).toContain(
        "Every conversation with spend this month started before workflow tracking. New ones show up here, split by workflow.",
      );
      expect(text).toContain(BLOCK_HEADER);
      // No bars: a one-bucket breakdown restates the headline.
      expect(barWidths(container)).toHaveLength(0);
      // Must not be confusable with the load failure (§16c).
      expect(text).not.toContain("Couldn't load the workflow split");
    });

    test("state 3a: a single NON-legacy bucket renders nothing at all", async () => {
      const container = await renderSection({
        mtdTotalUsd: 4.27,
        mtdCount: 12,
        byWorkflow: [bucket("one-shot", LABEL.oneShot, 4.27, 12)],
      });

      const text = sectionText(container);
      // §16a: no copy. Absence means "only one workflow"; a line means
      // "something failed". Rendering anything here collapses that.
      expect(text).not.toContain(BLOCK_HEADER);
      expect(text).not.toContain(LABEL.oneShot);
      expect(text).not.toContain(
        "Every conversation with spend this month started before workflow tracking",
      );
      expect(text).not.toContain("Couldn't load the workflow split");
      expect(barWidths(container)).toHaveLength(0);
    });

    test("state 3b: zero-MTD-with-history (empty bucket array) renders nothing", async () => {
      const container = await renderSection({
        mtdTotalUsd: 0,
        mtdCount: 0,
        rows: [conversation("c1", 0.0042)],
        byWorkflow: [],
      });

      const text = sectionText(container);
      expect(text).not.toContain(BLOCK_HEADER);
      expect(text).not.toContain("Couldn't load the workflow split");
      // The pre-existing §2b helper line is untouched by this feature.
      expect(text).toContain("Nothing billed this month yet.");
    });

    test("state 3c: buckets that exist but hold zero spend render nothing", async () => {
      const container = await renderSection({
        mtdTotalUsd: 0,
        mtdCount: 0,
        rows: [conversation("c1", 0.0042)],
        byWorkflow: [
          bucket("plan", LABEL.plan, 0, 0),
          bucket("work", LABEL.work, 0, 0),
        ],
      });

      expect(sectionText(container)).not.toContain(BLOCK_HEADER);
    });

    test("state 4: byWorkflow === null renders ONE unavailable line in a muted inset — red stays reserved", async () => {
      const container = await renderSection({
        mtdTotalUsd: 13.96,
        mtdCount: 30,
        byWorkflow: null,
      });

      const text = sectionText(container);
      // §16c — exactly one line, no error banner, no retry button.
      const line =
        "Couldn't load the workflow split. Your total and the conversations below are unaffected — reload to try again.";
      expect(text).toContain(line);
      expect(text.split("Couldn't load the workflow split").length - 1).toBe(1);

      // The section is NOT in an error state: the headline and list are correct.
      expect(text).toContain("$13.96 in April · 30 conversations");
      expect(text).not.toContain("Couldn't load your usage.");
      expect(
        screen.queryByRole("button", { name: /Retry/i }),
      ).not.toBeInTheDocument();
      expect(
        screen.queryByRole("button", { name: /Try again/i }),
      ).not.toBeInTheDocument();

      // RED IS RESERVED for the section-wide failure. Walk from the line up to
      // the section root; no ancestor may carry a red treatment.
      const el = screen.getByText(new RegExp("Couldn.t load the workflow split"));
      const classes: string[] = [];
      for (
        let node: HTMLElement | null = el;
        node && node.tagName !== "SECTION";
        node = node.parentElement
      ) {
        classes.push(node.className);
      }
      expect(classes.join(" ")).not.toMatch(/red/);
      // ...and it IS a muted inset, not a bare paragraph.
      expect(classes.join(" ")).toMatch(/bg-soleur-bg-surface-[23]/);
    });
  });

  describe("bars scale to the largest bucket, not the total (3.3.1)", () => {
    test("the largest bucket fills the track; others are a fraction OF IT", async () => {
      const container = await renderSection({
        mtdTotalUsd: 10,
        mtdCount: 10,
        byWorkflow: [
          bucket("work", LABEL.work, 8, 8),
          bucket("plan", LABEL.plan, 2, 2),
        ],
      });

      const widths = barWidths(container);
      expect(widths).toHaveLength(2);
      expect(widths[0]).toBeCloseTo(100, 5);
      // 2/8 = 25%. Scaling to the TOTAL would render 2/10 = 20%.
      expect(widths[1]).toBeCloseTo(25, 5);
    });

    test("a sub-cent bucket beside a dollar bucket still gets a visible sliver", async () => {
      const container = await renderSection({
        mtdTotalUsd: 8.1204,
        mtdCount: 15,
        byWorkflow: [
          bucket("work", LABEL.work, 8.12, 14),
          bucket("unrouted", LABEL.unrouted, 0.0004, 1),
        ],
      });

      const widths = barWidths(container);
      // 0.0004/8.12 is 0.005% — zero pixels. A floor keeps it legible.
      expect(widths[1]).toBeGreaterThan(0.5);
      expect(widths[1]).toBeLessThan(widths[0]);
    });
  });

  describe("largest-remainder allocation (3.3.3)", () => {
    test("displayed parts sum to the displayed whole", async () => {
      const container = await renderSection({
        mtdTotalUsd: 1.0,
        mtdCount: 3,
        byWorkflow: [
          bucket("review", LABEL.review, 0.333334, 1),
          bucket("plan", LABEL.plan, 0.333333, 1),
          bucket("work", LABEL.work, 0.333333, 1),
        ],
      });

      const text = sectionText(container);
      // Naive per-row rounding yields $0.33 + $0.33 + $0.33 = $0.99 against a
      // $1.00 headline. Largest-remainder gives the odd cent to the largest
      // fractional remainder: $0.34 + $0.33 + $0.33 = $1.00.
      const amounts = bucketAmounts(container, 3);
      expect(amounts).toEqual(["$0.34", "$0.33", "$0.33"]);
      expect(text).toContain("$1.00 in April");
    });

    test("displayed parts never OVER-run the whole either", async () => {
      const container = await renderSection({
        mtdTotalUsd: 1.0,
        mtdCount: 3,
        byWorkflow: [
          bucket("review", LABEL.review, 0.336, 1),
          bucket("plan", LABEL.plan, 0.336, 1),
          bucket("work", LABEL.work, 0.328, 1),
        ],
      });

      // Naive per-row rounding yields $0.34 + $0.34 + $0.33 = $1.01 against a
      // $1.00 headline — an over-run, and the direction a `Math.round` per row
      // gets wrong. Only one bucket may take the odd cent.
      const amounts = bucketAmounts(container, 3);
      expect(amounts).toEqual(["$0.34", "$0.33", "$0.33"]);
    });

    // REVIEW FIX (two agents converged). The three cases above all use totals
    // where `Math.round(total * 100)` and `total.toFixed(2)` happen to AGREE,
    // so they could not see the allocator targeting a different rounding
    // function from the one that renders the headline. These two straddle an
    // exact midpoint, where the two disagree.
    test("straddle: 0.615 — allocator target must follow the RENDERED headline", async () => {
      const container = await renderSection({
        mtdTotalUsd: 0.615,
        mtdCount: 2,
        byWorkflow: [
          bucket("review", LABEL.review, 0.41, 1),
          bucket("plan", LABEL.plan, 0.205, 1),
        ],
      });
      const text = sectionText(container);
      const amounts = Array.from(
        container.querySelectorAll<HTMLElement>(
          '[data-testid="workflow-bucket-total"]',
        ),
      ).map((el) => el.textContent ?? "");
      // toFixed(2) renders $0.61; Math.round(0.615*100) is 62. Targeting the
      // latter handed out a cent the headline does not show, so the rows
      // summed to $0.62 four lines above "the numbers will match to the cent".
      expect(text).toContain("$0.61");
      const centsSum = amounts.reduce(
        (a, v) => a + Math.round(Number(v.replace(/[^0-9.]/g, "")) * 100),
        0,
      );
      expect(centsSum).toBe(61);
    });

    test("sub-cent total: rows sum to the 4dp headline, not to whole cents", async () => {
      const container = await renderSection({
        mtdTotalUsd: 0.009,
        mtdCount: 3,
        byWorkflow: [
          bucket("review", LABEL.review, 0.004, 1),
          bucket("plan", LABEL.plan, 0.004, 1),
          bucket("work", LABEL.work, 0.001, 1),
        ],
      });
      const text = sectionText(container);
      const amounts = Array.from(
        container.querySelectorAll<HTMLElement>(
          '[data-testid="workflow-bucket-total"]',
        ),
      ).map((el) => el.textContent ?? "");
      // formatUsd renders a sub-cent total at 4dp ($0.0090), but the allocator
      // worked in whole CENTS: one bucket took a full cent ($0.01) while the
      // rest printed raw 4dp values, so the rows displayed $0.0150 — 67% over
      // the headline — under "Nothing is left out".
      expect(text).toContain("$0.0090");
      const unitsSum = amounts.reduce(
        (a, v) => a + Math.round(Number(v.replace(/[^0-9.]/g, "")) * 1e4),
        0,
      );
      expect(unitsSum).toBe(90);
    });

    test("a non-zero amount below display precision renders a floor marker for THAT grain, NEVER $0.0000", async () => {
      const container = await renderSection({
        mtdTotalUsd: 8.12,
        mtdCount: 15,
        byWorkflow: [
          bucket("work", LABEL.work, 8.12, 14),
          bucket("unrouted", LABEL.unrouted, 0.00003, 1),
        ],
      });

      const text = sectionText(container);
      // The headline is $8.12 — cents grain — so the marker is "<$0.01".
      // ("<$0.0001" is also true of this particular bucket, but the marker
      // states what is below the precision ON SCREEN, and pinning the 4dp
      // literal here is what let the cents-grain case render a false one for a
      // $0.0004 bucket. See the sibling ABOVE-4dp test.)
      expect(text).toContain("<$0.01");
      // Rendering real money as zero is the defect this rule exists to stop.
      expect(text).not.toContain("$0.0000");
      expect(text).not.toContain("$0.00 ");
    });

    test("the floor marker follows the grain: sub-cent total uses the 4dp marker", async () => {
      const container = await renderSection({
        mtdTotalUsd: 0.005,
        mtdCount: 3,
        byWorkflow: [
          bucket("work", LABEL.work, 0.005, 2),
          bucket("unrouted", LABEL.unrouted, 0.00003, 1),
        ],
      });

      const text = sectionText(container);
      // Headline renders 4dp here ($0.0050), so the floor is one 1e-4 unit.
      expect(text).toContain("<$0.0001");
      expect(text).not.toContain("<$0.01");
      expect(text).not.toContain("$0.0000");
    });

    test("a sub-cent bucket ABOVE 4dp precision renders its real figure, not the floor marker", async () => {
      const container = await renderSection({
        mtdTotalUsd: 8.1204,
        mtdCount: 15,
        byWorkflow: [
          bucket("work", LABEL.work, 8.12, 14),
          bucket("unrouted", LABEL.unrouted, 0.0004, 1),
        ],
      });

      const text = sectionText(container);
      // UPDATED AT REVIEW. This previously expected the literal "$0.0004".
      // That expectation encoded the defect: the headline renders $8.12, so
      // the rows must sum to 812 cents, and a row printing $0.0004 next to
      // $8.12 sums to $8.1204 — the parts out-running the whole, directly
      // under "Nothing is left out".
      //
      // The bucket still holds real money and must never read $0.00, so it
      // renders the floor marker for the grain currently on screen. At cents
      // grain that is "<$0.01" — "<$0.0001" would be a false statement about a
      // bucket holding $0.0004.
      expect(text).toContain("<$0.01");
      expect(text).not.toContain("$0.0000");
      expect(text).toContain("$8.12 in April");
    });
  });

  describe("attribution disclosure (3.3.4)", () => {
    const NOTE =
      "Every conversation counts under the first workflow it started. One that began in Planning the work and carried on into Doing the work counts entirely under Planning the work.";

    // NOT "not conditional on bucket count" — the earlier name. The disclosure
    // sits below the `buckets.length < 2` guard, so it is conditional on
    // exactly that. What it is unconditional ON is the breakdown: wherever
    // per-bucket figures render, the sentence explaining how they are
    // attributed renders too, in prose rather than behind a tooltip. The
    // suppressed states show no figures to misattribute. Naming the guard the
    // test does not cross was the drift; the component concedes it too.
    test("renders wherever the breakdown does — as prose, not behind a tooltip", async () => {
      for (const byWorkflow of [
        [bucket("work", LABEL.work, 8.12, 14), bucket("plan", LABEL.plan, 1.55, 4)],
        [
          bucket("work", LABEL.work, 8.12, 14),
          bucket("plan", LABEL.plan, 1.55, 4),
          bucket("review", LABEL.review, 0.61, 3),
          bucket("legacy", LABEL.legacy, 0.28, 2),
        ],
      ]) {
        const container = await renderSection({
          mtdTotalUsd: byWorkflow.reduce((a, b) => a + b.totalUsd, 0),
          mtdCount: byWorkflow.reduce((a, b) => a + b.count, 0),
          byWorkflow,
        });
        expect(sectionText(container)).toContain(NOTE);
        // Not inside a <details> disclosure — it is unconditional prose.
        const el = screen.getAllByText(/Every conversation counts under/)[0];
        expect(el.closest("details")).toBeNull();
        vi.clearAllMocks();
      }
    });

    test("carries no hedge words", async () => {
      const container = await renderSection({
        mtdTotalUsd: 9.67,
        mtdCount: 18,
        byWorkflow: [
          bucket("work", LABEL.work, 8.12, 14),
          bucket("plan", LABEL.plan, 1.55, 4),
        ],
      });

      const text = sectionText(container);
      expect(text).not.toMatch(/estimated/i);
      expect(text).not.toMatch(/approximate/i);
      expect(text).not.toMatch(/\baround\b/i);
      expect(text).not.toMatch(/roughly/i);
      expect(text).not.toContain("~");
    });
  });

  describe("footnote scoping (3.3.5) — asserted on RENDERED TEXT, never on source", () => {
    async function footnoteText() {
      const container = await renderSection({
        mtdTotalUsd: 9.67,
        mtdCount: 18,
        byWorkflow: [
          bucket("work", LABEL.work, 8.12, 14),
          bucket("plan", LABEL.plan, 1.55, 4),
        ],
      });
      // Collapse the JSX's line-wrapping whitespace: the component splits
      // `may under-reflect` across two source lines, which is exactly why a
      // source grep for it is vacuous and this assertion is not.
      return sectionText(container).replace(/\s+/g, " ");
    }

    test("`match to the cent` survives byte-unchanged", async () => {
      expect(await footnoteText()).toContain(
        "the numbers will match to the cent.",
      );
    });

    test("adds the sentence enumerating what the Console CAN confirm", async () => {
      // CORRECTED AT REVIEW. The original sentence claimed the Console "can
      // confirm the total". It cannot: this page's month groups a conversation
      // by when it STARTED (`created_at >= since` in both RPCs), while the
      // Console groups spend by the day it was INCURRED. A conversation opened
      // 2026-08-28 that burns $50 on 2026-09-05 is absent from this page's
      // September total and present in the Console's — ordinary use on a
      // product where one conversation spans days. The old copy told the user
      // to read that difference as Soleur being wrong.
      //
      // Per-conversation cross-check still holds, so the promise is narrowed
      // rather than dropped, and the window semantics are stated outright.
      const text = await footnoteText();
      expect(text).toContain(
        "it can confirm each conversation, not the split",
      );
      expect(text).toContain("groups a conversation into the month it");
      expect(text).toContain("STARTED");
      // The superseded over-claim must not survive anywhere in the footnote.
      expect(text).not.toContain("can confirm the total and each conversation");
    });

    test("the hedge is corrected to `under-report`", async () => {
      const text = await footnoteText();
      expect(text).toContain(
        "Conversations from before 2026-05-12 under-report cache-read tokens; newer ones capture all three input tiers.",
      );
      expect(text).not.toContain("under-reflect");
      expect(text).not.toContain("may under-report");
    });

    test("`any row` is narrowed to `any conversation` now a second kind of row exists", async () => {
      const text = await footnoteText();
      expect(text).toContain("Cross-check any conversation in your Anthropic Console");
      expect(text).not.toContain("Cross-check any row");
    });
  });

  describe("no raw slug ever reaches the DOM (3.2)", () => {
    test("every bucket key is rendered through the label map", async () => {
      const container = await renderSection({
        mtdTotalUsd: 14.28,
        mtdCount: 32,
        byWorkflow: [
          bucket("one-shot", LABEL.oneShot, 8.12, 14),
          bucket("brainstorm", LABEL.brainstorm, 3.4, 6),
          bucket("plan", LABEL.plan, 1.55, 4),
          bucket("work", LABEL.work, 0.61, 3),
          bucket("review", LABEL.review, 0.32, 3),
          bucket("drain-labeled-backlog", LABEL.backlog, 0.28, 2),
          bucket("unrouted", LABEL.unrouted, 0.0004, 1),
          bucket("legacy", LABEL.legacy, 0.0, 1),
        ],
      });

      const text = sectionText(container);
      for (const slug of [
        "drain-labeled-backlog",
        "__unrouted__",
        "__legacy__",
        "one-shot",
        "unrouted",
        "legacy",
      ]) {
        expect(text).not.toContain(slug);
      }
    });
  });

  describe("`What is a workflow?` tooltip placement (3.3.6)", () => {
    test("attaches to the breakdown block header, not the section header", async () => {
      const container = await renderSection({
        mtdTotalUsd: 9.67,
        mtdCount: 18,
        byWorkflow: [
          bucket("work", LABEL.work, 8.12, 14),
          bucket("plan", LABEL.plan, 1.55, 4),
        ],
      });

      const trigger = screen.getByText("What is a workflow?", {
        selector: "summary > span",
      });
      expect(trigger).toBeInTheDocument();
      expect(sectionText(container)).toContain(
        "A workflow is one of the routes Soleur runs your work down: exploring an idea, planning it, building it, reviewing it, or all of it in one go. Each conversation takes exactly one.",
      );

      // The section header already carries three tooltips of a different
      // family (they all explain how Anthropic prices a call). A fourth there
      // turns a right-aligned help column into a wall.
      const sectionHeader = container.querySelector("section > header");
      expect(sectionHeader).not.toBeNull();
      expect(sectionHeader!.contains(trigger)).toBe(false);
      expect(sectionHeader!.querySelectorAll("details")).toHaveLength(3);

      // It lives with the block it explains.
      const blockHeading = screen.getByText(BLOCK_HEADER);
      expect(blockHeading.parentElement?.contains(trigger)).toBe(true);
    });

    test("the tooltip does not render when the breakdown is suppressed", async () => {
      await renderSection({
        mtdTotalUsd: 4.27,
        mtdCount: 12,
        byWorkflow: [bucket("one-shot", LABEL.oneShot, 4.27, 12)],
      });

      expect(
        screen.queryByText("What is a workflow?", { selector: "summary > span" }),
      ).not.toBeInTheDocument();
    });
  });
});
