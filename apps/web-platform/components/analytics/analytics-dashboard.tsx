"use client";

import type { ReactNode } from "react";

import type { UserMetrics, FunnelResult } from "@/lib/analytics";
import { useIsMobile } from "@/hooks/use-is-mobile";

// --- Inline SVG sparkline helper ---

function Sparkline({
  data,
  width = 80,
  height = 24,
  colorClass = "text-soleur-accent-gold-fg",
}: {
  data: number[];
  width?: number;
  height?: number;
  colorClass?: string;
}) {
  if (data.length === 0) {
    return <span className="text-soleur-text-muted">—</span>;
  }

  if (data.length === 1) {
    return (
      <svg
        width={width}
        height={height}
        viewBox={`0 0 ${width} ${height}`}
        className={colorClass}
      >
        <circle cx={width / 2} cy={height / 2} r={2} fill="currentColor" />
      </svg>
    );
  }

  const max = Math.max(...data, 1);
  const padding = 2;
  const innerH = height - padding * 2;
  const step = (width - padding * 2) / (data.length - 1);

  const points = data
    .map((v, i) => {
      const x = padding + i * step;
      const y = padding + innerH - (v / max) * innerH;
      return `${x},${y}`;
    })
    .join(" ");

  return (
    <svg
      width={width}
      height={height}
      viewBox={`0 0 ${width} ${height}`}
      className={colorClass}
    >
      <polyline
        points={points}
        fill="none"
        stroke="currentColor"
        strokeWidth={1.5}
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}

// --- Helper to build sparkline data from sessionsByDay ---

function sessionSparklineData(
  sessionsByDay: Record<string, number>,
  days: number = 14,
): number[] {
  const now = new Date();
  const result: number[] = [];
  for (let i = days - 1; i >= 0; i--) {
    const d = new Date(now.getTime() - i * 86_400_000);
    const key = d.toISOString().slice(0, 10);
    result.push(sessionsByDay[key] ?? 0);
  }
  // Trim leading zeros to show only active period
  const firstNonZero = result.findIndex((v) => v > 0);
  return firstNonZero === -1 ? [] : result.slice(firstNonZero);
}

function kbSparklineData(
  history: Array<{ date: string; count: number }>,
): number[] {
  return history.map((h) => h.count);
}

// --- Format helpers ---

function formatDays(days: number | null): string {
  if (days === null) return "—";
  if (days === 0) return "<1d";
  return `${days}d`;
}

function formatPercent(rate: number): string {
  if (rate === 0) return "0%";
  return `${Math.round(rate * 100)}%`;
}

function kbGrowthLabel(
  history: Array<{ date: string; count: number }>,
): string {
  if (history.length === 0) return "—";
  const latest = history[history.length - 1];
  if (history.length === 1) return String(latest.count);
  const prev = history[history.length - 2];
  const delta = latest.count - prev.count;
  const sign = delta > 0 ? "+" : "";
  return `${latest.count} (${sign}${delta})`;
}

// --- Activation funnel section (#5049) ---

function FunnelSection({ funnel }: { funnel: FunnelResult }) {
  if (funnel.signupCount === 0) {
    return (
      <section className="rounded-xl border border-soleur-border-default bg-soleur-bg-surface-1/50 p-6">
        <h2 className="text-sm font-medium text-soleur-text-muted uppercase tracking-wider mb-2">
          Activation funnel
        </h2>
        <p className="text-soleur-text-secondary">No signups recorded yet.</p>
      </section>
    );
  }

  const maxCount = Math.max(...funnel.stages.map((s) => s.count), 1);

  return (
    <section className="rounded-xl border border-soleur-border-default bg-soleur-bg-surface-1/50 p-4 space-y-3 sm:p-6">
      <h2 className="text-sm font-medium text-soleur-text-muted uppercase tracking-wider">
        Activation funnel
      </h2>
      <div className="space-y-2">
        {funnel.stages.map((stage) => {
          const isActivated = stage.key === "activated";
          const widthPct = Math.round((stage.count / maxCount) * 100);
          return (
            <div key={stage.key} className="flex items-center gap-3">
              <div className="w-24 shrink-0 text-sm text-soleur-text-secondary flex items-center gap-1.5 sm:w-36">
                {stage.label}
                {isActivated && (
                  // Hidden on mobile: the narrow label column can't fit the
                  // badge without overlapping the funnel bar. The gold bar + the
                  // activation-definition text below already convey it.
                  <span
                    title={funnel.activationDef}
                    className="hidden text-[10px] font-semibold text-soleur-accent-gold-fg border border-soleur-accent-gold-fg/50 rounded px-1 cursor-help sm:inline"
                  >
                    SUCCESS METRIC
                  </span>
                )}
              </div>
              <div className="flex-1 h-6 rounded bg-soleur-bg-surface-2/40 overflow-hidden">
                <div
                  className={`h-full rounded ${
                    isActivated ? "bg-soleur-accent-gold-fg" : "bg-soleur-accent-gold-fg/40"
                  }`}
                  style={{ width: `${widthPct}%` }}
                />
              </div>
              <div className="w-12 shrink-0 text-right text-sm text-soleur-text-primary tabular-nums">
                {stage.count}
              </div>
              <div className="w-12 shrink-0 text-right text-xs text-soleur-text-muted tabular-nums sm:w-16">
                {/* Only a percentage drop gets a leading minus; the zero-prior
                    "—" sentinel and the first stage (null) stand alone. */}
                {stage.dropoffLabel === null
                  ? ""
                  : stage.dropoffLabel.endsWith("%")
                    ? `−${stage.dropoffLabel}`
                    : stage.dropoffLabel}
              </div>
            </div>
          );
        })}
      </div>
      <p className="text-xs text-soleur-text-muted">
        {funnel.activationDef}. Drop-off is relative to the preceding stage.
      </p>
    </section>
  );
}

// --- Mobile card layout (below md) ---
// Sibling renderer to the desktop <table>: one <tr> -> one card. Primary field
// (user email) bold top-left, churn status as a badge top-right, the remaining
// numeric metric columns collapse into a 2-col labeled stat grid. Every value is
// computed from the SAME helpers the table cells use — no duplicated logic.

function StatCell({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="min-w-0">
      <div className="text-[10px] font-medium uppercase tracking-wider text-soleur-text-muted">
        {label}
      </div>
      <div className="mt-0.5 text-soleur-text-secondary">{children}</div>
    </div>
  );
}

function MetricCard({ m }: { m: UserMetrics }) {
  return (
    <div className="rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 p-3 space-y-3">
      {/* Header: primary field (email) + churn status badge */}
      <div className="flex items-center justify-between gap-2">
        <span className="min-w-0 truncate font-mono text-xs font-medium text-soleur-text-primary">
          {m.email}
        </span>
        <span className="flex shrink-0 items-center gap-1.5">
          <span
            className={`inline-block w-2 h-2 rounded-full ${
              m.churning ? "bg-red-500" : "bg-green-500"
            }`}
          />
          <span className="whitespace-nowrap text-xs text-soleur-text-muted">
            {m.churning
              ? m.daysSinceLastSession !== null
                ? `${m.daysSinceLastSession}d ago`
                : "No sessions"
              : `${m.daysSinceLastSession ?? 0}d ago`}
          </span>
        </span>
      </div>

      {/* Numeric metric columns -> labeled 2-col stat grid (labels = headers) */}
      <div className="grid grid-cols-2 gap-2">
        <StatCell label="Domains">
          {m.totalSessions > 0 ? (
            <span
              title={Object.entries(m.domainCounts)
                .map(([k, v]) => `${k}: ${v}`)
                .join(", ")}
            >
              {Object.entries(m.domainCounts).map(([leader, count]) => (
                <span key={leader} className="inline-block mr-1.5 text-xs">
                  <span className="text-soleur-accent-gold-fg">{leader}</span>
                  <span className="text-soleur-text-muted ml-0.5">{count}</span>
                </span>
              ))}
            </span>
          ) : (
            <span className="text-soleur-text-muted">—</span>
          )}
        </StatCell>

        <StatCell label="Sessions">
          <span className="flex items-center gap-2">
            <span className="text-soleur-text-secondary">{m.totalSessions}</span>
            <Sparkline data={sessionSparklineData(m.sessionsByDay)} />
          </span>
        </StatCell>

        <StatCell label="Multi-Domain">
          {m.domainCount > 0 ? (
            m.domainCount
          ) : (
            <span className="text-soleur-text-muted">—</span>
          )}
        </StatCell>

        <StatCell label="KB Growth">
          <span className="flex items-center gap-2">
            <span className="text-soleur-text-secondary text-xs">
              {kbGrowthLabel(m.kbHistory)}
            </span>
            <Sparkline
              data={kbSparklineData(m.kbHistory)}
              colorClass="text-green-500"
            />
          </span>
        </StatCell>

        <StatCell label="TTFV">{formatDays(m.ttfvDays)}</StatCell>

        <StatCell label="Error Rate">
          <span
            className={
              m.errorRate > 0.5
                ? "text-red-400"
                : m.errorRate > 0
                  ? "text-amber-400"
                  : "text-soleur-text-secondary"
            }
          >
            {formatPercent(m.errorRate)}
          </span>
        </StatCell>
      </div>
    </div>
  );
}

// --- Main component ---

export function AnalyticsDashboard({
  metrics,
  funnel,
}: {
  metrics: UserMetrics[];
  funnel: FunnelResult;
}) {
  const isMobile = useIsMobile();

  if (metrics.length === 0) {
    return (
      <div className="mx-auto max-w-6xl px-4 py-6 space-y-6 sm:px-6 sm:py-8">
        <h1 className="text-2xl font-semibold text-soleur-text-primary">Analytics</h1>
        <FunnelSection funnel={funnel} />
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-6xl px-4 py-6 space-y-6 sm:px-6 sm:py-8">
      <h1 className="text-2xl font-semibold text-soleur-text-primary">Analytics</h1>
      <p className="text-sm text-soleur-text-muted">
        P4 validation metrics — {metrics.length} user{metrics.length !== 1 ? "s" : ""}
      </p>

      <FunnelSection funnel={funnel} />

      {isMobile ? (
        <div className="space-y-2">
          {metrics.map((m) => (
            <MetricCard key={m.userId} m={m} />
          ))}
        </div>
      ) : (
        <div className="rounded-xl border border-soleur-border-default bg-soleur-bg-surface-1/50 overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-soleur-border-default">
              <th className="px-4 py-3 text-left text-xs font-medium text-soleur-text-muted uppercase tracking-wider">
                User
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-soleur-text-muted uppercase tracking-wider">
                Domains
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-soleur-text-muted uppercase tracking-wider">
                Sessions
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-soleur-text-muted uppercase tracking-wider">
                Multi-Domain
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-soleur-text-muted uppercase tracking-wider">
                KB Growth
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-soleur-text-muted uppercase tracking-wider">
                TTFV
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-soleur-text-muted uppercase tracking-wider">
                Error Rate
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-soleur-text-muted uppercase tracking-wider">
                Status
              </th>
            </tr>
          </thead>
          <tbody>
            {metrics.map((m) => (
              <tr
                key={m.userId}
                className="border-b border-soleur-border-default/50 hover:bg-soleur-bg-surface-2/30"
              >
                <td className="px-4 py-3 text-soleur-text-secondary font-mono text-xs">
                  {m.email}
                </td>
                <td className="px-4 py-3 text-soleur-text-secondary">
                  {m.totalSessions > 0 ? (
                    <span title={Object.entries(m.domainCounts).map(([k, v]) => `${k}: ${v}`).join(", ")}>
                      {Object.entries(m.domainCounts).map(([leader, count]) => (
                        <span key={leader} className="inline-block mr-1.5 text-xs">
                          <span className="text-soleur-accent-gold-fg">{leader}</span>
                          <span className="text-soleur-text-muted ml-0.5">{count}</span>
                        </span>
                      ))}
                    </span>
                  ) : (
                    <span className="text-soleur-text-muted">—</span>
                  )}
                </td>
                <td className="px-4 py-3">
                  <div className="flex items-center gap-2">
                    <span className="text-soleur-text-secondary">{m.totalSessions}</span>
                    <Sparkline data={sessionSparklineData(m.sessionsByDay)} />
                  </div>
                </td>
                <td className="px-4 py-3 text-soleur-text-secondary">
                  {m.domainCount > 0 ? m.domainCount : <span className="text-soleur-text-muted">—</span>}
                </td>
                <td className="px-4 py-3">
                  <div className="flex items-center gap-2">
                    <span className="text-soleur-text-secondary text-xs">
                      {kbGrowthLabel(m.kbHistory)}
                    </span>
                    <Sparkline
                      data={kbSparklineData(m.kbHistory)}
                      colorClass="text-green-500"
                    />
                  </div>
                </td>
                <td className="px-4 py-3 text-soleur-text-secondary">
                  {formatDays(m.ttfvDays)}
                </td>
                <td className="px-4 py-3">
                  <span
                    className={
                      m.errorRate > 0.5
                        ? "text-red-400"
                        : m.errorRate > 0
                          ? "text-amber-400"
                          : "text-soleur-text-secondary"
                    }
                  >
                    {formatPercent(m.errorRate)}
                  </span>
                </td>
                <td className="px-4 py-3">
                  <div className="flex items-center gap-2">
                    <span
                      className={`inline-block w-2 h-2 rounded-full ${
                        m.churning ? "bg-red-500" : "bg-green-500"
                      }`}
                    />
                    <span className="text-xs text-soleur-text-muted">
                      {m.churning
                        ? m.daysSinceLastSession !== null
                          ? `${m.daysSinceLastSession}d ago`
                          : "No sessions"
                        : `${m.daysSinceLastSession ?? 0}d ago`}
                    </span>
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        </div>
      )}
    </div>
  );
}
