"use client";

// PR-A (#4124) — Shared click handler hook for the StripeCard, GitHubCard,
// and KbDriftCard variants in components/dashboard/today-card.tsx.
//
// Extracts the StripeCard send/edit/discard send-orchestration logic out
// of the component so GitHubCard + KbDriftCard can share the same 200 /
// 403 / 409 branching without code duplication (three callers after this
// PR — code-simplicity reviewer's "single-caller abstraction smell" is
// resolved because StripeCard + 2 new card variants all consume).
//
// Hook contract:
//   onSend            — fires the POST. Empty body for draft_one_click;
//                        the typed-confirm modal supplies the
//                        `confirmed_typed` payload for approve_every_time.
//   isPending         — Send is in-flight; buttons should disable.
//   error             — last error string for inline render.
//   acknowledged      — true on the FIRST 200 response. Combined with
//                        `artifactUrl` so the GitHubCard / KbDriftCard can
//                        render an "Acknowledged — View on GitHub" pill.
//                        StripeCard ignores `artifactUrl` and continues to
//                        use its existing `setArchived(true)` flow on send;
//                        GitHubCard + KbDriftCard render the pill.
//   artifactUrl       — server-derived deterministic URL of the
//                        acknowledgment artifact. Empty for kb_drift
//                        link-* sources until PR-B's leader-prompt loop
//                        resolves per-class targeting.
//   degraded          — set to "enqueue_failed" when the Inngest enqueue
//                        between writeActionSend and archive flip threw.
//                        Cards should render "Acknowledged (queued)" copy.
//   confirming        — non-null while the typed-confirm modal is open.
//   onConfirmTyped    — called from the typed-confirm modal submit.
//   onCancelConfirm   — called from the typed-confirm modal cancel.

import { useState, useTransition } from "react";

import type { DenyReason } from "@/server/templates/is-template-authorized";

export interface ConfirmationPayload {
  actionClass: string;
  tier: string;
  recipientExcerpt: string;
  contentExcerpt: string;
  expectedDraftPreviewHash: string;
  messageId: string;
}

export interface UseActionSendOptions {
  messageId: string;
  /**
   * Per-DenyReason copy override. Lets each card variant supply its own
   * founder-facing string for `template_revoked` / `template_expired`
   * etc. Falls back to a generic 403 string when omitted.
   */
  denyReasonCopy?: Partial<Record<DenyReason, string>>;
  /**
   * Optional callback fired on the FIRST 200 response. StripeCard wires
   * this to `setArchived(true)` (matches pre-PR-A behavior); GitHubCard +
   * KbDriftCard leave it unset and use the `acknowledged` pill instead.
   */
  onAcknowledgedArchive?: () => void;
}

export interface UseActionSendResult {
  onSend: () => void;
  isPending: boolean;
  error: string | null;
  acknowledged: boolean;
  artifactUrl: string;
  degraded: "enqueue_failed" | undefined;
  confirming: ConfirmationPayload | null;
  onConfirmTyped: (confirmedTyped: boolean, typedValue: string) => void;
  onCancelConfirm: () => void;
}

export function useActionSend(
  opts: UseActionSendOptions,
): UseActionSendResult {
  const { messageId, denyReasonCopy, onAcknowledgedArchive } = opts;
  const [isPending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [acknowledged, setAcknowledged] = useState(false);
  const [artifactUrl, setArtifactUrl] = useState("");
  const [degraded, setDegraded] = useState<"enqueue_failed" | undefined>(
    undefined,
  );
  const [confirming, setConfirming] = useState<ConfirmationPayload | null>(
    null,
  );

  async function postSend(extra?: {
    confirmed_typed: true;
    typed_value: string;
    expected_draft_preview_hash: string;
  }) {
    return fetch(`/api/dashboard/today/${messageId}/send`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(extra ?? {}),
    });
  }

  function handle200(json: {
    artifact_view_url?: string;
    degraded?: string;
  }) {
    setAcknowledged(true);
    setArtifactUrl(json.artifact_view_url ?? "");
    setDegraded(
      json.degraded === "enqueue_failed" ? "enqueue_failed" : undefined,
    );
    onAcknowledgedArchive?.();
  }

  function onSend() {
    setError(null);
    startTransition(async () => {
      try {
        const res = await postSend();
        if (res.status === 200) {
          const json = (await res
            .json()
            .catch(() => ({}))) as {
            artifact_view_url?: string;
            degraded?: string;
          };
          handle200(json);
          return;
        }
        if (res.status === 409) {
          const json = (await res.json().catch(() => ({}))) as {
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
              expectedDraftPreviewHash:
                json.expected_draft_preview_hash ?? "",
              messageId: json.message_id ?? messageId,
            });
            return;
          }
          if (json.error === "already_sent") {
            // Match StripeCard's pre-PR-A behavior: treat 409 already_sent
            // as a soft success — the row already exists.
            setAcknowledged(true);
            onAcknowledgedArchive?.();
            return;
          }
        }
        if (res.status === 403) {
          const json = (await res.json().catch(() => ({}))) as {
            error?: string;
            deny_reason?: string;
          };
          if (
            denyReasonCopy &&
            json.deny_reason !== undefined &&
            json.deny_reason in denyReasonCopy
          ) {
            const copy = denyReasonCopy[json.deny_reason as DenyReason];
            if (copy !== undefined) {
              setError(copy);
              return;
            }
          }
          if (
            json.error === "no_active_grant" &&
            denyReasonCopy?.no_scope_grant !== undefined
          ) {
            setError(denyReasonCopy.no_scope_grant);
            return;
          }
        }
        setError(`Send failed (${res.status})`);
      } catch {
        setError("Send failed — network error");
      }
    });
  }

  function onConfirmTyped(_confirmedTyped: boolean, typedValue: string) {
    const pendingHash = confirming?.expectedDraftPreviewHash ?? "";
    setConfirming(null);
    setError(null);
    startTransition(async () => {
      try {
        const res = await postSend({
          confirmed_typed: true,
          typed_value: typedValue,
          expected_draft_preview_hash: pendingHash,
        });
        if (res.status === 200) {
          const json = (await res
            .json()
            .catch(() => ({}))) as {
            artifact_view_url?: string;
            degraded?: string;
          };
          handle200(json);
          return;
        }
        if (res.status === 409) {
          const json = (await res.json().catch(() => ({}))) as {
            error?: string;
          };
          if (json.error === "already_sent") {
            setAcknowledged(true);
            onAcknowledgedArchive?.();
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

  return {
    onSend,
    isPending,
    error,
    acknowledged,
    artifactUrl,
    degraded,
    confirming,
    onConfirmTyped,
    onCancelConfirm,
  };
}
