"use client";

// PR-F (#3244, #3940) Phase 5 — single Today card.
// PR-H (#3244) — source-aware variants for `github` + `kb-drift` (render-
//   time redaction is the load-bearing Art. 14 gate per plan TR6).
// PR-H (#4077) — wires Send/Edit/Discard handlers + typed-confirm modal
//   on the default (Stripe / CFO) source.
// PR-A (#4124) — wires GitHubCard + KbDriftCard onClick handlers through
//   the shared `useActionSend()` hook (3 callers now justify the
//   extraction). Drops the `disabled aria-disabled` "Wires in PR-H+1"
//   buttons on those variants. Renders "Acknowledged — View on GitHub"
//   pill on the 200 response.
//
// Each source dispatches to its own component so React rules-of-hooks
// stay clean (no conditional hooks after early returns).

import { useState, useTransition } from "react";

import { TypedConfirmModal } from "@/components/ui/typed-confirm-modal";
import { useActionSend } from "@/hooks/use-action-send";
import { humanTitle } from "@/lib/messages/action-class-copy";
import { redactGithubSourcedText, type RedactionSource } from "@/lib/safety/redaction-allowlist";
import type { DenyReason } from "@/server/templates/is-template-authorized";

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
  const m = draftPreview.match(/^([^\s(]+)\s+\(([^)]+)\)/);
  if (m) return { id: m[1], severity: m[2] };
  return { id: "<unknown id>", severity: "<unknown severity>" };
}

/**
 * GitHubCard's approve_every_time target label — PR / issue / advisory
 * shape derived from source_ref so the typed-confirm modal names the
 * actual GitHub target (PR-A AC12). Returns undefined for shapes that
 * don't carry a parseable number.
 */
function githubActionTargetLabel(
  sourceRef: string | null | undefined,
): string | undefined {
  const ref = sourceRef ?? "";
  // Format: <prefix>-<owner>:<repo>:<n> (per github-on-event.ts deriveSourceRef).
  const m = ref.match(/^(pr|issue|secret-scan)-[^:]+:[^:]+:(\d+)$/);
  if (m) {
    if (m[1] === "pr") return `PR #${m[2]}`;
    return `issue #${m[2]}`;
  }
  const cveMatch = ref.match(/^cve-(.+)$/);
  if (cveMatch) return `advisory ${cveMatch[1]}`;
  return undefined;
}

const BASE_BUTTON =
  "min-h-[44px] rounded-md px-3 py-2 text-sm font-medium disabled:cursor-not-allowed disabled:opacity-50";

const SPAWN_BUTTON =
  "min-h-[44px] rounded-md bg-amber-600 px-3 py-2 text-sm font-medium text-white disabled:cursor-not-allowed disabled:opacity-50";

// PR-I (#4078) — Per-DenyReason copy surfaced when the send route
// returns 403 with `deny_reason`. `template_unauthorized` is unreachable
// in v2 (first-send-IS-authorization). `no_scope_grant` corresponds to
// the legacy 403 `error: 'no_active_grant'` shape — kept here for
// completeness so future predicate denials map cleanly.
const DENY_REASON_COPY: Record<DenyReason, string> = {
  no_scope_grant:
    "You need a scope grant first. Visit Settings → Scope grants.",
  template_unauthorized:
    "Send couldn't verify your template authorization. Try again in a moment.",
  template_revoked:
    "This template was revoked. Click Send again to re-authorize.",
  template_expired:
    "This template authorization expired (90-day limit). Click Send again to re-authorize.",
  template_quota_exhausted:
    "You've sent 100 messages with this template. Click Send again to re-authorize for another 100.",
};

export function TodayCard(props: TodayCardProps) {
  if (props.source === "kb-drift") return <KbDriftCard {...props} />;
  if (props.source === "github") return <GitHubCard {...props} />;
  return <StripeCard {...props} />;
}

// KB-drift: direct-action via /send. PR-A wires the click through
// useActionSend; the Inngest function classifies link-* refs as
// malformed_source_ref until PR-B adds per-class resolution (operator
// still sees the "Acknowledged (queued)" pill).
function KbDriftCard({
  id,
  source,
  sourceRef,
  owningDomain,
  draftPreview,
  urgency,
}: TodayCardProps) {
  const label = (sourceRef ?? "").startsWith("link-") ? "Fix link" : "Update anchor";
  const { onSend, isPending, error, acknowledged, artifactUrl, degraded } =
    useActionSend({ messageId: id, denyReasonCopy: DENY_REASON_COPY });

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
      {error ? (
        <p className="mb-2 text-xs text-red-600" role="alert">
          {error}
        </p>
      ) : null}
      <div className="flex flex-wrap gap-2">
        {acknowledged ? (
          <AcknowledgedPill artifactUrl={artifactUrl} degraded={degraded} />
        ) : (
          <button
            type="button"
            onClick={onSend}
            disabled={isPending}
            data-action="kb-drift-fix"
            className={SPAWN_BUTTON}
            aria-label={label}
          >
            {label}
          </button>
        )}
      </div>
    </article>
  );
}

// GitHub: source_ref-driven affordance + render-time redaction. CVE /
// secret-scan renders ID + severity only by default (AC6); the summary
// body is already stripped server-side. PR-A wires the click through
// useActionSend; the approve_every_time tier (cve_alert, secret-scan)
// surfaces the typed-confirm modal with action-target naming.
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
  const {
    onSend,
    isPending,
    error,
    acknowledged,
    artifactUrl,
    degraded,
    confirming,
    onConfirmTyped,
    onCancelConfirm,
  } = useActionSend({ messageId: id, denyReasonCopy: DENY_REASON_COPY });

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

      {error ? (
        <p className="mb-2 text-xs text-red-600" role="alert">
          {error}
        </p>
      ) : null}

      <div className="flex flex-wrap gap-2">
        {acknowledged ? (
          <AcknowledgedPill artifactUrl={artifactUrl} degraded={degraded} />
        ) : (
          <button
            type="button"
            onClick={onSend}
            disabled={isPending}
            data-action="github-handle"
            data-button-label={button.label}
            className={SPAWN_BUTTON}
            aria-label={button.ariaLabel}
          >
            {button.label}
          </button>
        )}
      </div>

      <TypedConfirmModal
        open={confirming !== null}
        recipientExcerpt={confirming?.recipientExcerpt ?? ""}
        contentExcerpt={confirming?.contentExcerpt ?? ""}
        actionClassLabel={confirming ? humanTitle(confirming.actionClass) : ""}
        tierLabel={confirming?.tier ?? ""}
        actionTargetLabel={githubActionTargetLabel(sourceRef)}
        onCancel={onCancelConfirm}
        onConfirm={onConfirmTyped}
      />
    </article>
  );
}

// Stripe / CFO path — PR-H (#4077) Send/Edit/Discard flow with typed-
// confirm modal for approve_every_time tier. PR-A (#4124) refactor:
// uses the shared `useActionSend()` hook with the
// `onAcknowledgedArchive` callback wired to `setArchived(true)` —
// preserves the pre-PR-A "card disappears on send" behavior. Edit /
// Discard stay local to this component (StripeCard-only affordances).
function StripeCard({
  id,
  source,
  sourceRef,
  owningDomain,
  draftPreview,
  urgency,
}: TodayCardProps) {
  const [isPendingLocal, startTransition] = useTransition();
  const [archived, setArchived] = useState(false);
  const [draft, setDraft] = useState(draftPreview);
  const [editError, setEditError] = useState<string | null>(null);

  const {
    onSend,
    isPending: isPendingSend,
    error: sendError,
    confirming,
    onConfirmTyped,
    onCancelConfirm,
  } = useActionSend({
    messageId: id,
    denyReasonCopy: DENY_REASON_COPY,
    onAcknowledgedArchive: () => setArchived(true),
  });

  const isPending = isPendingLocal || isPendingSend;
  const error = sendError ?? editError;

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
        setEditError(`Edit failed (${res.status})`);
      } catch {
        setEditError("Edit failed — network error");
      }
    });
  }

  function onDiscard() {
    setArchived(true);
    setEditError(null);
    startTransition(async () => {
      try {
        const res = await fetch(`/api/dashboard/today/${id}/discard`, {
          method: "POST",
        });
        if (res.status !== 200) {
          setArchived(false);
          setEditError(`Discard failed (${res.status})`);
        }
      } catch {
        setArchived(false);
        setEditError("Discard failed — network error");
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
        actionClassLabel={confirming ? humanTitle(confirming.actionClass) : ""}
        tierLabel={confirming?.tier ?? ""}
        onCancel={onCancelConfirm}
        onConfirm={onConfirmTyped}
      />
    </article>
  );
}

interface AcknowledgedPillProps {
  artifactUrl: string;
  degraded: "enqueue_failed" | "no_artifact_in_pr_a" | undefined;
}

type PillState = "ack" | "pending" | "queued" | "no_artifact";

function derivePillState(
  artifactUrl: string,
  degraded: AcknowledgedPillProps["degraded"],
): PillState {
  // Pure derivation. Precedence: no_artifact_in_pr_a > enqueue_failed >
  // artifactUrl-present > artifactUrl-absent. Each branch is exclusive.
  // The pure shape lets the component test matrix all four states
  // without rendering, and prevents the latent bug where a future
  // "degraded WITH partial artifact" shape silently drops the link.
  if (degraded === "no_artifact_in_pr_a") return "no_artifact";
  if (degraded === "enqueue_failed") return "queued";
  if (artifactUrl) return "ack";
  return "pending";
}

function AcknowledgedPill({ artifactUrl, degraded }: AcknowledgedPillProps) {
  // PR-A — optimistic acknowledgment pill rendered on the 200 response
  // from /send. The Inngest function emits the actual GitHub artifact
  // within ~60s (happy path); operator follows the link to verify.
  const state = derivePillState(artifactUrl, degraded);

  if (state === "no_artifact") {
    return (
      <span
        data-testid="acknowledged-pill"
        data-pill-state="no_artifact"
        className="inline-flex items-center gap-2 rounded-full bg-slate-700/40 px-3 py-1 text-xs font-medium text-slate-100"
      >
        Acknowledged — full handling lands in PR-B (#4360)
      </span>
    );
  }
  if (state === "queued") {
    return (
      <span
        data-testid="acknowledged-pill"
        data-pill-state="queued"
        className="inline-flex items-center gap-2 rounded-full bg-amber-700/30 px-3 py-1 text-xs font-medium text-amber-100"
      >
        Acknowledged (queued — retry from a fresh card if no artifact appears within a minute)
      </span>
    );
  }
  if (state === "pending") {
    return (
      <span
        data-testid="acknowledged-pill"
        data-pill-state="pending"
        className="inline-flex items-center gap-2 rounded-full bg-green-700/30 px-3 py-1 text-xs font-medium text-green-100"
      >
        Acknowledged (pending artifact)
      </span>
    );
  }
  return (
    <a
      href={artifactUrl}
      target="_blank"
      rel="noopener noreferrer"
      data-testid="acknowledged-pill"
      data-pill-state="ack"
      className="inline-flex items-center gap-2 rounded-full bg-green-700/30 px-3 py-1 text-xs font-medium text-green-100 hover:bg-green-700/40"
    >
      Acknowledged — View on GitHub
    </a>
  );
}
