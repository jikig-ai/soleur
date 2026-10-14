"use client";

import { Button } from "@/components/ui/button";
import { ResponsiveModal } from "@/components/ui/responsive-modal";

interface CancelRetentionModalProps {
  open: boolean;
  onClose: () => void;
  onConfirmCancel: () => void;
  conversationCount: number;
  serviceTokenCount: number;
  createdAt: string;
}

export function CancelRetentionModal({
  open,
  onClose,
  onConfirmCancel,
  conversationCount,
  serviceTokenCount,
  createdAt,
}: CancelRetentionModalProps) {
  const daysSinceSignup = Math.floor(
    (Date.now() - new Date(createdAt).getTime()) / (1_000 * 60 * 60 * 24),
  );

  const stats = [
    { value: conversationCount, label: "Conversations" },
    { value: serviceTokenCount, label: "Connected Services" },
    { value: daysSinceSignup, label: "Days Building" },
  ];

  const hasStats = conversationCount > 0 || serviceTokenCount > 0;

  return (
    <ResponsiveModal
      open={open}
      onClose={onClose}
      desktopMaxWidth="max-w-md"
      aria-labelledby="retention-heading"
    >
      <h3
        id="retention-heading"
        className="mb-2 text-xl font-semibold text-soleur-text-primary"
      >
        Before you go...
      </h3>
      <p className="mb-6 text-sm text-soleur-text-secondary">
        Here&apos;s what you&apos;ve built with Soleur so far:
      </p>

      {/* Stats grid */}
      {hasStats && (
        <div className="mb-6 grid grid-cols-2 gap-3">
          {stats.map((stat) => (
            <div
              key={stat.label}
              className="rounded-lg border border-soleur-border-default bg-soleur-bg-surface-2 p-4 text-center"
            >
              <p className="text-2xl font-semibold text-soleur-accent-gold-fg">
                {stat.value}
              </p>
              <p className="text-xs text-soleur-text-secondary">{stat.label}</p>
            </div>
          ))}
        </div>
      )}

      {/* CTAs */}
      <div className="flex gap-3">
        <Button
          variant="outlined"
          onClick={onConfirmCancel}
          className="flex-1 text-soleur-text-secondary"
        >
          Continue to cancel
        </Button>
        <Button
          variant="gold"
          onClick={onClose}
          className="flex-1"
        >
          Keep my account
        </Button>
      </div>
    </ResponsiveModal>
  );
}
