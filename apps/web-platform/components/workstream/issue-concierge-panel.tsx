"use client";

// The "Decision Making" Concierge panel inside the issue detail Sheet. Built
// WIRED and ready, but shown in a visibly OFFLINE/preview state in v1: the
// composer is present + disabled behind a single CONCIERGE_ONLINE flag, with an
// explicit "Concierge is offline — opening soon" notice (no enabled composer
// that silently drops messages — CPO P0). A working "Discuss in Chat" deep-link
// to the existing LIVE chat surface keeps the human-in-the-loop path real.
//
// Going live later is a one-flag-flip (CONCIERGE_ONLINE = true) + wiring the
// composer onSubmit to the conversation backend (tracked follow-up).

import Link from "next/link";
import { CONCIERGE_ONLINE } from "./concierge-flag";

const INTRO_MESSAGE =
  "I'm the Concierge. This is where we'll talk through decisions on this issue — " +
  "scope, trade-offs, and sign-off. This thread is a preview in v1; for a live " +
  "conversation, open it in Chat.";

export function IssueConciergePanel() {
  return (
    <section className="mt-6 border-t border-soleur-border-default pt-4">
      <h3 className="mb-3 text-xs font-semibold uppercase tracking-wider text-soleur-text-tertiary">
        Decision Making
      </h3>

      {/* Message area — one seeded Concierge intro message. */}
      <div className="space-y-3">
        <div className="flex items-start gap-2">
          <span
            aria-hidden="true"
            className="flex h-6 w-6 shrink-0 items-center justify-center rounded-full bg-soleur-bg-surface-2 text-[10px] font-semibold text-soleur-text-secondary"
          >
            C
          </span>
          <div className="min-w-0">
            <p className="text-xs font-medium text-soleur-text-secondary">
              Concierge
            </p>
            <p className="mt-0.5 text-sm text-soleur-text-secondary">
              {INTRO_MESSAGE}
            </p>
          </div>
        </div>
      </div>

      {/* Offline notice — honest, unambiguous. */}
      <p className="mt-4 flex items-center gap-1.5 text-xs text-soleur-text-tertiary">
        <span
          aria-hidden="true"
          className="h-1.5 w-1.5 rounded-full bg-soleur-text-muted"
        />
        Concierge is offline — opening soon
      </p>

      {/* Composer — present + WIRED but disabled in v1. */}
      <div className="mt-2 flex items-center gap-2">
        <input
          type="text"
          disabled={!CONCIERGE_ONLINE}
          placeholder="Message Concierge…"
          aria-label="Message Concierge"
          className="flex-1 rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 px-3 py-2 text-sm text-soleur-text-primary placeholder:text-soleur-text-tertiary disabled:cursor-not-allowed disabled:opacity-60 focus:outline-none"
        />
        <button
          type="button"
          disabled={!CONCIERGE_ONLINE}
          aria-label="Send"
          className="rounded-lg border border-soleur-border-default px-3 py-2 text-sm text-soleur-text-secondary disabled:cursor-not-allowed disabled:opacity-60"
        >
          Send
        </button>
      </div>

      {/* Real, working escape hatch to the live chat surface. */}
      <Link
        href="/dashboard/chat"
        className="mt-3 inline-flex items-center gap-1 text-sm text-soleur-accent-gold-text transition-opacity hover:opacity-80"
      >
        Discuss in Chat
        <span aria-hidden="true">→</span>
      </Link>
    </section>
  );
}
