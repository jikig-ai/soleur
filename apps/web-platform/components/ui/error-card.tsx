"use client";

import { Button } from "@/components/ui/button";
import { NavLink } from "@/components/ui/nav-link";

const ACTION_CLASS =
  "rounded-lg border border-soleur-border-default px-3 py-1.5 text-sm text-soleur-text-secondary transition-colors hover:border-soleur-border-default hover:text-soleur-text-primary";

interface ErrorCardProps {
  title: string;
  message: string;
  onRetry?: () => void;
  retryLabel?: string;
  action?: { label: string; href: string };
  /** Open the action in a new tab (plain external anchor) so the page that
   *  rendered the card, its draft and its state survive the trip. */
  newTab?: boolean;
  onDismiss?: () => void;
}

export function ErrorCard({
  title,
  message,
  onRetry,
  retryLabel = "Try again",
  action,
  newTab = false,
  onDismiss,
}: ErrorCardProps) {
  return (
    <div role="alert" className="relative rounded-xl border border-red-900/50 bg-red-950/20 p-5">
      {onDismiss && (
        <Button
          variant="ghost"
          type="button"
          onClick={onDismiss}
          aria-label="Dismiss"
          className="absolute right-3 top-3 p-1.5 hover:text-soleur-text-secondary"
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
        </Button>
      )}
      <h3 className="mb-1 pr-8 text-sm font-semibold text-red-300">{title}</h3>
      <p className="pr-8 text-sm text-soleur-text-secondary">{message}</p>
      <div className="mt-3 flex gap-2">
        {onRetry && (
          <Button
            variant="outlined"
            type="button"
            onClick={onRetry}
            className="px-3 py-1.5 text-soleur-text-secondary hover:text-soleur-text-primary"
          >
            {retryLabel}
          </Button>
        )}
        {action && newTab && (
          <a
            href={action.href}
            target="_blank"
            rel="noopener noreferrer"
            className={ACTION_CLASS}
          >
            {action.label}
          </a>
        )}
        {action && !newTab && (
          <NavLink
            href={action.href}
            className={ACTION_CLASS}
          >
            {action.label}
          </NavLink>
        )}
      </div>
    </div>
  );
}
