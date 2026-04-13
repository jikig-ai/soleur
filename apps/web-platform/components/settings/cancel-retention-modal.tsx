"use client";

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
  if (!open) return null;

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
    <div className="fixed inset-0 z-50 flex items-center justify-center">
      <div
        className="absolute inset-0 bg-black/60"
        onClick={onClose}
        role="presentation"
      />
      <div className="relative w-full max-w-md rounded-xl border border-neutral-800 bg-neutral-900 p-8">
        <h3 className="mb-2 text-xl font-semibold text-white">
          Before you go...
        </h3>
        <p className="mb-6 text-sm text-neutral-400">
          Here&apos;s what you&apos;ve built with Soleur so far:
        </p>

        {/* Stats grid */}
        {hasStats && (
          <div className="mb-6 grid grid-cols-2 gap-3">
            {stats.map((stat) => (
              <div
                key={stat.label}
                className="rounded-lg border border-neutral-800 bg-neutral-800/50 p-4 text-center"
              >
                <p className="text-2xl font-semibold text-amber-400">
                  {stat.value}
                </p>
                <p className="text-xs text-neutral-400">{stat.label}</p>
              </div>
            ))}
          </div>
        )}

        {/* CTAs */}
        <div className="flex gap-3">
          <button
            onClick={onConfirmCancel}
            className="flex-1 rounded-lg border border-neutral-700 px-4 py-2.5 text-sm font-medium text-neutral-300 transition-colors hover:bg-neutral-800"
          >
            Continue to cancel
          </button>
          <button
            onClick={onClose}
            className="flex-1 rounded-lg bg-amber-600 px-4 py-2.5 text-sm font-medium text-white transition-colors hover:bg-amber-500"
          >
            Keep my account
          </button>
        </div>
      </div>
    </div>
  );
}
