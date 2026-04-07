"use client";

import { Badge } from "@/components/ui/badge";
import { GoldButton } from "@/components/ui/gold-button";
import { OutlinedButton } from "@/components/ui/outlined-button";
import { Card } from "@/components/ui/card";
import { serif } from "./fonts";

interface GitHubResolveStateProps {
  onContinue: () => void;
  onBack: () => void;
}

export function GitHubResolveState({ onContinue, onBack }: GitHubResolveStateProps) {
  return (
    <div className="mx-auto max-w-lg space-y-8">
      <div className="space-y-4 text-center">
        <Badge>QUICK SETUP</Badge>
        <h1 className={`${serif.className} text-4xl font-semibold`}>
          Connect to GitHub
        </h1>
        <p className="text-base text-neutral-400">
          Your Soleur account was created with email. A quick GitHub sign-in
          lets us find the app installation on your account and connect your
          project.
        </p>
      </div>

      <Card>
        <h3 className="mb-4 text-sm font-medium text-neutral-200">What happens next</h3>
        <ol className="space-y-4">
          <li className="flex items-start gap-3">
            <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full border border-neutral-700 text-xs font-medium text-neutral-300">
              1
            </span>
            <span className="text-sm text-neutral-300">Sign in to GitHub (quick authorization)</span>
          </li>
          <li className="flex items-start gap-3">
            <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full border border-neutral-700 text-xs font-medium text-neutral-300">
              2
            </span>
            <span className="text-sm text-neutral-300">Return here to connect your project</span>
          </li>
        </ol>
      </Card>

      <div className="flex items-center gap-3">
        <GoldButton onClick={onContinue}>Continue with GitHub</GoldButton>
        <OutlinedButton onClick={onBack}>Go Back</OutlinedButton>
      </div>
    </div>
  );
}
