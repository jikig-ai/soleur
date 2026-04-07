"use client";

import { useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { Badge } from "@/components/ui/badge";
import { GoldButton } from "@/components/ui/gold-button";
import { OutlinedButton } from "@/components/ui/outlined-button";
import { Card } from "@/components/ui/card";
import { serif } from "./fonts";

interface LinkGitHubStateProps {
  onBack: () => void;
  onSkip: () => void;
  initialError?: string | null;
}

export function LinkGitHubState({ onBack, onSkip, initialError }: LinkGitHubStateProps) {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(initialError ?? null);

  async function handleLinkGitHub() {
    setLoading(true);
    setError(null);

    // Set a cookie so the callback knows this was a link attempt
    // (query params get lost through the Supabase → GitHub → callback chain)
    document.cookie = "soleur_link_attempt=1; path=/; max-age=300; SameSite=Lax";

    const supabase = createClient();
    const { error: linkError } = await supabase.auth.linkIdentity({
      provider: "github",
      options: {
        redirectTo: `${window.location.origin}/callback`,
      },
    });

    if (linkError) {
      setLoading(false);
      setError(linkError.message);
    }
    // If no error, browser is redirecting to GitHub OAuth
  }

  return (
    <div className="mx-auto max-w-lg space-y-8">
      <div className="space-y-4 text-center">
        <Badge>ACCOUNT SETUP</Badge>
        <h1 className={`${serif.className} text-4xl font-semibold`}>
          Connect Your GitHub Account
        </h1>
        <p className="text-base text-neutral-400">
          Your Soleur account was created with email. To connect a project,
          we need to link your GitHub account so we can access your
          repositories.
        </p>
      </div>

      <Card>
        <h3 className="mb-4 text-sm font-medium text-neutral-200">
          What happens next
        </h3>
        <ol className="space-y-4">
          <li className="flex items-start gap-3">
            <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full border border-neutral-700 text-xs font-medium text-neutral-300">
              1
            </span>
            <span className="text-sm text-neutral-300">
              Sign in to GitHub to link your account
            </span>
          </li>
          <li className="flex items-start gap-3">
            <span className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full border border-neutral-700 text-xs font-medium text-neutral-300">
              2
            </span>
            <span className="text-sm text-neutral-300">
              Return here to select or create a project
            </span>
          </li>
        </ol>
      </Card>

      {error && (
        <Card className="border-red-900/50 bg-red-950/20">
          <p className="text-sm text-red-400">{error}</p>
          <p className="mt-2 text-xs text-neutral-500">
            If this GitHub account is already linked to another Soleur
            account, please sign in with that account instead.
          </p>
        </Card>
      )}

      <div className="flex items-center gap-3">
        <GoldButton onClick={handleLinkGitHub} disabled={loading}>
          {loading ? (
            "Redirecting..."
          ) : (
            "Link GitHub Account"
          )}
        </GoldButton>
        <OutlinedButton onClick={onBack}>Go Back</OutlinedButton>
        <button
          onClick={onSkip}
          className="text-sm text-neutral-500 transition-colors hover:text-neutral-300"
        >
          Skip
        </button>
      </div>
    </div>
  );
}
