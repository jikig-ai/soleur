import Link from "next/link";
import {
  loadApiUsageForUser,
  relativeTime,
  formatUsd,
  MAX_USAGE_ROWS,
  type ApiUsageRow,
} from "@/server/api-usage";
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
  usage: { mtdTotalUsd: number; mtdCount: number; rows: ApiUsageRow[] };
}) {
  const { mtdTotalUsd, mtdCount, rows } = usage;
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

      <div className="mt-4 overflow-hidden rounded-md border border-soleur-border-default">
        <UsageList rows={rows} />
      </div>

      <p className="mt-3 text-xs text-soleur-text-muted">
        Figures come straight from the Anthropic SDK response. Cross-check
        any row in your Anthropic Console under Usage — the numbers will
        match to the cent.
      </p>
    </div>
  );
}

function UsageList({ rows }: { rows: ApiUsageRow[] }) {
  return (
    <ul className="divide-y divide-soleur-border-default">
      {rows.map((row) => (
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
            {row.inputTokens.toLocaleString("en-US")}
          </span>
          <span className="text-xs text-soleur-text-secondary">
            <span className="text-soleur-text-muted">Output </span>
            {row.outputTokens.toLocaleString("en-US")}
          </span>
          <span className="min-w-[72px] text-right text-sm font-medium tabular-nums text-soleur-text-primary">
            {formatUsd(row.costUsd)}
          </span>
        </li>
      ))}
    </ul>
  );
}
