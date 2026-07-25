"use client";

// feat-support-interface — flag-gated entry point. Renders nothing when the
// `support` flag is OFF (fail-closed). Owns the open state and the conversation
// (so the thread is retained across close/reopen). The floating bubble hides
// while the panel is open; the panel's X / Escape / backdrop close it.

import { useEffect, useRef, useState } from "react";
import { useOptionalFeatureFlag } from "@/components/feature-flags/provider";
import { useTour } from "@/components/tour/tour-provider";
import { SupportPanel } from "./support-panel";
import { useSupportChat } from "./use-support-chat";

export function SupportLauncher() {
  const enabled = useOptionalFeatureFlag("support");
  // `support-live` gates the REAL Concierge backend (SSE). Default OFF → the
  // bubble shows the canned interface-preview reply (no network). Flipped ON only
  // after the Phase-4 product-help corpus + search-root restriction are validated
  // live (else the support agent could read the internal knowledge base).
  const live = useOptionalFeatureFlag("support-live");
  const [open, setOpen] = useState(false);
  const { messages, send, abort, reset } = useSupportChat(live);
  const tour = useTour();
  const bubbleRef = useRef<HTMLButtonElement>(null);
  const wasOpenRef = useRef(false);

  // The bubble unmounts while the panel is open, so the panel's own
  // focus-return lands on <body>. When the panel closes, return focus to the
  // re-mounted bubble (runs after the panel's cleanup, so it wins). Also abort
  // any in-flight support turn on close (S1) so no Concierge turn streams to
  // nowhere and burns Anthropic cost after the user dismissed the panel.
  useEffect(() => {
    if (wasOpenRef.current && !open) {
      abort();
      bubbleRef.current?.focus();
    }
    wasOpenRef.current = open;
  }, [open, abort]);

  if (!enabled) return null;

  return (
    <>
      {!open && (
        <button
          ref={bubbleRef}
          type="button"
          onClick={() => setOpen(true)}
          aria-label="Open support"
          className="fixed bottom-[calc(1.25rem+env(safe-area-inset-bottom))] right-5 z-50 flex h-12 w-12 items-center justify-center rounded-full bg-soleur-accent-gold-fill text-soleur-text-on-accent shadow-lg transition-opacity hover:opacity-90"
        >
          <svg
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="2"
            strokeLinecap="round"
            strokeLinejoin="round"
            className="h-5 w-5"
            aria-hidden="true"
          >
            <path d="M21 11.5a8.38 8.38 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.38 8.38 0 0 1-3.8-.9L3 21l1.9-5.7a8.38 8.38 0 0 1-.9-3.8 8.5 8.5 0 0 1 4.7-7.6 8.38 8.38 0 0 1 3.8-.9h.5a8.48 8.48 0 0 1 8 8v.5z" />
          </svg>
        </button>
      )}
      <SupportPanel
        open={open}
        onClose={() => setOpen(false)}
        messages={messages}
        onSend={send}
        onReset={reset}
        live={Boolean(live)}
        onStartTour={
          tour.available
            ? () => {
                // Close the panel (tears down its focus-trap) BEFORE starting the
                // tour so the two overlays never fight over focus.
                setOpen(false);
                tour.startTour("support-panel");
              }
            : undefined
        }
      />
    </>
  );
}
