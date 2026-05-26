"use client";

interface ErrorCardProps {
  title: string;
  message: string;
  onRetry?: () => void;
  retryLabel?: string;
  action?: { label: string; href: string };
  onDismiss?: () => void;
}

export function ErrorCard({
  title,
  message,
  onRetry,
  retryLabel = "Try again",
  action,
  onDismiss,
}: ErrorCardProps) {
  return (
    <div role="alert" className="relative rounded-xl border border-red-900/50 bg-red-950/20 p-5">
      {onDismiss && (
        <button
          type="button"
          onClick={onDismiss}
          aria-label="Dismiss"
          className="absolute right-3 top-3 rounded p-1 text-soleur-text-muted transition-colors hover:text-soleur-text-secondary"
        >
          <svg
            width="16"
            height="16"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
            strokeLinecap="round"
            strokeLinejoin="round"
            aria-hidden="true"
          >
            <line x1="18" y1="6" x2="6" y2="18" />
            <line x1="6" y1="6" x2="18" y2="18" />
          </svg>
        </button>
      )}
      <h3 className="mb-1 pr-8 text-sm font-semibold text-red-300">{title}</h3>
      <p className="pr-8 text-sm text-soleur-text-secondary">{message}</p>
      <div className="mt-3 flex gap-2">
        {onRetry && (
          <button
            onClick={onRetry}
            className="rounded-lg border border-soleur-border-default px-3 py-1.5 text-sm text-soleur-text-secondary transition-colors hover:border-soleur-border-default hover:text-soleur-text-primary"
          >
            {retryLabel}
          </button>
        )}
        {action && (
          <a
            href={action.href}
            className="rounded-lg border border-soleur-border-default px-3 py-1.5 text-sm text-soleur-text-secondary transition-colors hover:border-soleur-border-default hover:text-soleur-text-primary"
          >
            {action.label}
          </a>
        )}
      </div>
    </div>
  );
}
