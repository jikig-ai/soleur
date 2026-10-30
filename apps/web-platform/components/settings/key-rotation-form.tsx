"use client";

import { useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";
import { usePendingAction } from "@/hooks/use-pending-action";
import type { CredentialBasis } from "@/lib/credential-basis";
import { RemoveSubscriptionTokenDialog } from "./remove-subscription-token-dialog";

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
  /**
   * #11524 — `describeCredentialBasis(...)` for the stored subscription token,
   * computed once by `SettingsContent` (null iff no token is stored). Drives
   * the removal control and its confirm-copy variant; an inert stored token
   * never gets a billing claim.
   */
  basis?: CredentialBasis | null;
}

type CredentialType = "api_key" | "oauth_token";

export function KeyRotationForm({
  hasExistingKey,
  canUseOauthCredential = false,
  basis = null,
}: KeyRotationFormProps) {
  const router = useRouter();
  const [apiKey, setApiKey] = useState("");
  const [credentialType, setCredentialType] = useState<CredentialType>("api_key");
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState(false);
  // #11524: post-removal notice. Owned here (not by the dialog) because the
  // dialog unmounts when router.refresh() makes `basis` null.
  const [removedNotice, setRemovedNotice] = useState<CredentialBasis | null>(
    null,
  );
  const noticeRef = useRef<HTMLParagraphElement>(null);

  // Focus after a successful removal: the API-key input when the account now
  // has no sign-in (variant B), otherwise the notice region. The add-key
  // input's typed text is untouched.
  useEffect(() => {
    if (!removedNotice) return;
    if (removedNotice.variant === "B") {
      document.getElementById("api-key-input")?.focus();
    } else {
      noticeRef.current?.focus();
    }
  }, [removedNotice]);

  function handleAddApiKey() {
    setCredentialType("api_key");
    document.getElementById("api-key-input")?.focus();
  }

  const isOauth = canUseOauthCredential && credentialType === "oauth_token";

  // asyncFn never throws: failures land on the local `error` surface.
  const { run, pending: isSubmitting } = usePendingAction(async () => {
    if (!apiKey.trim()) return;

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
        return;
      }

      if (!data.valid) {
        setError("Invalid API key. Please check and try again.");
        return;
      }

      setSuccess(true);
      // The saved key supersedes the post-removal "add an API key" notice.
      setRemovedNotice(null);
      setApiKey("");
      router.refresh();
    } catch {
      setError("Network error. Please try again.");
    }
  });

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    run();
  }

  return (
    <>
    {removedNotice && (
      <p
        ref={noticeRef}
        role="status"
        aria-live="polite"
        tabIndex={-1}
        className="mb-4 rounded-lg border border-green-500/60 px-4 py-3 text-sm text-green-400 focus:outline-none"
      >
        {removedNotice.notice}
      </p>
    )}
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
              data-button-exempt="role=radio option in a radiogroup — checked/unchecked state styling (border-emphasized + bg-surface-2) cannot reduce to a Button variant"
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
              data-button-exempt="role=radio option in a radiogroup — checked/unchecked state styling (border-emphasized + bg-surface-2) cannot reduce to a Button variant"
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

      <Button
        variant="gold"
        type="submit"
        disabled={!apiKey.trim() || isSubmitting}
        loading={isSubmitting}
        loadingLabel="Validating"
      >
        {hasExistingKey ? "Rotate Key" : "Save Key"}
      </Button>
    </form>
    {basis && (
      <RemoveSubscriptionTokenDialog
        basis={basis}
        onRemoved={setRemovedNotice}
        onAddApiKey={handleAddApiKey}
      />
    )}
    </>
  );
}
