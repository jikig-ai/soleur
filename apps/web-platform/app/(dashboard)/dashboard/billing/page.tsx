"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { DOMAIN_LEADERS } from "@/server/domain-leaders";

type SubscriptionStatus = "active" | "cancelled" | null;

interface ConversationCost {
  id: string;
  domain_leader: string;
  total_cost_usd: number;
  created_at: string;
}

export default function BillingPage() {
  const [status, setStatus] = useState<SubscriptionStatus>(null);
  const [loading, setLoading] = useState(true);
  const [checkoutLoading, setCheckoutLoading] = useState(false);
  const [error, setError] = useState("");
  const [conversations, setConversations] = useState<ConversationCost[]>([]);

  useEffect(() => {
    async function fetchData() {
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

        const { data: costData, error: costError } = await supabase
          .from("conversations")
          .select("id, domain_leader, total_cost_usd, created_at")
          .eq("user_id", user.id)
          .gt("total_cost_usd", 0)
          .order("created_at", { ascending: false })
          .limit(50);

        if (!costError && costData) {
          setConversations(costData);
        }
      }
      setLoading(false);
    }

    fetchData();
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

        {/* API Usage section */}
        <div className="rounded-lg border border-neutral-700 bg-neutral-900 p-6 space-y-4">
          <h2 className="text-sm font-medium text-neutral-200">API Usage</h2>

          {conversations.length > 0 ? (
            <div className="space-y-2">
              {conversations.map((conv) => {
                const leader = DOMAIN_LEADERS.find((l) => l.id === conv.domain_leader);
                return (
                  <div
                    key={conv.id}
                    className="flex items-center justify-between rounded-md border border-neutral-800 px-3 py-2"
                  >
                    <div className="flex items-center gap-2">
                      <span className="text-sm text-neutral-300">
                        {leader?.name ?? conv.domain_leader.toUpperCase()}
                      </span>
                      <span className="text-xs text-neutral-500">
                        {formatRelativeTime(conv.created_at)}
                      </span>
                    </div>
                    <span className="text-sm text-neutral-400">
                      ~${conv.total_cost_usd.toFixed(4)}
                      <span className="ml-1 text-neutral-500">estimated</span>
                    </span>
                  </div>
                );
              })}
            </div>
          ) : (
            <p className="text-sm text-neutral-500">
              No API usage yet. Conversations will appear here with their costs.
            </p>
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

function formatRelativeTime(isoDate: string): string {
  const diff = Date.now() - new Date(isoDate).getTime();
  const minutes = Math.floor(diff / 60000);
  if (minutes < 1) return "just now";
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  return `${days}d ago`;
}
