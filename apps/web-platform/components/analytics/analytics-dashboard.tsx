"use client";

import type { UserMetrics } from "@/lib/analytics";

// --- Inline SVG sparkline helper ---

function Sparkline({
  data,
  width = 80,
  height = 24,
  color = "#d97706",
}: {
  data: number[];
  width?: number;
  height?: number;
  color?: string;
}) {
  if (data.length === 0) {
    return <span className="text-neutral-600">—</span>;
  }

  if (data.length === 1) {
    return (
      <svg width={width} height={height} viewBox={`0 0 ${width} ${height}`}>
        <circle cx={width / 2} cy={height / 2} r={2} fill={color} />
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
    <svg width={width} height={height} viewBox={`0 0 ${width} ${height}`}>
      <polyline
        points={points}
        fill="none"
        stroke={color}
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

// --- Main component ---

export function AnalyticsDashboard({
  metrics,
}: {
  metrics: UserMetrics[];
}) {
  if (metrics.length === 0) {
    return (
      <div className="space-y-6">
        <h1 className="text-2xl font-semibold text-white">Analytics</h1>
        <div className="flex flex-col items-center justify-center min-h-[300px] rounded-xl border border-neutral-800 bg-neutral-900/50">
          <p className="text-neutral-400">No users registered yet.</p>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <h1 className="text-2xl font-semibold text-white">Analytics</h1>
      <p className="text-sm text-neutral-500">
        P4 validation metrics — {metrics.length} user{metrics.length !== 1 ? "s" : ""}
      </p>

      <div className="rounded-xl border border-neutral-800 bg-neutral-900/50 overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-neutral-800">
              <th className="px-4 py-3 text-left text-xs font-medium text-neutral-500 uppercase tracking-wider">
                User
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-neutral-500 uppercase tracking-wider">
                Domains
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-neutral-500 uppercase tracking-wider">
                Sessions
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-neutral-500 uppercase tracking-wider">
                Multi-Domain
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-neutral-500 uppercase tracking-wider">
                KB Growth
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-neutral-500 uppercase tracking-wider">
                TTFV
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-neutral-500 uppercase tracking-wider">
                Error Rate
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-neutral-500 uppercase tracking-wider">
                Status
              </th>
            </tr>
          </thead>
          <tbody>
            {metrics.map((m) => (
              <tr
                key={m.userId}
                className="border-b border-neutral-800/50 hover:bg-neutral-800/30"
              >
                <td className="px-4 py-3 text-neutral-300 font-mono text-xs">
                  {m.email}
                </td>
                <td className="px-4 py-3 text-neutral-400">
                  {m.totalSessions > 0 ? (
                    <span title={Object.entries(m.domainCounts).map(([k, v]) => `${k}: ${v}`).join(", ")}>
                      {Object.entries(m.domainCounts).map(([leader, count]) => (
                        <span key={leader} className="inline-block mr-1.5 text-xs">
                          <span className="text-amber-500">{leader}</span>
                          <span className="text-neutral-500 ml-0.5">{count}</span>
                        </span>
                      ))}
                    </span>
                  ) : (
                    <span className="text-neutral-600">—</span>
                  )}
                </td>
                <td className="px-4 py-3">
                  <div className="flex items-center gap-2">
                    <span className="text-neutral-300">{m.totalSessions}</span>
                    <Sparkline data={sessionSparklineData(m.sessionsByDay)} />
                  </div>
                </td>
                <td className="px-4 py-3 text-neutral-300">
                  {m.domainCount > 0 ? m.domainCount : <span className="text-neutral-600">—</span>}
                </td>
                <td className="px-4 py-3">
                  <div className="flex items-center gap-2">
                    <span className="text-neutral-300 text-xs">
                      {kbGrowthLabel(m.kbHistory)}
                    </span>
                    <Sparkline
                      data={kbSparklineData(m.kbHistory)}
                      color="#22c55e"
                    />
                  </div>
                </td>
                <td className="px-4 py-3 text-neutral-400">
                  {formatDays(m.ttfvDays)}
                </td>
                <td className="px-4 py-3">
                  <span
                    className={
                      m.errorRate > 0.5
                        ? "text-red-400"
                        : m.errorRate > 0
                          ? "text-amber-400"
                          : "text-neutral-400"
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
                    <span className="text-xs text-neutral-500">
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
    </div>
  );
}
