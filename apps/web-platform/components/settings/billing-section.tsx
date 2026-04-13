"use client";

import { useState } from "react";
import { CancelRetentionModal } from "./cancel-retention-modal";

interface BillingSectionProps {
  subscriptionStatus: string | null;
  currentPeriodEnd: string | null;
  cancelAtPeriodEnd: boolean;
  conversationCount: number;
  serviceTokenCount: number;
  createdAt: string;
}

export function BillingSection({
  subscriptionStatus,
  currentPeriodEnd,
  cancelAtPeriodEnd,
  conversationCount,
  serviceTokenCount,
  createdAt,
}: BillingSectionProps) {
  const [loading, setLoading] = useState(false);
  const [showRetentionModal, setShowRetentionModal] = useState(false);
  const [error, setError] = useState("");

  const isActive = subscriptionStatus === "active";
  const isCancelling = isActive && cancelAtPeriodEnd;
  const isCancelled = subscriptionStatus === "cancelled";

  const formattedPeriodEnd = currentPeriodEnd
    ? new Date(currentPeriodEnd).toLocaleDateString("en-US", {
        month: "long",
        day: "numeric",
        year: "numeric",
      })
    : null;

  async function handlePortalRedirect() {
    setLoading(true);
    setError("");
    try {
      const res = await fetch("/api/billing/portal", { method: "POST" });
      const data = await res.json();
      if (!res.ok) {
        setError(data.error || "Failed to open billing portal");
        return;
      }
      if (data.url) {
        window.location.href = data.url;
      }
    } catch {
      setError("Something went wrong. Please try again.");
    } finally {
      setLoading(false);
    }
  }

  async function handleSubscribe() {
    setLoading(true);
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
      setLoading(false);
    }
  }

  return (
    <section>
      <h2 className="mb-4 text-lg font-semibold text-white">Billing</h2>
      <div className="rounded-xl border border-neutral-800 bg-neutral-900/50 p-6">
        {/* No subscription */}
        {!isActive && !isCancelled && (
          <div className="flex flex-col items-center gap-4 py-4">
            <div className="h-12 w-12 rounded-full bg-neutral-800" />
            <p className="text-sm text-neutral-300">No active subscription</p>
            <p className="text-sm text-neutral-500">
              Subscribe to access the full Soleur platform.
            </p>
            <button
              onClick={handleSubscribe}
              disabled={loading}
              className="rounded-lg bg-amber-600 px-6 py-2 text-sm font-medium text-white transition-colors hover:bg-amber-500 disabled:opacity-50"
            >
              {loading ? "Redirecting..." : "Subscribe"}
            </button>
          </div>
        )}

        {/* Cancelled / expired */}
        {isCancelled && (
          <div className="flex flex-col items-center gap-4 py-4">
            <p className="text-sm text-neutral-300">
              Your subscription ended
              {formattedPeriodEnd ? ` on ${formattedPeriodEnd}` : ""}.
            </p>
            <button
              onClick={handleSubscribe}
              disabled={loading}
              className="rounded-lg bg-amber-600 px-6 py-2 text-sm font-medium text-white transition-colors hover:bg-amber-500 disabled:opacity-50"
            >
              {loading ? "Redirecting..." : "Resubscribe"}
            </button>
          </div>
        )}

        {/* Active subscription (includes cancelling state) */}
        {isActive && (
          <div className="space-y-4">
            {/* Cancelling banner */}
            {isCancelling && (
              <div className="rounded-lg border border-amber-800/50 bg-amber-950/30 p-4">
                <p className="text-sm text-neutral-300">
                  Your subscription will end on {formattedPeriodEnd}.
                  You&apos;ll retain full access until then.
                </p>
                <button
                  onClick={handlePortalRedirect}
                  className="mt-1 text-sm font-medium text-amber-400 hover:text-amber-300"
                >
                  Reactivate
                </button>
              </div>
            )}

            {/* Plan info */}
            <div className="flex items-center gap-3">
              <div>
                <p className="text-xs text-neutral-500">Plan</p>
                <p className="text-sm font-medium text-white">
                  Solo — $49/mo
                </p>
              </div>
              {isCancelling ? (
                <span className="rounded-full bg-amber-900/50 px-3 py-1 text-xs font-medium text-amber-400 border border-amber-800">
                  Cancelling
                </span>
              ) : (
                <span className="rounded-full bg-green-900/50 px-3 py-1 text-xs font-medium text-green-400 border border-green-800">
                  Active
                </span>
              )}
            </div>

            {/* Period end */}
            {formattedPeriodEnd && (
              <div className="border-t border-neutral-800 pt-4">
                <p className="text-xs text-neutral-500">
                  {isCancelling ? "Access ends" : "Billing period ends"}
                </p>
                <p className="text-sm text-white">{formattedPeriodEnd}</p>
              </div>
            )}

            {/* Action buttons */}
            <div className="flex gap-3 pt-2">
              <button
                onClick={handlePortalRedirect}
                disabled={loading}
                className="rounded-lg bg-amber-600 px-4 py-2 text-sm font-medium text-white transition-colors hover:bg-amber-500 disabled:opacity-50"
              >
                Manage Subscription
              </button>
              {!isCancelling && (
                <button
                  onClick={() => setShowRetentionModal(true)}
                  className="rounded-lg border border-neutral-700 px-4 py-2 text-sm font-medium text-neutral-300 transition-colors hover:bg-neutral-800"
                >
                  Cancel Subscription
                </button>
              )}
            </div>
          </div>
        )}

        {error && (
          <p className="mt-4 text-sm text-red-400" role="alert">
            {error}
          </p>
        )}
      </div>

      <CancelRetentionModal
        open={showRetentionModal}
        onClose={() => setShowRetentionModal(false)}
        onConfirmCancel={() => {
          setShowRetentionModal(false);
          handlePortalRedirect();
        }}
        conversationCount={conversationCount}
        serviceTokenCount={serviceTokenCount}
        createdAt={createdAt}
      />
    </section>
  );
}
