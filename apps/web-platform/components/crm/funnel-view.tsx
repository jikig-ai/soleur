"use client";

// Read-only conversion-funnel view (feat-beta-crm-ui #6172). Mirrors the bar
// style of components/analytics/analytics-dashboard.tsx FunnelSection, reskinned
// with per-stage accent hexes. Self-fetches GET /api/crm/funnel via SWR so the
// Board|Funnel toggle in crm-surface stays interactive even when this errors
// (AC9). Count-based only; conversionPct null → "insufficient data" (never a
// misleading 0/100% at beta volume). closed_lost is a terminal branch, shown
// apart. Honest thin-data footnote.

import useSWR from "swr";
import Link from "next/link";
import { jsonFetcher, swrKeys } from "@/lib/swr-config";
import { ErrorCard } from "@/components/ui/error-card";
import { LockIcon } from "@/components/icons";
import { STAGE_ACCENT, STAGE_LABEL, STAGE_ACCENT_FALLBACK, type Stage } from "./stage-style";

type FunnelStage = { stage: string; reached: number; conversionPct: number | null };
type PerTransition = { from: string; to: string; avgDays: number | null };
type FunnelResult = {
  stages: FunnelStage[];
  closedLost: number;
  avgTimeInStageDays: number | null;
  perTransition: PerTransition[];
};

const label = (s: string) => STAGE_LABEL[s as Stage] ?? s;

export function FunnelView() {
  const { data, error, isLoading, mutate } = useSWR<FunnelResult>(
    swrKeys.crmFunnel(),
    jsonFetcher,
  );

  if (error) {
    return (
      <ErrorCard
        title="Couldn't load the funnel"
        message="Something went wrong computing your conversion funnel. Please try again — or switch back to Board."
        onRetry={() => void mutate()}
      />
    );
  }
  if (isLoading || !data) {
    return (
      <div
        className="h-64 w-full animate-pulse rounded-xl border border-soleur-border-default/60 bg-soleur-bg-surface-1/40"
        aria-label="Loading funnel"
      />
    );
  }

  const entered = data.stages[0]?.reached ?? 0;
  const won = data.stages.find((s) => s.stage === "closed_won")?.reached ?? 0;
  const maxReached = Math.max(...data.stages.map((s) => s.reached), 1);

  if (entered === 0) {
    return (
      <section className="rounded-xl border border-soleur-border-default bg-soleur-bg-surface-1/50 p-6">
        <h2 className="mb-2 text-sm font-medium uppercase tracking-wider text-soleur-text-muted">
          Conversion funnel
        </h2>
        <p className="text-soleur-text-secondary">
          No contacts have entered the pipeline yet.
        </p>
      </section>
    );
  }

  return (
    <div className="space-y-4">
      <section className="rounded-xl border border-soleur-border-default bg-soleur-bg-surface-1/50 p-6">
        <div className="mb-4 flex items-baseline justify-between">
          <h2 className="text-sm font-medium uppercase tracking-wider text-soleur-text-muted">
            Conversion funnel
          </h2>
          <span className="text-xs tabular-nums text-soleur-text-muted">
            {entered} entered · {won} won
          </span>
        </div>
        <div className="space-y-2">
          {data.stages.map((s, i) => {
            const accent = STAGE_ACCENT[s.stage as Stage] ?? STAGE_ACCENT_FALLBACK;
            const widthPct = Math.round((s.reached / maxReached) * 100);
            const rightLabel =
              i === 0
                ? "Top of funnel"
                : s.conversionPct === null
                  ? "insufficient data"
                  : `${s.conversionPct}% of ${label(data.stages[i - 1].stage)}`;
            return (
              <div key={s.stage} className="flex items-center gap-3">
                <div className="flex w-32 shrink-0 items-center gap-1.5 text-sm text-soleur-text-secondary">
                  <span className="h-2 w-2 rounded-full" style={{ backgroundColor: accent }} aria-hidden />
                  {label(s.stage)}
                </div>
                <div className="relative h-7 flex-1 overflow-hidden rounded bg-soleur-bg-surface-2/30">
                  <div
                    className="flex h-full items-center rounded border px-2"
                    style={{
                      width: `${Math.max(widthPct, 8)}%`,
                      backgroundColor: `${accent}33`,
                      borderColor: `${accent}80`,
                    }}
                  >
                    <span className="text-xs font-medium tabular-nums text-soleur-text-primary">
                      {s.reached}
                    </span>
                  </div>
                </div>
                <div
                  className={`w-40 shrink-0 text-right text-xs tabular-nums ${
                    s.conversionPct === null && i > 0
                      ? "italic text-soleur-text-muted"
                      : "text-soleur-text-secondary"
                  }`}
                >
                  {rightLabel}
                </div>
              </div>
            );
          })}
        </div>
      </section>

      <div className="grid gap-4 md:grid-cols-[minmax(0,1fr)_2fr]">
        <ClosedLostCard count={data.closedLost} />
        <VelocityCard
          avg={data.avgTimeInStageDays}
          perTransition={data.perTransition}
        />
      </div>

      {/* Read-only escape hatch — AC11 requires the edit-via-agent hint on the
          funnel too (not just the board + drawer). */}
      <p className="flex items-center gap-1.5 text-xs text-soleur-text-muted">
        <LockIcon className="h-3.5 w-3.5 shrink-0" />
        Read-only. Update contacts by mentioning them in a{" "}
        <Link href="/dashboard/chat" className="text-soleur-accent-gold-fg hover:underline">
          chat with your CRO or CPO agent
        </Link>
        .
      </p>
    </div>
  );
}

function ClosedLostCard({ count }: { count: number }) {
  const accent = STAGE_ACCENT.closed_lost;
  return (
    <section className="rounded-xl border border-soleur-border-default bg-soleur-bg-surface-1/50 p-6">
      <div className="flex items-center gap-1.5">
        <span className="h-2 w-2 rounded-full" style={{ backgroundColor: accent }} aria-hidden />
        <h2 className="text-sm font-medium text-soleur-text-secondary">Closed Lost</h2>
      </div>
      <p className="mt-2 text-2xl font-semibold tabular-nums text-soleur-text-primary">
        {count}
      </p>
      <p className="mt-2 text-xs text-soleur-text-muted">
        Terminal branch — a contact that left the pipeline. Shown apart because it
        is not a funnel step.
      </p>
    </section>
  );
}

function VelocityCard({
  avg,
  perTransition,
}: {
  avg: number | null;
  perTransition: PerTransition[];
}) {
  return (
    <section className="rounded-xl border border-soleur-border-default bg-soleur-bg-surface-1/50 p-6">
      <div className="flex items-baseline gap-2">
        <span className="text-2xl font-semibold tabular-nums text-soleur-text-primary">
          {avg === null ? "—" : `${avg}d`}
        </span>
        <span className="text-sm text-soleur-text-muted">avg time-in-stage</span>
      </div>
      <div className="mt-3 flex flex-wrap gap-x-8 gap-y-2">
        {perTransition.map((p) => (
          <div key={`${p.from}-${p.to}`}>
            <p className="text-sm font-medium tabular-nums text-soleur-text-primary">
              {p.avgDays === null ? "—" : `${p.avgDays}d`}
            </p>
            <p className="text-[11px] text-soleur-text-muted">
              {label(p.from)} → {label(p.to)}
            </p>
          </div>
        ))}
      </div>
      <p className="mt-3 text-xs text-soleur-text-muted">
        Sourced from the append-only stage-transition history · thin at beta
        volume.
      </p>
    </section>
  );
}
