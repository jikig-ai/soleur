"use client";

import { AlertTriangleIcon } from "@/components/icons";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";

interface InterruptedStateProps {
  onResume: () => void;
  onStartOver: () => void;
  /** feat-ui-action-feedback: Resume triggers an external OAuth hard nav. */
  navPending?: boolean;
}

export function InterruptedState({ onResume, onStartOver, navPending }: InterruptedStateProps) {
  return (
    <div className="mx-auto max-w-lg space-y-8 text-center">
      <div className="mx-auto flex h-16 w-16 items-center justify-center rounded-full bg-amber-500/10">
        <AlertTriangleIcon className="h-8 w-8 text-amber-400" />
      </div>

      <div className="space-y-3">
        <h1 className="text-4xl font-semibold">
          Setup Was Interrupted
        </h1>
        <p className="text-base text-soleur-text-secondary">
          It looks like the GitHub authorization process was not completed. This
          can happen if the browser was closed or the connection was lost.
        </p>
      </div>

      <Card className="text-left">
        <p className="text-sm text-soleur-text-secondary">
          No changes were made to your GitHub account. You can resume the
          connection process right where you left off, or start over from the
          beginning.
        </p>
      </Card>

      <div className="flex items-center justify-center gap-3">
        <Button variant="gold" type="button" onClick={onResume} disabled={navPending} loading={navPending} loadingLabel="Resume on GitHub">Resume on GitHub</Button>
        <Button variant="outlined" type="button" onClick={onStartOver} disabled={navPending}>Start Over</Button>
      </div>
    </div>
  );
}
