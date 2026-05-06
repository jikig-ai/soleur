"use client";

import { AlertTriangleIcon } from "@/components/icons";
import { GoldButton } from "@/components/ui/gold-button";
import { OutlinedButton } from "@/components/ui/outlined-button";
import { Card } from "@/components/ui/card";
import { serif } from "./fonts";

interface InterruptedStateProps {
  onResume: () => void;
  onStartOver: () => void;
}

export function InterruptedState({ onResume, onStartOver }: InterruptedStateProps) {
  return (
    <div className="mx-auto max-w-lg space-y-8 text-center">
      <div className="mx-auto flex h-16 w-16 items-center justify-center rounded-full bg-amber-500/10">
        <AlertTriangleIcon className="h-8 w-8 text-amber-400" />
      </div>

      <div className="space-y-3">
        <h1 className={`${serif.className} text-4xl font-semibold`}>
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
        <GoldButton onClick={onResume}>Resume on GitHub</GoldButton>
        <OutlinedButton onClick={onStartOver}>Start Over</OutlinedButton>
      </div>
    </div>
  );
}
