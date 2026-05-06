"use client";

import { ShieldIcon } from "@/components/icons";
import { Badge } from "@/components/ui/badge";
import { GoldButton } from "@/components/ui/gold-button";
import { OutlinedButton } from "@/components/ui/outlined-button";
import { Card } from "@/components/ui/card";
import { serif } from "./fonts";

interface GitHubRedirectStateProps {
  onContinue: () => void;
  onBack: () => void;
}

export function GitHubRedirectState({ onContinue, onBack }: GitHubRedirectStateProps) {
  return (
    <div className="mx-auto max-w-lg space-y-8">
      <div className="space-y-4 text-center">
        <Badge>SECURE CONNECTION</Badge>
        <h1 className={`${serif.className} text-4xl font-semibold`}>
          Connecting to GitHub
        </h1>
        <p className="text-base text-soleur-text-secondary">
          GitHub is a trusted platform used by millions of developers and
          businesses to manage their projects securely.
        </p>
      </div>

      <Card>
        <h3 className="mb-4 text-sm font-medium text-soleur-text-primary">What happens next</h3>
        <ol className="space-y-4">
          <li className="flex items-start gap-3">
            <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full border border-soleur-border-default text-xs font-medium text-soleur-text-secondary">
              1
            </span>
            <span className="text-sm text-soleur-text-secondary">Sign in to GitHub</span>
          </li>
          <li className="flex items-start gap-3">
            <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full border border-soleur-border-default text-xs font-medium text-soleur-text-secondary">
              2
            </span>
            <div>
              <span className="text-sm text-soleur-text-secondary">Grant project access</span>
              <p className="mt-0.5 text-xs text-soleur-text-muted">
                We only request permission to read and manage your project files — nothing else.
              </p>
            </div>
          </li>
          <li className="flex items-start gap-3">
            <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full border border-soleur-border-default text-xs font-medium text-soleur-text-secondary">
              3
            </span>
            <span className="text-sm text-soleur-text-secondary">Return here automatically</span>
          </li>
        </ol>
      </Card>

      <Card className="flex items-start gap-3">
        <ShieldIcon className="mt-0.5 h-5 w-5 shrink-0 text-soleur-accent-gold-fg/70" />
        <div>
          <h3 className="text-sm font-medium text-soleur-text-primary">
            Why your own GitHub account?
          </h3>
          <p className="mt-1 text-xs text-soleur-text-muted">
            Your project stays in your GitHub account, under your control. Your
            AI team accesses it through a secure GitHub App installation — you
            can revoke access at any time from your GitHub settings.
          </p>
        </div>
      </Card>

      <div className="flex items-center gap-3">
        <GoldButton onClick={onContinue}>Continue to GitHub</GoldButton>
        <OutlinedButton onClick={onBack}>Go Back</OutlinedButton>
      </div>
    </div>
  );
}
