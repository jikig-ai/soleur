"use client";

// PR-F (#3244, #3940) Phase 5 — single Today card.
// PR-H (#3244) — source-aware variants for `github` + `kb-drift` (render-
//   time redaction is the load-bearing Art. 14 gate per plan TR6).
// PR-H (#4077) — wires Send/Edit/Discard handlers + typed-confirm modal
//   on the default (Stripe / CFO) source.
//
// Each source dispatches to its own component so React rules-of-hooks
// stay clean (no conditional hooks after early returns).

import { useState, useTransition } from "react";

import { TypedConfirmModal } from "@/components/ui/typed-confirm-modal";
import { redactGithubSourcedText, type RedactionSource } from "@/lib/safety/redaction-allowlist";

interface TodayCardProps {
  id: string;
  source: string;          // "stripe" | "github" | "kb-drift" | …
  sourceRef?: string | null;
  owningDomain: string;    // "cfo" | "engineering" | "product" | "security" | "knowledge"
  draftPreview: string;
  urgency: string;         // "critical" | "high" | "medium" | "normal" | "low"
}

interface GithubButtonSpec {
  label: string;
  ariaLabel: string;
  redactSource: RedactionSource;
}

function githubButtonSpec(sourceRef: string | null | undefined): GithubButtonSpec {
  const ref = sourceRef ?? "";
  if (ref.startsWith("pr-"))
    return { label: "Spawn review agent", ariaLabel: "Let CTO spawn a PR-review agent", redactSource: "pr_title" };
  if (ref.startsWith("ci-"))
    return { label: "Spawn fix agent", ariaLabel: "Let CTO spawn a CI-fix agent", redactSource: "pr_title" };
  if (ref.startsWith("issue-"))
    return { label: "Spawn triage agent", ariaLabel: "Let CTO spawn an issue-triage agent", redactSource: "issue_body" };
  if (ref.startsWith("cve-"))
    return { label: "Spawn CVE bump agent", ariaLabel: "Let CTO spawn a CVE-bump agent", redactSource: "cve_description" };
  if (ref.startsWith("secret-scan-"))
    return { label: "Spawn secret-rotate agent", ariaLabel: "Let CTO spawn a secret-rotate agent", redactSource: "cve_description" };
  return { label: "Let CTO handle it", ariaLabel: "Let CTO handle it", redactSource: "pr_title" };
}

function isCveOrSecretScan(sourceRef: string | null | undefined): boolean {
  const ref = sourceRef ?? "";
  return ref.startsWith("cve-") || ref.startsWith("secret-scan-");
}

function parseCveHeader(draftPreview: string): { id: string; severity: string } {
  // Walker shape mirrors server/inngest/functions/github-on-event.ts
  // extractRawPreview: `<ghsa_id> (<severity>): <summary>`.
  const m = /^([^\s(]+)\s+\(([^)]+)\)/.exec(draftPreview);
  if (m) return { id: m[1], severity: m[2] };
  return { id: "<unknown id>", severity: "<unknown severity>" };
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

export function TodayCard(props: TodayCardProps) {
  if (props.source === "kb-drift") return <KbDriftCard {...props} />;
  if (props.source === "github") return <GitHubCard {...props} />;
  return <StripeCard {...props} />;
}

// KB-drift: direct-action (no leader delegation; internal-infra signal —
// no third-party text to redact). Buttons disabled until PR-H+1 (#4098).
function KbDriftCard({
  id,
  source,
  sourceRef,
  owningDomain,
  draftPreview,
  urgency,
}: TodayCardProps) {
  const label = (sourceRef ?? "").startsWith("link-") ? "Fix link" : "Update anchor";
  return (
    <article
      data-message-id={id}
      data-source={source}
      data-source-ref={sourceRef ?? ""}
      data-urgency={urgency}
      className="mb-3 rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 p-4"
    >
      <header className="mb-2 flex items-center justify-between gap-2 text-xs uppercase tracking-wide text-soleur-text-secondary">
        <span>
          {owningDomain} • {source}
        </span>
        <span data-urgency-label={urgency}>{urgency}</span>
      </header>
      <p className="mb-3 whitespace-pre-line text-sm text-soleur-text-primary">{draftPreview}</p>
      <div className="flex flex-wrap gap-2">
        <button
          type="button"
          disabled
          aria-disabled="true"
          data-action="kb-drift-fix"
          title="Wires in PR-H+1"
          className="min-h-[44px] cursor-not-allowed rounded-md bg-amber-600/40 px-3 py-2 text-sm font-medium text-soleur-text-primary"
          aria-label={label}
        >
          {label}
        </button>
      </div>
    </article>
  );
}

// GitHub: source_ref-driven affordance + render-time redaction. CVE /
// secret-scan renders ID + severity only by default (AC6); the summary
// body is already stripped server-side. Buttons disabled until PR-H+1.
function GitHubCard({
  id,
  source,
  sourceRef,
  owningDomain,
  draftPreview,
  urgency,
}: TodayCardProps) {
  const button = githubButtonSpec(sourceRef);
  const cve = isCveOrSecretScan(sourceRef);
  const redactedBody = redactGithubSourcedText(draftPreview, { source: button.redactSource });

  return (
    <article
      data-message-id={id}
      data-source={source}
      data-source-ref={sourceRef ?? ""}
      data-urgency={urgency}
      className="mb-3 rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 p-4"
    >
      <header className="mb-2 flex items-center justify-between gap-2 text-xs uppercase tracking-wide text-soleur-text-secondary">
        <span>
          {owningDomain} • {source}
        </span>
        <span data-urgency-label={urgency}>{urgency}</span>
      </header>

      {cve ? (
        <div data-testid="today-card-cve" className="mb-3 flex items-center gap-2 text-sm">
          <span data-testid="cve-id" className="font-mono text-soleur-text-primary">
            {parseCveHeader(draftPreview).id}
          </span>
          <span
            data-testid="severity-badge"
            className="rounded-full bg-red-900/40 px-2 py-0.5 text-xs uppercase tracking-wide text-red-200"
          >
            {parseCveHeader(draftPreview).severity}
          </span>
        </div>
      ) : (
        <p
          data-testid="draft-preview-body"
          className="mb-3 whitespace-pre-line text-sm text-soleur-text-primary"
        >
          {redactedBody}
        </p>
      )}

      <div className="flex flex-wrap gap-2">
        <button
          type="button"
          disabled
          aria-disabled="true"
          data-action="github-handle"
          data-button-label={button.label}
          title="Wires in PR-H+1"
          className="min-h-[44px] cursor-not-allowed rounded-md bg-amber-600/40 px-3 py-2 text-sm font-medium text-soleur-text-primary"
          aria-label={button.ariaLabel}
        >
          {button.label}
        </button>
      </div>
    </article>
  );
}

// Stripe / CFO path — PR-H (#4077) Send/Edit/Discard flow with typed-
// confirm modal for approve_every_time tier.
function StripeCard({
  id,
  source,
  sourceRef,
  owningDomain,
  draftPreview,
  urgency,
}: TodayCardProps) {
  const [isPending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [archived, setArchived] = useState(false);
  const [draft, setDraft] = useState(draftPreview);
  const [confirming, setConfirming] = useState<ConfirmationPayload | null>(null);

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
          const json = (await res.json().catch(() => ({}))) as { error?: string };
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
      data-source={source}
      data-source-ref={sourceRef ?? ""}
      data-urgency={urgency}
      className="mb-3 rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 p-4"
    >
      <header className="mb-2 flex items-center justify-between gap-2 text-xs uppercase tracking-wide text-soleur-text-secondary">
        <span>
          {owningDomain} • {source}
        </span>
        <span data-urgency-label={urgency}>{urgency}</span>
      </header>
      <p
        data-testid="draft-preview-body"
        className="mb-3 whitespace-pre-line text-sm text-soleur-text-primary"
      >
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
