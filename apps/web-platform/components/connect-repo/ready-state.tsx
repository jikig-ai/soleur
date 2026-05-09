"use client";

import Link from "next/link";
import { CheckCircleIcon } from "@/components/icons";
import { GoldButton } from "@/components/ui/gold-button";
import { Card } from "@/components/ui/card";
import { serif } from "./fonts";
import type { ProjectHealthSnapshot } from "@/server/project-scanner";

interface ReadyStateProps {
  repoName: string;
  onContinue: () => void;
  onViewKb: () => void;
  healthSnapshot?: ProjectHealthSnapshot | null;
  /** When set, a sync conversation is actively running — show deep analysis status. */
  syncConversationId?: string | null;
}

const CATEGORY_LABELS: Record<ProjectHealthSnapshot["category"], string> = {
  strong: "Strong",
  developing: "Developing",
  "gaps-found": "Gaps Found",
};

const CATEGORY_COLORS: Record<ProjectHealthSnapshot["category"], string> = {
  strong: "bg-green-500/10 text-green-400",
  developing: "bg-amber-500/10 text-amber-400",
  "gaps-found": "bg-red-500/10 text-red-400",
};

export function ReadyState({
  repoName,
  onContinue,
  onViewKb,
  healthSnapshot,
  syncConversationId,
}: ReadyStateProps) {
  if (!healthSnapshot) {
    return (
      <div className="mx-auto max-w-lg space-y-8 text-center">
        <div className="mx-auto flex h-16 w-16 items-center justify-center rounded-full bg-green-500/10">
          <CheckCircleIcon className="h-8 w-8 text-green-400" />
        </div>

        <div className="space-y-3">
          <h1 className={`${serif.className} text-4xl font-semibold`}>
            Your AI Team Is Ready.
          </h1>
          <p className="text-base text-soleur-text-secondary">
            Your AI team. Your project. Full context from the first
            conversation.
          </p>
        </div>

        <Card className="mx-auto inline-block text-left">
          <div className="space-y-3">
            <div className="flex items-center justify-between gap-8">
              <span className="text-sm text-soleur-text-muted">Project</span>
              <span className="text-sm font-medium text-soleur-text-primary">
                {repoName}
              </span>
            </div>
            <div className="flex items-center justify-between gap-8">
              <span className="text-sm text-soleur-text-muted">Agents</span>
              <span className="text-sm font-medium text-green-400">
                {process.env.NEXT_PUBLIC_AGENT_COUNT || "60+"} ready
              </span>
            </div>
          </div>
        </Card>

        <p className="text-sm text-soleur-text-muted">
          You are always the decision-maker. Your AI team proposes — you
          approve.
        </p>

        <div className="flex flex-col items-center gap-3 sm:flex-row sm:justify-center">
          <GoldButton onClick={onContinue}>Open Dashboard</GoldButton>
          <button
            type="button"
            onClick={onViewKb}
            className="rounded-lg border border-soleur-border-default px-6 py-3 text-sm font-medium text-soleur-text-secondary transition-colors hover:border-soleur-text-muted hover:text-soleur-text-primary"
          >
            Review Knowledge Base
          </button>
        </div>
      </div>
    );
  }

  const categoryLabel = CATEGORY_LABELS[healthSnapshot.category];
  const categoryColor = CATEGORY_COLORS[healthSnapshot.category];

  return (
    <div className="mx-auto max-w-lg space-y-6 text-center">
      <div className="mx-auto flex h-16 w-16 items-center justify-center rounded-full bg-green-500/10">
        <CheckCircleIcon className="h-8 w-8 text-green-400" />
      </div>

      <div className="space-y-3">
        <h1 className={`${serif.className} text-3xl font-semibold`}>
          {repoName}
        </h1>
        <span
          className={`inline-block rounded-full px-3 py-1 text-xs font-medium ${categoryColor}`}
        >
          {categoryLabel}
        </span>
      </div>

      <Card className="mx-auto w-full text-left">
        <div className="space-y-4">
          {/* Detected signals */}
          <div data-testid="detected-signals">
            <h3 className="mb-2 text-xs font-medium uppercase tracking-wide text-soleur-text-muted">
              Detected
            </h3>
            <div className="flex flex-wrap gap-2">
              {healthSnapshot.signals.detected.map((signal) => (
                <span
                  key={signal.id}
                  className="inline-flex items-center gap-1.5 rounded-md bg-green-500/5 px-2 py-1 text-xs text-green-400"
                >
                  <span data-testid="signal-check">
                    <CheckCircleIcon className="h-3.5 w-3.5" />
                  </span>
                  {signal.label}
                </span>
              ))}
            </div>
          </div>

          {/* Missing signals */}
          {healthSnapshot.signals.missing.length > 0 && (
            <div data-testid="missing-signals">
              <h3 className="mb-2 text-xs font-medium uppercase tracking-wide text-soleur-text-muted">
                Missing
              </h3>
              <div className="flex flex-wrap gap-2">
                {healthSnapshot.signals.missing.map((signal) => (
                  <span
                    key={signal.id}
                    className="inline-flex items-center gap-1.5 rounded-md bg-amber-500/5 px-2 py-1 text-xs text-amber-400"
                  >
                    <span
                      className="h-1.5 w-1.5 rounded-full bg-amber-400"
                      data-testid="signal-missing"
                    />
                    {signal.label}
                  </span>
                ))}
              </div>
            </div>
          )}

          {/* Recommendations */}
          <div>
            <h3 className="mb-2 text-xs font-medium uppercase tracking-wide text-soleur-text-muted">
              Next Steps
            </h3>
            <ol className="space-y-2">
              {healthSnapshot.recommendations.map((rec, i) => (
                <li
                  key={i}
                  data-testid="recommendation-item"
                  className="flex gap-2 text-xs text-soleur-text-secondary"
                >
                  <span className="flex-shrink-0 font-medium text-soleur-text-muted">
                    {i + 1}.
                  </span>
                  {rec}
                </li>
              ))}
            </ol>
          </div>
        </div>
      </Card>

      {/* Deep analysis status — only shown when a sync conversation exists (#1816) */}
      {syncConversationId ? (
        <p className="text-xs text-soleur-text-muted">
          Deep analysis in progress —{" "}
          <Link
            href="/dashboard"
            className="text-soleur-accent-gold-fg underline underline-offset-2 hover:text-soleur-accent-gold-text"
          >
            View in Dashboard
          </Link>
        </p>
      ) : (
        <p className="text-xs text-soleur-text-muted">
          Your project is ready. Start a conversation to begin working with your AI team.
        </p>
      )}

      {/* CTAs */}
      <div className="flex items-center justify-center gap-3">
        <GoldButton onClick={onContinue}>Open Dashboard</GoldButton>
        <button
          type="button"
          onClick={onViewKb}
          className="rounded-lg border border-soleur-border-default px-6 py-3 text-sm font-medium text-soleur-text-secondary transition-colors hover:border-soleur-text-muted hover:text-soleur-text-primary"
        >
          Review Knowledge Base
        </button>
      </div>
    </div>
  );
}
