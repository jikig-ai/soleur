"use client";

// PR-B (#4379) Phase 5.3 — Today card leader-loop status panel.
//
// Subscribes to the action_sends row keyed by message_id and renders the
// per-AC11 state-matrix UI: status copy, Stop / Undo / Retry / Cost.
//
// Channels:
//   - Supabase Realtime (postgres_changes UPDATE on action_sends filtered
//     by message_id=eq.<id>). RLS-scoped via the tenant client; the row's
//     owner-SELECT policy gates payload delivery.
//   - 2s polling fallback (FR3) when the subscription open fails or the
//     channel state transitions to CLOSED / CHANNEL_ERROR / TIMED_OUT.
//
// Cost badge refresh: pull GET /api/dashboard/today/[id]/cost on every
// Realtime UPDATE (or every poll tick). The badge formats as
// `Cost: $X.XX (N turns)`.
//
// Optimistic UI:
//   - Stop click flips the local view to "Stopping" before the Realtime
//     UPDATE lands (cancellation_requested_at column write).
//   - Undo 207 surfaces the per-element ledger inline; 409 surfaces the
//     "Already undone" copy.
//
// When state === "done" the existing PR-A <AcknowledgedPill> renders (the
// caller threads the artifact URL through).

import { useEffect, useState, useRef, useCallback } from "react";

import { AcknowledgedPill } from "@/components/dashboard/acknowledged-pill";
import { createClient } from "@/lib/supabase/client";
import { reportSilentFallback } from "@/lib/client-observability";
import {
  deriveTodayCardState,
  type TodayCardActionSendInput,
} from "@/components/dashboard/today-card-state-matrix";

const POLL_INTERVAL_MS = 2000;

export interface LeaderLoopStatusProps {
  /** action_sends.message_id (the Today card's row key). */
  messageId: string;
  /**
   * Optional initial artifact URL — surfaced inside the "done" state's
   * AcknowledgedPill. PR-A's /send response returns it eagerly; the
   * Realtime UPDATE on artifact_url eventually overwrites it.
   */
  initialArtifactUrl?: string;
}

interface CostJson {
  cumulativeCents: number;
  turnCount: number;
}

// Shared shape between the /undo route's 207 response and the consumer
// here. Drift between the two surfaces is masked by the route's
// JSON.stringify boundary; cross-typing closes the gap.
export interface UndoElement {
  index: number;
  kind: string;
  status: string;
  error?: string;
}

export interface UndoResponseBody {
  allSucceeded: boolean;
  elements: UndoElement[];
}

type UndoState =
  | { kind: "idle" }
  | { kind: "pending" }
  | { kind: "partial"; elements: UndoElement[] }
  | { kind: "already_undone" }
  | { kind: "error"; message: string };

function formatCostCents(cents: number): string {
  return `$${(cents / 100).toFixed(2)}`;
}

function isTerminalSubscribeStatus(status: string): boolean {
  return (
    status === "CLOSED" ||
    status === "CHANNEL_ERROR" ||
    status === "TIMED_OUT"
  );
}

export function LeaderLoopStatus({
  messageId,
  initialArtifactUrl,
}: LeaderLoopStatusProps) {
  const [row, setRow] = useState<TodayCardActionSendInput | null>(null);
  const [cost, setCost] = useState<CostJson | null>(null);
  const [optimisticStopping, setOptimisticStopping] = useState(false);
  const [undoState, setUndoState] = useState<UndoState>({ kind: "idle" });
  const [cancelError, setCancelError] = useState<string | null>(null);
  const [resumeError, setResumeError] = useState<string | null>(null);
  const pollIntervalRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const fetchRowRef = useRef<() => Promise<void>>(() => Promise.resolve());
  const refreshCostRef = useRef<() => Promise<void>>(() => Promise.resolve());

  const fetchRow = useCallback(async () => {
    try {
      const supabase = createClient();
      const { data } = await supabase
        .from("action_sends")
        .select(
          "failure_reason,reversal_handles,undone_at,acknowledged_at,artifact_url,cancellation_requested_at,current_turn",
        )
        .eq("message_id", messageId)
        .maybeSingle();
      if (data) setRow(data as TodayCardActionSendInput);
    } catch (err) {
      // Polling fallback exists; one missed read is non-fatal. Mirror to
      // Sentry per cq-silent-fallback-must-mirror-to-sentry so a
      // sustained Supabase outage or RLS misconfig becomes visible.
      reportSilentFallback(err, {
        feature: "leader-loop-status",
        op: "fetch-row",
      });
    }
  }, [messageId]);

  const refreshCost = useCallback(async () => {
    try {
      const res = await fetch(`/api/dashboard/today/${messageId}/cost`);
      if (res.ok) {
        const json = (await res.json()) as CostJson;
        setCost(json);
      }
    } catch (err) {
      // Cost refresh is best-effort; server-side enforces the actual
      // ceiling. Mirror to Sentry per cq-silent-fallback-must-mirror-to-
      // sentry so a sustained /cost outage during a real spawn is visible.
      reportSilentFallback(err, {
        feature: "leader-loop-status",
        op: "refresh-cost",
      });
    }
  }, [messageId]);

  fetchRowRef.current = fetchRow;
  refreshCostRef.current = refreshCost;

  useEffect(() => {
    let cancelled = false;

    function startPolling() {
      if (pollIntervalRef.current !== null) return;
      pollIntervalRef.current = setInterval(() => {
        if (cancelled) return;
        fetchRowRef.current();
        refreshCostRef.current();
      }, POLL_INTERVAL_MS);
    }

    function stopPolling() {
      if (pollIntervalRef.current !== null) {
        clearInterval(pollIntervalRef.current);
        pollIntervalRef.current = null;
      }
    }

    fetchRow();
    refreshCost();

    const supabase = createClient();
    const channel = supabase
      .channel(`today-card-${messageId}`)
      .on(
        "postgres_changes",
        {
          event: "UPDATE",
          schema: "public",
          table: "action_sends",
          filter: `message_id=eq.${messageId}`,
        },
        (payload: { new: unknown }) => {
          if (cancelled) return;
          setRow(payload.new as TodayCardActionSendInput);
          refreshCostRef.current();
        },
      )
      .subscribe((status: string) => {
        if (cancelled) return;
        if (status === "SUBSCRIBED") {
          stopPolling();
        } else if (isTerminalSubscribeStatus(status)) {
          startPolling();
        }
      });

    return () => {
      cancelled = true;
      stopPolling();
      supabase.removeChannel(channel);
    };
  }, [messageId, fetchRow, refreshCost]);

  // Auto-clear optimisticStopping when the row reaches a definitive
  // terminal state OR the server has acknowledged the cancellation
  // request. Without this reconciliation, a /cancel POST that returned
  // 200 but for any reason did NOT land the cancellation_requested_at
  // write would leave the card stuck in "Stopping" forever; the row's
  // own state takes over once it's definitive.
  useEffect(() => {
    if (!optimisticStopping) return;
    if (!row) return;
    if (
      row.cancellation_requested_at ||
      row.acknowledged_at ||
      row.failure_reason ||
      row.undone_at
    ) {
      setOptimisticStopping(false);
    }
  }, [row, optimisticStopping]);

  async function onStop() {
    setCancelError(null);
    setOptimisticStopping(true);
    try {
      const res = await fetch(
        `/api/dashboard/today/${messageId}/cancel`,
        { method: "POST" },
      );
      if (!res.ok) {
        setOptimisticStopping(false);
        setCancelError(`Stop failed (${res.status})`);
      }
    } catch {
      setOptimisticStopping(false);
      setCancelError("Stop failed — network error");
    }
  }

  async function onUndo() {
    setUndoState({ kind: "pending" });
    try {
      const res = await fetch(
        `/api/dashboard/today/${messageId}/undo`,
        { method: "POST" },
      );
      if (res.status === 200) {
        setUndoState({ kind: "idle" });
        // Realtime UPDATE on undone_at flips the state matrix to "undone".
        fetchRow();
        return;
      }
      if (res.status === 207) {
        const json = (await res.json()) as UndoResponseBody;
        setUndoState({ kind: "partial", elements: json.elements ?? [] });
        fetchRow();
        return;
      }
      if (res.status === 409) {
        setUndoState({ kind: "already_undone" });
        return;
      }
      setUndoState({
        kind: "error",
        message: `Undo failed (${res.status})`,
      });
    } catch {
      setUndoState({ kind: "error", message: "Undo failed — network error" });
    }
  }

  async function onRetry() {
    try {
      const res = await fetch(
        `/api/dashboard/today/${messageId}/send`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
        },
      );
      if (res.ok) {
        // Server resets the failure_reason / advances turn; the next
        // Realtime UPDATE drives the matrix back to "working".
        fetchRow();
      }
    } catch {
      // Retry errors surface through the next state matrix update; no
      // dedicated inline error slot.
    }
  }

  // feat-l5-runaway-guard PR-A: clear the founder's runtime pause. This is
  // the in-product reach for the operator-resume route (the plan's "reachable
  // from the halt banner/email CTA"). Terminal-halt: clearing the pause lets
  // the founder start a FRESH run; it does not resume this halted spawn.
  async function onResume() {
    setResumeError(null);
    try {
      const res = await fetch("/api/dashboard/runtime/resume", {
        method: "POST",
      });
      if (!res.ok) {
        setResumeError(`Resume failed (${res.status})`);
        return;
      }
      fetchRow();
    } catch {
      setResumeError("Resume failed — network error");
    }
  }

  if (!row) {
    // Pre-fetch first-render — agent just acknowledged at the route,
    // action_sends row not yet readable via the tenant client. Render the
    // pre-turn-1 copy from the state matrix.
    return (
      <div
        data-testid="leader-loop-status"
        data-state-kind="acknowledged_starting"
        className="mt-2 flex flex-col gap-2"
      >
        <p className="text-sm text-soleur-text-secondary">
          Acknowledged — agent starting…
        </p>
      </div>
    );
  }

  // Synthesize cancellation_requested_at so deriveTodayCardState yields
  // "stopping" before the Realtime UPDATE lands. Reusing the matrix's
  // single source of truth avoids a parallel "stopping?" predicate.
  const effectiveRow: TodayCardActionSendInput = optimisticStopping
    ? { ...row, cancellation_requested_at: row.cancellation_requested_at ?? new Date().toISOString() }
    : row;
  const state = deriveTodayCardState(effectiveRow);

  const costLine =
    cost && cost.turnCount > 0
      ? `Cost: ${formatCostCents(cost.cumulativeCents)} (${cost.turnCount} turn${
          cost.turnCount === 1 ? "" : "s"
        })`
      : null;

  const artifactUrlForPill = row.artifact_url ?? initialArtifactUrl ?? "";

  return (
    <div
      data-testid="leader-loop-status"
      data-state-kind={state.kind}
      className="mt-2 flex flex-col gap-2"
    >
      {state.kind === "done" ? (
        <AcknowledgedPill artifactUrl={artifactUrlForPill} degraded={undefined} />
      ) : (
        <p
          data-testid="leader-loop-copy"
          className="text-sm text-soleur-text-primary"
        >
          {state.copy}
        </p>
      )}

      {costLine ? (
        <p
          data-testid="cost-badge"
          className="text-xs text-soleur-text-secondary"
        >
          {costLine}
        </p>
      ) : null}

      {cancelError ? (
        <p className="text-xs text-red-600" role="alert">
          {cancelError}
        </p>
      ) : null}

      {undoState.kind === "already_undone" ? (
        <p
          data-testid="undo-already-undone"
          className="text-xs text-soleur-text-secondary"
        >
          Already undone.
        </p>
      ) : null}

      {undoState.kind === "error" ? (
        <p className="text-xs text-red-600" role="alert">
          {undoState.message}
        </p>
      ) : null}

      {undoState.kind === "partial" ? (
        <ul
          data-testid="undo-partial-ledger"
          className="rounded-md border border-amber-700/40 bg-amber-950/20 p-2 text-xs text-amber-100"
        >
          {undoState.elements.map((el) => (
            <li
              key={el.index}
              data-undo-status={el.status}
              data-undo-kind={el.kind}
            >
              {el.kind} — {el.status}
              {el.error ? `: ${el.error}` : null}
            </li>
          ))}
        </ul>
      ) : null}

      <div className="flex flex-wrap gap-2">
        {state.showStop ? (
          <button
            type="button"
            onClick={onStop}
            disabled={state.stopDisabled || optimisticStopping}
            data-action="leader-stop"
            className="min-h-[44px] rounded-md border border-soleur-border-default bg-soleur-bg-surface-2 px-3 py-2 text-sm font-medium text-soleur-text-primary disabled:cursor-not-allowed disabled:opacity-50"
            aria-label="Stop agent"
          >
            Stop
          </button>
        ) : null}

        {state.showUndo ? (
          <button
            type="button"
            onClick={onUndo}
            disabled={undoState.kind === "pending"}
            data-action="leader-undo"
            className="min-h-[44px] rounded-md border border-soleur-border-default bg-soleur-bg-surface-2 px-3 py-2 text-sm font-medium text-soleur-text-primary disabled:cursor-not-allowed disabled:opacity-50"
            aria-label="Undo agent action"
          >
            Undo
          </button>
        ) : null}

        {state.showRetry ? (
          <button
            type="button"
            onClick={onRetry}
            data-action="leader-retry"
            className="min-h-[44px] rounded-md bg-amber-600 px-3 py-2 text-sm font-medium text-white"
            aria-label="Retry agent"
          >
            Retry
          </button>
        ) : null}

        {state.showResume ? (
          <button
            type="button"
            onClick={onResume}
            data-action="leader-resume"
            className="min-h-[44px] rounded-md bg-amber-600 px-3 py-2 text-sm font-medium text-white"
            aria-label="Resume run — clear pause"
          >
            Resume
          </button>
        ) : null}
      </div>

      {resumeError ? (
        <p className="text-xs text-red-600" role="alert">
          {resumeError}
        </p>
      ) : null}
    </div>
  );
}
