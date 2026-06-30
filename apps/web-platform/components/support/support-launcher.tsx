"use client";

// feat-support-interface — flag-gated entry point. Renders nothing when the
// `support` flag is OFF (fail-closed). Owns the open state and the conversation
// (so the thread is retained across close/reopen). The floating bubble hides
// while the panel is open; the panel's X / Escape / backdrop close it.

import { useState } from "react";
import { useOptionalFeatureFlag } from "@/components/feature-flags/provider";
import { SupportPanel } from "./support-panel";
import { useSupportChat } from "./use-support-chat";

export function SupportLauncher() {
  const enabled = useOptionalFeatureFlag("support");
  const [open, setOpen] = useState(false);
  const { messages, send } = useSupportChat();

  if (!enabled) return null;

  return (
    <>
      {!open && (
        <button
          type="button"
          onClick={() => setOpen(true)}
          aria-label="Open support"
          className="fixed bottom-5 right-5 z-50 flex h-12 w-12 items-center justify-center rounded-full bg-soleur-accent-gold-fill text-soleur-text-on-accent shadow-lg transition-opacity hover:opacity-90"
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
      />
    </>
  );
}
