"use client";

// Routines management surface (#5345 PR-1). Two tabs (Routines / Recent Runs)
// + Run-now with a confirm modal for protected routines. Spec-flow states:
// P0-1 (post-trigger ack + optimistic Running + disable-while-in-flight),
// P1-4 (empty state), P1-6 (keyset pagination). PR-2 adds the Concierge tab.
// PR-4 (#5412): Recent Runs filters (routine/status/trigger/range), a shared
// per-run detail panel (replaces the inline failed-row drill-in — one path for
// the tab + the drawer), and a per-routine slide-over drawer (metadata + a log
// scoped to that routine). actor_class renders as human text; actor_id /
// delegating_principal are never surfaced (PR-1 PII posture).

import { useCallback, useEffect, useState } from "react";
import useSWR from "swr";

import { ChatSurface } from "@/components/chat/chat-surface";
import { useIsMobile } from "@/hooks/use-is-mobile";
import { swrKeys } from "@/lib/swr-config";
import {
  ROUTINE_DRAFT_TAB_EVENT,
  type RoutineDraftTabEventDetail,
} from "./routine-draft-tab-event";

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
  description: string;
  domain: string;
  ownerRole: string;
  scheduleLabel: string;
  manualTrigger: "allowed" | "confirm";
  lastRun: RunSummary | null;
}
interface RecentRun extends RunSummary {
  id: string;
  routine_id: string;
  // #5412 — surfaced in the per-run detail panel. NEVER actor_id /
  // delegating_principal (operator-PII UUIDs are omitted server-side);
  // actor_class is a coarse enum (system | human | agent).
  run_id: string | null;
  actor_class: string;
}
// #5766 — an in-flight heavy-cron run (routine_run_progress). status is
// reader-computed (running | stuck); `resumed` is a badge overlay (attempt > 1).
interface LiveRun {
  id: string;
  routine_id: string;
  run_id: string;
  status: "running" | "stuck";
  resumed: boolean;
  started_at: string;
  last_heartbeat_at: string;
}

// ADR-067: shared fetcher for the routines list — RoutinesTab and the Recent
// Runs tab's routine-dropdown options key the SAME swrKeys.routinesList(), so
// switching tabs reuses one cached fetch (free dedup) and the Routines tab
// renders instantly on return.
async function fetchRoutines(): Promise<RoutineItem[]> {
  const res = await fetch("/api/dashboard/routines");
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const json = (await res.json()) as { routines: RoutineItem[] };
  return json.routines;
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

// #5412 — actor_class rendered as human text in the detail panel. Deliberately
// no "(you)" framing (single-operator tenant; the coarse class is the signal).
// Unknown values fall back to the raw class rather than guessing.
const ACTOR_CLASS_LABEL: Record<string, string> = {
  system: "System",
  human: "Operator",
  agent: "Agent",
};
function actorClassLabel(actorClass: string): string {
  return ACTOR_CLASS_LABEL[actorClass] ?? actorClass;
}

// #5412 — Recent Runs date-range presets → a `since` ISO bound (null = all time).
const RANGE_PRESETS: ReadonlyArray<{ key: string; label: string; ms: number | null }> = [
  { key: "all", label: "All time", ms: null },
  { key: "24h", label: "24h", ms: 24 * 3600_000 },
  { key: "7d", label: "7d", ms: 7 * 24 * 3600_000 },
  { key: "30d", label: "30d", ms: 30 * 24 * 3600_000 },
];

const STATUS_COLOR: Record<string, string> = {
  completed: "text-green-400",
  failed: "text-red-400",
  running: "text-blue-400",
  // #5766 — stuck (evicted, stale heartbeat) is deliberately DISTINCT from
  // running (amber vs blue) so a dead run never reads as healthy. `never` is
  // listed explicitly (self-documenting) though its value equals the muted
  // fallback below — a marker that "Never" is an intended status, not unknown.
  stuck: "text-amber-400",
  never: "text-soleur-text-muted",
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
  const [tab, setTab] = useState<"routines" | "runs" | "draft">("routines");

  // The guided tour switches to the "Draft a routine" tab to spotlight the
  // creation composer, then switches back on leave. Driven by a window event
  // (same decoupled pattern as the rail expand / New Issue dialog) — inert when
  // no tour is running.
  useEffect(() => {
    function onTourToggle(e: Event) {
      const detail = (e as CustomEvent<RoutineDraftTabEventDetail>).detail;
      setTab(detail?.open ? "draft" : "routines");
    }
    window.addEventListener(ROUTINE_DRAFT_TAB_EVENT, onTourToggle);
    return () =>
      window.removeEventListener(ROUTINE_DRAFT_TAB_EVENT, onTourToggle);
  }, []);

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
        <button
          role="tab"
          aria-selected={tab === "draft"}
          onClick={() => setTab("draft")}
          data-tour-id="action:draft-routine"
          className={`-mb-px ml-auto self-center border-b-2 pb-2 text-sm ${
            tab === "draft"
              ? "border-soleur-text-primary text-soleur-text-primary"
              : "border-transparent text-soleur-text-secondary hover:text-soleur-text-primary"
          }`}
        >
          Draft a routine with Concierge
        </button>
      </div>
      {tab === "routines" ? (
        <RoutinesTab />
      ) : tab === "runs" ? (
        <RecentRunsTab />
      ) : (
        <DraftRoutineTab />
      )}
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

// PR-2 (#5402): the "Draft a routine" Concierge tab. Routines are code-defined
// (no runtime CRUD), so the Concierge drafts NEW routines as GitHub PRs and
// runs/verifies EXISTING ones via the gated routine_run loop. Reuses the full
// chat stack via ChatSurface (sidebar variant — h-full, no header) scoped to
// routine-authoring mode via initialContext.type. Wireframe: screen 05-08.
const DRAFT_SUGGESTIONS = [
  "Draft a weekly competitor-price check",
  "Run & verify cron-legal-audit",
  "Explain cron-content-publisher",
];

function DraftRoutineTab() {
  return (
    <div className="flex h-full min-h-0 flex-col">
      <div className="mb-4">
        <h2 className="text-sm font-medium text-soleur-text-primary">
          Draft a routine with the Concierge
        </h2>
        <p className="mt-1 text-xs text-soleur-text-secondary">
          Describe the recurring work you want. The Concierge drafts it, tests
          it, and shows you the result — then opens a PR you approve. It can also
          run and verify routines you already have.
        </p>
        <div className="mt-3 grid gap-3 sm:grid-cols-2">
          <div className="rounded border border-soleur-border-default bg-soleur-bg-surface-1 p-3">
            <div className="text-xs font-medium text-soleur-text-primary">
              Draft a new routine
            </div>
            <div className="mt-1 text-xs text-soleur-text-secondary">
              Scaffolds a cron function and opens a GitHub PR for review. It
              can&apos;t run until the PR is merged and deployed.
            </div>
          </div>
          <div className="rounded border border-soleur-border-default bg-soleur-bg-surface-1 p-3">
            <div className="text-xs font-medium text-soleur-text-primary">
              Run &amp; verify an existing routine
            </div>
            <div className="mt-1 text-xs text-soleur-text-secondary">
              Runs a routine off-schedule behind a confirmation gate, then reads
              back the run log and confirms it worked.
            </div>
          </div>
        </div>
        <div className="mt-3 flex flex-wrap gap-2">
          {DRAFT_SUGGESTIONS.map((s) => (
            <span
              key={s}
              className="rounded border border-soleur-border-default px-2 py-1 text-[11px] text-soleur-text-secondary"
            >
              {s}
            </span>
          ))}
        </div>
        <p className="mt-2 text-[11px] text-soleur-text-muted">
          New routines ship as code — the Concierge drafts and tests; you approve
          the PR; it goes live on merge + deploy.
        </p>
      </div>
      <div className="min-h-0 flex-1" data-tour-id="action:draft-routine-composer">
        <ChatSurface
          variant="sidebar"
          conversationId="new"
          initialContext={{ type: "routine-authoring" }}
        />
      </div>
    </div>
  );
}

function RoutinesTab() {
  const [busy, setBusy] = useState<Record<string, boolean>>({});
  const [confirming, setConfirming] = useState<RoutineItem | null>(null);
  const [detail, setDetail] = useState<RoutineItem | null>(null);

  // ADR-067: cached so returning to the Routines tab renders instantly; the
  // loading gate is `data === undefined` (GAP F), so background revalidation
  // never re-shows the "Loading…" line.
  const {
    data: routines,
    error: loadError,
    mutate,
  } = useSWR(swrKeys.routinesList(), fetchRoutines);
  const error = loadError
    ? loadError instanceof Error
      ? loadError.message
      : "load failed"
    : null;

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
        // 202 (or any non-409): optimistic "Running" written into the cache
        // (no revalidate), then reconcile against DB truth. The optimistic row
        // has no terminal state of its own — the cron writes its routine_runs
        // row when it finishes — so without the reconcile it would read
        // "running" forever until a page reload.
        void mutate(
          (rs) =>
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
          { revalidate: false },
        );
        setConfirming(null);
        // One delayed reconciliation revalidation (not a polling loop — a single
        // bounded refetch) to replace the optimistic "running" with the real
        // terminal row once the run has had a moment to complete.
        setTimeout(() => {
          void mutate();
        }, RECONCILE_DELAY_MS);
      } finally {
        setBusy((b) => ({ ...b, [item.fnId]: false }));
      }
    },
    [mutate],
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
                onOpen={() => setDetail(item)}
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

      {detail && (
        <RoutineDetailDrawer item={detail} onClose={() => setDetail(null)} />
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
  onOpen,
}: {
  item: RoutineItem;
  busy: boolean;
  onRunNow: () => void;
  onOpen: () => void;
}) {
  const last = item.lastRun;
  return (
    <li className="flex items-center gap-4 px-4 py-3">
      <div className="min-w-0 flex-1">
        <button
          type="button"
          onClick={onOpen}
          data-testid={`routine-open-${item.fnId}`}
          className="truncate text-left text-sm text-soleur-text-primary hover:underline"
        >
          {humanizeFnId(item.fnId)}
        </button>
        <p className="mt-0.5 truncate text-xs text-soleur-text-secondary" title={item.description}>
          {item.description}
        </p>
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

interface RunFilters {
  routineId: string;
  status: string;
  triggerSource: string;
  range: string;
}
const EMPTY_FILTERS: RunFilters = {
  routineId: "",
  status: "",
  triggerSource: "",
  range: "all",
};
// Mirrors the route's accepted domains. "running" is deliberately ABSENT —
// it is a client-only optimistic state, never a persisted routine_runs status.
const STATUS_FILTERS: ReadonlyArray<{ value: string; label: string }> = [
  { value: "", label: "All" },
  { value: "completed", label: "Completed" },
  { value: "failed", label: "Failed" },
];
const TRIGGER_FILTERS: ReadonlyArray<{ value: string; label: string }> = [
  { value: "", label: "All triggers" },
  { value: "scheduled", label: "Scheduled" },
  { value: "manual", label: "Manual" },
  { value: "agent", label: "Agent" },
];

// The Recent Runs tab: full filter bar + the shared run-log view.
function RecentRunsTab() {
  // ADR-067: dropdown options share swrKeys.routinesList() with RoutinesTab, so
  // the routines fetch is reused across both tabs (dropdown options are
  // best-effort — the log still loads without them). The run LOG itself stays
  // on its own keyset-paginated fetch (see RunLogView scope-cut note).
  const { data: routineOptions = [] } = useSWR(
    swrKeys.routinesList(),
    fetchRoutines,
  );
  return <RunLogView showFilters routineOptions={routineOptions} />;
}

// Shared run-log: the Recent Runs tab (showFilters) and the per-routine drawer
// (fixedRoutineId, no filters) both render this — ONE table + ONE detail-panel
// path. Filters map to the route's validated query params; `since` is derived
// from the range preset client-side.
//
// ADR-067 scope-cut (plan Phase 5, permitted): this keeps its own cursor-keyset
// pagination (accumulate-pages-across-"Load more") rather than migrating to
// useSWRInfinite. Recent Runs is a secondary sub-tab, not a top-level nav view,
// and useSWRInfinite would have to re-encode the reset-on-filter-change +
// per-filter cursor reset for low cache benefit. The instant-tab-content win is
// delivered by the Routines list (RoutinesTab, on SWR). Migrating Recent Runs to
// useSWRInfinite is tracked in the conversations/TR3 follow-up's sibling note.
function RunLogView({
  showFilters,
  routineOptions,
  fixedRoutineId,
}: {
  showFilters: boolean;
  routineOptions?: RoutineItem[];
  fixedRoutineId?: string;
}) {
  const [filters, setFilters] = useState<RunFilters>(EMPTY_FILTERS);
  const [runs, setRuns] = useState<RecentRun[]>([]);
  // #5766 — in-flight live rows (first page only; not paginated).
  const [live, setLive] = useState<LiveRun[]>([]);
  const [cursor, setCursor] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [loaded, setLoaded] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [selected, setSelected] = useState<RecentRun | null>(null);
  // Phase 3 (mobile): below `md` the runs table collapses to one card per run.
  // Hydration-safe gate (seeds desktop on SSR + first client render, then flips)
  // — see hooks/use-is-mobile.ts. Only the <table>/<card-list> swaps; the
  // filter/error/empty/"Load more" states stay shared above/below the gate.
  const isMobile = useIsMobile();

  const buildUrl = useCallback(
    (c: string | null) => {
      const url = new URL(
        "/api/dashboard/routines/runs",
        window.location.origin,
      );
      const routineId = fixedRoutineId ?? filters.routineId;
      if (routineId) url.searchParams.set("routineId", routineId);
      // Status/trigger/range filters only exist on the unscoped tab view.
      if (!fixedRoutineId) {
        if (filters.status) url.searchParams.set("status", filters.status);
        if (filters.triggerSource)
          url.searchParams.set("triggerSource", filters.triggerSource);
        const preset = RANGE_PRESETS.find((p) => p.key === filters.range);
        if (preset?.ms != null)
          url.searchParams.set(
            "since",
            new Date(Date.now() - preset.ms).toISOString(),
          );
      }
      if (c) url.searchParams.set("cursor", c);
      return url.toString();
    },
    [fixedRoutineId, filters],
  );

  const loadMore = useCallback(
    async (reset: boolean) => {
      setLoading(true);
      try {
        const res = await fetch(buildUrl(reset ? null : cursor));
        if (!res.ok) {
          // Surface the failure instead of leaving an empty table that reads
          // as "no runs" — the route mirrors the real error to Sentry; the
          // operator sees a distinct error state here.
          setError(`Failed to load runs (HTTP ${res.status})`);
          return;
        }
        const json = (await res.json()) as {
          runs: RecentRun[];
          nextCursor: string | null;
          live?: LiveRun[];
        };
        setError(null);
        setRuns((prev) => (reset ? json.runs : [...prev, ...json.runs]));
        // Live rows exist only on the first page (reset); pagination keeps them.
        if (reset) setLive(json.live ?? []);
        setCursor(json.nextCursor);
      } catch {
        setError("Failed to load runs");
      } finally {
        setLoading(false);
        setLoaded(true);
      }
    },
    [buildUrl, cursor],
  );

  // Reset + refetch whenever the filters (or the fixed routine) change.
  useEffect(() => {
    void loadMore(true);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [filters, fixedRoutineId]);

  const hasActiveFilters =
    filters.routineId !== "" ||
    filters.status !== "" ||
    filters.triggerSource !== "" ||
    filters.range !== "all";

  return (
    <div>
      {showFilters && (
        <RunsFilterBar
          filters={filters}
          routineOptions={routineOptions ?? []}
          onChange={setFilters}
          onClear={() => setFilters(EMPTY_FILTERS)}
          hasActiveFilters={hasActiveFilters}
        />
      )}

      {error ? (
        <div className="rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 p-5 text-sm text-red-400">
          {error}{" "}
          <button
            type="button"
            onClick={() => loadMore(true)}
            className="ml-1 underline hover:text-red-300"
          >
            Retry
          </button>
        </div>
      ) : loaded && runs.length === 0 && live.length === 0 ? (
        <div className="rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 p-8 text-center text-sm text-soleur-text-muted">
          {hasActiveFilters
            ? "No runs match these filters."
            : "No runs yet. Routines will appear here as they execute."}
        </div>
      ) : (
        <>
          {isMobile ? (
            // Below md: same rows, same ordering (live first, then terminal
            // history), rendered as record cards from the SAME computed values.
            <div className="space-y-2">
              {live.map((l) => (
                <LiveRunRow
                  key={l.id}
                  live={l}
                  showRoutine={!fixedRoutineId}
                  variant="card"
                />
              ))}
              {runs.map((r) => (
                <RecentRunRow
                  key={r.id}
                  run={r}
                  showRoutine={!fixedRoutineId}
                  onSelect={() => setSelected(r)}
                  variant="card"
                />
              ))}
            </div>
          ) : (
            <table className="w-full text-left text-xs">
              <thead className="text-soleur-text-muted">
                <tr className="border-b border-soleur-border-default">
                  {!fixedRoutineId && (
                    <th className="py-2 font-normal">Routine</th>
                  )}
                  <th className="py-2 font-normal">Status</th>
                  <th className="py-2 font-normal">Started</th>
                  <th className="py-2 font-normal">Duration</th>
                  <th className="py-2 font-normal">Trigger</th>
                </tr>
              </thead>
              <tbody>
                {/* #5766 — in-flight live rows sit at the top (newest); terminal
                    history follows. */}
                {live.map((l) => (
                  <LiveRunRow
                    key={l.id}
                    live={l}
                    showRoutine={!fixedRoutineId}
                  />
                ))}
                {runs.map((r) => (
                  <RecentRunRow
                    key={r.id}
                    run={r}
                    showRoutine={!fixedRoutineId}
                    onSelect={() => setSelected(r)}
                  />
                ))}
              </tbody>
            </table>
          )}
          {cursor && (
            <button
              onClick={() => loadMore(false)}
              disabled={loading}
              className="mt-4 rounded border border-soleur-border-default px-3 py-1.5 text-xs text-soleur-text-secondary hover:bg-soleur-bg-surface-1 disabled:opacity-50"
            >
              {loading ? "Loading…" : "Load more"}
            </button>
          )}
        </>
      )}

      {selected && (
        <RunDetailPanel run={selected} onClose={() => setSelected(null)} />
      )}
    </div>
  );
}

function RunsFilterBar({
  filters,
  routineOptions,
  onChange,
  onClear,
  hasActiveFilters,
}: {
  filters: RunFilters;
  routineOptions: RoutineItem[];
  onChange: (next: RunFilters) => void;
  onClear: () => void;
  hasActiveFilters: boolean;
}) {
  const selectCls =
    "rounded border border-soleur-border-default bg-soleur-bg-surface-1 px-2 py-1 text-xs text-soleur-text-primary";
  return (
    <div className="mb-4 flex flex-wrap items-center gap-2">
      <select
        aria-label="Filter by routine"
        data-testid="runs-filter-routine"
        value={filters.routineId}
        onChange={(e) => onChange({ ...filters, routineId: e.target.value })}
        className={selectCls}
      >
        <option value="">All routines</option>
        {routineOptions.map((r) => (
          <option key={r.fnId} value={r.fnId}>
            {humanizeFnId(r.fnId)}
          </option>
        ))}
      </select>

      <div className="inline-flex overflow-hidden rounded border border-soleur-border-default">
        {STATUS_FILTERS.map((s) => (
          <button
            key={s.value || "all"}
            type="button"
            data-testid={`runs-filter-status-${s.value || "all"}`}
            onClick={() => onChange({ ...filters, status: s.value })}
            className={`px-2 py-1 text-xs ${
              filters.status === s.value
                ? "bg-soleur-bg-surface-2 text-soleur-text-primary"
                : "text-soleur-text-secondary hover:bg-soleur-bg-surface-1"
            }`}
          >
            {s.label}
          </button>
        ))}
      </div>

      <select
        aria-label="Filter by trigger source"
        data-testid="runs-filter-trigger"
        value={filters.triggerSource}
        onChange={(e) =>
          onChange({ ...filters, triggerSource: e.target.value })
        }
        className={selectCls}
      >
        {TRIGGER_FILTERS.map((t) => (
          <option key={t.value || "all"} value={t.value}>
            {t.label}
          </option>
        ))}
      </select>

      <div className="inline-flex overflow-hidden rounded border border-soleur-border-default">
        {RANGE_PRESETS.map((p) => (
          <button
            key={p.key}
            type="button"
            data-testid={`runs-filter-range-${p.key}`}
            onClick={() => onChange({ ...filters, range: p.key })}
            className={`px-2 py-1 text-xs ${
              filters.range === p.key
                ? "bg-soleur-bg-surface-2 text-soleur-text-primary"
                : "text-soleur-text-secondary hover:bg-soleur-bg-surface-1"
            }`}
          >
            {p.label}
          </button>
        ))}
      </div>

      {hasActiveFilters && (
        <button
          type="button"
          onClick={onClear}
          data-testid="runs-filter-clear"
          className="text-xs text-soleur-text-secondary underline hover:text-soleur-text-primary"
        >
          Clear
        </button>
      )}
    </div>
  );
}

function RecentRunRow({
  run,
  showRoutine,
  onSelect,
  variant = "row",
}: {
  run: RecentRun;
  showRoutine: boolean;
  onSelect: () => void;
  variant?: "row" | "card";
}) {
  // Single source of truth: the same computed values feed the desktop <tr>
  // cells and the mobile record card below.
  const started = relativeTime(run.started_at);
  const duration = formatDuration(run.duration_ms);

  if (variant === "card") {
    return (
      <div
        role="button"
        tabIndex={0}
        onClick={onSelect}
        onKeyDown={(e) => {
          if (e.key === "Enter" || e.key === " ") {
            e.preventDefault();
            onSelect();
          }
        }}
        data-testid={`run-row-${run.id}`}
        className="min-h-11 cursor-pointer rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 p-3"
      >
        <div className="flex items-center justify-between gap-2">
          {showRoutine && (
            <span className="min-w-0 truncate font-medium text-soleur-text-primary">
              {humanizeFnId(run.routine_id)}
            </span>
          )}
          <span className="ml-auto shrink-0">
            <StatusPill status={run.status} />
          </span>
        </div>
        <div className="mt-2 space-y-1">
          <CardStat label="Started" value={started} />
          <CardStat label="Duration" value={duration} />
          <CardStat label="Trigger" value={run.trigger_source} />
        </div>
      </div>
    );
  }

  return (
    <tr
      className="cursor-pointer border-b border-soleur-border-default hover:bg-soleur-bg-surface-1"
      onClick={onSelect}
      data-testid={`run-row-${run.id}`}
    >
      {showRoutine && (
        <td className="py-2 text-soleur-text-primary">
          {humanizeFnId(run.routine_id)}
        </td>
      )}
      <td className="py-2">
        <StatusPill status={run.status} />
      </td>
      <td className="py-2 font-mono text-soleur-text-muted">{started}</td>
      <td className="py-2 text-soleur-text-muted">{duration}</td>
      <td className="py-2 text-soleur-text-muted">{run.trigger_source}</td>
    </tr>
  );
}

// Phase 3 (mobile): a label:value stat row inside a record card. Shared by the
// LiveRunRow and RecentRunRow card variants so the collapsed columns read
// identically.
function CardStat({
  label,
  value,
}: {
  label: string;
  value: React.ReactNode;
}) {
  return (
    <div className="flex items-center justify-between gap-3 text-xs">
      <span className="text-soleur-text-muted">{label}</span>
      <span className="text-right text-soleur-text-secondary">{value}</span>
    </div>
  );
}

// #5766 — an in-flight (live) run row. Rendered above the terminal history in
// Recent Runs. `resumed` shows as a badge OVERLAY (not a mutually-exclusive
// status): a resumed run is still running/stuck. The heartbeat freshness (from
// last_heartbeat_at) is what distinguishes a healthy long run from a stuck one.
function LiveRunRow({
  live,
  showRoutine,
  variant = "row",
}: {
  live: LiveRun;
  showRoutine: boolean;
  variant?: "row" | "card";
}) {
  const heartbeat = relativeTime(live.last_heartbeat_at);
  // Single source of truth: shared by the desktop <tr> and the mobile card.
  const started = relativeTime(live.started_at);
  const durationText =
    live.status === "stuck"
      ? `no heartbeat · ${heartbeat}`
      : `running · updated ${heartbeat}`;
  const statusBadge = (
    <span className="inline-flex items-center gap-2">
      <StatusPill status={live.status} />
      {live.resumed && (
        <span
          data-testid={`resumed-badge-${live.id}`}
          className="inline-flex items-center rounded-full border border-amber-400/40 px-1.5 text-[10px] uppercase tracking-wide text-amber-300"
          title="Resumed after an interruption — completed steps were not re-run"
        >
          Resumed
        </span>
      )}
    </span>
  );

  if (variant === "card") {
    return (
      <div
        data-testid={`live-run-row-${live.id}`}
        data-status={live.status}
        className="rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 p-3"
      >
        <div className="flex items-center justify-between gap-2">
          {showRoutine && (
            <span className="min-w-0 truncate font-medium text-soleur-text-primary">
              {humanizeFnId(live.routine_id)}
            </span>
          )}
          <span className="ml-auto shrink-0">{statusBadge}</span>
        </div>
        <div className="mt-2 space-y-1">
          <CardStat label="Started" value={started} />
          <CardStat label="Duration" value={durationText} />
          <CardStat label="Trigger" value="—" />
        </div>
      </div>
    );
  }

  return (
    <tr
      className="border-b border-soleur-border-default"
      data-testid={`live-run-row-${live.id}`}
      data-status={live.status}
    >
      {showRoutine && (
        <td className="py-2 text-soleur-text-primary">
          {humanizeFnId(live.routine_id)}
        </td>
      )}
      <td className="py-2">{statusBadge}</td>
      <td className="py-2 font-mono text-soleur-text-muted">{started}</td>
      <td className="py-2 text-soleur-text-muted">{durationText}</td>
      <td className="py-2 text-soleur-text-muted">—</td>
    </tr>
  );
}

// Shared per-run detail panel (slide-over). The single drill-in path for both
// the tab and the per-routine drawer — replaces the old inline failed-row
// expansion. Surfaces run_id + actor_class (human text), NEVER actor_id /
// delegating_principal (those operator-PII UUIDs are omitted server-side).
function RunDetailPanel({
  run,
  onClose,
}: {
  run: RecentRun;
  onClose: () => void;
}) {
  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-label="Run detail"
      data-testid="run-detail-panel"
      className="fixed inset-0 z-50 flex justify-end bg-black/50"
      onClick={onClose}
    >
      <div
        className="h-full w-full max-w-md overflow-y-auto border-l border-soleur-border-default bg-soleur-bg-surface-1 p-5"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-start justify-between">
          <div>
            <div className="text-sm font-medium text-soleur-text-primary">
              {humanizeFnId(run.routine_id)}
            </div>
            <StatusPill status={run.status} />
          </div>
          <button
            type="button"
            onClick={onClose}
            aria-label="Close"
            className="text-soleur-text-muted hover:text-soleur-text-primary"
          >
            ✕
          </button>
        </div>

        <dl className="mt-4 space-y-2 text-xs">
          <DetailRow label="Run ID">
            <span className="font-mono">{run.run_id ?? "—"}</span>
          </DetailRow>
          <DetailRow label="Trigger">{run.trigger_source}</DetailRow>
          <DetailRow label="Actor">{actorClassLabel(run.actor_class)}</DetailRow>
          <DetailRow label="Started">
            <span className="font-mono">{run.started_at}</span>
          </DetailRow>
          <DetailRow label="Ended">
            <span className="font-mono">{run.ended_at ?? "—"}</span>
          </DetailRow>
          <DetailRow label="Duration">
            {formatDuration(run.duration_ms)}
          </DetailRow>
        </dl>

        {run.status === "failed" && (
          <div className="mt-4">
            <div className="mb-1 text-xs font-medium text-soleur-text-primary">
              Error
            </div>
            <pre className="overflow-x-auto whitespace-pre-wrap rounded border border-red-500/40 bg-red-500/10 p-3 font-mono text-[11px] text-red-300">
              {run.error_summary ?? "(no error detail captured)"}
            </pre>
          </div>
        )}
      </div>
    </div>
  );
}

function DetailRow({
  label,
  children,
}: {
  label: string;
  children: React.ReactNode;
}) {
  return (
    <div className="flex justify-between gap-4">
      <dt className="text-soleur-text-muted">{label}</dt>
      <dd className="text-right text-soleur-text-primary">{children}</dd>
    </div>
  );
}

// Per-routine slide-over: metadata header + a run log scoped to this routine
// (reuses RunLogView with a fixed routineId; no filter bar). No route change.
function RoutineDetailDrawer({
  item,
  onClose,
}: {
  item: RoutineItem;
  onClose: () => void;
}) {
  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-label="Routine detail"
      data-testid="routine-detail-drawer"
      className="fixed inset-0 z-40 flex justify-end bg-black/50"
      onClick={onClose}
    >
      <div
        className="h-full w-full max-w-lg overflow-y-auto border-l border-soleur-border-default bg-soleur-bg-surface-1 p-5"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-start justify-between">
          <div className="text-sm font-medium text-soleur-text-primary">
            {humanizeFnId(item.fnId)}
          </div>
          <button
            type="button"
            onClick={onClose}
            aria-label="Close"
            className="text-soleur-text-muted hover:text-soleur-text-primary"
          >
            ✕
          </button>
        </div>

        <p className="mt-2 text-xs leading-relaxed text-soleur-text-secondary">
          {item.description}
        </p>

        <dl className="mt-3 space-y-2 text-xs">
          <DetailRow label="Domain">{item.domain}</DetailRow>
          <DetailRow label="Owner">{item.ownerRole}</DetailRow>
          <DetailRow label="Schedule">
            <span className="font-mono">{item.scheduleLabel}</span>
          </DetailRow>
          <DetailRow label="Manual trigger">
            {item.manualTrigger === "confirm" ? (
              <span className="text-amber-400">⚠ protected</span>
            ) : (
              "allowed"
            )}
          </DetailRow>
          <DetailRow label="Last run">
            {item.lastRun ? (
              <span>
                {item.lastRun.status} · {relativeTime(item.lastRun.started_at)}
              </span>
            ) : (
              "Never"
            )}
          </DetailRow>
        </dl>

        <div className="mt-5">
          <div className="mb-2 text-xs font-semibold uppercase tracking-wide text-soleur-text-muted">
            Run log
          </div>
          <RunLogView showFilters={false} fixedRoutineId={item.fnId} />
        </div>
      </div>
    </div>
  );
}
