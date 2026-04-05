"use client";

import { XCircleIcon } from "@/components/icons";
import { GoldButton } from "@/components/ui/gold-button";
import { OutlinedButton } from "@/components/ui/outlined-button";
import { Card } from "@/components/ui/card";
import { serif } from "./fonts";

interface FailedStateProps {
  onRetry: () => void;
  errorMessage?: string | null;
}

export function FailedState({ onRetry, errorMessage }: FailedStateProps) {
  return (
    <div className="mx-auto max-w-lg space-y-8 text-center">
      <div className="mx-auto flex h-16 w-16 items-center justify-center rounded-full bg-red-500/10">
        <XCircleIcon className="h-8 w-8 text-red-400" />
      </div>

      <div className="space-y-3">
        <h1 className={`${serif.className} text-4xl font-semibold`}>
          Project Setup Failed
        </h1>
        <p className="text-base text-neutral-400">
          Something went wrong while setting up your project. This is usually a
          temporary issue.
        </p>
      </div>

      {errorMessage && (
        <Card className="text-left">
          <h3 className="mb-2 text-sm font-medium text-neutral-200">Error details</h3>
          <p className="text-sm text-neutral-400 font-mono break-all">{errorMessage}</p>
        </Card>
      )}

      <Card className="text-left">
        <h3 className="mb-3 text-sm font-medium text-neutral-200">What you can do</h3>
        <ol className="space-y-3">
          <li className="flex items-start gap-3">
            <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full border border-neutral-700 text-xs font-medium text-neutral-300">
              1
            </span>
            <span className="text-sm text-neutral-400">
              Try again — most issues resolve on a second attempt.
            </span>
          </li>
          <li className="flex items-start gap-3">
            <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full border border-neutral-700 text-xs font-medium text-neutral-300">
              2
            </span>
            <span className="text-sm text-neutral-400">
              Check GitHub&apos;s status page for ongoing incidents.
            </span>
          </li>
          <li className="flex items-start gap-3">
            <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full border border-neutral-700 text-xs font-medium text-neutral-300">
              3
            </span>
            <span className="text-sm text-neutral-400">
              If the problem persists, contact support with the time of the error.
            </span>
          </li>
        </ol>
      </Card>

      <div className="flex items-center justify-center gap-3">
        <GoldButton onClick={onRetry}>Try Again</GoldButton>
        <OutlinedButton
          onClick={() => window.open("https://www.githubstatus.com", "_blank")}
        >
          GitHub Status Page
        </OutlinedButton>
      </div>
    </div>
  );
}
