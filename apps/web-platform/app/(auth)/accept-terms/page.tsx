"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

export default function AcceptTermsPage() {
  const router = useRouter();
  const [accepted, setAccepted] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

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
