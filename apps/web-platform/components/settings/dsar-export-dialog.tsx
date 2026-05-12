"use client";

// Phase 8 UI: single-stage confirmation dialog for DSAR export.
//
// Plan rev-2 FR1 + S9 collapse: a single dialog with a <details>-style
// "What's included" disclosure (no two-stage flow). "Continue" -> POST
// the password (or trigger OAuth re-auth) -> on success, the parent
// kicks off the export POST.
//
// The dialog itself is pure UX. The reauth + enqueue side-effects live
// in the parent (dsar-export-job-list.tsx) so the dialog is reusable
// for re-issue flows.

import { useState } from "react";

interface DsarExportDialogProps {
  /**
   * Called when the user confirms with a password. Parent is
   * responsible for the reauth round-trip + enqueue POST.
   */
  onConfirmPassword: (password: string) => Promise<void>;
  /**
   * Called when the user chooses the OAuth re-auth path. Parent is
   * responsible for redirecting to supabase.auth.signInWithOAuth
   * with prompt=login + max_age=300.
   */
  onConfirmOAuth: () => void;
  /**
   * `true` when an active job exists for this user — disables the
   * trigger button per AC31.
   */
  hasActiveJob: boolean;
}

export function DsarExportDialog({
  onConfirmPassword,
  onConfirmOAuth,
  hasActiveJob,
}: DsarExportDialogProps) {
  const [isOpen, setIsOpen] = useState(false);
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleConfirm() {
    if (!password) return;
    setBusy(true);
    setError(null);
    try {
      await onConfirmPassword(password);
      setIsOpen(false);
      setPassword("");
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setBusy(false);
    }
  }

  if (!isOpen) {
    return (
      <button
        type="button"
        onClick={() => setIsOpen(true)}
        disabled={hasActiveJob}
        aria-disabled={hasActiveJob}
        className="rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 px-4 py-2 text-sm font-medium text-soleur-text-primary transition-colors hover:bg-soleur-bg-surface-2 disabled:cursor-not-allowed disabled:opacity-50"
      >
        Download my data
      </button>
    );
  }

  return (
    <div className="rounded-xl border border-soleur-border-default bg-soleur-bg-surface-1/50 p-6">
      <h3 className="mb-2 text-lg font-semibold text-soleur-text-primary">
        Download my data
      </h3>
      <p className="mb-4 text-sm text-soleur-text-secondary">
        We&apos;ll prepare a ZIP archive of your account data under GDPR Articles 15
        (right of access) and 20 (data portability). The bundle is delivered by
        email; the download link is single-use and expires in 7 days.
      </p>

      <details className="mb-4 rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 p-3">
        <summary className="cursor-pointer text-sm font-medium text-soleur-text-primary">
          What&apos;s included
        </summary>
        <ul className="mt-3 space-y-1 text-sm text-soleur-text-secondary">
          <li>• Your account profile (email, settings)</li>
          <li>• Your conversations, messages, and attachments</li>
          <li>• Knowledge-base share links and team/agent names</li>
          <li>• BYOK encrypted credentials (base64 in JSON)</li>
          <li>• BYOK usage audit log</li>
          <li>• Workspace files (your /workspaces/&lt;you&gt; directory)</li>
        </ul>
        <p className="mt-3 text-sm text-soleur-text-secondary">
          Excluded: operational/security telemetry (revocation lists, rate-limit
          counters, push-subscription tokens) — see /privacy-policy §4.7.
        </p>
      </details>

      <p className="mb-2 text-sm text-soleur-text-secondary">
        For your security, please re-authenticate before we package your data.
      </p>

      <label htmlFor="dsar-password" className="mb-2 block text-sm text-soleur-text-secondary">
        Confirm your password
      </label>
      <input
        id="dsar-password"
        type="password"
        value={password}
        onChange={(e) => setPassword(e.target.value)}
        placeholder="••••••••"
        autoComplete="current-password"
        className="mb-4 w-full rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 px-3 py-2 text-sm text-soleur-text-primary placeholder:text-soleur-text-muted focus:border-soleur-border-focus focus:outline-none focus:ring-1 focus:ring-soleur-border-focus"
      />

      {error && (
        <p
          role="alert"
          className="mb-3 rounded-md border border-red-800/50 bg-red-950/30 px-3 py-2 text-sm text-red-300"
        >
          {error}
        </p>
      )}

      <div className="flex flex-wrap gap-3">
        <button
          type="button"
          onClick={handleConfirm}
          disabled={busy || password.length === 0}
          className="rounded-lg bg-soleur-button-primary px-4 py-2 text-sm font-medium text-soleur-text-primary transition-colors hover:bg-soleur-button-primary-hover disabled:cursor-not-allowed disabled:opacity-50"
        >
          {busy ? "Preparing…" : "Continue"}
        </button>
        <button
          type="button"
          onClick={onConfirmOAuth}
          disabled={busy}
          className="rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 px-4 py-2 text-sm text-soleur-text-secondary transition-colors hover:bg-soleur-bg-surface-2 disabled:cursor-not-allowed disabled:opacity-50"
        >
          Re-authenticate with SSO
        </button>
        <button
          type="button"
          onClick={() => {
            setIsOpen(false);
            setPassword("");
            setError(null);
          }}
          disabled={busy}
          className="rounded-lg px-4 py-2 text-sm text-soleur-text-secondary transition-colors hover:text-soleur-text-primary disabled:cursor-not-allowed disabled:opacity-50"
        >
          Cancel
        </button>
      </div>

      <p className="mt-4 text-xs text-soleur-text-muted">
        Once requested, you&apos;ll receive an email at your registered address
        when the bundle is ready (usually within a few minutes; up to 48h for
        large accounts).
      </p>
    </div>
  );
}
