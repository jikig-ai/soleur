"use client";

// PR-G (#3947) — Three-radio tier picker with pessimistic UI + second-click
// acknowledgement on `auto` tier (money-class load-bearing primitive per
// CPO advisory; single-user-incident threshold makes the friction required,
// not optional).
//
// Pessimistic UI: radio state mirrors the server-confirmed value; user
// selections do not commit until the POST returns. On failure, radio reverts
// to last known good state.

import { useState, useTransition } from "react";
import {
  TRUST_TIER_COPY,
  type TrustTier,
} from "@/lib/messages/trust-tier-copy";
import type {
  ActionClass,
  ActionClassTier,
} from "@/server/scope-grants/action-class-map";

interface Props {
  actionClass: ActionClass;
  currentTier: ActionClassTier | null;
  grantedAt: string | null;
}

const TIER_ORDER: TrustTier[] = [
  "approve_every_time",
  "draft_one_click",
  "auto",
];

export function ScopeGrantRow({
  actionClass,
  currentTier,
  grantedAt,
}: Props) {
  // `selectedTier` is the radio's UI state (may be ahead of server).
  // `committedTier` is the last confirmed server state.
  const [selectedTier, setSelectedTier] = useState<TrustTier | null>(
    currentTier,
  );
  const [committedTier, setCommittedTier] = useState<TrustTier | null>(
    currentTier,
  );
  const [acked, setAcked] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [isPending, startTransition] = useTransition();

  const isDirty = selectedTier !== committedTier;
  const isAutoSelected = selectedTier === "auto";
  // Disabled-submit invariant: any tier change requires submit; auto-tier
  // additionally requires the acknowledgement checkbox.
  const canSubmit =
    !isPending &&
    isDirty &&
    selectedTier !== null &&
    (!isAutoSelected || acked);

  function onSelect(t: TrustTier) {
    setSelectedTier(t);
    setError(null);
    if (t !== "auto") setAcked(false);
  }

  function onGrant() {
    if (!selectedTier) return;
    startTransition(async () => {
      try {
        const res = await fetch("/api/scope-grants/grant", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            action_class: actionClass,
            tier: selectedTier,
          }),
        });
        if (!res.ok) {
          setError(`Failed to save (${res.status})`);
          // Pessimistic revert.
          setSelectedTier(committedTier);
          setAcked(false);
          return;
        }
        setCommittedTier(selectedTier);
        setAcked(false);
      } catch (e) {
        setError(e instanceof Error ? e.message : "Network error");
        setSelectedTier(committedTier);
        setAcked(false);
      }
    });
  }

  function onRevoke() {
    startTransition(async () => {
      try {
        const res = await fetch("/api/scope-grants/revoke", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            action_class: actionClass,
            reason: "user_revoke",
          }),
        });
        if (!res.ok) {
          setError(`Failed to revoke (${res.status})`);
          return;
        }
        setCommittedTier(null);
        setSelectedTier(null);
        setAcked(false);
      } catch (e) {
        setError(e instanceof Error ? e.message : "Network error");
      }
    });
  }

  return (
    <div className="rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 p-5">
      <header className="mb-4 flex items-center justify-between">
        <div>
          <h2 className="font-medium text-soleur-text-primary">
            {actionClass}
          </h2>
          {committedTier && grantedAt ? (
            <p className="mt-1 text-xs text-soleur-text-muted">
              Active at {TRUST_TIER_COPY[committedTier].label} since{" "}
              {new Date(grantedAt).toLocaleDateString()}
            </p>
          ) : (
            <p className="mt-1 text-xs text-soleur-text-muted">
              Not authorized — Soleur will not act on this class.
            </p>
          )}
        </div>
        {committedTier ? (
          <button
            type="button"
            onClick={onRevoke}
            disabled={isPending}
            className="rounded-md px-3 py-1.5 text-xs text-soleur-text-danger hover:bg-soleur-bg-surface-2 disabled:opacity-50"
          >
            Revoke
          </button>
        ) : null}
      </header>

      <fieldset
        className="space-y-2"
        disabled={isPending}
        aria-describedby={`${actionClass}-error`}
      >
        <legend className="sr-only">Trust tier for {actionClass}</legend>
        {TIER_ORDER.map((t) => {
          const copy = TRUST_TIER_COPY[t];
          const checked = selectedTier === t;
          return (
            <label
              key={t}
              className={`flex cursor-pointer items-start gap-3 rounded-md border p-3 ${
                checked
                  ? "border-soleur-gold bg-soleur-bg-surface-2"
                  : "border-soleur-border-default hover:bg-soleur-bg-surface-2/50"
              }`}
            >
              <input
                type="radio"
                name={`tier-${actionClass}`}
                value={t}
                checked={checked}
                onChange={() => onSelect(t)}
                className="mt-1"
              />
              <span className="flex-1">
                <span className="flex items-center gap-2">
                  <span className="font-medium text-soleur-text-primary">
                    {copy.label}
                  </span>
                  <span
                    className={`rounded px-1.5 py-0.5 text-xs ${
                      t === "auto"
                        ? "bg-red-900/40 text-red-200"
                        : t === "approve_every_time"
                          ? "bg-green-900/40 text-green-200"
                          : "bg-soleur-bg-surface-2 text-soleur-text-secondary"
                    }`}
                  >
                    {copy.badge}
                  </span>
                </span>
                <span className="mt-1 block text-sm text-soleur-text-secondary">
                  {copy.description}
                </span>
              </span>
            </label>
          );
        })}
      </fieldset>

      {isAutoSelected && isDirty ? (
        <div className="mt-4 rounded-md border border-red-900/50 bg-red-950/30 p-3">
          <label className="flex items-start gap-2 text-sm text-soleur-text-primary">
            <input
              type="checkbox"
              checked={acked}
              onChange={(e) => setAcked(e.target.checked)}
              className="mt-1"
            />
            <span>{TRUST_TIER_COPY.auto.confirmText}</span>
          </label>
        </div>
      ) : null}

      {error ? (
        <p
          id={`${actionClass}-error`}
          role="alert"
          className="mt-3 text-sm text-soleur-text-danger"
        >
          {error}
        </p>
      ) : null}

      <footer className="mt-4 flex items-center justify-between">
        <p className="text-xs text-soleur-text-muted">
          Cost disclosure: Soleur runs use your BYOK Anthropic key. You set the
          spending cap.
        </p>
        <button
          type="button"
          onClick={onGrant}
          disabled={!canSubmit}
          className="rounded-md bg-soleur-gold px-4 py-2 text-sm font-medium text-soleur-bg-page hover:opacity-90 disabled:opacity-40"
        >
          {isPending ? "Saving…" : committedTier ? "Update" : "Authorize"}
        </button>
      </footer>
    </div>
  );
}
