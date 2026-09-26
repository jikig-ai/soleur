"use client";

import { useState, useEffect } from "react";
import { Button } from "@/components/ui/button";
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

// ~8s escalation delay (feat-ui-action-feedback brief §5/§7).
const ESCALATION_DELAY_MS = 8_000;

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
  const [stillWorking, setStillWorking] = useState(false);
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

  // ~8s escalation (feat-ui-action-feedback brief §5): a billing action
  // pending longer than ESCALATION_DELAY_MS appends "Still working…" to a
  // polite live region so a slow Stripe redirect never reads as hung.
  // The timer resets per pending episode — a fast retry gets a fresh clock.
  useEffect(() => {
    setStillWorking(false);
    if (!loading) return;
    const timer = setTimeout(() => setStillWorking(true), ESCALATION_DELAY_MS);
    return () => clearTimeout(timer);
  }, [loading]);

  async function redirectTo(endpoint: string, fallbackError: string) {
    setLoading(true);
    setError("");
    try {
      const res = await fetch(endpoint, { method: "POST" });
      const data = await res.json();
      if (!res.ok) {
        setError(data.error || fallbackError);
        setLoading(false);
        return;
      }
      if (data.url) {
        // Redirect latch (use-sign-out precedent): once the hard nav is
        // assigned, `loading` must NEVER reset — the document load tearing
        // the page down IS the reset. Re-enabling in the gap before the
        // Stripe redirect commits reopens a double-submit window.
        window.location.href = data.url;
        return;
      }
      setLoading(false);
    } catch {
      setError("Something went wrong. Please try again.");
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
      <h2 className="mb-4 text-lg font-semibold text-soleur-text-primary">Billing</h2>
      <div className="rounded-xl border border-soleur-border-default bg-soleur-bg-surface-1 p-6">
        {/* Suspended recovery prompt */}
        {isUnpaid && (
          <div className="mb-4 rounded-lg border border-red-800/50 bg-red-950/30 p-4">
            <p className="text-sm font-medium text-red-400">
              Your subscription is unpaid
            </p>
            <p className="mt-1 text-sm text-soleur-text-secondary">
              Your account is in read-only mode. Update your payment method to
              restore full access.
            </p>
            <Button
              variant="danger"
              type="button"
              onClick={handlePortalRedirect}
              loading={loading}
              className="mt-3"
            >
              {loading ? "Redirecting..." : "Resolve Payment"}
            </Button>
          </div>
        )}

        {/* Past due warning */}
        {isPastDue && (
          <div className="mb-4 rounded-lg border border-orange-800/50 bg-orange-950/30 p-4">
            <p className="text-sm text-soleur-text-secondary">
              Your last payment failed. Update your payment method to avoid
              service interruption.
            </p>
            <Button
              variant="ghost"
              type="button"
              onClick={handlePortalRedirect}
              loading={loading}
              className="mt-2"
              style={{ color: "var(--color-orange-400)" }}
            >
              Update Payment Method
            </Button>
          </div>
        )}

        {/* No subscription */}
        {!isActive && !isCancelled && !isPastDue && !isUnpaid && (
          <div className="flex flex-col items-center gap-4 py-4">
            <div className="h-12 w-12 rounded-full bg-soleur-bg-surface-2" />
            <p className="text-sm text-soleur-text-secondary">No active subscription</p>
            <p className="text-sm text-soleur-text-muted">
              Subscribe to access the full Soleur platform.
            </p>
            <Button
              variant="gold"
              type="button"
              onClick={handleSubscribe}
              loading={loading}
            >
              {loading ? "Redirecting..." : "Subscribe"}
            </Button>
          </div>
        )}

        {/* Cancelled / expired */}
        {isCancelled && (
          <div className="flex flex-col items-center gap-4 py-4">
            <p className="text-sm text-soleur-text-secondary">
              Your subscription ended
              {formattedPeriodEnd ? ` on ${formattedPeriodEnd}` : ""}.
            </p>
            <Button
              variant="gold"
              type="button"
              onClick={handleSubscribe}
              loading={loading}
            >
              {loading ? "Redirecting..." : "Resubscribe"}
            </Button>
          </div>
        )}

        {/* Active / past_due / unpaid subscription info */}
        {(isActive || isPastDue || isUnpaid) && (
          <div className="space-y-4">
            {/* Cancelling banner */}
            {isCancelling && (
              <div className="rounded-lg border border-amber-800/50 bg-amber-950/30 p-4">
                <p className="text-sm text-soleur-text-secondary">
                  Your subscription will end on {formattedPeriodEnd}.
                  You&apos;ll retain full access until then.
                </p>
                <Button
                  variant="ghost"
                  type="button"
                  onClick={handlePortalRedirect}
                  loading={loading}
                  className="mt-1"
                  style={{ color: "var(--color-soleur-accent-gold-fg)" }}
                >
                  Reactivate
                </Button>
              </div>
            )}

            {/* Plan info */}
            <div className="flex items-center gap-3">
              <div>
                <p className="text-xs text-soleur-text-muted">Plan</p>
                <p className="text-sm font-medium text-soleur-text-primary">
                  Solo — $49/mo
                </p>
              </div>
              {statusBadge()}
            </div>

            {/* Period end */}
            {formattedPeriodEnd && (
              <div className="border-t border-soleur-border-default pt-4">
                <p className="text-xs text-soleur-text-muted">
                  {isCancelling ? "Access ends" : "Billing period ends"}
                </p>
                <p className="text-sm text-soleur-text-primary">{formattedPeriodEnd}</p>
              </div>
            )}

            {/* Action buttons */}
            <div className="flex gap-3 pt-2">
              <Button
                variant="gold"
                type="button"
                onClick={handlePortalRedirect}
                loading={loading}
              >
                Manage Subscription
              </Button>
              {!isCancelling && !isUnpaid && (
                <Button
                  variant="outlined"
                  type="button"
                  onClick={() => setShowRetentionModal(true)}
                >
                  Cancel Subscription
                </Button>
              )}
            </div>
          </div>
        )}

        {/* Reserved-space escalation sublabel (brief §5): always mounted
            so "Still working…" populating causes zero layout shift. */}
        <p
          role="status"
          aria-live="polite"
          className="mt-4 min-h-5 text-xs text-soleur-text-muted"
          data-testid="billing-escalation"
        >
          {stillWorking ? "Still working…" : ""}
        </p>
        {error && (
          <p className="mt-4 text-sm text-red-400" role="alert">
            {error}
          </p>
        )}
      </div>

      {/* Invoice list */}
      {(isActive || isPastDue || isUnpaid) && (
        <div className="mt-6 rounded-xl border border-soleur-border-default bg-soleur-bg-surface-1 p-6">
          <h3 className="mb-4 text-sm font-semibold text-soleur-text-primary">Invoices</h3>
          {invoicesLoading ? (
            <p className="text-sm text-soleur-text-muted">Loading invoices...</p>
          ) : invoices.length === 0 ? (
            <p className="text-sm text-soleur-text-muted">No invoices yet.</p>
          ) : (
            <div className="space-y-3">
              {invoices.map((inv) => (
                <div
                  key={inv.id}
                  className="flex items-center justify-between border-b border-soleur-border-default pb-3 last:border-0 last:pb-0"
                >
                  <div className="flex items-center gap-4">
                    <span className="text-sm text-soleur-text-secondary">
                      {formatDate(inv.date)}
                    </span>
                    <span className="text-sm font-medium text-soleur-text-primary">
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
                        className="text-sm text-soleur-accent-gold-fg hover:text-soleur-accent-gold-text"
                      >
                        View
                      </a>
                    )}
                    {inv.pdfUrl && (
                      <a
                        href={inv.pdfUrl}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="text-sm text-soleur-accent-gold-fg hover:text-soleur-accent-gold-text"
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
