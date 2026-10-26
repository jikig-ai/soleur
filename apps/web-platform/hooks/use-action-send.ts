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
//   degraded          — "no_artifact_in_pr_a" when the source_ref shape has
//                        no GitHub target yet (no Inngest event is sent). An
//                        exhausted enqueue is NOT a 200 any more (#10543): the
//                        route answers 503 enqueue_unavailable, the approval is
//                        saved and the draft stays, so `error` carries the
//                        retry copy and `acknowledged` stays false.
//   confirming        — non-null while the typed-confirm modal is open.
//   confirmPending    — typed-confirm POST in flight. The modal stays
//                        open (`confirming` is NOT cleared until the POST
//                        resolves) so the founder sees "Sending…" instead
//                        of a silent gap (was: modal closed before the
//                        POST — the highest-stakes feedback gap).
//   onConfirmTyped    — called from the typed-confirm modal submit.
//   onCancelConfirm   — called from the typed-confirm modal cancel.

import { useRef, useState, useTransition } from "react";

import { reportSilentFallback } from "@/lib/client-observability";
// Shared 30s termination horizon with the pending watchdog — one clock for
// every "hung request must not hold the UI" path in the feature.
import { PENDING_WATCHDOG_MS } from "@/hooks/use-pending-action";
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
  degraded: "no_artifact_in_pr_a" | undefined;
  confirming: ConfirmationPayload | null;
  confirmPending: boolean;
  onConfirmTyped: (confirmedTyped: boolean, typedValue: string) => void;
  onCancelConfirm: () => void;
}

export function useActionSend(
  opts: UseActionSendOptions,
): UseActionSendResult {
  const { messageId, denyReasonCopy, onAcknowledgedArchive } = opts;
  const [isPending, startTransition] = useTransition();
  const [confirmPending, startConfirmTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [acknowledged, setAcknowledged] = useState(false);
  const [artifactUrl, setArtifactUrl] = useState("");
  const [degraded, setDegraded] = useState<"no_artifact_in_pr_a" | undefined>(
    undefined,
  );
  const [confirming, setConfirming] = useState<ConfirmationPayload | null>(
    null,
  );
  // In-flight guard (#10543, CTO Q7): GitHubCard and KbDriftCard bind no `disabled` to isPending, and
  // isPending is stale inside a closure on a rapid double-click, so a ref is checked synchronously.
  // Released in a `finally`, so a 503, a 30s abort and a thrown fetch all release it.
  const inFlight = useRef(false);

  async function postSend(extra?: {
    confirmed_typed: true;
    typed_value: string;
    expected_draft_preview_hash: string;
  }) {
    // Pending must always terminate (spec FR2): an unbounded POST would lock
    // the typed-confirm modal open with every dismiss vector inert. Abort at
    // the watchdog horizon so the transition resolves into the in-modal
    // role="alert" error path instead.
    return fetch(`/api/dashboard/today/${messageId}/send`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(extra ?? {}),
      signal: AbortSignal.timeout(PENDING_WATCHDOG_MS),
    });
  }

  // Founder-facing copy for the statuses the send route can answer with besides 200 / already_sent /
  // requires_confirmation. Card-neutral on purpose: GitHubCard and KbDriftCard bind no `disabled` to a
  // hook flag and have no Discard/Edit, so every state here must be recoverable by a refresh and the
  // copy avoids naming Discard/Edit (CTO S1; the 503 line only says to click Send again). Pure over (status, parsed body) apart from the `denyReasonCopy`
  // option it closes over; returns null when the status is not one of these (the caller falls through
  // to its generic "Send failed (NNN)"). A 503 only reads as "approval saved" when the body says so: a
  // bare gateway 503 must not claim an approval exists.
  function failureCopy(
    status: number,
    json: { error?: string; deny_reason?: string },
  ): string | null {
    if (status === 503 && json.error === "enqueue_unavailable") {
      return "Your approval is saved, but we couldn't start the agent. Click Send again to retry.";
    }
    if (status === 409) {
      switch (json.error) {
        case "approval_expired":
        case "not_a_draft":
          return "This approval can no longer run. Refresh to update this card.";
        case "draft_changed_since_approval":
          return "This draft changed after you approved it, so this approval can't run.";
        case "send_in_progress":
          return "Another send is in progress — try again in a moment";
        default:
          return null;
      }
    }
    if (status === 403) {
      if (
        denyReasonCopy &&
        json.deny_reason !== undefined &&
        json.deny_reason in denyReasonCopy
      ) {
        const copy = denyReasonCopy[json.deny_reason as DenyReason];
        if (copy !== undefined) return copy;
      }
      if (
        json.error === "no_active_grant" &&
        denyReasonCopy?.no_scope_grant !== undefined
      ) {
        return denyReasonCopy.no_scope_grant;
      }
      if (
        json.error === "no_active_grant" ||
        json.error === "template_not_authorized"
      ) {
        return "Permissions changed since you approved. This action can't run.";
      }
    }
    return null;
  }

  function sendFailureMessage(err: unknown): string {
    if (err instanceof DOMException && err.name === "TimeoutError") {
      reportSilentFallback(err, {
        feature: "ui-action-feedback",
        op: "action-send-timeout",
        message: `send POST exceeded ${PENDING_WATCHDOG_MS}ms — aborted`,
      });
      return "Send timed out — please try again";
    }
    return "Send failed — network error";
  }

  function handle200(json: {
    artifact_view_url?: string;
    degraded?: string;
  }) {
    setAcknowledged(true);
    setArtifactUrl(json.artifact_view_url ?? "");
    setDegraded(
      json.degraded === "no_artifact_in_pr_a" ? "no_artifact_in_pr_a" : undefined,
    );
    onAcknowledgedArchive?.();
  }

  function onSend() {
    if (inFlight.current) return;
    inFlight.current = true;
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
        const json = (await res.json().catch(() => ({}))) as {
          error?: string;
          deny_reason?: string;
          action_class?: string;
          tier?: string;
          recipient_excerpt?: string;
          content_excerpt?: string;
          expected_draft_preview_hash?: string;
          message_id?: string;
        };
        if (res.status === 409) {
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
        const copy = failureCopy(res.status, json);
        if (copy !== null) {
          setError(copy);
          return;
        }
        setError(`Send failed (${res.status})`);
      } catch (err) {
        setError(sendFailureMessage(err));
      } finally {
        inFlight.current = false;
      }
    });
  }

  function onConfirmTyped(_confirmedTyped: boolean, typedValue: string) {
    if (inFlight.current) return;
    inFlight.current = true;
    const pendingHash = confirming?.expectedDraftPreviewHash ?? "";
    setError(null);
    // `confirming` stays set for the whole flight — the modal renders the
    // pending state and closes only on RESOLUTION: success clears it via
    // the acknowledged paths below; failure keeps it open with `error`
    // rendered in-modal (the typed SEND value persists).
    startConfirmTransition(async () => {
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
          setConfirming(null);
          handle200(json);
          return;
        }
        const json = (await res.json().catch(() => ({}))) as {
          error?: string;
          deny_reason?: string;
          expected_draft_preview_hash?: string;
        };
        if (res.status === 409) {
          if (json.error === "already_sent") {
            setConfirming(null);
            setAcknowledged(true);
            onAcknowledgedArchive?.();
            return;
          }
          if (json.error === "requires_confirmation") {
            // Adopt the server's fresh hash so a retype does not loop on the
            // stale one (the draft changed between the two POSTs).
            const fresh = json.expected_draft_preview_hash;
            if (typeof fresh === "string" && fresh !== "") {
              setConfirming((c) =>
                c ? { ...c, expectedDraftPreviewHash: fresh } : c,
              );
            }
            setError("Draft changed since you confirmed — please re-send.");
            return;
          }
        }
        const copy = failureCopy(res.status, json);
        if (copy !== null) {
          setError(copy);
          return;
        }
        setError(`Send failed (${res.status})`);
      } catch (err) {
        setError(sendFailureMessage(err));
      } finally {
        inFlight.current = false;
      }
    });
  }

  function onCancelConfirm() {
    // Never cleared mid-flight — Cancel is inert while the POST is out.
    // Belt-and-suspenders: the modal already makes every dismiss vector
    // inert while confirmPending, so this guard is unreachable in practice —
    // kept as defense if a future consumer wires onCancelConfirm loosely.
    if (confirmPending) return;
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
    confirmPending,
    onConfirmTyped,
    onCancelConfirm,
  };
}
