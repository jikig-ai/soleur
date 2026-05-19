// PR-H (#3244) Phase 6 — source-aware Today card variants. Extends PR-F's
// stripe/cfo card with `github` + `kb-drift` paths and render-time
// redaction (load-bearing Art. 14 gate per plan TR6 amendment).

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

export function TodayCard({
  id,
  source,
  sourceRef,
  owningDomain,
  draftPreview,
  urgency,
}: TodayCardProps) {
  // KB-drift: direct-action (no leader delegation; internal-infra signal
  // — no third-party text to redact).
  if (source === "kb-drift") {
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

  // GitHub: source_ref-driven affordance + render-time redaction.
  if (source === "github") {
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

  // Stripe / CFO path — unchanged from PR-F.
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
        {draftPreview}
      </p>
      <div className="flex flex-wrap gap-2">
        <button
          type="button"
          disabled
          aria-disabled="true"
          data-action="send"
          title="Wires in PR-G (#3947)"
          className="min-h-[44px] cursor-not-allowed rounded-md bg-amber-600/40 px-3 py-2 text-sm font-medium text-soleur-text-primary"
          aria-label="Send draft (wired in PR-G)"
        >
          Send
        </button>
        <button
          type="button"
          disabled
          aria-disabled="true"
          data-action="edit"
          title="Wires in PR-G (#3947)"
          className="min-h-[44px] cursor-not-allowed rounded-md border border-soleur-border-default bg-soleur-bg-surface-2 px-3 py-2 text-sm font-medium text-soleur-text-secondary opacity-60"
          aria-label="Edit draft (wired in PR-G)"
        >
          Edit
        </button>
        <button
          type="button"
          disabled
          aria-disabled="true"
          data-action="discard"
          title="Wires in PR-G (#3947)"
          className="min-h-[44px] cursor-not-allowed rounded-md border border-soleur-border-default bg-soleur-bg-surface-2 px-3 py-2 text-sm font-medium text-soleur-text-secondary opacity-60"
          aria-label="Discard draft (wired in PR-G)"
        >
          Discard
        </button>
      </div>
    </article>
  );
}
