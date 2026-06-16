"use client";

// Routines management surface (#5345 PR-1). Two tabs (Routines / Recent Runs)
// + Run-now with a confirm modal for protected routines. Spec-flow states:
// P0-1 (post-trigger ack + optimistic Running + disable-while-in-flight),
// P1-4 (empty state), P1-5 (failed-run drill-in → error_summary), P1-6
// (keyset pagination). PR-2 adds the Concierge tab.

import { useCallback, useEffect, useState } from "react";

// Delay before the single post-trigger reconciliation refetch that swaps the
// optimistic "running" row for the real terminal routine_runs row.
const RECONCILE_DELAY_MS = 5000;

interface RunSummary {
  status: string;
  trigger_source: string;
  started_at: string;
  ended_at: string | null;
  duration_ms: number | null;
  error_summary: string | null;
}
interface RoutineItem {
  fnId: string;
  domain: string;
  ownerRole: string;
  scheduleLabel: string;
  manualTrigger: "allowed" | "confirm";
  lastRun: RunSummary | null;
}
interface RecentRun extends RunSummary {
  id: string;
  routine_id: string;
}

function humanizeFnId(fnId: string): string {
  const s = fnId.replace(/^cron-/, "").replace(/-/g, " ");
  return s.charAt(0).toUpperCase() + s.slice(1);
}

function relativeTime(iso: string): string {
  const then = Date.parse(iso);
  if (Number.isNaN(then)) return iso;
  const diffMs = Date.now() - then;
  const min = Math.round(diffMs / 60000);
  if (min < 1) return "just now";
  if (min < 60) return `${min}m ago`;
  const hr = Math.round(min / 60);
  if (hr < 24) return `${hr}h ago`;
  return `${Math.round(hr / 24)}d ago`;
}

function formatDuration(ms: number | null): string {
  if (ms == null) return "—";
  if (ms < 1000) return `${ms}ms`;
  const s = Math.round(ms / 1000);
  if (s < 60) return `${s}s`;
  const m = Math.floor(s / 60);
  return `${m}m ${s % 60}s`;
}

const STATUS_COLOR: Record<string, string> = {
  completed: "text-green-400",
  failed: "text-red-400",
  running: "text-blue-400",
};

function StatusPill({ status }: { status: string }) {
  const color = STATUS_COLOR[status] ?? "text-soleur-text-muted";
  return (
    <span className={`inline-flex items-center gap-1.5 text-xs ${color}`}>
      <span className="h-1.5 w-1.5 rounded-full bg-current" />
      {status === "never" ? "Never" : status}
    </span>
  );
}

export function RoutinesSurface() {
  const [tab, setTab] = useState<"routines" | "runs">("routines");
  return (
    <div>
      <div
        role="tablist"
        className="mb-5 flex gap-5 border-b border-soleur-border-default"
      >
        <TabButton active={tab === "routines"} onClick={() => setTab("routines")}>
          Routines
        </TabButton>
        <TabButton active={tab === "runs"} onClick={() => setTab("runs")}>
          Recent Runs
        </TabButton>
        <span
          className="ml-auto cursor-not-allowed self-center pb-2 text-xs text-soleur-text-muted"
          title="Concierge routine authoring ships in v2"
        >
          Draft a routine
          <span className="ml-1 rounded bg-soleur-bg-surface-1 px-1 py-0.5 text-[10px]">
            v2
          </span>
        </span>
      </div>
      {tab === "routines" ? <RoutinesTab /> : <RecentRunsTab />}
    </div>
  );
}

function TabButton({
  active,
  onClick,
  children,
}: {
  active: boolean;
  onClick: () => void;
  children: React.ReactNode;
}) {
  return (
    <button
      role="tab"
      aria-selected={active}
      onClick={onClick}
      className={`-mb-px border-b-2 pb-2 text-sm ${
        active
          ? "border-soleur-text-primary text-soleur-text-primary"
          : "border-transparent text-soleur-text-secondary hover:text-soleur-text-primary"
      }`}
    >
      {children}
    </button>
  );
}

function RoutinesTab() {
  const [routines, setRoutines] = useState<RoutineItem[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState<Record<string, boolean>>({});
  const [confirming, setConfirming] = useState<RoutineItem | null>(null);

  const load = useCallback(async () => {
    setError(null);
    try {
      const res = await fetch("/api/dashboard/routines");
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const json = (await res.json()) as { routines: RoutineItem[] };
      setRoutines(json.routines);
    } catch (e) {
      setError(e instanceof Error ? e.message : "load failed");
    }
  }, []);

  useEffect(() => {
    void load();
  }, [load]);

  const runNow = useCallback(
    async (item: RoutineItem, confirmed: boolean) => {
      setBusy((b) => ({ ...b, [item.fnId]: true }));
      try {
        const res = await fetch("/api/dashboard/routines/run", {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({ fnId: item.fnId, confirmed }),
        });
        if (res.status === 409) {
          setConfirming(item); // protected — show confirm modal
          return;
        }
        // 202 (or any non-409): optimistic "Running", then reconcile against
        // DB truth. The optimistic row has no terminal state of its own — the
        // cron writes its routine_runs row when it finishes — so without this
        // refetch the row would read "running" forever until a page reload.
        setRoutines((rs) =>
          rs
            ? rs.map((r) =>
                r.fnId === item.fnId
                  ? {
                      ...r,
                      lastRun: {
                        status: "running",
                        trigger_source: "manual",
                        started_at: new Date().toISOString(),
                        ended_at: null,
                        duration_ms: null,
                        error_summary: null,
                      },
                    }
                  : r,
              )
            : rs,
        );
        setConfirming(null);
        // One delayed reconciliation refetch (not a polling loop — a single
        // bounded GET) to replace the optimistic "running" with the real
        // terminal row once the run has had a moment to complete.
        setTimeout(() => {
          void load();
        }, RECONCILE_DELAY_MS);
      } finally {
        setBusy((b) => ({ ...b, [item.fnId]: false }));
      }
    },
    [load],
  );

  if (error)
    return (
      <div className="rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 p-5 text-sm text-red-400">
        Failed to load routines: {error}
      </div>
    );
  if (!routines)
    return <div className="py-8 text-sm text-soleur-text-muted">Loading…</div>;

  const groups = groupByDomain(routines);

  return (
    <div>
      <div className="mb-3 text-sm text-soleur-text-muted">
        {routines.length} routines
      </div>
      {Object.entries(groups).map(([domain, items]) => (
        <section key={domain} className="mb-6">
          <h2 className="mb-2 text-xs font-semibold uppercase tracking-wide text-soleur-text-muted">
            {domain}{" "}
            <span className="ml-1 text-soleur-text-muted/70">{items.length}</span>
          </h2>
          <ul className="divide-y divide-soleur-border-default rounded-lg border border-soleur-border-default">
            {items.map((item) => (
              <RoutineRow
                key={item.fnId}
                item={item}
                busy={!!busy[item.fnId]}
                onRunNow={() => runNow(item, false)}
              />
            ))}
          </ul>
        </section>
      ))}

      {confirming && (
        <ConfirmRunModal
          item={confirming}
          busy={!!busy[confirming.fnId]}
          onCancel={() => setConfirming(null)}
          onConfirm={() => runNow(confirming, true)}
        />
      )}
    </div>
  );
}

function groupByDomain(routines: RoutineItem[]): Record<string, RoutineItem[]> {
  const out: Record<string, RoutineItem[]> = {};
  for (const r of routines) {
    (out[r.domain] ??= []).push(r);
  }
  return out;
}

function RoutineRow({
  item,
  busy,
  onRunNow,
}: {
  item: RoutineItem;
  busy: boolean;
  onRunNow: () => void;
}) {
  const last = item.lastRun;
  return (
    <li className="flex items-center gap-4 px-4 py-3">
      <div className="min-w-0 flex-1">
        <div className="truncate text-sm text-soleur-text-primary">
          {humanizeFnId(item.fnId)}
        </div>
        <div className="mt-1 flex items-center gap-2 text-xs text-soleur-text-muted">
          <span className="rounded bg-soleur-bg-surface-1 px-1.5 py-0.5">
            {item.domain}
          </span>
          <span className="rounded border border-soleur-border-default px-1.5 py-0.5">
            {item.ownerRole}
          </span>
          <span className="font-mono">{item.scheduleLabel}</span>
          {item.manualTrigger === "confirm" && (
            <span className="text-amber-400" title="Protected — confirm to run">
              ⚠ protected
            </span>
          )}
        </div>
      </div>
      <div className="w-40 text-right text-xs">
        {last ? (
          <>
            <StatusPill status={last.status} />
            <div className="mt-0.5 text-soleur-text-muted">
              {relativeTime(last.started_at)} · {formatDuration(last.duration_ms)}
            </div>
          </>
        ) : (
          <StatusPill status="never" />
        )}
      </div>
      <button
        onClick={onRunNow}
        disabled={busy}
        data-testid={`run-now-${item.fnId}`}
        className="rounded border border-soleur-border-default px-3 py-1 text-xs text-soleur-text-primary hover:bg-soleur-bg-surface-1 disabled:cursor-not-allowed disabled:opacity-50"
      >
        {busy ? "Running…" : "▷ Run now"}
      </button>
      <span className="text-xs text-green-400">● On</span>
    </li>
  );
}

function ConfirmRunModal({
  item,
  busy,
  onCancel,
  onConfirm,
}: {
  item: RoutineItem;
  busy: boolean;
  onCancel: () => void;
  onConfirm: () => void;
}) {
  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-label="Run protected routine"
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4"
    >
      <div className="w-full max-w-md rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 p-5">
        <h3 className="flex items-center gap-2 text-sm font-medium text-soleur-text-primary">
          <span className="text-amber-400">⚠</span> Run protected routine now?
        </h3>
        <p className="mt-1 text-xs text-soleur-text-secondary">
          This routine is protected. Off-schedule manual runs require
          confirmation.
        </p>
        <div className="mt-3 rounded border border-soleur-border-default p-3 text-xs">
          <div className="text-soleur-text-primary">{humanizeFnId(item.fnId)}</div>
          <div className="mt-1 font-mono text-soleur-text-muted">
            {item.domain} · {item.ownerRole} · {item.scheduleLabel}
          </div>
        </div>
        <p className="mt-3 rounded border border-amber-500/40 bg-amber-500/10 p-3 text-xs text-amber-300">
          This runs REAL production work, off-schedule. The action is logged to
          the audit ledger under your operator identity.
        </p>
        <div className="mt-4 flex justify-end gap-2">
          <button
            onClick={onCancel}
            className="rounded border border-soleur-border-default px-3 py-1.5 text-xs text-soleur-text-secondary hover:bg-soleur-bg-surface-2"
          >
            Cancel
          </button>
          <button
            onClick={onConfirm}
            disabled={busy}
            data-testid="confirm-run"
            className="rounded bg-amber-500 px-3 py-1.5 text-xs font-medium text-black hover:bg-amber-400 disabled:opacity-50"
          >
            {busy ? "Running…" : "▷ Run now"}
          </button>
        </div>
      </div>
    </div>
  );
}

function RecentRunsTab() {
  const [runs, setRuns] = useState<RecentRun[]>([]);
  const [cursor, setCursor] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [loaded, setLoaded] = useState(false);
  const [expanded, setExpanded] = useState<string | null>(null);

  const loadMore = useCallback(
    async (reset: boolean) => {
      setLoading(true);
      try {
        const url = new URL(
          "/api/dashboard/routines/runs",
          window.location.origin,
        );
        if (!reset && cursor) url.searchParams.set("cursor", cursor);
        const res = await fetch(url.toString());
        if (!res.ok) return;
        const json = (await res.json()) as {
          runs: RecentRun[];
          nextCursor: string | null;
        };
        setRuns((prev) => (reset ? json.runs : [...prev, ...json.runs]));
        setCursor(json.nextCursor);
      } finally {
        setLoading(false);
        setLoaded(true);
      }
    },
    [cursor],
  );

  useEffect(() => {
    void loadMore(true);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  if (loaded && runs.length === 0)
    return (
      <div className="rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 p-8 text-center text-sm text-soleur-text-muted">
        No runs yet. Routines will appear here as they execute.
      </div>
    );

  return (
    <div>
      <table className="w-full text-left text-xs">
        <thead className="text-soleur-text-muted">
          <tr className="border-b border-soleur-border-default">
            <th className="py-2 font-normal">Routine</th>
            <th className="py-2 font-normal">Status</th>
            <th className="py-2 font-normal">Started</th>
            <th className="py-2 font-normal">Duration</th>
            <th className="py-2 font-normal">Trigger</th>
          </tr>
        </thead>
        <tbody>
          {runs.map((r) => (
            <RecentRunRow
              key={r.id}
              run={r}
              expanded={expanded === r.id}
              onToggle={() =>
                setExpanded((e) => (e === r.id ? null : r.id))
              }
            />
          ))}
        </tbody>
      </table>
      {cursor && (
        <button
          onClick={() => loadMore(false)}
          disabled={loading}
          className="mt-4 rounded border border-soleur-border-default px-3 py-1.5 text-xs text-soleur-text-secondary hover:bg-soleur-bg-surface-1 disabled:opacity-50"
        >
          {loading ? "Loading…" : "Load more"}
        </button>
      )}
    </div>
  );
}

function RecentRunRow({
  run,
  expanded,
  onToggle,
}: {
  run: RecentRun;
  expanded: boolean;
  onToggle: () => void;
}) {
  const isFailed = run.status === "failed";
  return (
    <>
      <tr
        className={`border-b border-soleur-border-default ${isFailed ? "cursor-pointer" : ""}`}
        onClick={isFailed ? onToggle : undefined}
        data-testid={`run-row-${run.id}`}
      >
        <td className="py-2 text-soleur-text-primary">
          {humanizeFnId(run.routine_id)}
        </td>
        <td className="py-2">
          <StatusPill status={run.status} />
        </td>
        <td className="py-2 font-mono text-soleur-text-muted">
          {relativeTime(run.started_at)}
        </td>
        <td className="py-2 text-soleur-text-muted">
          {formatDuration(run.duration_ms)}
        </td>
        <td className="py-2 text-soleur-text-muted">{run.trigger_source}</td>
      </tr>
      {expanded && isFailed && (
        <tr className="border-b border-soleur-border-default bg-soleur-bg-surface-1">
          <td colSpan={5} className="px-3 py-2 font-mono text-[11px] text-red-300">
            {run.error_summary ?? "(no error detail captured)"}
          </td>
        </tr>
      )}
    </>
  );
}
