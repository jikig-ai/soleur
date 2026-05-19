"use client";

// PR-F (#3244, #3940) Phase 5 — single Today card.
// PR-H (#4077) — wires Send/Edit/Discard handlers + typed-confirm modal.
//
// Renders one draft message from /api/dashboard/today. Send POSTs to
// /api/dashboard/today/[id]/send; on 409 requires_confirmation the
// typed-confirm modal opens and the founder must type SEND (case-
// sensitive — load-bearing TOM per TR6). A second POST with
// confirmed_typed=true + typed_value carries the signature.

import { useState, useTransition } from "react";

import { TypedConfirmModal } from "@/components/ui/typed-confirm-modal";

interface TodayCardProps {
  id: string;
  source: string;          // "stripe" | "manual" | …
  owningDomain: string;    // "cfo" | …
  draftPreview: string;
  urgency: string;         // "low" | "medium" | "high"
}

interface ConfirmationPayload {
  actionClass: string;
  tier: string;
  recipientExcerpt: string;
  // Content excerpt as the SERVER saw draft_preview at 409-issue time —
  // NOT the local `draft` state. Binding the modal's content preview to
  // the server payload closes the Send→Edit→Send race where a sibling
  // tab edits between the 409 and the confirm POST. The server returns
  // the new hash on each 409; the second POST must echo it.
  contentExcerpt: string;
  expectedDraftPreviewHash: string;
  messageId: string;
}

const BASE_BUTTON =
  "min-h-[44px] rounded-md px-3 py-2 text-sm font-medium disabled:cursor-not-allowed disabled:opacity-50";

export function TodayCard({
  id,
  source,
  owningDomain,
  draftPreview,
  urgency,
}: TodayCardProps) {
  const [isPending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [archived, setArchived] = useState(false);
  const [draft, setDraft] = useState(draftPreview);
  const [confirming, setConfirming] = useState<ConfirmationPayload | null>(
    null,
  );

  // The server derives body_content and recipient_identifier from the
  // messages row at request time, so this client sends ONLY the typed-
  // confirm signature surface. Sending body/recipient from here would
  // let a compromised page bind the approval signature to content the
  // founder never saw (GDPR Art. 5(2) accountability — DPD §2.3(q)).
  async function postSend(extra?: {
    confirmed_typed: true;
    typed_value: string;
    expected_draft_preview_hash: string;
  }) {
    const res = await fetch(`/api/dashboard/today/${id}/send`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(extra ?? {}),
    });
    return res;
  }

  function onSend() {
    setError(null);
    startTransition(async () => {
      try {
        const res = await postSend();
        if (res.status === 200) {
          setArchived(true);
          return;
        }
        if (res.status === 409) {
          const json = (await res.json()) as {
            error?: string;
            action_class?: string;
            tier?: string;
            recipient_excerpt?: string;
            content_excerpt?: string;
            expected_draft_preview_hash?: string;
            message_id?: string;
          };
          if (json.error === "requires_confirmation") {
            setConfirming({
              actionClass: json.action_class ?? "",
              tier: json.tier ?? "",
              recipientExcerpt: json.recipient_excerpt ?? "",
              contentExcerpt: json.content_excerpt ?? "",
              expectedDraftPreviewHash: json.expected_draft_preview_hash ?? "",
              messageId: json.message_id ?? id,
            });
            return;
          }
          if (json.error === "already_sent") {
            // Another tab / a re-render / a retry beat us to it. The
            // WORM row already exists; reflect that locally.
            setArchived(true);
            return;
          }
        }
        setError(`Send failed (${res.status})`);
      } catch {
        setError("Send failed — network error");
      }
    });
  }

  function onConfirmTyped(confirmedTyped: boolean, typedValue: string) {
    const pendingHash = confirming?.expectedDraftPreviewHash ?? "";
    setConfirming(null);
    startTransition(async () => {
      try {
        const res = await postSend({
          confirmed_typed: true,
          typed_value: typedValue,
          expected_draft_preview_hash: pendingHash,
        });
        void confirmedTyped;
        if (res.status === 200) {
          setArchived(true);
          return;
        }
        if (res.status === 409) {
          // Either the draft hash drifted (concurrent edit between 409
          // and this POST) or another tab already sent. Surface the
          // error generically; the founder's next click will re-issue
          // a fresh 409 if appropriate.
          const json = (await res.json().catch(() => ({}))) as {
            error?: string;
          };
          if (json.error === "already_sent") {
            setArchived(true);
            return;
          }
          setError("Draft changed since you confirmed — please re-send.");
          return;
        }
        setError(`Send failed (${res.status})`);
      } catch {
        setError("Send failed — network error");
      }
    });
  }

  function onCancelConfirm() {
    setConfirming(null);
  }

  function onEdit() {
    // Inline prompt for PR-H; PR-I will replace with a richer editor.
    const next = window.prompt("Edit draft", draft);
    if (next === null) return;
    if (next === draft) return;
    startTransition(async () => {
      try {
        const res = await fetch(`/api/dashboard/today/${id}/edit`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ draft_preview: next }),
        });
        if (res.status === 200) {
          setDraft(next);
          return;
        }
        setError(`Edit failed (${res.status})`);
      } catch {
        setError("Edit failed — network error");
      }
    });
  }

  function onDiscard() {
    // Optimistic: hide the card immediately; revert on failure.
    setArchived(true);
    setError(null);
    startTransition(async () => {
      try {
        const res = await fetch(`/api/dashboard/today/${id}/discard`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
        });
        if (res.status !== 200) {
          setArchived(false);
          setError(`Discard failed (${res.status})`);
        }
      } catch {
        setArchived(false);
        setError("Discard failed — network error");
      }
    });
  }

  if (archived) return null;

  return (
    <article
      data-message-id={id}
      data-urgency={urgency}
      className="mb-3 rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 p-4"
    >
      <header className="mb-2 flex items-center justify-between gap-2 text-xs uppercase tracking-wide text-soleur-text-secondary">
        <span>
          {owningDomain} • {source}
        </span>
        <span data-urgency-label={urgency}>{urgency}</span>
      </header>
      <p className="mb-3 whitespace-pre-line text-sm text-soleur-text-primary">
        {draft}
      </p>
      {error ? (
        <p className="mb-2 text-xs text-red-600" role="alert">
          {error}
        </p>
      ) : null}
      <div className="flex flex-wrap gap-2">
        <button
          type="button"
          onClick={onSend}
          disabled={isPending}
          data-action="send"
          className={`${BASE_BUTTON} bg-amber-600 text-white`}
          aria-label="Send draft"
        >
          Send
        </button>
        <button
          type="button"
          onClick={onEdit}
          disabled={isPending}
          data-action="edit"
          className={`${BASE_BUTTON} border border-soleur-border-default bg-soleur-bg-surface-2 text-soleur-text-primary`}
          aria-label="Edit draft"
        >
          Edit
        </button>
        <button
          type="button"
          onClick={onDiscard}
          disabled={isPending}
          data-action="discard"
          className={`${BASE_BUTTON} border border-soleur-border-default bg-soleur-bg-surface-2 text-soleur-text-secondary`}
          aria-label="Discard draft"
        >
          Discard
        </button>
      </div>
      <TypedConfirmModal
        open={confirming !== null}
        recipientExcerpt={confirming?.recipientExcerpt ?? ""}
        contentExcerpt={confirming?.contentExcerpt ?? ""}
        actionClassLabel={confirming?.actionClass ?? ""}
        tierLabel={confirming?.tier ?? ""}
        onCancel={onCancelConfirm}
        onConfirm={onConfirmTyped}
      />
    </article>
  );
}
