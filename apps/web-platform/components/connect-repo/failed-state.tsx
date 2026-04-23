"use client";

import { XCircleIcon } from "@/components/icons";
import { GoldButton } from "@/components/ui/gold-button";
import { OutlinedButton } from "@/components/ui/outlined-button";
import { Card } from "@/components/ui/card";
import { serif } from "./fonts";
import type { GitErrorCode } from "@/server/git-auth";

interface FailedStateProps {
  onRetry: () => void;
  errorMessage?: string | null;
  errorCode?: GitErrorCode | string | null;
}

type ErrorCopy = {
  headline: string;
  body: string;
  steps: string[];
  primaryCta: { label: string; action: "retry" | "reinstall" | "choose" };
};

// Partial because CLONE_UNKNOWN intentionally falls through to the
// generic copy (same shape as legacy plain-stderr rows).
const ERROR_COPY: Partial<Record<GitErrorCode, ErrorCopy>> = {
  REPO_ACCESS_REVOKED: {
    headline: "Soleur no longer has access",
    body: "The Soleur GitHub App no longer has access to this repository. Reinstall the app and try again.",
    steps: [
      "Reinstall the Soleur GitHub App on the repository's owner.",
      "Make sure the app has access to this repository.",
      "Return here and click Try Again.",
    ],
    primaryCta: { label: "Reinstall GitHub App", action: "reinstall" },
  },
  REPO_NOT_FOUND: {
    headline: "Repository not found",
    body: "We could not find this repository. It may have been deleted, renamed, or made private without granting Soleur access.",
    steps: [
      "Choose a different repository to connect.",
      "If this repo still exists, make sure the Soleur GitHub App has access to it.",
    ],
    primaryCta: { label: "Choose a different repository", action: "choose" },
  },
  AUTH_FAILED: {
    headline: "Authentication failed",
    body: "We could not authenticate with GitHub for this repository. Reinstalling the Soleur GitHub App usually resolves this.",
    steps: [
      "Reinstall the Soleur GitHub App.",
      "Return here and click Try Again.",
    ],
    primaryCta: { label: "Reinstall GitHub App", action: "reinstall" },
  },
  CLONE_TIMEOUT: {
    headline: "Repository clone timed out",
    body: "The clone took longer than expected. Large repositories sometimes need a second attempt.",
    steps: [
      "Click Try Again — transient timeouts usually resolve on retry.",
      "If it persists, contact support with the time of the error.",
    ],
    primaryCta: { label: "Try Again", action: "retry" },
  },
  CLONE_NETWORK_ERROR: {
    headline: "Network error during clone",
    body: "We could not reach GitHub to fetch your repository. This is usually a transient issue.",
    steps: [
      "Check GitHub's status page for ongoing incidents.",
      "Click Try Again.",
    ],
    primaryCta: { label: "Try Again", action: "retry" },
  },
};

export function FailedState({ onRetry, errorMessage, errorCode }: FailedStateProps) {
  const copy =
    errorCode && errorCode in ERROR_COPY
      ? ERROR_COPY[errorCode as GitErrorCode]
      : undefined;

  const handlePrimary = () => {
    if (!copy || copy.primaryCta.action === "retry") {
      onRetry();
      return;
    }
    if (copy.primaryCta.action === "reinstall") {
      window.location.href = "/api/repo/install";
      return;
    }
    // "choose" — the parent page owns repo selection; onRetry takes the
    // user back to the choose step.
    onRetry();
  };

  return (
    <div className="mx-auto max-w-lg space-y-8 text-center">
      <div className="mx-auto flex h-16 w-16 items-center justify-center rounded-full bg-red-500/10">
        <XCircleIcon className="h-8 w-8 text-red-400" />
      </div>

      <div className="space-y-3">
        <h1 className={`${serif.className} text-4xl font-semibold`}>
          {copy?.headline ?? "Project Setup Failed"}
        </h1>
        <p className="text-base text-neutral-400">
          {copy?.body ??
            "Something went wrong while setting up your project. This is usually a temporary issue."}
        </p>
      </div>

      {errorMessage && (
        <Card className="text-left">
          <details>
            <summary className="cursor-pointer text-sm font-medium text-neutral-200">
              Error details (for support)
            </summary>
            <p className="mt-2 text-sm text-neutral-400 font-mono break-all">
              {errorMessage}
            </p>
          </details>
        </Card>
      )}

      <Card className="text-left">
        <h3 className="mb-3 text-sm font-medium text-neutral-200">What you can do</h3>
        <ol className="space-y-3">
          {(copy?.steps ?? [
            "Try again — most issues resolve on a second attempt.",
            "Check GitHub's status page for ongoing incidents.",
            "If the problem persists, contact support with the time of the error.",
          ]).map((step, i) => (
            <li key={i} className="flex items-start gap-3">
              <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full border border-neutral-700 text-xs font-medium text-neutral-300">
                {i + 1}
              </span>
              <span className="text-sm text-neutral-400">{step}</span>
            </li>
          ))}
        </ol>
      </Card>

      <div className="flex items-center justify-center gap-3">
        <GoldButton onClick={handlePrimary}>
          {copy?.primaryCta.label ?? "Try Again"}
        </GoldButton>
        <OutlinedButton
          onClick={() => window.open("https://www.githubstatus.com", "_blank")}
        >
          GitHub Status Page
        </OutlinedButton>
      </div>
    </div>
  );
}
