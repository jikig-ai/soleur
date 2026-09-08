import Link from "next/link";
import {
  loadApiUsageForUser,
  relativeTime,
  formatUsd,
  MAX_USAGE_ROWS,
  type ApiUsageRow,
  type WorkflowCostRow,
} from "@/server/api-usage";
import { WORKFLOW_COPY } from "@/lib/messages/workflow-copy";
import { ApiUsageRetryButton } from "./api-usage-retry-button";
import { ApiUsageInfoTooltip } from "./api-usage-info-tooltip";

interface ApiUsageSectionProps {
  userId: string;
}

export async function ApiUsageSection({ userId }: ApiUsageSectionProps) {
  const usage = await loadApiUsageForUser(userId);

  return (
    <section
      aria-labelledby="api-usage-heading"
      className="mt-6 rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 p-6 shadow-sm"
    >
      <header className="mb-4 flex items-start justify-between gap-4">
        <div>
          <h2
            id="api-usage-heading"
            className="text-lg font-semibold text-soleur-text-primary"
          >
            API Usage
          </h2>
          <p className="mt-1 text-sm text-soleur-text-secondary">
            Actual spend on your Anthropic key. No markup, no middle layer —
            you pay the API directly.
          </p>
        </div>
        <div className="flex flex-col items-end gap-2 text-right">
          <ApiUsageInfoTooltip label="What is a token?">
            Tokens are the units Anthropic charges for. One token is about
            four characters of English. A short reply costs a few hundred; a
            long document with context can cost tens of thousands.
          </ApiUsageInfoTooltip>
          <ApiUsageInfoTooltip label="Why does cost vary?">
            Cost scales with input and output tokens. Longer prompts,
            attached documents, and longer replies all push it up. Model
            choice matters too — Opus costs more per token than Sonnet or
            Haiku.
          </ApiUsageInfoTooltip>
          <ApiUsageInfoTooltip label="What about cache tokens?">
            Prompt caching reduces real cost — Anthropic prices input in
            three tiers: uncached (full price), cache write (slightly
            higher first time), and cache read (a fraction of full
            price). The Input column sums all three to match the
            Anthropic Console&apos;s headline number; the Cache read and
            Cache write pills break out what landed in each tier when
            present.
          </ApiUsageInfoTooltip>
        </div>
      </header>

      {usage === null ? <ErrorState /> : <UsageBody usage={usage} />}
    </section>
  );
}

function ErrorState() {
  return (
    <div className="flex flex-col items-start gap-3 rounded-md bg-red-50 p-4 text-sm dark:bg-red-950/30">
      <div>
        <p className="font-semibold text-red-900 dark:text-red-200">
          Couldn&apos;t load your usage.
        </p>
        <p className="mt-1 text-red-800 dark:text-red-300">
          The dashboard couldn&apos;t reach the usage service. Your API key
          and billing are unaffected. Try again in a moment.
        </p>
      </div>
      <ApiUsageRetryButton />
    </div>
  );
}

function EmptyState() {
  return (
    <div className="flex flex-col items-start gap-3 py-6">
      <p className="text-base font-medium text-soleur-text-primary">
        No API calls yet this month.
      </p>
      <p className="max-w-prose text-sm text-soleur-text-secondary">
        Every conversation you run here bills straight to your Anthropic
        key. Start one and costs show up in this table the moment the
        response lands.
      </p>
      <Link
        href="/dashboard"
        className="inline-flex items-center rounded-md bg-soleur-accent-gold-fill px-3 py-1.5 text-sm font-medium text-soleur-text-on-accent hover:opacity-90 focus:outline-none focus:ring-2 focus:ring-soleur-border-emphasized focus:ring-offset-2"
      >
        Start a conversation
      </Link>
    </div>
  );
}

function UsageBody({
  usage,
}: {
  usage: {
    mtdTotalUsd: number;
    mtdCount: number;
    rows: ApiUsageRow[];
    byWorkflow: WorkflowCostRow[] | null;
  };
}) {
  const { mtdTotalUsd, mtdCount, rows, byWorkflow } = usage;
  const isEmpty = rows.length === 0 && mtdTotalUsd === 0;

  if (isEmpty) return <EmptyState />;

  const now = new Date();
  const monthName = now.toLocaleString("en-US", {
    month: "long",
    timeZone: "UTC",
  });
  const conversationsLabel = mtdCount === 1 ? "conversation" : "conversations";
  const zeroMtdWithHistory = mtdTotalUsd === 0 && rows.length > 0;

  return (
    <div>
      <p className="text-sm font-medium text-soleur-text-primary">
        {formatUsd(mtdTotalUsd)} in {monthName} · {mtdCount}{" "}
        {conversationsLabel}
      </p>
      {zeroMtdWithHistory && (
        <p className="mt-1 text-xs text-soleur-text-muted">
          Showing your last {MAX_USAGE_ROWS} conversations with cost.
          Nothing billed this month yet.
        </p>
      )}

      <WorkflowBreakdown byWorkflow={byWorkflow} mtdTotalUsd={mtdTotalUsd} />

      <div className="mt-4 overflow-hidden rounded-md border border-soleur-border-default">
        <UsageList rows={rows} />
      </div>

      {/*
        Copy spec §15 + §15b. Three edits against the shipped string, and no
        more: `any row` → `any conversation` (a second kind of row now exists
        on this surface), one new sentence scoping the promise to what the
        Console CAN confirm, and the `may under-reflect` hedge corrected to
        `under-report` — the condition is deterministic, and a hedge on the
        one surface whose positioning is exactness is its own defect.
        `match to the cent` is untouched, in the same clause and position.
      */}
      <p className="mt-3 text-xs text-soleur-text-muted">
        Figures come straight from the Anthropic SDK response. Cross-check
        any conversation in your Anthropic Console under Usage — the numbers
        will match to the cent. The Console has no workflow dimension, so it
        can confirm each conversation, not the split. Its monthly total will
        also differ: this page groups a conversation into the month it
        STARTED, while the Console groups spend by the day it was incurred.
        Conversations from before 2026-05-12 under-report cache-read tokens;
        newer ones capture all three input tiers.
      </p>
    </div>
  );
}

function UsageList({ rows }: { rows: ApiUsageRow[] }) {
  return (
    <ul className="divide-y divide-soleur-border-default">
      {rows.map((row) => {
        // The Anthropic Console's headline "input tokens" is the SUM
        // of uncached + cache_read + cache_creation. The SDK's
        // `usage.input_tokens` is the uncached subset only. Render the
        // SUM here so the cross-check footnote below stays true for
        // cached prompts (plan §Risks R8).
        const totalInput =
          row.inputTokens + row.cacheReadTokens + row.cacheCreationTokens;
        return (
          <li
            key={row.id}
            className="flex flex-wrap items-baseline gap-x-4 gap-y-1 px-4 py-3"
          >
            <span className="flex-1 min-w-[180px] text-sm text-soleur-text-primary">
              <span className="font-medium">[{row.domainLabel}]</span>
              <span className="mx-1 text-soleur-text-secondary" aria-hidden="true">
                ·
              </span>
              <span className="text-soleur-text-secondary">
                {relativeTime(row.createdAt.toISOString())}
              </span>
            </span>
            <span className="text-xs text-soleur-text-secondary">
              <span className="text-soleur-text-muted">Input </span>
              {totalInput.toLocaleString("en-US")}
            </span>
            <span className="text-xs text-soleur-text-secondary">
              <span className="text-soleur-text-muted">Output </span>
              {row.outputTokens.toLocaleString("en-US")}
            </span>
            {row.cacheReadTokens > 0 && (
              <span className="text-xs text-soleur-text-secondary">
                <span className="text-soleur-text-muted">Cache read </span>
                {row.cacheReadTokens.toLocaleString("en-US")}
              </span>
            )}
            {row.cacheCreationTokens > 0 && (
              <span className="text-xs text-soleur-text-secondary">
                <span className="text-soleur-text-muted">Cache write </span>
                {row.cacheCreationTokens.toLocaleString("en-US")}
              </span>
            )}
            <span className="min-w-[72px] text-right text-sm font-medium tabular-nums text-soleur-text-primary">
              {formatUsd(row.costUsd)}
            </span>
          </li>
        );
      })}
    </ul>
  );
}

// ---------------------------------------------------------------------------
// Per-workflow cost breakdown (#1055)
//
// Renders between the month-to-date summary line (copy §2) and the conversation
// list (§3/§4). Every string comes from
// `knowledge-base/project/specs/feat-restore-byok-usage-dashboard/copy.md`
// §§11-17; layout from
// `knowledge-base/product/design/byok-cost-tracking/workflow-cost-breakdown.pen`
// frames 06-09. Lives inside this file alongside `UsageBody` / `UsageList` /
// `EmptyState` / `ErrorState` (plan §Phase 3).
// ---------------------------------------------------------------------------

/**
 * Floor on a bar's rendered width, in percent.
 *
 * Bars are scaled to the LARGEST bucket, not the total — a $0.0004 bucket beside
 * an $8.12 one is 0.005% of the max and would be zero pixels wide. The floor is
 * what keeps a real, non-zero cost visible as a sliver rather than as nothing.
 */
const BAR_MIN_PERCENT = 1.5;

/**
 * The smallest amount `formatUsd` can render. Below it, `toFixed(4)` prints
 * `$0.0000` — a real cost shown as zero, which is the defect this guard exists
 * to stop (plan §Phase 3 "Display precision").
 */
const MIN_DISPLAYABLE_USD = 0.0001;

/** `formatUsd`, except a non-zero amount below display precision never reads as zero. */
function formatBucketUsd(n: number): string {
  if (n > 0 && n < MIN_DISPLAYABLE_USD) return "<$0.0001";
  return formatUsd(n);
}

/**
 * The grain `formatUsd` will actually render `totalUsd` at, as units per dollar.
 *
 * `formatUsd` switches precision at $0.01 (4dp below, 2dp above), so a single
 * fixed grain cannot match it. Allocating in whole cents against a headline
 * rendered at 4dp is what let a $0.0090 total display rows summing to $0.0150.
 */
/**
 * The display grain, as one record rather than three coupled expressions.
 *
 * This was previously `unitsPerDollar` alone, with the floor marker
 * reverse-inferred at the render site as `unitsPerDollar === 100 ? "<$0.01"
 * : "<$0.0001"`. That inference is only correct while exactly two grains
 * exist: adding a third would silently fall through to the 4dp marker and
 * render a false statement about a bucket. Returning the marker WITH the
 * grain makes that unrepresentable.
 *
 * `CENTS_CEILING` is the same threshold `formatUsd` switches on
 * (`server/api-usage.ts`), which is why the two must move together — the
 * allocator targets what the headline RENDERS, so a grain the formatter does
 * not share would reintroduce the parts-vs-whole mismatch this replaced.
 */
const CENTS_CEILING = 0.01;

interface DisplayGrain {
  unitsPerDollar: number;
  floorMarker: string;
}

function displayGrain(totalUsd: number): DisplayGrain {
  return totalUsd > 0 && totalUsd < CENTS_CEILING
    ? { unitsPerDollar: 1e4, floorMarker: "<$0.0001" }
    : { unitsPerDollar: 100, floorMarker: "<$0.01" };
}

/**
 * The headline's value in display units, PARSED BACK OUT of the rendered
 * string.
 *
 * This is the load-bearing part. Recomputing the target as
 * `Math.round(totalUsd * 100)` is a DIFFERENT rounding function from the
 * `toFixed(2)` the headline renders with, and the two disagree on exact
 * midpoints: `0.615` gives `Math.round` 62 and `toFixed(2)` "$0.61", so the
 * rows summed to a cent more than the headline directly beneath copy promising
 * they match. Deriving the target from `formatUsd`'s own output makes the
 * invariant structural rather than coincidental — the two cannot drift, because
 * there is only one formatter.
 */
function headlineDisplayUnits(totalUsd: number, unitsPerDollar: number): number {
  const rendered = formatUsd(totalUsd);
  const parsed = Number(rendered.replace(/[^0-9.]/g, ""));
  if (!Number.isFinite(parsed)) return 0;
  return Math.round(parsed * unitsPerDollar);
}

/**
 * Largest-remainder (Hare quota) allocation of the headline's display units
 * across the buckets, so the DISPLAYED parts sum to the DISPLAYED whole.
 *
 * Rounding each bucket independently is a real failure on data with no race at
 * all: eight buckets can each round down and leave ~$0.045 of visible
 * discrepancy beneath a "match to the cent" promise. The NUMERIC partition is
 * exact SQL-side (AC1/AC2); this only reconciles what rendering discards.
 *
 * Returns integer display units, index-aligned with `values`.
 */
function allocateDisplayUnits(
  values: number[],
  totalUsd: number,
  unitsPerDollar: number,
): number[] {
  // Scale through 1e6 before dropping to display units: `8.12 * 100` is
  // 811.9999999999999 in binary floating point, which would floor to 811 and
  // hand a unit back to the wrong bucket. `totalUsd` goes through the same
  // scaling via `headlineDisplayUnits` -> `formatUsd`, so both sides of the
  // residue are computed at one grain.
  const exact = values.map((v) =>
    v > 0 ? (Math.round(v * 1e6) / 1e6) * unitsPerDollar : 0,
  );
  const units = exact.map((e) => Math.floor(e));
  const allocated = units.reduce((a, b) => a + b, 0);
  const residue = headlineDisplayUnits(totalUsd, unitsPerDollar) - allocated;

  // A negative residue means the buckets already display for more than the
  // headline — only reachable if the partition invariant broke upstream. Floors
  // under-state rather than over-state; never invent a subtraction here.
  //
  // This early return is EQUIVALENT to falling through: the loop below is
  // `k < residue`, which does not iterate for residue <= 0. It is kept as an
  // explicit statement of intent, not because deleting it changes a verdict —
  // mutation-verified. Saying so here so the next reader does not spend a
  // round trying to write the fixture that kills it.
  if (residue <= 0) return units;

  const byRemainder = exact
    .map((e, i) => ({ i, remainder: e - units[i] }))
    // Ties resolve by the caller's order, which the loader already fixed as
    // (total desc, bucket name asc) — so the allocation is deterministic.
    .sort((a, b) => b.remainder - a.remainder || a.i - b.i);

  for (let k = 0; k < residue && k < byRemainder.length; k += 1) {
    units[byRemainder[k].i] += 1;
  }
  return units;
}

function BreakdownHeader() {
  return (
    <div className="flex items-start justify-between gap-4">
      <h3
        id="workflow-breakdown-heading"
        className="text-sm font-semibold text-soleur-text-primary"
      >
        Where it went
      </h3>
      {/*
        Copy §17: this tooltip attaches HERE, not to the section header. That
        header's three triggers are one family — they all explain how Anthropic
        prices a call. "What is a workflow?" explains a Soleur concept, and a
        fourth trigger up there turns a help column into a wall.
      */}
      <ApiUsageInfoTooltip label="What is a workflow?">
        A workflow is one of the routes Soleur runs your work down: exploring
        an idea, planning it, building it, reviewing it, or all of it in one
        go. Each conversation takes exactly one.
      </ApiUsageInfoTooltip>
    </div>
  );
}

function WorkflowBreakdown({
  byWorkflow,
  mtdTotalUsd,
}: {
  byWorkflow: WorkflowCostRow[] | null;
  mtdTotalUsd: number;
}) {
  // State 4 — the aggregate FAILED. `null` and `[]` mean different things and
  // the UI must not collapse them. A muted inset, deliberately NOT red: red is
  // reserved for `ErrorState`, where the founder has no numbers at all. Here
  // the headline and the list are correct and complete, and the copy says so.
  if (byWorkflow === null) {
    return (
      <div className="mt-4">
        <BreakdownHeader />
        <div className="mt-2 rounded-md bg-soleur-bg-surface-2 p-3">
          <p className="text-xs text-soleur-text-muted">
            Couldn&apos;t load the workflow split. Your total and the
            conversations below are unaffected — reload to try again.
          </p>
        </div>
      </div>
    );
  }

  const buckets = byWorkflow.filter((b) => b.totalUsd > 0);

  // State 2 — every dollar landed in `legacy`. Ordered AHEAD of the generic
  // single-bucket rule on purpose: set-wise this is a single-bucket case, but a
  // new user seeing nothing learns nothing, whereas "tracking started recently,
  // the split is coming" is actionable and resolves itself on the next
  // conversation (copy §16b).
  if (buckets.length === 1 && buckets[0].bucket === "legacy") {
    return (
      <div className="mt-4">
        <BreakdownHeader />
        <p className="mt-1 text-xs text-soleur-text-muted">
          Every conversation with spend this month started before workflow
          tracking. New ones show up here, split by workflow.
        </p>
      </div>
    );
  }

  // State 3 — any other single-bucket case, and zero-MTD-with-history. Render
  // NOTHING. Silence is what makes state 4 legible: on this surface absence
  // means "only one workflow" and a line means "something failed". A line here
  // would collapse that distinction and land on the most common early-user path
  // as if something were wrong (copy §16a).
  if (buckets.length < 2) return null;

  const maxTotal = Math.max(...buckets.map((b) => b.totalUsd));
  const { unitsPerDollar, floorMarker } = displayGrain(mtdTotalUsd);
  const units = allocateDisplayUnits(
    buckets.map((b) => b.totalUsd),
    mtdTotalUsd,
    unitsPerDollar,
  );

  return (
    <div className="mt-4">
      <BreakdownHeader />
      <p className="mt-1 text-xs text-soleur-text-secondary">
        Your spend this month, split by the workflow each conversation started
        in. Nothing is left out.
      </p>

      <ul className="mt-3 space-y-2">
        {buckets.map((b, i) => {
          // EVERY bucket renders from its allocation. The previous raw-value
          // fallback for a zero-allocated bucket escaped the allocation
          // entirely, so the column stopped summing to the headline by
          // construction; a sub-cent total then displayed rows totalling ~67%
          // more than the headline. A bucket holding real money but allocated
          // zero units renders `<$0.0001` via formatBucketUsd rather than a
          // bare $0.00 — honest about being non-zero without breaking the sum.
          const displayUsd = units[i] / unitsPerDollar;
          // A bucket holding real money but allocated ZERO units is below the
          // precision THIS PANEL IS DISPLAYING AT, which is not a fixed
          // threshold: the headline renders at 2dp above $0.01 and 4dp below
          // it, so the marker has to track the same grain. Saying `<$0.0001`
          // for a bucket holding $0.0004 under a cents-grain headline would be
          // simply false.
          //
          // It cannot render its exact figure either: the headline shows $8.12,
          // so the rows must sum to 812 cents, and a row printing $0.0004
          // alongside $8.12 sums to $8.1204 — breaking "Nothing is left out"
          // in the other direction. Grain-relative floor keeps the sum exact
          // AND never shows $0.00 for real spend (plan 3.3.3).
          const displayLabel =
            units[i] === 0 && b.totalUsd > 0
              ? floorMarker
              : formatBucketUsd(displayUsd);
          const percent = Math.max(
            maxTotal > 0 ? (b.totalUsd / maxTotal) * 100 : 0,
            BAR_MIN_PERCENT,
          );
          return (
            <li
              key={b.bucket}
              className="flex flex-wrap items-center gap-x-3 gap-y-1"
            >
              <span className="min-w-[140px] flex-none text-sm text-soleur-text-primary">
                {b.label}
              </span>
              <span
                aria-hidden="true"
                className="hidden h-1.5 min-w-[80px] flex-1 overflow-hidden rounded-full bg-soleur-bg-surface-3 sm:block"
              >
                <span
                  data-testid="workflow-bar-fill"
                  className="block h-full rounded-full bg-soleur-accent-gold-fill"
                  style={{ width: `${percent}%` }}
                />
              </span>
              <span
                data-testid="workflow-bucket-total"
                className="min-w-[72px] flex-none text-right text-sm font-medium tabular-nums text-soleur-text-primary"
              >
                {displayLabel}
              </span>
              <span className="min-w-[150px] flex-none text-xs text-soleur-text-muted">
                {/*
                  Copy §13. `n` counts CONVERSATIONS, not turns — one
                  conversation can span days of work. At n === 1 the average is
                  the total restated, and `· $0.36 each` beside `$0.36` reads as
                  a rendering bug, so it is suppressed.
                */}
                {b.count === 1
                  ? "1 conversation"
                  : `${b.count} conversations · ${formatBucketUsd(b.avgUsd)} each`}
              </span>
            </li>
          );
        })}
      </ul>

      {/*
        Copy §14, load-bearing (CFO F7). Renders whenever the breakdown renders
        — not behind a tooltip, and unconditional for every state that shows
        per-bucket figures. (It sits below the `buckets.length < 2` guard, so
        it does not render for the suppressed states — which show no per-bucket
        figures to misattribute. The earlier wording, "not conditional on
        bucket count", described the intent and not the control flow.) The lock is
        first-writer-wins (`soleur-go-runner.ts` gates on
        `state.currentWorkflow === null`), so a conversation that began in one
        workflow and carried on into another bills ENTIRELY to the first. The
        worked example is the disclosure: "first workflow it started" alone
        reads as a harmless implementation detail.

        The two workflow names in that sentence are read from `WORKFLOW_COPY`
        rather than typed as literals. They are the SAME strings the rows above
        render, and the example only lands if the reader can find those exact
        labels in the table -- transcribing them here would let a copy change
        silently break the correspondence the example depends on.
      */}
      <p className="mt-3 text-xs text-soleur-text-muted">
        Every conversation counts under the first workflow it started. One that
        began in {WORKFLOW_COPY.plan.label} and carried on into{" "}
        {WORKFLOW_COPY.work.label} counts entirely under{" "}
        {WORKFLOW_COPY.plan.label}.
      </p>
    </div>
  );
}
