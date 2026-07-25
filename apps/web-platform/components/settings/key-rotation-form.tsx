"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

interface KeyRotationFormProps {
  hasExistingKey: boolean;
  /**
   * feat-operator-cc-oauth — when true, render the credential-type toggle
   * (API key vs Claude Code subscription OAuth token). Server-surfaced from
   * `settings/page.tsx`: true ONLY when the caller is an operator/internal
   * account AND the `CC_OAUTH_ENABLED` kill-switch is on. The toggle is a
   * convenience; the authoritative authorization fence is the server-side
   * check in `/api/keys` (AC5/AC8) — never UI hiding.
   */
  canUseOauthCredential?: boolean;
}

type CredentialType = "api_key" | "oauth_token";

export function KeyRotationForm({
  hasExistingKey,
  canUseOauthCredential = false,
}: KeyRotationFormProps) {
  const router = useRouter();
  const [apiKey, setApiKey] = useState("");
  const [credentialType, setCredentialType] = useState<CredentialType>("api_key");
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState(false);

  const isOauth = canUseOauthCredential && credentialType === "oauth_token";

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!apiKey.trim()) return;

    setIsSubmitting(true);
    setError(null);
    setSuccess(false);

    try {
      const res = await fetch("/api/keys", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        // Only send credential_type when the operator toggle is active; the
        // route defaults to 'api_key' when the field is absent (back-compat).
        body: JSON.stringify(
          isOauth ? { key: apiKey, credential_type: "oauth_token" } : { key: apiKey },
        ),
      });

      const data = await res.json();

      if (!res.ok) {
        setError(data.error || "Failed to save key");
        setIsSubmitting(false);
        return;
      }

      if (!data.valid) {
        setError("Invalid API key. Please check and try again.");
        setIsSubmitting(false);
        return;
      }

      setSuccess(true);
      setApiKey("");
      setIsSubmitting(false);
      router.refresh();
    } catch {
      setError("Network error. Please try again.");
      setIsSubmitting(false);
    }
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      {canUseOauthCredential && (
        <div>
          <span className="mb-2 block text-sm text-soleur-text-secondary">
            Credential type
          </span>
          <div className="flex gap-2" role="radiogroup" aria-label="Credential type">
            <button
              type="button"
              role="radio"
              aria-checked={credentialType === "api_key"}
              onClick={() => setCredentialType("api_key")}
              className={`rounded-lg border px-3 py-1.5 text-sm transition-colors ${
                credentialType === "api_key"
                  ? "border-soleur-border-emphasized bg-soleur-bg-surface-2 text-soleur-text-primary"
                  : "border-soleur-border-default bg-soleur-bg-surface-1 text-soleur-text-secondary"
              }`}
            >
              API key
            </button>
            <button
              type="button"
              role="radio"
              aria-checked={credentialType === "oauth_token"}
              onClick={() => setCredentialType("oauth_token")}
              className={`rounded-lg border px-3 py-1.5 text-sm transition-colors ${
                credentialType === "oauth_token"
                  ? "border-soleur-border-emphasized bg-soleur-bg-surface-2 text-soleur-text-primary"
                  : "border-soleur-border-default bg-soleur-bg-surface-1 text-soleur-text-secondary"
              }`}
            >
              Subscription token
            </button>
          </div>
        </div>
      )}

      <div>
        <label htmlFor="api-key-input" className="mb-2 block text-sm text-soleur-text-secondary">
          {isOauth ? "Claude Code subscription token" : "Anthropic API Key"}
        </label>
        <input
          id="api-key-input"
          type="password"
          value={apiKey}
          onChange={(e) => setApiKey(e.target.value)}
          placeholder={isOauth ? "sk-ant-oat..." : "sk-ant-..."}
          className="w-full rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 px-3 py-2 text-base text-soleur-text-primary placeholder:text-soleur-text-muted focus:border-soleur-border-emphasized focus:outline-none focus:ring-1 focus:ring-soleur-border-emphasized md:text-sm"
          autoComplete="off"
        />
        {isOauth && (
          <p className="mt-2 text-xs text-soleur-text-muted">
            Generate with{" "}
            <code className="rounded bg-soleur-bg-surface-2 px-1 py-0.5 font-mono">
              claude setup-token
            </code>{" "}
            on your own Claude subscription. Funds only your own runs.
          </p>
        )}
      </div>

      {error && (
        <p role="alert" className="text-sm text-red-400">{error}</p>
      )}

      {success && (
        <p className="text-sm text-green-400">Key saved successfully.</p>
      )}

      <button
        type="submit"
        disabled={!apiKey.trim() || isSubmitting}
        className="rounded-lg bg-soleur-accent-gold-fill px-4 py-2 text-sm font-medium text-soleur-text-on-accent transition-colors hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-50"
      >
        {isSubmitting
          ? "Validating..."
          : hasExistingKey
            ? "Rotate Key"
            : "Save Key"}
      </button>
    </form>
  );
}
