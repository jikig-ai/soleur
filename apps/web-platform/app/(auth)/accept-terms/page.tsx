"use client";

import { useState } from "react";
import { useRouter, useSearchParams } from "next/navigation";

export default function AcceptTermsPage() {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [accepted, setAccepted] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  // Middleware redirects here with `?error=db_unavailable` when the
  // T&C-version SELECT fails open-DB-side (fail-closed redirect). Surface
  // the outage so the user has a non-form explanation; the form remains
  // usable in case the outage cleared between redirect and render.
  const middlewareError = searchParams?.get("error");
  const outageBanner =
    middlewareError === "db_unavailable"
      ? "We're having trouble verifying your account. Please try again in a moment — if the problem persists, we've been alerted."
      : "";

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    setError("");

    try {
      const res = await fetch("/api/accept-terms", { method: "POST" });

      if (!res.ok) {
        const body = await res.json().catch(() => ({}));
        setError(body.error || "Something went wrong. Please try again.");
        return;
      }

      const { redirect } = await res.json();
      router.push(redirect || "/setup-key");
    } catch {
      setError("Network error. Please check your connection and try again.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <main className="flex min-h-screen items-center justify-center p-4">
      <div className="w-full max-w-sm space-y-6">
        <div className="space-y-2 text-center">
          <h1 className="text-2xl font-semibold">Accept Terms & Conditions</h1>
          <p className="text-sm text-soleur-text-secondary">
            To continue using Soleur, please review and accept our terms.
          </p>
        </div>

        {outageBanner && (
          <div
            role="status"
            aria-live="polite"
            className="rounded-lg border border-yellow-500/40 bg-yellow-500/10 p-3 text-sm text-yellow-200"
          >
            {outageBanner}
          </div>
        )}

        {/* Art. 13(3) GDPR — informs returning users of the substantive */}
        {/* change introduced in TC_VERSION 2.2.0 before re-acceptance.   */}
        {/* Rendered unconditionally because /accept-terms is only        */}
        {/* reached when the middleware detected a version mismatch       */}
        {/* (server side, via Supabase tc_accepted_version SELECT).       */}
        <div
          role="status"
          aria-live="polite"
          data-testid="tc-version-update-banner"
          className="rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 p-3 text-sm text-soleur-text-secondary"
        >
          <p className="font-medium text-soleur-text-primary">
            Updated May 22, 2026
          </p>
          <p className="mt-1">
            We&apos;ve added a new{" "}
            <strong>§Workspace Members</strong> section governing the
            team-workspace feature.{" "}
            <a
              href="https://soleur.ai/pages/legal/terms-and-conditions.html"
              target="_blank"
              rel="noopener noreferrer"
              className="text-soleur-text-link underline-offset-2 hover:underline"
            >
              Read the full Terms
            </a>
            .
          </p>
        </div>

        <form onSubmit={handleSubmit} className="space-y-4">
          <label className="flex items-start gap-3 text-sm text-soleur-text-secondary">
            <input
              type="checkbox"
              required
              checked={accepted}
              onChange={(e) => setAccepted(e.target.checked)}
              className="mt-0.5 h-4 w-4 rounded border-soleur-border-default bg-soleur-bg-surface-1"
            />
            <span>
              I agree to the{" "}
              <a
                href="https://soleur.ai/pages/legal/terms-and-conditions.html"
                target="_blank"
                rel="noopener noreferrer"
                className="text-soleur-text-primary underline hover:text-soleur-text-secondary"
              >
                Terms &amp; Conditions
              </a>{" "}
              and{" "}
              <a
                href="https://soleur.ai/pages/legal/privacy-policy.html"
                target="_blank"
                rel="noopener noreferrer"
                className="text-soleur-text-primary underline hover:text-soleur-text-secondary"
              >
                Privacy Policy
              </a>
            </span>
          </label>

          {error && <p role="alert" className="text-sm text-red-400">{error}</p>}

          <button
            type="submit"
            disabled={loading || !accepted}
            className="w-full rounded-lg bg-soleur-accent-gold-fill px-4 py-3 text-sm font-medium text-soleur-text-on-accent hover:opacity-90 disabled:opacity-50"
          >
            {loading ? "Saving..." : "Accept and continue"}
          </button>
        </form>
      </div>
    </main>
  );
}
