"use client";

// PR-G (#3947) — Three-radio tier picker with pessimistic UI + second-click
// acknowledgement on `auto` tier (money-class load-bearing primitive per
// CPO advisory; single-user-incident threshold makes the friction required,
// not optional).
//
// Pessimistic UI: radio state mirrors the server-confirmed value; user
// selections do not commit until the POST returns. On failure, radio reverts
// to last known good state.

import { useState } from "react";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";
import { usePendingAction } from "@/hooks/use-pending-action";
import {
  TRUST_TIER_COPY,
  type TrustTier,
} from "@/lib/messages/trust-tier-copy";
import { ACTION_CLASS_COPY } from "@/lib/messages/action-class-copy";
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
  const router = useRouter();

  // One shared flag for grant/revoke — a pending write disables the whole
  // row (fieldset + both buttons), same as the hand-rolled useTransition.
  // Per-row granularity is preserved: each row instance owns its hook.
  // asyncFn never throws — failures land on the local `error` surface.
  const { run, pending: isPending } = usePendingAction(
    async (op: "grant" | "revoke") => {
      if (op === "grant") {
        if (!selectedTier) return;
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
          router.refresh();
        } catch (e) {
          setError(e instanceof Error ? e.message : "Network error");
          setSelectedTier(committedTier);
          setAcked(false);
        }
        return;
      }
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
        router.refresh();
      } catch (e) {
        setError(e instanceof Error ? e.message : "Network error");
      }
    },
  );

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

  const onGrant = () => run("grant");
  const onRevoke = () => run("revoke");

  const copy = ACTION_CLASS_COPY[actionClass];

  return (
    <div className="rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 p-5">
      <header className="mb-4 flex items-start justify-between gap-4">
        <div className="min-w-0 flex-1">
          <h3 className="font-medium text-soleur-text-primary">{copy.title}</h3>
          <p className="mt-1 text-sm text-soleur-text-secondary">
            {copy.description}
          </p>
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
          <code className="mt-2 block text-xs text-soleur-text-muted">
            {actionClass}
          </code>
        </div>
        {committedTier ? (
          // text-soleur-text-danger referenced a token absent from the @theme
          // map (dead class — the button was never red). variant="danger" is
          // the live destructive treatment.
          <Button
            variant="danger"
            type="button"
            onClick={onRevoke}
            disabled={isPending}
            loading={isPending}
            loadingLabel="Revoking"
            className="rounded-md text-xs"
          >
            Revoke
          </Button>
        ) : null}
      </header>

      <fieldset
        className="space-y-2"
        disabled={isPending}
        aria-describedby={`${actionClass}-error`}
      >
        <legend className="sr-only">Trust tier for {copy.title}</legend>
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
        {/* bg-soleur-gold / text-soleur-bg-page reference tokens absent from
            the @theme map (dead classes — the CTA rendered unstyled).
            variant="gold" is the live gold-CTA treatment. */}
        <Button
          variant="gold"
          type="button"
          onClick={onGrant}
          disabled={!canSubmit}
          loading={isPending}
          loadingLabel="Saving"
          className="rounded-md disabled:opacity-40"
        >
          {committedTier ? "Update" : "Authorize"}
        </Button>
      </footer>
    </div>
  );
}
