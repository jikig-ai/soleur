"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";

type SubscriptionStatus = "active" | "cancelled" | null;

export default function BillingPage() {
  const [status, setStatus] = useState<SubscriptionStatus>(null);
  const [loading, setLoading] = useState(true);
  const [checkoutLoading, setCheckoutLoading] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => {
    async function fetchStatus() {
      const supabase = createClient();
      const {
        data: { user },
      } = await supabase.auth.getUser();

      if (user) {
        const { data } = await supabase
          .from("users")
          .select("subscription_status")
          .eq("id", user.id)
          .single();

        setStatus(data?.subscription_status ?? null);
      }
      setLoading(false);
    }

    fetchStatus();
  }, []);

  async function handleSubscribe() {
    setCheckoutLoading(true);
    setError("");

    try {
      const res = await fetch("/api/checkout", { method: "POST" });
      const data = await res.json();

      if (!res.ok) {
        setError(data.error || "Failed to create checkout session");
        return;
      }

      if (data.url) {
        window.location.href = data.url;
      }
    } catch {
      setError("Something went wrong. Please try again.");
    } finally {
      setCheckoutLoading(false);
    }
  }

  if (loading) {
    return (
      <main className="flex min-h-screen items-center justify-center p-4">
        <p className="text-neutral-400">Loading billing info...</p>
      </main>
    );
  }

  return (
    <main className="flex min-h-screen items-center justify-center p-4">
      <div className="w-full max-w-md space-y-6">
        <div className="space-y-2">
          <h1 className="text-2xl font-semibold">Billing</h1>
          <p className="text-sm text-neutral-400">
            Manage your Soleur subscription
          </p>
        </div>

        <div className="rounded-lg border border-neutral-700 bg-neutral-900 p-6 space-y-4">
          <div className="flex items-center justify-between">
            <span className="text-sm text-neutral-400">Subscription</span>
            {status === "active" ? (
              <span className="rounded-full bg-green-900/50 px-3 py-1 text-xs font-medium text-green-400 border border-green-800">
                Active
              </span>
            ) : status === "cancelled" ? (
              <span className="rounded-full bg-red-900/50 px-3 py-1 text-xs font-medium text-red-400 border border-red-800">
                Cancelled
              </span>
            ) : (
              <span className="rounded-full bg-neutral-800 px-3 py-1 text-xs font-medium text-neutral-400">
                No subscription
              </span>
            )}
          </div>

          {error && <p role="alert" className="text-sm text-red-400">{error}</p>}

          {status === "active" ? (
            <a
              href="https://billing.stripe.com/p/login/test"
              target="_blank"
              rel="noopener noreferrer"
              className="block w-full rounded-lg border border-neutral-600 px-4 py-3 text-center text-sm font-medium text-neutral-200 hover:bg-neutral-800"
            >
              Manage subscription
            </a>
          ) : (
            <button
              onClick={handleSubscribe}
              disabled={checkoutLoading}
              className="w-full rounded-lg bg-white px-4 py-3 text-sm font-medium text-black hover:bg-neutral-200 disabled:opacity-50"
            >
              {checkoutLoading ? "Redirecting..." : "Subscribe"}
            </button>
          )}
        </div>

        <a
          href="/dashboard"
          className="block text-center text-sm text-neutral-500 hover:text-neutral-300"
        >
          Back to dashboard
        </a>
      </div>
    </main>
  );
}
