"use client";

import { useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { reportSilentFallback } from "@/lib/client-observability";
import { mapSupabaseError } from "@/lib/auth/error-messages";

type Provider = "google" | "apple" | "github" | "azure";

interface ProviderConfig {
  id: Provider;
  label: string;
  icon: React.ReactNode;
  scopes?: string;
}

const PROVIDERS: ProviderConfig[] = [
  {
    id: "google",
    label: "Google",
    icon: (
      <svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true">
        <path d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92a5.06 5.06 0 0 1-2.2 3.32v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.1z" fill="#4285F4" />
        <path d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" fill="#34A853" />
        <path d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18A10.96 10.96 0 0 0 1 12c0 1.77.42 3.45 1.18 4.93l3.66-2.84z" fill="#FBBC05" />
        <path d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" fill="#EA4335" />
      </svg>
    ),
  },
  {
    id: "apple",
    label: "Apple",
    icon: (
      <svg viewBox="0 0 24 24" width="20" height="20" fill="currentColor" aria-hidden="true">
        <path d="M17.05 20.28c-.98.95-2.05.88-3.08.4-1.09-.5-2.08-.48-3.24 0-1.44.62-2.2.44-3.06-.4C2.79 15.25 3.51 7.59 9.05 7.31c1.35.07 2.29.74 3.08.8 1.18-.24 2.31-.93 3.57-.84 1.51.12 2.65.72 3.4 1.8-3.12 1.87-2.38 5.98.48 7.13-.57 1.5-1.31 2.99-2.54 4.09zM12.03 7.25c-.15-2.23 1.66-4.07 3.74-4.25.29 2.58-2.34 4.5-3.74 4.25z" />
      </svg>
    ),
  },
  {
    id: "github",
    label: "GitHub",
    icon: (
      <svg viewBox="0 0 24 24" width="20" height="20" fill="currentColor" aria-hidden="true">
        <path d="M12 2C6.477 2 2 6.484 2 12.017c0 4.425 2.865 8.18 6.839 9.504.5.092.682-.217.682-.483 0-.237-.008-.868-.013-1.703-2.782.605-3.369-1.343-3.369-1.343-.454-1.158-1.11-1.466-1.11-1.466-.908-.62.069-.608.069-.608 1.003.07 1.531 1.032 1.531 1.032.892 1.53 2.341 1.088 2.91.832.092-.647.35-1.088.636-1.338-2.22-.253-4.555-1.113-4.555-4.951 0-1.093.39-1.988 1.029-2.688-.103-.253-.446-1.272.098-2.65 0 0 .84-.27 2.75 1.026A9.564 9.564 0 0 1 12 6.844a9.59 9.59 0 0 1 2.504.338c1.909-1.296 2.747-1.027 2.747-1.027.546 1.379.202 2.398.1 2.651.64.7 1.028 1.595 1.028 2.688 0 3.848-2.339 4.695-4.566 4.943.359.309.678.92.678 1.855 0 1.338-.012 2.419-.012 2.747 0 .268.18.58.688.482A10.02 10.02 0 0 0 22 12.017C22 6.484 17.522 2 12 2z" />
      </svg>
    ),
  },
  {
    id: "azure",
    label: "Microsoft",
    icon: (
      <svg viewBox="0 0 24 24" width="20" height="20" aria-hidden="true">
        <rect x="1" y="1" width="10" height="10" fill="#F25022" />
        <rect x="13" y="1" width="10" height="10" fill="#7FBA00" />
        <rect x="1" y="13" width="10" height="10" fill="#00A4EF" />
        <rect x="13" y="13" width="10" height="10" fill="#FFB900" />
      </svg>
    ),
    scopes: "email profile openid",
  },
];

export function OAuthButtons({ disabled = false }: { disabled?: boolean }) {
  const [loading, setLoading] = useState<Provider | null>(null);
  const [error, setError] = useState("");

  async function handleOAuth(provider: ProviderConfig) {
    setLoading(provider.id);
    setError("");

    const supabase = createClient();
    const { error } = await supabase.auth.signInWithOAuth({
      provider: provider.id,
      options: {
        redirectTo: `${window.location.origin}/callback`,
        ...(provider.scopes && { scopes: provider.scopes }),
      },
    });

    if (error) {
      console.error("[auth] Supabase OAuth error:", error.message);
      // Forward only typed enum fields — error.message can embed the user's
      // email or other PII and Sentry is a shared project (cross-tenant
      // exposure vector). Provider tag distinguishes Google/Apple/GitHub/Azure.
      reportSilentFallback(error, {
        feature: "auth",
        op: "signInWithOAuth",
        extra: {
          provider: provider.id,
          errorCode: (error as { code?: string }).code,
          errorName: error.name,
        },
      });
      setError(mapSupabaseError(error.message));
      setLoading(null);
    }
    // On success, the browser redirects — no state cleanup needed
  }

  return (
    <div className="space-y-3">
      {PROVIDERS.map((provider) => (
        <button
          key={provider.id}
          type="button"
          onClick={() => handleOAuth(provider)}
          disabled={loading !== null || disabled}
          className="flex w-full items-center justify-center gap-3 rounded-lg border border-neutral-700 bg-neutral-900 px-4 py-3 text-sm font-medium text-white hover:bg-neutral-800 disabled:opacity-50"
        >
          {provider.icon}
          Continue with {provider.label}
        </button>
      ))}
      {error && <p role="alert" className="text-sm text-red-400">{error}</p>}
    </div>
  );
}
