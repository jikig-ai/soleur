"use client";

import { useEffect, useState } from "react";
import { OPEN_MEMBERSHIP_REVOKED_TERMINAL_EVENT } from "@/lib/ws-client";
import type { MembershipRevokedPreamble } from "@/lib/types";

// AC-FLOW2: terminal full-screen overlay rendered when the WS closes with
// MEMBERSHIP_REVOKED (4012). The user must sign out or close the tab — there
// is no in-app recovery (the JWT claim still encodes the now-removed
// workspace until the access token refreshes, and the revoked workspace can't
// even be re-listed in the org switcher).

export function MembershipRevokedScreen() {
  const [preamble, setPreamble] = useState<MembershipRevokedPreamble | null>(null);

  useEffect(() => {
    function handle(e: Event) {
      const detail = (e as CustomEvent<MembershipRevokedPreamble | null>).detail;
      setPreamble(detail ?? { type: "membership_revoked", organizationName: null });
    }
    window.addEventListener(OPEN_MEMBERSHIP_REVOKED_TERMINAL_EVENT, handle);
    return () =>
      window.removeEventListener(OPEN_MEMBERSHIP_REVOKED_TERMINAL_EVENT, handle);
  }, []);

  if (!preamble) return null;

  const orgLabel = preamble.organizationName ?? "this workspace";

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="membership-revoked-title"
      className="fixed inset-0 z-[9999] flex items-center justify-center bg-soleur-bg-base/95 px-4"
    >
      <div className="w-full max-w-md rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 p-8 text-center">
        <h1
          id="membership-revoked-title"
          className="mb-3 text-xl font-semibold text-soleur-text-primary"
        >
          You were removed from {orgLabel}
        </h1>
        <p className="mb-6 text-sm text-soleur-text-secondary">
          A workspace owner revoked your membership. Any in-flight agent runs
          have been aborted and your access to this workspace is closed.
        </p>
        <p className="mb-6 text-xs text-soleur-text-muted">
          Sign out and back in to access your other workspaces, or close this
          tab.
        </p>
        <a
          href="/login?signout=1"
          className="inline-block rounded-md bg-soleur-accent-gold-fg px-4 py-2 text-sm font-medium text-soleur-bg-surface-1 hover:opacity-90"
        >
          Sign out
        </a>
      </div>
    </div>
  );
}
