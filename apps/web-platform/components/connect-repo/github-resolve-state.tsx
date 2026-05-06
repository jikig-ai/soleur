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
        <p className="text-base text-soleur-text-secondary">
          Your Soleur account was created with email. A quick GitHub sign-in
          lets us find the app installation on your account and connect your
          project.
        </p>
      </div>

      <Card>
        <h3 className="mb-4 text-sm font-medium text-soleur-text-primary">What happens next</h3>
        <ol className="space-y-4">
          <li className="flex items-start gap-3">
            <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full border border-soleur-border-default text-xs font-medium text-soleur-text-secondary">
              1
            </span>
            <span className="text-sm text-soleur-text-secondary">Sign in to GitHub (quick authorization)</span>
          </li>
          <li className="flex items-start gap-3">
            <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full border border-soleur-border-default text-xs font-medium text-soleur-text-secondary">
              2
            </span>
            <span className="text-sm text-soleur-text-secondary">Return here to connect your project</span>
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
