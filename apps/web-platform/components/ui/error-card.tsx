"use client";

interface ErrorCardAction {
  label: string;
  href?: string;
  onClick?: () => void;
}

interface ErrorCardProps {
  title: string;
  message: string;
  onRetry?: () => void;
  retryLabel?: string;
  action?: ErrorCardAction;
}

export function ErrorCard({ title, message, onRetry, retryLabel = "Try again", action }: ErrorCardProps) {
  return (
    <div className="rounded-xl border border-red-900/50 bg-red-950/20 p-5">
      <h3 className="mb-1 text-sm font-semibold text-red-300">{title}</h3>
      <p className="text-sm text-neutral-400">{message}</p>
      <div className="mt-3 flex gap-2">
        {onRetry && (
          <button
            onClick={onRetry}
            className="rounded-lg border border-neutral-700 px-3 py-1.5 text-sm text-neutral-300 transition-colors hover:border-neutral-500 hover:text-white"
          >
            {retryLabel}
          </button>
        )}
        {action?.href && (
          <a
            href={action.href}
            className="rounded-lg border border-neutral-700 px-3 py-1.5 text-sm text-neutral-300 transition-colors hover:border-neutral-500 hover:text-white"
          >
            {action.label}
          </a>
        )}
        {action?.onClick && !action.href && (
          <button
            onClick={action.onClick}
            className="rounded-lg border border-neutral-700 px-3 py-1.5 text-sm text-neutral-300 transition-colors hover:border-neutral-500 hover:text-white"
          >
            {action.label}
          </button>
        )}
      </div>
    </div>
  );
}
