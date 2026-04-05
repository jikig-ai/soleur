"use client";

import { CheckCircleIcon } from "@/components/icons";
import { GoldButton } from "@/components/ui/gold-button";
import { Card } from "@/components/ui/card";
import { serif } from "./fonts";

interface ReadyStateProps {
  repoName: string;
  onContinue: () => void;
}

export function ReadyState({ repoName, onContinue }: ReadyStateProps) {
  return (
    <div className="mx-auto max-w-lg space-y-8 text-center">
      <div className="mx-auto flex h-16 w-16 items-center justify-center rounded-full bg-green-500/10">
        <CheckCircleIcon className="h-8 w-8 text-green-400" />
      </div>

      <div className="space-y-3">
        <h1 className={`${serif.className} text-4xl font-semibold`}>
          Your AI Team Is Ready.
        </h1>
        <p className="text-base text-neutral-400">
          Your AI team. Your project. Full context from the first conversation.
        </p>
      </div>

      <Card className="mx-auto inline-block text-left">
        <div className="space-y-3">
          <div className="flex items-center justify-between gap-8">
            <span className="text-sm text-neutral-500">Project</span>
            <span className="text-sm font-medium text-neutral-100">{repoName}</span>
          </div>
          <div className="flex items-center justify-between gap-8">
            <span className="text-sm text-neutral-500">Agents</span>
            <span className="text-sm font-medium text-green-400">{process.env.NEXT_PUBLIC_AGENT_COUNT || "60+"} ready</span>
          </div>
        </div>
      </Card>

      <p className="text-sm text-neutral-500">
        You are always the decision-maker. Your AI team proposes — you approve.
      </p>

      <GoldButton onClick={onContinue}>Open Dashboard</GoldButton>
    </div>
  );
}
