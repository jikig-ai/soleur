"use client";

import { useState, useEffect } from "react";
import { CancelRetentionModal } from "./cancel-retention-modal";

interface Invoice {
  id: string;
  date: number;
  amount: number;
  currency: string;
  status: string;
  hostedUrl: string | null;
  pdfUrl: string | null;
}

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
  const [invoices, setInvoices] = useState<Invoice[]>([]);
  const [invoicesLoading, setInvoicesLoading] = useState(false);

  const isActive = subscriptionStatus === "active";
  const isCancelling = isActive && cancelAtPeriodEnd;
  const isCancelled = subscriptionStatus === "cancelled";
  const isPastDue = subscriptionStatus === "past_due";
  const isUnpaid = subscriptionStatus === "unpaid";

  const formattedPeriodEnd = currentPeriodEnd
    ? new Date(currentPeriodEnd).toLocaleDateString("en-US", {
        month: "long",
        day: "numeric",
        year: "numeric",
      })
    : null;

  useEffect(() => {
    if (isActive || isPastDue || isUnpaid) {
      setInvoicesLoading(true);
      fetch("/api/billing/invoices")
        .then((res) => res.json())
        .then((data) => setInvoices(data.invoices ?? []))
        .catch(() => setInvoices([]))
        .finally(() => setInvoicesLoading(false));
    }
  }, [isActive, isPastDue, isUnpaid]);

  async function redirectTo(endpoint: string, fallbackError: string) {
    setLoading(true);
    setError("");
    try {
      const res = await fetch(endpoint, { method: "POST" });
      const data = await res.json();
      if (!res.ok) {
        setError(data.error || fallbackError);
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

  const handlePortalRedirect = () =>
    redirectTo("/api/billing/portal", "Failed to open billing portal");
  const handleSubscribe = () =>
    redirectTo("/api/checkout", "Failed to create checkout session");

  function statusBadge() {
    if (isUnpaid) {
      return (
        <span className="rounded-full bg-red-900/50 px-3 py-1 text-xs font-medium text-red-400 border border-red-800">
          Suspended
        </span>
      );
    }
    if (isPastDue) {
      return (
        <span className="rounded-full bg-orange-900/50 px-3 py-1 text-xs font-medium text-orange-400 border border-orange-800">
          Past Due
        </span>
      );
    }
    if (isCancelling) {
      return (
        <span className="rounded-full bg-amber-900/50 px-3 py-1 text-xs font-medium text-amber-400 border border-amber-800">
          Cancelling
        </span>
      );
    }
    return (
      <span className="rounded-full bg-green-900/50 px-3 py-1 text-xs font-medium text-green-400 border border-green-800">
        Active
      </span>
    );
  }

  function formatCurrency(amount: number, currency: string) {
    return new Intl.NumberFormat("en-US", {
      style: "currency",
      currency: currency.toUpperCase(),
    }).format(amount / 100);
  }

  function formatDate(timestamp: number) {
    return new Date(timestamp * 1_000).toLocaleDateString("en-US", {
      month: "short",
      day: "numeric",
      year: "numeric",
    });
  }

  return (
    <section>
      <h2 className="mb-4 text-lg font-semibold text-white">Billing</h2>
      <div className="rounded-xl border border-neutral-800 bg-neutral-900/50 p-6">
        {/* Suspended recovery prompt */}
        {isUnpaid && (
          <div className="mb-4 rounded-lg border border-red-800/50 bg-red-950/30 p-4">
            <p className="text-sm font-medium text-red-400">
              Your subscription is unpaid
            </p>
            <p className="mt-1 text-sm text-neutral-300">
              Your account is in read-only mode. Update your payment method to
              restore full access.
            </p>
            <button
              onClick={handlePortalRedirect}
              disabled={loading}
              className="mt-3 rounded-lg bg-red-600 px-4 py-2 text-sm font-medium text-white transition-colors hover:bg-red-500 disabled:opacity-50"
            >
              {loading ? "Redirecting..." : "Resolve Payment"}
            </button>
          </div>
        )}

        {/* Past due warning */}
        {isPastDue && (
          <div className="mb-4 rounded-lg border border-orange-800/50 bg-orange-950/30 p-4">
            <p className="text-sm text-neutral-300">
              Your last payment failed. Update your payment method to avoid
              service interruption.
            </p>
            <button
              onClick={handlePortalRedirect}
              disabled={loading}
              className="mt-2 text-sm font-medium text-orange-400 hover:text-orange-300"
            >
              Update Payment Method
            </button>
          </div>
        )}

        {/* No subscription */}
        {!isActive && !isCancelled && !isPastDue && !isUnpaid && (
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

        {/* Active / past_due / unpaid subscription info */}
        {(isActive || isPastDue || isUnpaid) && (
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
              {statusBadge()}
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
              {!isCancelling && !isUnpaid && (
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

      {/* Invoice list */}
      {(isActive || isPastDue || isUnpaid) && (
        <div className="mt-6 rounded-xl border border-neutral-800 bg-neutral-900/50 p-6">
          <h3 className="mb-4 text-sm font-semibold text-white">Invoices</h3>
          {invoicesLoading ? (
            <p className="text-sm text-neutral-500">Loading invoices...</p>
          ) : invoices.length === 0 ? (
            <p className="text-sm text-neutral-500">No invoices yet.</p>
          ) : (
            <div className="space-y-3">
              {invoices.map((inv) => (
                <div
                  key={inv.id}
                  className="flex items-center justify-between border-b border-neutral-800 pb-3 last:border-0 last:pb-0"
                >
                  <div className="flex items-center gap-4">
                    <span className="text-sm text-neutral-300">
                      {formatDate(inv.date)}
                    </span>
                    <span className="text-sm font-medium text-white">
                      {formatCurrency(inv.amount, inv.currency)}
                    </span>
                    <span className="rounded-full bg-green-900/50 px-2 py-0.5 text-xs text-green-400 border border-green-800">
                      Paid
                    </span>
                  </div>
                  <div className="flex gap-3">
                    {inv.hostedUrl && (
                      <a
                        href={inv.hostedUrl}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="text-sm text-amber-400 hover:text-amber-300"
                      >
                        View
                      </a>
                    )}
                    {inv.pdfUrl && (
                      <a
                        href={inv.pdfUrl}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="text-sm text-amber-400 hover:text-amber-300"
                      >
                        PDF
                      </a>
                    )}
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      )}

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
